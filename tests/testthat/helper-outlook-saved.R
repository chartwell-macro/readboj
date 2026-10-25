# Numeric fixtures come from the package bundle; no raw publication is embedded.
outlook_saved_fixture <- function() readRDS(system.file('extdata', 'outlook-saved.rds', package = 'readboj'))

outlook_index_from_catalogue <- function(catalogue) {
  rows <- vapply(seq_len(nrow(catalogue)), function(i) {
    x <- catalogue[i, , drop = FALSE]
    label <- paste(month.name[as.integer(substr(x$release, 6, 7))], substr(x$release, 1, 4))
    date <- function(d) paste0(month.name[as.integer(format(d, '%m'))], ' ', as.integer(format(d, '%d')), ', ', format(d, '%Y'))
    view <- sprintf('<tr><td>%s</td><td><a href="%s">%s</a></td>', date(x$publication_date), x$banks_view_url, label)
    if (is.na(x$full_text_url)) return(paste0(view, '</tr>'))
    if (is.na(x$full_text_date)) return(paste0(view, '<td><a href="', x$full_text_url, '">Full text</a></td></tr>'))
    paste0(view, '</tr><tr><td>', date(x$full_text_date), '</td><td><a href="',
      x$full_text_url, '">', label, ' (full text)</a></td></tr>')
  }, character(1L))
  paste0('<html><table>', paste(rows, collapse = ''), '</table></html>')
}

outlook_update_fixture <- function(.env = parent.frame()) {
  force(.env)
  state <- new.env(parent = emptyenv())
  state$base <- outlook_saved_fixture()
  state$catalogue <- state$base$catalogue
  state$changes <- list()
  state$requests <- character()
  state$parsed <- character()
  state$parser <- state$base$parser_sha256
  state$fail <- NULL
  state$interrupt <- NULL
  state$mutate_before_parse <- NULL
  state$path_hashes <- list()
  original_hash <- readboj:::sha256_file
    testthat::local_mocked_bindings(
    outlook_parser_fingerprint = function() state$parser,
    sha256_file = function(path) state$path_hashes[[path]] %||% original_hash(path),
    outlook_update_request = function(url, previous, path, ...) {
      state$requests <- c(state$requests, url)
      if (identical(state$fail, url)) stop('fixture source failure')
      if (!is.null(state$interrupt)) state$interrupt()
      if (endsWith(url, '/index.htm')) {
        writeLines(outlook_index_from_catalogue(state$catalogue), path)
        return(fixture_entry(path, url))
      }
      change <- state$changes[[url]]
      if (is.null(change) && !is.null(previous)) {
        previous$http_status <- 304L
        previous$path <- NULL
        return(previous)
      }
      writeLines(paste('synthetic revision', url, change %||% 'unchanged'), path)
      entry <- fixture_entry(path, url)
      if (is.null(change) && !is.null(state$base$assets[[url]])) {
        entry$raw_sha256 <- state$base$assets[[url]]$raw_sha256
        state$path_hashes[[path]] <- entry$raw_sha256
      }
      entry
    },
    read_outlook_edition = function(publication, fetch, ...) {
      release <- publication$release[[1L]]
      state$parsed <- c(state$parsed, release)
      if (!is.null(state$mutate_before_parse)) state$mutate_before_parse()
      primary <- fetch(publication$banks_view_url[[1L]])
      old_release <- if (release %in% state$base$catalogue$release) release else state$base$catalogue$release[[1L]]
      out <- state$base$data[state$base$data$release == old_release, , drop = FALSE]
      p <- state$base$editions[[old_release]]
      numeric_url <- if (isTRUE(p$source_is_full_text)) publication$full_text_url[[1L]] else publication$banks_view_url[[1L]]
      entry <- if (identical(numeric_url, primary$canonical_url)) primary else fetch(numeric_url)
      out$forecast_vintage[out$comparison == 'current'] <- release
      out$release <- release
      out$publication_date <- publication$publication_date
      out$source_url <- entry$canonical_url
      out$source_sha256 <- entry$raw_sha256
      if (!is.null(state$changes[[numeric_url]])) out$value[[1L]] <- out$value[[1L]] - .1
      p$canonical_url <- p$final_url <- entry$canonical_url
      p$raw_sha256 <- entry$raw_sha256
      p$release <- release
      p$publication_date <- publication$publication_date[[1L]]
      p$banks_view <- readboj:::snapshot_provenance(primary)
      p$full_text_url <- publication$full_text_url[[1L]]
      p$full_text_date <- publication$full_text_date[[1L]]
      readboj:::attach_provenance(out, p)
    }, .package = 'readboj', .env = .env)
  state
}
