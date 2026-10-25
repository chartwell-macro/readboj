documentation_rd_text <- function(x) {
  if (is.list(x)) {
    return(paste(vapply(x, documentation_rd_text, character(1)), collapse = ""))
  }
  paste(as.character(x), collapse = "")
}

documentation_aliases <- function(rd) {
  aliases <- tools:::.Rd_get_section(rd, "alias")
  if (!length(aliases)) {
    return(character())
  }
  vapply(aliases, documentation_rd_text, character(1))
}

documentation_source_root <- function() {
  candidates <- unique(c(
    testthat::test_path("..", ".."),
    getwd(),
    dirname(testthat::test_path("..", ".."))
  ))
  candidates <- normalizePath(candidates, mustWork = FALSE)
  candidates[vapply(
    candidates,
    function(path) {
      file.exists(file.path(path, "DESCRIPTION")) &&
        dir.exists(file.path(path, "inst", "extdata"))
    },
    logical(1)
  )][1L]
}

documentation_rd_database <- function() {
  source_root <- documentation_source_root()
  if (length(source_root) == 1L && !is.na(source_root) && nzchar(source_root)) {
    rd_files <- list.files(
      file.path(source_root, "man"),
      pattern = "[.]Rd$",
      full.names = TRUE
    )
    if (length(rd_files)) {
      return(stats::setNames(lapply(rd_files, tools::parse_Rd), basename(rd_files)))
    }
  }
  tools::Rd_db("readboj")
}

documentation_fixture_references <- function(text) {
  extract_group <- function(pattern) {
    matches <- gregexec(pattern, text, perl = TRUE)[[1L]]
    if (!length(matches) || nrow(matches) < 2L) {
      return(character())
    }
    as.character(regmatches(text, list(matches))[[1L]][2L, ])
  }

  unique(c(
    extract_group(
      "system\\.file\\(\\s*[\"']extdata[\"']\\s*,\\s*[\"']([^\"']+)[\"']"
    ),
    extract_group(
      "fixture_file\\(\\s*[\"']([^\"']+)[\"']\\s*\\)"
    ),
    extract_group(
      "file\\.path\\(\\s*[\"']inst[\"']\\s*,\\s*[\"']extdata[\"']\\s*,\\s*[\"']([^\"']+)[\"']"
    )
  ))
}

test_that("every exported function has a documented help alias and example", {
  rd_db <- documentation_rd_database()
  aliases <- unique(unlist(lapply(rd_db, documentation_aliases), use.names = FALSE))
  exported <- getNamespaceExports("readboj")

  missing_aliases <- setdiff(exported, aliases)
  expect_true(
    length(missing_aliases) == 0L,
    info = paste(
      "Exports without an Rd alias:",
      paste(missing_aliases, collapse = ", ")
    )
  )

  has_examples <- vapply(rd_db, function(rd) {
    examples <- tools:::.Rd_get_section(rd, "examples")
    length(examples) > 0L && nzchar(trimws(documentation_rd_text(examples)))
  }, logical(1))
  missing_examples <- exported[!vapply(exported, function(name) {
    any(vapply(rd_db, function(rd) {
      name %in% documentation_aliases(rd)
    }, logical(1)) & has_examples)
  }, logical(1))]

  expect_true(
    length(missing_examples) == 0L,
    info = paste(
      "Exports without a nonempty examples section:",
      paste(missing_examples, collapse = ", ")
    )
  )
})

test_that("the package help topic is present", {
  rd_db <- documentation_rd_database()
  package_topic <- any(vapply(
    rd_db,
    function(rd) any(documentation_aliases(rd) %in% c("readboj-package", "readboj")),
    logical(1)
  ))
  expect_true(package_topic)
})

test_that("documentation fixture references are bundled", {
  fixture_dir <- system.file("extdata", package = "readboj")
  if (!nzchar(fixture_dir)) {
    fixture_dir <- testthat::test_path("..", "..", "inst", "extdata")
  }
  expect_true(nzchar(fixture_dir))
  expect_true(dir.exists(fixture_dir))

  source_root <- documentation_source_root()
  source_docs <- character()
  if (length(source_root) == 1L && !is.na(source_root) && nzchar(source_root)) {
    source_docs <- c(
      file.path(source_root, c("README.Rmd", "README.md")),
      list.files(
        file.path(source_root, "vignettes"),
        pattern = "\\.(Rmd|Rnw|md)$",
        full.names = TRUE
      )
    )
    source_docs <- source_docs[file.exists(source_docs)]
  }

  fixture_inventory <- c(
    "api-data-en-page-1.csv",
    "api-data-en-page-2.csv",
    "api-data-jp-cp932.csv",
    "api-data-jp-utf8.csv",
    "api-data-page-1.json",
    "api-data-page-2.json",
    "bulk-catalogue.html",
    "metadata-bilingual-cp932.csv",
    "metadata-bilingual-utf8.csv",
    "tankan-range.html",
    "tankan-release.html",
    "tankan-root.html"
  )
  references <- fixture_inventory
  if (length(source_docs)) {
    documentation <- paste(
      vapply(
        source_docs,
        function(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
        character(1)
      ),
      collapse = "\n"
    )
    references <- documentation_fixture_references(documentation)
    if (!length(references)) {
      references <- fixture_inventory
    }
  }

  missing <- references[!file.exists(file.path(fixture_dir, references))]
  expect_true(
    length(missing) == 0L,
    info = paste("Documentation references missing fixtures:", paste(missing, collapse = ", "))
  )
})

test_that("the rendered chart and its source notice are bundled", {
  source_root <- documentation_source_root()
  chart_candidates <- c(
    system.file(
      "help", "figures", "readboj-fxerm07-2025.png",
      package = "readboj"
    ),
    if (length(source_root) == 1L && !is.na(source_root) && nzchar(source_root)) {
      file.path(source_root, "man", "figures", "readboj-fxerm07-2025.png")
    }
  )
  chart <- chart_candidates[nzchar(chart_candidates) & file.exists(chart_candidates)][1L]
  expect_true(length(chart) == 1L && !is.na(chart))
  expect_identical(
    digest::digest(file = chart, algo = "sha256"),
    "1cefa043fe7d8bb543f0d514f3f2418457f0d7a28f917cfbf9d48cae05843818"
  )

  notice_candidates <- c(
    system.file("NOTICE", "boj-chart-source.txt", package = "readboj"),
    if (length(source_root) == 1L && !is.na(source_root) && nzchar(source_root)) {
      file.path(source_root, "inst", "NOTICE", "boj-chart-source.txt")
    }
  )
  notice <- notice_candidates[nzchar(notice_candidates) & file.exists(notice_candidates)][1L]
  expect_true(length(notice) == 1L && !is.na(notice))
  notice_text <- paste(readLines(notice, warn = FALSE), collapse = "\n")
  expect_match(notice_text, "FM08", fixed = TRUE)
  expect_match(notice_text, "FXERM07", fixed = TRUE)
  expect_match(
    notice_text,
    "1cefa043fe7d8bb543f0d514f3f2418457f0d7a28f917cfbf9d48cae05843818",
    fixed = TRUE
  )
})
