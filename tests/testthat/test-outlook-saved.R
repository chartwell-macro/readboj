test_that('saved catalogue and series need neither network, raw documents nor Poppler', {
  trap <- function(...) stop('Forbidden ordinary-read I/O')
  local_mocked_bindings(fetch_snapshot = trap, outlook_update_request = trap,
    read_raw_file = trap, run_outlook_pdf = trap, extract_outlook_pdf = trap,
    outlook_executable = trap, .package = 'readboj')
  directory <- tempfile()
  calls <- 0L
  original <- readboj:::outlook_saved_read_file
  local_mocked_bindings(outlook_saved_read_file = function(...) {calls <<- calls + 1L; original(...)}, .package = 'readboj')
  memo <- readboj:::.readboj_outlook_memo; memo$loaded <- NULL
  catalogue <- list_boj_outlook_releases(data_dir = directory)
  all <- read_boj_outlook('all', comparison = 'all', data_dir = directory, pdftotext = '')
  expected <- outlook_saved_fixture()
  expect_identical(unname(as.matrix(catalogue)), unname(as.matrix(expected$catalogue)))
  attr(all, 'readboj_provenance') <- NULL
  expect_identical(all, expected$data)
  expect_equal(nrow(all), 4142L)
  expect_equal(sum(is.na(all$value)), 5L)
  expect_false(dir.exists(directory))
  for (i in 1:10) read_boj_outlook('latest', data_dir = directory, measure = 'real_gdp', statistic = 'median')
  expect_identical(calls, 1L)
  expect_equal(nrow(read_boj_outlook('2026-07', comparison = 'prior', data_dir = directory)), 27L)
  expect_error(read_boj_outlook('9999-01', data_dir = directory), class = 'readboj_identity_error')
  expect_error(read_boj_outlook(measure = 'inflation', data_dir = directory), class = 'readboj_parameter_error')
  expect_error(read_boj_outlook(statistic = 'fake', data_dir = directory), class = 'readboj_parameter_error')
  expect_error(read_boj_outlook(range_scope = 'confidence', data_dir = directory), class = 'readboj_parameter_error')
  expect_error(read_boj_outlook(expected_sha256 = strrep('0',64), data_dir = directory), class = 'readboj_identity_error')
  expect_error(read_boj_outlook('all', expected_sha256 = strrep('0',64)), class = 'readboj_parameter_error')
  expect_error(read_boj_outlook('bad'), class = 'readboj_parameter_error')
  expect_error(read_boj_outlook(comparison = 'fake'), class = 'readboj_parameter_error')
  read_boj_outlook(data_dir = directory, refresh = TRUE)
  expect_identical(calls, 2L)
})

test_that('saved snapshot validation detects schema, semantic and provenance corruption', {
  x <- outlook_saved_fixture()
  validate <- readboj:::outlook_saved_validate
  seal <- readboj:::outlook_saved_seal
  expect_silent(validate(x))
  bad <- x; bad$data$value[[1L]] <- 9
  expect_error(validate(bad), class = 'readboj_outlook_data_error')
  bad <- x; bad$data$period_start[[1L]] <- as.Date('1900-01-01')
  expect_error(validate(seal(bad)), class = 'readboj_outlook_data_error')
  bad <- x; bad$data$value[[1L]] <- NA_real_
  expect_error(validate(seal(bad)), class = 'readboj_outlook_data_error')
  bad <- x; bad$data$source_sha256[[1L]] <- strrep('0',64)
  expect_error(validate(seal(bad)), class = 'readboj_outlook_data_error')
  bad <- x; bad$schema <- 'future-incompatible'
  expect_error(validate(seal(bad)), class = 'readboj_outlook_data_error')
  bad <- x; bad$data <- rbind(bad$data, bad$data[1,])
  expect_error(validate(seal(bad)), class = 'readboj_outlook_data_error')
})

