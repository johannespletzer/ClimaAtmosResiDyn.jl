"""W25's isolation, scored: the ten pass rules of design/W25_ISOLATION.md,
section 4, each against its OD3 row (ROADMAP.md, approved 2026-09-24).

    python3 w25_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds the P4 runs
`w25i_d4w_{default,copies,untagged}_z{30,60,120}_{c,fo}/output_0000` and the
probes in `w25i_probes/{fixed_parent,refinement,first_step}/`. SCORE_DIR
(default: this record's `output/w25i/`) receives:
  - `w25_scores.csv`: one row per rule, rung, mode and metric, with the value,
    the threshold, the verdict and the OD3 row;
  - `windows.csv`: OD2's startup end per rung, from the untagged twin;
  - `first_step.csv`: P3, each tag's L1 between the modes at 1 h per variant;
  - `verifier/`: the verifier's JSON for R7 (`compare_runs.py --judge`).

Verdicts: `pass`, `fail`, `flag` (R9, R10: above 0.9, a structural cause),
`not assessable` (with the reason), `reported` (a number the rule reports but
does not judge). Where OD2's rule finds no end of startup, or the window is
empty, a window-based rule is not assessable, and the whole-period value is
written beside it as `reported`. Nothing here is tuned after the runs.
"""
import csv
import glob
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
SCORE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "w25i")
PROBES = os.path.join(ROOT, "w25i_probes")
VERIFIER = os.path.join(HERE, "..", "evidence", "compare_runs.py")
RUNGS = [f"z{z}_{r}" for z in (30, 60, 120) for r in ("c", "fo")]
MODES = ("default", "copies")
TAGS = ("tropo", "strat", "evap", "evap_tropo", "evap_strat")
DAY = 86400.0
P1_END = 6 * 3600.0

rows = []


def add(rule, rung, mode, metric, window, value, threshold, verdict, od3, note=""):
    rows.append(
        dict(rule=rule, rung=rung, mode=mode, metric=metric, window=window,
             value=value, threshold=threshold, verdict=verdict, od3_row=od3, note=note)
    )


def out_dir(kind, rung):
    return os.path.join(ROOT, f"w25i_d4w_{kind}_{rung}", "output_0000")


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


def read_nc(directory, name):
    """(time, z, values[time, z]) of `<name>_1h_inst.nc`, dimensions by name."""
    path = os.path.join(directory, f"{name}_1h_inst.nc")
    with nc.Dataset(path) as d:
        v = d[name]
        values = np.moveaxis(np.asarray(v[:], dtype=float), v.dimensions.index("time"), 0)
        return np.asarray(d["time"][:], dtype=float), np.asarray(d["z"][:], dtype=float), values


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


# ---------------------------------------------------------------------------
# OD2's windows, from each rung's untagged twin.
# ---------------------------------------------------------------------------
windows = {}
for rung in RUNGS:
    directory = out_dir("untagged", rung)
    time, water = w25_compare.column_water(directory)
    tendency = np.abs(np.diff(water)) / np.diff(time)
    ends = time[1:]
    level = 0.1 * tendency[ends <= 6 * 3600 + 1e-6].max()
    below = tendency < level
    start = None
    for i in range(len(below) - 2):
        if below[i] and below[i + 1] and below[i + 2]:
            start = ends[i - 1] if i > 0 else time[0]
            break
    windows[rung] = None if start is None else float(start)
    add("OD2", rung, "untagged", "startup_end_seconds", "", start if start is not None else "none",
        "", "reported", "OD2 windows", f"level {level:.3e} kg m^-2 s^-1")


def established(rung, end):
    t0 = windows[rung]
    if t0 is None:
        return None, "not assessable (OD2's rule finds no end of startup)"
    if t0 >= end - 1e-6:
        return None, f"not assessable (startup ends at {t0 / 3600:.1f} h, after {end / 3600:.0f} h)"
    return t0, ""


