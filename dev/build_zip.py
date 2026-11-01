# Package the Skill as categorical-correlated.zip (run from the Part3 folder: python dev/build_zip.py).
# The zip holds one top-level folder named categorical-correlated, as claude.ai expects, with
# forward-slash paths (PowerShell 5.1 Compress-Archive writes backslashes, which break on Linux).

import os
import zipfile

SKILL = "categorical-correlated"
OUT = "categorical-correlated.zip"
SKIP_DIRS = {"__pycache__", ".Rproj.user"}
SKIP_FILES = {".Rhistory", ".DS_Store"}

files = []
for root, dirs, names in os.walk(SKILL):
    dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
    for n in sorted(names):
        if n in SKIP_FILES or n.endswith(".pyc"):
            continue
        files.append(os.path.join(root, n))

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, f.replace(os.sep, "/"))

print(f"OK: {OUT}（{len(files)} 個檔案，{os.path.getsize(OUT) / 1024:.0f} KB）")
for f in files:
    print("  " + f.replace(os.sep, "/"))
