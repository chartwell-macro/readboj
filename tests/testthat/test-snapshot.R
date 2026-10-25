test_that("offline data snapshot retains null rows and exact provenance", {
  path <- fixture_path("api-data-page-1.json")
  out <- read_boj_snapshot(path, "data_json", "FM08")
  expect_equal(nrow(out), 3L)
  expect_identical(out$period, c("202601", "202602", "202603"))
  expect_true(is.na(out$value[[2L]]))
  expect_identical(out$date, as.Date(c("2026-01-01", "2026-02-01", "2026-03-01")))
  provenance <- boj_provenance(out)
  expect_match(provenance$raw_sha256, "^[0-9a-f]{64}$")
  expect_match(provenance$semantic_sha256, "^[0-9a-f]{64}$")
  expect_identical(provenance$bytes, unname(file.info(path)$size))
})

test_that("semantic hash ignores only volatile API DATE", {
  first <- fixture_path("api-data-page-1.json")
  second <- tempfile(fileext = ".json")
  text <- readLines(first, warn = FALSE)
  text <- sub("2026-08-02T00:00:00+09:00", "2026-08-03T00:00:00+09:00", text,
    fixed = TRUE)
  writeLines(text, second, useBytes = TRUE)
  expect_false(identical(readboj:::sha256_file(first), readboj:::sha256_file(second)))
  expect_identical(readboj:::semantic_json_hash(first), readboj:::semantic_json_hash(second))
})

test_that("snapshot byte bound is enforced before parsing", {
  expect_error(
    read_boj_snapshot(fixture_path("api-data-page-1.json"), "data_json", "FM08", max_bytes = 10),
    class = "readboj_size_error"
  )
})
