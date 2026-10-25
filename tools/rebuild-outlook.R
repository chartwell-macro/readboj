#!/usr/bin/env Rscript
# Repository maintenance only: review the changed numeric bundle before release.
suppressPackageStartupMessages(library(readboj))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop('Supply the explicit output .rds path.')
build_boj_outlook_bundle(args[[1L]], refresh = TRUE,
  deadline = Sys.time() + 1800)
