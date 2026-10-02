"""The G3 baselines on the new physics (design/G3_BASELINE_RERUN.md), scored.

    python3 g3base_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds the runs
`g3b_d4w_{untagged,default,copies}_z60_c`, `g3b_d4w_untagged_z30_c`,
`g3b_d4w_pulse_{default,copies}_z30_c` and `g3b_trmm0m_{untagged,default,copies}_6h`,
each in `output_0000`, and the probes in `g3base_probes/{fixed_parent,refinement}/`.
SCORE_DIR (default: this record's `output/g3base/`) receives:

  - `g3base_scores.csv`: one row per rule, case, mode and metric, with the
    value, the threshold, the verdict and the OD3 row;
  - `windows.csv`: OD2's end of startup per D4-W rung, from its untagged twin;
  - `px5.csv`: PX5's readings (the filter's share and its growth per halving);
  - `verifier/`: the verifier's JSON (`compare_runs.py`).

The rules are those of design/W25_ISOLATION.md, sections 4 and 8 (R1 to R10),
with their OD3 rows, and PX5's rule (PROVENANCE_PATHWAY.md). The code is taken
from `w25_score.py` and `w50_score.py`, with one arm instead of two. Nothing is
new, and nothing is tuned after the runs.

Verdicts: `pass`, `fail`, `flag` (R9, R10: above 0.9), `not assessable` (with
the reason), `reported` (a number a rule reports but does not judge), and
`waits for R6` (R7 where R5 passes and no refinement probe ran on the case).

`G3B_SMOKE=1` reads W50's main arm, W38's probes and W26's TRMM runs under
the old names. It checks this script on real output before the runs. Its
scores mean nothing, and W26 has no untagged twin, so TRMM's R1 is skipped.
"""
import csv
import json
import os
import subprocess
import sys

import netCDF4 as nc
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import w25_compare  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
SCORE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "g3base")
VERIFIER = os.path.join(HERE, "..", "evidence", "compare_runs.py")
SMOKE = os.environ.get("G3B_SMOKE", "") == "1"
PROBES = os.path.join(ROOT, "w25i_probes" if SMOKE else "g3base_probes")
DAY = 86400.0
P1_END = 6 * 3600.0
TRMM_END = 6 * 3600.0
MODES = ("default", "copies")
D4W_CASES = {
    "plain": dict(rung="z60_c", tags=("tropo", "strat", "evap", "evap_tropo", "evap_strat")),
    "pulse": dict(rung="z30_c", tags=("sfc", "air", "evap")),
}
TRMM_TAGS = ("pbl", "free", "evap")
TRMM_PARTITION = ("pbl", "free")

rows = []
px5 = []


def add(rule, case, mode, metric, window, value, threshold, verdict, od3, note=""):
    rows.append(
        dict(rule=rule, case=case, mode=mode, metric=metric, window=window, value=value,
             threshold=threshold, verdict=verdict, od3_row=od3, note=note)
    )


def job(case, mode):
    """The run's name. `case` is plain, pulse or trmm; `mode` default, copies or untagged."""
    if SMOKE:
        if case == "trmm":
            return None if mode == "untagged" else f"w4a_trmm0m_{mode}_6h"
        rung = D4W_CASES[case]["rung"]
        if mode == "untagged":
            return f"w50_d4w_untagged_{rung}"
        prefix = "w50_d4w_pulse" if case == "pulse" else "w50_d4w"
        return f"{prefix}_{mode}_{rung}_main"
    if case == "trmm":
        return f"g3b_trmm0m_{mode}_6h"
    rung = D4W_CASES[case]["rung"]
    if mode == "untagged":
        return f"g3b_d4w_untagged_{rung}"
    prefix = "g3b_d4w_pulse" if case == "pulse" else "g3b_d4w"
    return f"{prefix}_{mode}_{rung}"


