# 方法速查與 R 程式碼

每個方法：用途、H₀、統計量、效果量、R 程式碼。
沒有 R 也不能執行 Python 時，把這裡的程式碼依使用者的欄位名稱改好，交給使用者在 R／RStudio 執行並貼回輸出；**只能用這裡的程式碼，不可以自己另外寫統計程式**。

這裡所有程式碼都用課本的例子驗證過，數字和課本一致（`dev/verify_methods.R`，45 項）。

需要的套件：

```r
install.packages(c("PropCIs", "geepack", "multgee", "lme4"))
```

## 共同：資料格式

本 Skill 的模型都用**長格式**：一個叢集的每次測量各一列。

| id | time | y | 其他解釋變數 |
|---|---|---|---|
| 1 | 1 | 1 | … |
| 1 | 0 | 0 | … |

寬格式轉長格式（一人一列、兩次測量在 `y1`、`y2` 兩欄）：

```r
long <- data.frame(
  id   = rep(seq_len(nrow(wide)), each = 2),
  time = rep(c(1, 0), nrow(wide)),          # 1 = 第一次（y1），0 = 第二次（y2）
  y    = as.vector(rbind(wide$y1, wide$y2))
)
```

`geeglm`、`ordLORgee`、`nomLORgee` 要求**同一個叢集的資料連續排列**：先 `long <- long[order(long$id), ]`。

---

## A1　二元配對：McNemar 檢定（§8.1、§8.2.4）

| | |
|---|---|
| 用途 | 同一批人兩次的「成功」比例是否相同 |
| H₀ | 邊際同質性 P(Y₁ = 1) = P(Y₂ = 1)，等價於 π₁₂ = π₂₁ |
| 統計量 | z = (n₁₂ − n₂₁)/√(n₁₂ + n₂₁)，z² ~ χ²₁（n₁₂ + n₂₁ > 10 時） |
| 效果量 | 邊際比例差與 score 信賴區間；條件勝算比 n₁₂/n₂₁（個體層次） |

```r
library(PropCIs)
tab <- xtabs(~ y1 + y2, data = wide)       # 列 = 第一次、欄 = 第二次，第 1 類 = 成功
mcnemar.test(tab, correct = FALSE)          # 課本不用連續性校正（太保守）

n12 <- tab[1, 2]; n21 <- tab[2, 1]; n <- sum(tab)
p1 <- sum(tab[1, ]) / n                     # 第一次的成功比例
p2 <- sum(tab[, 1]) / n                     # 第二次的成功比例
p1 - p2                                     # 邊際比例差
scoreci.mp(n21, n12, n, 0.95)               # 比例差的 score 信賴區間（注意參數順序）
n12 / n21                                   # 條件勝算比（個體層次，§8.2.4）

# n12 + n21 <= 10 時改用精確二項檢定
binom.test(n12, n12 + n21, p = 0.5)
```

課本對照（Table 8.1）：X² = 2.615，P = 0.106；比例差 0.022，score CI (−0.005, 0.048)；條件勝算比 132/107 = 1.23。

---

## A2　名目配對：邊際同質性（§8.3）

| | |
|---|---|
| 用途 | 同一批人兩次的類別分布是否相同（類別沒有順序） |
| H₀ | 每一類的邊際比例都相同 |
| 統計量 | 對稱模型與準對稱模型的 deviance 差，~ χ²(c−1)（§8.3.4） |
| 追蹤 | 各類別「該類 vs 其他」合併成 2×2，做 McNemar（§8.3.2） |

```r
tab <- xtabs(~ y1 + y2, data = wide)        # c × c 方陣，列與欄的類別順序相同

# 把每一對 (n_ij, n_ji) 當成一個二項觀察值
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
d <- qs_data(tab)

symm <- glm(nij / (nij + nji) ~ -1, family = binomial, weights = nij + nji, data = d)
qs_formula <- as.formula(paste("nij / (nij + nji) ~ -1 +",
                               paste(paste0("b", 1:(nrow(tab) - 1)), collapse = " + ")))
qs <- glm(qs_formula, family = binomial, weights = nij + nji, data = d)

lr <- deviance(symm) - deviance(qs)
df <- df.residual(symm) - df.residual(qs)   # = c - 1
pchisq(lr, df, lower.tail = FALSE)

# 追蹤：第 k 類 vs 其他
k <- 1
tab2 <- matrix(c(tab[k, k], sum(tab[-k, k]), sum(tab[k, -k]), sum(tab[-k, -k])), 2)
mcnemar.test(tab2, correct = FALSE)
```

