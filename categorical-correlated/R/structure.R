# Data structure for correlated responses: wide → long, cluster summaries, missing data
# (checklist items 2, 4, 9–11, 15).

#' Wide to long: one row per cluster becomes one row per cluster × occasion.
#'
#' @param data   wide data, one row per cluster
#' @param cols   columns holding the repeated measurements, in time order (e.g. G1, G2, G3)
#' @param id     id column; NULL → create `id` from the row number (checklist item 2)
#' @param value  name of the new response column
#' @param time   name of the new time column
#' @param time_values labels for the occasions (default 1, 2, …)
cc_reshape_long <- function(data, cols, id = NULL, value = "y", time = "time", time_values = NULL) {
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0) stop("reshape：找不到欄位 ", paste(missing_cols, collapse = ", "))
  if (length(cols) < 2) stop("reshape：至少要 2 個重複測量的欄位。")
  time_values <- time_values %||% seq_along(cols)
  if (length(time_values) != length(cols)) stop("reshape：time_values 的個數必須和欄位個數相同。")
  notes <- character()
  if (is.null(id)) {
    id <- "id"
    if (id %in% names(data)) stop("reshape：資料已有 id 欄，請在 spec 指定 id。")
    data[[id]] <- seq_len(nrow(data))
    notes <- c(notes, sprintf("資料沒有 id 欄，依列號產生 id（1–%d），每一列視為一個叢集。", nrow(data)))
  }
  other <- setdiff(names(data), cols)
  pieces <- lapply(seq_along(cols), function(k) {
    piece <- data[, other, drop = FALSE]
    piece[[time]] <- time_values[k]
    piece[[value]] <- data[[cols[k]]]
    piece
  })
  long <- do.call(rbind, pieces)
  long <- long[order(long[[id]], match(long[[time]], time_values)), , drop = FALSE]
  rownames(long) <- NULL
  notes <- c(notes, sprintf("把 %s 轉成長格式：%s 欄為測量值，%s 欄為時間（%s），共 %d 列。",
                            paste(cols, collapse = "、"), value, time,
                            paste(sprintf("%s = %s", time_values, cols), collapse = "、"), nrow(long)))
  attr(long, "reshape_notes") <- notes
  attr(long, "id") <- id
  long
}

# Drop rows with missing values in the analysed columns (row by row: a cluster keeps its
# observed occasions) and summarise the clusters.
.prepare_long <- function(data, id, y, vars, method_family = c("gee", "glmm", "both")) {
  method_family <- match.arg(method_family)
  cols <- unique(c(id, y, vars))
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0) {
    stop(sprintf("資料中找不到欄位：%s。現有欄位：%s", paste(missing_cols, collapse = ", "),
                 paste(names(data), collapse = ", ")))
  }
  if (anyNA(data[[id]])) stop("id 欄有缺失值，無法判斷叢集。")
  complete <- stats::complete.cases(data[, cols, drop = FALSE])
  facts <- character()
  warnings <- list()
  n_all <- nrow(data)
  if (any(!complete)) {
    n_drop <- sum(!complete)
    share <- n_drop / n_all
    facts <- c(facts, sprintf("因 %s 有缺失，排除 %d 筆觀察值（占 %s）；其他時間點的資料仍保留。",
                              paste(setdiff(cols, id), collapse = "/"), n_drop, fmt_pct(share)))
    mech <- switch(method_family,
      gee = "GEE 需要缺失完全隨機（MCAR：缺不缺和任何變數都無關）才不會有偏誤。",
      glmm = "GLMM 只需要隨機缺失（MAR：缺不缺只和已觀察到的資料有關）。",
      both = "GEE 需要缺失完全隨機（MCAR），GLMM 只需要隨機缺失（MAR），所以缺失可能讓兩者的差異變大。")
    if (share >= 0.2) {
      warnings[[length(warnings) + 1]] <- cc_warning("MISSING_HIGH",
        sprintf("缺失比例 %s（≥ 20%%），結果可能高度受缺失影響。%s光看比例無法判斷是哪一種，請說明資料為什麼缺失。",
                fmt_pct(share), mech), "§9.5.1")
    } else if (share >= 0.05) {
      warnings[[length(warnings) + 1]] <- cc_warning("MISSING_DROPPED",
        sprintf("缺失比例 %s（≥ 5%%），可能影響結果。%s", fmt_pct(share), mech), "§9.5.1")
    }
  }
  d <- data[complete, , drop = FALSE]
  d <- d[order(d[[id]]), , drop = FALSE]   # geeglm / multgee need each cluster's rows together
  sizes <- table(d[[id]])
  n_clusters <- length(sizes)
  size_dist <- table(as.integer(sizes))
  facts <- c(facts, sprintf("共 %d 個叢集、%d 筆觀察值；每個叢集的筆數：%s。", n_clusters, nrow(d),
                            paste(sprintf("%s 筆 %d 個", names(size_dist), as.integer(size_dist)), collapse = "、")))
  n_single <- sum(sizes == 1)
  if (n_single > 0) {
    warnings[[length(warnings) + 1]] <- cc_warning("SINGLETON_CLUSTERS",
      sprintf("有 %d 個叢集只有 1 筆資料（占 %s）：它們對叢集內的效果（例如時間）沒有資訊。",
              n_single, fmt_pct(n_single / n_clusters)), "§9.2")
  }
  if (n_clusters < 2) stop("至少要有 2 個叢集。")
  list(data = d, facts = facts, warnings = warnings,
       clusters = list(n_clusters = n_clusters, n_obs = nrow(d),
                       sizes = stats::setNames(as.integer(size_dist), names(size_dist)),
                       n_singleton = n_single))
}