def probe_csv(probe, mode, case="plain"):
    if case == "pulse":
        # Run 12 (design section 7a): P2 on the pulse's copies at 30 levels.
        run = "w25i_d4w_pulse_copies_z30_c" if SMOKE else "g3b_d4w_pulse_copies_z30_c"
    else:
        run = f"w25i_d4w_{mode}_z60_c" if SMOKE else f"g3b_d4w_{mode}_z60_c"
    return os.path.join(PROBES, probe, f"{run}_{probe}.csv")


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


def suffix(case):
    return "_30m_inst.nc" if case == "trmm" else "_1h_inst.nc"


def read_nc(directory, name, case):
    """(time, z, values[time, level]) of `<name><suffix>`, dimensions by name."""
    with nc.Dataset(os.path.join(directory, name + suffix(case))) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        values = values.reshape(values.shape[0], -1)
        # A surface field such as `pr` has no `z`.
        z = np.asarray(d["z"][:], dtype=float) if "z" in d.variables else np.zeros(1)
        return np.asarray(d["time"][:], dtype=float), z, values


def thickness(z):
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    return np.diff(faces)


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def verdict(ok):
    return "pass" if ok else "fail"


def ratio_verdict(r, zero_both=False):
    if zero_both:
        return "vacuous (no throughput on either rung)"
    if r is None or not np.isfinite(r):
        return "not assessable (no throughput on the coarser rung)"
    if r <= 0.75:
        return "pass"
    return "flag" if r > 0.9 else "fail"


def verify(reference, run, path, hours, judge):
    """The verifier's JSON for `run` against `reference`, or None."""
    command = [sys.executable, VERIFIER, "--reference", out_dir(reference), "--run", out_dir(run),
               "--family", "water", "--hours", hours, "--json", path]
    if judge:
        command.append("--judge")
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return json.load(open(path)) if os.path.exists(path) else None


# ---------------------------------------------------------------------------
# OD2's windows, from each D4-W rung's untagged twin, by the approved rule
# (as w50_score.py).
# ---------------------------------------------------------------------------
windows = {}
for case, spec in D4W_CASES.items():
    time, water = w25_compare.column_water(out_dir(job(case, "untagged")))
    tendency = np.abs(np.diff(water)) / np.diff(time)
    ends = time[1:]
    level = 0.1 * tendency[ends <= 6 * 3600 + 1e-6].max()
    below = tendency < level
    start = None
    for i in range(len(below) - 2):
        if below[i] and below[i + 1] and below[i + 2]:
            start = ends[i - 1] if i > 0 else time[0]
            break
    windows[case] = None if start is None else float(start)


def established(case, end):
    t0 = windows.get(case)
    if t0 is None:
        return None, "not assessable (OD2's rule finds no end of startup)"
    if t0 >= end - 1e-6:
        return None, f"not assessable (startup ends at {t0 / 3600:.1f} h, after {end / 3600:.0f} h)"
    return t0, ""