課本對照（Table 8.5 咖啡）：對稱 22.47（df 10）、準對稱 9.97（df 6），差 12.50，df = 4，P = 0.014。

另一種做法（輸出可對照）：GEE 的 baseline-category logit 邊際模型（`multgee::nomLORgee`＋`waldts`，Wald = 12.49）或 CMH 檢定（`mantelhaen.test(time, y, id)`，12.29），見 B2。

---

## A3　有序配對：累積 logit 邊際模型（§8.4）

| | |
|---|---|
| 用途 | 同一批人兩次的回答是否整體偏高或偏低 |
| 模型 | logit P(Y₁ ≤ j) = αⱼ + β，logit P(Y₂ ≤ j) = αⱼ（比例勝算） |
| H₀ | β = 0（邊際同質性），df = 1 |
| 效果量 | exp(β)：第一次落在「j 或以下」的勝算是第二次的幾倍（對每個切點相同） |

```r
library(multgee)
long <- long[order(long$id), ]               # y 是 1, 2, …, c（由低到高）
fit <- ordLORgee(y ~ time, id = id, LORstr = "independence", data = long)
summary(fit)                                 # time 的 Estimate = β、san.se = robust SE
```

輔助（§8.4.3*，只用 `glm`）：有序準對稱模型，β 的意義是「高 x 類」的方向

```r
d <- qs_data(tab, scores = 1:nrow(tab))     # 類別分數，預設等距
oqs <- glm(nij / (nij + nji) ~ -1 + x, family = binomial, weights = nij + nji, data = d)
lr <- deviance(symm) - deviance(oqs)        # df = 1
```

課本對照（Table 8.6）：β̂ = 2.754（robust SE 0.081）；有序準對稱 β̂ = 2.394，deviance 4.41（df 5）。

> 正負號：`multgee` 和課本一樣是 logit P(Y ≤ j) = αⱼ + βx。β > 0 表示 x = 1 的那次回答**偏低**（較常落在前面的類別）。解釋時要換成使用者的類別名稱。

---

## B1　二元 GEE：邊際 logistic 模型（§9.1–9.2）

| | |
|---|---|
| 用途 | 重複測量或叢集資料，解釋變數對「整體平均」成功機率的效果 |
| 模型 | logit P(Yₜ = 1) = α + βₜ + γx |
| 推論 | robust（sandwich）SE 的 Wald 檢定；**沒有** LR 檢定 |
| 效果量 | exp(β)：整體來說的勝算比 |

```r
library(geepack)
long <- long[order(long$id), ]
fit <- geeglm(y ~ factor(time) + x, id = id, family = binomial,
              corstr = "exchangeable", data = long)
summary(fit)                # Std.err 就是 robust SE；Estimated Correlation Parameters 是 ρ̂
anova(fit)                  # 每個變數的 Wald 檢定（依序加入）
exp(coef(fit))              # 勝算比
```

課本對照（Table 9.1，情境 3 為參考組）：sit1 = 0.149（robust SE 0.030），gender = 0.003，ρ̂ = 0.817；控制性別後情境的 Wald = 26.02，df = 2。

---

## B2　多類別 GEE（§9.3）

```r
library(multgee)
long <- long[order(long$id), ]
# 有序結果：累積 logit
fit <- ordLORgee(y ~ time * x, id = id, LORstr = "independence", data = long)
# 名目結果：baseline-category logit（最後一類為基準）
fit <- nomLORgee(y ~ time + x, id = id, LORstr = "independence", data = long)
summary(fit)

# 變數整體效果：比較兩個模型的 Wald 檢定
fit0 <- ordLORgee(y ~ time + x, id = id, LORstr = "independence", data = long)
waldts(fit0, fit)
```

