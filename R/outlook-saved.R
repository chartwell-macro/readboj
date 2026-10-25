.readboj_outlook_saved_schema <- "outlook-saved-v1"
.readboj_outlook_memo <- new.env(parent = emptyenv())

outlook_parser_fingerprint <- function() {
  # Hash executable parser definitions, not file paths, timestamps or byte code.
  names <- c("outlook_space", "outlook_month", "outlook_date", "outlook_read_html",
    "outlook_pdf_coordinates", "outlook_pdf_line_frame", "outlook_pdf_labels",
    "outlook_pdf_fragments", "parse_outlook_table", "outlook_html_grid",
    "outlook_html_text", "parse_outlook_html", "outlook_measure", "outlook_vintage",
    "outlook_years", "outlook_parenthetical_vintage", "outlook_point_status",
    "outlook_cell_values", "outlook_cell_parts", "outlook_range_semantics",
    "outlook_observation", "outlook_finish", "parse_outlook_releases",
    "outlook_pdf_identity", "outlook_document_date", "outlook_html_identity",
    "read_outlook_edition", "extract_outlook_pdf", "run_outlook_pdf")
  definitions <- lapply(names, function(name) {
    fn <- get(name, envir = environment(outlook_parser_fingerprint))
    list(formals = lapply(formals(fn), deparse), body = deparse(body(fn), width.cutoff = 500L))
  })
  digest::digest(list(.readboj_outlook_schema, .readboj_outlook_table, definitions), algo = "sha256")
}

outlook_clean_receipt <- function(x) {
  if (!is.list(x)) return(x)
  x[c("path", "cache_path", "transfer_bytes", "request_attempts")] <- NULL
  lapply(x, outlook_clean_receipt)
}

outlook_saved_seal <- function(x) {
  x$content_sha256 <- NULL
  x$content_sha256 <- digest::digest(x, algo = "sha256")
  x
}

