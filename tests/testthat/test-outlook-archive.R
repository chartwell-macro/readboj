# The real corpus is external, not redistributed in the package. These values
# were transcribed from official HTML cells and rendered PDF tables, not from
# candidate parser output. None is runtime release/admission metadata.
outlook_archive_fixture <- function() {
  directory <- Sys.getenv("READBOJ_OUTLOOK_ARCHIVE_DIR")
  skip_if(!nzchar(directory), "Set READBOJ_OUTLOOK_ARCHIVE_DIR to the acquired official corpus")
  skip_if(!nzchar(Sys.which("pdftotext")), "Optional Poppler pdftotext is unavailable")
  index <- utils::read.csv(file.path(directory, "archive-assets.csv"), stringsAsFactors = FALSE)
  testthat::local_mocked_bindings(fetch_snapshot = function(url, ...) {
    path <- if (endsWith(url, "/index.htm")) file.path(directory, "sources", "index.htm") else {
      row <- index[index$url == url, , drop = FALSE]
      if (nrow(row) != 1L) stop("Unexpected corpus URL: ", url)
      file.path(directory, "sources", paste0(row$release, "-", row$kind, ".", row$format))
    }
    fixture_entry(path, url)
  }, .package = "readboj", .env = parent.frame())
  invisible(directory)
}

outlook_values <- function(x, year, measure, statistic, comparison = "current", scope = "majority") {
  x$value[x$fiscal_year == year & x$measure == measure & x$statistic == statistic &
    x$comparison == comparison & x$range_scope == scope]
}

test_that("all archive editions are actually parsed by the public all-edition reader", {
  directory <- outlook_archive_fixture()
  editions <- list_boj_outlook_releases_raw()
  expect_equal(nrow(editions), 74L)
  expect_identical(range(editions$release), c("2000-10", "2026-07"))
  expect_equal(sum(editions$source_format == "htm"), 24L)
  expect_equal(sum(editions$source_format == "pdf"), 50L)
  history <- read_boj_outlook_raw("all", comparison = "all", wait = 0, deadline = Sys.time() + 240)
  expect_equal(nrow(history), 4142L)
  expect_equal(sum(is.finite(history$value)), 4137L)
  saved <- read_boj_outlook("all", comparison = "all", data_dir = tempfile())
  attr(saved, "readboj_provenance") <- NULL
  parsed <- history
  attr(parsed, "readboj_provenance") <- NULL
  expect_identical(saved, parsed)
  expect_setequal(unique(history$release), editions$release)
  expect_length(boj_provenance(history)$editions, nrow(editions))
  expect_true(all(vapply(split(history, history$release), function(x) any(is.finite(x$value)), logical(1L))))
  expect_true(all(grepl("^[0-9a-f]{64}$", history$source_sha256)))
  expect_true(all(history$period_start == as.Date(paste0(history$fiscal_year, "-04-01"))))
  expect_true(all(history$period_end == as.Date(paste0(history$fiscal_year + 1L, "-03-31"))))
  pdf <- history$source_format == "pdf"
  expect_true(all(is.finite(history$pdf_xmin[pdf]) & is.finite(history$pdf_ymin[pdf])))
  expect_true(all(!is.na(history$source_xpath[!pdf])))
  expect_false(anyDuplicated(history[c("release","forecast_vintage","comparison","fiscal_year","measure","statistic","range_scope")]) > 0L)
  if (file.exists(file.path(directory, "independent-index.csv"))) {
    independent <- utils::read.csv(file.path(directory, "independent-index.csv"))
    expect_setequal(editions$banks_view_url, independent$url)
  }
})