test_that('updater checks the full dependency graph, throttles and avoids unnecessary parsing', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory, recursive = TRUE))
  result <- update_boj_outlook(directory, wait = 0, pdftotext = '')
  expect_identical(result$status, 'unchanged')
  expect_length(state$parsed, 0L)
  expect_setequal(state$requests, c(readboj:::.readboj_outlook_index, names(state$base$assets)))
  expect_equal(result$requests, 145L)
  expect_false(dir.exists(file.path(directory, '.staging')))
  expect_length(readboj:::outlook_saved_markers(directory), 0L)
  state$requests <- character()
  result <- update_boj_outlook(directory, wait = 0)
  expect_identical(result$status, 'throttled')
  expect_length(state$requests, 0L)
  expect_identical(boj_outlook_status(directory)$last_update_status, 'unchanged')
  result <- update_boj_outlook(directory, force = TRUE, wait = 0)
  expect_identical(result$status, 'unchanged')
  expect_length(state$parsed, 0L)
})

test_that('new unseen editions publish atomically into the actual ordinary read directory', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory, recursive = TRUE))
  extra <- state$catalogue[1,,drop=FALSE]
  extra$release <- '2027-01'
  extra$publication_date <- as.Date('2027-01-29')
  extra$full_text_date <- as.Date(NA)
  extra$banks_view_url <- 'https://www.boj.or.jp/en/mopo/outlook/gor2701a.pdf'
  extra$full_text_url <- NA_character_
  state$catalogue <- rbind(extra, state$catalogue)
  result <- update_boj_outlook(directory, wait=0)
  expect_identical(result$status, 'updated')
  expect_identical(state$parsed, '2027-01')
  expect_equal(nrow(list_boj_outlook_releases(data_dir=directory)), 75L)
  latest <- read_boj_outlook(data_dir=directory)
  expect_identical(unique(latest$release), '2027-01')
  expect_identical(boj_provenance(latest)$saved$origin, 'refreshed')
  history <- read_boj_outlook('all', comparison='all', data_dir=directory)
  original <- history[history$release != '2027-01',,drop=FALSE]
  attr(original,'readboj_provenance') <- NULL
  rownames(original) <- NULL
  expect_identical(original, state$base$data)
  expect_false(dir.exists(file.path(directory,'.staging')))
  expect_length(list.files(file.path(directory,'objects')), 1L)
})

test_that('historical revisions, changed links and secondary assets invalidate only their editions', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  historical <- state$catalogue$banks_view_url[state$catalogue$release=='2017-10']
  state$changes[[historical]] <- 'revision-1'
  result <- update_boj_outlook(directory,wait=0)
  expect_identical(result$parsed_editions, '2017-10')
  expect_identical(result$changed_assets,historical)
  x <- read_boj_outlook('all',comparison='all',data_dir=directory)
  before <- state$base$data
  expect_equal(x$value[x$release=='2017-10'][[1L]], before$value[before$release=='2017-10'][[1L]]-.1)
  unchanged <- x[x$release!='2017-10',,drop=FALSE]; attr(unchanged,'readboj_provenance')<-NULL
  expected <- before[before$release!='2017-10',,drop=FALSE]
  rownames(unchanged)<-rownames(expected)<-NULL
  expect_identical(unchanged,expected)
  active <- readboj:::outlook_saved_load(directory)$snapshot
  expect_length(active$revisions,1L)
  expect_identical(active$revisions[[1L]]$data,before[before$release=='2017-10',,drop=FALSE])
  state$parsed <- character()
  secondary <- state$catalogue$full_text_url[state$catalogue$release=='2026-07']
  state$changes[[secondary]] <- 'secondary-revision'
  result <- update_boj_outlook(directory,force=TRUE,wait=0)
  expect_identical(state$parsed,'2026-07')
  expect_true(secondary %in% result$changed_assets)
  state$parsed <- character()
  i <- which(state$catalogue$release=='2026-07')
  state$catalogue$banks_view_url[[i]] <- sub('a.pdf','c.pdf',state$catalogue$banks_view_url[[i]],fixed=TRUE)
  result <- update_boj_outlook(directory,force=TRUE,wait=0)
  expect_identical(state$parsed,'2026-07')
  expect_match(unique(read_boj_outlook(data_dir=directory)$source_url),'gor2607c.pdf',fixed=TRUE)
  state$parsed <- character()
  result <- update_boj_outlook(directory,force=TRUE,wait=0)
  expect_identical(result$status,'unchanged')
  expect_length(state$parsed,0L)
})