outlook_saved_validate <- function(x) {
  fail <- function(message) readboj_abort(paste0("Invalid saved Outlook data: ", message),
    "readboj_outlook_data_error")
  if (!is.list(x) || !identical(x$schema, .readboj_outlook_saved_schema) ||
      !is.character(x$parser_schema) || length(x$parser_schema) != 1L ||
      is.na(x$parser_schema) || !nzchar(x$parser_schema)) fail("unsupported schema.")
  hash <- x$content_sha256
  x$content_sha256 <- NULL
  if (!is.character(hash) || length(hash) != 1L ||
      !identical(hash, digest::digest(x, algo = "sha256"))) fail("content checksum mismatch.")
  if (!is.character(x$parser_sha256) || length(x$parser_sha256) != 1L ||
      !grepl("^[a-f0-9]{64}$", x$parser_sha256)) fail("missing parser identity.")
  d <- x$data
  catalogue <- x$catalogue
  required <- c("release", "publication_date", "forecast_vintage", "comparison",
    "fiscal_year", "period", "period_start", "period_end", "measure", "measure_label",
    "source_header", "statistic", "value", "raw_value", "raw_cell", "value_status",
    "unit", "frequency", "range_scope", "member_input", "range_trimming", "table_id",
    "table_index", "pdf_page", "printed_page", "table_row", "table_column",
    "source_row_label", "source_cell_id", "source_xpath", "source_column_span",
    "shared_cell", "pdf_xmin", "pdf_ymin", "pdf_xmax", "pdf_ymax", "source_url",
    "source_sha256", "source_format")
  if (!is.data.frame(d) || !nrow(d) || !identical(names(d), required) ||
      !is.numeric(d$value) || !is.integer(d$fiscal_year) ||
      !inherits(d$publication_date, "Date") || !inherits(d$period_start, "Date") ||
      !inherits(d$period_end, "Date")) fail("unexpected table schema or types.")
  integers <- c("fiscal_year", "table_index", "pdf_page", "table_row", "table_column")
  coordinates <- c("pdf_xmin", "pdf_ymin", "pdf_xmax", "pdf_ymax")
  characters <- setdiff(required, c(integers, coordinates, "value", "shared_cell",
    "publication_date", "period_start", "period_end"))
  if (!all(vapply(d[characters], is.character, logical(1L))) ||
      !all(vapply(d[integers], is.integer, logical(1L))) ||
      !all(vapply(d[coordinates], is.numeric, logical(1L))) ||
      !is.logical(d$shared_cell)) fail("unexpected column types.")
  if (!is.data.frame(catalogue) || !nrow(catalogue) ||
      !all(c("release", "publication_date", "banks_view_url", "source_format",
        "full_text_date", "full_text_url") %in% names(catalogue)) ||
      anyNA(catalogue$release) || anyDuplicated(catalogue$release) ||
      !inherits(catalogue$publication_date, "Date") || anyNA(catalogue$publication_date) ||
      !setequal(d$release, catalogue$release)) fail("incomplete edition catalogue.")
  if (anyNA(d[c("release", "forecast_vintage", "comparison", "fiscal_year", "measure",
      "statistic", "value_status", "range_scope", "source_url", "source_sha256")]) ||
      any(!grepl("^[0-9]{4}-(0[1-9]|1[012])$", d$release)) ||
      any(!d$comparison %in% c("current", "prior")) ||
      any(!d$statistic %in% c("majority_lower", "majority_upper", "all_lower", "all_upper",
        "median", "point", "actual", "conditional_estimate", "not_applicable")) ||
      any(!d$value_status %in% c("forecast", "actual", "conditional_estimate", "published_point", "not_applicable")) ||
      any(!d$range_scope %in% c("majority", "all_members")) ||
      anyNA(d[c("publication_date", "period_start", "period_end", "raw_value", "raw_cell")]) ||
      any(d$forecast_vintage[d$comparison == "current"] != d$release[d$comparison == "current"]) ||
      any((d$value_status == "not_applicable") != is.na(d$value)) ||
      any(!is.finite(d$value[!is.na(d$value)])) ||
      any(!grepl("^[0-9a-f]{64}$", d$source_sha256)) ||
      any(d$publication_date != catalogue$publication_date[match(d$release, catalogue$release)]) ||
      any(d$period != paste0("FY", d$fiscal_year)) ||
      any(d$period_start != as.Date(paste0(d$fiscal_year, "-04-01"))) ||
      any(d$period_end != as.Date(paste0(d$fiscal_year + 1L, "-03-31")))) fail("invalid values or fiscal identities.")
  key <- c("release", "forecast_vintage", "comparison", "fiscal_year", "measure", "statistic", "range_scope")
  if (anyDuplicated(d[key])) fail("duplicate scalar identities.")
  cells <- do.call(paste, c(d[setdiff(key, "statistic")], sep = "\r"))
  for (scope in c("majority", "all")) {
    lower <- which(d$statistic == paste0(scope, "_lower"))
    upper <- which(d$statistic == paste0(scope, "_upper"))
    matched <- match(cells[lower], cells[upper])
    if (length(lower) != length(upper) || anyNA(matched) ||
        any(d$value[lower] > d$value[upper[matched]])) fail("incomplete or reversed member ranges.")
    if (scope == "majority") {
      medians <- which(d$statistic == "median")
      j <- match(cells[medians], cells[lower])
      if (anyNA(j) || any(d$value[medians] < d$value[lower[j]]) ||
          any(d$value[medians] > d$value[upper[matched[j]]])) fail("median outside its member range.")
    }
  }
  if (!is.list(x$editions) || !setequal(names(x$editions), catalogue$release) ||
      !is.list(x$assets) || anyDuplicated(names(x$assets))) fail("missing provenance.")
  urls <- unique(stats::na.omit(c(catalogue$banks_view_url, catalogue$full_text_url)))
  if (!all(urls %in% names(x$assets)) || !all(d$source_url %in% urls)) fail("missing source dependencies.")
  for (url in urls) {
    e <- x$assets[[url]]
    if (!identical(e$canonical_url, url) || !identical(e$final_url, url) ||
        !is.character(e$raw_sha256) || length(e$raw_sha256) != 1L ||
        !grepl("^[a-f0-9]{64}$", e$raw_sha256)) fail("invalid asset identity.")
    validate_official_url(url)
  }
  for (release in catalogue$release) {
    rows <- d[d$release == release, , drop = FALSE]
    p <- x$editions[[release]]
    if (!nrow(rows) || !any(is.finite(rows$value)) ||
        !identical(p$release, release) || !all(rows$source_url == p$canonical_url) ||
        !all(rows$source_sha256 == p$raw_sha256) ||
        !identical(x$assets[[p$canonical_url]]$raw_sha256, p$raw_sha256)) fail("edition receipt disagrees with table.")
  }
  invisible(TRUE)
}

