outlook_now <- function() as.POSIXct(Sys.time(), tz = "UTC")

outlook_latest_check <- function(data_dir) {
  paths <- sort(list.files(file.path(data_dir, "checks"), pattern = "^[0-9]+-[a-f0-9]+\\.rds$",
    full.names = TRUE), decreasing = TRUE)
  for (path in paths) {
    check <- tryCatch(if (file.info(path)$size <= 65536) readRDS(path) else NULL,
      error = function(e) NULL)
    if (is.list(check) && is.character(check$status) && length(check$status) == 1L &&
        inherits(check$attempted_at, "POSIXt")) return(check)
  }
  NULL
}

outlook_atomic_rds <- function(x, destination, compress = "gzip") {
  temporary <- tempfile(".pending-", tmpdir = dirname(destination))
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(x, temporary, compress = compress, version = 2)
  if (!file.rename(temporary, destination)) readboj_abort(
    "Could not atomically publish Outlook metadata.", "readboj_outlook_update_error")
  invisible(destination)
}

outlook_write_check <- function(data_dir, status) {
  directory <- file.path(data_dir, "checks")
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  id <- digest::digest(list(status, Sys.getpid(), tempfile()), algo = "sha256")
  name <- paste0(sprintf("%020.0f", as.numeric(outlook_now()) * 1e6), "-", id, ".rds")
  outlook_atomic_rds(status, file.path(directory, name))
  paths <- sort(list.files(directory, full.names = TRUE), decreasing = TRUE)
  if (length(paths) > 30L) unlink(paths[-seq_len(30L)])
  invisible(status)
}

outlook_lock_owner <- function(path) tryCatch(readRDS(file.path(path, "owner.rds")),
  error = function(e) NULL)

outlook_windows_pid_alive <- function(pid, query = system2) {
  result <- tryCatch(suppressWarnings(query("tasklist",
    c("/FI", shQuote(paste("PID eq", pid)), "/FO", "CSV", "/NH"),
    stdout = TRUE, stderr = FALSE, timeout = 2)), error = identity)
  # An unavailable query cannot prove that a lock owner is dead.
  if (inherits(result, "error") ||
      (!is.null(attr(result, "status")) && attr(result, "status") != 0L)) return(TRUE)
  rows <- tryCatch(utils::read.csv(text = paste(result, collapse = "\n"),
    header = FALSE, colClasses = "character"), error = function(e) NULL)
  if (is.null(rows)) return(TRUE)
  # A successful filtered tasklist query reports no match as a single text field.
  if (ncol(rows) < 2L) return(FALSE)
  any(suppressWarnings(as.numeric(rows[[2L]])) == pid, na.rm = TRUE)
}

outlook_pid_alive <- function(pid) {
  if (!is.numeric(pid) || length(pid) != 1L || !is.finite(pid) ||
      pid <= 0 || pid > .Machine$integer.max || pid != floor(pid)) return(TRUE)
  if (pid == Sys.getpid()) return(TRUE)
  if (.Platform$OS.type == "windows") return(outlook_windows_pid_alive(pid))
  isTRUE(tryCatch(tools::pskill(pid, signal = 0L), error = function(e) TRUE))
}

outlook_update_lock <- function(data_dir) {
  path <- file.path(data_dir, "update.lock")
  host <- unname(Sys.info()[["nodename"]])
  if (!dir.create(path, showWarnings = FALSE)) {
    owner <- outlook_lock_owner(path)
    # Reclaim only a provably dead local owner, or an hour-old incomplete lock.
    dead <- !is.null(owner) && identical(owner$host, host) &&
      !outlook_pid_alive(owner$pid)
    incomplete <- is.null(owner) && isTRUE(as.numeric(difftime(outlook_now(),
      file.info(path)$mtime, units = "secs")) > 3600)
    if (dead || incomplete) {
      abandoned <- tempfile("abandoned-lock-", tmpdir = data_dir)
      if (file.rename(path, abandoned)) unlink(abandoned, recursive = TRUE)
    }
    if (!dir.create(path, showWarnings = FALSE)) readboj_abort(
      "Another Outlook updater owns the lock. Retry after it finishes; inspect update.lock if its remote owner has stopped.",
      "readboj_outlook_locked_error", owner = owner)
  }
  owner <- list(pid = Sys.getpid(), host = host, started_at = outlook_now(),
    token = digest::digest(list(Sys.getpid(), outlook_now(), tempfile()), algo = "sha256"))
  outlook_atomic_rds(owner, file.path(path, "owner.rds"))
  list(path = path, owner = owner)
}

