# Stage 3: describe the question's variables and compute every number the checklist needs
# (check.json), before any method is chosen. No test is run here.
#
# question (same field names as spec.json):
#   paired: list(mode = "paired", y1, y2, levels, success)
#   model : list(mode = "model", id, y, time, x, success, levels, reshape, recode)

cc_describe <- function(data, q) {
  mode <- q$mode %||% if (!is.null(q$y1)) "paired" else "model"
  if (mode == "paired") .describe_paired(data, q) else .describe_model(data, q)
}

.describe_paired <- function(data, q) {
  levels <- if (is.list(q$levels) && !is.null(names(q$levels))) q$levels[[q$y1]] else q$levels
  prep <- .prepare_paired(data, q$y1, q$y2, levels)
  tab <- prep$tab
  k <- nrow(tab); n <- sum(tab)
  check <- list(mode = "paired", y1 = q$y1, y2 = q$y2, n_pairs = n,
                n_dropped = nrow(data) - n, missing_share = (nrow(data) - n) / nrow(data),
                categories = prep$levels, n_categories = k,
                same_categories = !any(vapply(prep$warnings, `[[`, "", "code") == "NOT_SQUARE"),
                diagonal_share = sum(diag(tab)) / n,
                warnings = prep$warnings)
  facts <- c(prep$facts, sprintf("兩次回答相同（對角線）的有 %d 人（%s）。", sum(diag(tab)), fmt_pct(sum(diag(tab)) / n)))
  if (k == 2) {
    success <- q$success %||% rownames(tab)[1]
    ord <- c(success, setdiff(rownames(tab), success)); tab2 <- tab[ord, ord]
    check$n12 <- tab2[1, 2]; check$n21 <- tab2[2, 1]; check$n_discordant <- tab2[1, 2] + tab2[2, 1]
    facts <- c(facts, sprintf("回答改變的人：n12 = %d、n21 = %d，共 %d 人（McNemar 的常態近似需要 > 10，§8.1.1）。",
                              check$n12, check$n21, check$n_discordant))
  } else {
    d <- .qs_data(tab)
    empty <- d[d$nij + d$nji == 0, ]
    check$empty_pairs <- if (nrow(empty)) sprintf("%s↔%s", empty$i, empty$j) else character()
    check$off_diagonal_min <- min(d$nij + d$nji)
    if (nrow(empty)) facts <- c(facts, sprintf("這些類別之間沒有人改變：%s。", paste(check$empty_pairs, collapse = "、")))
  }
  list(check = check, facts = facts, tables = list(counts = tab, marginal = .marginal_table(tab, q$y1, q$y2)),
       plots = list(square_table = .plot_square(tab), marginals = .plot_marginals(tab)))
}

