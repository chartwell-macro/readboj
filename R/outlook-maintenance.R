.readboj_outlook_maintenance_schema <- "outlook-maintenance-v1"

outlook_maintenance_read <- function(root) {
  problems <- character()
  for (path in outlook_saved_markers(root)) {
    state <- tryCatch({
      if (file.info(path)$size > 4096) stop("Invalid maintenance commit size")
      marker <- readRDS(path)
      if (!is.character(marker$sha256) || length(marker$sha256) != 1L ||
          !grepl("^[a-f0-9]{64}$", marker$sha256) ||
          !identical(basename(path), sprintf("%012.0f-%s.rds", marker$generation, marker$sha256))) stop("Invalid maintenance commit")
      object <- file.path(root, "objects", paste0(marker$sha256, ".rds"))
      if (is.na(file.info(object)$size) || file.info(object)$size > 1024^2 ||
          !identical(sha256_file(object), marker$sha256)) stop("Invalid maintenance object")
      value <- readRDS(object)
      hash <- value$content_sha256
      value$content_sha256 <- NULL
      if (!identical(value$schema, .readboj_outlook_maintenance_schema) ||
          !identical(hash, digest::digest(value, algo = "sha256")) ||
          !inherits(value$next_due_at, "POSIXt") || length(value$next_due_at) != 1L ||
          is.na(value$next_due_at)) stop("Invalid maintenance schema/checksum")
      value$content_sha256 <- hash
      value
    }, error = function(e) {problems <<- c(problems, conditionMessage(e)); NULL})
    if (!is.null(state)) {
      attr(state, "maintenance_fallback_errors") <- problems
      return(state)
    }
  }
  if (length(problems)) warning("No valid maintenance state remains; rediscovering while retaining saved numeric data.", call. = FALSE)
  NULL
}

outlook_maintenance_write <- function(state, root, lock) {
  attr(state, "maintenance_fallback_errors") <- NULL
  state <- outlook_saved_seal(state)
  dir.create(file.path(root, "objects"), showWarnings = FALSE)
  dir.create(file.path(root, "commits"), showWarnings = FALSE)
  pending <- tempfile(".pending-", tmpdir = file.path(root, "objects"))
  on.exit(unlink(pending), add = TRUE)
  saveRDS(state, pending, version = 2)
  if (file.info(pending)$size > 1024^2) readboj_abort("Maintenance state exceeds 1 MiB.", "readboj_size_error")
  check <- readRDS(pending)
  expected <- check$content_sha256
  check$content_sha256 <- NULL
  if (!identical(expected, digest::digest(check, algo = "sha256"))) readboj_abort(
    "Maintenance checksum changed before publication.", "readboj_outlook_calendar_error")
  hash <- sha256_file(pending)
  object <- file.path(root, "objects", paste0(hash, ".rds"))
  outlook_assert_lock(lock)
  if (file.exists(object) && !identical(sha256_file(object), hash)) {
    # A corrupt object can have the intended name from an earlier generation.
    # Replace it only with the fully validated bytes for that exact hash.
    invalid <- tempfile(".invalid-", tmpdir = dirname(object))
    on.exit(unlink(invalid), add = TRUE)
    if (!file.rename(object, invalid)) readboj_abort("Could not quarantine corrupt maintenance state.", "readboj_outlook_calendar_error")
  }
  if (!file.exists(object) && !file.rename(pending, object)) readboj_abort(
    "Could not publish maintenance object.", "readboj_outlook_calendar_error")
  outlook_assert_lock(lock)
  markers <- outlook_saved_markers(root)
  generation <- if (length(markers)) max(as.numeric(substr(basename(markers), 1L, 12L))) + 1 else 1
  outlook_atomic_rds(list(generation = generation, sha256 = hash),
    file.path(root, "commits", sprintf("%012.0f-%s.rds", generation, hash)))
  outlook_cleanup_objects(root)
  invisible(state)
}

