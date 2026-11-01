# Part 3-A: comparing two dependent measurements on the same subjects (Agresti 2019, Ch.8).
# Input is wide: one row per subject, the two measurements in columns y1 and y2.

# Drop incomplete pairs, put both columns on one common set of categories, build the
# square table (rows = first measurement, columns = second). Checklist items 3, 11.
.prepare_paired <- function(data, y1, y2, levels = NULL) {
  for (v in c(y1, y2)) if (!v %in% names(data)) stop(sprintf("資料中找不到欄位：%s。現有欄位：%s", v,
                                                              paste(names(data), collapse = ", ")))
  facts <- character()
  warnings <- list()
  complete <- !is.na(data[[y1]]) & !is.na(data[[y2]])
  if (any(!complete)) {
    n_drop <- sum(!complete); share <- n_drop / nrow(data)
    facts <- c(facts, sprintf("%s 或 %s 有缺失，排除 %d 人（占 %s）；配對比較只用兩次都有回答的人。",
                              y1, y2, n_drop, fmt_pct(share)))
    if (share >= 0.2) {
      warnings[[length(warnings) + 1]] <- cc_warning("MISSING_HIGH",
        sprintf("缺失比例 %s（≥ 20%%），結果可能高度受缺失影響；請說明為什麼有人只有一次的回答。", fmt_pct(share)),
        "§9.5.1")
    } else if (share >= 0.05) {
      warnings[[length(warnings) + 1]] <- cc_warning("MISSING_DROPPED",
        sprintf("缺失比例 %s（≥ 5%%），可能影響結果；只有一次回答的人被排除，若他們和其他人不同，結論可能偏誤。",
                fmt_pct(share)), "§9.5.1")
    }
  }
  d <- data[complete, , drop = FALSE]
  v1 <- as.character(d[[y1]]); v2 <- as.character(d[[y2]])
  if (!is.null(levels)) {
    levels <- as.character(unlist(levels))
    bad <- setdiff(unique(c(v1, v2)), levels)
    if (length(bad) > 0) stop(sprintf("%s／%s 有不在 levels 中的值：%s", y1, y2, paste(bad, collapse = ", ")))
  } else {
    levels <- levels(code_order_factor(c(v1, v2)))
    only1 <- setdiff(unique(v1), unique(v2)); only2 <- setdiff(unique(v2), unique(v1))
    if (length(only1) + length(only2) > 0) {
      warnings[[length(warnings) + 1]] <- cc_warning("NOT_SQUARE",
        sprintf(paste0("兩欄的類別不完全相同（只出現在 %s：%s；只出現在 %s：%s）。配對比較需要兩次用同一組類別，",
                       "請確認兩欄是同一個量表；若只是某類剛好沒人選，可以繼續。"),
                y1, if (length(only1)) paste(only1, collapse = ", ") else "無",
                y2, if (length(only2)) paste(only2, collapse = ", ") else "無"), "§8.3")
    }
  }
  f1 <- factor(v1, levels = levels); f2 <- factor(v2, levels = levels)
  tab <- table(f1, f2, dnn = c(y1, y2))
  facts <- c(facts, sprintf("共 %d 人，每人兩次測量（%s、%s），類別：%s。", sum(tab), y1, y2,
                            paste(levels, collapse = "、")))
  list(tab = tab, levels = levels, f1 = f1, f2 = f2, facts = facts, warnings = warnings)
}

.marginal_table <- function(tab, y1, y2) {
  n <- sum(tab)
  data.frame(category = rownames(tab),
             count_1 = as.integer(rowSums(tab)), prop_1 = as.numeric(rowSums(tab)) / n,
             count_2 = as.integer(colSums(tab)), prop_2 = as.numeric(colSums(tab)) / n,
             check.names = FALSE, stringsAsFactors = FALSE) |>
    stats::setNames(c("category", paste0(y1, "_count"), paste0(y1, "_prop"),
                      paste0(y2, "_count"), paste0(y2, "_prop")))
}

