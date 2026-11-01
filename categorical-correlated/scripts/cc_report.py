# Python version of R/profile.R, R/describe.R, R/plots.R and the report writer (mode 2).
# Same outputs as the R scripts: profile.json, check.json, result.json companions, PNG plots, Markdown.

import math
import os

import numpy as np
import pandas as pd

import cc_engine as E

# ----------------------------------------------------------------------------- Markdown

def _fmt_cell(v, digits):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "—"
    if isinstance(v, (int, np.integer)) and not isinstance(v, bool):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        if math.isinf(v):
            return "∞" if v > 0 else "−∞"
        if abs(v) < 1e-3 and v != 0:
            return f"{v:.3e}"
        return f"{v:.{digits}f}"
    return str(v)


def md_table(df, digits=4):
    if df is None or len(df) == 0:
        return []
    cols = list(df.columns)
    cells = {}
    for c in cols:
        vals = df[c].tolist()
        nums = [v for v in vals if isinstance(v, (int, float, np.integer, np.floating)) and not isinstance(v, bool)
                and not (isinstance(v, float) and (math.isnan(v) or math.isinf(v)))]
        if nums and len(nums) == sum(v is not None and not (isinstance(v, float) and math.isnan(v)) for v in vals) \
                and all(float(v).is_integer() for v in nums):
            cells[c] = [_fmt_cell(int(v), 0) if isinstance(v, (int, float, np.integer, np.floating)) and not (isinstance(v, float) and (math.isnan(v) or math.isinf(v))) else _fmt_cell(v, 0) for v in vals]
        else:
            cells[c] = [_fmt_cell(v, digits) for v in vals]
    out = ["| " + " | ".join(map(str, cols)) + " |", "|" + "|".join(["---"] * len(cols)) + "|"]
    for i in range(len(df)):
        out.append("| " + " | ".join(cells[c][i] for c in cols) + " |")
    return out


def square_md(t):
    df = pd.DataFrame(t["values"], columns=t["cols"])
    df.insert(0, " ", t["rows"])
    return md_table(df, 0)


# ----------------------------------------------------------------------------- plots

_FONT = None


def _font():
    """A font with Chinese characters; None → English labels (as the Part 1 Python version)."""
    global _FONT
    if _FONT is None:
        from matplotlib import font_manager
        names = {f.name for f in font_manager.fontManager.ttflist}
        for cand in ("Microsoft JhengHei", "Microsoft YaHei", "Noto Sans CJK TC", "Noto Sans CJK SC", "PingFang TC",
                     "Heiti TC", "Arial Unicode MS", "WenQuanYi Zen Hei"):
            if cand in names:
                _FONT = cand
                break
        else:
            _FONT = ""
    return _FONT or None


def _lab(zh, en):
    return zh if _font() else en


def _setup():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    if _font():
        plt.rcParams["font.family"] = [_font(), "sans-serif"]
    plt.rcParams["axes.unicode_minus"] = False
    return plt


def _save(fig, path):
    fig.tight_layout()
    fig.savefig(path, dpi=150, facecolor="white")


def plot_square(t, path):
    plt = _setup()
    m = np.array(t["values"], dtype=float)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.imshow(m, cmap="Blues", aspect="auto")
    for i in range(m.shape[0]):
        for j in range(m.shape[1]):
            ax.text(j, i, int(m[i, j]), ha="center", va="center", fontweight="bold" if i == j else "normal",
                    color="white" if m[i, j] > m.max() * 0.6 else "black")
    ax.set_xticks(range(len(t["cols"])), t["cols"]); ax.set_yticks(range(len(t["rows"])), t["rows"])
    ax.set_xlabel(t["dimnames"][1]); ax.set_ylabel(t["dimnames"][0])
    ax.set_title(_lab("配對次數表（對角線 = 兩次相同）", "Paired table (diagonal = same answer)"), loc="left")
    _save(fig, path); plt.close(fig)


