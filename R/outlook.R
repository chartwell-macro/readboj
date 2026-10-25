.readboj_outlook_index <- "https://www.boj.or.jp/en/mopo/outlook/index.htm"
.readboj_outlook_table <- "Forecasts of the Majority of the Policy Board Members"
.readboj_outlook_schema <- "outlook-semantic-v2"

outlook_space <- function(x) trimws(gsub("[[:space:]\u00a0]+", " ", x))

outlook_count <- function(x, name, maximum) {
  x <- scalar_number(x, name, min = 1)
  if (x != floor(x) || x > maximum) readboj_abort(
    sprintf("`%s` must be a whole number from 1 through %s.", name, maximum),
    "readboj_parameter_error")
  as.integer(x)
}

outlook_month <- function(x) {
  names <- c(month.name, month.abb, "Sept")
  values <- c(seq_len(12L), seq_len(12L), 9L)
  values[match(sub("\\.$", "", x), names)]
}

outlook_date <- function(x) {
  x <- outlook_space(x)
  m <- regmatches(x, regexec("^([A-Za-z]+)\\.? ([0-9]{1,2}), ([0-9]{4})$", x))[[1L]]
  if (length(m) != 4L || is.na(outlook_month(m[[2L]]))) readboj_abort(
    "Unrecognized Outlook publication date.", "readboj_schema_error", source_date = x)
  value <- tryCatch(suppressWarnings(as.Date(sprintf("%s-%02d-%02d", m[[4L]],
    outlook_month(m[[2L]]), as.integer(m[[3L]])))), error = function(e) as.Date(NA))
  if (is.na(value)) readboj_abort("Invalid Outlook publication date.",
    "readboj_schema_error", source_date = x)
  value
}

outlook_executable <- function(pdftotext) {
  if (!is.character(pdftotext) || length(pdftotext) != 1L || is.na(pdftotext)) {
    readboj_abort("`pdftotext` must be one executable path (or an empty string).",
      "readboj_parameter_error")
  }
  if (!nzchar(pdftotext) || !file.exists(pdftotext) || dir.exists(pdftotext) ||
      file.access(pdftotext, 1L) != 0L) readboj_abort(
    "Outlook PDF extraction requires the optional Poppler `pdftotext` executable; set `pdftotext` or option `readboj.pdftotext` to its provisioned path.",
    "readboj_dependency_error", dependency = "Poppler pdftotext")
  normalizePath(pdftotext, mustWork = TRUE)
}

run_outlook_pdf <- function(command, args, log, deadline) {
  seconds <- floor(deadline_remaining(deadline))
  if (seconds < 1) readboj_abort("Insufficient deadline for bounded PDF extraction.",
    "readboj_timeout_error", deadline = deadline)
  status <- tryCatch(suppressWarnings(system2(command, args = shQuote(args),
    stdout = log, stderr = log, timeout = seconds)), error = function(e) readboj_abort(
      "Could not execute Poppler pdftotext.", "readboj_dependency_error", parent = e))
  if (identical(as.integer(status), 124L)) readboj_abort(
    "PDF extraction exceeded the caller-owned absolute deadline.",
    "readboj_timeout_error", deadline = deadline)
  deadline_remaining(deadline)
  if (status != 0L) readboj_abort("Poppler could not extract this PDF.",
    "readboj_parse_error", exit_status = status)
  invisible(NULL)
}

