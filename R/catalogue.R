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

#' Build a portable, hash-pinned Bank of Japan metadata catalogue snapshot
#'
#' build_boj_catalogue_snapshot() retrieves the selected databases through the
#' official getMetadata CSV route, retains each exact response body, inventories
#' it in bounded chunks, and publishes a portable directory. The directory has
#' one content-addressed raw CSV under objects/ for each database, plus
#' manifest.rds and manifest.csv. The RDS manifest also records the schema
#' version, generation time, requested database order, and whether all 50
#' databases in [boj_databases()] were selected. The raw files are the source
#' material for [search_boj_catalogue_snapshot()], not observation data.
#'
#' The request cache is used for each metadata response. With offline = TRUE,
#' every response must already be available as a valid, unexpired cache entry;
#' no network request is made. Otherwise requests use HTTPS and the package's
#' official Bank of Japan host allowlist, bounded response sizes, retries, and a
#' shared deadline. The function does not require credentials and does not
#' silently download at package load time.
#'
#' The destination and its objects/ directory are created when needed. A
#' manifest is not replaced unless overwrite = TRUE; with overwrite enabled,
#' the two manifest files are atomically replaced, while content-addressed raw
#' objects are retained and are never replaced by bytes with a different
#' SHA-256. Existing unrelated files are not removed. If a later database fails,
#' files already copied to the destination may remain; an incomplete directory is
#' rejected by the reader rather than treated as a valid snapshot.
#'
#' @param path A non-empty character scalar naming the destination directory.
#'   The caller is responsible for choosing a writable, suitably sized location.
#' @param db A non-empty character vector of unique database identifiers. Values
#'   are upper-cased and must be present in [boj_databases()]; use
#'   boj_databases()$db to request the complete declared surface.
#' @param language Metadata language: "both" (default), "en", or "jp". The
#'   bilingual Japanese CSV is used for "both" and "jp".
#' @param cache_dir Request-cache directory. The default is
#'   tools::R_user_dir("readboj", "cache"), subject to the
#'   readboj.cache_dir option.
#' @param refresh Logical scalar; if TRUE, ignore a current cache entry and
#'   retrieve each response again (unless offline = TRUE, in which case a
#'   missing refreshed response fails).
#' @param offline Logical scalar; require valid cached responses and prohibit
#'   network access.
#' @param max_age Maximum accepted cache age in seconds; Inf permits any age.
#' @param timeout Per-request timeout in seconds.
#' @param retries Number of retries for transient transport or HTTP failures.
#' @param wait Seconds between requests and retry attempts.
#' @param max_bytes Maximum decompressed response size for each metadata CSV.
#' @param max_databases Maximum number of selected databases (default 50).
#' @param max_rows_per_db Maximum metadata rows scanned for one database.
#' @param max_total_bytes Maximum sum of raw CSV bytes copied to the snapshot.
#' @param overwrite Logical scalar controlling replacement of existing manifests.
#' @param deadline Optional absolute POSIXct/POSIXlt deadline shared by every
#'   request, retry, and inter-request wait. When NULL, a bounded deadline is
#'   derived from the request count and timeout. Parser inventory is bounded by
#'   the row and byte limits but does not poll this deadline.
#' @return A data frame with one row per requested database, in the order of
#'   db, and a readboj_provenance attribute. Columns are db, language,
#'   canonical_url, retrieved_at, api_date, raw_sha256, bytes, row_count,
#'   series_count, frequencies, start_time, end_time, dimensions,
#'   last_update_field, relative_file, and complete_within_database.
#'   Identifiers, URLs, dates, hashes, frequencies, paths, and field names are
#'   character; bytes is numeric, row and series counts are integer, and
#'   complete_within_database is logical. The provenance includes the manifest
#'   path and SHA-256, generation time, total bytes, parser schema, and whether
#'   the declared 50-database surface is complete. boj_provenance() returns that
#'   attribute.
#' @seealso [search_boj_catalogue_snapshot()], [boj_metadata()],
#'   [boj_databases()], [boj_cache_prune()]
#' @examples
#' # A build uses the official metadata service. This small live example is
#' # opt-in so package checks and offline documentation builds remain deterministic.
#' databases <- boj_databases()
#' stopifnot("FM08" %in% databases$db)
#' if (identical(Sys.getenv("READBOJ_LIVE_EXAMPLES"), "true")) {
#'   destination <- tempfile("readboj-catalogue-")
#'   manifest <- build_boj_catalogue_snapshot(
#'     destination, db = "FM08",
#'     cache_dir = file.path(tempdir(), "readboj-live-example-cache"),
#'     timeout = 10, retries = 1L, wait = 0, max_bytes = 8 * 1024^2,
#'     max_databases = 1L, max_rows_per_db = 10000L,
#'     max_total_bytes = 64 * 1024^2, deadline = Sys.time() + 60)
#'   stopifnot(nrow(manifest) == 1L)
#'   search_boj_catalogue_snapshot(destination, "rate", db = "FM08")
#' } else {
#'   message("Set READBOJ_LIVE_EXAMPLES=true to run this live example.")
#' }
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

