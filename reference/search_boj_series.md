# Search Bank of Japan metadata with bounded output

Searches the official BOJ metadata CSV for text in the selected name,
category, notes and series-code fields. The cached file is scanned in
chunks, so even the large Tankan catalogue is not materialised as one
in-memory object. At most `limit` matching rows are retained. Use
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md)
when the complete bounded metadata table is required.

## Usage

``` r
search_boj_series(
  query,
  db,
  language = "both",
  regex = FALSE,
  limit = 100L,
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 60,
  retries = 3L,
  wait = 1,
  max_bytes = 128 * 1024^2,
  include_groups = FALSE,
  deadline = NULL
)
```

## Arguments

- query:

  One non-empty character string. It is matched against the series code
  and the selected language's name, category and notes fields.

- db:

  A BOJ database identifier, such as `"FM08"`. It is converted to
  uppercase after validation; an identifier with a syntactically valid
  shape can still be rejected by the BOJ API if that database is not
  available.

- language:

  Output language: `"both"`, `"en"`, or `"jp"`. `"both"` retains paired
  Japanese and English text fields; `"en"` and `"jp"` retain only the
  requested language's name, unit, category and notes.

- regex:

  Logical flag. If `FALSE` (the default), `query` is literal and fixed;
  if `TRUE`, it is a case-insensitive Perl-compatible regular
  expression. Invalid expressions raise `readboj_parameter_error` before
  downloading the metadata.

- limit:

  Positive whole-number maximum matching rows retained and returned. The
  default is 100; it is a bound, not a request to materialise the full
  source catalogue.

- cache_dir:

  Character path to the snapshot cache. The default is
  `boj_cache_dir()`, which uses the `readboj.cache_dir` option or
  `tools::R_user_dir("readboj", "cache")`. Missing cache subdirectories
  are created as needed.

- refresh:

  Logical flag. When `TRUE`, bypasses a current cached request snapshot
  and obtains a fresh response. It is validated even when
  `offline = TRUE`.

- offline:

  Logical flag. When `TRUE`, requires a valid cached snapshot and makes
  no network request. It is useful for deterministic replay.

- max_age:

  Non-negative number of seconds for which a cached snapshot is
  considered current; `Inf` permits any age. The default is 24 hours.

- timeout:

  Non-negative per-request timeout in seconds. The default for metadata
  requests is 60 seconds.

- retries:

  Non-negative whole number of retries for transient transport or HTTP
  failures. The default is 3; non-transient failures are not retried.

- wait:

  Non-negative number of seconds used between pages, code batches and
  retries. It is skipped for offline reads and is bounded by `deadline`.

- max_bytes:

  Positive maximum decompressed response bytes per page. The default is
  128 MiB; oversized responses fail with `readboj_size_error` before
  parsing or caching.

- include_groups:

  Logical scalar. `TRUE` retains hierarchy heading rows without a series
  code; `FALSE` (the default) excludes them.

- deadline:

  An optional absolute `POSIXct`/`POSIXlt` deadline shared by the
  metadata download, retries and delays. A bounded default is created
  when omitted.

## Value

A base `data.frame` in source order, with at most `limit` rows, row
names reset, `stringsAsFactors = FALSE`, and a `readboj_provenance`
attribute. Its columns and types are the same as
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md)
after `language` filtering: `db`, `series_code`, the retained language
name/unit/category/notes fields, `frequency`, integer `layer1`–`layer5`,
character `start_time`/`end_time`, `Date` `last_update`, and logical
`is_series`. Empty results retain the corresponding zero-row schema.
Provenance additionally records `query`, `result_limit`,
`scan = "chunked"`, source/cache identity, transfer encoding, BOJ
date/message ID, parser schema and package version.

## Details

Literal searches are case-insensitive and use fixed matching. With
`regex = TRUE`, `query` is interpreted as a Perl-compatible regular
expression and matching remains case-insensitive. In `language = "en"`
or `"jp"`, only fields in that language plus `series_code` are searched;
with `language = "both"`, both language versions are searched. Group
headings are excluded by default and can be included with
`include_groups = TRUE`. Rows are retained in source order until `limit`
is reached; no result rows are deduplicated.

The metadata response is fetched over HTTPS and cached using the same
content-addressed snapshot, offline, retry, timeout, and
absolute-deadline rules as
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md).
`CO` remains subject to the same large-catalogue guard only when using
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md);
this chunked search is the intended bounded discovery path.

## Errors and side effects

Invalid arguments, invalid regular expressions, malformed or changed CSV
schemas, row limits, API/transport failures and unavailable offline
snapshots raise typed `readboj_*_error` conditions. The function may
access the network and create cache files below `cache_dir`; it does not
write search results to the working directory.

## Examples

``` r
# The fixture shows the same bilingual schema without network access.
metadata_path <- system.file(
  "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
)
metadata <- read_boj_snapshot(
  metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
)
metadata[grepl("monthly", metadata$name_en, fixed = TRUE),
  c("series_code", "name_en", "is_series")]
#>   series_code                 name_en is_series
#> 2    SYNTHM01 Synthetic monthly index      TRUE
#> 3    SYNTHM02  Synthetic monthly rate      TRUE

if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  search_boj_series(
    "exchange", db = "FM08", language = "en", limit = 10L,
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.
```
