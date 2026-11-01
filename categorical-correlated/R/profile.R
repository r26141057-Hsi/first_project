# Stage 1: guess each variable's scale and look for signs of correlated data.
# Everything here is a *guess* for the user to confirm: the data alone cannot tell ordinal from
# nominal codes (§1.1.2) or prove which rows belong together (§1.1.3).
# The variable guesses and the id / wide-pair / aggregated rules follow Part 1
# (categorical-association) so both Skills flag the same things; Part 3 adds two wide-format
# detectors (numbered columns such as G1–G3, and name pairs such as Dalc/Walc).

.ordinal_words <- c(
  "非常", "很", "有點", "普通", "還好", "尚可", "不太", "同意", "滿意", "喜歡",
  "低", "中", "高", "從不", "從未", "很少", "偶爾", "有時", "經常", "時常", "總是",
  "輕", "重", "差", "好", "優", "劣", "每天", "每週", "每月",
  "never", "rarely", "seldom", "sometimes", "often", "usually", "always",
  "low", "medium", "moderate", "high", "none", "slight", "mild", "severe",
  "poor", "fair", "good", "excellent", "agree", "disagree", "neutral",
  "satisf", "dissatisf", "strongly", "very", "somewhat", "little"
)
.id_name_pattern <- paste0(
  "^(id|.*_id|person|subject|case|patient|participant|respondent|student|school|class|",
  "cluster|family|household|group|litter|center|centre|hospital|clinic)$|",
  "編號|學號|代號|受試|個案|病患|病人|受訪|學生|學校|班級|家庭|家戶|醫院|群組")
.time_name_pattern <- paste0(
  "^(time|visit|week|month|year|wave|occasion|round|period|trial|session|situation|question|",
  "item|condition|t)$|時間|時點|次數|第幾|週|月份|年度|期|回合|題目|情境")
.pair_name_pattern <- "pre|post|before|after|baseline|follow|^y[0-9]$|^t[0-9]$|前測|後測|之前|之後|第一次|第二次"
.count_name_pattern <- "^(n|count|counts|freq|frequency|weight|wt)$|次數|人數|頻數|數量|個數"
.age_name_pattern <- "^age$|_age$|^age_|年齡|歲"

profile_variable <- function(v, name) {
  n <- length(v)
  miss <- sum(is.na(v))
  x <- v[!is.na(v)]
  uniq <- unique(x)
  k <- length(uniq)
  is_num <- is.numeric(x)
  int_like <- is_num && all(abs(x - round(x)) < 1e-8)
  lev_counts <- if (k <= 20) table(code_order_factor(x)) else NULL

  guess <- "nominal"; confirm <- FALSE; reason <- ""
  if (k == 0) {
    guess <- "empty"; reason <- "全部缺失"
  } else if (grepl(.id_name_pattern, name, ignore.case = TRUE) && k > 10) {
    guess <- "id"; reason <- "欄名像識別碼，且類別很多"
  } else if (k == length(x) && k > 20 && (int_like || !is_num)) {
    guess <- "id"; reason <- "每一列的值都不同"
  } else if (k == 2) {
    guess <- "binary"; reason <- "只有 2 種值"
  } else if (is_num && grepl(.age_name_pattern, name, ignore.case = TRUE)) {
    guess <- "continuous"; reason <- "欄名像年齡，視為數值變數"
  } else if (is_num && !int_like) {
    guess <- "continuous"; reason <- "含小數的數值"
  } else if (int_like && k <= 10 && max(x) - min(x) == k - 1) {
    guess <- "ordinal_or_nominal_code"; confirm <- TRUE
    reason <- sprintf("只有 %d 個連續整數（%s–%s），可能是有序量表或類別代碼", k, min(x), max(x))
  } else if (int_like && min(x) >= 0 && grepl(.count_name_pattern, name, ignore.case = TRUE)) {
    guess <- "frequency_weight"; confirm <- TRUE; reason <- "欄名像次數，可能是彙整資料的次數欄"
  } else if (int_like && min(x) >= 0) {
    guess <- "count_or_continuous"; confirm <- TRUE; reason <- "非負整數且值很多，可能是計數或連續量"
  } else if (is_num) {
    guess <- "continuous"; reason <- "數值且值很多"
  } else if (k > 20) {
    guess <- "nominal_many_levels"; confirm <- TRUE; reason <- "文字類別超過 20 種，可能是自由填答或識別碼"
  } else {
    hits <- vapply(as.character(uniq), function(u)
      any(vapply(.ordinal_words, function(w) grepl(w, u, ignore.case = TRUE), logical(1))), logical(1))
    if (mean(hits) >= 0.5) {
      guess <- "ordinal_candidate"; confirm <- TRUE; reason <- "類別名稱像有順序的量表，請確認順序"
    } else {
      reason <- "文字類別，看起來沒有順序"
    }
  }
  list(
    name = name, n = n, n_missing = miss, n_unique = k,
    type_guess = guess, needs_confirmation = confirm, reason = reason,
    levels = if (!is.null(lev_counts)) as.list(stats::setNames(as.integer(lev_counts), names(lev_counts))) else NULL,
    examples = utils::head(as.character(uniq), 5),
    range = if (is_num && k > 0) c(min(x), max(x)) else NULL
  )
}