test_that("legacy HTML transitions preserve ranges, prior definitions and actual qualifications", {
  outlook_archive_fixture()
  first <- read_boj_outlook_raw("2000-10", comparison = "all", pdftotext = "")
  expect_equal(first$value, c(1.9,2.3,0,.1,-.4,-.2,1.5,2.3,0,.2,-.5,-.1))
  expect_false(any(first$statistic == "median"))
  expect_setequal(first$measure, c("real_gdp", "domestic_wpi", "cpi_ex_perishables"))
  old <- read_boj_outlook_raw("2001-10", comparison = "all", pdftotext = "")
  expect_equal(outlook_values(old,2001,"real_gdp","majority_lower","prior"), .3)
  expect_identical(unique(old$forecast_vintage[old$comparison == "prior"]), "2001-04")
  expect_false(any(old$statistic == "median"))
  median <- read_boj_outlook_raw("2003-04", comparison = "all", pdftotext = "")
  expect_equal(outlook_values(median,2003,"real_gdp","median"), 1)
  expect_equal(outlook_values(median,2003,"domestic_cgpi","median"), -1)
  expect_equal(outlook_values(median,2003,"domestic_wpi","majority_lower","prior"), -.7)
  expect_false(any(median$measure == "domestic_cgpi" & median$comparison == "prior"))
  expect_equal(outlook_values(median,2002,"real_gdp","conditional_estimate"), 1.8)
  expect_equal(outlook_values(median,2002,"cpi_ex_fresh_food","actual"), -.8)
  extended <- read_boj_outlook_raw("2005-04", comparison = "all", pdftotext = "")
  expect_setequal(unique(extended$fiscal_year), 2004:2006)
  expect_equal(outlook_values(extended,2004,"real_gdp","conditional_estimate"), 1.6)
  expect_equal(outlook_values(extended,2004,"domestic_cgpi","actual"), 1.5)
  expect_equal(outlook_values(extended,2006,"real_gdp","median"), 1.6)
  expect_equal(outlook_values(extended,2005,"real_gdp","all_upper",scope="all_members"), 1.8)
})

test_that("image HTML uses the archive-linked searchable PDF, with separate source date", {
  outlook_archive_fixture()
  image <- read_boj_outlook_raw("2004-10", comparison = "all")
  expect_equal(outlook_values(image,2004,"real_gdp","median"), 3.6)
  expect_equal(outlook_values(image,2004,"real_gdp","all_lower",scope="all_members"), 3.2)
  expect_equal(outlook_values(image,2005,"real_gdp","median"), 2.5)
  expect_true(boj_provenance(image)$source_is_full_text)
  expect_match(boj_provenance(image)$canonical_url, "/data/gor0410.pdf", fixed=TRUE)
  expect_identical(boj_provenance(image)$publication_date, as.Date("2004-10-29"))
  expect_identical(boj_provenance(image)$source_publication_date, as.Date("2004-11-01"))
  actual <- read_boj_outlook_raw("2006-04", comparison = "all")
  expect_equal(outlook_values(actual,2005,"real_gdp","conditional_estimate"), 3.2)
  expect_equal(outlook_values(actual,2006,"real_gdp","median"), 2.4)
  expect_equal(outlook_values(actual,2006,"real_gdp","all_upper",scope="all_members"), 3.0)
  expect_identical(boj_provenance(actual)$source_publication_date, as.Date("2006-05-01"))
  published <- read_boj_outlook_raw("2008-04", comparison = "all")
  expect_equal(outlook_values(published,2007,"real_gdp","conditional_estimate"), 1.6)
  expect_equal(outlook_values(published,2008,"real_gdp","median"), 1.5)
  expect_equal(outlook_values(published,2008,"real_gdp","all_upper",scope="all_members"), 1.8)
})

