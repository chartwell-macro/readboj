# Download an official Bank of Japan bulk file

Resolves a current catalogue file name or validates an exact official
`https://www.stat-search.boj.or.jp/` URL, then stores the response as a
content-addressed cache object. This function downloads bytes but does
not unpack or parse them; pass the result to
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md)
when it is a ZIP or CSV that should be inspected.

## Usage

``` r
download_boj_bulk(
  id,
  language = "en",
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 60,
  retries = 3L,
  wait = 1,
  max_bytes = 512 * 1024^2,
  deadline = NULL
)
```

## Arguments

- id:

  A non-empty catalogue `id` such as `"co.zip"`, or an exact HTTPS URL
  on the official `www.stat-search.boj.or.jp` host. A file name is
  looked up in the current catalogue; an exact URL bypasses catalogue
  lookup and is checked against the host allowlist.

- language:

  Catalogue language, one of `"en"` or `"jp"`, used when `id` is a file
  name. It is not used to rewrite an exact URL.

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

  Non-negative per-request timeout in seconds. The default for this file
  download is 60 seconds.

- retries:

  Non-negative integer number of retries for transient transport
  responses or errors. The default is `3L`.

- wait:

  Non-negative seconds between requests and retries. The default is one
  second; waiting is skipped for cached responses and offline reads.

- max_bytes:

  Positive maximum downloaded response bytes. The default is
  `512 * 1024^2` (512 MiB); this limit is applied before the response is
  placed in the cache.

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A length-one character vector with classes `c("boj_file", "character")`.
Its value is a regular local cache-object path. The
`readboj_provenance()` attribute contains the canonical and final URLs,
retrieval time, HTTP status and headers, byte count, and immutable raw
SHA-256 hash, together with cache and package/schema metadata.

## Details

The request uses HTTPS, follows only HTTPS redirects, and is restricted
to the official BOJ bulk host. Successful responses are kept under
`cache_dir` and subject to the package cache bounds; temporary response
files are removed after caching or failure. `offline = TRUE` permits a
valid cached response but never downloads a missing or stale file.
Downloading a mutable latest bulk file does not identify a historical
release beyond the response hash and recorded HTTP metadata.

Invalid file names, non-official URLs, cache corruption, rate limits,
authorization failures, transport errors, expired offline snapshots, or
a response above `max_bytes` produce a typed readboj error. A catalogue
lookup can also fail when the requested `id` is not unique in the
current page.

## See also

[`list_boj_bulk_files()`](https://chartwell-macro.github.io/readboj/reference/list_boj_bulk_files.md),
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  catalogue <- list_boj_bulk_files("en", max_age = 3600,
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
    deadline = Sys.time() + 30)
  ids <- catalogue$id[catalogue$role == "data_archive"]
  if (length(ids)) {
    archive <- download_boj_bulk(ids[[1L]],
      cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
      max_age = 3600, timeout = 10, retries = 0L, wait = 0,
      max_bytes = 64 * 1024^2, deadline = Sys.time() + 45)
    print(archive)
  }
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
