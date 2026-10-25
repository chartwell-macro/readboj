validate_codes <- function(code, max_codes_total) {
  if (!is.character(code) || length(code) == 0L || anyNA(code) || any(!nzchar(code))) {
    readboj_abort("`code` must be a non-empty character vector without missing values.",
      "readboj_parameter_error")
  }
  if (length(code) > max_codes_total) readboj_abort(sprintf(
    "`code` contains %s series, exceeding the %s-series bound.", length(code), max_codes_total),
    "readboj_size_error", series_limit = max_codes_total)
  if (anyDuplicated(code)) readboj_abort("`code` must not contain duplicates.", "readboj_parameter_error")
  code
}

next_position <- function(payload) {
  value <- payload$NEXTPOSITION
  if (is.null(value) || length(value) == 0L || identical(value, "")) return(NULL)
  if (length(value) != 1L || is.na(value) || !grepl("^[1-9][0-9]*$", as.character(value))) {
    readboj_abort("BOJ returned an invalid NEXTPOSITION.", "readboj_pagination_error")
  }
  as.character(value)
}

fetch_api_pages <- function(endpoint, query, db, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, max_pages, max_cells, deadline) {
  pages <- list()
  provenance <- list()
  position <- NULL
  seen <- character()
  cells <- 0L
  repeat {
    if (length(pages) >= max_pages) readboj_abort(sprintf(
      "BOJ pagination exceeded the %s-page bound.", max_pages), "readboj_pagination_error")
    page_query <- query
    if (!is.null(position)) page_query$startPosition <- position
    entry <- fetch_snapshot(paste0(.readboj_api_base, "/", endpoint), page_query,
      cache_dir = cache_dir, refresh = refresh, offline = offline, max_age = max_age,
      timeout = timeout, retries = retries, wait = wait, max_bytes = max_bytes,
      deadline = deadline)
    if (identical(query$format, "json")) {
      payload <- api_payload(entry$path, max_bytes)
      parsed <- parse_observation_payload(payload, db)
      semantic <- semantic_json_hash(entry$path, max_bytes)
      response_encoding <- "UTF-8"
    } else {
      csv <- parse_observation_csv(entry$path, db, query$lang, max_cells - cells)
      parsed <- csv$data
      payload <- as.list(csv$preamble)
      semantic <- semantic_csv_hash(entry$path, csv$encoding, max_bytes)
      response_encoding <- csv$encoding
    }
    cells <- cells + nrow(parsed)
    if (cells > max_cells) readboj_abort(sprintf(
      "BOJ observations exceed the %s-cell bound.", max_cells), "readboj_size_error",
      cell_limit = max_cells)
    pages[[length(pages) + 1L]] <- parsed
    page_provenance <- snapshot_provenance(entry, semantic)
    page_provenance$api_date <- as.character(payload$DATE %||% NA_character_)
    page_provenance$api_message_id <- as.character(payload$MESSAGEID %||% NA_character_)
    page_provenance$response_format <- query$format
    page_provenance$response_encoding <- response_encoding
    provenance[[length(provenance) + 1L]] <- page_provenance
    position <- next_position(payload)
    if (is.null(position)) break
    if (position %in% seen) readboj_abort("BOJ repeated NEXTPOSITION.", "readboj_pagination_error")
    seen <- c(seen, position)
    if (wait > 0 && !offline) deadline_pause(wait, deadline)
  }
  list(data = pages, provenance = provenance, cells = cells)
}

combine_api_results <- function(results, query) {
  pieces <- unlist(lapply(results, `[[`, "data"), recursive = FALSE)
  pieces <- Filter(function(x) nrow(x) > 0L, pieces)
  out <- if (length(pieces)) do.call(rbind, pieces) else empty_observations()
  rownames(out) <- NULL
  if (nrow(out)) {
    identity <- paste(out$db, out$series_code, out$period, sep = "\r")
    if (anyDuplicated(identity)) readboj_abort(
      "Duplicate observation identities occurred across API pages or batches; no rows were collapsed.",
      "readboj_identity_error", duplicate_keys = unique(identity[duplicated(identity) |
        duplicated(identity, fromLast = TRUE)]))
  }
  frequencies <- unique(out$frequency[nzchar(out$frequency)])
  if (length(frequencies) > 1L && !is.null(query$code)) {
    readboj_abort(paste0("Exact-code request returned multiple frequencies: ",
      paste(frequencies, collapse = ", "), "."), "readboj_parameter_error")
  }
  attach_provenance(out, list(
    source = "Bank of Japan Time-Series Data Search API",
    query = query,
    pages = unlist(lapply(results, `[[`, "provenance"), recursive = FALSE),
    total_cells = nrow(out), package_version = readboj_package_version(),
    parser_schema = .readboj_schema_version
  ))
}

