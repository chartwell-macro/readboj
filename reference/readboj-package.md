# readboj: Auditable Access to Bank of Japan Statistics

readboj retrieves official Bank of Japan statistical responses while
preserving the exact source identity needed for reproducible analysis.
It normalizes observations and metadata into stable data frames, retains
raw response and semantic hashes, and exposes source, cache, parser, and
API details through
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md).

## Supported surfaces

The package supports the Bank of Japan Time-Series Data Search API
through
[`read_boj_series()`](https://chartwell-macro.github.io/readboj/reference/read_boj_series.md),
[`read_boj_layer()`](https://chartwell-macro.github.io/readboj/reference/read_boj_layer.md),
[`boj_metadata()`](https://chartwell-macro.github.io/readboj/reference/boj_metadata.md),
and
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md).
[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md)
provides the locally pinned bilingual database registry.
[`read_boj_snapshot()`](https://chartwell-macro.github.io/readboj/reference/read_boj_snapshot.md)
parses a local API response for deterministic offline workflows.

Selected official flat/bulk files can be discovered with
[`list_boj_bulk_files()`](https://chartwell-macro.github.io/readboj/reference/list_boj_bulk_files.md),
downloaded with
[`download_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/download_boj_bulk.md),
and read with
[`read_boj_bulk()`](https://chartwell-macro.github.io/readboj/reference/read_boj_bulk.md).
Dated Tankan comprehensive-data release pages and their XLS, XLSX, and
ZIP assets are exposed by
[`list_boj_tankan_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_releases.md),
[`list_boj_tankan_assets()`](https://chartwell-macro.github.io/readboj/reference/list_boj_tankan_assets.md),
[`download_boj_tankan_asset()`](https://chartwell-macro.github.io/readboj/reference/download_boj_tankan_asset.md),
and
[`read_boj_workbook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_workbook.md).
A portable metadata catalogue can be built and searched with
[`build_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/build_boj_catalogue_snapshot.md)
and
[`search_boj_catalogue_snapshot()`](https://chartwell-macro.github.io/readboj/reference/search_boj_catalogue_snapshot.md).

Published Outlook forecasts use
[`list_boj_outlook_releases()`](https://chartwell-macro.github.io/readboj/reference/list_boj_outlook_releases.md)
and
[`read_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/read_boj_outlook.md)
for saved local reads, with
[`update_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/update_boj_outlook.md)
and
[`maintain_boj_outlook()`](https://chartwell-macro.github.io/readboj/reference/maintain_boj_outlook.md)
as separate source/calendar maintenance routes. The complete bundled
Outlook history is official-source numeric data, unlike the small
synthetic parser fixtures. See the individual help topics.

## Output and provenance

Observation and metadata readers return ordinary data frames with stable
names, explicit date/value columns, and source identity in a
readboj_provenance attribute. JSON nulls and API CSV blank cells remain
distinguishable through the documented raw/status columns; bulk
`NA`/`ND` markers remain literal text. Bulk and workbook readers
preserve text values and workbook/archive structure rather than guessing
a time-series model. Use
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)
to inspect provenance; it does not revalidate a moved file or an
external URL.

## Network, cache, and filesystem behavior

Live operations use HTTPS and an allowlist of official Bank of Japan
hosts. They use bounded timeouts, retries, response sizes, pagination,
archive sizes, and result sizes. There are no startup downloads and no
credential prompts. Request snapshots are stored under
tools::R_user_dir("readboj", "cache") by default, or under the caller's
cache_dir/option. Cache objects are content-addressed, success-only, and
bounded by package options; use
[`boj_cache_prune()`](https://chartwell-macro.github.io/readboj/reference/boj_cache_prune.md)
for explicit local maintenance. The package writes only caller-selected
output directories, its managed cache, and temporary files under
tempdir. Set offline = TRUE on reader functions that support it to
require cached snapshots and avoid network access.

## Limits and failure modes

Safety bounds are intentional. Defaults include 30- or 60-second API
timeouts, depending on the operation, bounded retries, 128 MiB response
limits, 2 GiB/1,000-object cache limits, pagination and cell/row limits,
and bounded bulk/workbook archive limits. The large Tankan CO metadata
catalogue is not eagerly materialised unless explicitly allowed; use
[`search_boj_series()`](https://chartwell-macro.github.io/readboj/reference/search_boj_series.md)
for discovery. Invalid parameters, changed official schemas, unsafe
paths, validated cache corruption, identity mismatches, offline misses,
rate limits, authorization failures, transport failures, and
size/deadline violations raise typed readboj conditions. These checks
are fail-closed; callers should handle availability and upstream schema
changes explicitly. Unexpected base or dependency errors from manually
malformed local metadata or third-party files should be reported with
their input identity.

## Official sources and terms

The upstream service is the Bank of Japan Time-Series Data Search. The
package's API credit and current notice/copyright links are returned by
[`boj_api_credit()`](https://chartwell-macro.github.io/readboj/reference/boj_api_credit.md).
BOJ terms remain applicable to live responses and downloaded materials;
readboj does not grant permission to redistribute them. Bundled extdata
includes small synthetic fixtures for deterministic tests and examples,
plus the separately identified saved Outlook history. Outlook
publication/graphic rights and commercial reuse restrictions remain with
BOJ; this package does not establish permission to redistribute that
material. Package code is MIT licensed, copyright Chartwell Macro. That
package licence does not reassign rights in Bank of Japan data,
publications, services, or other upstream material. The package retains
the required third-party attribution in inst/NOTICE/bojapi-MIT.txt.

## See also

Useful links:

- <https://github.com/chartwell-macro/readboj>

- Report bugs at
  [mailto:chartwellmacro@gmail.com](mailto:chartwellmacro@gmail.com)

## Author

Chartwell Macro
