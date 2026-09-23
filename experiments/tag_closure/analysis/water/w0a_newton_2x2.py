"""V-W0a's 2x2: for implicit and for explicit microphysics, how far 1 Newton
iteration is from 10, in the parent and in the tags' shares, over the rain-out
of the initial cloud. Weights: the 10-iteration run's ρ Δz."""
import csv, numpy as np, netCDF4 as nc
O = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
def path(mp, n): return f"{O}/w0a_0m_{mp}_newton{n}_2h/output_0000"
def read(mp, n, var):
    with nc.Dataset(f"{path(mp, n)}/{var}_5m_inst.nc") as d:
        v = np.asarray(d[var][:]); t = np.asarray(d["time"][:])
        dims = d[var].dimensions; z = np.asarray(d["z"][:]) if "z" in d.variables else None
    if dims[:2] == ("z", "time"): v = v.T
    return v, t, z
import glob, os
print("files:", sorted(os.path.basename(f) for f in glob.glob(path("implicit", 1) + "/*.nc"))[:6])

rho, t, zc = read("implicit", 10, "rhoa")
faces = np.concatenate([[0.0], 0.5 * (zc[1:] + zc[:-1]), [2 * zc[-1] - 0.5 * (zc[-1] + zc[-2])]])
dz = np.diff(faces)
minutes = [6, 18, 30, 60, 120]
idx = {m: int(np.where(np.isclose(t, 60 * m))[0][0]) for m in minutes}
for mp in ("implicit", "explicit"):
    pr, _, _ = read(mp, 10, "pr"); lwp, _, _ = read(mp, 10, "lwp")
    print(f"\n== {mp} microphysics (10 iterations): lwp kg/m2 at 0,18,30,60 min:",
          [f"{lwp[i]:.3e}" for i in (0, idx[18], idx[30], idx[60])],
          " pr kg/m2/s:", [f"{pr[idx[m]]:.2e}" for m in (6, 18, 30, 60)])
    # Rain-out over the first hour, from the closure table's total and the surface flux is not separable here;
    for var in ("hus", "ta"):
        a, _, _ = read(mp, 10, var); b, _, _ = read(mp, 1, var)
        vals = [np.sum(np.abs(b[idx[m]] - a[idx[m]]) * rho[idx[m]] * dz) / np.sum(np.abs(a[idx[m]]) * rho[idx[m]] * dz) for m in minutes]
        print(f"  parent {var}: L1(1 vs 10) at", minutes, "min:", [f"{v:.2e}" for v in vals])
    hus10, _, _ = read(mp, 10, "hus"); hus1, _, _ = read(mp, 1, "hus")
    for tag in ("tropo", "strat", "evap"):
        a, _, _ = read(mp, 10, f"q_tag_{tag}"); b, _, _ = read(mp, 1, f"q_tag_{tag}")
        vals = []
        for m in minutes:
            i = idx[m]; w = rho[i] * dz
            phia = a[i] / hus10[i]; phib = b[i] / hus1[i]
            vals.append(np.sum(np.abs(phib - phia) * hus10[i] * w) / np.sum(np.abs(phia) * hus10[i] * w))
        print(f"  tag {tag:5s} share L1φ(1 vs 10):", [f"{v:.2e}" for v in vals])
    for n in (1, 10):
        rows = list(csv.DictReader(open(f"{path(mp, n)}/water_tag_closure.csv")))
        g = {round(float(r["time"]) / 60): float(r["gross_relative"]) for r in rows}
        print(f"  closure gross_relative, {n:2d} it., at", minutes, "min:", [f"{g.get(m, float('nan')):.2e}" for m in minutes])