def plot_marginals(t, path):
    plt = _setup()
    m = np.array(t["values"], dtype=float)
    n = m.sum()
    p1, p2 = m.sum(1) / n, m.sum(0) / n
    x = np.arange(len(t["rows"]))
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for off, p, nm, col in ((-0.18, p1, t["dimnames"][0], "#3b82f6"), (0.18, p2, t["dimnames"][1], "#f59e0b")):
        bars = ax.bar(x + off, p, width=0.35, label=nm, color=col)
        for b, v in zip(bars, p):
            ax.text(b.get_x() + b.get_width() / 2, v, f"{v * 100:.1f}%", ha="center", va="bottom", fontsize=8)
    ax.set_xticks(x, t["rows"]); ax.set_ylabel(_lab("比例", "Proportion"))
    ax.yaxis.set_major_formatter(lambda v, _: f"{v * 100:.0f}%")
    ax.set_title(_lab("兩次測量的邊際分布", "Marginal distributions"), loc="left"); ax.legend(frameon=False)
    _save(fig, path); plt.close(fig)


def plot_time_proportion(p, path, success):
    if "time" not in p.columns:
        return False
    plt = _setup()
    fig, ax = plt.subplots(figsize=(7, 4.5))
    x = np.arange(len(p))
    ax.plot(x, p.proportion, marker="o", color="#3b82f6", linewidth=2)
    for xi, v in zip(x, p.proportion):
        ax.text(xi, v + 0.03, f"{v * 100:.1f}%", ha="center", fontsize=9)
    ax.set_xticks(x, p.time); ax.set_ylim(0, 1); ax.set_xlabel("time")
    ax.set_ylabel(_lab(f"比例（{success}）", f"Proportion ({success})"))
    ax.yaxis.set_major_formatter(lambda v, _: f"{v * 100:.0f}%")
    ax.set_title(_lab("各時間點的成功比例", "Proportion by time"), loc="left")
    _save(fig, path); plt.close(fig)
    return True


def plot_group_time(p, g, path, success):
    plt = _setup()
    fig, ax = plt.subplots(figsize=(7, 4.5))
    times = list(dict.fromkeys(p.time))
    for grp, sub in p.groupby("group", sort=False):
        ax.plot([times.index(t) for t in sub.time], sub.proportion, marker="o", linewidth=2, label=str(grp))
    ax.set_xticks(range(len(times)), times); ax.set_ylim(0, 1); ax.set_xlabel("time")
    ax.set_ylabel(_lab(f"比例（{success}）", f"Proportion ({success})"))
    ax.yaxis.set_major_formatter(lambda v, _: f"{v * 100:.0f}%")
    ax.set_title(_lab(f"各時間點的成功比例，依 {g} 分組", f"Proportion by time and {g}"), loc="left")
    ax.legend(title=g, frameon=False)
    _save(fig, path); plt.close(fig)


def plot_time_distribution(dist, lv, path):
    plt = _setup()
    fig, ax = plt.subplots(figsize=(7, 4.5))
    bottom = np.zeros(len(dist))
    colors = plt.get_cmap("Blues")(np.linspace(0.25, 0.95, len(lv)))
    for l, c in zip(lv, colors):
        v = dist[f"prop_{l}"].values
        ax.bar(dist.time.astype(str), v, bottom=bottom, color=c, label=l, width=0.7)
        bottom += v
    ax.set_xlabel("time"); ax.set_ylabel(_lab("比例", "Proportion"))
    ax.yaxis.set_major_formatter(lambda v, _: f"{v * 100:.0f}%")
    ax.set_title(_lab("各時間點的類別分布", "Distribution by time"), loc="left")
    ax.legend(frameon=False, bbox_to_anchor=(1, 1), loc="upper left")
    _save(fig, path); plt.close(fig)


def cc_plots(result, out_dir):
    m, files = result["method"], []
    t = result["tables"]
    if m.startswith("paired_"):
        plot_square(t["counts"], os.path.join(out_dir, "square_table.png")); files.append("square_table.png")
        plot_marginals(t["counts"], os.path.join(out_dir, "marginals.png")); files.append("marginals.png")
    elif m == "gee_binary":
        if plot_time_proportion(t["proportions"], os.path.join(out_dir, "proportions.png"), _lab("成功", "success")):
            files.append("proportions.png")
    elif m in ("gee_ordinal", "gee_nominal"):
        plot_time_distribution(t["distribution"], result["notes"]["levels"], os.path.join(out_dir, "distribution.png"))
        files.append("distribution.png")
    return files


# ----------------------------------------------------------------------------- report

