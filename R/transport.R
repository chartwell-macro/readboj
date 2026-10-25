.readboj_hosts <- c("www.stat-search.boj.or.jp", "www.boj.or.jp")

validate_official_url <- function(url) {
  url <- scalar_character(url, "url")
  parsed <- httr2::url_parse(url)
  if (!identical(tolower(parsed$scheme %||% ""), "https") ||
      !tolower(parsed$hostname %||% "") %in% .readboj_hosts) {
    readboj_abort("URL must use HTTPS on an official Bank of Japan host.",
      "readboj_config_error", url = url, allowed_hosts = .readboj_hosts)
  }
  url
}

canonical_url <- function(url, query = list()) {
  url <- validate_official_url(url)
  if (length(query) == 0L) return(url)
  if (is.null(names(query)) || any(!nzchar(names(query)))) {
    readboj_abort("Query parameters must be named.", "readboj_parameter_error")
  }
  query <- query[order(names(query))]
  encoded <- vapply(names(query), function(name) {
    value <- query[[name]]
    if (length(value) != 1L || is.na(value)) {
      readboj_abort("Every query parameter must be one non-missing value.",
        "readboj_parameter_error")
    }
    paste0(utils::URLencode(name, reserved = TRUE), "=",
      utils::URLencode(as.character(value), reserved = TRUE))
  }, character(1L))
  paste0(url, if (grepl("?", url, fixed = TRUE)) "&" else "?", paste(encoded, collapse = "&"))
}

resolve_deadline <- function(deadline = NULL, default_seconds = 300) {
  if (is.null(deadline)) return(Sys.time() + default_seconds)
  if (!inherits(deadline, "POSIXt") || length(deadline) != 1L || is.na(deadline)) {
    readboj_abort("`deadline` must be one absolute POSIXct/POSIXlt time.",
      "readboj_parameter_error")
  }
  as.POSIXct(deadline, tz = "UTC")
}

deadline_remaining <- function(deadline) {
  remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
  if (!is.finite(remaining) || remaining <= 0) readboj_abort(
    "The caller-owned absolute deadline has expired.", "readboj_timeout_error",
    deadline = deadline)
  remaining
}

deadline_pause <- function(seconds, deadline) {
  seconds <- max(0, seconds)
  remaining <- deadline_remaining(deadline)
  if (seconds >= remaining) readboj_abort(
    "Retry delay would exceed the caller-owned absolute deadline.",
    "readboj_timeout_error", deadline = deadline, requested_delay = seconds)
  if (seconds > 0) Sys.sleep(seconds)
  invisible(NULL)
}

response_headers_list <- function(response) {
  headers <- httr2::resp_headers(response)
  as.list(stats::setNames(as.character(headers), names(headers)))
}

snapshot_provenance <- function(entry, semantic_sha256 = NA_character_) {
  list(
    canonical_url = entry$canonical_url,
    final_url = entry$final_url %||% entry$canonical_url,
    retrieved_at = as.POSIXct(entry$retrieved_at, tz = "UTC"),
    raw_sha256 = entry$raw_sha256,
    semantic_sha256 = semantic_sha256,
    bytes = entry$bytes,
    http_status = entry$http_status,
    etag = entry$etag %||% NA_character_,
    last_modified = entry$last_modified %||% NA_character_,
    response_headers = entry$response_headers,
    source_date = entry$source_date %||% NA_character_,
    cache_status = entry$cache_status,
    cache_path = entry$path %||% NA_character_,
    package_version = readboj_package_version(),
    parser_schema = .readboj_schema_version
  )
}

perform_once <- function(canonical, path, timeout, max_bytes) {
  request <- httr2::request(canonical)
  request <- httr2::req_headers(request, `Accept-Encoding` = "gzip")
  request <- httr2::req_user_agent(request,
    paste0("readboj/", readboj_package_version(), " (R; official BOJ statistics client)"))
  request <- httr2::req_timeout(request, seconds = timeout)
  request <- httr2::req_options(request, maxfilesize_large = max_bytes,
    maxredirs = 3L, protocols_str = "https", redir_protocols_str = "https")
  request <- httr2::req_error(request, is_error = function(resp) FALSE)
  response <- httr2::req_perform(request, path = path)
  validate_official_url(httr2::resp_url(response))
  response
}

abort_http_response <- function(entry, path) {
  payload <- tryCatch(jsonlite::fromJSON(rawToChar(read_raw_file(path, entry$bytes)),
    simplifyVector = FALSE), error = function(e) NULL)
  unlink(path)
  entry$path <- NA_character_
  entry$cache_status <- "not_cached_error"
  provenance <- snapshot_provenance(entry)
  status <- entry$http_status
  if (status == 429L) readboj_abort("The BOJ source rate-limited the request.",
    "readboj_rate_limit_error", http_status = status, provenance = provenance)
  if (status %in% c(401L, 403L)) readboj_abort("The BOJ source rejected authorization.",
    "readboj_auth_error", http_status = status, provenance = provenance)
  if (is.list(payload) && length(payload$STATUS) == 1L) {
    api_status <- suppressWarnings(as.integer(payload$STATUS))
    readboj_abort(sprintf("BOJ API error %s (%s): %s", api_status,
      as.character(payload$MESSAGEID %||% ""), as.character(payload$MESSAGE %||% "")),
      "readboj_api_error", status = api_status, message_id = payload$MESSAGEID,
      api_message = payload$MESSAGE, provenance = provenance)
  }
  readboj_abort(sprintf("BOJ source returned HTTP status %s.", status),
    "readboj_transport_error", http_status = status, provenance = provenance)
}