outlook_pending_calendar <- function(events, catalogue, holidays = NULL) {
  # An independently discovered latest Bank's View must remain full-text pending
  # even when a calendar outage leaves it absent from the last-good schedule.
  latest <- catalogue[1L, , drop = FALSE]
  if (is.na(latest$full_text_url) && !latest$publication_date %in% events$publication_date) {
    business <- outlook_next_business_day(latest$publication_date,
      holidays %||% list(dates = as.Date(character()), years = integer()))
    fallback <- data.frame(edition_hint = latest$release, meeting_start_date = latest$publication_date,
      publication_date = latest$publication_date, bank_view_poll_from_at = outlook_tokyo_time(latest$publication_date),
      bank_view_timing = "after_mpm_no_fixed_time", full_text_date = if (business$confirmed) business$date else as.Date(NA),
      full_text_poll_from_at = outlook_tokyo_time(business$date, "14:00:00"), business_day_confirmed = business$confirmed,
      timing_rule = "calendar_unavailable_archive_pending_bound", calendar_xpath = NA_character_, retained_pending = TRUE)
    events <- if (is.null(events)) fallback else rbind(events, fallback)
  }
  if (is.null(events) || !nrow(events)) return(NULL)
  index <- match(events$publication_date, catalogue$publication_date)
  events$edition <- events$edition_hint
  found <- !is.na(index)
  events$edition[found] <- catalogue$release[index[found]]
  events$view_available <- found
  events$full_text_available <- found & !is.na(catalogue$full_text_url[index])
  events
}

outlook_merge_calendar <- function(previous, current, catalogue) {
  if (is.null(previous)) return(current)
  old <- outlook_pending_calendar(previous$events, catalogue, previous$holidays)
  keep <- !old$full_text_available & !old$edition_hint %in% current$events$edition_hint
  if (any(keep)) {
    retained <- old[keep, names(current$events), drop = FALSE]
    retained$retained_pending <- TRUE
    current$events <- rbind(retained, current$events)
  }
  if (nrow(current$events) > 500L) readboj_abort("Pending calendar exceeds 500 reports.", "readboj_size_error")
  current$events <- current$events[order(current$events$publication_date), , drop = FALSE]
  rownames(current$events) <- NULL
  current
}

outlook_probe_archive <- function(timeout, retries, deadline, path = tempfile("readboj-outlook-index-")) {
  on.exit(unlink(path), add = TRUE)
  entry <- outlook_update_request(.readboj_outlook_index, NULL, path,
    timeout, retries, 0, 2 * 1024^2, deadline)
  list(catalogue = parse_outlook_releases(entry, 2 * 1024^2, 1000L, deadline),
    receipt = outlook_clean_receipt(entry))
}

outlook_catalogue_signature <- function(catalogue) {
  # R serialization can differ for identical frames (e.g. ALTREP strings).
  # Compare canonical field text so metadata probes never trigger false updates.
  columns <- lapply(catalogue[c("release", "publication_date", "banks_view_url",
    "source_format", "full_text_date", "full_text_url")], function(x) enc2utf8(as.character(x)))
  text <- jsonlite::toJSON(columns, auto_unbox = FALSE, na = "null", null = "null")
  digest::digest(charToRaw(enc2utf8(text)), algo = "sha256", serialize = FALSE)
}

