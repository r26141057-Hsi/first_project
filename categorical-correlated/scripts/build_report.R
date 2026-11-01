# Assemble the whole step-by-step analysis into one report (stage 8 of the categorical-correlated Skill).
#
# Usage: Rscript build_report.R <output dir> [--no-render]   (--no-render: write the .md copy, skip Quarto)
#
# Reads, inside <output dir>:
#   analysis_log.json  written by the model during the analysis:
#     {"data_file": "student_por.csv", "question": "...", "settings": ["① ...", ...],
#      "steps": [{"dir": "step1", "question": "...", "reason": "...",
#                 "suggestions": [{"analysis": "gee_binary", "text": "...", "reason": "...", "recommended": true}],
#                 "choice": "使用者的回覆原文"}, ...]}
#   資料總覽_*.md, 初步檢視_*.md and their plots      (stages 1 and 3)
#   stepK/分析報告_*.md, stepK/*.png, stepK/reproduce.R (stage 5; the report already holds the model's explanation)
#   結論.md                                            (the model's overall conclusion, optional)
#
# Writes 整份分析報告_<data>.qmd, then renders it to .html when Quarto is found, otherwise writes a .md copy.
# Every number in the report comes from the step reports that run_analysis wrote; nothing is recomputed.

args <- commandArgs(trailingOnly = TRUE)
no_render <- "--no-render" %in% args
args <- setdiff(args, "--no-render")
if (length(args) != 1) stop("Usage: Rscript build_report.R <output dir> [--no-render]")
out_dir <- normalizePath(args[1], winslash = "/", mustWork = TRUE)

read_utf8 <- function(path) readLines(path, warn = FALSE, encoding = "UTF-8")
log_file <- file.path(out_dir, "analysis_log.json")
if (!file.exists(log_file)) stop("找不到 analysis_log.json：請先在輸出資料夾寫好分析紀錄。")
log <- jsonlite::fromJSON(paste(read_utf8(log_file), collapse = "\n"), simplifyVector = FALSE)
if (length(log$steps) == 0) stop("analysis_log.json 沒有任何步驟。")

METHOD_NAMES <- c(
  paired_binary = "McNemar 檢定（§8.1）",
  paired_nominal = "邊際同質性（§8.3）",
  paired_ordinal = "有序配對的累積 logit 邊際模型（§8.4）",
  gee_binary = "GEE 邊際 logistic 模型（§9.2）",
  gee_ordinal = "GEE 累積 logit 模型（§9.3）",
  gee_nominal = "GEE baseline-category logit 模型（§9.3）",
  glmm_binary = "GLMM 隨機截距 logistic 模型（§10.1–10.2）",
  compare_gee_glmm = "GEE 與 GLMM 並排（§10.1.4）")
method_name <- function(a) if (!is.null(a) && a %in% names(METHOD_NAMES)) METHOD_NAMES[[a]] else (a %||% "")
`%||%` <- function(a, b) if (is.null(a)) b else a

find_one <- function(dir, pattern) {
  f <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(f)) f[1] else NULL
}
# Drop the file's own title, shift headings down `shift` levels and point images at `prefix`.
embed_md <- function(path, shift, prefix) {
  lines <- read_utf8(path)
  first_h1 <- which(grepl("^# ", lines))[1]
  if (!is.na(first_h1)) lines <- lines[-first_h1]
  if (shift > 0) lines <- sub("^(#+) ", paste0(strrep("#", shift), "\\1 "), lines)
  if (nzchar(prefix)) lines <- gsub("!\\[([^]]*)\\]\\(([^)/:]+)\\)", paste0("![\\1](", prefix, "/\\2)"), lines)
  lines
}
md_cell <- function(x) gsub("\\|", "\\\\|", gsub("\n", " ", x %||% ""))

data_name <- tools::file_path_sans_ext(basename(log$data_file %||% "data"))
problems <- character()
out <- c(
  "---",
  sprintf('title: "整份分析報告：%s"', data_name),
  'lang: zh-Hant',
  'format:',
  '  html:',
  '    toc: true',
  '    toc-depth: 2',
  '    number-sections: true',
  '    embed-resources: true',
  '---', "")

# ---- 1. Data and question ----
out <- c(out, "# 資料與研究問題", "",
         sprintf("- 資料檔：`%s`", basename(log$data_file %||% "")),
         sprintf("- 研究問題：%s", log$question %||% ""))
overview <- find_one(out_dir, "^資料總覽_.*\\.md$")
if (!is.null(overview)) {
  size_line <- grep("^共 .*列", read_utf8(overview), value = TRUE)
  if (length(size_line)) out <- c(out, sprintf("- 資料大小：%s", sub("。$", "", size_line[1])))
}
out <- c(out, sprintf("- 分析步驟：共 %d 步", length(log$steps)), "")

# ---- 2. Confirmed settings ----
if (length(log$settings)) {
  out <- c(out, "# 確認的設定", "", "以下設定在分析開始前和使用者確認過。", "",
           paste0("- ", unlist(log$settings)), "")
}

