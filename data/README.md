# 示範資料

上課示範與自己練習都用這個資料夾裡的資料。

## student_por.csv

葡萄牙兩所高中的學生資料，649 位學生、一人一列，和 Part 1、Part 2 用同一份。

來源：Cortez, P. (2008). Student Performance [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5TG7T>。授權：CC BY 4.0。取自組員 Part 2 的版本（逗號分隔，新增 `pass` 欄 = G3 ≥ 10）。

這份資料表面上「一人一列」，但裡面藏著好幾種**不獨立**：

| 欄位 | 意義 | 為什麼不獨立 | 可以問的問題 |
|---|---|---|---|
| `G1`、`G2`、`G3` | 同一位學生三次考試成績（0–20） | 同一個人測三次 → 重複測量 | 三次考試的及格率有沒有改變？和性別有關嗎？ |
| `Dalc`、`Walc` | 同一位學生平日、週末喝酒程度（1 很少 – 5 很多） | 同一個人回答兩題 → 有序配對 | 平日和週末的喝酒程度一樣嗎？ |
| `Mjob`、`Fjob` | 同一位學生媽媽、爸爸的職業 | 同一個家庭的兩個人 → 名目配對 | 媽媽和爸爸的職業分布不同嗎？ |
| `sex`、`school`、`age` 等 | 學生的背景 | 每人一個值，可以當解釋變數 | — |

其他欄位的說明見 UCI 的資料頁。

## 第一個指令

在 Claude Code 裡，於 Part3 資料夾輸入：

```
請用 categorical-correlated skill 分析 data/student_por.csv：學生三次考試的及格率有沒有改變？和性別有關嗎？
```

在 claude.ai 網頁版，先上傳 `student_por.csv`，再輸入：

```
請用 categorical-correlated skill 分析 student_por.csv：學生三次考試的及格率有沒有改變？和性別有關嗎？
```

Skill 會先給資料總覽，接著用一則訊息列出確認清單（哪些欄是同一位學生、及格的門檻、要整體平均還是同一個人的效果……），**每一項都由你回答**。之後每做完一步，Skill 會建議下一步，由你決定要不要做。

Skill 的輸出會寫到資料旁邊的 `data/output/`（不會上傳到 GitHub）。