outlook_probe_asset <- function(url, previous, timeout, retries, deadline) {
  validate_official_url(url)
  for (attempt in seq_len(retries + 1L)) {
    request <- httr2::req_method(httr2::request(url), "HEAD")
    headers <- list()
    if (!is.null(previous$etag) && !is.na(previous$etag)) headers[["If-None-Match"]] <- previous$etag
    if (!is.null(previous$last_modified) && !is.na(previous$last_modified)) headers[["If-Modified-Since"]] <- previous$last_modified
    request <- do.call(httr2::req_headers, c(list(request), headers))
    request <- httr2::req_timeout(request, min(timeout, deadline_remaining(deadline)))
    request <- httr2::req_options(request, maxredirs = 0L, protocols_str = "https")
    request <- httr2::req_error(request, is_error = function(response) FALSE)
    response <- tryCatch(httr2::req_perform(request), error = identity)
    if (inherits(response, "error")) {
      if (attempt <= retries && is_transient_transport_error(response)) {
        deadline_pause(min(8, 2^(attempt - 1L)), deadline)
        next
      }
      stop(response)
    }
    status <- httr2::resp_status(response)
    if (!identical(httr2::resp_url(response), url)) readboj_abort("Metadata probe redirected.", "readboj_identity_error")
    if (status %in% c(405L, 501L)) return(list(supported = FALSE, changed = FALSE))
    if (status == 304L) return(list(supported = TRUE, changed = FALSE))
    if (status %in% c(408L, 429L, 500L, 502L, 503L, 504L) && attempt <= retries) {
      deadline_pause(min(8, 2^(attempt - 1L)), deadline)
      next
    }
    if (status != 200L) readboj_abort("Asset metadata probe failed.", "readboj_transport_error", http_status = status)
    etag <- httr2::resp_header(response, "etag") %||% NA_character_
    modified <- httr2::resp_header(response, "last-modified") %||% NA_character_
    changed <- (!is.na(etag) && !is.null(previous$etag) && !is.na(previous$etag) && etag != previous$etag) ||
      (!is.na(modified) && !is.null(previous$last_modified) && !is.na(previous$last_modified) && modified != previous$last_modified)
    return(list(supported = !is.na(etag) || !is.na(modified), changed = changed,
      etag = etag, last_modified = modified))
  }
}

outlook_maintenance_plan <- function(state, catalogue, now, probe_interval) {
  pending <- outlook_pending_calendar(state$calendar$events, catalogue, state$calendar$holidays)
  stages <- list()
  if (!is.null(pending)) for (i in seq_len(nrow(pending))) {
    event <- pending[i, , drop = FALSE]
    if (!event$view_available) {
      stages[[length(stages) + 1L]] <- list(stage = "banks_view", date = event$publication_date,
        edition = event$edition, due = event$bank_view_poll_from_at, fixed_time = FALSE)
    } else if (!event$full_text_available) {
      stages[[length(stages) + 1L]] <- list(stage = "full_text", date = event$full_text_date,
        edition = event$edition, due = event$full_text_poll_from_at,
        fixed_time = event$business_day_confirmed)
    }
  }
  first <- if (length(stages)) stages[[which.min(vapply(stages, function(x) as.numeric(x$due), numeric(1L)))]] else NULL
  event_due <- if (is.null(first)) as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC") else first$due
  if (!is.na(event_due) && event_due <= now) {
    event_due <- max(now, state$next_probe_at %||% now)
  }
  choices <- c(state$next_calendar_at, state$next_revision_at, event_due)
  state$next_due_at <- min(choices[!is.na(choices)])
  state$next_release <- first
  state$full_text_pending <- !is.null(pending) && any(pending$view_available & !pending$full_text_available)
  state$pending_full_text <- if (is.null(pending)) list() else lapply(which(pending$view_available & !pending$full_text_available), function(i) {
    list(edition = pending$edition[[i]], date = as.character(pending$full_text_date[[i]]),
      due_at = outlook_utc(pending$full_text_poll_from_at[[i]]),
      business_day_confirmed = pending$business_day_confirmed[[i]])
  })
  state
}

