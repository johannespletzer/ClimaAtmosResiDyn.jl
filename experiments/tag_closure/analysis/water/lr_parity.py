# Parity of the long runs' second submission (output_0001): per site, each
# tagged run's model fields against the untagged twin, bit for bit, per day.
import glob, os, sys
import netCDF4, numpy as np
O = sys.argv[1] if len(sys.argv) > 1 else '/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output'
S = '_1d_inst.nc'
model = ['rhoa', 'ta', 'hus', 'clw', 'cli', 'wa', 'pr', 'lwp', 'arup', 'husup']
def load(run, name):
    p = f'{O}/{run}/output_0001/{name}{S}'
    if not os.path.exists(p):
        return None
    try:
        with netCDF4.Dataset(p) as d:
            return np.asarray(d[name][:])
    except Exception:
        return None
for site in ('23', '26'):
    ref = f'lr_s{site}_untagged'
    for v in ('samesign', 'absm', 'copies'):
        run = f'lr_s{site}_{v}'
        worst, days = None, 0
        for n in model:
            x, y = load(ref, n), load(run, n)
            if x is None or y is None:
                continue
            m = min(x.shape[-1], y.shape[-1])
            days = m
            diff = [k for k in range(m) if not np.array_equal(x[..., k], y[..., k])]
            if diff and (worst is None or diff[0] < worst[1]):
                worst = (n, diff[0])
        print(f'{run}: days {days}, ' + ('bit for bit' if worst is None else f'DIFFERS first in {worst[0]} at output {worst[1]}'))