#' Read Bank of Japan observations by exact series code
#'
#' Requests are split at the official 250-code limit and every exact
#' `NEXTPOSITION` cursor is followed. Missing JSON values remain `NA` rows.
#'
#' @param db Database identifier.
#' @param code Series code vector, without the database prefix.
#' @param start_date,end_date Optional BoJ `YYYY` or `YYYYPP` bounds.
#' @param language Response language, `"en"` or `"jp"`.
#' @param format Official response format, `"json"` or `"csv"`.
#' @param cache_dir Snapshot cache directory.
#' @param refresh Ignore a current request snapshot.
#' @param offline Require cached snapshots and make no network request.
#' @param max_age Maximum cache age in seconds.
#' @param timeout Request timeout in seconds.
#' @param retries Retry count for transient failures.
#' @param wait Seconds between automatic requests.
#' @param max_bytes Maximum decompressed response bytes per page.
#' @param max_pages Maximum pages across each code batch.
#' @param max_cells Maximum observation cells across the result.
#' @param max_codes_total Maximum accepted input series count.
#' @param deadline One absolute `POSIXct`/`POSIXlt` deadline shared by every
#'   batch, page, retry and delay in the call. A bounded default is created when
#'   omitted.
#' @return A data frame with exact period codes, parsed dates and provenance.
#' @export
read_boj_series <- function(db, code, start_date = NULL, end_date = NULL,
    language = "en", format = "json", cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 30, retries = 3L, wait = 1,
    max_bytes = 128 * 1024^2, max_pages = 100L, max_cells = 1000000L,
    max_codes_total = 5000L, deadline = NULL) {
  db <- normalize_db(db)
  language <- normalize_language(language, both = FALSE)
  format <- tolower(scalar_character(format, "format"))
  if (!format %in% c("json", "csv")) readboj_abort(
    "`format` must be `json` or `csv`.", "readboj_parameter_error")
  max_pages <- scalar_number(max_pages, "max_pages", min = 1, integer = TRUE)
  max_cells <- scalar_number(max_cells, "max_cells", min = 1, integer = TRUE)
  max_codes_total <- scalar_number(max_codes_total, "max_codes_total", min = 1, integer = TRUE)
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  code <- validate_codes(code, max_codes_total)
  start_date <- normalize_period(start_date, "start_date")
  end_date <- normalize_period(end_date, "end_date")
  if (!is.null(start_date) && !is.null(end_date) && start_date > end_date) {
    readboj_abort("`start_date` must not be after `end_date`.", "readboj_parameter_error")
  }
  chunks <- split(code, ceiling(seq_along(code) / .readboj_max_codes))
  results <- vector("list", length(chunks))
  remaining <- max_cells
  for (i in seq_along(chunks)) {
    if (i > 1L && wait > 0 && !offline) deadline_pause(wait, deadline)
    query <- list(format = format, lang = language, db = db,
      code = paste(chunks[[i]], collapse = ","))
    if (!is.null(start_date)) query$startDate <- start_date
    if (!is.null(end_date)) query$endDate <- end_date
    results[[i]] <- fetch_api_pages("getDataCode", query, db, cache_dir, refresh,
      offline, max_age, timeout, retries, wait, max_bytes, max_pages, remaining,
      deadline)
    remaining <- remaining - results[[i]]$cells
  }
  combine_api_results(results, list(db = db, code = code, start_date = start_date,
    end_date = end_date, language = language, format = format))
}

#' Read Bank of Japan observations by hierarchy layer
#'
#' @param frequency One of `CY`, `FY`, `CH`, `FH`, `Q`, `M`, `W`, or `D`.
#' @param layer One to five comma-separated hierarchy values; `*` is a wildcard.
#' @param max_series Maximum distinct series retained from a layer request.
#' @inheritParams read_boj_series
#' @return A data frame with provenance.
#' @export
read_boj_layer <- function(db, frequency, layer, start_date = NULL, end_date = NULL,
    language = "en", format = "json", cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 30, retries = 3L, wait = 1,
    max_bytes = 128 * 1024^2, max_pages = 100L, max_cells = 1000000L,
    max_series = 1250L, deadline = NULL) {
  db <- normalize_db(db)
  frequency <- toupper(scalar_character(frequency, "frequency"))
  if (!frequency %in% c("CY", "FY", "CH", "FH", "Q", "M", "W", "D")) {
    readboj_abort("`frequency` must be CY, FY, CH, FH, Q, M, W, or D.",
      "readboj_parameter_error")
  }
  language <- normalize_language(language, both = FALSE)
  format <- tolower(scalar_character(format, "format"))
  if (!format %in% c("json", "csv")) readboj_abort(
    "`format` must be `json` or `csv`.", "readboj_parameter_error")
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  if (is.numeric(layer)) layer <- as.character(layer)
  if (length(layer) > 1L) layer <- paste(layer, collapse = ",")
  layer <- scalar_character(layer, "layer")
  parts <- strsplit(layer, ",", fixed = TRUE)[[1L]]
  if (length(parts) > 5L || any(!grepl("^(\\*|[0-9]+)$", parts))) {
    readboj_abort("`layer` must contain one to five non-negative integers or `*`.",
      "readboj_parameter_error")
  }
  start_date <- normalize_period(start_date, "start_date")
  end_date <- normalize_period(end_date, "end_date")
  if (!is.null(start_date) && !is.null(end_date) && start_date > end_date) {
    readboj_abort("`start_date` must not be after `end_date`.", "readboj_parameter_error")
  }
  query <- list(format = format, lang = language, db = db,
    frequency = frequency, layer = layer)
  if (!is.null(start_date)) query$startDate <- start_date
  if (!is.null(end_date)) query$endDate <- end_date
  result <- fetch_api_pages("getDataLayer", query, db, cache_dir, refresh, offline,
    max_age, timeout, retries, wait, max_bytes,
    scalar_number(max_pages, "max_pages", min = 1, integer = TRUE),
    scalar_number(max_cells, "max_cells", min = 1, integer = TRUE), deadline)
  out <- combine_api_results(list(result), list(db = db, frequency = frequency, layer = layer,
    start_date = start_date, end_date = end_date, language = language, format = format))
  max_series <- scalar_number(max_series, "max_series", min = 1, integer = TRUE)
  if (length(unique(out$series_code)) > max_series) readboj_abort(
    "Layer result exceeds the caller's series bound.", "readboj_size_error",
    series_limit = max_series)
  out
}