outlook_assert_lock <- function(lock) {
  if (!identical(outlook_lock_owner(lock$path)$token, lock$owner$token)) readboj_abort(
    "Outlook update lock ownership changed; publication was cancelled.", "readboj_outlook_conflict_error")
  invisible(TRUE)
}

outlook_release_lock <- function(lock) {
  if (identical(outlook_lock_owner(lock$path)$token, lock$owner$token)) unlink(lock$path, recursive = TRUE)
  invisible(NULL)
}

outlook_removed_identities <- function(previous, candidate) {
  identity <- c("release", "forecast_vintage", "comparison", "fiscal_year",
    "measure", "statistic", "range_scope")
  before <- do.call(paste, c(previous[identity], sep = "\r"))
  after <- do.call(paste, c(candidate[identity], sep = "\r"))
  removed <- previous[!before %in% after, identity, drop = FALSE]
  rownames(removed) <- NULL
  removed
}

outlook_update_request <- function(url, previous, path, timeout, retries, wait, max_bytes, deadline,
    max_total_bytes = Inf) {
  validate_official_url(url)
  transferred <- 0
  for (attempt in seq_len(retries + 1L)) {
    bound <- min(max_bytes, max_total_bytes - transferred)
    if (bound < 1) readboj_abort("Outlook retries exhausted the total raw byte bound.",
      "readboj_size_error", transfer_bytes = transferred, request_attempts = attempt - 1L)
    request <- httr2::request(url)
    request <- httr2::req_user_agent(request, paste0("readboj/", readboj_package_version(), " Outlook updater"))
    headers <- list(`Accept-Encoding` = "gzip")
    if (!is.null(previous)) {
      if (is.character(previous$etag) && !is.na(previous$etag) && nzchar(previous$etag)) headers[["If-None-Match"]] <- previous$etag
      if (is.character(previous$last_modified) && !is.na(previous$last_modified) && nzchar(previous$last_modified)) {
        headers[["If-Modified-Since"]] <- previous$last_modified
      }
    }
    request <- do.call(httr2::req_headers, c(list(request), headers))
    request <- httr2::req_timeout(request, min(timeout, deadline_remaining(deadline)))
    request <- httr2::req_options(request, maxfilesize_large = bound, maxredirs = 0L,
      protocols_str = "https", redir_protocols_str = "https")
    request <- httr2::req_error(request, is_error = function(resp) FALSE)
    unlink(path)
    response <- tryCatch(httr2::req_perform(request, path = path), error = identity)
    received <- file.info(path)$size
    if (!is.na(received)) transferred <- transferred + received
    if (transferred > max_total_bytes) readboj_abort("Outlook retries exceeded the total raw byte bound.",
      "readboj_size_error", transfer_bytes = transferred, request_attempts = attempt)
    if (inherits(response, "error")) {
      unlink(path)
      if (attempt <= retries && is_transient_transport_error(response)) {
        deadline_pause(max(wait, min(8, 2^(attempt - 1L))), deadline)
        next
      }
      readboj_abort(paste0("Outlook source check failed: ", conditionMessage(response)),
        "readboj_transport_error", parent = response, url = url,
        transfer_bytes = transferred, request_attempts = attempt)
    }
    status <- httr2::resp_status(response)
    if (!identical(httr2::resp_url(response), url)) readboj_abort(
      "Outlook source redirected to another identity.", "readboj_identity_error", url = url)
    if (status %in% c(408L, 429L, 500L, 502L, 503L, 504L) && attempt <= retries) {
      unlink(path)
      after <- suppressWarnings(as.numeric(httr2::resp_header(response, "retry-after") %||% NA_character_))
      if (!is.na(after) && after > 60) readboj_abort("Outlook Retry-After exceeds 60 seconds.", "readboj_rate_limit_error")
      deadline_pause(max(wait, ifelse(is.na(after), 0, after), min(8, 2^(attempt - 1L))), deadline)
      next
    }
    if (status == 304L) {
      unlink(path)
      if (is.null(previous)) readboj_abort("Unexpected source 304 without a prior identity.", "readboj_transport_error")
      previous$path <- NULL
      previous$http_status <- 304L
      previous$checked_at <- outlook_now()
      previous$transfer_bytes <- transferred
      previous$request_attempts <- attempt
      return(previous)
    }
    if (status != 200L) readboj_abort(sprintf("Outlook source returned HTTP %s.", status),
      "readboj_transport_error", http_status = status, url = url,
      transfer_bytes = transferred, request_attempts = attempt)
    size <- file.info(path)$size
    if (is.na(size) || size < 1 || size > bound) readboj_abort(
      "Outlook source exceeded the response byte bound.", "readboj_size_error", url = url)
    return(list(canonical_url = url, final_url = url, path = path,
      raw_sha256 = sha256_file(path), bytes = size, http_status = status,
      transfer_bytes = transferred, request_attempts = attempt,
      retrieved_at = format(outlook_now(), tz = "UTC", usetz = TRUE),
      checked_at = outlook_now(), response_headers = response_headers_list(response),
      etag = httr2::resp_header(response, "etag") %||% NA_character_,
      last_modified = httr2::resp_header(response, "last-modified") %||% NA_character_,
      source_date = httr2::resp_header(response, "date") %||% NA_character_,
      cache_status = "update_staging"))
  }
  readboj_abort("Outlook retry loop ended unexpectedly.", "readboj_transport_error")
}

