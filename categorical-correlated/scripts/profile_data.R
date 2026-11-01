# Stage 1: profile a data file - guessed variable scales, signs of correlated data, and an
# overview table of every variable.
#
# Usage: Rscript profile_data.R <data file> <output dir>
# Writes <output dir>/profile.json and 資料總覽_<data>.md. Every guess must be confirmed with the user.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) stop("Usage: Rscript profile_data.R <data file> <output dir>")
data_file <- args[1]; out_dir <- args[2]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[1]))), "load_engine.R"))

out_file <- file.path(out_dir, "profile.json")
profile <- tryCatch(cc_profile(read_data(data_file)), error = function(e) {
  writeLines(jsonlite::toJSON(list(error = paste("無法讀取資料：", conditionMessage(e))),
                              auto_unbox = TRUE, pretty = TRUE), out_file, useBytes = TRUE)
  message("ERROR: ", conditionMessage(e))
  quit(status = 1)
})
profile$file <- normalizePath(data_file, winslash = "/")
writeLines(jsonlite::toJSON(profile, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
           out_file, useBytes = TRUE)

data_name <- tools::file_path_sans_ext(basename(data_file))
overview_file <- file.path(out_dir, paste0("資料總覽_", data_name, ".md"))
writeLines(cc_overview_md(profile, basename(data_file)), overview_file, useBytes = TRUE)
message("OK: ", normalizePath(out_file))
message("OK: ", normalizePath(overview_file))
