# Install the R packages this Skill needs (run once).
pkgs <- c("jsonlite", "readr", "readxl", "ggplot2", "scales", "PropCIs", "geepack", "multgee", "lme4")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
cat("OK:", paste(pkgs, collapse = ", "), "\n")