outlook_cleanup_objects <- function(data_dir) {
  markers <- outlook_saved_markers(data_dir)
  if (length(markers) > 3L) unlink(markers[-seq_len(3L)])
  keep <- sub("^[0-9]{12}-", "", basename(utils::head(markers, 3L)))
  directory <- file.path(data_dir, "objects")
  objects <- list.files(directory, pattern = "^[a-f0-9]{64}\\.rds$", full.names = TRUE)
  unlink(objects[!basename(objects) %in% keep])
  for (name in c("objects", "commits", "checks")) {
    unlink(list.files(file.path(data_dir, name), pattern = "^\\.pending-",
      all.files = TRUE, full.names = TRUE))
  }
  invisible(NULL)
}

outlook_publish <- function(snapshot, data_dir, lock, base_markers) {
  outlook_saved_validate(snapshot)
  if (as.numeric(utils::object.size(snapshot)) > 64 * 1024^2) readboj_abort(
    "Structured Outlook history exceeds the 64 MiB in-memory bound; archive revisions explicitly before retrying.",
    "readboj_size_error")
  directory <- file.path(data_dir, "objects")
  dir.create(directory, showWarnings = FALSE)
  dir.create(file.path(data_dir, "commits"), showWarnings = FALSE)
  pending <- tempfile(".pending-", tmpdir = directory)
  created <- committed <- FALSE
  destination <- NULL
  on.exit({
    unlink(pending)
    if (created && !committed && identical(outlook_lock_owner(lock$path)$token, lock$owner$token)) {
      unlink(destination)
    }
  }, add = TRUE)
  saveRDS(snapshot, pending, compress = "xz", version = 2)
  outlook_saved_read_file(pending)
  hash <- sha256_file(pending)
  destination <- file.path(directory, paste0(hash, ".rds"))
  if (file.exists(destination) && !identical(sha256_file(destination), hash)) readboj_abort(
    "Existing immutable Outlook object is corrupt.", "readboj_outlook_data_error")
  if (!file.exists(destination)) {
    if (!file.rename(pending, destination)) readboj_abort(
      "Could not publish immutable Outlook object.", "readboj_outlook_update_error")
    created <- TRUE
  }
  outlook_assert_lock(lock)
  if (!identical(outlook_saved_markers(data_dir), base_markers)) readboj_abort(
    "Outlook generation changed during update; publication was cancelled.", "readboj_outlook_conflict_error")
  generation <- if (length(base_markers)) max(as.numeric(substr(basename(base_markers), 1L, 12L))) + 1 else 1
  marker <- file.path(data_dir, "commits", sprintf("%012.0f-%s.rds", generation, hash))
  outlook_atomic_rds(list(generation = generation, sha256 = hash), marker)
  committed <- TRUE
  # Keep three complete generations. Readers hold immutable loaded objects; a
  # reader racing cleanup retries another marker instead of opening a partial file.
  outlook_cleanup_objects(data_dir)
  list(generation = generation, sha256 = hash, bytes = unname(file.info(destination)$size))
}

