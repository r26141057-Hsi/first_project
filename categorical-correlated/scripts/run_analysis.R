# Run one analysis for the categorical-correlated Skill (Part 3).
#
# Usage: Rscript run_analysis.R <data file> <spec.json> <output dir>
#
# spec.json (fields not used by an analysis are ignored):
#   record fields : question, structure ("paired" | "repeated" | "clustered"), types, method_id, reason
#   analysis      : paired_binary | paired_nominal | paired_ordinal |
#                   gee_binary | gee_ordinal | gee_nominal | glmm_binary | compare_gee_glmm
#   paired (wide) : y1, y2, success, levels (low → high for ordinal), scores, ordinal
#   models (long) : id, y, time, x (array), numeric (array), ref ({var: level}), interactions (array),
#                   success, levels, baseline, corstr, lorstr, nagq, test
#   reshape       : {"cols": ["G1","G2","G3"], "value": "G", "time": "time", "time_values": [1,2,3], "id": null}
#                   wide → long before the analysis; id null → created from the row number
#   recode        : new categorical variables (applied after reshape), same format as Part 1
#   conf_level    : default 0.95
#
# Writes to <output dir>: result.json, PNG plots, 分析報告_<data>_<analysis>.md, reproduce.R, spec.json.
# On failure, result.json contains {"error": "..."} and the script exits with status 1.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) stop("Usage: Rscript run_analysis.R <data file> <spec.json> <output dir>")
data_file <- args[1]; spec_file <- args[2]; out_dir <- args[3]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fail <- function(msg) {
  writeLines(jsonlite::toJSON(list(error = msg), auto_unbox = TRUE, pretty = TRUE),
             file.path(out_dir, "result.json"), useBytes = TRUE)
  message("ERROR: ", msg)
  quit(status = 1)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))
suppressPackageStartupMessages({ library(lme4) })   # glmer formulas need the `|` operator in scope

spec <- jsonlite::fromJSON(spec_file, simplifyVector = TRUE)
data <- tryCatch(read_data(data_file), error = function(e) fail(paste("無法讀取資料：", conditionMessage(e))))
prep_notes <- character()
if (!is.null(spec$reshape)) {
  r <- spec$reshape
  data <- tryCatch(cc_reshape_long(data, cols = r$cols, id = r$id, value = r$value %||% "y",
                                   time = r$time %||% "time", time_values = r$time_values),
                   error = function(e) fail(conditionMessage(e)))
  prep_notes <- c(prep_notes, attr(data, "reshape_notes"))
  if (is.null(spec$id)) spec$id <- attr(data, "id")
}
if (!is.null(spec$recode)) {
  data <- tryCatch(cc_recode(data, spec$recode), error = function(e) fail(conditionMessage(e)))
  prep_notes <- c(prep_notes, attr(data, "recode_notes"))
}

# `levels` may be an array (the response's categories) or {variable: [...]} as in Part 1.
response_levels <- function(var) {
  lv <- spec$levels
  if (is.null(lv)) return(NULL)
  if (is.list(lv) && !is.null(names(lv))) return(lv[[var]])
  lv
}
conf <- spec$conf_level %||% 0.95
common <- function() list(data = data, id = spec$id, y = spec$y, x = spec$x %||% character(), time = spec$time,
                          numeric = spec$numeric %||% character(), ref = as.list(spec$ref %||% list()),
                          interactions = spec$interactions %||% character(), conf.level = conf)
calls <- list(
  paired_binary = function() list("cc_paired_binary", list(data = data, y1 = spec$y1, y2 = spec$y2,
    success = spec$success, levels = response_levels(spec$y1), conf.level = conf)),
  paired_nominal = function() list("cc_paired_nominal", list(data = data, y1 = spec$y1, y2 = spec$y2,
    levels = response_levels(spec$y1), ordinal = spec$ordinal %||% character(), conf.level = conf)),
  paired_ordinal = function() list("cc_paired_ordinal", list(data = data, y1 = spec$y1, y2 = spec$y2,
    levels = response_levels(spec$y1), scores = spec$scores, conf.level = conf)),
  gee_binary = function() list("cc_gee_binary", c(common(), list(success = spec$success,
    corstr = spec$corstr %||% "exchangeable", test = spec$test %||% "wald"))),
  gee_ordinal = function() list("cc_gee_multinomial", c(common(), list(type = "ordinal",
    levels = response_levels(spec$y), lorstr = spec$lorstr %||% "independence"))),
  gee_nominal = function() list("cc_gee_multinomial", c(common(), list(type = "nominal",
    levels = response_levels(spec$y), baseline = spec$baseline, lorstr = spec$lorstr %||% "independence"))),
  glmm_binary = function() list("cc_glmm_binary", c(common(), list(success = spec$success,
    nagq = spec$nagq %||% 100))),
  compare_gee_glmm = function() list("cc_compare_gee_glmm", c(common(), list(success = spec$success,
    corstr = spec$corstr %||% "exchangeable", nagq = spec$nagq %||% 100)))
)
if (is.null(spec$analysis) || !spec$analysis %in% names(calls)) {
  fail(paste0("本 Skill 不支援的分析：", spec$analysis %||% "（未指定）", "。可用：", paste(names(calls), collapse = ", "),
              "。資料若其實彼此獨立，請改用 Part 1（categorical-association）或 Part 2（categorical-modeling）。"))
}
call_info <- calls[[spec$analysis]]()
result <- tryCatch(do.call(call_info[[1]], call_info[[2]]), error = function(e) fail(conditionMessage(e)))
result$facts <- c(prep_notes, result$facts)

