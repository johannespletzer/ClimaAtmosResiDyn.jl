"""
The cost table of V-W10 (G3 WP9), from the drivers' CSVs. It decides nothing.
It lays the measurements out beside their untagged baseline, and the owner
reads them against the budget of design/WP9_COST.md.

    source $MODULESHOME/init/zsh; module load python/3.12
    python3 experiments/tag_closure/analysis/wp9_cost_table.py \
        $SCRATCH/tag_closure/output/wp9_cost [--out table.md]

The argument is the directory with one subdirectory per arm. Each arm has one
CSV per point from `wp9_cost_driver.jl`, and a `status.csv` from
`runscripts/wp9_cost.sh`.

What it reports, per family, base config, mode and precipitation setting:
  - build time, and how much of it the runtime counted as compile;
  - the first step, which compiles the stepper;
  - step time, the minimum over the timed blocks and the median, and their
    ratio to the untagged baseline of the same base config;
  - the added step time per tag, `(step_N - step_0) / N`;
  - allocation per step, and the peak memory of the process.

The ratio uses the minimum, since a shared node's contention only adds time. The
median is printed beside it, and the spread of the blocks tells how far to
trust either.

It fails, and does not fill in, when:
  - a point in a status file has a non-zero exit and no CSV, unless the point
    is reported as "not finished" with its status (a timeout, 124, is that);
  - a base config has tagged points and no untagged baseline;
  - two CSVs have the same label;
  - the arms of one base config ran at different commits;
  - a status file names a point twice.
"""

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

FLOAT_COLUMNS = (
    "load_s", "build_s", "build_compile_s", "build_gc_s", "build_gb",
    "first_step_s", "first_step_compile_s", "step_ms_min", "step_ms_median",
    "step_ms_max", "bytes_per_step_min", "bytes_per_step_max", "gc_fraction_max",
    "maxrss_build_gb", "maxrss_warm_gb", "maxrss_final_gb", "loadavg1",
)


def read_points(root):
    rows, statuses = {}, []
    arms = sorted(p for p in root.iterdir() if p.is_dir())
    if not arms:
        sys.exit(f"No arm directories under {root}.")
    for arm in arms:
        status_file = arm / "status.csv"
        if not status_file.is_file():
            sys.exit(f"{arm} has no status.csv, so its points are not accounted for.")
        seen = set()
        with open(status_file) as f:
            for s in csv.DictReader(f):
                key = (arm.name, s["point"])
                if key in seen:
                    sys.exit(f"{status_file} names point {s['point']} twice.")
                seen.add(key)
                s["arm"] = arm.name
                statuses.append(s)
        for path in sorted(arm.glob("*.csv")):
            if path.name == "status.csv":
                continue
            with open(path) as f:
                got = list(csv.DictReader(f))
            if len(got) != 1:
                sys.exit(f"{path} should have one row, has {len(got)}.")
            row = got[0]
            for c in FLOAT_COLUMNS:
                row[c] = float(row[c])
            row["ntags"] = int(row["ntags"])
            row["arm"] = arm.name
            if row["label"] in rows:
                sys.exit(f"Two CSVs have the label {row['label']}.")
            rows[row["label"]] = row
    return rows, statuses


def check_statuses(rows, statuses):
    not_finished = []
    by_arm_point = {(r["arm"], f"{r['ntags']}" + ("" if r["variant"] == "none" else ":" + r["variant"]))
                    for r in rows.values()}
    for s in statuses:
        has_csv = (s["arm"], s["point"]) in by_arm_point
        code = int(s["exit_status"])
        if code == 0 and not has_csv:
            sys.exit(f"Point {s['point']} of {s['arm']} exited 0 and wrote no CSV.")
        if code != 0 and has_csv:
            sys.exit(f"Point {s['point']} of {s['arm']} exited {code} but wrote a CSV.")
        if code != 0:
            not_finished.append(s)
    return not_finished


def fmt(x, digits=1):
    return f"{x:.{digits}f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("root", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    rows, statuses = read_points(args.root)
    not_finished = check_statuses(rows, statuses)

    groups = defaultdict(list)
    for r in rows.values():
        groups[(r["family"], r["base"])].append(r)
    lines = []
    for (family, base), points in sorted(groups.items()):
        commits = {r["commit"] for r in points}
        if len(commits) != 1:
            sys.exit(f"{base} ran at more than one commit: {sorted(commits)}.")
        baselines = [r for r in points if r["ntags"] == 0]
        if len(baselines) != 1:
            sys.exit(f"{base} has {len(baselines)} untagged baselines, not one.")
        base0 = baselines[0]
        lines += [
            f"### {family}, `{base}`, commit `{next(iter(commits))[:8]}`",
            "",
            f"Untagged: build {fmt(base0['build_s'])} s, step {base0['step_ms_min']:.3f} ms "
            f"(min) / {base0['step_ms_median']:.3f} ms (median), {base0['bytes_per_step_min']:.0f} B/step, "
            f"peak {base0['maxrss_final_gb']:.2f} GB.",
            "",
            "| mode | precip | variant | tags | build s | compile s | first step s | step ms min | step ms median "
            "| block spread | x untagged (min) | ms per tag | B/step | peak GB | follower |",
            "|:--|:--|:--|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--|",
        ]
        order = sorted(
            (r for r in points if r["ntags"] > 0),
            key=lambda r: (r["mode"], r["precip"], r["variant"] != "none", r["variant"], r["ntags"]),
        )
        for r in order:
            blocks = np.array([float(x) for x in r["step_ms_blocks"].split(";")])
            spread = (blocks.max() - blocks.min()) / blocks.min()
            ratio = r["step_ms_min"] / base0["step_ms_min"]
            per_tag = (r["step_ms_min"] - base0["step_ms_min"]) / r["ntags"]
            lines.append(
                f"| {r['mode']} | {'yes' if r['precip'] == '1' else 'no'} | {r['variant']} | {r['ntags']} "
                f"| {fmt(r['build_s'])} | {fmt(r['build_compile_s'])} | {fmt(r['first_step_s'])} "
                f"| {r['step_ms_min']:.3f} | {r['step_ms_median']:.3f} | {100 * spread:.1f}% "
                f"| {ratio:.3f} | {per_tag:.4f} | {r['bytes_per_step_min']:.0f} "
                f"| {r['maxrss_final_gb']:.2f} | {r['follower']} |"
            )
        lines.append("")
    if not_finished:
        lines += ["### Points that did not finish", "", "| arm | point | exit status | seconds |", "|:--|:--|--:|--:|"]
        for s in not_finished:
            note = " (timeout)" if s["exit_status"] == "124" else ""
            lines.append(f"| {s['arm']} | {s['point']} | {s['exit_status']}{note} | {s['seconds']} |")
        lines.append("")
    text = "\n".join(lines)
    print(text)
    if args.out:
        args.out.write_text(text + "\n")


if __name__ == "__main__":
    main()
