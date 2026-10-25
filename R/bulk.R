#' List the current Bank of Japan bulk-file catalogue
#'
#' Retrieves the official flat-file catalogue for the English or Japanese
#' Bank of Japan (BOJ) statistics site and extracts links ending in `.zip`,
#' `.csv`, `.xls`, or `.xlsx`. The catalogue is a selected bulk-download
#' route; it is not a complete listing of the 50 API databases and it does not
#' provide historical vintages of files that the BOJ no longer publishes.
#'
#' @param language Catalogue language: exactly `"en"` (English) or `"jp"`
#'   (Japanese). The returned `language` column uses the selected lower-case
#'   value.
#' @param cache_dir Directory used for content-addressed response snapshots.
#'   The default is `tools::R_user_dir("readboj", "cache")`; it is created
#'   when needed. Use a package-managed temporary directory in tests.
#' @param refresh Logical scalar. If `TRUE`, ignore an otherwise usable
#'   request snapshot and retrieve the catalogue again.
#' @param offline Logical scalar. If `TRUE`, make no network request and use a
#'   valid cached snapshot only; an absent or stale snapshot raises an
#'   `readboj_offline_error`.
#' @param max_age Non-negative cache age in seconds, or `Inf` for no age limit.
#'   The default is 24 hours.
#' @param timeout Non-negative per-request timeout in seconds. The default is
#'   30 seconds.
#' @param retries Non-negative integer number of retries for transient
#'   transport responses or errors. The default is `3L`.
#' @param wait Non-negative seconds between requests and retries. The default
#'   is one second; waiting is skipped for cached responses and offline reads.
#' @param max_bytes Positive maximum response size in bytes. The default is
#'   `8 * 1024^2` (8 MiB), and protects the HTML snapshot before parsing.
#' @param deadline Optional single absolute `POSIXct`/`POSIXlt` time shared by
#'   the request, retries, and waits. When omitted, a bounded deadline is
#'   derived from `timeout` and `retries`.
#'
#' @return A base `data.frame` with no row names and exactly these columns:
#'   `id`, `label`, `language`, `role`, and `url`. All columns are character;
#'   `id` is the final URL basename without a query or fragment, `label` is
#'   the link text, `language` repeats the selected catalogue language, `role`
#'   is `"metadata_catalogue"` for `PRList.xlsx`/`FOFList.xlsx` and
#'   `"data_archive"` otherwise, and `url` is the absolute link. The object
#'   has a `readboj_provenance()` attribute containing the canonical/final URL,
#'   retrieval time, HTTP status and headers, raw SHA-256, byte count, cache
#'   status/path, and parser/package schema metadata.
#'
#' @details The catalogue is fetched over HTTPS from the allowlisted
#'   `www.stat-search.boj.or.jp` host. Successful responses are retained in
#'   the bounded readboj cache; no response is cached when the request fails.
#'   The HTML parser keeps link labels and URLs as published and does not
#'   download the linked files.
#'
#' Invalid parameters, an expired offline snapshot, an unavailable source,
#' an HTTP/rate-limit/authentication failure, a changed HTML schema, or a
#' response exceeding `max_bytes` produces a typed readboj error. A source
#' catalogue change can therefore require caller review rather than silently
#' changing the interpretation of a link.
#'
#' @seealso [download_boj_bulk()], [read_boj_bulk()], [boj_provenance()]
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   catalogue <- list_boj_bulk_files("en", max_age = 3600,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'     deadline = Sys.time() + 30)
#'   head(catalogue[c("id", "role", "url")])
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
#' @export
list_boj_bulk_files <- function(language = "en", cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 30, retries = 3L, wait = 1, max_bytes = 8 * 1024^2,
    deadline = NULL) {
  language <- normalize_language(language, both = FALSE)
  deadline <- resolve_deadline(deadline, default_seconds = max(120, timeout * (retries + 1L) + 30))
  source <- if (language == "en") .readboj_bulk_en else .readboj_bulk_jp
  entry <- fetch_snapshot(source, cache_dir = cache_dir, refresh = refresh,
    offline = offline, max_age = max_age, timeout = timeout, retries = retries,
    wait = wait, max_bytes = max_bytes, deadline = deadline)
  links <- html_links(entry$path, source)
  links <- links[grepl("\\.(zip|csv|xlsx?)([?#].*)?$", links$url, ignore.case = TRUE), , drop = FALSE]
  links$id <- basename(sub("[?#].*$", "", links$url))
  links$language <- language
  links$role <- ifelse(tolower(links$id) %in% c("prlist.xlsx", "foflist.xlsx"),
    "metadata_catalogue", "data_archive")
  links <- links[c("id", "label", "language", "role", "url")]
  rownames(links) <- NULL
  attach_provenance(links, c(snapshot_provenance(entry), list(
    source = "Bank of Japan flat/bulk download catalogue", language = language)))
}

#' Download an official Bank of Japan bulk file
#'
#' Resolves a current catalogue file name or validates an exact official
#' `https://www.stat-search.boj.or.jp/` URL, then stores the response as a
#' content-addressed cache object. This function downloads bytes but does not
#' unpack or parse them; pass the result to [read_boj_bulk()] when it is a ZIP
#' or CSV that should be inspected.
#'
#' @param id A non-empty catalogue `id` such as `"co.zip"`, or an exact HTTPS
#'   URL on the official `www.stat-search.boj.or.jp` host. A file name is
#'   looked up in the current catalogue; an exact URL bypasses catalogue
#'   lookup and is checked against the host allowlist.
#' @param language Catalogue language, one of `"en"` or `"jp"`, used when
#'   `id` is a file name. It is not used to rewrite an exact URL.
#' @inheritParams list_boj_bulk_files
#' @param timeout Non-negative per-request timeout in seconds. The default for
#'   this file download is 60 seconds.
#' @param max_bytes Positive maximum downloaded response bytes. The default is
#'   `512 * 1024^2` (512 MiB); this limit is applied before the response is
#'   placed in the cache.
#'
#' @return A length-one character vector with classes `c("boj_file",
#'   "character")`. Its value is a regular local cache-object path. The
#'   `readboj_provenance()` attribute contains the canonical and final URLs,
#'   retrieval time, HTTP status and headers, byte count, and immutable raw
#'   SHA-256 hash, together with cache and package/schema metadata.
#'
#' @details The request uses HTTPS, follows only HTTPS redirects, and is
#'   restricted to the official BOJ bulk host. Successful responses are kept
#'   under `cache_dir` and subject to the package cache bounds; temporary
#'   response files are removed after caching or failure. `offline = TRUE`
#'   permits a valid cached response but never downloads a missing or stale
#'   file. Downloading a mutable latest bulk file does not identify a historical
#'   release beyond the response hash and recorded HTTP metadata.
#'
#' Invalid file names, non-official URLs, cache corruption, rate limits,
#' authorization failures, transport errors, expired offline snapshots, or a
#' response above `max_bytes` produce a typed readboj error. A catalogue lookup
#' can also fail when the requested `id` is not unique in the current page.
#'
#' @seealso [list_boj_bulk_files()], [read_boj_bulk()], [boj_provenance()]
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   catalogue <- list_boj_bulk_files("en", max_age = 3600,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'     deadline = Sys.time() + 30)
#'   ids <- catalogue$id[catalogue$role == "data_archive"]
#'   if (length(ids)) {
#'     archive <- download_boj_bulk(ids[[1L]],
#'       cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'       max_age = 3600, timeout = 10, retries = 0L, wait = 0,
#'       max_bytes = 64 * 1024^2, deadline = Sys.time() + 45)
#'     print(archive)
#'   }
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
#' @export
download_boj_bulk <- function(id, language = "en", cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 60, retries = 3L, wait = 1, max_bytes = 512 * 1024^2,
    deadline = NULL) {
  id <- scalar_character(id, "id")
  deadline <- resolve_deadline(deadline, default_seconds = max(600, timeout * (retries + 1L) + 60))
  if (grepl("^https://", id)) {
    url <- id
    if (!grepl("^https://www\\.stat-search\\.boj\\.or\\.jp/", url)) {
      readboj_abort("Bulk URL must be on the official stat-search.boj.or.jp host.",
        "readboj_parameter_error")
    }
  } else {
    catalogue <- list_boj_bulk_files(language, cache_dir, refresh = FALSE,
      offline = offline, max_age = max_age, timeout = timeout, retries = retries,
      wait = wait, deadline = deadline)
    match <- which(catalogue$id == id)
    if (length(match) != 1L) readboj_abort(sprintf("Bulk file `%s` is not uniquely present in the current catalogue.", id),
      "readboj_parameter_error")
    url <- catalogue$url[[match]]
  }
  download_snapshot(url, cache_dir, refresh, offline, max_age, timeout, retries,
    wait, max_bytes, deadline)
}

safe_zip_entries <- function(path, max_entries, max_uncompressed_bytes,
    max_member_bytes) {
  info <- utils::unzip(path, list = TRUE)
  if (nrow(info) > max_entries) readboj_abort("ZIP entry count exceeds the safety bound.",
    "readboj_archive_error", entry_limit = max_entries)
  names <- gsub("\\\\", "/", info$Name)
  unsafe <- startsWith(names, "/") | grepl("(^|/)\\.\\.(/|$)", names) |
    grepl("^[A-Za-z]:", names)
  if (any(unsafe)) readboj_abort("ZIP contains an unsafe path.", "readboj_archive_error")
  total <- sum(info$Length, na.rm = TRUE)
  if (total > max_uncompressed_bytes) readboj_abort("ZIP uncompressed size exceeds the safety bound.",
    "readboj_archive_error", uncompressed_bytes = total,
    uncompressed_limit = max_uncompressed_bytes)
  if (any(info$Length > max_member_bytes, na.rm = TRUE)) readboj_abort(
    "ZIP member size exceeds the safety bound.", "readboj_archive_error",
    member_limit = max_member_bytes)
  info
}

read_bulk_csv <- function(path, encoding, max_rows) {
  first <- readLines(path, n = 1L, warn = FALSE, encoding = encoding)
  fields <- if (length(first)) strsplit(first, ",", fixed = TRUE)[[1L]] else character()
  known_header <- any(toupper(gsub('^"|"$', "", fields)) %in%
    c("SERIES_CODE", "FREQUENCY", "TIME", "PERIOD", "DATE"))
  result <- if (!known_header && length(fields) == 4L) {
    readr::read_csv(path, col_names = c("series_code", "frequency", "period", "value"),
      locale = readr::locale(encoding = encoding),
      col_types = readr::cols(.default = readr::col_character()),
      na = character(), n_max = max_rows + 1L, progress = FALSE,
      show_col_types = FALSE)
  } else {
    readr::read_csv(path, locale = readr::locale(encoding = encoding),
      col_types = readr::cols(.default = readr::col_character()),
      na = character(), n_max = max_rows + 1L, progress = FALSE,
      show_col_types = FALSE)
  }
  if (nrow(result) > max_rows) readboj_abort("Bulk CSV row count exceeds the safety bound.",
    "readboj_size_error", row_limit = max_rows)
  result <- as.data.frame(result, stringsAsFactors = FALSE)
  if (all(c("series_code", "frequency", "period", "value") %in% names(result))) {
    result$value_numeric <- suppressWarnings(as.numeric(result$value))
    result$value_status <- ifelse(result$value %in% c("", "NA", "ND"),
      result$value, "observed")
  }
  result
}

#' Read a downloaded official Bank of Japan bulk ZIP or CSV
#'
#' Parses a local bulk response or a `boj_file` from
#' [download_boj_bulk()]. Headerless four-column Flow-of-Funds/Tankan long
#' files and named wide CSV matrices are accepted. ZIP traversal, entry count,
#' uncompressed size, individual member size, and CSV row count are bounded
#' before the result is retained in memory.
#'
#' @param path A local regular ZIP/CSV path, or the length-one `boj_file`
#'   returned by [download_boj_bulk()]. The file is read as bytes to detect a
#'   ZIP signature; its filename extension is not trusted.
#' @param encoding Character encoding passed to `readr::read_csv()` for CSV
#'   text, such as `"UTF-8"` or `"CP932"`. It must name an encoding supported
#'   by the local R installation.
#' @param max_entries Positive integer maximum number of ZIP members. The
#'   default is `1000L`.
#' @param max_uncompressed_bytes Positive maximum total uncompressed ZIP
#'   member bytes. The default is `1024^3` (1 GiB).
#' @param max_member_bytes Positive maximum uncompressed bytes for one ZIP
#'   member. The default is `512 * 1024^2` (512 MiB).
#' @param max_rows Positive integer maximum rows retained from each CSV. The
#'   default is `2000000L`; one extra row is read to detect an over-limit file.
#'
#' @return For a CSV, a base `data.frame` whose columns are the parsed CSV
#'   columns and whose values are read as character. A headerless four-column
#'   file is named `series_code`, `frequency`, `period`, and `value`, then gets
#'   `value_numeric` (numeric conversion, with non-numeric values as `NA`) and
#'   `value_status` (the original `""`, `"NA"`, or `"ND"` marker, otherwise
#'   `"observed"`). For a ZIP containing one CSV, the same data frame is
#'   returned with a `source_file` column. For a ZIP containing multiple CSVs,
#'   a named list of those data frames is returned with classes
#'   `c("boj_bulk", "list")`; names are the archive member paths and each
#'   table has its `source_file`. Every result has a `readboj_provenance()`
#'   attribute with the source hash/bytes, parser name and schema, encoding,
#'   and, for ZIPs, selected member names and total uncompressed bytes.
#'
#' @details This is an offline local parser: it makes no network request and
#' does not update the readboj cache. ZIP members must be regular safe paths;
#' absolute paths, drive-letter paths, and `..` traversal are rejected. Only
#' `.csv` members are extracted, into a temporary directory removed on exit;
#' non-CSV ZIP members are ignored. The parser preserves text identifiers,
#' labels, units, and suppression markers rather than guessing numeric types.
#'
#' Missing or non-regular paths, unsupported parameters, unsafe archive paths,
#' absent CSV members, and configured size/row bounds are checked by the
#' package and produce typed readboj errors where applicable. Low-level
#' malformed ZIP/CSV input or unsupported encoding may instead retain a base-R
#' or dependency error or warning. A ZIP with no CSV members is rejected. This
#' function does not infer a common schema across files or reconcile
#' publication revisions.
#'
#' @seealso [download_boj_bulk()], [read_boj_workbook()], [boj_provenance()]
#' @examples
#' local({
#'   csv <- tempfile(fileext = ".csv")
#'   on.exit(unlink(csv), add = TRUE)
#'   writeLines(c(
#'     "series_code,frequency,period,value",
#'     "SYNTHM01,MONTHLY,202601,101.5",
#'     "SYNTHM01,MONTHLY,202602,NA"
#'   ), csv)
#'   parsed <- read_boj_bulk(csv, max_rows = 10L)
#'   parsed[c("series_code", "period", "value_numeric", "value_status")]
#' })
#' @export
read_boj_bulk <- function(path, encoding = "UTF-8", max_entries = 1000L,
    max_uncompressed_bytes = 1024^3, max_member_bytes = 512 * 1024^2,
    max_rows = 2000000L) {
  provenance <- boj_provenance(path)
  path <- scalar_character(as.character(path), "path")
  if (!file.exists(path) || dir.exists(path)) readboj_abort("`path` is not a regular file.",
    "readboj_parameter_error")
  max_entries <- scalar_number(max_entries, "max_entries", min = 1, integer = TRUE)
  max_uncompressed_bytes <- scalar_number(max_uncompressed_bytes,
    "max_uncompressed_bytes", min = 1)
  max_member_bytes <- scalar_number(max_member_bytes, "max_member_bytes", min = 1)
  max_rows <- scalar_number(max_rows, "max_rows", min = 1, integer = TRUE)
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  signature <- readBin(connection, what = "raw", n = 4L)
  close(connection)
  on.exit(NULL, add = FALSE)
  is_zip <- length(signature) >= 2L && identical(as.integer(signature[1:2]), c(80L, 75L))
  if (!is_zip) {
    out <- read_bulk_csv(path, encoding, max_rows)
    source_provenance <- provenance %||% list(raw_sha256 = sha256_file(path),
      bytes = file.info(path)$size, source = "local BOJ bulk CSV")
    return(attach_provenance(out, c(source_provenance, list(
      parser = "read_boj_bulk/csv", parser_schema = .readboj_schema_version,
      encoding = encoding, rows = nrow(out)))))
  }
  info <- safe_zip_entries(path, max_entries, max_uncompressed_bytes, max_member_bytes)
  csv <- info$Name[grepl("\\.csv$", info$Name, ignore.case = TRUE)]
  if (!length(csv)) readboj_abort("ZIP contains no CSV files.", "readboj_archive_error")
  directory <- tempfile("readboj-unzip-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  utils::unzip(path, files = csv, exdir = directory, junkpaths = FALSE)
  out <- lapply(file.path(directory, csv), read_bulk_csv, encoding = encoding,
    max_rows = max_rows)
  names(out) <- csv
  for (i in seq_along(out)) out[[i]]$source_file <- csv[[i]]
  result <- if (length(out) == 1L) out[[1L]] else structure(out, class = c("boj_bulk", "list"))
  source_provenance <- provenance %||% list(raw_sha256 = sha256_file(path),
    bytes = file.info(path)$size, source = "local BOJ bulk ZIP")
  attach_provenance(result, c(source_provenance, list(
    parser = "read_boj_bulk/zip_csv", parser_schema = .readboj_schema_version,
    encoding = encoding, archive_members = csv,
    uncompressed_bytes = sum(info$Length, na.rm = TRUE))))
}