.level_set <- function(v) sort(unique(as.character(stats::na.omit(v))), method = "radix")

# Look for signs that rows are not independent observations (Ch.8–10).
detect_structure <- function(data, vars) {
  hints <- list()
  types <- vapply(vars, `[[`, "", "type_guess")
  names(types) <- names(data)
  add <- function(h) hints[[length(hints) + 1]] <<- h

  # 1. Long format: an id-like column with repeated values (rule from Part 1).
  id_cols <- names(data)[grepl(.id_name_pattern, names(data), ignore.case = TRUE)]
  if (any(types == "frequency_weight")) id_cols <- character()
  for (idc in id_cols) {
    ids <- data[[idc]][!is.na(data[[idc]])]
    per_id <- table(ids)
    if (length(per_id) >= 5 && max(per_id) >= 2) {
      time_cols <- setdiff(names(data)[grepl(.time_name_pattern, names(data), ignore.case = TRUE)], idc)
      within <- Filter(function(tc) {
        k <- length(unique(stats::na.omit(data[[tc]])))
        k >= 2 && k <= 20 && all(tapply(data[[tc]], data[[idc]], function(z) !anyDuplicated(stats::na.omit(z))))
      }, time_cols)
      kind <- if (length(within) > 0) "repeated_measures" else "clustered"
      add(list(
        type = kind, columns = I(c(idc, within)), format = "long",
        evidence = sprintf("%s 有 %d 個不同的值，每個值出現 %d–%d 列（中位數 %s）%s",
                           idc, length(per_id), min(per_id), max(per_id), stats::median(per_id),
                           if (length(within)) paste0("；", paste(within, collapse = "/"), " 在每個 ", idc, " 內不重複，像是時間或情境") else ""),
        question = if (kind == "repeated_measures")
          sprintf("同一個 %s 是否被測量了多次（每次一列）？%s 是時間或情境嗎？", idc, paste(within, collapse = "/"))
          else sprintf("%s 是否代表群組（例如學校、家庭），同群組內的觀察可能彼此相關？", idc),
        suggested = list(id = idc, time = if (length(within)) within[1] else NULL),
        book_ref = "§9.1, §10.1"))
    }
  }
  long_format <- any(vapply(hints, function(h) h$format == "long", logical(1)))

  if (!long_format) {
    cat_types <- c("binary", "nominal", "ordinal_candidate", "ordinal_or_nominal_code")
    seen <- character()

    # 2. Numbered columns with the same stem, e.g. G1, G2, G3 or score_t1, score_t2 (Part 3).
    stems <- sub("[_.]?(t|time|wave)?[0-9]+$", "", names(data), ignore.case = TRUE)
    numbered <- grepl("[0-9]+$", names(data)) & nchar(stems) > 0
    for (st in unique(stems[numbered])) {
      cols <- names(data)[numbered & stems == st]
      if (length(cols) < 2) next
      if (length(unique(types[cols])) != 1 || types[cols[1]] %in% c("id", "empty")) next
      seen <- c(seen, paste(sort(cols), collapse = "|"))
      add(list(
        type = "repeated_wide", columns = I(cols), format = "wide",
        evidence = sprintf("%s 欄名相同、只差編號，型態都是 %s，像是同一件事的重複測量", paste(cols, collapse = "、"),
                           types[cols[1]]),
        question = sprintf("%s 是不是同一個人在不同時間（或情境）的測量？若是，會轉成長格式，每人 %d 列。",
                           paste(cols, collapse = "、"), length(cols)),
        suggested = list(reshape_cols = I(cols)),
        book_ref = "§9.1"))
    }

    # 3. Two columns whose names differ only in the first letter and that share the same
    #    categories, e.g. Dalc/Walc (weekday/weekend), Mjob/Fjob (mother/father) (Part 3).
    cand <- names(data)[types %in% cat_types & nchar(names(data)) >= 3]
    for (i in seq_along(cand)) for (j in seq_along(cand)) {
      if (j <= i) next
      a <- cand[i]; b <- cand[j]
      if (nchar(a) != nchar(b) || substring(a, 2) != substring(b, 2)) next
      if (!identical(.level_set(data[[a]]), .level_set(data[[b]]))) next
      key <- paste(sort(c(a, b)), collapse = "|")
      if (key %in% seen) next
      seen <- c(seen, key)
      add(list(
        type = "possible_matched_pairs_wide", columns = I(c(a, b)), format = "wide",
        evidence = sprintf("%s 和 %s 的欄名只差第一個字母，類別也完全相同（%s）", a, b,
                           paste(.level_set(data[[a]]), collapse = "/")),
        question = sprintf("%s 和 %s 是不是同一個人對兩個相似問題（或兩個時間）的回答？", a, b),
        suggested = list(y1 = a, y2 = b),
        book_ref = "§8.1"))
    }

    # 4. Wide matched pairs by name pattern or a shared text scale (rule from Part 1).
    cat_cols <- names(data)[types %in% cat_types]
    if (length(cat_cols) >= 2) {
      sets <- lapply(cat_cols, function(cc) .level_set(data[[cc]]))
      names(sets) <- cat_cols
      for (i in seq_along(sets)) {
        same <- names(sets)[vapply(sets, identical, logical(1), sets[[i]])]
        key <- paste(sort(same), collapse = "|")
        if (length(same) < 2 || key %in% seen) next
        named_like_pairs <- sum(grepl(.pair_name_pattern, same, ignore.case = TRUE)) >= 2
        text_scale <- length(sets[[i]]) >= 3 && !is.numeric(data[[same[1]]])
        if (!named_like_pairs && !text_scale) next
        seen <- c(seen, key)
        add(list(
          type = "possible_matched_pairs_wide", columns = I(same), format = "wide",
          evidence = sprintf("%s 的類別完全相同（%s）%s", paste(same, collapse = "、"), paste(sets[[i]], collapse = "/"),
                             if (named_like_pairs) "，且欄名像前後測或重複測量" else ""),
          question = sprintf("%s 是不是同一個人在不同時間或不同題目的回答（配對資料）？還是只是剛好用相同選項的不同變數？",
                             paste(same, collapse = "、")),
          suggested = if (length(same) == 2) list(y1 = same[1], y2 = same[2]) else list(reshape_cols = I(same)),
          book_ref = "§8.1"))
      }
    }
  }

  # 5. Aggregated data: each row is a cell, not a subject (rule from Part 1).
  freq_cols <- names(types)[types == "frequency_weight"]
  if (length(freq_cols) > 0) {
    add(list(
      type = "aggregated_counts", columns = I(freq_cols), format = "aggregated",
      evidence = sprintf("%s 看起來是次數欄，每一列可能代表一個格子而不是一個人", paste(freq_cols, collapse = "、")),
      question = sprintf("%s 是否代表「這種組合有幾個人」？本 Skill 需要一人（或一人一次）一列的資料。",
                         paste(freq_cols, collapse = "、")),
      book_ref = "§8.2.3"))
  }

  list(
    n_rows = nrow(data),
    hints = hints,
    default = if (length(hints) == 0) "no_correlation_detected" else "needs_confirmation",
    note = paste0("資料本身無法證明哪些列屬於同一個人或同一群（§1.1.3）。沒有偵測到線索不代表資料獨立；",
                  "偵測到線索也要使用者確認。")
  )
}