test_that('source, coverage, byte and parser failures preserve the last good dataset', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  original <- read_boj_outlook('all',comparison='all',data_dir=directory)
  state$fail <- state$catalogue$banks_view_url[[1L]]
  expect_error(update_boj_outlook(directory,wait=0),class='readboj_outlook_update_error')
  expect_identical(boj_outlook_status(directory)$last_update_status,'failed')
  expect_identical(read_boj_outlook('all',comparison='all',data_dir=directory)$value,original$value)
  expect_false(dir.exists(file.path(directory,'.staging')))
  expect_false(dir.exists(file.path(directory,'update.lock')))
  state$fail <- NULL
  state$catalogue <- state$catalogue[-1,,drop=FALSE]
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0),class='readboj_outlook_update_error')
  state$catalogue <- state$base$catalogue
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0,max_total_bytes=5),class='readboj_outlook_update_error')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  state$parser <- strrep('f',64)
  expect_true(boj_outlook_status(directory)$parser_update_required)
  # Parser changes bypass the daily throttle and require every edition.
  result <- update_boj_outlook(directory,wait=0)
  expect_identical(result$status,'updated')
  expect_setequal(result$parsed_editions,state$catalogue$release)
  expect_false(boj_outlook_status(directory)$parser_update_required)
})

test_that('corrupt active objects and commits fall back explicitly to good data', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  url <- state$catalogue$banks_view_url[[1L]]
  state$changes[[url]] <- 'revision'
  update_boj_outlook(directory,wait=0)
  object <- readboj:::outlook_saved_load(directory)$path
  writeBin(as.raw(1:10),object)
  expect_warning(x <- read_boj_outlook(data_dir=directory),class='readboj_outlook_fallback_warning')
  expect_identical(boj_provenance(x)$saved$origin,'package')
  expect_length(boj_provenance(x)$saved$fallback_errors,1L)
  marker <- readboj:::outlook_saved_markers(directory)[[1L]]
  writeBin(as.raw(1:10),marker)
  expect_warning(boj_outlook_status(directory),class='readboj_outlook_fallback_warning')
})

test_that('writer exclusion, lost ownership and interrupted staging cannot publish a partial update', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  lock <- readboj:::outlook_update_lock(directory)
  expect_error(update_boj_outlook(directory,wait=0),class='readboj_outlook_locked_error')
  readboj:::outlook_release_lock(lock)
  state$interrupt <- function() stop('interrupted update')
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0),class='readboj_outlook_update_error')
  state$interrupt <- NULL
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  dir.create(file.path(directory,'.staging'))
  writeLines('abandoned raw',file.path(directory,'.staging','source-pdf'))
  result <- update_boj_outlook(directory,force=TRUE,wait=0)
  expect_identical(result$status,'unchanged')
  expect_false(dir.exists(file.path(directory,'.staging')))
  state$changes[[state$catalogue$banks_view_url[[1L]]]] <- 'changed'
  local_mocked_bindings(outlook_assert_lock=function(...) stop('lost writer ownership'),.package='readboj')
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0),class='readboj_outlook_update_error')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  expect_identical(boj_outlook_status(directory)$origin,'package')
})

test_that('conditional transport checks validate full identities and hash new bodies', {
  url <- 'https://www.boj.or.jp/en/mopo/outlook/gor2607a.pdf'
  previous <- outlook_saved_fixture()$assets[[url]]
  directory <- tempfile(); dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  captured <- list()
  mode <- 304L
  testthat::local_mocked_bindings(req_perform = function(req,path,...) {
    captured[[length(captured)+1L]] <<- req
    if (mode == 200L) writeBin(charToRaw('new official test body'),path)
    httr2::response(status_code=mode,url=url,headers=list(etag='"new"'))
  },.package='httr2')
  request <- readboj:::outlook_update_request
  e <- request(url,previous,file.path(directory,'body'),30,0L,0,1024,Sys.time()+10)
  expect_identical(e$http_status,304L)
  expect_identical(e$raw_sha256,previous$raw_sha256)
  expect_identical(captured[[1L]]$headers[['If-None-Match']],previous$etag)
  expect_identical(captured[[1L]]$headers[['If-Modified-Since']],previous$last_modified)
  expect_false(file.exists(file.path(directory,'body')))
  mode <- 200L
  e <- request(url,previous,file.path(directory,'body'),30,0L,0,1024,Sys.time()+10)
  expect_identical(e$raw_sha256,readboj:::sha256_file(e$path))
  expect_false(identical(e$raw_sha256,previous$raw_sha256))
  mode <- 404L
  expect_error(request(url,previous,file.path(directory,'body'),30,0L,0,1024,Sys.time()+10),class='readboj_transport_error')
  mode <- 304L
  expect_error(request(url,NULL,file.path(directory,'body'),30,0L,0,1024,Sys.time()+10),class='readboj_transport_error')
})

