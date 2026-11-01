# Stage 8 — Python version of build_report.R (mode 2): assemble the whole step-by-step analysis into one report.
# Usage: python build_report.py <output dir> [--no-render]   (--no-render: write the .md copy, skip Quarto)
# Reads analysis_log.json, the stage 1/3 files, stepK/分析報告_*.md and 結論.md (see build_report.R for the formats);
# writes 整份分析報告_<data>.qmd, rendered to .html when Quarto is found, otherwise a .md copy.
# Every number comes from the step reports that run_analysis wrote; nothing is recomputed.

import glob
import json
import os
import re
import shutil
import subprocess
import sys

args = [a for a in sys.argv[1:] if a != "--no-render"]
if len(args) != 1:
    sys.exit("Usage: python build_report.py <output dir> [--no-render]")
no_render = "--no-render" in sys.argv[1:]
out_dir = os.path.abspath(args[0]).replace("\\", "/")

METHOD_NAMES = {
    "paired_binary": "McNemar 檢定（§8.1）",
    "paired_nominal": "邊際同質性（§8.3）",
    "paired_ordinal": "有序配對的累積 logit 邊際模型（§8.4）",
    "gee_binary": "GEE 邊際 logistic 模型（§9.2）",
    "gee_ordinal": "GEE 累積 logit 模型（§9.3）",
    "gee_nominal": "GEE baseline-category logit 模型（§9.3）",
    "glmm_binary": "GLMM 隨機截距 logistic 模型（§10.1–10.2）",
    "compare_gee_glmm": "GEE 與 GLMM 並排（§10.1.4）",
}


def method_name(a):
    return METHOD_NAMES.get(a, a or "") if a is not None else ""


