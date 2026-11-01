# Stage 3 — Python version of describe_question.R (mode 2): plots and checklist numbers, no test.
# Usage: python describe_question.py <data file> <question.json> <output dir>
# Writes check.json, 初步檢視_<data>.md and PNG plots.

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_engine as E  # noqa: E402
import cc_report as Rp  # noqa: E402

if len(sys.argv) != 4:
    sys.exit("Usage: python describe_question.py <data file> <question.json> <output dir>")
data_file, q_file, out_dir = sys.argv[1:]
os.makedirs(out_dir, exist_ok=True)


def fail(msg):
    json.dump({"error": msg}, open(os.path.join(out_dir, "check.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    sys.exit("ERROR: " + msg)


q = json.load(open(q_file, encoding="utf-8"))
try:
    data = E.read_data(data_file)
except Exception as e:  # noqa: BLE001
    fail(f"無法讀取資料： {e}")
notes = []
try:
    if q.get("reshape"):
        r = q["reshape"]
        data, rn, idc = E.cc_reshape_long(data, r["cols"], r.get("id"), r.get("value") or "y", r.get("time") or "time",
                                          r.get("time_values"))
        notes += rn
        q["id"] = q.get("id") or idc
    if q.get("recode"):
        data, rn = E.cc_recode(data, q["recode"])
        notes += rn
    check, facts, tables, plots = Rp.cc_describe(data, q, out_dir)
except E.CCError as e:
    fail(str(e))
facts = notes + facts
check["facts"] = facts
check["plots"] = plots
check["tables"] = {k: ({kk: vv for kk, vv in v.items() if kk != "dimnames"} if isinstance(v, dict) else v) for k, v in tables.items()}
with open(os.path.join(out_dir, "check.json"), "w", encoding="utf-8") as f:
    f.write(json.dumps(E._clean(check), ensure_ascii=False, indent=2))
name = os.path.splitext(os.path.basename(data_file))[0]
md = os.path.join(out_dir, f"初步檢視_{name}.md")
with open(md, "w", encoding="utf-8") as f:
    f.write("\n".join(Rp.describe_md(check, facts, tables, plots, os.path.basename(data_file), q.get("question"))) + "\n")
print("OK: " + os.path.abspath(os.path.join(out_dir, "check.json")))
print("OK: " + os.path.abspath(md))
