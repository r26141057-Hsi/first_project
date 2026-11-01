# Python engine tests:
#   1. textbook numbers (same examples as dev/test_engine.R)
#   2. Python vs R on the student_por demo specs: result.json numbers, warnings and facts
# Run from the Part3 folder: python dev/test_python.py   (part 2 needs the R outputs in dev/demo/out_*)

import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.join("categorical-correlated", "scripts"))
import cc_engine as E  # noqa: E402

results = []


def check(item, got, book, tol):
    got = float(got)
    results.append((item, round(got, 5), book, tol, abs(got - book) <= tol))


def square_to_wide(tab, labels):
    rows = []
    for i in range(len(labels)):
        for j in range(len(labels)):
            rows += [(labels[i], labels[j])] * int(tab[i][j])
    return pd.DataFrame(rows, columns=["y1", "y2"])


def square_to_long(tab, labels=None):
    rows, pid = [], 0
    k = len(tab)
    for i in range(k):
        for j in range(k):
            for _ in range(int(tab[i][j])):
                pid += 1
                rows += [(pid, 1, labels[i] if labels else i + 1), (pid, 0, labels[j] if labels else j + 1)]
    return pd.DataFrame(rows, columns=["person", "time", "y"])


def est(r, measure, col="estimate"):
    e = r["estimates"]
    return e.loc[e.measure == measure, col].iloc[0]


def test_stat(r, pattern, col="statistic"):
    t = r["tests"]
    return t.loc[t.test.str.contains(pattern, regex=False), col].iloc[0]


def has_warning(r, code):
    return any(w["code"] == code for w in r["warnings"])


# ---- 1. textbook ----
t81 = [[227, 132], [107, 678]]
r = E.cc_paired_binary(square_to_wide(t81, ["yes", "no"]), "y1", "y2", success="yes")
check("A1 McNemar X2", test_stat(r, "McNemar"), 2.6151, 1e-4)
check("A1 score CI lower", est(r, "Difference of proportions (y1 - y2)", "lower"), -0.00466, 1e-5)
check("A1 score CI upper", est(r, "Difference of proportions (y1 - y2)", "upper"), 0.04849, 1e-5)
check("A1 conditional OR", est(r, "Conditional odds ratio n12/n21: y1 vs y2 (subject-specific)"), 132 / 107, 1e-6)
small = pd.DataFrame({"y1": ["yes"] * 26 + ["no"] * 32, "y2": ["yes"] * 20 + ["no"] * 6 + ["yes"] * 2 + ["no"] * 30})
r = E.cc_paired_binary(small, "y1", "y2", success="yes")
check("A1 FEW_DISCORDANT", has_warning(r, "FEW_DISCORDANT"), 1, 0)
check("A1 exact P", test_stat(r, "Exact", "p_value"), 0.2890625, 1e-6)

lv85 = ["HighPoint", "Tasters", "Sanka", "Nescafe", "Brim"]
t85 = [[93, 17, 44, 7, 10], [9, 46, 11, 0, 9], [17, 11, 155, 9, 12], [6, 4, 9, 15, 2], [10, 4, 12, 2, 27]]
r = E.cc_paired_nominal(square_to_wide(t85, lv85), "y1", "y2", levels=lv85)
check("A2 MH LR", test_stat(r, "symmetry vs quasi"), 12.4989, 1e-3)
check("A2 symmetry deviance", test_stat(r, "Symmetry model"), 22.473, 1e-3)
check("A2 CMH", test_stat(r, "CMH"), 12.291, 1e-3)
check("A2 HighPoint z", r["estimates"].z.iloc[0], 3.28634, 1e-4)
check("A2 HighPoint CI lower", r["estimates"].lower.iloc[0], 0.02727, 1e-4)

t86 = [[12, 43, 163, 233], [4, 21, 99, 185], [4, 8, 77, 230], [0, 1, 18, 132]]
lv86 = ["always", "often", "sometimes", "never"]
r = E.cc_paired_ordinal(square_to_wide(t86, lv86), "y1", "y2", levels=lv86)
check("A3 GEE beta", est(r, "beta: cumulative logit, first vs second (logit P(Y <= j))"), 2.75361, 1e-4)
check("A3 GEE robust SE", est(r, "beta: cumulative logit, first vs second (logit P(Y <= j))", "se"), 0.08147, 1e-5)
check("A3 ordinal QS beta", est(r, "Ordinal quasi-symmetry beta"), 2.3936, 1e-4)
check("A3 change up", r["tables"]["changes"].n.iloc[0], 953, 0)

seqs = [(1, 1, 1), (1, 1, 0), (0, 1, 1), (0, 1, 0), (1, 0, 1), (1, 0, 0), (0, 0, 1), (0, 0, 0)]
counts = {0: [342, 26, 6, 21, 11, 32, 19, 356], 1: [440, 25, 14, 18, 14, 47, 22, 457]}
rows, pid = [], 0
for g in (0, 1):
    for s, n in zip(seqs, counts[g]):
        for _ in range(n):
            pid += 1
            rows += [(pid, g, t + 1, s[t]) for t in range(3)]
