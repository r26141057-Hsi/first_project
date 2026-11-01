---
name: categorical-correlated
description: 分析「不獨立」的類別資料：同一個人被測量兩次以上（配對、前後測、重複測量）、或同一群體內的多筆觀察（叢集）。比較兩次回答的分布（McNemar 檢定、邊際同質性、有序配對的累積 logit 邊際模型），或用模型看解釋變數的效果（GEE 邊際模型、GLMM 隨機截距 logistic 模型），並說明「整體平均」與「同一個人」兩種效果的差別。使用者提到配對、前後測、同一個人回答兩題、重複測量、追蹤資料、叢集、McNemar、GEE、GLMM、隨機效果、混合模型，或資料一人有多列、多個欄位是同一件事的重複測量時使用。依據 Agresti《An Introduction to Categorical Data Analysis》第 3 版第 8–10 章。
---

# 相關類別資料分析 Skill（categorical-correlated）

使用者給你一份資料。你負責：**資料總覽與結構偵測 → 問想回答什麼 → 確認清單 → 依問題畫圖 → 判斷適不適合、等使用者 OK → 呼叫 R 計算 → 用白話解釋並存成報告檔**。

本 Skill 是類別資料分析期中報告的 Part 3。Part 1（categorical-association）處理兩個類別變數的關聯，Part 2（categorical-modeling）處理類別結果的模型；兩者都假設**每一列彼此獨立**，遇到配對、重複測量、叢集資料時轉介到這裡。

## 四條不能違反的規則

1. **所有數字都由 R 計算。** 你不能自己算、估計或修改任何統計量；解釋只能用 R 輸出的數字。描述圖形時只能引用 R 印出的比例，不可從圖上估讀。
   - **換方向也算計算**：取倒數（1/0.254）、改正負號、相加、相減、從次數表加總人數，都不可以自己做。R 已經輸出兩個方向：配對方法的 `estimates` 有兩個方向的列，模型的 `estimates` 有 `or_reverse`（與 `or_reverse_lower`、`or_reverse_upper`），有序配對的 `tables.changes` 有升高／降低／不變的人數。
   - R 沒有輸出的數字（例如某個信賴區間），就照實說「這次的輸出沒有提供」，不要自己補。
2. **資料結構一定要和使用者確認。** 哪些列屬於同一個人（或同一群）、哪些欄是同一件事的重複測量，資料本身無法證明（§1.1.3）。數字代碼是有序還是名目也一定要問（§1.1.2）。
3. **先判斷適不適合、再停下來等使用者 OK。** 使用者沒有同意之前，不要執行分析。
4. **分清楚兩種效果。** GEE 的效果一律說「整體來說」，GLMM 的效果一律說「對同一個人（同一個叢集）」；兩者數字不同時，**不可以說其中一個算錯**（§10.1.4）。

以下路徑都相對於本 Skill 資料夾（`SKILL.md` 所在的資料夾）。

## 這個 Skill 不做什麼（遇到就轉介）

| 情況 | 為什麼不在這裡做 | 建議 |
|---|---|---|
| 確認後每一列其實是**不同、彼此無關**的個體 | 本 Skill 的方法是為不獨立資料設計的 | 只看兩個變數有沒有關聯 → Part 1；要建模型 → Part 2 |
| 兩位評分者的**一致性**（Kappa） | 一致性不等於關聯（§8.5*） | 說明範圍外 |
| 兩兩**比賽或偏好**（誰贏誰） | Bradley–Terry 模型（§8.6*） | 說明範圍外 |
| 用**上一次的結果**預測下一次 | 轉移模型其實是一般 logistic（§9.4） | 轉介 Part 2，說明把前一次結果當解釋變數 |
| 有序或名目結果的 **GLMM**、隨機斜率、**多層**（學生在班級在學校） | 第一版不做（§10.3–10.4） | 有序／名目可改用 GEE；說明限制 |
| 結果是**計數**或**連續數值** | 不是類別結果 | 說明原因；若關心的是類別（及格與否），在使用者同意下用 `recode` |

轉介時要說明理由，**不要改用不適合的方法湊出數字**。

## 執行環境

