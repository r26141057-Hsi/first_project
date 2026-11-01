# Part 3-B: models for clustered / repeated categorical responses (Agresti 2019, Ch.9–10).
# Input is long: one row per cluster × occasion, with an id column.

# Default "success" category (same rule as Part 2): an affirmative value if present,
# otherwise the second category in code order.
.default_success <- function(values) {
  lv <- levels(code_order_factor(values))
  hit <- lv[tolower(lv) %in% c("1", "yes", "y", "true", "pass", "success", "是", "有")]
  if (length(hit)) hit[1] else lv[min(2, length(lv))]
}

# Default baseline for a nominal response (same rule as Part 2): other/其他, else the last category.
.default_baseline <- function(lv) {
  hit <- lv[tolower(lv) %in% c("other", "others", "其他")]
  if (length(hit)) hit[1] else lv[length(lv)]
}

# Everything the B-type models share: missing data, cluster summary, predictors, response.
.prepare_model <- function(data, id, y, x = character(), time = NULL, numeric = character(),
                           ref = list(), interactions = character(), response = c("binary", "ordinal", "nominal"),
                           success = NULL, levels = NULL, baseline = NULL, family = "gee") {
  response <- match.arg(response)
  vars <- unique(c(time, x))
  prep <- .prepare_long(data, id, y, vars, family)
  d <- prep$data
  warnings <- prep$warnings; facts <- prep$facts
  bp <- .build_predictors(d, vars, numeric, ref)
  d <- bp$data
  d$.cc_id <- as.integer(factor(d[[id]], levels = unique(d[[id]])))
  if (!is.null(time)) {
    tv <- sort(unique(as.character(d[[time]])), method = "radix")
    if (is.numeric(d[[time]])) tv <- as.character(sort(unique(d[[time]])))
    d$.cc_wave <- match(as.character(d[[time]]), tv)
  } else {
    d$.cc_wave <- stats::ave(d$.cc_id, d$.cc_id, FUN = seq_along)
  }
  if (any(duplicated(d[, c(".cc_id", ".cc_wave")]))) {
    stop("同一個叢集在同一個時間點有超過一筆資料；請確認 id 與 time 欄位。")
  }
  d <- d[order(d$.cc_id, d$.cc_wave), , drop = FALSE]

  yv <- as.character(d[[y]])
  resp <- list(type = response)
  if (response == "binary") {
    lv <- levels(code_order_factor(d[[y]]))
    if (length(lv) != 2) stop(sprintf("二元模型的結果變數要剛好 2 類，%s 有 %d 類：%s。", y, length(lv),
                                      paste(lv, collapse = ", ")))
    success <- success %||% .default_success(d[[y]])
    if (!success %in% lv) stop(sprintf("成功類別「%s」不在 %s 中。", success, y))
    d$.cc_y <- as.integer(yv == success)
    resp$success <- success; resp$failure <- setdiff(lv, success)
  } else {
    lv <- if (!is.null(levels)) as.character(unlist(levels)) else levels(code_order_factor(d[[y]]))
    bad <- setdiff(unique(yv), lv)
    if (length(bad)) stop(sprintf("%s 有不在 levels 中的值：%s", y, paste(bad, collapse = ", ")))
    if (response == "ordinal" && is.null(levels)) stop("有序結果需要 levels（由低到高），請和使用者確認後填入。")
    if (response == "nominal") {
      baseline <- baseline %||% .default_baseline(lv)
      if (!baseline %in% lv) stop(sprintf("基準類別「%s」不在 %s 中。", baseline, y))
      lv <- c(setdiff(lv, baseline), baseline)   # multgee uses the last category as baseline
      resp$baseline <- baseline
    }
    if (length(lv) < 3) stop("只有 2 類，請改用二元模型。")
    d$.cc_y <- match(yv, lv)
    resp$levels <- lv
  }
  rhs_terms <- c(vars, interactions)
  levels_info <- vapply(vars, function(v) .cluster_level(d, ".cc_id", v), "")
  facts <- c(facts, if (length(vars)) sprintf("叢集間變數（同一個叢集內不變）：%s；叢集內變數（同一個叢集內會變）：%s。",
    if (any(levels_info == "between")) paste(vars[levels_info == "between"], collapse = "、") else "無",
    if (any(levels_info == "within")) paste(vars[levels_info == "within"], collapse = "、") else "無"))
  list(data = d, rhs = .formula_rhs(rhs_terms), terms = rhs_terms, predictors = bp$info,
       response = resp, warnings = warnings, facts = facts, clusters = prep$clusters,
       cluster_level = as.list(levels_info), y = y, id = id)
}