extract_outlook_pdf <- function(path, command, max_pdf_pages, max_text_bytes, deadline) {
  directory <- tempfile("readboj-outlook-")
  if (!dir.create(directory)) readboj_abort("Could not create PDF extraction directory.",
    "readboj_parse_error")
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  log <- file.path(directory, "extract.log")
  run_outlook_pdf(command, "-v", log, deadline)
  version <- strsplit(rawToChar(read_raw_file(log, 4096L)), "\n", fixed = TRUE)[[1L]][[1L]]
  if (!grepl("^pdftotext version [0-9]+\\.[0-9]+", version)) readboj_abort(
    "The configured extractor is not recognized as Poppler pdftotext.",
    "readboj_dependency_error")
  text_path <- file.path(directory, "layout.txt")
  run_outlook_pdf(command, c("-q", "-layout", "-enc", "UTF-8", "-f", "1", "-l",
    as.character(max_pdf_pages), path, text_path), log, deadline)
  raw <- read_raw_file(text_path, max_text_bytes)
  text <- tryCatch(rawToChar(raw), error = function(e) readboj_abort(
    "Invalid PDF text output.", "readboj_parse_error", parent = e))
  if (!isTRUE(validUTF8(text))) readboj_abort("PDF text is not valid UTF-8.",
    "readboj_parse_error")
  pages <- strsplit(text, "\f", fixed = TRUE)[[1L]]
  if (!length(pages) || length(pages) > max_pdf_pages) readboj_abort(
    "Invalid or excessive extracted PDF page count.", "readboj_size_error")
  deadline_remaining(deadline)
  coordinate_path <- file.path(directory, "coordinates.xhtml")
  run_outlook_pdf(command, c("-q", "-bbox-layout", "-enc", "UTF-8", "-f", "1", "-l",
    as.character(max_pdf_pages), path, coordinate_path), log, deadline)
  coordinates <- outlook_pdf_coordinates(coordinate_path, max_text_bytes * 8)
  if (length(coordinates) != length(pages)) outlook_schema_error("PDF page/text geometry counts disagree.")
  list(pages = pages, coordinates = coordinates, extractor = version,
    coordinates_sha256 = sha256_file(coordinate_path), text_sha256 = digest::digest(
    raw, algo = "sha256", serialize = FALSE))
}

outlook_schema_error <- function(message, ...) readboj_abort(message,
  "readboj_schema_error", table_id = .readboj_outlook_table, ...)

outlook_read_html <- function(entry, max_bytes, deadline) {
  deadline_remaining(deadline)
  read_raw_file(entry$path, max_bytes)
  doc <- tryCatch(xml2::read_html(entry$path, encoding = "UTF-8"),
    error = function(e) readboj_abort("Could not parse official Outlook HTML.",
      "readboj_schema_error", parent = e))
  deadline_remaining(deadline)
  doc
}

