# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/student_por.csv")
spec <- jsonlite::fromJSON("{\"question\": \"學生平日和週末的喝酒程度一樣嗎？\", \"structure\": \"paired\", \"method_id\": \"paired_ordinal\",\n \"reason\": \"同一位學生的兩個有序回答（1–5），比較兩次是否整體偏高或偏低（§8.4）\",\n \"analysis\": \"paired_ordinal\", \"y1\": \"Dalc\", \"y2\": \"Walc\", \"levels\": [\"1\", \"2\", \"3\", \"4\", \"5\"]}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(y1 = "Dalc", y2 = "Walc", levels = c("1", "2", "3", "4", 
"5"), scores = NULL, conf.level = 0.95)
result <- do.call("cc_paired_ordinal", c(list(data = data), args))
print(result)