def report_md(result, spec, data_file):
    t = result["tables"]
    desc = t.get("proportions") if t.get("proportions") is not None else t.get("distribution")
    if desc is None:
        desc = t.get("marginal")
    effect = result["notes"].get("effect_type")
    lines = [f"# 分析報告：{spec.get('question') or result['method_label']}", "",
             f"- 資料檔：`{os.path.basename(data_file)}`",
             f"- 方法：{result['method_label']}（Agresti {result['book_ref']}）"]
    if spec.get("structure"):
        lines.append(f"- 資料結構：{spec['structure']}")
    if spec.get("reason"):
        lines.append(f"- 選擇理由：{spec['reason']}")
    if effect:
        lines.append("- 效果的意義：" + ("整體平均（population-averaged）" if effect == "population-averaged" else "同一個叢集（subject-specific）"))
    lines.append("")
    if t.get("counts") is not None:
        lines += ["## 配對次數表", "", "列 = 第一次、欄 = 第二次。", ""] + square_md(t["counts"]) + [""]
    if desc is not None:
        lines += ["## 描述統計", ""] + md_table(desc) + [""]
    lines += ["## 結果", ""] + [f"- {f}" for f in result["facts"]] + [""]
    if len(result["tests"]):
        lines += ["## 檢定", ""] + md_table(result["tests"][["test", "statistic", "df", "p_value", "book_ref"]]) + [""]
    if len(result["estimates"]):
        lines += ["## 估計值", ""] + md_table(result["estimates"]) + [""]
    if result["warnings"]:
        lines += ["## 注意事項", ""] + [f"- **{w['code']}**：{w['message']}（Agresti {w['book_ref']}）" for w in result["warnings"]] + [""]
    if result["notes"].get("cluster_reminder"):
        lines += [f"> {result['notes']['cluster_reminder']}", ""]
    if result.get("plots"):
        lines += ["## 圖", ""] + [f"![]({p})" for p in result["plots"]] + [""]
    lines.append(f"> {result['notes'].get('reminder', '')}")
    return lines


# ----------------------------------------------------------------------------- stage 1: profile

ORDINAL_WORDS = ["非常", "很", "有點", "普通", "還好", "尚可", "不太", "同意", "滿意", "喜歡", "低", "中", "高", "從不", "從未",
                 "很少", "偶爾", "有時", "經常", "時常", "總是", "輕", "重", "差", "好", "優", "劣", "每天", "每週", "每月",
                 "never", "rarely", "seldom", "sometimes", "often", "usually", "always", "low", "medium", "moderate", "high",
                 "none", "slight", "mild", "severe", "poor", "fair", "good", "excellent", "agree", "disagree", "neutral",
                 "satisf", "dissatisf", "strongly", "very", "somewhat", "little"]
import re  # noqa: E402

ID_PAT = re.compile(r"^(id|.*_id|person|subject|case|patient|participant|respondent|student|school|class|cluster|family|household|group|litter|center|centre|hospital|clinic)$|"
                    r"編號|學號|代號|受試|個案|病患|病人|受訪|學生|學校|班級|家庭|家戶|醫院|群組", re.I)
TIME_PAT = re.compile(r"^(time|visit|week|month|year|wave|occasion|round|period|trial|session|situation|question|item|condition|t)$|"
                      r"時間|時點|次數|第幾|週|月份|年度|期|回合|題目|情境", re.I)
PAIR_PAT = re.compile(r"pre|post|before|after|baseline|follow|^y[0-9]$|^t[0-9]$|前測|後測|之前|之後|第一次|第二次", re.I)
COUNT_PAT = re.compile(r"^(n|count|counts|freq|frequency|weight|wt)$|次數|人數|頻數|數量|個數", re.I)
AGE_PAT = re.compile(r"^age$|_age$|^age_|年齡|歲", re.I)
CAT_TYPES = ("binary", "nominal", "ordinal_candidate", "ordinal_or_nominal_code")


