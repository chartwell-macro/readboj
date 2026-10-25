.readboj_api_base <- "https://www.stat-search.boj.or.jp/api/v1"
.readboj_bulk_en <- "https://www.stat-search.boj.or.jp/info/dload_en.html"
.readboj_bulk_jp <- "https://www.stat-search.boj.or.jp/info/dload.html"
.readboj_tankan_en <- "https://www.boj.or.jp/en/statistics/tk/zenyo/index.htm"
.readboj_tankan_jp <- "https://www.boj.or.jp/statistics/tk/zenyo/index.htm"
.readboj_schema_version <- "1"
.readboj_max_codes <- 250L

`%||%` <- function(x, y) if (is.null(x)) y else x

