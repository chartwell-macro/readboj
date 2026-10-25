# Retrieve Bank of Japan series metadata

Retrieves and parses the official BOJ `getMetadata` CSV for one
database. The Japanese metadata route is the canonical bilingual source:
it carries both Japanese (`*_J`) and English fields. Use
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md)
for bounded discovery in a large catalogue, especially the Tankan `CO`
database, rather than eagerly materialising that database by default.

## Usage

``` r
boj_metadata(
  db,
  language = "both",
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 60,
  retries = 3L,
  wait = 1,
  max_bytes = 128 * 1024^2,
  max_rows = 50000L,
  allow_large = FALSE,
  include_groups = TRUE,
  deadline = NULL
)
```

## Arguments

- db:

  A BOJ database identifier, such as `"FM08"`. It is converted to
  uppercase after validation; an identifier with a syntactically valid
  shape can still be rejected by the BOJ API if that database is not
  available.

- language:

  Output language: `"both"`, `"en"`, or `"jp"`. `"both"` retains paired
  Japanese and English text fields; `"en"` and `"jp"` retain only the
  requested language's name, unit, category and notes.

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

- max_rows:

  Positive whole-number maximum metadata rows materialised, including
  hierarchy groups before `include_groups` filtering. The default is
  50,000; exceeding it raises `readboj_size_error`.

- allow_large:

  Logical flag. `TRUE` explicitly permits eager `CO` (Tankan)
  materialisation, subject to `max_rows`, byte, timeout and deadline
  bounds. The default is `FALSE`.

- include_groups:

  Logical flag. `TRUE` (the default) keeps hierarchy heading rows, which
  have an empty `series_code` and `is_series = FALSE`; `FALSE` filters
  them out after parsing.

- deadline:

  An optional absolute `POSIXct`/`POSIXlt` deadline shared by the
  metadata request, retries and delays. A bounded default is created
  when omitted.

## Value

A base `data.frame` in BOJ source order, with row names reset,
`stringsAsFactors = FALSE`, and a `readboj_provenance` attribute. For
`language = "both"`, columns are in this exact order: `db`,
`series_code`, `name_jp`, `name_en`, `unit_jp`, `unit_en`, `frequency`,
`category_jp`, `category_en`, `layer1`, `layer2`, `layer3`, `layer4`,
`layer5`, `start_time`, `end_time`, `last_update`, `notes_jp`,
`notes_en`, and `is_series`. The first two columns and all text fields
are character; `layer1`–`layer5` are integer; `last_update` is `Date`;
and `is_series` is logical. For `language = "en"`, the Japanese name,
unit, category and notes columns are removed; for `language = "jp"`, the
English counterparts are removed. Thus the retained language fields
preserve the corresponding column order from the bilingual schema.
`start_time` and `end_time` are source period labels as character.
Provenance records the canonical and final URLs, raw hash,
retrieval/cache identity, transfer encoding, BOJ date/message ID,
selected database and language, parser schema and package version.

## Details

`language = "both"` and `language = "jp"` request the Japanese CSV
(CP932) so that paired fields are available; `language = "en"` requests
the English CSV (UTF-8) and removes Japanese columns from the result.
Metadata is read in source order. With `include_groups = TRUE`,
hierarchy heading rows without a series code are retained and have
`is_series = FALSE`; setting it to `FALSE` retains only rows with a
non-empty series code.

A `CO` request is rejected before downloading unless
`allow_large = TRUE`. That opt-in does not remove the independent
`max_rows` materialisation bound. Responses are fetched over HTTPS from
the official BOJ host and successfully cached as content-addressed
snapshots. A current snapshot is reused unless `refresh = TRUE`;
`offline = TRUE` requires a valid matching snapshot and makes no network
request. See
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md)
for the common cache, retry, timeout, and deadline controls.

## Errors and side effects

Invalid parameters, an unavailable large database, malformed or changed
CSV schema, API errors, row limits, transport failures and missing
offline snapshots raise typed `readboj_*_error` conditions. The function
may perform network I/O and create cache files below `cache_dir`;
temporary files are cleaned up and no package startup download occurs.

## Examples

``` r
# This small installed fixture is synthetic and makes no network request.
metadata_path <- system.file(
  "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
)
metadata <- read_boj_snapshot(
  metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
)
metadata[c("series_code", "name_en", "name_jp", "is_series")]
#>   series_code                 name_en      name_jp is_series
#> 1                   Synthetic heading     合成階層     FALSE
#> 2    SYNTHM01 Synthetic monthly index 合成月次指数      TRUE
#> 3    SYNTHM02  Synthetic monthly rate 合成月次金利      TRUE

if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  boj_metadata(
    "FM08", language = "both", include_groups = FALSE,
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
    max_rows = 100L
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.
```
