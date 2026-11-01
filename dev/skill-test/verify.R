# 獨立驗證：不使用 skill 的引擎（categorical-correlated/R），直接呼叫 R 套件計算實測題目的數字，
# 用來核對 skill 在新對話中輸出的 result.json。
# 執行（在 Part3 資料夾）：Rscript dev/skill-test/verify.R

suppressPackageStartupMessages({ library(multgee); library(geepack); library(lme4) })
d <- read.csv("dev/demo/student_por.csv")
out <- list()

# q1 Dalc vs Walc：有序配對，累積 logit 邊際模型（§8.4.2）
n <- nrow(d)
long1 <- data.frame(id = rep(seq_len(n), each = 2), time = rep(c(1, 0), n),
                    occ = rep(1:2, n), y = as.vector(rbind(d$Dalc, d$Walc)))
f1 <- ordLORgee(y ~ time, id = id, repeated = occ, LORstr = "independence", data = long1)
s1 <- summary(f1)$coefficients
out$q1 <- list(beta = s1["time", 1], robust_se = s1["time", 2],
               or_dalc_higher = exp(-s1["time", 1]),
               mean_dalc = mean(d$Dalc), mean_walc = mean(d$Walc))

# q2 Mjob vs Fjob：名目配對，對稱 vs 準對稱 LR（§8.3.4）與 CMH（§8.3.3）
lv <- sort(unique(c(d$Mjob, d$Fjob)))
tab <- table(factor(d$Mjob, lv), factor(d$Fjob, lv))
pairs <- t(combn(length(lv), 2))
X <- matrix(0, nrow(pairs), length(lv))
X[cbind(seq_len(nrow(pairs)), pairs[, 1])] <- 1
X[cbind(seq_len(nrow(pairs)), pairs[, 2])] <- -1
qd <- data.frame(X, nij = tab[pairs], nji = tab[pairs[, 2:1]])
symm <- glm(nij / (nij + nji) ~ -1, binomial, weights = nij + nji, data = qd)
qs <- glm(nij / (nij + nji) ~ -1 + X1 + X2 + X3 + X4, binomial, weights = nij + nji, data = qd)
long2 <- data.frame(id = rep(seq_len(n), 2), time = rep(1:2, each = n), y = c(d$Mjob, d$Fjob))
cmh <- mantelhaen.test(factor(long2$time), factor(long2$y), factor(long2$id))
out$q2 <- list(lr = deviance(symm) - deviance(qs), df = df.residual(symm) - df.residual(qs),
               cmh = unname(cmh$statistic),
               prop_mother = as.list(round(rowSums(tab) / n, 4)), prop_father = as.list(round(colSums(tab) / n, 4)))

# q3 G1–G3 及格（≥ 10）× 性別：GEE exchangeable（§9.2）與隨機截距 GLMM（§10.1–10.2）
long3 <- data.frame(id = rep(seq_len(n), each = 3), period = factor(rep(1:3, n)),
                    sex = factor(rep(d$sex, each = 3), levels = c("F", "M")),
                    pass = as.integer(as.vector(t(as.matrix(d[, c("G1", "G2", "G3")]))) >= 10))
g <- geeglm(pass ~ period + sex, id = id, family = binomial, corstr = "exchangeable", data = long3)
m <- glmer(pass ~ period + sex + (1 | id), family = binomial, nAGQ = 100, data = long3)
out$q3 <- list(
  prop_by_period = as.list(round(tapply(long3$pass, long3$period, mean), 4)),
  gee = list(coef = as.list(coef(g)), robust_se = as.list(sqrt(diag(vcov(g)))), alpha = unname(g$geese$alpha)),
  glmm = list(coef = as.list(fixef(m)), se = as.list(sqrt(diag(as.matrix(vcov(m))))),
              sigma = unname(attr(VarCorr(m)$id, "stddev"))),
  all_same_share = mean(tapply(long3$pass, long3$id, function(z) length(unique(z)) == 1)))

jsonlite::write_json(out, "dev/skill-test/verify_results.json", auto_unbox = TRUE, digits = 6, pretty = TRUE)
str(out, max.level = 3, digits.d = 5)
