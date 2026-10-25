boj_cache_dir <- function(cache_dir = getOption(
    "readboj.cache_dir", tools::R_user_dir("readboj", "cache"))) {
  scalar_character(cache_dir, "cache_dir")
}

ensure_cache_dir <- function(cache_dir) {
  for (part in c(cache_dir, file.path(cache_dir, "objects"), file.path(cache_dir, "requests"))) {
    if (!dir.exists(part) && !dir.create(part, recursive = TRUE, showWarnings = FALSE)) {
      readboj_abort(sprintf("Could not create cache directory %s.", part), "readboj_cache_error")
    }
  }
  invisible(cache_dir)
}

cache_request_key <- function(canonical_url) {
  digest::digest(charToRaw(enc2utf8(canonical_url)), algo = "sha256", serialize = FALSE)
}

cache_index_path <- function(cache_dir, key) file.path(cache_dir, "requests", paste0(key, ".rds"))
cache_object_path <- function(cache_dir, hash) file.path(cache_dir, "objects", paste0(hash, ".raw"))

path_is_link <- function(path) {
  link <- Sys.readlink(path)
  length(link) == 1L && !is.na(link) && nzchar(link)
}

read_cache_entry <- function(cache_dir, canonical_url, max_age = Inf) {
  key <- cache_request_key(canonical_url)
  index <- cache_index_path(cache_dir, key)
  if (!file.exists(index) && !path_is_link(index)) return(NULL)
  if (dir.exists(index) || path_is_link(index)) readboj_abort(
    "Cache index is not a regular in-cache file.", "readboj_cache_corruption_error",
    cache_index = index)
  entry <- tryCatch(readRDS(index), error = function(e) readboj_abort(
    paste0("Cache index is unreadable: ", conditionMessage(e)),
    "readboj_cache_corruption_error", parent = e, cache_index = index))
  if (!is.list(entry) || !is.character(entry$raw_sha256) ||
      length(entry$raw_sha256) != 1L || !grepl("^[0-9a-f]{64}$", entry$raw_sha256)) {
    readboj_abort("Cache index schema is invalid.", "readboj_cache_corruption_error",
      cache_index = index)
  }
  if (!identical(entry$canonical_url, canonical_url)) readboj_abort(
    "Cache query identity does not match its request index.", "readboj_identity_error",
    expected_url = canonical_url, cached_url = entry$canonical_url)
  path <- cache_object_path(cache_dir, entry$raw_sha256)
  if (!file.exists(path) || dir.exists(path) || path_is_link(path)) readboj_abort(
    "Cache object is missing or is not a regular in-cache file.",
    "readboj_cache_corruption_error", cache_object = path)
  actual_hash <- sha256_file(path)
  if (!identical(actual_hash, entry$raw_sha256)) readboj_abort(
    "Cache object SHA-256 does not match its index.", "readboj_cache_corruption_error",
    expected_sha256 = entry$raw_sha256, actual_sha256 = actual_hash)
  age <- as.numeric(difftime(Sys.time(), as.POSIXct(entry$retrieved_at, tz = "UTC"), units = "secs"))
  if (is.finite(max_age) && (is.na(age) || age > max_age)) return(NULL)
  entry$path <- path
  entry$cache_status <- "hit"
  entry
}

write_cache_entry <- function(cache_dir, entry, source_path) {
  ensure_cache_dir(cache_dir)
  object <- cache_object_path(cache_dir, entry$raw_sha256)
  if (path_is_link(object)) {
    readboj_abort("Refusing to write through a cache-object symbolic link.", "readboj_cache_error")
  }
  if (!file.exists(object)) {
    if (!file.rename(source_path, object)) {
      if (!file.copy(source_path, object, overwrite = FALSE)) {
        readboj_abort("Could not persist the response snapshot.", "readboj_cache_error")
      }
      unlink(source_path)
    }
  } else {
    unlink(source_path)
  }
  index <- cache_index_path(cache_dir, cache_request_key(entry$canonical_url))
  if (path_is_link(index)) {
    readboj_abort("Refusing to replace a cache-index symbolic link.", "readboj_cache_error")
  }
  temporary <- tempfile("readboj-index-", tmpdir = dirname(index))
  saveRDS(entry, temporary, version = 3)
  if (!file.rename(temporary, index)) {
    unlink(temporary)
    readboj_abort("Could not atomically publish the cache index.", "readboj_cache_error")
  }
  entry$path <- object
  entry$cache_status <- "miss"
  entry
}

cache_bounds <- function() {
  bytes <- getOption("readboj.cache_max_bytes", 2 * 1024^3)
  entries <- getOption("readboj.cache_max_entries", 1000L)
  list(
    bytes = scalar_number(bytes, "readboj.cache_max_bytes", min = 1),
    entries = scalar_number(entries, "readboj.cache_max_entries", min = 1, integer = TRUE)
  )
}

prune_cache_objects <- function(cache_dir, max_bytes, max_entries, protected_hash = character()) {
  object_dir <- file.path(cache_dir, "objects")
  files <- list.files(object_dir, pattern = "^[0-9a-f]{64}\\.raw$", full.names = TRUE)
  files <- files[file.exists(files) & !dir.exists(files) & !vapply(files, path_is_link, logical(1L))]
  info <- file.info(files)
  order_old <- order(info$mtime, decreasing = FALSE)
  files <- files[order_old]
  sizes <- info$size[order_old]
  hashes <- sub("\\.raw$", "", basename(files))
  remove <- logical(length(files))
  while (sum(!remove) > max_entries || sum(sizes[!remove], na.rm = TRUE) > max_bytes) {
    candidate <- which(!remove & !hashes %in% protected_hash)[1L]
    if (is.na(candidate)) {
      readboj_abort("The protected cache object alone exceeds configured cache bounds.",
        "readboj_cache_error", cache_max_bytes = max_bytes,
        cache_max_entries = max_entries)
    }
    remove[candidate] <- TRUE
  }
  removed_hash <- hashes[remove]
  bytes_removed <- sum(sizes[remove], na.rm = TRUE)
  if (any(remove)) unlink(files[remove], force = FALSE)
  indexes <- list.files(file.path(cache_dir, "requests"), pattern = "\\.rds$", full.names = TRUE)
  for (index in indexes) {
    if (dir.exists(index) || path_is_link(index)) next
    entry <- tryCatch(readRDS(index), error = function(e) NULL)
    if (is.list(entry) && entry$raw_sha256 %in% removed_hash) unlink(index)
  }
  data.frame(removed = sum(remove), bytes_removed = bytes_removed,
    remaining = sum(!remove), remaining_bytes = sum(sizes[!remove], na.rm = TRUE))
}

#' Prune the readboj cache to explicit bounds
#'
#' Only regular content-addressed objects and their readboj request indexes are
#' removed. Directories and unrelated files are left untouched.
#'
#' @param cache_dir Cache directory.
#' @param max_bytes Maximum retained raw-object bytes.
#' @param max_entries Maximum retained raw-object count.
#' @return A summary data frame.
#' @export
boj_cache_prune <- function(cache_dir = boj_cache_dir(), max_bytes = 1024^3,
    max_entries = 1000L) {
  max_bytes <- scalar_number(max_bytes, "max_bytes", min = 0)
  max_entries <- scalar_number(max_entries, "max_entries", min = 0, integer = TRUE)
  if (!dir.exists(cache_dir)) return(data.frame(removed = 0L, bytes_removed = 0,
    remaining = 0L, remaining_bytes = 0))
  prune_cache_objects(cache_dir, max_bytes, max_entries)
}
