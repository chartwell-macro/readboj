# List the current Bank of Japan bulk-file catalogue

Retrieves the official flat-file catalogue for the English or Japanese
Bank of Japan (BOJ) statistics site and extracts links ending in `.zip`,
`.csv`, `.xls`, or `.xlsx`. The catalogue is a selected bulk-download
route; it is not a complete listing of the 50 API databases and it does
not provide historical vintages of files that the BOJ no longer
publishes.

## Usage

``` r
list_boj_bulk_files(
  language = "en",
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

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A base `data.frame` with no row names and exactly these columns: `id`,
`label`, `language`, `role`, and `url`. All columns are character; `id`
is the final URL basename without a query or fragment, `label` is the
link text, `language` repeats the selected catalogue language, `role` is
`"metadata_catalogue"` for `PRList.xlsx`/`FOFList.xlsx` and
`"data_archive"` otherwise, and `url` is the absolute link. The object
has a `readboj_provenance()` attribute containing the canonical/final
URL, retrieval time, HTTP status and headers, raw SHA-256, byte count,
cache status/path, and parser/package schema metadata.

## Details

The catalogue is fetched over HTTPS from the allowlisted
`www.stat-search.boj.or.jp` host. Successful responses are retained in
the bounded readboj cache; no response is cached when the request fails.
The HTML parser keeps link labels and URLs as published and does not
download the linked files.

Invalid parameters, an expired offline snapshot, an unavailable source,
an HTTP/rate-limit/authentication failure, a changed HTML schema, or a
response exceeding `max_bytes` produces a typed readboj error. A source
catalogue change can therefore require caller review rather than
silently changing the interpretation of a link.

## See also

[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md),
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  catalogue <- list_boj_bulk_files("en", max_age = 3600,
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
    deadline = Sys.time() + 30)
  head(catalogue[c("id", "role", "url")])
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
