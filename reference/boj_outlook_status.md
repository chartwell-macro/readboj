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
#> Error: No valid saved Outlook dataset is available.
```
