"""V-W7, criterion 9: the Float32 twin of D4-W (design/F32_TWIN.md), scored.

    python3 f32_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds, each in
`output_0000`:

  - the Float32 runs `f32_d4w_{untagged,default,copies}_z60_c`;
  - the Float64 reference `g3b_d4w_{untagged,default,copies}_z60_c` (W54,
    W55, model `b34bbd8b`);
  - the Float64 confirmation `f32_d4w_default_z60_c_f64` (model `d3c5e42f`).

SCORE_DIR (default: this record's `output/f32/`) receives `f32_scores.csv`
(one row per rule, mode and metric, with the Float64 value, the Float32 value,
their ratio, the threshold and the verdict) and `windows.csv`.

The rules are the design's section 3:

  - P0: the Float64 confirmation against the reference, bit for bit in every
    NetCDF file and byte for byte in the closure and audit tables. It says
    whether W54's and W55's numbers hold on `d3c5e42f`.
  - R1: each Float32 tagged run against the Float32 untagged twin, every model
    field the twin writes, bit for bit (criterion 3 within Float32).
  - M: each criterion-4 measure of `g3base_score.py` (R4, R5, R8), computed the
    same way for both precisions over the same window. A measure passes when
    its Float32 value is at most 10 times its Float64 value. Where the Float64
    value is zero, there is no factor to apply, and the measure is judged on
    its own row's budget instead.
  - Reported, not judged: the whole-day readings, `led_inc`, the
    second-half rule as written (`second <= first`), R3, and the parent's
    precision difference (Float32 against Float64 untagged column water).

Criterion 9 reads pass when R1 passes in both modes and every judged measure
passes. A non-finite value or a missing hour is a failure.

`F32_SMOKE=1` reads the Float64 runs as the Float32 runs too. Every ratio is
then 1 and every rule passes. It checks this script on real output before the
runs, and its scores mean nothing.
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
SMOKE = os.environ.get("F32_SMOKE", "") == "1"
DAY = 86400.0
MODES = ("default", "copies")
TAGS = ("tropo", "strat", "evap", "evap_tropo", "evap_strat")
FACTOR = 10.0
SUFFIX = "_1h_inst.nc"

F64 = {m: f"g3b_d4w_{m}_z60_c" for m in ("untagged",) + MODES}
F32 = dict(F64) if SMOKE else {m: f"f32_d4w_{m}_z60_c" for m in ("untagged",) + MODES}
CONFIRM = "g3b_d4w_default_z60_c" if SMOKE else "f32_d4w_default_z60_c_f64"

rows = []


def add(rule, mode, metric, window, f64, f32, threshold, verdict, note=""):
    ratio = ""
    if isinstance(f64, float) and isinstance(f32, float) and f64 != 0.0:
        ratio = f32 / f64
    rows.append(dict(rule=rule, mode=mode, metric=metric, window=window, f64=f64, f32=f32, ratio=ratio,
                     threshold=threshold, verdict=verdict, note=note))


def out_dir(name):
    return os.path.join(ROOT, name, "output_0000")


def read_csv(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def row_at(table, time):
    """The first row at or after `time`."""
    for r in table:
        if r["time"] >= time - 1e-6:
            return r
    return None


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def same_nc(path_a, path_b, var):
    with nc.Dataset(path_a) as a, nc.Dataset(path_b) as b:
        return (
            a[var].shape == b[var].shape
            and a[var].dtype == b[var].dtype
            and np.array_equal(bits(np.asarray(a[var][:])), bits(np.asarray(b[var][:])))
            and np.array_equal(bits(np.asarray(a["time"][:])), bits(np.asarray(b["time"][:])))
        )


def read_nc(directory, name, suffix=SUFFIX):
    with nc.Dataset(os.path.join(directory, name + suffix)) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        values = values.reshape(values.shape[0], -1)
        z = np.asarray(d["z"][:], dtype=float) if "z" in d.variables else np.zeros(1)
        return np.asarray(d["time"][:], dtype=float), z, values


def column_water(run_dir):
    """`w25_compare.column_water`: the parent's water every 10 minutes."""
    time, z, rho = read_nc(run_dir, "rhoa", "_10m_inst.nc")
    _, _, q = read_nc(run_dir, "hus", "_10m_inst.nc")
    dz = np.gradient(z) if z.size > 1 else np.ones(1)
    return time, (rho * q * dz).sum(axis=1)


def od2_window(run_dir):
    """OD2's end of startup, as `g3base_score.py` reads it from the twin."""
    time, water = column_water(run_dir)
    tendency = np.abs(np.diff(water)) / np.diff(time)
    ends = time[1:]
    level = 0.1 * tendency[ends <= 6 * 3600 + 1e-6].max()
    below = tendency < level
    for i in range(len(below) - 2):
        if below[i] and below[i + 1] and below[i + 2]:
            return float(ends[i - 1] if i > 0 else time[0])
    return None


def finite(x):
    return isinstance(x, float) and math.isfinite(x)


