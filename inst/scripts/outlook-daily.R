#!/usr/bin/env Rscript
# Run once from a daily scheduler, or use --watch as a long-lived app worker.
# Configure READBOJ_OUTLOOK_DATA_DIR identically for this worker and its readers.
suppressPackageStartupMessages(library(readboj))
arguments <- commandArgs(trailingOnly = TRUE)
if ('--maintenance' %in% arguments) {
  # Keep the established daily CLI while exposing the calendar-aware mode.
  sys.source(system.file('scripts','outlook-maintenance.R',package='readboj'),envir=environment())
} else {
allowed <- c('--once', '--watch', '--force', '--rebuild')
if (any(!arguments %in% allowed) || all(c('--once', '--watch') %in% arguments)) {
  stop('Usage: outlook-daily.R [--once | --watch] [--force] [--rebuild]')
}
watch <- '--watch' %in% arguments
last_failure <- NULL
repeat {
  outcome <- tryCatch(update_boj_outlook(force = '--force' %in% arguments,
    rebuild = '--rebuild' %in% arguments), error = function(e) {
      result <- e$status
      if (!is.list(result)) result <- list()
      result$status <- 'failed'
      if (is.null(result$error)) result$error <- conditionMessage(e)
      result
    })
  if (!is.list(outcome) || !is.character(outcome$status) || length(outcome$status) != 1L) {
    outcome <- list(status = 'failed', error = 'The updater did not return a valid status.')
  }
  throttled <- identical(outcome$status, 'throttled')
  effective_status <- if (throttled) outcome$previous_status else outcome$status
  successful <- is.character(effective_status) && length(effective_status) == 1L &&
    effective_status %in% c('updated', 'unchanged')
  if (!successful) {
    # A throttle is not evidence of success: its previous completed outcome
    # governs the scheduler exit code. Deduplicate the same failure in --watch.
    reason <- if (is.null(outcome$error)) 'No successful source check is recorded.' else outcome$error
    failure_key <- paste(effective_status, as.character(outcome$attempted_at), reason, sep = '|')
    if (!watch || !identical(last_failure, failure_key)) {
      message(if (throttled) 'Outlook daily check is throttled after an unsuccessful update. ' else
        'Outlook daily check failed. ', reason,
        if (throttled) ' Use --force to retry today; last-good data remains available.' else '')
    }
    last_failure <- failure_key
  } else {
    if (!throttled || !is.null(last_failure)) {
      # Also report recovery by another worker, once, when the persisted result
      # changes from failed to successful while this watcher is throttled.
      cat(jsonlite::toJSON(outcome, auto_unbox = TRUE, null = 'null', pretty = TRUE), '\n')
    }
    last_failure <- NULL
  }
  if (!watch) {
    if (!successful) quit(status = 1L)
    break
  }
  # Do not bypass the daily attempt throttle after a failure or spin on it.
  arguments <- setdiff(arguments, c('--force', '--rebuild'))
  Sys.sleep(60)
}
}