# ---------------------------------------------------------------------------
# R1: parity of every model field against the untagged twin.
# ---------------------------------------------------------------------------
for rung in RUNGS:
    untagged = out_dir("untagged", rung)
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(untagged, "*_1h_*.nc")))
    for mode in MODES:
        tagged = out_dir(mode, rung)
        differ, missing = [], []
        for f in names:
            other = os.path.join(tagged, f)
            if not os.path.exists(other):
                missing.append(f)
                continue
            var = f.rsplit("_", 2)[0]
            with nc.Dataset(os.path.join(untagged, f)) as a, nc.Dataset(other) as b:
                same = (
                    a[var].shape == b[var].shape
                    and np.array_equal(bits(np.asarray(a[var][:])), bits(np.asarray(b[var][:])))
                    and np.array_equal(bits(np.asarray(a["time"][:])), bits(np.asarray(b["time"][:])))
                )
            if not same:
                differ.append(var)
        ok = not differ and not missing
        note = f"{len(names) - len(missing)} fields compared"
        if differ:
            note += f"; differ: {differ}"
        if missing:
            note += f"; missing in the tagged run: {missing}"
        add("R1", rung, mode, "model fields bit for bit", "whole day", len(differ) + len(missing),
            0, verdict(ok), "Parent validity: parity", note)

# ---------------------------------------------------------------------------
# P1: R2 (the parent's E at two iterations) and R10 (each tag's E, two
# against one).
# ---------------------------------------------------------------------------
def p1_E(table, n, var, keep):
    kept = [r for r in table if keep(r)]
    if not kept:
        return None
    increment = sum(r[f"increment_{var}"] for r in kept)
    error = sum(r[f"error_n{n}_{var}"] for r in kept)
    return error / increment if increment > 0 else None


for rung in RUNGS:
    for mode in MODES:
        run = f"w25i_d4w_{mode}_{rung}"
        table = read_csv(os.path.join(PROBES, "fixed_parent", f"{run}_fixed_parent.csv"))
        if table is None:
            reason = "not assessable (P1 failed: the 10-iteration reference diverged; README)"
            add("R2", rung, mode, "E rho_q_tot, n2", "", "", 1e-3, reason, "Parent validity: Newton")
            add("R10", rung, mode, "E n2 / E n1, each tag", "", "", 0.75, reason, "Refinement")
            continue
        for r in table:
            r["time"] = r["t_seconds"]
        t0, why = established(rung, P1_END)
        windows_p1 = [("whole 6 h", lambda r: True)]
        if t0 is not None:
            windows_p1.insert(0, ("established", lambda r, t0=t0: r["time"] > t0 + 1e-6))
            windows_p1.append(("startup", lambda r, t0=t0: r["time"] <= t0 + 1e-6))
        for label, keep in windows_p1:
            scored = label == "established"
            E2 = p1_E(table, 2, "ρq_tot", keep)
            E1 = p1_E(table, 1, "ρq_tot", keep)
            add("R2", rung, mode, "E rho_q_tot, n2", label, E2, 1e-3,
                verdict(E2 is not None and E2 <= 1e-3) if scored else "reported",
                "Parent validity: Newton", f"E n1 = {E1}")
            for tag in TAGS:
                var = f"ρq_tag_{tag}"
                e1, e2 = p1_E(table, 1, var, keep), p1_E(table, 2, var, keep)
                ratio = e2 / e1 if (e1 and e2 is not None) else None
                add("R10", rung, mode, f"E n2 / E n1, {tag}", label, ratio, 0.75,
                    ratio_verdict(ratio) if scored else "reported", "Refinement",
                    f"E n1 = {e1}, E n2 = {e2}")
        if t0 is None:
            add("R2", rung, mode, "E rho_q_tot, n2", "established", "", 1e-3, why, "Parent validity: Newton")
            add("R10", rung, mode, "E n2 / E n1, each tag", "established", "", 0.75, why, "Refinement")

