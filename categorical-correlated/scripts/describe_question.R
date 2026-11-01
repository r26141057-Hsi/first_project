# Stage 3: plots and checklist numbers for the user's question (no test is run).
#
# Usage: Rscript describe_question.R <data file> <question.json> <output dir>
#
# question.json uses the same field names as spec.json:
#   paired: {"mode": "paired", "y1": "Dalc", "y2": "Walc", "levels": ["1","2","3","4","5"], "success": null}
#   model : {"mode": "model", "reshape": {...}, "recode": {...}, "id": "id", "y": "passed",
#            "time": "period", "x": ["sex"], "success": "pass", "numeric": [], "ref": {}}
# Writes check.json, 初步檢視_<data>.md and PNG plots.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) stop("Usage: Rscript describe_question.R <data file> <question.json> <output dir>")
data_file <- args[1]; q_file <- args[2]; out_dir <- args[3]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fail <- function(msg) {
  writeLines(jsonlite::toJSON(list(error = msg), auto_unbox = TRUE, pretty = TRUE),
             file.path(out_dir, "check.json"), useBytes = TRUE)
  message("ERROR: ", msg)
  quit(status = 1)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))

q <- jsonlite::fromJSON(q_file, simplifyVector = TRUE)
data <- tryCatch(read_data(data_file), error = function(e) fail(paste("無法讀取資料：", conditionMessage(e))))
notes <- character()
if (!is.null(q$reshape)) {
  r <- q$reshape
  data <- tryCatch(cc_reshape_long(data, cols = r$cols, id = r$id, value = r$value %||% "y",
                                   time = r$time %||% "time", time_values = r$time_values),
                   error = function(e) fail(conditionMessage(e)))
  notes <- c(notes, attr(data, "reshape_notes"))
  if (is.null(q$id)) q$id <- attr(data, "id")
}
if (!is.null(q$recode)) {
  data <- tryCatch(cc_recode(data, q$recode), error = function(e) fail(conditionMessage(e)))
  notes <- c(notes, attr(data, "recode_notes"))
}

desc <- tryCatch(cc_describe(data, q), error = function(e) fail(conditionMessage(e)))
desc$facts <- c(notes, desc$facts)
for (nm in names(desc$plots)) {
  ggplot2::ggsave(file.path(out_dir, paste0(nm, ".png")), desc$plots[[nm]], width = 7, height = 4.5, dpi = 150, bg = "white")
}
check <- desc$check
check$facts <- desc$facts
check$plots <- paste0(names(desc$plots), ".png")
check$tables <- lapply(desc$tables, function(t) if (is.table(t) || is.matrix(t)) {
  m <- as.matrix(t); list(rows = rownames(m), cols = colnames(m), values = unname(split(m, row(m))))
} else t)
writeLines(jsonlite::toJSON(.mark_infinite(check), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA),
           file.path(out_dir, "check.json"), useBytes = TRUE)

data_name <- tools::file_path_sans_ext(basename(data_file))
md_file <- file.path(out_dir, paste0("初步檢視_", data_name, ".md"))
writeLines(cc_describe_md(desc, basename(data_file), q$question), md_file, useBytes = TRUE)
message("OK: ", normalizePath(file.path(out_dir, "check.json")))
message("OK: ", normalizePath(md_file))
