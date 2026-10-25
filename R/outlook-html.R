outlook_html_grid <- function(table) {
  rows <- xml2::xml_find_all(table, "./thead/tr|./tbody/tr|./tr")
  if (length(rows) > 100L) readboj_abort("Forecast HTML table exceeds 100 rows.", "readboj_size_error")
  grid <- matrix(NA_integer_, length(rows), 20L)
  nodes <- list()
  header <- logical(length(rows))
  for (r in seq_along(rows)) {
    header[[r]] <- xml2::xml_name(xml2::xml_parent(rows[[r]])) == "thead"
    cells <- xml2::xml_find_all(rows[[r]], "./th|./td")
    column <- 1L
    for (cell in cells) {
      while (column <= 20L && !is.na(grid[r, column])) column <- column + 1L
      span <- suppressWarnings(as.integer(xml2::xml_attr(cell, "colspan")))
      height <- suppressWarnings(as.integer(xml2::xml_attr(cell, "rowspan")))
      if (is.na(span)) span <- 1L
      if (is.na(height)) height <- 1L
      if (span < 1L || height < 1L || column + span - 1L > 20L || r + height - 1L > nrow(grid)) {
        outlook_schema_error("Invalid forecast HTML table span.")
      }
      rr <- r:(r + height - 1L)
      cc <- column:(column + span - 1L)
      if (any(!is.na(grid[rr, cc]))) outlook_schema_error("Overlapping forecast HTML cells.")
      nodes[[length(nodes) + 1L]] <- cell
      grid[rr, cc] <- length(nodes)
      column <- column + span
    }
  }
  width <- max(which(colSums(!is.na(grid)) > 0L))
  list(grid = grid[, seq_len(width), drop = FALSE], nodes = nodes, header = header)
}

outlook_html_text <- function(node) {
  # xml_text does not insert separators at br/span boundaries. Preserve them
  # explicitly; source bytes and XPath are retained separately.
  clone <- xml2::read_html(paste0("<html><body><table><tr>", as.character(node),
    "</tr></table></body></html>"), encoding = "UTF-8")
  xml2::xml_remove(xml2::xml_find_all(clone, ".//sup"))
  breaks <- xml2::xml_find_all(clone, ".//br")
  for (br in breaks) xml2::xml_text(br) <- " "
  outlook_space(xml2::xml_text(clone))
}

