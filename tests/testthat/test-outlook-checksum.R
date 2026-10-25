test_that("saved checksums retain all values across serialization options", {
  base <- outlook_saved_fixture()
  fields <- base
  fields$content_sha256 <- NULL
  golden <- "1933f6789e21b0428573cdb0ffa345e239385aa5355dddac34ade63991d9984c"
  for (version in c(2L, 3L)) {
    withr::local_options(serializeVersion = version)
    sealed <- readboj:::outlook_saved_seal(base)
    expect_identical(sealed$content_sha256, golden)
    actual <- sealed
    actual$content_sha256 <- NULL
    expect_identical(actual, fields)
    expect_identical(nrow(actual$data), 4142L)
    expect_identical(sum(is.na(actual$data$value)), 5L)
    expect_identical(nrow(actual$catalogue), 74L)
    expect_silent(readboj:::outlook_saved_validate(sealed))
    path <- tempfile(fileext = ".rds")
    withr::defer(unlink(path))
    saveRDS(sealed, path, version = 2)
    expect_identical(readRDS(path), sealed)
    expect_silent(readboj:::outlook_saved_validate(readRDS(path)))
    bad <- sealed
    bad$data$value[[1L]] <- bad$data$value[[1L]] + 1
    expect_error(readboj:::outlook_saved_validate(bad), class = "readboj_outlook_data_error")
    bad <- sealed
    attr(bad$data$value, "unexpected") <- TRUE
    expect_error(readboj:::outlook_saved_validate(bad), class = "readboj_outlook_data_error")
    bad <- sealed
    bad$data$source_sha256[[1L]] <- strrep("0", 64)
    expect_error(readboj:::outlook_saved_validate(bad), class = "readboj_outlook_data_error")
  }
})

test_that("legacy content checksums remain readable without trusting modified data", {
  legacy <- outlook_saved_fixture()
  legacy$content_sha256 <- NULL
  # Recreate the earlier format using digest directly, independently of the new helper.
  values <- numeric()
  for (i in seq_along(legacy$data$value)) values[[i]] <- legacy$data$value[[i]]
  legacy$data$value <- values
  legacy$content_sha256 <- digest::digest(legacy, algo = "sha256", serializeVersion = 2L)
  withr::local_options(serializeVersion = 3L)
  expect_silent(readboj:::outlook_saved_validate(legacy))
  legacy$data$value[[1L]] <- legacy$data$value[[1L]] + 1
  expect_error(readboj:::outlook_saved_validate(legacy), class = "readboj_outlook_data_error")
})

test_that("the original legacy bundle is preserved and falls back explicitly when needed", {
  fixture <- test_path("fixtures", "outlook-saved-v1.rds")
  legacy <- readRDS(fixture)
  expect_identical(legacy$content_sha256,
    "ad5ffa9e6a1e970f6e32c98e97436add3f1eacd9b7ad83763c5babbb7c6a2a49")
  fields <- legacy
  fields$content_sha256 <- NULL
  current <- outlook_saved_fixture()
  current$content_sha256 <- NULL
  expect_identical(fields, current)
  reproducible <- identical(legacy$content_sha256,
    digest::digest(fields, algo = "sha256", serializeVersion = 2L))
  directory <- tempfile("legacy-outlook-")
  dir.create(directory)
  withr::defer(unlink(directory, recursive = TRUE))
  dir.create(file.path(directory, "objects"))
  dir.create(file.path(directory, "commits"))
  hash <- digest::digest(file = fixture, algo = "sha256", serialize = FALSE)
  object <- file.path(directory, "objects", paste0(hash, ".rds"))
  file.copy(fixture, object)
  marker <- file.path(directory, "commits", paste0("000000000001-", hash, ".rds"))
  saveRDS(list(generation = 1, sha256 = hash), marker, version = 2)
  withr::local_options(serializeVersion = 3L)
  if (reproducible) {
    expect_silent(result <- read_boj_outlook("all", comparison = "all", data_dir = directory))
    expect_identical(boj_provenance(result)$saved$origin, "refreshed")
  } else {
    expect_warning(result <- read_boj_outlook("all", comparison = "all", data_dir = directory),
      class = "readboj_outlook_fallback_warning")
    expect_identical(boj_provenance(result)$saved$origin, "package")
  }
  attr(result, "readboj_provenance") <- NULL
  expect_identical(result, fields$data)
  expect_identical(digest::digest(file = object, algo = "sha256", serialize = FALSE), hash)
})

test_that("maintenance state survives serialization option changes", {
  state <- outlook_maintenance_fixture()
  withr::local_options(serializeVersion = 3L)
  first <- maintain_boj_outlook(state$directory)
  expect_identical(first$status, "idle")
  stored <- readboj:::outlook_maintenance_read(file.path(state$directory, "maintenance"))
  expect_s3_class(stored$next_due_at, "POSIXt")
  withr::local_options(serializeVersion = 2L)
  expect_identical(maintain_boj_outlook(state$directory)$next_due_at, first$next_due_at)
})
