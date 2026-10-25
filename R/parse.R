api_payload <- function(path, max_bytes = 128 * 1024^2) {
  payload <- tryCatch(
    jsonlite::fromJSON(rawToChar(read_raw_file(path, max_bytes)), simplifyVector = FALSE),
    error = function(e) readboj_abort(paste0("Invalid BOJ JSON: ", conditionMessage(e)),
      "readboj_schema_error", parent = e)
  )
  if (!is.list(payload) || is.null(names(payload)) || length(payload$STATUS) != 1L) {
    readboj_abort("BOJ JSON lacks the required scalar STATUS field.", "readboj_schema_error")
  }
  status <- suppressWarnings(as.integer(payload$STATUS))
  if (is.na(status)) readboj_abort("BOJ STATUS is not an integer.", "readboj_schema_error")
  if (status != 200L) {
    readboj_abort(sprintf("BOJ API error %s (%s): %s", status,
      as.character(payload$MESSAGEID %||% ""), as.character(payload$MESSAGE %||% "")),
      "readboj_api_error", status = status, message_id = payload$MESSAGEID,
      api_message = payload$MESSAGE)
  }
  if (is.null(payload$RESULTSET)) payload$RESULTSET <- list()
  if (!is.list(payload$RESULTSET)) {
    readboj_abort("BOJ RESULTSET is not an array.", "readboj_schema_error")
  }
  payload
}

item_character <- function(item, name, default = NA_character_) {
  value <- item[[name]]
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) default else as.character(value[[1L]])
}

item_integer <- function(item, name) {
  value <- suppressWarnings(as.integer(item_character(item, name)))
  if (is.na(value)) NA_integer_ else value
}

item_number <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) return(NA_real_)
  result <- suppressWarnings(as.numeric(value[[1L]]))
  if (is.na(result)) NA_real_ else result
}

parse_observation_payload <- function(payload, db) {
  if (length(payload$RESULTSET) == 0L) return(empty_observations())
  rows <- vector("list", length(payload$RESULTSET))
  for (i in seq_along(payload$RESULTSET)) {
    item <- payload$RESULTSET[[i]]
    if (!is.list(item)) readboj_abort("Observation item is not an object.", "readboj_schema_error")
    code <- item_character(item, "SERIES_CODE", "")
    frequency <- item_character(item, "FREQUENCY", "")
    values <- item$VALUES %||% list()
    dates <- values$SURVEY_DATES %||% list()
    observations <- values$VALUES %||% list()
    if (!is.list(dates)) dates <- as.list(dates)
    if (!is.list(observations)) observations <- as.list(observations)
    if (length(dates) != length(observations)) {
      readboj_abort(sprintf("Series %s has mismatched period and value lengths.", code),
        "readboj_schema_error", series_code = code)
    }
    if (length(dates) == 0L) next
    period <- vapply(dates, function(x) item_character(list(x = x), "x", ""), character(1L))
    value <- vapply(observations, item_number, double(1L))
    raw_value <- vapply(observations, function(x) {
      if (is.null(x) || length(x) == 0L || is.na(x[[1L]])) NA_character_ else
        as.character(x[[1L]])
    }, character(1L))
    rows[[i]] <- data.frame(
      db = rep(db, length(period)), series_code = rep(code, length(period)),
      name_en = rep(item_character(item, "NAME_OF_TIME_SERIES"), length(period)),
      name_jp = rep(item_character(item, "NAME_OF_TIME_SERIES_J"), length(period)),
      unit_en = rep(item_character(item, "UNIT"), length(period)),
      unit_jp = rep(item_character(item, "UNIT_J"), length(period)),
      frequency = rep(frequency, length(period)),
      category_en = rep(item_character(item, "CATEGORY"), length(period)),
      category_jp = rep(item_character(item, "CATEGORY_J"), length(period)),
      last_update = rep(parse_yyyymmdd(item$LAST_UPDATE), length(period)),
      period = period, date = period_date(period, rep(frequency, length(period))),
      value = value, raw_value = raw_value,
      value_status = ifelse(is.na(raw_value), "null", "observed"),
      stringsAsFactors = FALSE
    )
  }
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) return(empty_observations())
  out <- do.call(rbind, rows)
  key <- paste(out$db, out$series_code, out$period, sep = "\r")
  if (anyDuplicated(key)) {
    readboj_abort("Duplicate database/series/period identities were returned; no rows were collapsed.",
      "readboj_identity_error", duplicate_keys = unique(key[duplicated(key) |
        duplicated(key, fromLast = TRUE)]))
  }
  rownames(out) <- NULL
  out
}

decode_prefix <- function(path, encoding, bytes = 65536L) {
  decoded <- decode_complete_line_prefix(path, encoding, bytes)
  if (length(decoded) != 1L || is.na(decoded)) readboj_abort(
    sprintf("BOJ response is not valid %s text.", encoding), "readboj_schema_error")
  decoded
}