outlook_maintenance_result <- function(state, now, status = state$status) {
  next_release <- state$next_release
  list(status = status, last_status = state$status,
    next_due_at = outlook_utc(state$next_due_at), due = state$next_due_at <= now,
    next_release_at = if (is.null(next_release)) NA_character_ else outlook_utc(next_release$due),
    next_release_date = if (is.null(next_release)) NA_character_ else as.character(next_release$date),
    edition = next_release$edition %||% NA_character_, release_stage = next_release$stage %||% NA_character_,
    release_time_is_fixed = next_release$fixed_time %||% FALSE,
    full_text_pending = state$full_text_pending %||% FALSE,
    pending_full_text = state$pending_full_text %||% list(),
    calendar_checked_at = outlook_utc(state$calendar$checked_at),
    calendar_fresh = !is.null(state$calendar) && is.null(state$calendar_error) && now < state$next_calendar_at,
    calendar_sources = state$calendar$sources, calendar_error = state$calendar_error,
    calendar_warnings = if (!is.null(state$calendar) && any(!state$calendar$events$business_day_confirmed))
      "Holiday-year coverage is unavailable for some full-text dates; their polling bounds are unconfirmed." else NULL,
    updater_outcome = state$updater_outcome, error = state$error,
    failure_count = state$failure_count %||% 0L,
    state_schema = .readboj_outlook_maintenance_schema,
    state_fallback_errors = attr(state, "maintenance_fallback_errors") %||% character())
}

#' Inspect local calendar-aware Outlook maintenance state
#' @param data_dir Persistent directory shared with saved reads and maintenance.
#' @return Machine-readable local status with UTC ISO8601 next-due/release times,
#'   pending full text, calendar freshness, updater outcome and errors. No network.
#' @examples
#' boj_outlook_maintenance_status(data_dir = tempfile("outlook-data-"))
#' @export
boj_outlook_maintenance_status <- function(data_dir = boj_outlook_data_dir()) {
  state <- outlook_maintenance_read(file.path(path.expand(scalar_character(data_dir, "data_dir")), "maintenance"))
  now <- outlook_now()
  if (is.null(state)) return(list(status = "uninitialized", next_due_at = outlook_utc(now), due = TRUE,
    state_schema = .readboj_outlook_maintenance_schema))
  outlook_maintenance_result(state, now)
}

