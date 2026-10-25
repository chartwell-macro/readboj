# List saved Outlook editions without network access

Reads the package baseline or newest valid local refresh. The structured
dataset is reused across selections. `refresh` reloads saved data only.
Transport arguments apply only to explicit `source = "raw"` discovery.

## Usage

``` r
list_boj_outlook_releases(
  cache_dir = boj_cache_dir(),
  refresh = FALSE,
  offline = FALSE,
  max_age = 24 * 60 * 60,
  timeout = 30,
  retries = 3L,
  wait = 1,
  max_bytes = 8 * 1024^2,
  max_releases = 200L,
  deadline = NULL,
  source = "saved",
  data_dir = boj_outlook_data_dir()
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

- source:

  `"saved"` (default) or explicit raw archive discovery.

- data_dir:

  Directory shared with
  [`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md).

## Value

Edition catalogue with saved-data and discovery provenance.

## Examples

``` r
editions <- list_boj_outlook_releases(data_dir = tempfile("outlook-data-"))
head(editions)
#>   release publication_date                                     banks_view_url
#> 1 2026-07       2026-07-31 https://www.boj.or.jp/en/mopo/outlook/gor2607a.pdf
#> 2 2026-04       2026-04-28 https://www.boj.or.jp/en/mopo/outlook/gor2604a.pdf
#> 3 2026-01       2026-01-23 https://www.boj.or.jp/en/mopo/outlook/gor2601a.pdf
#> 4 2025-10       2025-10-30 https://www.boj.or.jp/en/mopo/outlook/gor2510a.pdf
#> 5 2025-07       2025-07-31 https://www.boj.or.jp/en/mopo/outlook/gor2507a.pdf
#> 6 2025-04       2025-05-01 https://www.boj.or.jp/en/mopo/outlook/gor2504a.pdf
#>   source_format full_text_date
#> 1           pdf     2026-08-03
#> 2           pdf     2026-04-30
#> 3           pdf     2026-01-26
#> 4           pdf     2025-10-31
#> 5           pdf     2025-08-01
#> 6           pdf     2025-05-02
#>                                        full_text_url
#> 1 https://www.boj.or.jp/en/mopo/outlook/gor2607b.pdf
#> 2 https://www.boj.or.jp/en/mopo/outlook/gor2604b.pdf
#> 3 https://www.boj.or.jp/en/mopo/outlook/gor2601b.pdf
#> 4 https://www.boj.or.jp/en/mopo/outlook/gor2510b.pdf
#> 5 https://www.boj.or.jp/en/mopo/outlook/gor2507b.pdf
#> 6 https://www.boj.or.jp/en/mopo/outlook/gor2504b.pdf
```
