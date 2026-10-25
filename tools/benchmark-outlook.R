#!/usr/bin/env Rscript
# Run from the repository after dependencies are provisioned. Uses only local
# structured data and deterministic update fixtures, never network. Optional
# READBOJ_OUTLOOK_ARCHIVE_DIR also measures genuine parsing with local PDFs.
args <- commandArgs(trailingOnly=TRUE)
if(length(args)!=1L || !dir.exists(args[[1L]])) stop('Supply an existing evidence directory')
evidence <- normalizePath(args[[1L]])
pkgload::load_all('.',quiet=TRUE)
source('tests/testthat/helper-fixtures.R')
source('tests/testthat/helper-outlook-saved.R')
base <- outlook_saved_fixture()
private <- tempfile('outlook-benchmark-',tmpdir=evidence);dir.create(private)
local({
  withr::defer(unlink(private,recursive=TRUE))
  empty <- file.path(private,'ordinary')
  memo <- readboj:::.readboj_outlook_memo
  clock <- function(expr) unname(system.time(force(expr))[['elapsed']])
  measure <- function(directory) {
    cold <- replicate(10,{memo$loaded<-NULL;clock(read_boj_outlook('all',comparison='all',data_dir=directory))})
    warm <- replicate(100,clock(read_boj_outlook('latest',measure='real_gdp',statistic='median',data_dir=directory)))
    list(cold_seconds=list(min=min(cold),median=median(cold),max=max(cold)),
      warm_seconds=list(min=min(warm),median=median(warm),max=max(warm)))
  }
  ordinary <- measure(empty)
  allocation <- file.path(private,'allocations')
  memo$loaded<-NULL
  if(capabilities('profmem')) {
    Rprofmem(allocation)
    result <- read_boj_outlook('all',comparison='all',data_dir=empty)
    Rprofmem(NULL)
    lines <- readLines(allocation)
    allocated <- suppressWarnings(as.numeric(sub(' .*','',lines)))
    ordinary$allocated_bytes <- sum(allocated,na.rm=TRUE)
  }
  ordinary$dataset_object_bytes <- as.numeric(object.size(base))
  ordinary$bundle_bytes <- file.info(system.file('extdata','outlook-saved.rds',package='readboj'))$size
  ordinary$files_written_by_read <- length(list.files(empty,recursive=TRUE,all.files=TRUE))
  # Add twenty distinct synthetic edition identities, purely for capacity timing.
  # This is 94 editions / 5,222 rows, above both 25% headroom thresholds.
  headroom <- base
  template <- base$catalogue[1,,drop=FALSE]
  for(i in seq_len(20L)) {
    date <- seq(as.Date('2026-08-01'),by='month',length.out=20L)[[i]]
    release <- format(date,'%Y-%m')
    publication <- template
    publication$release <- release; publication$publication_date <- date
    publication$banks_view_url <- paste0('https://www.boj.or.jp/en/mopo/outlook/gor',format(date,'%y%m'),'a.pdf')
    publication$full_text_url <- NA_character_;publication$full_text_date <- as.Date(NA)
    d <- base$data[base$data$release==template$release,,drop=FALSE]
    d$release <- release;d$forecast_vintage[d$comparison=='current'] <- release
    d$publication_date <- date;d$source_url<-publication$banks_view_url
    p <- base$editions[[template$release]];p$release<-release;p$publication_date<-date
    p$canonical_url<-p$final_url<-publication$banks_view_url
    p$full_text_url<-NA_character_;p$full_text_date<-as.Date(NA)
    headroom$editions[[release]]<-p
    e <- base$assets[[template$banks_view_url]];e$canonical_url<-e$final_url<-publication$banks_view_url
    headroom$assets[[publication$banks_view_url]]<-e
    headroom$catalogue<-rbind(publication,headroom$catalogue)
    headroom$data<-rbind(d,headroom$data)
  }
  rownames(headroom$data)<-rownames(headroom$catalogue)<-NULL
  headroom$editions<-headroom$editions[headroom$catalogue$release]
  headroom<-readboj:::outlook_saved_seal(headroom)
  head_dir<-file.path(private,'headroom');dir.create(head_dir)
  lock<-readboj:::outlook_update_lock(head_dir)
  publication<-readboj:::outlook_publish(headroom,head_dir,lock,character())
  readboj:::outlook_release_lock(lock)
  capacity<-measure(head_dir)
  capacity$editions<-nrow(headroom$catalogue);capacity$rows<-nrow(headroom$data)
  capacity$serialized_bytes<-publication$bytes
  capacity$object_bytes<-as.numeric(object.size(headroom))
  # Update fixtures isolate parse/disk cost from public network latency. Their
  # source body/hash mapping is mocked; the live no-change run is recorded apart.
  updates <- local({
    state<-outlook_update_fixture()
    directory<-file.path(private,'updates')
    inventory<-function() {
      paths<-list.files(directory,recursive=TRUE,all.files=TRUE,full.names=TRUE)
      paths<-paths[!dir.exists(paths)]
      setNames(file.info(paths)$size,paths)
    }
    run<-function() {
      before<-inventory()
      seconds<-clock(status<-update_boj_outlook(directory,force=TRUE,wait=0))
      after<-inventory();added<-setdiff(names(after),names(before))
      list(seconds=seconds,status=status$status,requests=status$requests,
        parsed_editions=status$parsed_editions,raw_bytes=status$downloaded_bytes,
        durable_new_files=length(added),durable_new_bytes=sum(after[added]),
        snapshot_bytes=status$publication$bytes)
    }
    unchanged<-run()
    extra<-state$catalogue[1,,drop=FALSE];extra$release<-'2027-01'
    extra$publication_date<-as.Date('2027-01-29');extra$full_text_date<-as.Date(NA)
    extra$banks_view_url<-'https://www.boj.or.jp/en/mopo/outlook/gor2701a.pdf';extra$full_text_url<-NA_character_
    state$catalogue<-rbind(extra,state$catalogue)
    new<-run()
    url<-state$catalogue$banks_view_url[state$catalogue$release=='2017-10']
    state$changes[[url]]<-'historical revision'
    revised<-run()
    list(no_change=unchanged,one_new_edition=new,one_historical_revision=revised)
  })
  archive_updates <- NULL
  corpus <- Sys.getenv('READBOJ_OUTLOOK_ARCHIVE_DIR')
  if(nzchar(corpus)) archive_updates <- local({
    inventory <- read.csv(file.path(corpus,'archive-assets.csv'))
    paths <- setNames(file.path(corpus,'sources',paste0(inventory$release,'-',inventory$kind,'.',inventory$format)),inventory$url)
    directory <- file.path(private,'actual-parser-updates');dir.create(directory)
    seed <- base
    latest <- seed$catalogue$release[[1L]]
    removed_urls <- na.omit(c(seed$catalogue$banks_view_url[[1L]],seed$catalogue$full_text_url[[1L]]))
    seed$catalogue <- seed$catalogue[seed$catalogue$release!=latest,,drop=FALSE]
    seed$data <- seed$data[seed$data$release!=latest,,drop=FALSE];rownames(seed$data)<-NULL
    seed$editions[[latest]] <- NULL;seed$assets[removed_urls]<-NULL
    seed <- readboj:::outlook_saved_seal(seed)
    lock<-readboj:::outlook_update_lock(directory)
    readboj:::outlook_publish(seed,directory,lock,character())
    readboj:::outlook_release_lock(lock)
    revision_url <- NULL
    revised_pdf <- file.path(private,'controlled-revision.pdf')
    meta_bytes <- extract_bytes <- 0
    atomic <- readboj:::outlook_atomic_rds
    pdf <- readboj:::run_outlook_pdf
    testthat::local_mocked_bindings(
      outlook_parser_fingerprint=function() base$parser_sha256,
      outlook_atomic_rds=function(x,destination,...) {
        value<-atomic(x,destination,...)
        meta_bytes<<-meta_bytes+file.info(destination)$size
        value
      },
      run_outlook_pdf=function(command,args,log,deadline) {
        value<-pdf(command,args,log,deadline)
        if(file.exists(log)) extract_bytes<<-extract_bytes+file.info(log)$size
        output<-utils::tail(args,1L)
        if(length(args)>1L && file.exists(output)) extract_bytes<<-extract_bytes+file.info(output)$size
        value
      },
      outlook_update_request=function(url,previous,path,...) {
        if(endsWith(url,'/index.htm')) {
          writeLines(outlook_index_from_catalogue(base$catalogue),path)
          return(fixture_entry(path,url))
        }
        if(!is.null(previous) && !identical(url,revision_url)) {
          previous$path<-NULL;previous$http_status<-304L
          return(previous)
        }
        source<-if(identical(url,revision_url)) revised_pdf else paths[[url]]
        stopifnot(file.copy(source,path,overwrite=TRUE))
        fixture_entry(path,url)
      },.package='readboj')
    run<-function() {
      meta_bytes<<-extract_bytes<<-0
      seconds<-clock(status<-update_boj_outlook(directory,force=TRUE,wait=0))
      list(seconds=seconds,status=status$status,parsed_editions=status$parsed_editions,
        requests=status$requests,raw_body_bytes_written=status$downloaded_bytes,
        extractor_bytes_written=extract_bytes,metadata_bytes_written=meta_bytes,
        snapshot_bytes_written=status$publication$bytes,
        total_content_bytes_written=status$downloaded_bytes+extract_bytes+meta_bytes+status$publication$bytes)
    }
    added <- run()
    # A controlled byte revision of an official historical PDF, preserving its
    # numeric content. This is a cost/detection fixture, not an upstream revision.
    revision_url <- base$catalogue$banks_view_url[base$catalogue$release=='2017-10']
    stopifnot(file.copy(paths[[revision_url]],revised_pdf))
    con<-file(revised_pdf,'ab');writeBin(charToRaw('\n% readboj controlled benchmark revision\n'),con);close(con)
    revised<-run()
    list(one_added_official_edition_73_to_74=added,
      one_controlled_historical_byte_revision=revised,
      note='Real parser and Poppler; local source transport. Byte revision preserves official table values. Content bytes include transient files, excluding filesystem metadata/journaling.')
  })
  output<-list(measured_at=format(Sys.time(),tz='UTC',usetz=TRUE),R=R.version.string,
    budgets=list(cold_seconds=1,warm_seconds=.25,headroom_editions=93,headroom_rows=5178),
    full_corpus=ordinary,synthetic_headroom=capacity,deterministic_updates=updates,
    archived_source_parser_updates=archive_updates)
  jsonlite::write_json(output,file.path(evidence,'performance.json'),auto_unbox=TRUE,pretty=TRUE,null='null',digits=9)
  saveRDS(output,file.path(evidence,'performance.rds'))
  print(output)
  stopifnot(ordinary$cold_seconds$max<=1,ordinary$warm_seconds$max<=.25,
    capacity$cold_seconds$max<=1,capacity$warm_seconds$max<=.25,
    capacity$editions>=93,capacity$rows>=5178)
})
