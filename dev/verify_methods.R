# 驗證 references/methods.md 的 R 程式碼：每個方法都要重現課本印出的數字
# 執行：Rscript dev/verify_methods.R（在 Part3 資料夾）

suppressPackageStartupMessages({
  library(PropCIs); library(geepack); library(multgee); library(lme4)
})
source("dev/textbook_data.R")

results <- data.frame(item = character(), got = numeric(), book = numeric(), tol = numeric())
check <- function(item, got, book, tol) {
  got <- suppressWarnings(as.numeric(unlist(got))[1])
  results[nrow(results) + 1, ] <<- list(item, round(got, 5), book, tol)
}

# ---- 配對資料的準對稱模型用的資料（§8.3.4、§8.4.3）----
qs_data <- function(tab, scores = seq_len(nrow(tab))) {
  k <- nrow(tab)
  pr <- t(combn(k, 2))
  X <- matrix(0, nrow(pr), k)
  X[cbind(seq_len(nrow(pr)), pr[, 1])] <- 1
  X[cbind(seq_len(nrow(pr)), pr[, 2])] <- -1
  colnames(X) <- paste0("b", seq_len(k))
  data.frame(X, x = scores[pr[, 2]] - scores[pr[, 1]],
             nij = tab[pr], nji = tab[pr[, 2:1]])
}

# ---- A1 McNemar（§8.1）----
tab <- tab_8_1
mc <- mcnemar.test(tab, correct = FALSE)
check("A1 McNemar X2", mc$statistic, 2.6151, 1e-4)
ci <- scoreci.mp(tab[2, 1], tab[1, 2], sum(tab), 0.95)$conf.int
check("A1 score CI lower", ci[1], -0.00466, 1e-5)
check("A1 score CI upper", ci[2], 0.04849, 1e-5)
p1 <- sum(tab[1, ]) / sum(tab); p2 <- sum(tab[, 1]) / sum(tab)
check("A1 difference", p1 - p2, 0.022, 5e-4)
check("A1 conditional OR n12/n21", tab[1, 2] / tab[2, 1], 1.23, 5e-3)
# Table 8.3 配對 case-control：條件勝算比 22/8
check("A1 matched case-control OR", 22 / 8, 2.75, 1e-6)

# ---- A2 名目：邊際同質性（§8.3）----
d <- qs_data(tab_8_5)
symm <- glm(nij / (nij + nji) ~ -1, family = binomial, weights = nij + nji, data = d)
qs <- glm(nij / (nij + nji) ~ -1 + b1 + b2 + b3 + b4, family = binomial,
          weights = nij + nji, data = d)
check("A2 symmetry deviance", deviance(symm), 22.473, 1e-3)
check("A2 quasi-symmetry deviance", deviance(qs), 9.974, 1e-3)
lr <- deviance(symm) - deviance(qs)
check("A2 MH LR", lr, 12.50, 5e-3)
check("A2 MH P", pchisq(lr, df.residual(symm) - df.residual(qs), lower.tail = FALSE), 0.014, 5e-4)
# methods.md 的通用寫法（qs_formula）要和上面相同
tab <- tab_8_5
qs_formula <- as.formula(paste("nij / (nij + nji) ~ -1 +",
                               paste(paste0("b", 1:(nrow(tab) - 1)), collapse = " + ")))
