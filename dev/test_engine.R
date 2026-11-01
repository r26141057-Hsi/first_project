# Engine tests: every analysis function must reproduce the textbook numbers.
# Run from the Part3 folder: Rscript dev/test_engine.R

suppressPackageStartupMessages({ library(lme4) })
engine <- "categorical-correlated/R"
for (f in c("utils.R", setdiff(list.files(engine, pattern = "\\.R$"), "utils.R"))) source(file.path(engine, f), encoding = "UTF-8")
source("dev/textbook_data.R")

results <- data.frame(item = character(), got = numeric(), book = numeric(), tol = numeric())
check <- function(item, got, book, tol) {
  got <- suppressWarnings(as.numeric(unlist(got))[1])
  results[nrow(results) + 1, ] <<- list(item, round(got, 5), book, tol)
}
est <- function(res, measure, col = "estimate") res$estimates[res$estimates$measure == measure, col]
test_stat <- function(res, pattern, col = "statistic") res$tests[grepl(pattern, res$tests$test, fixed = TRUE), col][1]
has_warning <- function(res, code) any(vapply(res$warnings, `[[`, "", "code") == code)

# square table → wide data (one row per subject)
square_to_wide <- function(tab) {
  idx <- which(tab > 0, arr.ind = TRUE)
  data.frame(y1 = rownames(tab)[rep(idx[, 1], tab[idx])], y2 = colnames(tab)[rep(idx[, 2], tab[idx])],
             stringsAsFactors = FALSE)
}

# ---- A1 ----
w81 <- square_to_wide(tab_8_1)
r <- cc_paired_binary(w81, "y1", "y2", success = "yes")
check("A1 McNemar X2", test_stat(r, "McNemar"), 2.6151, 1e-4)
check("A1 McNemar P", test_stat(r, "McNemar", "p_value"), 0.1059, 1e-4)
check("A1 difference", est(r, "Difference of proportions (y1 - y2)"), 0.02185, 1e-5)
check("A1 score CI lower", est(r, "Difference of proportions (y1 - y2)", "lower"), -0.00466, 1e-5)
check("A1 score CI upper", est(r, "Difference of proportions (y1 - y2)", "upper"), 0.04849, 1e-5)
check("A1 marginal OR", est(r, "Marginal odds ratio y1 vs y2 (population-averaged)"), 1.11, 5e-3)
check("A1 conditional OR", est(r, "Conditional odds ratio n12/n21: y1 vs y2 (subject-specific)"), 1.23, 5e-3)
check("A1 primary = McNemar", r$notes$primary_test == "McNemar X2", 1, 0)
# both directions are in the output (first skill test: Claude inverted numbers itself)
check("A1 reverse difference", est(r, "Difference of proportions (y2 - y1)"), -0.02185, 1e-5)
check("A1 reverse CI lower", est(r, "Difference of proportions (y2 - y1)", "lower"), -0.04849, 1e-5)
check("A1 reverse CI upper", est(r, "Difference of proportions (y2 - y1)", "upper"), 0.00466, 1e-5)
check("A1 reverse conditional OR", est(r, "Conditional odds ratio n21/n12: y2 vs y1 (subject-specific)"), 107 / 132, 1e-5)
# few discordant pairs → exact test is primary
small <- data.frame(y1 = c(rep("yes", 20), rep("yes", 6), rep("no", 2), rep("no", 30)),
                    y2 = c(rep("yes", 20), rep("no", 6), rep("yes", 2), rep("no", 30)))
r <- cc_paired_binary(small, "y1", "y2", success = "yes")
check("A1 FEW_DISCORDANT", has_warning(r, "FEW_DISCORDANT"), 1, 0)
check("A1 exact P (6 vs 2)", test_stat(r, "Exact", "p_value"), 2 * pbinom(2, 8, 0.5), 1e-5)