test_that('invalid parser output and sources that change mid-update cannot publish', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  url <- state$catalogue$banks_view_url[[1L]]
  state$changes[[url]] <- 'first'
  state$mutate_before_parse <- function() state$changes[[url]] <- 'second'
  # The changed body was already staged, so fetching it again must use exactly
  # that checked revision. Removing it forces a second, conflicting transfer.
  state$mutate_before_parse <- function() {
    unlink(list.files(file.path(directory,'.staging'),full.names=TRUE))
    state$changes[[url]] <- 'second'
  }
  expect_error(update_boj_outlook(directory,wait=0),class='readboj_outlook_update_error')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  state$mutate_before_parse <- NULL
  parser <- readboj:::read_outlook_edition
  local_mocked_bindings(read_outlook_edition=function(...) {
    x <- parser(...); x$value[[1L]] <- NA_real_; x
  },.package='readboj')
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0),class='readboj_outlook_update_error')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
})

test_that('concurrent readers see only complete old or new generations', {
  skip_if(.Platform$OS.type != 'unix','Fork-based concurrency check requires Unix')
  state <- outlook_update_fixture()
  directory <- tempfile(); dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  url <- state$catalogue$banks_view_url[[1L]]
  state$changes[[url]] <- 'concurrent'
  paused <- file.path(directory,'paused')
  release <- file.path(directory,'release')
  state$mutate_before_parse <- function() {
    writeLines('paused',paused)
    limit <- Sys.time()+15
    while (!file.exists(release) && Sys.time()<limit) Sys.sleep(.01)
    if (!file.exists(release)) stop('Timed out waiting for reader')
  }
  child <- parallel::mcparallel(update_boj_outlook(directory,wait=0),silent=TRUE)
  collected <- FALSE
  withr::defer(if (!collected) try(tools::pskill(child$pid,9L),silent=TRUE))
  limit <- Sys.time()+15
  while (!file.exists(paused) && Sys.time()<limit) Sys.sleep(.01)
  expect_true(file.exists(paused))
  before <- read_boj_outlook(data_dir=directory)
  expect_identical(boj_provenance(before)$saved$origin,'package')
  expect_error(update_boj_outlook(directory,force=TRUE,wait=0),class='readboj_outlook_locked_error')
  writeLines('resume',release)
  result <- parallel::mccollect(child,wait=TRUE)[[1L]]
  collected <- TRUE
  expect_identical(result$status,'updated')
  after <- read_boj_outlook(data_dir=directory)
  expect_identical(boj_provenance(after)$saved$origin,'refreshed')
  expect_equal(after$value[[1L]],before$value[[1L]]-.1)
  expect_false(dir.exists(file.path(directory,'.staging')))
})

test_that('a killed writer is recovered without losing the last good snapshot', {
  skip_if(.Platform$OS.type != 'unix','Fork-based interruption check requires Unix')
  state <- outlook_update_fixture()
  directory <- tempfile(); dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  state$changes[[state$catalogue$banks_view_url[[1L]]]] <- 'crash'
  paused <- file.path(directory,'paused')
  state$mutate_before_parse <- function() {writeLines('paused',paused); Sys.sleep(20)}
  child <- parallel::mcparallel(update_boj_outlook(directory,wait=0),silent=TRUE)
  limit <- Sys.time()+15
  while (!file.exists(paused) && Sys.time()<limit) Sys.sleep(.01)
  expect_true(file.exists(paused))
  tools::pskill(child$pid,9L)
  suppressWarnings(parallel::mccollect(child,wait=TRUE))
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  expect_identical(boj_outlook_status(directory)$origin,'package')
  expect_identical(boj_outlook_status(directory)$last_update_status,'running')
  state$mutate_before_parse <- NULL
  result <- update_boj_outlook(directory,wait=0)
  expect_identical(result$status,'updated')
  expect_false(dir.exists(file.path(directory,'update.lock')))
  expect_false(dir.exists(file.path(directory,'.staging')))
})

