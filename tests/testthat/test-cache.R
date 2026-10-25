test_that("request cache supports exact offline replay", {
  cache <- tempfile("readboj-cache-")
  readboj:::ensure_cache_dir(cache)
  source <- tempfile()
  file.copy(fixture_path("api-data-page-1.json"), source)
  url <- "https://www.stat-search.boj.or.jp/api/v1/getDataCode?db=FM08"
  entry <- fixture_entry(source, url)
  entry$cache_status <- NULL
  saved <- readboj:::write_cache_entry(cache, entry, source)
  replay <- readboj:::fetch_snapshot("https://www.stat-search.boj.or.jp/api/v1/getDataCode",
    query = list(db = "FM08"), cache_dir = cache, offline = TRUE, max_age = Inf)
  expect_identical(replay$raw_sha256, saved$raw_sha256)
  expect_identical(replay$cache_status, "hit")
  expect_identical(readboj:::sha256_file(replay$path), replay$raw_sha256)
})

test_that("offline mode fails without a matching snapshot", {
  expect_error(readboj:::fetch_snapshot("https://www.stat-search.boj.or.jp/api/v1/missing",
    cache_dir = tempfile("empty-cache-"), offline = TRUE), class = "readboj_offline_error")
})

test_that("cache pruning respects entry and byte bounds", {
  cache <- tempfile("readboj-cache-")
  readboj:::ensure_cache_dir(cache)
  for (i in 1:3) {
    source <- tempfile()
    writeLines(paste(rep(as.character(i), i * 10), collapse = ""), source)
    entry <- fixture_entry(source, paste0("https://example.invalid/", i))
    entry$cache_status <- NULL
    readboj:::write_cache_entry(cache, entry, source)
    Sys.setFileTime(readboj:::cache_object_path(cache, entry$raw_sha256), Sys.time() + i)
  }
  result <- boj_cache_prune(cache, max_entries = 1L, max_bytes = 1000)
  expect_equal(result$removed, 2L)
  expect_equal(result$remaining, 1L)
})

test_that("automatic cache bounds preserve the just-fetched object", {
  cache <- tempfile("readboj-cache-")
  old_options <- options(readboj.cache_max_entries = 1L,
    readboj.cache_max_bytes = 1000)
  on.exit(options(old_options), add = TRUE)
  readboj:::ensure_cache_dir(cache)
  for (i in 1:2) {
    source <- tempfile()
    writeLines(paste0("object-", i), source)
    entry <- fixture_entry(source, paste0("https://example.invalid/auto-", i))
    entry$cache_status <- NULL
    saved <- readboj:::write_cache_entry(cache, entry, source)
    readboj:::prune_cache_objects(cache, 1000, 1L, saved$raw_sha256)
    expect_true(file.exists(saved$path))
  }
  expect_equal(length(list.files(file.path(cache, "objects"))), 1L)
})

test_that("cache corruption and query mismatch fail closed", {
  cache <- tempfile("readboj-cache-")
  readboj:::ensure_cache_dir(cache)
  source <- tempfile()
  writeLines("original", source)
  url <- "https://www.stat-search.boj.or.jp/api/v1/getMetadata?db=FM08"
  entry <- fixture_entry(source, url)
  entry$cache_status <- NULL
  saved <- readboj:::write_cache_entry(cache, entry, source)
  writeLines("tampered", saved$path)
  expect_error(readboj:::read_cache_entry(cache, url),
    class = "readboj_cache_corruption_error")

  source2 <- tempfile(); writeLines("second", source2)
  entry2 <- fixture_entry(source2, url); entry2$cache_status <- NULL
  saved2 <- readboj:::write_cache_entry(cache, entry2, source2)
  index <- readboj:::cache_index_path(cache, readboj:::cache_request_key(url))
  index_entry <- readRDS(index)
  index_entry$canonical_url <- paste0(url, "&lang=jp")
  saveRDS(index_entry, index)
  expect_error(readboj:::read_cache_entry(cache, url),
    class = "readboj_identity_error")
})
