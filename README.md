# categorical-correlated

一個 Claude Skill，分析**不獨立**的類別資料：同一個人被測量兩次以上（配對、前後測、重複測量），或同一群體內的多筆觀察（叢集）。

**資料結構偵測 → 問使用者想問什麼 → 確認清單 → 依問題畫圖 → 判斷適不適合（✅／⚠️／❌），等使用者 OK → 計算 → 白話解釋並存成報告**

所有數字都由 Skill 內的程式計算，Claude 不可以自己算、換方向或加總。方法依據 Agresti《An Introduction to Categorical Data Analysis》第 3 版第 8–10 章。
本 Skill 是類別資料分析期中報告的 **Part 3（相關資料）**；Part 1（關聯分析，categorical-association）與 Part 2（類別模型，categorical-modeling）是組員的 Skill，兩者遇到配對、重複測量、叢集資料時會轉介到這裡。

## 先看這兩頁

| 檔案 | 內容 |
|---|---|
| `correlated-report.html` | Part 3 報告：配對（McNemar、邊際同質性）、整體平均 vs 同一個人、GEE、GLMM、Skill 介紹與真實資料實測 |
| `make-skill-tutorial.html` | 製作教學：要解決的問題、運作方式、安裝與跟著做、三層驗證、開發過程 |

兩個 `.html` 都是單一檔案，下載後用瀏覽器打開即可。`.qmd` 是原始檔，在 Part3 資料夾用 Quarto render（頁面上的數字會由 Skill 的程式重新計算）。

## 涵蓋的方法

| 情境 | 方法 | 課本 |
|---|---|---|
| 同一批人兩次，二元 | McNemar＋相依比例差的 score 信賴區間＋條件勝算比 | §8.1、§8.2.4 |
| 同一批人兩次，名目 | 邊際同質性（對稱 vs 準對稱 LR）＋逐類別追蹤 | §8.3 |
| 同一批人兩次，有序 | 累積 logit 邊際模型（GEE）＋有序準對稱 | §8.4 |
| 有解釋變數，整體平均 | GEE：邊際 logistic、累積 logit、baseline-category logit | §9.2–9.3 |
| 有解釋變數，同一個人 | GLMM：隨機截距 logistic | §10.1–10.2 |
| 兩種效果都要 | GEE 與 GLMM 並排 | §10.1.4 |

不做（說明並轉介）：資料其實獨立 → Part 1／Part 2；評分者一致性（§8.5）、Bradley–Terry（§8.6）、有序或名目的 GLMM、多層模型（§10.3–10.4）、計數或連續結果。

## 資料夾內容

```
Part3/
├── categorical-correlated.zip    打包好的 Skill（claude.ai 上傳用；重新打包：python dev/build_zip.py）
├── categorical-correlated/       Skill 本體（上傳或複製這個資料夾）
│   ├── SKILL.md
│   ├── references/               決策樹、注意事項清單、方法與 R 程式碼、課本公式
│   ├── R/                        計算引擎（R 版，模式 1）
│   └── scripts/                  各階段腳本：*.R（模式 1）、*.py（模式 2，沒有 R 時）
├── correlated-report.qmd/.html   Part 3 報告
├── make-skill-tutorial.qmd/.html 製作教學
├── skill規劃.md、章節建議.md       規劃文件
└── dev/
    ├── textbook_data.R           由課本表格重建的 7 個例子
    ├── verify_methods.R          methods.md 的程式碼 vs 課本（45 項）
    ├── test_engine.R             R 引擎 vs 課本（70 項）
    ├── test_python.py            Python 版 vs 課本與 R 版（57 項）
    ├── demo/                     示範資料 student_por.csv 與各分析的輸出
    ├── skill-test/               真實資料實測：judgment.yml、verify.R、實測腳本、實測結果、輸出
    ├── build_zip.py              打包 categorical-correlated.zip
    └── ai-log.csv                AI 使用紀錄
```

## 安裝

**Claude Code（Windows，有 R）**

1. 安裝 R 套件：`Rscript categorical-correlated/scripts/install_packages.R`
2. 把 `categorical-correlated` 資料夾複製到 `C:\Users\<使用者名稱>\.claude\skills\`（或專案的 `.claude\skills\`）。
3. 在資料所在的資料夾開啟 Claude Code，輸入「請用 categorical-correlated skill 分析 <資料檔>：<問題>」。

**claude.ai 網頁版（沒有 R）**：在「設定 → 功能」開啟程式碼執行，再到「Skills」上傳 `categorical-correlated.zip`。Skill 會改用 Python 版；Python 版不做 GLMM，需要時會給 R 程式碼請使用者自己執行。

**不要上傳含個人資料的檔案**（姓名、學號、病歷）。

## 測試

在 Part3 資料夾執行：

```
Rscript dev/verify_methods.R      # references/methods.md 的程式碼 vs 課本
Rscript dev/test_engine.R         # R 引擎 vs 課本
python dev/test_python.py         # Python 版 vs 課本與 R 版（需要先跑過 dev/demo 的 R 輸出）
Rscript dev/skill-test/verify.R   # 實測題目的獨立驗證
```

## 示範資料

`dev/demo/student_por.csv`：Cortez, P. (2008). Student Performance [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5TG7T>。授權：CC BY 4.0。取自組員 Part 2 的版本（逗號分隔，新增 `pass` 欄 = G3 ≥ 10）。

| 欄位 | 用途 |
|---|---|
| `Dalc`、`Walc` | 同一位學生平日、週末喝酒程度（1–5）→ 有序配對 |
| `Mjob`、`Fjob` | 同一位學生媽媽、爸爸的職業 → 名目配對 |
| `G1`、`G2`、`G3` | 同一位學生三次成績（0–20）→ 轉成及格與否後是重複測量 |

課本例子的資料由書中印出的表格重建（`dev/textbook_data.R`），不另外下載。

## 使用的軟體

- R Core Team. *R: A language and environment for statistical computing*；套件 geepack（Halekoh et al., 2006）、multgee（Touloumis, 2015）、lme4（Bates et al., 2015）、PropCIs（Scherer）、ggplot2、jsonlite、readr、readxl、scales、yaml、knitr
- Python：numpy、pandas、scipy、statsmodels（Seabold & Perktold, 2010）、matplotlib
- Quarto：產生報告頁與製作教學
- 開發過程使用 Claude Code（Anthropic）輔助，紀錄見 `dev/ai-log.csv`

## 參考文獻

Agresti, A. (2019). *An Introduction to Categorical Data Analysis* (3rd ed.). Wiley.
