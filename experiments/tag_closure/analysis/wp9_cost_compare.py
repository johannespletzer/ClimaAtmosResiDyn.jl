"""
V-W10's two passes side by side, point by point. It decides nothing.

    python3 analysis/wp9_cost_compare.py <first pass dir> <rerun dir>

Written after the exclusive rerun, so the columns beyond the pre-registered
ones are a reading aid, not a registered measure. Per tagged point it prints:
  - the ratio to the untagged baseline (minimum block) in each pass, and the
    added step time per tag in each pass;
  - the rerun's block spread over all five blocks (the registered measure),
    over blocks 3 to 5 only, and median over minimum;
  - the spread of the ratio to the baseline block by block, over all blocks
    and over blocks 3 to 5;
  - whether the point and its baseline ran on one node in the rerun;
  - "beyond" when the two passes' ratios differ by more than the rerun's own
    spread (amendment, section 7: then both are reported, and the less
    favourable ratio is quoted).
"""
import csv
import glob
import sys

import numpy as np


def load(root):
    rows = {}
    for f in sorted(glob.glob(root + "/*/*.csv")):
        if f.endswith("status.csv"):
            continue
        got = list(csv.DictReader(open(f)))
        if len(got) != 1:
            sys.exit(f"{f}: one row expected")
        r = got[0]
        r["blocks"] = np.array(r["step_ms_blocks"].split(";"), float)
        rows[r["label"]] = r
    return rows


def spread(x):
    return 100 * (x.max() / x.min() - 1)


first, rerun = load(sys.argv[1]), load(sys.argv[2])
base1 = {r["base"]: r for r in first.values() if r["ntags"] == "0"}
base2 = {r["base"]: r for r in rerun.values() if r["ntags"] == "0"}
print("| point | N | ratio pass 1 | ratio rerun | ms/tag pass 1 | ms/tag rerun | spread all | spread 3-5 "
      "| median/min | ratio spread all | ratio spread 3-5 | same node as baseline | passes |")
print("|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|:--|")
for label in sorted(rerun, key=lambda k: (rerun[k]["base"], rerun[k]["mode"], rerun[k]["precip"],
                                          rerun[k]["variant"], int(rerun[k]["ntags"]))):
    r2 = rerun[label]
    n = int(r2["ntags"])
    if n == 0:
        continue
    b2 = base2[r2["base"]]
    ratio2 = float(r2["step_ms_min"]) / float(b2["step_ms_min"])
    per2 = (float(r2["step_ms_min"]) - float(b2["step_ms_min"])) / n
    q = r2["blocks"] / b2["blocks"]
    s_all = spread(r2["blocks"])
    if label in first:
        r1, b1 = first[label], base1[r2["base"]]
        ratio1 = float(r1["step_ms_min"]) / float(b1["step_ms_min"])
        per1 = (float(r1["step_ms_min"]) - float(b1["step_ms_min"])) / n
        beyond = "beyond" if abs(ratio1 / ratio2 - 1) * 100 > s_all else "within"
        p1 = f"{ratio1:.3f} | ... | {per1:.3f}"
    else:
        p1, beyond = "n/a | ... | n/a", "rerun only"
    p1 = p1.replace("...", f"{ratio2:.3f}")
    short = label.replace(r2["family"] + "_wp9_", "")
    print(f"| {short} | {n} | {p1} | {per2:.3f} | {s_all:.1f}% | {spread(r2['blocks'][2:]):.1f}% "
          f"| {100 * (float(r2['step_ms_median']) / float(r2['step_ms_min']) - 1):.1f}% "
          f"| {spread(q):.1f}% | {spread(q[2:]):.1f}% | {'yes' if r2['host'] == b2['host'] else 'no'} | {beyond} |")
