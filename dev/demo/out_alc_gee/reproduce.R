# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/student_por.csv")
spec <- jsonlite::fromJSON("{\"question\": \"平日與週末喝酒程度，男女有差嗎？\", \"structure\": \"repeated\", \"analysis\": \"gee_ordinal\", \"reshape\": {\"cols\": [\"Dalc\",\"Walc\"], \"value\": \"alc\", \"time\": \"day\", \"time_values\": [\"weekday\",\"weekend\"]}, \"y\": \"alc\", \"time\": \"day\", \"x\": [\"sex\"], \"levels\": [\"1\",\"2\",\"3\",\"4\",\"5\"]}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(id = "id", y = "alc", x = "sex", time = "day", numeric = character(0), 
    ref = list(), interactions = character(0), conf.level = 0.95, 
    type = "ordinal", levels = c("1", "2", "3", "4", "5"), lorstr = "independence")
result <- do.call("cc_gee_multinomial", c(list(data = data), args))
print(result)
