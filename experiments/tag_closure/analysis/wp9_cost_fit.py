"""
The scaling of V-W10's added step time and build time with the tag count, and
the block-to-block spread that says how far to trust each point. It decides
nothing.

    python3 analysis/wp9_cost_fit.py $SCRATCH/tag_closure/output/wp9_cost

For each arm of variant `none` it fits `log(added) = a + k log N` by least
squares, where added is `step_min(N) - step_min(0)` (ms) or `build(N)` (s), over
the tag counts given. It prints the exponent `k` with the points it rests on,
and the local exponent between neighbouring counts. Two points fit exactly, so
read `k` with its point count. The spread column is that of the ratio to the
untagged baseline block by block, which removes model-time changes in cost.
"""
import csv, glob, sys
from collections import defaultdict
import numpy as np

root = sys.argv[1]
rows = []
for f in sorted(glob.glob(root + "/*/*.csv")):
    if f.endswith("status.csv"):
        continue
    got = list(csv.DictReader(open(f)))
    if len(got) != 1:
        sys.exit(f"{f}: one row expected")
    rows.append(got[0])
base = {}
for r in rows:
    if r["ntags"] == "0":
        if r["base"] in base:
            sys.exit(f"two baselines for {r['base']}")
        base[r["base"]] = r
groups = defaultdict(list)
for r in rows:
    if r["variant"] == "none" and r["ntags"] != "0":
        groups[(r["base"], r["mode"], r["precip"])].append(r)
def fit(ns, ys):
    k, a = np.polyfit(np.log(ns), np.log(ys), 1)
    return k
print("base, mode, precip: exponent of added step time | of build time | local exponents of added step time")
for key, pts in sorted(groups.items()):
    if key[0] not in base:
        sys.exit(f"no baseline for {key[0]}")
    b0 = base[key[0]]
    pts.sort(key=lambda r: int(r["ntags"]))
    ns = np.array([int(r["ntags"]) for r in pts], float)
    add = np.array([float(r["step_ms_min"]) - float(b0["step_ms_min"]) for r in pts])
    build = np.array([float(r["build_s"]) for r in pts])
    loc = [np.log(add[i + 1] / add[i]) / np.log(ns[i + 1] / ns[i]) for i in range(len(ns) - 1)]
    print(key, "N=%s" % [int(n) for n in ns], "k_step=%.2f" % fit(ns, add), "k_build=%.2f" % fit(ns, build),
          "local", [round(x, 2) for x in loc])
    # spread of the block ratios, dropping nothing
    for r in pts:
        q = np.array(r["step_ms_blocks"].split(";"), float) / np.array(b0["step_ms_blocks"].split(";"), float)
        q4 = q[1:]
        print("   N=%s ratio blocks %s spread %.1f%% (blocks 2-5 %.1f%%)" % (r["ntags"], np.round(q, 2),
              100 * (q.max() / q.min() - 1), 100 * (q4.max() / q4.min() - 1)))