# ---------------------------------------------------------------------------
# R3: temperature and negative water, on each tagged run (P4).
# ---------------------------------------------------------------------------
for rung in RUNGS:
    for mode in MODES + ("untagged",):
        d = out_dir(mode, rung)
        _, z, ta = read_nc(d, "ta")
        _, _, rho = read_nc(d, "rhoa")
        _, _, hus = read_nc(d, "hus")
        dz = thickness(z)
        floor_points = int(np.sum(ta <= 150.0 + 1e-9))
        top_move = float(np.max(np.abs(ta[:, -1] - ta[0, -1])))
        negative = np.sum(rho * np.minimum(hus, 0) * dz, axis=1)
        total = np.sum(rho * hus * dz, axis=1)
        worst = float(np.max(np.abs(negative) / total))
        add("R3", rung, mode, "points at the 150 K floor", "whole day", floor_points, 0,
            verdict(floor_points == 0), "Parent validity: temperature")
        add("R3", rung, mode, "top level's temperature change, K", "whole day", top_move, 5.0,
            verdict(top_move < 5.0), "Parent validity: temperature")
        add("R3", rung, mode, "negative water over the water, max over hours", "whole day", worst, 1e-4,
            verdict(worst < 1e-4), "Parent validity: negative water")

# ---------------------------------------------------------------------------
# R4, R5, R8 from the closure and audit CSVs (P4).
# ---------------------------------------------------------------------------
repair_verdicts = {}
for rung in RUNGS:
    for mode in MODES:
        d = out_dir(mode, rung)
        closure = read_csv(os.path.join(d, "water_tag_closure.csv"))
        audit = read_csv(os.path.join(d, "water_tag_audit.csv"))
        void = any(r.get("void", 0) for r in closure)
        G = {h: row_at(closure, h * 3600)["gross_relative"] for h in (0, 12, 24)}
        add("R4", rung, mode, "gross residual at 24 h, of the water", "24 h", G[24], 2e-3,
            verdict(G[24] <= 2e-3), "Closure, water", "void rows" if void else "")
        second = G[24] - G[12]
        first = G[12] - G[0]
        add("R4", rung, mode, "second 12 h minus first 12 h", "0-12-24 h", second - first, 0.0,
            verdict(second <= first), "Closure, water", f"first {first:.3e}, second {second:.3e}")

        end = row_at(audit, DAY)
        water = row_at(closure, DAY)["total"]
        t0, why = established(rung, DAY)

        def per_day(column, start):
            s = row_at(audit, start)
            return (end[column] - s[column]) / water / ((end["time"] - s["time"]) / DAY)

        # R8: the partition repair's retained gross per day; each tag's led_fix.
        whole = per_day("led_repair_retained", 0.0)
        if t0 is not None:
            value = per_day("led_repair_retained", t0)
            add("R8", rung, mode, "partition repair retained gross per day", "established", value, 5e-3,
                verdict(value <= 5e-3), "Intervention, aggregate", f"whole day {whole:.3e}")
        else:
            add("R8", rung, mode, "partition repair retained gross per day", "established", "", 5e-3,
                why, "Intervention, aggregate")
            add("R8", rung, mode, "partition repair retained gross per day", "whole day", whole, 5e-3,
                "reported", "Intervention, aggregate")
        for tag in TAGS:
            frac = end[f"led_fix_{tag}_inventory_fraction"]
            retained = end[f"led_fix_{tag}_retained"]
            # The tag's inventory at 24 h, from the audit's own fraction.
            inventory = retained / frac if frac > 0 else None
            if t0 is None:
                add("R8", rung, mode, f"led_fix inventory fraction, {tag}", "established", "", 0.02, why,
                    "Intervention, per tag")
                add("R8", rung, mode, f"led_fix inventory fraction, {tag}", "whole day", frac, 0.02,
                    "reported", "Intervention, per tag")
                continue
            start = row_at(audit, t0)[f"led_fix_{tag}_retained"]
            value = (retained - start) / inventory if inventory else 0.0
            add("R8", rung, mode, f"led_fix inventory fraction, {tag}", "established", value, 0.02,
                verdict(value <= 0.02), "Intervention, per tag", f"whole day {frac:.3e}")
            key = f"led_inc_{tag}_inventory_fraction"
            if key in end:
                add("R8", rung, mode, f"led_inc inventory fraction, {tag}", "whole day", end[key], "",
                    "reported", "Intervention, per tag (led_inc reported)")

        if mode != "copies":
            continue
        # R5: the copies' own residual and their repair.
        own = max(r["copy_residual_relative"] for r in audit)
        add("R5", rung, mode, "copies' own residual, max over hours", "whole day", own, 2e-4,
            verdict(own <= 2e-4), "Comparator: its own residual",
            f"at 24 h {end['copy_residual_relative']:.3e}")
        signed = abs(end["copy_repair_relative"])
        whole = per_day("led_uprepair_retained", 0.0)
        if t0 is not None:
            value = per_day("led_uprepair_retained", t0)
            ok = value <= 2e-3
            add("R5", rung, mode, "copies' repair, gross, per day", "established", value, 2e-3,
                verdict(ok), "Comparator: its repair",
                f"whole day {whole:.3e}; signed ledger over the day {signed:.3e}")
        else:
            ok = None
            add("R5", rung, mode, "copies' repair, gross, per day", "established", "", 2e-3, why,
                "Comparator: its repair")
            add("R5", rung, mode, "copies' repair, gross, per day", "whole day", whole, 2e-3,
                "reported", "Comparator: its repair", f"signed ledger over the day {signed:.3e}")
        repair_verdicts[rung] = (own <= 2e-4) and bool(ok)