# ---------------------------------------------------------------------------
# P0: the Float64 confirmation on d3c5e42f against the reference on b34bbd8b.
# ---------------------------------------------------------------------------
ref, conf = out_dir(F64["default"]), out_dir(CONFIRM)
if not os.path.isdir(conf):
    add("P0", "default", "Float64 on d3c5e42f against b34bbd8b, bit for bit", "whole run", "", "", 0,
        "not assessable (no confirmation run)")
else:
    names = sorted(f for f in os.listdir(ref) if f.endswith(".nc"))
    differ = []
    for f in names:
        other = os.path.join(conf, f)
        var = f.split("_1h_")[0].split("_10m_")[0]
        if not os.path.exists(other) or not same_nc(os.path.join(ref, f), other, var):
            differ.append(f)
    for table in ("water_tag_closure.csv", "water_tag_audit.csv"):
        a, b = os.path.join(ref, table), os.path.join(conf, table)
        if not os.path.exists(b) or open(a, "rb").read() != open(b, "rb").read():
            differ.append(table)
    add("P0", "default", "Float64 on d3c5e42f against b34bbd8b, bit for bit", "whole run", "", float(len(differ)),
        0, "pass" if not differ else "fail",
        f"{len(names)} NetCDF files and 2 tables" + (f"; differ: {differ}" if differ else ""))

# ---------------------------------------------------------------------------
# R1 within Float32: each tagged run against the untagged twin.
# ---------------------------------------------------------------------------
parity = {}
untagged = out_dir(F32["untagged"])
names = sorted(f for f in os.listdir(untagged) if f.endswith(SUFFIX)) if os.path.isdir(untagged) else []
for mode in MODES:
    tagged = out_dir(F32[mode])
    differ, missing = [], []
    for f in names:
        other = os.path.join(tagged, f)
        if not os.path.exists(other):
            missing.append(f)
            continue
        if not same_nc(os.path.join(untagged, f), other, f[: -len(SUFFIX)]):
            differ.append(f[: -len(SUFFIX)])
    ok = bool(names) and not differ and not missing
    parity[mode] = ok
    note = f"{len(names) - len(missing)} fields compared"
    if differ:
        note += f"; differ: {differ}"
    if missing:
        note += f"; missing in the tagged run: {missing}"
    if not names:
        note = "no untagged Float32 output"
    add("R1", mode, "Float32 model fields bit for bit with the Float32 twin", "whole run", "",
        float(len(differ) + len(missing)), 0, "pass" if ok else "fail", note)

# ---------------------------------------------------------------------------
# The window: OD2's rule on the Float64 twin, applied to both precisions. The
# Float32 twin's own window is reported.
# ---------------------------------------------------------------------------
t0 = od2_window(out_dir(F64["untagged"]))
t0_f32 = od2_window(untagged) if os.path.isdir(untagged) else None
os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "windows.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["twin", "startup_end_seconds"])
    w.writerow(["float64", t0 if t0 is not None else "none"])
    w.writerow(["float32", t0_f32 if t0_f32 is not None else "none"])
if t0 is None:
    sys.exit("OD2's rule finds no end of startup on the Float64 twin; the design has no fallback.")


# ---------------------------------------------------------------------------
# The criterion-4 measures, as g3base_score.py computes R4, R5 and R8.
# Each entry: name -> (value, judged, the row's own budget, window label).
# ---------------------------------------------------------------------------
def measures(run_dir, mode):
    closure = read_csv(os.path.join(run_dir, "water_tag_closure.csv"))
    audit = read_csv(os.path.join(run_dir, "water_tag_audit.csv"))
    if closure is None or audit is None or row_at(closure, DAY) is None or row_at(audit, DAY) is None:
        return None
    out = {}
    half = DAY / 2
    G = {t: row_at(closure, t)["gross_relative"] for t in (0.0, half, DAY)}
    A = {t: row_at(closure, t)["gross_residual"] for t in (0.0, half, DAY)}
    first, second = G[half] - G[0.0], G[DAY] - G[half]
    out["R4 gross residual at 24 h, of the water"] = (G[DAY], True, 2e-3, "24 h")
    out["R4 the second 12 h's addition, of the water"] = (second, True, None, "12-24 h")
    out["R4 second minus first 12 h, of the water (rule as written: <= 0)"] = (second - first, False, 0.0, "0-12-24 h")
    out["R4 the second 12 h's addition, kg/m2"] = (A[DAY] - A[half], False, None, "12-24 h")
    end = row_at(audit, DAY)
    water = row_at(closure, DAY)["total"]

    def per_day(column, start, divide_by=water):
        s = row_at(audit, start)
        return (end[column] - s[column]) / divide_by / ((end["time"] - s["time"]) / DAY)

    out["R8 partition repair retained gross per day"] = (per_day("led_repair_retained", t0), True, 5e-3,
                                                         "established")
    out["R8 partition repair retained gross per day, whole day"] = (per_day("led_repair_retained", 0.0), False,
                                                                    5e-3, "whole day")
    for tag in TAGS:
        key = f"led_fix_{tag}_inventory_fraction"
        if key not in end:
            continue
        frac = end[key]
        retained = end[f"led_fix_{tag}_retained"]
        inventory = retained / frac if frac > 0 else None
        start = row_at(audit, t0)[f"led_fix_{tag}_retained"]
        value = (retained - start) / inventory if inventory else 0.0
        out[f"R8 led_fix inventory fraction, {tag}"] = (value, True, 0.02, "established")
        out[f"R8 led_fix inventory fraction, {tag}, whole day"] = (frac, False, 0.02, "whole day")
        key = f"led_inc_{tag}_inventory_fraction"
        if key in end:
            out[f"R8 led_inc inventory fraction, {tag}"] = (end[key], False, None, "whole day")
    if mode == "copies":
        own = max(r["copy_residual_relative"] for r in audit if r["time"] <= DAY + 1e-6)
        out["R5 copies' own residual, max over outputs"] = (own, True, 2e-4, "whole run")
        out["R5 copies' repair, gross, per day"] = (per_day("led_uprepair_retained", t0), True, 2e-3, "established")
        inside = [r["total"] for r in closure if t0 - 1e-6 <= r["time"] <= DAY + 1e-6]
        out["R5 copies' repair, gross, per day, over the window's mean water"] = (
            per_day("led_uprepair_retained", t0, divide_by=float(np.mean(inside))), False, 2e-3, "established")
        out["R5 copies' repair, gross, per day, whole day"] = (per_day("led_uprepair_retained", 0.0), False, 2e-3,
                                                               "whole day")
    return out


