synthetic_response <- function(url, status = 200L, headers = list()) {
  httr2::new_response(method = "GET", url = url, status_code = status,
    headers = headers, body = raw())
}

test_that("transport rejects non-official hosts and expired deadlines", {
  expect_error(readboj:::fetch_snapshot("https://example.com/data"),
    class = "readboj_config_error")
  expect_error(readboj:::fetch_snapshot(
    "https://www.stat-search.boj.or.jp/api/v1/getMetadata",
    cache_dir = tempfile(), deadline = Sys.time() - 1),
    class = "readboj_timeout_error")
})

test_that("only transient transport failures are retried", {
  calls <- 0L
  testthat::local_mocked_bindings(
    perform_once = function(canonical, path, timeout, max_bytes) {
      calls <<- calls + 1L
      if (calls < 3L) stop("connection reset by peer")
      writeLines("success", path)
      synthetic_response(canonical, 200L, list(date = "Sat, 01 Aug 2026 15:00:00 GMT"))
    },
    deadline_pause = function(...) invisible(NULL),
    .package = "readboj"
  )
  out <- readboj:::fetch_snapshot(
    "https://www.stat-search.boj.or.jp/info/synthetic.csv",
    cache_dir = tempfile(), retries = 3L, wait = 0)
  expect_equal(calls, 3L)
  expect_match(out$raw_sha256, "^[0-9a-f]{64}$")

  calls <- 0L
  testthat::local_mocked_bindings(
    perform_once = function(...) { calls <<- calls + 1L; stop("certificate invalid") },
    .package = "readboj"
  )
  expect_error(readboj:::fetch_snapshot(
    "https://www.stat-search.boj.or.jp/info/synthetic.csv",
    cache_dir = tempfile(), retries = 3L, wait = 0),
    class = "readboj_transport_error")
  expect_equal(calls, 1L)
})

test_that("HTTP errors are typed and never enter the success cache", {
  cache <- tempfile("readboj-error-cache-")
  error_body <- '{"STATUS":400,"MESSAGEID":"M181013E","MESSAGE":"Invalid code"}'
  testthat::local_mocked_bindings(
    perform_once = function(canonical, path, timeout, max_bytes) {
      writeLines(error_body, path, useBytes = TRUE)
      synthetic_response(canonical, 400L,
        list(`content-type` = "application/json"))
    }, .package = "readboj"
  )
  error <- expect_error(readboj:::fetch_snapshot(
    "https://www.stat-search.boj.or.jp/api/v1/getDataCode",
    cache_dir = cache, retries = 0L), class = "readboj_api_error")
  expect_identical(error$message_id, "M181013E")
  expect_length(list.files(file.path(cache, "objects")), 0L)
  expect_length(list.files(file.path(cache, "requests")), 0L)
})

