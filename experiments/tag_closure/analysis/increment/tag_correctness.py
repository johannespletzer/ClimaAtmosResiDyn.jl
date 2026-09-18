"""G1, criterion 4: each tag of a run against a reference run of the same
atmosphere, pointwise.

    python tag_correctness.py <reference run> <run> [hours, default 1,6,12,24]

Runs are directory names under the tag-closure output root on scratch. For each
tag and hour it prints the tag's column integral in the reference, the relative
difference of the integrals, the L1 difference `∫ρ|Δe|dz / ∫ρ|e_ref|dz`, and
the largest pointwise difference over the reference's largest value. First it
checks whether the two runs share their atmosphere: `ta` and `rhoa` equal, or
how far apart they are.
"""
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
TAGS = ["rad", "sfc", "sub", "mp", "strat", "tropo", "new_strat", "new_tropo"]


def get(run, name):
    path = sorted(glob.glob(f"{ROOT}/{run}/output_0*/{name}_1h_inst.nc"))[-1]
    with Dataset(path) as ds:
        # The files hold (z, time); rows are times here.
        return (
            np.array(ds[name][:]).T,
            np.array(ds["z"][:]),
            np.array(ds["time"][:]) / 3600,
        )


ref, run = sys.argv[1], sys.argv[2]
hours = [int(h) for h in (sys.argv[3] if len(sys.argv) > 3 else "1,6,12,24").split(",")]

for name in ("ta", "rhoa"):
    a, _, ta = get(ref, name)
    b, _, tb = get(run, name)
    n = min(len(ta), len(tb))
    same = np.array_equal(a[:n], b[:n], equal_nan=True)
    rel = np.max(np.abs(b[:n] - a[:n]) / np.abs(a[:n]))
    print(f"{name}: {'bit for bit' if same else f'max relative difference {rel:.2e}'} over {n} hours")

rho, z, t = get(ref, "rhoa")
dz = np.gradient(z)
print(
    f"\n{'tag':10s} {'hour':>4s} {'∫ref J/m²':>12s} {'Δ∫/∫':>10s} {'L1':>9s} {'L∞':>9s}"
)
for h in hours:
    i = int(np.argmin(np.abs(t - h)))
    w = rho[i] * dz
    for tag in TAGS:
        try:
            a = get(ref, "e_src_" + tag)[0][i]
            b = get(run, "e_src_" + tag)[0][i]
        except (IndexError, OSError):
            continue
        integral_a, integral_b = np.sum(a * w), np.sum(b * w)
        l1 = np.sum(np.abs(b - a) * w) / max(np.sum(np.abs(a) * w), 1e-300)
        linf = np.max(np.abs(b - a)) / max(np.max(np.abs(a)), 1e-300)
        change = (integral_b - integral_a) / integral_a if integral_a else float("nan")
        print(
            f"{tag:10s} {h:4d} {integral_a:12.4e} {change:+10.2e} {l1:9.2e} {linf:9.2e}"
        )
    print()
