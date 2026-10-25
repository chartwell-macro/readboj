# Optional local-fixture tests: source PDFs are kept outside the package because
# their intended-use/redistribution permissions have not been established.
# Values below were transcribed from rendered appendix cells, not this parser.
test_that("three official Outlook PDFs match independent full-table values", {
  directory <- Sys.getenv("READBOJ_OUTLOOK_FIXTURE_DIR")
  skip_if(!nzchar(directory), "Set READBOJ_OUTLOOK_FIXTURE_DIR to the official source-file directory")
  command <- unname(Sys.which("pdftotext"))
  skip_if(!nzchar(command), "Optional Poppler pdftotext is unavailable")
  required <- c("index.htm", "gor2601a.pdf", "gor2604a.pdf", "gor2607a.pdf", "gor2607b.pdf")
  expect_true(all(file.exists(file.path(directory, required))))
  local_mocked_bindings(fetch_snapshot = function(url, ...) {
    path <- file.path(directory, basename(url))
    if (!file.exists(path)) stop("Unexpected source identity: ", url)
    fixture_entry(path, url)
  }, .package = "readboj")
  expected <- list(
    "2026-01" = c(
      .8, .9, .9, 2.7, 2.8, 2.7, 2.9, 3.1, 3.0,
      .6, .8, .7, 2.7, 2.9, 2.7, 2.8, 3.0, 2.8,
      .8, 1.0, 1.0, 1.9, 2.0, 1.9, 2.0, 2.3, 2.2,
      .6, .8, .7, 1.6, 2.0, 1.8, 1.8, 2.2, 2.0,
      .8, 1.0, .8, 1.9, 2.2, 2.0, 2.0, 2.3, 2.1,
      .7, 1.1, 1.0, 1.8, 2.0, 2.0, 2.0, 2.2, 2.0),
    "2026-04" = c(
      1.0, 1.0, 1.0, 2.7, 3.0,
      .8, .9, .9, 2.7, 2.8, 2.7, 2.9, 3.1, 3.0,
      .4, .7, .5, 2.8, 3.0, 2.8, 2.5, 2.7, 2.6,
      .8, 1.0, 1.0, 1.9, 2.0, 1.9, 2.0, 2.3, 2.2,
      .6, .8, .7, 2.3, 2.4, 2.3, 2.6, 2.7, 2.6,
      .8, 1.0, .8, 1.9, 2.2, 2.0, 2.0, 2.3, 2.1,
      .7, .8, .8, 2.0, 2.2, 2.0, 2.1, 2.4, 2.2),
    "2026-07" = c(
      .6, .7, .6, 2.3, 2.7, 2.5, 2.3, 2.6, 2.5,
      .4, .7, .5, 2.8, 3.0, 2.8, 2.5, 2.7, 2.6,
      .7, .8, .8, 2.2, 2.5, 2.4, 2.2, 2.7, 2.6,
      .6, .8, .7, 2.3, 2.4, 2.3, 2.6, 2.7, 2.6,
      .7, .8, .8, 2.0, 2.2, 2.0, 2.1, 2.3, 2.2,
      .7, .8, .8, 2.0, 2.2, 2.0, 2.1, 2.4, 2.2))
  hashes <- c(
    "2026-01" = "fbc11985def3702f3cde3e495159512c9bd4cc301b42095a256705576013f9eb",
    "2026-04" = "8a4fcad24024040cfb35ff4d6ed38815ddc8fc00486c14dc5c0ae3c57d007d9c",
    "2026-07" = "90a79df3e1a98b10605e6d934b541df1dcc2370d012f05c9554f40980e41d163")
  results <- list()
  for (release in names(expected)) {
    x <- read_boj_outlook_raw(release, comparison = "all", pdftotext = command,
      expected_sha256 = hashes[[release]], deadline = Sys.time() + 20)
    expect_equal(x$value, expected[[release]], info = release)
    expect_identical(boj_provenance(x)$raw_sha256, hashes[[release]])
    expect_identical(unique(x$source_sha256), hashes[[release]])
    expect_true(all(x$source_row_label[x$comparison == "prior"] == switch(release,
      "2026-01" = "Forecasts made in October 2025", "2026-04" = "Forecasts made in January 2026",
      "2026-07" = "Forecasts made in April 2026")))
    expect_true(all(x$period_start == as.Date(paste0(x$fiscal_year, "-04-01"))))
    expect_true(all(x$period_end == as.Date(paste0(x$fiscal_year + 1L, "-03-31"))))
    results[[release]] <- x
  }
  january <- results[["2026-01"]]
  april <- results[["2026-04"]]
  july <- results[["2026-07"]]
  expect_identical(unique(january$fiscal_year), 2025:2027)
  expect_identical(boj_provenance(january)$pdf_page, 9L)
  expect_identical(unique(april$fiscal_year), 2025:2028)
  actual <- april[april$value_status == "actual", ]
  expect_identical(actual$statistic, c("actual", "actual"))
  expect_equal(actual$value, c(2.7, 3.0))
  expect_true(all(actual$fiscal_year == 2025 & actual$comparison == "current"))
  expect_equal(nrow(april[april$fiscal_year == 2025 & april$comparison == "current", ]), 5L)
  expect_identical(unique(july$fiscal_year), 2026:2028)
  expect_equal(july$value[july$fiscal_year == 2026 & july$comparison == "current"],
    c(.6, .7, .6, 2.3, 2.7, 2.5, 2.3, 2.6, 2.5))
  expect_identical(boj_provenance(july)$publication_date, as.Date("2026-07-31"))
  expect_identical(boj_provenance(july)$full_text_date, as.Date("2026-08-03"))
  view <- readboj:::extract_outlook_pdf(file.path(directory, "gor2607a.pdf"), command,
    20L, 1024^2, Sys.time() + 20)
  full <- readboj:::extract_outlook_pdf(file.path(directory, "gor2607b.pdf"), command,
    20L, 1024^2, Sys.time() + 20)
  expect_equal(unname(which(vapply(full$pages, grepl, logical(1L),
    pattern = "Forecasts of the Majority of the Policy Board Members", fixed = TRUE))), 12L)
  expect_identical(readboj:::outlook_space(view$pages[[10L]]),
    readboj:::outlook_space(full$pages[[12L]]))
  expect_error(readboj:::extract_outlook_pdf(file.path(directory, "gor2607a.pdf"), command,
    20L, 1L, Sys.time() + 20), class = "readboj_size_error")
})

test_that("official Outlook discovery and reader remain live when explicitly enabled", {
  skip_if(tolower(Sys.getenv("READBOJ_OUTLOOK_LIVE_TESTS")) != "true")
  skip_if(!nzchar(Sys.which("pdftotext")), "Optional Poppler pdftotext is unavailable")
  cache <- tempfile("readboj-outlook-live-")
  x <- read_boj_outlook_raw("2026-07", cache_dir = cache, refresh = TRUE,
    timeout = 15, retries = 0L, wait = 0, deadline = Sys.time() + 40,
    expected_sha256 = "90a79df3e1a98b10605e6d934b541df1dcc2370d012f05c9554f40980e41d163")
  expect_equal(x$value[x$fiscal_year == 2026 & x$statistic == "median"], c(.6, 2.5, 2.5))
  expect_identical(boj_provenance(x)$cache_status, "miss")
  replay <- read_boj_outlook_raw("2026-07", cache_dir = cache, offline = TRUE,
    max_age = Inf, deadline = Sys.time() + 20)
  expect_identical(replay$value, x$value)
  expect_identical(boj_provenance(replay)$cache_status, "hit")
})
