test_that("Outlook discovery associates the later full text with one vintage", {
  index <- outlook_test_index()
  local_mocked_bindings(fetch_snapshot = function(url, ...) fixture_entry(index, url),
    extract_outlook_pdf = function(...) stop("Discovery must not extract PDFs"), .package = "readboj")
  x <- list_boj_outlook_releases_raw()
  expect_identical(x$release, c("2026-07", "2026-04", "2026-01"))
  expect_identical(x$publication_date[[1L]], as.Date("2026-07-31"))
  expect_identical(x$full_text_date[[1L]], as.Date("2026-08-03"))
  expect_match(x$full_text_url[[1L]], "gor2607b.pdf$", fixed = FALSE)
  expect_identical(x$source_format, rep("pdf", 3L))
  expect_match(boj_provenance(x)$raw_sha256, "^[0-9a-f]{64}$")
  expect_identical(boj_provenance(x)$parser_schema, "outlook-semantic-v2")
})

test_that("Outlook archive identity and size ambiguities fail explicitly", {
  path <- outlook_test_index()
  source <- paste(readLines(path), collapse = "\n")
  parse <- function(text, bound = 200L, bytes = 1e6) {
    writeLines(text, path)
    readboj:::parse_outlook_releases(fixture_entry(path), bytes, bound, Sys.time() + 20)
  }
  expect_error(parse(source, bound = 1L), class = "readboj_size_error")
  expect_error(parse(source, bytes = 5), class = "readboj_size_error")
  expect_error(parse(gsub("gor2607a.pdf", "gor2604a.pdf", source, fixed = TRUE)),
    class = "readboj_identity_error")
  expect_error(parse(gsub("/en/mopo/outlook/gor2607a.pdf", "https://example.com/gor2607a.pdf",
    source, fixed = TRUE)), class = "readboj_config_error")
  expect_error(parse(gsub("July 31, 2026", "July 99, 2026", source, fixed = TRUE)),
    class = "readboj_schema_error")
  expect_error(parse(gsub("July 31, 2026", "July 32 2026", source, fixed = TRUE)),
    class = "readboj_schema_error")
  expect_error(parse(gsub("<table>", paste0("<table>", source), source, fixed = TRUE)),
    class = "readboj_identity_error")
  expect_error(parse("<table><tr><td>No reports</td></tr></table>"),
    class = "readboj_schema_error")
})

test_that("synthetic Outlook cells retain statistics, signs, fiscal dates and comparators", {
  x <- readboj:::parse_outlook_table(outlook_test_extracted(), outlook_test_publication(), Sys.time() + 10)
  expect_equal(nrow(x), 54L)
  expect_identical(unique(x$measure), c("real_gdp", "cpi_ex_fresh_food", "cpi_ex_fresh_food_energy"))
  expect_identical(unique(x$statistic), c("majority_lower", "majority_upper", "median"))
  expect_identical(unique(x$comparison), c("current", "prior"))
  expect_identical(unique(x$forecast_vintage[x$comparison == "prior"]), "2026-04")
  expect_equal(x$value[x$comparison == "current" & x$fiscal_year == 2026L],
    c(-0.3, 0.1, 0, 1.1, 1.4, 1.2, -0.1, 0.1, 0))
  expect_equal(x$value[x$comparison == "prior" & x$fiscal_year == 2026L],
    c(0.1, 0.3, 0.2, 1.2, 1.6, 1.4, 0.1, 0.5, 0.3))
  expect_true(all(x$period_start == as.Date(paste0(x$fiscal_year, "-04-01"))))
  expect_true(all(x$period_end == as.Date(paste0(x$fiscal_year + 1L, "-03-31"))))
  expect_identical(x$raw_value[[1L]], "-0.3")
  expect_true(all(x$value_status == "forecast"))
  expect_true(all(x$pdf_page == 10L & x$printed_page == 10L))
  expect_identical(sort(unique(x$table_row)), 1:6)
  expect_identical(sort(unique(x$table_column)), 1:3)
  expect_false(any(grepl("rate|probability|member_id", names(x))))
  expect_error(readboj:::parse_outlook_table(outlook_test_extracted(), outlook_test_publication(),
    Sys.time() - 1), class = "readboj_timeout_error")
})