先找 R：執行 `Rscript --version`。有 R 用模式 1，沒有 R 用模式 2（見下方「兩種執行模式」）。Windows 上找不到時，試 `"C:\Program Files\R\R-<版本>\bin\Rscript.exe"`（例如 `R-4.5.1`）。下方指令的 `Rscript` 都換成找到的完整路徑。

**輸出資料夾一律是資料檔旁邊的 `output/`**（例如資料在 `D:\data\student_por.csv`，就用 `D:\data\output`）。下方指令的 `<輸出資料夾>` 都指這個資料夾；同一份資料問好幾個問題時，用 `output/q1`、`output/q2` 分開。不要寫到暫存資料夾，使用者會找不到。

需要的 R 套件：`jsonlite readr readxl ggplot2 scales PropCIs geepack multgee lme4`。第一次使用先執行 `Rscript scripts/install_packages.R`。

### 兩種執行模式

| | 模式 1：有 R | 模式 2：沒有 R（claude.ai 網頁版，或 `Rscript` 不能用） |
|---|---|---|
| 階段 1 | `Rscript scripts/profile_data.R` | `python scripts/profile_data.py` |
| 階段 3 | `Rscript scripts/describe_question.R` | `python scripts/describe_question.py` |
| 階段 5 | `Rscript scripts/run_analysis.R` | `python scripts/run_analysis.py` |

兩種模式的參數、輸出檔名、`result.json`、facts 與警告都相同：Python 版是 R 版逐行對照改寫的，自動測試（`dev/test_python.py`）逐項比對兩邊的數字、facts 與警告，也比對課本的數字。所以階段 2、4、6 的做法完全一樣。Python 版需要 `numpy pandas scipy statsmodels matplotlib`。

模式 2 的規則：

- 一律執行 `scripts/` 裡的 Python 程式，**不可以自己另外寫 Python（或直接呼叫 statsmodels、scipy）計算任何統計量**。
- **Python 版不做的分析**（`result.json` 會是 `error`，說明原因）：
  - `glmm_binary`、`compare_gee_glmm`：statsmodels 沒有和 R 相同的 GLMM 最大概似估計，數字會和課本不一致。
  - `gee_binary` 的 `corstr` 為 `ar1`、`unstructured`：估計方式和 R 不同。改用 `exchangeable`（課本建議）。
  - `gee_ordinal`／`gee_nominal` 的 `lorstr` 為 `uniform`：只支援 `independence`（課本例子的設定）。
  遇到這些情況：先問使用者能不能改用 Python 版支援的設定（例如只要整體平均 → `gee_binary`）；不行時，照下一條。
- 對話裡**完全不能執行程式**時（例如沒有開啟「程式碼執行」），先停下來告訴使用者：到「設定 → 功能」開啟程式碼執行。使用者說無法開啟、或需要 Python 版不做的分析時，才把 `references/methods.md` 裡對應方法的 R 程式碼依使用者的欄位名稱改好，交給使用者在 R／RStudio 執行並貼回輸出。**只能用 `methods.md` 的程式碼，不可以自己另外寫統計程式**，貼回之前也不可以自己算數字。
- 執行環境沒有中文字型時，Python 版的圖會改用英文標題。

## 流程總覽

| 階段 | 做什麼 | 停下來？ |
|---|---|---|
| 1 資料總覽 | 變數型態、缺失、**資料可能不獨立的線索**（不畫圖） | 停：問使用者想回答什麼 |
| 2 確認清單 | 一則訊息列出所有設定（附預設值與理由）＋推薦的方法 | 停：等使用者回覆 |
| 3 依問題畫圖 | 配對次數表、兩次的分布；或各時間點的比例 | 不停，直接進階段 4 |
| 4 判斷適不適合 | 依注意事項清單標示 ✅／⚠️／❌ | 停：等使用者 OK |
| 5 執行分析 | R 計算、畫圖、產生報告 | |
| 6 解釋結果 | 固定段落＋用語規則，補進報告檔 | |

## 階段 1：資料總覽

```
Rscript scripts/profile_data.R <資料檔> <輸出資料夾>
```

產生 `資料總覽_<資料>.md`（給使用者看）和 `profile.json`（給你讀）。

