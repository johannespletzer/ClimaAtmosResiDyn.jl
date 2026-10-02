"""The rounding level of V-W7's named parts, from the Opus review of the W60 addendum.

    python3 f32_named_floor.py [OUTPUT_ROOT] [SCORE_DIR]

Reads the same four runs as `f32_named_score.py` and writes
`f32_named_floor.csv` to SCORE_DIR (default: this record's `output/f32/`).
One row per run and hour: the measures `G`, `P_inc` and `N` of the design's
section 9.2, each relative to the column's water, and each divided by
`eps·√n`. Here `eps` is the run's machine epsilon and `n` the steps taken
(`dt` 120 s, so 30 an hour).

`eps·√n` is the growth of a random walk of one relative `eps` per step. It is
a yardstick, not a rule. Nothing here sets or changes a verdict.
"""

import csv
import os
import sys

import netCDF4 as nc
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
SCORE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "f32")
STEPS_PER_HOUR = 30

RUNS = {
    (1, "f64"): "g3b_d4w_default_z60_c",
    (1, "f32"): "f32_d4w_default_z60_c",
    (10, "f64"): "f32_d4w_default_z60_c_n10_f64",
    (10, "f32"): "f32_d4w_default_z60_c_n10_f32",
}
EPS = {"f64": float(np.finfo(np.float64).eps), "f32": float(np.finfo(np.float32).eps)}


def read(directory, name):
    with nc.Dataset(os.path.join(directory, name + "_1h_inst.nc")) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        return (np.asarray(d["time"][:], dtype=float), np.asarray(d["z"][:], dtype=float),
                values.reshape(values.shape[0], -1))


def thickness(z):
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    return np.diff(faces)


rows = []
for (iters, prec), name in RUNS.items():
    directory = os.path.join(ROOT, name, "output_0000")
    time, z, rho = read(directory, "rhoa")
    _, _, hus = read(directory, "hus")
    _, _, res = read(directory, "q_tag_res")
    _, _, left = read(directory, "q_tag_inc_left")
    w = rho * thickness(z)
    water = np.sum(w * hus, axis=1)
    measures = dict(
        G=np.sum(w * np.abs(res), axis=1) / water,
        P_inc=np.sum(w * np.abs(left), axis=1) / water,
        N=np.sum(w * np.abs(res - left), axis=1) / water,
    )
    for i, t in enumerate(time):
        hour = t / 3600.0
        n = hour * STEPS_PER_HOUR
        scale = EPS[prec] * np.sqrt(n) if n > 0 else float("nan")
        row = dict(run=name, newton=iters, precision=prec, hour=round(hour, 3), eps_sqrt_n=scale)
        for key, values in measures.items():
            row[key] = float(values[i])
            row[key + "_over_eps_sqrt_n"] = float(values[i] / scale) if n > 0 else ""
        rows.append(row)

os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "f32_named_floor.csv"), "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)

for (iters, prec), name in RUNS.items():
    sel = [r for r in rows if r["run"] == name and 1 <= r["hour"] <= 24]
    summary = ", ".join(
        f"{key} {min(r[key + '_over_eps_sqrt_n'] for r in sel):.2f} to {max(r[key + '_over_eps_sqrt_n'] for r in sel):.2f}"
        for key in ("G", "P_inc", "N"))
    print(f"{name} (Newton {iters}, {prec}), 1 h to 24 h, over eps·√n: {summary}")
