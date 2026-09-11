# Where the tags' leftover residuals come from: the one-iteration Newton
# increment (FINDINGS E39). A reviewer agent wrote these scripts on 2026-09-11 and
# ran them on the terrabyte login node. Their outputs are in
# `output/newton_lag/`.
#
#   - `first_hour_0m.jl` steps C9's column one step at a time, in five variants:
#     one Newton iteration, a converged solve, no post-Newton upwind correction,
#     both, and a 5 s step.
#   - `c8_variants.jl` does the same for C8's 1M column. Only its first 60 audit
#     steps ran here, because the 1M build takes about 20 minutes on the login
#     node. `first_hour_sphere.jl` is the sphere's two-hour test. Both are meant
#     for short Slurm jobs.
#   - `formb_vs_flux.py`, `after_first_hour.py`, `signed_by_loss_rule.py` and
#     `sphere_levels.py` read the per-step tables and the runs' NetCDF.
#
# The paths inside point to the scratch directory they ran from. Change the output
# directory before running them again.

import netCDF4, numpy as np
root = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/"
def rd(run, name):
    ds = netCDF4.Dataset(root + run + "/output_active/" + name + "_1h_inst.nc")
    v = ds[name]; d = list(v.dimensions); a = np.moveaxis(np.array(v[:]), d.index("time"), 0); d.remove("time"); return a, tuple(["time"] + d), ds
# ---- column: is the residual's decay after 1 h the loss rule, dr = sum_p min(D_p,0) r / E ?
run = "c9_column_enthalpy"
r, dims, ds = rd(run, "e_src_res"); print(run, dims, r.shape)
z = np.array(ds["z"][:])
E = rd(run, "e_src_strat")[0] + rd(run, "e_src_tropo")[0] + r          # specific E = tags + residual
rec = {p: rd(run, "e_prc_" + p)[0] for p in ("radiation", "surface_flux", "subsidence", "microphysics")}
logpred = np.zeros_like(r)
for h in range(2, r.shape[0]):
    loss = sum(np.minimum(rec[p][h] - rec[p][h - 1], 0.0) for p in rec)
    logpred[h] = logpred[h - 1] + loss / (0.5 * (E[h] + E[h - 1]))
rho = rd(run, "rhoa")[0]; dz = 1500.0 / r.shape[1]
print(" level z   r(1h) J/kg   r(24h)     obs ratio  loss-rule ratio")
for k in range(r.shape[1]):
    if abs(r[1, k]) > 1e-3 * np.abs(r[1]).max():
        print(f"  {z[k]:6.0f}  {r[1,k]:+10.4f} {r[24,k]:+10.4f}   {r[24,k]/r[1,k]:8.4f}   {np.exp(logpred[24,k]):8.4f}")
for h in (1, 2, 6, 12, 24):
    pred = r[1] * np.exp(logpred[h]); obs = r[h]
    print(f" t={h:2d} h gross {np.sum(np.abs(rho[h]*obs))*dz:9.2f}  loss-rule prediction {np.sum(np.abs(rho[h]*pred))*dz:9.2f}  gross of (obs-pred) {np.sum(np.abs(rho[h]*(obs-pred)))*dz:8.2f}  signed obs {np.sum(rho[h]*obs)*dz:+8.2f} pred {np.sum(rho[h]*pred)*dz:+8.2f}")
# ---- sphere: is the residual frozen in place after 1 h?
run = "c9_sphere_enthalpy"
r, dims, ds = rd(run, "e_src_res"); print(run, dims, r.shape)
a = r[1].ravel()
for h in (2, 6, 12, 24):
    b = r[h].ravel()
    print(f" t={h:2d} h  corr(r(1h), r(t)) {np.corrcoef(a, b)[0,1]:.6f}  rms ratio {np.sqrt((b**2).mean()/(a**2).mean()):.5f}  rms(r(t)-r(1h))/rms(r(1h)) {np.sqrt(((b-a)**2).mean()/(a**2).mean()):.2e}")
zs = np.array(ds["z"][:]); axes = tuple(i for i, d in enumerate(dims[1:]) if d != "z")
lvl = np.abs(r[1]).mean(axis=axes)
print(" mean |r| at 1 h by level (J/kg):", " ".join(f"{zz/1000:.1f}km:{v:.3g}" for zz, v in zip(zs, lvl)))
