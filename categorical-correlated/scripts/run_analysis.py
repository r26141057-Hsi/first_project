# Run one analysis for the categorical-correlated Skill — Python version (mode 2: no R).
#
# Usage: python run_analysis.py <data file> <spec.json> <output dir>
# Same spec.json and outputs as run_analysis.R (result.json, PNG plots, 分析報告_<data>_<analysis>.md,
# reproduce.py, spec.json). glmm_binary and compare_gee_glmm are R only: result.json then holds an
# error telling Claude to hand the R code in references/methods.md to the user.

import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_engine as E  # noqa: E402
import cc_report as Rp  # noqa: E402


def main():
    if len(sys.argv) != 4:
        sys.exit("Usage: python run_analysis.py <data file> <spec.json> <output dir>")
    data_file, spec_file, out_dir = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)

    def fail(msg):
        with open(os.path.join(out_dir, "result.json"), "w", encoding="utf-8") as f:
            json.dump({"error": msg}, f, ensure_ascii=False, indent=2)
        sys.stderr.write("ERROR: " + msg + "\n")
        sys.exit(1)

    spec = json.load(open(spec_file, encoding="utf-8"))
    analysis = spec.get("analysis")
    if analysis in E.R_ONLY:
        fail(E.R_ONLY_MESSAGE.format(analysis=analysis))
    try:
        data = E.read_data(data_file)
    except Exception as e:  # noqa: BLE001
        fail(f"無法讀取資料： {e}")
    try:
        result, call = run(data, spec)
    except E.CCError as e:
        fail(str(e))
    except Exception as e:  # noqa: BLE001
        fail(f"計算時發生錯誤：{e}")

    try:
        result["plots"] = Rp.cc_plots(result, out_dir)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"plot skipped: {e}\n")
        result["plots"] = []

    data_name = os.path.splitext(os.path.basename(data_file))[0]
    report_file = os.path.join(out_dir, f"分析報告_{data_name}_{analysis}.md")
    with open(report_file, "w", encoding="utf-8") as f:
        f.write("\n".join(Rp.report_md(result, spec, data_file)) + "\n")
    result["report"] = os.path.basename(report_file)

    scripts = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
    with open(os.path.join(out_dir, "reproduce.py"), "w", encoding="utf-8") as f:
        f.write("\n".join([
            "# 重現這次分析的 Python 程式碼（需要本 Skill 的 scripts/ 資料夾）",
            "import json, sys",
            f"sys.path.insert(0, {scripts!r})",
            "import cc_engine as E",
            "from run_analysis import run",
            f"data = E.read_data({os.path.abspath(data_file).replace(chr(92), '/')!r})",
            f"spec = json.loads({json.dumps(spec, ensure_ascii=False)!r})",
            "result, call = run(data, spec)",
            "print(json.dumps({k: result[k] for k in ('method', 'facts')}, ensure_ascii=False, indent=2))", ""]))

    spec_copy = os.path.join(out_dir, "spec.json")
    if not os.path.exists(spec_copy) or os.path.abspath(spec_file) != os.path.abspath(spec_copy):
        shutil.copyfile(spec_file, spec_copy)
    E.cc_to_json(result, os.path.join(out_dir, "result.json"))
    print("OK: " + os.path.abspath(os.path.join(out_dir, "result.json")))
    print("REPORT: " + os.path.abspath(report_file))


def run(data, spec):
    """Apply reshape / recode, then call the analysis. Returns (result, (function name, arguments))."""
    notes = []
    if spec.get("reshape"):
        r = spec["reshape"]
        data, rn, idc = E.cc_reshape_long(data, r["cols"], r.get("id"), r.get("value") or "y", r.get("time") or "time",
                                          r.get("time_values"))
        notes += rn
        spec = dict(spec, id=spec.get("id") or idc)
    if spec.get("recode"):
        data, rn = E.cc_recode(data, spec["recode"])
        notes += rn

    def levels_of(var):
        lv = spec.get("levels")
        if isinstance(lv, dict):
            return lv.get(var)
        return lv

    conf = spec.get("conf_level") or 0.95
    common = dict(id=spec.get("id"), y=spec.get("y"), x=spec.get("x") or [], time=spec.get("time"),
                  numeric=spec.get("numeric") or [], ref=spec.get("ref") or {}, interactions=spec.get("interactions") or [],
                  conf_level=conf)
    a = spec.get("analysis")
    calls = {
        "paired_binary": ("cc_paired_binary", dict(y1=spec.get("y1"), y2=spec.get("y2"), success=spec.get("success"),
                                                   levels=levels_of(spec.get("y1")), conf_level=conf)),
        "paired_nominal": ("cc_paired_nominal", dict(y1=spec.get("y1"), y2=spec.get("y2"), levels=levels_of(spec.get("y1")),
                                                     ordinal=spec.get("ordinal") or [], conf_level=conf)),
        "paired_ordinal": ("cc_paired_ordinal", dict(y1=spec.get("y1"), y2=spec.get("y2"), levels=levels_of(spec.get("y1")),
                                                     scores=spec.get("scores"), conf_level=conf)),
        "gee_binary": ("cc_gee_binary", dict(common, success=spec.get("success"), corstr=spec.get("corstr") or "exchangeable",
                                             test=spec.get("test") or "wald")),
        "gee_ordinal": ("cc_gee_multinomial", dict(common, type="ordinal", levels=levels_of(spec.get("y")),
                                                   lorstr=spec.get("lorstr") or "independence")),
        "gee_nominal": ("cc_gee_multinomial", dict(common, type="nominal", levels=levels_of(spec.get("y")),
                                                   baseline=spec.get("baseline"), lorstr=spec.get("lorstr") or "independence")),
    }
    if a not in calls:
        raise E.CCError(f"本 Skill 不支援的分析：{a or '（未指定）'}。可用：{', '.join(list(calls) + list(E.R_ONLY))}。"
                        "資料若其實彼此獨立，請改用 Part 1（categorical-association）或 Part 2（categorical-modeling）。")
    fun, args = calls[a]
    result = getattr(E, fun)(data, **args)
    result["facts"] = notes + result["facts"]
    return result, (fun, args)


if __name__ == "__main__":
    main()
