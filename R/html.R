html_links <- function(path, base_url) {
  document <- tryCatch(xml2::read_html(path, encoding = "UTF-8"),
    error = function(e) readboj_abort(paste0("Could not parse official HTML: ", conditionMessage(e)),
      "readboj_schema_error", parent = e))
  nodes <- xml2::xml_find_all(document, ".//a[@href]")
  href <- xml2::xml_attr(nodes, "href")
  label <- trimws(gsub("[[:space:]]+", " ", xml2::xml_text(nodes)))
  keep <- !is.na(href) & nzchar(href)
  data.frame(label = label[keep], href = href[keep],
    url = xml2::url_absolute(href[keep], base_url), stringsAsFactors = FALSE)
}