# ---- A2 ----
w85 <- square_to_wide(tab_8_5)
lv85 <- rownames(tab_8_5)
r <- cc_paired_nominal(w85, "y1", "y2", levels = lv85)
check("A2 MH LR", test_stat(r, "symmetry vs quasi"), 12.4989, 1e-3)
check("A2 MH df", test_stat(r, "symmetry vs quasi", "df"), 4, 0)
check("A2 MH P", test_stat(r, "symmetry vs quasi", "p_value"), 0.014, 5e-4)
check("A2 symmetry deviance", test_stat(r, "Symmetry model"), 22.473, 1e-3)
check("A2 CMH", test_stat(r, "CMH"), 12.291, 1e-3)
check("A2 follow-up HighPoint z", r$estimates$z[r$estimates$category == "HighPoint"], 3.29, 5e-3)
check("A2 follow-up HighPoint diff", r$estimates$difference[r$estimates$category == "HighPoint"], 0.0665, 5e-4)
check("A2 std residual H→S", r$tables$symmetry_residuals$std_residual[2], 3.46, 5e-3)
# §8.3.2: 0.07 ± 0.04 (Wald: 0.0272 to 0.1058); the score interval should be close
check("A2 follow-up HighPoint CI lower", r$estimates$lower[r$estimates$category == "HighPoint"], 0.0272, 3e-3)
check("A2 follow-up HighPoint CI upper", r$estimates$upper[r$estimates$category == "HighPoint"], 0.1058, 3e-3)

# ---- A3 ----
w86 <- square_to_wide(tab_8_6)
r <- cc_paired_ordinal(w86, "y1", "y2", levels = rownames(tab_8_6))
check("A3 GEE beta", est(r, "beta: cumulative logit, first vs second (logit P(Y <= j))"), 2.75361, 1e-4)
check("A3 GEE robust SE", est(r, "beta: cumulative logit, first vs second (logit P(Y <= j))", "se"), 0.08147, 1e-4)
check("A3 OR higher = exp(-beta)", est(r, "Odds ratio: y1 in a higher category vs y2"), exp(-2.75361), 1e-4)
check("A3 OR y2 higher = exp(beta)", est(r, "Odds ratio: y2 in a higher category vs y1"), exp(2.75361), 1e-3)
check("A3 change: y2 higher", r$tables$changes$n[1], 43 + 163 + 233 + 99 + 185 + 230, 0)
check("A3 change: y2 lower", r$tables$changes$n[2], 4 + 4 + 8 + 0 + 1 + 18, 0)
check("A3 change: same", r$tables$changes$n[3], 12 + 21 + 77 + 132, 0)
check("A3 ordinal QS beta", est(r, "Ordinal quasi-symmetry beta"), 2.3936, 1e-4)
check("A3 OQS LR", test_stat(r, "Ordinal quasi-symmetry"), 1106.124 - 4.4139, 1e-2)
check("A3 mean recycle", est(r, "Mean score y1"), 2.1, 0.05)
check("A3 mean drive", est(r, "Mean score y2"), 3.5, 0.05)

# ---- reshape: wide 3 situations → long ----
ab <- abortion_long()
ab_wide <- reshape(ab, idvar = c("person", "gender"), timevar = "situation", direction = "wide")
names(ab_wide) <- sub("response.", "s", names(ab_wide), fixed = TRUE)
ab2 <- cc_reshape_long(ab_wide, cols = c("s3", "s1", "s2"), id = "person", value = "response",
                       time = "situation", time_values = c("3", "1", "2"))
check("reshape rows", nrow(ab2), 5550, 0)

# ---- B1 ----
ab$situation <- factor(ab$situation, levels = c(3, 1, 2))
r <- cc_gee_binary(ab, id = "person", y = "response", x = "gender", time = "situation",
                   numeric = "gender", success = "1", corstr = "exchangeable")
e <- r$estimates
check("B1 GEE sit1", e$estimate[e$term == "situation1"], 0.14935, 1e-4)
check("B1 GEE sit1 robust SE", e$se[e$term == "situation1"], 0.02974, 2e-4)
check("B1 GEE gender", e$estimate[e$term == "gender"], 0.00344, 1e-4)
check("B1 GEE rho", r$notes$working_correlation, 0.81733, 1e-3)
check("B1 or_reverse sit1", e$or_reverse[e$term == "situation1"], exp(-0.14935), 1e-4)
check("B1 or_reverse CI ordered", e$or_reverse_lower[2] < e$or_reverse[2] && e$or_reverse[2] < e$or_reverse_upper[2], 1, 0)
check("B1 Wald situation (2 df)", test_stat(r, "situation"), 26.0171, 0.05)
check("B1 Wald situation df", test_stat(r, "situation", "df"), 2, 0)
check("B1 time is within-cluster", r$notes$cluster_level$situation == "within", 1, 0)
check("B1 gender is between-cluster", r$notes$cluster_level$gender == "between", 1, 0)
r_lr <- cc_gee_binary(ab, id = "person", y = "response", x = "gender", time = "situation",
                      numeric = "gender", success = "1", test = "lr")
check("B1 GEE_NO_LIKELIHOOD", has_warning(r_lr, "GEE_NO_LIKELIHOOD"), 1, 0)