test_that("changed semantic table structure fails without dated metadata", {
  original <- outlook_test_pages()
  edits <- list(c("Real GDP", "Real GNP"), c("fresh food and energy", "fresh food and goods"),
    c("y/y % chg.", "q/q % chg."), c("Fiscal 2027", "Fiscal 2026"), c("Fiscal", "Year"),
    c("-0.3 to +0.1", "+0.3 to -0.1"), c("[+1.2]", "[+9.2]"), c("[+1.2]", "       "),
    c("with the highest figure and the lowest figure excluded", "Member construction missing"))
  for (edit in edits) {
    pages <- original
    pages[[10L]] <- gsub(edit[[1L]], edit[[2L]], pages[[10L]], fixed = TRUE)
    expect_error(readboj:::parse_outlook_table(outlook_test_extracted(pages),
      outlook_test_publication(), Sys.time() + 10), class = "readboj_schema_error")
  }
  pages <- original
  pages[[11L]] <- pages[[10L]]
  expect_error(readboj:::parse_outlook_table(outlook_test_extracted(pages),
    outlook_test_publication(), Sys.time() + 10), class = "readboj_schema_error")
  wrong <- original
  wrong[[1L]] <- sub("July 31", "July 30", wrong[[1L]], fixed = TRUE)
  expect_error(readboj:::outlook_pdf_identity(outlook_test_extracted(wrong),
    outlook_test_publication(), FALSE), class = "readboj_identity_error")
})

test_that("reader preserves PDF provenance, explicit pins and current/prior selection", {
  pdf <- outlook_mock_reader()
  command <- unname(Sys.which("Rscript")) # extractor itself is mocked
  x <- read_boj_outlook_raw("latest", pdftotext = command,
    expected_sha256 = digest::digest(file = pdf, algo = "sha256", serialize = FALSE))
  expect_equal(nrow(x), 27L)
  expect_identical(unique(x$comparison), "current")
  p <- boj_provenance(x)
  expect_identical(p$requested_release, "latest")
  expect_identical(p$release, "2026-07")
  expect_identical(p$parser_schema, "outlook-semantic-v2")
  expect_identical(p$discovery$parser_schema, "outlook-semantic-v2")
  expect_identical(p$pdf_page_index, 9L)
  expect_identical(p$full_text_date, as.Date("2026-08-03"))
  expect_identical(unique(x$source_sha256), p$raw_sha256)
  expect_identical(unique(x$source_url), p$canonical_url)
  expect_match(p$range_definition, "not a confidence", fixed = TRUE)
  expect_equal(nrow(read_boj_outlook_raw("2026-07", comparison = "all", pdftotext = command)), 54L)
  prior <- read_boj_outlook_raw("2026-07", comparison = "prior", pdftotext = command)
  expect_identical(unique(prior$forecast_vintage), "2026-04")
  expect_error(read_boj_outlook_raw("2026-07", expected_sha256 = strrep("0", 64),
    pdftotext = command), class = "readboj_identity_error")
})

test_that("reader enforces dependency, parameter, PDF, page and identity failures", {
  pdf <- outlook_mock_reader()
  command <- unname(Sys.which("Rscript"))
  expect_error(read_boj_outlook_raw(pdftotext = ""), class = "readboj_dependency_error")
  expect_error(read_boj_outlook_raw(pdftotext = tempfile()), class = "readboj_dependency_error")
  expect_error(read_boj_outlook_raw(pdftotext = NA_character_), class = "readboj_parameter_error")
  expect_error(read_boj_outlook_raw("2026-06"), class = "readboj_identity_error")
  expect_error(read_boj_outlook_raw(comparison = "previous"), class = "readboj_parameter_error")
  expect_error(read_boj_outlook_raw(expected_sha256 = "partial"), class = "readboj_parameter_error")
  expect_error(read_boj_outlook_raw(max_pdf_pages = 1e20), class = "readboj_parameter_error")
  expect_error(read_boj_outlook_raw(max_pdf_pages = 2.5), class = "readboj_parameter_error")
  expect_error(list_boj_outlook_releases_raw(max_releases = 1e20), class = "readboj_parameter_error")
  expect_error(read_boj_outlook_raw(max_pdf_pages = 9L, pdftotext = command), class = "readboj_size_error")
  expect_error(read_boj_outlook_raw("2025-10", pdftotext = command), class = "readboj_identity_error")
  writeLines("<html>Maintenance</html>", pdf)
  expect_error(read_boj_outlook_raw(pdftotext = command), class = "readboj_parse_error")
  index <- outlook_test_index()
  local_mocked_bindings(fetch_snapshot = function(url, ...) {
    entry <- fixture_entry(if (endsWith(url, "index.htm")) index else pdf, url)
    if (endsWith(url, ".pdf")) entry$final_url <- "https://www.boj.or.jp/en/mopo/outlook/gor2604a.pdf"
    entry
  }, .package = "readboj")
  expect_error(read_boj_outlook_raw(pdftotext = command), class = "readboj_identity_error")
})

