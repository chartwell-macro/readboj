# Build a portable, hash-pinned Bank of Japan metadata catalogue snapshot

build_boj_catalogue_snapshot() retrieves the selected databases through
the official getMetadata CSV route, retains each exact response body,
inventories it in bounded chunks, and publishes a portable directory.
The directory has one content-addressed raw CSV under objects/ for each
database, plus manifest.rds and manifest.csv. The RDS manifest also
records the schema version, generation time, requested database order,
and whether all 50 databases in
[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md)
were selected. The raw files are the source material for
[`search_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/search_boj_catalogue_snapshot.md),
not observation data.

## Usage

``` r
build_boj_catalogue_snapshot(
  path,
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
  max_databases = 50L,
  max_rows_per_db = 250000L,
  max_total_bytes = 2 * 1024^3,
  overwrite = FALSE,
  deadline = NULL
)
```

## Arguments

- path:

  A non-empty character scalar naming the destination directory. The
  caller is responsible for choosing a writable, suitably sized
  location.

- db:

  A non-empty character vector of unique database identifiers. Values
  are upper-cased and must be present in
  [`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md);
  use boj_databases()\$db to request the complete declared surface.

- language:

  Metadata language: "both" (default), "en", or "jp". The bilingual
  Japanese CSV is used for "both" and "jp".

- cache_dir:

  Request-cache directory. The default is tools::R_user_dir("readboj",
  "cache"), subject to the readboj.cache_dir option.

- refresh:

  Logical scalar; if TRUE, ignore a current cache entry and retrieve
  each response again (unless offline = TRUE, in which case a missing
  refreshed response fails).

- offline:

  Logical scalar; require valid cached responses and prohibit network
  access.

- max_age:

  Maximum accepted cache age in seconds; Inf permits any age.

- timeout:

  Per-request timeout in seconds.

- retries:

  Number of retries for transient transport or HTTP failures.

- wait:

  Seconds between requests and retry attempts.

- max_bytes:

  Maximum decompressed response size for each metadata CSV.

- max_databases:

  Maximum number of selected databases (default 50).

- max_rows_per_db:

  Maximum metadata rows scanned for one database.

- max_total_bytes:

  Maximum sum of raw CSV bytes copied to the snapshot.

- overwrite:

  Logical scalar controlling replacement of existing manifests.

- deadline:

  Optional absolute POSIXct/POSIXlt deadline shared by every request,
  retry, and inter-request wait. When NULL, a bounded deadline is
  derived from the request count and timeout. Parser inventory is
  bounded by the row and byte limits but does not poll this deadline.

## Value

A data frame with one row per requested database, in the order of db,
and a readboj_provenance attribute. Columns are db, language,
canonical_url, retrieved_at, api_date, raw_sha256, bytes, row_count,
series_count, frequencies, start_time, end_time, dimensions,
last_update_field, relative_file, and complete_within_database.
Identifiers, URLs, dates, hashes, frequencies, paths, and field names
are character; bytes is numeric, row and series counts are integer, and
complete_within_database is logical. The provenance includes the
manifest path and SHA-256, generation time, total bytes, parser schema,
and whether the declared 50-database surface is complete.
boj_provenance() returns that attribute.

## Details

The request cache is used for each metadata response. With offline =
TRUE, every response must already be available as a valid, unexpired
cache entry; no network request is made. Otherwise requests use HTTPS
and the package's official Bank of Japan host allowlist, bounded
response sizes, retries, and a shared deadline. The function does not
require credentials and does not silently download at package load time.

The destination and its objects/ directory are created when needed. A
manifest is not replaced unless overwrite = TRUE; with overwrite
enabled, the two manifest files are atomically replaced, while
content-addressed raw objects are retained and are never replaced by
bytes with a different SHA-256. Existing unrelated files are not
removed. If a later database fails, files already copied to the
destination may remain; an incomplete directory is rejected by the
reader rather than treated as a valid snapshot.

## See also

[`search_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/search_boj_catalogue_snapshot.md),
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md),
[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md),
[`boj_cache_prune()`](https://chartwell-macro.github.io/readboj/reference/boj_cache_prune.md)

## Examples

``` r
# A build uses the official metadata service. This small live example is
# opt-in so package checks and offline documentation builds remain deterministic.
databases <- boj_databases()
stopifnot("FM08" %in% databases$db)
if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
  destination <- tempfile("readboj-catalogue-")
  manifest <- build_boj_catalogue_snapshot(
    destination, db = "FM08",
    cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
    timeout = 10, retries = 1L, wait = 0, max_bytes = 8 * 1024^2,
    max_databases = 1L, max_rows_per_db = 10000L,
    max_total_bytes = 64 * 1024^2, deadline = Sys.time() + 60)
  stopifnot(nrow(manifest) == 1L)
  search_boj_catalogue_snapshot(destination, "rate", db = "FM08")
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```
