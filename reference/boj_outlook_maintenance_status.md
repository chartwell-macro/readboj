# Inspect local calendar-aware Outlook maintenance state

Inspect local calendar-aware Outlook maintenance state

## Usage

``` r
boj_outlook_maintenance_status(data_dir = boj_outlook_data_dir())
```

## Arguments

- data_dir:

  Persistent directory shared with saved reads and maintenance.

## Value

Machine-readable local status with UTC ISO8601 next-due/release times,
pending full text, calendar freshness, updater outcome and errors. No
network.

## Examples

``` r
boj_outlook_maintenance_status(data_dir = tempfile("outlook-data-"))
#> $status
#> [1] "uninitialized"
#> 
#> $next_due_at
#> [1] "2026-10-25T06:19:14Z"
#> 
#> $due
#> [1] TRUE
#> 
#> $state_schema
#> [1] "outlook-maintenance-v1"
#> 
```
