fixture_path <- function(name) {
  installed <- system.file("extdata", name, package = "readboj")
  if (nzchar(installed)) installed else
    testthat::test_path("..", "..", "inst", "extdata", name)
}

fixture_entry <- function(path, url = "https://www.stat-search.boj.or.jp/api/v1/synthetic") {
  list(
    canonical_url = url,
    final_url = url,
    retrieved_at = "2026-08-02 00:00:00 UTC",
    raw_sha256 = digest::digest(file = path, algo = "sha256", serialize = FALSE),
    bytes = unname(file.info(path)$size), http_status = 200L,
    response_headers = list(`content-type` = "application/json"),
    source_date = "Sat, 01 Aug 2026 15:00:00 GMT", path = path,
    cache_status = "fixture"
  )
}

write_synthetic_response <- function(path, next_position = NULL, code = "SYNTHM01",
    values = list(1, NULL, 3)) {
  payload <- list(
    STATUS = 200L, MESSAGEID = "M181000I", MESSAGE = "Synthetic success",
    DATE = "2026-08-02T00:00:00+09:00", NEXTPOSITION = next_position,
    RESULTSET = list(list(
      SERIES_CODE = code, NAME_OF_TIME_SERIES = "Synthetic",
      UNIT = "Index", FREQUENCY = "MONTHLY", CATEGORY = "Synthetic",
      LAST_UPDATE = "20260801",
      VALUES = list(SURVEY_DATES = c("202601", "202602", "202603"), VALUES = values)
    ))
  )
  writeLines(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null"), path,
    useBytes = TRUE)
  path
}
