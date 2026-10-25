test_that("database registry is complete, bilingual, and revisioned", {
  databases <- boj_databases()
  expect_equal(nrow(databases), 50L)
  expect_identical(anyDuplicated(databases$db), 0L)
  expect_true(all(c("IR01", "FM08", "MD14", "LA05", "BS01", "CO", "BP01", "BIS", "DER", "OT") %in% databases$db))
  expect_true(all(nzchar(databases$name_en)))
  expect_true(all(nzchar(databases$name_jp)))
  expect_identical(unique(databases$manual_revision), "2026-02-18")
  expect_match(boj_provenance(databases)$source_sha256, "^[0-9a-f]{64}$")
  expect_true(boj_provenance(databases)$complete_declared_surface)
})

test_that("credit exposes prescribed text and release contact", {
  credit <- boj_api_credit("en")
  expect_match(credit$credit, "Time-Series Data Search", fixed = TRUE)
  expect_identical(credit$service_release_contact, "post.rsd17@boj.or.jp")
  expect_match(credit$api_notice, "stat-search.boj.or.jp", fixed = TRUE)
})
