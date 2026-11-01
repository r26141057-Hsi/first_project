# Python version of the categorical-correlated engine (mode 2: no R available).
#
# Ported line by line from R/ (utils.R, structure.R, paired.R, models.R) so that result.json,
# facts and warnings are the same; dev/test_python.py compares both versions item by item.
# GLMM (glmm_binary, compare_gee_glmm) is R only: statsmodels has no adaptive Gauss-Hermite ML fit.
#
# Needs: numpy, pandas, scipy, statsmodels.

import json
import math
import re

import numpy as np
import pandas as pd
import scipy.stats as st
import statsmodels.api as sm
from scipy.optimize import minimize
from scipy.special import expit


class CCError(Exception):
    """An error message meant for the user (written to result.json as {"error": ...})."""


# ----------------------------------------------------------------------------- utils

def cc_warning(code, message, book_ref):
    return {"code": code, "message": message, "book_ref": book_ref}


def cc_result(method, method_label, book_ref, tier, estimates=None, tests=None, tables=None,
              warnings=None, facts=None, notes=None):
    return {"method": method, "method_label": method_label, "book_ref": book_ref, "tier": tier,
            "estimates": estimates if estimates is not None else pd.DataFrame(),
            "tests": tests if tests is not None else _tests_frame([]),
            "tables": tables or {}, "warnings": warnings or [], "facts": [f for f in (facts or []) if f],
            "notes": notes or {}}


def fmt_num(x, digits=3):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "NA"
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    return f"{x:.{digits}f}"


def fmt_p(p):
    """Used as "P %s" -> "P = 0.012" or "P < 0.001" (same as R)."""
    if p is None or (isinstance(p, float) and math.isnan(p)):
        return "= NA"
    if p < 0.001:
        return "< 0.001"
    return f"= {p:.3f}"


def fmt_pct(x, accuracy=0.1):
    digits = max(0, -int(round(math.log10(accuracy))))
    return f"{x * 100:.{digits}f}%"


def r_str(v):
    """as.character() of a value: whole numbers without '.0' (R prints 1, not 1.0)."""
    if isinstance(v, (bool, np.bool_)):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        if float(v).is_integer():
            return str(int(v))
        return repr(float(v))
    return str(v)


def code_order(values):
    """Category order of code_order_factor: numbers numerically, text in code-point order."""
    vals = [v for v in values if not _isna(v)]
    uniq = list(dict.fromkeys(vals))
    if all(isinstance(v, (int, float, np.integer, np.floating)) and not isinstance(v, bool) for v in uniq):
        return [r_str(v) for v in sorted(uniq)]
    return sorted({r_str(v) for v in uniq})


def _isna(v):
    try:
        return v is None or (isinstance(v, float) and math.isnan(v)) or pd.isna(v)
    except (TypeError, ValueError):
        return False


def as_chr(series):
    return [None if _isna(v) else r_str(v) for v in series]


def read_data(path):
    """Textbook .dat, Excel, UTF-8 or Big5 CSV; delimiter = most frequent of , ; tab in the header."""
    low = path.lower()
    if low.endswith(".dat"):
        return pd.read_csv(path, sep=r"\s+")
    if low.endswith(".xlsx") or low.endswith(".xls"):
        return pd.read_excel(path)
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
        encoding = "utf-8-sig"
    except UnicodeDecodeError:
        text = raw.decode("big5", errors="replace")
        encoding = "big5"
    header = text.splitlines()[0] if text else ""
    counts = {s: header.count(s) for s in [",", ";", "\t"]}
    sep = max(counts, key=counts.get)
    return pd.read_csv(path, sep=sep, encoding=encoding)


def cc_recode(data, recode):
    """Same rules as R cc_recode: breaks (each break starts a new category) or map."""
    data = data.copy()
    notes = []
    for nm, r in recode.items():
        src_name = r.get("from")
        if src_name is None or src_name not in data.columns:
            raise CCError(f"recode：找不到來源欄位 {src_name}")
        src = data[src_name]
        if r.get("breaks") is not None:
            br = sorted(float(b) for b in np.atleast_1d(r["breaks"]))
            labs = [str(l) for l in np.atleast_1d(r["labels"])]
            if len(labs) != len(br) + 1:
                raise CCError(f"recode：{nm} 的 labels 數目必須比 breaks 多 1。")
            x = pd.to_numeric(src, errors="coerce")
            idx = np.searchsorted(br, x.values, side="right")
            data[nm] = [None if _isna(v) else labs[i] for v, i in zip(x.values, idx)]
            ranges = [f"< {r_str(br[0])}"] + [f"{r_str(a)} – < {r_str(b)}" for a, b in zip(br[:-1], br[1:])] + \
                     [f"≥ {r_str(br[-1])}"]
            notes += [f"新變數 {nm} 由 {src_name} 轉換：" + "；".join(f"{a} → {b}" for a, b in zip(ranges, labs)) + "。",
                      f"提醒：把連續的 {src_name} 切成類別會損失資訊，結論可能隨切點改變。"]
        elif r.get("map") is not None:
            mp = {str(k): str(v) for k, v in r["map"].items()}
            vals = as_chr(src)
            unmapped = [v for v in dict.fromkeys(vals) if v is not None and v not in mp]
            if unmapped:
                raise CCError(f"recode：{nm} 的 map 缺少這些原始值：" + ", ".join(unmapped))
            data[nm] = [None if v is None else mp[v] for v in vals]
            notes.append(f"新變數 {nm} 由 {src_name} 合併類別：" + "；".join(f"{k} → {v}" for k, v in mp.items()) + "。")
        else:
            raise CCError(f"recode：{nm} 需要 breaks（切點）或 map（類別對應）。")
    return data, notes


def joint_wald(coefs, vc, idx):
    b = coefs[idx]
    V = vc[np.ix_(idx, idx)]
    stat = float(b @ np.linalg.solve(V, b))
    return stat, len(idx), float(st.chi2.sf(stat, len(idx)))


def _tests_frame(rows):
    return pd.DataFrame(rows, columns=["test", "statistic", "df", "p_value", "book_ref"])


# ----------------------------------------------------------------------------- structure

def cc_reshape_long(data, cols, id=None, value="y", time="time", time_values=None):
    missing = [c for c in cols if c not in data.columns]
    if missing:
        raise CCError("reshape：找不到欄位 " + ", ".join(missing))
    if len(cols) < 2:
        raise CCError("reshape：至少要 2 個重複測量的欄位。")
    time_values = list(time_values) if time_values is not None else list(range(1, len(cols) + 1))
    if len(time_values) != len(cols):
        raise CCError("reshape：time_values 的個數必須和欄位個數相同。")
    notes = []
    data = data.copy()
    if id is None:
        id = "id"
        if id in data.columns:
            raise CCError("reshape：資料已有 id 欄，請在 spec 指定 id。")
        data[id] = np.arange(1, len(data) + 1)
        notes.append(f"資料沒有 id 欄，依列號產生 id（1–{len(data)}），每一列視為一個叢集。")
    other = [c for c in data.columns if c not in cols]
    pieces = []
    for k, c in enumerate(cols):
        piece = data[other].copy()
        piece[time] = time_values[k]
        piece[value] = data[c].values
        piece["._order"] = k
        pieces.append(piece)
    long = pd.concat(pieces, ignore_index=True)
    long = long.sort_values([id, "._order"], kind="stable").drop(columns="._order").reset_index(drop=True)
    notes.append(f"把 {'、'.join(cols)} 轉成長格式：{value} 欄為測量值，{time} 欄為時間（"
                 + "、".join(f"{r_str(t)} = {c}" for t, c in zip(time_values, cols)) + f"），共 {len(long)} 列。")
    return long, notes, id


