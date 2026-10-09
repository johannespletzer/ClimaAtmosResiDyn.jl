"""Part 8 glue for the TRMM 0M 6 h pilot (design/PART8_BASELINE.md).

    python3 part8_pilot.py w58 DATA_DIR RECORDED_CSV [--prefix g3b|p8] [--json OUT]
    python3 part8_pilot.py od2 UNTAGGED_OUTPUT_DIR [--period 10m] [--json OUT]
    python3 part8_pilot.py tables RUN_DIR MODE [--end-seconds S] [--json OUT]
    python3 part8_pilot.py rank --mode MODE --score SCORE_JSON --tables TABLES_JSON
        [--newton VALUE --newton-source TEXT] --out CSV

`w58` recomputes the table-derived rows of W58's record (R4, R5, R8) from the
closure and audit tables in DATA_DIR and compares them with RECORDED_CSV, the
recorded `g3base_scores.csv`. DATA_DIR is either the record's flat copy
(`output/g3base/data`) or the output root of the runs, where each run keeps
its tables under `output_0000`. With `--prefix p8` it reads the rerun's runs
and lists each row that differs from W58's record. `od2` reads OD2's boundary
on the untagged twin at its own output cadence. `tables` writes the
table-derived rows of one run.
`rank` builds one mode's ranked table of error terms from the scorer's result
and the table rows.

It adds no threshold. Every limit it compares comes from score_acceptance.py,
or from closure_verdict.py as the scorer does. test_acceptance.py pins the
approved numbers. The arithmetic of
the table rows is that of analysis/water/g3base_score.py, which wrote W58's
record, so a recomputed value equals the recorded one bit for bit. The
contract reading of each row is stated beside the legacy verdict, since a
six-hour closure is reported under WA-SCOPE and no threshold is transplanted.

Exit 0: done, and for `w58` every recorded row is reproduced. Exit 1: `w58`
found a difference, which on the rerun is a changed number to report.
Exit 2: an input is missing or inconsistent.
"""

import argparse
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np

from acceptance_data import DataError, od2_start, require
from convert_output import ConversionError, Run, faces_and_thickness, read_field
from score_acceptance import (AGGREGATE_REPAIR_PER_DAY, COMPARATOR_REPAIR_PER_DAY, COPIES_RESIDUAL_MAX,
                              LED_FIX_MAX, NEWTON_MAX, origin_limits)
from closure_verdict import WATER_GROSS

DAY = 86400.0
TRMM_END = 21600.0
TRMM_TAGS = ("pbl", "free", "evap")
# The pilot's tag kinds, as the converter reads them from the config.
TRMM_KINDS = {"pbl": "region", "free": "region", "evap": "source"}
# A term measured on another case or commit carries this status. It is listed, not ranked.
PRIOR = "prior"
# A scorer verdict that makes a measured term a reading only. Until PX12's
# eligibility file is attached, the first-hour origin rows carry it. Such a
# term keeps its fraction and is listed, not ranked (proposed, 2026-10-09).
READING = "NOT ASSESSABLE"
# Every limit used here, by the ID the design cites. Values come from the scorer.
LIMITS = {
    "WATER_GROSS": WATER_GROSS,
    "COPIES_RESIDUAL_MAX": COPIES_RESIDUAL_MAX,
    "COMPARATOR_REPAIR_PER_DAY": COMPARATOR_REPAIR_PER_DAY,
    "AGGREGATE_REPAIR_PER_DAY": AGGREGATE_REPAIR_PER_DAY,
    "LED_FIX_MAX": LED_FIX_MAX,
    "NEWTON_MAX": NEWTON_MAX,
}
# The fix candidate in part 9's queue that each term would name (proposed,
# 2026-10-09, design/PART8_BASELINE.md section 7). Data, not a threshold.
FIX_CANDIDATES = {
    "closure_residual": {"default": "none known: the follower closes the partition to rounding",
                         "copies": "none in the queue: the copies are the comparator (UP1 after PX12)"},
    "partition_repair": {"default": "WP4c leak corrections, gated by PX7 and PX2",
                         "copies": "WP4c leak corrections, gated by PX7 and PX2"},
    "copies_repair": {"copies": "WP4a-J and UP1 after PX12's result"},
    "copies_own_residual": {"copies": "WP4a-J and UP1 after PX12's result"},
    "origin_first_hour": {"default": "WP4a-J and UP1 after PX12, WP4b stages 2 and 3 once rain starts"},
    "led_fix": {"default": "WP4c leak corrections, gated by PX7 and PX2",
                "copies": "WP4c leak corrections, gated by PX7 and PX2"},
    "intervention_events": {"default": "Part 5 producer registration (accepted application accounting)",
                            "copies": "Part 5 producer registration (accepted application accounting)"},
    "parent_newton": {"default": "none known in the queue: the Newton count is OD1's configuration",
                      "copies": "none known in the queue: the Newton count is OD1's configuration"},
    "precip_sum_defect": {"default": "WP4b stages 2 and 3 (criterion 7)",
                          "copies": "WP4b stages 2 and 3 (criterion 7)"},
}


