# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/student_por.csv")
spec <- jsonlite::fromJSON("{\"question\": \"smoke test: schoolsup vs famsup\", \"structure\": \"paired\", \"analysis\": \"paired_binary\", \"y1\": \"schoolsup\", \"y2\": \"famsup\", \"success\": \"yes\"}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(y1 = "schoolsup", y2 = "famsup", success = "yes", levels = NULL, 
    conf.level = 0.95)
result <- do.call("cc_paired_binary", c(list(data = data), args))
print(result)
