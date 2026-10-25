# Outlook 0.2.0 release evidence — 25 October 2026

Review input from the package implementation owner. Independent approval must
identify the exact clean candidate and artifact before default-branch merge.
The authoritative approval and publication receipt will accompany the private
pull request; this record does not itself grant approval or claim deployment.

## Candidate and scope

- Private target: `chartwell-macro/readboj`, default `main`, refreshed target
  `pre-publication baseline`.
- Original Outlook base: `pre-publication baseline`.
- Branch: `codex/outlook-forecast-tables`; the commit containing this record is
  the clean integrated release candidate. Current main documentation, vignettes,
  CI and maintainer privacy (`Chartwell Macro`) are preserved.
- Version: `0.2.0`, a feature release after `0.1.1`. No runtime R import is added;
  `withr` remains a test-only Suggests dependency.
- All 16 original API/bulk/Tankan modules have identical parsed executable
  expressions across the original base, current target and combined candidate.
  All nine Outlook modules retain identical executable expressions to the
  independently accepted maintenance implementation. Its earlier artifact
  SHA256 was `48df15797d0bf1c5410c2bfee4ef2b76774b1421834f248aaa2c48c00a41f327`
  (645 assertions plus 94 focused maintenance assertions).
- Reconciliation adds documentation examples for every new export, the Outlook
  reference index and source notice, current repository/citation metadata, and a
  private-repository guard on public GitHub Pages deployment. It does not change
  reader/updater execution, Mac jobs, Chartwell, lockfiles or Library stores.

## Exact checked artifact

`readboj_0.2.0.tar.gz`, 378,071 bytes, SHA256:

`d33be177116afad8043bebc3fd7a3f11299dbcb65d943cb71116c9ac88c059e8`

`R CMD build` built all five vignettes. `R CMD check --no-manual` completed
**Status: OK — 657 PASS, zero failures/warnings/notes, one skip**. The skip is
the pre-existing optional broad statistical live suite. Outlook live checks and
the complete already-downloaded official archive corpus were enabled. New
upstream documentation tests and all non-network examples passed. The final
archive matches 107 worktree source files byte-for-byte; only DESCRIPTION
build metadata and generated vignette/documentation files are generated.

Reproduction, with R 4.5.1 and the existing dependencies/Poppler provisioned:

```sh
R CMD build /path/to/readboj
READBOJ_OUTLOOK_FIXTURE_DIR=/path/to/three-release-evidence \
READBOJ_OUTLOOK_ARCHIVE_DIR=/path/to/complete-archive-evidence \
READBOJ_OUTLOOK_LIVE_TESTS=true READBOJ_LIVE_EXAMPLES=false \
R CMD check --no-manual readboj_0.2.0.tar.gz
```

Without the external corpus, the package's ordinary deterministic tests still
run; external evidence checks remain explicit rather than invented. Local
pkgdown 2.2.0 built the complete site/reference/articles into a disposable task
directory and `check_pkgdown()` reported **No problems found**. Pandoc emitted
five tool deprecation notices for `--highlight-style`; they do not change the
rendered content and are separate from the zero-warning R package check.
Public Pages deployment is disabled for this private repository. The canonical
metadata URL is `https://chartwell-macro.github.io/readboj/`; a local build does not
claim that this release was published there.

## Preserved data and ordinary installed workflows

The bundle remains **74 editions, 2000-10 through 2026-07; 4,142 rows; 39 fields;
4,137 finite scalars; five explicit published NAs; 144 official assets**. Its
67,628-byte file SHA256 is
`ba77323813bb03578c8f99dadfe4cd0422b0a66e59b1e6fc2d1e5dd2636838d6`;
numeric-content SHA256 is
`ad5ffa9e6a1e970f6e32c98e97436add3f1eacd9b7ad83763c5babbb7c6a2a49`.
Parser SHA256 remains
`25b5df5528361b00eee515d0d37aac4d7ce0f6accd17f637eb66d036dc662caf`.

