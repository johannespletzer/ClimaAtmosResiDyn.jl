"""Known issue 7, option C: where site 23's closure miss sits (reported after
V2 failed; design/NEGATIVE_PARENT_WATER.md section 8.3 leaves the reading to
the ledgers and the owner).

    python3 ic_overclaim_where.py [OUTPUT_ROOT]

From `ic_s23_c`'s daily output: the region tags' excess over the target,
`max(q_tag_pbl + q_tag_free − max(q_tot, 0), 0)`, weighted by ρΔz and over
the column's `∫ρ max(q_tot, 0)`, split into cells where `q_tot ≤ 0` (the
target is zero there, so any region tag is excess) and cells where it is
positive. The split is printed at every day the closure table's gross exceeds
0.2%, with the closure table's gross beside it as a check on the weights.
Then the ten largest 6-hourly rises of the excess against every ledger's
change in the same cells. Weights as in `lr_rule_metrics.py`: faces rebuilt
from the cell centres and checked against `z_max`.
"""
import csv
import os
import re
import sys

import netCDF4
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
RUN = "ic_s23_c"
OUT = os.path.join(ROOT, RUN, "output_0000")
DAY = 86400.0


def read(name, period="1d"):
    path = os.path.join(OUT, f"{name}_{period}_inst.nc")
    if not os.path.exists(path):
        raise SystemExit(f"FAIL: missing {path}")
    with netCDF4.Dataset(path) as d:
        v = np.asarray(d[name][:])
        v = np.moveaxis(v, d[name].dimensions.index("time"), 0)
        return np.asarray(d["time"][:]), v.reshape(v.shape[0], -1), np.asarray(d["z"][:])


def thickness(z):
    with open(os.path.join(OUT, f"{RUN}.yml")) as f:
        m = re.search(r'^z_max:\s*"?([0-9.eE+-]+)', f.read(), re.M)
    top = float(m.group(1))
    faces = [0.0]
    for c in z:
        faces.append(2 * c - faces[-1])
    dz = np.diff(faces)
    if not (np.all(dz > 0) and abs(faces[-1] - top) <= 1e-6 * top):
        raise SystemExit(f"FAIL: faces end at {faces[-1]}, z_max {top}")
    return dz


def main():
    t, q, z = read("hus")
    _, rho, _ = read("rhoa")
    region = read("q_tag_pbl")[1] + read("q_tag_free")[1]
    w = rho * thickness(z)
    target = np.maximum(q, 0)
    scale = np.sum(w * target, axis=1)
    excess = w * np.maximum(region - target, 0)
    negative = q <= 0
    with open(os.path.join(OUT, "water_tag_closure.csv")) as f:
        gross = {round(float(r["time"]) / DAY, 6): float(r["gross_relative"]) for r in csv.DictReader(f)}
    print("day | closure gross | excess, all | in q_tot<=0 cells | in q_tot>0 cells | cells q_tot<=0 | their heights (m)")
    worst = (0.0, None)
    for k in range(len(t)):
        day = round(t[k] / DAY, 6)
        g = gross.get(day)
        if g is None or g <= 2e-3:
            continue
        all_, neg = excess[k].sum() / scale[k], (excess[k] * negative[k]).sum() / scale[k]
        heights = f"{z[negative[k]].min():.0f}-{z[negative[k]].max():.0f}" if negative[k].any() else "-"
        print(f"{day:g} | {g:.3e} | {all_:.3e} | {neg:.3e} | {all_ - neg:.3e} | {int(negative[k].sum())} | {heights}")
        worst = max(worst, (all_, day))
    over = [k for k in range(len(t)) if gross.get(round(t[k] / DAY, 6), 0) > 2e-3]
    share = np.array([(excess[k] * negative[k]).sum() / excess[k].sum() for k in over])
    print(f"days over 0.2%: {len(over)}; share of the excess in q_tot<=0 cells: "
          f"median {np.median(share):.2f}, range {share.min():.2f} to {share.max():.2f}; worst daily excess {worst[0]:.3e} on day {worst[1]:g}")
    ledgers_at_rises()


LEDGERS = ("q_tag_inc_negative", "q_tag_inc_moved", "q_tag_led_repair", "q_tag_led_fix_pbl", "q_tag_led_fix_free")


def ledgers_at_rises(count=10):
    """The ten largest 6-hourly rises of the excess, and beside each, every
    ledger's change over the same interval in the cells holding an excess at
    its end, `Σ |Δ(ρΔz L)|` over the target's integral. A rise that no ledger
    matches in size was carried by none of them."""
    t, q, z = read("hus", "6h")
    _, rho, _ = read("rhoa", "6h")
    region = read("q_tag_pbl", "6h")[1] + read("q_tag_free", "6h")[1]
    w = rho * thickness(z)
    target = np.maximum(q, 0)
    scale = np.sum(w * target, axis=1)
    excess = w * np.maximum(region - target, 0)
    fraction = excess.sum(axis=1) / scale
    ledger = {name: w * read(name, "6h")[1] for name in LEDGERS}
    rise = np.diff(fraction)
    print(f"\nthe {count} largest 6-hourly rises of the excess; per ledger, its change in the cells with an excess at the end")
    print("interval (days) | rise | excess at end | " + " | ".join(n.removeprefix("q_tag_") for n in LEDGERS) + " | largest ledger over the rise")
    for k in sorted(np.argsort(rise)[::-1][:count]):
        cells = excess[k + 1] > 0
        changes = [np.sum(np.abs(ledger[n][k + 1] - ledger[n][k]) * cells) / scale[k + 1] for n in LEDGERS]
        print(f"{t[k] / DAY:.2f}-{t[k + 1] / DAY:.2f} | {rise[k]:.2e} | {fraction[k + 1]:.2e} | "
              + " | ".join(f"{c:.2e}" for c in changes) + f" | {max(changes) / rise[k]:.2g}")


if __name__ == "__main__":
    main()
