# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3-實測/q1/.claude/skills/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3-實測/q1/.claude/skills/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3-實測/q1/student_por.csv")
spec <- jsonlite::fromJSON("{\n  \"question\": \"學生平日和週末的喝酒程度一樣嗎？\",\n  \"structure\": \"paired\",\n  \"types\": {\"Dalc\": \"ordinal\", \"Walc\": \"ordinal\"},\n  \"method_id\": \"paired_ordinal\",\n  \"reason\": \"同一位學生回答平日（Dalc）與週末（Walc）兩題，類別相同的有序 1–5 量表，只比較兩者分布、沒有解釋變數；有序方法 df = 1 檢定力較高（§8.4）\",\n  \"analysis\": \"paired_ordinal\",\n  \"y1\": \"Dalc\", \"y2\": \"Walc\",\n  \"levels\": [\"1\", \"2\", \"3\", \"4\", \"5\"],\n  \"conf_level\": 0.95\n}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(y1 = "Dalc", y2 = "Walc", levels = c("1", "2", "3", "4", 
"5"), scores = NULL, conf.level = 0.95)
result <- do.call("cc_paired_ordinal", c(list(data = data), args))
print(result)
