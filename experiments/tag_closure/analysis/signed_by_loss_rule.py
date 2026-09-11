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

# Point 3: under tracer transport, is the column's signed residual the loss rule acting on the
# transport-made residual?  d(signed)/dt = sum_z rho dz * sum_p min(D_p, 0) * r / E  (tag brackets only)
import netCDF4, numpy as np, csv
root = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/"
def rd(run, name):
    ds = netCDF4.Dataset(root + run + "/output_active/" + name + "_1h_inst.nc")
    v = ds[name]; d = list(v.dimensions)
    return np.moveaxis(np.array(v[:]), d.index("time"), 0)
for run, procs in (("c6_column_repair", ("radiation", "surface_flux", "subsidence", "microphysics")),
                   ("c8_column_1m", ("radiation", "surface_flux", "subsidence", "microphysics")),
                   ("c9_column_enthalpy", ("radiation", "surface_flux", "subsidence", "microphysics"))):
    r = rd(run, "e_src_res"); rho = rd(run, "rhoa"); dz = 1500.0 / r.shape[1]
    E = rd(run, "e_src_strat") + rd(run, "e_src_tropo") + r
    rec = {p: rd(run, "e_prc_" + p) for p in procs}
    tab = list(csv.DictReader(open(f"/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn.jl/experiments/tag_closure/output/{run}/energy_source_tag_closure.csv")))
    obs = [float(x["residual"]) for x in tab]
    pred = [0.0]
    for h in range(1, r.shape[0]):
        loss = sum(np.minimum(rec[p][h] - rec[p][h - 1], 0.0) for p in procs)   # J/kg lost this hour, per level
        rm, Em, rhm = 0.5 * (r[h] + r[h - 1]), 0.5 * (E[h] + E[h - 1]), 0.5 * (rho[h] + rho[h - 1])
        pred.append(pred[-1] + np.sum(rhm * loss * rm / Em) * dz)
    print(f"== {run}: signed column residual, J/m^2, observed vs loss rule on the residual (hour-midpoint estimate)")
    for h in (1, 2, 3, 6, 12, 18, 24):
        print(f"   {h:2d} h  observed {obs[h]:+12.1f}   loss rule {pred[h]:+12.1f}   gross {float(tab[h]['gross_residual']):10.0f}")
