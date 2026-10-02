"""V-W7's named parts (design/F32_TWIN.md, section 9), scored.

    python3 f32_named_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds, each in
`output_0000`, D4-W's default mode at 60 levels:

  - one Newton iteration: `g3b_d4w_default_z60_c` (Float64, W55) and
    `f32_d4w_default_z60_c` (Float32, W60);
  - ten Newton iterations: `f32_d4w_default_z60_c_n10_f64` and
    `f32_d4w_default_z60_c_n10_f32`.

SCORE_DIR (default: this record's `output/f32/`) receives
`f32_named_scores.csv`: one row per rule, iteration count and measure, with
the Float64 value, the Float32 value, their ratio, the threshold and the
verdict.

Every measure is taken from the hourly NetCDF output, gross over the cells
and relative to the column's water at the same hour, `Σ ρ q_tot Δz`:

  - `G`: the residual `q_tag_res`;
  - `P_inc`: the one-iteration part, `q_tag_inc_left`, the part of the
    parent's implicit increment that changes a column's total and that the
    follower leaves in `q_tag_res`;
  - `P_leak`: the vertical diffusion's leak, `q_tag_leak_vdiff` (a rate,
    hourly means) summed over the hours. It is reported only. Under the
    follower the tags take the parent's implicit increment, the vertical
    diffusion included, so the leak does not land in `q_tag_res` (W40, and
    section 9.2 of the design);
  - `N`: what the named parts leave, `q_tag_res − q_tag_inc_left`.

The rules are the design's section 9.3. `C4` reads N in Float64 against
criterion 4's 1e-6, at both iteration counts. `C9` reads each measure in
Float32 against 10 times its Float64 value. The Float32 rounding level
(the Float32 one-iteration run's `G` at 0 h, the rounding of the initial
partition) is printed beside each Float32 value. It changes no verdict.

`F32N_SMOKE=1` reads the Float64 one-iteration run in place of every run, to
check the script before the jobs. Its scores mean nothing.
"""

import csv
import math
import os
import sys

import netCDF4 as nc
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
SCORE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "f32")
SMOKE = os.environ.get("F32N_SMOKE", "") == "1"
DAY = 86400.0
FACTOR = 10.0
REMAINDER_BUDGET = 1e-6

RUNS = {
    (1, "f64"): "g3b_d4w_default_z60_c",
    (1, "f32"): "f32_d4w_default_z60_c",
    (10, "f64"): "f32_d4w_default_z60_c_n10_f64",
    (10, "f32"): "f32_d4w_default_z60_c_n10_f32",
}
if SMOKE:
    RUNS = {k: "g3b_d4w_default_z60_c" for k in RUNS}

rows = []


def add(rule, iters, metric, hour, f64, f32, threshold, verdict, note=""):
    ratio = f32 / f64 if isinstance(f64, float) and isinstance(f32, float) and f64 != 0.0 else ""
    rows.append(dict(rule=rule, newton=iters, metric=metric, hour=hour, f64=f64, f32=f32, ratio=ratio,
                     threshold=threshold, verdict=verdict, note=note))


def out_dir(name):
    return os.path.join(ROOT, name, "output_0000")


def read(directory, name, suffix="_1h_inst.nc"):
    """(time, z, values[time, level]) of `<name><suffix>`, time found by name."""
    with nc.Dataset(os.path.join(directory, name + suffix)) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        return (np.asarray(d["time"][:], dtype=float), np.asarray(d["z"][:], dtype=float),
                values.reshape(values.shape[0], -1))


def thickness(z):
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    return np.diff(faces)


def index_at(time, t):
    hits = np.nonzero(np.abs(time - t) < 1e-3)[0]
    return int(hits[0]) if hits.size else None


