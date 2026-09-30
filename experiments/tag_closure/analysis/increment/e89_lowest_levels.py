"""E89, read after the score and not pre-registered: what the NetCDF tag fields
show at the lowest levels, fix arm against main arm, and whether the
partition tags, strat and tropo, reproduce the closure table's `tagged` column
when weighted by rho*dz. The other tags are source tags and count the sourced
energy again, so they are not summed.

    python3 e89_lowest_levels.py [OUTPUT_ROOT]

It reads `e_src_<tag>_1h_inst.nc`, `rhoa_1h_inst.nc` and
`energy_source_tag_closure.csv` of the two arms. The cell thickness is taken
from the level centres (equal spacing, 50 m on D4). It proposes no threshold.
"""
import csv
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
FIX, MAIN = "e89_d4_default_fix", "e89_d4_default_main"
TAGS = ["strat", "tropo", "rad", "sfc", "sub", "mp", "new_strat", "new_tropo"]


def read(job, var):
    with nc.Dataset(os.path.join(ROOT, job, "output_0000", f"{var}_1h_inst.nc")) as d:
        return np.asarray(d[var][:]), np.asarray(d["z"][:]), np.asarray(d["time"][:])


rho, z, time = read(MAIN, "rhoa")
zf = np.concatenate([[0], (z[1:] + z[:-1]) / 2, [z[-1] + (z[-1] - z[-2]) / 2]])
w = np.diff(zf)[:, None] * rho  # axes are (level, time)

print("lowest four levels, J/kg: fix, main, fix minus main")
for hour in (1, 24):
    print(f"hour {hour}")
    for tag in TAGS:
        a, _, _ = read(FIX, "e_src_" + tag)
        b, _, _ = read(MAIN, "e_src_" + tag)
        print(f"  {tag:10s} fix {np.round(a[:4, hour], 4)} main {np.round(b[:4, hour], 4)} diff {np.round((a - b)[:4, hour], 4)}")

print("strat + tropo, rho*dz-weighted over the column (J/m²), against the closure table's `tagged`")
PART = ["strat", "tropo"]
sums = {}
for job in (FIX, MAIN):
    s = sum(read(job, "e_src_" + t)[0] for t in PART)
    sums[job] = s
    closure = {float(r["time"]): float(r["tagged"]) for r in csv.DictReader(open(os.path.join(ROOT, job, "output_0000", "energy_source_tag_closure.csv")))}
    for hour in (0, 1, 12, 24):
        v = float(np.sum((s * w)[:, hour]))
        c = closure[float(time[hour])]
        print(f"  {job} hour {hour}: fields {v:.6e}, closure table {c:.6e}, ratio {v / c:.8f}")
for hour in (1, 12, 24):
    print(f"  fix minus main, strat + tropo, hour {hour}: {float(np.sum(((sums[FIX] - sums[MAIN]) * w)[:, hour])):.3e} J/m²")