parse_outlook_html <- function(document, publication, deadline) {
  main <- xml2::xml_find_first(document, ".//main")
  if (inherits(main, "xml_missing")) main <- xml2::xml_root(document)
  text <- outlook_space(xml2::xml_text(main))
  tables <- xml2::xml_find_all(main, ".//table[.//th[contains(., 'Real GDP')]]")
  if (!length(tables)) return(NULL)
  note_nodes <- xml2::xml_find_all(tables[[1L]], paste0(
    "following::*[(self::p or self::li or self::h2 or self::h3) ",
    "and ancestor::main and not(ancestor::table)]"))
  if (length(note_nodes)) {
    headings <- xml2::xml_name(note_nodes) %in% c("h2", "h3")
    stop <- which(headings & grepl("Risk Assessments|Risk Balance|Charts?|Reference",
      xml2::xml_text(note_nodes), ignore.case = TRUE))
    if (length(stop)) note_nodes <- note_nodes[seq_len(stop[[1L]] - 1L)]
  }
  source_notes <- outlook_space(paste(xml2::xml_text(note_nodes), collapse = " "))
  if (!nzchar(source_notes)) {
    before <- xml2::xml_find_all(tables[[1L]],
      "preceding::*[(self::p or self::li) and not(ancestor::table)]")
    before_text <- outlook_space(xml2::xml_text(before))
    definitions <- before_text[grepl("highest[^.]*lowest|exclud[^.]*highest", before_text,
      ignore.case = TRUE)]
    source_notes <- paste(utils::tail(definitions, 1L), collapse = " ")
  }
  if (!grepl("[Yy]/[Yy] *% *(change|chg)", text)) outlook_schema_error(
    "Unrecognized forecast table units.")
  if (!grepl("highest[^.]*lowest[^.]*exclud|exclud[^.]*highest[^.]*lowest", text,
      ignore.case = TRUE)) outlook_schema_error(
    "The publication does not define the majority-member range.")
  result <- list()
  for (ti in seq_along(tables)) {
    deadline_remaining(deadline)
    table <- tables[[ti]]
    data <- outlook_html_grid(table)
    texts <- vapply(data$nodes, outlook_html_text, character(1L))
    headers <- vapply(seq_len(ncol(data$grid)), function(c) {
      ids <- unique(stats::na.omit(data$grid[data$header, c]))
      outlook_space(paste(texts[ids], collapse = " "))
    }, character(1L))
    measure_columns <- which(grepl("Real GDP|Domestic|CPI|[Ee]xcluding.*effects", headers))
    if (length(measure_columns) < 2L || length(measure_columns) > 6L) outlook_schema_error(
      "Ambiguous measure columns in forecast HTML.")
    for (h in headers[measure_columns]) outlook_measure(h)
    caption <- outlook_space(xml2::xml_text(xml2::xml_find_first(table, "./caption")))
    predecessors <- xml2::xml_find_all(table,
      "preceding::*[(self::p or self::li or self::h2 or self::h3) and not(ancestor::table)]")
    preceding <- if (length(predecessors)) outlook_space(xml2::xml_text(utils::tail(predecessors, 1L))) else ""
    scope <- if (grepl("forecasts of all|range.*includes.*all", preceding, ignore.case = TRUE) ||
        grepl("[Ff]orecasts of [Aa]ll", caption)) "all_members" else "majority"
    year_context <- outlook_years(caption)
    year <- if (length(year_context) == 1L) year_context[[1L]] else NA_integer_
    parent_vintage <- outlook_parenthetical_vintage(source_notes)
    body <- which(!data$header)
    for (r in seq_along(body)) {
      row_index <- body[[r]]
      label_ids <- unique(stats::na.omit(data$grid[row_index, seq_len(min(measure_columns) - 1L)]))
      label <- outlook_space(paste(texts[label_ids], collapse = " "))
      row_years <- outlook_years(label)
      if (length(row_years) > 1L) outlook_schema_error("Ambiguous fiscal target in HTML row.")
      if (length(row_years)) year <- row_years[[1L]]
      if (is.na(year)) outlook_schema_error("HTML row has no fiscal-year target.", source_label = label)
      prior <- grepl("[Ff]orecasts? (made|of|in)|[Rr]ange of forecasts", label) &&
        grepl("[A-Za-z]+ +[0-9]{4}", label)
      if (prior) {
        date_label <- sub("^.*[Ff]orecasts made in +", "", label)
        vintage <- outlook_vintage(date_label)
      } else vintage <- publication$release
      comparison <- if (prior) "prior" else "current"
      if (!prior && !grepl("[Ff]iscal|[Aa]ctual", label)) outlook_schema_error(
        "Unrecognized forecast HTML row identity.", source_label = label)
      for (j in seq_along(measure_columns)) {
        c <- measure_columns[[j]]
        id <- data$grid[row_index, c]
        if (is.na(id)) outlook_schema_error("Unexplained missing HTML cell.")
        cell <- texts[[id]]
        if (!nzchar(cell)) next # a physically blank cell publishes no statistic
        spans <- which(data$grid[row_index, measure_columns] == id)
        column_span <- paste(range(spans), collapse = ":")
        if (length(spans) == 1L) column_span <- as.character(j)
        for (part in outlook_cell_parts(cell, parent_vintage)) {
          part_comparison <- if (is.null(part$vintage)) comparison else "prior"
          part_vintage <- part$vintage %||% vintage
          result[[length(result) + 1L]] <- outlook_observation(part$text, headers[[c]],
            year, label, part_comparison, part_vintage, publication, scope, ti, r, j, source_notes,
            paste0("html-table-", ti, "/cell-", id), xpath = xml2::xml_path(data$nodes[[id]]),
            column_span = column_span)
        }
      }
    }
  }
  out <- outlook_finish(result, deadline)
  attr(out, "outlook_notes") <- source_notes
  attr(out, "outlook_format_family") <- "semantic-html-tables"
  out
}
