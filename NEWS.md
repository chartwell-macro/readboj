# readboj 0.1.1

* Fixes bounded Shift-JIS/CP932 response validation so a byte limit that lands
  inside a multibyte character is trimmed to the preceding complete line.
* Adds deterministic split-character coverage and a live IR02 bilingual
  metadata canary.

# readboj 0.1.0

* Adds bounded, paginated retrieval from all three official Bank of Japan
  Time-Series Data Search API operations.
* Adds exact raw-response snapshots, SHA-256 provenance, cache/offline replay,
  a semantic API hash that excludes only the volatile response `DATE`, and
  automatic total cache bounds.
* Adds stable English/Japanese metadata fields and streamed, result-bounded
  search suitable for the large Tankan catalogue.
* Adds portable atomic catalogue snapshots with complete per-database counts,
  source URL/hash pins and fully offline bounded search.
* Adds official bulk-file and dated Tankan release-asset discovery/download.
* Adds bounded text-preserving XLS/XLSX parsing for official catalogues and
  Tankan workbooks.
* Supports both official JSON and English/Japanese CSV observation responses,
  one caller-owned absolute deadline, HTTPS/host/redirect allowlists,
  success-only cache entries and typed transport/identity/corruption failures.
* Ships synthetic structural fixtures and opt-in representative live checks.
