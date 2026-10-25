#' Rebuild a portable Outlook data bundle from the complete raw archive
#'
#' This maintenance route is independent of the saved bundle. It discovers and
#' parses all editions, retrieves every linked asset for the source manifest,
#' validates the complete result, and writes a compact RDS atomically. It never
#' activates or installs the bundle. Raw documents stay in the separately bounded
#' source cache and are not embedded in the output.
#' @param path Explicit output RDS path; the parent directory must exist.
#' @inheritParams read_boj_outlook_raw
#' @return Invisibly, the validated snapshot written to `path`.
#' @examples
#' \dontrun{
#' build_boj_outlook_bundle(
#'   tempfile(fileext = ".rds"), cache_dir = tempfile("outlook-build-"),
#'   deadline = Sys.time() + 1800
#' )
#' }
#' @export
build_boj_outlook_bundle <- function(path, cache_dir = boj_cache_dir(), refresh = FALSE,
    offline = FALSE, max_age = Inf, timeout = 30, retries = 2L, wait = 0.1,
    max_bytes = 16 * 1024^2, max_releases = 200L, max_pdf_pages = 20L,
    max_text_bytes = 1024^2,
    pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
    deadline = NULL) {
  path <- path.expand(scalar_character(path, "path"))
  if (!dir.exists(dirname(path))) readboj_abort("Bundle output directory does not exist.", "readboj_parameter_error")
  deadline <- resolve_deadline(deadline, 1800)
  max_pdf_pages <- outlook_count(max_pdf_pages, "max_pdf_pages", 100L)
  max_bytes <- scalar_number(max_bytes, "max_bytes", min = 1)
  max_text_bytes <- scalar_number(max_text_bytes, "max_text_bytes", min = 1)
  catalogue <- list_boj_outlook_releases_raw(cache_dir, refresh, offline, max_age,
    timeout, retries, wait, min(max_bytes, 8 * 1024^2), max_releases, deadline)
  discovery <- outlook_clean_receipt(boj_provenance(catalogue))
  assets <- list()
  fetch <- function(url) {
    e <- fetch_snapshot(url, cache_dir = cache_dir, refresh = refresh, offline = offline,
      max_age = max_age, timeout = timeout, retries = retries, wait = wait,
      max_bytes = max_bytes, deadline = deadline)
    if (!identical(e$final_url, url)) readboj_abort("Bundle asset redirected to another identity.", "readboj_identity_error")
    assets[[url]] <<- outlook_clean_receipt(e)
    e
  }
  rows <- receipts <- list()
  for (i in seq_len(nrow(catalogue))) {
    release <- catalogue$release[[i]]
    if (i > 1L && !offline && wait > 0) deadline_pause(wait, deadline)
    edition <- read_outlook_edition(catalogue[i, , drop = FALSE], fetch, pdftotext,
      max_bytes, max_pdf_pages, max_text_bytes, NULL, deadline)
    receipts[[release]] <- outlook_clean_receipt(boj_provenance(edition))
    attr(edition, "readboj_provenance") <- NULL
    rows[[release]] <- edition
  }
  urls <- unique(stats::na.omit(c(catalogue$banks_view_url, catalogue$full_text_url)))
  for (url in setdiff(urls, names(assets))) {
    if (!offline && wait > 0) deadline_pause(wait, deadline)
    fetch(url)
  }
  data <- do.call(rbind, rows)
  rownames(data) <- NULL
  attr(catalogue, "readboj_provenance") <- NULL
  checked <- min(vapply(assets, function(e) as.numeric(as.POSIXct(e$retrieved_at, tz = "UTC")), numeric(1L)))
  snapshot <- outlook_saved_seal(list(schema = .readboj_outlook_saved_schema,
    parser_schema = .readboj_outlook_schema, parser_sha256 = outlook_parser_fingerprint(),
    built_at = outlook_now(), checked_at = as.POSIXct(checked, origin = "1970-01-01", tz = "UTC"),
    catalogue = catalogue, data = data, editions = receipts, assets = assets,
    discovery = discovery, revisions = list()))
  outlook_saved_validate(snapshot)
  temporary <- tempfile(".bundle-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(snapshot, temporary, compress = "xz", version = 2)
  outlook_saved_read_file(temporary)
  deadline_remaining(deadline)
  if (!file.rename(temporary, path)) readboj_abort("Could not publish rebuilt Outlook bundle.", "readboj_outlook_update_error")
  invisible(snapshot)
}