# Each pair of opposite off-diagonal cells (n_ij, n_ji) as a binomial observation (§8.3.4).
.qs_data <- function(tab, scores = seq_len(nrow(tab))) {
  k <- nrow(tab)
  pr <- t(utils::combn(k, 2))
  X <- matrix(0, nrow(pr), k)
  X[cbind(seq_len(nrow(pr)), pr[, 1])] <- 1
  X[cbind(seq_len(nrow(pr)), pr[, 2])] <- -1
  colnames(X) <- paste0("b", seq_len(k))
  data.frame(X, x = scores[pr[, 2]] - scores[pr[, 1]],
             i = rownames(tab)[pr[, 1]], j = rownames(tab)[pr[, 2]],
             nij = as.numeric(tab[pr]), nji = as.numeric(tab[pr[, 2:1]]), stringsAsFactors = FALSE)
}

.fit_symmetry <- function(d) {
  stats::glm(nij / (nij + nji) ~ -1, family = stats::binomial, weights = nij + nji,
             data = d[d$nij + d$nji > 0, ])
}

#' A1 Binary matched pairs: McNemar test (§8.1, §8.2.4)
#'
#' @param success category counted as "success" (default: first level)
cc_paired_binary <- function(data, y1, y2, success = NULL, levels = NULL, conf.level = 0.95) {
  prep <- .prepare_paired(data, y1, y2, levels)
  tab <- prep$tab; warnings <- prep$warnings; facts <- prep$facts
  if (nrow(tab) != 2) stop(sprintf("二元配對需要剛好 2 個類別，現在有 %d 個：%s。3 類以上請用 paired_nominal 或 paired_ordinal。",
                                   nrow(tab), paste(rownames(tab), collapse = ", ")))
  success <- success %||% rownames(tab)[1]
  if (!success %in% rownames(tab)) stop(sprintf("成功類別「%s」不在資料中。", success))
  ord <- c(success, setdiff(rownames(tab), success))
  tab <- tab[ord, ord]
  n <- sum(tab); n12 <- tab[1, 2]; n21 <- tab[2, 1]; nstar <- n12 + n21
  p1 <- sum(tab[1, ]) / n; p2 <- sum(tab[, 1]) / n

  tests <- data.frame(test = character(), statistic = numeric(), df = numeric(), p_value = numeric(),
                      book_ref = character(), stringsAsFactors = FALSE)
  if (nstar > 0) {
    mc <- stats::mcnemar.test(tab, correct = FALSE)
    ex <- stats::binom.test(n12, nstar, p = 0.5)
    tests <- rbind(tests,
      data.frame(test = "McNemar X2", statistic = unname(mc$statistic), df = 1, p_value = mc$p.value,
                 book_ref = "§8.1.1"),
      data.frame(test = "Exact binomial (n12 ~ Bin(n*, 0.5))", statistic = n12, df = NA, p_value = ex$p.value,
                 book_ref = "§8.1.1"))
  }
  primary <- if (nstar > 10) "McNemar X2" else "Exact binomial (n12 ~ Bin(n*, 0.5))"
  if (nstar == 0) {
    warnings[[length(warnings) + 1]] <- cc_warning("ZERO_DISCORDANT",
      "所有人兩次的回答都相同（n12 = n21 = 0），沒有任何改變，無法檢定也無法估計條件勝算比。", "§8.1.1")
  } else if (nstar <= 10) {
    warnings[[length(warnings) + 1]] <- cc_warning("FEW_DISCORDANT",
      sprintf("回答改變的人只有 n12 + n21 = %d 人（≤ 10），McNemar 的常態近似不可靠，以精確二項檢定為主。", nstar),
      "§8.1.1")
  }
  if (nstar > 0 && (n12 == 0 || n21 == 0)) {
    warnings[[length(warnings) + 1]] <- cc_warning("ZERO_DISCORDANT",
      sprintf("不一致的格子有 0（n12 = %d、n21 = %d），條件勝算比 n12/n21 為 %s，不加 0.5 校正。",
              n12, n21, if (n21 == 0) "∞" else "0"), "§8.2.4")
  }

  ci <- if (nstar > 0) PropCIs::scoreci.mp(n21, n12, n, conf.level)$conf.int else c(NA, NA)
  odds <- function(p) p / (1 - p)
  # Both directions are given so the explanation never has to negate or invert a number itself.
  ratio <- function(a, b) if (b == 0) Inf else a / b
  estimates <- data.frame(
    measure = c(sprintf("P(%s = %s)", y1, success), sprintf("P(%s = %s)", y2, success),
                sprintf("Difference of proportions (%s - %s)", y1, y2),
                sprintf("Difference of proportions (%s - %s)", y2, y1),
                sprintf("Marginal odds ratio %s vs %s (population-averaged)", y1, y2),
                sprintf("Marginal odds ratio %s vs %s (population-averaged)", y2, y1),
                sprintf("Conditional odds ratio n12/n21: %s vs %s (subject-specific)", y1, y2),
                sprintf("Conditional odds ratio n21/n12: %s vs %s (subject-specific)", y2, y1)),
    estimate = c(p1, p2, p1 - p2, p2 - p1, odds(p1) / odds(p2), odds(p2) / odds(p1),
                 ratio(n12, n21), ratio(n21, n12)),
    lower = c(NA, NA, ci[1], -ci[2], NA, NA, NA, NA), upper = c(NA, NA, ci[2], -ci[1], NA, NA, NA, NA),
    book_ref = c("§8.1", "§8.1", "§8.1.2", "§8.1.2", "§8.2.2", "§8.2.2", "§8.2.4", "§8.2.4"),
    stringsAsFactors = FALSE)

  pt <- tests[tests$test == primary, ]
  facts <- c(facts,
    sprintf("%s 選「%s」的比例 %s，%s 為 %s，差 %s（%d%% score 信賴區間 %s 到 %s）。",
            y1, success, fmt_num(p1), y2, fmt_num(p2), fmt_num(p1 - p2), round(conf.level * 100),
            fmt_num(ci[1]), fmt_num(ci[2])),
    sprintf("回答改變的人：%s 是「%s」但 %s 不是的有 n12 = %d 人，反過來的有 n21 = %d 人；兩次回答相同的 %d 人不影響檢定。",
            y1, success, y2, n12, n21, n - nstar),
    if (nrow(pt)) sprintf("主要檢定：%s，P %s。", primary, fmt_p(pt$p_value)),
    if (nrow(tests)) sprintf("McNemar X² = %s（df = 1），P %s；精確二項檢定 P %s。",
                             fmt_num(tests$statistic[1], 2), fmt_p(tests$p_value[1]), fmt_p(tests$p_value[2])),
    sprintf("邊際勝算比（整體平均）：%s 對 %s = %s，%s 對 %s = %s。", y1, y2, fmt_num(odds(p1) / odds(p2)),
            y2, y1, fmt_num(odds(p2) / odds(p1))),
    sprintf("條件勝算比（同一個人）：%s 對 %s = n12/n21 = %s，%s 對 %s = n21/n12 = %s。", y1, y2,
            if (n21 == 0) "∞" else fmt_num(n12 / n21), y2, y1, if (n12 == 0) "∞" else fmt_num(n21 / n12)))

  cc_result("paired_binary", "McNemar test for binary matched pairs", "§8.1", "A",
            estimates = estimates, tests = tests,
            tables = list(counts = tab, marginal = .marginal_table(tab, y1, y2)),
            warnings = warnings, facts = facts,
            notes = list(primary_test = primary, success = success, n_discordant = nstar,
                         reminder = "McNemar 只用到回答改變的人；條件勝算比是個體層次，邊際勝算比是整體層次，兩者不可混稱（§8.2.4）。"))
}

