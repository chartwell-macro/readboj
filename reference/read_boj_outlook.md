# Read saved published Outlook forecast tables

The default reads structured local data, without HTTP, PDF reads or an
extractor, including on first use. Use
[`read_boj_outlook_raw()`](https://chartwell-macro.github.io/readboj/reference/read_boj_outlook_raw.md)
for general archive discovery and source parsing; no dated release
admission list exists. `refresh` reloads the saved dataset, and never
runs the updater.

## Usage

``` r
read_boj_outlook(
  release = "latest",
  comparison = "current",
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 16 * 1024^2,
  max_releases = 200L,
  max_pdf_pages = 20L,
  max_text_bytes = 1024^2,
  expected_sha256 = NULL,
  pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
  deadline = NULL,
  source = "saved",
  data_dir = boj_outlook_data_dir(),
  measure = NULL,
  statistic = NULL,
  range_scope = NULL
)
```

## Arguments

- release:

  One edition month (`YYYY-MM`), `"latest"`, or `"all"`.

- comparison:

  `"current"` (default), `"prior"`, or `"all"`.

- cache_dir:

  Directory used for content-addressed response snapshots. The default
  is `tools::R_user_dir("readboj", "cache")`; it is created when needed.
  Use a package-managed temporary directory in tests.

- refresh:

  Logical scalar. If `TRUE`, ignore an otherwise usable request snapshot
  and retrieve the catalogue again.

- offline:

  Logical scalar. If `TRUE`, make no network request and use a valid
  cached snapshot only; an absent or stale snapshot raises an
  `readboj_offline_error`.

- max_age:

  Non-negative cache age in seconds, or `Inf` for no age limit. The
  default is 24 hours.

- timeout:

  Non-negative per-request timeout in seconds. The default is 30
  seconds.

- retries:

  Non-negative integer number of retries for transient transport
  responses or errors. The default is `3L`.

- wait:

  Non-negative seconds between requests and retries. The default is one
  second; waiting is skipped for cached responses and offline reads.

- max_bytes:

  Positive maximum response size in bytes. The default is `8 * 1024^2`
  (8 MiB), and protects the HTML snapshot before parsing.

- max_releases:

  Maximum archive editions (1 through 1,000); excess fails instead of
  silently truncating discovery.

- max_pdf_pages:

  Maximum leading pages extracted (1 through 100).

- max_text_bytes:

  Maximum accepted layout text bytes. Coordinate XML is separately
  bounded to eight times this size. Checked after the bounded subprocess
  finishes; this is not a streaming disk quota.

- expected_sha256:

  Optional complete SHA-256 pin of the numeric source asset (HTML or
  PDF). For image-only HTML this is the linked full-text PDF. A single
  pin is invalid with `release = "all"`; pin individual editions.

- pdftotext:

  Optional provisioned Poppler executable. HTML tables need no
  extractor. PDF extraction raises `readboj_dependency_error` if
  unavailable; nothing is installed. Consults option
  `readboj.pdftotext`, then `Sys.which`.

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

- source:

  `"saved"` (default) or explicit raw source parsing.

- data_dir:

  Directory shared with
  [`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md).

- measure, statistic, range_scope:

  Optional vectors of exact semantic IDs. Unknown IDs raise a parameter
  error. `NULL` selects all IDs.

## Value

A long data frame preserving all published scalars, explicit NA cells,
fiscal and source identities, with edition and saved-snapshot
provenance.

## Examples

``` r
history <- read_boj_outlook("all", comparison = "all",
                            data_dir = tempfile("outlook-data-"))
#> Error: No valid saved Outlook dataset is available.
head(history[c("release", "fiscal_year", "measure", "statistic", "value")])
#> Error in history[c("release", "fiscal_year", "measure", "statistic", "value")]: object of type 'closure' is not subsettable
```
