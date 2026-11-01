# Plots for each analysis, drawn only from numbers already in the result.

.cc_theme <- function() ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), plot.title.position = "plot")

.plot_square <- function(tab) {
  df <- as.data.frame(as.table(tab), stringsAsFactors = FALSE)
  names(df) <- c("first", "second", "n")
  lv <- rownames(tab)
  df$first <- factor(df$first, levels = rev(lv)); df$second <- factor(df$second, levels = lv)
  df$diag <- as.character(df$first) == as.character(df$second)
  ggplot2::ggplot(df, ggplot2::aes(second, first, fill = n)) +
    ggplot2::geom_tile(color = "white", linewidth = 0.8) +
    ggplot2::geom_text(ggplot2::aes(label = n, fontface = ifelse(diag, "bold", "plain")), size = 4) +
    ggplot2::scale_fill_gradient(low = "#f1f5f9", high = "#3b82f6", guide = "none") +
    ggplot2::labs(x = names(dimnames(tab))[2], y = names(dimnames(tab))[1],
                  title = "配對次數表（對角線 = 兩次相同）") +
    .cc_theme()
}

.plot_marginals <- function(tab) {
  n <- sum(tab); lv <- rownames(tab); nm <- names(dimnames(tab))
  df <- data.frame(category = factor(rep(lv, 2), levels = lv),
                   measurement = factor(rep(nm, each = length(lv)), levels = nm),
                   prop = c(rowSums(tab), colSums(tab)) / n)
  ggplot2::ggplot(df, ggplot2::aes(category, prop, fill = measurement)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(prop, accuracy = 0.1)),
                       position = ggplot2::position_dodge(width = 0.75), vjust = -0.3, size = 3.2) +
    ggplot2::scale_y_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::scale_fill_manual(values = c("#3b82f6", "#f59e0b"), name = NULL) +
    ggplot2::labs(x = NULL, y = "比例", title = "兩次測量的邊際分布") +
    .cc_theme() + ggplot2::theme(legend.position = "top")
}

.plot_time_proportion <- function(p, success) {
  if (is.null(p$time)) return(NULL)
  p$time <- factor(p$time, levels = p$time)
  ggplot2::ggplot(p, ggplot2::aes(time, proportion, group = 1)) +
    ggplot2::geom_line(color = "#3b82f6", linewidth = 1) +
    ggplot2::geom_point(color = "#3b82f6", size = 3) +
    ggplot2::geom_text(ggplot2::aes(label = scales::percent(proportion, accuracy = 0.1)), vjust = -1, size = 3.4) +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(x = "time", y = sprintf("比例（%s）", success), title = "各時間點的成功比例") +
    .cc_theme()
}

.plot_time_distribution <- function(dist, lv) {
  cols <- paste0("prop_", lv)
  df <- do.call(rbind, lapply(seq_along(lv), function(j)
    data.frame(time = dist$time, category = lv[j], prop = dist[[cols[j]]], stringsAsFactors = FALSE)))
  df$category <- factor(df$category, levels = rev(lv)); df$time <- factor(df$time, levels = dist$time)
  ggplot2::ggplot(df, ggplot2::aes(time, prop, fill = category)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::scale_y_continuous(labels = scales::percent) +
    ggplot2::scale_fill_brewer(palette = "Blues", direction = -1, name = NULL) +
    ggplot2::labs(x = "time", y = "比例", title = "各時間點的類別分布") +
    .cc_theme()
}

.plot_compare <- function(res) {
  g <- res$notes$gee$estimates; m <- res$notes$glmm$estimates
  # Legend keys stay ASCII: the Windows png device clips CJK text in legend labels.
  df <- rbind(data.frame(term = g$term, model = "GEE", or = g$odds_ratio, lo = g$or_lower, hi = g$or_upper),
              data.frame(term = m$term, model = "GLMM", or = m$odds_ratio, lo = m$or_lower, hi = m$or_upper))
  df <- df[df$term != "(Intercept)", ]
  if (!nrow(df)) return(NULL)
  ggplot2::ggplot(df, ggplot2::aes(or, term, color = model)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, color = "grey50") +
    ggplot2::geom_pointrange(ggplot2::aes(xmin = lo, xmax = hi), position = ggplot2::position_dodge(width = 0.5)) +
    ggplot2::scale_x_log10() +
    ggplot2::scale_color_manual(values = c("#3b82f6", "#f59e0b"), name = NULL) +
    ggplot2::labs(x = "勝算比（對數尺度）", y = NULL, title = "GEE 與 GLMM 的勝算比",
                  subtitle = "GEE = 整體平均的效果；GLMM = 同一個叢集內的效果") +
    .cc_theme() + ggplot2::theme(legend.position = "top")
}

cc_plots <- function(result) {
  m <- result$method
  plots <- list()
  if (m %in% c("paired_binary", "paired_nominal", "paired_ordinal")) {
    plots$square_table <- .plot_square(result$tables$counts)
    plots$marginals <- .plot_marginals(result$tables$counts)
  } else if (m %in% c("gee_binary", "glmm_binary", "compare_gee_glmm")) {
    plots$proportions <- .plot_time_proportion(result$tables$proportions, "成功")
    if (m == "compare_gee_glmm") plots$compare <- .plot_compare(result)
  } else if (m %in% c("gee_ordinal", "gee_nominal")) {
    plots$distribution <- .plot_time_distribution(result$tables$distribution, result$notes$levels)
  }
  Filter(Negate(is.null), plots)
}
