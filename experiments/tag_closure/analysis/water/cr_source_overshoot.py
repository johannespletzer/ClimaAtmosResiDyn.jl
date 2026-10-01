"""W49, reported, not pre-registered as a rule: the source tags' most negative
value and their overshoot above the parent (design/NEGATIVE_PARENT_WATER.md
11.11.4, decision 4: "a crossing step's source-tag overshoot is accepted and
reported in V5"). `cr_validate.py` prints the source tags' negative water as a
column integral only. This script adds the pointwise numbers, written after
the runs were read, so it is a measurement and not a test.

    python3 cr_source_overshoot.py [OUTPUT_ROOT]

For `cr_s23` and `cr_s26`, tags `evap` and `fcg`, daily and 6-hourly outputs to
day 90, per output and column, with M = the largest |hus| in the column:
  - most negative q_tag / M, and where;
  - largest (q_tag - hus) / M over cells, and where. A positive value is a tag
    above its parent.
"""
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
DAY = 86400.0


def read(job, var, period):
    with nc.Dataset(os.path.join(ROOT, job, "output_0000", f"{var}_{period}_inst.nc")) as d:
        v = d[var]
        dims = v.dimensions
        a = np.moveaxis(np.asarray(v[:]), [dims.index("time"), dims.index("z")], [0, 1])
        return np.asarray(d["time"][:]), np.asarray(d["z"][:]), a.reshape(a.shape[0], a.shape[1], -1)


for job in ("cr_s23", "cr_s26"):
    for period in ("1d", "6h"):
        t, z, hus = read(job, "hus", period)
        keep = t <= 90 * DAY + 1
        scale = np.abs(hus).max(axis=1)  # (time, column)
        for tag in ("evap", "fcg"):
            tq, _, q = read(job, f"q_tag_{tag}", period)
            n = min(len(t), len(tq))
            assert np.array_equal(t[:n], tq[:n])
            k = keep[:n]
            neg = q[:n][k] / scale[:n][k][:, None, :]
            over = (q[:n][k] - hus[:n][k]) / scale[:n][k][:, None, :]
            i = np.unravel_index(np.argmin(neg), neg.shape)
            j = np.unravel_index(np.argmax(over), over.shape)
            tk = t[:n][k]
            print(f"{job} {period} {tag}: most negative {neg[i]:.3e} of the column's largest |q_tot| "
                  f"(day {tk[i[0]] / DAY:g}, z {z[i[1]]:.0f} m); "
                  f"above its parent by at most {over[j]:.3e} (day {tk[j[0]] / DAY:g}, z {z[j[1]]:.0f} m); "
                  f"outputs with a negative value: {int((q[:n][k] < 0).any(axis=(1, 2)).sum())} of {int(k.sum())}; "
                  f"outputs above the parent by more than 1e-12: {int((over > 1e-12).any(axis=(1, 2)).sum())}")
            h = hus[:n][k]
            pos_over = np.where(h > 0, over, -np.inf)
            jp = np.unravel_index(np.argmax(pos_over), pos_over.shape)
            _, _, qm = read(f"{job}_main", f"q_tag_{tag}", period)
            print(f"    at the largest overshoot's cell: hus {h[j] / scale[:n][k][j[0], j[2]]:.3e} M, "
                  f"tag {q[:n][k][j] / scale[:n][k][j[0], j[2]]:.3e} M, main's tag "
                  f"{qm[:n][k][j] / scale[:n][k][j[0], j[2]]:.3e} M; "
                  f"over cells with hus > 0 only: {pos_over[jp]:.3e} (day {tk[jp[0]] / DAY:g}, z {z[jp[1]]:.0f} m)")