def read_table(path):
    """A closure or audit table as rows of floats. NaN stays NaN."""
    path = Path(path)
    require(path.is_file(), f"missing table {path}")
    with path.open() as stream:
        rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(stream)]
    require(rows, f"empty table {path}")
    return rows


def row_at(table, time):
    """The first row at or after `time`, as g3base_score.py reads it."""
    for r in table:
        if r["time"] >= time - 1e-6:
            return r
    raise DataError(f"no table row at or after {time:g} s")


def verdict(ok):
    return "pass" if ok else "fail"


def table_rows(closure, audit, mode, end=TRMM_END, tags=TRMM_TAGS):
    """W58's table-derived rows of one run, with the limit IDs they cite.

    The pilot has no established window (W58), so every window is the whole
    run from 0 s. `legacy_verdict` is g3base_score.py's reading. `contract`
    is the reading under G3_PLAN 6.1.2 and WA-SCOPE.
    """
    rows = []

    def add(rule, metric, window, value, limit_id, legacy, contract, note=""):
        rows.append({"rule": rule, "mode": mode, "metric": metric, "window": window, "value": value,
                     "limit_id": limit_id, "limit": LIMITS.get(limit_id), "legacy_verdict": legacy,
                     "contract": contract, "note": note})

    last = row_at(closure, end)
    half = end / 2
    g = {t: row_at(closure, t)["gross_relative"] for t in (0.0, half, end)}
    a = {t: row_at(closure, t)["gross_residual"] for t in (0.0, half, end)}
    label = f"{end / 3600:.0f} h"
    add("R4", f"gross residual at {label}, of the water", label, g[end], "WATER_GROSS",
        verdict(g[end] <= WATER_GROSS), "reported: the approved closure is at 24 h")
    first, second = g[half] - g[0.0], g[end] - g[half]
    add("R4", "second half minus first half, of the water", "0-half-end", second - first, None, "reported",
        "reported", f"first {first:.3e}, second {second:.3e}; absolute (kg/m2) first "
        f"{a[half] - a[0.0]:.4e}, second {a[end] - a[half]:.4e}")
    stop = row_at(audit, end)
    water = last["total"]

    def per_day(column, start=0.0, divide_by=water):
        s = row_at(audit, start)
        return (stop[column] - s[column]) / divide_by / ((stop["time"] - s["time"]) / DAY)

    window = "whole run"
    require("led_repair_retained" in stop, "the audit has no led_repair_retained column")
    value = per_day("led_repair_retained")
    add("R8", "partition repair retained gross per day", window, value, "AGGREGATE_REPAIR_PER_DAY",
        verdict(value <= AGGREGATE_REPAIR_PER_DAY), "scored per OD2 window by the scorer",
        f"whole run {value:.3e}")
    for tag in tags:
        key = f"led_fix_{tag}_inventory_fraction"
        require(key in stop, f"the audit has no {key} column")
        frac, retained = stop[key], stop[f"led_fix_{tag}_retained"]
        inventory = retained / frac if frac > 0 else None
        start = row_at(audit, 0.0)[f"led_fix_{tag}_retained"]
        value = (retained - start) / inventory if inventory else 0.0
        add("R8", f"led_fix inventory fraction, {tag}", window, value, "LED_FIX_MAX",
            verdict(value <= LED_FIX_MAX), "scored per OD2 window by the scorer, at accepted-step cadence",
            f"whole run {frac:.3e}; events {stop[f'led_fix_{tag}_events']:.0f}")
        key = f"led_inc_{tag}_inventory_fraction"
        if key in stop:
            add("R8", f"led_inc inventory fraction, {tag}", "whole run", stop[key], None, "reported", "reported")
    events = {k[:-len("_events")]: stop[k] for k in stop if k.endswith("_events") and not math.isnan(stop[k])}
    add("EV", "intervention events at the end", "whole run", float(sum(events.values())), None, "reported",
        "reported: retained and attempted counts, not cancellation-safe applications",
        "; ".join(f"{k} {v:.0f}" for k, v in sorted(events.items()) if v))
    if mode != "copies":
        return rows
    own = max(r["copy_residual_relative"] for r in audit if r["time"] <= end + 1e-6)
    add("R5", "copies' own residual, max over outputs", window, own, "COPIES_RESIDUAL_MAX",
        verdict(own <= COPIES_RESIDUAL_MAX), "reported until PX12 reads eligibility",
        f"at the end {stop['copy_residual_relative']:.3e}")
    require("led_uprepair_retained" in stop, "the copies' audit has no led_uprepair_retained column")
    value = per_day("led_uprepair_retained")
    inside = [r["total"] for r in closure if -1e-6 <= r["time"] <= end + 1e-6]
    mean_water = per_day("led_uprepair_retained", divide_by=float(np.mean(inside)))
    add("R5", "copies' repair, gross, per day", window, value, "COMPARATOR_REPAIR_PER_DAY",
        verdict(value <= COMPARATOR_REPAIR_PER_DAY), "reported until PX12 reads eligibility",
        f"over the window's mean water {mean_water:.3e}; whole run {value:.3e}; "
        f"signed ledger at the end {abs(stop['copy_repair_relative']):.3e}")
    # g3base_score.py also wrote the whole-run rate as a reported row. On the
    # pilot the window is the whole run, so the two rows carry one value.
    add("R5", "copies' repair, gross, per day", "whole run", value, "COMPARATOR_REPAIR_PER_DAY", "reported",
        "reported until PX12 reads eligibility")
    s = row_at(audit, 0.0)
    filt = stop["led_upfilter_retained"] - s["led_upfilter_retained"]
    rep = stop["led_uprepair_retained"] - s["led_uprepair_retained"]
    add("PX5", "the filter's share of the copies' two corrections", window,
        filt / (filt + rep) if filt + rep > 0 else None, None, "reported",
        "reported: PX5's growth clause needs PX12's time-step ladder", f"filter {filt:.4e}, repair {rep:.4e}")
    return rows


