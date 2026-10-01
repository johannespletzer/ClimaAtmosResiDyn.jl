"""Synthetic inputs for cr_windows_score.py, built from W48's probe
(design/NEGATIVE_PARENT_WATER.md, section 11.7, item 7 of the score scripts'
changes). It checks W5's parsing and verdicts only. The per-step `ref_total`
is made up, so that the sums are exact, and the probe's forcing columns are
zeroed so that W1 and W2 pass and only W5 decides.

    python3 cr_windows_score_synthetic.py OUTPUT_ROOT TEST_ROOT

OUTPUT_ROOT holds `ic_miss_probe2_s23/output_0000/` (W48's probe). TEST_ROOT
receives `ic_miss_probe2_s23/` and `cr_probe_s23/`, both with links to W48's
NetCDF files (so W0 passes) and their own steps CSV. Then it runs the score
script (`CR_SCRIPT_DIR` names another copy of it, for a mutant) and checks the
verdicts it printed:

  rise 30.50-30.75  R = 0.05 R48   W5 passes
  rise 30.75-31.00  R = 0.10 R48   W5 passes (the tolerance is inclusive)
  rise 52.50-52.75  R = 0.15 R48   W5 fails
  rise 52.75-53.00  R48 = 0        W5 fails (cannot be scored)
  rise 53.00-53.25  R = -1 R48     W5 passes (the rise is gone)

and the script exits 1, since W5 fails twice. Exit 0 here means all checks hold.
"""
import csv
import os
import subprocess
import sys

ROOT, TEST = sys.argv[1], sys.argv[2]
HERE = os.environ.get("CR_SCRIPT_DIR", os.path.dirname(os.path.abspath(__file__)))
W48 = os.path.join(ROOT, "ic_miss_probe2_s23", "output_0000")
DAY = 86400.0
# (start, end, factor of the probe's per-step ref_total over W48's, W48's per-step ref_total, expect W5 pass)
CASES = [
    (30.50, 30.75, 0.05, 10.0, True),
    (30.75, 31.00, 0.10, 10.0, True),
    (52.50, 52.75, 0.15, 10.0, False),
    (52.75, 53.00, 1.00, 0.0, False),
    (53.00, 53.25, -1.0, 10.0, True),
]

dirs = {}
for name in ("ic_miss_probe2_s23", "cr_probe_s23"):
    dirs[name] = os.path.join(TEST, name, "output_0000")
    os.makedirs(dirs[name], exist_ok=True)
    for f in os.listdir(W48):
        if f.endswith(".nc"):
            link = os.path.join(dirs[name], f)
            if not os.path.lexists(link):
                os.symlink(os.path.join(W48, f), link)

with open(os.path.join(W48, "ic_miss_probe2_s23_steps.csv")) as f:
    reader = csv.DictReader(f)
    header = reader.fieldnames
    rows = list(reader)
zeroed = ("probe_forcing_total", "probe_forcing_M5_up", "probe_forcing_M5_down")
assert all(c in header for c in zeroed + ("ref_total",)), "W48's steps CSV lacks a column"
with open(os.path.join(dirs["ic_miss_probe2_s23"], "ic_miss_probe2_s23_steps.csv"), "w", newline="") as f48, \
        open(os.path.join(dirs["cr_probe_s23"], "cr_probe_s23_steps.csv"), "w", newline="") as fcr:
    w48, wcr = csv.DictWriter(f48, header), csv.DictWriter(fcr, header)
    w48.writeheader()
    wcr.writeheader()
    for r in rows:
        t = float(r["t_seconds"])
        ref48, factor = 10.0, 1.0
        for a, b, fac, per, _ in CASES:
            if a * DAY < t <= b * DAY + 1e-6:
                ref48, factor = per, fac
        r48 = dict(r, ref_total=repr(ref48))
        rcr = dict(r, ref_total=repr(ref48 * factor), **{c: "0.0" for c in zeroed})
        w48.writerow(r48)
        wcr.writerow(rcr)

res = subprocess.run([sys.executable, os.path.join(HERE, "cr_windows_score.py"), TEST], capture_output=True, text=True)
print(res.stdout)
print(res.stderr[-2000:] if res.stderr else "")
bad = []
for a, b, _, _, ok in CASES:
    rule = f"W5 {a}-{b}"
    in_failed = f"'{rule}'" in res.stdout.split("RESULT", 1)[-1]
    if in_failed == ok:
        bad.append(f"{rule}: expected {'pass' if ok else 'FAIL'}, the script's RESULT says the opposite")
for rule in ("W0", "W1 30.3-31.0", "W1 52.4-53.3", "W2 30.5-30.75", "W2 30.75-31.0", "W2 52.5-52.75", "W2 53.0-53.25"):
    if f"'{rule}'" in res.stdout.split("RESULT", 1)[-1]:
        bad.append(f"{rule} failed, but only W5 should decide")
if "W2 52.75-53.0" not in res.stdout.split("RESULT", 1)[-1]:
    bad.append("W2 52.75-53.0 should fail too: its share divides by R48 = 0")
if res.returncode != 1:
    bad.append(f"the script should exit 1, it exited {res.returncode}")
print("SYNTHETIC", "all checks hold" if not bad else "FAILED: " + "; ".join(bad))
sys.exit(1 if bad else 0)
