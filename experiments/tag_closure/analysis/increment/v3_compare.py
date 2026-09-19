"""V3: the tags' mixing against the air's own, on D4.

    python v3_compare.py [run, default v3_d4_passive_tracer] [reference, default g1_inc_d4]

The passive tracer `q_gas_A` and the ratio `ψ = tropo / (tropo + strat)` start
equal, the mask of `tropo`, and only transport, mixing and the repair change
either (analysis/increment/v3_driver.jl). The tracer has an updraft copy,
`q_gas_Aup`; the tags have none. So `ψ - q_gas_A` is how the tags' mixing
differs from the air's, the updraft included.

Prints the two profiles hourly at a few times, their L1 and largest
difference, the updraft's own tracer against the grid mean's, and whether
`ta` is bit for bit the reference run's. The NetCDF at t = 0 holds the tracer
before the driver set it, so the first comparison is at 1 h.
"""
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
run = sys.argv[1] if len(sys.argv) > 1 else "v3_d4_passive_tracer"
reference = sys.argv[2] if len(sys.argv) > 2 else "g1_inc_d4"


def get(r, name):
    path = sorted(glob.glob(f"{ROOT}/{r}/output_0*/{name}_1h_inst.nc"))[-1]
    with Dataset(path) as ds:
        # The files hold (z, time); rows are times here.
        return np.array(ds[name][:]).T, np.array(ds["z"][:])


strat, z = get(run, "e_src_strat")
tropo, _ = get(run, "e_src_tropo")
chi, _ = get(run, "q_gas_A")
chi_up, _ = get(run, "q_gas_Aup")
area_up, _ = get(run, "arup")
rho, _ = get(run, "rhoa")
psi = tropo / (tropo + strat)
w = rho * np.gradient(z)[None, :]

ta, _ = get(run, "ta")
ta_ref, _ = get(reference, "ta")
same = ta.shape == ta_ref.shape and np.array_equal(ta, ta_ref, equal_nan=True)
print(f"ta against {reference}: {'bit for bit' if same else 'DIFFERS, max ' + str(np.nanmax(np.abs(ta - ta_ref)))}")

print("\nψ = tropo/(tropo+strat) against the tracer q_gas_A (the air's own mixing)")
print(f"{'hour':>4s} {'L1 |ψ-χ|/χ':>12s} {'max |ψ-χ|':>10s} {'at z':>6s}")
for h in (1, 2, 3, 6, 12, 18, 24):
    if h >= len(psi):
        continue
    d = psi[h] - chi[h]
    l1 = np.sum(np.abs(d) * w[h]) / np.sum(np.abs(chi[h]) * w[h])
    k = int(np.argmax(np.abs(d)))
    print(f"{h:4d} {l1:12.3e} {d[k]:+10.4f} {z[k]:6.0f}")

for h in (1, 6, 24):
    if h >= len(psi):
        continue
    print(f"\nprofiles at {h} h: z, ψ (tags), χ (tracer), χ in the updraft, updraft area")
    for k in range(0, len(z), 2):
        up = f"{chi_up[h, k]:.4f}" if area_up[h, k] > 1e-3 else "   -  "
        print(f"  {z[k]:6.0f} {psi[h, k]:.4f} {chi[h, k]:.4f} {up} {area_up[h, k]:.3f}")
