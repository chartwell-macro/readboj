# readboj 0.1.1 certification

Certification date: 2026-08-02 (Australia/Sydney)

The package was certified before any Chartwell application integration.

## Deterministic gate

- `testthat::test_local()` — 34 tests, 111 expectations, 0 failures, 0 errors,
  0 warnings; the one opt-in live block was skipped by default.
- `R CMD build /path/to/user/dev/readboj` from
  `/private/tmp/readboj-final.Jf2Zba` — built `readboj_0.1.1.tar.gz`
  successfully.
- `R CMD INSTALL --library=/private/tmp/readboj-cert.fVFIsY/lib
  /private/tmp/readboj_0.1.1.tar.gz` — passed, followed by the installed-artifact
  IR02 canary described below.
- `R CMD check --no-manual
  /private/tmp/readboj-final.Jf2Zba/readboj_0.1.1.tar.gz`
  — `Status: OK`; code, test and documentation checks all passed. Repository
  index lookup warnings printed by R were caused by the sandboxed check process
  having no DNS access and did not change the check status.

Deterministic fixtures cover English JSON, English CSV pagination, Japanese
CP932 CSV, bilingual metadata, headerless/wide ZIP data, workbook text parsing,
bulk and Tankan HTML discovery, null/blank/NA/ND retention, duplicates, schema
drift, exact cursor behavior, batch/page/row/series/cell/byte/archive/member
bounds, raw/semantic hashes, cache-only replay, corruption, identity mismatch,
eviction, transient-only retry, absolute deadline, official-host allowlisting
and success-only error caching. The 0.1.1 regression additionally verifies that
a bounded CP932 prefix ending on the first byte of a multibyte character is
trimmed to the preceding complete line, while a genuinely invalid complete line
still fails validation.

## Opt-in live gate

`READBOJ_LIVE_TESTS=true ... test-live.R` passed 39 expectations. It checked:

- English JSON exact-code data for IR01 policy rates, FM01 call rates, MD01
  monetary base, MD02 money stock, BS01 BoJ balance sheet, FM08 FX and CO
  Tankan, retaining official null forecast rows;
- Japanese CP932 CSV exact-code data, bilingual FM08 metadata, and bounded
  bilingual IR02 metadata search;
- the official CSV layer route;
- the full current English bulk catalogue, an exact CGPI ZIP download/hash and
  bounded parse;
- all six Tankan archive range indexes, a current release page, asset listing
  and exact XLSX download/hash.

The IR02 incident fixture was an official HTTP 200 response with declared
`text/csv; charset=Shift_JIS`, 35,580 raw bytes and SHA-256
`4dc1c88fed7155f675bf28914261576900e41c2345240cef44c4bb9a0edab383`.
The full object decoded as CP932; only the former arbitrary 16 KiB prefix ended
inside a multibyte character. The built and installed 0.1.1 artifact then
returned five IR02 rows with complete English and Japanese names and retained
`transfer_encoding = "CP932"`.

The package commit and remote SHA are reported externally because a Git commit
cannot truthfully contain its own final SHA.