test_that("row adjustments and blank columns are preserved without invented statistics", {
  outlook_archive_fixture()
  rows <- read_boj_outlook_raw("2012-10", comparison = "all")
  expect_equal(outlook_values(rows,2014,"domestic_cgpi","median"), 4.2)
  expect_equal(outlook_values(rows,2014,"domestic_cgpi_ex_consumption_tax","median"), 1.3)
  expect_equal(outlook_values(rows,2014,"cpi_ex_fresh_food_ex_consumption_tax","median"), .8)
  expect_equal(outlook_values(rows,2014,"domestic_cgpi_ex_consumption_tax","all_lower",scope="all_members"), .4)
  columns <- read_boj_outlook_raw("2013-04", comparison = "all")
  expect_false(any(columns$measure == "cpi_ex_fresh_food_ex_consumption_tax" & columns$fiscal_year < 2014))
  expect_equal(outlook_values(columns,2014,"cpi_ex_fresh_food","median"), 3.4)
  expect_equal(outlook_values(columns,2014,"cpi_ex_fresh_food_ex_consumption_tax","median"), 1.4)
  tax <- read_boj_outlook_raw("2015-10", comparison = "all")
  shared <- tax[tax$fiscal_year == 2015 & tax$comparison == "current" & tax$statistic == "median" & startsWith(tax$measure,"cpi"),]
  expect_equal(shared$value, c(.1,.1))
  expect_true(all(shared$shared_cell))
  expect_length(unique(shared$source_cell_id), 1L)
  html <- read_boj_outlook_raw("2018-01", comparison = "all", pdftotext = "")
  expect_true(any(html$shared_cell))
  education <- read_boj_outlook_raw("2020-01", comparison = "all", pdftotext = "")
  expect_equal(outlook_values(education,2019,"cpi_ex_fresh_food_ex_tax_education","median"), .4)
  expect_false(any(education$measure == "cpi_ex_fresh_food_energy"))
})

test_that("pandemic ranges and scoped actual/assumption notes remain distinct", {
  outlook_archive_fixture()
  april <- read_boj_outlook_raw("2020-04", comparison = "all")
  expect_false(any(april$statistic == "median"))
  expect_equal(outlook_values(april,2020,"real_gdp","majority_lower"), -5)
  expect_identical(unique(april$member_input[april$comparison == "current"]), "member_intervals")
  expect_identical(unique(april$range_trimming[april$comparison == "current"]), "two_highest_and_two_lowest_endpoints")
  expect_identical(unique(april$member_input[april$comparison == "prior"]), "member_points")
  # Published page 6 footnote 4 explicitly calls headline FY2019 CPI actual.
  # The separate policy-adjusted reference is not automatically an actual.
  expect_equal(outlook_values(april,2019,"cpi_ex_fresh_food","actual"), .6)
  expect_equal(outlook_values(april,2019,"cpi_ex_fresh_food_ex_tax_education","conditional_estimate"), .4)
  expect_false(any(april$measure == "cpi_ex_fresh_food_ex_tax_education" & april$value_status == "actual"))
  july <- read_boj_outlook_raw("2020-07", comparison = "all")
  expect_equal(outlook_values(july,2020,"real_gdp","median"), -4.7)
  expect_identical(unique(july$member_input[july$comparison == "prior"]), "member_intervals")
  expect_false(any(july$comparison == "prior" & july$statistic == "median"))
  prior_estimate <- read_boj_outlook_raw("2009-04", comparison = "all")
  expect_equal(outlook_values(prior_estimate,2008,"domestic_cgpi","actual"), 3.3)
  expect_equal(outlook_values(prior_estimate,2008,"cpi_ex_fresh_food","conditional_estimate"), 1.2)
  expect_equal(sum(prior_estimate$value_status == "not_applicable"), 2L)
  two <- read_boj_outlook_raw("2021-04", comparison = "all")
  expect_setequal(two$measure, c("real_gdp","cpi_ex_fresh_food"))
  expect_equal(outlook_values(two,2020,"cpi_ex_fresh_food","actual"), -.4)
  reference <- read_boj_outlook_raw("2022-04", comparison = "all")
  expect_equal(outlook_values(reference,2021,"cpi_ex_fresh_food_energy","actual"), -.8)
  expect_equal(sum(reference$measure == "cpi_ex_fresh_food_energy" & reference$statistic == "not_applicable"), 3L)
})