def _prepare_long(data, id, y, vars, method_family="gee"):
    cols = list(dict.fromkeys([id, y] + list(vars)))
    missing = [c for c in cols if c not in data.columns]
    if missing:
        raise CCError(f"資料中找不到欄位：{', '.join(missing)}。現有欄位：{', '.join(map(str, data.columns))}")
    if data[id].isna().any():
        raise CCError("id 欄有缺失值，無法判斷叢集。")
    complete = data[cols].notna().all(axis=1)
    facts, warnings = [], []
    n_all = len(data)
    if (~complete).any():
        n_drop = int((~complete).sum())
        share = n_drop / n_all
        facts.append(f"因 {'/'.join([c for c in cols if c != id])} 有缺失，排除 {n_drop} 筆觀察值（占 {fmt_pct(share)}）；其他時間點的資料仍保留。")
        mech = {"gee": "GEE 需要缺失完全隨機（MCAR：缺不缺和任何變數都無關）才不會有偏誤。",
                "glmm": "GLMM 只需要隨機缺失（MAR：缺不缺只和已觀察到的資料有關）。",
                "both": "GEE 需要缺失完全隨機（MCAR），GLMM 只需要隨機缺失（MAR），所以缺失可能讓兩者的差異變大。"}[method_family]
        if share >= 0.2:
            warnings.append(cc_warning("MISSING_HIGH",
                f"缺失比例 {fmt_pct(share)}（≥ 20%），結果可能高度受缺失影響。{mech}光看比例無法判斷是哪一種，請說明資料為什麼缺失。", "§9.5.1"))
        elif share >= 0.05:
            warnings.append(cc_warning("MISSING_DROPPED", f"缺失比例 {fmt_pct(share)}（≥ 5%），可能影響結果。{mech}", "§9.5.1"))
    d = data.loc[complete].copy()
    d = d.sort_values(id, kind="stable")
    sizes = d.groupby(id, sort=True).size()
    n_clusters = len(sizes)
    size_dist = sizes.value_counts().sort_index()
    facts.append(f"共 {n_clusters} 個叢集、{len(d)} 筆觀察值；每個叢集的筆數："
                 + "、".join(f"{int(k)} 筆 {int(v)} 個" for k, v in size_dist.items()) + "。")
    n_single = int((sizes == 1).sum())
    if n_single > 0:
        warnings.append(cc_warning("SINGLETON_CLUSTERS",
            f"有 {n_single} 個叢集只有 1 筆資料（占 {fmt_pct(n_single / n_clusters)}）：它們對叢集內的效果（例如時間）沒有資訊。", "§9.2"))
    if n_clusters < 2:
        raise CCError("至少要有 2 個叢集。")
    return {"data": d, "facts": facts, "warnings": warnings,
            "clusters": {"n_clusters": n_clusters, "n_obs": len(d),
                         "sizes": {str(int(k)): int(v) for k, v in size_dist.items()}, "n_singleton": n_single}}


def _all_same_share(d, id, y):
    multi = [g for _, g in d.groupby(id)[y] if len(g) >= 2]
    if not multi:
        return float("nan")
    return float(np.mean([len(set(as_chr(g))) == 1 for g in multi]))


def _cluster_level(d, id, v):
    varies = d.groupby(id)[v].apply(lambda z: len(set(as_chr(z))) > 1)
    return "within" if varies.any() else "between"


def _build_predictors(d, vars, numeric=(), ref=None):
    ref = ref or {}
    info = {}
    d = d.copy()
    for v in vars:
        if v in numeric:
            x = pd.to_numeric(d[v], errors="coerce")
            if x[d[v].notna()].isna().any():
                raise CCError(f"{v} 被設定為數值分數，但有非數字的值。")
            d[v] = x.astype(float)
            info[v] = {"type": "numeric"}
        else:
            lv = code_order(d[v].tolist())
            r = str(ref[v]) if v in ref else lv[0]
            if r not in lv:
                raise CCError(f"{v} 的參考組「{r}」不在資料中；現有類別：{', '.join(lv)}")
            lv = [r] + [l for l in lv if l != r]
            if len(lv) < 2:
                raise CCError(f"{v} 只有 1 個類別，不能當解釋變數。")
            d[v] = pd.Categorical(as_chr(d[v]), categories=lv)
            info[v] = {"type": "factor", "ref": r, "levels": lv}
    return d, info


def _model_matrix(d, terms, intercept=True):
    """model.matrix(~ terms) with treatment contrasts and R's column names and order.
    Returns (X, column names, term of each column)."""
    blocks = {}
    for t in terms:
        if ":" in t:
            continue
        if isinstance(d[t].dtype, pd.CategoricalDtype):
            lv = list(d[t].cat.categories)
            blocks[t] = [(f"{t}{l}", (d[t].astype(str) == l).astype(float).values) for l in lv[1:]]
        else:
            blocks[t] = [(t, d[t].astype(float).values)]
    cols, names, owner = [], [], []
    if intercept:
        cols.append(np.ones(len(d))); names.append("(Intercept)"); owner.append(None)
    for t in [t for t in terms if ":" not in t]:
        for nm, c in blocks[t]:
            cols.append(c); names.append(nm); owner.append(t)
    for t in [t for t in terms if ":" in t]:
        parts = t.split(":")
        combos = [("", np.ones(len(d)))]
        for p in parts:                                    # first factor varies fastest (as R)
            combos = [(f"{a}:{nm}" if a else nm, ca * c) for nm, c in blocks[p] for a, ca in combos]
        for nm, c in combos:
            cols.append(c); names.append(nm); owner.append(t)
    X = np.column_stack(cols) if cols else np.zeros((len(d), 0))
    return X, names, owner


def _term_index(coef_names, owner_of, terms, nominal=False):
    """Coefficients of each term; a main effect inside an interaction is tested with it (as R)."""
    base = [re.sub(r":[0-9]+$", "", n) if nominal else n for n in coef_names]
    own = {t: [i for i, b in enumerate(base) if owner_of.get(b) == t] for t in terms}
    out = {}
    for t in terms:
        if ":" not in t:
            inter = [s for s in terms if ":" in s and t in s.split(":")]
            if inter:
                out[f"{t} (with {', '.join(inter)})"] = sorted(set(own[t] + sum((own[s] for s in inter), [])))
                continue
        out[t] = own[t]
    return out


# ----------------------------------------------------------------------------- paired (Ch.8)

def scoreci_mp(b, c, n, conf_level):
    """Line-by-line port of PropCIs::scoreci.mp (§8.1.2)."""
    pa = 2 * n
    z = st.norm.ppf(1 - (1 - conf_level) / 2)

    def bound(direction):
        proot = (c - b) / n
        dp = 1 - proot if direction > 0 else 1 + proot
        for _ in range(50):
            dp = 0.5 * dp
            p2 = proot + direction * dp
            pb = -b - c + (2 * n - c + b) * p2
            pc = -b * p2 * (1 - p2)
            q21 = (math.sqrt(pb ** 2 - 4 * pa * pc) - pb) / (2 * pa)
            score = (c - b - n * p2) / math.sqrt(n * (2 * q21 + p2 * (1 - p2)))
            if abs(score) < z:
                proot = p2
            if dp < 1e-7 or abs(z - score) < 1e-6:
                return p2
        raise CCError("score 信賴區間沒有收斂。")

    ul = 1.0 if c == n else bound(+1)
    ll = -1.0 if b == n else bound(-1)
    return ll, ul


