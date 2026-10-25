# Format-independent semantic cells. No release dates, page locations, target
# horizons or observed values are runtime admission metadata.
outlook_measure <- function(header) {
  header <- outlook_space(header)
  key <- tolower(gsub("[^a-zA-Z0-9 ]", " ", header))
  key <- outlook_space(key)
  id <- if (key == "real gdp") "real_gdp" else if (key %in% c("domestic wpi", "domestic wp")) {
    "domestic_wpi"
  } else if (grepl("domestic cgpi", key) && grepl("consumption", key)) {
    "domestic_cgpi_ex_consumption_tax"
  } else if (key == "domestic cgpi") "domestic_cgpi" else if (grepl("perishables", key)) {
    "cpi_ex_perishables"
  } else if (grepl("consumption", key) && grepl("education", key)) {
    "cpi_ex_fresh_food_ex_tax_education"
  } else if (grepl("consumption", key)) "cpi_ex_fresh_food_ex_consumption_tax" else if (
    grepl("cpi", key) && grepl("fresh food and energy", key)) "cpi_ex_fresh_food_energy" else if (
    grepl("cpi", key) && grepl("fresh food", key)) "cpi_ex_fresh_food" else {
      outlook_schema_error("Unrecognized forecast measure header; identity needs review.", header = header)
    }
  list(id = id, label = header)
}

outlook_vintage <- function(text) {
  m <- regmatches(text, regexec("([A-Za-z]+) +([0-9]{4})", text))[[1L]]
  if (length(m) != 3L || is.na(outlook_month(m[[2L]]))) outlook_schema_error(
    "A comparator has no unambiguous named publication month.", source_label = text)
  sprintf("%s-%02d", m[[3L]], outlook_month(m[[2L]]))
}

outlook_years <- function(text) {
  m <- regmatches(text, gregexpr("[Ff]iscal +[0-9]{4}", text))[[1L]]
  unique(as.integer(sub("[Ff]iscal +", "", m)))
}

outlook_parenthetical_vintage <- function(notes) {
  m <- regmatches(notes, regexec(
    "[Pp]arenthese[s]?[^.]*?([A-Z][a-z]+) +([0-9]{4})", notes, perl = TRUE))[[1L]]
  if (length(m)) outlook_vintage(paste(m[[2L]], m[[3L]])) else NA_character_
}

outlook_point_status <- function(measure, year, comparison, label, notes) {
  if (comparison != "current") return("published_point")
  notes <- outlook_space(notes)
  actual <- grepl("[Aa]ctual", label)
  # Require explicit subject and fiscal target. A lone number is not enough to
  # call a value an actual, and a conditional estimate is not an actual.
  sentences <- strsplit(notes, paste0("(?<=[.]) +(?=[A-Z0-9])|",
    ", +and +(?=(?:the )?(?:CPI|domestic CGPI|real GDP))"), perl = TRUE)[[1L]]
  subject <- if (startsWith(measure, "cpi")) "CPI|consumer price" else if (measure == "real_gdp") {
    "GDP"
  } else if (startsWith(measure, "domestic_cgpi")) "CGPI|corporate goods" else "WPI|wholesale"
  year_match <- grepl(paste0("[Ff]iscal +", year, "\\b"), sentences, perl = TRUE)
  inherited_year <- c(FALSE, utils::head(year_match, -1L)) &
    !grepl("[0-9]{4}", sentences) & grepl("actual", sentences, ignore.case = TRUE)
  qualified <- sentences[grepl(subject, sentences, ignore.case = TRUE) &
    (year_match | inherited_year | actual)]
  adjusted <- grepl("_ex_consumption_tax|_ex_tax_education", measure)
  adjustment_note <- grepl("consumption tax|free education|direct effects|contribution", qualified,
    ignore.case = TRUE)
  if (adjusted) {
    qualified <- qualified[adjustment_note]
    # A headline actual does not make a mechanically adjusted reference actual.
    actual <- FALSE
  } else qualified <- qualified[!adjustment_note]
  if (length(qualified) && any(grepl("calculated|estimated|estimation", qualified, ignore.case = TRUE) &
      grepl("assumption|assuming", qualified, ignore.case = TRUE))) return("conditional_estimate")
  assertions <- qualified[grepl("\\b(is|are) +(an? +|the +)?actual +(figure|value)s?\\b",
    qualified, ignore.case = TRUE, perl = TRUE)]
  if (measure == "cpi_ex_fresh_food_energy") assertions <- assertions[
    grepl("CPI figures|fresh food and energy", assertions, ignore.case = TRUE)]
  if (length(assertions)) actual <- TRUE
  if (actual) "actual" else "published_point"
}

