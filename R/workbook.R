#' Read a bounded official BOJ XLS/XLSX workbook
#'
#' Sheets are returned as text-valued tables so official identifiers, labels,
#' units and suppression markers are not numerically coerced. The exact source
#' workbook remains identified by SHA-256 provenance. This is a structural
#' workbook reader; it does not infer a time-series schema from presentation
#' tables or silently join survey breaks.
#'
#' @param path Local official workbook path or `boj_file`.
#' @param sheets Optional exact sheet names; defaults to all sheets.
#' @param max_sheets Maximum workbook sheets.
#' @param max_rows_per_sheet Maximum rows read from one sheet.
#' @param max_columns Maximum columns in one sheet.
#' @param max_cells Maximum cells retained across all sheets.
#' @return A named list of text-valued data frames with source provenance.
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