def profile_variable(v, name):
    n = len(v); miss = int(v.isna().sum())
    x = v.dropna()
    uniq = list(dict.fromkeys(x.tolist()))
    k = len(uniq)
    is_num = pd.api.types.is_numeric_dtype(x) and not pd.api.types.is_bool_dtype(x)
    int_like = is_num and k > 0 and bool(np.all(np.abs(x - np.round(x)) < 1e-8))
    lev_counts = None
    if k <= 20:
        order = E.code_order(x.tolist())
        cnt = pd.Series(E.as_chr(x)).value_counts()
        lev_counts = {l: int(cnt.get(l, 0)) for l in order}
    guess, confirm, reason = "nominal", False, ""
    if k == 0:
        guess, reason = "empty", "全部缺失"
    elif ID_PAT.search(name) and k > 10:
        guess, reason = "id", "欄名像識別碼，且類別很多"
    elif k == len(x) and k > 20 and (int_like or not is_num):
        guess, reason = "id", "每一列的值都不同"
    elif k == 2:
        guess, reason = "binary", "只有 2 種值"
    elif is_num and AGE_PAT.search(name):
        guess, reason = "continuous", "欄名像年齡，視為數值變數"
    elif is_num and not int_like:
        guess, reason = "continuous", "含小數的數值"
    elif int_like and k <= 10 and x.max() - x.min() == k - 1:
        guess, confirm = "ordinal_or_nominal_code", True
        reason = f"只有 {k} 個連續整數（{E.r_str(x.min())}–{E.r_str(x.max())}），可能是有序量表或類別代碼"
    elif int_like and x.min() >= 0 and COUNT_PAT.search(name):
        guess, confirm, reason = "frequency_weight", True, "欄名像次數，可能是彙整資料的次數欄"
    elif int_like and x.min() >= 0:
        guess, confirm, reason = "count_or_continuous", True, "非負整數且值很多，可能是計數或連續量"
    elif is_num:
        guess, reason = "continuous", "數值且值很多"
    elif k > 20:
        guess, confirm, reason = "nominal_many_levels", True, "文字類別超過 20 種，可能是自由填答或識別碼"
    else:
        hits = [any(w.lower() in str(u).lower() for w in ORDINAL_WORDS) for u in uniq]
        if np.mean(hits) >= 0.5:
            guess, confirm, reason = "ordinal_candidate", True, "類別名稱像有順序的量表，請確認順序"
        else:
            reason = "文字類別，看起來沒有順序"
    return {"name": name, "n": n, "n_missing": miss, "n_unique": k, "type_guess": guess, "needs_confirmation": confirm,
            "reason": reason, "levels": lev_counts, "examples": [E.r_str(u) for u in uniq[:5]],
            "range": [E.r_str(x.min()), E.r_str(x.max())] if is_num and k > 0 else None}


def _level_set(v):
    return sorted({E.r_str(a) for a in v.dropna().tolist()})


