"""WP5b-V (design/EXPLICIT_1M_DEFAULT.md): how often the water tags' shares
clamp, and where the partition's norm is zero, at each output time.

    python3 w5v_clamps.py OUTPUT_DIR [PARTITION_TAGS] [SOURCE_TAGS]

OUTPUT_DIR is a run's `output_0000`. PARTITION_TAGS and SOURCE_TAGS are
comma-separated tag names (default `pbl,free` and `evap`). From the 30-minute
`q_tag_<name>`, `hus` and `rhoa` it prints, per output time, the fraction of
cells, and of the column's water (weights ρ, the grid is uniform), where:
  - a tag's share clamps: the tag above `q_tot` or below zero;
  - how much the clamps cut, over the column's water:
    Σ ρ (max(q_tag − q_tot, 0) + max(−q_tag, 0)) / Σ ρ q_tot;
  - the partition's norm is zero: no partition tag holds positive water.
The shares clamp in `water_tag_fraction`; the norm is the sum of the partition
tags' clamped shares (`water_tag_share_norm!`).
"""

import sys

import netCDF4
import numpy as np


def read(directory, name):
    with netCDF4.Dataset(f"{directory}/{name}_30m_inst.nc") as ds:
        return np.asarray(ds["time"][:]), np.asarray(ds[name][:]).reshape(len(ds["time"]), -1)


def main():
    directory = sys.argv[1]
    partition = (sys.argv[2] if len(sys.argv) > 2 else "pbl,free").split(",")
    sources = (sys.argv[3] if len(sys.argv) > 3 else "evap").split(",")
    time, q_tot = read(directory, "hus")
    _, rho = read(directory, "rhoa")
    tags = {name: read(directory, f"q_tag_{name}")[1] for name in partition + sources}
    water = rho * q_tot
    print("time_h  clamped_cells  clamped_water  clamped_amount  zero_norm_cells  zero_norm_water")
    worst = (0.0, 0.0, 0.0, 0.0, 0.0)
    for k in range(len(time)):
        clamped = np.zeros(q_tot.shape[1], dtype=bool)
        amount = 0.0
        for q in tags.values():
            clamped |= (q[k] > q_tot[k]) | (q[k] < 0)
            amount += (rho[k] * (np.maximum(q[k] - q_tot[k], 0) + np.maximum(-q[k], 0))).sum()
        norm_zero = np.all([tags[name][k] <= 0 for name in partition], axis=0)
        row = (
            clamped.mean(),
            water[k][clamped].sum() / water[k].sum(),
            amount / water[k].sum(),
            norm_zero.mean(),
            water[k][norm_zero].sum() / water[k].sum(),
        )
        worst = tuple(max(a, b) for a, b in zip(worst, row))
        print(f"{time[k] / 3600:6.2f}  " + "  ".join(f"{x:.3e}" for x in row))
    print("RESULT max_over_times " + " ".join(
        f"{n}={x:.3e}" for n, x in zip(
            ("clamped_cells", "clamped_water", "clamped_amount", "zero_norm_cells", "zero_norm_water"), worst
        )
    ))


if __name__ == "__main__":
    main()
