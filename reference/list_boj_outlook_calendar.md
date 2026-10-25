# Discover the official Outlook publication calendar

Selects only the Outlook Bank's View column of the MPM schedule.
Summary, Minutes and non-Outlook meetings supply no release dates.
Bank's View has no fixed publication time; its timestamp is a date-start
polling boundary. Full text uses the official next-business-day 14:00
Tokyo rule and BoJ holiday tables. If holiday-year coverage is
unavailable its polling bound is marked unconfirmed, rather than
asserted as a publication date.

## Usage

``` r
list_boj_outlook_calendar(
  upcoming_only = TRUE,
  timeout = 30,
  retries = 2L,
  deadline = NULL
)
```

## Arguments

- upcoming_only:

  Keep reports with a Bank's View date or full-text stage still on/after
  the current Tokyo date/time.

- timeout, retries, deadline:

  Bounded transport settings as in
  [`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md).

## Value

A data frame with edition hints, publication dates and separate stage
polling times, with official source receipts in provenance. The
archive's actual edition identity takes precedence over a meeting-month
hint.

## Examples

``` r
if (FALSE) { # \dontrun{
list_boj_outlook_calendar(timeout = 10, retries = 0L,
                        deadline = Sys.time() + 30)
} # }
```
