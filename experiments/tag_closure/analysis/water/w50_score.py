"""W50, the first hour again (design/W25_ISOLATION.md, section 8): D4-W with
the surface flux modelled at the plume's start (section 7), in two arms.

    python3 w50_score.py [OUTPUT_ROOT] [SCORE_DIR]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds the runs
`w50_d4w_{default,copies}_{z30,z60}_c_{fix,main}`,
`w50_d4w_pulse_{default,copies}_z30_c_{fix,main}` and the untagged twins
`w50_d4w_untagged_{z30,z60}_c`, each in `output_0000`. SCORE_DIR (default:
this record's `output/w50/`) receives:

  - `w50_scores.csv`: one row per rule, case, arm, mode and metric, with the
    value, the threshold, the verdict and the OD3 row (R1, R4, R5, R7);
  - `effect.csv`: the rule's effect, reported and not judged. Per tag and
    hour, R7's L1 and L∞ in both arms, and each mode's change between the
    arms (fix against main);
  - `windows.csv`: OD2's end of startup per rung, from the untagged twin;
  - `verifier/`: the verifier's JSON (`compare_runs.py`).

The rules are section 4's, with their OD3 rows. Nothing is new, and nothing is
tuned after the runs. R7 is a provenance verdict only where R5 passes on that
case and arm, and R6 too. R6 is not rerun here, so where R5 passes, R7 reads
"waits for R6" (section 8). Where R5 fails, R7 is not assessable, and its
numbers are reported.

`W50_SMOKE=1` reads W38's plain runs (`w25i_d4w_*`) as both arms and skips
the pulse. It checks this script on real output before the runs, and its
scores mean nothing.
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
SCORE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "output", "w50")
VERIFIER = os.path.join(HERE, "..", "evidence", "compare_runs.py")
SMOKE = os.environ.get("W50_SMOKE", "") == "1"
CASES = [("plain", "z30_c"), ("plain", "z60_c")] + ([] if SMOKE else [("pulse", "z30_c")])
ARMS = ("fix", "main")
MODES = ("default", "copies")
DAY = 86400.0

rows = []
effects = []


def add(rule, case, rung, arm, mode, metric, window, value, threshold, verdict, od3, note=""):
    rows.append(
        dict(rule=rule, case=case, rung=rung, arm=arm, mode=mode, metric=metric, window=window,
             value=value, threshold=threshold, verdict=verdict, od3_row=od3, note=note)
    )


def job(case, rung, mode, arm):
    if SMOKE:
        return f"w25i_d4w_{mode}_{rung}"
    if mode == "untagged":
        return f"w50_d4w_untagged_{rung}"
    prefix = "w50_d4w_pulse" if case == "pulse" else "w50_d4w"
    return f"{prefix}_{mode}_{rung}_{arm}"


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


def verdict(ok):
    return "pass" if ok else "fail"


def verify(reference, run, path, judge):
    """The verifier's JSON for `run` against `reference`, or None."""
    command = [sys.executable, VERIFIER, "--reference", out_dir(reference), "--run", out_dir(run),
               "--family", "water", "--hours", "0,1,12,24", "--json", path]
    if judge:
        command.append("--judge")
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return json.load(open(path)) if os.path.exists(path) else None


# ---------------------------------------------------------------------------
# OD2's windows, from each rung's untagged twin, by the approved rule.
# ---------------------------------------------------------------------------
windows = {}
for rung in sorted({rung for _, rung in CASES}):
    directory = out_dir(job(None, rung, "untagged", None))
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


def established(rung, end):
    t0 = windows[rung]
    if t0 is None:
        return None, "not assessable (OD2's rule finds no end of startup)"
    if t0 >= end - 1e-6:
        return None, f"not assessable (startup ends at {t0 / 3600:.1f} h, after {end / 3600:.0f} h)"
    return t0, ""


# ---------------------------------------------------------------------------
# R1: every model field the untagged twin writes, bit for bit, both arms.
# ---------------------------------------------------------------------------
for case, rung in CASES:
    untagged = out_dir(job(case, rung, "untagged", None))
    names = sorted(f for f in os.listdir(untagged) if f.endswith(".nc") and "_1h_" in f)
    for arm in ARMS:
        for mode in MODES:
            tagged = out_dir(job(case, rung, mode, arm))
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
            note = f"{len(names) - len(missing)} fields compared"
            if differ:
                note += f"; differ: {differ}"
            if missing:
                note += f"; missing in the tagged run: {missing}"
            add("R1", case, rung, arm, mode, "model fields bit for bit", "whole day",
                len(differ) + len(missing), 0, verdict(not differ and not missing),
                "Parent validity: parity", note)