def measures(directory, t):
    """The section 9.3 measures at time `t`, or None if the run lacks that hour."""
    if not os.path.isdir(directory):
        return None
    time, z, rho = read(directory, "rhoa")
    _, _, hus = read(directory, "hus")
    _, _, res = read(directory, "q_tag_res")
    _, _, left = read(directory, "q_tag_inc_left")
    lt, _, leak = read(directory, "q_tag_leak_vdiff", "_1h_average.nc")
    i = index_at(time, t)
    if i is None:
        return None
    w = rho[i] * thickness(z)
    water = float(np.sum(w * hus[i]))
    # Hourly means up to t, each over the hour that ends at its time stamp.
    leak_sum = np.sum(leak[lt <= t + 1e-3], axis=0) * 3600.0
    remainder = res[i] - left[i]
    out = dict(
        G=float(np.sum(w * np.abs(res[i]))) / water,
        P_inc=float(np.sum(w * np.abs(left[i]))) / water,
        P_leak=float(np.sum(w * np.abs(leak_sum))) / water,
        N=float(np.sum(w * np.abs(remainder))) / water,
    )
    out["P_inc_net"] = float(np.sum(w * left[i])) / water
    return out


def closure_gross(directory, t):
    path = os.path.join(directory, "water_tag_closure.csv")
    if not os.path.exists(path):
        return None
    for r in csv.DictReader(open(path)):
        if abs(float(r["time"]) - t) < 1e-3:
            return float(r["gross_relative"])
    return None


def finite(x):
    return isinstance(x, float) and math.isfinite(x)


rounding = measures(out_dir(RUNS[(1, "f32")]), 0.0)
rounding = rounding["G"] if rounding else float("nan")

judged = {"C4": [], "C9": []}
NAMES = dict(G="gross residual", P_inc="the one-iteration part (inc_left), gross",
             P_leak="the vertical diffusion's leak, gross", N="what the named parts leave, gross")
for iters in (1, 10):
    for hour in (12, 24):
        t = hour * 3600.0
        m64 = measures(out_dir(RUNS[(iters, "f64")]), t)
        m32 = measures(out_dir(RUNS[(iters, "f32")]), t)
        judged_hour = hour == 24
        if m64 is None or m32 is None:
            add("C9", iters, "run", hour, "", "", "", "fail (a run is missing or lacks the hour)")
            if judged_hour:
                judged["C9"].append(False)
                judged["C4"].append(m64 is not None)
            continue
        # The method's check: G from NetCDF against the closure table.
        for prec, m in (("f64", m64), ("f32", m32)):
            table = closure_gross(out_dir(RUNS[(iters, prec)]), t)
            add("CHECK", iters, f"G from NetCDF against the closure table, {prec}", hour,
                table if table is not None else "", m["G"], "", "reported")
        add("REP", iters, "the one-iteration part, net over the column", hour, m64["P_inc_net"],
            m32["P_inc_net"], "", "reported")
        for key, label in NAMES.items():
            v64, v32 = m64[key], m32[key]
            if not judged_hour or key == "P_leak":
                add("C9", iters, label, hour, v64, v32, "", "reported")
                continue
            note = f"Float32 rounding level {rounding:.2e}: {'below' if v32 < rounding else 'above'}"
            if not (finite(v64) and finite(v32)):
                ok, threshold = False, ""
            elif v64 == 0.0:
                threshold = 0.0 if v32 == 0.0 else REMAINDER_BUDGET
                ok = v32 <= threshold
                note += "; Float64 zero: judged on the remainder budget unless both are zero"
            else:
                threshold = FACTOR * v64
                ok = v32 <= threshold
            add("C9", iters, label, hour, v64, v32, threshold, "pass" if ok else "fail", note)
            judged["C9"].append(ok)
        ok = finite(m64["N"]) and m64["N"] <= REMAINDER_BUDGET
        add("C4", iters, "what the named parts leave, Float64, against criterion 4", hour if judged_hour else hour,
            m64["N"], m32["N"], REMAINDER_BUDGET, ("pass" if ok else "fail") if judged_hour else "reported",
            "the Float32 value is reported")
        if judged_hour:
            judged["C4"].append(ok)

add("C4", "both", "criterion 4's named-parts clause, Float64", 24, "", "", "",
    "pass" if judged["C4"] and all(judged["C4"]) else "fail")
add("C9", "both", "criterion 9's named-parts measures", 24, "", "", "",
    "pass" if judged["C9"] and all(judged["C9"]) else "fail")

os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "f32_named_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
if not SMOKE:
    for r in rows:
        print(r["rule"], r["newton"], r["metric"], r["hour"], r["f64"], r["f32"], r["threshold"], r["verdict"],
              r["note"], sep=" | ")
else:
    print(f"smoke: {len(rows)} rows written")
