# Discover all official Outlook Report editions

Reads both modern and legacy archive tables, including HTML Bank's Views
and legacy unlabeled full-text PDF links. One row is one official report
edition; the later full text is not a new forecast vintage. No dated
admission list or quarterly calendar is used. Pre-2016 interim
assessments are separate monetary policy statements and are not invented
as report editions.

## Usage

``` r
list_boj_outlook_releases_raw(
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 8 * 1024^2,
  max_releases = 200L,
  deadline = NULL
)
```

## Arguments

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

- deadline:

  Optional single absolute `POSIXct`/`POSIXlt` time shared by the
  request, retries, and waits. When omitted, a bounded deadline is
  derived from `timeout` and `retries`.

## Value

A data frame of edition month, Bank's View date/URL/format and full-text
date/URL. A legacy full-text date not stated by the archive is `NA`.

## See also

[`read_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_outlook.md)

## Examples

``` r
if (FALSE) { # \dontrun{
list_boj_outlook_releases_raw(cache_dir = tempfile("outlook-raw-"),
                              timeout = 10, retries = 0L,
                              deadline = Sys.time() + 30)
} # }
```
