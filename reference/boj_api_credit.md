# Prescribed Bank of Japan API credit and terms links

Returns the credit text prescribed by the Bank of Japan API notice
together with the notice URL, the applicable Bank of Japan copyright
page, and the service-release notification address. This is a local
helper and performs no network request, credential lookup, or file
write. The URLs are references to current external terms; they are not
reproduced permissions and should be checked by the service operator
before redistribution or publication.

## Usage

``` r
boj_api_credit(language = "en")
```

## Arguments

- language:

  Output language, exactly `"en"` (default) or `"jp"`. Other values
  raise a readboj_parameter_error.

## Value

A named character list with exactly four elements: credit (the
prescribed English or Japanese service credit), api_notice (the official
API-notice PDF URL in that language), copyright (the corresponding Bank
of Japan copyright URL), and service_release_contact (the scalar address
post.rsd17@boj.or.jp). No provenance attribute is attached.

## Details

The release-notification address is supplied for the operator's use when
deploying a service based on the API. readboj does not send that
notification, grant permission to reuse Bank of Japan materials, or
decide whether a downstream use is commercial or otherwise permitted.
The package's bundled synthetic fixtures are not official BOJ data.

## See also

[`boj_databases()`](https://chartwell-macro.github.io/readboj/reference/boj_databases.md),
[`boj_provenance()`](https://chartwell-macro.github.io/readboj/reference/boj_provenance.md)

## Examples

``` r
credit <- boj_api_credit()
stopifnot(identical(names(credit),
  c("credit", "api_notice", "copyright", "service_release_contact")))
stopifnot(grepl("Time-Series Data Search", credit$credit, fixed = TRUE))
japanese <- boj_api_credit("jp")
stopifnot(grepl("API", japanese$credit, fixed = TRUE))
```
