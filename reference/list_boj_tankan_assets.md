# List downloadable assets on a dated Tankan release page

Fetches one dated Tankan comprehensive-data release page and keeps only
its official workbook and ZIP links. The page itself can be obtained
from
[`list_boj_tankan_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_releases.md).

## Usage

``` r
list_boj_tankan_assets(
  release_url,
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 8 * 1024^2,
  deadline = NULL
)
```

## Arguments

- release_url:

  A non-empty exact HTTPS URL for an official BOJ Tankan archive page
  under `/statistics/tk/zenyo/`, including the optional `/en/` language
  path. It is typically a dated release page returned by
  [`list_boj_tankan_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_releases.md),
  although a root or range index under that path is also accepted and
  may yield no assets. It is not a local filename or an arbitrary web
  page.

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
  default is 24 hours.

- timeout:

  Non-negative per-request timeout in seconds. The default is 30
  seconds.

- retries:

  Non-negative integer number of retries for transient transport
  responses or errors. The default is `3L`.

- wait:

  Non-negative seconds between requests and retries. The default is one
  second; waiting is skipped for cached responses and offline reads.

- max_bytes:

  Positive maximum response size in bytes. The default is `8 * 1024^2`
  (8 MiB), and protects the HTML snapshot before parsing.

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A base `data.frame` with no row names and exactly the character columns
`id`, `label`, and `url`. `id` is the XLS/XLSX/ZIP basename without a
query or fragment, `label` is the published link text, and `url` is the
absolute asset URL. Duplicate rows with the same URL are removed.
`readboj_provenance()` records the page snapshot and the exact
`release_url` used for discovery.

## Details

Only URLs ending in `.xls`, `.xlsx`, or `.zip` are retained; notices,
PDFs, and other links are deliberately excluded. The release page is
fetched over HTTPS from `www.boj.or.jp`, with successful response bytes
cached under `cache_dir`. `offline = TRUE` requires a valid page
snapshot and makes no network request. This function does not download
the listed assets.

Invalid or non-official `release_url` values, a missing/changed page,
transport or HTTP/rate-limit/authentication failures, stale offline
data, or parameter/size/deadline violations produce typed readboj
errors.

## See also

[`list_boj_tankan_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_releases.md),
[`download_boj_tankan_asset()`](https://chartwell-macro.github.io/readboj/reference/download_boj_tankan_asset.md),
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md),
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
    head(assets)
  }
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