#' A2 Nominal matched pairs: marginal homogeneity (§8.3)
cc_paired_nominal <- function(data, y1, y2, levels = NULL, ordinal = character(), conf.level = 0.95) {
  prep <- .prepare_paired(data, y1, y2, levels)
  tab <- prep$tab; warnings <- prep$warnings; facts <- prep$facts
  k <- nrow(tab)
  if (k < 3) stop("只有 2 個類別，請改用 paired_binary（McNemar）。")
  if (any(c(y1, y2) %in% ordinal)) {
    warnings[[length(warnings) + 1]] <- cc_warning("ORDINAL_IGNORED",
      "結果變數已確認是有序的，名目檢定（df = c − 1）沒有用到順序；有序方法（paired_ordinal，df = 1）通常檢定力較高。",
      "§8.4")
  }
  d <- .qs_data(tab)
  empty <- d[d$nij + d$nji == 0, ]
  if (nrow(empty) > 0) {
    warnings[[length(warnings) + 1]] <- cc_warning("EMPTY_PAIR",
      sprintf("這些類別之間沒有任何人改變（兩個方向都是 0）：%s；這幾對不提供資訊。",
              paste(sprintf("%s↔%s", empty$i, empty$j), collapse = "、")), "§8.3.4")
  }
  fit_d <- d[d$nij + d$nji > 0, ]
  symm <- .fit_symmetry(d)
  qs_f <- stats::as.formula(paste("nij / (nij + nji) ~ -1 +", paste(paste0("b", 1:(k - 1)), collapse = " + ")))
  qs <- stats::glm(qs_f, family = stats::binomial, weights = nij + nji, data = fit_d)
  lr <- stats::deviance(symm) - stats::deviance(qs)
  df <- stats::df.residual(symm) - stats::df.residual(qs)
  tests <- data.frame(test = "Marginal homogeneity: symmetry vs quasi-symmetry LR", statistic = lr, df = df,
                      p_value = stats::pchisq(lr, df, lower.tail = FALSE), book_ref = "§8.3.4",
                      stringsAsFactors = FALSE)
  tests <- rbind(tests,
    data.frame(test = "Symmetry model deviance (fit)", statistic = stats::deviance(symm),
               df = stats::df.residual(symm),
               p_value = stats::pchisq(stats::deviance(symm), stats::df.residual(symm), lower.tail = FALSE),
               book_ref = "§8.3.4"),
    data.frame(test = "Quasi-symmetry model deviance (fit)", statistic = stats::deviance(qs),
               df = stats::df.residual(qs),
               p_value = if (stats::df.residual(qs) > 0) stats::pchisq(stats::deviance(qs), stats::df.residual(qs), lower.tail = FALSE) else NA,
               book_ref = "§8.3.4"))
  long <- data.frame(id = rep(seq_along(prep$f1), 2), time = rep(c(1, 0), each = length(prep$f1)),
                     y = c(as.character(prep$f1), as.character(prep$f2)))
  cmh <- tryCatch(stats::mantelhaen.test(factor(long$time), factor(long$y, levels = prep$levels), factor(long$id)),
                  error = function(e) NULL)
  if (!is.null(cmh)) {
    tests <- rbind(tests, data.frame(test = "CMH (score test of marginal homogeneity)",
                                     statistic = unname(cmh$statistic), df = unname(cmh$parameter),
                                     p_value = cmh$p.value, book_ref = "§8.3.3", stringsAsFactors = FALSE))
  }

  n <- sum(tab)
  follow <- do.call(rbind, lapply(seq_len(k), function(j) {
    t2 <- matrix(c(tab[j, j], sum(tab[-j, j]), sum(tab[j, -j]), sum(tab[-j, -j])), 2)
    nst <- t2[1, 2] + t2[2, 1]
    z <- if (nst > 0) (t2[1, 2] - t2[2, 1]) / sqrt(nst) else NA
    ci <- if (nst > 0) PropCIs::scoreci.mp(t2[2, 1], t2[1, 2], n, conf.level)$conf.int else c(NA, NA)
    data.frame(category = rownames(tab)[j], prop_1 = sum(tab[j, ]) / n, prop_2 = sum(tab[, j]) / n,
               difference = (sum(tab[j, ]) - sum(tab[, j])) / n, lower = ci[1], upper = ci[2],
               n12 = t2[1, 2], n21 = t2[2, 1],
               z = z, p_value = if (is.na(z)) NA else 2 * stats::pnorm(-abs(z)), stringsAsFactors = FALSE)
  }))
  resid <- data.frame(pair = sprintf("%s → %s vs %s → %s", d$i, d$j, d$j, d$i), n_ij = d$nij, n_ji = d$nji,
                      std_residual = ifelse(d$nij + d$nji > 0, (d$nij - d$nji) / sqrt(d$nij + d$nji), NA),
                      stringsAsFactors = FALSE)
  big <- resid[!is.na(resid$std_residual) & abs(resid$std_residual) > 2, ]

  facts <- c(facts,
    sprintf("邊際同質性檢定（對稱 vs 準對稱模型）：LR = %s（df = %d），P %s。", fmt_num(lr, 2), df,
            fmt_p(tests$p_value[1])),
    if (!is.null(cmh)) sprintf("對照：CMH 檢定 = %s（df = %d），P %s。", fmt_num(cmh$statistic, 2),
                               as.integer(cmh$parameter), fmt_p(cmh$p.value)),
    sprintf("各類別的比例（%s → %s）：%s。", y1, y2,
            paste(sprintf("%s %s → %s", follow$category, fmt_num(follow$prop_1), fmt_num(follow$prop_2)), collapse = "；")),
    sprintf("各類別的比例差（%s − %s，%d%% score 信賴區間）：%s。", y1, y2, round(conf.level * 100),
            paste(sprintf("%s %s（%s 到 %s）", follow$category, fmt_num(follow$difference), fmt_num(follow$lower),
                          fmt_num(follow$upper)), collapse = "；")),
    if (nrow(big)) sprintf("改變方向明顯不對稱的類別配對（|標準化殘差| > 2）：%s。",
                           paste(sprintf("%s（%s）", big$pair, fmt_num(big$std_residual, 2)), collapse = "；")))
  cc_result("paired_nominal", "Marginal homogeneity for nominal matched pairs", "§8.3", "A",
            estimates = follow, tests = tests,
            tables = list(counts = tab, marginal = .marginal_table(tab, y1, y2), symmetry_residuals = resid),
            warnings = warnings, facts = facts,
            notes = list(reminder = paste0("逐類別的追蹤檢定（estimates）沒有做多重比較校正，只用來描述哪些類別改變；",
                                           "整體結論以邊際同質性檢定為準（§8.3.2）。")))
}

