# List Bank of Japan API databases

Returns the package's static transcription of the 50 database
identifiers declared by the official Bank of Japan Time-Series Data
Search API manual, revision 2026-02-18. The registry is local and
deterministic: calling this function does not contact the Bank of Japan,
use the request cache, or write files. The manual URL, retrieval date,
SHA-256, and byte count are retained in provenance so callers can audit
which declared registry was packaged.

## Usage

``` r
boj_databases()
```

## Value

A 50-row data frame in the fixed manual order with character columns db
(database identifier), category_en (English category), name_en (English
database name), name_jp (Japanese database name), and manual_revision
(the scalar value "2026-02-18" in every row). The data frame has a
readboj_provenance attribute containing source, source_url,
source_sha256, source_bytes, source_retrieved_at, manual_revision,
complete_declared_surface (TRUE), and database_count (50L).

## Details

The registry describes API database identities and bilingual labels; it
is not a download of observations and does not assert that every
database is currently available. The labels and database facts follow
the official manual. The package also retains a third-party notice for
registry/API parsing design informed by bojapi; that notice does not
make its author a readboj author or change this package's MIT license.

## See also

[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md),
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md),
[`build_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/build_boj_catalogue_snapshot.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
databases <- boj_databases()
stopifnot(nrow(databases) == 50L)
stopifnot(identical(databases$db[[1L]], "IR01"))
stopifnot(identical(unique(databases$manual_revision), "2026-02-18"))
```
