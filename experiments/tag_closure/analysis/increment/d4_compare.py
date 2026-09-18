"""Compare a D4 run of the increment prototype with a reference run of the same
atmosphere: the closure and audit tables hour by hour, G1's growth test, the
residual by layer, and whether `ta` and `rhoa` are bit for bit.

    python d4_compare.py <run> <reference run> [more runs ...]

Each run is a directory name under the tag-closure output root on scratch.
The first run is compared with the second; any further runs are only tabled.
"""
import csv
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
HOURS = [1, 2, 4, 8, 12, 16, 20, 24]


def output_dir(run):
    dirs = sorted(glob.glob(f"{ROOT}/{run}/output_0*"))
    if not dirs:
        sys.exit(f"no output for {run}")
    return dirs[-1]


def table(run, name):
    with open(f"{output_dir(run)}/energy_source_tag_{name}.csv") as f:
        rows = list(csv.DictReader(f))
    return {round(float(r["time"]) / 3600, 6): r for r in rows}


def field(run, name):
    with Dataset(f"{output_dir(run)}/{name}_1h_inst.nc") as ds:
        return np.array(ds[name][:]), np.array(ds["z"][:])


def value(rows, hour, column):
    row = rows.get(float(hour))
    return float(row[column]) if row and column in row else float("nan")


runs = sys.argv[1:]
closures = {run: table(run, "closure") for run in runs}
audits = {run: table(run, "audit") for run in runs}

print("gross residual, J/m²")
print("hour " + "".join(f"{run:>34}" for run in runs))
for hour in HOURS:
    print(
        f"{hour:4d} "
        + "".join(f"{value(closures[r], hour, 'gross_residual'):34.4e}" for r in runs)
    )
print("\nsigned residual, J/m²")
for hour in HOURS:
    print(
        f"{hour:4d} "
        + "".join(f"{value(closures[r], hour, 'residual'):34.4e}" for r in runs)
    )

print("\nG1 criterion 1, per run: gross at 24 h, and the second 12 h against the first")
for run in runs:
    g0, g12, g24 = (value(closures[run], h, "gross_residual") for h in (0, 12, 24))
    print(
        f"  {run}: gross(24 h) = {g24:.4e}, first 12 h +{g12 - g0:.4e}, "
        f"second 12 h {g24 - g12:+.4e}, "
        f"{'meets' if g24 <= 1e4 and g24 - g12 <= g12 - g0 else 'misses'} the target"
    )

print("\naudit at 24 h")
for run in runs:
    row = audits[run].get(24.0, {})
    keys = [
        k
        for k in row
        if k != "time" and not k.endswith("relative") and k != "source_minimum"
    ]
    print(f"  {run}: " + ", ".join(f"{k} {float(row[k]):.3e}" for k in keys))

print("\nresidual by layer at 24 h, gross (signed), J/m²")
for run in runs:
    res, z = field(run, "e_src_res")
    rho, _ = field(run, "rhoa")
    dz = np.gradient(z)
    t = min(24, res.shape[0] - 1)
    parts = []
    for label, mask in (
        ("<550 m", z < 550),
        ("550-800 m", (z >= 550) & (z < 800)),
        (">800 m", z >= 800),
    ):
        weight = (rho[t] * dz)[mask]
        parts.append(
            f"{label} {np.sum(np.abs(res[t][mask]) * weight):.3e} "
            f"({np.sum(res[t][mask] * weight):+.3e})"
        )
    print(f"  {run}: " + ", ".join(parts))

if len(runs) >= 2:
    a, b = runs[0], runs[1]
    print(f"\nthe model's fields, {a} against {b}")
    for name in ("ta", "rhoa"):
        x, _ = field(a, name)
        y, _ = field(b, name)
        same = x.shape == y.shape and np.array_equal(x, y, equal_nan=True)
        diff = np.nanmax(np.abs(x - y)) if x.shape == y.shape else float("nan")
        print(f"  {name}: {'bit for bit' if same else 'DIFFERS'} (max |diff| {diff:.3e}, shape {x.shape})")
