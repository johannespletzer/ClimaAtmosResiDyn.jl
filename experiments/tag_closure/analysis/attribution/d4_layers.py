# Split D4's closure residual e_src_res by layer, from the hourly NetCDF on scratch.
# Layers: subcloud 0-550 m, cloud and inversion 550-800 m, free troposphere 800-1500 m.
# Also fits the subcloud slope and compares it with R_d times the lapse rate.
import netCDF4 as nc, numpy as np
base='/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
def load(run, var):
    d=nc.Dataset(f'{base}/{run}/output_0001/{var}_1h_inst.nc'); return np.array(d.variables['z'][:]), np.array(d.variables[var][:])
for run in ['d4_column_edmf','d4_column_edmf_enthalpy']:
    z,r=load(run,'e_src_res'); _,rho=load(run,'rhoa'); _,ta=load(run,'ta')
    dz=np.full_like(z,50.0)
    layers={'subcloud <550m':z<550,'cloud+inv 550-800m':(z>550)&(z<800),'free trop >800m':z>800}
    print('=====',run)
    print(' t  | ' + ' | '.join(f'{k:>28s}' for k in layers) + ' |  total gross  total signed')
    for t in [1,3,6,12,18,24]:
        w=rho[:,t]*dz; cells=[]
        for k,m in layers.items():
            cells.append(f'{(np.abs(r[m,t])*w[m]).sum():10.3e} / {(r[m,t]*w[m]).sum():+10.3e}')
        print(f'{t:3d} | ' + ' | '.join(f'{c:>28s}' for c in cells) + f' | {(np.abs(r[:,t])*w).sum():10.3e} {(r[:,t]*w).sum():+10.3e}')
    # linear ramp in the lowest 11 levels (to 525 m): how much of the subcloud gross a line explains
    m=z<550
    for t in [6,12,24]:
        p=np.polyfit(z[m],r[m,t],1); fit=np.polyval(p,z[m]); w=rho[m,t]*50
        print(f'  t={t}: subcloud slope {p[0]:.2f} J/kg/m, -R_d dT/dz {-287*np.polyfit(z[m],ta[m,t],1)[0]:.2f}; gross of the line {(np.abs(fit)*w).sum():.3e}, of the misfit {(np.abs(r[m,t]-fit)*w).sum():.3e}')
