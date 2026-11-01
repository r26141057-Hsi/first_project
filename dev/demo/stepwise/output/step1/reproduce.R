# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/stepwise/student_por.csv")
spec <- jsonlite::fromJSON("{\n  \"question\": \"第一次和第三次考試的及格率一樣嗎？\",\n  \"structure\": \"paired\",\n  \"types\": {\"pass1\": \"binary\", \"pass3\": \"binary\"},\n  \"method_id\": \"paired_binary\",\n  \"reason\": \"同一位學生兩次考試的及不及格，只比較兩次的分布（§8.1）\",\n  \"analysis\": \"paired_binary\",\n  \"recode\": {\"pass1\": {\"from\": \"G1\", \"breaks\": [10], \"labels\": [\"fail\", \"pass\"]},\n             \"pass3\": {\"from\": \"G3\", \"breaks\": [10], \"labels\": [\"fail\", \"pass\"]}},\n  \"y1\": \"pass1\", \"y2\": \"pass3\", \"success\": \"pass\", \"conf_level\": 0.95\n}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(y1 = "pass1", y2 = "pass3", success = "pass", levels = NULL, 
    conf.level = 0.95)
result <- do.call("cc_paired_binary", c(list(data = data), args))
print(result)
