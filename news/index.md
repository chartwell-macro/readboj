# Changelog

## readboj 0.2.0

- Adds calendar-aware
  [`maintain_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/maintain_boj_outlook.md),
  official Outlook/holiday discovery, local maintenance status and
  installed `--maintenance` mode. Persists separate Bank’s
  View/full-text stages, UTC next-due times, catch-up/retry state and
  cheap metadata probes. Calendar outages preserve prior evidence
  without blocking independently due data updates; ordinary reads remain
  saved-only.
- Makes ordinary
  [`list_boj_outlook_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_outlook_releases.md)
  and
  [`read_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_outlook.md)
  calls read memoized saved numeric data with no network, raw PDF reads
  or extractor. Bundles all 74 verified editions (4,142 rows, five NA
  markers). General source discovery/parsing remains explicit through
  the corresponding `_raw()` functions.
- Adds
  [`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md),
  local freshness/status and a full bundle builder. Checks every linked
  source for new editions, changed links and historical revisions;
  validates complete candidates before atomic publication. Readers
  consume refreshed user data while the package baseline stays
  read-only. Adds writer exclusion, last-good fallback, daily
  throttling, bounded raw staging cleanup and installed/repository daily
  scheduling entrypoints.
- Rejects revised tables that lose existing scalar identities/targets by
  default; reviewed coverage-loss opt-in records removed identities and
  retains old rows. Makes failed-throttled daily runs exit nonzero, with
  quiet repeated watch failures and explicit recovery reporting.
- Derives measure definitions, fiscal horizons, statistics, comparator
  vintages, actuals and conditional point estimates from source
  tables/notes. Preserves WPI/CGPI, tax/education-adjusted CPI, shared
  cells, separate all-member ranges and the pandemic member-interval
  construction without inventing medians.
- Retains bounded raw caching, offline replay, source pins and optional
  Poppler extraction under one deadline. Adds HTML XPath/PDF bounding
  boxes, source publication metadata and per-edition receipts. No
  runtime R dependency is added.
- Verifies all 74 archive editions and retains the original 167-cell
  regression, held-out full-table checks and
  format-transition/semantic/failure tests.

## readboj 0.1.1

- Fixes bounded Shift-JIS/CP932 response validation so a byte limit that
  lands inside a multibyte character is trimmed to the preceding
  complete line.
- Adds deterministic split-character coverage and a live IR02 bilingual
  metadata canary.
- Expands the user-facing documentation, reference articles, vignettes,
  package metadata, pkgdown configuration, and contributor/support
  guidance for a deterministic pre-CRAN workflow.
- Adds a prominent retrieve-select-chart workflow for the official
  `FM08/FXERM07` series, with a provenance-recorded rendered figure and
  an offline documentation path.
- Standardizes the package author, maintainer, citation, and
  copyright-holder display to `Chartwell Macro`.
- Adds CRAN-readiness checks and release documentation. These
  documentation and release-engineering changes do not alter exported
  signatures, defaults, output schemas/classes/attributes, cache
  behavior, endpoints, or provider behavior; the CP932 response-boundary
  fix above is the only runtime correction recorded for 0.1.1.

## readboj 0.1.0

- Adds bounded, paginated retrieval from all three official Bank of
  Japan Time-Series Data Search API operations.
- Adds exact raw-response snapshots, SHA-256 provenance, cache/offline
  replay, a semantic API hash that excludes only the volatile response
  `DATE`, and automatic total cache bounds.
- Adds stable English/Japanese metadata fields and streamed,
  result-bounded search suitable for the large Tankan catalogue.
- Adds portable atomic catalogue snapshots with complete per-database
  counts, source URL/hash pins and fully offline bounded search.
- Adds official bulk-file and dated Tankan release-asset
  discovery/download.
- Adds bounded text-preserving XLS/XLSX parsing for official catalogues
  and Tankan workbooks.
- Supports both official JSON and English/Japanese CSV observation
  responses, one caller-owned absolute deadline, HTTPS/host/redirect
  allowlists, success-only cache entries and typed
  transport/identity/corruption failures.
- Ships synthetic structural fixtures and opt-in representative live
  checks.