outlook_saved_read_file <- function(path, expected = NULL) {
  size <- file.info(path)$size
  if (is.na(size) || size > 32 * 1024^2) readboj_abort(
    "Saved Outlook file is missing or exceeds 32 MiB.", "readboj_outlook_data_error")
  if (!is.null(expected) && !identical(sha256_file(path), expected)) readboj_abort(
    "Saved Outlook file checksum mismatch.", "readboj_outlook_data_error")
  x <- tryCatch(readRDS(path), error = function(e) readboj_abort(
    "Could not deserialize saved Outlook data.", "readboj_outlook_data_error", parent = e))
  outlook_saved_validate(x)
  x
}

#' Location of refreshed Outlook data
#'
#' Ordinary reads never create this directory. Configure the same location for
#' the application and its daily updater with option `readboj.outlook_data_dir`
#' or environment variable `READBOJ_OUTLOOK_DATA_DIR`.
#' @return The configured directory path.
#' @examples
#' boj_outlook_data_dir()
#' @export
boj_outlook_data_dir <- function() {
  path <- getOption("readboj.outlook_data_dir", Sys.getenv("READBOJ_OUTLOOK_DATA_DIR",
    unset = file.path(tools::R_user_dir("readboj", "data"), "outlook")))
  path.expand(scalar_character(path, "data_dir"))
}

outlook_saved_markers <- function(data_dir) {
  sort(list.files(file.path(data_dir, "commits"), pattern = "^[0-9]{12}-[a-f0-9]{64}\\.rds$",
    full.names = TRUE), decreasing = TRUE)
}

outlook_saved_load <- function(data_dir, refresh = FALSE) {
  data_dir <- path.expand(scalar_character(data_dir, "data_dir"))
  refresh <- scalar_flag(refresh, "refresh")
  baseline <- system.file("extdata", "outlook-saved.rds", package = "readboj")
  markers <- outlook_saved_markers(data_dir)
  problems <- character()
  candidates <- c(markers, baseline)
  for (candidate in candidates) {
    result <- tryCatch({
      marker <- if (candidate %in% markers) {
        if (is.na(file.info(candidate)$size) || file.info(candidate)$size > 4096) stop("Invalid commit size")
        readRDS(candidate)
      } else NULL
      if (!is.null(marker) && (!is.list(marker) || !is.character(marker$sha256) ||
          length(marker$sha256) != 1L || !grepl("^[a-f0-9]{64}$", marker$sha256) ||
          !identical(basename(candidate), sprintf("%012.0f-%s.rds", marker$generation, marker$sha256)))) {
        stop("Invalid commit identity")
      }
      path <- if (is.null(marker)) candidate else file.path(data_dir, "objects", paste0(marker$sha256, ".rds"))
      info <- file.info(path)
      key <- paste(path, info$size, as.numeric(info$mtime), as.numeric(info$ctime), sep = "|")
      cached <- .readboj_outlook_memo$loaded
      if (!refresh && !is.null(cached) && identical(cached$key, key)) {
        snapshot <- cached$snapshot
      } else {
        snapshot <- outlook_saved_read_file(path, if (is.null(marker)) NULL else marker$sha256)
        .readboj_outlook_memo$loaded <- list(key = key, snapshot = snapshot)
      }
      list(snapshot = snapshot, data_dir = data_dir, origin = if (is.null(marker)) "package" else "refreshed",
        path = path, generation = if (is.null(marker)) 0 else marker$generation,
        marker = if (is.null(marker)) NULL else candidate)
    }, error = function(e) { problems <<- c(problems, conditionMessage(e)); NULL })
    if (!is.null(result)) {
      result$problems <- problems
      if (length(problems)) warning(structure(list(message = paste0(
        "Saved Outlook refresh is invalid; using the last good snapshot. ", problems[[1L]]),
        call = NULL), class = c("readboj_outlook_fallback_warning", "warning", "condition")))
      return(result)
    }
  }
  readboj_abort("No valid saved Outlook dataset is available.", "readboj_outlook_data_error",
    problems = problems)
}