# ---------------------------------------------------------------------------
# R1: every model field the untagged twin writes at the tagged runs' period,
# bit for bit. R3: temperature and negative water, every run.
# ---------------------------------------------------------------------------
for case in list(D4W_CASES) + ["trmm"]:
    twin = job(case, "untagged")
    if twin is None:
        add("R1", case, "both", "model fields bit for bit", "whole run", "", 0,
            "not assessable (smoke: no twin)", "Parent validity: parity")
    else:
        untagged = out_dir(twin)
        names = sorted(f for f in os.listdir(untagged) if f.endswith(suffix(case)))
        for mode in MODES:
            tagged = out_dir(job(case, mode))
            differ, missing = [], []
            for f in names:
                other = os.path.join(tagged, f)
                if not os.path.exists(other):
                    missing.append(f)
                    continue
                var = f[: -len(suffix(case))]
                with nc.Dataset(os.path.join(untagged, f)) as a, nc.Dataset(other) as b:
                    same = (
                        a[var].shape == b[var].shape
                        and np.array_equal(bits(np.asarray(a[var][:])), bits(np.asarray(b[var][:])))
                        and np.array_equal(bits(np.asarray(a["time"][:])), bits(np.asarray(b["time"][:])))
                    )
                if not same:
                    differ.append(var)
            note = f"{len(names) - len(missing)} fields compared"
            if differ:
                note += f"; differ: {differ}"
            if missing:
                note += f"; missing in the tagged run: {missing}"
            add("R1", case, mode, "model fields bit for bit", "whole run", len(differ) + len(missing), 0,
                verdict(not differ and not missing), "Parent validity: parity", note)
    for mode in MODES + ("untagged",):
        name = job(case, mode)
        if name is None:
            continue
        d = out_dir(name)
        _, z, ta = read_nc(d, "ta", case)
        _, _, rho = read_nc(d, "rhoa", case)
        _, _, hus = read_nc(d, "hus", case)
        dz = thickness(z)
        floor_points = int(np.sum(ta <= 150.0 + 1e-9))
        top_move = float(np.max(np.abs(ta[:, -1] - ta[0, -1])))
        negative = np.sum(rho * np.minimum(hus, 0) * dz, axis=1)
        total = np.sum(rho * hus * dz, axis=1)
        worst = float(np.max(np.abs(negative) / total))
        add("R3", case, mode, "points at the 150 K floor", "whole run", floor_points, 0,
            verdict(floor_points == 0), "Parent validity: temperature")
        add("R3", case, mode, "top level's temperature change, K", "whole run", top_move, 5.0,
            verdict(top_move < 5.0), "Parent validity: temperature")
        add("R3", case, mode, "negative water over the water, max over outputs", "whole run", worst, 1e-4,
            verdict(worst < 1e-4), "Parent validity: negative water")

