# Read Bank of Japan observations for a hierarchy layer

Fetches the observations selected by the official BOJ Time-Series Data
Search `getDataLayer` route. A layer is one to five hierarchy values,
with `*` selecting all values at a level. Every `NEXTPOSITION` cursor is
followed and the returned observations use the same schema as
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md).
Use
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md)
when the desired series codes are already known.

## Usage

``` r
read_boj_layer(
  db,
  frequency,
  layer,
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
  max_series = 1250L,
  deadline = NULL
)
```

## Arguments

- db:

  A BOJ database identifier, such as `"FM08"`; it is normalized to
  uppercase and may still be rejected by the API if unknown.

- frequency:

  Observation frequency code: `"CY"`, `"FY"`, `"CH"`, `"FH"`, `"Q"`,
  `"M"`, `"W"`, or `"D"`. Matching is case-insensitive.

- layer:

  One to five comma-separated non-negative integer hierarchy values, or
  `*` as a wildcard at a level. A numeric vector is collapsed with
  commas; an empty value, more than five values, or any other character
  raises `readboj_parameter_error`.

- start_date:

  Optional inclusive `YYYY` or `YYYYPP` period bound; `NULL` omits it
  from the request.

- end_date:

  Optional inclusive `YYYY` or `YYYYPP` period bound; `NULL` omits it.
  If both bounds are supplied, `start_date` must not be later.

- language:

  Response language, exactly `"en"` or `"jp"`.

- format:

  Response format, `"json"` or `"csv"`; matching is case-insensitive.

- cache_dir:

  Character path to the content-addressed response cache; see
  [`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md)
  and `boj_cache_dir()`.

- refresh:

  Logical flag to bypass a current request snapshot.

- offline:

  Logical flag requiring a valid cached snapshot and disabling network
  access.

- max_age:

  Non-negative cache age in seconds, or `Inf`; the default is 24 hours.

- timeout:

  Non-negative per-attempt HTTP timeout in seconds; the default is 30
  seconds.

- retries:

  Non-negative whole-number transient-failure retry count; the default
  is 3.

- wait:

  Non-negative seconds between pages and retries; skipped offline.

- max_bytes:

  Positive decompressed response-byte bound per page; the default is 128
  MiB.

- max_pages:

  Positive whole-number page bound for this layer request; the default
  is 100.

- max_cells:

  Positive whole-number observation-row bound across all pages; the
  default is 1,000,000.

- max_series:

  Positive whole-number maximum distinct series allowed in the result;
  the default is 1,250.

- deadline:

  Optional absolute one-element `POSIXct`/`POSIXlt` deadline shared by
  all requests, retries and delays. A bounded default is created when
  omitted.

## Value

An ungrouped base `data.frame` with row names reset and the same exact
observation columns and types as
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md):
character `db`, `series_code`, `name_en`, `name_jp`, `unit_en`,
`unit_jp`, `frequency`, `category_en`, `category_jp`, and `period`;
`Date` `last_update` and `date`; numeric `value`; and character
`raw_value` and `value_status`, in that column order. A
`readboj_provenance` attribute records the layer query, page identities,
hashes, cache status, parser schema and package version. No duplicate
observation identity is collapsed.

## Details

`frequency` is normalized to uppercase and must be one of `CY`, `FY`,
`CH`, `FH`, `Q`, `M`, `W`, or `D`; `layer` values are non-negative
integers or `*`. A numeric `layer` vector is joined with commas before
validation. The request is bounded by `max_pages` and `max_cells`, then
fails with `readboj_size_error` if more than `max_series` distinct
series are returned; it is not silently truncated. Network, HTTPS-host,
cache, offline and deadline behavior is the same as
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md).

## Errors and side effects

Invalid parameters, malformed or changed BOJ responses, pagination
loops, duplicate identities, result bounds, transport failures and
unavailable offline snapshots raise typed `readboj_*_error` conditions.
The function may access the network and write only successful response
snapshots below `cache_dir`; it does not intentionally issue warnings.

## Examples

``` r
if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  read_boj_layer(
    db = "IR01", frequency = "D", layer = "*",
    start_date = "202607", end_date = "202607", format = "csv",
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 0L, wait = 0, max_bytes = 8 * 1024^2,
    max_pages = 2L, max_cells = 1000L, max_series = 100L
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run the live BOJ example.
```
