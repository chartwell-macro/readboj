# Getting started with readboj

`readboj` is an R client for official Bank of Japan (BOJ) statistics. It
is designed for workflows where the source response, parser schema, and
retrieval identity matter as much as the resulting values. The package
can read exact API series, search metadata, inspect official bulk files,
and discover dated Tankan comprehensive-data releases.

This article takes the shortest path to a useful result. Its default
build combines a verified rendering made from an official API response
with small synthetic fixtures that exercise the public parsers. Network
retrieval remains an explicit opt-in, so vignette and CRAN builds stay
deterministic and offline.

## Load the package and discover databases

``` r

databases <- boj_databases()
databases[c(1L, 12L, 40L), c("db", "category_en", "name_en")]
#>      db                          category_en
#> 1  IR01 Interest Rates on Deposits and Loans
#> 12 FM08                    Financial Markets
#> 40   CO                               TANKAN
#>                                          name_en
#> 1  The Basic Discount Rates and Basic Loan Rates
#> 12                        Foreign Exchange Rates
#> 40                                        TANKAN
```

[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md)
is a local, revisioned registry. Its `db` values are the identities
accepted by the API; the bilingual names and category are useful for
presenting a choice to a user. The returned data frame also has
provenance, including the BOJ API-manual URL and source hash:

``` r

db_provenance <- boj_provenance(databases)
db_provenance[c("source", "source_url", "manual_revision", "database_count")]
#> $source
#> [1] "Bank of Japan Time-Series Data Search API Manual"
#> 
#> $source_url
#> [1] "https://www.stat-search.boj.or.jp/info/api_manual_en.pdf"
#> 
#> $manual_revision
#> [1] "2026-02-18"
#> 
#> $database_count
#> [1] 50
```

## Retrieve and chart a time series

The following workflow searches official metadata, selects the exact
monthly exchange-rate series `FM08/FXERM07`, retrieves a closed 2025
period, keeps valid `date` and `value` rows, and charts the result. Set
`READBOJ_LIVE_EXAMPLES=true` to execute the bounded network path. The
default article build displays the checked-in rendering made from the
verified response recorded in `inst/NOTICE/boj-chart-source.txt`.

``` r

cache <- file.path(tempdir(), "readboj-chart-cache")
matches <- search_boj_series(
  query = "FXERM07", db = "FM08", language = "en", limit = 10L,
  cache_dir = cache, deadline = Sys.time() + 90
)
selected <- matches[matches$series_code == "FXERM07", , drop = FALSE]
stopifnot(nrow(selected) == 1L)

series <- read_boj_series(
  db = selected$db[[1]], code = selected$series_code[[1]],
  start_date = "202501", end_date = "202512", language = "en",
  cache_dir = cache, deadline = Sys.time() + 90
)
chart_data <- series[
  !is.na(series$date) & is.finite(series$value),
  c("date", "value")
]
stopifnot(nrow(chart_data) > 1L)
```

``` r

if (requireNamespace("ggplot2", quietly = TRUE)) {
  ggplot2::ggplot(
    chart_data,
    ggplot2::aes(x = date, y = value)
  ) +
    ggplot2::geom_line() +
    ggplot2::labs(
      title = "Yen per U.S. dollar in 2025",
      subtitle = "Monthly published observations",
      x = "Month",
      y = "Yen per U.S. dollar",
      caption = "Source: Bank of Japan Time-Series Data Search API"
    ) +
    ggplot2::theme_minimal(base_size = 13)
}
```

![Line chart of the monthly yen per U.S. dollar spot rate during 2025,
falling through April and rising through
December.](../reference/figures/readboj-fxerm07-2025.png)

The rendered series is *US.Dollar/Yen Spot Rate at 17:00 in JST, Average
in the Month, Tokyo Market*, measured in yen per U.S. dollar. The chart
is a readboj documentation illustration rather than an official BoJ
chart or a bundled raw-data snapshot. Use `boj_provenance(series)` after
a live run to retain the response URL, retrieval time, hashes, and query
identity.

## Parse and inspect a saved response

