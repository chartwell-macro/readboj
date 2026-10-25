#' Read a bounded official BOJ XLS/XLSX workbook
#'
#' Reads one or more sheets from a local Bank of Japan (BOJ) Excel workbook as
#' text-valued tables. Keeping every cell as text preserves official
#' identifiers, labels, units, and suppression markers. The exact source
#' workbook remains identified by SHA-256 provenance. This is a structural
#' reader: it does not infer a time-series schema from presentation tables,
#' evaluate a publication's definitions, or silently join survey breaks.
#'
#' @param path A local regular `.xls`/`.xlsx` workbook path, or the length-one
#'   `boj_file` returned by [download_boj_tankan_asset()]. The file is opened
#'   locally; this function does not download it or search the readboj cache.
#' @param sheets Optional non-empty character vector of unique exact sheet
#'   names. The default `NULL` reads every sheet in workbook order. Requested
#'   names must exist; no partial or fuzzy matching is performed.
#' @param max_sheets Positive integer maximum number of sheets in the workbook.
#'   The default is `100L`.
#' @param max_rows_per_sheet Positive integer maximum rows read from each
#'   selected sheet. The default is `200000L`; one extra row is read to detect
#'   an over-limit sheet.
#' @param max_columns Positive integer maximum columns in each selected sheet.
#'   The default is `1000L`.
#' @param max_cells Positive integer maximum aggregate cells retained across
#'   selected sheets. The default is `5000000L`.
#'
#' @return A named base `list`, with one element per selected sheet in `sheets`
#'   order (or workbook order from `readxl::excel_sheets()` when `sheets` is
#'   `NULL`). Each element is a base `data.frame` whose column names are
#'   repaired to be unique by readxl and whose cells are character values or
#'   `NA_character_`; no numeric or date conversion is performed. The list has
#'   a `readboj_provenance()`
#'   attribute containing the source path/hash and byte count (or the
#'   downloaded response provenance), parser/schema and package versions,
#'   selected sheet names, and aggregate `cells` count.
#'
#' @details The workbook is inspected with `readxl` using `col_types = "text"`.
#' Sheet count is checked before reading, and row, column, and aggregate-cell
#' bounds are checked while reading. Formula results, merged-cell layout,
#' formatting, hidden sheets, and workbook-specific semantic conventions are
#' not normalised into a BOJ time-series schema; use the returned raw tables
#' and the publication documentation to interpret them.
#'
#' Reading is local and has no network or cache side effect. `readxl` may use
#' temporary resources internally, but readboj does not write to the home or a
#' global workspace. A missing/non-regular path, unreadable or malformed
#' workbook, absent/duplicated sheet selection, or any sheet/cell bound
#' violation produces a typed readboj error (`readboj_parameter_error`,
#' `readboj_archive_error`, `readboj_identity_error`, or
#' `readboj_size_error`).
#'
#' @seealso [download_boj_tankan_asset()], [list_boj_tankan_assets()],
#'   [read_boj_bulk()], [boj_provenance()]
#' @examples
#' if (requireNamespace("writexl", quietly = TRUE)) {
#'   local({
#'     workbook <- tempfile(fileext = ".xlsx")
#'     on.exit(unlink(workbook), add = TRUE)
#'     writexl::write_xlsx(list(catalogue = data.frame(
#'       series_code = c("SYNTHM01", "SYNTHM02"),
#'       marker = c("ND", "NA"),
#'       stringsAsFactors = FALSE
#'     )), workbook)
#'     tables <- read_boj_workbook(workbook, max_rows_per_sheet = 10L,
#'       max_columns = 5L, max_cells = 50L)
#'     tables$catalogue[c("series_code", "marker")]
#'   })
#' }
#' @export
read_boj_workbook <- function(path, sheets = NULL, max_sheets = 100L,
    max_rows_per_sheet = 200000L, max_columns = 1000L,
    max_cells = 5000000L) {
  provenance <- boj_provenance(path)
  path <- scalar_character(as.character(path), "path")
  if (!file.exists(path) || dir.exists(path)) readboj_abort(
    "`path` is not a regular workbook file.", "readboj_parameter_error")
  max_sheets <- scalar_number(max_sheets, "max_sheets", min = 1, integer = TRUE)
  max_rows_per_sheet <- scalar_number(max_rows_per_sheet, "max_rows_per_sheet",
    min = 1, integer = TRUE)
  max_columns <- scalar_number(max_columns, "max_columns", min = 1, integer = TRUE)
  max_cells <- scalar_number(max_cells, "max_cells", min = 1, integer = TRUE)
  available <- tryCatch(readxl::excel_sheets(path), error = function(e) readboj_abort(
    paste0("Official workbook cannot be opened: ", conditionMessage(e)),
    "readboj_archive_error", parent = e))
  if (length(available) > max_sheets) readboj_abort(
    "Workbook sheet count exceeds the safety bound.", "readboj_size_error",
    sheet_limit = max_sheets)
  if (is.null(sheets)) sheets <- available else {
    if (!is.character(sheets) || !length(sheets) || anyNA(sheets) || anyDuplicated(sheets)) {
      readboj_abort("`sheets` must be unique exact sheet names.", "readboj_parameter_error")
    }
    absent <- setdiff(sheets, available)
    if (length(absent)) readboj_abort("Requested workbook sheet is absent.",
      "readboj_identity_error", absent_sheets = absent)
  }
  result <- vector("list", length(sheets)); names(result) <- sheets
  cells <- 0
  for (i in seq_along(sheets)) {
    table <- readxl::read_excel(path, sheet = sheets[[i]], col_types = "text",
      n_max = max_rows_per_sheet + 1L, .name_repair = "unique")
    if (nrow(table) > max_rows_per_sheet) readboj_abort(
      "Workbook sheet exceeds the row bound.", "readboj_size_error",
      sheet = sheets[[i]], row_limit = max_rows_per_sheet)
    if (ncol(table) > max_columns) readboj_abort(
      "Workbook sheet exceeds the column bound.", "readboj_size_error",
      sheet = sheets[[i]], column_limit = max_columns)
    cells <- cells + nrow(table) * ncol(table)
    if (cells > max_cells) readboj_abort(
      "Workbook exceeds the aggregate cell bound.", "readboj_size_error",
      cell_limit = max_cells)
    result[[i]] <- as.data.frame(table, stringsAsFactors = FALSE)
  }
  source_provenance <- provenance %||% list(
    source = "local official BOJ workbook", path = normalizePath(path),
    raw_sha256 = sha256_file(path), bytes = unname(file.info(path)$size))
  attach_provenance(result, c(source_provenance, list(
    parser = "read_boj_workbook/text", parser_schema = .readboj_schema_version,
    package_version = readboj_package_version(), sheets = sheets, cells = cells)))
}
