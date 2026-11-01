# 課本例子的資料：由書中印出的表格重建成長格式（一人一個時間點一列）
# Agresti (2019), An Introduction to Categorical Data Analysis, 3rd ed.

# 方陣 c×c（列 = 第一次、欄 = 第二次）→ 長格式 person, time(1 = 第一次, 0 = 第二次), y
square_to_long <- function(tab) {
  idx <- which(tab > 0, arr.ind = TRUE)
  y1 <- rep(idx[, 1], tab[idx])
  y2 <- rep(idx[, 2], tab[idx])
  n <- length(y1)
  long <- data.frame(person = rep(seq_len(n), each = 2),
                     time = rep(c(1, 0), n),
                     y = as.vector(rbind(y1, y2)))
  long
}

# Table 8.1：環境意見（付較高的稅 × 降低生活水準），1 = yes、2 = no
tab_8_1 <- matrix(c(227, 107, 132, 678), 2,
                  dimnames = list(taxes = c("yes", "no"), living = c("yes", "no")))

# Table 8.5：兩次購買的咖啡品牌
tab_8_5 <- matrix(c(93, 17, 44, 7, 10,
                    9, 46, 11, 0, 9,
                    17, 11, 155, 9, 12,
                    6, 4, 9, 15, 2,
                    10, 4, 12, 2, 27), 5, byrow = TRUE,
                  dimnames = list(first = c("HighPoint", "Tasters", "Sanka", "Nescafe", "Brim"),
                                  second = c("HighPoint", "Tasters", "Sanka", "Nescafe", "Brim")))

# Table 8.6：回收（列）× 少開車（欄），1 = always … 4 = never
tab_8_6 <- matrix(c(12, 43, 163, 233,
                    4, 21, 99, 185,
                    4, 8, 77, 230,
                    0, 1, 18, 132), 4, byrow = TRUE,
                  dimnames = list(recycle = c("always", "often", "sometimes", "never"),
                                  drive = c("always", "often", "sometimes", "never")))

# Table 9.1：三種情境是否支持墮胎合法化，依性別（gender 1 = female）
abortion_long <- function() {
  seqs <- list(c(1,1,1), c(1,1,0), c(0,1,1), c(0,1,0), c(1,0,1), c(1,0,0), c(0,0,1), c(0,0,0))
  male <- c(342, 26, 6, 21, 11, 32, 19, 356)
  female <- c(440, 25, 14, 18, 14, 47, 22, 457)
  out <- list(); pid <- 0
  for (g in c(0, 1)) {
    counts <- if (g == 0) male else female
    for (k in seq_along(seqs)) {
      for (r in seq_len(counts[k])) {
        pid <- pid + 1
        out[[pid]] <- data.frame(person = pid, gender = g, situation = 1:3, response = seqs[[k]])
      }
    }
  }
  do.call(rbind, out)
}

# Table 9.2：失眠試驗，入睡時間（1 <20、2 20–30、3 30–60、4 >60），treat 1 = active
insomnia_long <- function() {
  active <- matrix(c(7, 4, 1, 0, 11, 5, 2, 2, 13, 23, 3, 1, 9, 17, 13, 8), 4, byrow = TRUE)
  placebo <- matrix(c(7, 4, 2, 1, 14, 5, 1, 0, 6, 9, 18, 2, 4, 11, 14, 22), 4, byrow = TRUE)
  out <- list(); pid <- 0
  for (tr in c(1, 0)) {
    tab <- if (tr == 1) active else placebo
    for (i in 1:4) for (j in 1:4) for (r in seq_len(tab[i, j])) {
      pid <- pid + 1
      out[[pid]] <- data.frame(case = pid, treat = tr, occasion = c(0, 1), response = c(i, j))
    }
  }
  do.call(rbind, out)
}