outlook_cell_values <- function(cell, scope, status = "forecast") {
  raw <- outlook_space(cell)
  text <- gsub("[\u2013\u2212\u2014]", "-", raw, perl = TRUE)
  text <- gsub("([+-]) +([0-9])", "\\1\\2", text)
  text <- gsub("\\[ +", "[", text)
  text <- gsub(" +\\]", "]", text)
  if (text %in% c("--", "-", "\u2015", "n.a.")) return(data.frame(
    statistic = "not_applicable", value = NA_real_, raw_value = raw,
    value_status = "not_applicable"))
  number <- "([+-]?[0-9]+\\.[0-9]+)"
  match <- regmatches(text, regexec(paste0("^", number, " +to +", number,
    "(?: *\\[", number, "\\])?$"), text, perl = TRUE))[[1L]]
  if (length(match)) {
    if (status == "actual") outlook_schema_error(
      "The source labels this cell as an actual but prints a forecast range.", raw_cell = raw)
    values <- as.numeric(match[2:3])
    if (values[[1L]] > values[[2L]]) outlook_schema_error("Reversed member range.", raw_cell = raw)
    statistics <- paste0(if (scope == "all_members") "all_" else "majority_", c("lower", "upper"))
    raw_values <- match[2:3]
    if (length(match) >= 4L && nzchar(match[[4L]])) {
      median <- as.numeric(match[[4L]])
      if (median < values[[1L]] || median > values[[2L]]) outlook_schema_error(
        "Median is outside its member range.", raw_cell = raw)
      values <- c(values, median)
      raw_values <- c(raw_values, match[[4L]])
      statistics <- c(statistics, "median")
    }
    return(data.frame(statistic = statistics, value = values, raw_value = raw_values,
      value_status = "forecast"))
  }
  if (grepl(paste0("^", number, "$"), text)) return(data.frame(
    statistic = if (status == "published_point") "point" else status,
    value = as.numeric(text), raw_value = text, value_status = status))
  outlook_schema_error("Unrecognized published numeric cell; no values were inferred.", raw_cell = raw)
}

outlook_cell_parts <- function(cell, parenthetical_vintage) {
  match <- regmatches(cell, regexec("^(.*?) *\\(([^()]*)\\) *$", cell, perl = TRUE))[[1L]]
  if (!length(match)) return(list(list(text = cell, vintage = NULL)))
  if (is.na(parenthetical_vintage)) outlook_schema_error(
    "Parenthesized figures lack a dated comparator definition.", raw_cell = cell)
  list(list(text = outlook_space(match[[2L]]), vintage = NULL),
    list(text = outlook_space(match[[3L]]), vintage = parenthetical_vintage))
}

