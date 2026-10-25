#' Parse an exact local Bank of Japan response snapshot
#'
#' Supports deterministic offline parser certification without a network
#' request. Official values are not bundled; package fixtures are synthetic.
#'
#' @param path Local response-body path.
#' @param type `"data_json"`, `"data_csv"`, or `"metadata_csv"`.
#' @param db Database identity needed by the normalized schema.
#' @param language Data CSV language, `"en"` or `"jp"`.
#' @param encoding Metadata CSV encoding.
#' @param max_bytes Maximum input bytes.
#' @param max_rows Maximum metadata rows.
#' @return A parsed data frame with local hash provenance.
#' @export
read_boj_snapshot <- function(path,
    type = c("data_json", "data_csv", "metadata_csv"), db,
    language = "en", encoding = "UTF-8", max_bytes = 128 * 1024^2,
    max_rows = 50000L) {
  path <- scalar_character(path, "path")
  if (!file.exists(path) || dir.exists(path)) readboj_abort("`path` is not a regular file.",
    "readboj_parameter_error")
  type <- match.arg(type)
  db <- normalize_db(db)
  language <- normalize_language(language, both = FALSE)
  size <- file.info(path)$size
  if (size > max_bytes) readboj_abort("Snapshot exceeds `max_bytes`.", "readboj_size_error")
  out <- if (type == "data_json") {
    parse_observation_payload(api_payload(path, max_bytes), db)
  } else if (type == "data_csv") {
    parse_observation_csv(path, db, language, max_rows)$data
  } else {
    parse_metadata_csv(path, db, encoding, max_rows)
  }
  attach_provenance(out, list(source = "local response snapshot", path = normalizePath(path),
    raw_sha256 = sha256_file(path), semantic_sha256 = if (type == "data_json")
      semantic_json_hash(path, max_bytes) else if (type == "data_csv")
      semantic_csv_hash(path, if (language == "jp") "CP932" else "UTF-8",
        max_bytes) else NA_character_, bytes = unname(size),
    parser_schema = .readboj_schema_version, package_version = readboj_package_version()))
}
