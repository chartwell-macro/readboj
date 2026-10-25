metadata_snapshot <- function(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline) {
  api_lang <- if (language == "en") "en" else "jp"
  entry <- fetch_snapshot(paste0(.readboj_api_base, "/getMetadata"),
    list(format = "csv", lang = api_lang, db = db), cache_dir = cache_dir,
    refresh = refresh, offline = offline, max_age = max_age,
    timeout = timeout, retries = retries, wait = wait, max_bytes = max_bytes,
    deadline = deadline)
  encoding <- if (api_lang == "jp") "CP932" else "UTF-8"
  decoded <- decode_complete_line_prefix(entry$path, encoding, 16384L)
  if (length(decoded) != 1L || is.na(decoded)) readboj_abort(
    sprintf("BOJ metadata is not valid %s text.", encoding), "readboj_schema_error")
  preamble <- strsplit(decoded, "\n", fixed = TRUE)[[1L]]
  preamble <- sub("\r$", "", utils::head(preamble, 5L))
  if (length(preamble) != 5L) readboj_abort(
    "BOJ metadata CSV has fewer than five preamble rows.", "readboj_schema_error")
  split <- strsplit(preamble, ",", fixed = TRUE)
  preamble_names <- vapply(split, function(x) x[[1L]] %||% "", character(1L))
  preamble_values <- vapply(split, function(x) paste(x[-1L], collapse = ","), character(1L))
  preamble <- stats::setNames(preamble_values, preamble_names)
  if (!all(c("STATUS", "MESSAGEID", "DATE") %in% names(preamble))) {
    readboj_abort("BOJ metadata CSV preamble is incomplete.", "readboj_schema_error")
  }
  if (!identical(unname(preamble[["STATUS"]]), "200")) {
    readboj_abort(sprintf("BOJ API error %s (%s).", preamble[["STATUS"]],
      preamble[["MESSAGEID"]]), "readboj_api_error",
      status = suppressWarnings(as.integer(preamble[["STATUS"]])),
      message_id = preamble[["MESSAGEID"]])
  }
  list(entry = entry, encoding = encoding, preamble = preamble)
}

filter_metadata_language <- function(data, language) {
  if (language == "both") return(data)
  if (language == "en") {
    data$name_jp <- data$unit_jp <- data$category_jp <- data$notes_jp <- NULL
  } else {
    data$name_en <- data$unit_en <- data$category_en <- data$notes_en <- NULL
  }
  data
}