def generalized_cmh(x, y, strata):
    """Generalized CMH general-association statistic, as R mantelhaen.test for an I x J x K table."""
    xs, ys = sorted(set(x)), sorted(set(y))
    I, J = len(xs), len(ys)
    s = np.zeros((I - 1) * (J - 1))
    V = np.zeros((len(s), len(s)))
    df = pd.DataFrame({"x": x, "y": y, "k": strata})
    for _, g in df.groupby("k"):
        t = pd.crosstab(pd.Categorical(g.x, xs), pd.Categorical(g.y, ys), dropna=False).values.astype(float)
        nk = t.sum()
        if nk < 2:
            continue
        rs, cs = t.sum(1), t.sum(0)
        s += t[:-1, :-1].flatten() - np.outer(rs[:-1], cs[:-1]).flatten() / nk
        Vr = np.diag(rs[:-1]) - np.outer(rs[:-1], rs[:-1]) / nk
        Vc = np.diag(cs[:-1]) - np.outer(cs[:-1], cs[:-1]) / nk
        V += np.kron(Vr, Vc) / (nk - 1)
    stat = float(s @ np.linalg.solve(V, s))
    dfree = (I - 1) * (J - 1)
    return stat, dfree, float(st.chi2.sf(stat, dfree))


def _prepare_paired(data, y1, y2, levels=None):
    for v in (y1, y2):
        if v not in data.columns:
            raise CCError(f"資料中找不到欄位：{v}。現有欄位：{', '.join(map(str, data.columns))}")
    facts, warnings = [], []
    complete = data[y1].notna() & data[y2].notna()
    if (~complete).any():
        n_drop = int((~complete).sum()); share = n_drop / len(data)
        facts.append(f"{y1} 或 {y2} 有缺失，排除 {n_drop} 人（占 {fmt_pct(share)}）；配對比較只用兩次都有回答的人。")
        if share >= 0.2:
            warnings.append(cc_warning("MISSING_HIGH", f"缺失比例 {fmt_pct(share)}（≥ 20%），結果可能高度受缺失影響；請說明為什麼有人只有一次的回答。", "§9.5.1"))
        elif share >= 0.05:
            warnings.append(cc_warning("MISSING_DROPPED", f"缺失比例 {fmt_pct(share)}（≥ 5%），可能影響結果；只有一次回答的人被排除，若他們和其他人不同，結論可能偏誤。", "§9.5.1"))
    d = data.loc[complete]
    v1, v2 = as_chr(d[y1]), as_chr(d[y2])
    if levels is not None:
        levels = [str(l) for l in np.atleast_1d(levels)]
        bad = [v for v in dict.fromkeys(v1 + v2) if v not in levels]
        if bad:
            raise CCError(f"{y1}／{y2} 有不在 levels 中的值：{', '.join(bad)}")
    else:
        levels = code_order(d[y1].tolist() + d[y2].tolist())
        only1 = [v for v in dict.fromkeys(v1) if v not in set(v2)]
        only2 = [v for v in dict.fromkeys(v2) if v not in set(v1)]
        if only1 or only2:
            warnings.append(cc_warning("NOT_SQUARE",
                f"兩欄的類別不完全相同（只出現在 {y1}：{', '.join(only1) if only1 else '無'}；只出現在 {y2}：{', '.join(only2) if only2 else '無'}）。"
                "配對比較需要兩次用同一組類別，請確認兩欄是同一個量表；若只是某類剛好沒人選，可以繼續。", "§8.3"))
    k = len(levels)
    pos = {l: i for i, l in enumerate(levels)}
    tab = np.zeros((k, k), dtype=int)
    for a, b in zip(v1, v2):
        tab[pos[a], pos[b]] += 1
    facts.append(f"共 {int(tab.sum())} 人，每人兩次測量（{y1}、{y2}），類別：{'、'.join(levels)}。")
    return {"tab": tab, "levels": levels, "v1": v1, "v2": v2, "facts": facts, "warnings": warnings}


def _square(tab, levels, y1, y2):
    return {"rows": list(levels), "cols": list(levels), "values": [list(map(int, r)) for r in tab], "dimnames": [y1, y2]}


def _marginal_table(tab, levels, y1, y2):
    n = tab.sum()
    return pd.DataFrame({"category": levels, f"{y1}_count": tab.sum(1).astype(int), f"{y1}_prop": tab.sum(1) / n,
                         f"{y2}_count": tab.sum(0).astype(int), f"{y2}_prop": tab.sum(0) / n})


def _qs_data(tab, levels, scores=None):
    k = tab.shape[0]
    scores = list(range(1, k + 1)) if scores is None else list(scores)
    rows = []
    for i in range(k):
        for j in range(i + 1, k):
            b = np.zeros(k); b[i] = 1; b[j] = -1
            rows.append(dict({f"b{m + 1}": b[m] for m in range(k)}, x=scores[j] - scores[i],
                             i=levels[i], j=levels[j], nij=float(tab[i, j]), nji=float(tab[j, i])))
    return pd.DataFrame(rows)


def _binom_glm(d, cols):
    """glm(nij/(nij+nji) ~ -1 + cols, binomial, weights = nij + nji) on pairs with data."""
    fd = d[d.nij + d.nji > 0]
    endog = np.column_stack([fd.nij.values, fd.nji.values])
    if not cols:                               # symmetry: p = 0.5 for every pair, no parameters
        m = fd.nij + fd.nji
        with np.errstate(divide="ignore", invalid="ignore"):
            dev = 2 * np.nansum(np.where(fd.nij > 0, fd.nij * np.log(fd.nij / (m / 2)), 0) +
                                np.where(fd.nji > 0, fd.nji * np.log(fd.nji / (m / 2)), 0))
        return {"deviance": float(dev), "df_resid": int(len(fd)), "params": {}, "bse": {}}
    X = fd[cols].values.astype(float)
    res = sm.GLM(endog, X, family=sm.families.Binomial()).fit()
    rank = np.linalg.matrix_rank(X)
    return {"deviance": float(res.deviance), "df_resid": int(len(fd) - rank),
            "params": dict(zip(cols, res.params)), "bse": dict(zip(cols, res.bse))}


