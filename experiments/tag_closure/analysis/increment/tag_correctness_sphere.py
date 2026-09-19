"""G2: each tag of a sphere run against a reference run, pointwise, as
`tag_correctness.py` does on a column (E66).

    python tag_correctness_sphere.py <reference run> <run> [hours, default 1,6,12,24]

For V2 the reference is its twin with ten fixed Newton iterations, and the
comparison measures the one-iteration solve's effect on the tags. The two
atmospheres drift apart, so it first prints how far: `ta`'s largest
difference and `E`'s L1 difference. Early on these are small, and the tags'
differences are then the solve's.

Integrals weight each point of the lat-lon-z output by `rhoa`, the level
spacing and `cos(lat)`.
"""
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
TAGS = ["rad", "sfc", "mp", "tropics", "extratropics", "new_tropics", "new_extratropics"]


def get(run, name):
    path = sorted(glob.glob(f"{ROOT}/{run}/output_0*/{name}_1h_inst.nc"))[-1]
    with Dataset(path) as ds:
        v = np.array(ds[name][:])
        dims = ds[name].dimensions
        zname = "z_reference" if "z_reference" in ds.variables else "z"
        lat = np.array(ds["lat"][:])
        z = np.array(ds[zname][:])
        t = np.array(ds["time"][:]) / 3600
    order = [dims.index(d) for d in ("time", "lon", "lat", zname)]
    return np.transpose(v, order), lat, z, t


ref, run = sys.argv[1], sys.argv[2]
hours = [int(h) for h in (sys.argv[3] if len(sys.argv) > 3 else "1,6,12,24").split(",")]

rho, lat, z, t = get(ref, "rhoa")
edges = np.r_[0, 0.5 * (z[1:] + z[:-1]), 2 * z[-1] - 0.5 * (z[-1] + z[-2])]
dz = np.diff(edges)
area = np.cos(np.deg2rad(lat))[None, :, None]
ta_a, ta_b = get(ref, "ta")[0], get(run, "ta")[0]
E_a = sum(get(ref, "e_src_" + n)[0] for n in ("tropics", "extratropics", "res"))
E_b = sum(get(run, "e_src_" + n)[0] for n in ("tropics", "extratropics", "res"))

print(f"{run} against {ref}")
print(f"{'tag':17s} {'hour':>4s} {'∫ref':>11s} {'Δ∫/∫':>10s} {'L1':>9s} {'L∞':>9s}")
for h in hours:
    i = int(np.argmin(np.abs(t - h)))
    if abs(t[i] - h) > 0.01:
        continue
    w = rho[i] * area * dz
    E_l1 = np.sum(np.abs(E_b[i] - E_a[i]) * w) / np.sum(np.abs(E_a[i]) * w)
    print(
        f"{'(atmosphere)':17s} {h:4d}   ta max diff {np.max(np.abs(ta_b[i] - ta_a[i])):.3f} K, "
        f"E L1 {E_l1:.2e}"
    )
    for tag in TAGS:
        try:
            a = get(ref, "e_src_" + tag)[0][i]
            b = get(run, "e_src_" + tag)[0][i]
        except (IndexError, OSError):
            continue
        if not np.any(a) and not np.any(b):
            print(f"{tag:17s} {h:4d}   zero in both")
            continue
        integral_a, integral_b = np.sum(a * w), np.sum(b * w)
        l1 = np.sum(np.abs(b - a) * w) / max(np.sum(np.abs(a) * w), 1e-300)
        linf = np.max(np.abs(b - a)) / max(np.max(np.abs(a)), 1e-300)
        change = (integral_b - integral_a) / integral_a if integral_a else float("nan")
        print(f"{tag:17s} {h:4d} {integral_a:11.3e} {change:+10.2e} {l1:9.2e} {linf:9.2e}")
    print()
