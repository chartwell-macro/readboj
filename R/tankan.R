tankan_root <- function(language) if (language == "en") .readboj_tankan_en else .readboj_tankan_jp

#' List dated official Tankan comprehensive-data releases
#'
#' Discovers the six official range indexes from 2000 onward, then their dated
#' release pages. These release pages are distinct from the latest revised
#' long-run `CO` API database.
#'
#' @inheritParams list_boj_bulk_files
#' @param max_pages Maximum range index pages followed.
#' @return A data frame of release pages with provenance for every index page.
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
#' @param release_url Exact official release page URL.
#' @inheritParams list_boj_bulk_files
#' @return A data frame of XLS, XLSX and ZIP assets with provenance.
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
#' @param url Exact XLS, XLSX or ZIP URL returned by [list_boj_tankan_assets()].
#' @inheritParams list_boj_bulk_files
#' @return A `boj_file` path with immutable response hash provenance.
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