outlook_saved_receipt <- function(loaded) {
  x <- loaded$snapshot
  check <- outlook_latest_check(loaded$data_dir)
  list(origin = loaded$origin, snapshot_sha256 = x$content_sha256,
    parser_sha256 = x$parser_sha256, generation = loaded$generation,
    parser_schema = x$parser_schema,
    built_at = x$built_at, checked_at = check$last_successful_check %||% x$checked_at,
    last_update_status = check$status %||% "bundled", fallback_errors = loaded$problems,
    coverage_loss = x$coverage_loss,
    update = "Run update_boj_outlook() separately; ordinary reads perform no source checks.")
}

#' List saved Outlook editions without network access
#'
#' Reads the package baseline or newest valid local refresh. The structured
#' dataset is reused across selections. `refresh` reloads saved data only.
#' Transport arguments apply only to explicit `source = "raw"` discovery.
#' @inheritParams list_boj_outlook_releases_raw
#' @param source `"saved"` (default) or explicit raw archive discovery.
#' @param data_dir Directory shared with [update_boj_outlook()].
#' @return Edition catalogue with saved-data and discovery provenance.
#' @examples
#' editions <- list_boj_outlook_releases(data_dir = tempfile("outlook-data-"))
#' head(editions)
#' @export
list_boj_outlook_releases <- function(cache_dir = boj_cache_dir(), refresh = FALSE,
    offline = FALSE, max_age = 24 * 60 * 60, timeout = 30, retries = 3L,
    wait = 1, max_bytes = 8 * 1024^2, max_releases = 200L, deadline = NULL,
    source = "saved", data_dir = boj_outlook_data_dir()) {
  source <- scalar_character(source, "source", c("saved", "raw"))
  if (source == "raw") return(list_boj_outlook_releases_raw(cache_dir, refresh,
    offline, max_age, timeout, retries, wait, max_bytes, max_releases, deadline))
  if (!is.null(deadline)) deadline_remaining(resolve_deadline(deadline))
  loaded <- outlook_saved_load(data_dir, refresh)
  p <- loaded$snapshot$discovery
  p$saved <- outlook_saved_receipt(loaded)
  attach_provenance(loaded$snapshot$catalogue, p)
}