api_csv_layout <- function(path, encoding) {
  lines <- strsplit(decode_prefix(path, encoding), "\n", fixed = TRUE)[[1L]]
  lines <- sub("\r$", "", lines)
  header_candidates <- which(startsWith(lines, "SERIES_CODE,"))
  if (!length(header_candidates) || header_candidates[[1L]] < 2L) readboj_abort(
    "BOJ data CSV header was not found within the bounded prefix.",
    "readboj_schema_error")
  header <- header_candidates[[1L]]
  preamble_lines <- lines[seq_len(header - 1L)]
  names <- sub(",.*$", "", preamble_lines)
  values <- sub("^[^,]*,", "", preamble_lines)
  first_value <- function(name) {
    match <- which(names == name)
    if (!length(match)) NA_character_ else values[[match[[1L]]]]
  }
  preamble <- c(STATUS = first_value("STATUS"), MESSAGEID = first_value("MESSAGEID"),
    MESSAGE = first_value("MESSAGE"), DATE = first_value("DATE"),
    NEXTPOSITION = first_value("NEXTPOSITION"))
  if (is.na(preamble[["STATUS"]]) || !identical(preamble[["STATUS"]], "200")) {
    readboj_abort(sprintf("BOJ API error %s (%s): %s", preamble[["STATUS"]],
      preamble[["MESSAGEID"]], preamble[["MESSAGE"]]), "readboj_api_error",
      status = suppressWarnings(as.integer(preamble[["STATUS"]])),
      message_id = preamble[["MESSAGEID"]], api_message = preamble[["MESSAGE"]])
  }
  list(skip = header - 1L, preamble = preamble)
}

parse_observation_csv <- function(path, db, language, max_rows) {
  encoding <- if (language == "jp") "CP932" else "UTF-8"
  layout <- api_csv_layout(path, encoding)
  raw <- readr::read_csv(path, skip = layout$skip,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), n_max = max_rows + 1L, progress = FALSE,
    show_col_types = FALSE)
  if (nrow(raw) > max_rows) readboj_abort(
    "BOJ CSV observations exceed the row bound.", "readboj_size_error",
    row_limit = max_rows)
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)
  required <- c("SERIES_CODE", "FREQUENCY", "LAST_UPDATE", "SURVEY_DATES", "VALUES")
  missing <- setdiff(required, names(raw))
  if (length(missing)) readboj_abort(paste0("BOJ data CSV schema drift: missing ",
    paste(missing, collapse = ", "), "."), "readboj_schema_error", missing = missing)
  column <- function(name) if (name %in% names(raw)) as.character(raw[[name]]) else
    rep(NA_character_, nrow(raw))
  value_raw <- column("VALUES")
  out <- data.frame(
    db = rep(db, nrow(raw)), series_code = column("SERIES_CODE"),
    name_en = column("NAME_OF_TIME_SERIES"), name_jp = column("NAME_OF_TIME_SERIES_J"),
    unit_en = column("UNIT"), unit_jp = column("UNIT_J"),
    frequency = column("FREQUENCY"), category_en = column("CATEGORY"),
    category_jp = column("CATEGORY_J"),
    last_update = as.Date(column("LAST_UPDATE"), "%Y%m%d"),
    period = column("SURVEY_DATES"), stringsAsFactors = FALSE
  )
  out$date <- period_date(out$period, out$frequency)
  out$value <- suppressWarnings(as.numeric(value_raw))
  out$raw_value <- value_raw
  out$value_status <- ifelse(is.na(value_raw) | !nzchar(value_raw), "blank", "observed")
  identity <- paste(out$db, out$series_code, out$period, sep = "\r")
  if (anyDuplicated(identity)) readboj_abort(
    "Duplicate database/series/period identities were returned in CSV; no rows were collapsed.",
    "readboj_identity_error")
  list(data = out, preamble = layout$preamble, encoding = encoding)
}

metadata_schema <- c(
  "SERIES_CODE", "NAME_OF_TIME_SERIES", "UNIT", "FREQUENCY", "CATEGORY",
  "LAYER1", "LAYER2", "LAYER3", "LAYER4", "LAYER5",
  "START_OF_THE_TIME_SERIES", "END_OF_THE_TIME_SERIES", "LAST_UPDATE", "NOTES"
)

standardize_metadata <- function(raw, db) {
  missing <- setdiff(metadata_schema, names(raw))
  if (length(missing)) readboj_abort(paste0("BOJ metadata schema drift: missing ",
    paste(missing, collapse = ", "), "."), "readboj_schema_error", missing = missing)
  n <- nrow(raw)
  column <- function(name, default = NA_character_) {
    if (name %in% names(raw)) as.character(raw[[name]]) else rep(default, n)
  }
  integer_column <- function(name) suppressWarnings(as.integer(column(name)))
  data.frame(
    db = rep(db, n), series_code = column("SERIES_CODE", ""),
    name_jp = column("NAME_OF_TIME_SERIES_J"), name_en = column("NAME_OF_TIME_SERIES"),
    unit_jp = column("UNIT_J"), unit_en = column("UNIT"), frequency = column("FREQUENCY"),
    category_jp = column("CATEGORY_J"), category_en = column("CATEGORY"),
    layer1 = integer_column("LAYER1"), layer2 = integer_column("LAYER2"),
    layer3 = integer_column("LAYER3"), layer4 = integer_column("LAYER4"),
    layer5 = integer_column("LAYER5"), start_time = column("START_OF_THE_TIME_SERIES"),
    end_time = column("END_OF_THE_TIME_SERIES"),
    last_update = as.Date(column("LAST_UPDATE"), "%Y%m%d"),
    notes_jp = column("NOTES_J"), notes_en = column("NOTES"),
    is_series = nzchar(column("SERIES_CODE", "")), stringsAsFactors = FALSE
  )
}

parse_metadata_csv <- function(path, db, encoding = "CP932", max_rows = 50000L) {
  max_rows <- scalar_number(max_rows, "max_rows", min = 1, integer = TRUE)
  raw <- readr::read_csv(path, skip = 5L,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), n_max = max_rows + 1L, progress = FALSE, show_col_types = FALSE)
  if (nrow(raw) > max_rows) readboj_abort(sprintf("Metadata exceeds the %s-row materialisation bound.", max_rows),
    "readboj_size_error", row_limit = max_rows)
  standardize_metadata(as.data.frame(raw), db)
}
