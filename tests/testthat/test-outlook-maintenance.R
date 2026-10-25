test_that('official column parsing excludes non-Outlook MPM, Summary and Minutes dates', {
  files<-outlook_calendar_fixture_files();withr::defer(unlink(unlist(files)))
  holidays<-readboj:::parse_outlook_holidays(files$holidays)
  events<-readboj:::parse_outlook_calendar(files$calendar,holidays)
  expect_identical(nrow(events),8L)
  expect_identical(as.character(events$publication_date),c('2026-01-23','2026-04-28','2026-07-31','2026-10-30',
    '2027-01-22','2027-04-28','2027-07-22','2027-10-29'))
  expect_identical(as.character(events$full_text_date),c('2026-01-26','2026-04-30','2026-08-03','2026-11-02',
    '2027-01-25','2027-04-30','2027-07-23','2027-11-01'))
  expect_identical(readboj:::outlook_utc(events$bank_view_poll_from_at[[4L]]),'2026-10-29T15:00:00Z')
  expect_identical(readboj:::outlook_utc(events$full_text_poll_from_at[[4L]]),'2026-11-02T05:00:00Z')
  expect_true(all(events$bank_view_timing=='after_mpm_no_fixed_time'))
  expect_identical(holidays$years,c(2026L,2027L)) # Headings, not stale captions.
  cross<-readboj:::outlook_next_business_day(as.Date('2027-12-30'),holidays)
  expect_identical(cross$date,as.Date('2028-01-04'))
  expect_false(cross$confirmed)
  expect_identical(readboj:::outlook_calendar_date('May 1 (Fri.)',2026L),as.Date('2026-05-01'))
  expect_identical(readboj:::outlook_calendar_date('Jan. 4 (Mon.), 2027',2026L),as.Date('2027-01-04'))
  expect_identical(readboj:::outlook_calendar_date('Jan. 4,2027',2026L),as.Date('2027-01-04'))
})

test_that('not-due maintenance is local-only and release probes do not repeat full source checks', {
  state<-outlook_maintenance_fixture()
  first<-maintain_boj_outlook(state$directory)
  expect_identical(first$status,'idle')
  expect_identical(first$next_due_at,'2026-10-29T15:00:00Z')
  expect_identical(first$next_release_date,'2026-10-30')
  expect_identical(first$edition,'2026-10')
  expect_false(first$release_time_is_fixed)
  expect_length(state$update_calls,0L)
  calls<-state$calendar_calls
  state$now<-state$now+600
  local_mocked_bindings(outlook_saved_load=function(...) stop('Not-due call must not read the numeric bundle'),.package='readboj')
  result<-maintain_boj_outlook(state$directory)
  expect_identical(result$status,'idle')
  expect_identical(state$calendar_calls,calls)
  expect_identical(state$probe_calls,0L)
})

test_that('Bank View and later same-day-throttled full text are separately completed', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory)
  state$now<-as.POSIXct('2026-10-29 15:00:00',tz='UTC')
  waiting<-maintain_boj_outlook(state$directory)
  expect_identical(waiting$status,'waiting')
  expect_identical(state$probe_calls,1L)
  expect_length(state$update_calls,0L)
  state$now<-state$now+300
  maintain_boj_outlook(state$directory)
  expect_identical(state$probe_calls,1L)
  state$now<-as.POSIXct('2026-10-30 03:00:00',tz='UTC')
  outlook_fixture_add_edition(state,'2026-10','2026-10-30')
  arrived<-maintain_boj_outlook(state$directory)
  expect_identical(arrived$status,'success')
  expect_true(arrived$full_text_pending)
  expect_identical(arrived$release_stage,'full_text')
  expect_identical(arrived$next_release_at,'2026-11-02T05:00:00Z')
  expect_identical(unique(read_boj_outlook(data_dir=state$directory)$release),'2026-10')
  state$now<-as.POSIXct('2026-11-02 00:00:00',tz='UTC')
  maintain_boj_outlook(state$directory) # Daily revision check before full-text time.
  before<-length(state$update_calls)
  row<-which(state$catalogue$release=='2026-10')
  state$catalogue$full_text_url[[row]]<-sub('a.pdf','b.pdf',state$catalogue$banks_view_url[[row]],fixed=TRUE)
  state$catalogue$full_text_date[[row]]<-as.Date('2026-11-02')
  state$now<-as.POSIXct('2026-11-02 05:00:00',tz='UTC')
  full<-maintain_boj_outlook(state$directory)
  expect_identical(length(state$update_calls),before+1L)
  expect_true(tail(state$update_calls,1L)[[1L]]$force)
  expect_false(full$full_text_pending)
  expect_identical(full$edition,'2027-01')
  expect_identical(full$next_release_date,'2027-01-22')
})

