"""C's revision: the parity check's output (design/NEGATIVE_PARENT_WATER.md,
section 11.8).

    python3 cr_parity.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds
`cr_parity_{tags,untagged}_{rev,main}/output_0000`: site 23 for 10 days, on
the revision's run tree and on main's. For each pair it compares every
NetCDF file both runs wrote, as bit patterns, at every output time:

  - the revision against main, with tags and without: every model field must
    match, with the same times, and every file of the main run must exist in
    the revision's run;
  - with tags against without, on each tree: every model field must match
    (the fork's parity with a diagnostic on);
  - the water tags' files, the revision against main: reported. Each is
    either the same, or differs from a first output time on. The rule acts
    only where the parent is below zero, which here starts after day 9.

The prognostic state at day 10 is compared by `cr_parity_state.jl`. It exits
1 if a model field differs or is missing.
"""
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
DAY = 86400.0
MODEL_FIELDS = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")
failed = []


def out(job):
    return os.path.join(ROOT, job, "output_0000")


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def load(path, var):
    with nc.Dataset(path) as d:
        v = d[var]
        a = np.asarray(v[:])
        if "time" in v.dimensions:
            a = np.moveaxis(a, v.dimensions.index("time"), 0)
        return np.asarray(d["time"][:]), a


def variable(name):
    return re.sub(r"_(1d|6h|1h)_(inst|average)\.nc$", "", name)


def compare_model(a, b, label):
    files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(out(b), "*.nc")))
    files = [f for f in files if variable(f) in MODEL_FIELDS]
    bad = []
    for f in files:
        if not os.path.exists(os.path.join(out(a), f)):
            bad.append(f"{f} (missing)")
            continue
        ta, va = load(os.path.join(out(a), f), variable(f))
        tb, vb = load(os.path.join(out(b), f), variable(f))
        if not (np.array_equal(bits(ta), bits(tb)) and va.shape == vb.shape and np.array_equal(bits(va), bits(vb))):
            bad.append(f)
    ok = bool(files) and not bad
    if not ok:
        failed.append(label)
    last = load(os.path.join(out(b), files[0]), variable(files[0]))[0][-1] / DAY if files else None
    print(f"{label}: {len(files)} model field files, to day {last}: {'bit for bit' if ok else 'FAIL'}"
          + (f" ({bad})" if bad else ""))


def compare_tags(a, b):
    files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(out(b), "q_tag_*.nc")))
    for f in files:
        if not os.path.exists(os.path.join(out(a), f)):
            print(f"    {f}: missing in {a}")
            continue
        ta, va = load(os.path.join(out(a), f), variable(f))
        tb, vb = load(os.path.join(out(b), f), variable(f))
        n = min(len(ta), len(tb))
        same = [np.array_equal(bits(va[i]), bits(vb[i])) for i in range(n)]
        if all(same):
            print(f"    {f}: the same at {n} outputs")
            continue
        first = same.index(False)
        scale = max(float(np.max(np.abs(vb[:n]))), np.finfo(float).tiny)
        print(f"    {f}: the same to day {ta[first - 1] / DAY if first else None}, differs from day "
              f"{ta[first] / DAY}, largest difference {float(np.max(np.abs(va[:n] - vb[:n]))) / scale:.2e} "
              f"of the field's largest value")


def main():
    compare_model("cr_parity_tags_rev", "cr_parity_tags_main", "tags on, the revision against main")
    compare_model("cr_parity_untagged_rev", "cr_parity_untagged_main", "tags off, the revision against main")
    compare_model("cr_parity_tags_rev", "cr_parity_untagged_rev", "the revision, tags on against off")
    compare_model("cr_parity_tags_main", "cr_parity_untagged_main", "main, tags on against off")
    print("the water tags, the revision against main (reported):")
    compare_tags("cr_parity_tags_rev", "cr_parity_tags_main")
    print("RESULT", "every model field bit for bit" if not failed else f"failed: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
