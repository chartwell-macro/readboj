# Read Bank of Japan observations for exact series codes

Fetches observations from the official Bank of Japan (BOJ) Time-Series
Data Search `getDataCode` route for one or more exact series codes.
Input codes are sent in batches of at most 250 (the API limit), and
every `NEXTPOSITION` cursor returned by the service is followed in
order. JSON `null` values and CSV blank values remain rows rather than
being dropped. Use
[`read_boj_snapshot()`](https://chartwell-macro.github.io/readboj/reference/read_boj_snapshot.md)
to parse a saved response without a network request, or
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)
to inspect the identity of responses used by this function.

## Usage

``` r
read_boj_series(
  db,
  code,
  start_date = NULL,
  end_date = NULL,
  language = "en",
  format = "json",
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 128 * 1024^2,
  max_pages = 100L,
  max_cells = 1000000L,
  max_codes_total = 5000L,
  deadline = NULL
)
```

## Arguments

- db:

  A BOJ database identifier, such as `"FM08"`. It is converted to
  uppercase after validation; an identifier with a syntactically valid
  shape can still be rejected by the BOJ API if that database is not
  available.

- code:

  A non-empty character vector of exact series codes without the
  database prefix. Values must be non-missing, non-empty and unique. The
  vector is limited by `max_codes_total` and split into API batches of
  250.

- start_date:

  Optional inclusive lower period bound as one `YYYY` or `YYYYPP` code.
  `NULL` omits the bound from the request.

- end_date:

  Optional inclusive upper period bound as one `YYYY` or `YYYYPP` code.
  `NULL` omits the bound; when both bounds are supplied, `start_date`
  must not be later than `end_date`.

- language:

  Response language: exactly `"en"` or `"jp"`. The value controls the
  language fields returned by BOJ and, for CSV responses, the transfer
  encoding.

- format:

  Official response format, `"json"` or `"csv"`; matching is
  case-insensitive. JSON responses are parsed as UTF-8, while Japanese
  CSV responses are decoded as CP932.

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

  Non-negative number of seconds allowed for each HTTP attempt. The
  default is 30 seconds; the call-wide `deadline` remains authoritative.

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

- max_pages:

  Positive whole-number maximum pages allowed for each code batch. The
  default is 100.

- max_cells:

  Positive whole-number maximum observation rows retained across all
  batches and pages. The default is 1,000,000.

- max_codes_total:

  Positive whole-number maximum number of input series codes. The
  default is 5,000; the official per-request 250-code batch limit is
  applied separately.

- deadline:

  An optional absolute one-element `POSIXct` or `POSIXlt` deadline
  shared by every batch, page, retry and delay. If `NULL`, a bounded
  deadline is derived from `timeout` and `retries` (at least five
  minutes). An expired deadline raises `readboj_timeout_error`.

## Value

An ungrouped base `data.frame` (`stringsAsFactors = FALSE`) with row
names reset and one row per returned observation. The columns are in
this exact order and have these types: `db`, `series_code`, `name_en`,
`name_jp`, `unit_en`, `unit_jp`, `frequency`, `category_en`, and
`category_jp` are character; `last_update` is `Date`; `period` is the
exact BOJ period code as character; `date` is `Date`; `value` is
numeric; `raw_value` is the source value as character; and
`value_status` is character. `date` is the first calendar date inferred
from `frequency` and `period`, and can be `NA` when the source code
cannot be mapped. JSON missing values have `value = NA`,
`raw_value = NA`, and `value_status = "null"`; CSV blank values have
`value = NA`, the original empty `raw_value`, and
`value_status = "blank"`. The returned object has a `readboj_provenance`
attribute;
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)
returns its list of source URL(s), retrieval/cache identity, hashes,
response metadata, query, page list, parser schema and package version.

## Details

Requests use HTTPS and are restricted to the official BOJ hosts.
Successful response bodies are retained as content-addressed snapshots
below `cache_dir`; a valid snapshot is reused while it is within
`max_age`, unless `refresh = TRUE`. With `offline = TRUE`, no network
request is attempted and the call fails with class
`readboj_offline_error` when a matching valid snapshot is unavailable.
Temporary response files are removed after a successful cache write or
an error.

Each code batch is paginated independently. The result is never silently
deduplicated: duplicate `db`/`series_code`/`period` identities cause a
`readboj_identity_error`. The page, cell, byte, retry and absolute
deadline bounds are enforced before unbounded work can occur. The API's
latest revised history is returned; this function does not provide
vintage or as-of retrieval.

## Errors and side effects

Invalid arguments, malformed responses, schema changes, pagination
loops, duplicate identities and size limits raise typed
`readboj_*_error` conditions. API and HTTP failures retain response
identity in the error where available. The function may perform network
I/O and create or update files below `cache_dir`; it does not write to
the current working directory or a global workspace. The default managed
cache is in the user-specific location returned by
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html).

## Examples

``` r
# The packaged response is a small synthetic fixture and is read offline.
json_path <- system.file("extdata", "api-data-page-1.json", package = "readboj")
local_data <- read_boj_snapshot(json_path, type = "data_json", db = "FM08")
local_data[c("series_code", "period", "value", "value_status")]
#>   series_code period  value value_status
#> 1    SYNTHM01 202601 101.25     observed
#> 2    SYNTHM01 202602     NA         null
#> 3    SYNTHM01 202603 103.75     observed

if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  read_boj_series(
    db = "FM08", code = "FXERM07",
    start_date = "202601", end_date = "202606",
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
    max_pages = 2L, max_cells = 1000L, max_codes_total = 1L
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.
```