def run_tables(directory, mode, end=TRMM_END):
    d = Path(directory)
    return table_rows(read_table(d / "water_tag_closure.csv"), read_table(d / "water_tag_audit.csv"), mode, end)


def tables_dir(directory):
    """Where a run keeps its tables: `output_0000` in the runs' output tree, the directory itself in the flat copy."""
    d = Path(directory)
    return d / "output_0000" if (d / "output_0000").is_dir() else d


def same_value(a, b):
    """Recorded CSV numbers carry Python's shortest repr, so equal floats print equal."""
    if a is None or b in ("", None):
        return a is None and b in ("", None)
    return float(b) == a


def compare_w58(data_dir, recorded_csv, prefix="g3b"):
    """Recompute the TRMM table rows of `<prefix>_trmm0m_{default,copies}_6h` and compare them with W58's record.

    With the default prefix it reproduces W58 from its own tables. With
    `p8` it lists every row of the part 8 rerun that differs from W58.
    """
    with Path(recorded_csv).open() as stream:
        recorded = [r for r in csv.DictReader(stream) if r["case"] == "trmm" and r["rule"] in ("R4", "R5", "R8")]
    require(recorded, "the record has no TRMM R4, R5 or R8 rows")
    computed = {}
    for mode in ("default", "copies"):
        for r in run_tables(tables_dir(Path(data_dir) / f"{prefix}_trmm0m_{mode}_6h"), mode):
            computed.setdefault((r["rule"], mode, r["metric"]), []).append(r)
    checked, differences = [], []
    for rec in recorded:
        key = (rec["rule"], rec["mode"], rec["metric"])
        candidates = computed.get(key, [])
        match = next((c for c in candidates if same_value(c["value"], rec["value"]) and
                      c["legacy_verdict"] == rec["verdict"]), None)
        entry = {"rule": rec["rule"], "mode": rec["mode"], "metric": rec["metric"], "window": rec["window"],
                 "recorded_value": rec["value"], "recorded_verdict": rec["verdict"]}
        if match is None:
            entry["computed"] = [(c["value"], c["legacy_verdict"]) for c in candidates]
            differences.append(entry)
        else:
            entry.update(contract=match["contract"], limit_id=match["limit_id"])
            checked.append(entry)
    return {"reproduced": checked, "differences": differences}