# ---------------------------------------------------------------------------
# P2: R6 (the copies' repair under refinement) and R9 (the default's repair
# and inc_left, finer against coarser).
# ---------------------------------------------------------------------------
refinement_verdicts = {}
for rung in RUNGS:
    for mode in MODES:
        table = read_csv(os.path.join(PROBES, "refinement", f"w25i_d4w_{mode}_{rung}_refinement.csv"))
        if table is None:
            continue
        by = {(int(r["dt"]), int(r["newton"])): r for r in table}
        pairs = [((60, 1), (120, 1)), ((30, 1), (60, 1)), ((120, 2), (120, 1)), ((120, 10), (120, 1))]
        if mode == "copies":
            ledger, rule, threshold, od3 = "q_tag_led_uprepair_per_hour", "R6", 1.1, "Comparator: refinement"
            all_ok = True
            for fine, coarse in pairs:
                a, b = by[fine][ledger], by[coarse][ledger]
                r = a / b if b > 0 else None
                ok = r is not None and r <= threshold
                all_ok &= ok
                moved = by[fine]["parent_hus_change_vs_first"]
                add(rule, rung, mode, f"copies' repair per hour, {fine} over {coarse}", "6-7 h", r,
                    threshold, verdict(ok), od3,
                    f"{a:.3e} over {b:.3e}" + ("; parent moved more than 1%" if moved > 0.01 else ""))
            refinement_verdicts[rung] = all_ok
        else:
            rule, od3 = "R9", "Refinement"
            chain = [((60, 1), (120, 1)), ((30, 1), (60, 1)), ((120, 2), (120, 1)), ((120, 10), (120, 2))]
            for ledger in ("q_tag_led_repair_per_hour", "q_tag_inc_left_per_hour"):
                if ledger not in table[0]:
                    continue
                for fine, coarse in chain:
                    a, b = by[fine][ledger], by[coarse][ledger]
                    r = a / b if b > 0 else None
                    moved = by[fine]["parent_hus_change_vs_first"]
                    add(rule, rung, mode, f"{ledger.replace('_per_hour', '')}, {fine} over {coarse}",
                        "6-7 h", r, 0.75, ratio_verdict(r, a == 0 and b == 0), od3,
                        f"{a:.3e} over {b:.3e}" + ("; parent moved more than 1%" if moved > 0.01 else ""))

