#' Extract readboj provenance
#'
#' @param x An object returned by readboj.
#' @return A provenance list, or `NULL` when none is attached.
#' @export
boj_provenance <- function(x) attr(x, "readboj_provenance", exact = TRUE)

attach_provenance <- function(x, provenance) {
  attr(x, "readboj_provenance") <- provenance
  x
}

semantic_json_hash <- function(path, max_bytes = 128 * 1024^2) {
  raw <- read_raw_file(path, max_bytes)
  payload <- tryCatch(
    jsonlite::fromJSON(rawToChar(raw), simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) return(NA_character_)
  if (is.list(payload) && !is.null(names(payload))) payload$DATE <- NULL
  canonical <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", digits = 17,
    pretty = FALSE, force = TRUE)
  digest::digest(charToRaw(enc2utf8(canonical)), algo = "sha256", serialize = FALSE)
}

semantic_csv_hash <- function(path, encoding, max_bytes = 128 * 1024^2) {
  text <- iconv(rawToChar(read_raw_file(path, max_bytes)), from = encoding,
    to = "UTF-8", sub = NA)
  if (length(text) != 1L || is.na(text)) return(NA_character_)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  lines[startsWith(lines, "DATE,")] <- "DATE,"
  canonical <- paste(lines, collapse = "\n")
  digest::digest(charToRaw(enc2utf8(canonical)), algo = "sha256", serialize = FALSE)
}
