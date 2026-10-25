# Read a downloaded official Bank of Japan bulk ZIP or CSV

Parses a local bulk response or a `boj_file` from
[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md).
Headerless four-column Flow-of-Funds/Tankan long files and named wide
CSV matrices are accepted. ZIP traversal, entry count, uncompressed
size, individual member size, and CSV row count are bounded before the
result is retained in memory.

## Usage

``` r
read_boj_bulk(
  path,
  encoding = "UTF-8",
  max_entries = 1000L,
  max_uncompressed_bytes = 1024^3,
  max_member_bytes = 512 * 1024^2,
  max_rows = 2000000L
)
```

## Arguments

- path:

  A local regular ZIP/CSV path, or the length-one `boj_file` returned by
  [`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md).
  The file is read as bytes to detect a ZIP signature; its filename
  extension is not trusted.

- encoding:

  Character encoding passed to
  [`readr::read_csv()`](https://readr.tidyverse.org/reference/read_delim.html)
  for CSV text, such as `"UTF-8"` or `"CP932"`. It must name an encoding
  supported by the local R installation.

- max_entries:

  Positive integer maximum number of ZIP members. The default is
  `1000L`.

- max_uncompressed_bytes:

  Positive maximum total uncompressed ZIP member bytes. The default is
  `1024^3` (1 GiB).

- max_member_bytes:

  Positive maximum uncompressed bytes for one ZIP member. The default is
  `512 * 1024^2` (512 MiB).

- max_rows:

  Positive integer maximum rows retained from each CSV. The default is
  `2000000L`; one extra row is read to detect an over-limit file.

## Value

For a CSV, a base `data.frame` whose columns are the parsed CSV columns
and whose values are read as character. A headerless four-column file is
named `series_code`, `frequency`, `period`, and `value`, then gets
`value_numeric` (numeric conversion, with non-numeric values as `NA`)
and `value_status` (the original `""`, `"NA"`, or `"ND"` marker,
otherwise `"observed"`). For a ZIP containing one CSV, the same data
frame is returned with a `source_file` column. For a ZIP containing
multiple CSVs, a named list of those data frames is returned with
classes `c("boj_bulk", "list")`; names are the archive member paths and
each table has its `source_file`. Every result has a
`readboj_provenance()` attribute with the source hash/bytes, parser name
and schema, encoding, and, for ZIPs, selected member names and total
uncompressed bytes.

## Details

This is an offline local parser: it makes no network request and does
not update the readboj cache. ZIP members must be regular safe paths;
absolute paths, drive-letter paths, and `..` traversal are rejected.
Only `.csv` members are extracted, into a temporary directory removed on
exit; non-CSV ZIP members are ignored. The parser preserves text
identifiers, labels, units, and suppression markers rather than guessing
numeric types.

Missing or non-regular paths, unsupported parameters, unsafe archive
paths, absent CSV members, and configured size/row bounds are checked by
the package and produce typed readboj errors where applicable. Low-level
malformed ZIP/CSV input or unsupported encoding may instead retain a
base-R or dependency error or warning. A ZIP with no CSV members is
rejected. This function does not infer a common schema across files or
reconcile publication revisions.

## See also

[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md),
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
local({
  csv <- tempfile(fileext = ".csv")
  on.exit(unlink(csv), add = TRUE)
  writeLines(c(
    "series_code,frequency,period,value",
    "SYNTHM01,MONTHLY,202601,101.5",
    "SYNTHM01,MONTHLY,202602,NA"
  ), csv)
  parsed <- read_boj_bulk(csv, max_rows = 10L)
  parsed[c("series_code", "period", "value_numeric", "value_status")]
})
#>   series_code period value_numeric value_status
#> 1    SYNTHM01 202601         101.5     observed
#> 2    SYNTHM01 202602            NA           NA
```
