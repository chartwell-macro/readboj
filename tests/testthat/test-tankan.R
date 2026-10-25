test_that("Tankan assets are restricted to official workbook and ZIP links", {
  release <- fixture_path("tankan-release.html")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, ...) fixture_entry(release, url),
    .package = "readboj"
  )
  out <- list_boj_tankan_assets(
    "https://www.boj.or.jp/en/statistics/tk/zenyo/2026/all2606.htm")
  expect_identical(sort(out$id), c("all2606.xlsx", "all2606.zip"))
  expect_false(any(grepl("pdf$", out$url)))
  expect_match(boj_provenance(out)$raw_sha256, "^[0-9a-f]{64}$")
})

test_that("Tankan release discovery follows bounded range indexes", {
  root <- fixture_path("tankan-root.html")
  range <- fixture_path("tankan-range.html")
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, ...) fixture_entry(
      if (grepl("/index.htm$", url) && !grepl("/20(21|26)/", url)) root else range, url),
    .package = "readboj"
  )
  out <- list_boj_tankan_releases(wait = 0)
  expect_equal(nrow(out), 1L)
  expect_identical(out$id, "all2606")
})

