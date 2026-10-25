readboj_abort <- function(message, class = "readboj_error", ...) {
  condition <- structure(
    c(list(message = message, call = NULL), list(...)),
    class = c(class, "readboj_error", "error", "condition")
  )
  stop(condition)
}

scalar_character <- function(x, name, choices = NULL) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    readboj_abort(sprintf("`%s` must be one non-empty string.", name), "readboj_parameter_error")
  }
  if (!is.null(choices) && !x %in% choices) {
    readboj_abort(
      sprintf("`%s` must be one of: %s.", name, paste(choices, collapse = ", ")),
      "readboj_parameter_error"
    )
  }
  x
}

scalar_number <- function(x, name, min = -Inf, integer = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x < min ||
      (integer && x != floor(x))) {
    readboj_abort(sprintf("`%s` must be one finite%s number >= %s.", name,
      if (integer) " whole" else "", format(min)), "readboj_parameter_error")
  }
  if (integer) as.integer(x) else as.numeric(x)
}

scalar_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    readboj_abort(sprintf("`%s` must be TRUE or FALSE.", name), "readboj_parameter_error")
  }
  x
}

normalize_db <- function(db) {
  db <- toupper(scalar_character(db, "db"))
  if (!grepl("^[A-Z]{2,3}[0-9]{0,2}$", db)) {
    readboj_abort("`db` is not a valid BoJ database identifier.", "readboj_parameter_error")
  }
  db
}

normalize_language <- function(language, both = TRUE) {
  choices <- if (both) c("both", "en", "jp") else c("en", "jp")
  tolower(scalar_character(language, "language", choices))
}

normalize_period <- function(x, name) {
  if (is.null(x)) return(NULL)
  x <- scalar_character(as.character(x), name)
  if (!grepl("^[0-9]{4}([0-9]{2})?$", x)) {
    readboj_abort(sprintf("`%s` must be YYYY or YYYYPP.", name), "readboj_parameter_error")
  }
  x
}

sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)

read_raw_file <- function(path, max_bytes = Inf) {
  size <- file.info(path)$size
  if (is.na(size) || size > max_bytes) {
    readboj_abort(sprintf("Snapshot is %s bytes, exceeding the %s-byte bound.", size, max_bytes),
      "readboj_size_error", bytes = size, byte_limit = max_bytes)
  }
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  readBin(connection, what = "raw", n = size)
}

decode_complete_line_prefix <- function(path, encoding, bytes) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  prefix <- readBin(connection, what = "raw", n = bytes)
  line_ends <- which(prefix == as.raw(0x0a))
  if (length(line_ends)) {
    prefix <- prefix[seq_len(utils::tail(line_ends, 1L))]
  }
  if (!length(prefix)) return(NA_character_)
  tryCatch(
    iconv(rawToChar(prefix), from = encoding, to = "UTF-8", sub = NA),
    error = function(error) NA_character_
  )
}

empty_metadata <- function() {
  data.frame(
    db = character(), series_code = character(), name_jp = character(),
    name_en = character(), unit_jp = character(), unit_en = character(),
    frequency = character(), category_jp = character(), category_en = character(),
    layer1 = integer(), layer2 = integer(), layer3 = integer(), layer4 = integer(),
    layer5 = integer(), start_time = character(), end_time = character(),
    last_update = as.Date(character()), notes_jp = character(), notes_en = character(),
    is_series = logical(), stringsAsFactors = FALSE
  )
}

empty_observations <- function() {
  data.frame(
    db = character(), series_code = character(), name_en = character(),
    name_jp = character(), unit_en = character(), unit_jp = character(),
    frequency = character(), category_en = character(), category_jp = character(),
    last_update = as.Date(character()), period = character(), date = as.Date(character()),
    value = double(), raw_value = character(), value_status = character(),
    stringsAsFactors = FALSE
  )
}

parse_yyyymmdd <- function(x) {
  x <- if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1L]])
  if (is.na(x) || !grepl("^[0-9]{8}$", x)) return(as.Date(NA_character_))
  as.Date(x, format = "%Y%m%d")
}

period_date_one <- function(period, frequency) {
  if (is.na(period) || !nzchar(period)) return(as.Date(NA_character_))
  if ((identical(frequency, "DAILY") || startsWith(frequency, "WEEKLY(")) &&
      grepl("^[0-9]{8}$", period)) return(as.Date(period, "%Y%m%d"))
  if (!grepl("^[0-9]{4}([0-9]{2})?$", period)) return(as.Date(NA_character_))
  year <- as.integer(substr(period, 1L, 4L))
  part <- if (nchar(period) == 6L) as.integer(substr(period, 5L, 6L)) else NA_integer_
  month <- switch(frequency,
    "ANNUAL" = 1L, "ANNUAL(MAR)" = 4L,
    "SEMIANNUAL" = if (part == 1L) 1L else if (part == 2L) 7L else NA_integer_,
    "SEMIANNUAL(SEP)" = if (part == 1L) 4L else if (part == 2L) 10L else NA_integer_,
    "QUARTERLY" = if (part %in% 1:4) 1L + 3L * (part - 1L) else NA_integer_,
    "MONTHLY" = if (part %in% 1:12) part else NA_integer_, NA_integer_)
  if (is.na(month)) return(as.Date(NA_character_))
  as.Date(sprintf("%04d-%02d-01", year, month))
}

period_date <- function(period, frequency) {
  as.Date(mapply(period_date_one, as.character(period), as.character(frequency),
    USE.NAMES = FALSE), origin = "1970-01-01")
}

readboj_package_version <- function() {
  tryCatch(as.character(utils::packageVersion("readboj")), error = function(e) "development")
}
