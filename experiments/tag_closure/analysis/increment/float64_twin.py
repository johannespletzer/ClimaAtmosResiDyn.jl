"""The Float64 twin, a screen for precision sensitivity (G4_TODO, prepared
item 2; G3 WP0, for V-W7).

Given a run's config, `make` writes its twin: `FLOAT_TYPE: Float64`, `t_end`
two hours, everything else the same. Submit the twin on one process; the
config does not carry the process count, the sbatch line does.

`compare` reads the two runs' closure tables and reports, at each output time
both have, the closure residual of each and their ratio.

What it shows: if the residual falls by orders of magnitude in Float64, the
run's residual is sensitive to precision (the sphere of E70: 5.7e-15 against
3.85e-6). If it hardly falls, most of the residual is not (D4, E65: a factor
of 2.3). What it does not show: a cause. Float64 also changes the parent's
trajectory, and a small residual does not show that the tags' provenance is
right. A causal reading needs, at each precision, a tagged and an untagged run
with bitwise parent fields, the difference of the two precisions' parent
states, a refinement, and a per-tag comparison against a reference.

    python3 float64_twin.py make --config configs/<run>.yml [--out configs/<run>_f64twin.yml]
    python3 float64_twin.py compare --run <output_XXXX> --twin <output_XXXX> [--family water]

Needs python/3.12 (stdlib only for `make` and `compare`).
"""

import argparse
import csv
import math
import os
import re
import sys

# The closure table each family writes, and its columns.
CLOSURE_TABLES = {
    "water": "water_tag_closure.csv",
    "energy": "energy_tag_closure.csv",
    "energy_source": "energy_source_tag_closure.csv",
}
TWIN_T_END = "2hours"


def make_twin(config_path, out_path):
    """Write the twin config. Line-based, so the config's comments and layout
    survive and a reader can diff the two files: only FLOAT_TYPE, t_end and
    job_id change, and a header says where the twin came from."""
    with open(config_path) as f:
        lines = f.read().split("\n")
    keys = {"FLOAT_TYPE": '"Float64"', "t_end": f'"{TWIN_T_END}"'}
    seen = set()
    job_id = None
    out = []
    for line in lines:
        match = re.match(r'^(FLOAT_TYPE|t_end|job_id):\s*(.*)$', line)
        if match is None:
            out.append(line)
            continue
        key, value = match.group(1), match.group(2).strip()
        seen.add(key)
        if key == "job_id":
            job_id = value.strip("\"'")
            out.append(f'job_id: "{job_id}_f64twin"')
        else:
            out.append(f"{key}: {keys[key]}")
    if job_id is None:
        sys.exit(f"{config_path}: no top-level job_id, so the twin's output would overwrite the run's")
    for key in keys:
        if key not in seen:
            out.append(f"{key}: {keys[key]}")
    header = [
        f"# The Float64 twin of {os.path.basename(config_path)}, written by",
        "# analysis/increment/float64_twin.py: FLOAT_TYPE Float64, t_end two hours,",
        "# everything else the same. Run it on one process. It screens for precision",
        "# sensitivity and decides no cause (G4_TODO, prepared item 2).",
    ]
    with open(out_path, "w") as f:
        f.write("\n".join(header + out))
    return out_path


def read_closure(output_dir, family):
    """Return {time: (relative, gross_relative)} from the family's closure
    table. Refuses a missing table, a missing column or a non-finite value,
    since any of them would make the ratio meaningless."""
    path = os.path.join(output_dir, CLOSURE_TABLES[family])
    if not os.path.isfile(path):
        sys.exit(f"no closure table {path}; is --family right?")
    rows = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            for column in ("time", "relative", "gross_relative"):
                if column not in row:
                    sys.exit(f"{path}: no column {column}")
            values = [float(row[c]) for c in ("time", "relative", "gross_relative")]
            if not all(math.isfinite(v) for v in values):
                sys.exit(f"{path}: a non-finite value at time {row['time']}")
            rows[values[0]] = (values[1], values[2])
    return rows


def float_type(output_dir):
    """The FLOAT_TYPE the run's merged config records, or None."""
    for name in os.listdir(output_dir):
        if name.endswith(".yml"):
            with open(os.path.join(output_dir, name)) as f:
                for line in f:
                    match = re.match(r'^FLOAT_TYPE:\s*"?(\w+)"?', line)
                    if match:
                        return match.group(1)
    return None


def compare(run_dir, twin_dir, family):
    run_type, twin_type = float_type(run_dir), float_type(twin_dir)
    if twin_type != "Float64":
        sys.exit(f"the twin records FLOAT_TYPE {twin_type}, not Float64")
    run = read_closure(run_dir, family)
    twin = read_closure(twin_dir, family)
    times = sorted(set(run) & set(twin))
    if not times:
        sys.exit("the two tables share no output time")
    print(f"run  {run_dir} ({run_type})")
    print(f"twin {twin_dir} ({twin_type})")
    print(f"{'time h':>7s} {'gross, run':>12s} {'gross, twin':>12s} {'run / twin':>11s} {'signed, run':>12s} {'signed, twin':>13s}")
    for t in times:
        g_run, g_twin = run[t][1], twin[t][1]
        ratio = g_run / g_twin if g_twin > 0 else float("inf") if g_run > 0 else float("nan")
        print(f"{t / 3600:7.2f} {g_run:12.3e} {g_twin:12.3e} {ratio:11.3g} {run[t][0]:12.3e} {twin[t][0]:13.3e}")
    print("\nA screen for precision sensitivity, not a cause (see this file's docstring).")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    make_parser = sub.add_parser("make", help="write the twin config")
    make_parser.add_argument("--config", required=True)
    make_parser.add_argument("--out")
    compare_parser = sub.add_parser("compare", help="compare the two closure tables")
    compare_parser.add_argument("--run", required=True)
    compare_parser.add_argument("--twin", required=True)
    compare_parser.add_argument("--family", choices=sorted(CLOSURE_TABLES), default="water")
    args = parser.parse_args()
    if args.command == "make":
        out = args.out or re.sub(r"\.yml$", "_f64twin.yml", args.config)
        if os.path.abspath(out) == os.path.abspath(args.config):
            sys.exit("--out would overwrite the config")
        print(make_twin(args.config, out))
        return 0
    return compare(args.run, args.twin, args.family)


if __name__ == "__main__":
    sys.exit(main())
