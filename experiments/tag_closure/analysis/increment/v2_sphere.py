"""G2: V2 on the sphere under the increment prototype.

    python v2_sphere.py <run> [hours between rows, default 24]

Reads the closure and audit tables and the hourly lat-lon-z NetCDF output.
Prints:

  - the closure over time, and whether its growth slows: the second half of
    the run against the first;
  - the audit: the zero-sum split, the repair, and the increment ledger;
  - the residual set against its loss rate, as E60 did. The loss rule removes
    `R/E` of every loss, so the residual obeys `dG/dt = P - λ_R·G`, with `G`
    the gross residual and `λ_R` the loss rate weighted by `|R|`. From the
    hourly records this gives the production `P` that the residual's growth
    implies, and the level `G* = P/λ_R` where the two would balance;
  - where the residual sits: above 10 km and below 2 km.

The fields are remapped to a lat-lon-z grid, so the integrals weight each
point by `rhoa`, the level spacing and `cos(lat)`. Good for rates and
fractions; the closure table has the exact integrals.
"""
import csv
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
REGIONS = ("tropics", "extratropics")
PROCESSES = ("radiation", "surface_flux", "microphysics", "precipitation")

run = sys.argv[1]
step = int(sys.argv[2]) if len(sys.argv) > 2 else 24
out = sorted(glob.glob(f"{ROOT}/{run}/output_0*"))[-1]


def table(name):
    with open(f"{out}/energy_source_tag_{name}.csv") as f:
        return list(csv.DictReader(f))


def get(name):
    with Dataset(f"{out}/{name}_1h_inst.nc") as ds:
        v = np.array(ds[name][:])
        dims = ds[name].dimensions
        lat = np.array(ds["lat"][:])
        # With topography the levels are terrain-following, `z_reference`.
        zname = "z_reference" if "z_reference" in ds.variables else "z"
        z = np.array(ds[zname][:])
        t = np.array(ds["time"][:]) / 3600
    order = [dims.index(d) for d in ("time", "lon", "lat", zname)]
    return np.transpose(v, order), lat, z, t


closure = table("closure")
audit = table("audit")
hours = [float(r["time"]) / 3600 for r in closure]
gross = [float(r["gross_residual"]) for r in closure]
relative = [float(r["gross_relative"]) for r in closure]
print(f"{run}: the closure, J and over the scale")
for h, g, r in zip(hours, gross, relative):
    if h % step == 0:
        print(f"  {h:6.0f} h  gross {g:.4e}  relative {r:.3e}")
if len(hours) > 2:
    half = hours[-1] / 2
    i_half = min(range(len(hours)), key=lambda i: abs(hours[i] - half))
    first, second = gross[i_half] - gross[0], gross[-1] - gross[i_half]
    print(
        f"  first half ({hours[i_half]:.0f} h) +{first:.3e}, second half {second:+.3e}: "
        f"{'slowing' if second <= first else 'NOT slowing'}"
    )

print("\nthe audit at the last row")
last = audit[-1]
for key in (
    "untagged",
    "overclaimed",
    "repair_moved",
    "increment_left",
    "increment_left_gross",
    "increment_moved_gross",
):
    if key in last:
        print(f"  {key:22s} {float(last[key]):+.4e}  ({float(last[key + '_relative']):+.3e} of the scale)")

R, lat, z, t = get("e_src_res")
rho = get("rhoa")[0]
E = R + sum(get("e_src_" + r)[0] for r in REGIONS)
records = {p: get("e_prc_" + p)[0] for p in PROCESSES}
edges = np.r_[0, 0.5 * (z[1:] + z[:-1]), 2 * z[-1] - 0.5 * (z[-1] + z[-2])]
dz = np.diff(edges)
area = np.cos(np.deg2rad(lat))[None, :, None]
print(
    "\nthe residual against its loss rate (E60); rates per day\n"
    "  hour   G (arb.)     dG/dt/G   λ_R      P/G      G*/G   |R| above 10 km, below 2 km"
)
G = [(np.abs(R[i]) * rho[i] * area * dz).sum() for i in range(len(t))]
for i in range(1, len(t) - 1):
    if t[i] % step != 0 and i != 1:
        continue
    loss = sum(np.maximum(-(records[p][i + 1] - records[p][i]), 0) for p in PROCESSES)
    rate = loss / np.where(E[i] > 0, E[i], np.inf) * 24
    w = np.abs(R[i]) * rho[i] * area * dz
    lam = (w * rate).sum() / w.sum()
    growth = (G[i + 1] - G[i - 1]) / (t[i + 1] - t[i - 1]) * 24 / G[i]
    production = growth + lam
    above = w[:, :, z > 10000].sum() / w.sum()
    below = w[:, :, z < 2000].sum() / w.sum()
    ratio = production / lam if lam > 0 else float("inf")
    print(
        f"  {t[i]:5.0f}  {G[i]:.4e}  {growth:+.4f}  {lam:.4f}  {production:+.4f}  "
        f"{ratio:7.2f}  {above:.2f}, {below:.2f}"
    )
