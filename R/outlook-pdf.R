outlook_pdf_coordinates <- function(path, max_bytes) {
  raw <- read_raw_file(path, max_bytes)
  doc <- tryCatch(xml2::read_xml(raw), error = function(e) readboj_abort(
    "Cannot parse Poppler bounding-box output.", "readboj_parse_error", parent = e))
  xml2::xml_ns_strip(doc)
  pages <- xml2::xml_find_all(doc, ".//page")
  lapply(seq_along(pages), function(p) {
    nodes <- xml2::xml_find_all(pages[[p]], ".//line")
    lines <- lapply(seq_along(nodes), function(i) {
      words <- xml2::xml_find_all(nodes[[i]], "./word")
      data <- data.frame(text = xml2::xml_text(words),
        x0 = as.numeric(xml2::xml_attr(words, "xMin")),
        y0 = as.numeric(xml2::xml_attr(words, "yMin")),
        x1 = as.numeric(xml2::xml_attr(words, "xMax")),
        y1 = as.numeric(xml2::xml_attr(words, "yMax")))
      list(text = outlook_space(paste(data$text, collapse = " ")),
        x0 = min(data$x0), y0 = min(data$y0), x1 = max(data$x1), y1 = max(data$y1), words = data)
    })
    lines[order(vapply(lines, `[[`, numeric(1L), "y0"), vapply(lines, `[[`, numeric(1L), "x0"))]
  })
}

outlook_pdf_line_frame <- function(lines) {
  data.frame(text = vapply(lines, `[[`, character(1L), "text"),
    x0 = vapply(lines, `[[`, numeric(1L), "x0"),
    y0 = vapply(lines, `[[`, numeric(1L), "y0"),
    x1 = vapply(lines, `[[`, numeric(1L), "x1"),
    y1 = vapply(lines, `[[`, numeric(1L), "y1"))
}

outlook_pdf_labels <- function(lines, left_boundary, year_context) {
  candidates <- lines[lines$x0 < left_boundary, , drop = FALSE]
  result <- list()
  i <- 1L
  year <- year_context
  last_comparison <- "current"
  last_vintage <- NA_character_
  while (i <= nrow(candidates)) {
    line <- candidates[i, ]
    label <- line$text
    current <- grepl("^[Ff]iscal +[0-9]{4}$", label)
    prior <- grepl("^[Ff]orecasts? made in|^[Rr]ange of forecasts", label)
    actual <- grepl("^[\"']?[Aa]ctual[\"']?$", label)
    adjusted <- grepl("^[Ee]xcluding the effects", label)
    if (!current && !prior && !actual && !adjusted) { i <- i + 1L; next }
    start <- i
    if (prior && !grepl("[A-Za-z]+ +[0-9]{4}", sub("[Ff]orecasts? made in", "", label))) {
      while (i < nrow(candidates) && i - start < 4L) {
        i <- i + 1L
        label <- paste(label, candidates$text[[i]])
        if (grepl("[A-Za-z]+ +[0-9]{4}", sub("[Ff]orecasts? made in", "", label))) break
      }
    }
    if (adjusted && !grepl("consumption tax hike", label)) {
      if (i == nrow(candidates)) outlook_schema_error("Incomplete tax-adjusted row label.")
      i <- i + 1L
      label <- paste(label, candidates$text[[i]])
    }
    if (current) year <- outlook_years(label)[[1L]]
    if (is.na(year)) outlook_schema_error("PDF table row has no fiscal-year context.", source_label = label)
    if (!adjusted) {
      last_comparison <- if (prior) "prior" else "current"
      last_vintage <- if (prior) outlook_vintage(sub("^.*[Ff]orecasts? made in +", "", label)) else NA_character_
    }
    result[[length(result) + 1L]] <- data.frame(label = label, fiscal_year = year,
      comparison = last_comparison, vintage = last_vintage, adjusted = adjusted,
      y0 = candidates$y0[[start]], y1 = candidates$y1[[i]])
    i <- i + 1L
  }
  if (!length(result)) outlook_schema_error("No fiscal forecast rows identified in PDF table.")
  out <- do.call(rbind, result)
  out$center <- (out$y0 + out$y1) / 2
  if (any(diff(out$center) <= 0)) outlook_schema_error("Overlapping PDF row identities.")
  out
}

