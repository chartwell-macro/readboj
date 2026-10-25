# Parse a local Bank of Japan response snapshot

Parses one saved Bank of Japan (BOJ) response body with the same
normalization used by the network-facing readers. This function is fully
offline: it never opens a network connection, writes to the readboj
cache, or changes the source file. The package's small `inst/extdata`
examples are deterministic synthetic fixtures, not official BOJ
observations.

## Usage

``` r
read_boj_snapshot(
  path,
  type = c("data_json", "data_csv", "metadata_csv"),
  db,
  language = "en",
  encoding = "UTF-8",
  max_bytes = 128 * 1024^2,
  max_rows = 50000L
)
```

## Arguments

- path:

  Character path to an existing regular local response-body file. The
  returned provenance records its normalized path and exact SHA-256.

- type:

  Response kind: `"data_json"`, `"data_csv"`, or `"metadata_csv"`. The
  default expression selects `"data_json"`.

- db:

  BOJ database identifier used to populate the normalized `db` column;
  it is normalized to uppercase after validation.

- language:

  For `type = "data_csv"`, response language `"en"` or `"jp"`; Japanese
  CSV is decoded as CP932. It is still validated for other types but
  does not alter their parsing.

- encoding:

  Character encoding passed to the metadata CSV reader when
  `type = "metadata_csv"`; use `"UTF-8"` or `"CP932"` for the supported
  BOJ encodings.

- max_bytes:

  Positive maximum input bytes checked before parsing. The default is
  128 MiB; oversized snapshots raise `readboj_size_error`.

- max_rows:

  Positive whole-number maximum rows for `data_csv` and `metadata_csv`.
  The default is 50,000; it is ignored for `data_json`.

## Value

A base `data.frame` with `stringsAsFactors = FALSE`, row names reset,
and a `readboj_provenance` attribute containing
`source = "local response snapshot"`, the normalized `path`,
`raw_sha256`, `semantic_sha256`, byte count, parser schema and package
version. For `type = "data_json"` or `"data_csv"`, the exact columns, in
order, are character `db`, `series_code`, `name_en`, `name_jp`,
`unit_en`, `unit_jp`, `frequency`, `category_en`, `category_jp`; `Date`
`last_update`; character `period`; `Date` `date`; numeric `value`; and
character `raw_value` and `value_status`. `date` is inferred from the
frequency/period pair and may be `NA`; JSON nulls use
`value_status = "null"`, while CSV blank values use
`value_status = "blank"`. For `type = "metadata_csv"`, the exact
columns, in order, are character `db`, `series_code`, `name_jp`,
`name_en`, `unit_jp`, `unit_en`, `frequency`, `category_jp`,
`category_en`; integer `layer1`–`layer5`; character `start_time` and
`end_time`; `Date` `last_update`; character `notes_jp` and `notes_en`;
and logical `is_series`. The metadata parser always retains both
language columns. `semantic_sha256` excludes the volatile JSON `DATE`
field for JSON input, canonicalizes the decoded CSV `DATE` line for
observation CSV input, and is `NA` for metadata CSV input; `raw_sha256`
always covers the exact file bytes.

## Details

`type = "data_json"` parses an API JSON response, `type = "data_csv"`
parses an observation CSV, and `type = "metadata_csv"` parses a five-row
preamble followed by a metadata CSV. The default `type` selects
`"data_json"`. `language` is validated for every call and selects CP932
for Japanese observation CSVs; it is otherwise ignored for JSON and
metadata snapshots. `encoding` is used for metadata CSV decoding;
`"UTF-8"` and `"CP932"` cover the package fixtures and official routes.

The file size is checked against `max_bytes` before parsing. For CSV
inputs, `max_rows` is an inclusive materialisation bound; it is not used
for JSON responses because JSON observations are already bounded by the
response body and parser structure. For `data_json` and `data_csv`,
non-success API statuses, malformed schemas and duplicate
`db`/`series_code`/`period` identities fail closed rather than silently
dropping or collapsing rows. A `metadata_csv` input is expected to
contain the five-row BOJ preamble and is parsed as a tabular metadata
file; its preamble is skipped without interpreting an API status field.
Missing JSON values remain rows with an explicit status marker, and CSV
blank markers remain observable in `raw_value`.

## Errors and side effects

Missing paths, directories, invalid database/language values, oversized
inputs, known observation-status/schema/identity failures, and metadata
row limits are checked by the package and use typed `readboj_*_error`
conditions where applicable. Unsupported `type` values and some
low-level malformed or encoding/bound inputs may instead retain base-R
or dependency errors and warnings. The function only reads `path`; it
does not perform network I/O, create cache directories, or write files.

## Examples

``` r
json_path <- system.file("extdata", "api-data-page-1.json", package = "readboj")
json_data <- read_boj_snapshot(json_path, type = "data_json", db = "FM08")
json_data[c("series_code", "period", "value", "value_status")]
#>   series_code period  value value_status
#> 1    SYNTHM01 202601 101.25     observed
#> 2    SYNTHM01 202602     NA         null
#> 3    SYNTHM01 202603 103.75     observed

csv_path <- system.file("extdata", "api-data-en-page-1.csv", package = "readboj")
csv_data <- read_boj_snapshot(csv_path, type = "data_csv", db = "FM08")
csv_data[c("series_code", "period", "value", "value_status")]
#>   series_code period  value value_status
#> 1    SYNTHM01 202601 101.25     observed
#> 2    SYNTHM01 202602     NA        blank
#> 3    SYNTHM01 202603 103.75     observed

metadata_path <- system.file(
  "extdata", "metadata-bilingual-utf8.csv", package = "readboj"
)
metadata <- read_boj_snapshot(
  metadata_path, type = "metadata_csv", db = "FM08", encoding = "UTF-8"
)
metadata[c("series_code", "name_en", "name_jp", "is_series")]
#>   series_code                 name_en      name_jp is_series
#> 1                   Synthetic heading     合成階層     FALSE
#> 2    SYNTHM01 Synthetic monthly index 合成月次指数      TRUE
#> 3    SYNTHM02  Synthetic monthly rate 合成月次金利      TRUE
```