parse_outlook_releases <- function(entry, max_bytes, max_releases, deadline) {
  doc <- outlook_read_html(entry, max_bytes, deadline)
  rows <- xml2::xml_find_all(doc, ".//table//tr[td]")
  assets <- list()
  for (row in rows) {
    deadline_remaining(deadline)
    cells <- xml2::xml_find_all(row, "./td")
    links <- xml2::xml_find_all(row, ".//a[@href]")
    if (length(cells) < 2L || !length(links)) next
    label <- outlook_space(xml2::xml_text(links[[1L]]))
    m <- regmatches(label, regexec("^([A-Za-z]+) ([0-9]{4})(.*)$", label))[[1L]]
    if (length(m) != 4L || is.na(outlook_month(m[[2L]]))) next
    year <- as.integer(m[[3L]])
    month <- outlook_month(m[[2L]])
    release <- sprintf("%04d-%02d", year, month)
    date <- outlook_date(xml2::xml_text(cells[[1L]]))
    if (!length(cells) %in% c(2L, 3L)) outlook_schema_error("Ambiguous archive row columns.")
    for (j in seq_along(links)) {
      url <- xml2::url_absolute(xml2::xml_attr(links[[j]], "href"), .readboj_outlook_index)
      validate_official_url(url)
      pattern <- sprintf("^https://www\\.boj\\.or\\.jp/en/mopo/outlook/(data/)?gor%02d%02d[a-z]?(_[0-9]+)?\\.(pdf|htm)$",
        year %% 100L, month)
      if (!grepl(pattern, url)) readboj_abort("Archive URL and Outlook edition label disagree.",
        "readboj_identity_error", url = url, label = label)
      kind <- if (grepl("(full text)", label, fixed = TRUE) || (length(cells) == 3L && j == 2L)) "full" else "view"
      assets[[length(assets) + 1L]] <- data.frame(release = release, kind = kind, url = url,
        date = if (kind == "full" && length(cells) == 3L) as.Date(NA) else date)
      if (length(assets) > max_releases * 2L) readboj_abort("Outlook archive exceeds `max_releases`.", "readboj_size_error")
    }
  }
  if (!length(assets)) outlook_schema_error("No official Outlook editions discovered.")
  assets <- do.call(rbind, assets)
  if (anyDuplicated(assets[c("release", "kind")])) readboj_abort(
    "Duplicate Outlook edition identity in archive.", "readboj_identity_error")
  views <- assets[assets$kind == "view", , drop = FALSE]
  full <- assets[assets$kind == "full", , drop = FALSE]
  if (any(!full$release %in% views$release)) readboj_abort(
    "Full text has no corresponding Bank's View edition.", "readboj_identity_error")
  if (nrow(views) > max_releases) readboj_abort("Outlook archive exceeds `max_releases`.", "readboj_size_error")
  j <- match(views$release, full$release)
  out <- data.frame(release = views$release, publication_date = views$date,
    banks_view_url = views$url, source_format = tools::file_ext(views$url),
    full_text_date = full$date[j], full_text_url = full$url[j])
  if (any(out$full_text_date < out$publication_date, na.rm = TRUE)) readboj_abort(
    "Full-text publication predates its Bank's View.", "readboj_identity_error")
  out <- out[order(out$publication_date, out$release, decreasing = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  provenance <- snapshot_provenance(entry)
  provenance$source <- "Bank of Japan complete English Outlook archive"
  provenance$parser_schema <- .readboj_outlook_schema
  attach_provenance(out, provenance)
}

#' Discover all official Outlook Report editions
#'
#' Reads both modern and legacy archive tables, including HTML Bank's Views and
#' legacy unlabeled full-text PDF links. One row is one official report edition;
#' the later full text is not a new forecast vintage. No dated admission list or
#' quarterly calendar is used. Pre-2016 interim assessments are separate monetary
#' policy statements and are not invented as report editions.
#'
#' @inheritParams list_boj_bulk_files
#' @param max_releases Maximum archive editions (1 through 1,000); excess fails
#'   instead of silently truncating discovery.
#' @return A data frame of edition month, Bank's View date/URL/format and full-text
#'   date/URL. A legacy full-text date not stated by the archive is `NA`.
#' @seealso [read_boj_outlook()]
#' @examples
#' \dontrun{
#' list_boj_outlook_releases_raw(cache_dir = tempfile("outlook-raw-"),
#'                               timeout = 10, retries = 0L,
#'                               deadline = Sys.time() + 30)
#' }
#' @export
list_boj_outlook_releases_raw <- function(cache_dir = boj_cache_dir(), refresh = FALSE,
    offline = FALSE, max_age = 24 * 60 * 60, timeout = 30, retries = 3L,
    wait = 1, max_bytes = 8 * 1024^2, max_releases = 200L, deadline = NULL) {
  max_releases <- outlook_count(max_releases, "max_releases", 1000L)
  deadline <- resolve_deadline(deadline)
  deadline_remaining(deadline)
  entry <- fetch_snapshot(.readboj_outlook_index, cache_dir = cache_dir,
    refresh = refresh, offline = offline, max_age = max_age, timeout = timeout,
    retries = retries, wait = wait, max_bytes = max_bytes, deadline = deadline)
  parse_outlook_releases(entry, max_bytes, max_releases, deadline)
}

outlook_pdf_identity <- function(extracted, publication, source_is_full) {
  text <- outlook_space(paste(utils::head(extracted$pages, 2L), collapse = " "))
  month <- month.name[[as.integer(substr(publication$release, 6L, 7L))]]
  year <- substr(publication$release, 1L, 4L)
  if (!grepl("Bank of Japan", text, fixed = TRUE) ||
      !grepl(paste(month, year), text, fixed = TRUE)) readboj_abort(
    "PDF does not identify the selected Outlook edition.", "readboj_identity_error")
  if (!source_is_full) {
    date <- publication$publication_date
    printed <- sprintf("%s %s, %s", month.name[[as.integer(format(date, "%m"))]],
      as.integer(format(date, "%d")), format(date, "%Y"))
    if (!grepl(printed, text, fixed = TRUE)) readboj_abort(
      "Bank's View date disagrees with archive identity.", "readboj_identity_error")
  }
  invisible(TRUE)
}

outlook_document_date <- function(pages) {
  for (page in utils::head(pages, 2L)) {
    text <- outlook_space(page)
    tokens <- regmatches(text, gregexpr(paste0("(", paste(month.name, collapse = "|"),
      ") +[0-9]{1,2}, +[0-9]{4}"), text))[[1L]]
    dates <- unique(vapply(tokens, function(token) as.character(outlook_date(token)), character(1L)))
    if (length(dates) == 1L) return(as.Date(dates))
    if (length(dates) > 1L) break
  }
  as.Date(NA)
}

outlook_html_identity <- function(document, publication) {
  main <- xml2::xml_find_first(document, ".//main")
  if (inherits(main, "xml_missing")) main <- xml2::xml_root(document)
  title <- outlook_space(xml2::xml_text(xml2::xml_find_first(main, ".//h1")))
  text <- outlook_space(xml2::xml_text(main))
  date <- publication$publication_date
  printed <- sprintf("%s %s, %s", month.name[[as.integer(format(date, "%m"))]],
    as.integer(format(date, "%d")), format(date, "%Y"))
  if (is.na(title) || !grepl("Outlook|Risk Assessment", title) ||
      !grepl(printed, text, fixed = TRUE)) readboj_abort(
    "HTML title/date does not identify the selected Outlook edition.", "readboj_identity_error")
  invisible(TRUE)
}

read_outlook_edition <- function(publication, fetch, command, max_bytes, max_pdf_pages,
    max_text_bytes, expected_sha256, deadline) {
  primary <- fetch(publication$banks_view_url[[1L]])
  entry <- primary
  source_is_full <- FALSE
  extracted <- NULL
  if (publication$source_format == "htm") {
    doc <- outlook_read_html(primary, max_bytes, deadline)
    outlook_html_identity(doc, publication)
    out <- parse_outlook_html(doc, publication, deadline)
    if (is.null(out)) {
      if (is.na(publication$full_text_url) || !nzchar(publication$full_text_url)) readboj_abort(
        "HTML publishes no numeric table and no full-text PDF is linked by the archive.",
        "readboj_no_forecast_table_error", release = publication$release)
      entry <- fetch(publication$full_text_url[[1L]])
      source_is_full <- TRUE
    }
  } else out <- NULL
  if (!is.null(expected_sha256) && entry$raw_sha256 != expected_sha256) readboj_abort(
    "Outlook source does not match `expected_sha256`.", "readboj_identity_error",
    expected_sha256 = expected_sha256, actual_sha256 = entry$raw_sha256)
  if (is.null(out)) {
    path <- outlook_executable(command)
    connection <- file(entry$path, "rb")
    magic <- readBin(connection, "raw", 5L)
    close(connection)
    if (!identical(magic, charToRaw("%PDF-"))) readboj_abort("Official Outlook asset is not a PDF.", "readboj_parse_error")
    extracted <- extract_outlook_pdf(entry$path, path, max_pdf_pages, max_text_bytes, deadline)
    outlook_pdf_identity(extracted, publication, source_is_full)
    out <- tryCatch(parse_outlook_table(extracted, publication, deadline),
      readboj_no_forecast_table_error = function(e) {
        if (length(extracted$pages) >= max_pdf_pages) readboj_abort(
          "The page bound may exclude the numeric forecast table.", "readboj_size_error",
          max_pdf_pages = max_pdf_pages)
        stop(e)
      })
  }
  out$source_url <- entry$canonical_url
  out$source_sha256 <- entry$raw_sha256
  out$source_format <- if (is.null(extracted)) "html" else "pdf"
  p <- snapshot_provenance(entry)
  p$parser_schema <- .readboj_outlook_schema
  p$source <- "Bank of Japan Outlook Report published member forecast tables"
  p$release <- publication$release[[1L]]
  p$publication_date <- publication$publication_date[[1L]]
  p$banks_view <- snapshot_provenance(primary)
  p$full_text_date <- publication$full_text_date[[1L]]
  p$full_text_url <- publication$full_text_url[[1L]]
  p$source_is_full_text <- source_is_full
  p$source_publication_date <- if (is.null(extracted)) publication$publication_date[[1L]] else {
    outlook_document_date(extracted$pages)
  }
  p$format_family <- attr(out, "outlook_format_family")
  p$table_notes <- attr(out, "outlook_notes")
  p$table_id <- .readboj_outlook_table
  p$pdf_page <- unique(out$pdf_page[!is.na(out$pdf_page)])
  p$pdf_page_index <- p$pdf_page - 1L
  p$printed_page <- unique(out$printed_page[!is.na(out$printed_page)])
  p$extractor <- if (is.null(extracted)) "xml2 semantic HTML tables" else extracted$extractor
  p$extracted_text_sha256 <- if (is.null(extracted)) NA_character_ else extracted$text_sha256
  p$coordinates_sha256 <- if (is.null(extracted)) NA_character_ else extracted$coordinates_sha256
  p$range_definition <- "See each row's member_input/range_trimming and the source table notes. Member dispersion, not a confidence or forecast-error interval."
  p$source_credit <- "Source: Bank of Japan"
  p$copyright_url <- "https://www.boj.or.jp/en/about/copyright.htm"
  p$rights_status <- "Intended-use permission is not established by this reader."
  attr(out, "outlook_notes") <- NULL
  attr(out, "outlook_format_family") <- NULL
  attach_provenance(out, p)
}

#' Read published Outlook forecast tables for any official edition
#'
#' Discovers dated HTML/PDF editions and derives measure headers, fiscal targets,
#' current/prior publication, actuals and available statistics from their source
#' tables and notes. There is no release whitelist. `latest` resolves the actual
#' newest archive edition; `all` reads every edition under one bounded deadline.
#'
#' Majority ranges and all-member ranges are distinct member dispersion, not
#' confidence intervals. Medians are returned only when actually printed. Legacy
#' WPI/CGPI, perishables CPI and tax/education-adjusted CPI retain separate IDs.
#' Explicit actuals and conditional estimates are distinguished. Fiscal periods
#' run April through March. Images/symbols are never used to estimate values.
#'
#' @param release One edition month (`YYYY-MM`), `"latest"`, or `"all"`.
#' @param comparison `"current"` (default), `"prior"`, or `"all"`.
#' @param pdftotext Optional provisioned Poppler executable. HTML tables need no
#'   extractor. PDF extraction raises `readboj_dependency_error` if unavailable;
#'   nothing is installed. Consults option `readboj.pdftotext`, then `Sys.which`.
#' @param expected_sha256 Optional complete SHA-256 pin of the numeric source
#'   asset (HTML or PDF). For image-only HTML this is the linked full-text PDF.
#'   A single pin is invalid with `release = "all"`; pin individual editions.
#' @param max_pdf_pages Maximum leading pages extracted (1 through 100).
#' @param max_text_bytes Maximum accepted layout text bytes. Coordinate XML is
#'   separately bounded to eight times this size. Checked after the bounded
#'   subprocess finishes; this is not a streaming disk quota.
#' @inheritParams list_boj_outlook_releases_raw
#' @return A long data frame of published scalars and explicit not-applicable
#'   cells, retaining measure/statistic/status, fiscal dates, comparison/vintage,
#'   raw cells, exact HTML XPath or PDF bounding boxes, source hashes and table
#'   identities. All-edition provenance has a separate receipt per edition.
#' @seealso [list_boj_outlook_releases()], [boj_provenance()]
#' @examples
#' \dontrun{
#' read_boj_outlook_raw("latest", cache_dir = tempfile("outlook-raw-"),
#'                      deadline = Sys.time() + 300)
#' }
#' @export
read_boj_outlook_raw <- function(release = "latest", comparison = "current",
    cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 30, retries = 3L, wait = 1,
    max_bytes = 16 * 1024^2, max_releases = 200L, max_pdf_pages = 20L,
    max_text_bytes = 1024^2, expected_sha256 = NULL,
    pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
    deadline = NULL) {
  release <- scalar_character(release, "release")
  if (!release %in% c("latest", "all") && !grepl("^[0-9]{4}-(0[1-9]|1[012])$", release)) {
    readboj_abort("`release` must be `latest`, `all`, or YYYY-MM.", "readboj_parameter_error")
  }
  comparison <- scalar_character(comparison, "comparison", c("current", "prior", "all"))
  max_pdf_pages <- outlook_count(max_pdf_pages, "max_pdf_pages", 100L)
  max_text_bytes <- scalar_number(max_text_bytes, "max_text_bytes", min = 1)
  max_bytes <- scalar_number(max_bytes, "max_bytes", min = 1)
  if (!is.null(expected_sha256)) {
    expected_sha256 <- tolower(scalar_character(expected_sha256, "expected_sha256"))
    if (!grepl("^[0-9a-f]{64}$", expected_sha256) || release == "all") readboj_abort(
      "`expected_sha256` must be a complete single-edition source hash.", "readboj_parameter_error")
  }
  deadline <- resolve_deadline(deadline)
  deadline_remaining(deadline)
  releases <- list_boj_outlook_releases_raw(cache_dir = cache_dir, refresh = refresh,
    offline = offline, max_age = max_age, timeout = timeout, retries = retries,
    wait = wait, max_bytes = min(max_bytes, 8 * 1024^2), max_releases = max_releases, deadline = deadline)
  selected <- if (release == "all") releases else if (release == "latest") releases[1L, , drop = FALSE] else
    releases[releases$release == release, , drop = FALSE]
  if (!nrow(selected) || (release != "all" && nrow(selected) != 1L)) readboj_abort(
    "No unique official Outlook edition found.", "readboj_identity_error", release = release)
  fetch <- function(url) {
    e <- fetch_snapshot(url, cache_dir = cache_dir, refresh = refresh, offline = offline,
      max_age = max_age, timeout = timeout, retries = retries, wait = wait,
      max_bytes = max_bytes, deadline = deadline)
    deadline_remaining(deadline)
    if (!identical(e$final_url, url)) readboj_abort("Outlook asset redirected to another identity.", "readboj_identity_error")
    if (is.na(file.info(e$path)$size) || file.info(e$path)$size > max_bytes) readboj_abort(
      "Cached Outlook source exceeds `max_bytes`.", "readboj_size_error")
    e
  }
  results <- list()
  receipts <- list()
  for (i in seq_len(nrow(selected))) {
    if (i > 1L && wait > 0 && !offline) deadline_pause(wait, deadline)
    out <- read_outlook_edition(selected[i, , drop = FALSE], fetch, pdftotext,
      max_bytes, max_pdf_pages, max_text_bytes, expected_sha256, deadline)
    receipts[[selected$release[[i]]]] <- boj_provenance(out)
    if (comparison != "all") out <- out[out$comparison == comparison, , drop = FALSE]
    results[[i]] <- out
  }
  result <- do.call(rbind, results)
  rownames(result) <- NULL
  p <- if (release == "all") list(source = "Bank of Japan complete Outlook archive",
    parser_schema = .readboj_outlook_schema, editions = receipts) else receipts[[1L]]
  p$requested_release <- release
  p$comparison <- comparison
  p$discovery <- boj_provenance(releases)
  deadline_remaining(deadline)
  attach_provenance(result, p)
}