# Share of clusters (with ≥ 2 observations) whose responses are all the same (checklist 15).
.all_same_share <- function(d, id, y) {
  by_id <- split(as.character(d[[y]]), d[[id]])
  multi <- by_id[lengths(by_id) >= 2]
  if (length(multi) == 0) return(NA_real_)
  mean(vapply(multi, function(v) length(unique(v)) == 1, TRUE))
}

# Is the variable constant within every cluster? → between-cluster (e.g. sex),
# otherwise within-cluster (e.g. time). Used to explain GEE vs GLMM (§9.2.3, §10.2.5).
.cluster_level <- function(d, id, v) {
  varies <- tapply(as.character(d[[v]]), d[[id]], function(z) length(unique(z)) > 1)
  if (any(varies, na.rm = TRUE)) "within" else "between"
}

# Build the model frame columns: factors with the reference level first, or numeric scores.
#   numeric: variables the user confirmed to use as numeric scores (Part 2 rule, §4.3)
#   ref:     list(var = "level") reference category; default = first in code order
.build_predictors <- function(d, vars, numeric = character(), ref = list()) {
  info <- list()
  for (v in vars) {
    if (v %in% numeric) {
      x <- suppressWarnings(as.numeric(as.character(d[[v]])))
      if (anyNA(x[!is.na(d[[v]])])) stop(sprintf("%s 被設定為數值分數，但有非數字的值。", v))
      d[[v]] <- x
      info[[v]] <- list(type = "numeric")
    } else {
      f <- if (is.factor(d[[v]])) droplevels(d[[v]]) else code_order_factor(d[[v]])
      f <- droplevels(f)
      r <- ref[[v]] %||% levels(f)[1]
      if (!r %in% levels(f)) stop(sprintf("%s 的參考組「%s」不在資料中；現有類別：%s", v, r,
                                          paste(levels(f), collapse = ", ")))
      d[[v]] <- stats::relevel(factor(f, ordered = FALSE), ref = r)
      if (nlevels(d[[v]]) < 2) stop(sprintf("%s 只有 1 個類別，不能當解釋變數。", v))
      info[[v]] <- list(type = "factor", ref = r, levels = levels(d[[v]]))
    }
  }
  list(data = d, info = info)
}

# Which coefficients belong to each model term (for joint Wald tests). Uses the model matrix's
# `assign` attribute, so factor levels and interactions map correctly. For multgee's nominal
# model, coefficient names carry a ":<category>" suffix (e.g. "sexM:2"), stripped first.
.term_index <- function(coef_names, formula_rhs, d, nominal = FALSE) {
  mm <- stats::model.matrix(stats::as.formula(paste("~", formula_rhs)), data = d)
  labels <- attr(stats::terms(stats::as.formula(paste("~", formula_rhs))), "term.labels")
  col_term <- stats::setNames(labels[attr(mm, "assign")[attr(mm, "assign") > 0]],
                              colnames(mm)[attr(mm, "assign") > 0])
  base <- if (nominal) sub(":[0-9]+$", "", coef_names) else coef_names
  own <- lapply(stats::setNames(labels, labels), function(term) which(base %in% names(col_term)[col_term == term]))
  # A main effect that also appears in an interaction is tested together with those interaction
  # terms, the same hypothesis as the GLMM likelihood-ratio test that drops the term and its
  # interactions (first skill test: the two tests disagreed in meaning).
  out <- own
  for (term in labels[!grepl(":", labels)]) {
    inter <- labels[grepl(":", labels) & vapply(strsplit(labels, ":"), function(p) term %in% p, TRUE)]
    if (length(inter)) {
      out[[term]] <- sort(unique(c(own[[term]], unlist(own[inter]))))
      names(out)[names(out) == term] <- sprintf("%s (with %s)", term, paste(inter, collapse = ", "))
    }
  }
  out
}

.formula_rhs <- function(vars) if (length(vars)) paste(vars, collapse = " + ") else "1"