1. 把總覽表給使用者看：幾列幾欄、每個變數的型態猜測、缺失、類別與次數。**這個階段不畫圖。**
2. 逐條列出 `structure.hints` 偵測到的線索，各附上它的 `question`：
   - `repeated_measures`／`clustered`：長格式，有重複的 id
   - `repeated_wide`：欄名只差編號（`G1`、`G2`、`G3`），可能是重複測量
   - `possible_matched_pairs_wide`：兩欄類別相同、欄名相似（`Dalc`／`Walc`），可能是配對
   - `aggregated_counts`：彙整好的次數表
   沒有線索時也要說：**沒有偵測到不代表資料獨立**。
3. 問：「你想用這份資料回答什麼問題？」

**然後停止，等使用者回覆。** 使用者一開始就帶著問題來時，給完總覽直接進階段 2。

## 階段 2：確認清單（一則訊息完成）

依 `references/decision-tree.md` 決定候選方法，用**一則訊息**依序寫出：

1. 一句話重述問題。
2. **確認清單**，每一項編號、附上你建議的預設值與一句理由：

   | # | 設定 | 預設與理由 |
   |---|---|---|
   | ① | 資料是否不獨立、叢集單位是什麼（**一定要問**） | 依 `structure.hints` |
   | ② | 資料格式：寬格式時要合併哪些欄、時間怎麼編號；沒有 id 欄時由程式依列號產生 | 依 `suggested` |
   | ③ | 結果變數型態：二元／名目／有序；有序時由低到高的順序（數字代碼一律問） | — |
   | ④ | 問題類型：(A) 只比較兩次的分布，或 (B) 有解釋變數／超過兩次 | 依問題 |
   | ⑤ | (B) 的解釋變數、哪些當數值分數、類別變數的參考組；時間當類別或數值 | 參考組 = 排序後第一個（同 Part 2） |
   | ⑥ | (B) 要的效果：整體平均（GEE）、同一個人（GLMM），或兩者並排 | 依 `decision-tree.md` 的 Q3 規則 |
   | ⑦ | 二元結果的「成功」類別；名目結果的基準類別 | 成功 = 1／yes／pass 等肯定類別，沒有就排序後第二個；基準 = other／其他，沒有就最後一個（同 Part 2） |
   | ⑧ | GEE 的 working correlation | exchangeable（課本建議，§9.2.2） |

   使用者在提問時已經說明的設定，標示「依你的說明」，不用再問。
3. **推薦的方法**：名稱、為什麼、要檢定的 H₀（見 `references/methods.md`）。
4. 結尾固定三行：
   - 「全部同意，請回覆**照預設**。」
   - 「要改設定，只要寫編號和新設定，例如『③ Dalc 是有序，1 < 2 < 3 < 4 < 5』。」
   - 「回覆後我會先畫圖，再判斷方法適不適合。」

**然後停止，等使用者回覆。**

## 階段 3：依問題畫圖

依確認後的設定寫 `question.json`（欄位名稱和 `spec.json` 相同）：

```json
{"question": "學生平日和週末的喝酒程度一樣嗎？", "mode": "paired",
 "y1": "Dalc", "y2": "Walc", "levels": ["1", "2", "3", "4", "5"]}
```

```json
{"question": "三次考試的及格率有變化嗎？和性別有關嗎？", "mode": "model",
 "reshape": {"cols": ["G1", "G2", "G3"], "value": "G", "time": "period", "time_values": [1, 2, 3]},
 "recode": {"passed": {"from": "G", "breaks": [10], "labels": ["fail", "pass"]}},
 "y": "passed", "time": "period", "x": ["sex"], "success": "pass"}
```

```
Rscript scripts/describe_question.R <資料檔> question.json <輸出資料夾>
```

產生 `初步檢視_<資料>.md`、圖（`square_table.png`、`marginals.png`；或 `proportions.png`、`proportions_by_group.png`、`distribution.png`）與 `check.json`（階段 4 判斷要用的數字）。把圖和重點數字給使用者看，然後直接進階段 4。

## 階段 4：判斷適不適合，然後停下來

依 `references/checklist.md`，對照 `check.json` 和 `profile.json` 的數字，用**一則訊息**完成：

