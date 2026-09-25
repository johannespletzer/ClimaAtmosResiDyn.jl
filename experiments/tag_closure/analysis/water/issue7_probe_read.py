"""Known issue 7's probe, read as design/NEGATIVE_PARENT_WATER.md section 5
pre-registers it.

    python3 issue7_probe_read.py [OUTPUT_ROOT] [OUT_DIR]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds
`lr_s23_probe_ledgers/output_0000` (job 13932689) and its untagged twin
`lr_s23_untagged/output_0001`. OUT_DIR (default this record's
`output/issue7_probe/`) receives:
  - `validity.csv`: `rhoa`, `ta`, `hus` at the daily outputs of days 1 to 20,
    bit for bit against the twin, as `lr_parity.py` compares them;
  - `rates.csv`: per 6-hour interval from day 5 to day 20, per ledger and
    cell set, the rate in kg m^-2 day^-1;
  - `readings.csv`: per ledger and set, the baseline (days 5 to 8), the rate
    over days 10 to 20, their ratio, whether it grows (10 times), and the
    first interval at which it passes 10 times its baseline.

The cell sets, per interval: N, where `hus < 0` at either end; P, the rest.
P is also split, as a supplement the pre-registration does not define, into
the cells next to an N cell (P_adj) and the rest (P_far), because option C's
row reads "in or next to N".

A rate is the interval's increment of a per-step gross ledger times `ρΔz`,
summed over the set, per day. `ρ` is the mean of the interval's two ends, and
`Δz` comes from the centres as the verifier rebuilds it. The overclaim is
`(q_pbl + q_free − hus)⁺ ρΔz` at the interval's end, summed over the set; it
is a stock, and its "rate" here is its mean over the window.
"""
import csv
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "issue7_probe")
PROBE = os.path.join(ROOT, "lr_s23_probe_ledgers", "output_0000")
TWIN = os.path.join(ROOT, "lr_s23_untagged", "output_0001")
DAY = 86400.0
TAGS = ("pbl", "free", "evap", "fcg")
PARTITION = ("pbl", "free")
LEDGERS = {
    "rescale": "q_tag_led_rescale_gross",
    "empty": "q_tag_led_empty_gross",
    "repair": "q_tag_led_repair_gross",
    "repairnet": "q_tag_led_repairnet_gross",
    "inc_left": "q_tag_inc_left_gross",
    "inc_moved": "q_tag_inc_moved_gross",
    **{f"led_fix_{t}": f"q_tag_led_fixgross_{t}" for t in TAGS},
    **{f"led_inc_{t}": f"q_tag_led_incgross_{t}" for t in TAGS},
}
# The option each ledger's growth points to (section 5's table).
KIND = {
    "rescale": "B", "empty": "B", "repair": "B", "repairnet": "B",
    "inc_left": "C", "inc_moved": "C",
    **{f"led_inc_{t}": "C" for t in TAGS},
    **{f"led_fix_{t}": "B" for t in TAGS},
}
SETS = ("N", "P", "P_adj", "P_far")


def read(directory, name, period):
    with nc.Dataset(os.path.join(directory, f"{name}_{period}_inst.nc")) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:]), v.dimensions.index("time"), 0)
        return np.asarray(d["time"][:]), np.asarray(d["z"][:]), values


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


os.makedirs(OUT, exist_ok=True)

