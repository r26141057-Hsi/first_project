# 重現這次分析的 R 程式碼（需要本 Skill 的 R/ 資料夾）
suppressPackageStartupMessages(library(lme4))
for (f in c("utils.R", setdiff(list.files("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", pattern = "\\.R$"), "utils.R"))) source(file.path("C:/Users/User/Desktop/claude/Part3/categorical-correlated/R", f), encoding = "UTF-8")
data <- read_data("C:/Users/User/Desktop/claude/Part3/dev/demo/student_por.csv")
spec <- jsonlite::fromJSON("{\"analysis\": \"gee_nominal\", \"reshape\": {\"cols\": [\"Mjob\",\"Fjob\"], \"value\": \"job\", \"time\": \"parent\", \"time_values\": [\"mother\",\"father\"]}, \"y\": \"job\", \"time\": \"parent\", \"x\": [\"school\"]}")
if (!is.null(spec$reshape)) data <- cc_reshape_long(data, spec$reshape$cols, spec$reshape$id, spec$reshape$value %||% "y", spec$reshape$time %||% "time", spec$reshape$time_values)
if (!is.null(spec$recode)) data <- cc_recode(data, spec$recode)
args <- list(id = "id", y = "job", x = "school", time = "parent", numeric = character(0), 
    ref = list(), interactions = character(0), conf.level = 0.95, 
    type = "nominal", levels = NULL, baseline = NULL, lorstr = "independence")
result <- do.call("cc_gee_multinomial", c(list(data = data), args))
print(result)