#' A3 Ordinal matched pairs: cumulative logit marginal model by GEE (§8.4.1–8.4.2),
#' with the ordinal quasi-symmetry model as a check (§8.4.3*).
#'
#' @param levels categories from low to high (required: the order cannot be guessed)
#' @param scores category scores for the ordinal quasi-symmetry model (default 1, 2, …)
cc_paired_ordinal <- function(data, y1, y2, levels, scores = NULL, conf.level = 0.95) {
  if (is.null(levels)) stop("有序配對需要 levels（由低到高的類別順序），請和使用者確認後填入。")
  prep <- .prepare_paired(data, y1, y2, levels)
  tab <- prep$tab; warnings <- prep$warnings; facts <- prep$facts
  k <- nrow(tab)
  if (k < 3) stop("只有 2 個類別，請改用 paired_binary（McNemar）。")
  scores <- as.numeric(unlist(scores %||% seq_len(k)))
  if (length(scores) != k || is.unsorted(scores, strictly = TRUE)) stop("scores 的個數要等於類別數，且必須遞增。")

  n <- length(prep$f1)
  long <- data.frame(id = rep(seq_len(n), each = 2), time = rep(c(1, 0), n),
                     y = as.integer(as.vector(rbind(as.integer(prep$f1), as.integer(prep$f2)))))
  long$occasion <- ifelse(long$time == 1, 1L, 2L)
  fit <- multgee::ordLORgee(y ~ time, id = id, repeated = occasion, LORstr = "independence", data = long)
  s <- summary(fit)$coefficients
  beta <- s["time", 1]; se <- s["time", 2]; z <- qnorm(1 - (1 - conf.level) / 2)
  tests <- data.frame(test = "Cumulative logit marginal model (GEE), Wald z^2", statistic = (beta / se)^2, df = 1,
                      p_value = 2 * stats::pnorm(-abs(beta / se)), book_ref = "§8.4.2", stringsAsFactors = FALSE)

  d <- .qs_data(tab, scores)
  symm <- .fit_symmetry(d)
  oqs <- stats::glm(nij / (nij + nji) ~ -1 + x, family = stats::binomial, weights = nij + nji,
                    data = d[d$nij + d$nji > 0, ])
  lr <- stats::deviance(symm) - stats::deviance(oqs)
  tests <- rbind(tests, data.frame(test = "Ordinal quasi-symmetry vs symmetry LR", statistic = lr, df = 1,
                                   p_value = stats::pchisq(lr, 1, lower.tail = FALSE), book_ref = "§8.4.3",
                                   stringsAsFactors = FALSE))
  mean1 <- sum(scores * rowSums(tab)) / sum(tab); mean2 <- sum(scores * colSums(tab)) / sum(tab)
  # Both directions of the odds ratio, so the explanation never inverts a number itself.
  estimates <- data.frame(
    measure = c("beta: cumulative logit, first vs second (logit P(Y <= j))",
                sprintf("Odds ratio: %s in a higher category vs %s", y1, y2),
                sprintf("Odds ratio: %s in a higher category vs %s", y2, y1),
                "Ordinal quasi-symmetry beta", sprintf("Mean score %s", y1), sprintf("Mean score %s", y2)),
    estimate = c(beta, exp(-beta), exp(beta), stats::coef(oqs)[["x"]], mean1, mean2),
    se = c(se, NA, NA, sqrt(stats::vcov(oqs)[1, 1]), NA, NA),
    lower = c(beta - z * se, exp(-beta - z * se), exp(beta - z * se), NA, NA, NA),
    upper = c(beta + z * se, exp(-beta + z * se), exp(beta + z * se), NA, NA, NA),
    book_ref = c("§8.4.1", "§8.4.1", "§8.4.1", "§8.4.3", "§8.4.3", "§8.4.3"), stringsAsFactors = FALSE)
  # Who moved up, down or stayed (rows = y1, columns = y2; above the diagonal = y2 higher).
  n_all <- sum(tab)
  up <- sum(tab[upper.tri(tab)]); down <- sum(tab[lower.tri(tab)]); same <- sum(diag(tab))
  changes <- data.frame(change = c(sprintf("%s higher than %s", y2, y1), sprintf("%s lower than %s", y2, y1), "same"),
                        n = c(up, down, same), proportion = c(up, down, same) / n_all, stringsAsFactors = FALSE)
  direction <- if (beta > 0) sprintf("%s 傾向落在較低的類別（較接近「%s」）", y1, prep$levels[1]) else
    sprintf("%s 傾向落在較高的類別（較接近「%s」）", y1, prep$levels[k])
  facts <- c(facts,
    sprintf("累積 logit 邊際模型（GEE）：β̂ = %s（robust SE %s），Wald z = %s，P %s。",
            fmt_num(beta), fmt_num(se), fmt_num(beta / se, 2), fmt_p(2 * stats::pnorm(-abs(beta / se)))),
    sprintf("%s 落在較高類別的勝算是 %s 的 %s 倍（%d%% 信賴區間 %s 到 %s）；反過來，%s 落在較高類別的勝算是 %s 的 %s 倍（%s 到 %s）。對每個切點都相同（比例勝算）。",
            y1, y2, fmt_num(exp(-beta)), round(conf.level * 100), fmt_num(exp(-beta - z * se)),
            fmt_num(exp(-beta + z * se)), y2, y1, fmt_num(exp(beta)), fmt_num(exp(beta - z * se)),
            fmt_num(exp(beta + z * se))),
    sprintf("方向：%s。", direction),
    sprintf("逐人比較：%s 比 %s 高的有 %d 人（%s），較低的 %d 人（%s），相同的 %d 人（%s）。", y2, y1,
            up, fmt_pct(up / n_all), down, fmt_pct(down / n_all), same, fmt_pct(same / n_all)),
    sprintf("對照：有序準對稱模型 β̂ = %s，和對稱模型比較 LR = %s（df = 1），P %s；平均分數 %s = %s、%s = %s（分數 %s）。",
            fmt_num(stats::coef(oqs)[["x"]]), fmt_num(lr, 2), fmt_p(tests$p_value[2]),
            y1, fmt_num(mean1, 2), y2, fmt_num(mean2, 2), paste(scores, collapse = ", ")))
  cc_result("paired_ordinal", "Cumulative logit marginal model for ordinal matched pairs", "§8.4", "A",
            estimates = estimates, tests = tests,
            tables = list(counts = tab, marginal = .marginal_table(tab, y1, y2), changes = changes),
            warnings = warnings, facts = facts,
            notes = list(scores = scores, levels = prep$levels,
                         reminder = paste0("比例勝算：模型假設每個切點的效果相同（§8.4.1）。",
                                           "平均分數取決於分數設定，只用來幫助描述方向。")))
}
