#' List official Bank of Japan bulk files
#'
#' Scrapes the current official flat-file catalogue and retains its exact HTML
#' response identity. The catalogue is selected coverage, not all 50 API
#' databases and not a general historical-vintage service.
#'
#' @param language Catalogue language, `"en"` or `"jp"`.
#' @inheritParams read_boj_series
#' @return A data frame of official downloadable ZIP/CSV links.
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
#' @param id A catalogue file name such as `"co.zip"`, or an exact official URL.
#' @inheritParams list_boj_bulk_files
#' @param max_bytes Maximum downloaded bytes.
#' @return A `boj_file` path whose provenance contains the exact SHA-256.
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
#' Headerless Flow-of-Funds/Tankan long files and named wide CSV matrices are
#' both accepted. Archive traversal, entry count, uncompressed size and row
#' count are bounded.
#'
#' @param path Local ZIP/CSV path or `boj_file` returned by [download_boj_bulk()].
#' @param encoding CSV encoding.
#' @param max_entries Maximum ZIP entries.
#' @param max_uncompressed_bytes Maximum total uncompressed bytes.
#' @param max_member_bytes Maximum uncompressed bytes for one archive member.
#' @param max_rows Maximum rows per CSV.
#' @return A data frame for one CSV, otherwise a named list of data frames.
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
