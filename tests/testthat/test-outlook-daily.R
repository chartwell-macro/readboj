# Exercise the actual installed/source entrypoint. Intercept quit/sleep in its
# evaluation environment so tests cannot exit the runner or start a daemon.
outlook_daily_script <- function(arguments = '--once', outcomes, stop_after_sleeps = 0L) {
  path <- system.file('scripts', 'outlook-daily.R', package = 'readboj')
  if (!nzchar(path)) path <- testthat::test_path('..','..','inst','scripts','outlook-daily.R')
  index <- 0L
  invocations <- list()
  testthat::local_mocked_bindings(update_boj_outlook = function(...) {
    index <<- index + 1L
    invocations[[index]] <<- list(...)
    value <- outcomes[[min(index,length(outcomes))]]
    if (inherits(value,'error')) stop(value)
    value
  }, .package='readboj')
  environment <- new.env(parent = globalenv())
  environment$commandArgs <- function(...) arguments
  exit_status <- 0L
  sleeps <- numeric()
  finish <- function() stop(structure(list(message='entrypoint test finished',call=NULL),
    class=c('outlook_daily_test_finished','error','condition')))
  environment$quit <- function(status = 0L,...) {exit_status <<- as.integer(status);finish()}
  environment$Sys.sleep <- function(seconds) {
    sleeps <<- c(sleeps,seconds)
    if(length(sleeps)>=stop_after_sleeps) finish()
  }
  messages <- character()
  stdout <- capture.output(invisible(withCallingHandlers(
    tryCatch(sys.source(path,envir=environment),outlook_daily_test_finished=function(e) NULL),
    message=function(e) {messages <<- c(messages,conditionMessage(e));invokeRestart('muffleMessage')})))
  list(exit_status=exit_status,stdout=stdout,messages=messages,invocations=invocations,sleeps=sleeps)
}

test_that('once reports a failed same-day throttle and exits nonzero', {
  result <- outlook_daily_script(outcomes=list(list(status='throttled',previous_status='failed',
    attempted_at=as.POSIXct('2026-10-24 00:00:00',tz='UTC'),error='fixture source failure')))
  expect_identical(result$exit_status,1L)
  expect_length(result$messages,1L)
  expect_match(result$messages,'throttled after an unsuccessful update',fixed=TRUE)
  expect_match(result$messages,'fixture source failure',fixed=TRUE)
  expect_length(result$stdout,0L)
  expect_length(result$sleeps,0L)
})

test_that('successful same-day throttles are quiet and exit zero', {
  for(status in c('updated','unchanged')) {
    result <- outlook_daily_script(outcomes=list(list(status='throttled',previous_status=status)))
    expect_identical(result$exit_status,0L)
    expect_length(result$messages,0L)
    expect_length(result$stdout,0L)
    expect_length(result$sleeps,0L)
  }
})

test_that('normal update failure is explicit and does not become successful throttling', {
  failure <- structure(list(message='fixture failed update',call=NULL,
    status=list(status='failed',error='fixture source failure')),class=c('readboj_outlook_update_error','error','condition'))
  result <- outlook_daily_script(outcomes=list(failure))
  expect_identical(result$exit_status,1L)
  expect_length(result$messages,1L)
  expect_match(result$messages,'fixture source failure',fixed=TRUE)
  expect_length(result$sleeps,0L)
  result <- outlook_daily_script(outcomes=list(simpleError('could not save a check receipt')))
  expect_identical(result$exit_status,1L)
  expect_match(result$messages,'could not save a check receipt',fixed=TRUE)
})

test_that('watch reports a failure once, sleeps, and reports recovery without noisy repeats', {
  attempted <- as.POSIXct('2026-10-24 00:00:00',tz='UTC')
  failure <- structure(list(message='fixture failed update',call=NULL,
    status=list(status='failed',error='fixture source failure',attempted_at=attempted)),
    class=c('readboj_outlook_update_error','error','condition'))
  result <- outlook_daily_script(arguments=c('--watch','--force','--rebuild'),stop_after_sleeps=5L,
    outcomes=list(failure,
      list(status='throttled',previous_status='failed',error='fixture source failure',attempted_at=attempted),
      list(status='throttled',previous_status='failed',error='fixture source failure',attempted_at=attempted),
      list(status='throttled',previous_status='unchanged'),
      list(status='throttled',previous_status='unchanged')))
  expect_length(result$messages,1L)
  expect_match(result$messages,'fixture source failure',fixed=TRUE)
  expect_identical(result$sleeps,rep(60,5))
  expect_identical(result$invocations[[1L]],list(force=TRUE,rebuild=TRUE))
  expect_true(all(vapply(result$invocations[-1L],identical,logical(1L),list(force=FALSE,rebuild=FALSE))))
  printed <- jsonlite::fromJSON(paste(result$stdout,collapse='\n'))
  expect_identical(printed$status,'throttled')
  expect_identical(printed$previous_status,'unchanged')
})

test_that('watch exposes a new meaningful failure and ordinary successful checks', {
  result <- outlook_daily_script(arguments='--watch',stop_after_sleeps=3L,
    outcomes=list(simpleError('first failure'),simpleError('different failure'),list(status='updated')))
  expect_length(result$messages,2L)
  expect_match(result$messages[[1L]],'first failure',fixed=TRUE)
  expect_match(result$messages[[2L]],'different failure',fixed=TRUE)
  expect_identical(result$sleeps,rep(60,3))
  expect_identical(jsonlite::fromJSON(paste(result$stdout,collapse='\n'))$status,'updated')
})
