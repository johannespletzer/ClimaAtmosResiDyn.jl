"""C's revision, 11.11.11 item 7: the exp ledger's timing against the first tag difference.

    python3 cr_exp_ledger_timing.py [OUTPUT_ROOT [PREFIX [REV_OUTPUT [MAIN_OUTPUT]]]]

Defaults: `$SCRATCH/tag_closure/output`, `cr_parity30`, `output_active`,
`output_active`. It reads `water_tag_audit.csv` of
`<PREFIX>_tags_rev/REV_OUTPUT`: the columns `exp_negative_retained` and
`exp_negative_events`, one row per audit time. Both are running totals.

It finds the first output time at which a water tag file of the revision
differs from main's, as `compare_tags` in `cr_parity.py` does: every
`q_tag_*.nc` of `<PREFIX>_tags_main/MAIN_OUTPUT` that the revision's output has,
bit for bit, the earliest time of any difference over all files. Exit status 0
only if

  - both columns are zero at every audit row before that time, and
  - at least one of them is nonzero at every audit row from that time on.

The first row with a nonzero total is printed with the first differing time.
No differing tag file, or no audit column, fails.
"""
import csv
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
PREFIX = sys.argv[2] if len(sys.argv) > 2 else "cr_parity30"
REV_OUTPUT = sys.argv[3] if len(sys.argv) > 3 else "output_active"
MAIN_OUTPUT = sys.argv[4] if len(sys.argv) > 4 else "output_active"
COLUMNS = ("exp_negative_retained", "exp_negative_events")


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def first_difference(rev_dir, main_dir):
    """The earliest output time at which any shared q_tag_*.nc differs, and the file that shows it."""
    first, where = None, None
    for path in sorted(glob.glob(os.path.join(main_dir, "q_tag_*.nc"))):
        name = os.path.basename(path)
        other = os.path.join(rev_dir, name)
        if not os.path.exists(other):
            continue
        with nc.Dataset(other) as a, nc.Dataset(path) as b:
            var = re.sub(r"_(1d|6h|1h)_(inst|average)\.nc$", "", name)
            if var not in a.variables:
                continue
            ta, tb = np.asarray(a["time"][:]), np.asarray(b["time"][:])
            n = min(len(ta), len(tb))
            va = np.moveaxis(np.asarray(a[var][:]), a[var].dimensions.index("time"), 0)[:n]
            vb = np.moveaxis(np.asarray(b[var][:]), b[var].dimensions.index("time"), 0)[:n]
            for i in range(n):
                if not np.array_equal(bits(va[i]), bits(vb[i])):
                    if first is None or ta[i] < first:
                        first, where = float(ta[i]), name
                    break
    return first, where


def main():
    rev_dir = os.path.join(ROOT, f"{PREFIX}_tags_rev", REV_OUTPUT)
    main_dir = os.path.join(ROOT, f"{PREFIX}_tags_main", MAIN_OUTPUT)
    print(f"revision: {os.path.realpath(rev_dir)}\nmain:     {os.path.realpath(main_dir)}")
    first, where = first_difference(rev_dir, main_dir)
    if first is None:
        print("FAIL: no water tag file differs between the revision and main")
        return 1
    with open(os.path.join(rev_dir, "water_tag_audit.csv")) as f:
        rows = list(csv.DictReader(f))
    if not rows or any(c not in rows[0] for c in COLUMNS):
        print(f"FAIL: water_tag_audit.csv has no rows or lacks {COLUMNS}")
        return 1
    times = [float(r["time"]) for r in rows]
    nonzero = [any(float(r[c]) != 0.0 for c in COLUMNS) for r in rows]
    before = [i for i, t in enumerate(times) if t < first]
    after = [i for i, t in enumerate(times) if t >= first]
    early = [times[i] for i in before if nonzero[i]]
    zero_after = [times[i] for i in after if not nonzero[i]]
    first_nonzero = next((times[i] for i, z in enumerate(nonzero) if z), None)
    ok = bool(before) and bool(after) and not early and not zero_after
    print(f"first differing tag output: {first:.0f} s (day {first / 86400.0}), file {where}")
    print(f"audit rows: {len(rows)}, {len(before)} before that time, {len(after)} from it on")
    print(f"first audit row with a nonzero exp_negative_retained or exp_negative_events: "
          f"{first_nonzero if first_nonzero is None else f'{first_nonzero:.0f} s (day {first_nonzero / 86400.0})'}")
    print(f"nonzero before the first difference: {early or 'none'}")
    print(f"zero from the first difference on: {zero_after or 'none'}")
    print("LEDGER TIMING", "pass" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