def detect_structure(data, vars_):
    hints = []
    types = {v["name"]: v["type_guess"] for v in vars_}
    names = list(data.columns)
    id_cols = [c for c in names if ID_PAT.search(c)]
    if "frequency_weight" in types.values():
        id_cols = []
    for idc in id_cols:
        per_id = data[idc].dropna().value_counts()
        if len(per_id) >= 5 and per_id.max() >= 2:
            time_cols = [c for c in names if TIME_PAT.search(c) and c != idc]
            within = [tc for tc in time_cols if 2 <= data[tc].nunique() <= 20 and
                      all(not g.dropna().duplicated().any() for _, g in data.groupby(idc)[tc])]
            kind = "repeated_measures" if within else "clustered"
            ev = f"{idc} 有 {len(per_id)} 個不同的值，每個值出現 {per_id.min()}–{per_id.max()} 列（中位數 {E.r_str(float(per_id.median()))}）"
            if within:
                ev += f"；{'/'.join(within)} 在每個 {idc} 內不重複，像是時間或情境"
            hints.append({"type": kind, "columns": [idc] + within, "format": "long", "evidence": ev,
                          "question": (f"同一個 {idc} 是否被測量了多次（每次一列）？{'/'.join(within)} 是時間或情境嗎？" if within
                                       else f"{idc} 是否代表群組（例如學校、家庭），同群組內的觀察可能彼此相關？"),
                          "suggested": {"id": idc, "time": within[0] if within else None}, "book_ref": "§9.1, §10.1"})
    long_format = any(h["format"] == "long" for h in hints)
    if not long_format:
        seen = set()
        stems = {c: re.sub(r"[_.]?(t|time|wave)?[0-9]+$", "", c, flags=re.I) for c in names}
        numbered = [c for c in names if re.search(r"[0-9]+$", c) and stems[c]]
        for stem in dict.fromkeys(stems[c] for c in numbered):
            cols = [c for c in numbered if stems[c] == stem]
            if len(cols) < 2 or len({types[c] for c in cols}) != 1 or types[cols[0]] in ("id", "empty"):
                continue
            seen.add("|".join(sorted(cols)))
            hints.append({"type": "repeated_wide", "columns": cols, "format": "wide",
                          "evidence": f"{'、'.join(cols)} 欄名相同、只差編號，型態都是 {types[cols[0]]}，像是同一件事的重複測量",
                          "question": f"{'、'.join(cols)} 是不是同一個人在不同時間（或情境）的測量？若是，會轉成長格式，每人 {len(cols)} 列。",
                          "suggested": {"reshape_cols": cols}, "book_ref": "§9.1"})
        cand = [c for c in names if types[c] in CAT_TYPES and len(c) >= 3]
        for i, a in enumerate(cand):
            for b in cand[i + 1:]:
                if len(a) != len(b) or a[1:] != b[1:] or _level_set(data[a]) != _level_set(data[b]):
                    continue
                key = "|".join(sorted([a, b]))
                if key in seen:
                    continue
                seen.add(key)
                hints.append({"type": "possible_matched_pairs_wide", "columns": [a, b], "format": "wide",
                              "evidence": f"{a} 和 {b} 的欄名只差第一個字母，類別也完全相同（{'/'.join(_level_set(data[a]))}）",
                              "question": f"{a} 和 {b} 是不是同一個人對兩個相似問題（或兩個時間）的回答？",
                              "suggested": {"y1": a, "y2": b}, "book_ref": "§8.1"})
        cat_cols = [c for c in names if types[c] in CAT_TYPES]
        sets = {c: _level_set(data[c]) for c in cat_cols}
        for c in cat_cols:
            same = [o for o in cat_cols if sets[o] == sets[c]]
            key = "|".join(sorted(same))
            if len(same) < 2 or key in seen:
                continue
            named = sum(bool(PAIR_PAT.search(s)) for s in same) >= 2
            text_scale = len(sets[c]) >= 3 and not pd.api.types.is_numeric_dtype(data[same[0]])
            if not named and not text_scale:
                continue
            seen.add(key)
            hints.append({"type": "possible_matched_pairs_wide", "columns": same, "format": "wide",
                          "evidence": f"{'、'.join(same)} 的類別完全相同（{'/'.join(sets[c])}）" + ("，且欄名像前後測或重複測量" if named else ""),
                          "question": f"{'、'.join(same)} 是不是同一個人在不同時間或不同題目的回答（配對資料）？還是只是剛好用相同選項的不同變數？",
                          "suggested": {"y1": same[0], "y2": same[1]} if len(same) == 2 else {"reshape_cols": same},
                          "book_ref": "§8.1"})
    freq = [c for c in names if types[c] == "frequency_weight"]
    if freq:
        hints.append({"type": "aggregated_counts", "columns": freq, "format": "aggregated",
                      "evidence": f"{'、'.join(freq)} 看起來是次數欄，每一列可能代表一個格子而不是一個人",
                      "question": f"{'、'.join(freq)} 是否代表「這種組合有幾個人」？本 Skill 需要一人（或一人一次）一列的資料。",
                      "book_ref": "§8.2.3"})
    return {"n_rows": len(data), "hints": hints,
            "default": "no_correlation_detected" if not hints else "needs_confirmation",
            "note": "資料本身無法證明哪些列屬於同一個人或同一群（§1.1.3）。沒有偵測到線索不代表資料獨立；偵測到線索也要使用者確認。"}


def cc_profile(data):
    vars_ = [profile_variable(data[c], c) for c in data.columns]
    return {"n_rows": len(data), "n_cols": data.shape[1], "variables": vars_, "structure": detect_structure(data, vars_)}


TYPE_LABEL = {"binary": "二元", "nominal": "名目", "ordinal_candidate": "可能有序（請確認順序）",
              "ordinal_or_nominal_code": "數字代碼（有序或名目？）", "continuous": "連續數值", "count_or_continuous": "計數或連續",
              "frequency_weight": "次數欄？", "id": "識別碼", "nominal_many_levels": "名目（類別很多）", "empty": "全部缺失"}