judged = []
for mode in MODES:
    m64 = measures(out_dir(F64[mode]), mode)
    m32 = measures(out_dir(F32[mode]), mode) if os.path.isdir(out_dir(F32[mode])) else None
    if m64 is None:
        sys.exit(f"the Float64 reference {F64[mode]} is incomplete")
    if m32 is None:
        add("M", mode, "run", "", "", "", "", "fail (the Float32 run did not reach 24 h)")
        judged.append(False)
        continue
    for name, (v64, is_judged, budget, window) in m64.items():
        v32 = m32.get(name, (None,))[0]
        v32 = float(v32) if v32 is not None else None
        v64 = float(v64)
        if not finite(v32):
            add("M", mode, name, window, v64, v32 if v32 is not None else "", "", "fail (missing or non-finite)")
            judged.append(False) if is_judged else None
            continue
        if not is_judged:
            add("M", mode, name, window, v64, v32, budget if budget is not None else "", "reported")
            continue
        if v64 == 0.0:
            ok = v32 <= budget
            add("M", mode, name, window, v64, v32, budget, "pass" if ok else "fail",
                "Float64 value is zero: judged on the row's own budget")
        else:
            threshold = FACTOR * abs(v64)
            ok = v32 <= threshold
            note = "" if budget is None else f"the row's own budget {budget:g}: {'within' if v32 <= budget else 'above'}"
            add("M", mode, name, window, v64, v32, threshold, "pass" if ok else "fail", note)
        judged.append(ok)

# ---------------------------------------------------------------------------
# Reported: R3 on the Float32 runs, and the parent's precision difference.
# ---------------------------------------------------------------------------
for mode in ("untagged",) + MODES:
    d = out_dir(F32[mode])
    if not os.path.isdir(d):
        continue
    _, z, ta = read_nc(d, "ta")
    _, _, rho = read_nc(d, "rhoa")
    _, _, hus = read_nc(d, "hus")
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    dz = np.diff(faces)
    negative = np.sum(rho * np.minimum(hus, 0) * dz, axis=1)
    total = np.sum(rho * hus * dz, axis=1)
    add("R3", mode, "points at the 150 K floor", "whole run", "", float(np.sum(ta <= 150.0 + 1e-9)), 0, "reported")
    add("R3", mode, "top level's temperature change, K", "whole run", "",
        float(np.max(np.abs(ta[:, -1] - ta[0, -1]))), 5.0, "reported")
    add("R3", mode, "negative water over the water, max over outputs", "whole run", "",
        float(np.max(np.abs(negative) / total)), 1e-4, "reported")
if os.path.isdir(untagged):
    t64, w64 = column_water(out_dir(F64["untagged"]))
    t32, w32 = column_water(untagged)
    n = min(len(t64), len(t32))
    rel = np.abs(w32[:n] - w64[:n]) / np.abs(w64[:n])
    add("PREC", "untagged", "parent's column water, Float32 against Float64, relative", "24 h", float(w64[n - 1]),
        float(w32[n - 1]), "", "reported", f"at 24 h {rel[n - 1]:.3e}; largest over the 10-minute outputs {rel.max():.3e}")

verdict9 = all(parity.get(m, False) for m in MODES) and all(judged)
add("C9", "both", "criterion 9: R1 in both modes and every judged measure", "", "", "", "",
    "pass" if verdict9 else "fail")

with open(os.path.join(SCORE, "f32_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)

for r in rows:
    if r["verdict"] != "reported" or r["rule"] in ("PREC",):
        print(r["rule"], r["mode"], r["metric"], r["f64"], r["f32"], r["threshold"], r["verdict"], r["note"],
              sep=" | ")