test_that('a calendar failure retains its last good calendar while independent due data refresh succeeds', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory)
  prior<-readboj:::outlook_maintenance_read(file.path(state$directory,'maintenance'))$calendar
  state$now<-state$now+86401
  state$calendar_failure<-TRUE
  outlook_fixture_add_edition(state,'2026-10','2026-10-30')
  result<-maintain_boj_outlook(state$directory)
  expect_identical(result$status,'failed')
  expect_identical(result$error$operation,'calendar')
  expect_match(result$error$message,'calendar unavailable',fixed=TRUE)
  expect_false(result$calendar_fresh)
  expect_identical(result$updater_outcome$status,'updated')
  expect_identical(unique(read_boj_outlook(data_dir=state$directory)$release),'2026-10')
  current<-readboj:::outlook_maintenance_read(file.path(state$directory,'maintenance'))
  expect_identical(current$calendar,prior)
  expect_identical(as.numeric(difftime(current$next_due_at,state$now,units='secs')),300)
  calls<-c(state$calendar_calls,length(state$update_calls))
  state$now<-state$now+60
  idle_failure<-maintain_boj_outlook(state$directory)
  expect_identical(idle_failure$status,'failed')
  expect_identical(c(state$calendar_calls,length(state$update_calls)),calls)
  state$calendar_failure<-FALSE;state$now<-state$now+240
  recovered<-maintain_boj_outlook(state$directory)
  expect_false(recovered$status=='failed')
  expect_true(recovered$calendar_fresh)
  expect_identical(length(state$update_calls),calls[[2L]])
})

test_that('daily source checks catch up after sleep and metadata changes force one update per observation', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory)
  state$now<-as.POSIXct('2026-10-30 03:00:00',tz='UTC')
  outlook_fixture_add_edition(state,'2026-10','2026-10-30')
  maintain_boj_outlook(state$directory)
  state$now<-as.POSIXct('2026-11-02 05:00:00',tz='UTC')
  maintain_boj_outlook(state$directory) # Due daily check, still no full-text link.
  before<-length(state$update_calls)
  state$head_version<-'new-validator'
  state$now<-state$now+3600
  maintain_boj_outlook(state$directory)
  expect_identical(length(state$update_calls),before+1L)
  state$now<-state$now+3600
  maintain_boj_outlook(state$directory)
  expect_identical(length(state$update_calls),before+1L)
  state$now<-as.POSIXct('2027-01-25 06:00:00',tz='UTC')
  state$calendar$events<-state$calendar$events[format(state$calendar$events$publication_date,'%Y')=='2027',,drop=FALSE]
  outlook_fixture_add_edition(state,'2027-01','2027-01-22',full=TRUE)
  caught_up<-maintain_boj_outlook(state$directory)
  expect_identical(unique(read_boj_outlook(data_dir=state$directory)$release),'2027-01')
  expect_identical(caught_up$edition,'2026-10') # Earlier unresolved full text survives sleep/new editions.
  expect_true(caught_up$full_text_pending)
  row<-which(state$catalogue$release=='2026-10')
  state$catalogue$full_text_url[[row]]<-sub('a.pdf','b.pdf',state$catalogue$banks_view_url[[row]],fixed=TRUE)
  state$catalogue$full_text_date[[row]]<-as.Date('2026-11-02')
  state$now<-state$now+3600
  resolved<-maintain_boj_outlook(state$directory)
  expect_identical(resolved$edition,'2027-04')
})

