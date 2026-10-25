metadata_inventory <- function(path, db, encoding, max_rows) {
  state <- new.env(parent = emptyenv())
  state$rows <- 0L
  state$series <- 0L
  state$frequencies <- character()
  state$start <- character()
  state$end <- character()
  callback <- readr::SideEffectChunkCallback$new(function(chunk, pos) {
    normalized <- standardize_metadata(as.data.frame(chunk), db)
    state$rows <- state$rows + nrow(normalized)
    if (state$rows > max_rows) readboj_abort(
      "Catalogue database exceeds the snapshot row bound.", "readboj_size_error",
      db = db, row_limit = max_rows)
    series <- normalized[normalized$is_series, , drop = FALSE]
    state$series <- state$series + nrow(series)
    state$frequencies <- union(state$frequencies,
      series$frequency[!is.na(series$frequency) & nzchar(series$frequency)])
    state$start <- c(state$start,
      series$start_time[!is.na(series$start_time) & nzchar(series$start_time)])
    state$end <- c(state$end,
      series$end_time[!is.na(series$end_time) & nzchar(series$end_time)])
    invisible(NULL)
  })
  readr::read_csv_chunked(path, callback = callback, chunk_size = 5000L, skip = 5L,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), progress = FALSE, show_col_types = FALSE)
  list(rows = state$rows, series = state$series,
    frequencies = paste(sort(state$frequencies), collapse = "|"),
    start_time = if (length(state$start)) min(state$start) else NA_character_,
    end_time = if (length(state$end)) max(state$end) else NA_character_)
}

validate_snapshot_db <- function(db) {
  if (!is.character(db) || !length(db) || anyNA(db)) readboj_abort(
    "`db` must explicitly select one or more database identifiers.",
    "readboj_parameter_error")
  db <- unique(toupper(db))
  unknown <- setdiff(db, boj_databases()$db)
  if (length(unknown)) readboj_abort(paste0("Unknown database identifiers: ",
    paste(unknown, collapse = ", "), "."), "readboj_parameter_error")
  db
}

write_atomic_rds <- function(object, path) {
  temporary <- tempfile("readboj-manifest-", tmpdir = dirname(path))
  saveRDS(object, temporary, version = 3)
  if (!file.rename(temporary, path)) {
    unlink(temporary)
    readboj_abort("Could not atomically publish the catalogue manifest.",
      "readboj_cache_error")
  }
  invisible(path)
}

