"""Where does the residual sit on the D4 column, and how fast could the loss
rule remove it there?

For each hour: R(z) = e_src_res, E/rho = strat + tropo + res, the bracketed
loss per process from hourly differences of the records (e_prc_*, cumulative
J/kg), and the local decay rate lambda(z) = sum_p max(-d rec_p, 0) / (E/rho).
The residual-weighted rate lambda_R = sum |R| rho lambda / sum |R| rho.
"""
import sys
import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/{}/output_active/{}_1h_inst.nc"
run = sys.argv[1] if len(sys.argv) > 1 else "d4_column_edmf_enthalpy"
procs = sys.argv[2].split(",") if len(sys.argv) > 2 else [
    "radiation", "surface_flux", "subsidence", "microphysics", "precipitation"]


def get(name):
    with Dataset(ROOT.format(run, name)) as ds:
        v = np.array(ds[name][:])  # (z, time)
        z = np.array(ds["z"][:])
        t = np.array(ds["time"][:]) / 3600
    return v, z, t


R, z, t = get("e_src_res")
rho, _, _ = get("rhoa")
strat, _, _ = get("e_src_strat")
tropo, _, _ = get("e_src_tropo")
Em = strat + tropo + R  # E / rho, J/kg
dz = np.gradient(z)[:, None]
rec = {p: get("e_prc_" + p)[0] for p in procs}

print(f"run {run}; dz {dz[0,0]:.0f} m; z {z[0]:.0f}..{z[-1]:.0f}")
print("hour  G=int|R|    signed    lamR(1/day) lamE(1/day) G_pred_next  G_next   z_centroid|R|  frac|R| z>1000")
Gs = (np.abs(R) * rho * dz).sum(0)
for i in range(1, len(t) - 1):
    loss = sum(np.maximum(-(rec[p][:, i + 1] - rec[p][:, i]), 0) for p in procs)  # J/kg per hour
    lam = loss / Em[:, i] * 24  # per day
    w = np.abs(R[:, i]) * rho[:, i] * dz[:, 0]
    lamR = (w * lam).sum() / w.sum()
    wE = Em[:, i] * rho[:, i] * dz[:, 0]
    lamE = (wE * lam).sum() / wE.sum()
    G = w.sum()
    Gpred = G * np.exp(-lamR / 24)
    zc = (w * z).sum() / w.sum()
    top = w[z > 1000].sum() / w.sum()
    print(f"{t[i]:4.0f} {G:10.3e} {(R[:, i]*rho[:, i]*dz[:, 0]).sum():+10.3e} {lamR:10.3f} {lamE:10.3f} "
          f"{Gpred:11.3e} {Gs[i+1]:10.3e} {zc:9.0f} {top:9.2f}")

# Profiles at selected hours
for h in [1, 3, 7, 12, 14, 18, 24]:
    i = int(np.argmin(abs(t - h)))
    print(f"\nprofile at {t[i]:.0f} h: z, R (J/kg), E/rho, R/(E/rho), cumulative rad record, loss rate 1/day (next hr or prev)")
    j = min(i + 1, len(t) - 1)
    k = i if j > i else i - 1
    loss = sum(np.maximum(-(rec[p][:, k + 1] - rec[p][:, k]), 0) for p in procs)
    for n in range(len(z)):
        if abs(R[n, i]) * rho[n, i] * dz[n, 0] > 0.02 * Gs[i] or n % 5 == 0:
            print(f"  {z[n]:6.0f} {R[n, i]:+9.2f} {Em[n, i]:9.0f} {R[n, i]/Em[n, i]:+.2e} "
                  f"{rec['radiation'][n, i]:+9.0f} {loss[n]/Em[n, i]*24:7.3f}")