def od2_reading(directory, period="10m"):
    """OD2's boundary on the untagged twin at its own output cadence."""
    run = Run("untagged", directory)
    run.period = period
    q, why = read_field(run, "hus", "kg kg^-1")
    require(q is not None, f"untagged: {why}")
    rho, why = read_field(run, "rhoa", "kg m^-3")
    require(rho is not None, f"untagged: {why}")
    require(np.array_equal(q["time"], rho["time"]) and q["dims"] == rho["dims"] == ("z",) and
            np.array_equal(q["coords"]["z"], rho["coords"]["z"]), "hus and rhoa differ in time or levels")
    z_max = run.config("z_max")
    require(z_max is not None, "the twin's config names no z_max")
    _, dz = faces_and_thickness(q["coords"]["z"], float(z_max))
    water = (rho["values"] * q["values"]) @ dz
    start = od2_start(q["time"], water)
    steps = np.diff(q["time"])
    return {"startup_end_seconds": start, "period": period, "samples": int(len(q["time"])),
            "cadence_seconds": float(steps[0]) if len(steps) and np.all(steps == steps[0]) else None,
            "end_seconds": float(q["time"][-1]),
            "established": bool(start is not None and start < q["time"][-1]),
            "rule": "OD2: three sustained intervals below 10% of the first six hours' peak rate"}


def term(mode, name, observable, value, units, limit_id, status, source, note=""):
    limit = LIMITS.get(limit_id) if limit_id else None
    if limit_id and limit is None:
        raise DataError(f"unknown limit {limit_id}")
    fraction = value / limit if (limit and value is not None and np.isfinite(value)) else None
    return {"mode": mode, "term": name, "observable": observable, "value": value, "units": units,
            "limit_id": limit_id or "", "fraction_of_limit": fraction, "status": status, "source": source,
            "fix_candidate": FIX_CANDIDATES.get(name.split(":")[0], {}).get(mode, "none known"), "note": note}


def rank_terms(mode, score, tables, newton=None, newton_source=""):
    """One mode's error terms, ranked by the fraction of their cited limit (proposed, 2026-10-09).

    Terms measured on this pilot with a cited limit and a finite value come
    first, largest fraction first. Prior terms from another case, terms the
    scorer marks NOT ASSESSABLE (the first-hour origins until PX12) and terms
    without a limit follow unranked, in the order of the design's section 7.
    A fraction is a reading against the cited limit, not a verdict.
    """
    rows = {r["id"]: r for r in score["rows"]}
    out = []

    def metric(row_id, key):
        row = rows.get(row_id)
        return (row or {}).get("metrics", {}).get(key), (row or {}).get("verdict", "absent")

    value, status = metric("WATER.CLOSURE", "gross_over_raw")
    out.append(term(mode, "closure_residual", "gross residual over raw untagged water at the end", value, "1",
                    "WATER_GROSS", status, "score: WATER.CLOSURE gross_over_raw"))
    by_metric = {(r["rule"], r["metric"]): r for r in tables}
    r = by_metric[("R8", "partition repair retained gross per day")]
    out.append(term(mode, "partition_repair", r["metric"], r["value"], "day^-1", r["limit_id"], r["contract"],
                    "tables: water_tag_audit.csv led_repair_retained"))
    if mode == "copies":
        r = by_metric[("R5", "copies' repair, gross, per day")]
        px5 = by_metric.get(("PX5", "the filter's share of the copies' two corrections"))
        out.append(term(mode, "copies_repair", r["metric"], r["value"], "day^-1", r["limit_id"], r["contract"],
                        "tables: water_tag_audit.csv led_uprepair_retained",
                        f"PX5 share {px5['value']}" if px5 else ""))
        r = by_metric[("R5", "copies' own residual, max over outputs")]
        out.append(term(mode, "copies_own_residual", r["metric"], r["value"], "1", r["limit_id"], r["contract"],
                        "tables: water_tag_audit.csv copy_residual_relative"))
    for tag in TRMM_TAGS:
        row_id = f"WATER.ORIGINS.{tag}.3600"
        if row_id not in rows:
            continue
        m = rows[row_id].get("metrics", {})
        if m.get("L1") is None and m.get("absolute_L1") is None:
            continue  # no comparator in this bundle, so nothing was measured
        # The scorer writes a small-tag limit only where the small-tag rule applies.
        small = m.get("small_absolute_limit") is not None
        l1_limit, linf_limit = origin_limits(TRMM_KINDS[tag], 3600.0)
        if small:
            value, fraction = m["absolute_L1"], m["absolute_L1"] / m["small_absolute_limit"]
        else:
            value = m.get("L1")
            fraction = max(value / l1_limit, m["Linf"] / linf_limit) if value is not None else None
        t = term(mode, f"origin_first_hour:{tag}", "absolute L1 (small tag)" if small else "L1 at 1 h", value,
                 "kg m^-2" if small else "1", None, rows[row_id]["verdict"],
                 f"score: {row_id}", rows[row_id].get("limitation", ""))
        t.update(limit_id="SMALL (small-tag absolute rule)" if small else
                 f"ORIGIN_L1_FIRST_HOUR and ORIGIN_LINF_FIRST_HOUR, {TRMM_KINDS[tag]}",
                 fraction_of_limit=fraction)
        out.append(t)
    for tag in TRMM_TAGS:
        r = by_metric.get(("R8", f"led_fix inventory fraction, {tag}"))
        if r:
            out.append(term(mode, f"led_fix:{tag}", r["metric"], r["value"], "1", r["limit_id"], r["contract"],
                            f"tables: water_tag_audit.csv led_fix_{tag}_retained", r["note"]))
    r = by_metric[("EV", "intervention events at the end")]
    out.append(term(mode, "intervention_events", r["metric"], r["value"], "count", None,
                    rows.get("COMMON.ACCEPTED_APPLICATION_ACTIVITY", {}).get("verdict", "absent"),
                    "tables: water_tag_audit.csv *_events. Part 5 reader: COMMON.ACCEPTED_APPLICATION_ACTIVITY",
                    r["note"]))
    if newton is not None:
        out.append(term(mode, "parent_newton", "fixed-parent one-step E, 2 iterations", newton, "1", "NEWTON_MAX",
                        PRIOR + ", another case", newton_source))
    value, status = metric("WATER.PRECIP_INSTANTANEOUS", "max_absolute_rate_defect")
    out.append(term(mode, "precip_sum_defect", "max absolute D_p over outputs", value, "kg m^-2 s^-1", None,
                    status, "score: WATER.PRECIP_INSTANTANEOUS max_absolute_rate_defect"))
    measured = [t for t in out if t["fraction_of_limit"] is not None and not t["status"].startswith(PRIOR)
                and t["status"] != READING]
    ranked = sorted(measured, key=lambda t: -t["fraction_of_limit"])
    rest = [t for t in out if all(t is not u for u in measured)]
    for i, t in enumerate(ranked, 1):
        t["rank"] = i
    for t in rest:
        t["rank"] = ""
    return ranked + rest


