"""V-W7 under criterion 9's rounding floor (design/F32_TWIN.md, section 10).

    python3 f32_floor_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds, each in
`output_0000`, the fresh runs `f32fl_d4w_{default,copies}_z60_c_n10_{f64,f32}`
(D4-W at 60 levels, ten Newton iterations), and W54's untagged twin
`g3b_d4w_untagged_z60_c`, whose OD2 window (1 h) the per-day rates use, as
in W60. SCORE_DIR (default: this record's `output/f32/`) receives
`f32_floor_scores.csv`.

The rule (the owner, 2026-10-02): a Float32 measure passes if it is at most
`max(10 × Float64, 3 · eps32 · √n_steps)`, with `eps32 = 2^-23` and `n_steps`
the number of 120 s steps the measure accumulates over:

  - a state at 24 h (the gross residual, `q_tag_inc_left`, what the named
    parts leave) and the largest over the outputs (the copies' own residual):
    720, from 0 to 24 h;
  - the second 12 h's addition: 360, from 12 to 24 h;
  - a rate over OD2's established window (the repairs per day, `led_fix`):
    690, from 1 to 24 h.

The measures are W60's (`f32_score.py`: R4, R5, R8) and its addendum's
(`f32_named_score.py`: the residual, the one-iteration part, what the named
parts leave), computed the same way. Reported, not judged: the Float64 values
against criterion 4's own budgets, the whole-day readings, and whether the
fresh default runs repeat runs 5 and 6 (`f32_d4w_default_z60_c_n10_*`) byte
for byte in their closure tables. A non-finite value or a missing hour fails.

`F32FL_SMOKE=1` reads runs 5 and 6 as the default pair and W54's and W60's
one-iteration copies as the copies pair, to check the script before the jobs.
Its scores mean nothing.
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
SMOKE = os.environ.get("F32FL_SMOKE", "") == "1"
DAY = 86400.0
DT = 120.0
EPS32 = 2.0 ** -23
FACTOR = 10.0
TAGS = ("tropo", "strat", "evap", "evap_tropo", "evap_strat")
TWIN = "g3b_d4w_untagged_z60_c"

RUNS = {(m, p): f"f32fl_d4w_{m}_z60_c_n10_{p}" for m in ("default", "copies") for p in ("f64", "f32")}
OLD = {p: f"f32_d4w_default_z60_c_n10_{p}" for p in ("f64", "f32")}
if SMOKE:
    RUNS = {("default", "f64"): OLD["f64"], ("default", "f32"): OLD["f32"],
            ("copies", "f64"): "g3b_d4w_copies_z60_c", ("copies", "f32"): "f32_d4w_copies_z60_c"}

rows = []


def floor(n_steps):
    return 3.0 * EPS32 * math.sqrt(n_steps)


def add(rule, mode, metric, f64, f32, threshold, verdict, note=""):
    ratio = f32 / f64 if isinstance(f64, float) and isinstance(f32, float) and f64 != 0.0 else ""
    rows.append(dict(rule=rule, mode=mode, metric=metric, f64=f64, f32=f32, ratio=ratio, threshold=threshold,
                     verdict=verdict, note=note))


def out_dir(name):
    return os.path.join(ROOT, name, "output_0000")


def read_csv(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def row_at(table, time):
    for r in table:
        if r["time"] >= time - 1e-6:
            return r
    return None


def read_nc(directory, name, suffix="_1h_inst.nc"):
    with nc.Dataset(os.path.join(directory, name + suffix)) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        z = np.asarray(d["z"][:], dtype=float) if "z" in d.variables else np.zeros(1)
        return np.asarray(d["time"][:], dtype=float), z, values.reshape(values.shape[0], -1)


def thickness(z):
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    return np.diff(faces)


def od2_window(run_dir):
    """OD2's end of startup, as `g3base_score.py` and `f32_score.py` read it."""
    time, z, rho = read_nc(run_dir, "rhoa", "_10m_inst.nc")
    _, _, q = read_nc(run_dir, "hus", "_10m_inst.nc")
    dz = np.gradient(z) if z.size > 1 else np.ones(1)
    water = (rho * q * dz).sum(axis=1)
    tendency = np.abs(np.diff(water)) / np.diff(time)
    ends = time[1:]
    level = 0.1 * tendency[ends <= 6 * 3600 + 1e-6].max()
    below = tendency < level
    for i in range(len(below) - 2):
        if below[i] and below[i + 1] and below[i + 2]:
            return float(ends[i - 1] if i > 0 else time[0])
    return None


T0 = od2_window(out_dir(TWIN))
if T0 is None:
    sys.exit("OD2's rule finds no end of startup on W54's twin")
N_DAY, N_HALF, N_WINDOW = int(DAY / DT), int(DAY / 2 / DT), int((DAY - T0) / DT)


