# readboj

`readboj` is an auditable R client for the official Bank of Japan (BoJ)
statistical surfaces. It covers the 2026 Time-Series Data Search API, selected
official bulk ZIP files, and dated Tankan comprehensive-data assets. It does
not use an aggregator fallback.

The package preserves exact raw response/file bytes in a content-addressed
cache. Every returned object has `readboj_provenance`, including the canonical
request URL, retrieval time, raw SHA-256, byte count, response identity, parser
version and (for API JSON) a semantic hash excluding the volatile response
`DATE`. Network operations have explicit time, retry, page, byte, cell, row and
cache bounds and support offline replay. The content-addressed cache is bounded
by default to 2 GiB and 1,000 objects; these can be tightened with
`options(readboj.cache_max_bytes = ..., readboj.cache_max_entries = ...)`.

```r
library(readboj)

search_boj_series("US Dollar", db = "FM08", language = "both")

fx <- read_boj_series(
  db = "FM08", code = "FXERM07",
  start_date = "202601", end_date = "202606"
)
boj_provenance(fx)

# Build a portable pinned metadata snapshot (one DB shown; all 50 supported)
snapshot <- build_boj_catalogue_snapshot(
  tempfile(), db = "FM08", language = "both"
)
search_boj_catalogue_snapshot(boj_provenance(snapshot)$snapshot_path, "ドル")
```

Tankan metadata is very large. `search_boj_series()` scans the cached CP932
CSV in chunks and returns at most `limit` matches. `boj_metadata("CO")` refuses
eager materialisation unless `allow_large = TRUE` is explicit.

Both official JSON and CSV code/layer responses are supported. Japanese CSV is
decoded as CP932. API nulls and CSV blanks remain explicit rows with
`raw_value` and `value_status`; bulk `NA`/`ND` markers remain literal strings.
No duplicate observation identity is collapsed.

## Scope and truthfulness

The API and normal bulk files are latest-history surfaces, not vintage APIs.
Local snapshots prove what this client retrieved at a time; they are not
described as official first releases. Dated Tankan workbooks are retained as
official release-specific assets. Monetary Policy Meeting decisions are HTML
or PDF documents outside this statistical parser.

## Service credit and release terms

Run `boj_api_credit()` for the prescribed credit and current official terms
URLs. The BoJ API notice asks a service operator to notify the Bank when a
service using the API is released. Commercial or specially restricted reuse
may require permission under the general site copyright terms.

Live package tests are opt-in:

```sh
READBOJ_LIVE_TESTS=true Rscript -e 'testthat::test_local()'
```
