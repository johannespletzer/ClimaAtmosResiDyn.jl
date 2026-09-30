"""E89 (design/W25_ISOLATION.md, section 9): the energy source tags' plume start
on D4, the fix arm against the main arm, with the untagged twin.

    python3 e89_score.py [OUTPUT_ROOT]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output, with `e89_d4_default_fix`,
`e89_d4_default_main` and `e89_d4_untagged`, each in `output_0000`. It prints,
for each arm:

  - R1, parity: every field the untagged twin writes, bit for bit (the OD3 row
    "Parent validity: parity");
  - closure: the partition's gross residual over the window, against the
    window's gross source throughput, the audit's exact `source_throughput`
    (OD4). The OD3 row "Closure, energy" is 0.2% of it;

and, reported and not judged, each tag's change between the arms at 1 h and
24 h (the verifier, `compare_runs.py --family energy`, fix against main),
with the sign. The window is OD2's rule on the partitioned total of the main
arm, as G4.11 read it (`g411_eligibility.py`). Nothing is tuned after the
runs, and no threshold is new.
"""
import csv
import glob
import json
import os
import subprocess
import sys

import netCDF4 as nc
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
VERIFIER = os.path.join(HERE, "..", "evidence", "compare_runs.py")
CLOSURE_MAX = 2e-3
DAY = 86400.0


def out_dir(job):
    return os.path.join(ROOT, job, "output_0000")


def read_csv(job, name):
    path = os.path.join(out_dir(job), name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def at(rows, time, column):
    return next(r[column] for r in rows if abs(r["time"] - time) < 1e-6)


def startup_end(closure):
    t = np.array([r["time"] for r in closure])
    total = np.array([r["total"] for r in closure])
    tendency = np.abs(np.diff(total) / np.diff(t))
    peak = tendency[t[1:] <= 6 * 3600].max()
    below = tendency < 0.1 * peak
    for n in range(len(below) - 2):
        if below[n] and below[n + 1] and below[n + 2]:
            return t[n]
    return None


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def parity(untagged, job):
    names = sorted(os.path.basename(f) for f in glob.glob(f"{out_dir(untagged)}/*.nc"))
    differ = []
    for f in names:
        var = f.rsplit("_", 2)[0]
        other = os.path.join(out_dir(job), f)
        if not os.path.exists(other):
            differ.append(f"{var} (missing)")
            continue
        with nc.Dataset(f"{out_dir(untagged)}/{f}") as da, nc.Dataset(other) as db:
            a, b = np.asarray(da[var][:]), np.asarray(db[var][:])
        if not (a.shape == b.shape and np.array_equal(bits(a), bits(b))):
            differ.append(var)
    return len(names), differ


arms = ("e89_d4_default_fix", "e89_d4_default_main")
closure_main = read_csv("e89_d4_default_main", "energy_source_tag_closure.csv")
t0 = startup_end(closure_main) if closure_main else None
if closure_main and t0 is None:
    # As G4.11: where the rule finds no end, OD2's table's first hour for D4.
    t0 = 3600.0
    print("window: OD2's rule finds no end of startup; OD2's table's first hour is used")
print(f"window: startup ends at {t0} s; scored to {DAY} s")

for job in arms:
    n, differ = parity("e89_d4_untagged", job)
    verdict = "pass" if n and not differ else "fail"
    print(f"R1 {job}: {n} fields against e89_d4_untagged, {'bit for bit' if not differ else 'differ ' + ', '.join(differ)}: {verdict}")
    closure = read_csv(job, "energy_source_tag_closure.csv")
    audit = read_csv(job, "energy_source_tag_audit.csv")
    if closure is None or audit is None or t0 is None:
        print(f"closure {job}: not assessable (no output)")
        continue
    if "source_throughput" not in audit[0]:
        print(f"closure {job}: not assessable (no exact source_throughput in the audit)")
        continue
    scale = at(audit, DAY, "source_throughput") - at(audit, t0, "source_throughput")
    gross = at(closure, DAY, "gross_residual") - at(closure, t0, "gross_residual")
    ratio = gross / scale
    print(f"closure {job}: gross {gross:.4e} over throughput {scale:.4e} J/m² = {ratio:.3e} "
          f"(at most {CLOSURE_MAX:g}): {'pass' if ratio <= CLOSURE_MAX else 'fail'}")

path = os.path.join(HERE, "..", "..", "output", "e89", "verifier_fix_vs_main.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
subprocess.run(
    [sys.executable, VERIFIER, "--reference", out_dir("e89_d4_default_main"), "--run",
     out_dir("e89_d4_default_fix"), "--family", "energy", "--hours", "0,1,12,24", "--json", path],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
if os.path.exists(path):
    report = json.load(open(path))
    print("the rule's effect, reported and not judged (fix against main, L1 and L∞ relative to main):")
    for tag, hours in sorted(report["tag_metrics"].items()):
        cells = []
        for hour in ("1", "24"):
            m = hours.get(hour, {})
            cells.append(f"{hour} h L1 {m.get('L1_mass_weighted', 'n/a')}, L∞ {m.get('Linf_peak_normalized', 'n/a')}, "
                         f"absolute L1 {m.get('abs_L1', 'n/a')} J/m², integral change {m.get('rel_integral_change', 'n/a')}")
        print(f"  {tag}: " + "; ".join(cells))
else:
    print("the rule's effect: not assessable (verifier failed)")
