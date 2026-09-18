"""Per-tag difference between two runs of the same atmosphere whose tags move
differently (tracer vs enthalpy audit). The audit run is taken as reference.

Prints, per tag and hour: column integral in the reference, the signed
difference of the integrals over the reference integral, and the L1 difference
int rho |dT| dz over int rho |T_ref| dz.
"""
import sys
import numpy as np
from netCDF4 import Dataset

ref, other = sys.argv[1], sys.argv[2]
tags = sys.argv[3].split(",")
hours = [int(h) for h in (sys.argv[4] if len(sys.argv) > 4 else "6,12,24").split(",")]
ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/{}/output_active/{}_1h_inst.nc"


def get(run, name):
    with Dataset(ROOT.format(run, name)) as ds:
        return np.array(ds[name][:]), np.array(ds["z"][:]), np.array(ds["time"][:]) / 3600


rho_r, z, t = get(ref, "rhoa")
try:
    rho_o, _, _ = get(other, "rhoa")
    print(f"rhoa max rel diff between runs: {np.max(np.abs(rho_o - rho_r) / rho_r):.2e}")
except (FileNotFoundError, OSError):
    print("no rhoa in", other)
dz = np.gradient(z)[:, None]
Eref = sum(get(ref, "e_src_" + n)[0] for n in ["strat", "tropo", "res"])
IE = (rho_r * Eref * dz).sum(0)
Rr = get(ref, "e_src_res")[0]
Ro = get(other, "e_src_res")[0]
print(f"{'tag':10s} {'hour':>4s} {'int_ref J/m2':>13s} {'int/intE':>9s} {'d(int)/int':>11s} {'L1 rel':>9s}")
for h in hours:
    i = int(np.argmin(abs(t - h)))
    print(f"{'G_res':10s} {h:4d} ref {np.sum(np.abs(Rr[:, i])*rho_r[:, i]*dz[:, 0]):.3e} other {np.sum(np.abs(Ro[:, i])*rho_r[:, i]*dz[:, 0]):.3e} (over intE ref {np.sum(np.abs(Rr[:, i])*rho_r[:, i]*dz[:, 0])/IE[i]:.2e}, other {np.sum(np.abs(Ro[:, i])*rho_r[:, i]*dz[:, 0])/IE[i]:.2e})")
    for n in tags:
        a = get(ref, "e_src_" + n)[0][:, i]
        b = get(other, "e_src_" + n)[0][:, i]
        w = rho_r[:, i] * dz[:, 0]
        Ia, Ib = (a * w).sum(), (b * w).sum()
        l1 = (np.abs(b - a) * w).sum() / max((np.abs(a) * w).sum(), 1e-300)
        print(f"{n:10s} {h:4d} {Ia:13.4e} {Ia/IE[i]:9.2e} {(Ib-Ia)/Ia:+11.3e} {l1:9.3e}")
