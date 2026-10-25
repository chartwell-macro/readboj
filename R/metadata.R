metadata_snapshot <- function(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline) {
  api_lang <- if (language == "en") "en" else "jp"
  entry <- fetch_snapshot(paste0(.readboj_api_base, "/getMetadata"),
    list(format = "csv", lang = api_lang, db = db), cache_dir = cache_dir,
    refresh = refresh, offline = offline, max_age = max_age,
    timeout = timeout, retries = retries, wait = wait, max_bytes = max_bytes,
    deadline = deadline)
  encoding <- if (api_lang == "jp") "CP932" else "UTF-8"
  decoded <- decode_complete_line_prefix(entry$path, encoding, 16384L)
  if (length(decoded) != 1L || is.na(decoded)) readboj_abort(
    sprintf("BOJ metadata is not valid %s text.", encoding), "readboj_schema_error")
  preamble <- strsplit(decoded, "\n", fixed = TRUE)[[1L]]
  preamble <- sub("\r$", "", utils::head(preamble, 5L))
  if (length(preamble) != 5L) readboj_abort(
    "BOJ metadata CSV has fewer than five preamble rows.", "readboj_schema_error")
  split <- strsplit(preamble, ",", fixed = TRUE)
  preamble_names <- vapply(split, function(x) x[[1L]] %||% "", character(1L))
  preamble_values <- vapply(split, function(x) paste(x[-1L], collapse = ","), character(1L))
  preamble <- stats::setNames(preamble_values, preamble_names)
  if (!all(c("STATUS", "MESSAGEID", "DATE") %in% names(preamble))) {
    readboj_abort("BOJ metadata CSV preamble is incomplete.", "readboj_schema_error")
  }
  if (!identical(unname(preamble[["STATUS"]]), "200")) {
    readboj_abort(sprintf("BOJ API error %s (%s).", preamble[["STATUS"]],
      preamble[["MESSAGEID"]]), "readboj_api_error",
      status = suppressWarnings(as.integer(preamble[["STATUS"]])),
      message_id = preamble[["MESSAGEID"]])
  }
  list(entry = entry, encoding = encoding, preamble = preamble)
}

filter_metadata_language <- function(data, language) {
  if (language == "both") return(data)
  if (language == "en") {
    data$name_jp <- data$unit_jp <- data$category_jp <- data$notes_jp <- NULL
  } else {
    data$name_en <- data$unit_en <- data$category_en <- data$notes_en <- NULL
  }
  data
}

#' Retrieve bilingual Bank of Japan series metadata
#'
#' Japanese metadata CSV is the canonical bilingual source because it carries
#' both `_J` and English fields. Eager materialisation of the very large Tankan
#' database is refused unless explicitly allowed; use [search_boj_series()] for
#' normal Tankan discovery.
#'
#' @inheritParams read_boj_series
#' @param language `"both"`, `"en"`, or `"jp"`.
#' @param max_rows Maximum materialised metadata rows.
#' @param allow_large Permit eager `CO` materialisation.
#' @param include_groups Include hierarchy heading rows without series codes.
#' @return A stable metadata data frame with provenance.
#' @export
boj_metadata <- function(db, language = "both", cache_dir = boj_cache_dir(),
    refresh = FALSE, offline = FALSE, max_age = 24 * 60 * 60,
    timeout = 60, retries = 3L, wait = 1, max_bytes = 128 * 1024^2,
    max_rows = 50000L, allow_large = FALSE, include_groups = TRUE,
    deadline = NULL) {
  db <- normalize_db(db)
  language <- normalize_language(language)
  allow_large <- scalar_flag(allow_large, "allow_large")
  include_groups <- scalar_flag(include_groups, "include_groups")
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  if (identical(db, "CO") && !allow_large) readboj_abort(
    "The Tankan metadata catalogue is large; use `search_boj_series()` or set `allow_large = TRUE` with an explicit row bound.",
    "readboj_size_error", db = db)
  snapshot <- metadata_snapshot(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline)
  out <- parse_metadata_csv(snapshot$entry$path, db, snapshot$encoding, max_rows)
  if (!include_groups) out <- out[out$is_series, , drop = FALSE]
  out <- filter_metadata_language(out, language)
  attach_provenance(out, c(snapshot_provenance(snapshot$entry), list(
    source = "Bank of Japan getMetadata CSV", db = db, language = language,
    transfer_encoding = snapshot$encoding, api_date = unname(snapshot$preamble[["DATE"]]),
    api_message_id = unname(snapshot$preamble[["MESSAGEID"]]))))
}

