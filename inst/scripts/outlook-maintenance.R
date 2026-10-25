#!/usr/bin/env Rscript
# Calendar-aware scheduler entrypoint; shares the reader's persistent data dir.
suppressPackageStartupMessages(library(readboj))
arguments <- commandArgs(trailingOnly = TRUE)
arguments <- setdiff(arguments, '--maintenance')
if (any(!arguments %in% c('--once','--watch','--force')) ||
    all(c('--once','--watch') %in% arguments)) stop(
  'Usage: outlook-maintenance.R [--once | --watch] [--force]')
watch <- '--watch' %in% arguments
last_outcome <- NULL
repeat {
  outcome <- tryCatch(maintain_boj_outlook(force = '--force' %in% arguments),
    error = function(e) list(status = 'failed', error = conditionMessage(e),
      next_due_at = format(Sys.time()+300,'%Y-%m-%dT%H:%M:%SZ',tz='UTC')))
  # Always machine-readable in --once, including failures and inexpensive idles.
  # A watcher stays quiet for the same outcome until it changes meaningfully.
  key <- jsonlite::toJSON(outcome[c('status','next_due_at','next_release_at','edition',
    'full_text_pending','error')],auto_unbox=TRUE,null='null')
  if (!watch || !identical(key,last_outcome)) {
    cat(jsonlite::toJSON(outcome,auto_unbox=TRUE,null='null',pretty=TRUE), '\n')
  }
  last_outcome <- key
  if (!watch) {
    if (outcome$status %in% c('failed','busy')) quit(status=1L)
    break
  }
  arguments <- setdiff(arguments,'--force')
  Sys.sleep(60)
}