test_that('generation retention is bounded and abandoned pending files are cleaned', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  url <- state$catalogue$banks_view_url[[1L]]
  for(i in 1:5) {
    state$changes[[url]] <- paste('revision',i)
    update_boj_outlook(directory,force=TRUE,wait=0)
  }
  expect_length(readboj:::outlook_saved_markers(directory),3L)
  expect_length(list.files(file.path(directory,'objects')),3L)
  expect_length(readboj:::outlook_saved_load(directory)$snapshot$revisions,5L)
  for(name in c('objects','commits','checks')) {
    writeLines('incomplete',file.path(directory,name,'.pending-abandoned'))
  }
  writeLines('orphan',file.path(directory,'objects',paste0(strrep('0',64),'.rds')))
  result <- update_boj_outlook(directory,force=TRUE,wait=0)
  expect_identical(result$status,'unchanged')
  expect_length(list.files(file.path(directory,'objects'),all.files=TRUE,no..=TRUE),3L)
  expect_false(any(grepl('pending',list.files(directory,recursive=TRUE,all.files=TRUE))))
})

test_that('retry response bodies count against the total transaction byte bound', {
  calls <- 0L
  url <- 'https://www.boj.or.jp/en/mopo/outlook/gor2607a.pdf'
  testthat::local_mocked_bindings(req_perform=function(req,path,...) {
    calls <<- calls+1L
    writeBin(as.raw(1:6),path)
    httr2::response(status_code=503L,url=url)
  },.package='httr2')
  local_mocked_bindings(deadline_pause=function(...) NULL,.package='readboj')
  path <- tempfile()
  withr::defer(unlink(path))
  expect_error(readboj:::outlook_update_request(url,NULL,path,30,2L,0,8,Sys.time()+10,max_total_bytes=6),class='readboj_size_error')
  expect_identical(calls,1L)
})

test_that('failure of an ancillary receipt after commit reports valid publication', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  state$changes[[state$catalogue$banks_view_url[[1L]]]] <- 'receipt test'
  write_check <- readboj:::outlook_write_check
  count <- 0L
  local_mocked_bindings(outlook_write_check=function(...) {
    count <<- count+1L
    if(count==2L) stop('fixture receipt write failure')
    write_check(...)
  },.package='readboj')
  expect_warning(result <- update_boj_outlook(directory,wait=0),'final check receipt')
  expect_identical(result$status,'updated')
  expect_match(result$receipt_error,'fixture receipt write failure',fixed=TRUE)
  expect_identical(boj_outlook_status(directory)$origin,'refreshed')
  expect_length(readboj:::outlook_saved_markers(directory),1L)
})

test_that('caller interrupts are recorded without changing good data', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  state$interrupt <- function() signalCondition(structure(list(message='fixture interrupt',call=NULL),class=c('interrupt','condition')))
  condition <- tryCatch(update_boj_outlook(directory,wait=0),interrupt=identity)
  expect_s3_class(condition,'interrupt')
  expect_identical(boj_outlook_status(directory)$last_update_status,'interrupted')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
  expect_false(dir.exists(file.path(directory,'.staging')))
  expect_false(dir.exists(file.path(directory,'update.lock')))
})

test_that('compatible old parser schemas remain readable and invalidate every edition on update', {
  state <- outlook_update_fixture()
  directory <- tempfile();dir.create(directory)
  withr::defer(unlink(directory,recursive=TRUE))
  old <- state$base
  old$parser_schema <- 'outlook-semantic-previous'
  old <- readboj:::outlook_saved_seal(old)
  lock <- readboj:::outlook_update_lock(directory)
  readboj:::outlook_publish(old,directory,lock,character())
  readboj:::outlook_release_lock(lock)
  expect_equal(nrow(read_boj_outlook('all',comparison='all',data_dir=directory)),4142L)
  expect_true(boj_outlook_status(directory)$parser_update_required)
  result <- update_boj_outlook(directory,wait=0)
  expect_identical(result$status,'updated')
  expect_setequal(result$parsed_editions,state$catalogue$release)
  expect_false(boj_outlook_status(directory)$parser_update_required)
})

