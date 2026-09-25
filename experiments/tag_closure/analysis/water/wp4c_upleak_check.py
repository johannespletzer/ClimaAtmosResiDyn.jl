"""V2's criterion 4 for the copies (FINDINGS W46): what `upleaknet`'s column
integral is.

    python3 wp4c_upleak_check.py GATE_CSV [--startup 6600]

GATE_CSV is `wp4c_gate_probe.jl`'s per-step table of V2
(`wp4c_corr_d4w_copies_gate.csv`). Per step it holds the column integral of
each ledger's change in the probe's "on, follower" trial
(`on_ledger_<ledger>_net`), and the closed-form leak of the copies'
diffusion mirror at the step's start, `dt ∫ ρ leak_diffusion_up dz`
(`diffusion_up_source_net`; `water_tag_leak!(:diffusion_up)`, which is the
grid mean's leak times `ρaʲ/ρ`). If the copies' correction takes the copies'
leak and nothing else, the first sums to minus the second. Then `upleaknet`'s
column integral is the `ρaʲ`-weighted integral of a flux divergence, which
vanishes only where `aʲ` is uniform in height, and `leaknet`'s, unweighted,
vanishes. It prints both, per step and summed, and over the whole run and the
established window.
"""
import argparse
import csv

import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("gate_csv")
parser.add_argument("--startup", type=float, default=6600.0)
args = parser.parse_args()

rows = list(csv.DictReader(open(args.gate_csv)))
col = lambda c: np.array([float(r[c]) for r in rows])
t = col("t_seconds")
water = col("water")
up = col("on_ledger_q_tag_led_upleaknet_net")
net = col("on_ledger_q_tag_led_leaknet_net")
src = col("diffusion_up_source_net")
src_gross = col("diffusion_up_source_gross")
print(f"{len(t)} steps, t = {t[0]:.0f} s to {t[-1]:.0f} s; water at the end {water[-1]:.6g} kg m-2")
for label, keep in (("whole run", t > 0), ("established flow", t > args.startup)):
    u, s, n = up[keep].sum(), src[keep].sum(), net[keep].sum()
    print(f"-- {label}, {keep.sum()} steps")
    print(f"   Σ ∫ Δupleaknet dz            {u:+.5e} kg m-2 ({u / water[-1]:+.3e} of the water)")
    print(f"   Σ dt ∫ ρ leak_diffusion_up dz {s:+.5e} kg m-2 (gross {src_gross[keep].sum():.5e})")
    print(f"   ratio of the first to minus the second: {u / -s:.4f}")
    print(f"   Σ ∫ Δleaknet dz (grid mean, unweighted): {n:+.3e} kg m-2")
    k = keep & (np.abs(src) > 0)
    r = up[k] / -src[k]
    print(f"   per step: correlation {np.corrcoef(up[k], -src[k])[0, 1]:.4f}; ratio median "
          f"{np.median(r):.4f}, 5th to 95th percentile {np.percentile(r, 5):.4f} to {np.percentile(r, 95):.4f}")