# ---------------------------------------------------------------------------
# R7: default against copies per tag, where R5 and R6 pass on the rung.
# ---------------------------------------------------------------------------
os.makedirs(os.path.join(SCORE, "verifier"), exist_ok=True)
for rung in RUNGS:
    path = os.path.join(SCORE, "verifier", f"r7_{rung}.json")
    subprocess.run(
        [sys.executable, VERIFIER, "--reference", out_dir("copies", rung), "--run", out_dir("default", rung),
         "--family", "water", "--hours", "0,1,12,24", "--judge", "--json", path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    eligible = repair_verdicts.get(rung, False) and refinement_verdicts.get(rung, False)
    failed = [n for n, v in (("R5", repair_verdicts.get(rung)), ("R6", refinement_verdicts.get(rung))) if not v]
    if not os.path.exists(path):
        add("R7", rung, "default vs copies", "verifier", "", "", "", "not assessable (verifier failed)", "Provenance")
        continue
    report = json.load(open(path))
    for jr in report["judge"]["rows"]:
        m = report["tag_metrics"][jr["tag"]][str(jr["hour"])]
        value = m["abs_L1"] if jr["small"] else m["L1_mass_weighted"]
        metric = f"{jr['tag']} at {jr['hour']} h, " + ("abs L1 (small tag)" if jr["small"] else "L1")
        v = verdict(jr["passed"]) if eligible else f"not assessable ({' and '.join(failed)} failed)"
        add("R7", rung, "default vs copies", metric, f"{jr['hour']} h", value, jr["reason"].split("(budget ")[1].split(")")[0] if not jr["small"] else "2e-4 of the water",
            v, "Provenance, per tag", f"{jr['reason']}; judged {'pass' if jr['passed'] else 'fail'} if it were scored")

# ---------------------------------------------------------------------------
# P3: the first-step probes, as w25_compare.py first_step.
# ---------------------------------------------------------------------------
first_rows = []
for rung in ("z30_c", "z60_c"):
    outdir = os.path.join(PROBES, "first_step")
    for variant in ("baseline", "converged_first", "tags_after_first"):
        dp = os.path.join(outdir, f"w25i_d4w_pulse_default_{rung}_first_step_{variant}.csv")
        cp = os.path.join(outdir, f"w25i_d4w_pulse_copies_{rung}_first_step_{variant}.csv")
        if not (os.path.exists(dp) and os.path.exists(cp)):
            continue
        d, c = w25_compare.read_profile(dp), w25_compare.read_profile(cp)
        dz = np.gradient(d["z"])
        parity = np.array_equal(d["rho_q_tot"], c["rho_q_tot"])
        for tag in (k for k in d if k.startswith("ρq_tag_")):
            ref = np.sum(np.abs(c[tag]) * dz)
            l1 = np.sum(np.abs(d[tag] - c[tag]) * dz) / ref if ref > 0 else float("nan")
            share = np.sum(c[tag] * dz) / np.sum(c["rho_q_tot"] * dz)
            first_rows.append(dict(rung=rung, variant=variant, tag=tag.replace("ρq_tag_", ""), L1=l1,
                                   share=share, parent_bit_for_bit=parity))

# ---------------------------------------------------------------------------
# Write.
# ---------------------------------------------------------------------------
os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "w25_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow({k: (repr(v) if isinstance(v, float) else v) for k, v in r.items()})
with open(os.path.join(SCORE, "windows.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["rung", "startup_end_seconds"])
    for rung in RUNGS:
        w.writerow([rung, windows[rung] if windows[rung] is not None else "none"])
with open(os.path.join(SCORE, "first_step.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["rung", "variant", "tag", "L1", "share", "parent_bit_for_bit"])
    w.writeheader()
    for r in first_rows:
        w.writerow(r)

# A short tally on stdout.
from collections import Counter  # noqa: E402

for rule in ("R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10"):
    tally = Counter(r["verdict"].split(" (")[0] for r in rows if r["rule"] == rule)
    print(rule, dict(tally))