# ---------------------------------------------------------------------------
# R4, R5 and R8 from the closure and audit tables. D4-W over a day, as W38
# and W50; TRMM over its 6 h, with the day's budgets applied at its end and
# its rates scaled to a day.
# ---------------------------------------------------------------------------
eligible = {}
for case in list(D4W_CASES) + ["trmm"]:
    end_time = TRMM_END if case == "trmm" else DAY
    tags = TRMM_TAGS if case == "trmm" else D4W_CASES[case]["tags"]
    for mode in MODES:
        d = out_dir(job(case, mode))
        closure = read_csv(os.path.join(d, "water_tag_closure.csv"))
        audit = read_csv(os.path.join(d, "water_tag_audit.csv"))
        if closure is None or audit is None or row_at(closure, end_time) is None:
            add("R4", case, mode, "run", "", "", "", "not assessable (the run did not reach its end)",
                "Closure, water")
            continue
        void = any(r.get("closure_void", 0) or r.get("negative_water_void", 0) for r in closure)
        half = end_time / 2
        G = {t: row_at(closure, t)["gross_relative"] for t in (0.0, half, end_time)}
        A = {t: row_at(closure, t)["gross_residual"] for t in (0.0, half, end_time)}
        label = f"{end_time / 3600:.0f} h"
        add("R4", case, mode, f"gross residual at {label}, of the water", label, G[end_time], 2e-3,
            verdict(G[end_time] <= 2e-3), "Closure, water", "void rows" if void else "")
        first, second = G[half] - G[0.0], G[end_time] - G[half]
        note = (f"first {first:.3e}, second {second:.3e}; absolute (kg/m2) first "
                f"{A[half] - A[0.0]:.4e}, second {A[end_time] - A[half]:.4e}")
        add("R4", case, mode, "second half minus first half, of the water", "0-half-end", second - first,
            0.0, verdict(second <= first) if case != "trmm" else "reported", "Closure, water", note)

        end = row_at(audit, end_time)
        water = row_at(closure, end_time)["total"]
        if case == "trmm":
            t0, why = 0.0, ""
        else:
            t0, why = established(case, end_time)

        def per_day(column, start, divide_by=water):
            s = row_at(audit, start)
            return (end[column] - s[column]) / divide_by / ((end["time"] - s["time"]) / DAY)

        window_label = "whole run" if case == "trmm" else "established"
        # R8: the partition repair's retained gross per day; each tag's led_fix.
        if "led_repair_retained" not in end:
            add("R8", case, mode, "partition repair retained gross per day", window_label, "", 5e-3,
                "not assessable (no ledger column)", "Intervention, aggregate")
        elif t0 is None:
            add("R8", case, mode, "partition repair retained gross per day", window_label, "", 5e-3, why,
                "Intervention, aggregate")
        else:
            value = per_day("led_repair_retained", t0)
            add("R8", case, mode, "partition repair retained gross per day", window_label, value, 5e-3,
                verdict(value <= 5e-3), "Intervention, aggregate",
                f"whole run {per_day('led_repair_retained', 0.0):.3e}")
        for tag in tags:
            key = f"led_fix_{tag}_inventory_fraction"
            if key not in end:
                add("R8", case, mode, f"led_fix inventory fraction, {tag}", window_label, "", 0.02,
                    "not assessable (no per-tag ledger)", "Intervention, per tag")
                continue
            frac = end[key]
            retained = end[f"led_fix_{tag}_retained"]
            inventory = retained / frac if frac > 0 else None
            if t0 is None:
                add("R8", case, mode, f"led_fix inventory fraction, {tag}", window_label, "", 0.02, why,
                    "Intervention, per tag", f"whole run {frac:.3e}")
            else:
                start = row_at(audit, t0)[f"led_fix_{tag}_retained"]
                value = (retained - start) / inventory if inventory else 0.0
                add("R8", case, mode, f"led_fix inventory fraction, {tag}", window_label, value, 0.02,
                    verdict(value <= 0.02), "Intervention, per tag", f"whole run {frac:.3e}")
            key = f"led_inc_{tag}_inventory_fraction"
            if key in end:
                add("R8", case, mode, f"led_inc inventory fraction, {tag}", "whole run", end[key], "",
                    "reported", "Intervention, per tag (led_inc reported)")

        if mode != "copies":
            continue
        # R5: the copies' own residual and their repair.
        own = max(r["copy_residual_relative"] for r in audit if r["time"] <= end_time + 1e-6)
        add("R5", case, mode, "copies' own residual, max over outputs", "whole run", own, 2e-4,
            verdict(own <= 2e-4), "Comparator: its own residual",
            f"at the end {end['copy_residual_relative']:.3e}")
        signed = abs(end["copy_repair_relative"])
        if "led_uprepair_retained" not in end:
            add("R5", case, mode, "copies' repair, gross, per day", window_label, "", 2e-3,
                "not assessable (no ledger column)", "Comparator: its repair", f"signed {signed:.3e}")
            eligible[case] = False
            continue
        whole = per_day("led_uprepair_retained", 0.0)
        if t0 is None:
            ok = False
            add("R5", case, mode, "copies' repair, gross, per day", window_label, "", 2e-3, why,
                "Comparator: its repair")
        else:
            value = per_day("led_uprepair_retained", t0)
            inside = [r["total"] for r in closure if t0 - 1e-6 <= r["time"] <= end_time + 1e-6]
            mean_water = per_day("led_uprepair_retained", t0, divide_by=float(np.mean(inside)))
            ok = value <= 2e-3
            add("R5", case, mode, "copies' repair, gross, per day", window_label, value, 2e-3,
                verdict(ok), "Comparator: its repair",
                f"over the window's mean water {mean_water:.3e}; whole run {whole:.3e}; "
                f"signed ledger at the end {signed:.3e}")
        add("R5", case, mode, "copies' repair, gross, per day", "whole run", whole, 2e-3, "reported",
            "Comparator: its repair")
        eligible[case] = (own <= 2e-4) and ok

