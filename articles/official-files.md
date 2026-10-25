# Official files: bulk archives, workbooks, and Tankan releases

Not every BOJ dataset is best represented as a time-series API call. The
package also supports the official bulk-file catalogue and dated Tankan
comprehensive-data release pages. The workflow is intentionally
two-stage: discover an official URL, then download and parse the exact
file. The parser keeps source hashes and applies archive, row, sheet,
and cell bounds.

The default examples below are offline. The local CSV and workbook
created in this article contain synthetic values solely to exercise the
parsers; they are not BOJ releases.

## Read a bulk CSV with markers intact

[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md)
accepts a local CSV or the `boj_file` path returned by
[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md).
A headerless long file is interpreted as `series_code`, `frequency`,
`period`, and `value`. Values stay character in the source column, with
convenient numeric/status companions:

``` r

bulk_path <- tempfile("readboj-bulk-", fileext = ".csv")
writeLines(c(
  "SYNTHM01,MONTHLY,202601,101.5",
  "SYNTHM01,MONTHLY,202602,NA",
  "SYNTHM01,MONTHLY,202603,ND"
), bulk_path, useBytes = TRUE)

bulk_data <- read_boj_bulk(bulk_path, max_rows = 10L)
bulk_data[, c(
  "series_code", "frequency", "period", "value", "value_numeric",
  "value_status"
)]
#>   series_code frequency period value value_numeric value_status
#> 1    SYNTHM01   MONTHLY 202601 101.5         101.5     observed
#> 2    SYNTHM01   MONTHLY 202602    NA            NA           NA
#> 3    SYNTHM01   MONTHLY 202603    ND            NA           ND
invisible(unlink(bulk_path))
```

The original `value` markers (`"NA"` and `"ND"`) are not discarded.
Their `value_numeric` values are `NA`, and `value_status` identifies the
marker. For a ZIP archive, the same function validates entry paths and
aggregate uncompressed sizes before extracting CSV members. If one CSV
is present it returns a data frame; multiple CSVs are returned as a
named `boj_bulk` list.

## Read a bounded workbook as text

Official workbooks often contain identifiers, labels, suppression
markers, and presentation sheets rather than a tidy time-series table.
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md)
therefore reads selected sheets as text and does not silently coerce an
identifier or marker to a number. The following creates a tiny synthetic
workbook when the optional `writexl` package is available:

``` r

if (requireNamespace("writexl", quietly = TRUE)) {
  workbook_path <- tempfile("readboj-workbook-", fileext = ".xlsx")
  writexl::write_xlsx(list(catalogue = data.frame(
    series_code = c("SYNTHM01", "SYNTHM02"),
    unit = c("Index", "Percent"),
    marker = c("ND", "NA"),
    stringsAsFactors = FALSE
  )), workbook_path)

  workbook <- read_boj_workbook(
    workbook_path,
    sheets = "catalogue",
    max_rows_per_sheet = 10L,
    max_columns = 10L,
    max_cells = 100L
  )
  workbook$catalogue
  boj_provenance(workbook)[c("raw_sha256", "parser", "sheets", "cells")]
  invisible(unlink(workbook_path))
}
```

The result is a named list of data frames. Use the `sheets`,
`max_rows_per_sheet`, `max_columns`, and `max_cells` arguments to make a
report’s resource budget explicit. This reader is structural: it does
not infer a time-series schema or join survey breaks for you.

## Discover official bulk and Tankan files

The catalogue and Tankan functions use live official HTML pages, so they
are shown only in an explicitly opt-in block. They can be pointed at an
explicit cache directory and replayed later with `offline = TRUE`:

``` r

live <- identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")
if (live) {
  cache <- file.path(tempdir(), "readboj-file-cache")

  bulk_catalogue <- list_boj_bulk_files(
    language = "en", cache_dir = cache,
    timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
    deadline = Sys.time() + 30
  )
  archives <- bulk_catalogue[bulk_catalogue$role == "data_archive", , drop = FALSE]
  if (nrow(archives)) {
    bulk_file <- download_boj_bulk(
      archives$id[[1L]], language = "en", cache_dir = cache,
      timeout = 10, retries = 0L, wait = 0, max_bytes = 20 * 1024^2,
      deadline = Sys.time() + 45
    )
    bulk_result <- read_boj_bulk(
      bulk_file, max_uncompressed_bytes = 50 * 1024^2,
      max_rows = 100000L
    )
    boj_provenance(bulk_file)
  }

  releases <- list_boj_tankan_releases(
    language = "en", cache_dir = cache, max_pages = 6L,
    timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
    deadline = Sys.time() + 60
  )
  if (nrow(releases)) {
    assets <- list_boj_tankan_assets(
      releases$url[[1L]], cache_dir = cache,
      timeout = 10, retries = 0L, wait = 0, max_bytes = 2 * 1024^2,
      deadline = Sys.time() + 30
    )
    xlsx <- assets$url[grepl("\\.xlsx?$", assets$url, ignore.case = TRUE)]
    if (length(xlsx)) {
      tankan_file <- download_boj_tankan_asset(
        xlsx[[1L]], cache_dir = cache,
        timeout = 10, retries = 0L, wait = 0,
        max_bytes = 20 * 1024^2, deadline = Sys.time() + 45
      )
      boj_provenance(tankan_file)
    }
  }
} else {
  message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
}
#> Set READBOJ_LIVE_EXAMPLES=true to run this live example.
```

[`list_boj_bulk_files()`](https://chartwell-macro.github.io/readboj/reference/list_boj_bulk_files.md)
is selected current catalogue coverage, not a promise that every API
database has a bulk file.
[`list_boj_tankan_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_releases.md)
tracks dated comprehensive-data pages from the official archive, while
[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md)
admits only XLS/XLSX and ZIP links from a release page. PDF notices and
unrelated links are not treated as data assets.

No credentials are required or accepted. Network requests are HTTPS-only
and restricted to official BOJ hosts. Documented request, bound, and
schema failures use typed conditions, and an unsuccessful response is
not cached as a successful data object. Dependency errors from a
malformed third-party file may retain their original class and should be
reported with the file identity.
