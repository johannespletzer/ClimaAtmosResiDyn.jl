# Hourly increments of D4's free-troposphere residual (mean J/kg above 800 m) beside the
# hourly increments of each process record's column integral, to see what the steps follow.
import netCDF4 as nc, numpy as np
base='/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
def load(run, var):
    d=nc.Dataset(f'{base}/{run}/output_0001/{var}_1h_inst.nc'); return np.array(d.variables['z'][:]), np.array(d.variables[var][:])
run='d4_column_edmf_enthalpy'
z,r=load(run,'e_src_res'); _,rho=load(run,'rhoa')
ft=z>800; sub=z<550; cl=(z>550)&(z<800)
recs={}
for v in ['e_prc_radiation','e_prc_surface_flux','e_prc_subsidence','e_prc_precipitation','e_prc_microphysics']:
    _,x=load(run,v); recs[v]=(x*rho*50).sum(axis=0)
print(' t | dFT J/kg | dgross_sub dgross_cloud dgross_FT (J/m2) | d rad  d sfc  d sub  d precip  (J/m2 per h)')
g=lambda m,t: (np.abs(r[m,t])*rho[m,t]*50).sum()
for t in range(1,25):
    dft=r[ft,t].mean()-r[ft,t-1].mean()
    print(f'{t:2d} | {dft:8.2f} | {g(sub,t)-g(sub,t-1):10.0f} {g(cl,t)-g(cl,t-1):10.0f} {g(ft,t)-g(ft,t-1):10.0f} | ' + ' '.join(f'{recs[v][t]-recs[v][t-1]:9.0f}' for v in ['e_prc_radiation','e_prc_surface_flux','e_prc_subsidence','e_prc_precipitation']))
