test_that("representative official BOJ surfaces remain live", {
  skip_if(tolower(Sys.getenv("READBOJ_LIVE_TESTS")) != "true")
  cache <- tempfile("readboj-live-")
  cases <- list(
    list("IR01", "MADR1Z@D", "202607", "202607"),
    list("FM01", "STRDCLUCON", "202607", "202607"),
    list("MD01", "MABS1AN11", "202601", "202606"),
    list("MD02", "MAM1NAM2M2MO", "202601", "202606"),
    list("BS01", "MABJMA5", "202601", "202606"),
    list("FM08", "FXERM07", "202601", "202606"),
    list("CO", "TK99F0000601GCQ00000", "202501", "202604")
  )
  for (case in cases) {
    out <- read_boj_series(case[[1L]], case[[2L]], case[[3L]], case[[4L]],
      cache_dir = cache, wait = 1, max_cells = 10000L)
    expect_true(nrow(out) > 0L)
    expect_identical(unique(out$db), case[[1L]])
    expect_match(boj_provenance(out)$pages[[1L]]$raw_sha256, "^[0-9a-f]{64}$")
  }

  metadata <- boj_metadata("FM08", language = "both", cache_dir = cache, wait = 1)
  fx <- metadata[metadata$series_code == "FXERM07", ]
  expect_equal(nrow(fx), 1L)
  expect_true(nzchar(fx$name_en) && nzchar(fx$name_jp))
  expect_match(boj_provenance(metadata)$api_date, "^2026-")

  ir02 <- search_boj_series(".", "IR02", language = "both", regex = TRUE,
    limit = 5L, cache_dir = cache, refresh = TRUE, wait = 1)
  expect_equal(nrow(ir02), 5L)
  expect_true(all(nzchar(ir02$name_en)))
  expect_true(all(nzchar(ir02$name_jp)))
  expect_identical(boj_provenance(ir02)$transfer_encoding, "CP932")

  fx_jp <- read_boj_series("FM08", "FXERM07", "202601", "202606",
    language = "jp", format = "csv", cache_dir = cache, wait = 1)
  expect_identical(unique(fx_jp$series_code), "FXERM07")
  expect_true(all(nzchar(fx_jp$name_jp)))

  layer <- read_boj_layer("IR01", "D", "*", "202607", "202607",
    format = "csv", cache_dir = cache, wait = 1, max_cells = 1000L)
  expect_true(nrow(layer) > 0L)
  expect_identical(unique(layer$db), "IR01")

  bulk <- list_boj_bulk_files("en", cache_dir = cache)
  expect_gte(nrow(bulk), 16L)
  expect_true(all(grepl("stat-search.boj.or.jp", bulk$url, fixed = TRUE)))
  bulk_file <- download_boj_bulk("cgpi_m_en.zip", cache_dir = cache, max_bytes = 5 * 1024^2)
  expect_match(boj_provenance(bulk_file)$raw_sha256, "^[0-9a-f]{64}$")
  bulk_data <- read_boj_bulk(bulk_file, max_uncompressed_bytes = 10 * 1024^2,
    max_rows = 100000L)
  expect_true(NROW(bulk_data) > 0L)

  releases <- list_boj_tankan_releases("en", cache_dir = cache, wait = 1)
  expect_true(nrow(releases) > 0L)
  assets <- list_boj_tankan_assets(releases$url[[1L]], cache_dir = cache)
  expect_true(any(grepl("\\.zip$", assets$url, ignore.case = TRUE)))
  workbook <- assets$url[grepl("\\.xlsx?$", assets$url, ignore.case = TRUE)][[1L]]
  workbook_file <- download_boj_tankan_asset(workbook, cache_dir = cache,
    max_bytes = 20 * 1024^2)
  expect_match(boj_provenance(workbook_file)$raw_sha256, "^[0-9a-f]{64}$")
})