outlook_pdf_fragments <- function(lines, left_boundary) {
  result <- list()
  for (line in lines) {
    words <- line$words
    words <- words[(words$x0 + words$x1) / 2 > left_boundary, , drop = FALSE]
    if (!nrow(words)) next
    # Decimal printed numbers, range connectors and brackets are table content.
    # Superscript integer footnote references are retained in source geometry,
    # but do not become scalar observations.
    allowed <- !grepl("[A-Za-z]", words$text) | words$text == "to"
    words <- words[allowed & !grepl("^[0-9]+$", words$text), , drop = FALSE]
    if (!nrow(words)) next
    words <- words[order(words$x0), , drop = FALSE]
    gap <- c(Inf, words$x0[-1L] - words$x1[-nrow(words)])
    group <- cumsum(gap > max(10, stats::median(words$y1 - words$y0) * 1.5))
    for (g in unique(group)) {
      w <- words[group == g, , drop = FALSE]
      text <- outlook_space(paste(w$text, collapse = " "))
      marker <- gsub("[\u2013\u2212\u2014]", "-", text, perl = TRUE)
      if (!grepl("[0-9]\\.[0-9]", text) && !marker %in% c("-", "--")) next
      result[[length(result) + 1L]] <- data.frame(text = text,
        x0 = min(w$x0), y0 = min(w$y0), x1 = max(w$x1), y1 = max(w$y1))
    }
  }
  if (!length(result)) outlook_schema_error("No numeric PDF table fragments found.")
  do.call(rbind, result)
}

