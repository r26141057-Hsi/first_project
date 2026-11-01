# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3-實測/q2/.claude/skills/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3-實測/q2/.claude/skills/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3-實測/q2/student_por.csv")
spec <- jsonlite::fromJSON("{\n  \"question\": \"媽媽和爸爸的職業分布不同嗎？\",\n  \"structure\": \"matched_pairs\",\n  \"types\": {\"Mjob\": \"nominal\", \"Fjob\": \"nominal\"},\n  \"method_id\": \"paired_nominal\",\n  \"reason\": \"同一位學生的媽媽職業與爸爸職業是配對的名目結果（5 類，方陣），只比較兩者的邊際分布，沒有其他解釋變數（§8.3）\",\n  \"analysis\": \"paired_nominal\",\n  \"y1\": \"Mjob\", \"y2\": \"Fjob\",\n  \"levels\": [\"at_home\", \"health\", \"other\", \"services\", \"teacher\"],\n  \"conf_level\": 0.95\n}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(y1 = "Mjob", y2 = "Fjob", levels = c("at_home", "health", 
"other", "services", "teacher"), ordinal = character(0), conf.level = 0.95)
result <- do.call("cc_paired_nominal", c(list(data = data), args))
print(result)
