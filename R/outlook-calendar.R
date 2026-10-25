.readboj_outlook_calendar_url <- "https://www.boj.or.jp/en/mopo/mpmsche_minu/"
.readboj_outlook_holidays_url <- "https://www.boj.or.jp/en/about/outline/holi.htm"

outlook_utc <- function(x) {
  if (is.null(x) || !length(x) || is.na(x)) return(NA_character_)
  format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

outlook_tokyo_time <- function(date, time = "00:00:00") {
  instant <- as.POSIXct(paste(as.character(date), time), tz = "Asia/Tokyo")
  as.POSIXct(as.numeric(instant), origin = "1970-01-01", tz = "UTC")
}

outlook_calendar_year <- function(table) {
  heading <- outlook_space(xml2::xml_text(xml2::xml_find_first(table,
    "preceding::*[self::h2 or self::h3][1]")))
  if (grepl("^[0-9]{4}$", heading)) return(as.integer(heading))
  caption <- xml2::xml_text(xml2::xml_find_first(table, "./caption"))
  year <- regmatches(caption, regexpr("[0-9]{4}", caption))
  if (length(year) != 1L || !nzchar(year)) readboj_abort(
    "Official calendar table has no unambiguous year.", "readboj_outlook_calendar_error")
  as.integer(year)
}

outlook_calendar_date <- function(text, year) {
  text <- outlook_space(gsub("\\[[^]]*\\]|\\([^)]*\\)", " ", text))
  match <- regmatches(text, regexec("^([A-Za-z]+)\\.? +([0-9]{1,2})(?:[ ,]+([0-9]{4}))?", text))[[1L]]
  if (length(match) != 4L || is.na(outlook_month(match[[2L]]))) readboj_abort(
    "Unrecognized official Outlook calendar date.", "readboj_outlook_calendar_error", text = text)
  if (nzchar(match[[4L]])) year <- as.integer(match[[4L]])
  date <- suppressWarnings(as.Date(sprintf("%04d-%02d-%02d", year,
    outlook_month(match[[2L]]), as.integer(match[[3L]]))))
  if (is.na(date)) readboj_abort("Invalid official calendar date.", "readboj_outlook_calendar_error")
  date
}

outlook_calendar_headers <- function(table) {
  grid <- outlook_html_grid(table)
  text <- vapply(grid$nodes, outlook_html_text, character(1L))
  headers <- vapply(seq_len(ncol(grid$grid)), function(column) {
    ids <- unique(stats::na.omit(grid$grid[grid$header, column]))
    outlook_space(paste(text[ids], collapse = " "))
  }, character(1L))
  list(grid = grid, text = text, headers = headers)
}

parse_outlook_holidays <- function(path) {
  doc <- xml2::read_html(path)
  dates <- as.Date(character())
  years <- integer()
  for (table in xml2::xml_find_all(doc, ".//table")) {
    value <- outlook_calendar_headers(table)
    if (!identical(value$headers, c("Month", "Date"))) next
    year <- outlook_calendar_year(table) # Heading is authoritative; captions can lag a year.
    months <- integer()
    for (r in which(!value$grid$header)) {
      ids <- value$grid$grid[r, ]
      if (anyNA(ids)) readboj_abort("Incomplete official holiday table.", "readboj_outlook_calendar_error")
      month <- outlook_month(value$text[[ids[[1L]]]])
      if (is.na(month)) readboj_abort("Unknown holiday month.", "readboj_outlook_calendar_error")
      months <- c(months, month)
      raw <- value$text[[ids[[2L]]]]
      if (grepl("^[-\u2013\u2014]+$", raw)) next
      if (!grepl("^[0-9, ]+$", raw)) readboj_abort("Unknown holiday date syntax.", "readboj_outlook_calendar_error")
      days <- as.integer(strsplit(gsub(" ", "", raw), ",", fixed = TRUE)[[1L]])
      days <- days[!is.na(days)]
      parsed <- suppressWarnings(as.Date(sprintf("%04d-%02d-%02d", year, month, days)))
      if (anyNA(parsed)) readboj_abort("Invalid holiday date.", "readboj_outlook_calendar_error")
      dates <- c(dates, parsed)
    }
    if (!setequal(months, 1:12) || anyDuplicated(months) || year %in% years) readboj_abort(
      "Incomplete or duplicated holiday-year coverage.", "readboj_outlook_calendar_error")
    years <- c(years, year)
  }
  if (!length(years)) readboj_abort("No official holiday calendars found.", "readboj_outlook_calendar_error")
  list(dates = sort(unique(dates)), years = sort(years))
}

outlook_next_business_day <- function(date, holidays) {
  candidate <- date
  confirmed <- TRUE
  for (i in seq_len(30L)) {
    candidate <- candidate + 1
    year <- as.integer(format(candidate, "%Y"))
    confirmed <- confirmed && year %in% holidays$years
    weekday <- as.POSIXlt(candidate, tz = "UTC")$wday
    year_close <- format(candidate, "%m-%d") %in% c("12-31", "01-01", "01-02", "01-03")
    if (!weekday %in% c(0L, 6L) && !year_close && !candidate %in% holidays$dates) {
      return(list(date = candidate, confirmed = confirmed))
    }
  }
  readboj_abort("No business day within the bounded calendar horizon.", "readboj_outlook_calendar_error")
}

parse_outlook_calendar <- function(path, holidays) {
  doc <- xml2::read_html(path)
  body <- outlook_space(xml2::xml_text(doc))
  if (!grepl("immediately after relevant MPMs", body, fixed = TRUE) ||
      !grepl("full text at (2:00 p\\.m\\.|14:00) on the next business day", body)) readboj_abort(
    "Official Outlook timing rule is missing or changed; refusing to assume a release time.",
    "readboj_outlook_calendar_error")
  result <- list()
  for (table in xml2::xml_find_all(doc, ".//table")) {
    value <- outlook_calendar_headers(table)
    column <- which(grepl("Outlook Report.*Bank.s View", value$headers))
    if (!length(column)) next
    meeting <- which(grepl("Date of MPM", value$headers, fixed = TRUE))
    if (length(column) != 1L || length(meeting) != 1L) readboj_abort(
      "Ambiguous Outlook calendar column.", "readboj_outlook_calendar_error")
    year <- outlook_calendar_year(table)
    for (r in which(!value$grid$header)) {
      id <- value$grid$grid[r, column]
      if (is.na(id)) readboj_abort("Missing Outlook calendar cell.", "readboj_outlook_calendar_error")
      text <- value$text[[id]]
      if (grepl("^[-\u2013\u2014]+$", text)) next # Non-Outlook MPM; Summary/Minutes never supply dates.
      date <- outlook_calendar_date(text, year)
      start <- outlook_calendar_date(value$text[[value$grid$grid[r, meeting]]], year)
      business <- outlook_next_business_day(date, holidays)
      result[[length(result) + 1L]] <- data.frame(edition_hint = format(start, "%Y-%m"),
        meeting_start_date = start, publication_date = date,
        bank_view_poll_from_at = outlook_tokyo_time(date),
        bank_view_timing = "after_mpm_no_fixed_time",
        full_text_date = if (business$confirmed) business$date else as.Date(NA),
        full_text_poll_from_at = outlook_tokyo_time(business$date, "14:00:00"),
        business_day_confirmed = business$confirmed,
        timing_rule = "in_principle_14:00_Asia/Tokyo_next_business_day",
        calendar_xpath = xml2::xml_path(value$grid$nodes[[id]]), retained_pending = FALSE)
    }
  }
  if (!length(result)) readboj_abort("No Outlook dates found in the official calendar.", "readboj_outlook_calendar_error")
  result <- do.call(rbind, result)
  if (nrow(result) > 500L || anyDuplicated(result$publication_date) || anyDuplicated(result$edition_hint)) readboj_abort(
    "Excessive or ambiguous Outlook dates.", "readboj_outlook_calendar_error")
  result <- result[order(result$publication_date), , drop = FALSE]
  rownames(result) <- NULL
  result
}

outlook_fetch_calendar <- function(timeout, retries, deadline, stage_dir = NULL) {
  stage <- stage_dir %||% tempfile("readboj-calendar-")
  if (!is.null(stage_dir)) unlink(stage, recursive = TRUE)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  calendar <- outlook_update_request(.readboj_outlook_calendar_url, NULL,
    file.path(stage, "calendar.htm"), timeout, retries, 0, 2 * 1024^2, deadline)
  holiday <- outlook_update_request(.readboj_outlook_holidays_url, NULL,
    file.path(stage, "holidays.htm"), timeout, retries, 0, 2 * 1024^2, deadline)
  holidays <- parse_outlook_holidays(holiday$path)
  list(events = parse_outlook_calendar(calendar$path, holidays), holidays = holidays,
    checked_at = outlook_now(), sources = list(calendar = outlook_clean_receipt(calendar),
      holidays = outlook_clean_receipt(holiday)))
}

#' Discover the official Outlook publication calendar
#'
#' Selects only the Outlook Bank's View column of the MPM schedule. Summary,
#' Minutes and non-Outlook meetings supply no release dates. Bank's View has no
#' fixed publication time; its timestamp is a date-start polling boundary.
#' Full text uses the official next-business-day 14:00 Tokyo rule and BoJ holiday
#' tables. If holiday-year coverage is unavailable its polling bound is marked
#' unconfirmed, rather than asserted as a publication date.
#' @param upcoming_only Keep reports with a Bank's View date or full-text stage
#'   still on/after the current Tokyo date/time.
#' @param timeout,retries,deadline Bounded transport settings as in [update_boj_outlook()].
#' @return A data frame with edition hints, publication dates and separate stage
#'   polling times, with official source receipts in provenance. The archive's
#'   actual edition identity takes precedence over a meeting-month hint.
#' @examples
#' \dontrun{
#' list_boj_outlook_calendar(timeout = 10, retries = 0L,
#'                         deadline = Sys.time() + 30)
#' }
#' @export
list_boj_outlook_calendar <- function(upcoming_only = TRUE, timeout = 30, retries = 2L,
    deadline = NULL) {
  upcoming_only <- scalar_flag(upcoming_only, "upcoming_only")
  timeout <- scalar_number(timeout, "timeout", min = 0.001)
  retries <- outlook_count(retries + 1, "retries + 1", 11L) - 1L
  calendar <- outlook_fetch_calendar(timeout, retries, resolve_deadline(deadline, 120))
  events <- calendar$events
  if (upcoming_only) events <- events[events$publication_date >= as.Date(outlook_now(), tz = "Asia/Tokyo") |
    events$full_text_poll_from_at >= outlook_now(), , drop = FALSE]
  attach_provenance(events, list(source = "Bank of Japan MPM Outlook column and bank holidays",
    checked_at = calendar$checked_at, sources = calendar$sources))
}