#' Read saved published Outlook forecast tables
#'
#' The default reads structured local data, without HTTP, PDF reads or an
#' extractor, including on first use. Use [read_boj_outlook_raw()] for general
#' archive discovery and source parsing; no dated release admission list exists.
#' `refresh` reloads the saved dataset, and never runs the updater.
#' @inheritParams read_boj_outlook_raw
#' @param source `"saved"` (default) or explicit raw source parsing.
#' @param data_dir Directory shared with [update_boj_outlook()].
#' @param measure,statistic,range_scope Optional vectors of exact semantic IDs.
#'   Unknown IDs raise a parameter error. `NULL` selects all IDs.
#' @return A long data frame preserving all published scalars, explicit NA cells,
#'   fiscal and source identities, with edition and saved-snapshot provenance.
#' @examples
#' history <- read_boj_outlook("all", comparison = "all",
#'                             data_dir = tempfile("outlook-data-"))
#' head(history[c("release", "fiscal_year", "measure", "statistic", "value")])
#' @export
read_boj_outlook <- function(release = "latest", comparison = "current",
    cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 30, retries = 3L, wait = 1,
    max_bytes = 16 * 1024^2, max_releases = 200L, max_pdf_pages = 20L,
    max_text_bytes = 1024^2, expected_sha256 = NULL,
    pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
    deadline = NULL, source = "saved", data_dir = boj_outlook_data_dir(),
    measure = NULL, statistic = NULL, range_scope = NULL) {
  source <- scalar_character(source, "source", c("saved", "raw"))
  if (source == "raw") {
    out <- read_boj_outlook_raw(release, comparison, cache_dir, refresh, offline,
      max_age, timeout, retries, wait, max_bytes, max_releases, max_pdf_pages,
      max_text_bytes, expected_sha256, pdftotext, deadline)
  } else {
    release <- scalar_character(release, "release")
    if (!release %in% c("latest", "all") && !grepl("^[0-9]{4}-(0[1-9]|1[012])$", release)) {
      readboj_abort("`release` must be `latest`, `all`, or YYYY-MM.", "readboj_parameter_error")
    }
    comparison <- scalar_character(comparison, "comparison", c("current", "prior", "all"))
    if (!is.null(deadline)) deadline_remaining(resolve_deadline(deadline))
    loaded <- outlook_saved_load(data_dir, refresh)
    snapshot <- loaded$snapshot
    selected <- if (release == "latest") snapshot$catalogue$release[[1L]] else
      if (release == "all") snapshot$catalogue$release else release
    if (!all(selected %in% snapshot$catalogue$release)) readboj_abort(
      "No saved Outlook edition found. Run update_boj_outlook() or use the raw reader.",
      "readboj_identity_error", release = release)
    if (!is.null(expected_sha256)) {
      pin <- tolower(scalar_character(expected_sha256, "expected_sha256"))
      if (release == "all" || !grepl("^[a-f0-9]{64}$", pin)) readboj_abort(
        "`expected_sha256` must be a complete single-edition source hash.", "readboj_parameter_error")
      if (!identical(snapshot$editions[[selected]]$raw_sha256, pin)) readboj_abort(
        "Saved numeric source does not match `expected_sha256`.", "readboj_identity_error")
    }
    keep <- snapshot$data$release %in% selected
    if (comparison != "all") keep <- keep & snapshot$data$comparison == comparison
    out <- snapshot$data[keep, , drop = FALSE]
    p <- if (release == "all") list(source = "Bank of Japan complete Outlook archive",
      parser_schema = snapshot$parser_schema, editions = snapshot$editions[selected]) else snapshot$editions[[selected]]
    p$discovery <- snapshot$discovery
    p$requested_release <- release
    p$comparison <- comparison
    p$saved <- outlook_saved_receipt(loaded)
    out <- attach_provenance(out, p)
  }
  p <- boj_provenance(out)
  filters <- list(measure = measure, statistic = statistic, range_scope = range_scope)
  for (name in names(filters)) {
    ids <- filters[[name]]
    if (is.null(ids)) next
    available <- if (source == "saved") unique(snapshot$data[[name]]) else unique(out[[name]])
    if (!is.character(ids) || !length(ids) || anyNA(ids) || any(!ids %in% available)) readboj_abort(
      sprintf("`%s` must contain known semantic IDs.", name), "readboj_parameter_error")
    out <- out[out[[name]] %in% ids, , drop = FALSE]
  }
  rownames(out) <- NULL
  p$selection <- filters
  attach_provenance(out, p)
}