ab = pd.DataFrame(rows, columns=["person", "gender", "situation", "response"])
r = E.cc_gee_binary(ab, "person", "response", x=["gender"], time="situation", numeric=["gender"],
                    ref={"situation": "3"}, success="1")
e = r["estimates"]
check("B1 GEE sit1", e.estimate[e.term == "situation1"].iloc[0], 0.14935, 1e-4)
check("B1 GEE sit1 SE", e.se[e.term == "situation1"].iloc[0], 0.02974, 1e-4)
check("B1 GEE rho", r["notes"]["working_correlation"][0], 0.81733, 1e-4)
check("B1 Wald situation", test_stat(r, "situation"), 26.0171, 0.01)

ins_rows, pid = [], 0
act = [[7, 4, 1, 0], [11, 5, 2, 2], [13, 23, 3, 1], [9, 17, 13, 8]]
pla = [[7, 4, 2, 1], [14, 5, 1, 0], [6, 9, 18, 2], [4, 11, 14, 22]]
for tr, tab in ((1, act), (0, pla)):
    for i in range(4):
        for j in range(4):
            for _ in range(tab[i][j]):
                pid += 1
                ins_rows += [(pid, tr, 0, i + 1), (pid, tr, 1, j + 1)]
ins = pd.DataFrame(ins_rows, columns=["case", "treat", "occasion", "response"])
r = E.cc_gee_multinomial(ins, "case", "response", x=["treat"], time="occasion", numeric=["treat", "occasion"],
                         interactions=["occasion:treat"], type="ordinal", levels=["1", "2", "3", "4"])
e = r["estimates"]
check("B2 interaction", e.estimate[e.term == "occasion:treat"].iloc[0], 0.70776, 1e-4)
check("B2 interaction SE", e.se[e.term == "occasion:treat"].iloc[0], 0.24352, 1e-4)

cof = square_to_long(t85, lv85)
r = E.cc_gee_multinomial(cof, "person", "y", time="time", numeric=["time"], type="nominal", levels=lv85, baseline="Brim")
e = r["estimates"]
check("B2 nominal HighPoint", e.estimate[e.category == "HighPoint"].iloc[0], 0.32340, 1e-4)
check("B2 nominal SE", e.se[e.category == "HighPoint"].iloc[0], 0.16830, 1e-4)
check("B2 nominal Wald", test_stat(r, "time"), 12.4869, 1e-3)

# ---- 2. Python vs R on the demo specs ----
R_OUT = {"spec_drink.json": "out_drink", "spec_job.json": "out_job", "spec_sup.json": "out_sup",
         "spec_alc_gee.json": "out_alc_gee", "spec_job_gee.json": "out_job_gee",
         "spec_pass_gee_exchangeable.json": "out_pass_gee_exchangeable",
         "spec_pass_gee_independence.json": "out_pass_gee_independence",
         "spec_pass_gee_int.json": "out_pass_gee_int"}
compare_notes = []


def flatten(x, prefix=""):
    if isinstance(x, dict):
        out = {}
        for k, v in x.items():
            out.update(flatten(v, f"{prefix}.{k}" if prefix else k))
        return out
    if isinstance(x, list):
        out = {}
        for i, v in enumerate(x):
            out.update(flatten(v, f"{prefix}[{i}]"))
        return out
    return {prefix: x}


