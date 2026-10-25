test_that("bulk catalogue fixture exposes only downloadable data", {
  links <- readboj:::html_links(fixture_path("bulk-catalogue.html"),
    "https://www.stat-search.boj.or.jp/info/dload_en.html")
  files <- links[grepl("\\.(zip|csv)$", links$url), ]
  expect_identical(basename(files$url), c("fof.zip", "co.zip"))
})

test_that("headerless long bulk CSV is normalized without losing missing markers", {
  csv <- tempfile(fileext = ".csv")
  writeLines(c("SYNTHM01,MONTHLY,202601,101.5", "SYNTHM01,MONTHLY,202602,NA"), csv)
  out <- read_boj_bulk(csv, max_rows = 10L)
  expect_identical(names(out)[1:4], c("series_code", "frequency", "period", "value"))
  expect_equal(nrow(out), 2L)
  expect_identical(out$value[[2L]], "NA")
  expect_true(is.na(out$value_numeric[[2L]]))
  expect_identical(out$value_status[[2L]], "NA")
  expect_match(boj_provenance(out)$raw_sha256, "^[0-9a-f]{64}$")
  expect_identical(boj_provenance(out)$parser, "read_boj_bulk/csv")
})

test_that("bulk ZIP expansion and row bounds are enforced", {
  directory <- tempfile("bulk-files-")
  dir.create(directory)
  csv <- file.path(directory, "synthetic.csv")
  writeLines(c("series_code,frequency,period,value", "S1,MONTHLY,202601,1"), csv)
  zip <- tempfile(fileext = ".zip")
  old <- setwd(directory); on.exit(setwd(old), add = TRUE)
  utils::zip(zip, "synthetic.csv", flags = "-q")
  setwd(old); on.exit(NULL, add = FALSE)
  out <- read_boj_bulk(zip, max_uncompressed_bytes = 10000, max_rows = 10L)
  expect_equal(nrow(out), 1L)
  expect_error(read_boj_bulk(zip, max_uncompressed_bytes = 1),
    class = "readboj_archive_error")
})

test_that("workbook reader preserves identifiers and markers as bounded text", {
  skip_if_not_installed("writexl")
  workbook <- tempfile(fileext = ".xlsx")
  writexl::write_xlsx(list(catalogue = data.frame(
    series_code = c("S1", "S2"), unit = c("Index", "%"),
    marker = c("ND", "NA"), stringsAsFactors = FALSE)), workbook)
  out <- read_boj_workbook(workbook, max_rows_per_sheet = 10L,
    max_columns = 10L, max_cells = 100L)
  expect_identical(out$catalogue$series_code, c("S1", "S2"))
  expect_identical(out$catalogue$marker, c("ND", "NA"))
  expect_match(boj_provenance(out)$raw_sha256, "^[0-9a-f]{64}$")
  expect_identical(boj_provenance(out)$parser, "read_boj_workbook/text")
  expect_error(read_boj_workbook(workbook, max_cells = 1L),
    class = "readboj_size_error")
})
