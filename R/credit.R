#' Prescribed Bank of Japan API credit and terms links
#'
#' Returns the credit text prescribed by the Bank of Japan API notice together
#' with the notice URL, the applicable Bank of Japan copyright page, and the
#' service-release notification address. This is a local helper and performs no
#' network request, credential lookup, or file write. The URLs are references to
#' current external terms; they are not reproduced permissions and should be
#' checked by the service operator before redistribution or publication.
#'
#' The release-notification address is supplied for the operator's use when
#' deploying a service based on the API. readboj does not send that notification,
#' grant permission to reuse Bank of Japan materials, or decide whether a
#' downstream use is commercial or otherwise permitted. The package's bundled
#' synthetic fixtures are not official BOJ data.
#'
#' @param language Output language, exactly `"en"` (default) or `"jp"`.
#'   Other values raise a readboj_parameter_error.
#' @return A named character list with exactly four elements: credit (the
#'   prescribed English or Japanese service credit), api_notice (the official
#'   API-notice PDF URL in that language), copyright (the corresponding Bank of
#'   Japan copyright URL), and service_release_contact (the scalar address
#'   post.rsd17@boj.or.jp). No provenance attribute is attached.
#' @seealso [boj_databases()], [boj_provenance()]
#' @family attribution functions
#' @examples
#' credit <- boj_api_credit()
#' stopifnot(identical(names(credit),
#'   c("credit", "api_notice", "copyright", "service_release_contact")))
#' stopifnot(grepl("Time-Series Data Search", credit$credit, fixed = TRUE))
#' japanese <- boj_api_credit("jp")
#' stopifnot(grepl("API", japanese$credit, fixed = TRUE))
#' @export
boj_api_credit <- function(language = "en") {
  language <- normalize_language(language, both = FALSE)
  credit <- if (language == "en") {
    'This service uses the API provided by the "Bank of Japan Time-Series Data Search." The Bank of Japan does not guarantee the content of the service.'
  } else {
    '\u672c\u30b5\u30fc\u30d3\u30b9\u306f\u3001\u65e5\u672c\u9280\u884c\u300c\u6642\u7cfb\u5217\u7d71\u8a08\u30c7\u30fc\u30bf\u691c\u7d22\u30b5\u30a4\u30c8\u300d\u306eAPI\u3092\u5229\u7528\u3057\u3066\u3044\u307e\u3059\u3002\u672c\u30b5\u30fc\u30d3\u30b9\u306e\u5185\u5bb9\u306b\u3064\u3044\u3066\u3001\u65e5\u672c\u9280\u884c\u306f\u4e00\u5207\u306e\u8cac\u4efb\u3092\u8ca0\u3044\u307e\u305b\u3093\u3002'
  }
  list(credit = credit,
    api_notice = if (language == "en")
      "https://www.stat-search.boj.or.jp/info/api_notice_en.pdf" else
      "https://www.stat-search.boj.or.jp/info/api_notice.pdf",
    copyright = if (language == "en")
      "https://www.boj.or.jp/en/about/copyright.htm" else
      "https://www.boj.or.jp/about/copyright.htm",
    service_release_contact = "post.rsd17@boj.or.jp")
}
