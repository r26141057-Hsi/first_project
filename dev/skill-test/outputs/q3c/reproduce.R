# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3-實測/q3c/.claude/skills/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3-實測/q3c/.claude/skills/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3-實測/q3c/student_por.csv")
spec <- jsonlite::fromJSON("{\n  \"question\": \"三次考試的及格率有變化嗎？和性別有關嗎？\",\n  \"structure\": \"repeated\",\n  \"types\": {\"passed\": \"binary\", \"sex\": \"binary\", \"period\": \"time\"},\n  \"method_id\": \"gee_binary\",\n  \"reason\": \"同一位學生三次考試的二元結果（G ≥ 10 為及格）；使用者只想知道整體來說及格率有沒有變、男女整體有沒有差，所以用邊際 logistic GEE（§9.2）\",\n  \"analysis\": \"gee_binary\",\n  \"reshape\": {\"cols\": [\"G1\", \"G2\", \"G3\"], \"value\": \"G\", \"time\": \"period\", \"time_values\": [1, 2, 3], \"id\": null},\n  \"recode\": {\"passed\": {\"from\": \"G\", \"breaks\": [10], \"labels\": [\"fail\", \"pass\"]}},\n  \"y\": \"passed\", \"time\": \"period\", \"x\": [\"sex\"], \"success\": \"pass\",\n  \"ref\": {\"sex\": \"F\"},\n  \"corstr\": \"exchangeable\", \"conf_level\": 0.95\n}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(id = "id", y = "passed", x = "sex", time = "period", numeric = character(0), 
    ref = list(sex = "F"), interactions = character(0), conf.level = 0.95, 
    success = "pass", corstr = "exchangeable", test = "wald")
result <- do.call("cc_gee_binary", c(list(data = data), args))
print(result)
