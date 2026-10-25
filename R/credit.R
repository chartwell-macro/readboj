#' Prescribed Bank of Japan API credit and terms links
#'
#' @param language `"en"` or `"jp"`.
#' @return A named list. The release notification and permission decisions
#'   remain the service operator's responsibility.
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