def cc_paired_binary(data, y1, y2, success=None, levels=None, conf_level=0.95):
    prep = _prepare_paired(data, y1, y2, levels)
    tab, lv = prep["tab"], prep["levels"]
    warnings, facts = prep["warnings"], prep["facts"]
    if len(lv) != 2:
        raise CCError(f"二元配對需要剛好 2 個類別，現在有 {len(lv)} 個：{', '.join(lv)}。3 類以上請用 paired_nominal 或 paired_ordinal。")
    success = str(success) if success is not None else lv[0]
    if success not in lv:
        raise CCError(f"成功類別「{success}」不在資料中。")
    order = [lv.index(success), 1 - lv.index(success)]
    tab = tab[np.ix_(order, order)]
    lv = [lv[i] for i in order]
    n = int(tab.sum()); n12 = int(tab[0, 1]); n21 = int(tab[1, 0]); nstar = n12 + n21
    p1 = tab[0].sum() / n; p2 = tab[:, 0].sum() / n
    rows = []
    if nstar > 0:
        x2 = (n12 - n21) ** 2 / nstar
        rows.append({"test": "McNemar X2", "statistic": x2, "df": 1, "p_value": float(st.chi2.sf(x2, 1)), "book_ref": "§8.1.1"})
        rows.append({"test": "Exact binomial (n12 ~ Bin(n*, 0.5))", "statistic": n12, "df": None,
                     "p_value": float(st.binomtest(n12, nstar, 0.5).pvalue), "book_ref": "§8.1.1"})
    tests = _tests_frame(rows)
    primary = "McNemar X2" if nstar > 10 else "Exact binomial (n12 ~ Bin(n*, 0.5))"
    if nstar == 0:
        warnings.append(cc_warning("ZERO_DISCORDANT", "所有人兩次的回答都相同（n12 = n21 = 0），沒有任何改變，無法檢定也無法估計條件勝算比。", "§8.1.1"))
    elif nstar <= 10:
        warnings.append(cc_warning("FEW_DISCORDANT", f"回答改變的人只有 n12 + n21 = {nstar} 人（≤ 10），McNemar 的常態近似不可靠，以精確二項檢定為主。", "§8.1.1"))
    if nstar > 0 and (n12 == 0 or n21 == 0):
        warnings.append(cc_warning("ZERO_DISCORDANT",
            f"不一致的格子有 0（n12 = {n12}、n21 = {n21}），條件勝算比 n12/n21 為 {'∞' if n21 == 0 else '0'}，不加 0.5 校正。", "§8.2.4"))
    ci = scoreci_mp(n21, n12, n, conf_level) if nstar > 0 else (float("nan"), float("nan"))
    odds = lambda p: p / (1 - p)
    ratio = lambda a, b: float("inf") if b == 0 else a / b
    nan = float("nan")
    estimates = pd.DataFrame({
        "measure": [f"P({y1} = {success})", f"P({y2} = {success})",
                    f"Difference of proportions ({y1} - {y2})", f"Difference of proportions ({y2} - {y1})",
                    f"Marginal odds ratio {y1} vs {y2} (population-averaged)",
                    f"Marginal odds ratio {y2} vs {y1} (population-averaged)",
                    f"Conditional odds ratio n12/n21: {y1} vs {y2} (subject-specific)",
                    f"Conditional odds ratio n21/n12: {y2} vs {y1} (subject-specific)"],
        "estimate": [p1, p2, p1 - p2, p2 - p1, odds(p1) / odds(p2), odds(p2) / odds(p1), ratio(n12, n21), ratio(n21, n12)],
        "lower": [nan, nan, ci[0], -ci[1], nan, nan, nan, nan], "upper": [nan, nan, ci[1], -ci[0], nan, nan, nan, nan],
        "book_ref": ["§8.1", "§8.1", "§8.1.2", "§8.1.2", "§8.2.2", "§8.2.2", "§8.2.4", "§8.2.4"]})
    pt = tests[tests.test == primary]
    facts += [
        f"{y1} 選「{success}」的比例 {fmt_num(p1)}，{y2} 為 {fmt_num(p2)}，差 {fmt_num(p1 - p2)}（{round(conf_level * 100)}% score 信賴區間 {fmt_num(ci[0])} 到 {fmt_num(ci[1])}）。",
        f"回答改變的人：{y1} 是「{success}」但 {y2} 不是的有 n12 = {n12} 人，反過來的有 n21 = {n21} 人；兩次回答相同的 {n - nstar} 人不影響檢定。",
        f"主要檢定：{primary}，P {fmt_p(pt.p_value.iloc[0])}。" if len(pt) else None,
        f"McNemar X² = {fmt_num(tests.statistic.iloc[0], 2)}（df = 1），P {fmt_p(tests.p_value.iloc[0])}；精確二項檢定 P {fmt_p(tests.p_value.iloc[1])}。" if len(tests) else None,
        f"邊際勝算比（整體平均）：{y1} 對 {y2} = {fmt_num(odds(p1) / odds(p2))}，{y2} 對 {y1} = {fmt_num(odds(p2) / odds(p1))}。",
        f"條件勝算比（同一個人）：{y1} 對 {y2} = n12/n21 = {'∞' if n21 == 0 else fmt_num(n12 / n21)}，{y2} 對 {y1} = n21/n12 = {'∞' if n12 == 0 else fmt_num(n21 / n12)}。"]
    return cc_result("paired_binary", "McNemar test for binary matched pairs", "§8.1", "A",
                     estimates=estimates, tests=tests,
                     tables={"counts": _square(tab, lv, y1, y2), "marginal": _marginal_table(tab, lv, y1, y2)},
                     warnings=warnings, facts=facts,
                     notes={"primary_test": primary, "success": success, "n_discordant": nstar,
                            "reminder": "McNemar 只用到回答改變的人；條件勝算比是個體層次，邊際勝算比是整體層次，兩者不可混稱（§8.2.4）。"})