def overview_md(profile, file_name):
    rows = []
    for v in profile["variables"]:
        if v["levels"] is not None and len(v["levels"]) <= 8:
            lv = "、".join(f"{k}（{c}）" for k, c in v["levels"].items())
        elif v["range"] is not None:
            lv = f"範圍 {v['range'][0]}–{v['range'][1]}，{v['n_unique']} 種值"
        else:
            lv = f"{v['n_unique']} 種值，例如 {'、'.join(v['examples'])}"
        rows.append(f"| {v['name']} | {TYPE_LABEL.get(v['type_guess'], v['type_guess'])}{' ❓' if v['needs_confirmation'] else ''} | {v['n_missing']} | {lv} |")
    hints = profile["structure"]["hints"]
    hint_md = []
    for i, h in enumerate(hints, 1):
        hint_md += [f"{i}. **{h['type']}**：{h['evidence']}（Agresti {h['book_ref']}）", f"   - 要問使用者：{h['question']}"]
    if not hints:
        hint_md = ["- 沒有偵測到明顯的線索。**這不代表資料彼此獨立**，仍要請使用者說明每一列的關係。"]
    return ([f"# 資料總覽：{file_name}", "", f"共 {profile['n_rows']} 列、{profile['n_cols']} 欄。", "",
             "## 變數", "", "❓ = 型態需要使用者確認。", "", "| 變數 | 型態猜測 | 缺失 | 類別與次數 |", "|---|---|---|---|"]
            + rows + ["", "## 資料可能不獨立的線索", ""] + hint_md + ["", f"> {profile['structure']['note']}"])


# ----------------------------------------------------------------------------- stage 3: describe

