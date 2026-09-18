# Profiles of e_src_res in the four C1c runs (E59), to see where each option's growth sits
# and whether options 1 and 3 drift with opposite signs, as the inexact-Jacobian toy predicts.
import netCDF4 as nc, numpy as np, glob
base='/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
def load(run, var):
    f=glob.glob(f'{base}/{run}/output_*/{var}_1h_inst.nc')[0]
    d=nc.Dataset(f); return np.array(d.variables['z'][:]), np.array(d.variables[var][:])
np.set_printoptions(linewidth=250, precision=0, suppress=True)
for opt in ['base','opt1','opt2','opt3']:
    run=f'c1c_{opt}_d4_enthalpy'
    z,r=load(run,'e_src_res'); _,rho=load(run,'rhoa')
    print('=====',opt)
    for t in [1,6,24]: print(f' t={t:2d}', r[:20,t])
    m=z<550
    for t in [1,24]:
        p=np.polyfit(z[m],r[m,t],1)
        print(f'  t={t}: subcloud slope {p[0]:.2f} J/kg/m; gross by layer <550/550-800/>800:',
              ' '.join(f'{(np.abs(r[mm,t])*rho[mm,t]*50).sum():.2e}' for mm in [z<550,(z>550)&(z<800),z>800]))
