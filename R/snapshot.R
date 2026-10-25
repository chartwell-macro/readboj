#' Parse a local Bank of Japan response snapshot
#'
#' Parses one saved Bank of Japan (BOJ) response body with the same
#' normalization used by the network-facing readers. This function is fully
#' offline: it never opens a network connection, writes to the readboj cache,
#' or changes the source file. The package's small `inst/extdata` examples are
#' deterministic synthetic fixtures, not official BOJ observations.
#'
#' @details
#' `type = "data_json"` parses an API JSON response, `type = "data_csv"`
#' parses an observation CSV, and `type = "metadata_csv"` parses a five-row
#' preamble followed by a metadata CSV. The default `type` selects
#' `"data_json"`. `language` is validated for every call and selects CP932 for
#' Japanese observation CSVs; it is otherwise ignored for JSON and metadata
#' snapshots. `encoding` is used for metadata CSV decoding; `"UTF-8"` and
#' `"CP932"` cover the package fixtures and official routes.
#'
#' The file size is checked against `max_bytes` before parsing. For CSV inputs,
#' `max_rows` is an inclusive materialisation bound; it is not used for JSON
#' responses because JSON observations are already bounded by the response
#' body and parser structure. For `data_json` and `data_csv`, non-success API
#' statuses, malformed schemas and duplicate `db`/`series_code`/`period`
#' identities fail closed rather than silently dropping or collapsing rows.
#' A `metadata_csv` input is expected to contain the five-row BOJ preamble and
#' is parsed as a tabular metadata file; its preamble is skipped without
#' interpreting an API status field. Missing JSON values remain rows with an
#' explicit status marker, and CSV blank markers remain observable in
#' `raw_value`.
#'
#' @param path Character path to an existing regular local response-body file.
#'   The returned provenance records its normalized path and exact SHA-256.
#' @param type Response kind: `"data_json"`, `"data_csv"`, or
#'   `"metadata_csv"`. The default expression selects `"data_json"`.
#' @param db BOJ database identifier used to populate the normalized `db`
#'   column; it is normalized to uppercase after validation.
#' @param language For `type = "data_csv"`, response language `"en"` or
#'   `"jp"`; Japanese CSV is decoded as CP932. It is still validated for other
#'   types but does not alter their parsing.
#' @param encoding Character encoding passed to the metadata CSV reader when
#'   `type = "metadata_csv"`; use `"UTF-8"` or `"CP932"` for the supported
#'   BOJ encodings.
#' @param max_bytes Positive maximum input bytes checked before parsing. The
#'   default is 128 MiB; oversized snapshots raise `readboj_size_error`.
#' @param max_rows Positive whole-number maximum rows for `data_csv` and
#'   `metadata_csv`. The default is 50,000; it is ignored for `data_json`.
#' @return A base `data.frame` with `stringsAsFactors = FALSE`, row names reset,
#'   and a `readboj_provenance` attribute containing `source =
#'   "local response snapshot"`, the normalized `path`, `raw_sha256`,
#'   `semantic_sha256`, byte count, parser schema and package version. For
#'   `type = "data_json"` or `"data_csv"`, the exact columns, in order, are
#'   character `db`, `series_code`, `name_en`, `name_jp`, `unit_en`, `unit_jp`,
#'   `frequency`, `category_en`, `category_jp`; `Date` `last_update`; character
#'   `period`; `Date` `date`; numeric `value`; and character `raw_value` and
#'   `value_status`. `date` is inferred from the frequency/period pair and may
#'   be `NA`; JSON nulls use `value_status = "null"`, while CSV blank values use
#'   `value_status = "blank"`. For `type = "metadata_csv"`, the exact columns,
#'   in order, are character `db`, `series_code`, `name_jp`, `name_en`,
#'   `unit_jp`, `unit_en`, `frequency`, `category_jp`, `category_en`; integer
#'   `layer1`--`layer5`; character `start_time` and `end_time`; `Date`
#'   `last_update`; character `notes_jp` and `notes_en`; and logical
#'   `is_series`. The metadata parser always retains both language columns.
#'   `semantic_sha256` excludes the volatile JSON `DATE` field for JSON input,
#'   canonicalizes the decoded CSV `DATE` line for observation CSV input, and
#'   is `NA` for metadata CSV input; `raw_sha256` always covers the exact file
#'   bytes.
#'
#' @section Errors and side effects:
#' Missing paths, directories, invalid database/language values, oversized
#' inputs, known observation-status/schema/identity failures, and metadata row
#' limits are checked by the package and use typed `readboj_*_error` conditions
#' where applicable. Unsupported `type` values and some low-level malformed or
#' encoding/bound inputs may instead retain base-R or dependency errors and
#' warnings. The function only reads `path`; it does not perform network I/O,
#' create cache directories, or write files.
#'
#' @examples
#' json_path <- system.file("extdata", "api-data-page-1.json", package = "readboj")
#' json_data <- read_boj_snapshot(json_path, type = "data_json", db = "FM08")
#' json_data[c("series_code", "period", "value", "value_status")]
#'
#' csv_path <- system.file("extdata", "api-data-en-page-1.csv", package = "readboj")
#' csv_data <- read_boj_snapshot(csv_path, type = "data_csv", db = "FM08")
#' csv_data[c("series_code", "period", "value", "value_status")]
#'
#' metadata_path <- system.file(
#'   "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
#' )
#' metadata <- read_boj_snapshot(
#'   metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
#' )
#' metadata[c("series_code", "name_en", "name_jp", "is_series")]
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