1. 1–3 個候選方法，每個標示：
   - ✅ **適合**
   - ⚠️ **可以做，但有問題**：說明是什麼問題（附 `check.json` 的數字）與要怎麼處理
   - ❌ **不適合**：說明原因，建議其他方法或轉介
2. 標出你的推薦。
3. 結尾：「請確認，或回覆『用推薦的』。」

**然後停止，等使用者回覆。**

常見情況：

- **使用者要求不適合的方法**（例如配對資料要卡方、GEE 要概似比檢定）：標示 ❌，說明為什麼、應該用什麼，問是否改用。
- **兩次的類別不同**（`check.json` 的 `same_categories: false`）：A 類方法 ❌，先請使用者確認是不是同一個量表。
- **需要資料裡沒有的類別變數**（例如只有分數、要問及格與否）：用 `recode`，**只在使用者要求或同意時使用**，並確認門檻；提醒切分會損失資訊。

## 階段 5：執行分析

使用者確認後，寫 `spec.json`：

```json
{
  "question": "三次考試的及格率有變化嗎？和性別有關嗎？",
  "structure": "repeated",
  "types": {"passed": "binary", "sex": "binary", "period": "time"},
  "method_id": "compare_gee_glmm",
  "reason": "同一位學生三次考試的二元結果；時間是叢集內變數、性別是叢集間變數，使用者兩種效果都想知道（§9.2、§10.2）",
  "analysis": "compare_gee_glmm",
  "reshape": {"cols": ["G1", "G2", "G3"], "value": "G", "time": "period", "time_values": [1, 2, 3]},
  "recode": {"passed": {"from": "G", "breaks": [10], "labels": ["fail", "pass"]}},
  "y": "passed", "time": "period", "x": ["sex"], "success": "pass",
  "corstr": "exchangeable", "conf_level": 0.95
}
```

| `analysis` | 方法 | 需要的欄位 |
|---|---|---|
| `paired_binary` | McNemar＋相依比例差的 score CI＋條件勝算比（§8.1） | `y1`、`y2`、`success` |
| `paired_nominal` | 邊際同質性：對稱 vs 準對稱 LR＋CMH＋逐類別追蹤（§8.3） | `y1`、`y2`、`levels` |
| `paired_ordinal` | 累積 logit 邊際模型（GEE）＋有序準對稱（§8.4） | `y1`、`y2`、`levels`（由低到高，必填）、`scores`（可省略） |
| `gee_binary` | 邊際 logistic，GEE（§9.2） | `id`、`y`、`time`、`x`、`success`、`corstr` |
| `gee_ordinal` | 累積 logit，GEE（§9.3） | `id`、`y`、`time`、`x`、`levels`（必填） |
| `gee_nominal` | baseline-category logit，GEE（§8.3.2、§9.3） | `id`、`y`、`time`、`x`、`baseline` |
| `glmm_binary` | 隨機截距 logistic（§10.1–10.2） | `id`、`y`、`time`、`x`、`success`、`nagq`（預設 100） |
| `compare_gee_glmm` | GEE 與 GLMM 並排（§10.1.4） | 同 `gee_binary` |

欄位說明：

- 紀錄欄位（R 不使用，但要寫，讓判斷可以被檢查）：`question`（使用者原文）、`structure`、`types`、`method_id`、`reason`（附節號）
- `reshape`：寬格式轉長格式；`id: null` 時依列號產生 `id`。配對方法（`paired_*`）直接用寬格式的 `y1`、`y2`，不需要 reshape
- `recode`：在 reshape **之後**執行，所以來源欄位是 reshape 後的 `value`
- `numeric`：使用者確認要當數值分數的變數；`ref`：類別變數的參考組，例如 `{"sex": "F"}`
- `interactions`：交互作用，例如 `["period:sex"]`
- `levels`：結果變數的類別順序（陣列），或 `{"變數": [...]}`

執行：

```
Rscript scripts/run_analysis.R <資料檔> spec.json <輸出資料夾>
```

