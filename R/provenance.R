#' Extract readboj provenance
#'
#' readboj attaches a readboj_provenance attribute to data frames, lists, and
#' downloaded file paths when the source identity can be retained. This accessor
#' returns that attribute without recomputing hashes or touching the filesystem.
#' It is therefore safe to use on an object after its source file has moved,
#' although the recorded path may no longer exist.
#'
#' Provenance is a named list whose fields depend on the producer. API and
#' download results commonly include canonical_url, final_url, retrieved_at,
#' raw_sha256, bytes, HTTP headers, cache status and parser schema; metadata,
#' catalogue, and local-parser results may add database, query, manifest, or
#' source fields. The list is descriptive evidence, not a live authorization
#' check and not a guarantee that an external URL remains available.
#'
#' @param x Any R object. Objects without the exact readboj_provenance attribute
#'   return NULL; x is not otherwise validated or modified.
#' @return The exact object stored in x's readboj_provenance attribute, normally
#'   a named list, or NULL when that attribute is absent. No copy is normalized
#'   and no class is added.
#' @seealso [boj_databases()], [boj_metadata()], [read_boj_snapshot()],
#'   [download_boj_bulk()]
#' @family provenance functions
#' @examples
#' databases <- boj_databases()
#' provenance <- boj_provenance(databases)
#' stopifnot(is.list(provenance), identical(provenance$database_count, 50L))
#' stopifnot(is.null(boj_provenance(list())))
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