# ---- 3. First look (stage 3) ----
first_look <- find_one(out_dir, "^初步檢視_.*\\.md$")
if (!is.null(first_look)) out <- c(out, "# 初步檢視", "", embed_md(first_look, 0, ""), "")

# ---- 4. Steps ----
out <- c(out, "# 分析過程", "")
for (k in seq_along(log$steps)) {
  s <- log$steps[[k]]
  step_dir <- file.path(out_dir, s$dir %||% sprintf("step%d", k))
  spec_file <- file.path(step_dir, "spec.json")
  spec <- if (file.exists(spec_file)) jsonlite::fromJSON(paste(read_utf8(spec_file), collapse = "\n")) else list()
  out <- c(out, sprintf("## 第 %d 步：%s", k, s$question %||% method_name(spec$analysis)), "",
           sprintf("**方法**：%s", method_name(spec$analysis)), "")
  if (!is.null(s$reason)) out <- c(out, "### 為什麼做這一步", "", s$reason, "")
  report <- find_one(step_dir, "^分析報告_.*\\.md$")
  if (is.null(report)) {
    problems <- c(problems, sprintf("第 %d 步（%s）沒有分析報告。", k, basename(step_dir)))
    out <- c(out, "> 這一步沒有分析報告（`run_analysis` 可能沒有成功）。", "")
  } else {
    if (!any(grepl("^## 結論與解釋", read_utf8(report)))) {
      problems <- c(problems, sprintf("第 %d 步的分析報告還沒有「## 結論與解釋」。", k))
    }
    # The step section already names the data, method and reason; drop the report's own header lines.
    body <- embed_md(report, 1, basename(step_dir))
    body <- body[!grepl("^- (資料檔|方法|資料結構|選擇理由)：", body)]
    out <- c(out, body, "")
  }
  if (length(s$suggestions)) {
    rows <- vapply(seq_along(s$suggestions), function(i) {
      g <- s$suggestions[[i]]
      sprintf("| %d | %s%s | %s | %s |", i, md_cell(g$text), if (isTRUE(g$recommended)) "（推薦）" else "",
              md_cell(method_name(g$analysis)), md_cell(g$reason))
    }, "")
    out <- c(out, "### 下一步的建議", "", "| # | 建議 | 方法 | 理由 |", "|---|---|---|---|", rows, "",
             sprintf("**使用者的選擇**：%s", s$choice %||% "（沒有紀錄）"), "")
  }
}

# ---- 5. Conclusion ----
conclusion <- file.path(out_dir, "結論.md")
out <- c(out, "# 結論與限制", "")
if (file.exists(conclusion)) {
  out <- c(out, embed_md(conclusion, 1, ""), "")
} else {
  problems <- c(problems, "沒有 結論.md（整體結論與限制）。")
  out <- c(out, "> 尚未撰寫整體結論。", "")
}

# ---- 6. Appendix: code to reproduce each step ----
out <- c(out, "# 附錄：重現每一步的程式碼", "",
         "每一步的數字都可以用下面的程式碼重新計算（需要本 Skill 的計算引擎）。", "")
for (k in seq_along(log$steps)) {
  step_dir <- file.path(out_dir, log$steps[[k]]$dir %||% sprintf("step%d", k))
  for (f in c("reproduce.R", "reproduce.py")) {
    p <- file.path(step_dir, f)
    if (file.exists(p)) {
      out <- c(out, sprintf("## 第 %d 步（`%s/%s`）", k, basename(step_dir), f), "",
               paste0("```", if (f == "reproduce.R") "r" else "python"), read_utf8(p), "```", "")
    }
  }
}

qmd <- file.path(out_dir, sprintf("整份分析報告_%s.qmd", data_name))
writeLines(enc2utf8(out), qmd, useBytes = TRUE)
message("QMD: ", qmd)

# ---- Render with Quarto when available (no code chunks, so R is not needed to render) ----
find_quarto <- function() {
  cands <- c(Sys.getenv("QUARTO_PATH"), Sys.which("quarto"),
             "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
             "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto")
  cands <- cands[nzchar(cands) & file.exists(cands)]
  if (length(cands)) cands[1] else NULL
}
html <- sub("\\.qmd$", ".html", qmd)
quarto <- if (no_render) NULL else find_quarto()
rendered <- FALSE
if (!is.null(quarto)) {
  old <- setwd(out_dir)
  status <- tryCatch(system2(quarto, c("render", shQuote(basename(qmd)), "--to", "html"), stdout = FALSE, stderr = FALSE),
                     error = function(e) 1)
  setwd(old)
  rendered <- identical(as.integer(status), 0L) && file.exists(html)
}
if (rendered) {
  message("HTML: ", html)
} else {
  md <- sub("\\.qmd$", ".md", qmd)
  body <- out[-seq_len(which(out == "---")[2])]
  writeLines(enc2utf8(c(sprintf("# 整份分析報告：%s", data_name), "", body)), md, useBytes = TRUE)
  reason <- if (no_render) "不轉檔（--no-render）" else if (is.null(quarto)) "找不到 Quarto" else "Quarto 轉檔失敗"
  message(reason, "，改輸出 Markdown：", md)
}
for (p in problems) message("WARNING: ", p)