def measures(run_dir, mode):
    """name -> (value, judged, n_steps, criterion 4's own budget)."""
    closure = read_csv(os.path.join(run_dir, "water_tag_closure.csv"))
    audit = read_csv(os.path.join(run_dir, "water_tag_audit.csv"))
    if closure is None or audit is None or row_at(closure, DAY) is None or row_at(audit, DAY) is None:
        return None
    out = {}
    half = DAY / 2
    G = {t: row_at(closure, t)["gross_relative"] for t in (0.0, half, DAY)}
    out["R4 gross residual at 24 h"] = (G[DAY], True, N_DAY, 2e-3)
    out["R4 the second 12 h's addition"] = (G[DAY] - G[half], True, N_HALF, None)
    out["R4 second minus first 12 h (criterion 4: <= 0)"] = (
        (G[DAY] - G[half]) - (G[half] - G[0.0]), False, None, 0.0)
    end = row_at(audit, DAY)
    water = row_at(closure, DAY)["total"]

    def per_day(column, start, divide_by=water):
        s = row_at(audit, start)
        return (end[column] - s[column]) / divide_by / ((end["time"] - s["time"]) / DAY)

    out["R8 partition repair retained gross per day"] = (per_day("led_repair_retained", T0), True, N_WINDOW, 5e-3)
    out["R8 partition repair, whole day"] = (per_day("led_repair_retained", 0.0), False, None, 5e-3)
    for tag in TAGS:
        key = f"led_fix_{tag}_inventory_fraction"
        if key not in end:
            continue
        frac = end[key]
        retained = end[f"led_fix_{tag}_retained"]
        inventory = retained / frac if frac > 0 else None
        start = row_at(audit, T0)[f"led_fix_{tag}_retained"]
        value = (retained - start) / inventory if inventory else 0.0
        out[f"R8 led_fix inventory fraction, {tag}"] = (value, True, N_WINDOW, 0.02)
    if mode == "copies":
        own = max(r["copy_residual_relative"] for r in audit if r["time"] <= DAY + 1e-6)
        out["R5 copies' own residual, max over outputs"] = (own, True, N_DAY, 2e-4)
        out["R5 copies' repair, gross, per day"] = (per_day("led_uprepair_retained", T0), True, N_WINDOW, 2e-3)
        out["R5 copies' repair, whole day"] = (per_day("led_uprepair_retained", 0.0), False, None, 2e-3)
    else:
        # The named parts (W60's addendum), from the hourly NetCDF output.
        time, z, rho = read_nc(run_dir, "rhoa")
        _, _, hus = read_nc(run_dir, "hus")
        _, _, res = read_nc(run_dir, "q_tag_res")
        _, _, left = read_nc(run_dir, "q_tag_inc_left")
        i = int(np.nonzero(np.abs(time - DAY) < 1e-3)[0][0])
        w = rho[i] * thickness(z)
        total = float(np.sum(w * hus[i]))
        out["named: the one-iteration part, q_tag_inc_left, gross"] = (
            float(np.sum(w * np.abs(left[i]))) / total, True, N_DAY, None)
        out["named: what the named parts leave, gross"] = (
            float(np.sum(w * np.abs(res[i] - left[i]))) / total, True, N_DAY, 1e-6)
    return out


judged = []
for mode in ("default", "copies"):
    m64 = measures(out_dir(RUNS[(mode, "f64")]), mode)
    m32 = measures(out_dir(RUNS[(mode, "f32")]), mode)
    if m64 is None or m32 is None:
        add("C9", mode, "run", "", "", "", "fail (a run is missing or did not reach 24 h)")
        judged.append(False)
        continue
    for name, (v64, is_judged, n_steps, budget) in m64.items():
        v32 = m32.get(name, (float("nan"),))[0]
        v64, v32 = float(v64), float(v32)
        if budget is not None:
            ok4 = v64 <= budget if math.isfinite(v64) else False
            add("C4", mode, name + ", Float64 against criterion 4", v64, v32, budget,
                "reported (" + ("within" if ok4 else "above") + ")")
        if not is_judged:
            add("C9", mode, name, v64, v32, "", "reported")
            continue
        threshold = max(FACTOR * abs(v64), floor(n_steps))
        ok = math.isfinite(v32) and math.isfinite(v64) and v32 <= threshold
        which = "floor" if floor(n_steps) >= FACTOR * abs(v64) else "10x"
        add("C9", mode, name, v64, v32, threshold, "pass" if ok else "fail",
            f"n_steps {n_steps}, floor {floor(n_steps):.3e}, the threshold is the {which}")
        judged.append(ok)

for p in ("f64", "f32"):
    a = os.path.join(out_dir(RUNS[("default", p)]), "water_tag_closure.csv")
    b = os.path.join(out_dir(OLD[p]), "water_tag_closure.csv")
    same = os.path.exists(a) and os.path.exists(b) and open(a, "rb").read() == open(b, "rb").read()
    add("REP", "default", f"closure table byte for byte with run {'5' if p == 'f64' else '6'} ({p})", "", "", "",
        "reported", "same" if same else "differs")

add("C9", "both", "criterion 9 under the rounding floor, every judged measure", "", "", "",
    "pass" if judged and all(judged) else "fail")

os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "f32_floor_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
if SMOKE:
    print(f"smoke: {len(rows)} rows, window from {T0 / 3600:.1f} h, n_steps {N_DAY}, {N_HALF}, {N_WINDOW}")
else:
    for r in rows:
        if r["rule"] != "C4":
            print(r["rule"], r["mode"], r["metric"], r["f64"], r["f32"], r["threshold"], r["verdict"], r["note"],
                  sep=" | ")