For a completely reproducible first success, parse an exact local
response body with
[`read_boj_snapshot()`](https://chartwell-macro.github.io/readboj/reference/read_boj_snapshot.md).
This is the same normalised observation schema used by the API reader,
without a live request:

``` r

observations <- read_boj_snapshot(
  fixture_file("api-data-page-1.json"),
  type = "data_json",
  db = "FM08"
)
observations[, c(
  "db", "series_code", "frequency", "period", "date",
  "value", "raw_value", "value_status"
)]
#>     db series_code frequency period       date  value raw_value value_status
#> 1 FM08    SYNTHM01   MONTHLY 202601 2026-01-01 101.25    101.25     observed
#> 2 FM08    SYNTHM01   MONTHLY 202602 2026-02-01     NA      <NA>         null
#> 3 FM08    SYNTHM01   MONTHLY 202603 2026-03-01 103.75    103.75     observed
```

The observation table keeps both the official period code and a parsed
`Date`. `value` is numeric where a value is present; a JSON `null`
remains an `NA_real_`, and `value_status` records that it was `"null"`.
The `raw_value` column is retained so a downstream transformation can
distinguish a missing source value from a value that was never returned.

The result is an ordinary data frame with stable columns and a
provenance attribute. Use
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)
whenever a result is saved, joined, or reported:

``` r

observation_provenance <- boj_provenance(observations)
observation_provenance[c(
  "source", "raw_sha256", "semantic_sha256", "bytes",
  "parser_schema"
)]
#> $source
#> [1] "local response snapshot"
#> 
#> $raw_sha256
#> [1] "d40035a4d0847d5f9162f98468577f6dbec67545e032955b36d0aea8ac1ad3f3"
#> 
#> $semantic_sha256
#> [1] "c376b8ec04648c05b0ab73f2d400b36e21d52f29c92e9d693cceb6119d2e65c9"
#> 
#> $bytes
#> [1] 484
#> 
#> $parser_schema
#> [1] "1"
basename(observation_provenance$path)
#> [1] "api-data-page-1.json"
```

The raw SHA-256 identifies the exact response bytes. For JSON, the
semantic hash is stable when only the volatile API `DATE` changes. This
gives a small but useful audit trail even for a local fixture.

## Reuse connected results offline

The retrieval shown in the chart workflow writes successful responses to
its bounded `cache_dir`. Repeating the same
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md)
call with `offline = TRUE` replays a matching current snapshot without a
network request. Requests use HTTPS and official BoJ hosts, and the
public API requires no BoJ credentials. Typed `readboj_*` conditions
distinguish unavailable sources, transport failures, invalid responses,
and configured resource bounds.

For prescribed service wording and BOJ terms links, use:

``` r

credit <- boj_api_credit()
credit[c("credit", "api_notice", "copyright", "service_release_contact")]
#> $credit
#> [1] "This service uses the API provided by the \"Bank of Japan Time-Series Data Search.\" The Bank of Japan does not guarantee the content of the service."
#> 
#> $api_notice
#> [1] "https://www.stat-search.boj.or.jp/info/api_notice_en.pdf"
#> 
#> $copyright
#> [1] "https://www.boj.or.jp/en/about/copyright.htm"
#> 
#> $service_release_contact
#> [1] "post.rsd17@boj.or.jp"
```

The package handles parsing and source identity; users remain
responsible for the BOJ service credit, release notification, and any
downstream use of live data.

## Where to go next

- [API
  workflows](https://chartwell-macro.github.io/readboj/articles/api-workflows.md)
  compares exact-series and hierarchy reads and shows bilingual CSV
  parsing.
- [Official
  files](https://chartwell-macro.github.io/readboj/articles/official-files.md)
  covers bulk ZIP/CSV and workbook readers, plus the live catalogue and
  Tankan discovery path.
- [Reproducibility](https://chartwell-macro.github.io/readboj/articles/reproducibility.md)
  explains cache directories, provenance, and portable catalogue
  snapshots.
- [Troubleshooting](https://chartwell-macro.github.io/readboj/articles/troubleshooting.md)
  shows how to recognise typed errors, missing-value markers, and
  resource limits.