search_chunked_metadata <- function(path, db, encoding, query, regex, limit,
    include_groups, language) {
  state <- new.env(parent = emptyenv())
  state$matches <- list()
  state$count <- 0L
  callback <- readr::SideEffectChunkCallback$new(function(chunk, pos) {
    normalized <- standardize_metadata(as.data.frame(chunk), db)
    if (!include_groups) normalized <- normalized[normalized$is_series, , drop = FALSE]
    fields <- if (language == "en") c("series_code", "name_en", "category_en", "notes_en") else
      if (language == "jp") c("series_code", "name_jp", "category_jp", "notes_jp") else
        c("series_code", "name_en", "name_jp", "category_en", "category_jp", "notes_en", "notes_jp")
    haystack <- do.call(paste, c(lapply(normalized[fields], function(x) ifelse(is.na(x), "", x)), sep = "\r"))
    keep <- if (regex) grepl(query, haystack, ignore.case = TRUE, perl = TRUE) else
      grepl(tolower(query), tolower(haystack), fixed = TRUE)
    selected <- normalized[keep, , drop = FALSE]
    if (nrow(selected)) {
      available <- limit - state$count
      if (available > 0L) {
        selected <- utils::head(selected, available)
        state$matches[[length(state$matches) + 1L]] <- selected
        state$count <- state$count + nrow(selected)
      }
    }
    invisible(NULL)
  })
  readr::read_csv_chunked(path, callback = callback, chunk_size = 5000L, skip = 5L,
    locale = readr::locale(encoding = encoding),
    col_types = readr::cols(.default = readr::col_character()),
    na = character(), progress = FALSE, show_col_types = FALSE)
  if (!length(state$matches)) return(empty_metadata())
  out <- do.call(rbind, state$matches)
  rownames(out) <- NULL
  out
}

#' Search Bank of Japan metadata with bounded output
#'
#' The cached CSV is scanned in chunks, so the large Tankan catalogue is not
#' materialised as one in-memory object. At most `limit` matches are retained.
#'
#' @param query Literal text or regular expression.
#' @param regex Interpret `query` as a Perl-compatible regular expression.
#' @param limit Maximum result rows retained in memory.
#' @inheritParams boj_metadata
#' @return A bilingual metadata data frame with provenance.
#' @export
search_boj_series <- function(query, db, language = "both", regex = FALSE,
    limit = 100L, cache_dir = boj_cache_dir(), refresh = FALSE, offline = FALSE,
    max_age = 24 * 60 * 60, timeout = 60, retries = 3L, wait = 1,
    max_bytes = 128 * 1024^2, include_groups = FALSE, deadline = NULL) {
  query <- scalar_character(query, "query")
  db <- normalize_db(db)
  language <- normalize_language(language)
  regex <- scalar_flag(regex, "regex")
  limit <- scalar_number(limit, "limit", min = 1, integer = TRUE)
  include_groups <- scalar_flag(include_groups, "include_groups")
  deadline <- resolve_deadline(deadline, default_seconds = max(300, timeout * (retries + 1L) + 60))
  if (regex) tryCatch(grepl(query, "", perl = TRUE), error = function(e)
    readboj_abort(paste0("Invalid regular expression: ", conditionMessage(e)),
      "readboj_parameter_error"))
  snapshot <- metadata_snapshot(db, language, cache_dir, refresh, offline, max_age,
    timeout, retries, wait, max_bytes, deadline)
  out <- search_chunked_metadata(snapshot$entry$path, db, snapshot$encoding, query,
    regex, limit, include_groups, language)
  out <- filter_metadata_language(out, language)
  attach_provenance(out, c(snapshot_provenance(snapshot$entry), list(
    source = "Bank of Japan getMetadata CSV", db = db, language = language,
    query = query, result_limit = limit, scan = "chunked", transfer_encoding = snapshot$encoding,
    api_date = unname(snapshot$preamble[["DATE"]]),
    api_message_id = unname(snapshot$preamble[["MESSAGEID"]]))))
}