# ---------------------------------------------------------------------------
# R4 and R5, from the closure and audit tables.
# ---------------------------------------------------------------------------
eligible = {}
for case, rung in CASES:
    for arm in ARMS:
        for mode in MODES:
            d = out_dir(job(case, rung, mode, arm))
            closure = read_csv(os.path.join(d, "water_tag_closure.csv"))
            audit = read_csv(os.path.join(d, "water_tag_audit.csv"))
            if closure is None or audit is None or row_at(closure, DAY) is None:
                add("R4", case, rung, arm, mode, "run", "", "", "", "not assessable (no day of output)",
                    "Closure, water")
                continue
            void = any(r.get("void", 0) for r in closure)
            G = {h: row_at(closure, h * 3600)["gross_relative"] for h in (0, 12, 24)}
            add("R4", case, rung, arm, mode, "gross residual at 24 h, of the water", "24 h", G[24], 2e-3,
                verdict(G[24] <= 2e-3), "Closure, water", "void rows" if void else "")
            first, second = G[12] - G[0], G[24] - G[12]
            add("R4", case, rung, arm, mode, "second 12 h minus first 12 h", "0-12-24 h", second - first,
                0.0, verdict(second <= first), "Closure, water",
                f"first {first:.3e}, second {second:.3e}")
            if mode != "copies":
                continue
            end = row_at(audit, DAY)
            water = row_at(closure, DAY)["total"]
            t0, why = established(rung, DAY)

            def per_day(column, start):
                s = row_at(audit, start)
                return (end[column] - s[column]) / water / ((end["time"] - s["time"]) / DAY)

            own = max(r["copy_residual_relative"] for r in audit)
            add("R5", case, rung, arm, mode, "copies' own residual, max over hours", "whole day", own,
                2e-4, verdict(own <= 2e-4), "Comparator: its own residual",
                f"at 24 h {end['copy_residual_relative']:.3e}")
            whole = per_day("led_uprepair_retained", 0.0)
            signed = abs(end["copy_repair_relative"])
            if t0 is None:
                ok = False
                add("R5", case, rung, arm, mode, "copies' repair, gross, per day", "established", "",
                    2e-3, why, "Comparator: its repair")
            else:
                value = per_day("led_uprepair_retained", t0)
                ok = value <= 2e-3
                add("R5", case, rung, arm, mode, "copies' repair, gross, per day", "established", value,
                    2e-3, verdict(ok), "Comparator: its repair",
                    f"whole day {whole:.3e}; signed ledger over the day {signed:.3e}")
            add("R5", case, rung, arm, mode, "copies' repair, gross, per day", "whole day", whole, 2e-3,
                "reported", "Comparator: its repair")
            eligible[(case, rung, arm)] = (own <= 2e-4) and ok

# ---------------------------------------------------------------------------
# R7: default against copies per tag, each arm, at 1 h and 24 h.
# ---------------------------------------------------------------------------
os.makedirs(os.path.join(SCORE, "verifier"), exist_ok=True)
r7 = {}
for case, rung in CASES:
    for arm in ARMS:
        path = os.path.join(SCORE, "verifier", f"r7_{case}_{rung}_{arm}.json")
        report = verify(job(case, rung, "copies", arm), job(case, rung, "default", arm), path, True)
        if report is None:
            add("R7", case, rung, arm, "default vs copies", "verifier", "", "", "",
                "not assessable (verifier failed)", "Provenance")
            continue
        r7[(case, rung, arm)] = report
        if eligible.get((case, rung, arm)):
            status = "waits for R6 (section 8: P2 first)"
        else:
            status = "not assessable (R5 failed)"
        for jr in report["judge"]["rows"]:
            m = report["tag_metrics"][jr["tag"]][str(jr["hour"])]
            value = m["abs_L1"] if jr["small"] else m["L1_mass_weighted"]
            metric = f"{jr['tag']} at {jr['hour']} h, " + ("abs L1 (small tag)" if jr["small"] else "L1")
            add("R7", case, rung, arm, "default vs copies", metric, f"{jr['hour']} h", value,
                "see note", status, "Provenance, per tag",
                f"{jr['reason']}; judged {'pass' if jr['passed'] else 'fail'} if it were scored")

# ---------------------------------------------------------------------------
# The rule's effect, reported and not judged.
# ---------------------------------------------------------------------------
for case, rung in CASES:
    between = {}
    for mode in MODES:
        path = os.path.join(SCORE, "verifier", f"arms_{case}_{rung}_{mode}.json")
        between[mode] = verify(job(case, rung, mode, "main"), job(case, rung, mode, "fix"), path, False)
    fix, main = r7.get((case, rung, "fix")), r7.get((case, rung, "main"))
    tags = sorted((fix or main or {"tag_metrics": {}})["tag_metrics"])
    for tag in tags:
        for hour in ("1", "24"):
            row = dict(case=case, rung=rung, tag=tag, hour=hour)
            for label, report in (("fix", fix), ("main", main)):
                m = report["tag_metrics"][tag][hour] if report else {}
                row[f"modes_L1_{label}"] = m.get("L1_mass_weighted", "")
                row[f"modes_Linf_{label}"] = m.get("Linf_peak_normalized", "")
                row[f"modes_absL1_{label}"] = m.get("abs_L1", "")
            for mode in MODES:
                report = between[mode]
                m = report["tag_metrics"][tag][hour] if report else {}
                row[f"{mode}_fix_vs_main_L1"] = m.get("L1_mass_weighted", "")
                row[f"{mode}_fix_vs_main_Linf"] = m.get("Linf_peak_normalized", "")
            effects.append(row)

# ---------------------------------------------------------------------------
# Write.
# ---------------------------------------------------------------------------
os.makedirs(SCORE, exist_ok=True)
with open(os.path.join(SCORE, "w50_scores.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow({k: (repr(v) if isinstance(v, float) else v) for k, v in r.items()})
if effects:
    with open(os.path.join(SCORE, "effect.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(effects[0].keys()))
        w.writeheader()
        for r in effects:
            w.writerow({k: (repr(v) if isinstance(v, float) else v) for k, v in r.items()})
with open(os.path.join(SCORE, "windows.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["rung", "startup_end_seconds"])
    for rung, start in sorted(windows.items()):
        w.writerow([rung, start if start is not None else "none"])

from collections import Counter  # noqa: E402

for rule in ("R1", "R4", "R5", "R7"):
    tally = Counter(r["verdict"].split(" (")[0] for r in rows if r["rule"] == rule)
    print(rule, dict(tally))