test_that("held-out editions match independently transcribed complete tables", {
  outlook_archive_fixture()
  expected <- list(
    "2010-04" = c(
      -2.2,-2.1,-2.2,-5.2,-1.6, -2.5,-2.5,-2.5,-5.3,-5.2,-5.3,-1.5,-1.5,-1.5,
      1.6,2,1.8,1.1,1.5,1.3,-.5,-.2,-.5, 1.2,1.4,1.3,-.5,-.4,-.5,-.6,-.5,-.5,
      2,2.2,2,.5,.8,.7,-.1,.2,.1, 1.7,2.4,2.1,-.5,0,-.4,-.3,-.1,-.2,
      -2.2,-2,-5.2,-1.6, -2.6,-2.3,-5.5,-5,-1.6,-1.5,
      1.5,2,1,1.6,-.6,-.2, 1,1.5,-.9,-.4,-.7,-.4,
      1.9,2.4,.4,1,-.1,.3, 1.6,2.5,-.5,.2,-.3,0),
    "2014-10" = c(
      .2,.7,.5,3.1,3.4,3.2,1.1,1.4,1.2, .6,1.3,1,3.2,3.5,3.3,1.2,1.5,1.3,
      1.2,1.7,1.5,1.8,2.6,2.4,1.1,1.9,1.7, 1.2,1.6,1.5,1.9,2.8,2.6,1.2,2.1,1.9,
      1,1.4,1.2,1.9,3,2.8,1.2,2.3,2.1, 1,1.5,1.3,2,3,2.8,1.3,2.3,2.1,
      .1,1,3,3.4,1,1.4, .5,1.3,3,3.7,1,1.7,
      .8,1.8,1.6,2.7,.9,2, .9,1.7,1.7,2.8,1,2.1,
      .6,1.6,1.6,3,.9,2.3, .7,1.6,1.6,3,.9,2.3),
    "2017-10" = c(
      1.7,2,1.9,.7,1,.8,.7,1,.8, 1.5,1.8,1.8,.5,1.3,1.1,.5,1.3,1.1,
      1.2,1.4,1.4,1.1,1.6,1.4,1.1,1.6,1.4, 1.1,1.5,1.4,.8,1.6,1.5,.8,1.6,1.5,
      .7,.8,.7,2,2.5,2.3,1.5,2,1.8, .7,.8,.7,1.4,2.5,2.3,.9,2,1.8),
    "2022-07" = c(
      2.2,2.5,2.4,2.2,2.4,2.3,1.2,1.4,1.3, 2.6,3,2.9,1.8,2,1.9,.8,1,.9,
      1.7,2.1,2,1.2,1.5,1.4,1.2,1.4,1.4, 1.5,2.1,1.9,.9,1.3,1.1,1.1,1.3,1.2,
      1.1,1.5,1.3,1.1,1.5,1.3,1.4,1.7,1.5, 1.1,1.3,1.1,1,1.3,1.1,1.2,1.5,1.5))
  for (edition in names(expected)) {
    x <- read_boj_outlook_raw(edition, comparison = "all")
    expect_equal(x$value, expected[[edition]], info = edition)
    expect_true(all(is.finite(x$pdf_xmin)))
    expect_match(boj_provenance(x)$raw_sha256, "^[0-9a-f]{64}$")
  }
})

test_that('complete bundle rebuilding is independent of existing saved data', {
  outlook_archive_fixture()
  local_mocked_bindings(outlook_saved_load = function(...) stop('Builder must not read saved data'), .package='readboj')
  output <- tempfile(fileext='.rds')
  withr::defer(unlink(output))
  result <- build_boj_outlook_bundle(output, wait=0, deadline=Sys.time()+240)
  expect_equal(nrow(result$catalogue),74L)
  expect_length(result$assets,144L)
  expect_length(result$revisions,0L)
  expected <- readRDS(system.file('extdata','outlook-saved.rds',package='readboj'))
  expect_identical(result$data,expected$data)
  expect_identical(result$parser_sha256,readboj:::outlook_parser_fingerprint())
  expect_silent(readboj:::outlook_saved_validate(readRDS(output)))
})