qs2 <- glm(qs_formula, family = binomial, weights = nij + nji, data = d)
check("A2 generic QS deviance", deviance(qs2), 9.974, 1e-3)
check("A2 df", df.residual(symm) - df.residual(qs2), 4, 0)
# 追蹤：High Point vs 其他（§8.3.2：(93, 78 / 42, 328)，z = 3.3）
k <- 1
tab2 <- matrix(c(tab[k, k], sum(tab[-k, k]), sum(tab[k, -k]), sum(tab[-k, -k])), 2)
check("A2 follow-up n12", tab2[1, 2], 78, 0)
check("A2 follow-up n21", tab2[2, 1], 42, 0)
check("A2 follow-up z", sqrt(mcnemar.test(tab2, correct = FALSE)$statistic), 3.3, 0.05)
coffee <- square_to_long(tab_8_5)
cmh <- with(coffee, mantelhaen.test(factor(time), factor(y), factor(person)))
check("A2 CMH M2", cmh$statistic, 12.291, 1e-3)
fit_nom <- nomLORgee(y ~ time, id = person, LORstr = "independence", data = coffee)
fit_nom0 <- nomLORgee(y ~ 1, id = person, LORstr = "independence", data = coffee)
wt <- waldts(fit_nom0, fit_nom)
check("A2 GEE Wald", wt$waldstatistic, 12.4869, 1e-3)

# ---- A3 有序：累積 logit 邊際模型（§8.4.2）與有序準對稱（§8.4.3）----
envir <- square_to_long(tab_8_6)
fit_ord <- ordLORgee(y ~ time, id = person, LORstr = "independence", data = envir)
s <- summary(fit_ord)$coefficients
check("A3 GEE beta", s["time", 1], 2.75361, 1e-4)
check("A3 GEE robust SE", s["time", 2], 0.08147, 1e-4)
d6 <- qs_data(tab_8_6)
symm6 <- glm(nij / (nij + nji) ~ -1, family = binomial, weights = nij + nji, data = d6)
oqs <- glm(nij / (nij + nji) ~ -1 + x, family = binomial, weights = nij + nji, data = d6)
check("A3 ordinal QS beta", coef(oqs)["x"], 2.3936, 1e-4)
check("A3 ordinal QS deviance", deviance(oqs), 4.4139, 1e-3)
check("A3 symmetry deviance", deviance(symm6), 1106.124, 1e-2)

# ---- B1 二元 GEE（§9.2）----
ab <- abortion_long()
ab$sit <- factor(ab$situation, levels = c(3, 1, 2))
fit_gee <- geeglm(response ~ sit + gender, id = person, family = binomial,
                  corstr = "exchangeable", data = ab)
cg <- summary(fit_gee)$coefficients
check("B1 GEE sit1", cg["sit1", 1], 0.14935, 1e-4)
check("B1 GEE sit1 robust SE", cg["sit1", 2], 0.02974, 2e-4)
check("B1 GEE gender", cg["gender", 1], 0.00344, 1e-4)
check("B1 GEE rho", summary(fit_gee)$corr[1, 1], 0.81733, 1e-3)
fit_gee2 <- geeglm(response ~ gender + factor(situation), id = person, family = binomial,
                   corstr = "exchangeable", data = ab)
check("B1 GEE Wald situation", anova(fit_gee2)["factor(situation)", "X2"], 26.0171, 1e-2)

# ---- B2 有序 GEE（§9.3）----
ins <- insomnia_long()
fit_ins <- ordLORgee(response ~ occasion + treat + occasion:treat, id = case,
                     LORstr = "independence", data = ins)
si <- summary(fit_ins)$coefficients
check("B2 GEE interaction", si["occasion:treat", 1], 0.70776, 1e-4)
check("B2 GEE interaction SE", si["occasion:treat", 2], 0.24352, 1e-4)

# ---- B3 GLMM（§10.1–10.2）----
op <- square_to_long(tab_8_1)
op$y <- as.integer(op$y == 1)
fit_m <- glmer(y ~ (1 | person) + time, family = binomial, nAGQ = 50, data = op)
check("B3 GLMM beta (Table 10.1)", fixef(fit_m)["time"], 0.2100, 1e-3)
check("B3 GLMM sigma (Table 10.1)", attr(VarCorr(fit_m)$person, "stddev"), 2.854, 1e-3)
fit_ab <- glmer(response ~ (1 | person) + sit + gender, family = binomial, nAGQ = 100, data = ab)
check("B3 GLMM sit1", fixef(fit_ab)["sit1"], 0.83478, 1e-3)
check("B3 GLMM sit1 SE", sqrt(vcov(fit_ab)["sit1", "sit1"]), 0.16004, 1e-3)
check("B3 GLMM sigma", attr(VarCorr(fit_ab)$person, "stddev"), 8.746, 1e-2)

