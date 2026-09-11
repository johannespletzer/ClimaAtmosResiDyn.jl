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

# Test: does C8's form B track dt*gamma times the rain energy outflow at the surface?
import csv, netCDF4, numpy as np
d = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/c8_column_1m/output_active/"
def col(name):
    ds = netCDF4.Dataset(d + name + "_1h_inst.nc")
    v = np.array(ds[name][:]); dims = ds[name].dimensions
    if dims[0] != "time": v = v.T
    return v, ds
rho, ds = col("rhoa"); prec, _ = col("e_prc_precipitation")
print("shapes", rho.shape, prec.shape, "z[:3]", np.array(ds["z"][:3]))
dz = 1500.0 / rho.shape[1]
I = (rho * prec * dz).sum(axis=1)       # records are specific in the output, as c5_process_closure integrates rhoa*value*dz
rows = list(csv.DictReader(open("/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn.jl/experiments/tag_closure/output/c8_column_1m/process_closure.csv")))
fb = np.array([float(r["form_b"]) for r in rows]); rec = np.array([float(r["records"]) for r in rows])
F = np.gradient(I, 3600.0)              # centred hourly rate, W/m^2
gam = 0.4358665215 * 10.0
print(" h  int_prec(J/m2)  rate(W/m2)   form_B  dtgam*rate  ratio")
for k in range(len(I)):
    print(f"{k:3d} {I[k]:13.1f} {F[k]:10.4f} {fb[k]:+8.3f} {gam*F[k]:+9.3f} {fb[k]/(gam*F[k]) if F[k] else float('nan'):7.3f}")
m = slice(1, None)
print("slope of form B on rate (s):", (fb[m]*F[m]).sum()/(F[m]**2).sum(), " corr:", np.corrcoef(fb[m], F[m])[0,1], " dt*gamma:", gam)
