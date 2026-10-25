# Incrementally refresh saved Outlook forecast tables

Checks the live archive and every linked Bank's View/full-text asset
using HTTP validators where available and SHA-256 otherwise. A changed
URL, source hash or parser invalidates only its dependent editions (all
editions after a parser change). Unchanged numeric tables are reused.
Missing historical editions fail validation rather than silently
reducing coverage.

## Usage

``` r
update_boj_outlook(
  data_dir = boj_outlook_data_dir(),
  force = FALSE,
  rebuild = FALSE,
  timeout = 30,
  retries = 2L,
  wait = 0.1,
  max_bytes = 16 * 1024^2,
  max_total_bytes = 256 * 1024^2,
  max_releases = 200L,
  max_pdf_pages = 20L,
  max_text_bytes = 1024^2,
  pdftotext = getOption("readboj.pdftotext", unname(Sys.which("pdftotext"))),
  deadline = NULL,
  allow_coverage_loss = FALSE
)
```

## Arguments

- data_dir:

  Persistent user directory also used by ordinary reads.

- force:

  Bypass daily attempt throttling.

- rebuild:

  Reparse all editions, including unchanged sources.

- timeout, retries, wait:

  Per-request timeout, bounded retry count and delay.

- max_bytes:

  Per-source response bound.

- max_total_bytes:

  Total downloaded raw bytes per transaction; also bounds staged raw
  bytes. All staging is temporary.

- max_releases:

  Maximum discovered editions (1 through 1,000).

- max_pdf_pages, max_text_bytes, pdftotext:

  See
  [`read_boj_outlook_raw()`](https://chartwell-macro.github.io/readboj/reference/read_boj_outlook_raw.md).

- deadline:

  Caller-owned absolute deadline; default thirty minutes.

- allow_coverage_loss:

  Explicit reviewed opt-in to removing existing logical scalar
  identities/targets from an edition. Default `FALSE` rejects
  partial-but-otherwise-valid revisions. When enabled, removed
  identities and original rows/receipts remain in revision history and
  the outcome reports the reduction. Use `force = TRUE` for a same-day
  retry after rejection.

## Value

A status list: `updated`, `unchanged`, or `throttled`, identities,
changed assets/editions, parse counts, bytes downloaded and publication
size. Failures raise a typed error and leave a `failed` local check
receipt.

## Details

A complete candidate is validated before an atomic commit. The package
bundle is read-only. Readers use the newest valid local generation,
falling back with an explicit warning if it is corrupt. One writer holds
a process lock; checks are throttled to once per UTC day unless forced
or the parser changed. Failed attempts are recorded separately and never
replace good data.

Raw staging is deleted on success/error and at the next locked run after
a crash. No raw documents are retained. At most three structured
generations and thirty check receipts remain. Revision history within
the current snapshot retains superseded tables and receipts, with a 32
MiB serialized-file bound; exceeding a bound fails without discarding
history.

## Examples

``` r
if (FALSE) { # \dontrun{
update_boj_outlook(data_dir = boj_outlook_data_dir(),
                   deadline = Sys.time() + 1800)
} # }
```