#' Search a portable Bank of Japan catalogue snapshot fully offline
#'
#' search_boj_catalogue_snapshot() validates the manifest and SHA-256 identity
#' of every referenced raw CSV before scanning the selected files in chunks. It
#' performs no network access, does not consult the live catalogue, and retains
#' at most limit matching rows across all selected databases. Use
#' [build_boj_catalogue_snapshot()] to create the directory and keep the
#' directory together when moving or archiving it.
#'
#' query is a case-insensitive literal by default. With regex = TRUE, it is
#' interpreted as a Perl-compatible regular expression and searched across the
#' series code, names, categories, and notes in the requested language(s).
#' Group headings have an empty series_code; they are excluded unless
#' include_groups = TRUE. The function trusts only the manifest's selected
#' files, so a missing, symlinked, tampered, unsafe, or schema-invalid file is
#' rejected rather than silently skipped.
#'
#' @param snapshot_path A non-empty character scalar naming a directory created
#'   by [build_boj_catalogue_snapshot()]. It must contain the manifest and all
#'   referenced content-addressed objects.
#' @param query A non-empty character scalar containing literal search text or a
#'   regular expression when regex = TRUE.
#' @param db NULL to search every database in the snapshot, or a character
#'   vector of known database identifiers to search in that requested order.
#' @param language Search/output language: "both" (default), "en", or "jp".
#'   Language-specific output removes the other language's name, unit, category,
#'   and notes columns.
#' @param regex Logical scalar; interpret query as a Perl-compatible regular
#'   expression when TRUE, otherwise perform a case-insensitive literal match.
#' @param limit Maximum number of matching rows retained across all selected
#'   databases (default 100).
#' @param include_groups Logical scalar; include hierarchy rows without a series
#'   code when TRUE.
#' @return A data frame with zero or more matching metadata rows and a
#'   readboj_provenance attribute. With language = "both", columns are
#'   db, series_code, name_jp, name_en, unit_jp, unit_en, frequency,
#'   category_jp, category_en, layer1--layer5, start_time, end_time,
#'   last_update, notes_jp, notes_en, and is_series. The layer columns are
#'   integer, last_update is Date, is_series is logical, and text fields are
#'   character; language-specific calls omit the four columns for the other
#'   language. Rows retain source order within the selected databases and have
#'   ordinary NULL row names. Provenance records the normalized snapshot path,
#'   manifest SHA-256, source completeness flag, object hashes, query, result
#'   limit, and parser schema.
#' @seealso [build_boj_catalogue_snapshot()], [boj_metadata()],
#'   [boj_provenance()]
#' @examples
#' # Search a packaged synthetic UTF-8 metadata fixture without a network call.
#' fixture <- system.file("extdata", "metadata-bilingual-utf8.csv", package = "readboj")
#' snapshot_path <- tempfile("readboj-catalogue-")
#' object_dir <- file.path(snapshot_path, "objects")
#' dir.create(object_dir, recursive = TRUE)
#' object_hash <- digest::digest(file = fixture, algo = "sha256", serialize = FALSE)
#' object_file <- file.path(object_dir, paste0(object_hash, ".csv"))
#' file.copy(fixture, object_file)
#' manifest <- data.frame(
#'   db = "FM08", language = "en",
#'   canonical_url = paste0("https://www.stat-search.boj.or.jp/api/v1/getMetadata",
#'     "?db=FM08&format=csv&lang=en"),
#'   raw_sha256 = object_hash, bytes = unname(file.info(object_file)$size),
#'   relative_file = file.path("objects", basename(object_file)),
#'   complete_within_database = TRUE, stringsAsFactors = FALSE
#' )
#' saveRDS(list(schema_version = "1", generated_at = "fixture",
#'   declared_databases = "FM08", complete_declared_surface = FALSE,
#'   manifest = manifest), file.path(snapshot_path, "manifest.rds"), version = 3)
#' result <- search_boj_catalogue_snapshot(
#'   snapshot_path, "Synthetic monthly rate", db = "FM08", language = "en")
#' stopifnot(identical(result$series_code, "SYNTHM02"))
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
