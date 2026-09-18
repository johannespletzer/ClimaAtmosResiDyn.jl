"""Denominators on the D4 column: process throughput per level (gross of the
hourly record increments), and the gross local change of E per hour, which
bounds transport plus processes from below. Records are transported too, so
the per-level record increments include some record transport (upper bound on
the local process part)."""
import sys, numpy as np
from netCDF4 import Dataset
run=sys.argv[1]
R="/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output/%s/output_active/%%s_1h_inst.nc"%run
def g(n):
    with Dataset(R%n) as d: return np.array(d[n][:]), np.array(d["z"][:])
rho,z=g("rhoa"); dz=np.gradient(z)[:,None]
Em=sum(g("e_src_"+n)[0] for n in ["strat","tropo","res"])
EV=rho*Em
procs=["radiation","surface_flux","subsidence","microphysics","precipitation"]
tot_gross=0; tot_net=0
for p in procs:
    r=g("e_prc_"+p)[0]*rho   # per volume, cumulative
    d=np.diff(r,axis=1)
    gross=(np.abs(d)*dz).sum(); net=(r[:,-1]*dz[:,0]).sum()
    neg=(np.maximum(-d,0)*dz).sum()
    tot_gross+=gross; tot_net+=abs(net)
    print(f"{p:14s} column net {net:+.3e}  per-level gross {gross:.3e}  per-level loss {neg:.3e} J/m2/day")
dE=np.diff(EV,axis=1)
print(f"sum |net| records {tot_net:.3e}; sum per-level gross records {tot_gross:.3e}")
print(f"gross local change of E, sum_h int|dE| dz: {(np.abs(dE)*dz).sum():.3e} J/m2/day; net change {((EV[:,-1]-EV[:,0])*dz[:,0]).sum():+.3e}")
print(f"int E at 24h {(EV[:,-1]*dz[:,0]).sum():.3e}")
