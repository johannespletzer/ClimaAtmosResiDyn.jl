"""WP5b's distinguishing experiment: read the probes' RESULT lines and final
columns, and compare.

    python3 wp5b_compare.py PROBE_DIR LOG_DIR

PROBE_DIR holds `<run>.csv` from `wp5b_probe.jl`; LOG_DIR holds the jobs'
`.out`/`.err` with the RESULT lines. It prints:
  - per run, the closure (net and gross), the part the follower left out, the
    smallest partition tag and the partition repair ledger;
  - the parent fields' parity across all runs, compared as the exact values
    `repr` wrote (ρ, ρq_tot, ρe_tot, ρq_rai, ρq_sno);
  - per tag, the default mode against the copies, L1 over the column with
    weights ρ (the grid is uniform), at each cross-block setting and transport.
"""

import csv
import glob
import os
import re
import sys

import numpy as np


def read_results(log_dir):
    results = {}
    for path in glob.glob(os.path.join(log_dir, "*.out")) + glob.glob(os.path.join(log_dir, "*.err")):
        with open(path) as f:
            text = f.read()
        m = re.search(r"RESULT run=(\S+) commit=(\S+) ret=(\S+)", text)
        if not m:
            continue
        run = m.group(1)
        r = results.setdefault(run, {"commit": m.group(2), "ret": m.group(3)})
        if (m := re.search(r"RESULT closure net=(\S+) gross=(\S+)", text)):
            r["net"], r["gross"] = float(m.group(1)), float(m.group(2))
        if (m := re.search(r"RESULT smallest_partition_tag_kg_per_kg=(\S+)", text)):
            r["smallest"] = float(m.group(1))
        if (m := re.search(r"RESULT partition_repair_ledger_abs_sum_over_cells=(\S+) scale=(\S+)", text)):
            r["repair"], r["scale"] = float(m.group(1)), float(m.group(2))
        if (m := re.search(r"increment_left_relative = (\S+?)[,)]", text)):
            r["left"] = float(m.group(1))
    return results


def read_column(path):
    with open(path) as f:
        rows = list(csv.reader(f))
    header, values = rows[0], rows[1:]
    exact = {name: [row[i] for row in values] for i, name in enumerate(header)}
    numeric = {name: np.array([float(v) for v in col]) for name, col in exact.items()}
    return exact, numeric


def main():
    probe_dir, log_dir = sys.argv[1], sys.argv[2]
    results = read_results(log_dir)
    columns = {os.path.basename(p)[:-4]: read_column(p) for p in glob.glob(os.path.join(probe_dir, "*.csv"))}
    runs = sorted(set(results) | set(columns))
    print("run | commit | net | gross | left out | smallest tag | repair / scale")
    for run in runs:
        r = results.get(run, {})
        rep = r.get("repair", float("nan")) / r.get("scale", float("nan")) if "scale" in r else float("nan")
        print(
            f"{run} | {r.get('commit', '?')} | {r.get('net', float('nan')):+.2e} | {r.get('gross', float('nan')):.2e} | "
            f"{r.get('left', float('nan')):+.2e} | {r.get('smallest', float('nan')):.2e} | {rep:.2e}"
        )
    parent = ("ρ", "ρq_tot", "ρe_tot", "ρq_rai", "ρq_sno")
    names = sorted(columns)
    if names:
        reference = columns[names[0]][0]
        for run in names[1:]:
            differing = [n for n in parent if columns[run][0].get(n) != reference.get(n)]
            print(f"parent parity {run} against {names[0]}: {'bit for bit' if not differing else 'DIFFERS in ' + ', '.join(differing)}")
    for label in ("off", "on"):
        for transport in ("tracer", "increment"):
            d = f"wp5b_{label}_default_{transport}_n1"
            c = f"wp5b_{label}_copies_{transport}_n1"
            if d not in columns or c not in columns:
                continue
            nd, nc = columns[d][1], columns[c][1]
            rho = nc["ρ"]
            line = []
            for tag in ("ρq_tag_tropo", "ρq_tag_strat", "ρq_tag_evap"):
                qd, qc = nd[tag] / nd["ρ"], nc[tag] / rho
                l1 = np.sum(rho * np.abs(qd - qc)) / np.sum(rho * np.abs(qc))
                line.append(f"{tag[6:]} {100 * l1:.3f}%")
            print(f"default against copies, cross blocks {label}, {transport}: " + ", ".join(line))


if __name__ == "__main__":
    main()
