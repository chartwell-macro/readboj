test_that("portable catalogue snapshot is pinned, complete, and searchable offline", {
  fixture <- fixture_path("metadata-bilingual-cp932.csv")
  testthat::local_mocked_bindings(
    metadata_snapshot = function(db, language, cache_dir, refresh, offline,
        max_age, timeout, retries, wait, max_bytes, deadline) {
      list(entry = fixture_entry(fixture,
        paste0("https://www.stat-search.boj.or.jp/api/v1/getMetadata?db=", db,
          "&format=csv&lang=jp")), encoding = "CP932",
        preamble = c(STATUS = "200", MESSAGEID = "M181000I",
          DATE = "2026-08-02T00:00:00+09:00"))
    }, .package = "readboj"
  )
  destination <- tempfile("boj-catalogue-")
  manifest <- build_boj_catalogue_snapshot(destination, db = "FM08", wait = 0,
    max_rows_per_db = 10L, max_total_bytes = 100000L)
  expect_identical(manifest$db, "FM08")
  expect_equal(manifest$series_count, 2L)
  expect_true(manifest$complete_within_database)
  expect_false(boj_provenance(manifest)$complete_declared_surface)
  expect_match(boj_provenance(manifest)$manifest_sha256, "^[0-9a-f]{64}$")
  result <- search_boj_catalogue_snapshot(destination, "月次金利", db = "FM08")
  expect_identical(result$series_code, "SYNTHM02")
  expect_match(boj_provenance(result)$manifest_sha256, "^[0-9a-f]{64}$")
})

test_that("catalogue object corruption and absent database fail closed", {
  fixture <- fixture_path("metadata-bilingual-cp932.csv")
  testthat::local_mocked_bindings(
    metadata_snapshot = function(db, language, cache_dir, refresh, offline,
        max_age, timeout, retries, wait, max_bytes, deadline) {
      list(entry = fixture_entry(fixture,
        paste0("https://www.stat-search.boj.or.jp/api/v1/getMetadata?db=", db,
          "&format=csv&lang=jp")), encoding = "CP932",
        preamble = c(STATUS = "200", MESSAGEID = "M181000I",
          DATE = "2026-08-02T00:00:00+09:00"))
    }, .package = "readboj"
  )
  destination <- tempfile("boj-catalogue-")
  build_boj_catalogue_snapshot(destination, db = "FM08", wait = 0)
  expect_error(search_boj_catalogue_snapshot(destination, "x", db = "CO"),
    class = "readboj_identity_error")
  object <- list.files(file.path(destination, "objects"), full.names = TRUE)[[1L]]
  writeLines("tampered", object)
  expect_error(search_boj_catalogue_snapshot(destination, "x"),
    class = "readboj_cache_corruption_error")
})

