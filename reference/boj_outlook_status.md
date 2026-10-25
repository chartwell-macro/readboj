# Inspect local Outlook data and updater status

Inspect local Outlook data and updater status

## Usage

``` r
boj_outlook_status(data_dir = boj_outlook_data_dir())
```

## Arguments

- data_dir:

  Directory containing refreshed structured data.

## Value

A list of coverage, snapshot/parser identities, freshness, last update
outcome and fallback errors. This performs no network or source parsing.

## Examples

``` r
boj_outlook_status(data_dir = tempfile("outlook-data-"))
#> $origin
#> [1] "package"
#> 
#> $snapshot_sha256
#> [1] "1933f6789e21b0428573cdb0ffa345e239385aa5355dddac34ade63991d9984c"
#> 
#> $parser_sha256
#> [1] "25b5df5528361b00eee515d0d37aac4d7ce0f6accd17f637eb66d036dc662caf"
#> 
#> $generation
#> [1] 0
#> 
#> $parser_schema
#> [1] "outlook-semantic-v2"
#> 
#> $built_at
#> [1] "2026-10-24 02:28:06 UTC"
#> 
#> $checked_at
#> [1] "2026-10-22 11:01:42 UTC"
#> 
#> $last_update_status
#> [1] "bundled"
#> 
#> $fallback_errors
#> character(0)
#> 
#> $coverage_loss
#> NULL
#> 
#> $update
#> [1] "Run update_boj_outlook() separately; ordinary reads perform no source checks."
#> 
#> $editions
#> [1] 74
#> 
#> $rows
#> [1] 4142
#> 
#> $first_release
#> [1] "2000-10"
#> 
#> $latest_release
#> [1] "2026-07"
#> 
#> $parser_update_required
#> [1] FALSE
#> 
#> $last_attempt
#> NULL
#> 
#> $data_dir
#> [1] "/tmp/RtmpzrvYDr/outlook-data-1acd2a044126"
#> 
```