is_transient_transport_error <- function(error) {
  grepl(paste(
    "timed? ?out", "timeout", "temporar", "connection reset",
    "could not connect", "could not resolve", "resolve host",
    "empty reply", "partial file", "send failure", "receive failure",
    sep = "|"), conditionMessage(error), ignore.case = TRUE)
}

fetch_snapshot <- function(url, query = list(), cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 30, retries = 3L, wait = 1, max_bytes = 128 * 1024^2,
    deadline = NULL) {
  refresh <- scalar_flag(refresh, "refresh")
  offline <- scalar_flag(offline, "offline")
  max_age <- if (is.numeric(max_age) && length(max_age) == 1L && identical(max_age, Inf)) {
    Inf
  } else {
    scalar_number(max_age, "max_age", min = 0)
  }
  timeout <- scalar_number(timeout, "timeout", min = 0)
  retries <- scalar_number(retries, "retries", min = 0, integer = TRUE)
  wait <- scalar_number(wait, "wait", min = 0)
  max_bytes <- scalar_number(max_bytes, "max_bytes", min = 1)
  deadline <- resolve_deadline(deadline, default_seconds = max(60, timeout * (retries + 1L) + 30))
  canonical <- canonical_url(url, query)
  ensure_cache_dir(cache_dir)
  cached <- if (!refresh) read_cache_entry(cache_dir, canonical, max_age) else NULL
  if (!is.null(cached)) return(cached)
  if (offline) readboj_abort(sprintf("No valid offline snapshot exists for %s.", canonical),
    "readboj_offline_error", canonical_url = canonical)

  transient <- c(408L, 429L, 500L, 502L, 503L, 504L)
  for (attempt in seq_len(retries + 1L)) {
    attempt_timeout <- min(timeout, deadline_remaining(deadline))
    temporary <- tempfile("readboj-response-")
    result <- tryCatch(
      list(response = perform_once(canonical, temporary, attempt_timeout, max_bytes), error = NULL),
      error = function(e) list(response = NULL, error = e)
    )
    if (!is.null(result$error)) {
      unlink(temporary)
      transient_error <- is_transient_transport_error(result$error)
      if (attempt <= retries && transient_error) {
        deadline_pause(max(wait, min(8, 2^(attempt - 1L))), deadline)
        next
      }
      class <- if (grepl("timed? ?out|timeout", conditionMessage(result$error),
        ignore.case = TRUE)) "readboj_timeout_error" else "readboj_transport_error"
      readboj_abort(paste0("BOJ request failed: ", conditionMessage(result$error)),
        class, parent = result$error, canonical_url = canonical, deadline = deadline)
    }
    response <- result$response
    status <- httr2::resp_status(response)
    if (status %in% transient && attempt <= retries) {
      unlink(temporary)
      retry_after <- suppressWarnings(as.numeric(httr2::resp_header(response, "retry-after")))
      if (!is.na(retry_after) && retry_after > 60) readboj_abort(
        "BOJ Retry-After exceeds the 60-second safety bound.",
        "readboj_rate_limit_error", retry_after = retry_after)
      deadline_pause(max(wait, ifelse(is.na(retry_after), 0, retry_after),
        min(8, 2^(attempt - 1L))), deadline)
      next
    }
    size <- file.info(temporary)$size
    if (is.na(size) || size > max_bytes) {
      unlink(temporary)
      readboj_abort(sprintf("BOJ response exceeded the %s-byte bound.", max_bytes),
        "readboj_size_error", bytes = size, byte_limit = max_bytes)
    }
    final_url <- httr2::resp_url(response)
    entry <- list(
      canonical_url = canonical, final_url = final_url,
      retrieved_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
      raw_sha256 = sha256_file(temporary), bytes = unname(size),
      http_status = status, response_headers = response_headers_list(response),
      source_date = httr2::resp_header(response, "date") %||% NA_character_,
      etag = httr2::resp_header(response, "etag") %||% NA_character_,
      last_modified = httr2::resp_header(response, "last-modified") %||% NA_character_
    )
    if (status >= 400L) abort_http_response(entry, temporary)
    bounds <- cache_bounds()
    if (entry$bytes > bounds$bytes) {
      unlink(temporary)
      readboj_abort("Response exceeds the configured total cache byte bound.",
        "readboj_cache_error", bytes = entry$bytes, cache_max_bytes = bounds$bytes)
    }
    entry <- write_cache_entry(cache_dir, entry, temporary)
    prune_cache_objects(cache_dir, bounds$bytes, bounds$entries,
      protected_hash = entry$raw_sha256)
    return(entry)
  }
  readboj_abort("BOJ retry loop ended unexpectedly.", "readboj_transport_error")
}

download_snapshot <- function(url, cache_dir = boj_cache_dir(), refresh = FALSE,
    offline = FALSE, max_age = 24 * 60 * 60, timeout = 60, retries = 3L,
    wait = 1, max_bytes = 512 * 1024^2, deadline = NULL) {
  entry <- fetch_snapshot(url, cache_dir = cache_dir, refresh = refresh, offline = offline,
    max_age = max_age, timeout = timeout, retries = retries, wait = wait,
    max_bytes = max_bytes, deadline = deadline)
  structure(entry$path, class = c("boj_file", "character"),
    readboj_provenance = snapshot_provenance(entry))
}