#' Build a portable, hash-pinned BOJ metadata catalogue snapshot
#'
#' Each selected database is downloaded through the same exact metadata route,
#' retained as its official CSV response body, inventoried in chunks, and
#' pinned in atomic RDS and CSV manifests. Supplying all values from
#' [boj_databases()] creates a complete snapshot of the declared API catalogue.
#'
#' @param path Destination directory.
#' @param db Explicit database vector. Use `boj_databases()$db` for all 50.
#' @param overwrite Replace existing manifest files. Content-addressed objects
#'   are never overwritten with different bytes.
#' @param max_databases Maximum selected databases.
#' @param max_rows_per_db Maximum metadata rows scanned per database.
#' @param max_total_bytes Maximum total raw catalogue bytes copied.
#' @inheritParams boj_metadata
#' @return The pinned manifest data frame with snapshot provenance.
#' @export
build_boj_catalogue_snapshot <- function(path, db, language = "both",
    cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 60, retries = 3L, wait = 1,
    max_bytes = 128 * 1024^2, max_databases = 50L,
    max_rows_per_db = 250000L, max_total_bytes = 2 * 1024^3,
    overwrite = FALSE, deadline = NULL) {
  path <- scalar_character(path, "path")
  db <- validate_snapshot_db(db)
  language <- normalize_language(language)
  overwrite <- scalar_flag(overwrite, "overwrite")
  max_databases <- scalar_number(max_databases, "max_databases", min = 1, integer = TRUE)
  max_rows_per_db <- scalar_number(max_rows_per_db, "max_rows_per_db", min = 1, integer = TRUE)
  max_total_bytes <- scalar_number(max_total_bytes, "max_total_bytes", min = 1)
  if (length(db) > max_databases) readboj_abort("Selected database count exceeds `max_databases`.",
    "readboj_size_error", database_limit = max_databases)
  deadline <- resolve_deadline(deadline,
    default_seconds = max(1800, length(db) * (timeout + wait)))
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    readboj_abort("Could not create the catalogue snapshot directory.", "readboj_cache_error")
  }
  object_dir <- file.path(path, "objects")
  if (!dir.exists(object_dir)) dir.create(object_dir)
  manifest_rds <- file.path(path, "manifest.rds")
  manifest_csv <- file.path(path, "manifest.csv")
  if (!overwrite && (file.exists(manifest_rds) || file.exists(manifest_csv))) {
    readboj_abort("Catalogue manifest already exists; set `overwrite = TRUE` explicitly.",
      "readboj_config_error")
  }
  rows <- vector("list", length(db))
  total_bytes <- 0
  for (i in seq_along(db)) {
    if (i > 1L && wait > 0 && !offline) deadline_pause(wait, deadline)
    snapshot <- metadata_snapshot(db[[i]], language, cache_dir, refresh, offline,
      max_age, timeout, retries, wait, max_bytes, deadline)
    total_bytes <- total_bytes + snapshot$entry$bytes
    if (total_bytes > max_total_bytes) readboj_abort(
      "Catalogue snapshot exceeds `max_total_bytes`.", "readboj_size_error",
      byte_limit = max_total_bytes)
    inventory <- metadata_inventory(snapshot$entry$path, db[[i]], snapshot$encoding,
      max_rows_per_db)
    object_name <- paste0(snapshot$entry$raw_sha256, ".csv")
    destination <- file.path(object_dir, object_name)
    if (file.exists(destination) && !identical(sha256_file(destination),
        snapshot$entry$raw_sha256)) readboj_abort(
      "Existing catalogue object has the wrong SHA-256.",
      "readboj_cache_corruption_error", path = destination)
    if (!file.exists(destination) && !file.copy(snapshot$entry$path, destination,
        overwrite = FALSE)) readboj_abort("Could not copy a catalogue object.",
      "readboj_cache_error")
    rows[[i]] <- data.frame(
      db = db[[i]], language = language,
      canonical_url = snapshot$entry$canonical_url,
      retrieved_at = snapshot$entry$retrieved_at,
      api_date = unname(snapshot$preamble[["DATE"]]),
      raw_sha256 = snapshot$entry$raw_sha256,
      bytes = snapshot$entry$bytes, row_count = inventory$rows,
      series_count = inventory$series, frequencies = inventory$frequencies,
      start_time = inventory$start_time, end_time = inventory$end_time,
      dimensions = "LAYER1|LAYER2|LAYER3|LAYER4|LAYER5",
      last_update_field = "LAST_UPDATE", relative_file = file.path("objects", object_name),
      complete_within_database = TRUE, stringsAsFactors = FALSE
    )
  }
  manifest <- do.call(rbind, rows)
  manifest <- manifest[match(db, manifest$db), , drop = FALSE]
  generated_at <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  manifest_object <- list(schema_version = .readboj_schema_version,
    generated_at = generated_at, declared_databases = db,
    complete_declared_surface = setequal(db, boj_databases()$db), manifest = manifest)
  write_atomic_rds(manifest_object, manifest_rds)
  temporary_csv <- tempfile("readboj-manifest-", tmpdir = path)
  utils::write.csv(manifest, temporary_csv, row.names = FALSE, na = "")
  if (!file.rename(temporary_csv, manifest_csv)) {
    unlink(temporary_csv)
    readboj_abort("Could not atomically publish the catalogue CSV manifest.",
      "readboj_cache_error")
  }
  attach_provenance(manifest, list(
    source = "Bank of Japan getMetadata catalogue snapshot",
    generated_at = generated_at, snapshot_path = normalizePath(path),
    manifest_sha256 = sha256_file(manifest_rds),
    complete_declared_surface = manifest_object$complete_declared_surface,
    total_bytes = total_bytes, parser_schema = .readboj_schema_version))
}

