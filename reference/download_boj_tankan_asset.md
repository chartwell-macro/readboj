# Download an official dated Tankan asset

Downloads one workbook or ZIP URL returned by
[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md)
and stores the exact response as a content-addressed cache object. Use
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md)
for an XLS/XLSX response or
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md)
for a ZIP containing CSV files.

## Usage

``` r
download_boj_tankan_asset(
  url,
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = Inf,
  timeout = 60,
  retries = 3L,
  wait = 1,
  max_bytes = 512 * 1024^2,
  deadline = NULL
)
```

## Arguments

- url:

  A non-empty exact HTTPS URL under the official BOJ Tankan
  comprehensive-data archive, ending in `.xls`, `.xlsx`, or `.zip`
  (query and fragment text is permitted). URLs returned by
  [`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md)
  are the intended input; arbitrary BOJ pages and non-BOJ hosts are
  rejected.

- cache_dir:

  Directory used for content-addressed response snapshots. The default
  is `tools::R_user_dir("readboj", "cache")`; it is created when needed.
  Use a package-managed temporary directory in tests.

- refresh:

  Logical scalar. If `TRUE`, ignore an otherwise usable request snapshot
  and retrieve the catalogue again.

- offline:

  Logical scalar. If `TRUE`, make no network request and use a valid
  cached snapshot only; an absent or stale snapshot raises an
  `readboj_offline_error`.

- max_age:

  Non-negative cache age in seconds, or `Inf` for no age limit. The
  default for this dated-asset downloader is `Inf`.

- timeout:

  Non-negative per-request timeout in seconds. The default for this
  asset download is 60 seconds.

- retries:

  Non-negative integer number of retries for transient transport
  responses or errors. The default is `3L`.

- wait:

  Non-negative seconds between requests and retries. The default is one
  second; waiting is skipped for cached responses and offline reads.

- max_bytes:

  Positive maximum downloaded response bytes. The default is
  `512 * 1024^2` (512 MiB); the limit is enforced before caching.

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A length-one character vector with classes `c("boj_file", "character")`.
The value is a regular local cache-object path. Its
`readboj_provenance()` attribute contains the canonical/final URL,
retrieval time, status and headers, byte count, immutable raw SHA-256,
cache status/path, and package/schema metadata.

## Details

The request is HTTPS-only, follows only HTTPS redirects, and is
restricted to `www.boj.or.jp` Tankan archive paths. Successful downloads
are cached under `cache_dir` and subject to the package cache bounds;
temporary response files are removed on success or failure. The default
`max_age = Inf` allows a cached asset of any age, while `refresh = TRUE`
explicitly retrieves the current response. `offline = TRUE` never
downloads a missing or stale response. The hash identifies the bytes but
does not make the BOJ's dated publication immutable at the URL.

Invalid URLs, source changes, cache corruption, rate limits,
authorization/transport failures, expired offline snapshots, or response
size/deadline violations produce typed readboj errors. The package does
not interpret workbook sheets or extract CSV members during download.

## See also

[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md),
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md),
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  releases <- list_boj_tankan_releases("en", max_pages = 6L,
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
    deadline = Sys.time() + 60)
  if (nrow(releases)) {
    assets <- list_boj_tankan_assets(releases$url[[1L]],
      cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
      timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
      deadline = Sys.time() + 30)
    candidates <- assets$url[grepl("\\.(xlsx?|zip)([?#].*)?$", assets$url,
      ignore.case = TRUE)]
    if (length(candidates)) {
      candidate <- candidates[[1L]]
      asset <- download_boj_tankan_asset(candidate,
        cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
        max_age = Inf, timeout = 10, retries = 0L, wait = 0,
        max_bytes = 64 * 1024^2, deadline = Sys.time() + 60)
      print(asset)
    }
  }
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