test_that('a partial revised edition preserves last-good bytes, values and check time by default', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  release <- '2017-10'
  url <- state$catalogue$banks_view_url[state$catalogue$release==release]
  state$changes[[url]] <- 'complete revision'
  update_boj_outlook(directory,wait=0)
  before <- read_boj_outlook(release,comparison='all',data_dir=directory)
  last_good <- readboj:::outlook_saved_load(directory)
  markers <- readboj:::outlook_saved_markers(directory)
  bytes <- readBin(last_good$path,'raw',n=file.info(last_good$path)$size)
  checked_at <- boj_outlook_status(directory)$checked_at
  original <- readboj:::read_outlook_edition
  local_mocked_bindings(read_outlook_edition=function(...) {
    x <- original(...)
    if(unique(x$release)!=release) return(x)
    p <- boj_provenance(x)
    x <- x[x$fiscal_year!=max(x$fiscal_year),,drop=FALSE]
    readboj:::attach_provenance(x,p)
  },.package='readboj')
  state$changes[[url]] <- 'partial revision'
  rejected <- tryCatch(update_boj_outlook(directory,force=TRUE,wait=0),error=identity)
  expect_s3_class(rejected,'readboj_outlook_update_error')
  expect_s3_class(rejected$parent,'readboj_outlook_coverage_error')
  expect_identical(rejected$status$coverage_loss$removed_scalars,18L)
  expect_identical(unique(rejected$parent$removed_identities$fiscal_year),2019L)
  expect_identical(readboj:::outlook_saved_markers(directory),markers)
  expect_identical(readBin(last_good$path,'raw',n=file.info(last_good$path)$size),bytes)
  after <- read_boj_outlook(release,comparison='all',data_dir=directory)
  expect_identical(after$value,before$value)
  expect_identical(after$fiscal_year,before$fiscal_year)
  expect_identical(boj_outlook_status(directory)$checked_at,checked_at)
  expect_identical(boj_outlook_status(directory)$last_update_status,'failed')
  expect_false(dir.exists(file.path(directory,'.staging')))
  expect_false(dir.exists(file.path(directory,'update.lock')))

  # Only an explicit reviewed opt-in may change the canonical coverage. Its
  # reduced coverage is visible in both status and ordinary-read provenance.
  allowed <- update_boj_outlook(directory,force=TRUE,wait=0,allow_coverage_loss=TRUE)
  expect_identical(allowed$status,'updated')
  expect_true(allowed$coverage_loss$allowed)
  expect_identical(allowed$coverage_loss$removed_scalars,18L)
  reduced <- read_boj_outlook(release,comparison='all',data_dir=directory)
  expect_identical(nrow(reduced),36L)
  expect_identical(boj_provenance(reduced)$saved$coverage_loss$removed_scalars,18L)
  revision <- tail(readboj:::outlook_saved_load(directory)$snapshot$revisions,1L)[[1L]]
  expect_identical(nrow(revision$removed_identities),18L)
  expect_true(2019L %in% revision$data$fiscal_year)
  expect_equal(nrow(revision$data),nrow(before))
})

test_that('the coverage guard protects individual scalar identities as well as fiscal targets', {
  state <- outlook_update_fixture()
  directory <- tempfile()
  withr::defer(unlink(directory,recursive=TRUE))
  url <- state$catalogue$banks_view_url[[1L]]
  state$changes[[url]] <- 'one median removed'
  original <- readboj:::read_outlook_edition
  local_mocked_bindings(read_outlook_edition=function(...) {
    x <- original(...)
    p <- boj_provenance(x)
    x <- x[-which(x$statistic=='median')[[1L]],,drop=FALSE]
    readboj:::attach_provenance(x,p)
  },.package='readboj')
  rejected <- tryCatch(update_boj_outlook(directory,wait=0),error=identity)
  expect_s3_class(rejected$parent,'readboj_outlook_coverage_error')
  expect_identical(rejected$status$coverage_loss$removed_scalars,1L)
  expect_identical(rejected$parent$removed_identities$statistic,'median')
  expect_length(readboj:::outlook_saved_markers(directory),0L)
})
