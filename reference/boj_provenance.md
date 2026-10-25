# Extract readboj provenance

readboj attaches a readboj_provenance attribute to data frames, lists,
and downloaded file paths when the source identity can be retained. This
accessor returns that attribute without recomputing hashes or touching
the filesystem. It is therefore safe to use on an object after its
source file has moved, although the recorded path may no longer exist.

## Usage

``` r
boj_provenance(x)
```

## Arguments

- x:

  Any R object. Objects without the exact readboj_provenance attribute
  return NULL; x is not otherwise validated or modified.

## Value

The exact object stored in x's readboj_provenance attribute, normally a
named list, or NULL when that attribute is absent. No copy is normalized
and no class is added.

## Details

Provenance is a named list whose fields depend on the producer. API and
download results commonly include canonical_url, final_url,
retrieved_at, raw_sha256, bytes, HTTP headers, cache status and parser
schema; metadata, catalogue, and local-parser results may add database,
query, manifest, or source fields. The list is descriptive evidence, not
a live authorization check and not a guarantee that an external URL
remains available.

## See also

[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md),
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md),
[`read_boj_snapshot()`](https://chartwell-macro.github.io/readboj/reference/read_boj_snapshot.md),
[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md)

## Examples

``` r
databases <- boj_databases()
provenance <- boj_provenance(databases)
stopifnot(is.list(provenance), identical(provenance$database_count, 50L))
stopifnot(is.null(boj_provenance(list())))
```