def cc_paired_nominal(data, y1, y2, levels=None, ordinal=(), conf_level=0.95):
    prep = _prepare_paired(data, y1, y2, levels)
    tab, lv = prep["tab"], prep["levels"]
    warnings, facts = prep["warnings"], prep["facts"]
    k = len(lv)
    if k < 3:
        raise CCError("只有 2 個類別，請改用 paired_binary（McNemar）。")
    if y1 in ordinal or y2 in ordinal:
        warnings.append(cc_warning("ORDINAL_IGNORED", "結果變數已確認是有序的，名目檢定（df = c − 1）沒有用到順序；有序方法（paired_ordinal，df = 1）通常檢定力較高。", "§8.4"))
    d = _qs_data(tab, lv)
    empty = d[d.nij + d.nji == 0]
    if len(empty):
        warnings.append(cc_warning("EMPTY_PAIR", "這些類別之間沒有任何人改變（兩個方向都是 0）："
                                   + "、".join(f"{a}↔{b}" for a, b in zip(empty.i, empty.j)) + "；這幾對不提供資訊。", "§8.3.4"))
    symm = _binom_glm(d, [])
    qs = _binom_glm(d, [f"b{m}" for m in range(1, k)])
    lr = symm["deviance"] - qs["deviance"]
    df = symm["df_resid"] - qs["df_resid"]
    rows = [{"test": "Marginal homogeneity: symmetry vs quasi-symmetry LR", "statistic": lr, "df": df,
             "p_value": float(st.chi2.sf(lr, df)), "book_ref": "§8.3.4"},
            {"test": "Symmetry model deviance (fit)", "statistic": symm["deviance"], "df": symm["df_resid"],
             "p_value": float(st.chi2.sf(symm["deviance"], symm["df_resid"])), "book_ref": "§8.3.4"},
            {"test": "Quasi-symmetry model deviance (fit)", "statistic": qs["deviance"], "df": qs["df_resid"],
             "p_value": float(st.chi2.sf(qs["deviance"], qs["df_resid"])) if qs["df_resid"] > 0 else None, "book_ref": "§8.3.4"}]
    n_people = len(prep["v1"])
    try:
        cmh = generalized_cmh(np.r_[np.ones(n_people), np.zeros(n_people)], prep["v1"] + prep["v2"],
                              np.r_[np.arange(n_people), np.arange(n_people)])
        rows.append({"test": "CMH (score test of marginal homogeneity)", "statistic": cmh[0], "df": cmh[1],
                     "p_value": cmh[2], "book_ref": "§8.3.3"})
    except Exception:
        cmh = None
    tests = _tests_frame(rows)
    n = tab.sum()
    follow = []
    for j in range(k):
        mask = np.arange(k) != j
        n12_ = tab[j, mask].sum(); n21_ = tab[mask, j].sum()
        nst = n12_ + n21_
        z = (n12_ - n21_) / math.sqrt(nst) if nst > 0 else float("nan")
        ci = scoreci_mp(n21_, n12_, n, conf_level) if nst > 0 else (float("nan"), float("nan"))
        follow.append({"category": lv[j], "prop_1": tab[j].sum() / n, "prop_2": tab[:, j].sum() / n,
                       "difference": (tab[j].sum() - tab[:, j].sum()) / n, "lower": ci[0], "upper": ci[1],
                       "n12": int(n12_), "n21": int(n21_), "z": z,
                       "p_value": float("nan") if math.isnan(z) else float(2 * st.norm.sf(abs(z)))})
    follow = pd.DataFrame(follow)
    resid = pd.DataFrame({"pair": [f"{a} → {b} vs {b} → {a}" for a, b in zip(d.i, d.j)], "n_ij": d.nij, "n_ji": d.nji,
                          "std_residual": [(a - b) / math.sqrt(a + b) if a + b > 0 else float("nan") for a, b in zip(d.nij, d.nji)]})
    big = resid[resid.std_residual.abs() > 2]
    facts += [
        f"邊際同質性檢定（對稱 vs 準對稱模型）：LR = {fmt_num(lr, 2)}（df = {df}），P {fmt_p(rows[0]['p_value'])}。",
        f"對照：CMH 檢定 = {fmt_num(cmh[0], 2)}（df = {cmh[1]}），P {fmt_p(cmh[2])}。" if cmh else None,
        f"各類別的比例（{y1} → {y2}）：" + "；".join(f"{c} {fmt_num(a)} → {fmt_num(b)}" for c, a, b in zip(follow.category, follow.prop_1, follow.prop_2)) + "。",
        f"各類別的比例差（{y1} − {y2}，{round(conf_level * 100)}% score 信賴區間）："
        + "；".join(f"{c} {fmt_num(a)}（{fmt_num(lo)} 到 {fmt_num(hi)}）" for c, a, lo, hi in zip(follow.category, follow.difference, follow.lower, follow.upper)) + "。",
        ("改變方向明顯不對稱的類別配對（|標準化殘差| > 2）：" + "；".join(f"{p}（{fmt_num(r, 2)}）" for p, r in zip(big.pair, big.std_residual)) + "。") if len(big) else None]
    return cc_result("paired_nominal", "Marginal homogeneity for nominal matched pairs", "§8.3", "A",
                     estimates=follow, tests=tests,
                     tables={"counts": _square(tab, lv, y1, y2), "marginal": _marginal_table(tab, lv, y1, y2), "symmetry_residuals": resid},
                     warnings=warnings, facts=facts,
                     notes={"reminder": "逐類別的追蹤檢定（estimates）沒有做多重比較校正，只用來描述哪些類別改變；整體結論以邊際同質性檢定為準（§8.3.2）。"})


# cumulative logit, logit P(Y <= j) = a_j + x'b (textbook / multgee sign), ML + cluster sandwich ------------

def _cum_parts(theta, y, X, K):
    a, b = theta[:K - 1], theta[K - 1:]
    eta = a[None, :] + (X @ b)[:, None]
    n = len(y)
    F = np.hstack([np.zeros((n, 1)), expit(eta), np.ones((n, 1))])
    f = np.hstack([np.zeros((n, 1)), expit(eta) * (1 - expit(eta)), np.zeros((n, 1))])
    idx = np.arange(n)
    return F, f, F[idx, y] - F[idx, y - 1]


def _cum_score_obs(theta, y, X, K):
    F, f, P = _cum_parts(theta, y, X, K)
    idx = np.arange(len(y))
    fu, fl = f[idx, y], f[idx, y - 1]
    S = np.zeros((len(y), K - 1 + X.shape[1]))
    for j in range(1, K):
        S[:, j - 1] = ((y == j) * fu - (y - 1 == j) * fl) / P
    S[:, K - 1:] = X * ((fu - fl) / P)[:, None]
    return S


def _cum_fit(y, X, K):
    cum = np.array([np.mean(y <= j) for j in range(1, K)])
    cum = np.clip(cum, 1e-6, 1 - 1e-6)
    a0 = np.maximum.accumulate(np.log(cum / (1 - cum)) + np.arange(K - 1) * 1e-6)
    start = np.concatenate([[a0[0]], np.log(np.maximum(np.diff(a0), 1e-6)), np.zeros(X.shape[1])])

    def to_theta(u):
        return np.concatenate([u[0] + np.concatenate([[0], np.cumsum(np.exp(u[1:K - 1]))]), u[K - 1:]])

    def jac(u):
        J = np.eye(len(u))
        J[:K - 1, 0] = 1
        for j in range(1, K - 1):
            J[j:K - 1, j] = np.exp(u[j])
        return J

    def nll(u):
        P = _cum_parts(to_theta(u), y, X, K)[2]
        return np.inf if np.any(P <= 0) else -np.sum(np.log(P))

    res = minimize(nll, start, jac=lambda u: -_cum_score_obs(to_theta(u), y, X, K).sum(0) @ jac(u),
                   method="BFGS", options={"gtol": 1e-9, "maxiter": 20000})
    return to_theta(res.x)


def _cum_expected_info(theta, X, K):
    n = X.shape[0]
    info = np.zeros((len(theta), len(theta)))
    for c in range(1, K + 1):
        yc = np.full(n, c)
        P = _cum_parts(theta, yc, X, K)[2]
        S = _cum_score_obs(theta, yc, X, K)
        info += (S * P[:, None]).T @ S
    return info


def _sandwich(score_obs, bread_info, groups):
    S = pd.DataFrame(score_obs).groupby(np.asarray(groups)).sum().values
    Binv = np.linalg.inv(bread_info)
    return Binv @ (S.T @ S) @ Binv


def ordinal_gee_independence(y, X, groups, K):
    """= multgee::ordLORgee(LORstr = "independence"): ML estimates, sandwich with expected information."""
    theta = _cum_fit(y, X, K)
    V = _sandwich(_cum_score_obs(theta, y, X, K), _cum_expected_info(theta, X, K), groups)
    return theta, V


def nominal_gee_independence(ycode, X, groups, K):
    """= multgee::nomLORgee(LORstr = "independence"): multinomial logit ML, cluster sandwich.
    ycode 1..K with K the baseline. Returns params ordered [const_1, x_1..., const_2, x_2, ...] and V."""
    yb = np.where(ycode == K, 0, ycode)          # MNLogit baseline = code 0
    mod = sm.MNLogit(yb, X)
    res = mod.fit(disp=False, method="newton", maxiter=500)
    p = np.asarray(res.params).flatten(order="F")
    V = _sandwich(mod.score_obs(p), -mod.hessian(p), groups)
    return p, V