plots <- tryCatch(cc_plots(result), error = function(e) { message("plot skipped: ", conditionMessage(e)); list() })
result$plots <- character()
for (name in names(plots)) {
  path <- file.path(out_dir, paste0(name, ".png"))
  ggplot2::ggsave(path, plots[[name]], width = 7, height = 4.5, dpi = 150, bg = "white")
  result$plots <- c(result$plots, basename(path))
}

# ---- Markdown report: every number is written here by R, never retyped by the model ----
counts <- result$tables$counts
count_md <- if (!is.null(counts)) {
  m <- as.matrix(counts)
  md_table(cbind(data.frame(` ` = rownames(m), check.names = FALSE), as.data.frame.matrix(m)), digits = 0)
} else character()
desc <- result$tables$proportions %||% result$tables$distribution %||% result$tables$marginal
data_name <- tools::file_path_sans_ext(basename(data_file))
report <- c(
  sprintf("# 分析報告：%s", spec$question %||% result$method_label), "",
  sprintf("- 資料檔：`%s`", basename(data_file)),
  sprintf("- 方法：%s（Agresti %s）", result$method_label, result$book_ref),
  if (!is.null(spec$structure)) sprintf("- 資料結構：%s", spec$structure),
  if (!is.null(spec$reason)) sprintf("- 選擇理由：%s", spec$reason),
  if (!is.null(result$notes$effect_type)) sprintf("- 效果的意義：%s", if (result$notes$effect_type == "population-averaged")
    "整體平均（population-averaged）" else "同一個叢集（subject-specific）"), "",
  if (length(count_md)) c("## 配對次數表", "", "列 = 第一次、欄 = 第二次。", "", count_md, ""),
  if (!is.null(desc)) c("## 描述統計", "", md_table(desc), ""),
  "## 結果", "", paste0("- ", result$facts), "",
  if (nrow(result$tests) > 0) c("## 檢定", "", md_table(result$tests[, c("test", "statistic", "df", "p_value", "book_ref")]), ""),
  if (nrow(result$estimates) > 0) c("## 估計值", "", md_table(result$estimates), ""),
  if (length(result$warnings) > 0) c("## 注意事項", "",
    vapply(result$warnings, function(w) sprintf("- **%s**：%s（Agresti %s）", w$code, w$message, w$book_ref), ""), ""),
  if (!is.null(result$notes$cluster_reminder)) c(sprintf("> %s", result$notes$cluster_reminder), ""),
  if (length(result$plots)) c("## 圖", "", sprintf("![](%s)", result$plots), ""),
  sprintf("> %s", result$notes$reminder))
report_file <- file.path(out_dir, sprintf("分析報告_%s_%s.md", data_name, spec$analysis))
writeLines(report, report_file, useBytes = TRUE)
result$report <- basename(report_file)

writeLines(c(
  "# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）",
  "suppressPackageStartupMessages(library(lme4))",
  sprintf('for (f in c("utils.R", setdiff(list.files("%s", pattern = "\\\\.R$"), "utils.R"))) source(file.path("%s", f), encoding = "UTF-8")',
          ENGINE_DIR, ENGINE_DIR),
  sprintf('data <- read_data("%s")', normalizePath(data_file, winslash = "/")),
  sprintf("spec <- jsonlite::fromJSON(%s)", deparse(paste(readLines(spec_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))),
  "if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% \"y\", spec$reshape$time %||% \"time\", spec$reshape$time_values)",
  "if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)",
  paste0("args <- ", paste(deparse(call_info[[2]][setdiff(names(call_info[[2]]), "data")]), collapse = "\n")),
  sprintf("result <- do.call(%s, c(list(data = data), args))", deparse(call_info[[1]])),
  "print(result)"
), file.path(out_dir, "reproduce.R"), useBytes = TRUE)

spec_copy <- file.path(out_dir, "spec.json")
if (!file.exists(spec_copy) || normalizePath(spec_file) != normalizePath(spec_copy)) {
  invisible(file.copy(spec_file, spec_copy, overwrite = TRUE))
}
cc_to_json(result, file.path(out_dir, "result.json"))
message("OK: ", normalizePath(file.path(out_dir, "result.json")))
message("REPORT: ", normalizePath(report_file))
