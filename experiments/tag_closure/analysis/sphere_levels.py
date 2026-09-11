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

# Which levels carry the sphere audit's 1 h residual, mass-weighted? rho from ta by hydrostatic balance (dry, approximate).
import netCDF4, numpy as np
root = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/c9_sphere_enthalpy/output_active/"
def rd(name):
    ds = netCDF4.Dataset(root + name + "_1h_inst.nc"); v = ds[name]; d = list(v.dimensions)
    return np.moveaxis(np.array(v[:]), d.index("time"), 0), ds
r, ds = rd("e_src_res"); ta, _ = rd("ta")
z = np.array(ds["z"][:]); lat = np.array(ds["lat"][:])
faces = np.concatenate([[0.0], 0.5 * (z[1:] + z[:-1]), [30000.0]]); dz = np.diff(faces)
g, Rd = 9.81, 287.0
T = ta[1]                                   # (z, lat, lon)
p = np.empty_like(T); p[0] = 1e5 * np.exp(-g * z[0] / (Rd * T[0]))
for k in range(1, len(z)):
    p[k] = p[k - 1] * np.exp(-g * (z[k] - z[k - 1]) / (Rd * 0.5 * (T[k] + T[k - 1])))
rho = p / (Rd * T)
w = np.cos(np.deg2rad(lat))[None, :, None]
contrib = (np.abs(r[1]) * rho * dz[:, None, None] * w).sum(axis=(1, 2))
share = contrib / contrib.sum()
print(" level z(km)  dz(km)  mean|r| J/kg   share of mass-weighted gross at 1 h")
for k in range(len(z)):
    print(f"  {z[k]/1000:6.2f}  {dz[k]/1000:5.2f}  {np.abs(r[1][k]).mean():10.3g}   {share[k]:.3f}")
# does the top-level residual form in the first hour and stay? check its signed pattern stability
for h in (1, 2, 24):
    print(f" t={h:2d} h  top-level mean r {r[h][-1].mean():+.4g}  mean|r| {np.abs(r[h][-1]).mean():.4g}")