# ---- B2 ordinal ----
ins <- insomnia_long()
r <- cc_gee_multinomial(ins, id = "case", y = "response", x = "treat", time = "occasion",
                        numeric = c("treat", "occasion"), interactions = "occasion:treat",
                        type = "ordinal", levels = 1:4)
e <- r$estimates
check("B2 occasion", e$estimate[e$term == "occasion"], 1.03808, 1e-4)
check("B2 interaction", e$estimate[e$term == "occasion:treat"], 0.70776, 1e-4)
check("B2 interaction SE", e$se[e$term == "occasion:treat"], 0.24352, 1e-4)
check("B2 Wald interaction", test_stat(r, "Wald (robust SE): occasion:treat"), (0.70776 / 0.24352)^2, 0.01)
# main effects in an interaction are tested jointly with it: occasion + occasion:treat (2 df)
check("B2 Wald occasion (with interaction) df", test_stat(r, "occasion (with occasion:treat)", "df"), 2, 0)

# ---- B2 nominal (coffee as long data) ----
coffee <- square_to_long(tab_8_5)
coffee$y <- rownames(tab_8_5)[coffee$y]
r <- cc_gee_multinomial(coffee, id = "person", y = "y", time = "time", numeric = "time",
                        type = "nominal", levels = lv85, baseline = "Brim")
e <- r$estimates
check("B2 nominal time:HighPoint", e$estimate[e$category == "HighPoint"], 0.32340, 1e-4)
check("B2 nominal SE HighPoint", e$se[e$category == "HighPoint"], 0.16830, 1e-4)
check("B2 nominal Wald time (4 df)", test_stat(r, "time"), 12.4869, 1e-3)

# ---- B3 ----
op <- square_to_long(tab_8_1)
op$y <- ifelse(op$y == 1, "yes", "no")
r <- cc_glmm_binary(op, id = "person", y = "y", time = "time", numeric = "time", success = "yes", nagq = 50)
e <- r$estimates
check("B3 GLMM beta (Table 10.1)", e$estimate[e$term == "time"], 0.2100, 1e-3)
check("B3 GLMM SE", e$se[e$term == "time"], 0.1301, 1e-3)
check("B3 GLMM sigma", r$notes$sigma, 2.854, 1e-3)
check("B3 sigma 2.85: 25 vs 50 points stable", !has_warning(r, "QUADRATURE_UNSTABLE"), 1, 0)
r <- cc_glmm_binary(ab, id = "person", y = "response", x = "gender", time = "situation",
                    numeric = "gender", success = "1", nagq = 100)
e <- r$estimates
check("B3 GLMM sit1", e$estimate[e$term == "situation1"], 0.83478, 1e-3)
check("B3 GLMM sit1 SE", e$se[e$term == "situation1"], 0.16004, 1e-3)
check("B3 GLMM sigma", r$notes$sigma, 8.746, 1e-2)
check("B3 all-same share 1595/1850", r$notes$all_same_share, 1595 / 1850, 1e-5)
# σ = 8.75 is large: 50 points give σ̂ 8.788, sit1 0.836 vs 100 points 8.746, 0.835 → warn (§10.1.5)
check("B3 sigma 8.75: 50 vs 100 points flagged", has_warning(r, "QUADRATURE_UNSTABLE"), 1, 0)

# ---- B4 ----
r <- cc_compare_gee_glmm(ab, id = "person", y = "response", x = "gender", time = "situation",
                         numeric = "gender", success = "1", nagq = 100)
e <- r$estimates
check("B4 GEE sit1", e$gee_estimate[e$term == "situation1"], 0.149, 1e-3)
check("B4 GLMM sit1", e$glmm_estimate[e$term == "situation1"], 0.835, 1e-3)
check("B4 GEE gender SE", e$gee_se[e$term == "gender"], 0.088, 1e-3)
check("B4 GLMM gender SE", e$glmm_se[e$term == "gender"], 0.490, 1e-3)
check("B4 ratio sit1 ~ 5.6", e$ratio[e$term == "situation1"], 0.83478 / 0.14935, 0.02)
check("B4 ALL_SAME_RESPONSE", has_warning(r, "ALL_SAME_RESPONSE"), 1, 0)

results$ok <- abs(results$got - results$book) <= results$tol
print(results, row.names = FALSE)
cat(sprintf("\n%d / %d 和課本一致\n", sum(results$ok), nrow(results)))
if (!all(results$ok)) quit(status = 1)
