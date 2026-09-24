"""The owner's review of #102, point 4: the follower's two rules for the column's
total mismatch, |m| and same sign, compared on one case.

    python3 w5r_rule_compare.py OUTPUT_ROOT RUN_ABSM RUN_SAMESIGN [HOURS]

For each run, from its own `output_0000`: the smallest tag value over the
partition's tags and all output times; the partition repair's ledger
(`q_tag_fix_*`, the column's absolute value integrated, relative to the
column's water); and from `water_tag_closure.csv` and `water_tag_audit.csv` at
each hour the gross closure residual, what the follower left out, and the
cells' absolute moved ledger. Agreement with the copies is the verifier's job
(`compare_runs.py`), not this script's.
"""

import csv
import sys

import netCDF4
import numpy as np


def rows(path):
    with open(path) as f:
        return {float(r["time"]): r for r in csv.DictReader(f)}


def nc(directory, name):
    matches = [f"{directory}/{name}_1h_inst.nc", f"{directory}/{name}_30m_inst.nc"]
    for path in matches:
        try:
            with netCDF4.Dataset(path) as ds:
                return np.array(ds["time"][:]), np.array(ds[name][:])
        except FileNotFoundError:
            continue
    return None, None


def moved_column(audit_row):
    for key in ("increment_moved_net_abs_relative", "increment_moved_gross_relative"):
        if key in audit_row:
            return float(audit_row[key])
    return float("nan")


def main():
    root, runs = sys.argv[1], sys.argv[2:4]
    hours = [float(h) for h in sys.argv[4].split(",")] if len(sys.argv) > 4 else None
    for run in runs:
        d = f"{root}/{run}/output_0000"
        closure, audit = rows(f"{d}/water_tag_closure.csv"), rows(f"{d}/water_tag_audit.csv")
        tags = [n for n in ("tropo", "strat", "pbl", "free") if nc(d, f"q_tag_{n}")[0] is not None]
        smallest = min(float(np.min(nc(d, f"q_tag_{n}")[1])) for n in tags)
        print(f"{run}: partition tags {tags}, smallest tag value over the run {smallest:.3e} kg/kg")
        times = sorted(closure)
        for t in times:
            h = t / 3600
            if hours is not None and h not in hours:
                continue
            c, a = closure[t], audit.get(t, {})
            left = float(a.get("increment_left_relative", "nan"))
            print(
                f"  {h:5.1f} h  gross residual {float(c['gross_relative']):.2e}  "
                f"net {float(c['relative']):+.2e}  left out {left:+.2e}  "
                f"moved (net abs over cells) {moved_column(a):.2e}"
            )


if __name__ == "__main__":
    main()
