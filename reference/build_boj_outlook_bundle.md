# Rebuild a portable Outlook data bundle from the complete raw archive

This maintenance route is independent of the saved bundle. It discovers
and parses all editions, retrieves every linked asset for the source
manifest, validates the complete result, and writes a compact RDS
atomically. It never activates or installs the bundle. Raw documents
stay in the separately bounded source cache and are not embedded in the
output.

## Usage

``` r
build_boj_outlook_bundle(
  path,
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = Inf,
  timeout = 30,
  retries = 2L,
  wait = 0.1,
  max_bytes = 16 * 1024^2,
  max_releases = 200L,
  max_pdf_pages = 20L,
  max_text_bytes = 1024^2,
  pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
  deadline = NULL
)
```

## Arguments

- path:

  Explicit output RDS path; the parent directory must exist.

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

Invisibly, the validated snapshot written to `path`.

## Examples

``` r
if (FALSE) { # \dontrun{
build_boj_outlook_bundle(
  tempfile(fileext = ".rds"), cache_dir = tempfile("outlook-build-"),
  deadline = Sys.time() + 1800
)
} # }
```
