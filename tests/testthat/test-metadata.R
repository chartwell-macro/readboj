test_that("bilingual metadata has stable paired fields", {
  path <- fixture_path("metadata-bilingual-utf8.csv")
  out <- read_boj_snapshot(path, "metadata_csv", "FM08", encoding = "UTF-8")
  expect_equal(nrow(out), 3L)
  series <- out[out$series_code == "SYNTHM01", ]
  expect_identical(series$name_en, "Synthetic monthly index")
  expect_identical(series$name_jp, "合成月次指数")
  expect_identical(series$notes_en, "Synthetic note")
  expect_identical(series$notes_jp, "合成注記")
  expect_false(out$is_series[[1L]])
})

test_that("CP932 metadata behavior is deterministic", {
  source <- fixture_path("metadata-bilingual-utf8.csv")
  target <- tempfile(fileext = ".csv")
  input <- file(source, open = "r", encoding = "UTF-8")
  output <- file(target, open = "w", encoding = "CP932")
  on.exit({ close(input); close(output) }, add = TRUE)
  writeLines(readLines(input, warn = FALSE), output, useBytes = TRUE)
  close(input); close(output)
  on.exit(NULL, add = FALSE)
  out <- read_boj_snapshot(target, "metadata_csv", "FM08", encoding = "CP932")
  expect_identical(out$name_jp[out$series_code == "SYNTHM02"], "合成月次金利")
  expect_identical(out$name_en[out$series_code == "SYNTHM02"], "Synthetic monthly rate")
})

test_that("bounded CP932 validation never ends inside a multibyte character", {
  path <- tempfile(fileext = ".csv")
  japanese <- iconv("あ", from = "UTF-8", to = "CP932", toRaw = TRUE)[[1L]]
  writeBin(c(charToRaw("A\n"), japanese, charToRaw("\n")), path)

  decoded <- readboj:::decode_complete_line_prefix(path, "CP932", 3L)
  expect_identical(decoded, "A\n")

  invalid <- tempfile(fileext = ".csv")
  writeBin(c(charToRaw("A"), as.raw(0x80), charToRaw("\n")), invalid)
  expect_true(is.na(readboj:::decode_complete_line_prefix(
    invalid,
    "CP932",
    3L
  )))
})

test_that("metadata schema drift and row limits fail closed", {
  source <- readLines(fixture_path("metadata-bilingual-utf8.csv"), warn = FALSE)
  drift <- tempfile(fileext = ".csv")
  source[[6L]] <- sub(",NOTES$", ",NOTES_OLD", source[[6L]])
  writeLines(source, drift, useBytes = TRUE)
  expect_error(read_boj_snapshot(drift, "metadata_csv", "FM08"),
    class = "readboj_schema_error")
  expect_error(read_boj_snapshot(fixture_path("metadata-bilingual-utf8.csv"),
    "metadata_csv", "FM08", max_rows = 1L), class = "readboj_size_error")
})

test_that("chunked search is bilingual, bounded, and does not eagerly admit CO", {
  path <- fixture_path("metadata-bilingual-utf8.csv")
  english <- readboj:::search_chunked_metadata(path, "FM08", "UTF-8", "monthly",
    FALSE, 1L, FALSE, "both")
  japanese <- readboj:::search_chunked_metadata(path, "FM08", "UTF-8", "月次金利",
    FALSE, 10L, FALSE, "both")
  expect_equal(nrow(english), 1L)
  expect_identical(japanese$series_code, "SYNTHM02")
  expect_lt(as.numeric(object.size(english)), 100000)
  expect_error(boj_metadata("CO"), class = "readboj_size_error")
})

test_that("metadata preamble identity is preserved", {
  path <- fixture_path("metadata-bilingual-cp932.csv")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, query, ...) fixture_entry(path,
      readboj:::canonical_url(url, query)), .package = "readboj"
  )
  out <- boj_metadata("FM08", language = "both", max_rows = 10L)
  expect_identical(boj_provenance(out)$api_date, "2026-08-02T00:00:00+09:00")
  expect_identical(boj_provenance(out)$api_message_id, "M181000I")
})