.describe_model <- function(data, q) {
  x <- q$x %||% character()
  vars <- unique(c(q$time, x))
  prep <- .prepare_long(data, q$id, q$y, vars, "both")
  d <- prep$data
  yv <- as.character(d[[q$y]])
  lv <- if (!is.null(q$levels)) as.character(unlist(if (is.list(q$levels) && !is.null(names(q$levels))) q$levels[[q$y]] else q$levels))
        else levels(code_order_factor(d[[q$y]]))
  counts <- table(factor(yv, levels = lv))
  d$.cc_id <- d[[q$id]]
  check <- list(mode = "model", id = q$id, y = q$y, time = q$time, x = x,
                n_obs = nrow(d), n_dropped = nrow(data) - nrow(d), missing_share = (nrow(data) - nrow(d)) / nrow(data),
                clusters = prep$clusters,
                response_categories = as.list(stats::setNames(as.integer(counts), names(counts))),
                n_response_categories = length(lv),
                all_same_share = .all_same_share(d, ".cc_id", q$y),
                cluster_level = as.list(vapply(vars, function(v) .cluster_level(d, ".cc_id", v), "")),
                warnings = prep$warnings)
  facts <- prep$facts
  facts <- c(facts, sprintf("結果變數 %s 的次數：%s。", q$y, paste(sprintf("%s %d", names(counts), as.integer(counts)), collapse = "、")))
  if (!is.na(check$all_same_share)) facts <- c(facts, sprintf("有 %s 的叢集（≥ 2 筆）所有回答都相同。", fmt_pct(check$all_same_share)))
  if (length(vars)) facts <- c(facts, sprintf("%s。", paste(sprintf("%s 是%s變數", vars,
    ifelse(unlist(check$cluster_level) == "between", "叢集間（同一個叢集內不變）", "叢集內（同一個叢集內會變）")), collapse = "；")))

  tables <- list(); plots <- list()
  if (length(lv) == 2) {
    success <- q$success %||% .default_success(d[[q$y]])
    d$.cc_y <- as.integer(yv == success)
    check$success <- success
    check$smaller_outcome_count <- min(sum(d$.cc_y), sum(1 - d$.cc_y))
    tables$proportions <- .time_proportions(d, q$time, q$y, success)
    if (!is.null(q$time)) {
      plots$proportions <- .plot_time_proportion(tables$proportions, success)
      grp <- x[vapply(x, function(v) !is.numeric(d[[v]]) && length(unique(d[[v]])) <= 6 &&
                                      check$cluster_level[[v]] == "between", TRUE)]
      if (length(grp)) {
        tables$proportions_by_group <- .group_time_proportions(d, q$time, grp[1])
        plots$proportions_by_group <- .plot_group_time(tables$proportions_by_group, grp[1], success)
      }
    }
    if (length(vars)) {
      bp <- .build_predictors(d, vars, q$numeric %||% character(), as.list(q$ref %||% list()))
      sep <- .check_separation(stats::as.formula(paste(".cc_y ~", .formula_rhs(vars))), bp$data)
      check$separation <- length(sep) > 0
      check$warnings <- c(check$warnings, sep)
    }
  } else {
    d$.cc_y <- match(yv, lv)
    tables$distribution <- .time_distribution(d, q$time, q$y, lv)
    plots$distribution <- .plot_time_distribution(tables$distribution, lv)
  }
  list(check = check, facts = facts, tables = tables, plots = Filter(Negate(is.null), plots))
}

.group_time_proportions <- function(d, time, g) {
  key <- interaction(d[[time]], d[[g]], drop = TRUE, sep = "\r")
  s <- split(d$.cc_y, key)
  parts <- do.call(rbind, strsplit(names(s), "\r", fixed = TRUE))
  data.frame(time = parts[, 1], group = parts[, 2], n = vapply(s, length, 0L),
             proportion = vapply(s, mean, 0), row.names = NULL, stringsAsFactors = FALSE)
}

.plot_group_time <- function(p, g, success) {
  p$time <- factor(p$time, levels = unique(p$time))
  ggplot2::ggplot(p, ggplot2::aes(time, proportion, color = group, group = group)) +
    ggplot2::geom_line(linewidth = 1) + ggplot2::geom_point(size = 3) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(x = "time", y = sprintf("比例（%s）", success), color = g,
                  title = sprintf("各時間點的成功比例，依 %s 分組", g)) +
    .cc_theme() + ggplot2::theme(legend.position = "top")
}

cc_describe_md <- function(desc, file_name, question) {
  md_tabs <- unlist(lapply(names(desc$tables), function(nm) {
    t <- desc$tables[[nm]]
    body <- if (is.table(t) || is.matrix(t)) {
      m <- as.matrix(t)
      md_table(cbind(data.frame(` ` = rownames(m), check.names = FALSE), as.data.frame.matrix(m)))
    } else md_table(t)
    c(sprintf("### %s", nm), "", body, "")
  }))
  c(sprintf("# 初步檢視：%s", file_name), "",
    if (!is.null(question)) c(sprintf("問題：%s", question), ""),
    "## 重點數字", "", paste0("- ", desc$facts), "",
    if (length(desc$check$warnings)) c("## 需要注意", "",
      vapply(desc$check$warnings, function(w) sprintf("- **%s**：%s（Agresti %s）", w$code, w$message, w$book_ref), ""), ""),
    "## 表", "", md_tabs,
    "## 圖", "", sprintf("![](%s.png)", names(desc$plots)))
}