# ---------------------------------------------------------------------------
# P1 on the default at 60 levels: R2 (the parent's E, reported at 1 to 4
# iterations, judged at 2) and R10 (each tag's E, two against one).
# ---------------------------------------------------------------------------
def p1_E(table, n, var, keep):
    kept = [r for r in table if keep(r)]
    if not kept or f"error_n{n}_{var}" not in kept[0]:
        return None
    increment = sum(r[f"increment_{var}"] for r in kept)
    error = sum(r[f"error_n{n}_{var}"] for r in kept)
    return error / increment if increment > 0 else None


table = read_csv(probe_csv("fixed_parent", "default"))
if table is None:
    add("R2", "plain", "default", "E rho_q_tot, n2", "", "", 1e-3, "not assessable (P1 has no output)",
        "Parent validity: Newton")
else:
    for r in table:
        r["time"] = r["t_seconds"]
    t0, why = established("plain", P1_END)
    windows_p1 = [("whole 6 h", lambda r: True)]
    if t0 is not None:
        windows_p1.insert(0, ("established", lambda r, t0=t0: r["time"] > t0 + 1e-6))
    else:
        add("R2", "plain", "default", "E rho_q_tot, n2", "established", "", 1e-3, why,
            "Parent validity: Newton")
    for label, keep in windows_p1:
        scored = label == "established"
        E = {n: p1_E(table, n, "ρq_tot", keep) for n in (1, 2, 3, 4)}
        add("R2", "plain", "default", "E rho_q_tot, n2", label, E[2], 1e-3,
            verdict(E[2] is not None and E[2] <= 1e-3) if scored else "reported",
            "Parent validity: Newton", "; ".join(f"E n{n} = {E[n]}" for n in (1, 2, 3, 4)))
        for tag in D4W_CASES["plain"]["tags"]:
            var = f"ρq_tag_{tag}"
            e1, e2 = p1_E(table, 1, var, keep), p1_E(table, 2, var, keep)
            ratio = e2 / e1 if (e1 and e2 is not None) else None
            add("R10", "plain", "default", f"E n2 / E n1, {tag}", label, ratio, 0.75,
                ratio_verdict(ratio) if scored else "reported", "Refinement",
                f"E n1 = {e1}, E n2 = {e2}, E n4 = {p1_E(table, 4, var, keep)}")

# ---------------------------------------------------------------------------
# P2 at 60 levels: R6 (the copies' repair under refinement), R9 (the default's
# repair and inc_left), and PX5's growth of the filter per halving of dt.
# ---------------------------------------------------------------------------
refinement_ok = None
p2 = {}
for mode in MODES:
    table = read_csv(probe_csv("refinement", mode))
    if table is None:
        add("R6" if mode == "copies" else "R9", "plain", mode, "P2", "6-7 h", "", "",
            "not assessable (P2 has no output)", "Comparator: refinement" if mode == "copies" else "Refinement")
        continue
    by = {(int(r["dt"]), int(r["newton"])): r for r in table}
    p2[mode] = by
    if mode == "copies":
        pairs = [((60, 1), (120, 1)), ((30, 1), (60, 1)), ((120, 2), (120, 1)), ((120, 10), (120, 1))]
        refinement_ok = True
        for fine, coarse in pairs:
            a, b = by[fine]["q_tag_led_uprepair_per_hour"], by[coarse]["q_tag_led_uprepair_per_hour"]
            r = a / b if b > 0 else None
            ok = r is not None and r <= 1.1
            refinement_ok &= ok
            moved = by[fine]["parent_hus_change_vs_first"]
            add("R6", "plain", mode, f"copies' repair per hour, {fine} over {coarse}", "6-7 h", r, 1.1,
                verdict(ok), "Comparator: refinement",
                f"{a:.3e} over {b:.3e}" + ("; parent moved more than 1%" if moved > 0.01 else ""))
    else:
        chain = [((60, 1), (120, 1)), ((30, 1), (60, 1)), ((120, 2), (120, 1)), ((120, 10), (120, 2))]
        for ledger in ("q_tag_led_repair_per_hour", "q_tag_inc_left_per_hour"):
            if ledger not in table[0]:
                continue
            for fine, coarse in chain:
                a, b = by[fine][ledger], by[coarse][ledger]
                r = a / b if b > 0 else None
                moved = by[fine]["parent_hus_change_vs_first"]
                add("R9", "plain", mode, f"{ledger.replace('_per_hour', '')}, {fine} over {coarse}", "6-7 h",
                    r, 0.75, ratio_verdict(r, a == 0 and b == 0), "Refinement",
                    f"{a:.3e} over {b:.3e}" + ("; parent moved more than 1%" if moved > 0.01 else ""))