def read_utf8(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read().splitlines()


def find_one(d, pattern):
    files = sorted(f for f in os.listdir(d) if re.search(pattern, f)) if os.path.isdir(d) else []
    return os.path.join(d, files[0]) if files else None


def embed_md(path, shift, prefix):
    """Drop the file's own title, shift headings down `shift` levels and point images at `prefix`."""
    lines = read_utf8(path)
    for i, line in enumerate(lines):
        if line.startswith("# "):
            del lines[i]
            break
    if shift > 0:
        lines = [re.sub(r"^(#+) ", lambda m: "#" * shift + m.group(1) + " ", x) for x in lines]
    if prefix:
        lines = [re.sub(r"!\[([^]]*)\]\(([^)/:]+)\)", lambda m: f"![{m.group(1)}]({prefix}/{m.group(2)})", x)
                 for x in lines]
    return lines


def md_cell(x):
    return (x or "").replace("\n", " ").replace("|", "\\|")


log_file = os.path.join(out_dir, "analysis_log.json")
if not os.path.exists(log_file):
    sys.exit("找不到 analysis_log.json：請先在輸出資料夾寫好分析紀錄。")
with open(log_file, encoding="utf-8-sig") as f:
    log = json.load(f)
steps = log.get("steps") or []
if not steps:
    sys.exit("analysis_log.json 沒有任何步驟。")

data_name = os.path.splitext(os.path.basename(log.get("data_file") or "data"))[0]
problems = []
out = ["---", f'title: "整份分析報告：{data_name}"', "lang: zh-Hant", "format:", "  html:", "    toc: true",
       "    toc-depth: 2", "    number-sections: true", "    embed-resources: true", "---", ""]

# ---- 1. Data and question ----
out += ["# 資料與研究問題", "", f"- 資料檔：`{os.path.basename(log.get('data_file') or '')}`",
        f"- 研究問題：{log.get('question') or ''}"]
overview = find_one(out_dir, r"^資料總覽_.*\.md$")
if overview:
    size_line = [x for x in read_utf8(overview) if re.match(r"^共 .*列", x)]
    if size_line:
        out.append(f"- 資料大小：{re.sub('。$', '', size_line[0])}")
out += [f"- 分析步驟：共 {len(steps)} 步", ""]

# ---- 2. Confirmed settings ----
if log.get("settings"):
    out += ["# 確認的設定", "", "以下設定在分析開始前和使用者確認過。", ""] + ["- " + s for s in log["settings"]] + [""]

# ---- 3. First look (stage 3) ----
first_look = find_one(out_dir, r"^初步檢視_.*\.md$")
if first_look:
    out += ["# 初步檢視", ""] + embed_md(first_look, 0, "") + [""]

# ---- 4. Steps ----
out += ["# 分析過程", ""]
for k, s in enumerate(steps, start=1):
    step_dir = os.path.join(out_dir, s.get("dir") or f"step{k}")
    spec_file = os.path.join(step_dir, "spec.json")
    spec = json.load(open(spec_file, encoding="utf-8-sig")) if os.path.exists(spec_file) else {}
    out += [f"## 第 {k} 步：{s.get('question') or method_name(spec.get('analysis'))}", "",
            f"**方法**：{method_name(spec.get('analysis'))}", ""]
    if s.get("reason") is not None:
        out += ["### 為什麼做這一步", "", s["reason"], ""]
    report = find_one(step_dir, r"^分析報告_.*\.md$")
    if report is None:
        problems.append(f"第 {k} 步（{os.path.basename(step_dir)}）沒有分析報告。")
        out += ["> 這一步沒有分析報告（`run_analysis` 可能沒有成功）。", ""]
    else:
        if not any(x.startswith("## 結論與解釋") for x in read_utf8(report)):
            problems.append(f"第 {k} 步的分析報告還沒有「## 結論與解釋」。")
        # The step section already names the data, method and reason; drop the report's own header lines.
        body = [x for x in embed_md(report, 1, os.path.basename(step_dir))
                if not re.match(r"^- (資料檔|方法|資料結構|選擇理由)：", x)]
        out += body + [""]
    if s.get("suggestions"):
        rows = [f"| {i} | {md_cell(g.get('text'))}{'（推薦）' if g.get('recommended') is True else ''} | "
                f"{md_cell(method_name(g.get('analysis')))} | {md_cell(g.get('reason'))} |"
                for i, g in enumerate(s["suggestions"], start=1)]
        out += ["### 下一步的建議", "", "| # | 建議 | 方法 | 理由 |", "|---|---|---|---|"] + rows + [
            "", f"**使用者的選擇**：{s.get('choice') or '（沒有紀錄）'}", ""]

# ---- 5. Conclusion ----
conclusion = os.path.join(out_dir, "結論.md")
out += ["# 結論與限制", ""]
if os.path.exists(conclusion):
    out += embed_md(conclusion, 1, "") + [""]
else:
    problems.append("沒有 結論.md（整體結論與限制）。")
    out += ["> 尚未撰寫整體結論。", ""]

# ---- 6. Appendix: code to reproduce each step ----
out += ["# 附錄：重現每一步的程式碼", "", "每一步的數字都可以用下面的程式碼重新計算（需要本 Skill 的計算引擎）。", ""]
for k, s in enumerate(steps, start=1):
    step_dir = os.path.join(out_dir, s.get("dir") or f"step{k}")
    for fname in ("reproduce.R", "reproduce.py"):
        p = os.path.join(step_dir, fname)
        if os.path.exists(p):
            out += [f"## 第 {k} 步（`{os.path.basename(step_dir)}/{fname}`）", "",
                    "```" + ("r" if fname == "reproduce.R" else "python")] + read_utf8(p) + ["```", ""]

qmd = f"{out_dir}/整份分析報告_{data_name}.qmd"
with open(qmd, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print("QMD: " + qmd)


# ---- Render with Quarto when available (no code chunks, so neither R nor Jupyter is needed) ----
def find_quarto():
    cands = [os.environ.get("QUARTO_PATH", ""), shutil.which("quarto") or "",
             "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
             "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto"]
    cands = [c for c in cands if c and os.path.exists(c)]
    return cands[0] if cands else None


html = qmd[:-4] + ".html"
quarto = None if no_render else find_quarto()
rendered = False
if quarto:
    try:
        status = subprocess.run([quarto, "render", os.path.basename(qmd), "--to", "html"], cwd=out_dir,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except OSError:
        status = 1
    rendered = status == 0 and os.path.exists(html)
if rendered:
    print("HTML: " + html)
else:
    md = qmd[:-4] + ".md"
    end_yaml = [i for i, x in enumerate(out) if x == "---"][1]
    with open(md, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join([f"# 整份分析報告：{data_name}", ""] + out[end_yaml + 1:]) + "\n")
    reason = "不轉檔（--no-render）" if no_render else "找不到 Quarto" if quarto is None else "Quarto 轉檔失敗"
    print(f"{reason}，改輸出 Markdown：" + md)
for p in problems:
    print("WARNING: " + p)