# quadrature 點數檢查與固定效果 LR 檢定（methods.md B3）
# σ 很大時（8.75）點數太少不穩定：25 點和 100 點差 0.006、σ̂ 9.34 vs 8.75（§10.1.5 的警告）
fit_ab25 <- update(fit_ab, nAGQ = 25)
check("B3 nAGQ 25 unstable (diff > 0.005)", abs(fixef(fit_ab25)["sit1"] - fixef(fit_ab)["sit1"]) > 0.005, 1, 0)
fit_ab50 <- update(fit_ab, nAGQ = 50)
check("B3 nAGQ 50 vs 100 sit1 diff < 0.002", abs(fixef(fit_ab50)["sit1"] - fixef(fit_ab)["sit1"]) < 0.002, 1, 0)
fit_ab_nog <- update(fit_ab, . ~ . - gender)
check("B3 LR gender P > 0.9", anova(fit_ab_nog, fit_ab)[2, "Pr(>Chisq)"] > 0.9, 1, 0)

# B4 並排表（Table 10.3）
tab_b4 <- data.frame(
  GEE_est  = coef(fit_gee),  GEE_se  = summary(fit_gee)$coefficients[, "Std.err"],
  GLMM_est = fixef(fit_ab), GLMM_se = sqrt(diag(as.matrix(vcov(fit_ab))))
)
check("B4 GEE sit1", tab_b4["sit1", "GEE_est"], 0.149, 1e-3)
check("B4 GLMM sit1", tab_b4["sit1", "GLMM_est"], 0.835, 1e-3)
check("B4 GLMM gender SE", tab_b4["gender", "GLMM_se"], 0.490, 1e-3)
check("B4 GEE gender SE", tab_b4["gender", "GEE_se"], 0.088, 1e-3)

# σ = 0 的邊界檢定（§10.1.6、§10.2.2 罰球例）
ft <- data.frame(T = c(39, 49, 21, 13, 19, 14, 3, 12, 19, 16, 13, 3, 6, 7, 8, 13, 6, 8, 10, 14),
                 p = c(.82, .78, .52, .77, .84, .86, .33, .83, .63, .50,
                       .92, .67, 1.00, 1.00, .62, .92, .67, .62, .80, .79))
ft$y <- round(ft$p * ft$T); ft$player <- factor(seq_len(nrow(ft)))
fit_ft <- glmer(y / T ~ 1 + (1 | player), family = binomial, weights = T, nAGQ = 100, data = ft)
fit_ft0 <- glm(y / T ~ 1, family = binomial, weights = T, data = ft)
# lme4 的 deviance() 和 glm 的 residual deviance 尺度不同，要用 logLik 相減
lr_sigma <- 2 * (as.numeric(logLik(fit_ft)) - as.numeric(logLik(fit_ft0)))
check("B3 total made (book 222)", sum(ft$y), 222, 0)
check("B3 sigma LR", lr_sigma, 1.56, 0.01)
# 課本：「P 值是 χ²₁ 右尾機率的一半，右尾機率為 0.21」→ P = 0.21 / 2
check("B3 sigma chi2 right tail", pchisq(lr_sigma, 1, lower.tail = FALSE), 0.21, 0.01)
check("B3 sigma P (half chi2)", 0.5 * pchisq(lr_sigma, 1, lower.tail = FALSE), 0.105, 0.005)

results$ok <- abs(results$got - results$book) <= results$tol
print(results, row.names = FALSE)
cat(sprintf("\n%d / %d 和課本一致\n", sum(results$ok), nrow(results)))