#' Inspect local Outlook data and updater status
#' @param data_dir Directory containing refreshed structured data.
#' @return A list of coverage, snapshot/parser identities, freshness, last update
#'   outcome and fallback errors. This performs no network or source parsing.
#' @examples
#' boj_outlook_status(data_dir = tempfile("outlook-data-"))
#' @export
boj_outlook_status <- function(data_dir = boj_outlook_data_dir()) {
  loaded <- outlook_saved_load(data_dir)
  x <- loaded$snapshot
  c(outlook_saved_receipt(loaded), list(editions = nrow(x$catalogue), rows = nrow(x$data),
    first_release = min(x$catalogue$release), latest_release = max(x$catalogue$release),
    parser_update_required = !identical(x$parser_sha256, outlook_parser_fingerprint()) ||
      !identical(x$parser_schema, .readboj_outlook_schema),
    last_attempt = outlook_latest_check(data_dir), data_dir = path.expand(data_dir)))
}

#' Incrementally refresh saved Outlook forecast tables
#'
#' Checks the live archive and every linked Bank's View/full-text asset using
#' HTTP validators where available and SHA-256 otherwise. A changed URL, source
#' hash or parser invalidates only its dependent editions (all editions after a
#' parser change). Unchanged numeric tables are reused. Missing historical
#' editions fail validation rather than silently reducing coverage.
#'
#' A complete candidate is validated before an atomic commit. The package bundle
#' is read-only. Readers use the newest valid local generation, falling back
#' with an explicit warning if it is corrupt. One writer holds a process lock;
#' checks are throttled to once per UTC day unless forced or the parser changed.
#' Failed attempts are recorded separately and never replace good data.
#'
#' Raw staging is deleted on success/error and at the next locked run after a
#' crash. No raw documents are retained. At most three structured generations
#' and thirty check receipts remain. Revision history within the current snapshot
#' retains superseded tables and receipts, with a 32 MiB serialized-file bound;
#' exceeding a bound fails without discarding history.
#'
#' @param data_dir Persistent user directory also used by ordinary reads.
#' @param force Bypass daily attempt throttling.
#' @param rebuild Reparse all editions, including unchanged sources.
#' @param allow_coverage_loss Explicit reviewed opt-in to removing existing
#'   logical scalar identities/targets from an edition. Default `FALSE` rejects
#'   partial-but-otherwise-valid revisions. When enabled, removed identities and
#'   original rows/receipts remain in revision history and the outcome reports
#'   the reduction. Use `force = TRUE` for a same-day retry after rejection.
#' @param timeout,retries,wait Per-request timeout, bounded retry count and delay.
#' @param max_bytes Per-source response bound.
#' @param max_total_bytes Total downloaded raw bytes per transaction; also bounds
#'   staged raw bytes. All staging is temporary.
#' @param max_releases Maximum discovered editions (1 through 1,000).
#' @param max_pdf_pages,max_text_bytes,pdftotext See [read_boj_outlook_raw()].
#' @param deadline Caller-owned absolute deadline; default thirty minutes.
#' @return A status list: `updated`, `unchanged`, or `throttled`, identities,
#'   changed assets/editions, parse counts, bytes downloaded and publication size.
#'   Failures raise a typed error and leave a `failed` local check receipt.
#' @examples
#' \dontrun{
#' update_boj_outlook(data_dir = boj_outlook_data_dir(),
#'                    deadline = Sys.time() + 1800)
#' }
#' @export
update_boj_outlook <- function(data_dir = boj_outlook_data_dir(), force = FALSE,
    rebuild = FALSE, timeout = 30, retries = 2L, wait = 0.1,
    max_bytes = 16 * 1024^2, max_total_bytes = 256 * 1024^2,
    max_releases = 200L, max_pdf_pages = 20L, max_text_bytes = 1024^2,
    pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
    deadline = NULL, allow_coverage_loss = FALSE) {
  data_dir <- path.expand(scalar_character(data_dir, "data_dir"))
  force <- scalar_flag(force, "force")
  rebuild <- scalar_flag(rebuild, "rebuild")
  allow_coverage_loss <- scalar_flag(allow_coverage_loss, "allow_coverage_loss")
  timeout <- scalar_number(timeout, "timeout", min = 0.001)
  retries <- outlook_count(retries + 1, "retries + 1", 11L) - 1L
  wait <- scalar_number(wait, "wait", min = 0)
  max_bytes <- scalar_number(max_bytes, "max_bytes", min = 1)
  max_total_bytes <- scalar_number(max_total_bytes, "max_total_bytes", min = 1)
  max_releases <- outlook_count(max_releases, "max_releases", 1000L)
  max_pdf_pages <- outlook_count(max_pdf_pages, "max_pdf_pages", 100L)
  max_text_bytes <- scalar_number(max_text_bytes, "max_text_bytes", min = 1)
  deadline <- resolve_deadline(deadline, 1800)
  deadline_remaining(deadline)
  loaded <- outlook_saved_load(data_dir)
  prior <- loaded$snapshot
  parser <- outlook_parser_fingerprint()
  last <- outlook_latest_check(data_dir)
  if (!force && !rebuild && !is.null(last) && last$status %in% c("updated", "unchanged", "failed") && identical(last$parser_sha256, parser) &&
      identical(as.Date(last$attempted_at, tz = "UTC"), as.Date(outlook_now(), tz = "UTC"))) {
    return(c(list(status = "throttled", previous_status = last$status),
      last[setdiff(names(last), "status")]))
  }
  if (!dir.exists(data_dir) && !dir.create(data_dir, recursive = TRUE)) readboj_abort(
    "Could not create Outlook data directory.", "readboj_outlook_update_error")
  lock <- outlook_update_lock(data_dir)
  on.exit(outlook_release_lock(lock), add = TRUE)
  # Re-read under the lock: another updater may have completed during startup.
  loaded <- outlook_saved_load(data_dir, refresh = TRUE)
  prior <- loaded$snapshot
  last <- outlook_latest_check(data_dir)
  if (!force && !rebuild && !is.null(last) && last$status %in% c("updated", "unchanged", "failed") && identical(last$parser_sha256, parser) &&
      identical(as.Date(last$attempted_at, tz = "UTC"), as.Date(outlook_now(), tz = "UTC"))) {
    return(list(status = "throttled", previous_status = last$status, attempted_at = last$attempted_at))
  }
  base_markers <- outlook_saved_markers(data_dir)
  outlook_cleanup_objects(data_dir)
  base_markers <- outlook_saved_markers(data_dir)
  staging <- file.path(data_dir, ".staging")
  unlink(staging, recursive = TRUE)
  if (!dir.create(staging)) readboj_abort("Could not create bounded Outlook staging.", "readboj_outlook_update_error")
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  status <- list(status = "running", attempted_at = outlook_now(), parser_sha256 = parser,
    last_successful_check = last$last_successful_check %||% prior$checked_at,
    requests = 0L, downloaded_bytes = 0, parsed_editions = character(), changed_assets = character())
  outlook_write_check(data_dir, status)
  result <- tryCatch({
    entries <- new.env(parent = emptyenv())
    get_source <- function(url, previous = NULL, require_body = FALSE) {
      if (exists(url, envir = entries, inherits = FALSE)) {
        e <- get(url, envir = entries)
        if (!require_body || (!is.null(e$path) && file.exists(e$path))) return(e)
        previous <- NULL
      }
      remaining <- max_total_bytes - status$downloaded_bytes
      if (remaining < 1) readboj_abort("Outlook update exhausted its total raw byte bound.", "readboj_size_error")
      if (status$requests > 0L && wait > 0) deadline_pause(wait, deadline)
      path <- tempfile("source-", tmpdir = staging)
      e <- tryCatch(outlook_update_request(url, if (require_body) NULL else previous, path,
        timeout, retries, wait, min(max_bytes, remaining), deadline, max_total_bytes = remaining),
        error = function(e) {
          status$requests <<- status$requests + (e$request_attempts %||% 1L)
          status$downloaded_bytes <<- status$downloaded_bytes + (e$transfer_bytes %||% 0)
          stop(e)
        })
      status$requests <<- status$requests + (e$request_attempts %||% 1L)
      status$downloaded_bytes <<- status$downloaded_bytes + (e$transfer_bytes %||%
        if (!is.null(e$path)) file.info(e$path)$size else 0)
      if (!is.null(e$path)) {
        size <- file.info(e$path)$size
        if (is.na(size) || size < 1 || size > min(max_bytes, remaining) ||
            !identical(sha256_file(e$path), e$raw_sha256)) readboj_abort(
          "Invalid or excessive staged Outlook source.", "readboj_size_error")
      } else if (require_body || is.null(previous) || !identical(e$http_status, 304L) ||
          !identical(e$raw_sha256, previous$raw_sha256)) readboj_abort(
        "Source check did not return a usable identity.", "readboj_transport_error")
      if (!identical(e$canonical_url, url) || !identical(e$final_url, url)) readboj_abort(
        "Staged source identity mismatch.", "readboj_identity_error")
      assign(url, e, envir = entries)
      e
    }
    # The archive itself must have a body so link and date changes are discovered.
    index <- get_source(.readboj_outlook_index, require_body = TRUE)
    status$archive_sha256 <- index$raw_sha256
    catalogue <- parse_outlook_releases(index, min(max_bytes, 8 * 1024^2), max_releases, deadline)
    if (!all(prior$catalogue$release %in% catalogue$release)) readboj_abort(
      "The archive lost historical editions; refusing a partial refresh.", "readboj_outlook_coverage_error",
      missing_editions = setdiff(prior$catalogue$release, catalogue$release))
    urls <- unique(stats::na.omit(c(catalogue$banks_view_url, catalogue$full_text_url)))
    status$source_assets <- length(urls)
    assets <- list()
    for (url in urls) {
      e <- get_source(url, prior$assets[[url]])
      changed <- is.null(prior$assets[[url]]) || !identical(e$raw_sha256, prior$assets[[url]]$raw_sha256)
      if (changed) status$changed_assets <- c(status$changed_assets, url)
      assets[[url]] <- outlook_clean_receipt(e)
      # Unchanged bodies need not remain on disk. An affected dependency can be
      # fetched unconditionally later if parsing needs it after a 304/cleanup.
      if (!changed && !is.null(e$path)) unlink(e$path)
    }
    invalid_parser <- !identical(parser, prior$parser_sha256) ||
      !identical(.readboj_outlook_schema, prior$parser_schema)
    affected <- character()
    for (i in seq_len(nrow(catalogue))) {
      row <- catalogue[i, , drop = FALSE]
      old <- prior$catalogue[prior$catalogue$release == row$release, , drop = FALSE]
      attr(old, "readboj_provenance") <- NULL
      attr(row, "readboj_provenance") <- NULL
      rownames(old) <- rownames(row) <- NULL
      deps <- stats::na.omit(c(row$banks_view_url, row$full_text_url))
      if (rebuild || invalid_parser || !identical(row, old) || any(deps %in% status$changed_assets)) {
        affected <- c(affected, row$release)
      }
    }
    parts <- list()
    receipts <- prior$editions
    for (release in catalogue$release) {
      if (release %in% affected) {
        publication <- catalogue[catalogue$release == release, , drop = FALSE]
        fetch <- function(url) {
          e <- get_source(url, require_body = TRUE)
          if (!identical(e$raw_sha256, assets[[url]]$raw_sha256)) readboj_abort(
            "Source changed again during the update; refusing mixed revisions.", "readboj_outlook_conflict_error")
          e
        }
        rows <- read_outlook_edition(publication, fetch, pdftotext, max_bytes,
          max_pdf_pages, max_text_bytes, NULL, deadline)
        receipts[[release]] <- outlook_clean_receipt(boj_provenance(rows))
        status$parsed_editions <- c(status$parsed_editions, release)
      } else rows <- prior$data[prior$data$release == release, , drop = FALSE]
      attr(rows, "readboj_provenance") <- NULL
      parts[[release]] <- rows
    }
    data <- do.call(rbind, parts)
    rownames(data) <- NULL
    removed <- outlook_removed_identities(prior$data, data)
    status$coverage_loss <- list(allowed = allow_coverage_loss,
      removed_scalars = nrow(removed), editions = unique(removed$release),
      fiscal_years = sort(unique(removed$fiscal_year)),
      identities_sha256 = .readboj_content_digest(removed))
    if (nrow(removed) && !allow_coverage_loss) readboj_abort(
      "A revised edition lost existing logical scalar identities or fiscal targets; refusing a partial refresh. Review the removal before explicitly opting in with `allow_coverage_loss = TRUE`.",
      "readboj_outlook_coverage_error", removed_identities = removed)
    discovery <- outlook_clean_receipt(boj_provenance(catalogue))
    attr(catalogue, "readboj_provenance") <- NULL
    changed <- length(affected) > 0L || length(status$changed_assets) > 0L
    if (changed) {
      revisions <- prior$revisions
      replaced <- intersect(affected, prior$catalogue$release)
      if (length(replaced)) revisions[[length(revisions) + 1L]] <- list(
        superseded_at = outlook_now(), parser_sha256 = prior$parser_sha256,
        snapshot_sha256 = prior$content_sha256, editions = prior$editions[replaced],
        catalogue = prior$catalogue[prior$catalogue$release %in% replaced, , drop = FALSE],
        assets = prior$assets, data = prior$data[prior$data$release %in% replaced, , drop = FALSE],
        removed_identities = removed[removed$release %in% replaced, , drop = FALSE])
      candidate <- outlook_saved_seal(list(schema = .readboj_outlook_saved_schema,
        parser_schema = .readboj_outlook_schema, parser_sha256 = parser,
        built_at = outlook_now(), checked_at = outlook_now(), catalogue = catalogue,
        data = data, editions = receipts[catalogue$release], assets = assets,
        discovery = discovery, revisions = revisions, coverage_loss = status$coverage_loss))
      deadline_remaining(deadline)
      suspendInterrupts({
        publication <- outlook_publish(candidate, data_dir, lock, base_markers)
        status$publication <- publication
        status$snapshot_sha256 <- candidate$content_sha256
        status$status <- "updated"
      })
    } else {
      # Fully validate unchanged data too, without rewriting the dataset object.
      outlook_saved_validate(prior)
      status$status <- "unchanged"
      status$snapshot_sha256 <- prior$content_sha256
      status$publication <- list(generation = loaded$generation, bytes = 0)
    }
    status$last_successful_check <- outlook_now()
    status$completed_at <- outlook_now()
    # Publication has already succeeded. A receipt-write failure must not report
    # a failed transaction or imply that the valid new generation was rolled back.
    tryCatch(outlook_write_check(data_dir, status), error = function(e) {
      status$receipt_error <<- conditionMessage(e)
      warning("Outlook data is valid, but its final check receipt could not be saved.", call. = FALSE)
    })
    status
  }, interrupt = function(e) {
    if (!identical(status$status, "updated")) status$status <- "interrupted"
    status$completed_at <- outlook_now()
    status$error <- "Update interrupted by caller."
    try(outlook_write_check(data_dir, status), silent = TRUE)
    stop(e)
  }, error = function(e) {
    if (identical(status$status, "updated")) readboj_abort(
      paste0("Outlook data was committed successfully; ancillary status reporting failed. ", conditionMessage(e)),
      "readboj_outlook_receipt_error", parent = e, status = status)
    status$status <- "failed"
    status$completed_at <- outlook_now()
    status$error <- conditionMessage(e)
    status$error_class <- class(e)[[1L]]
    try(outlook_write_check(data_dir, status), silent = TRUE)
    readboj_abort(paste0("Outlook refresh failed; the last good dataset is unchanged. ",
      conditionMessage(e)), "readboj_outlook_update_error", parent = e, status = status)
  })
  result
}
