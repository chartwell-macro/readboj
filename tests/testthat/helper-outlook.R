# Synthetic layout only. Real-value tests use independently acquired official
# PDFs outside the source tree; no source publication is redistributed.
outlook_test_index <- function(rows = NULL) {
  if (is.null(rows)) rows <- c(
    "<tr><td>Aug.&nbsp;&nbsp;3,&nbsp;2026</td><td><a href='/en/mopo/outlook/gor2607b.pdf'>July 2026 (full text) [PDF]</a></td></tr>",
    "<tr><td>July 31, 2026</td><td><a href='/en/mopo/outlook/gor2607a.pdf'>July 2026 (The Bank's View) [PDF]</a></td></tr>",
    "<tr><td>Apr. 28, 2026</td><td><a href='/en/mopo/outlook/gor2604a.pdf'>April 2026 (The Bank's View) [PDF]</a></td></tr>",
    "<tr><td>Jan. 23, 2026</td><td><a href='/en/mopo/outlook/gor2601a.pdf'>January 2026 (The Bank's View) [PDF]</a></td></tr>")
  path <- tempfile(fileext = ".html")
  writeLines(c("<html><body><table>", rows, "</table></body></html>"), path)
  path
}

outlook_test_pages <- function() {
  center <- function(x) {
    left <- floor((25L - nchar(x)) / 2)
    paste0(strrep(" ", left), x, strrep(" ", 25L - nchar(x) - left))
  }
  row <- function(label = "", cells = rep("", 3L)) paste0(
    sprintf("%-42s", label), paste(vapply(cells, center, character(1L)), collapse = ""))
  header <- c("(Appendix)", .readboj_outlook_table, "y/y % chg.", "",
    row(cells = c("Real GDP", "CPI (all items less", "(Reference)")),
    row(cells = c("", "fresh food)", "CPI (all items less")),
    row(cells = c("", "", "fresh food and energy)")), "")
  current_range <- c("-0.3 to +0.1", "+1.1 to +1.4", "-0.1 to +0.1")
  current_median <- c("[+0.0]", "[+1.2]", "[+0.0]")
  prior_range <- c("+0.1 to +0.3", "+1.2 to +1.6", "+0.1 to +0.5")
  prior_median <- c("[+0.2]", "[+1.4]", "[+0.3]")
  body <- unlist(lapply(2026:2028, function(year) c(
    row(cells = current_range), row(paste("Fiscal", year)),
    row(cells = current_median), "", row(cells = prior_range),
    row("Forecasts made in April 2026"), row(cells = prior_median), "")))
  notes <- c("Notes: 1. Figures in brackets indicate the medians",
    "2. with the highest figure and the lowest figure excluded",
    "3. The range does not indicate the forecast errors.", "", "10")
  pages <- rep("Synthetic non-table page", 11L)
  pages[[1L]] <- paste("July 31, 2026", "Bank of Japan",
    "Outlook for Economic Activity and Prices (July 2026)", "The Bank's View", sep = "\n")
  pages[[10L]] <- paste(c(header, body, notes), collapse = "\n")
  pages
}

outlook_test_publication <- function() data.frame(release = "2026-07",
  publication_date = as.Date("2026-07-31"))

outlook_test_extracted <- function(pages = outlook_test_pages(), max_pdf_pages = 100L) {
  pages <- utils::head(pages, max_pdf_pages)
  coordinates <- lapply(pages, function(page) {
    lines <- strsplit(page, "\n", fixed = TRUE)[[1L]]
    result <- list()
    for (i in seq_along(lines)) {
      line <- lines[[i]]
      runs <- gregexpr("[^ ]+(?: [^ ]+)*", line, perl = TRUE)[[1L]]
      if (runs[[1L]] == -1L) next
      lengths <- attr(runs, "match.length")
      for (j in seq_along(runs)) {
        text <- substr(line, runs[[j]], runs[[j]] + lengths[[j]] - 1L)
        positions <- gregexpr("[^ ]+", text)[[1L]]
        words <- regmatches(text, list(positions))[[1L]]
        x <- (runs[[j]] + positions - 2L) * 4
        w <- data.frame(text = words, x0 = x, y0 = i * 12,
          x1 = x + nchar(words) * 4, y1 = i * 12 + 8)
        result[[length(result) + 1L]] <- list(text = text, x0 = min(w$x0),
          y0 = min(w$y0), x1 = max(w$x1), y1 = max(w$y1), words = w)
      }
    }
    result
  })
  list(pages = pages, coordinates = coordinates, extractor = "synthetic test extractor",
    text_sha256 = strrep("a", 64), coordinates_sha256 = strrep("b", 64))
}

outlook_test_html <- function() {
  path <- tempfile(fileext = ".htm")
  writeLines(c("<html><main><h1>Outlook and Risk Assessment (October 2000)</h1>",
    "<p>October 31, 2000 Bank of Japan</p>",
    "<p>Forecasts of the majority exclude the highest and lowest figures.</p>",
    "<table><caption>Forecasts of the Majority (Y/y % change)</caption>",
    "<thead><tr><th></th><th>Real GDP</th><th>Domestic WPI</th><th>CPI (excluding perishables)</th></tr></thead>",
    "<tbody><tr><th>Fiscal 2000</th><td>+1.1 to +1.3</td><td>0.0 to +0.1</td><td>-0.4 to -0.2</td></tr></tbody>",
    "</table></main></html>"), path)
  path
}

outlook_test_pdf <- function() {
  path <- tempfile(fileext = ".pdf")
  writeBin(charToRaw("%PDF-synthetic test bytes\n"), path)
  path
}

outlook_mock_reader <- function(index = outlook_test_index(), pdf = outlook_test_pdf()) {
  testthat::local_mocked_bindings(
    fetch_snapshot = function(url, ...) fixture_entry(
      if (endsWith(url, "index.htm")) index else pdf, url),
    extract_outlook_pdf = function(path, command, max_pdf_pages, ...) {
      outlook_test_extracted(max_pdf_pages = max_pdf_pages)
    },
    .package = "readboj", .env = parent.frame())
  invisible(pdf)
}
