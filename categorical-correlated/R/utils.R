# Shared building blocks for the categorical-correlated engine (Part 3).
#
# Same result structure as Part 1 (categorical-association), so the three Skills read alike:
# numbers live only in `estimates`, `tests` and `tables`; `facts` are fixed-template sentences
# built from those numbers, so the language model can rephrase them without computing anything.

cc_result <- function(method, method_label, book_ref, tier,
                      estimates = data.frame(), tests = data.frame(),
                      tables = list(), warnings = list(), facts = character(),
                      notes = list()) {
  structure(
    list(method = method, method_label = method_label, book_ref = book_ref, tier = tier,
         estimates = estimates, tests = tests, tables = tables,
         warnings = warnings, facts = facts, notes = notes),
    class = "cc_result"
  )
}

# A warning always carries the textbook section that justifies it (codes: checklist.md).
cc_warning <- function(code, message, book_ref) {
  list(code = code, message = message, book_ref = book_ref)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

fmt_num <- function(x, digits = 3) formatC(x, digits = digits, format = "f")

# Used as "P %s" → "P = 0.012" or "P < 0.001".
fmt_p <- function(p) {
  vapply(p, function(v) {
    if (is.na(v)) return("= NA")
    if (v < 0.001) return("< 0.001")
    paste("=", formatC(v, digits = 3, format = "f"))
  }, "", USE.NAMES = FALSE)
}

fmt_pct <- function(x, accuracy = 0.1) scales::percent(x, accuracy = accuracy)

# Categories in character-code order (numbers numerically), independent of locale.
code_order_factor <- function(v) {
  if (is.factor(v)) return(v)
  factor(v, levels = sort(unique(v[!is.na(v)]), method = "radix"))
}

# JSON has no infinity; write "Inf"/"-Inf" so it is not read as missing.
.mark_infinite <- function(x) {
  if (is.data.frame(x)) { x[] <- lapply(x, .mark_infinite); return(x) }
  if (is.list(x)) return(lapply(x, .mark_infinite))
  if (is.numeric(x) && any(is.infinite(x))) {
    return(lapply(x, function(v) if (is.infinite(v)) (if (v > 0) "Inf" else "-Inf") else v))
  }
  x
}

cc_to_json <- function(result, path = NULL) {
  out <- unclass(result)
  out$tables <- lapply(result$tables, function(t) {
    if (is.table(t) || is.matrix(t)) {
      m <- as.matrix(t)
      list(rows = rownames(m), cols = colnames(m), values = unname(split(m, row(m))))
    } else t
  })
  json <- jsonlite::toJSON(.mark_infinite(out), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null")
  if (!is.null(path)) writeLines(json, path, useBytes = TRUE)
  invisible(json)
}

print.cc_result <- function(x, ...) {
  cat(x$method_label, " [", x$book_ref, ", tier ", x$tier, "]\n", sep = "")
  if (length(x$facts)) cat(paste0("- ", x$facts), sep = "\n")
  if (length(x$warnings)) {
    cat("Warnings:\n")
    for (w in x$warnings) cat("  ! ", w$message, " (", w$book_ref, ")\n", sep = "")
  }
  invisible(x)
}

# Read a user's data file: textbook .dat, Excel, UTF-8 or Big5 CSV; delimiter = the most
# frequent of comma, semicolon, tab in the header line (UCI student data uses semicolons).
read_data <- function(path) {
  if (grepl("\\.dat$", path, ignore.case = TRUE)) {
    return(utils::read.table(path, header = TRUE, stringsAsFactors = FALSE))
  }
  if (grepl("\\.xlsx?$", path, ignore.case = TRUE)) {
    return(as.data.frame(readxl::read_excel(path)))
  }
  raw <- readBin(path, "raw", file.info(path)$size)
  text <- rawToChar(raw)
  encoding <- if (validUTF8(text)) "UTF-8" else "BIG5"
  header <- sub("[\r\n].*$", "", text)
  counts <- vapply(c(",", ";", "\t"), function(s) lengths(regmatches(header, gregexpr(s, header, fixed = TRUE))), 0)
  as.data.frame(readr::read_delim(path, delim = names(which.max(counts)),
                                  locale = readr::locale(encoding = encoding),
                                  show_col_types = FALSE, progress = FALSE))
}

# New categorical variables requested by the user (Skill `recode`), computed here so the
# language model never derives a value. Same format as Part 1:
#   list(pass = list(from = "G", breaks = 10, labels = c("fail", "pass")))
#   list(Walc2 = list(from = "Walc", map = list("1" = "low", "2" = "low", ...)))
cc_recode <- function(data, recode) {
  notes <- character()
  for (nm in names(recode)) {
    r <- recode[[nm]]
    if (is.null(r$from) || !r$from %in% names(data)) stop("recode：找不到來源欄位 ", r$from)
    src <- data[[r$from]]
    if (!is.null(r$breaks)) {
      br <- sort(as.numeric(unlist(r$breaks)))
      labs <- unlist(r$labels)
      if (length(labs) != length(br) + 1) stop("recode：", nm, " 的 labels 數目必須比 breaks 多 1。")
      data[[nm]] <- factor(cut(as.numeric(src), breaks = c(-Inf, br, Inf), labels = labs, right = FALSE),
                           levels = labs)
      ranges <- c(sprintf("< %s", br[1]),
                  if (length(br) > 1) sprintf("%s – < %s", utils::head(br, -1), br[-1]) else NULL,
                  sprintf("≥ %s", br[length(br)]))
      notes <- c(notes,
                 sprintf("新變數 %s 由 %s 轉換：%s。", nm, r$from,
                         paste(sprintf("%s → %s", ranges, labs), collapse = "；")),
                 sprintf("提醒：把連續的 %s 切成類別會損失資訊，結論可能隨切點改變。", r$from))
    } else if (!is.null(r$map)) {
      map <- unlist(r$map)
      vals <- as.character(src)
      unmapped <- setdiff(unique(vals[!is.na(vals)]), names(map))
      if (length(unmapped) > 0) stop("recode：", nm, " 的 map 缺少這些原始值：", paste(unmapped, collapse = ", "))
      data[[nm]] <- factor(unname(map[vals]), levels = unique(unname(map)))
      notes <- c(notes, sprintf("新變數 %s 由 %s 合併類別：%s。", nm, r$from,
                                paste(sprintf("%s → %s", names(map), map), collapse = "；")))
    } else {
      stop("recode：", nm, " 需要 breaks（切點）或 map（類別對應）。")
    }
  }
  attr(data, "recode_notes") <- notes
  data
}

# Markdown table writer shared by the report.
md_table <- function(df, digits = 4) {
  if (is.null(df) || nrow(df) == 0) return(character())
  fmt <- function(v) {
    if (!is.numeric(v)) return(as.character(v))
    finite <- v[is.finite(v)]
    if (length(finite) && all(finite == round(finite))) {        # counts, df: no decimals
      return(ifelse(is.na(v), "—", ifelse(is.infinite(v), ifelse(v > 0, "∞", "−∞"), formatC(v, format = "d", big.mark = ""))))
    }
    ifelse(is.na(v), "—", ifelse(is.infinite(v), ifelse(v > 0, "∞", "−∞"),
      ifelse(abs(v) < 1e-3 & v != 0, formatC(v, digits = 3, format = "e"),
             formatC(v, digits = digits, format = "f"))))
  }
  cells <- as.data.frame(lapply(df, fmt), check.names = FALSE, stringsAsFactors = FALSE)
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(cells, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

# Wald test that a set of coefficients is jointly 0, using a (robust) covariance matrix.
# Used for each explanatory term with all other terms in the model (not sequential).
.joint_wald <- function(coefs, vc, idx) {
  b <- coefs[idx]
  V <- vc[idx, idx, drop = FALSE]
  stat <- as.numeric(t(b) %*% solve(V, b))
  c(statistic = stat, df = length(idx), p_value = stats::pchisq(stat, length(idx), lower.tail = FALSE))
}

# Capture warnings from a model fit (e.g. lme4 convergence messages) instead of losing them.
.with_warnings <- function(expr) {
  msgs <- character()
  value <- withCallingHandlers(expr, warning = function(w) {
    msgs <<- c(msgs, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  list(value = value, warnings = msgs)
}
