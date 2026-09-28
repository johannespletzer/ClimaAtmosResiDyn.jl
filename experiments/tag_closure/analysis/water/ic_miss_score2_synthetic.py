"""Synthetic inputs for ic_miss_score2.py, built from the first probe's CSV
(design/NEGATIVE_PARENT_WATER.md, section 9.7.6). It checks the score script's
parsing and flow only: the added columns and the levels are made up.

    python3 ic_miss_score2_synthetic.py OUTPUT_ROOT TEST_ROOT

OUTPUT_ROOT holds `ic_s23_c/` and `ic_miss_probe_s23/`. TEST_ROOT receives
links to both, and an `ic_miss_probe2_s23/output_0000/` with links to the
first probe's NetCDF and the two synthetic CSVs. Then:

    python3 ic_miss_score2.py TEST_ROOT
"""
import csv
import os
import random
import sys

ROOT, TEST = sys.argv[1], sys.argv[2]
FIRST = os.path.join(ROOT, "ic_miss_probe_s23", "output_0000")
OUT = os.path.join(TEST, "ic_miss_probe2_s23", "output_0000")
os.makedirs(OUT, exist_ok=True)
for name in ("ic_s23_c", "ic_miss_probe_s23"):
    link = os.path.join(TEST, name)
    if not os.path.lexists(link):
        os.symlink(os.path.join(ROOT, name), link)
for f in os.listdir(FIRST):
    if f.endswith(".nc") and not os.path.lexists(os.path.join(OUT, f)):
        os.symlink(os.path.join(FIRST, f), os.path.join(OUT, f))

with open(os.path.join(FIRST, "ic_miss_probe_s23_steps.csv")) as f:
    rows = list(csv.DictReader(f))
cols = list(rows[0].keys())
# The forcing's terms, as the first probe labels them.
terms = sorted({c[len("probe_"): -len("_total")] for c in cols
                if c.startswith("probe_forcing_") and c.endswith("_total")
                and c != "probe_forcing_total"})
without = [t.replace("forcing_", "forcing_without_") for t in terms]
parts = ("total", "N", "P", "X")
header = cols + [f"probe_{w}_{k}" for w in without for k in parts]
header += ["negative_water", "negative_water_relative", "latch",
           "ref_M5_up", "ref_M5_down", "probe_forcing_M5_up", "probe_forcing_M5_down"]
with open(os.path.join(OUT, "ic_miss_probe2_s23_steps.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(header)
    for r in rows:
        extra = [float(r[f"probe_forcing_{k}"]) - float(r[f"probe_{t}_{k}"]) for t in terms for k in parts]
        ref, forcing = float(r["ref_total"]), float(r["probe_forcing_total"])
        extra += [1e-3, 2e-4, 1.0, 0.4 * ref, 0.2 * ref, 0.5 * forcing, 0.3 * forcing]
        w.writerow([r[c] for c in cols] + extra)

random.seed(0)
quantities = ["ref", "ref_N", "ref_M5", "forcing"] + terms + without + ["forcing_M5"]
with open(os.path.join(OUT, "ic_miss_probe2_s23_levels.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["interval_start_days", "level", "z_m"] + quantities)
    for start in (30.25, 30.5, 30.75, 52.25, 52.5, 52.75, 53.0, 53.25):
        for k in range(60):
            w.writerow([start, k + 1, 30.0 * (k + 1)] + [random.random() * 1e-5 for _ in quantities])
print(f"synthetic inputs in {OUT}: {len(rows)} steps, {len(terms)} forcing terms")