#' Retrieve Bank of Japan series metadata
#'
#' Retrieves and parses the official BOJ `getMetadata` CSV for one database.
#' The Japanese metadata route is the canonical bilingual source: it carries
#' both Japanese (`*_J`) and English fields. Use [search_boj_series()] for
#' bounded discovery in a large catalogue, especially the Tankan `CO`
#' database, rather than eagerly materialising that database by default.
#'
#' @details
#' `language = "both"` and `language = "jp"` request the Japanese CSV (CP932)
#' so that paired fields are available; `language = "en"` requests the English
#' CSV (UTF-8) and removes Japanese columns from the result. Metadata is read in
#' source order. With `include_groups = TRUE`, hierarchy heading rows without a
#' series code are retained and have `is_series = FALSE`; setting it to `FALSE`
#' retains only rows with a non-empty series code.
#'
#' A `CO` request is rejected before downloading unless `allow_large = TRUE`.
#' That opt-in does not remove the independent `max_rows` materialisation
#' bound. Responses are fetched over HTTPS from the official BOJ host and
#' successfully cached as content-addressed snapshots. A current snapshot is
#' reused unless `refresh = TRUE`; `offline = TRUE` requires a valid matching
#' snapshot and makes no network request. See [read_boj_series()] for the
#' common cache, retry, timeout, and deadline controls.
#'
#' @inheritParams read_boj_series
#' @param language Output language: `"both"`, `"en"`, or `"jp"`. `"both"`
#'   retains paired Japanese and English text fields; `"en"` and `"jp"`
#'   retain only the requested language's name, unit, category and notes.
#' @param timeout Non-negative per-request timeout in seconds. The default for
#'   metadata requests is 60 seconds.
#' @param max_rows Positive whole-number maximum metadata rows materialised,
#'   including hierarchy groups before `include_groups` filtering. The default
#'   is 50,000; exceeding it raises `readboj_size_error`.
#' @param allow_large Logical flag. `TRUE` explicitly permits eager `CO`
#'   (Tankan) materialisation, subject to `max_rows`, byte, timeout and
#'   deadline bounds. The default is `FALSE`.
#' @param include_groups Logical flag. `TRUE` (the default) keeps hierarchy
#'   heading rows, which have an empty `series_code` and `is_series = FALSE`;
#'   `FALSE` filters them out after parsing.
#' @param deadline An optional absolute `POSIXct`/`POSIXlt` deadline shared by
#'   the metadata request, retries and delays. A bounded default is created
#'   when omitted.
#' @return A base `data.frame` in BOJ source order, with row names reset,
#'   `stringsAsFactors = FALSE`, and a `readboj_provenance` attribute. For
#'   `language = "both"`, columns are in this exact order: `db`,
#'   `series_code`, `name_jp`, `name_en`, `unit_jp`, `unit_en`, `frequency`,
#'   `category_jp`, `category_en`, `layer1`, `layer2`, `layer3`, `layer4`,
#'   `layer5`, `start_time`, `end_time`, `last_update`, `notes_jp`, `notes_en`,
#'   and `is_series`. The first two columns and all text fields are character;
#'   `layer1`--`layer5` are integer; `last_update` is `Date`; and `is_series`
#'   is logical. For `language = "en"`, the Japanese name, unit, category and
#'   notes columns are removed; for `language = "jp"`, the English counterparts
#'   are removed. Thus the retained language fields preserve the corresponding
#'   column order from the bilingual schema. `start_time` and `end_time` are
#'   source period labels as character. Provenance records the canonical and
#'   final URLs, raw hash, retrieval/cache identity, transfer encoding, BOJ
#'   date/message ID, selected database and language, parser schema and package
#'   version.
#'
#' @section Errors and side effects:
#' Invalid parameters, an unavailable large database, malformed or changed
#' CSV schema, API errors, row limits, transport failures and missing offline
#' snapshots raise typed `readboj_*_error` conditions. The function may perform
#' network I/O and create cache files below `cache_dir`; temporary files are
#' cleaned up and no package startup download occurs.
#'
#' @examples
#' # This small installed fixture is synthetic and makes no network request.
#' metadata_path <- system.file(
#'   "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
#' )
#' metadata <- read_boj_snapshot(
#'   metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
#' )
#' metadata[c("series_code", "name_en", "name_jp", "is_series")]
#'
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   boj_metadata(
#'     "FM08", language = "both", include_groups = FALSE,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
#'     max_rows = 100L
#'   )
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
#' }
#' @export
boj_metadata <- function(db, language = "both", cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 60, retries = 3L, wait = 1, max_bytes = 128 * 1024^2,
    max_rows = 50000L, allow_large = FALSE, include_groups = TRUE,
    deadline = NULL) {
  db <- normalize_db(db)
  language <- normalize_language(language)
  allow_large <- scalar_flag(allow_large, "allow_large")
  include_groups <- scalar_flag(include_groups, "include_groups")
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  if (identical(db, "CO") && !allow_large) readboj_abort(
    "The Tankan metadata catalogue is large; use `search_boj_series()` or set `allow_large = TRUE` with an explicit row bound.",
    "readboj_size_error", db = db)
  snapshot <- metadata_snapshot(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline)
  out <- parse_metadata_csv(snapshot$entry$path, db, snapshot$encoding, max_rows)
  if (!include_groups) out <- out[out$is_series, , drop = FALSE]
  out <- filter_metadata_language(out, language)
  attach_provenance(out, c(snapshot_provenance(snapshot$entry), list(
    source = "Bank of Japan getMetadata CSV", db = db, language = language,
    transfer_encoding = snapshot$encoding, api_date = unname(snapshot$preamble[["DATE"]]),
    api_message_id = unname(snapshot$preamble[["MESSAGEID"]]))))
}

search_chunked_metadata <- function(path, db, encoding, query, regex, limit,
    include_groups, language) {
  state <- new.env(parent = emptyenv())
  state$matches <- list()
  state$count <- 0L
  callback <- readr::SideEffectChunkCallback$new(function(chunk, pos) {
    normalized <- standardize_metadata(as.data.frame(chunk), db)
    if (!include_groups) normalized <- normalized[normalized$is_series, , drop = FALSE]
    fields <- if (language == "en") c("series_code", "name_en", "category_en", "notes_en") else
      if (language == "jp") c("series_code", "name_jp", "category_jp", "notes_jp") else
        c("series_code", "name_en", "name_jp", "category_en", "category_jp", "notes_en", "notes_jp")
    haystack <- do.call(paste, c(lapply(normalized[fields], function(x) ifelse(is.na(x), "", x)), sep = "\r"))
    keep <- if (regex) grepl(query, haystack, ignore.case = TRUE, perl = TRUE) else
      grepl(tolower(query), tolower(haystack), fixed = TRUE)
    selected <- normalized[keep, , drop = FALSE]
    if (nrow(selected)) {
      available <- limit - state$count
      if (available > 0L) {
        selected <- utils::head(selected, available)
        state$matches[[length(state$matches) + 1L]] <- selected
        state$count <- state$count + nrow(selected)
      }
    }
    invisible(NULL)
  })
  readr::read_csv_chunked(path, callback = callback, chunk_size = 5000L, skip = 5L,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), progress = FALSE, show_col_types = FALSE)
  if (!length(state$matches)) return(empty_metadata())
  out <- do.call(rbind, state$matches)
  rownames(out) <- NULL
  out
}