cc_profile <- function(data) {
  data <- as.data.frame(data, check.names = FALSE)
  vars <- lapply(names(data), function(nm) profile_variable(data[[nm]], nm))
  names(vars) <- names(data)
  list(n_rows = nrow(data), n_cols = ncol(data), variables = unname(vars),
       structure = detect_structure(data, vars))
}

.type_label <- c(binary = "二元", nominal = "名目", ordinal_candidate = "可能有序（請確認順序）",
                 ordinal_or_nominal_code = "數字代碼（有序或名目？）", continuous = "連續數值",
                 count_or_continuous = "計數或連續", frequency_weight = "次數欄？", id = "識別碼",
                 nominal_many_levels = "名目（類別很多）", empty = "全部缺失")

# Stage 1 overview shown to the user (no plots at this stage).
cc_overview_md <- function(profile, file_name) {
  rows <- vapply(profile$variables, function(v) {
    lv <- if (!is.null(v$levels) && length(v$levels) <= 8)
      paste(sprintf("%s（%d）", names(v$levels), unlist(v$levels)), collapse = "、")
      else if (!is.null(v$range)) sprintf("範圍 %s–%s，%d 種值", v$range[1], v$range[2], v$n_unique)
      else sprintf("%d 種值，例如 %s", v$n_unique, paste(v$examples, collapse = "、"))
    sprintf("| %s | %s%s | %d | %s |", v$name, .type_label[[v$type_guess]] %||% v$type_guess,
            if (isTRUE(v$needs_confirmation)) " ❓" else "", v$n_missing, lv)
  }, "")
  hints <- profile$structure$hints
  hint_md <- if (length(hints)) unlist(lapply(seq_along(hints), function(i) {
    h <- hints[[i]]
    c(sprintf("%d. **%s**：%s（Agresti %s）", i, h$type, h$evidence, h$book_ref),
      sprintf("   - 要問使用者：%s", h$question))
  })) else "- 沒有偵測到明顯的線索。**這不代表資料彼此獨立**，仍要請使用者說明每一列的關係。"
  c(sprintf("# 資料總覽：%s", file_name), "",
    sprintf("共 %d 列、%d 欄。", profile$n_rows, profile$n_cols), "",
    "## 變數", "", "❓ = 型態需要使用者確認。", "",
    "| 變數 | 型態猜測 | 缺失 | 類別與次數 |", "|---|---|---|---|", rows, "",
    "## 資料可能不獨立的線索", "", hint_md, "",
    sprintf("> %s", profile$structure$note))
}
