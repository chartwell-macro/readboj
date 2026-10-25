# readboj 0.1.1

## Test environments

* macOS Sequoia 15.6, aarch64, R 4.5.1 (UTF-8; Apple clang 17.0.0 and GNU
  Fortran 15.1.0).

The clean baseline at commit `pre-publication baseline` was
also checked locally on R 4.5.1 and completed with 0 errors, 0 warnings, and 2
NOTEs.

## Author and maintainer metadata

`Authors@R` records Chartwell Macro as author, creator, and copyright holder. The built
`Author` and `Maintainer` fields, package citation, GitHub citation metadata,
README, package topic, and pkgdown author page use the same display. Package
code is MIT licensed, copyright Chartwell Macro. Bank of Japan source rights and
preserved third-party people, copyright notices, and licence terms remain
unchanged.

## R CMD check results

The current built source tarball was checked with `R CMD check --as-cran
--timings` from `/private/tmp/readboj-email-privacy-final.XkFilU` and
completed with 0 errors, 0 warnings, and 1 NOTE. The full check log is
`/private/tmp/readboj-email-privacy-final.XkFilU/readboj.Rcheck/00check.log`.

The package installed into a clean library; examples, tests, five vignettes,
vignette rebuilding, and both PDF and HTML reference manuals passed. The
offline test suite also passed locally, with the live-network test remaining
opt-in.

The remaining NOTE is repository-visibility related:

* CRAN incoming-feasibility reports a new submission and cannot verify the
  repository, issue tracker, Actions, CONTRIBUTING, or pkgdown URLs because
  they return HTTP 404 without authenticated access. The repository/site must
  be published or made reachable before a CRAN submission.

The baseline check's environment-only current-time NOTE did not recur in the
final check.

## Documentation and release validation

The README and five vignettes were rendered using the offline/default path.
The local pkgdown site built successfully and `pkgdown::check_pkgdown()` found
no problems in `/private/tmp/readboj-pkgdown-email-privacy.pr1REf`; the
generated author page, citation, homepage, package topic, and changelog all use
`Chartwell Macro`, with no optional Chartwell address, stale author names, or local build
paths. Earlier desktop and narrow-layout inspection confirmed that the
provenance-recorded chart is readable, follows its compact executable code,
and introduces no broken images or horizontal overflow.

The only amendment change under `R/` is package-topic roxygen commentary in
`R/readboj-package.R`; all runtime-source comment-stripped executable hashes
match the merged baseline. The installed chart and source notice also match
their pinned SHA-256 hashes, and the fixture-based observation probe remains
identical to the baseline. A matched
offline parser benchmark (30 warm-ups, 400 measurements) retained the 5.0 ms
median and measured 11.0 ms p95 versus the 10.0 ms baseline p95 (0% and +10%,
respectively); two additional stable 400-measurement runs were faster at 2.0
ms median and 4.0 ms p95. A separate 1,000-measurement diagnostic showed
large host-scheduling outliers, so the repeated stable passes and
byte-identical executable sources provide the performance conclusion.

Fixture-based equivalence probes covered all 18 exports in 31 cases. All
values, names/order, types, classes, attributes, dates, warnings, typed errors,
and filesystem effects matched the baseline after removing only generated
timestamps and temporary paths. A paired, offline two-page benchmark used 100
measurements after warm-up: the full cached workflow changed from 9.70 ms
median/15.435 ms p95 to 10.05 ms/14.940 ms (+3.61%/-3.21%), and its separate
parse/normalisation stage changed from 6.70 ms/9.260 ms to 6.875 ms/9.425 ms
(+2.61%/+1.78%). Network time was zero. Neither validation is represented as
an R CMD check.

## Continuous integration

GitHub Actions passed on the chart/documentation feature branch at commit
`pre-publication baseline`. The R CMD check matrix passed on
Ubuntu with R oldrel-1, release, and devel; macOS with R release; and Windows
with R release. The pkgdown build/check and test-coverage workflows also
passed. Subsequent default-branch reruns at the same SHA were rejected before
any steps started because GitHub reported an account billing or Actions
spending-limit issue. Follow-up author, citation, and licensing-metadata pushes
were rejected for the same reason before any workflow step started; these are
external CI infrastructure failures, not package check failures. An initial
Windows run exposed a platform-specific invalid-byte test fixture; the fixture
was made deterministic without changing package runtime code, and the complete
feature matrix then passed.

Separate Win-builder and R-hub checks have not been run or claimed.