# R6 on the pulse's copies, from run 12 (design section 7a), as on the plain case.
pulse_refinement_ok = None
table = read_csv(probe_csv("refinement", "copies", "pulse"))
if table is not None:
    by = {(int(r["dt"]), int(r["newton"])): r for r in table}
    pulse_refinement_ok = True
    for fine, coarse in [((60, 1), (120, 1)), ((30, 1), (60, 1)), ((120, 2), (120, 1)), ((120, 10), (120, 1))]:
        a, b = by[fine]["q_tag_led_uprepair_per_hour"], by[coarse]["q_tag_led_uprepair_per_hour"]
        r = a / b if b > 0 else None
        ok = r is not None and r <= 1.1
        pulse_refinement_ok &= ok
        moved = by[fine]["parent_hus_change_vs_first"]
        add("R6", "pulse", "copies", f"copies' repair per hour, {fine} over {coarse}", "6-7 h", r, 1.1,
            verdict(ok), "Comparator: refinement",
            f"{a:.3e} over {b:.3e}" + ("; parent moved more than 1%" if moved > 0.01 else ""))

# PX5 (PROVENANCE_PATHWAY.md, PX5 and PT10). (a) The filter's share of the
# copies' two corrections, gross, over the day's established window; (b) its
# growth per halving of dt, per hour, from P2; (c) where it acts, reported.
d = out_dir(job("plain", "copies"))
audit = read_csv(os.path.join(d, "water_tag_audit.csv"))
t0, why = established("plain", DAY)
share = None
if audit is not None and row_at(audit, DAY) is not None and t0 is not None:
    s, e = row_at(audit, t0), row_at(audit, DAY)
    filt = e["led_upfilter_retained"] - s["led_upfilter_retained"]
    rep = e["led_uprepair_retained"] - s["led_uprepair_retained"]
    share = filt / (filt + rep) if filt + rep > 0 else None
    px5.append(dict(reading="share, day, established", value=share, note=f"filter {filt:.4e}, repair {rep:.4e}"))
    s0 = row_at(audit, 0.0)
    filt0 = e["led_upfilter_retained"] - s0["led_upfilter_retained"]
    rep0 = e["led_uprepair_retained"] - s0["led_uprepair_retained"]
    px5.append(dict(reading="share, whole day (reported)", value=filt0 / (filt0 + rep0) if filt0 + rep0 > 0 else "",
                    note=f"filter {filt0:.4e}, repair {rep0:.4e}, filter events {e['led_upfilter_events']:.0f}"))
growth = []
if "copies" in p2 and "q_tag_led_upfilter_per_hour" in next(iter(p2["copies"].values())):
    by = p2["copies"]
    for key in sorted(by, key=lambda k: (-k[0], k[1])):
        f_, r_ = by[key]["q_tag_led_upfilter_per_hour"], by[key]["q_tag_led_uprepair_per_hour"]
        px5.append(dict(reading=f"P2 per hour, dt {key[0]} s, {key[1]} iterations", value=f_ / (f_ + r_)
                        if f_ + r_ > 0 else "", note=f"filter {f_:.4e}, repair {r_:.4e} (share of the two)"))
    for fine, coarse in (((60, 1), (120, 1)), ((30, 1), (60, 1))):
        a, b = by[fine]["q_tag_led_upfilter_per_hour"], by[coarse]["q_tag_led_upfilter_per_hour"]
        g = a / b if b > 0 else None
        growth.append(g)
        px5.append(dict(reading=f"filter growth, {fine} over {coarse}", value=g, note=f"{a:.4e} over {b:.4e}"))
