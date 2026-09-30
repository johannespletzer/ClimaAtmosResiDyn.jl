"""WP4a-J's score: known issue 4's Jacobian switch on the raining 0M column.

    python3 wp4aj_score.py [--root DIR] [--index RUN=output_XXXX ...] [--out DIR]

Pre-registered in design/ZERO_M_SPLIT.md, section 5.1, before any run. Every
number comes from the verifier, `analysis/evidence/compare_runs.py`, called
once per pair with `--json`, and every budget from the verifier's own table
and `judge_tag_row` (G3_PLAN.md 6.1's first-hour row and small-tag rule). The
17 runs are the `configs/wp4aj_*.yml`. Each run's output directory is
`<root>/<run>/output_0000` unless `--index RUN=output_XXXX` names another; the
report records every resolved path.

What it computes, in the section's order:

  P1  the untagged twin against `wp4aj_dt120_n1_off`: every parent field bit
      for bit (`--parity-only`);
  P2  at each of the five rungs, the switch on against off: every parent
      field bit for bit (`--expect-parity`);
  M1  the primary readout, the same five pairs: each tag's L1 and L∞ of on
      against off at every reported hour;
  M2  each of the ten on and off runs against its dt's 20-iteration
      reference, per tag, at every reported hour; the three off runs at one
      iteration are judged at 1 h (the verdict below), the rest reported;
  V1  each reference against its 40-iteration check, judged at 1 h with the
      same budgets;
  V2  the column rains in the first hour: `pr` is not zero at some output up
      to 1 h in `wp4aj_dt120_n1_off`;
  R   reported: G(t), each run's gross residual over its own water; OD2's
      startup end read from the untagged twin; the bound on `c`.

Verdict: known issue 4 is closed if P1, P2, V1 and V2 pass and the three off
runs at one iteration are within the budgets of their dt's reference at 1 h,
every tag; restated with its size (the worst tag, its L1 and L∞) if P1, P2,
V1 and V2 pass and a tag misses; not assessable if P1, V1 or V2 fails. A P2
failure is a parity defect of the switch, and nothing else is read.
"""
import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent / "evidence"
sys.path.insert(0, str(EVIDENCE))
import compare_runs as verifier  # noqa: E402  the verifier's budgets and judge

VERIFIER = EVIDENCE / "compare_runs.py"
DEFAULT_ROOT = Path("/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output")
# Every 6-minute output to 1 h, then every 12 minutes: each is an exact number
# of seconds as the verifier computes `h * 3600` (1.1 h is not).
HOURS = [round(0.1 * k, 1) for k in range(1, 11)] + [1.2, 1.4, 1.6, 1.8, 2.0]
HOURS_ARG = ",".join(f"{h:g}" for h in HOURS)
JUDGED_HOUR = 1
DTS = (120, 60, 30)
RUNGS = [(120, 1), (120, 2), (120, 10), (60, 1), (30, 1)]
# ARS222's implicit coefficient, and the 0M precipitation timescale.
GAMMA_ARS222 = 1 - 1 / math.sqrt(2)
TAU_0M = 1000.0


def run_name(dt, newton, switch):
    return f"wp4aj_dt{dt}_n{newton}_{switch}"


def ref_name(dt, newton=20):
    return f"wp4aj_ref_dt{dt}_n{newton}"


def all_runs():
    runs = [ref_name(dt, n) for dt in DTS for n in (20, 40)]
    runs += [run_name(dt, n, s) for (dt, n) in RUNGS for s in ("off", "on")]
    return runs + ["wp4aj_dt120_n1_untagged"]


def output_dir(root, index, run):
    return root / run / index.get(run, "output_0000")


