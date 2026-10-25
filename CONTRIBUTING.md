# Contributing to readboj

`readboj` is an R client for official Bank of Japan (BOJ) statistical
services. Version 0.2.0 is a pre-CRAN release. Contributions should preserve
the package's auditable request identity, bounded resource use, deterministic
offline path, and documented return contracts.

## Before reporting a problem or opening a pull request

Please email [chartwellmacro@gmail.com](mailto:chartwellmacro@gmail.com) before substantial changes. For a parser or normalisation problem, start with a packaged synthetic
fixture so that the report does not depend on a changing BOJ response:

```r
path <- system.file("extdata", "api-data-page-1.json", package = "readboj")
local_data <- read_boj_snapshot(path, type = "data_json", db = "FM08")
local_data[c("series_code", "period", "value", "value_status")]
```

The fixtures in `inst/extdata/` are deliberately synthetic; they are not
official BOJ observations. A live check is available only when it is useful
for a service-availability or current-schema report:

```sh
READBOJ_LIVE_TESTS=true Rscript -e 'testthat::test_local()'
```

Live requests depend on the current BOJ service and its current data. Do not
make the default test suite, examples, or a pull request depend on network
availability. Use a temporary `cache_dir` while developing and use
`offline = TRUE` or `read_boj_snapshot()` when a deterministic replay is
possible.

## Pull requests

Keep changes focused and explain the user-visible reason for them. In
particular:

- preserve exported signatures, defaults, output column order and types,
  `readboj_provenance`, typed error classes, cache bounds, and HTTPS/host
  restrictions unless a deliberately reviewed compatibility change is being
  proposed;
- add or update deterministic tests for changed parsing, identity, error, or
  resource-boundary behavior;
- keep examples and vignettes runnable without credentials or a live network;
- update roxygen source, generated reference pages, README/articles, and NEWS
  together when documentation or a public contract changes; and
- retain `inst/NOTICE/bojapi-MIT.txt`, official BOJ service credit, and any
  provenance or permission information when adapting third-party material.

Before submitting, run the focused tests you changed and the full local test
suite:

```sh
Rscript -e 'testthat::test_local()'
```

If documentation or package metadata is changed, also run the relevant
documentation build and `R CMD check` locally. Report the exact commands and
results; do not describe a live, platform-specific, or unavailable check as
passing.

## What to include in a report

Include the smallest reproducible example, the `readboj` version, R version,
operating system, and relevant `sessionInfo()`. For a returned object, include
the names, classes, dimensions, and a redacted summary from
`boj_provenance(x)`. For an error, include its condition class, message,
warnings, and (when present) the canonical URL/query, HTTP status, response
format/encoding, and raw SHA-256. Redact local paths, tokens, credentials,
personal data, and any unrelated private request content. Use the security
process for a suspected vulnerability rather than publishing exploit details
in an issue or pull request.

## License and provenance

Package code: MIT, copyright Chartwell Macro. That package licence does not reassign
rights in Bank of Japan data, publications, services, or other upstream
material. The package includes a preserved third-party MIT notice and uses
official BOJ services subject to their own credit and use terms. If a
contribution adapts external code, data, or text, record its source and
permission in the pull request and preserve the relevant notice. Do not add
real BOJ response payloads to fixtures; use small synthetic fixtures or a
documented, opt-in live canary.
