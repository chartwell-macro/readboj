# Location of refreshed Outlook data

Ordinary reads never create this directory. Configure the same location
for the application and its daily updater with option
`readboj.outlook_data_dir` or environment variable
`READBOJ_OUTLOOK_DATA_DIR`.

## Usage

``` r
boj_outlook_data_dir()
```

## Value

The configured directory path.

## Examples

``` r
boj_outlook_data_dir()
#> [1] "/home/runner/.local/share/R/readboj/outlook"
```