def verify(out, label, reference, run, extra):
    """One verifier call. Returns its exit status and its JSON (None if it
    wrote none, as `--parity-only` may not)."""
    json_path = out / f"{label}.json"
    command = [
        sys.executable,
        str(VERIFIER),
        "--reference",
        str(reference),
        "--run",
        str(run),
        *extra,
        "--json",
        str(json_path),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    (out / f"{label}.txt").write_text(
        " ".join(command) + "\n\n" + result.stdout + "\n" + result.stderr
    )
    report = json.loads(json_path.read_text()) if json_path.exists() else None
    return result.returncode, report


def column_weights(directory, hour):
    """The verifier's weights, `w = rho dz`, and the water `sum(q_tot w)` of
    one run at one hour, with the verifier's own faces."""
    suffix = verifier.output_suffix(directory, "run")
    with Dataset(directory / f"rhoa{suffix}") as d:
        time = np.asarray(d["time"][:], dtype=np.float64)
        z = np.asarray(d["z"][:], dtype=np.float64)
        i = int(np.nonzero(time == hour * 3600)[0][0])
        rhoa = np.asarray(d["rhoa"][i, :] if d["rhoa"].dimensions[0] == "time" else d["rhoa"][:, i], dtype=np.float64)
    with Dataset(directory / f"hus{suffix}") as d:
        hus = np.asarray(d["hus"][i, :] if d["hus"].dimensions[0] == "time" else d["hus"][:, i], dtype=np.float64)
    _, dz = verifier.compute_faces_and_dz(z, "run")
    w = rhoa * dz
    return w, float(np.sum(hus * w))


def read_series(directory, name):
    suffix = verifier.output_suffix(directory, "run")
    with Dataset(directory / f"{name}{suffix}") as d:
        time = np.asarray(d["time"][:], dtype=np.float64)
        values = np.asarray(d[name][:], dtype=np.float64)
        dims = d[name].dimensions
    # Time first, levels second, whatever the file's order.
    if values.ndim == 2 and dims[0] != "time":
        values = values.T
    return time, values


def judge_at_hour(report, directory_ref, hour):
    """`judge_tag_row` for every tag of one verifier report at one hour."""
    _, total_ref = column_weights(directory_ref, hour)
    rows = []
    for tag in report["tags"]:
        kind = verifier.classify_tag(tag, set(report["region_tags"]), set(report["source_tags"]))
        row = report["tag_metrics"][tag][str(verifier.parse_hour(f"{hour:g}"))]
        rows.append(verifier.judge_tag_row(tag, hour, row, kind, total_ref))
    return rows


def metrics_table(report):
    """Per tag and hour: L1, L∞ and the absolute L1."""
    table = {}
    for tag, per_hour in report["tag_metrics"].items():
        table[tag] = {
            h: {
                "L1": row.get("L1_mass_weighted"),
                "Linf": row.get("Linf_peak_normalized"),
                "abs_L1": row.get("abs_L1"),
                "ref_zero": row.get("ref_zero"),
            }
            for h, row in per_hour.items()
        }
    return table


def worst(table, up_to=None):
    """The largest L1 and L∞ over tags and hours (up to `up_to` h)."""
    result = {}
    for tag, per_hour in table.items():
        rows = [r for h, r in per_hour.items() if up_to is None or float(h) <= up_to]
        l1 = [r["L1"] for r in rows if r["L1"] is not None]
        linf = [r["Linf"] for r in rows if r["Linf"] is not None]
        result[tag] = {"L1": max(l1) if l1 else None, "Linf": max(linf) if linf else None}
    return result


def gross_residual(directory):
    """G(t) = sum |q_tag_res| w / sum q_tot w, the run's own (6.1)."""
    time, res = read_series(directory, "q_tag_res")
    _, hus = read_series(directory, "hus")
    _, rhoa = read_series(directory, "rhoa")
    with Dataset(directory / f"rhoa{verifier.output_suffix(directory, 'run')}") as d:
        z = np.asarray(d["z"][:], dtype=np.float64)
    _, dz = verifier.compute_faces_and_dz(z, "run")
    w = rhoa * dz
    G = np.sum(np.abs(res) * w, axis=1) / np.sum(hus * w, axis=1)
    return {f"{t / 3600:g}": float(g) for t, g in zip(time, G) if round(t / 3600, 6) in HOURS}


def startup_end(directory):
    """OD2's rule (ROADMAP.md, approved 2026-09-24): startup ends at the first
    output after which the domain-mean tendency of the column water, averaged
    over the output interval, stays below 10% of its largest value in the
    run's first 6 hours for three outputs in a row."""
    time, hus = read_series(directory, "hus")
    _, rhoa = read_series(directory, "rhoa")
    with Dataset(directory / f"rhoa{verifier.output_suffix(directory, 'run')}") as d:
        z = np.asarray(d["z"][:], dtype=np.float64)
    _, dz = verifier.compute_faces_and_dz(z, "run")
    water = np.sum(hus * rhoa * dz, axis=1)
    tendency = np.abs(np.diff(water) / np.diff(time))
    within = time[1:] <= 6 * 3600
    largest = float(np.max(tendency[within]))
    for k in range(len(tendency) - 2):
        if np.all(tendency[k : k + 3] < 0.1 * largest):
            return {"end_s": float(time[k]), "largest_tendency": largest}
    return {"end_s": None, "largest_tendency": largest}


def c_bound(directory, dt):
    """The design's bound on c, `dtγ (q_c / q_tot) / τ`, largest over the
    cells and the outputs up to 1 h."""
    time, clw = read_series(directory, "clw")
    _, cli = read_series(directory, "cli")
    _, hus = read_series(directory, "hus")
    keep = time <= JUDGED_HOUR * 3600
    ratio = (clw + cli)[keep] / hus[keep]
    return float(GAMMA_ARS222 * dt * np.max(ratio) / TAU_0M)


def rains_in_first_hour(directory):
    time, pr = read_series(directory, "pr")
    keep = time <= JUDGED_HOUR * 3600
    return bool(np.any(pr[keep] != 0))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(DEFAULT_ROOT))
    parser.add_argument("--index", action="append", default=[], metavar="RUN=output_XXXX")
    parser.add_argument("--out", default=str(HERE.parent.parent / "output" / "wp4aj"))
    args = parser.parse_args()
    root = Path(args.root)
    index = dict(entry.split("=", 1) for entry in args.index)
    out = Path(args.out)
    (out / "verifier").mkdir(parents=True, exist_ok=True)
    runs = {run: output_dir(root, index, run) for run in all_runs()}
    missing = [run for run, path in runs.items() if not path.is_dir()]
    if missing:
        sys.exit(f"missing output directories: {missing}")
    score = {"paths": {run: str(path) for run, path in runs.items()}, "hours": HOURS}
    v = out / "verifier"

    # P1: the untagged twin.
    status, _ = verify(v, "P1_untagged_vs_dt120_n1_off", runs["wp4aj_dt120_n1_untagged"], runs[run_name(120, 1, "off")], ["--parity-only"])
    score["P1"] = {"pass": status == 0}

    # P2 and M1: on against off at every rung.
    score["P2"], score["M1"] = {}, {}
    for dt, n in RUNGS:
        label = f"dt{dt}_n{n}"
        status, report = verify(v, f"P2_M1_{label}_on_vs_off", runs[run_name(dt, n, "off")], runs[run_name(dt, n, "on")], ["--hours", HOURS_ARG, "--expect-parity"])
        score["P2"][label] = {"pass": status == 0}
        if report is not None:
            table = metrics_table(report)
            score["M1"][label] = {"table": table, "worst_to_1h": worst(table, JUDGED_HOUR), "worst": worst(table)}

    # M2: each run against its dt's reference; the verdict's three runs judged.
    score["M2"], verdict_rows, on_rows = {}, [], []
    for dt, n in RUNGS:
        for switch in ("off", "on"):
            name = run_name(dt, n, switch)
            status, report = verify(v, f"M2_{name}_vs_ref", runs[ref_name(dt)], runs[name], ["--hours", HOURS_ARG])
            entry = {"verifier_status": status}
            if report is not None:
                table = metrics_table(report)
                entry.update({"table": table, "worst_to_1h": worst(table, JUDGED_HOUR), "worst": worst(table)})
                if n == 1:
                    rows = judge_at_hour(report, runs[ref_name(dt)], JUDGED_HOUR)
                    entry["judged_1h"] = rows
                    (verdict_rows if switch == "off" else on_rows).extend((name, r) for r in rows)
            score["M2"][name] = entry

    # V1: each reference against its 40-iteration check.
    score["V1"] = {}
    for dt in DTS:
        status, report = verify(v, f"V1_ref_dt{dt}_n40_vs_n20", runs[ref_name(dt)], runs[ref_name(dt, 40)], ["--hours", HOURS_ARG])
        entry = {"verifier_status": status}
        if report is not None:
            table = metrics_table(report)
            rows = judge_at_hour(report, runs[ref_name(dt)], JUDGED_HOUR)
            entry.update({"worst": worst(table), "judged_1h": rows, "pass": all(r["passed"] for r in rows)})
        else:
            entry["pass"] = False
        score["V1"][f"dt{dt}"] = entry

    # V2: the column rains in the first hour.
    score["V2"] = {"pass": rains_in_first_hour(runs[run_name(120, 1, "off")])}

    # Reported only.
    score["G"] = {run: gross_residual(path) for run, path in runs.items() if not run.endswith("untagged")}
    score["startup_end"] = startup_end(runs["wp4aj_dt120_n1_untagged"])
    score["c_bound"] = {f"dt{dt}": c_bound(runs[run_name(dt, 1, "off")], dt) for dt in DTS}
    score["on_judged_1h"] = [{"run": name, **row} for name, row in on_rows]

    # The verdict.
    p1 = score["P1"]["pass"]
    p2 = all(e["pass"] for e in score["P2"].values())
    v1 = all(e["pass"] for e in score["V1"].values())
    v2 = score["V2"]["pass"]
    within = bool(verdict_rows) and all(r["passed"] for _, r in verdict_rows)
    if not p2:
        verdict = "parity defect: the switch changed a model field (P2); nothing else is read"
    elif not (p1 and v1 and v2):
        verdict = "not assessable (P1, V1 or V2 failed)"
    elif within:
        verdict = "known issue 4 closed: the off runs at one iteration are within the budgets at 1 h"
    else:
        misses = [(name, r) for name, r in verdict_rows if not r["passed"]]
        verdict = "known issue 4 restated with its size: " + "; ".join(f"{name} {r['tag']}: {r['reason']}" for name, r in misses)
    score["verdict_rows"] = [{"run": name, **row} for name, row in verdict_rows]
    score["verdict"] = verdict

    (out / "wp4aj_score.json").write_text(json.dumps(score, indent=1, allow_nan=False))
    lines = [f"verdict: {verdict}", f"P1 {p1}  P2 {p2}  V1 {v1}  V2 {v2}", ""]
    lines.append("judged at 1 h, off runs at one iteration against their dt's reference:")
    lines += [f"  {name:22s} {r['tag']:6s} {'pass' if r['passed'] else 'FAIL'}  {r['reason']}" for name, r in verdict_rows]
    lines.append("\nthe same for the on runs (reported):")
    lines += [f"  {name:22s} {r['tag']:6s} {'pass' if r['passed'] else 'fail'}  {r['reason']}" for name, r in on_rows]
    lines.append("\nM1, on against off, worst L1 / L-inf up to 1 h and over 2 h, per tag:")
    for label, entry in score["M1"].items():
        for tag in entry["worst"]:
            a, b = entry["worst_to_1h"][tag], entry["worst"][tag]
            lines.append(f"  {label:10s} {tag:6s} to 1 h {a['L1']!s:>24} {a['Linf']!s:>24}   to 2 h {b['L1']!s:>24} {b['Linf']!s:>24}")
    lines.append("\nV1, 40 against 20 iterations, worst over 2 h:")
    for label, entry in score["V1"].items():
        lines.append(f"  {label}: pass {entry['pass']}  {entry.get('worst')}")
    lines.append(f"\nOD2 startup end (untagged twin): {score['startup_end']}")
    lines.append(f"bound on c: {score['c_bound']}")
    lines.append("\nG(t), each run's gross residual over its water, at 1 h and 2 h:")
    for run, G in score["G"].items():
        lines.append(f"  {run:24s} {G.get('1')!s:>24} {G.get('2')!s:>24}")
    (out / "wp4aj_score.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
