# 分析報告：Marginal logistic model fitted by GEE

- 資料檔：`student_por.csv`
- 方法：Marginal logistic model fitted by GEE（Agresti §9.2）
- 效果的意義：整體平均（population-averaged）

## 描述統計

| time | n | successes | proportion |
|---|---|---|---|
| 1 | 649 | 492 | 0.7581 |
| 2 | 649 | 504 | 0.7766 |
| 3 | 649 | 549 | 0.8459 |

## 結果

- 資料沒有 id 欄，依列號產生 id（1–649），每一列視為一個叢集。
- 把 G1、G2、G3 轉成長格式：G 欄為測量值，period 欄為時間（1 = G1、2 = G2、3 = G3），共 1947 列。
- 新變數 passed 由 G 轉換：< 10 → fail；≥ 10 → pass。
- 提醒：把連續的 G 切成類別會損失資訊，結論可能隨切點改變。
- 共 649 個叢集、1947 筆觀察值；每個叢集的筆數：3 筆 649 個。
- 叢集間變數（同一個叢集內不變）：sex；叢集內變數（同一個叢集內會變）：period。
- 邊際 logistic 模型（GEE），成功 =「pass」，working correlation = independence。
- period2：整體來說，勝算比 = 1.110（95% 信賴區間 0.946 到 1.303），P = 0.200。
- period3：整體來說，勝算比 = 1.759（95% 信賴區間 1.482 到 2.089），P < 0.001。
- sexM：整體來說，勝算比 = 0.643（95% 信賴區間 0.461 到 0.898），P = 0.010。
- Wald (robust SE): period = 47.90（df = 2），P < 0.001。
- Wald (robust SE): sex = 6.72（df = 1），P = 0.010。

## 檢定

| test | statistic | df | p_value | book_ref |
|---|---|---|---|---|
| Wald (robust SE): period | 47.9019 | 2 | 3.965e-11 | §9.2.4 |
| Wald (robust SE): sex | 6.7177 | 1 | 0.0095 | §9.2.4 |

## 估計值

| term | estimate | se | z | p_value | odds_ratio | or_lower | or_upper | or_reverse | or_reverse_lower | or_reverse_upper |
|---|---|---|---|---|---|---|---|---|---|---|
| (Intercept) | 1.3351 | 0.1245 | 10.7227 | 7.960e-27 | 3.8003 | 2.9774 | 4.8507 | 0.2631 | 0.2062 | 0.3359 |
| period2 | 0.1045 | 0.0816 | 1.2804 | 0.2004 | 1.1102 | 0.9460 | 1.3028 | 0.9008 | 0.7676 | 1.0570 |
| period3 | 0.5650 | 0.0875 | 6.4578 | 1.062e-10 | 1.7594 | 1.4822 | 2.0885 | 0.5684 | 0.4788 | 0.6747 |
| sexM | -0.4411 | 0.1702 | -2.5918 | 0.0095 | 0.6434 | 0.4609 | 0.8981 | 1.5543 | 1.1135 | 2.1697 |

> GEE 的 robust SE 是大樣本方法，叢集少時傾向低估（§9.2.4）；本資料有 649 個叢集，課本沒有給門檻，請自行判斷是否足夠。

## 圖

![](proportions.png)

> 勝算比是「整體平均」的效果；SE 為 robust（sandwich）SE，即使 working correlation 設錯也有效（§9.2.2）。