test_that("latest reads an unseen future edition without a profile or fallback", {
  path <- outlook_test_index("<tr><td>Oct. 29, 2032</td><td><a href='/en/mopo/outlook/gor3210a.pdf'>October 2032 (The Bank's View) [PDF]</a></td></tr>")
  pdf <- outlook_test_pdf()
  pages <- outlook_test_pages()
  for (from in c("2028", "2027", "2026")) pages <- gsub(from, as.character(as.integer(from) + 6L), pages, fixed = TRUE)
  pages[[1L]] <- gsub("July 31", "October 29", pages[[1L]], fixed = TRUE)
  pages[[1L]] <- gsub("July 2032", "October 2032", pages[[1L]], fixed = TRUE)
  local_mocked_bindings(fetch_snapshot = function(url, ...) fixture_entry(if (endsWith(url, "index.htm")) path else pdf, url),
    extract_outlook_pdf = function(...) outlook_test_extracted(pages), .package = "readboj")
  x <- read_boj_outlook_raw("latest", pdftotext = unname(Sys.which("Rscript")))
  expect_identical(unique(x$release), "2032-10")
  expect_identical(unique(x$fiscal_year), 2032:2034)
  expect_equal(nrow(x), 27L)
})

test_that("one absolute deadline reaches discovery, PDF retrieval and extraction", {
  index <- outlook_test_index()
  pdf <- outlook_test_pdf()
  end <- Sys.time() + 30
  calls <- list()
  local_mocked_bindings(fetch_snapshot = function(url, ...) {
    args <- list(...)
    calls[[length(calls) + 1L]] <<- args
    fixture_entry(if (endsWith(url, "index.htm")) index else pdf, url)
  }, extract_outlook_pdf = function(path, command, max_pdf_pages, max_text_bytes, deadline) {
    expect_identical(as.numeric(deadline), as.numeric(end))
    outlook_test_extracted()
  }, .package = "readboj")
  read_boj_outlook_raw(pdftotext = unname(Sys.which("Rscript")), refresh = TRUE, offline = TRUE,
    max_age = Inf, timeout = 5, retries = 0L, wait = 0, deadline = end)
  expect_length(calls, 2L)
  for (args in calls) {
    expect_identical(as.numeric(args$deadline), as.numeric(end))
    expect_true(args$refresh)
    expect_true(args$offline)
    expect_identical(args$max_age, Inf)
    expect_identical(args$timeout, 5)
    expect_identical(args$retries, 0L)
    expect_identical(args$wait, 0)
  }
  calls <- list()
  expect_error(read_boj_outlook_raw(deadline = Sys.time() - 1), class = "readboj_timeout_error")
  expect_error(list_boj_outlook_releases_raw(deadline = Sys.time() - 1), class = "readboj_timeout_error")
  expect_length(calls, 0L)
})

test_that("Outlook uses bounded raw cache, offline replay and refresh bypass", {
  index <- outlook_test_index()
  pdf <- outlook_test_pdf()
  cache <- tempfile("outlook-cache-")
  calls <- 0L
  local_mocked_bindings(perform_once = function(canonical, path, timeout, max_bytes) {
    calls <<- calls + 1L
    file.copy(if (endsWith(canonical, "index.htm")) index else pdf, path)
    httr2::new_response(method = "GET", url = canonical, status_code = 200L,
      headers = list(), body = raw())
  }, extract_outlook_pdf = function(...) outlook_test_extracted(), .package = "readboj")
  command <- unname(Sys.which("Rscript"))
  x <- read_boj_outlook_raw(cache_dir = cache, pdftotext = command, wait = 0)
  expect_equal(calls, 2L)
  y <- read_boj_outlook_raw(cache_dir = cache, pdftotext = command, offline = TRUE)
  expect_equal(calls, 2L)
  expect_equal(x$value, y$value)
  expect_identical(boj_provenance(y)$cache_status, "hit")
  read_boj_outlook_raw(cache_dir = cache, pdftotext = command, refresh = TRUE, wait = 0)
  expect_equal(calls, 4L)
  expect_length(list.files(file.path(cache, "objects")), 2L)
  expect_error(list_boj_outlook_releases_raw(cache_dir = cache, offline = TRUE,
    max_bytes = 1), class = "readboj_size_error")
  expect_error(read_boj_outlook_raw(cache_dir = tempfile(), pdftotext = command, offline = TRUE),
    class = "readboj_offline_error")
})