#' Maintain saved Outlook data and its official next-release schedule
#'
#' A scheduler can invoke this hourly. A not-due call reads local state only.
#' Due daily revision checks use the full incremental updater. Around an overdue
#' release, cheap archive/HEAD probes trigger a forced update only after links,
#' dates or validators change. Bank's View and next-business-day full text remain
#' separate pending stages. Every update recomputes the next due time from fresh
#' official calendar evidence. No OS job or background worker is installed.
#' @param data_dir Persistent directory shared with ordinary saved reads.
#' @param force Ignore maintenance timing and run a full source/calendar check.
#' @param calendar_max_age,revision_interval Seconds between calendar refreshes
#'   and complete historical source revision checks (defaults one day).
#' @param probe_interval Minimum seconds between release-window metadata probes.
#' @param timeout,retries,deadline Bounded request/deadline settings.
#' @param ... Additional arguments for [update_boj_outlook()], such as a Poppler
#'   path. Maintenance never enables coverage-loss opt-in automatically.
#' @return A list with status, scalar ISO8601 UTC `next_due_at`, release/date/
#'   edition, separate full-text pending state, freshness and errors. Operational
#'   failures return `failed` and a persisted bounded retry schedule, preserving
#'   last-good numeric data and calendar. Busy writers return `busy` for retry.
#' @examples
#' \dontrun{
#' # A scheduler and ordinary readers should share one persistent directory.
#' maintain_boj_outlook(data_dir = boj_outlook_data_dir(),
#'                      deadline = Sys.time() + 1800)
#' }
#' @export
maintain_boj_outlook <- function(data_dir = boj_outlook_data_dir(), force = FALSE,
    calendar_max_age = 86400, revision_interval = 86400, probe_interval = 3600,
    timeout = 30, retries = 2L, deadline = NULL, ...) {
  data_dir <- path.expand(scalar_character(data_dir, "data_dir"))
  force <- scalar_flag(force, "force")
  calendar_max_age <- scalar_number(calendar_max_age, "calendar_max_age", min = 60)
  revision_interval <- scalar_number(revision_interval, "revision_interval", min = 3600)
  probe_interval <- scalar_number(probe_interval, "probe_interval", min = 60)
  timeout <- scalar_number(timeout, "timeout", min = 0.001)
  retries <- outlook_count(retries + 1L, "retries + 1", 11L) - 1L
  deadline <- resolve_deadline(deadline, 1800)
  now <- outlook_now()
  root <- file.path(data_dir, "maintenance")
  state <- outlook_maintenance_read(root)
  if (!force && !is.null(state) && now < state$next_due_at) {
    return(outlook_maintenance_result(state, now, if (identical(state$status, "failed")) "failed" else "idle"))
  }
  if (!dir.exists(root) && !dir.create(root, recursive = TRUE)) readboj_abort(
    "Could not create maintenance directory.", "readboj_outlook_calendar_error")
  lock <- tryCatch(outlook_update_lock(root), error = identity)
  if (inherits(lock, "error")) return(list(status = "busy", next_due_at = outlook_utc(now + 60),
    error = conditionMessage(lock), state_schema = .readboj_outlook_maintenance_schema))
  on.exit(outlook_release_lock(lock), add = TRUE)
  unlink(file.path(root, c(".calendar-stage", ".archive-probe.htm")), recursive = TRUE)
  state <- outlook_maintenance_read(root)
  if (!force && !is.null(state) && now < state$next_due_at) {
    return(outlook_maintenance_result(state, now, if (identical(state$status, "failed")) "failed" else "idle"))
  }
  loaded <- outlook_saved_load(data_dir)
  snapshot <- loaded$snapshot
  if (is.null(state)) {
    checked <- outlook_latest_check(data_dir)$last_successful_check %||% snapshot$checked_at
    state <- list(schema = .readboj_outlook_maintenance_schema, status = "idle", calendar = NULL,
      next_due_at = now, next_calendar_at = now, next_revision_at = checked + revision_interval,
      next_probe_at = now, failure_count = 0L)
  }
  operation <- "calendar"
  refreshed <- FALSE
  did_update <- FALSE
  record_failure <- function(component, error) {
    detail <- list(operation = component, message = conditionMessage(error), class = class(error)[[1L]])
    state$failure_count <<- min(5L, (state$failure_count %||% 0L) + 1L)
    retry <- max(now, outlook_now()) + c(300, 900, 3600, 21600, 86400)[[state$failure_count]]
    if (component == "calendar") {
      state$calendar_error <<- detail
      state$next_calendar_at <<- retry
    } else if (component == "update") {
      state$update_error <<- detail
      state$next_revision_at <<- retry
    } else if (component == "probe") {
      state$probe_error <<- detail
      state$next_probe_at <<- retry
    }
    state$error <<- detail
    state$retry_action <<- component
    invisible(retry)
  }
  run_update <- function() {
    operation <<- "update"
    state$updater_outcome <<- NULL
    outcome <- tryCatch(update_boj_outlook(data_dir = data_dir, force = TRUE,
      timeout = timeout, retries = retries, deadline = deadline, ...), error = function(e) {
        state$updater_outcome <<- e$status %||% list(status = "failed", error = conditionMessage(e))
        stop(e)
      })
    state$updater_outcome <<- outcome
    state$next_revision_at <<- outlook_now() + revision_interval
    state$next_probe_at <<- outlook_now() + probe_interval
    state$update_error <<- NULL
    state$probe_error <<- NULL
    did_update <<- TRUE
    snapshot <<- outlook_saved_load(data_dir, refresh = TRUE)$snapshot
  }
  refresh_calendar <- function() {
    operation <<- "calendar"
    candidate <- outlook_fetch_calendar(timeout, retries, deadline, stage_dir = file.path(root, ".calendar-stage"))
    state$calendar <<- outlook_merge_calendar(state$calendar, candidate, snapshot$catalogue)
    state$next_calendar_at <<- candidate$checked_at + calendar_max_age
    state$calendar_error <<- NULL
    refreshed <<- TRUE
  }
  tryCatch({
    if (force || now >= state$next_calendar_at) {
      # Calendar availability must not gate an independent due numeric revision
      # check. Retain its failure, continue that work, then schedule its retry.
      tryCatch(refresh_calendar(), error = function(e) {
        record_failure("calendar", e)
      })
    }
    if (force || now >= state$next_revision_at) {
      tryCatch(run_update(), error = function(e) record_failure("update", e))
    } else {
      pending <- outlook_pending_calendar(state$calendar$events, snapshot$catalogue, state$calendar$holidays)
      due <- (!pending$view_available & pending$bank_view_poll_from_at <= now) |
        (pending$view_available & !pending$full_text_available & pending$full_text_poll_from_at <= now)
      if (any(due) && now >= state$next_probe_at) tryCatch({
        operation <- "probe"
        probe <- outlook_probe_archive(timeout, retries, deadline, path = file.path(root, ".archive-probe.htm"))
        changed <- !identical(outlook_catalogue_signature(probe$catalogue), outlook_catalogue_signature(snapshot$catalogue))
        state$archive_probe <- probe$receipt
        if (!changed) {
          urls <- snapshot$catalogue$banks_view_url[match(pending$publication_date[due & pending$view_available], snapshot$catalogue$publication_date)]
          for (url in unique(stats::na.omit(urls))) {
            previous <- state$asset_probes[[url]] %||% snapshot$assets[[url]]
            metadata <- outlook_probe_asset(url, previous, timeout, retries, deadline)
            observed <- list(etag = previous$etag, last_modified = previous$last_modified)
            if (!is.null(metadata$etag) && !is.na(metadata$etag)) observed$etag <- metadata$etag
            if (!is.null(metadata$last_modified) && !is.na(metadata$last_modified)) observed$last_modified <- metadata$last_modified
            state$asset_probes[[url]] <- observed
            changed <- changed || isTRUE(metadata$changed)
          }
        }
        state$next_probe_at <- now + probe_interval
        state$probe_error <- NULL
        if (changed && (is.null(state$update_error) || now >= state$next_revision_at)) {
          tryCatch(run_update(), error = function(e) record_failure("update", e))
        }
      }, error = function(e) record_failure("probe", e))
    }
    if (did_update && !refreshed && is.null(state$calendar_error)) {
      tryCatch(refresh_calendar(), error = function(e) record_failure("calendar", e))
    }
    completed <- outlook_now()
    state <- outlook_maintenance_plan(state, snapshot$catalogue, completed, probe_interval)
    pending_error <- state$update_error %||% state$calendar_error %||% state$probe_error
    state$status <- if (!is.null(pending_error)) "failed" else
      if (did_update && identical(state$updater_outcome$status, "updated")) "success" else
      if (did_update) "unchanged" else if (!is.null(state$next_release) && state$next_release$due <= completed) "waiting" else "idle"
    state$error <- pending_error
    if (is.null(pending_error)) {
      state$failure_count <- 0L
      state$retry_action <- NULL
    }
    state$completed_at <- outlook_now()
    operation <- "state"
    outlook_maintenance_write(state, root, lock)
    outlook_maintenance_result(state, completed)
  }, error = function(e) {
    state$status <- "failed"
    state$error <- list(operation = operation, message = conditionMessage(e), class = class(e)[[1L]])
    if (operation == "calendar") state$calendar_error <- state$error
    state$failure_count <- min(5L, (state$failure_count %||% 0L) + 1L)
    delay <- c(300, 900, 3600, 21600, 86400)[[state$failure_count]]
    state$retry_action <- operation
    state$next_due_at <- max(now, outlook_now()) + delay
    state$completed_at <- outlook_now()
    tryCatch(outlook_maintenance_write(state, root, lock), error = function(write_error) {
      state$error$state_write_error <<- conditionMessage(write_error)
    })
    outlook_maintenance_result(state, now)
  })
}