# --- Validity -------------------------------------------------------------
valid = True
with open(os.path.join(OUT, "validity.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["field", "days_compared", "bit_for_bit", "max_abs_diff"])
    for name in ("rhoa", "ta", "hus"):
        tp, zp, vp = read(PROBE, name, "1d")
        tt, zt, vt = read(TWIN, name, "1d")
        days = [k for k, t in enumerate(tp) if 1 * DAY - 1 <= t <= 20 * DAY + 1]
        same = np.array_equal(bits(zp), bits(zt))
        worst = 0.0
        for k in days:
            j = np.nonzero(tt == tp[k])[0]
            if len(j) != 1:
                same = False
                continue
            a, b = vp[k], vt[j[0]]
            same &= a.shape == b.shape and np.array_equal(bits(a), bits(b))
            worst = max(worst, float(np.max(np.abs(a - b))))
        valid &= same and len(days) == 20
        w.writerow([name, len(days), same, worst])
print("validity:", "bit for bit, days 1 to 20" if valid else "NOT bit for bit: the probe is void")

# --- Rates ----------------------------------------------------------------
t, z, hus = read(PROBE, "hus", "6h")
_, _, rho = read(PROBE, "rhoa", "6h")
faces = np.zeros(len(z) + 1)
for k in range(len(z)):
    faces[k + 1] = 2 * z[k] - faces[k]
dz = np.diff(faces)
assert np.all(dz > 0)
ledgers = {key: read(PROBE, name, "6h")[2] for key, name in LEDGERS.items()}
tags = {tag: read(PROBE, f"q_tag_{tag}", "6h")[2] for tag in PARTITION}

intervals = [k for k in range(len(t) - 1) if t[k] >= 5 * DAY - 1 and t[k + 1] <= 20 * DAY + 1]
rate_rows = []
series = {(key, s): [] for key in list(LEDGERS) + ["overclaim"] for s in SETS}
for k in intervals:
    negative = (hus[k] < 0) | (hus[k + 1] < 0)
    adjacent = np.zeros_like(negative)
    adjacent[1:] |= negative[:-1]
    adjacent[:-1] |= negative[1:]
    adjacent &= ~negative
    masks = {"N": negative, "P": ~negative, "P_adj": adjacent, "P_far": ~negative & ~adjacent}
    weight = 0.5 * (rho[k] + rho[k + 1]) * dz
    days = (t[k + 1] - t[k]) / DAY
    over = np.maximum(sum(tags[g][k + 1] for g in PARTITION) - hus[k + 1], 0) * rho[k + 1] * dz
    for s, m in masks.items():
        for key, L in ledgers.items():
            r = float(np.sum((L[k + 1] - L[k])[m] * weight[m]) / days)
            series[(key, s)].append((t[k], r))
            rate_rows.append([t[k] / DAY, s, key, r, int(m.sum())])
        o = float(np.sum(over[m]))
        series[("overclaim", s)].append((t[k], o))
        rate_rows.append([t[k] / DAY, s, "overclaim", o, int(m.sum())])

with open(os.path.join(OUT, "rates.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["interval_start_day", "set", "quantity", "rate_kg_m2_per_day_or_stock_kg_m2", "cells"])
    w.writerows(rate_rows)

# --- Readings -------------------------------------------------------------
def window_mean(values, lo, hi):
    kept = [r for (tk, r) in values if lo * DAY - 1 <= tk and tk + 6 * 3600 <= hi * DAY + 1]
    return float(np.mean(kept)) if kept else float("nan")


readings = []
for (key, s), values in series.items():
    base = window_mean(values, 5, 8)
    late = window_mean(values, 10, 20)
    ratio = late / base if base > 0 else (float("inf") if late > 0 else float("nan"))
    grows = bool(late >= 10 * base and late > 0)
    first = next((tk / DAY for tk, r in values if tk >= 5 * DAY - 1 and r > 0 and r >= 10 * base), None)
    readings.append(dict(quantity=key, set=s, option=KIND.get(key, "-"), baseline=base, rate_10_20=late,
                         ratio=ratio, grows=grows, first_day=first))
with open(os.path.join(OUT, "readings.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(readings[0].keys()))
    w.writeheader()
    w.writerows(readings)

for s in SETS:
    print(f"== {s}")
    for r in sorted((r for r in readings if r["set"] == s), key=lambda r: (r["first_day"] is None, r["first_day"] or 0)):
        print(f"   {r['quantity']:14} base {r['baseline']:.3e} late {r['rate_10_20']:.3e} "
              f"ratio {r['ratio']:.3e} grows {r['grows']!s:5} first {r['first_day']}")
