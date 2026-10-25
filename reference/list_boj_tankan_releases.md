# List dated official Tankan comprehensive-data releases

Traverses the official Bank of Japan (BOJ) Tankan comprehensive-data
archive: the root index, the bounded range indexes from 2000 onward, and
the dated release-page links extracted from those indexes. These dated
releases are distinct from the latest revised long-run `CO` API database
and are the route to publication-specific workbook and ZIP assets.
Release pages are listed from the range indexes; they are not fetched
individually by this function.

## Usage

``` r
list_boj_tankan_releases(
  language = "en",
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 8 * 1024^2,
  max_pages = 10L,
  deadline = NULL
)
```

## Arguments

- language:

  Catalogue language: exactly `"en"` (English) or `"jp"` (Japanese). The
  returned `language` column uses the selected lower-case value.

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

- max_pages:

  Positive integer maximum number of range index pages to follow. The
  default is `10L`; the current archive is expected to expose six
  ranges.

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A base `data.frame` with no row names and exactly the character columns
`id`, `label`, `language`, `url`, and `range_url`. `id` is the dated
release-page basename without `.htm`, `label` is the published link
text, `language` is the selected lower-case archive language, `url` is
the absolute dated release-page URL extracted from a range index, and
`range_url` identifies that index. Duplicate release URLs are removed. A
`readboj_provenance()` list records the archive source, language, and
the snapshot provenance for the root and every followed range page.

## Details

Discovery uses HTTPS on `www.boj.or.jp` and may make one request for the
root plus one request per range index. Successful pages are cached under
`cache_dir`; `offline = TRUE` reads only valid cached pages. The six
range paths are an explicit coverage boundary, so releases outside the
archive's discovered 2000-onward indexes are not returned. `wait` is
applied between page requests when online and the one absolute
`deadline` bounds all pages, retries, and waits.

Invalid arguments, an unavailable or changed archive, no recognized
range index, more range pages than `max_pages`, stale/missing offline
snapshots, transport or HTTP/rate-limit/authentication failures, and
size/deadline violations produce typed readboj errors. The function
lists pages only; it does not download release assets.

## See also

[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md),
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
  head(releases[c("id", "language", "url", "range_url")])
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