COLUMNS = ("rank", "mode", "term", "observable", "value", "units", "limit_id", "fraction_of_limit", "status",
           "source", "fix_candidate", "note")


def write_csv(rows, path):
    with Path(path).open("x", newline="") as stream:
        w = csv.DictWriter(stream, fieldnames=COLUMNS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def dump(obj, path):
    text = json.dumps(obj, indent=2, sort_keys=True, default=float) + "\n"
    if path:
        with Path(path).open("x") as stream:
            stream.write(text)
    else:
        sys.stdout.write(text)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="command", required=True)
    a = sub.add_parser("w58")
    a.add_argument("data_dir")
    a.add_argument("recorded_csv")
    a.add_argument("--prefix", default="g3b", help="g3b for W58's tables, p8 for the rerun's")
    a.add_argument("--json")
    a = sub.add_parser("od2")
    a.add_argument("untagged_dir")
    a.add_argument("--period", default="10m")
    a.add_argument("--json")
    a = sub.add_parser("tables")
    a.add_argument("run_dir")
    a.add_argument("mode", choices=("default", "copies"))
    a.add_argument("--end-seconds", type=float, default=TRMM_END)
    a.add_argument("--json")
    a = sub.add_parser("rank")
    a.add_argument("--mode", choices=("default", "copies"), required=True)
    a.add_argument("--score", required=True)
    a.add_argument("--tables", required=True)
    a.add_argument("--newton", type=float)
    a.add_argument("--newton-source", default="")
    a.add_argument("--out", required=True)
    args = p.parse_args(argv)
    try:
        if args.command == "w58":
            result = compare_w58(args.data_dir, args.recorded_csv, args.prefix)
            dump(result, args.json)
            return 1 if result["differences"] else 0
        if args.command == "od2":
            dump(od2_reading(args.untagged_dir, args.period), args.json)
        elif args.command == "tables":
            dump(run_tables(args.run_dir, args.mode, args.end_seconds), args.json)
        else:
            score = json.loads(Path(args.score).read_text())
            tables = json.loads(Path(args.tables).read_text())
            require((args.newton is None) == (not args.newton_source),
                    "a prior Newton error needs its source, and a source needs its value")
            write_csv(rank_terms(args.mode, score, tables, args.newton, args.newton_source), args.out)
    except (DataError, ConversionError, OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"DATA FAILURE: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
