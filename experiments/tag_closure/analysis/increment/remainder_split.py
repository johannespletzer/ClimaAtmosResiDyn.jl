"""G1, criterion 2: split a prototype run's closure residual into named parts.

    python remainder_split.py <run> [hours, default 1,6,12,24]

The run must write `e_src_res`, `e_src_inc_left`, `e_src_inc_moved` and `rhoa`
hourly, and its closure check must have `audit: true`. All three fields are per
unit mass, so each is weighted by `rhoa` and the level spacing.

  - `left` is what the increment correction left out of the tags: the column
    totals of the parent's implicit increment that the tags' own implicit
    tendencies did not take. It lands in `e_src_res` as it is made.
  - `other` is `e_src_res - left`: what everything else leaves in the
    residual, the explicit tendencies the tags do not follow, and the loss
    rule, which removes `R/E` of each loss from the residual whatever made it.
    The ledger is not flushed by the loss rule, so a negative share of `other`
    that mirrors `left` is the loss rule acting on it.
  - `moved` is what the correction moved between levels. It sums to zero in a
    column and is not in the residual. It sizes what the tags' own implicit
    tendencies missed of the parent's vertical transport.
"""
import csv
import glob
import sys

import numpy as np
from netCDF4 import Dataset

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
LAYERS = (
    ("below 550 m", lambda z: z < 550),
    ("550 to 800 m", lambda z: (z >= 550) & (z < 800)),
    ("above 800 m", lambda z: z >= 800),
)


def output_dir(run):
    return sorted(glob.glob(f"{ROOT}/{run}/output_0*"))[-1]


def get(run, name):
    with Dataset(f"{output_dir(run)}/{name}_1h_inst.nc") as ds:
        # The files hold (z, time); rows are times here.
        return np.array(ds[name][:]).T, np.array(ds["z"][:]), np.array(ds["time"][:]) / 3600


run = sys.argv[1]
hours = [int(h) for h in (sys.argv[2] if len(sys.argv) > 2 else "1,6,12,24").split(",")]

res, z, t = get(run, "e_src_res")
left, _, _ = get(run, "e_src_inc_left")
moved, _, _ = get(run, "e_src_inc_moved")
rho, _, _ = get(run, "rhoa")
dz = np.gradient(z)
other = res - left

with open(f"{output_dir(run)}/energy_source_tag_audit.csv") as f:
    audit = {round(float(r["time"]) / 3600, 6): r for r in csv.DictReader(f)}

print(f"{run}: the closure residual split into parts, J/m², signed (gross)")
print(f"{'hour':>4s} {'residual':>22s} {'left':>22s} {'other':>22s} {'moved, gross':>13s}")
for h in hours:
    i = int(np.argmin(np.abs(t - h)))
    w = rho[i] * dz

    def part(x):
        return f"{np.sum(x[i] * w):+10.3e} ({np.sum(np.abs(x[i]) * w):9.3e})"

    print(
        f"{h:4d} {part(res)} {part(left)} {part(other)} "
        f"{np.sum(np.abs(moved[i]) * w):13.3e}"
    )
    row = audit.get(float(h))
    if row and "increment_left" in row:
        print(
            f"     audit: increment_left {float(row['increment_left']):+.3e}, "
            f"gross {float(row['increment_left_gross']):.3e}, "
            f"moved gross {float(row['increment_moved_gross']):.3e}"
        )

i = int(np.argmin(np.abs(t - hours[-1])))
w = rho[i] * dz
print(f"\nby layer at {hours[-1]} h, signed (gross)")
for label, mask_of in LAYERS:
    m = mask_of(z)

    def part(x):
        return f"{np.sum((x[i] * w)[m]):+10.3e} ({np.sum((np.abs(x[i]) * w)[m]):9.3e})"

    print(f"  {label:13s} residual {part(res)}, left {part(left)}, other {part(other)}")

print(f"\nlowest five levels at {hours[-1]} h, J/kg")
for k in range(5):
    print(
        f"  z {z[k]:6.0f} m: residual {res[i, k]:+9.3f}, left {left[i, k]:+9.3f}, "
        f"other {other[i, k]:+9.3f}, moved {moved[i, k]:+10.3f}"
    )

# The loss rule removes `R/E` of each loss from the residual, whatever made it.
# Predicted from the hourly records: each hour, the losses are the records'
# negative hourly changes, and `R/E` is taken at the start of the hour. If the
# tags follow every explicit process, `other` is this and nothing else.
try:
    records = [
        get(run, "e_prc_" + p)[0]
        for p in ("radiation", "surface_flux", "subsidence", "microphysics", "precipitation")
    ]
    tags = [get(run, "e_src_" + n)[0] for n in ("strat", "tropo")]
except (IndexError, OSError, KeyError):
    sys.exit(0)
E = tags[0] + tags[1] + res
loss = sum(np.maximum(-(np.diff(r, axis=0)), 0) for r in records)
flushed = np.cumsum(-(res[:-1] / E[:-1]) * loss, axis=0)
flushed = np.vstack([np.zeros_like(flushed[:1]), flushed])
print("\nthe loss rule's flushing, predicted from the hourly records, against `other`, J/m², signed")
for h in hours:
    i = int(np.argmin(np.abs(t - h)))
    w = rho[i] * dz
    parts = []
    for label, mask_of in LAYERS:
        m = mask_of(z)
        parts.append(
            f"{label}: other {np.sum((other[i] * w)[m]):+9.3e}, "
            f"predicted {np.sum((flushed[i] * w)[m]):+9.3e}"
        )
    print(f"{h:4d} " + "; ".join(parts))