# The rule needs both clauses. A share below 0.7 decides it without the growth.
if share is not None and share < 0.7:
    add("PX5", "plain", "copies", "filter share >= 0.7 and growth >= 1.5 per halving", "established; 6-7 h",
        share, "0.7; 1.5", "no eligible D4-like comparator at production cost", "PX5 (PT10)",
        "the share is below 0.7; growth " + ", ".join("none" if g is None else f"{g:.3f}" for g in growth))
elif share is None or len(growth) < 2 or any(g is None for g in growth):
    add("PX5", "plain", "copies", "filter share >= 0.7 and growth >= 1.5 per halving", "established; 6-7 h",
        share, "0.7; 1.5", "not assessable (a reading is missing)", "PX5 (PT10)")
else:
    per_step = share >= 0.7 and min(growth) >= 1.5
    add("PX5", "plain", "copies", "filter share >= 0.7 and growth >= 1.5 per halving", "established; 6-7 h",
        share, "0.7; 1.5",
        "per-step cause" if per_step else "no eligible D4-like comparator at production cost",
        "PX5 (PT10)", f"growth {growth[0]:.3f}, {growth[1]:.3f}")
try:
    time, z, gross = read_nc(d, "q_tag_led_upfilter_gross", "plain")
    _, _, rho = read_nc(d, "rhoa", "plain")
    _, _, clw = read_nc(d, "clw", "plain")
    i0 = int(np.searchsorted(time, (t0 or 0.0) - 1e-6))
    dz = thickness(z)
    added = (gross[-1] - gross[i0]) * rho[-1] * dz
    tops = [z[np.nonzero(row > 1e-5)[0][-1]] for row in clw[i0:] if np.any(row > 1e-5)]
    top = float(np.mean(tops)) if tops else float("nan")
    near = float(added[np.abs(z - top) <= 50.0].sum() / added.sum()) if added.sum() > 0 else float("nan")
    px5.append(dict(reading="filter gross within 50 m of the mean cloud top", value=near,
                    note=f"cloud top {top:.0f} m (clw > 1e-5); largest level {z[int(np.argmax(added))]:.0f} m"))
except (OSError, KeyError, IndexError) as error:
    px5.append(dict(reading="filter gross by level", value="", note=f"not read: {error}"))

# ---------------------------------------------------------------------------
# R7: default against copies per tag. D4-W at 1 h and 24 h (`--judge`), a
# verdict only where R5 and R6 pass on the case; TRMM at 1, 3 and 6 h,
# reported only (TRMM has no refinement probe here; PX12 is its refinement).
# ---------------------------------------------------------------------------
os.makedirs(os.path.join(SCORE, "verifier"), exist_ok=True)
for case in D4W_CASES:
    path = os.path.join(SCORE, "verifier", f"r7_{case}.json")
    report = verify(job(case, "copies"), job(case, "default"), path, "0,1,12,24", True)
    if report is None:
        add("R7", case, "default vs copies", "verifier", "", "", "", "not assessable (verifier failed)",
            "Provenance")
        continue
    if not eligible.get(case):
        status = "not assessable (R5 failed)"
    elif case == "plain" and refinement_ok:
        status = None
    elif case == "plain":
        status = "not assessable (R6 failed)"
    elif pulse_refinement_ok is None:
        status = "waits for R6 (no P2 on this case)"
    elif pulse_refinement_ok:
        status = None
    else:
        status = "not assessable (R6 failed)"
    for jr in report["judge"]["rows"]:
        m = report["tag_metrics"][jr["tag"]][str(jr["hour"])]
        value = m["abs_L1"] if jr["small"] else m["L1_mass_weighted"]
        metric = f"{jr['tag']} at {jr['hour']} h, " + ("abs L1 (small tag)" if jr["small"] else "L1")
        judged = "pass" if jr["passed"] else "fail"
        add("R7", case, "default vs copies", metric, f"{jr['hour']} h", value, "see note",
            judged if status is None else status, "Provenance, per tag",
            f"{jr['reason']}; L-inf {m.get('Linf_peak_normalized', '')}; judged {judged} if it were scored")