test_that('maintenance lock exclusion and atomic state failure keep good state/data', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory)
  root<-file.path(state$directory,'maintenance')
  lock<-readboj:::outlook_update_lock(root)
  busy<-maintain_boj_outlook(state$directory,force=TRUE)
  expect_identical(busy$status,'busy')
  readboj:::outlook_release_lock(lock)
  original<-readboj:::outlook_atomic_rds
  old_markers<-readboj:::outlook_saved_markers(root)
  local_mocked_bindings(outlook_atomic_rds=function(x,destination,...) {
    if(normalizePath(dirname(destination),winslash='/',mustWork=TRUE)==
        normalizePath(file.path(root,'commits'),winslash='/',mustWork=TRUE)) {
      stop('interrupted maintenance commit')
    }
    original(x,destination,...)
  },.package='readboj')
  failed<-maintain_boj_outlook(state$directory,force=TRUE)
  expect_identical(failed$status,'failed')
  expect_identical(readboj:::outlook_saved_markers(root),old_markers)
  expect_equal(nrow(read_boj_outlook('all',comparison='all',data_dir=state$directory)),4142L)
})

test_that('a corrupt maintenance generation falls back and repairs without damaging numeric data', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory)
  state$now<-state$now+3600
  maintain_boj_outlook(state$directory)
  root<-file.path(state$directory,'maintenance')
  marker<-readRDS(readboj:::outlook_saved_markers(root)[[1L]])
  writeBin(as.raw(1:10),file.path(root,'objects',paste0(marker$sha256,'.rds')))
  status<-boj_outlook_maintenance_status(state$directory)
  expect_length(status$state_fallback_errors,1L)
  expect_identical(status$next_release_date,'2026-10-30')
  maintain_boj_outlook(state$directory)
  repaired<-boj_outlook_maintenance_status(state$directory)
  expect_length(repaired$state_fallback_errors,0L)
  expect_equal(nrow(read_boj_outlook('all',comparison='all',data_dir=state$directory)),4142L)
})

outlook_maintenance_cli <- function(args,outcomes,stop_sleeps=0L,bridge=FALSE) {
  index<-0L;calls<-list();sleeps<-numeric();exit_status<-0L
  local_mocked_bindings(maintain_boj_outlook=function(...) {
    index<<-index+1L;calls[[index]]<<-list(...)
    item<-outcomes[[min(index,length(outcomes))]]
    if(inherits(item,'error')) stop(item)
    item
  },.package='readboj')
  env<-new.env(parent=globalenv());env$commandArgs<-function(...) args
  finish<-function() stop(structure(list(message='finished',call=NULL),class=c('maintenance_cli_finished','error','condition')))
  env$quit<-function(status=0L,...) {exit_status<<-as.integer(status);finish()}
  env$Sys.sleep<-function(seconds) {sleeps<<-c(sleeps,seconds);if(length(sleeps)>=stop_sleeps) finish()}
  filename<-if(bridge) 'outlook-daily.R' else 'outlook-maintenance.R'
  path<-system.file('scripts',filename,package='readboj')
  stdout<-capture.output(invisible(tryCatch(sys.source(path,envir=env),maintenance_cli_finished=function(e) NULL)))
  list(exit_status=exit_status,stdout=stdout,sleeps=sleeps,calls=calls)
}