parse_outlook_table <- function(extracted, publication, deadline) {
  deadline_remaining(deadline)
  if (is.null(extracted$coordinates)) outlook_schema_error("PDF extraction supplied no table coordinates.")
  result <- list()
  table_count <- 0L
  notes_all <- list()
  for (page in seq_along(extracted$coordinates)) {
    deadline_remaining(deadline)
    lines <- extracted$coordinates[[page]]
    frame <- outlook_pdf_line_frame(lines)
    titles <- grepl("^Forecasts of (the )?[Mm]ajority of (the )?Policy Board [Mm]embers", frame$text)
    if (!any(titles)) next
    if (!grepl("[Yy]/[Yy] *% *(chg|change)", extracted$pages[[page]])) outlook_schema_error(
      "Unrecognized annual percentage-change units in PDF table.")
    gdp <- which(frame$text == "Real GDP")
    gdp <- gdp[frame$y0[gdp] > min(frame$y0[titles])]
    if (!length(gdp)) outlook_schema_error("Forecast table heading has no identified Real GDP column.")
    for (hi in seq_along(gdp)) {
      deadline_remaining(deadline)
      header_i <- gdp[[hi]]
      hy <- frame$y0[[header_i]]
      next_header <- if (hi < length(gdp)) frame$y0[[gdp[[hi + 1L]]]] else Inf
      above <- frame[frame$y1 < hy, , drop = FALSE]
      hints <- which(grepl("^Forecasts of (the )?[Mm]ajority|forecasts of all|ranges? (shown )?below.*all",
        above$text, ignore.case = TRUE))
      if (!length(hints)) next
      hint <- above[utils::tail(hints, 1L), ]
      scope <- if (grepl("forecasts of all|ranges? (shown )?below.*all", hint$text,
        ignore.case = TRUE)) "all_members" else "majority"
      near <- frame[frame$y0 > hy & frame$y0 < next_header, , drop = FALSE]
      numbers <- near[grepl("[0-9]\\.[0-9]", near$text), , drop = FALSE]
      if (!nrow(numbers)) next
      first_body <- min(numbers$y0)
      label_y <- near$y0[grepl("^[Ff]iscal +[0-9]{4}$|^[Ff]orecasts? made in|^[Aa]ctual$", near$text)]
      first_body <- min(c(first_body, label_y))
      header_start <- max(hint$y1, hy - 70)
      header_area <- frame[frame$y0 > header_start & frame$y0 < first_body, , drop = FALSE]
      anchors <- header_area[grepl("^Real GDP$|^Domestic (CGPI|WPI|WP)$|^CPI( |$)|^[Ee]xcluding the effects", header_area$text), , drop = FALSE]
      anchors <- anchors[order((anchors$x0 + anchors$x1) / 2), , drop = FALSE]
      if (nrow(anchors) < 2L || nrow(anchors) > 6L) outlook_schema_error(
        "Cannot identify semantic PDF measure headers.", pdf_page = page)
      centers <- (anchors$x0 + anchors$x1) / 2
      if (any(diff(centers) < 35)) outlook_schema_error("Overlapping PDF measure columns.")
      headers <- vapply(seq_along(centers), function(j) {
        x <- (header_area$x0 + header_area$x1) / 2
        assignment <- vapply(x, function(value) which.min(abs(value - centers)), integer(1L))
        pieces <- header_area[assignment == j & !grepl("[Yy]/[Yy]|Appendix", header_area$text), ]
        outlook_space(paste(pieces$text[order(pieces$y0)], collapse = " "))
      }, character(1L))
      for (h in headers) outlook_measure(h)
      left_boundary <- centers[[1L]] - min(diff(centers)) * .6
      stops <- frame$y0[frame$y0 > first_body &
        (grepl("^Notes? *:", frame$text) | grepl("^Forecasts of (the )?[Mm]ajority", frame$text))]
      end <- min(c(next_header, stops, Inf))
      body_indexes <- which(frame$y0 >= first_body - 1 & frame$y0 < end)
      body <- frame[body_indexes, , drop = FALSE]
      caption_years <- outlook_years(hint$text)
      year_context <- if (length(caption_years) == 1L) caption_years[[1L]] else NA_integer_
      row_labels <- outlook_pdf_labels(body, left_boundary, year_context)
      numeric <- outlook_pdf_fragments(lines[body_indexes], left_boundary)
      numeric$row <- vapply((numeric$y0 + numeric$y1) / 2, function(y) {
        which.min(abs(y - row_labels$center))
      }, integer(1L))
      # The maximum accepted distance is tied to actual row geometry, not dates.
      if (nrow(row_labels) > 1L && any(abs((numeric$y0 + numeric$y1) / 2 -
          row_labels$center[numeric$row]) > max(diff(row_labels$center)) / 2 + 3)) {
        outlook_schema_error("Numeric PDF content cannot be assigned to a fiscal row.")
      }
      numeric$column <- vapply((numeric$x0 + numeric$x1) / 2, function(x) which.min(abs(x - centers)), integer(1L))
      numeric$span <- as.character(numeric$column)
      # A printed cell shared across headline and tax-adjusted CPI columns has
      # its own source geometry. It applies to both headers, as HTML colspan
      # does; it is never inferred from equality of numeric values.
      tax <- which(grepl("consumption", headers, ignore.case = TRUE))
      if (length(tax) == 1L && tax > 1L) {
        previous <- tax - 1L
        midpoint <- mean(centers[c(previous, tax)])
        distance <- centers[[tax]] - centers[[previous]]
        x <- (numeric$x0 + numeric$x1) / 2
        shared <- abs(x - midpoint) < distance * .2 &
          abs(x - centers[numeric$column]) > distance * .25
        numeric$span[shared] <- paste(previous, tax, sep = ":")
      }
      table_count <- table_count + 1L
      page_text <- extracted$pages[[page]]
      notes <- outlook_space(page_text)
      if (!grepl("highest[^.]*lowest[^.]*exclud|exclud[^.]*highest[^.]*lowest", notes,
          ignore.case = TRUE)) outlook_schema_error("The source does not define its member-range construction.")
      notes_all[[as.character(table_count)]] <- notes
      printed <- frame[grepl("^[0-9]+$", frame$text), , drop = FALSE]
      printed_page <- if (nrow(printed)) printed$text[[which.max(printed$y0)]] else NA_character_
      for (r in seq_len(nrow(row_labels))) {
        row <- row_labels[r, ]
        pieces <- numeric[numeric$row == r, , drop = FALSE]
        if (!nrow(pieces)) outlook_schema_error("A fiscal PDF row has no numeric cells.")
        seen <- unique(unlist(lapply(pieces$span, function(span) {
          z <- as.integer(strsplit(span, ":", fixed = TRUE)[[1L]])
          seq.int(min(z), max(z))
        })))
        mandatory <- if (row$adjusted) seq_along(headers)[grepl("CPI|CGPI", headers)] else {
          seq_along(headers)[!grepl("consumption", headers, ignore.case = TRUE)]
        }
        if (any(!mandatory %in% seen)) outlook_schema_error(
          "A required measure cell is missing from a PDF fiscal row.", source_label = row$label)
        for (span in unique(pieces$span)) {
          fragments <- pieces[pieces$span == span, , drop = FALSE]
          fragments <- fragments[order(fragments$y0, fragments$x0), ]
          cell <- outlook_space(paste(fragments$text, collapse = " "))
          columns <- as.integer(strsplit(span, ":", fixed = TRUE)[[1L]])
          columns <- seq.int(min(columns), max(columns))
          for (j in columns) {
            header <- headers[[j]]
            if (row$adjusted) header <- paste(header, row$label)
            result[[length(result) + 1L]] <- outlook_observation(cell, header,
              row$fiscal_year, row$label, row$comparison,
              if (row$comparison == "prior") row$vintage else publication$release,
              publication, scope, table_count, r, j, notes,
              paste0("pdf-", page, "/table-", table_count, "/row-", r, "/column-", span),
              page, printed_page, column_span = span,
              bbox = c(min(fragments$x0), min(fragments$y0), max(fragments$x1), max(fragments$y1)))
          }
        }
      }
    }
  }
  out <- outlook_finish(result, deadline)
  attr(out, "outlook_notes") <- notes_all
  attr(out, "outlook_format_family") <- "semantic-pdf-tables"
  out
}