def cc_paired_ordinal(data, y1, y2, levels, scores=None, conf_level=0.95):
    if levels is None:
        raise CCError("有序配對需要 levels（由低到高的類別順序），請和使用者確認後填入。")
    prep = _prepare_paired(data, y1, y2, levels)
    tab, lv = prep["tab"], prep["levels"]
    warnings, facts = prep["warnings"], prep["facts"]
    k = len(lv)
    if k < 3:
        raise CCError("只有 2 個類別，請改用 paired_binary（McNemar）。")
    scores = [float(s) for s in (scores if scores is not None else range(1, k + 1))]
    if len(scores) != k or any(b <= a for a, b in zip(scores, scores[1:])):
        raise CCError("scores 的個數要等於類別數，且必須遞增。")
    pos = {l: i + 1 for i, l in enumerate(lv)}
    n = len(prep["v1"])
    y = np.array([pos[v] for pair in zip(prep["v1"], prep["v2"]) for v in pair])
    X = np.tile([[1.0], [0.0]], (n, 1))
    groups = np.repeat(np.arange(n), 2)
    theta, V = ordinal_gee_independence(y, X, groups, k)
    beta = float(theta[k - 1]); se = float(math.sqrt(V[k - 1, k - 1])); z = st.norm.ppf(1 - (1 - conf_level) / 2)
    pval = float(2 * st.norm.sf(abs(beta / se)))
    rows = [{"test": "Cumulative logit marginal model (GEE), Wald z^2", "statistic": (beta / se) ** 2, "df": 1,
             "p_value": pval, "book_ref": "§8.4.2"}]
    d = _qs_data(tab, lv, scores)
    symm = _binom_glm(d, [])
    oqs = _binom_glm(d, ["x"])
    lr = symm["deviance"] - oqs["deviance"]
    rows.append({"test": "Ordinal quasi-symmetry vs symmetry LR", "statistic": lr, "df": 1,
                 "p_value": float(st.chi2.sf(lr, 1)), "book_ref": "§8.4.3"})
    tests = _tests_frame(rows)
    sc = np.array(scores)
    mean1 = float((sc * tab.sum(1)).sum() / tab.sum()); mean2 = float((sc * tab.sum(0)).sum() / tab.sum())
    nan = float("nan")
    estimates = pd.DataFrame({
        "measure": ["beta: cumulative logit, first vs second (logit P(Y <= j))",
                    f"Odds ratio: {y1} in a higher category vs {y2}", f"Odds ratio: {y2} in a higher category vs {y1}",
                    "Ordinal quasi-symmetry beta", f"Mean score {y1}", f"Mean score {y2}"],
        "estimate": [beta, math.exp(-beta), math.exp(beta), oqs["params"]["x"], mean1, mean2],
        "se": [se, nan, nan, oqs["bse"]["x"], nan, nan],
        "lower": [beta - z * se, math.exp(-beta - z * se), math.exp(beta - z * se), nan, nan, nan],
        "upper": [beta + z * se, math.exp(-beta + z * se), math.exp(beta + z * se), nan, nan, nan],
        "book_ref": ["§8.4.1", "§8.4.1", "§8.4.1", "§8.4.3", "§8.4.3", "§8.4.3"]})
    n_all = int(tab.sum())
    up = int(np.triu(tab, 1).sum()); down = int(np.tril(tab, -1).sum()); same = int(np.trace(tab))
    changes = pd.DataFrame({"change": [f"{y2} higher than {y1}", f"{y2} lower than {y1}", "same"],
                            "n": [up, down, same], "proportion": [up / n_all, down / n_all, same / n_all]})
    direction = f"{y1} 傾向落在較低的類別（較接近「{lv[0]}」）" if beta > 0 else f"{y1} 傾向落在較高的類別（較接近「{lv[-1]}」）"
    facts += [
        f"累積 logit 邊際模型（GEE）：β̂ = {fmt_num(beta)}（robust SE {fmt_num(se)}），Wald z = {fmt_num(beta / se, 2)}，P {fmt_p(pval)}。",
        f"{y1} 落在較高類別的勝算是 {y2} 的 {fmt_num(math.exp(-beta))} 倍（{round(conf_level * 100)}% 信賴區間 {fmt_num(math.exp(-beta - z * se))} 到 {fmt_num(math.exp(-beta + z * se))}）；"
        f"反過來，{y2} 落在較高類別的勝算是 {y1} 的 {fmt_num(math.exp(beta))} 倍（{fmt_num(math.exp(beta - z * se))} 到 {fmt_num(math.exp(beta + z * se))}）。對每個切點都相同（比例勝算）。",
        f"方向：{direction}。",
        f"逐人比較：{y2} 比 {y1} 高的有 {up} 人（{fmt_pct(up / n_all)}），較低的 {down} 人（{fmt_pct(down / n_all)}），相同的 {same} 人（{fmt_pct(same / n_all)}）。",
        f"對照：有序準對稱模型 β̂ = {fmt_num(oqs['params']['x'])}，和對稱模型比較 LR = {fmt_num(lr, 2)}（df = 1），P {fmt_p(rows[1]['p_value'])}；"
        f"平均分數 {y1} = {fmt_num(mean1, 2)}、{y2} = {fmt_num(mean2, 2)}（分數 {', '.join(r_str(s) for s in scores)}）。"]
    return cc_result("paired_ordinal", "Cumulative logit marginal model for ordinal matched pairs", "§8.4", "A",
                     estimates=estimates, tests=tests,
                     tables={"counts": _square(tab, lv, y1, y2), "marginal": _marginal_table(tab, lv, y1, y2), "changes": changes},
                     warnings=warnings, facts=facts,
                     notes={"scores": scores, "levels": lv,
                            "reminder": "比例勝算：模型假設每個切點的效果相同（§8.4.1）。平均分數取決於分數設定，只用來幫助描述方向。"})


# ----------------------------------------------------------------------------- models (Ch.9)

def default_success(values):
    lv = code_order(values)
    hit = [l for l in lv if l.lower() in ("1", "yes", "y", "true", "pass", "success", "是", "有")]
    return hit[0] if hit else lv[min(1, len(lv) - 1)]


def default_baseline(lv):
    hit = [l for l in lv if l.lower() in ("other", "others", "其他")]
    return hit[0] if hit else lv[-1]


