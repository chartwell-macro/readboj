# Read published Outlook forecast tables for any official edition

Discovers dated HTML/PDF editions and derives measure headers, fiscal
targets, current/prior publication, actuals and available statistics
from their source tables and notes. There is no release whitelist.
`latest` resolves the actual newest archive edition; `all` reads every
edition under one bounded deadline.

## Usage

``` r
read_boj_outlook_raw(
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
  deadline = NULL
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

## Value

A long data frame of published scalars and explicit not-applicable
cells, retaining measure/statistic/status, fiscal dates,
comparison/vintage, raw cells, exact HTML XPath or PDF bounding boxes,
source hashes and table identities. All-edition provenance has a
separate receipt per edition.

## Details

Majority ranges and all-member ranges are distinct member dispersion,
not confidence intervals. Medians are returned only when actually
printed. Legacy WPI/CGPI, perishables CPI and tax/education-adjusted CPI
retain separate IDs. Explicit actuals and conditional estimates are
distinguished. Fiscal periods run April through March. Images/symbols
are never used to estimate values.

## See also

[`list_boj_outlook_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_outlook_releases.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
if (FALSE) { # \dontrun{
read_boj_outlook_raw("latest", cache_dir = tempfile("outlook-raw-"),
                     deadline = Sys.time() + 300)
} # }
```