read_catalogue_manifest <- function(path) {
  path <- scalar_character(path, "path")
  manifest_path <- file.path(path, "manifest.rds")
  if (!file.exists(manifest_path) || dir.exists(manifest_path) || path_is_link(manifest_path)) {
    readboj_abort("Catalogue manifest is missing or unsafe.",
      "readboj_cache_corruption_error")
  }
  object <- tryCatch(readRDS(manifest_path), error = function(e) readboj_abort(
    "Catalogue manifest is unreadable.", "readboj_cache_corruption_error", parent = e))
  required <- c("db", "language", "canonical_url", "raw_sha256", "bytes",
    "relative_file", "complete_within_database")
  if (!is.list(object) || !is.data.frame(object$manifest) ||
      !all(required %in% names(object$manifest))) readboj_abort(
    "Catalogue manifest schema is invalid.", "readboj_cache_corruption_error")
  manifest <- object$manifest
  if (any(!manifest$complete_within_database)) readboj_abort(
    "Catalogue manifest contains an incomplete database.", "readboj_identity_error")
  for (i in seq_len(nrow(manifest))) {
    validate_official_url(manifest$canonical_url[[i]])
    relative <- manifest$relative_file[[i]]
    if (startsWith(relative, "/") || grepl("(^|/)\\.\\.(/|$)", relative)) readboj_abort(
      "Catalogue manifest contains an unsafe object path.",
      "readboj_cache_corruption_error")
    object_path <- file.path(path, relative)
    if (!file.exists(object_path) || dir.exists(object_path) || path_is_link(object_path) ||
        !identical(sha256_file(object_path), manifest$raw_sha256[[i]])) readboj_abort(
      "Catalogue object identity does not match its manifest.",
      "readboj_cache_corruption_error", db = manifest$db[[i]])
  }
  list(header = object, manifest = manifest, path = normalizePath(path),
    manifest_path = manifest_path)
}

#' Search a portable BOJ catalogue snapshot fully offline
#'
#' @param snapshot_path Directory created by [build_boj_catalogue_snapshot()].
#' @param query Literal or regular-expression query.
#' @param db Optional subset of pinned database identifiers.
#' @param language Search/output language.
#' @param regex Interpret `query` as a regular expression.
#' @param limit Maximum retained results across all selected databases.
#' @param include_groups Include hierarchy headings without series codes.
#' @return Bilingual metadata rows with manifest and object hashes.
#' @export
search_boj_catalogue_snapshot <- function(snapshot_path, query, db = NULL,
    language = "both", regex = FALSE, limit = 100L, include_groups = FALSE) {
  snapshot <- read_catalogue_manifest(snapshot_path)
  query <- scalar_character(query, "query")
  language <- normalize_language(language)
  regex <- scalar_flag(regex, "regex")
  limit <- scalar_number(limit, "limit", min = 1, integer = TRUE)
  include_groups <- scalar_flag(include_groups, "include_groups")
  manifest <- snapshot$manifest
  if (!is.null(db)) {
    db <- validate_snapshot_db(db)
    absent <- setdiff(db, manifest$db)
    if (length(absent)) readboj_abort("Requested database is absent from this snapshot.",
      "readboj_identity_error", absent_databases = absent)
    manifest <- manifest[match(db, manifest$db), , drop = FALSE]
  }
  results <- list()
  retained <- 0L
  for (i in seq_len(nrow(manifest))) {
    if (retained >= limit) break
    encoding <- if (manifest$language[[i]] == "en") "UTF-8" else "CP932"
    data <- search_chunked_metadata(file.path(snapshot$path,
      manifest$relative_file[[i]]), manifest$db[[i]], encoding, query, regex,
      limit - retained, include_groups, language)
    if (nrow(data)) {
      results[[length(results) + 1L]] <- data
      retained <- retained + nrow(data)
    }
  }
  out <- if (length(results)) do.call(rbind, results) else empty_metadata()
  out <- filter_metadata_language(out, language)
  rownames(out) <- NULL
  attach_provenance(out, list(source = "offline pinned BOJ catalogue snapshot",
    snapshot_path = snapshot$path, manifest_sha256 = sha256_file(snapshot$manifest_path),
    generated_at = snapshot$header$generated_at,
    complete_declared_surface = snapshot$header$complete_declared_surface,
    object_sha256 = stats::setNames(manifest$raw_sha256, manifest$db),
    query = query, result_limit = limit, parser_schema = .readboj_schema_version))
}