課本對照（Table 9.2 失眠）：交互作用 0.708（robust SE 0.244），z = 2.91。

---

## B3　二元 GLMM：隨機截距 logistic（§10.1–10.2）

| | |
|---|---|
| 用途 | 解釋變數對「同一個人」成功勝算的效果；或估計每個叢集自己的機率 |
| 模型 | logit P(Yᵢₜ = 1) = uᵢ + α + βₜ + γxᵢ，uᵢ ~ N(0, σ²) |
| 推論 | 固定效果：Wald 或 LR 檢定；σ = 0：LR 檢定，P 值取 χ²₁ 右尾的一半 |
| 效果量 | exp(β)：對同一個人（uᵢ 相同時）的勝算比；σ̂：個體差異的大小 |

```r
library(lme4)
fit <- glmer(y ~ (1 | id) + factor(time) + x, family = binomial, nAGQ = 100, data = long)
summary(fit)                               # Random effects 的 Std.Dev. = σ̂
fixef(fit); exp(fixef(fit))

# 檢查 quadrature 點數：估計值應該穩定（§10.1.5）
fit50 <- update(fit, nAGQ = 50)
cbind(nAGQ50 = fixef(fit50), nAGQ100 = fixef(fit))
c(attr(VarCorr(fit50)$id, "stddev"), attr(VarCorr(fit)$id, "stddev"))   # σ̂ 最敏感

# 固定效果的 LR 檢定（例如 x）
fit_no_x <- update(fit, . ~ . - x)
anova(fit_no_x, fit)

# σ = 0 的檢定（§10.1.6）：和沒有隨機效果的 glm 比，P 值取一半
fit_glm <- glm(y ~ factor(time) + x, family = binomial, data = long)
lr <- 2 * (as.numeric(logLik(fit)) - as.numeric(logLik(fit_glm)))
0.5 * pchisq(lr, df = 1, lower.tail = FALSE)
```

注意：

- 預設用 100 點、再和 50 點比較。σ 很大時點數少會不準：課本墮胎例（σ̂ = 8.75），10 點得 σ̂ = 10.63、25 點 9.34、50 點 8.79、100 點 8.75；sit1 在 25 點是 0.841，100 點是 0.835。
- `nAGQ > 1` 只能用在**只有一個隨機截距**的模型（`lme4` 的限制）。
- 比較 GLMM 與 glm 要用 `logLik`，不要用 `deviance()`：`lme4` 的 `deviance()` 和 glm 的 residual deviance 尺度不同。
- 每列是彙整次數時（y 次成功、T 次嘗試）：`glmer(y / T ~ 1 + (1 | id), family = binomial, weights = T, nAGQ = 100)`。

課本對照：
- Table 10.1：β̂ = 0.210（SE 0.130），σ̂ = 2.85
- Table 9.1（§10.2.3）：sit1 = 0.835（SE 0.160），σ̂ = 8.75
- 罰球（§10.2.2）：σ = 0 的 LR = 1.57，χ²₁ 右尾 0.21，P = 0.21/2 ≈ 0.11

---

## B4　GEE 與 GLMM 並排（§10.1.4、§10.2.5）

```r
gee  <- geeglm(y ~ factor(time) + x, id = id, family = binomial,
               corstr = "exchangeable", data = long)
glmm <- glmer(y ~ (1 | id) + factor(time) + x, family = binomial, nAGQ = 100, data = long)
data.frame(
  GEE_est  = coef(gee),  GEE_se  = summary(gee)$coefficients[, "Std.err"],
  GLMM_est = fixef(glmm), GLMM_se = sqrt(diag(as.matrix(vcov(glmm))))
)
```

課本對照（Table 10.3）：

| 效果 | GLMM | GEE |
|---|---|---|
| β₁ − β₃ | 0.835 (0.160) | 0.149 (0.030) |
| γ（性別） | 0.013 (0.490) | 0.003 (0.088) |
| σ | 8.75 | — |

解釋重點：GLMM 的估計值約為 GEE 的 5–6 倍，SE 也一樣，所以結論相同；差異來自很大的個體差異（σ̂ = 8.75），不是任何一方算錯。