path = os.path.join(SCORE, "verifier", "r7_trmm.json")
report = verify(job("trmm", "copies"), job("trmm", "default"), path, "1,3,6", False)
if report is None:
    add("R7", "trmm", "default vs copies", "verifier", "", "", "", "not assessable (verifier failed)", "Provenance")
else:
    for tag, by_hour in sorted(report["tag_metrics"].items()):
        for hour, m in sorted(by_hour.items(), key=lambda kv: float(kv[0])):
            add("R7", "trmm", "default vs copies", f"{tag} at {hour} h, L1", f"{hour} h",
                m.get("L1_mass_weighted", ""), "reported", "reported", "Provenance, per tag",
                f"L-inf {m.get('Linf_peak_normalized', '')}; abs L1 {m.get('abs_L1', '')}")

# ---------------------------------------------------------------------------
# Criterion 7 on TRMM 0M: the partition's surface precipitation by tag
# against `pr`, at every output with rain, both modes. Reported, as W26.
# ---------------------------------------------------------------------------
for mode in MODES:
    d = out_dir(job("trmm", mode))
    try:
        _, _, pr = read_nc(d, "pr", "trmm")
        parts = {tag: read_nc(d, f"pr_tag_{tag}", "trmm")[2] for tag in TRMM_TAGS}
    except (OSError, KeyError) as error:
        add("C7", "trmm", mode, "sum of the partition's pr_tag against pr", "", "", "",
            f"not assessable ({error})", "Criterion 7")
        continue
    pr = pr[:, 0]
    total = sum(parts[t][:, 0] for t in TRMM_PARTITION)
    raining = np.abs(pr) > 1e-12
    if not raining.any():
        add("C7", "trmm", mode, "sum of the partition's pr_tag against pr", "outputs with rain", "", "",
            "not assessable (no rain at an output)", "Criterion 7")
        continue
    rel = np.abs(total[raining] - pr[raining]) / np.abs(pr[raining])
    evap = parts["evap"][:, 0][raining] / pr[raining]
    add("C7", "trmm", mode, "sum of the partition's pr_tag against pr, max relative", "outputs with rain",
        float(rel.max()), "reported (W26: 1.8e-3)", "reported", "Criterion 7",
        f"{int(raining.sum())} outputs with rain; evap's share {evap.min():.3f} to {evap.max():.3f}")

# ---------------------------------------------------------------------------
# Write.
# ---------------------------------------------------------------------------
os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "g3base_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow({k: (repr(v) if isinstance(v, float) else v) for k, v in r.items()})
with open(os.path.join(SCORE, "px5.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["reading", "value", "note"])
    w.writeheader()
    for r in px5:
        w.writerow({k: (repr(v) if isinstance(v, float) else v) for k, v in r.items()})
with open(os.path.join(SCORE, "windows.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["case", "startup_end_seconds"])
    for case, start in sorted(windows.items()):
        w.writerow([case, start if start is not None else "none"])

from collections import Counter  # noqa: E402

for rule in ("R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "PX5", "C7"):
    tally = Counter(r["verdict"].split(" (")[0] for r in rows if r["rule"] == rule)
    print(rule, dict(tally))