outlook_range_semantics <- function(notes, scope, comparison, vintage) {
  first <- sub("^.*?Notes?: *1\\. *", "", notes, perl = TRUE)
  pieces <- strsplit(first, " 2\\. ", perl = TRUE)[[1L]]
  first <- if (length(pieces)) pieces[[1L]] else ""
  intervals <- grepl("made their forecasts as a range|submit[^.]*two figures", first,
    ignore.case = TRUE)
  if (comparison == "prior" && !is.na(vintage)) {
    month <- month.name[[as.integer(substr(vintage, 6L, 7L))]]
    if (grepl(paste0("In the ", month, " Outlook Report[^.]*made their forecasts as a range"),
        notes, ignore.case = TRUE)) intervals <- TRUE
    if (grepl(paste0("In the ", month, " Outlook Report[^.]*point estimates"),
        notes, ignore.case = TRUE)) intervals <- FALSE
  }
  list(input = if (intervals) "member_intervals" else "member_points",
    trimming = if (scope == "all_members") "none" else if (intervals) {
      "two_highest_and_two_lowest_endpoints"
    } else "highest_and_lowest_member_points")
}

outlook_observation <- function(cell, header, year, label, comparison, vintage,
    publication, scope, table_index, row, column, notes, source_cell,
    page = NA_integer_, printed_page = NA_character_, xpath = NA_character_,
    column_span = as.character(column), bbox = rep(NA_real_, 4L)) {
  measure <- outlook_measure(header)
  if (comparison == "prior" && measure$id == "domestic_cgpi" &&
      grepl("[Ff]orecasts for domestic [^.]*WPI|[Ff]orecasts for domestic wholesale price", notes)) {
    measure <- list(id = "domestic_wpi", label = "Domestic WPI (prior comparator; source footnote)")
  }
  values <- outlook_cell_values(cell, scope, outlook_point_status(
    measure$id, year, comparison, label, notes))
  semantics <- outlook_range_semantics(notes, scope, comparison, vintage)
  data.frame(release = publication$release, publication_date = publication$publication_date,
    forecast_vintage = vintage, comparison = comparison, fiscal_year = year,
    period = paste0("FY", year), period_start = as.Date(sprintf("%04d-04-01", year)),
    period_end = as.Date(sprintf("%04d-03-31", year + 1L)),
    measure = measure$id, measure_label = measure$label, source_header = header,
    statistic = values$statistic,
    value = values$value, raw_value = values$raw_value, raw_cell = outlook_space(cell),
    value_status = values$value_status, unit = "y/y % chg.", frequency = "ANNUAL(MAR)",
    range_scope = scope, member_input = semantics$input, range_trimming = semantics$trimming,
    table_id = .readboj_outlook_table, table_index = table_index,
    pdf_page = page, printed_page = printed_page, table_row = row, table_column = column,
    source_row_label = label, source_cell_id = source_cell, source_xpath = xpath,
    source_column_span = column_span, shared_cell = grepl(":", column_span, fixed = TRUE),
    pdf_xmin = bbox[[1L]], pdf_ymin = bbox[[2L]], pdf_xmax = bbox[[3L]], pdf_ymax = bbox[[4L]])
}

outlook_finish <- function(tables, deadline) {
  if (!length(tables)) readboj_abort("This publication contains no identified numeric forecast table.",
    "readboj_no_forecast_table_error")
  result <- do.call(rbind, tables)
  groups <- split(result, interaction(result$table_index, result$comparison, result$range_scope,
    drop = TRUE))
  for (group in groups) {
    if (any(group$statistic == "median") && any(group$range_scope == "majority")) {
      cells <- split(group, paste(group$fiscal_year, group$measure, sep = ":"))
      for (cell in cells) if (any(cell$statistic == "majority_lower") &&
          !any(cell$statistic == "median")) outlook_schema_error(
        "A median-bearing table has an incomplete forecast cell.", raw_cell = cell$raw_cell[[1L]])
    }
  }
  identity <- c("forecast_vintage", "comparison", "fiscal_year", "measure", "statistic", "range_scope")
  if (anyDuplicated(result[identity])) outlook_schema_error(
    "The publication contains duplicate forecast identities; tables were not collapsed.")
  if (!any(is.finite(result$value))) outlook_schema_error("No numeric forecast values found.")
  rownames(result) <- NULL
  deadline_remaining(deadline)
  result
}
