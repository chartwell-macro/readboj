# Maintain saved Outlook data and its official next-release schedule

A scheduler can invoke this hourly. A not-due call reads local state
only. Due daily revision checks use the full incremental updater. Around
an overdue release, cheap archive/HEAD probes trigger a forced update
only after links, dates or validators change. Bank's View and
next-business-day full text remain separate pending stages. Every update
recomputes the next due time from fresh official calendar evidence. No
OS job or background worker is installed.

## Usage

``` r
maintain_boj_outlook(
  data_dir = boj_outlook_data_dir(),
  force = FALSE,
  calendar_max_age = 86400,
  revision_interval = 86400,
  probe_interval = 3600,
  timeout = 30,
  retries = 2L,
  deadline = NULL,
  ...
)
```

## Arguments

- data_dir:

  Persistent directory shared with ordinary saved reads.

- force:

  Ignore maintenance timing and run a full source/calendar check.

- calendar_max_age, revision_interval:

  Seconds between calendar refreshes and complete historical source
  revision checks (defaults one day).

- probe_interval:

  Minimum seconds between release-window metadata probes.

- timeout, retries, deadline:

  Bounded request/deadline settings.

- ...:

  Additional arguments for
  [`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md),
  such as a Poppler path. Maintenance never enables coverage-loss opt-in
  automatically.

## Value

A list with status, scalar ISO8601 UTC `next_due_at`, release/date/
edition, separate full-text pending state, freshness and errors.
Operational failures return `failed` and a persisted bounded retry
schedule, preserving last-good numeric data and calendar. Busy writers
return `busy` for retry.

## Examples

``` r
if (FALSE) { # \dontrun{
# A scheduler and ordinary readers should share one persistent directory.
maintain_boj_outlook(data_dir = boj_outlook_data_dir(),
                     deadline = Sys.time() + 1800)
} # }
```