for spec, rdir in R_OUT.items():
    rpath = os.path.join("dev", "demo", rdir, "result.json")
    if not os.path.exists(rpath):
        compare_notes.append(f"略過 {spec}：沒有 R 的輸出")
        continue
    pdir = os.path.join("dev", "demo", rdir + "_py")
    proc = subprocess.run([sys.executable, os.path.join("categorical-correlated", "scripts", "run_analysis.py"),
                           os.path.join("dev", "demo", "student_por.csv"), os.path.join("dev", "demo", spec), pdir],
                          capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        results.append((f"{spec} runs", 0, 1, 0, False)); compare_notes.append(proc.stderr[-800:]); continue
    R = json.load(open(rpath, encoding="utf-8")); P = json.load(open(os.path.join(pdir, "result.json"), encoding="utf-8"))
    fr, fp = flatten({k: R[k] for k in ("estimates", "tests")}), flatten({k: P[k] for k in ("estimates", "tests")})
    bad = []
    for k, v in fr.items():
        w = fp.get(k, "<missing>")
        if isinstance(v, (int, float)) and isinstance(w, (int, float)):
            if abs(v - w) > 1e-4 * max(1, abs(v)):
                bad.append(f"{k}: R {v} / Py {w}")
        elif v != w:
            bad.append(f"{k}: R {v!r} / Py {w!r}")
    results.append((f"{spec} numbers", len(bad), 0, 0, not bad))
    if bad:
        compare_notes += [f"{spec}: {b}" for b in bad[:8]]
    rw = sorted(w["code"] for w in R["warnings"]); pw = sorted(w["code"] for w in P["warnings"])
    results.append((f"{spec} warnings", int(rw == pw), 1, 0, rw == pw))
    same_facts = R["facts"] == P["facts"]
    results.append((f"{spec} facts", int(same_facts), 1, 0, same_facts))
    if not same_facts:
        for a, b in zip(R["facts"], P["facts"]):
            if a != b:
                compare_notes.append(f"{spec} fact\n  R : {a}\n  Py: {b}")
        if len(R["facts"]) != len(P["facts"]):
            compare_notes.append(f"{spec}: {len(R['facts'])} R facts vs {len(P['facts'])} Py facts")

# GLMM is R only: the Python script must stop with a message pointing to methods.md
pdir = os.path.join("dev", "demo", "out_glmm_py")
proc = subprocess.run([sys.executable, os.path.join("categorical-correlated", "scripts", "run_analysis.py"),
                       os.path.join("dev", "demo", "student_por.csv"), os.path.join("dev", "demo", "spec_pass.json"), pdir],
                      capture_output=True, text=True, encoding="utf-8")
err = json.load(open(os.path.join(pdir, "result.json"), encoding="utf-8")).get("error", "")
results.append(("GLMM refused in Python with methods.md pointer", int("methods.md" in err), 1, 0,
                proc.returncode != 0 and "methods.md" in err))

# ar1 / unstructured: statsmodels differs from geepack, so Python must refuse instead of giving other numbers
for cs in ("ar1", "unstructured"):
    pdir = os.path.join("dev", "demo", f"out_pass_gee_{cs}_py")
    proc = subprocess.run([sys.executable, os.path.join("categorical-correlated", "scripts", "run_analysis.py"),
                           os.path.join("dev", "demo", "student_por.csv"), os.path.join("dev", "demo", f"spec_pass_gee_{cs}.json"), pdir],
                          capture_output=True, text=True, encoding="utf-8")
    err = json.load(open(os.path.join(pdir, "result.json"), encoding="utf-8")).get("error", "")
    results.append((f"GEE {cs} refused in Python", int("exchangeable" in err), 1, 0, proc.returncode != 0 and "exchangeable" in err))

# Stage 1 and stage 3: Python vs R
for stage, args, rdir in (("profile_data", [], "stage1"), ("describe_question", ["q_drink.json"], "stage3_drink"),
                          ("describe_question", ["q_pass.json"], "stage3_pass")):
    pdir = os.path.join("dev", "demo", rdir + "_py")
    proc = subprocess.run([sys.executable, os.path.join("categorical-correlated", "scripts", stage + ".py"),
                           os.path.join("dev", "demo", "student_por.csv")] + [os.path.join("dev", "demo", a) for a in args] + [pdir],
                          capture_output=True, text=True, encoding="utf-8")
    fname = "profile.json" if stage == "profile_data" else "check.json"
    if proc.returncode != 0:
        results.append((f"{rdir} runs", 0, 1, 0, False)); compare_notes.append(proc.stderr[-800:]); continue
    R = json.load(open(os.path.join("dev", "demo", rdir, fname), encoding="utf-8"))
    P = json.load(open(os.path.join(pdir, fname), encoding="utf-8"))
    if stage == "profile_data":
        rh = [(h["type"], tuple(h["columns"])) for h in R["structure"]["hints"]]
        ph = [(h["type"], tuple(h["columns"])) for h in P["structure"]["hints"]]
        results.append((f"{rdir} hints", int(rh == ph), 1, 0, rh == ph))
        rt = [(v["name"], v["type_guess"]) for v in R["variables"]]; pt = [(v["name"], v["type_guess"]) for v in P["variables"]]
        results.append((f"{rdir} type guesses", int(rt == pt), 1, 0, rt == pt))
        if rt != pt:
            compare_notes += [f"type: R {a} / Py {b}" for a, b in zip(rt, pt) if a != b]
    else:
        same_facts = R["facts"] == P["facts"]
        results.append((f"{rdir} facts", int(same_facts), 1, 0, same_facts))
        if not same_facts:
            compare_notes += [f"{rdir}\n  R : {a}\n  Py: {b}" for a, b in zip(R["facts"], P["facts"]) if a != b]
        keys = [k for k in R if isinstance(R[k], (int, float)) and not isinstance(R[k], bool)]
        bad = [k for k in keys if abs(R[k] - P.get(k, float("nan"))) > 1e-8]
        results.append((f"{rdir} numbers", len(bad), 0, 0, not bad))

w = max(len(r[0]) for r in results)
for item, got, book, tol, ok in results:
    print(f"{item:<{w}}  {got:>12}  {book:>12}  {'OK' if ok else 'FAIL'}")
print("\n".join(compare_notes))
print(f"\n{sum(r[4] for r in results)} / {len(results)} 通過")
sys.exit(0 if all(r[4] for r in results) else 1)
