# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/stepwise/student_por.csv")
spec <- jsonlite::fromJSON("{\n  \"question\": \"整體平均和同一位學生的效果各是多少？\",\n  \"structure\": \"repeated\",\n  \"types\": {\"passed\": \"binary\", \"sex\": \"binary\", \"period\": \"time\"},\n  \"method_id\": \"compare_gee_glmm\",\n  \"reason\": \"使用者也想知道同一位學生的效果；交互作用的證據不足，使用者決定拿掉（§10.1.4）\",\n  \"analysis\": \"compare_gee_glmm\",\n  \"reshape\": {\"cols\": [\"G1\", \"G2\", \"G3\"], \"value\": \"G\", \"time\": \"period\", \"time_values\": [1, 2, 3]},\n  \"recode\": {\"passed\": {\"from\": \"G\", \"breaks\": [10], \"labels\": [\"fail\", \"pass\"]}},\n  \"y\": \"passed\", \"time\": \"period\", \"x\": [\"sex\"], \"success\": \"pass\",\n  \"corstr\": \"exchangeable\", \"conf_level\": 0.95\n}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(id = "id", y = "passed", x = "sex", time = "period", numeric = character(0), 
    ref = list(), interactions = character(0), conf.level = 0.95, 
    success = "pass", corstr = "exchangeable", nagq = 100)
result <- do.call("cc_compare_gee_glmm", c(list(data = data), args))
print(result)
