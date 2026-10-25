tankan_root <- function(language) if (language == "en") .readboj_tankan_en else .readboj_tankan_jp

#' List dated official Tankan comprehensive-data releases
#'
#' Traverses the official Bank of Japan (BOJ) Tankan comprehensive-data
#' archive: the root index, the bounded range indexes from 2000 onward, and
#' the dated release-page links extracted from those indexes. These dated
#' releases are distinct from the latest revised long-run `CO` API database and
#' are the route to publication-specific workbook and ZIP assets. Release pages
#' are listed from the range indexes; they are not fetched individually by this
#' function.
#'
#' @inheritParams list_boj_bulk_files
#' @param max_pages Positive integer maximum number of range index pages to
#'   follow. The default is `10L`; the current archive is expected to expose
#'   six ranges.
#'
#' @return A base `data.frame` with no row names and exactly the character
#'   columns `id`, `label`, `language`, `url`, and `range_url`. `id` is the
#'   dated release-page basename without `.htm`, `label` is the published link
#'   text, `language` is the selected lower-case archive language, `url` is the
#'   absolute dated release-page URL extracted from a range index, and
#'   `range_url` identifies that index. Duplicate release URLs are removed. A
#'   `readboj_provenance()` list records the archive source, language, and the
#'   snapshot provenance for the root and every followed range page.
#'
#' @details Discovery uses HTTPS on `www.boj.or.jp` and may make one request
#'   for the root plus one request per range index. Successful pages are
#'   cached under `cache_dir`; `offline = TRUE` reads only valid cached pages.
#'   The six range paths are an explicit coverage boundary, so releases outside
#'   the archive's discovered 2000-onward indexes are not returned. `wait` is
#'   applied between page requests when online and the one absolute `deadline`
#'   bounds all pages, retries, and waits.
#'
#' Invalid arguments, an unavailable or changed archive, no recognized range
#'   index, more range pages than `max_pages`, stale/missing offline snapshots,
#'   transport or HTTP/rate-limit/authentication failures, and size/deadline
#'   violations produce typed readboj errors. The function lists pages only; it
#'   does not download release assets.
#'
#' @seealso [list_boj_tankan_assets()], [download_boj_tankan_asset()],
#'   [read_boj_workbook()], [boj_provenance()]
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   releases <- list_boj_tankan_releases("en", max_pages = 6L,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'     deadline = Sys.time() + 60)
#'   head(releases[c("id", "language", "url", "range_url")])
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
#' @export
list_boj_tankan_releases <- function(language = "en", cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 30, retries = 3L, wait = 1, max_bytes = 8 * 1024^2,
    max_pages = 10L, deadline = NULL) {
  language <- normalize_language(language, both = FALSE)
  max_pages <- scalar_number(max_pages, "max_pages", min = 1, integer = TRUE)
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  root <- tankan_root(language)
  first <- fetch_snapshot(root, cache_dir = cache_dir, refresh = refresh, offline = offline,
    max_age = max_age, timeout = timeout, retries = retries, wait = wait,
    max_bytes = max_bytes, deadline = deadline)
  links <- html_links(first$path, root)
  ranges <- links[grepl("/zenyo/(2000|2006|2011|2016|2021|2026)/index\\.htm$", links$url), , drop = FALSE]
  ranges <- unique(ranges$url)
  if (!length(ranges)) readboj_abort("No Tankan range indexes found; official HTML may have changed.",
    "readboj_schema_error")
  if (length(ranges) > max_pages) readboj_abort("Tankan range index count exceeds the page bound.",
    "readboj_size_error")
  results <- list()
  provenance <- list(snapshot_provenance(first))
  for (i in seq_along(ranges)) {
    if (i > 1L && wait > 0 && !offline) deadline_pause(wait, deadline)
    entry <- fetch_snapshot(ranges[[i]], cache_dir = cache_dir, refresh = refresh,
      offline = offline, max_age = max_age, timeout = timeout, retries = retries,
      wait = wait, max_bytes = max_bytes, deadline = deadline)
    page <- html_links(entry$path, ranges[[i]])
    keep <- grepl("/zenyo/[0-9]{4}/[^/]+\\.htm$", page$url) &
      !grepl("/index\\.htm$", page$url)
    page <- page[keep, , drop = FALSE]
    if (nrow(page)) {
      page$range_url <- ranges[[i]]
      results[[length(results) + 1L]] <- page
    }
    provenance[[length(provenance) + 1L]] <- snapshot_provenance(entry)
  }
  out <- if (length(results)) do.call(rbind, results) else
    data.frame(label = character(), href = character(), url = character(), range_url = character())
  out$id <- basename(sub("\\.htm$", "", out$url))
  out$language <- language
  out <- out[c("id", "label", "language", "url", "range_url")]
  out <- out[!duplicated(out$url), , drop = FALSE]
  rownames(out) <- NULL
  attach_provenance(out, list(source = "Bank of Japan Tankan comprehensive-data archive",
    pages = provenance, language = language))
}

#' List downloadable assets on a dated Tankan release page
#'
#' Fetches one dated Tankan comprehensive-data release page and keeps only its
#' official workbook and ZIP links. The page itself can be obtained from
#' [list_boj_tankan_releases()].
#'
#' @param release_url A non-empty exact HTTPS URL for an official BOJ Tankan
#'   archive page under `/statistics/tk/zenyo/`, including the optional `/en/`
#'   language path. It is typically a dated release page returned by
#'   [list_boj_tankan_releases()], although a root or range index under that
#'   path is also accepted and may yield no assets. It is not a local filename
#'   or an arbitrary web page.
#' @inheritParams list_boj_bulk_files
#'
#' @return A base `data.frame` with no row names and exactly the character
#'   columns `id`, `label`, and `url`. `id` is the XLS/XLSX/ZIP basename
#'   without a query or fragment, `label` is the published link text, and
#'   `url` is the absolute asset URL. Duplicate rows with the same URL are
#'   removed. `readboj_provenance()` records the page snapshot and the exact
#'   `release_url` used for discovery.
#'
#' @details Only URLs ending in `.xls`, `.xlsx`, or `.zip` are retained;
#' notices, PDFs, and other links are deliberately excluded. The release page
#' is fetched over HTTPS from `www.boj.or.jp`, with successful response bytes
#' cached under `cache_dir`. `offline = TRUE` requires a valid page snapshot
#' and makes no network request. This function does not download the listed
#' assets.
#'
#' Invalid or non-official `release_url` values, a missing/changed page,
#' transport or HTTP/rate-limit/authentication failures, stale offline data,
#' or parameter/size/deadline violations produce typed readboj errors.
#'
#' @seealso [list_boj_tankan_releases()], [download_boj_tankan_asset()],
#'   [read_boj_workbook()], [boj_provenance()]
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   releases <- list_boj_tankan_releases("en", max_pages = 6L,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'     deadline = Sys.time() + 60)
#'   if (nrow(releases)) {
#'     assets <- list_boj_tankan_assets(releases$url[[1L]],
#'       cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'       timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'       deadline = Sys.time() + 30)
#'     head(assets)
#'   }
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
#' @export
list_boj_tankan_assets <- function(release_url, cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 30, retries = 3L, wait = 1, max_bytes = 8 * 1024^2,
    deadline = NULL) {
  release_url <- scalar_character(release_url, "release_url")
  deadline <- resolve_deadline(deadline, default_seconds = max(120, timeout * (retries + 1L) + 30))
  if (!grepl("^https://www\\.boj\\.or\\.jp/(en/)?statistics/tk/zenyo/", release_url)) {
    readboj_abort("`release_url` must be an official BoJ Tankan archive page.",
      "readboj_parameter_error")
  }
  entry <- fetch_snapshot(release_url, cache_dir = cache_dir, refresh = refresh,
    offline = offline, max_age = max_age, timeout = timeout, retries = retries,
    wait = wait, max_bytes = max_bytes, deadline = deadline)
  links <- html_links(entry$path, release_url)
  links <- links[grepl("\\.(xlsx?|zip)([?#].*)?$", links$url, ignore.case = TRUE), , drop = FALSE]
  links$id <- basename(sub("[?#].*$", "", links$url))
  links <- unique(links[c("id", "label", "url")])
  rownames(links) <- NULL
  attach_provenance(links, c(snapshot_provenance(entry), list(
    source = "Bank of Japan dated Tankan release page", release_url = release_url)))
}

#' Download an official dated Tankan asset
#'
#' Downloads one workbook or ZIP URL returned by
#' [list_boj_tankan_assets()] and stores the exact response as a
#' content-addressed cache object. Use [read_boj_workbook()] for an XLS/XLSX
#' response or [read_boj_bulk()] for a ZIP containing CSV files.
#'
#' @param url A non-empty exact HTTPS URL under the official BOJ Tankan
#'   comprehensive-data archive, ending in `.xls`, `.xlsx`, or `.zip` (query
#'   and fragment text is permitted). URLs returned by
#'   [list_boj_tankan_assets()] are the intended input; arbitrary BOJ pages and
#'   non-BOJ hosts are rejected.
#' @inheritParams list_boj_bulk_files
#' @param max_age Non-negative cache age in seconds, or `Inf` for no age limit.
#'   The default for this dated-asset downloader is `Inf`.
#' @param timeout Non-negative per-request timeout in seconds. The default for
#'   this asset download is 60 seconds.
#' @param max_bytes Positive maximum downloaded response bytes. The default is
#'   `512 * 1024^2` (512 MiB); the limit is enforced before caching.
#'
#' @return A length-one character vector with classes `c("boj_file",
#'   "character")`. The value is a regular local cache-object path. Its
#'   `readboj_provenance()` attribute contains the canonical/final URL,
#'   retrieval time, status and headers, byte count, immutable raw SHA-256,
#'   cache status/path, and package/schema metadata.
#'
#' @details The request is HTTPS-only, follows only HTTPS redirects, and is
#'   restricted to `www.boj.or.jp` Tankan archive paths. Successful downloads
#'   are cached under `cache_dir` and subject to the package cache bounds;
#'   temporary response files are removed on success or failure. The default
#'   `max_age = Inf` allows a cached asset of any age, while `refresh = TRUE`
#'   explicitly retrieves the current response. `offline = TRUE` never
#'   downloads a missing or stale response. The hash identifies the bytes but
#'   does not make the BOJ's dated publication immutable at the URL.
#'
#' Invalid URLs, source changes, cache corruption, rate limits,
#' authorization/transport failures, expired offline snapshots, or response
#' size/deadline violations produce typed readboj errors. The package does not
#' interpret workbook sheets or extract CSV members during download.
#'
#' @seealso [list_boj_tankan_assets()], [read_boj_workbook()],
#'   [read_boj_bulk()], [boj_provenance()]
#' @examples
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   releases <- list_boj_tankan_releases("en", max_pages = 6L,
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'     deadline = Sys.time() + 60)
#'   if (nrow(releases)) {
#'     assets <- list_boj_tankan_assets(releases$url[[1L]],
#'       cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'       timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
#'       deadline = Sys.time() + 30)
#'     candidates <- assets$url[grepl("\\.(xlsx?|zip)([?#].*)?$", assets$url,
#'       ignore.case = TRUE)]
#'     if (length(candidates)) {
#'       candidate <- candidates[[1L]]
#'       asset <- download_boj_tankan_asset(candidate,
#'         cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'         max_age = Inf, timeout = 10, retries = 0L, wait = 0,
#'         max_bytes = 64 * 1024^2, deadline = Sys.time() + 60)
#'       print(asset)
#'     }
#'   }
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
#' @export
download_boj_tankan_asset <- function(url, cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = Inf, timeout = 60,
    retries = 3L, wait = 1, max_bytes = 512 * 1024^2, deadline = NULL) {
  url <- scalar_character(url, "url")
  deadline <- resolve_deadline(deadline, default_seconds = max(600, timeout * (retries + 1L) + 60))
  if (!grepl("^https://www\\.boj\\.or\\.jp/(en/)?statistics/tk/zenyo/.*\\.(xlsx?|zip)([?#].*)?$",
      url, ignore.case = TRUE)) {
    readboj_abort("Tankan asset must be an official XLS, XLSX or ZIP URL.",
      "readboj_parameter_error")
  }
  download_snapshot(url, cache_dir, refresh, offline, max_age, timeout, retries,
    wait, max_bytes, deadline)
}