def _prepare_model(data, id, y, x=(), time=None, numeric=(), ref=None, interactions=(), response="binary",
                   success=None, levels=None, baseline=None, family="gee"):
    vars_ = list(dict.fromkeys(([time] if time else []) + list(x)))
    prep = _prepare_long(data, id, y, vars_, family)
    d = prep["data"]
    warnings, facts = prep["warnings"], prep["facts"]
    d, info = _build_predictors(d, vars_, numeric, ref)
    d["._id"] = pd.factorize(d[id])[0] + 1
    if time:
        # as R: numeric time → numeric order; otherwise the labels in character order
        if pd.api.types.is_numeric_dtype(d[time]) and not isinstance(d[time].dtype, pd.CategoricalDtype):
            tv = [r_str(v) for v in sorted(d[time].unique())]
        else:
            tv = sorted(set(as_chr(d[time].astype(object))))
        d["._wave"] = [tv.index(v) + 1 for v in as_chr(d[time].astype(object))]
    else:
        d["._wave"] = d.groupby("._id").cumcount() + 1
    if d.duplicated(["._id", "._wave"]).any():
        raise CCError("同一個叢集在同一個時間點有超過一筆資料；請確認 id 與 time 欄位。")
    d = d.sort_values(["._id", "._wave"], kind="stable").reset_index(drop=True)
    yv = as_chr(d[y])
    resp = {"type": response}
    if response == "binary":
        lv = code_order(d[y].tolist())
        if len(lv) != 2:
            raise CCError(f"二元模型的結果變數要剛好 2 類，{y} 有 {len(lv)} 類：{', '.join(lv)}。")
        success = str(success) if success is not None else default_success(d[y].tolist())
        if success not in lv:
            raise CCError(f"成功類別「{success}」不在 {y} 中。")
        d["._y"] = [1 if v == success else 0 for v in yv]
        resp["success"] = success
        resp["failure"] = [l for l in lv if l != success][0]
    else:
        lv = [str(l) for l in np.atleast_1d(levels)] if levels is not None else code_order(d[y].tolist())
        bad = [v for v in dict.fromkeys(yv) if v not in lv]
        if bad:
            raise CCError(f"{y} 有不在 levels 中的值：{', '.join(bad)}")
        if response == "ordinal" and levels is None:
            raise CCError("有序結果需要 levels（由低到高），請和使用者確認後填入。")
        if response == "nominal":
            baseline = str(baseline) if baseline is not None else default_baseline(lv)
            if baseline not in lv:
                raise CCError(f"基準類別「{baseline}」不在 {y} 中。")
            lv = [l for l in lv if l != baseline] + [baseline]
            resp["baseline"] = baseline
        if len(lv) < 3:
            raise CCError("只有 2 類，請改用二元模型。")
        d["._y"] = [lv.index(v) + 1 for v in yv]
        resp["levels"] = lv
    terms = vars_ + list(interactions)
    level_info = {v: _cluster_level(d, "._id", v) for v in vars_}
    if vars_:
        btw = [v for v in vars_ if level_info[v] == "between"]
        wtn = [v for v in vars_ if level_info[v] == "within"]
        facts.append(f"叢集間變數（同一個叢集內不變）：{'、'.join(btw) if btw else '無'}；叢集內變數（同一個叢集內會變）：{'、'.join(wtn) if wtn else '無'}。")
    return {"data": d, "terms": terms, "predictors": info, "response": resp, "warnings": warnings, "facts": facts,
            "clusters": prep["clusters"], "cluster_level": level_info, "y": y, "id": id}


def _is_number(s):
    try:
        float(s)
        return True
    except (TypeError, ValueError):
        return False


def _coef_table(names, est, se, conf_level, exp_sign=1):
    z = st.norm.ppf(1 - (1 - conf_level) / 2)
    est, se = np.asarray(est, float), np.asarray(se, float)
    lo, hi = exp_sign * (est - z * se), exp_sign * (est + z * se)
    return pd.DataFrame({"term": names, "estimate": est, "se": se, "z": est / se,
                         "p_value": 2 * st.norm.sf(np.abs(est / se)), "odds_ratio": np.exp(exp_sign * est),
                         "or_lower": np.exp(np.minimum(lo, hi)), "or_upper": np.exp(np.maximum(lo, hi)),
                         "or_reverse": np.exp(-exp_sign * est),
                         "or_reverse_lower": np.exp(-np.maximum(lo, hi)), "or_reverse_upper": np.exp(-np.minimum(lo, hi))})


def _term_tests(coefs, vc, idx, label, book_ref):
    rows = []
    for t, ix in idx.items():
        if not ix:
            continue
        s, df, p = joint_wald(coefs, vc, ix)
        rows.append({"test": f"{label}: {t}", "statistic": s, "df": df, "p_value": p, "book_ref": book_ref})
    return _tests_frame(rows)


def _check_separation(X, y):
    try:
        res = sm.GLM(y, X, family=sm.families.Binomial()).fit()
        mu = res.fittedvalues
        eps = 10 * np.finfo(float).eps
        if np.any(mu < eps) or np.any(mu > 1 - eps):
            raise ValueError
        return []
    except Exception:
        return [cc_warning("SEPARATION", "有解釋變數的某些值幾乎能完美區分成功與失敗（完全分離），對應的係數其實是無限大，係數、SE 與檢定沒有意義。", "§5.3")]


def _cluster_reminder(k):
    return f"GEE 的 robust SE 是大樣本方法，叢集少時傾向低估（§9.2.4）；本資料有 {k} 個叢集，課本沒有給門檻，請自行判斷是否足夠。"


def _time_proportions(d, time):
    if not time:
        return pd.DataFrame({"n": [len(d)], "successes": [int(d["._y"].sum())], "proportion": [d["._y"].mean()]})
    cats = list(d[time].cat.categories) if isinstance(d[time].dtype, pd.CategoricalDtype) else sorted(d[time].unique())
    rows = []
    for c in cats:
        g = d.loc[d[time].astype(object) == c, "._y"]
        if len(g):
            rows.append({"time": r_str(c), "n": len(g), "successes": int(g.sum()), "proportion": g.mean()})
    return pd.DataFrame(rows)


def _time_distribution(d, time, lv):
    grp = ["all"] * len(d) if not time else as_chr(d[time].astype(object))
    out = []
    for g in sorted(set(grp)):
        ys = d["._y"].values[np.array(grp) == g]
        row = {"time": g, "n": len(ys)}
        for j, l in enumerate(lv):
            row[f"prop_{l}"] = float(np.mean(ys == j + 1))
        out.append(row)
    return pd.DataFrame(out)


def cc_gee_binary(data, id, y, x=(), time=None, numeric=(), ref=None, interactions=(), success=None,
                  corstr="exchangeable", test="wald", conf_level=0.95):
    if corstr not in ("exchangeable", "ar1", "independence", "unstructured"):
        raise CCError(f"corstr 只能是 exchangeable、ar1、independence、unstructured，不是 {corstr}。")
    if corstr in ("ar1", "unstructured"):
        # statsmodels estimates these correlations differently from geepack (ar1: 0.656 vs 0.732 on the
        # demo data), so the robust SEs would not match the R version.
        raise CCError(f"Python 版的 working correlation 只支援 exchangeable（課本建議，§9.2.2）與 independence；"
                      f"{corstr} 的估計方式和 R 的 geepack 不同，數字會對不上。請改用 exchangeable，"
                      "或把 references/methods.md 的 B1 R 程式碼交給使用者執行。")
    pm = _prepare_model(data, id, y, x, time, numeric, ref, interactions, "binary", success=success, family="gee")
    d, warnings, facts = pm["data"], pm["warnings"], pm["facts"]
    if str(test).lower() == "lr":
        warnings.append(cc_warning("GEE_NO_LIKELIHOOD", "GEE 沒有概似函數，不能做概似比檢定或比較 deviance；以下改用 robust SE 的 Wald 檢定。", "§9.2.4"))
    X, names, owner = _model_matrix(d, pm["terms"])
    yv = d["._y"].values.astype(float)
    warnings += _check_separation(X, yv)
    cs = {"exchangeable": sm.cov_struct.Exchangeable(), "ar1": sm.cov_struct.Autoregressive(grid=True),
          "independence": sm.cov_struct.Independence(), "unstructured": sm.cov_struct.Unstructured()}[corstr]
    model = sm.GEE(yv, X, groups=d["._id"].values, time=(d["._wave"].values - 1), family=sm.families.Binomial(), cov_struct=cs)
    res = model.fit(maxiter=200)
    coefs = np.asarray(res.params); vc = np.asarray(res.cov_robust)
    est = _coef_table(names, coefs, np.sqrt(np.diag(vc)), conf_level)
    tests = _term_tests(coefs, vc, _term_index(names, dict(zip(names, owner)), pm["terms"]), "Wald (robust SE)", "§9.2.4")
    if corstr == "independence":
        alpha = []
    elif corstr == "unstructured":
        A = np.asarray(cs.dep_params)
        alpha = [float(A[i, j]) for i in range(A.shape[0]) for j in range(i + 1, A.shape[1])]
    else:
        alpha = [float(cs.dep_params)]
    facts.append(f"邊際 logistic 模型（GEE），成功 =「{pm['response']['success']}」，working correlation = {corstr}"
                 + (f"（估計相關 {', '.join(fmt_num(a) for a in alpha)}）" if alpha else "") + "。")
    for r in range(1, len(est)):
        e = est.iloc[r]
        facts.append(f"{e.term}：整體來說，勝算比 = {fmt_num(e.odds_ratio)}（{round(conf_level * 100)}% 信賴區間 {fmt_num(e.or_lower)} 到 {fmt_num(e.or_upper)}），P {fmt_p(e.p_value)}。")
    for _, t in tests.iterrows():
        facts.append(f"{t.test} = {fmt_num(t.statistic, 2)}（df = {int(t.df)}），P {fmt_p(t.p_value)}。")
    return cc_result("gee_binary", "Marginal logistic model fitted by GEE", "§9.2", "A",
                     estimates=est, tests=tests, tables={"proportions": _time_proportions(d, time)},
                     warnings=warnings, facts=facts,
                     notes={"effect_type": "population-averaged", "corstr": corstr, "working_correlation": alpha,
                            "clusters": pm["clusters"], "cluster_level": pm["cluster_level"], "predictors": pm["predictors"],
                            "cluster_reminder": _cluster_reminder(pm["clusters"]["n_clusters"]),
                            "reminder": "勝算比是「整體平均」的效果；SE 為 robust（sandwich）SE，即使 working correlation 設錯也有效（§9.2.2）。"})


