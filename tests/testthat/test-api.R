test_that("exact API cursor is followed and missing cells remain", {
  positions <- character()
  page1 <- fixture_path("api-data-page-1.json")
  page2 <- fixture_path("api-data-page-2.json")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) {
      position <- query$startPosition %||% ""
      positions <<- c(positions, position)
      path <- if (identical(position, "")) page1 else page2
      fixture_entry(path, readboj:::canonical_url(url, query))
    }, .package = "readboj"
  )
  out <- read_boj_series("FM08", "SYNTHM01", wait = 0, max_cells = 10L)
  expect_identical(positions, c("", "255"))
  expect_equal(nrow(out), 5L)
  expect_true(anyNA(out$value))
  expect_equal(length(boj_provenance(out)$pages), 2L)
  expect_equal(boj_provenance(out)$total_cells, 5L)
  expect_identical(boj_provenance(out)$pages[[1L]]$api_date,
    "2026-08-02T00:00:00+09:00")
})

test_that("repeated cursors and cell excess fail closed", {
  page1 <- fixture_path("api-data-page-1.json")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) fixture_entry(page1,
      readboj:::canonical_url(url, query)), .package = "readboj"
  )
  expect_error(read_boj_series("FM08", "SYNTHM01", wait = 0),
    class = "readboj_pagination_error")
  expect_error(read_boj_series("FM08", "SYNTHM01", wait = 0, max_cells = 2L),
    class = "readboj_size_error")
})

test_that("code requests batch at 250 series", {
  calls <- list()
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) {
      calls[[length(calls) + 1L]] <<- strsplit(query$code, ",", fixed = TRUE)[[1L]]
      page <- tempfile(fileext = ".json")
      write_synthetic_response(page, next_position = NULL,
        code = calls[[length(calls)]][[1L]])
      fixture_entry(page, readboj:::canonical_url(url, query))
    }, .package = "readboj"
  )
  codes <- sprintf("S%03d", 1:251)
  suppressWarnings(read_boj_series("FM08", codes, wait = 0, max_cells = 10L))
  expect_identical(lengths(calls), c(250L, 1L))
})

test_that("duplicate identities fail closed without row collapse", {
  duplicate <- tempfile(fileext = ".json")
  payload <- jsonlite::fromJSON(fixture_path("api-data-page-1.json"),
    simplifyVector = FALSE)
  payload$NEXTPOSITION <- NULL
  payload$RESULTSET <- c(payload$RESULTSET, payload$RESULTSET)
  writeLines(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null"), duplicate)
  expect_error(read_boj_snapshot(duplicate, "data_json", "FM08"),
    class = "readboj_identity_error")
})

test_that("HTTP error JSON is retained and raised as a typed API error", {
  error_path <- tempfile(fileext = ".json")
  writeLines('{"STATUS":400,"MESSAGEID":"M181013E","MESSAGE":"Synthetic invalid code","DATE":"2026-08-02T00:00:00+09:00","RESULTSET":[]}',
    error_path, useBytes = TRUE)
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) {
      entry <- fixture_entry(error_path, readboj:::canonical_url(url, query))
      entry$http_status <- 400L
      entry
    }, .package = "readboj"
  )
  error <- expect_error(read_boj_series("FM08", "INVALID", wait = 0),
    class = "readboj_api_error")
  expect_identical(error$message_id, "M181013E")
  expect_identical(error$status, 400L)
})

test_that("official CSV pagination, blank markers, and bilingual encoding are preserved", {
  positions <- character()
  page1 <- fixture_path("api-data-en-page-1.csv")
  page2 <- fixture_path("api-data-en-page-2.csv")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) {
      position <- query$startPosition %||% ""
      positions <<- c(positions, position)
      path <- if (identical(position, "")) page1 else page2
      fixture_entry(path, readboj:::canonical_url(url, query))
    }, .package = "readboj"
  )
  out <- read_boj_series("FM08", "SYNTHM01", format = "csv", wait = 0)
  expect_identical(positions, c("", "255"))
  expect_equal(nrow(out), 5L)
  expect_identical(out$value_status[[2L]], "blank")
  expect_identical(out$raw_value[[2L]], "")
  expect_true(is.na(out$value[[2L]]))
  expect_identical(boj_provenance(out)$pages[[1L]]$response_encoding, "UTF-8")

  jp <- read_boj_snapshot(fixture_path("api-data-jp-cp932.csv"),
    type = "data_csv", db = "FM08", language = "jp", encoding = "CP932")
  expect_true(all(jp$name_jp == "合成月次指数"))
  expect_true(all(is.na(jp$name_en)))
})
