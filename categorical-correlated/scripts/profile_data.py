# Stage 1 — Python version of profile_data.R (mode 2).
# Usage: python profile_data.py <data file> <output dir>
# Writes profile.json and 資料總覽_<data>.md. Every guess must be confirmed with the user.

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cc_engine as E  # noqa: E402
import cc_report as Rp  # noqa: E402

if len(sys.argv) != 3:
    sys.exit("Usage: python profile_data.py <data file> <output dir>")
data_file, out_dir = sys.argv[1:]
os.makedirs(out_dir, exist_ok=True)
out_file = os.path.join(out_dir, "profile.json")
try:
    profile = Rp.cc_profile(E.read_data(data_file))
except Exception as e:  # noqa: BLE001
    json.dump({"error": f"無法讀取資料： {e}"}, open(out_file, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    sys.exit("ERROR: " + str(e))
profile["file"] = os.path.abspath(data_file).replace("\\", "/")
with open(out_file, "w", encoding="utf-8") as f:
    f.write(json.dumps(E._clean(profile), ensure_ascii=False, indent=2))
name = os.path.splitext(os.path.basename(data_file))[0]
overview = os.path.join(out_dir, f"資料總覽_{name}.md")
with open(overview, "w", encoding="utf-8") as f:
    f.write("\n".join(Rp.overview_md(profile, os.path.basename(data_file))) + "\n")
print("OK: " + os.path.abspath(out_file))
print("OK: " + os.path.abspath(overview))