#' Search Bank of Japan metadata with bounded output
#'
#' Searches the official BOJ metadata CSV for text in the selected name,
#' category, notes and series-code fields. The cached file is scanned in
#' chunks, so even the large Tankan catalogue is not materialised as one
#' in-memory object. At most `limit` matching rows are retained. Use
#' [boj_metadata()] when the complete bounded metadata table is required.
#'
#' @details
#' Literal searches are case-insensitive and use fixed matching. With
#' `regex = TRUE`, `query` is interpreted as a Perl-compatible regular
#' expression and matching remains case-insensitive. In `language = "en"` or
#' `"jp"`, only fields in that language plus `series_code` are searched; with
#' `language = "both"`, both language versions are searched. Group headings
#' are excluded by default and can be included with `include_groups = TRUE`.
#' Rows are retained in source order until `limit` is reached; no result rows
#' are deduplicated.
#'
#' The metadata response is fetched over HTTPS and cached using the same
#' content-addressed snapshot, offline, retry, timeout, and absolute-deadline
#' rules as [boj_metadata()]. `CO` remains subject to the same large-catalogue
#' guard only when using [boj_metadata()]; this chunked search is the intended
#' bounded discovery path.
#'
#' @param query One non-empty character string. It is matched against the
#'   series code and the selected language's name, category and notes fields.
#' @param regex Logical flag. If `FALSE` (the default), `query` is literal and
#'   fixed; if `TRUE`, it is a case-insensitive Perl-compatible regular
#'   expression. Invalid expressions raise `readboj_parameter_error` before
#'   downloading the metadata.
#' @param limit Positive whole-number maximum matching rows retained and
#'   returned. The default is 100; it is a bound, not a request to materialise
#'   the full source catalogue.
#' @inheritParams boj_metadata
#' @param include_groups Logical scalar. `TRUE` retains hierarchy heading rows
#'   without a series code; `FALSE` (the default) excludes them.
#' @param deadline An optional absolute `POSIXct`/`POSIXlt` deadline shared by
#'   the metadata download, retries and delays. A bounded default is created
#'   when omitted.
#' @return A base `data.frame` in source order, with at most `limit` rows,
#'   row names reset, `stringsAsFactors = FALSE`, and a
#'   `readboj_provenance` attribute. Its columns and types are the same as
#'   [boj_metadata()] after `language` filtering: `db`, `series_code`, the
#'   retained language name/unit/category/notes fields, `frequency`, integer
#'   `layer1`--`layer5`, character `start_time`/`end_time`, `Date`
#'   `last_update`, and logical `is_series`. Empty results retain the
#'   corresponding zero-row schema. Provenance additionally records `query`,
#'   `result_limit`, `scan = "chunked"`, source/cache identity, transfer
#'   encoding, BOJ date/message ID, parser schema and package version.
#'
#' @section Errors and side effects:
#' Invalid arguments, invalid regular expressions, malformed or changed CSV
#' schemas, row limits, API/transport failures and unavailable offline
#' snapshots raise typed `readboj_*_error` conditions. The function may access
#' the network and create cache files below `cache_dir`; it does not write
#' search results to the working directory.
#'
#' @examples
#' # The fixture shows the same bilingual schema without network access.
#' metadata_path <- system.file(
#'   "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
#' )
#' metadata <- read_boj_snapshot(
#'   metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
#' )
#' metadata[grepl("monthly", metadata$name_en, fixed = TRUE),
#'   c("series_code", "name_en", "is_series")]
#'
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   search_boj_series(
#'     "exchange", db = "FM08", language = "en", limit = 10L,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2
#'   )
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
#' }
#' @export
search_boj_series <- function(query, db, language = "both", regex = FALSE,
    limit = 100L, cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 60, retries = 3L, wait = 1,
    max_bytes = 128 * 1024^2, include_groups = FALSE, deadline = NULL) {
  query <- scalar_character(query, "query")
  db <- normalize_db(db)
  language <- normalize_language(language)
  regex <- scalar_flag(regex, "regex")
  limit <- scalar_number(limit, "limit", min = 1, integer = TRUE)
  include_groups <- scalar_flag(include_groups, "include_groups")
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  if (regex) tryCatch(grepl(query, "", perl = TRUE), error = function(e)
    readboj_abort(paste0("Invalid regular expression: ", conditionMessage(e)),
      "readboj_parameter_error"))
  snapshot <- metadata_snapshot(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline)
  out <- search_chunked_metadata(snapshot$entry$path, db, snapshot$encoding, query,
    regex, limit, include_groups, language)
  out <- filter_metadata_language(out, language)
  attach_provenance(out, c(snapshot_provenance(snapshot$entry), list(
    source = "Bank of Japan getMetadata CSV", db = db, language = language,
    query = query, result_limit = limit, scan = "chunked", transfer_encoding = snapshot$encoding,
    api_date = unname(snapshot$preamble[["DATE"]]),
    api_message_id = unname(snapshot$preamble[["MESSAGEID"]]))))
}