# Odds ratios in both directions (e.g. M vs F and F vs M), so the explanation never inverts a
# number itself (first skill test: Claude computed 1/0.254 on its own).
.coef_table <- function(est, se, conf.level, exp_sign = 1) {
  z <- stats::qnorm(1 - (1 - conf.level) / 2)
  lo <- exp_sign * (est - z * se); hi <- exp_sign * (est + z * se)
  data.frame(term = names(est), estimate = unname(est), se = unname(se), z = unname(est / se),
             p_value = 2 * stats::pnorm(-abs(unname(est / se))),
             odds_ratio = exp(exp_sign * unname(est)),
             or_lower = unname(exp(pmin(lo, hi))), or_upper = unname(exp(pmax(lo, hi))),
             or_reverse = exp(-exp_sign * unname(est)),
             or_reverse_lower = unname(exp(-pmax(lo, hi))), or_reverse_upper = unname(exp(-pmin(lo, hi))),
             stringsAsFactors = FALSE, row.names = NULL)
}

.term_tests <- function(coefs, vc, idx, label, book_ref) {
  idx <- idx[lengths(idx) > 0]
  if (!length(idx)) return(data.frame())
  rows <- lapply(names(idx), function(t) {
    w <- .joint_wald(coefs, vc, idx[[t]])
    data.frame(test = sprintf("%s: %s", label, t), statistic = w[["statistic"]], df = w[["df"]],
               p_value = w[["p_value"]], book_ref = book_ref, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Checklist 16: separation shows up as fitted probabilities of 0 or 1 in the ordinary logistic fit.
.check_separation <- function(formula, d) {
  w <- .with_warnings(stats::glm(formula, family = stats::binomial, data = d))
  if (any(grepl("fitted probabilities numerically 0 or 1", w$warnings))) {
    list(cc_warning("SEPARATION",
      "有解釋變數的某些值幾乎能完美區分成功與失敗（完全分離），對應的係數其實是無限大，係數、SE 與檢定沒有意義。",
      "§5.3"))
  } else list()
}

.cluster_reminder <- function(k) {
  sprintf("GEE 的 robust SE 是大樣本方法，叢集少時傾向低估（§9.2.4）；本資料有 %d 個叢集，課本沒有給門檻，請自行判斷是否足夠。", k)
}

#' B1 Binary GEE: marginal logistic model (§9.1–9.2)
#'
#' @param corstr working correlation: exchangeable (default, §9.2.2), ar1, independence, unstructured
#' @param test   "wald"; asking for "lr" gives GEE_NO_LIKELIHOOD (checklist 12)
cc_gee_binary <- function(data, id, y, x = character(), time = NULL, numeric = character(), ref = list(),
                          interactions = character(), success = NULL, corstr = "exchangeable",
                          test = "wald", conf.level = 0.95) {
  corstr <- match.arg(corstr, c("exchangeable", "ar1", "independence", "unstructured"))
  pm <- .prepare_model(data, id, y, x, time, numeric, ref, interactions, "binary", success = success, family = "gee")
  d <- pm$data; warnings <- pm$warnings; facts <- pm$facts
  if (tolower(test) == "lr") {
    warnings[[length(warnings) + 1]] <- cc_warning("GEE_NO_LIKELIHOOD",
      "GEE 沒有概似函數，不能做概似比檢定或比較 deviance；以下改用 robust SE 的 Wald 檢定。", "§9.2.4")
  }
  f <- stats::as.formula(paste(".cc_y ~", pm$rhs))
  warnings <- c(warnings, .check_separation(f, d))
  fit <- geepack::geeglm(f, id = .cc_id, waves = .cc_wave, family = stats::binomial, corstr = corstr, data = d)
  coefs <- stats::coef(fit); vc <- stats::vcov(fit)
  est <- .coef_table(coefs, sqrt(diag(vc)), conf.level)
  tests <- .term_tests(coefs, vc, .term_index(names(coefs), pm$rhs, d), "Wald (robust SE)", "§9.2.4")
  alpha <- fit$geese$alpha
  facts <- c(facts,
    sprintf("邊際 logistic 模型（GEE），成功 =「%s」，working correlation = %s%s。", pm$response$success, corstr,
            if (length(alpha)) sprintf("（估計相關 %s）", paste(fmt_num(alpha), collapse = ", ")) else ""),
    vapply(seq_len(nrow(est))[-1], function(r) sprintf(
      "%s：整體來說，勝算比 = %s（%d%% 信賴區間 %s 到 %s），P %s。", est$term[r], fmt_num(est$odds_ratio[r]),
      round(conf.level * 100), fmt_num(est$or_lower[r]), fmt_num(est$or_upper[r]), fmt_p(est$p_value[r])), ""),
    if (nrow(tests)) vapply(seq_len(nrow(tests)), function(r) sprintf("%s = %s（df = %d），P %s。",
      tests$test[r], fmt_num(tests$statistic[r], 2), as.integer(tests$df[r]), fmt_p(tests$p_value[r])), ""))
  cc_result("gee_binary", "Marginal logistic model fitted by GEE", "§9.2", "A",
            estimates = est, tests = tests,
            tables = list(proportions = .time_proportions(d, time, pm$y, pm$response$success)),
            warnings = warnings, facts = facts,
            notes = list(effect_type = "population-averaged", corstr = corstr, working_correlation = alpha,
                         clusters = pm$clusters, cluster_level = pm$cluster_level, predictors = pm$predictors,
                         cluster_reminder = .cluster_reminder(pm$clusters$n_clusters),
                         reminder = "勝算比是「整體平均」的效果；SE 為 robust（sandwich）SE，即使 working correlation 設錯也有效（§9.2.2）。"))
}

#' B2 Ordinal / nominal GEE (§9.3, §8.3.2), multgee with local odds ratios.
cc_gee_multinomial <- function(data, id, y, x = character(), time = NULL, numeric = character(), ref = list(),
                               interactions = character(), type = c("ordinal", "nominal"), levels = NULL,
                               baseline = NULL, lorstr = "independence", conf.level = 0.95) {
  type <- match.arg(type)
  lorstr <- match.arg(lorstr, c("independence", "uniform"))
  pm <- .prepare_model(data, id, y, x, time, numeric, ref, interactions, type, levels = levels,
                       baseline = baseline, family = "gee")
  d <- pm$data; warnings <- pm$warnings; facts <- pm$facts
  f <- stats::as.formula(paste(".cc_y ~", pm$rhs))
  fit <- if (type == "ordinal") {
    multgee::ordLORgee(f, id = .cc_id, repeated = .cc_wave, LORstr = lorstr, data = d)
  } else {
    multgee::nomLORgee(f, id = .cc_id, repeated = .cc_wave, LORstr = lorstr, data = d)
  }
  coefs <- stats::coef(fit); vc <- stats::vcov(fit)
  keep <- !grepl("^beta[0-9]+0$", names(coefs))          # drop the cutpoints / intercepts
  lv <- pm$response$levels
  if (type == "ordinal") {
    # multgee: logit P(Y <= j) = beta_j0 + beta x. Report exp(-beta): odds of a higher category.
    est <- .coef_table(coefs[keep], sqrt(diag(vc))[keep], conf.level, exp_sign = -1)
    names(est)[names(est) == "odds_ratio"] <- "odds_ratio_higher"
    facts <- c(facts, sprintf("累積 logit 邊際模型（GEE），類別由低到高：%s；局部勝算比結構 = %s。",
                              paste(lv, collapse = " < "), lorstr),
      vapply(seq_len(nrow(est)), function(r) sprintf(
        "%s：整體來說，落在較高類別的勝算比 = %s（%d%% 信賴區間 %s 到 %s），P %s（每個切點相同）。",
        est$term[r], fmt_num(est$odds_ratio_higher[r]), round(conf.level * 100), fmt_num(est$or_lower[r]),
        fmt_num(est$or_upper[r]), fmt_p(est$p_value[r])), ""))
  } else {
    est <- .coef_table(coefs[keep], sqrt(diag(vc))[keep], conf.level)
    cat_idx <- as.integer(sub("^.*:([0-9]+)$", "\\1", est$term))
    est$category <- lv[cat_idx]
    est$term <- sub(":[0-9]+$", "", est$term)
    est <- est[, c("term", "category", setdiff(names(est), c("term", "category")))]
    facts <- c(facts, sprintf("baseline-category logit 邊際模型（GEE），基準類別 =「%s」；局部勝算比結構 = %s。",
                              pm$response$baseline, lorstr),
      vapply(seq_len(nrow(est)), function(r) sprintf(
        "%s（%s vs %s）：整體來說，勝算比 = %s（%d%% 信賴區間 %s 到 %s），P %s。", est$term[r], est$category[r],
        pm$response$baseline, fmt_num(est$odds_ratio[r]), round(conf.level * 100), fmt_num(est$or_lower[r]),
        fmt_num(est$or_upper[r]), fmt_p(est$p_value[r])), ""))
  }
  tests <- .term_tests(coefs, vc, .term_index(names(coefs), pm$rhs, d, nominal = type == "nominal"),
                       "Wald (robust SE)", "§9.3")
  if (nrow(tests)) facts <- c(facts, vapply(seq_len(nrow(tests)), function(r) sprintf("%s = %s（df = %d），P %s。",
    tests$test[r], fmt_num(tests$statistic[r], 2), as.integer(tests$df[r]), fmt_p(tests$p_value[r])), ""))
  cc_result(paste0("gee_", type),
            if (type == "ordinal") "Cumulative logit marginal model fitted by GEE" else
              "Baseline-category logit marginal model fitted by GEE", "§9.3", "A",
            estimates = est, tests = tests,
            tables = list(distribution = .time_distribution(d, time, pm$y, lv)),
            warnings = warnings, facts = facts,
            notes = list(effect_type = "population-averaged", lorstr = lorstr, levels = lv,
                         clusters = pm$clusters, cluster_level = pm$cluster_level, predictors = pm$predictors,
                         cluster_reminder = .cluster_reminder(pm$clusters$n_clusters),
                         reminder = if (type == "ordinal") "比例勝算：模型假設每個切點的效果相同（§6.3.2、§9.3.1），第一版不做正式檢定。" else
                           "每個勝算比都是「該類 vs 基準類別」；換基準類別不影響配適（§6.1）。"))
}

# Fit the random-intercept logistic GLMM, capturing convergence messages.
.fit_glmm <- function(f, d, nagq) {
  w <- .with_warnings(lme4::glmer(f, family = stats::binomial, data = d, nAGQ = nagq))
  w
}

#' B3 Binary GLMM: random-intercept logistic model (§10.1–10.2)
#'
#' @param nagq quadrature points; also refit with nagq/2 to check stability (checklist 13)
cc_glmm_binary <- function(data, id, y, x = character(), time = NULL, numeric = character(), ref = list(),
                           interactions = character(), success = NULL, nagq = 100, conf.level = 0.95) {
  pm <- .prepare_model(data, id, y, x, time, numeric, ref, interactions, "binary", success = success, family = "glmm")
  d <- pm$data; warnings <- pm$warnings; facts <- pm$facts
  f <- stats::as.formula(paste(".cc_y ~", pm$rhs, "+ (1 | .cc_id)"))
  warnings <- c(warnings, .check_separation(stats::as.formula(paste(".cc_y ~", pm$rhs)), d))
  main <- .fit_glmm(f, d, nagq)
  half <- .fit_glmm(f, d, max(1, nagq %/% 2))
  fit <- main$value
  conv <- unique(main$warnings[grepl("converge|singular|Hessian", main$warnings, ignore.case = TRUE)])
  if (length(conv)) {
    warnings[[length(warnings) + 1]] <- cc_warning("NOT_CONVERGED",
      sprintf("GLMM 配適時出現收斂相關的訊息：%s。估計值可能不可靠，請不要只依這個模型下結論。",
              paste(conv, collapse = "；")), "§10.1.5")
  }
  sigma <- attr(lme4::VarCorr(fit)$.cc_id, "stddev")[[1]]
  sigma_half <- attr(lme4::VarCorr(half$value)$.cc_id, "stddev")[[1]]
  fe <- lme4::fixef(fit); fe_half <- lme4::fixef(half$value)
  # Stable = every fixed effect and σ̂ moves by less than half a unit in the 3rd decimal
  # (comparing rounded values would flag 2.85313 vs 2.85359 just because of a rounding boundary).
  if (max(abs(fe - fe_half), abs(sigma - sigma_half)) > 5e-4) {
    warnings[[length(warnings) + 1]] <- cc_warning("QUADRATURE_UNSTABLE",
      sprintf("用 %d 點和 %d 點配適的估計值差異超過 0.0005（σ̂：%s vs %s），數值積分可能還沒穩定；以下報告 %d 點的結果。",
              max(1, nagq %/% 2), nagq, fmt_num(sigma_half), fmt_num(sigma), nagq), "§10.1.5")
  }
  vc <- as.matrix(stats::vcov(fit))
  est <- .coef_table(fe, sqrt(diag(vc)), conf.level)

  # Likelihood-ratio test for each term (GLMM has a likelihood, §10.1.6)
  tests <- data.frame()
  for (t in pm$terms) {
    others <- setdiff(pm$terms, t)
    label <- t
    if (!grepl(":", t)) {
      inter <- others[vapply(strsplit(others, ":"), function(p) t %in% p, TRUE)]
      others <- setdiff(others, inter)
      if (length(inter)) label <- sprintf("%s (with %s)", t, paste(inter, collapse = ", "))
    }
    f0 <- stats::as.formula(paste(".cc_y ~", .formula_rhs(others), "+ (1 | .cc_id)"))
    fit0 <- .fit_glmm(f0, d, nagq)$value
    lr <- 2 * (as.numeric(stats::logLik(fit)) - as.numeric(stats::logLik(fit0)))
    df <- attr(stats::logLik(fit), "df") - attr(stats::logLik(fit0), "df")
    tests <- rbind(tests, data.frame(test = sprintf("Likelihood-ratio: %s", label), statistic = lr, df = df,
                                     p_value = stats::pchisq(lr, df, lower.tail = FALSE), book_ref = "§10.1.6",
                                     stringsAsFactors = FALSE))
  }
  # sigma = 0 is on the boundary: P = half the chi-squared(1) right tail (§10.1.6)
  glm0 <- stats::glm(stats::as.formula(paste(".cc_y ~", pm$rhs)), family = stats::binomial, data = d)
  lr_s <- max(0, 2 * (as.numeric(stats::logLik(fit)) - as.numeric(stats::logLik(glm0))))
  tests <- rbind(tests, data.frame(test = "Random effect sigma = 0 (LR, half chi-squared)", statistic = lr_s, df = 1,
                                   p_value = 0.5 * stats::pchisq(lr_s, 1, lower.tail = FALSE), book_ref = "§10.1.6",
                                   stringsAsFactors = FALSE))
  same <- .all_same_share(d, ".cc_id", ".cc_y")
  facts <- c(facts,
    sprintf("隨機截距 logistic 模型（GLMM），成功 =「%s」，adaptive Gauss–Hermite %d 點。", pm$response$success, nagq),
    sprintf("隨機效果標準差 σ̂ = %s：叢集之間的差異%s。σ = 0 的檢定 LR = %s，P %s（χ²₁ 右尾的一半）。",
            fmt_num(sigma), if (sigma > 0) "越大，同一叢集內的回答越相像" else "估計為 0",
            fmt_num(lr_s, 2), fmt_p(0.5 * stats::pchisq(lr_s, 1, lower.tail = FALSE))),
    if (!is.na(same)) sprintf("有 %s 的叢集（≥ 2 筆）所有回答都相同。", fmt_pct(same)),
    vapply(seq_len(nrow(est))[-1], function(r) sprintf(
      "%s：對同一個叢集（隨機效果相同時），勝算比 = %s（%d%% 信賴區間 %s 到 %s），Wald P %s。", est$term[r],
      fmt_num(est$odds_ratio[r]), round(conf.level * 100), fmt_num(est$or_lower[r]), fmt_num(est$or_upper[r]),
      fmt_p(est$p_value[r])), ""),
    vapply(seq_len(nrow(tests) - 1), function(r) sprintf("%s = %s（df = %d），P %s。",
      tests$test[r], fmt_num(tests$statistic[r], 2), as.integer(tests$df[r]), fmt_p(tests$p_value[r])), ""))
  cc_result("glmm_binary", "Random-intercept logistic model (GLMM)", "§10.1–10.2", "A",
            estimates = est, tests = tests,
            tables = list(proportions = .time_proportions(d, time, pm$y, pm$response$success),
                          quadrature_check = data.frame(nAGQ = c(max(1, nagq %/% 2), nagq),
                                                        sigma = c(sigma_half, sigma),
                                                        rbind(fe_half, fe), row.names = NULL, check.names = FALSE)),
            warnings = warnings, facts = facts,
            notes = list(effect_type = "subject-specific", sigma = sigma, all_same_share = same, nAGQ = nagq,
                         clusters = pm$clusters, cluster_level = pm$cluster_level, predictors = pm$predictors,
                         reminder = "勝算比是「同一個叢集內」的效果（隨機效果固定時），不是整體平均（§10.1.4）。"))
}

#' B4 GEE and GLMM side by side (§10.1.4, §10.2.5, Table 10.3)
cc_compare_gee_glmm <- function(data, id, y, x = character(), time = NULL, numeric = character(), ref = list(),
                                interactions = character(), success = NULL, corstr = "exchangeable",
                                nagq = 100, conf.level = 0.95) {
  gee <- cc_gee_binary(data, id, y, x, time, numeric, ref, interactions, success, corstr, conf.level = conf.level)
  glmm <- cc_glmm_binary(data, id, y, x, time, numeric, ref, interactions, success, nagq, conf.level)
  tab <- data.frame(term = gee$estimates$term,
                    gee_estimate = gee$estimates$estimate, gee_se = gee$estimates$se,
                    glmm_estimate = glmm$estimates$estimate, glmm_se = glmm$estimates$se,
                    stringsAsFactors = FALSE)
  tab$ratio <- ifelse(abs(tab$gee_estimate) > 1e-8, tab$glmm_estimate / tab$gee_estimate, NA)
  tab$gee_or <- exp(tab$gee_estimate); tab$glmm_or <- exp(tab$glmm_estimate)
  tab$gee_or_reverse <- exp(-tab$gee_estimate); tab$glmm_or_reverse <- exp(-tab$glmm_estimate)
  warnings <- gee$warnings
  for (w in glmm$warnings) if (!w$code %in% vapply(warnings, `[[`, "", "code")) warnings[[length(warnings) + 1]] <- w
  same <- glmm$notes$all_same_share
  if (!is.na(same)) {
    warnings[[length(warnings) + 1]] <- cc_warning("ALL_SAME_RESPONSE",
      sprintf("有 %s 的叢集所有回答都相同，σ̂ = %s：叢集之間差異越大，GLMM（同一個叢集）的效果就比 GEE（整體平均）大越多，SE 也一樣變大。這不是錯誤。",
              fmt_pct(same), fmt_num(glmm$notes$sigma)), "§10.1.4、§10.2.3")
  }
  rows <- tab[-1, ]
  facts <- c(
    sprintf("同一份資料（%d 個叢集、%d 筆）分別配適 GEE（整體平均）與 GLMM（同一個叢集）。",
            gee$notes$clusters$n_clusters, gee$notes$clusters$n_obs),
    vapply(seq_len(nrow(rows)), function(r) sprintf(
      "%s：GEE 估計 %s（SE %s）、GLMM 估計 %s（SE %s），GLMM / GEE = %s。", rows$term[r],
      fmt_num(rows$gee_estimate[r]), fmt_num(rows$gee_se[r]), fmt_num(rows$glmm_estimate[r]),
      fmt_num(rows$glmm_se[r]), if (is.na(rows$ratio[r])) "—" else fmt_num(rows$ratio[r], 2)), ""),
    sprintf("GLMM 的隨機效果標準差 σ̂ = %s；GEE 的 working correlation 估計 = %s。", fmt_num(glmm$notes$sigma),
            if (length(gee$notes$working_correlation)) paste(fmt_num(gee$notes$working_correlation), collapse = ", ") else "—"),
    "兩者回答不同的問題：GEE 是母體中隨機抽的人的平均效果，GLMM 是固定同一個叢集時的效果；邏輯連結下，σ 越大，整體平均的效果越接近 0（§10.1.4）。")
  cc_result("compare_gee_glmm", "GEE (population-averaged) vs GLMM (subject-specific)", "§10.1.4, §10.2.5", "A",
            estimates = tab, tests = rbind(gee$tests, glmm$tests),
            tables = list(proportions = gee$tables$proportions),
            warnings = warnings, facts = facts,
            notes = list(gee = unclass(gee)[c("estimates", "facts", "notes")],
                         glmm = unclass(glmm)[c("estimates", "facts", "notes")],
                         reminder = "兩個模型的數字不同不代表其中一個算錯；結論通常相同（§10.2.3）。"))
}

# Descriptive tables used by the report and plots (computed here, never by the model).
.time_proportions <- function(d, time, y, success) {
  if (is.null(time)) {
    return(data.frame(n = nrow(d), successes = sum(d$.cc_y), proportion = mean(d$.cc_y)))
  }
  g <- split(d$.cc_y, d[[time]])
  data.frame(time = names(g), n = vapply(g, length, 0L), successes = vapply(g, sum, 0),
             proportion = vapply(g, mean, 0), row.names = NULL, stringsAsFactors = FALSE)
}

.time_distribution <- function(d, time, y, lv) {
  grp <- if (is.null(time)) rep("all", nrow(d)) else as.character(d[[time]])
  tab <- table(grp, factor(lv[d$.cc_y], levels = lv))
  prop <- prop.table(tab, 1)
  out <- data.frame(time = rownames(tab), n = as.integer(rowSums(tab)), stringsAsFactors = FALSE)
  for (j in seq_along(lv)) out[[paste0("prop_", lv[j])]] <- as.numeric(prop[, j])
  out
}
