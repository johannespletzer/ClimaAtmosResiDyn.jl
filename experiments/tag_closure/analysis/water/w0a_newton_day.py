"""V-W0a: 1 against 10 Newton iterations on the precipitating 0M column.
Shares φ = q_tag/q_tot on each run's own atmosphere, weighted by the
reference's ρ Δz, against the parent's own change."""
import numpy as np, netCDF4 as nc
O = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
runs = {"n1": f"{O}/w0a_0m_newton1/output_0000", "n10": f"{O}/w0a_0m_newton10/output_0000"}
def read(run, var):
    with nc.Dataset(f"{runs[run]}/{var}_1h_inst.nc") as d:
        v = d[var][:]
        if d[var].dimensions == ("z", "time"):
            v = np.asarray(v).T
        t = d["time"][:]
        z = d["z"][:] if "z" in d.variables else None
    return np.asarray(v).squeeze(), np.asarray(t), z
rho, t, z = read("n10", "rhoa")
zc = np.asarray(z)
faces = np.concatenate([[0.0], 0.5 * (zc[1:] + zc[:-1]), [2 * zc[-1] - 0.5 * (zc[-1] + zc[-2])]])
dz = np.diff(faces)
hours = [1, 2, 6, 12, 24]
idx = {h: int(np.where(np.isclose(t, 3600 * h))[0][0]) for h in hours}
pr, _, _ = read("n10", "pr"); lwp, _, _ = read("n10", "lwp"); pr1, _, _ = read("n1", "pr")
print("precipitation pr (kg m-2 s-1) n10 at 1,6,12,24 h:", [f"{pr[idx[h]]:.3e}" for h in hours])
print("precipitation pr n1  at 1,6,12,24 h:", [f"{pr1[idx[h]]:.3e}" for h in hours])
print("lwp n10:", [f"{lwp[idx[h]]:.3e}" for h in hours])
for var in ["hus", "ta", "rhoa", "clw"]:
    a, _, _ = read("n10", var); b, _, _ = read("n1", var)
    row = []
    for h in hours:
        i = idx[h]; w = rho[i] * dz
        den = np.sum(np.abs(a[i]) * w)
        row.append(np.sum(np.abs(b[i] - a[i]) * w) / den if den > 0 else np.nan)
    print(f"parent {var:5s} L1(n1 vs n10):", [f"{x:.2e}" for x in row])
hus10, _, _ = read("n10", "hus"); hus1, _, _ = read("n1", "hus")
for tag in ["tropo", "strat", "evap"]:
    a, _, _ = read("n10", f"q_tag_{tag}"); b, _, _ = read("n1", f"q_tag_{tag}")
    out = []
    for h in hours:
        i = idx[h]; w = rho[i] * dz
        phia = a[i] / hus10[i]; phib = b[i] / hus1[i]
        l1_share = np.sum(np.abs(phib - phia) * hus10[i] * w) / np.sum(np.abs(phia) * hus10[i] * w)
        l1_mass = np.sum(np.abs(b[i] - a[i]) * w) / np.sum(np.abs(a[i]) * w)
        linf = np.max(np.abs(b[i] - a[i])) / np.max(np.abs(a[i]))
        share = np.sum(a[i] * w) / np.sum(hus10[i] * w)
        out.append(f"{h}h S={share:.3f} L1φ={l1_share:.2e} L1={l1_mass:.2e} L∞={linf:.2e}")
    print(f"tag {tag:5s}:", " | ".join(out))