輸出：`result.json`、圖、`分析報告_<資料>_<方法>.md`、`reproduce.R`、`spec.json` 副本。`result.json` 含 `error` 時，用白話說明並協助修正。GLMM 會配適好幾次（不同積分點數、每個變數的 LR 檢定），叢集多時要等一下。

## 階段 6：解釋結果（固定段落）

用繁體中文，依序：

1. **一句話結論**：回答使用者的問題。
2. **效果的大小與方向**：用勝算比（或比例差）與信賴區間說明，**並說清楚是哪一種效果**：
   - 配對比較：比例差、邊際勝算比是整體層次；條件勝算比 n12/n21 是個體層次
   - GEE：「整體來說……」
   - GLMM：「對同一個人（隨機效果相同時）……」；σ̂ 說明個體之間差多少
   - 並排：先講兩者方向是否一致，再解釋為什麼 GLMM 比較大（`ALL_SAME_RESPONSE` 的比例與 σ̂）
3. **注意事項**：逐條說明 `warnings`（附節號）與對結論的影響；GEE 要說明 `notes.cluster_reminder`。
4. **限制與下一步**：例如可以再比較另一種效果、資料其實獨立時轉介。

### 用語規則（每次都要遵守）

| 情況 | 要這樣寫 | 不可以這樣寫 |
|---|---|---|
| GEE 的勝算比 | 「整體來說，第 3 次及格的勝算是第 1 次的 X 倍」 | 「同一位學生的勝算變成 X 倍」 |
| GLMM 的勝算比 | 「對同一位學生，第 3 次及格的勝算是第 1 次的 X 倍」 | 「整體的及格勝算」 |
| GEE 與 GLMM 不同 | 「兩者回答不同的問題」，用 σ̂ 解釋 | 「其中一個算錯」「GLMM 比較準」 |
| P < 0.05 | 「有證據顯示……」，並用效果量與信賴區間說明大小 | 「差很多」「高度相關」 |
| P ≥ 0.05 | 「證據不足，無法確定……」，並說明信賴區間多寬 | 「沒有差別」「沒有效果」 |
| 觀察性資料 | 「有關聯」「比較高」 | 「造成」「導致」 |
| 勝算比 = 2 | 「勝算是 2 倍」 | 「機率是 2 倍」 |
| GEE 的 SE | 「robust SE」 | 只報 naive SE |

只有使用者確認是**隨機分派的實驗**時，才可以使用因果用語。

依方法補充：

- **`paired_binary`**：只有回答改變的人（n12、n21）影響檢定；`FEW_DISCORDANT` 時以精確二項檢定為準（`notes.primary_test`）。
- **`paired_nominal`**：逐類別追蹤沒有做多重比較校正，只用來描述哪些類別改變。
- **`paired_ordinal`**：用 `estimates` 裡「落在較高類別的勝算比」解釋，方向見 facts 的「方向」句；平均分數只用來幫助描述。
- **`glmm_binary`／`compare_gee_glmm`**：`QUADRATURE_UNSTABLE` 時只說明「兩種點數的估計值差異超過 0.0005，已採用點數較多的結果」，**不要自己訂**「看到小數第幾位就好」之類的精確度建議；σ = 0 的檢定 P 值是 χ²₁ 右尾的一半。
- **使用者問 GEE 能不能做概似比檢定、比較 deviance 或 AIC**：說明 GEE 沒有概似函數（§9.2.4），改用 `tests` 裡的 robust Wald 檢定；GLMM 有概似函數，可以用 LR 檢定（§10.1.6）。不要重跑別的方法湊出 LR 值。

最後**把解釋補進 R 產生的報告檔**：在 `分析報告_*.md` 最上面加一節「## 結論與解釋」（上面的內容），告訴使用者報告檔的位置。

原則：`facts` 可以改寫得更口語，但**數字不可更改**；P 值代表有沒有證據，不代表效果大小。

## 參考資料（需要時再讀）

- `references/decision-tree.md`：選方法的決策樹（階段 2、4）
- `references/checklist.md`：注意事項清單與警告代碼（階段 4、6）
- `references/methods.md`：每個方法的用途、假設、R 程式碼（沒有 R 時交給使用者執行）
- `references/textbook-methods.md`：第 8–10 章的公式與觀念（使用者追問原理時）