def cc_describe(data, q, out_dir):
    mode = q.get("mode") or ("paired" if q.get("y1") else "model")
    plots = []
    if mode == "paired":
        lv = q.get("levels")
        if isinstance(lv, dict):
            lv = lv.get(q["y1"])
        prep = E._prepare_paired(data, q["y1"], q["y2"], lv)
        tab, levels = prep["tab"], prep["levels"]
        k, n = len(levels), int(tab.sum())
        check = {"mode": "paired", "y1": q["y1"], "y2": q["y2"], "n_pairs": n, "n_dropped": len(data) - n,
                 "missing_share": (len(data) - n) / len(data), "categories": levels, "n_categories": k,
                 "same_categories": not any(w["code"] == "NOT_SQUARE" for w in prep["warnings"]),
                 "diagonal_share": float(np.trace(tab) / n), "warnings": prep["warnings"]}
        facts = prep["facts"] + [f"兩次回答相同（對角線）的有 {int(np.trace(tab))} 人（{E.fmt_pct(np.trace(tab) / n)}）。"]
        if k == 2:
            success = str(q.get("success") or levels[0])
            o = [levels.index(success), 1 - levels.index(success)]
            t2 = tab[np.ix_(o, o)]
            check.update(n12=int(t2[0, 1]), n21=int(t2[1, 0]), n_discordant=int(t2[0, 1] + t2[1, 0]))
            facts.append(f"回答改變的人：n12 = {check['n12']}、n21 = {check['n21']}，共 {check['n_discordant']} 人（McNemar 的常態近似需要 > 10，§8.1.1）。")
        else:
            d = E._qs_data(tab, levels)
            empty = d[d.nij + d.nji == 0]
            check["empty_pairs"] = [f"{a}↔{b}" for a, b in zip(empty.i, empty.j)]
            check["off_diagonal_min"] = int((d.nij + d.nji).min())
            if len(empty):
                facts.append(f"這些類別之間沒有人改變：{'、'.join(check['empty_pairs'])}。")
        sq = E._square(tab, levels, q["y1"], q["y2"])
        tables = {"counts": sq, "marginal": E._marginal_table(tab, levels, q["y1"], q["y2"])}
        plot_square(sq, os.path.join(out_dir, "square_table.png")); plots.append("square_table.png")
        plot_marginals(sq, os.path.join(out_dir, "marginals.png")); plots.append("marginals.png")
        return check, facts, tables, plots
    x = list(q.get("x") or [])
    vars_ = list(dict.fromkeys(([q["time"]] if q.get("time") else []) + x))
    prep = E._prepare_long(data, q["id"], q["y"], vars_, "both")
    d = prep["data"]
    yv = E.as_chr(d[q["y"]])
    lv = q.get("levels")
    if isinstance(lv, dict):
        lv = lv.get(q["y"])
    lv = [str(l) for l in lv] if lv is not None else E.code_order(d[q["y"]].tolist())
    cnt = pd.Series(yv).value_counts()
    d["._id"] = d[q["id"]]
    check = {"mode": "model", "id": q["id"], "y": q["y"], "time": q.get("time"), "x": x, "n_obs": len(d),
             "n_dropped": len(data) - len(d), "missing_share": (len(data) - len(d)) / len(data), "clusters": prep["clusters"],
             "response_categories": {l: int(cnt.get(l, 0)) for l in lv}, "n_response_categories": len(lv),
             "all_same_share": E._all_same_share(d, "._id", q["y"]),
             "cluster_level": {v: E._cluster_level(d, "._id", v) for v in vars_}, "warnings": prep["warnings"]}
    facts = prep["facts"] + [f"結果變數 {q['y']} 的次數：" + "、".join(f"{l} {int(cnt.get(l, 0))}" for l in lv) + "。"]
    if not math.isnan(check["all_same_share"]):
        facts.append(f"有 {E.fmt_pct(check['all_same_share'])} 的叢集（≥ 2 筆）所有回答都相同。")
    if vars_:
        facts.append("；".join(f"{v} 是{'叢集間（同一個叢集內不變）' if check['cluster_level'][v] == 'between' else '叢集內（同一個叢集內會變）'}變數" for v in vars_) + "。")
    tables = {}
    if len(lv) == 2:
        success = str(q["success"]) if q.get("success") is not None else E.default_success(d[q["y"]].tolist())
        d["._y"] = [1 if v == success else 0 for v in yv]
        check["success"] = success
        check["smaller_outcome_count"] = int(min(d["._y"].sum(), (1 - d["._y"]).sum()))
        if q.get("time"):
            dd, _ = E._build_predictors(d, [q["time"]], q.get("numeric") or [], q.get("ref") or {})
            tables["proportions"] = E._time_proportions(dd, q["time"])
            if plot_time_proportion(tables["proportions"], os.path.join(out_dir, "proportions.png"), success):
                plots.append("proportions.png")
            grp = [v for v in x if not pd.api.types.is_numeric_dtype(d[v]) and d[v].nunique() <= 6 and check["cluster_level"][v] == "between"]
            if grp:
                g = grp[0]
                rows = []
                for tv in tables["proportions"].time:
                    for gv in E.code_order(d[g].tolist()):
                        m = (pd.Series(E.as_chr(d[q["time"]])).values == tv) & (pd.Series(E.as_chr(d[g])).values == gv)
                        if m.any():
                            rows.append({"time": tv, "group": gv, "n": int(m.sum()), "proportion": float(d["._y"].values[m].mean())})
                tables["proportions_by_group"] = pd.DataFrame(rows)
                plot_group_time(tables["proportions_by_group"], g, os.path.join(out_dir, "proportions_by_group.png"), success)
                plots.append("proportions_by_group.png")
        if vars_:
            dd, _ = E._build_predictors(d, vars_, q.get("numeric") or [], q.get("ref") or {})
            X, _, _ = E._model_matrix(dd, vars_)
            sep = E._check_separation(X, d["._y"].values.astype(float))
            check["separation"] = bool(sep)
            check["warnings"] = check["warnings"] + sep
    else:
        d["._y"] = [lv.index(v) + 1 for v in yv]
        tables["distribution"] = E._time_distribution(d, q.get("time"), lv)
        plot_time_distribution(tables["distribution"], lv, os.path.join(out_dir, "distribution.png")); plots.append("distribution.png")
    return check, facts, tables, plots


def describe_md(check, facts, tables, plots, file_name, question):
    lines = [f"# 初步檢視：{file_name}", ""]
    if question:
        lines += [f"問題：{question}", ""]
    lines += ["## 重點數字", ""] + [f"- {f}" for f in facts] + [""]
    if check["warnings"]:
        lines += ["## 需要注意", ""] + [f"- **{w['code']}**：{w['message']}（Agresti {w['book_ref']}）" for w in check["warnings"]] + [""]
    lines += ["## 表", ""]
    for nm, t in tables.items():
        lines += [f"### {nm}", ""] + (square_md(t) if isinstance(t, dict) else md_table(t)) + [""]
    lines += ["## 圖", ""] + [f"![]({p})" for p in plots]
    return lines
