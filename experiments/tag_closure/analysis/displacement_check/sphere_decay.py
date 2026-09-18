"""Residual-weighted loss rate on a sphere run (remapped lat-lon-z output).

rho is not output, so it is approximated as 1.2 exp(-z / 8 km); dz from the
level midpoints; area weights cos(lat). Good for an order of magnitude only.
"""
import sys
import numpy as np
from netCDF4 import Dataset

run = sys.argv[1]
regions = sys.argv[2].split(",")
procs = sys.argv[3].split(",")
ROOT = f"/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/{run}/output_active/" + "{}_1h_inst.nc"


def get(name):
    with Dataset(ROOT.format(name)) as ds:
        v = np.array(ds[name][:])
        dims = ds[name].dimensions
        lat = np.array(ds["lat"][:])
        z = np.array(ds["z"][:])
        t = np.array(ds["time"][:]) / 3600
    # to (time, lon, lat, z)
    order = [dims.index(d) for d in ("time", "lon", "lat", "z")]
    return np.transpose(v, order), lat, z, t


R, lat, z, t = get("e_src_res")
Em = R + sum(get("e_src_" + r)[0] for r in regions)
rec = {p: get("e_prc_" + p)[0] for p in procs}
edges = np.r_[0, 0.5 * (z[1:] + z[:-1]), 30000.0]
dz = np.diff(edges)
rho = 1.2 * np.exp(-z / 8000.0)
w0 = np.cos(np.deg2rad(lat))[None, :, None] * (rho * dz)[None, None, :]
print(f"{run}: hour, G~sum|R|w (arb), lamR 1/day, lamE 1/day, frac|R| above 10 km, frac|R| below 2 km")
for i in range(1, len(t) - 1):
    loss = sum(np.maximum(-(rec[p][i + 1] - rec[p][i]), 0) for p in procs)
    lam = loss / Em[i] * 24
    w = np.abs(R[i]) * w0
    wE = Em[i] * w0
    lamR = (w * lam).sum() / w.sum()
    lamE = (wE * lam).sum() / wE.sum()
    hi = w[:, :, z > 10000].sum() / w.sum()
    lo = w[:, :, z < 2000].sum() / w.sum()
    if i in (1, 2, 6, 12, 18, 23):
        print(f"{t[i]:4.0f} {w.sum():.4e} {lamR:.4f} {lamE:.4f} {hi:.2f} {lo:.2f}")