def cc_gee_multinomial(data, id, y, x=(), time=None, numeric=(), ref=None, interactions=(), type="ordinal",
                       levels=None, baseline=None, lorstr="independence", conf_level=0.95):
    if lorstr != "independence":
        raise CCError("Python 版只支援 lorstr = independence（課本例子的設定）；uniform 請用 R 版。")
    pm = _prepare_model(data, id, y, x, time, numeric, ref, interactions, type, levels=levels, baseline=baseline, family="gee")
    d, warnings, facts = pm["data"], pm["warnings"], pm["facts"]
    lv = pm["response"]["levels"]
    K = len(lv)
    X, names, owner = _model_matrix(d, pm["terms"], intercept=(type == "nominal"))
    yv = d["._y"].values.astype(int)
    groups = d["._id"].values
    if type == "ordinal":
        theta, V = ordinal_gee_independence(yv, X, groups, K)
        coef_names = [f"beta{j}0" for j in range(1, K)] + names
        coefs = theta
        keep = list(range(K - 1, len(theta)))
        est = _coef_table([coef_names[i] for i in keep], coefs[keep], np.sqrt(np.diag(V))[keep], conf_level, exp_sign=-1)
        est = est.rename(columns={"odds_ratio": "odds_ratio_higher"})
        facts.append(f"累積 logit 邊際模型（GEE），類別由低到高：{' < '.join(lv)}；局部勝算比結構 = {lorstr}。")
        for _, e in est.iterrows():
            facts.append(f"{e.term}：整體來說，落在較高類別的勝算比 = {fmt_num(e.odds_ratio_higher)}（{round(conf_level * 100)}% 信賴區間 {fmt_num(e.or_lower)} 到 {fmt_num(e.or_upper)}），P {fmt_p(e.p_value)}（每個切點相同）。")
        owner_of = dict(zip(names, owner))
    else:
        coefs, V = nominal_gee_independence(yv, X, groups, K)
        p = X.shape[1]
        coef_names = []
        for j in range(1, K):
            coef_names += [f"beta{j}0"] + [f"{nm}:{j}" for nm in names[1:]]
        keep = [i for i, nm in enumerate(coef_names) if not re.match(r"^beta[0-9]+0$", nm)]
        est = _coef_table([coef_names[i] for i in keep], coefs[keep], np.sqrt(np.diag(V))[keep], conf_level)
        est.insert(1, "category", [lv[int(re.sub(r"^.*:([0-9]+)$", r"\1", t)) - 1] for t in est.term])
        est["term"] = [re.sub(r":[0-9]+$", "", t) for t in est.term]
        facts.append(f"baseline-category logit 邊際模型（GEE），基準類別 =「{pm['response']['baseline']}」；局部勝算比結構 = {lorstr}。")
        for _, e in est.iterrows():
            facts.append(f"{e.term}（{e.category} vs {pm['response']['baseline']}）：整體來說，勝算比 = {fmt_num(e.odds_ratio)}（{round(conf_level * 100)}% 信賴區間 {fmt_num(e.or_lower)} 到 {fmt_num(e.or_upper)}），P {fmt_p(e.p_value)}。")
        owner_of = dict(zip(names, owner))
    tests = _term_tests(np.asarray(coefs), V, _term_index(coef_names, owner_of, pm["terms"], nominal=(type == "nominal")),
                        "Wald (robust SE)", "§9.3")
    for _, t in tests.iterrows():
        facts.append(f"{t.test} = {fmt_num(t.statistic, 2)}（df = {int(t.df)}），P {fmt_p(t.p_value)}。")
    return cc_result(f"gee_{type}", "Cumulative logit marginal model fitted by GEE" if type == "ordinal" else
                     "Baseline-category logit marginal model fitted by GEE", "§9.3", "A",
                     estimates=est, tests=tests, tables={"distribution": _time_distribution(d, time, lv)},
                     warnings=warnings, facts=facts,
                     notes={"effect_type": "population-averaged", "lorstr": lorstr, "levels": lv,
                            "clusters": pm["clusters"], "cluster_level": pm["cluster_level"], "predictors": pm["predictors"],
                            "cluster_reminder": _cluster_reminder(pm["clusters"]["n_clusters"]),
                            "reminder": "比例勝算：模型假設每個切點的效果相同（§6.3.2、§9.3.1），第一版不做正式檢定。" if type == "ordinal"
                            else "每個勝算比都是「該類 vs 基準類別」；換基準類別不影響配適（§6.1）。"})


R_ONLY = ("glmm_binary", "compare_gee_glmm")
R_ONLY_MESSAGE = ("Python 版不做 GLMM（{analysis}）：statsmodels 沒有和 R lme4 相同的最大概似估計（adaptive Gauss–Hermite），"
                  "數字會和課本不一致。請依 SKILL.md「沒有 R 時」的做法，把 references/methods.md 的 B3／B4 R 程式碼"
                  "交給使用者在 R／RStudio 執行並貼回輸出；只要整體平均的效果，可以改用 gee_binary。")


# ----------------------------------------------------------------------------- JSON

def _clean(obj):
    if isinstance(obj, pd.DataFrame):
        return [_clean(r) for r in obj.to_dict(orient="records")]
    if isinstance(obj, dict):
        return {str(k): _clean(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_clean(v) for v in obj]
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating, float)):
        v = float(obj)
        if math.isnan(v):
            return None
        if math.isinf(v):
            return "Inf" if v > 0 else "-Inf"
        return v
    if isinstance(obj, np.ndarray):
        return [_clean(v) for v in obj.tolist()]
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    return obj


def cc_to_json(result, path=None):
    out = dict(result)
    out["tables"] = {k: ({kk: vv for kk, vv in v.items() if kk != "dimnames"} if isinstance(v, dict) and "rows" in v else v)
                     for k, v in result["tables"].items()}
    text = json.dumps(_clean(out), ensure_ascii=False, indent=2)
    if path:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    return text