test_that('maintenance CLI returns UTC JSON for idle/failure and the daily maintenance mode dispatches correctly', {
  idle<-list(status='idle',next_due_at='2026-10-30T00:00:00Z',next_release_date='2026-10-30',full_text_pending=FALSE)
  result<-outlook_maintenance_cli(c('--maintenance','--once'),list(idle),bridge=TRUE)
  expect_identical(result$exit_status,0L)
  expect_identical(jsonlite::fromJSON(paste(result$stdout,collapse='\n'))$next_due_at,idle$next_due_at)
  failed<-list(status='failed',next_due_at='2026-10-30T00:05:00Z',error=list(operation='calendar',message='unavailable'))
  result<-outlook_maintenance_cli('--once',list(failed))
  expect_identical(result$exit_status,1L)
  expect_identical(jsonlite::fromJSON(paste(result$stdout,collapse='\n'))$error$operation,'calendar')
  watch<-outlook_maintenance_cli(c('--watch','--force'),list(idle,idle,failed,failed),stop_sleeps=4L)
  expect_identical(watch$sleeps,rep(60,4))
  expect_true(watch$calls[[1L]]$force)
  expect_false(watch$calls[[2L]]$force)
  expect_equal(sum(grepl('"status"',watch$stdout)),2L)
})

test_that('bootstrap calendar outage does not block due data or lose its separate full text', {
  state<-outlook_maintenance_fixture()
  state$calendar_failure<-TRUE
  state$now<-state$now+86401
  outlook_fixture_add_edition(state,'2026-10','2026-10-30')
  result<-maintain_boj_outlook(state$directory)
  expect_identical(result$status,'failed')
  expect_identical(result$updater_outcome$status,'updated')
  expect_false(result$calendar_fresh)
  expect_true(result$full_text_pending)
  expect_identical(result$edition,'2026-10')
  expect_identical(result$release_stage,'full_text')
  expect_false(result$release_time_is_fixed) # Holiday/calendar evidence is unavailable.
  expect_identical(unique(read_boj_outlook(data_dir=state$directory)$release),'2026-10')
})

test_that('a failed due updater reports its current failure rather than a stale successful outcome', {
  state<-outlook_maintenance_fixture()
  maintain_boj_outlook(state$directory,force=TRUE)
  before<-read_boj_outlook('all',comparison='all',data_dir=state$directory)
  state$now<-state$now+86401
  state$fail<-state$catalogue$banks_view_url[[1L]]
  failed<-maintain_boj_outlook(state$directory)
  expect_identical(failed$status,'failed')
  expect_identical(failed$error$operation,'update')
  expect_identical(failed$updater_outcome$status,'failed')
  expect_match(failed$updater_outcome$error,'fixture source failure',fixed=TRUE)
  expect_identical(read_boj_outlook('all',comparison='all',data_dir=state$directory)$value,before$value)
  state$fail<-NULL;state$now<-state$now+300
  recovered<-maintain_boj_outlook(state$directory)
  expect_identical(recovered$status,'unchanged')
  expect_identical(recovered$updater_outcome$status,'unchanged')
})

test_that('long calendar backoff never postpones an earlier independent numeric deadline', {
  state<-outlook_maintenance_fixture()
  state$now<-as.POSIXct('2026-10-25 14:00:00',tz='UTC') # No release-window probe before the daily deadline.
  maintain_boj_outlook(state$directory,force=TRUE)
  root<-file.path(state$directory,'maintenance')
  initial<-readboj:::outlook_maintenance_read(root)
  state$calendar_failure<-TRUE
  state$now<-state$now+60
  maintain_boj_outlook(state$directory,force=TRUE)
  for(i in 1:4) {
    current<-readboj:::outlook_maintenance_read(root)
    state$now<-current$next_calendar_at
    maintain_boj_outlook(state$directory)
  }
  pending<-readboj:::outlook_maintenance_read(root)
  expect_gt(pending$next_calendar_at,pending$next_revision_at)
  expect_identical(pending$next_due_at,pending$next_revision_at)
  calls<-state$calendar_calls;updates<-length(state$update_calls)
  state$now<-pending$next_revision_at
  result<-maintain_boj_outlook(state$directory)
  expect_identical(state$calendar_calls,calls) # Its later retry is respected.
  expect_identical(length(state$update_calls),updates+1L)
  expect_identical(result$updater_outcome$status,'unchanged')
  expect_identical(result$status,'failed') # Calendar is still unavailable.
  expect_false(result$calendar_fresh)
  after<-readboj:::outlook_maintenance_read(root)
  expect_identical(after$next_calendar_at,pending$next_calendar_at)
  expect_gt(after$next_revision_at,state$now)
})
