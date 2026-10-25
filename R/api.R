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

#' Read Bank of Japan observations for exact series codes
#'
#' Fetches observations from the official Bank of Japan (BOJ) Time-Series Data
#' Search `getDataCode` route for one or more exact series codes. Input codes
#' are sent in batches of at most 250 (the API limit), and every
#' `NEXTPOSITION` cursor returned by the service is followed in order. JSON
#' `null` values and CSV blank values remain rows rather than being dropped.
#' Use [read_boj_snapshot()] to parse a saved response without a network
#' request, or [boj_provenance()] to inspect the identity of responses used by
#' this function.
#'
#' @details
#' Requests use HTTPS and are restricted to the official BOJ hosts. Successful
#' response bodies are retained as content-addressed snapshots below
#' `cache_dir`; a valid snapshot is reused while it is within `max_age`, unless
#' `refresh = TRUE`. With `offline = TRUE`, no network request is attempted and
#' the call fails with class `readboj_offline_error` when a matching valid
#' snapshot is unavailable. Temporary response files are removed after a
#' successful cache write or an error.
#'
#' Each code batch is paginated independently. The result is never silently
#' deduplicated: duplicate `db`/`series_code`/`period` identities cause a
#' `readboj_identity_error`. The page, cell, byte, retry and absolute deadline
#' bounds are enforced before unbounded work can occur. The API's latest
#' revised history is returned; this function does not provide vintage or
#' as-of retrieval.
#'
#' @param db A BOJ database identifier, such as `"FM08"`. It is converted to
#'   uppercase after validation; an identifier with a syntactically valid shape
#'   can still be rejected by the BOJ API if that database is not available.
#' @param code A non-empty character vector of exact series codes without the
#'   database prefix. Values must be non-missing, non-empty and unique. The
#'   vector is limited by `max_codes_total` and split into API batches of 250.
#' @param start_date Optional inclusive lower period bound as one `YYYY` or
#'   `YYYYPP` code. `NULL` omits the bound from the request.
#' @param end_date Optional inclusive upper period bound as one `YYYY` or
#'   `YYYYPP` code. `NULL` omits the bound; when both bounds are supplied,
#'   `start_date` must not be later than `end_date`.
#' @param language Response language: exactly `"en"` or `"jp"`. The value
#'   controls the language fields returned by BOJ and, for CSV responses, the
#'   transfer encoding.
#' @param format Official response format, `"json"` or `"csv"`; matching is
#'   case-insensitive. JSON responses are parsed as UTF-8, while Japanese CSV
#'   responses are decoded as CP932.
#' @param cache_dir Character path to the snapshot cache. The default is
#'   `boj_cache_dir()`, which uses the `readboj.cache_dir` option or
#'   `tools::R_user_dir("readboj", "cache")`. Missing cache subdirectories are
#'   created as needed.
#' @param refresh Logical flag. When `TRUE`, bypasses a current cached request
#'   snapshot and obtains a fresh response. It is validated even when
#'   `offline = TRUE`.
#' @param offline Logical flag. When `TRUE`, requires a valid cached snapshot
#'   and makes no network request. It is useful for deterministic replay.
#' @param max_age Non-negative number of seconds for which a cached snapshot is
#'   considered current; `Inf` permits any age. The default is 24 hours.
#' @param timeout Non-negative number of seconds allowed for each HTTP attempt.
#'   The default is 30 seconds; the call-wide `deadline` remains authoritative.
#' @param retries Non-negative whole number of retries for transient transport
#'   or HTTP failures. The default is 3; non-transient failures are not retried.
#' @param wait Non-negative number of seconds used between pages, code batches
#'   and retries. It is skipped for offline reads and is bounded by `deadline`.
#' @param max_bytes Positive maximum decompressed response bytes per page. The
#'   default is 128 MiB; oversized responses fail with
#'   `readboj_size_error` before parsing or caching.
#' @param max_pages Positive whole-number maximum pages allowed for each code
#'   batch. The default is 100.
#' @param max_cells Positive whole-number maximum observation rows retained
#'   across all batches and pages. The default is 1,000,000.
#' @param max_codes_total Positive whole-number maximum number of input series
#'   codes. The default is 5,000; the official per-request 250-code batch limit
#'   is applied separately.
#' @param deadline An optional absolute one-element `POSIXct` or `POSIXlt`
#'   deadline shared by every batch, page, retry and delay. If `NULL`, a
#'   bounded deadline is derived from `timeout` and `retries` (at least five
#'   minutes). An expired deadline raises `readboj_timeout_error`.
#' @return An ungrouped base `data.frame` (`stringsAsFactors = FALSE`) with
#'   row names reset and one row per returned observation. The columns are in
#'   this exact order and have these types: `db`, `series_code`, `name_en`,
#'   `name_jp`, `unit_en`, `unit_jp`, `frequency`, `category_en`, and
#'   `category_jp` are character; `last_update` is `Date`; `period` is the
#'   exact BOJ period code as character; `date` is `Date`; `value` is numeric;
#'   `raw_value` is the source value as character; and `value_status` is
#'   character. `date` is the first calendar date inferred from `frequency`
#'   and `period`, and can be `NA` when the source code cannot be mapped. JSON
#'   missing values have `value = NA`, `raw_value = NA`, and
#'   `value_status = "null"`; CSV blank values have `value = NA`, the original
#'   empty `raw_value`, and `value_status = "blank"`. The returned object has
#'   a `readboj_provenance` attribute; [boj_provenance()] returns its list of
#'   source URL(s), retrieval/cache identity, hashes, response metadata,
#'   query, page list, parser schema and package version.
#'
#' @section Errors and side effects:
#' Invalid arguments, malformed responses, schema changes, pagination loops,
#' duplicate identities and size limits raise typed `readboj_*_error`
#' conditions. API and HTTP failures retain response identity in the error
#' where available. The function may perform network I/O and create or update
#' files below `cache_dir`; it does not write to the current working directory
#' or a global workspace. The default managed cache is in the user-specific
#' location returned by `tools::R_user_dir()`.
#'
#' @examples
#' # The packaged response is a small synthetic fixture and is read offline.
#' json_path <- system.file("extdata", "api-data-page-1.json", package = "readboj")
#' local_data <- read_boj_snapshot(json_path, type = "data_json", db = "FM08")
#' local_data[c("series_code", "period", "value", "value_status")]
#'
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   read_boj_series(
#'     db = "FM08", code = "FXERM07",
#'     start_date = "202601", end_date = "202606",
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
#'     max_pages = 2L, max_cells = 1000L, max_codes_total = 1L
#'   )
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
#' }
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

#' Read Bank of Japan observations for a hierarchy layer
#'
#' Fetches the observations selected by the official BOJ Time-Series Data
#' Search `getDataLayer` route. A layer is one to five hierarchy values, with
#' `*` selecting all values at a level. Every `NEXTPOSITION` cursor is followed
#' and the returned observations use the same schema as [read_boj_series()].
#' Use [read_boj_series()] when the desired series codes are already known.
#'
#' @details
#' `frequency` is normalized to uppercase and must be one of `CY`, `FY`, `CH`,
#' `FH`, `Q`, `M`, `W`, or `D`; `layer` values are non-negative integers or
#' `*`. A numeric `layer` vector is joined with commas before validation. The
#' request is bounded by `max_pages` and `max_cells`, then fails with
#' `readboj_size_error` if more than `max_series` distinct series are returned;
#' it is not silently truncated. Network, HTTPS-host, cache, offline and
#' deadline behavior is the same as [read_boj_series()].
#'
#' @param db A BOJ database identifier, such as `"FM08"`; it is normalized to
#'   uppercase and may still be rejected by the API if unknown.
#' @param frequency Observation frequency code: `"CY"`, `"FY"`, `"CH"`,
#'   `"FH"`, `"Q"`, `"M"`, `"W"`, or `"D"`. Matching is case-insensitive.
#' @param layer One to five comma-separated non-negative integer hierarchy
#'   values, or `*` as a wildcard at a level. A numeric vector is collapsed
#'   with commas; an empty value, more than five values, or any other character
#'   raises `readboj_parameter_error`.
#' @param start_date Optional inclusive `YYYY` or `YYYYPP` period bound; `NULL`
#'   omits it from the request.
#' @param end_date Optional inclusive `YYYY` or `YYYYPP` period bound; `NULL`
#'   omits it. If both bounds are supplied, `start_date` must not be later.
#' @param language Response language, exactly `"en"` or `"jp"`.
#' @param format Response format, `"json"` or `"csv"`; matching is
#'   case-insensitive.
#' @param cache_dir Character path to the content-addressed response cache;
#'   see [read_boj_series()] and `boj_cache_dir()`.
#' @param refresh Logical flag to bypass a current request snapshot.
#' @param offline Logical flag requiring a valid cached snapshot and disabling
#'   network access.
#' @param max_age Non-negative cache age in seconds, or `Inf`; the default is
#'   24 hours.
#' @param timeout Non-negative per-attempt HTTP timeout in seconds; the default
#'   is 30 seconds.
#' @param retries Non-negative whole-number transient-failure retry count; the
#'   default is 3.
#' @param wait Non-negative seconds between pages and retries; skipped offline.
#' @param max_bytes Positive decompressed response-byte bound per page; the
#'   default is 128 MiB.
#' @param max_pages Positive whole-number page bound for this layer request;
#'   the default is 100.
#' @param max_cells Positive whole-number observation-row bound across all
#'   pages; the default is 1,000,000.
#' @param max_series Positive whole-number maximum distinct series allowed in
#'   the result; the default is 1,250.
#' @param deadline Optional absolute one-element `POSIXct`/`POSIXlt` deadline
#'   shared by all requests, retries and delays. A bounded default is created
#'   when omitted.
#' @return An ungrouped base `data.frame` with row names reset and the same
#'   exact observation columns and types as [read_boj_series()]: character
#'   `db`, `series_code`, `name_en`, `name_jp`, `unit_en`, `unit_jp`,
#'   `frequency`, `category_en`, `category_jp`, and `period`; `Date`
#'   `last_update` and `date`; numeric `value`; and character `raw_value` and
#'   `value_status`, in that column order. A `readboj_provenance` attribute
#'   records the layer query, page identities, hashes, cache status, parser
#'   schema and package version. No duplicate observation identity is
#'   collapsed.
#'
#' @section Errors and side effects:
#' Invalid parameters, malformed or changed BOJ responses, pagination loops,
#' duplicate identities, result bounds, transport failures and unavailable
#' offline snapshots raise typed `readboj_*_error` conditions. The function
#' may access the network and write only successful response snapshots below
#' `cache_dir`; it does not intentionally issue warnings.
#'
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   read_boj_layer(
#'     db = "IR01", frequency = "D", layer = "*",
#'     start_date = "202607", end_date = "202607", format = "csv",
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
#'     max_pages = 2L, max_cells = 1000L, max_series = 100L
#'   )
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
#' }
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
