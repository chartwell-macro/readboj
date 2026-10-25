# Saved Outlook forecasts and general raw reader

`readboj` bundles the complete verified numeric history for ordinary local
reads. A separate updater and raw reader derive tables from source semantics. It has no dated release profiles, fixed target-year windows,
page-number allowlist or per-edition support gate. The complete archive snapshot
verified on 22 October 2026 contains 74 editions (24 HTML / 50 PDF primary
Bank's Views), October 2000 through July 2026. Every edition has a successful
numeric-table parse; the per-edition inventory records its counts and source
identities. All 144 primary/full-text archive assets were acquired separately.

## Interface and edition identity

```r
releases <- list_boj_outlook_releases()
latest <- read_boj_outlook("latest")
dated <- read_boj_outlook("2000-10", comparison = "all")
history <- read_boj_outlook("all", comparison = "all")
boj_outlook_status()
update_boj_outlook() # separately from ordinary selections
raw <- read_boj_outlook_raw("latest", deadline = Sys.time() + 300)
receipts <- boj_provenance(history)$editions
```

The explicit raw route discovers both archive table families, including the legacy three-column
rows with unlabeled full-text PDF links. The date/label/URL must agree. A release
is a nominal report month, not an assumed quarterly calendar. Before 2016 the
archive reports were semiannual; January/July interim assessments were separate
policy statements. Full text belongs to its Bank's View edition, even when
published in the next month. A legacy full-text date not stated in the archive
is `NA`; the reader separately retains the PDF's observed cover date as
`source_publication_date`.

`release` accepts an exact `YYYY-MM`, `latest`, or `all`. Latest selects the
newest saved edition on the default route, or newest official edition on the
explicit raw route. Raw all-mode reads every discovered edition under one
absolute deadline and fails explicitly if any cannot be read; it never returns
successful partial archive coverage. `comparison` accepts `current` (default),
`prior`, or `all`. The all-mode receipt has one entry per edition. Exact dated
calls return the original scalar receipt structure.

For each observation, `release` and `publication_date` identify the containing
Bank's View. `forecast_vintage` identifies the original current/prior forecast
month printed in that source. Reproduced comparators are not relabeled as new
forecasts or assumed byte-identical to their original publication. An October
report may explicitly compare a July interim assessment even though July was
not a separate Outlook report edition in that period.

## Saved-data contract and daily delivery

`inst/extdata/outlook-saved.rds` is a compact xz-compressed structured bundle.
It contains the full catalogue, all 39 row fields, per-edition receipts, a
144-asset hash/HTTP-validator manifest, parser identity, integrity checksum and
revision history. It contains no HTML, PDFs, images or workbooks. Local cache
paths are removed from portable receipts; URL/hash/acquisition/extraction
identity and scoped table notes remain. The package baseline is never changed
by the updater. Full-corpus equality is checked against the independently
acquired and verified raw result, including all NA cells and source locations.

Normal catalogue and series reads inspect local commit metadata and load one
validated structured object. Repeated selections reuse it. No HTTP request,
subprocess or raw document read occurs, even with no Poppler executable.
`measure`, `statistic` and `range_scope` accept exact semantic-ID vectors;
unknown IDs fail. All releases and comparisons remain selectable. `refresh`
reloads saved data only. A saved source pin checks the recorded numeric asset
hash; it does not contact that URL. Raw transport parameters apply only when
explicitly selecting `source = "raw"`; the `_raw()` functions are clearer.

The default persistent directory is
`file.path(tools::R_user_dir("readboj", "data"), "outlook")`. Configure one shared
location using `READBOJ_OUTLOOK_DATA_DIR`, option `readboj.outlook_data_dir`, or
`data_dir` on both reads and updates. Ordinary reads do not create or write it.
`boj_outlook_status()` and result provenance expose origin, generation, data
and parser hashes, last successful source check and last attempt outcome.
A newer parser makes `parser_update_required` true and invalidates all editions
on the next update. Existing compatible saved rows remain usable meanwhile.

`update_boj_outlook()` fetches the current archive and checks **all** linked
primary and full-text sources. HTTP ETag/Last-Modified conditional requests
are used where available. A 200 response is hashed, so servers ignoring
conditional headers still support revision detection. Detection never relies
only on the latest publication date. Source URL/date changes, new hashes and
secondary linked-asset changes invalidate dependent editions. Unchanged
editions are copied byte-for-byte at the row level. Any disappeared historical
edition, failed source, inconsistent second download, parser ambiguity,
invalid scalar identity or incomplete candidate fails the entire transaction.
A revised table must preserve every existing release/vintage/comparison/FY/
measure/statistic/range-scope identity by default, including its fiscal targets.
A genuine intentional removal requires the reviewed `allow_coverage_loss = TRUE`
opt-in (with `force = TRUE` after same-day rejection). Status reports the exact
removal count, affected editions/targets and identity hash; revision history
retains the removed identities and the prior rows/receipts. Ordinary provenance
reports the snapshot coverage-loss summary for an accepted opt-in.
A same-URL historical correction retains the replaced rows, old catalogue,
asset hashes and receipts in the new snapshot's revision history.

Publication uses an exclusive directory lock with PID/host/token ownership,
immutable content-addressed RDS objects and immutable monotonically numbered
commit markers. Only a complete, checksummed, reread and validated object gets
a marker through a same-directory atomic rename. Readers see complete old/new
generations and reuse the last good one during updates. Three generations are
retained; a corrupt active object or marker triggers a typed warning and
fallback to an older valid generation or the package baseline. Checks and
failures are separate from dataset commits. A lost lock or concurrent change
cancels publication. A dead local writer's lock is reclaimed; foreign-host
locks require operator inspection. An incomplete lock is reclaimable after
one hour. No lock is reclaimed by age alone while its local owner is alive.

Attempts are throttled once per **UTC day**, including failed attempts;
`force = TRUE` retries immediately. A running/interrupted attempt does not
satisfy the throttle. Graceful interrupts receive an `interrupted` receipt; a
killed process leaves `running` until the next locked recovery. Parser changes and `rebuild = TRUE` bypass it. Failures
raise `readboj_outlook_update_error`, retain their parent class/status fields,
and save a `failed` check receipt without claiming a successful source check.
A successfully committed dataset remains valid if writing the final ancillary
status receipt fails; that failure is reported separately.

Update bounds: 16 MiB per response, 256 MiB downloaded/staged per transaction,
200 editions, 20 leading PDF pages, 1 MiB extracted text and a thirty-minute
absolute deadline by default. Raw staging is removed on success/error and on
the next locked run after a process crash. No permanent raw update cache exists.
Three structured generations, thirty small status receipts and revision history
inside the current snapshot remain. Structured objects are limited to 32 MiB
on disk / 64 MiB in memory. Exceeding a bound fails instead of silently pruning
revision provenance. The independent raw reader/builder still uses the existing
bounded raw cache (default 2 GiB / 1,000 objects), configurable/prunable through
the package's existing cache interface.

The installed application/scheduler entrypoint is:

```sh
READBOJ_OUTLOOK_DATA_DIR=/your/persistent/readboj/outlook \
Rscript /installed/readboj/scripts/outlook-daily.R --once
# Or start a long-lived application worker with --watch.
```

Find its exact installed path with
`system.file("scripts", "outlook-daily.R", package = "readboj")`. `--watch` checks
the daily throttle every sixty seconds, runs immediately when due, and writes
only meaningful update outcomes to stdout. `--force` / `--rebuild` affect the
first attempt only. A throttled attempt following a failed update remains a
failed scheduler outcome: `--once` reports it and exits nonzero. Successful
throttles exit zero quietly. Watch mode reports the same failure once, sleeps
sixty seconds between checks, clears one-shot force/rebuild flags, and reports
a new failure or successful recovery without repeating an unchanged failure.
Start it as an application worker or invoke `--once` from
your approved scheduler; this implementation installs no OS-global jobs and
creates no Codex reminders. The source-controlled
`.github/workflows/outlook-daily.yml` runs daily at 03:17 UTC and manually. It
installs in a temporary CI library and preserves its own validated user-data
cache. This CI cache is a maintenance check, **not a delivery channel to installed
consumers**. Consumer refreshes run the installed entrypoint with the consumer's
shared persistent directory. No workflow has been activated or published in
this uncommitted implementation.

For an independent package-baseline rebuild, use
`build_boj_outlook_bundle(explicit_output_path, refresh = TRUE)` or
`tools/rebuild-outlook.R`. It discovers and parses the complete archive without
reading the existing saved bundle, validates the result, and atomically writes
a portable RDS. Review its coverage/value/source diff before a later approved
package release. The builder never installs or activates an output bundle.

## Calendar-aware autonomous maintenance

New published data does not require an R package release. Use the same persistent
reader directory for `maintain_boj_outlook()` and your hourly/application scheduler.
The caller can use returned `next_due_at` to arrange a more precise next wake-up.
The package itself creates no OS jobs, automation entries or global installs.
A genuinely new source structure can still require a parser update.

```r
calendar <- list_boj_outlook_calendar() # Official listed upcoming stages.
result <- maintain_boj_outlook()
result$next_due_at                     # Scalar ISO8601 UTC string.
boj_outlook_maintenance_status()        # Local status, no network.
```

Installed CLI modes are `outlook-daily.R --maintenance --once` and the standalone
`outlook-maintenance.R --once`; both support `--watch` / `--force`. The maintenance
CLI prints machine-readable JSON for once-mode operational results, including
idle/failure; invalid command arguments remain standard usage errors.
`failed` and `busy` exit nonzero. A watcher sleeps sixty seconds and suppresses
unchanged results. Existing daily data-only CLI behavior remains available.

The calendar source is [BoJ's MPM schedule](https://www.boj.or.jp/en/mopo/mpmsche_minu/).
Only the explicitly labelled Outlook Bank's View column supplies report dates;
non-Outlook MPMs, Summary of Opinions and Minutes do not. Calendar table headings
supply the year; there is no production release-date allowlist. The nominal
meeting-month edition is a hint until the archive supplies the actual edition
identity, so cross-month publication does not relabel a report incorrectly.
Bank's View is after the relevant MPM with no fixed time: its midnight Tokyo
value is a polling boundary, never an asserted publication timestamp.

Full text is a separate stage, in principle at 14:00 Tokyo on the next business
day. [BoJ's holiday tables](https://www.boj.or.jp/en/about/outline/holi.htm), weekends
and the stated December 31–January 3 closure determine that day. Holiday headings
are used rather than captions, because current source captions lag their year.
If future holiday-year coverage is unavailable the date is explicitly unconfirmed
and only an earliest polling bound is returned. The archive's observed publication
always wins. No full-text obligation is lost when Bank's View arrives, after a
year-table rollover, after sleep, or when an independent archive update discovers
a report absent from a temporarily unavailable calendar.

`maintenance/` beside the numeric data stores schema `outlook-maintenance-v1`:
parsed official calendar/holiday dates and source hashes, stage obligations,
check/probe clocks, next UTC due time, updater outcome, errors and retry state.
It uses a separate writer lock and checksummed immutable objects/atomic generation
markers, retaining three generations. Corrupt generations fall back to valid prior
state; an exact-hash replacement repairs a corrupt object safely under the lock.
Calendar and tiny archive staging is bounded and removed on normal exit/error,
with fixed staging paths cleaned by the next locked run after interruption.
No raw calendar pages are distributed or embedded in maintenance snapshots.

Not-due calls read local maintenance state only: no network, PDF extraction,
numeric-bundle load or write. Due daily revision checks still validate the full
source dependency graph with `update_boj_outlook()`. During an overdue publication
window, one small archive probe and optional HEAD validator probes detect new
links/dates/assets or current-stage validator revisions and can force an update
past the data updater's same-day throttle. Unchanged probes do not scan all 144
assets. Canonical field JSON prevents differences in R serialization from causing
false changes, and observed validators are retained even if source bytes were
unchanged. Servers without usable HEAD validators retain daily byte-hash coverage.

Default calendar/revision intervals are 86,400 seconds; release probes are at
least 3,600 seconds apart. Due work catches up on the next invocation after sleep.
A calendar/holiday failure retains its last-good calendar **and still permits an
independently due numeric refresh**. Result remains truthfully `failed`, marks
calendar freshness false, includes any successful updater outcome, and retries
calendar work rather than repeating that completed numeric update. Retry delays
are bounded at 5 minutes, 15 minutes, 1 hour, 6 hours, then at most daily. Calendar, data-update and release-probe retry clocks are independent: a long
calendar backoff cannot postpone an earlier daily data deadline. Successful
independent work does not clear the pending calendar error or retry time. Each
HTTP operation also has its request retry limit and the shared absolute deadline.

Machine status includes `status`, UTC `next_due_at`/`next_release_at`,
`next_release_date`, `edition`, `release_stage`, `release_time_is_fixed`,
`full_text_pending` / `pending_full_text`, calendar timestamps/sources/error/warnings,
`updater_outcome`, structured `error` and `failure_count`. Statuses are `success`,
`unchanged`, `idle`, `waiting`, `failed` or `busy`. Local status may be
`uninitialized` before first maintenance. Calendar failure and numeric success are
separate facts; neither failure metadata nor a stale calendar claims a new source
check or erases valid numeric data.

A host invoking hourly can be up to one invocation interval late; it should use
returned UTC due times for tighter timing if required. Package code and source-
controlled CI definitions are not an activated host scheduler. The parent task
provisions the actual local job; CI uses its own maintenance cache, which remains
separate from installed-consumer delivery.

## Measured performance and acceptance

Budgets were recorded before the saved-route implementation: cold local read
at most 1 second; warm series selection at most 250 ms, with full history plus
at least 25% headroom. Final corrected implementation on this macOS arm64 / R
4.5.1 host:

| Operation | Median | Maximum | Coverage |
|---|---:|---:|---|
| Cold saved all-history read | 0.102 s | 0.177 s | 74 editions / 4,142 rows |
| Warm latest GDP-median selection | 0.001 s | 0.004 s | Same loaded full dataset |
| Cold capacity read | 0.1295 s | 0.170 s | 94 synthetic editions / 5,222 rows |
| Warm capacity selection | 0.002 s | 0.003 s | Same capacity dataset |

Ten cold reads clear the package's in-process memo; the OS filesystem cache is
not flushed. Warm timing uses 100 selections. Five separate installed-package
R processes took 0.167–0.230 seconds for package load plus full read, and
0.258–0.341 seconds including R process startup. These are host measurements,
not cross-platform guarantees. The larger fixture exists only during benchmarking
and is never bundled as a forecast. Its 94 editions / 5,222 rows exceed both
25% thresholds (93 / 5,178).

The compressed real bundle is 67,628 bytes; its structured object is 3,666,480
bytes. Cold-read allocation profiling recorded 63,608,336 transient bytes.
Fresh installed R-process peak RSS was 141,410,304 bytes, including R and loaded
dependencies. Ordinary reads wrote zero files. Deterministic I/O traps verify
zero HTTP, raw-document reads or extractor calls, and one structured load reused
across selections. Before this change, raw all-history replay from the local
source cache took 16.816 seconds and warm latest parsing took 0.296–0.404 seconds.

The corrected installed daily CLI completed a fresh live source check at
00:14:02 AEDT on 25 October 2026: 145 requests, 144 assets, 1,423,013 downloaded
bytes, about 37 seconds, no source/scalar-coverage changes, zero reparsed editions
and no rewritten snapshot. Conditional support varies by server; a 200 response
is still hashed. A deterministic no-network no-change run took 0.437 seconds,
wrote only two durable status files (958 bytes) and no snapshot. Mocked
single-addition and historical numeric-revision runs took 0.687 / 0.823 seconds,
parsing only their affected edition; those exclude real extraction cost.

Separately, genuine parser/Poppler runs against the local acquired corpus
measured 1.351 seconds to add the missing latest official edition (73 to 74),
and 1.161 seconds for a controlled historical PDF byte revision. Each parsed
one edition. Their measured file-content writes were 2,277,044 / 850,786 bytes,
including transient source/extractor files, metadata and the new structured
snapshot; filesystem metadata/journaling is excluded. The revision fixture
appends a PDF comment and preserves official numbers; it is not an assertion
that BoJ revised that source. Separate tests exercise changed numeric values.

Reproduce the local benchmark from the repository with
`Rscript tools/benchmark-outlook.R /existing/evidence/directory`. Optional
`READBOJ_OUTLOOK_ARCHIVE_DIR` enables real parsing of externally acquired PDFs;
no raw publications are shipped for this benchmark. The final built-package
check passed **645 assertions, zero failures/warnings/notes**, with one existing
opt-in broad statistical live suite skipped. The Outlook live tests and full
external corpus, including independent held-out value checks, were enabled.

Parent review reproduced and verified two additional regressions: failed-throttled
entrypoint runs now exit nonzero and report failure; partial-but-otherwise-valid
edition revisions now preserve all existing scalar identities/targets by default.
Tests check unchanged last-good bytes/values/check time, explicit reviewed loss
with revision history, actual entrypoint once/watch behavior and quiet recovery.
Independent parent tests also used the real HTML parser to verify a same-URL
numeric correction, unseen 2027 edition, source pins, unchanged fields and failure
recovery, alongside a fresh 145-request live check.

## Format families and published definitions

The implementation uses format rules, not release rows:

| Source structure | Treatment |
|---|---|
| Early HTML majority/all-member tables | Expand HTML row/column spans; derive headers, targets and scope from captions/context |
| Parenthesized prior forecasts | Read the dated parentheses definition from source notes; do not invent absent prior medians |
| Medians introduced in later tables | Return bracketed medians only where printed; retain range-only cells |
| Actual/comparator tables and extended horizons | Read their caption fiscal target and row identities |
| Legacy image-only HTML | Use the full-text PDF linked by the official archive; keep both Bank's View and numeric-source receipts |
| PDF tables | Derive headers, fiscal rows, statistics and page location from Poppler text/bounding boxes |
| Tax-adjusted rows or columns | Retain separate CPI/CGPI definitions; blank diagonal cells publish no statistic |
| Shared CPI cells | Preserve the single source cell/span/coordinates when it applies to both column definitions |
| Pandemic member-submitted ranges | Preserve the input/range-trimming definition separately for current and prior vintages |
| Printed dashes | Retain explicit `not_applicable` / `NA` rows, without invented endpoints |

The following IDs describe source measures, not guessed API series:

| ID | Published definition |
|---|---|
| `real_gdp` | Real GDP growth |
| `domestic_wpi` | Domestic wholesale prices, including the source's `Domestic WP` spelling |
| `domestic_cgpi` | Domestic corporate goods prices |
| `domestic_cgpi_ex_consumption_tax` | Domestic CGPI excluding the consumption-tax effects |
| `cpi_ex_perishables` | Legacy CPI excluding perishables |
| `cpi_ex_fresh_food` | CPI excluding fresh food / all items less fresh food |
| `cpi_ex_fresh_food_ex_consumption_tax` | CPI excluding fresh food and the stated consumption-tax effects |
| `cpi_ex_fresh_food_ex_tax_education` | Reference CPI excluding the stated tax/free-education effects |
| `cpi_ex_fresh_food_energy` | CPI excluding fresh food and energy |

The prior parentheses under an early CGPI header can explicitly refer to WPI;
that source footnote changes the comparator's measure identity. A historic
reference column is not automatically today's ex-fresh-food/energy CPI.
`source_header`, raw cells and source table notes remain attached. Additional
published qualifications, such as index rebasing, GDP fixed-base/chain-linking
comparisons or tuition-subsidy treatment, survive in the table notes; consumers
must retain them when comparing definitions across editions.

Fiscal targets have `period = FYyyyy`, `period_start = yyyy-04-01`, and
`period_end = (yyyy+1)-03-31`, inclusive. Units are the source's annual percentage
changes, normalized to `y/y % chg.` with `frequency = ANNUAL(MAR)`. The report
month is not a fiscal target or a March-quarter growth period.

Statistics are `majority_lower`, `majority_upper`, `median`, `all_lower` and
`all_upper` where those statistics are printed. A single value becomes `actual`
only when its source row/measure-specific note says so. A source-conditioned
point estimate becomes `conditional_estimate`; otherwise an unqualified
published scalar is `point` / `published_point`. A date alone never makes a
point an actual. Adjustment assumptions do not invalidate published forecast
ranges, and do not turn a headline actual into an adjusted reference actual.
Notes are scoped to the forecast tables, excluding nearby risk-chart prose.

Member ranges are dispersion, not confidence intervals. Most majority ranges
exclude the highest and lowest member point forecasts. In April 2020 members
submitted intervals and the majority range excluded two high and two low
endpoints. The January comparator remained a point-based range. July 2020
returned to point forecasts while reproducing April's interval-based comparator.
The returned `member_input`, `range_trimming`, `range_scope` and dated
`forecast_vintage` preserve these distinctions. No median is fabricated for
the interval-only publication or its reproduced comparator.

A shared cell is represented for each applicable header with the same
`source_cell_id`, `source_column_span` and `shared_cell = TRUE`. This is explicit
HTML colspan or PDF table geometry, not inference from equal numbers. Logical
scalar counts therefore differ from counts of distinct physical source cells.

The reader never estimates coordinates from illustrated member/risk symbols,
assigns member identities/trajectories, constructs probabilities, or invents a
policy-rate path. Tankan survey expectations remain separate.

## Explicit raw parsing: runtime, bounds and failures

HTML numeric tables need only the existing `xml2` dependency. PDF extraction
uses optional, provisioned Poppler `pdftotext`, including its layout and
bounding-box output. No R dependency was added; `pdftools` and `processx` are
not used. The tested existing executable was `/opt/homebrew/bin/pdftotext`,
version 26.07.0, with R 4.5.1. Configure another approved path with argument
`pdftotext` or option `readboj.pdftotext`. Nothing is installed by this reader.
A deployment must separately provision/pin and qualify its executable and
review its packaging/license obligations. Missing support raises
`readboj_dependency_error` for PDF sources while HTML/statistical readers work.

Retrieval reuses official HTTPS/host validation, retries, raw SHA-256 snapshots,
corruption checks, offline replay and bounded total raw caching. Defaults:

| Bound | Default |
|---|---|
| Archive bytes | 8 MiB, or the caller's smaller source bound |
| Source HTML/PDF bytes per asset | 16 MiB |
| Discovered editions | 200, configurable 1-1,000; excess fails |
| Leading PDF pages | 20, configurable 1-100 |
| Accepted UTF-8 layout text | 1 MiB |
| Accepted bounding-box XML | 8 times the layout-text bound |
| HTML table dimensions | 100 rows / 20 physical columns |
| Parsed measure columns | 2-6 |
| HTTP timeout / retries | 30 seconds / 3 retries |
| Whole-operation default deadline | One absolute time, 300 seconds |
| Total raw cache | Existing 2 GiB / 1,000 objects defaults |

Bounds also apply to cache hits. All-mode carries one absolute deadline through
discovery, each edition, retries/delays, version probes, extraction and parsing.
Subprocess timeout is the remaining whole seconds; less than one second fails
before launching. Output sizes are checked after the bounded subprocess and
before reading/parsing; this is not a streaming disk quota. Extraction temporary
files are removed on failure/success. This explicit raw route does not consult saved data.

On the explicit raw route, refresh bypasses archive and source raw caches. Offline replay still needs the
extractor for PDF sources. `expected_sha256` optionally pins the numeric asset
(HTML, or the linked PDF for image-only HTML), with an identity error on change.
Pin individual editions; a single pin with all-mode is rejected. Actual source
hashes are always returned. There is no dated hash admission table in runtime
metadata and no claim that a mutable URL is official first-release history.

The parser checks source title/date, official edition and asset identity,
semantic headers, fiscal row association, prior month labels/parenthesis notes,
range construction, available medians, actual/conditional notes, complete cell
syntax, ordered endpoints, median inclusion and duplicate identities. It fails
on ambiguity. Unknown structures raise schema/parse errors rather than empty
successes. Missing structured HTML and absent linked numeric PDFs have an
explicit `readboj_no_forecast_table_error`; inaccessible assets retain typed
transport failures. The current exhaustive corpus has no such exceptions.

## Provenance and source verification

Each row retains raw value/cell, source header/row label, source cell ID,
table index/row/column/span, shared-cell flag, fiscal/vintage identity, source
URL/hash/format, and HTML XPath or PDF page/printed-page/bounding box.
`boj_provenance()` adds archive provenance, both source receipts when a linked
full PDF is used, observed source publication date, raw HTTP/cache identity,
extractor version, layout and coordinate hashes, parser schema and scoped notes.

The archive snapshot, all 144 retrieval outcomes and source hashes, 74 parse
outcomes/scalar counts, extracted text, rendered representatives, exact-cache
all-mode result, independent-index cross-check and test/check logs are retained
under `/private/tmp/readboj-outlook-general-20261022/` for this implementation.
Raw sources and rendering logs are research/test artifacts. The validated numeric
rows and portable receipts now form the package baseline. Source PDFs/images are
not bundled or redistributed with the package.

The existing three-report 167-cell January/April/July 2026 regression remains.
Additional real tests cover every observed format transition and independent
full-table transcriptions for held-out April 2010, October 2014, October 2017
and July 2022 editions, all absent from runtime metadata. Tests include all-mode
coverage and source receipts, the legacy lower/upper-only tables, WPI comparator
footnotes, conditional GDP, explicit dashes, shared columns, adjusted rows,
pandemic definitions, the headline-CPI actual/scoped-adjustment regression,
future-edition resolution, cache bounds, corruption/identity, deadlines and
missing-runtime failures. Existing API/bulk/Tankan/transport suites remain.

```sh
Rscript --vanilla -e 'testthat::test_local()'
READBOJ_OUTLOOK_FIXTURE_DIR=/path/to/three-report-fixtures \
READBOJ_OUTLOOK_ARCHIVE_DIR=/path/to/acquired-archive \
Rscript --vanilla -e 'testthat::test_local(filter="outlook")'
READBOJ_OUTLOOK_LIVE_TESTS=true Rscript --vanilla -e 'testthat::test_local(filter="outlook-real")'
R CMD build .
R CMD check --no-manual readboj_0.2.0.tar.gz
```

## Chartwell wiring and rights

A minimal selector remains an Outlook subtype, release selector, comparison,
measure and statistic. Fetch a whole edition once, then select locally. Add
`range_scope` where all-member endpoints are offered. Keep logical latest/all
separate from actual edition metadata and complete source receipts; for
immutable replay retain the resolved edition and source pin. Use fiscal start
and end plus FY labels. Preserve actual/conditional/forecast status, shared
cells, range construction and defining notes through downstream exports.
Existing database/code selectors require no changes. No Chartwell file,
lockfile, Library or production-data change is part of this package work.

The package MIT license does not license BoJ publications. The
[official copyright terms](https://www.boj.or.jp/en/about/copyright.htm) require
source credit and specify prior permission for commercial reproduction,
specified materials and graphics, with alteration conditions. Intended-use
permission for extracted data/derived exports is not established here. Retain
`Source: Bank of Japan` and the exact source links. API notification/credit
procedures do not grant Outlook publication/graphic permissions. Production
runtime/rights admission and app wiring/acceptance remain downstream work.