The exact final installed artifact returned all 39 columns equal by value,
order and type to the approved bundle. Publication/fiscal start/end remain
`Date`; current/prior vintage, fiscal targets, comparators, actual/conditional
status, ranges, raw values/NA and source provenance are preserved. One
structured load served catalogue and all-history reads; trapped HTTP, raw PDF
and updater paths were never called, and the ordinary directory was not
created. The real installed `outlook-daily.R --maintenance --once` returned
`idle`, exit 0, with unchanged state hashes. A not-due API call also trapped
numeric-bundle loads. Its state was copied from a genuine earlier successful
calendar/numeric check, without fabricating freshness timestamps.

Calendar discovery still uses the official Outlook Bank's View column and BOJ
holidays. Bank's View and normally next-business-day 14:00 Tokyo full text are
separate obligations; missing holiday coverage stays unconfirmed. Calendar,
numeric update and release-probe retry clocks remain independent. Catch-up,
metadata polling, year rollover, locks, corrupt-state fallback/repair, atomic
publication and failure exit status are covered by the unchanged 94 focused
assertions and combined package suite. No not-due network or numeric work is
introduced. Temporary raw staging is disposable and cleaned; last-good numeric
data and coverage-loss guards remain intact.

## Applicable review gates and retained performance

| Gate | Package evidence / remaining acceptance |
|---|---|
| G1 Scope/integration | Refreshed exact target, preserved upstream, bounded Outlook/release diff, private target and no unrelated production edits. |
| G2 Correctness/state | 657 assertions plus the complete corpus; all 39 fields and typed dates preserved; original executable modules identical. |
| G3 Ordinary workflows | Exact installed saved reader, local status, API idle and real installed CLI; Chartwell UI wiring belongs to the parent task. |
| G4 Resilience/isolation | Existing independent calendar/data retries, same-URL revisions, separate full-text stage, year roll, lock/concurrency, atomic/corrupt/failure fixtures; only disposable test directories. |
| G5 Visual/export | No app chart/export change. Existing upstream source chart and notice are unchanged; README/reference/vignettes build and check. Chartwell visuals require downstream app acceptance. |
| G6 Performance | Unchanged executable/runtime imports preserve the accepted implementation. Saved-read performance evidence below is retained because release changes are documentation/metadata only. |
| G7 Delivery/evidence | Exact artifact/source correspondence and clean committed candidate; independent APPROVE, passing required remote checks, private PR merge and remote verification remain publication gates. |

Retained matched full-corpus evidence from the accepted saved-reader work:
cold 0.094/0.102/0.177 s min/median/max; warm 0.001/0.001/0.004 s; no read writes,
network or extractors. Headroom used 94 editions/5,222 rows: cold median
0.1295 s and warm median 0.002 s. Budgets were 1 s cold / 0.25 s warm and at least
25% corpus growth. Numeric staging and source acquisition remain outside
ordinary selection. These are retained measurements, not newly measured
claims for the release metadata change. Fresh process timings in private smoke
receipts are informational rather than a replacement paired performance gate.

## Rights and publication boundary

Source: Bank of Japan. Exact source URLs/hashes, notes and provenance remain
with the tables. MIT applies to package code, not BOJ publications, graphics or
data. Commercial or specified reuse may require prior permission; intended-use
permission is not established by this private release. The bundle is not
relabeled synthetic and no public bank-data release is authorized or performed.
See `inst/NOTICE/outlook-source.txt` and `docs/outlook.md`.

Final temporary logs and machine receipts are under the task evidence directory
`/private/tmp/readboj-release-20261025`, including `final/check.log`,
`final/readboj.Rcheck/tests/testthat.Rout`, both executable-equivalence files,
`final/installed-smoke.json`, `final/installed-cli.json` and `pkgdown.log`.
This compact source record retains the values, identities, commands, evidence
limits and artifact hash if temporary logs expire. Review and publication are
separate decisions; the private PR records their exact SHAs and outcomes.
