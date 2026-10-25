# Read a bounded official BOJ XLS/XLSX workbook

Reads one or more sheets from a local Bank of Japan (BOJ) Excel workbook
as text-valued tables. Keeping every cell as text preserves official
identifiers, labels, units, and suppression markers. The exact source
workbook remains identified by SHA-256 provenance. This is a structural
reader: it does not infer a time-series schema from presentation tables,
evaluate a publication's definitions, or silently join survey breaks.

## Usage

``` r
read_boj_workbook(
  path,
  sheets = NULL,
  max_sheets = 100L,
  max_rows_per_sheet = 200000L,
  max_columns = 1000L,
  max_cells = 5000000L
)
```

## Arguments

- path:

  A local regular `.xls`/`.xlsx` workbook path, or the length-one
  `boj_file` returned by
  [`download_boj_tankan_asset()`](https://chartwell-macro.github.io/readboj/reference/download_boj_tankan_asset.md).
  The file is opened locally; this function does not download it or
  search the readboj cache.

- sheets:

  Optional non-empty character vector of unique exact sheet names. The
  default `NULL` reads every sheet in workbook order. Requested names
  must exist; no partial or fuzzy matching is performed.

- max_sheets:

  Positive integer maximum number of sheets in the workbook. The default
  is `100L`.

- max_rows_per_sheet:

  Positive integer maximum rows read from each selected sheet. The
  default is `200000L`; one extra row is read to detect an over-limit
  sheet.

- max_columns:

  Positive integer maximum columns in each selected sheet. The default
  is `1000L`.

- max_cells:

  Positive integer maximum aggregate cells retained across selected
  sheets. The default is `5000000L`.

## Value

A named base `list`, with one element per selected sheet in `sheets`
order (or workbook order from
[`readxl::excel_sheets()`](https://readxl.tidyverse.org/reference/excel_sheets.html)
when `sheets` is `NULL`). Each element is a base `data.frame` whose
column names are repaired to be unique by readxl and whose cells are
character values or `NA_character_`; no numeric or date conversion is
performed. The list has a `readboj_provenance()` attribute containing
the source path/hash and byte count (or the downloaded response
provenance), parser/schema and package versions, selected sheet names,
and aggregate `cells` count.

## Details

The workbook is inspected with `readxl` using `col_types = "text"`.
Sheet count is checked before reading, and row, column, and
aggregate-cell bounds are checked while reading. Formula results,
merged-cell layout, formatting, hidden sheets, and workbook-specific
semantic conventions are not normalised into a BOJ time-series schema;
use the returned raw tables and the publication documentation to
interpret them.

Reading is local and has no network or cache side effect. `readxl` may
use temporary resources internally, but readboj does not write to the
home or a global workspace. A missing/non-regular path, unreadable or
malformed workbook, absent/duplicated sheet selection, or any sheet/cell
bound violation produces a typed readboj error
(`readboj_parameter_error`, `readboj_archive_error`,
`readboj_identity_error`, or `readboj_size_error`).

## See also

[`download_boj_tankan_asset()`](https://chartwell-macro.github.io/readboj/reference/download_boj_tankan_asset.md),
[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md),
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
if (requireNamespace("writexl", quietly = TRUE)) {
  local({
    workbook <- tempfile(fileext = ".xlsx")
    on.exit(unlink(workbook), add = TRUE)
    writexl::write_xlsx(list(catalogue = data.frame(
      series_code = c("SYNTHM01", "SYNTHM02"),
      marker = c("ND", "NA"),
      stringsAsFactors = FALSE
    )), workbook)
    tables <- read_boj_workbook(workbook, max_rows_per_sheet = 10L,
      max_columns = 5L, max_cells = 50L)
    tables$catalogue[c("series_code", "marker")]
  })
}
#>   series_code marker
#> 1    SYNTHM01     ND
#> 2    SYNTHM02     NA
```