test_that("extractor subprocesses are killed by the absolute deadline", {
  skip_on_os("windows")
  # Exercise a real external process without re-entering R's check environment.
  shell <- unname(Sys.which("sh"))
  log <- tempfile()
  before <- Sys.time()
  expect_error(readboj:::run_outlook_pdf(shell,
    c("-c", "exec sleep 5"), log, Sys.time() + 1.8),
    class = "readboj_timeout_error")
  expect_lt(as.numeric(difftime(Sys.time(), before, units = "secs")), 4)
  expect_error(readboj:::run_outlook_pdf(shell,
    c("-c", "exit 3"), log, Sys.time() + 10),
    class = "readboj_parse_error")
})


test_that("legacy three-column archive rows retain full text without inventing its date", {
  path <- outlook_test_index("<tr><td>Oct. 31, 2007</td><td><a href='/en/mopo/outlook/gor0710.htm'>October 2007</a></td><td><a href='/en/mopo/outlook/data/gor0710.pdf'>[PDF]</a></td></tr>")
  local_mocked_bindings(fetch_snapshot = function(url, ...) fixture_entry(path, url), .package = "readboj")
  x <- list_boj_outlook_releases_raw()
  expect_identical(x$release, "2007-10")
  expect_identical(x$full_text_url, "https://www.boj.or.jp/en/mopo/outlook/data/gor0710.pdf")
  expect_true(is.na(x$full_text_date))
})

test_that("page locations, fiscal horizons and comparator months are source semantics", {
  pages <- outlook_test_pages()
  pages[[9L]] <- pages[[10L]]
  pages[[10L]] <- "The forecast table can move."
  pages[[9L]] <- gsub("April 2026", "January 2026", pages[[9L]], fixed = TRUE)
  pages[[9L]] <- gsub("Fiscal 2028", "Fiscal 2031", pages[[9L]], fixed = TRUE)
  x <- readboj:::parse_outlook_table(outlook_test_extracted(pages), outlook_test_publication(), Sys.time() + 10)
  expect_identical(unique(x$pdf_page), 9L)
  expect_identical(unique(x$printed_page), "10")
  expect_identical(unique(x$fiscal_year), c(2026L, 2027L, 2031L))
  expect_identical(unique(x$forecast_vintage[x$comparison == "prior"]), "2026-01")
  expect_true(all(is.finite(x$pdf_xmin) & is.finite(x$pdf_ymin)))
})

test_that("HTML needs no Poppler and never invents absent medians", {
  index <- outlook_test_index("<tr><td>Oct. 31, 2000</td><td><a href='/en/mopo/outlook/gor0010.htm'>October 2000</a></td><td></td></tr>")
  html <- outlook_test_html()
  local_mocked_bindings(fetch_snapshot = function(url, ...) fixture_entry(if (endsWith(url, "index.htm")) index else html, url),
    extract_outlook_pdf = function(...) stop("HTML must not invoke PDF extraction"), .package = "readboj")
  x <- read_boj_outlook_raw("2000-10", pdftotext = "")
  expect_equal(x$value, c(1.1,1.3,0,.1,-.4,-.2))
  expect_false(any(x$statistic == "median"))
  expect_identical(unique(x$measure), c("real_gdp", "domestic_wpi", "cpi_ex_perishables"))
  expect_true(all(!is.na(x$source_xpath)))
  expect_identical(unique(x$source_format), "html")
})

test_that("measure-scoped notes separate headline actuals and adjusted estimates", {
  notes <- paste("The direct effects of the consumption tax hike on the CPI for fiscal 2019 are estimated.",
    "Based on a specific assumption, the direct effects of free education on the CPI for fiscal 2019 are estimated.",
    "The CPI (all items less fresh food) for fiscal 2019 is an actual figure.")
  expect_identical(readboj:::outlook_point_status("cpi_ex_fresh_food",2019L,"current","Fiscal 2019",notes),"actual")
  expect_identical(readboj:::outlook_point_status("cpi_ex_fresh_food_ex_tax_education",2019L,"current","Fiscal 2019",notes),"conditional_estimate")
  expect_identical(readboj:::outlook_point_status("cpi_ex_fresh_food",2020L,"current","Fiscal 2020",notes),"published_point")
  expect_identical(readboj:::outlook_point_status("cpi_ex_fresh_food_energy",2019L,"current","Fiscal 2019",notes),"published_point")
  expect_error(readboj:::outlook_cell_values("+1.0 to +1.1","majority","actual"),class="readboj_schema_error")
  conditional <- readboj:::outlook_cell_values("+1.0 to +1.2 [+1.1]", "majority", "conditional_estimate")
  expect_identical(conditional$value_status, rep("forecast", 3L))
  expect_identical(conditional$statistic, c("majority_lower", "majority_upper", "median"))
  expect_error(read_boj_outlook_raw("all",expected_sha256=strrep("0",64)),class="readboj_parameter_error")
})
