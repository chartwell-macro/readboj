# API workflows: exact series, layers, and bilingual responses

The BOJ Time-Series Data Search API offers two complementary discovery
patterns:

- [`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md)
  requests exact series codes and is the most controlled path for a
  known set of indicators.
- [`read_boj_layer()`](https://chartwell-macro.github.io/readboj/reference/read_boj_layer.md)
  requests a hierarchy layer and is useful when the series codes are not
  known in advance. Its `max_series`, `max_pages`, and `max_cells`
  arguments keep a broad query bounded.

Both readers return the same observation columns and attach provenance.
This article uses small synthetic response bodies shipped with
`readboj`; nothing below makes a network request unless the explicitly
marked opt-in blocks are enabled with `READBOJ_LIVE_EXAMPLES=true`.

## Exact series and period identity

An exact JSON response can be normalised locally with
[`read_boj_snapshot()`](https://chartwell-macro.github.io/readboj/reference/read_boj_snapshot.md).
The `period` column remains the BOJ period code, while `date` is the
first day of its parsed month (or the corresponding date for other
supported frequencies):

``` r

json_series <- read_boj_snapshot(
  fixture_file("api-data-page-1.json"),
  type = "data_json",
  db = "FM08"
)
json_series[, c("series_code", "period", "date", "value", "value_status")]
#>   series_code period       date  value value_status
#> 1    SYNTHM01 202601 2026-01-01 101.25     observed
#> 2    SYNTHM01 202602 2026-02-01     NA         null
#> 3    SYNTHM01 202603 2026-03-01 103.75     observed
```

The synthetic fixture contains a JSON `null`. `readboj` retains that
row, returns `NA` in `value`, and labels its `value_status` as `"null"`;
it does not silently drop or interpolate the observation.

The live equivalent is an exact-code request. `code` excludes the
database prefix and can contain multiple unique codes. Requests are
split at the official 250-code request limit, and API pagination cursors
are followed until the response is complete:

``` r

live <- identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")
if (live) {
  cache <- file.path(tempdir(), "readboj-api-cache")
  exact <- read_boj_series(
    db = "FM08",
    code = c("FXERM07", "STRDCLUCON"),
    start_date = "202601",
    end_date = "202606",
    language = "en",
    format = "json",
    cache_dir = cache,
    timeout = 10,
    retries = 0L,
    wait = 0,
    max_bytes = 8 * 1024^2,
    max_pages = 2L,
    max_cells = 2000L,
    max_codes_total = 2L,
    deadline = Sys.time() + 30
  )
  exact[, c("series_code", "period", "date", "value", "value_status")]
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```

## CSV responses and bilingual metadata

CSV is useful when a response must be retained in the API’s tabular
form. The English fixture demonstrates that blank CSV cells stay
distinguishable from JSON nulls:

``` r

csv_series <- read_boj_snapshot(
  fixture_file("api-data-en-page-1.csv"),
  type = "data_csv",
  db = "FM08",
  language = "en"
)
csv_series[, c("series_code", "period", "date", "value", "raw_value", "value_status")]
#>   series_code period       date  value raw_value value_status
#> 1    SYNTHM01 202601 2026-01-01 101.25    101.25     observed
#> 2    SYNTHM01 202602 2026-02-01     NA                  blank
#> 3    SYNTHM01 202603 2026-03-01 103.75    103.75     observed
```

For Japanese responses the API uses CP932. Metadata responses are
bilingual, so a local metadata snapshot can be parsed with an explicit
encoding and searched using the stable paired fields:

``` r

metadata <- read_boj_snapshot(
  fixture_file("metadata-bilingual-cp932.csv"),
  type = "metadata_csv",
  db = "FM08",
  encoding = "CP932"
)
metadata[metadata$is_series, c(
  "series_code", "name_en", "name_jp", "unit_en", "unit_jp",
  "frequency", "start_time", "end_time", "last_update"
)]
#>   series_code                 name_en      name_jp unit_en unit_jp frequency
#> 2    SYNTHM01 Synthetic monthly index 合成月次指数   Index    指数   MONTHLY
#> 3    SYNTHM02  Synthetic monthly rate 合成月次金利 Percent      ％   MONTHLY
#>   start_time end_time last_update
#> 2     202001   202612  2026-08-01
#> 3     202001   202612  2026-08-01
```

The metadata table keeps hierarchy headings (`is_series == FALSE`) when
the input includes them.
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md)
can return the same schema from a live API response, while
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md)
scans a cached CSV in chunks and retains at most `limit` matches. For
the very large `CO` database, use
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md)
rather than eager materialisation.

## Layer queries and safety bounds

Layer queries use a frequency such as `M` for monthly data and one to
five hierarchy values. A `*` wildcard selects the matching branch. This
is an opt-in live example because the shipped fixtures are exact-series
responses rather than layer responses:

``` r

live <- identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")
if (live) {
  layer <- read_boj_layer(
    db = "IR01",
    frequency = "D",
    layer = "*",
    start_date = "202607",
    end_date = "202607",
    format = "csv",
    cache_dir = file.path(tempdir(), "readboj-layer-cache"),
    timeout = 10,
    retries = 0L,
    wait = 0,
    max_bytes = 8 * 1024^2,
    max_pages = 2L,
    max_cells = 1000L,
    max_series = 100L,
    deadline = Sys.time() + 30
  )
  c(rows = nrow(layer), series = length(unique(layer$series_code)))
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```

Set `max_cells`, `max_pages`, and (for layers) `max_series` to a value
that matches the job’s memory and time budget. A request that would
exceed a bound fails with a typed size or pagination error; rows are not
truncated into an ambiguous partial result.

## Network, cache, and credentials

The API is public: `readboj` has no credential argument and does not
place secrets in request URLs. Live requests use HTTPS and the package’s
official BOJ host allowlist. Pass an explicit `cache_dir` when a
workflow should be portable or isolated from a user’s default
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) location.

Every network-facing API reader accepts `offline = TRUE`. In that mode
only a matching, unexpired cached response is used; a missing snapshot
raises a `readboj_offline_error` rather than attempting a fallback
network request. Successful responses carry raw and semantic hashes in
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md),
which lets a report record exactly which source body was parsed.
