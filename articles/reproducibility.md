# Reproducible reads: provenance, cache, and portable snapshots

An API result is easier to audit when a report can answer three
questions: which source was requested, which bytes were parsed, and
which parser schema produced the table? `readboj` attaches that
information as provenance and keeps successful network responses in a
bounded content-addressed cache.

This article uses a shipped synthetic response so that every default
chunk is deterministic and offline. The fixture’s values are not
official BOJ data.

## Record exact response identity

Parsing a local response body is a useful way to certify a
transformation without relying on current network state:

``` r

path <- fixture_file("api-data-page-1.json")
result <- read_boj_snapshot(path, type = "data_json", db = "FM08")
provenance <- boj_provenance(result)
provenance[c(
  "source", "raw_sha256", "semantic_sha256", "bytes",
  "parser_schema", "package_version"
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
#> 
#> $package_version
#> [1] "0.2.0"
basename(provenance$path)
#> [1] "api-data-page-1.json"
```

`raw_sha256` identifies the exact bytes, including formatting. For JSON
and CSV responses, `semantic_sha256` is designed to ignore only the
volatile API retrieval date while retaining the data and response
structure. `bytes`, `parser_schema`, and `package_version` help explain
why a future reparse might not be identical.

The same input is deterministic across repeated parses:

``` r

again <- read_boj_snapshot(path, type = "data_json", db = "FM08")
identical(result, again)
#> [1] TRUE
identical(
  boj_provenance(result)[c("raw_sha256", "semantic_sha256")],
  boj_provenance(again)[c("raw_sha256", "semantic_sha256")]
)
#> [1] TRUE
```

Keep the data object and its provenance together when serialising a
result. The provenance attribute is part of the returned object and can
be extracted before writing a separate audit record.

## Use an explicit cache and offline replay

Live API, metadata, bulk, and Tankan readers accept `cache_dir`,
`max_age`, and `offline`. For a portable project, choose a
project-managed cache path explicitly and record it in the project
instructions rather than relying on a machine-specific default. A
successful response is stored under its raw hash; the request index
binds the canonical URL and query to that object.

``` r

cache_dir <- file.path(tempdir(), "readboj-repro-cache")
cache_summary <- boj_cache_prune(
  cache_dir = cache_dir,
  max_bytes = 10 * 1024^2,
  max_entries = 20L
)
cache_summary
#>   removed bytes_removed remaining remaining_bytes
#> 1       0             0         0               0
```

[`boj_cache_prune()`](https://chartwell-macro.github.io/readboj/reference/boj_cache_prune.md)
removes only readboj cache objects and matching request indexes.
Directories and unrelated files are left alone. The default cache limits
are bounded, and an explicit
[`boj_cache_prune()`](https://chartwell-macro.github.io/readboj/reference/boj_cache_prune.md)
call makes a smaller report-specific limit visible in a pipeline.

With a populated cache, the following pattern makes the network policy
explicit. It is opt-in because the package does not ship an official
cached response for this series:

``` r

live <- identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")
if (live) {
  live_result <- read_boj_series(
    db = "FM08",
    code = "FXERM07",
    start_date = "202601",
    end_date = "202606",
    cache_dir = cache_dir,
    timeout = 10,
    retries = 0L,
    wait = 0,
    max_bytes = 8 * 1024^2,
    max_pages = 2L,
    max_cells = 1000L,
    max_codes_total = 1L,
    deadline = Sys.time() + 30
  )
  replay <- read_boj_series(
    db = "FM08",
    code = "FXERM07",
    start_date = "202601",
    end_date = "202606",
    cache_dir = cache_dir,
    offline = TRUE,
    wait = 0,
    max_bytes = 8 * 1024^2,
    max_pages = 2L,
    max_cells = 1000L,
    max_codes_total = 1L,
    deadline = Sys.time() + 30
  )
  live_rows <- live_result
  replay_rows <- replay
  attr(live_rows, "readboj_provenance") <- NULL
  attr(replay_rows, "readboj_provenance") <- NULL
  identical(live_rows, replay_rows)
  identical(
    vapply(boj_provenance(live_result)$pages, `[[`, "", "raw_sha256"),
    vapply(boj_provenance(replay)$pages, `[[`, "", "raw_sha256")
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```

The row values and response hashes match, while provenance correctly
records the online fetch as a cache miss and the replay as a cache hit.
`offline = TRUE` never falls back to a network request. If the canonical
URL and query do not have a current matching snapshot, the call stops
with a `readboj_offline_error`. A stale snapshot can be deliberately
refreshed in a connected run by setting `refresh = TRUE`; failed
responses are not published as successful cache objects.

## Build a portable metadata catalogue

For a larger metadata job,
[`build_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/build_boj_catalogue_snapshot.md)
copies exact metadata response bodies into a portable directory and
writes hash-pinned RDS and CSV manifests.
[`search_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/search_boj_catalogue_snapshot.md)
then searches those objects fully offline. The complete workflow is
shown below as an optional opt-in example because building even one real
catalogue object requires an official network response:

``` r

live <- identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")
if (live) {
  catalogue_dir <- file.path(tempdir(), "readboj-catalogue")
  manifest <- build_boj_catalogue_snapshot(
    path = catalogue_dir,
    db = "FM08",
    language = "both",
    cache_dir = cache_dir,
    timeout = 10,
    retries = 0L,
    wait = 0,
    max_bytes = 8 * 1024^2,
    max_databases = 1L,
    max_rows_per_db = 10000L,
    max_total_bytes = 64 * 1024^2,
    deadline = Sys.time() + 60
  )
  manifest[, c("db", "raw_sha256", "row_count", "series_count")]

  search_boj_catalogue_snapshot(
    catalogue_dir, query = "FXERM", db = "FM08", limit = 10L
  )
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```

A catalogue snapshot is a bounded, declared surface rather than a claim
that the BOJ catalogue never changes. Preserve its manifest with the
report and cite the retrieval date and source hashes when results are
published.
