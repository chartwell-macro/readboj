outlook_calendar_fixture_files <- function() {
  calendar <- tempfile(fileext='.htm');holidays <- tempfile(fileext='.htm')
  schedule <- function(year,dates) paste0('<h2>',year,'</h2><table><thead>',
    '<tr><th rowspan="2">Date of MPM</th><th colspan="3">Release Schedule</th></tr>',
    '<tr><th>Outlook Report<br>(The Bank\'s View)</th><th>Summary of Opinions</th><th>MPM Minutes</th></tr></thead><tbody>',
    paste(vapply(dates,function(x) paste0('<tr><td>',x[[1]],'</td><td>',x[[2]],'</td><td>Dec. 31</td><td>Jan. 27, ',year+1L,'</td></tr>'),character(1)),collapse=''),'</tbody></table>')
  writeLines(paste0('<html><main>',schedule(2026,list(
    c('Jan. 22, 23','Jan. 23'),c('Mar. 18, 19','-'),c('Apr. 27, 28','Apr. 28'),
    c('July 30, 31','July 31'),c('Oct. 29, 30','Oct. 30'),c('Dec. 17, 18','-'))),
    schedule(2027,list(c('Jan. 21, 22','Jan. 22'),c('Mar. 17, 18','-'),
      c('Apr. 27, 28','Apr. 28'),c('July 21, 22','July 22'),c('Oct. 28, 29','Oct. 29'))),
    '<p>"The Bank\'s View" will be released immediately after relevant MPMs, and the full text at 2:00 p.m. on the next business day.</p></main></html>'),calendar)
  yearly <- function(year) paste0('<h3>',year,'</h3><table><caption>Holiday Schedule ',year-1L,
    '</caption><thead><tr><th>Month</th><th>Date</th></tr></thead><tbody>',
    paste(vapply(seq_len(12L),function(month) paste0('<tr><td>',month.name[[month]],'</td><td>',
      switch(as.character(month),'1'='1, 2, 3','4'='29','5'='3, 4, 5, 6','11'='3, 23','12'='31','--'),'</td></tr>'),character(1)),collapse=''),'</tbody></table>')
  writeLines(paste0('<html>',yearly(2026),yearly(2027),'</html>'),holidays)
  list(calendar=calendar,holidays=holidays)
}

outlook_maintenance_fixture <- function() {
  env <- parent.frame()
  state <- outlook_update_fixture(.env=env)
  state$directory <- tempfile('outlook-maintenance-')
  files <- outlook_calendar_fixture_files()
  withr::defer(unlink(c(state$directory,unlist(files)),recursive=TRUE),envir=env)
  holiday <- readboj:::parse_outlook_holidays(files$holidays)
  state$calendar <- list(events=readboj:::parse_outlook_calendar(files$calendar,holiday),
    holidays=holiday,sources=list(calendar=list(raw_sha256=strrep('a',64)),holidays=list(raw_sha256=strrep('b',64))))
  state$now <- as.POSIXct('2026-10-29 14:00:00',tz='UTC')
  state$calendar_calls <- state$probe_calls <- state$head_calls <- 0L
  state$update_calls <- list()
  state$calendar_failure <- FALSE
  state$probe_failure <- FALSE
  state$head_version <- NULL
  real_update <- readboj::update_boj_outlook
  testthat::local_mocked_bindings(outlook_now=function() state$now,
    outlook_fetch_calendar=function(...) {
      state$calendar_calls <- state$calendar_calls+1L
      if(state$calendar_failure) stop('fixture calendar unavailable')
      value <- state$calendar;value$checked_at<-state$now;value
    },
    outlook_probe_archive=function(...) {
      state$probe_calls <- state$probe_calls+1L
      if(state$probe_failure) stop('fixture archive probe failed')
      list(catalogue=state$catalogue,receipt=list(raw_sha256=strrep('c',64)))
    },
    outlook_probe_asset=function(url,previous,...) {
      state$head_calls <- state$head_calls+1L
      list(changed=!is.null(state$head_version) && !identical(previous$etag,state$head_version),
        supported=TRUE,etag=state$head_version,last_modified=NA_character_)
    },
    update_boj_outlook=function(...) {
      args<-list(...);state$update_calls[[length(state$update_calls)+1L]]<-args
      if(is.null(args$wait)) args$wait<-0
      do.call(real_update,args)
    },.package='readboj',.env=env)
  readboj:::outlook_write_check(state$directory,list(status='unchanged',attempted_at=state$now,
    last_successful_check=state$now,parser_sha256=state$parser))
  state
}

outlook_fixture_add_edition <- function(state,release,date,full=FALSE) {
  row<-state$catalogue[1,,drop=FALSE]
  row$release<-release;row$publication_date<-as.Date(date)
  row$banks_view_url<-paste0('https://www.boj.or.jp/en/mopo/outlook/gor',substr(release,3,4),substr(release,6,7),'a.pdf')
  row$full_text_url<-if(full) sub('a.pdf','b.pdf',row$banks_view_url,fixed=TRUE) else NA_character_
  row$full_text_date<-if(full) as.Date(date)+3 else as.Date(NA)
  state$catalogue<-rbind(row,state$catalogue[state$catalogue$release!=release,,drop=FALSE])
  invisible(row)
}
