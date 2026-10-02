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
# Section 10 (2026-10-02): `--discard 1` drops the first timed block before
# anything is read from the blocks.
discard = int(sys.argv[sys.argv.index("--discard") + 1]) if "--discard" in sys.argv else 0
# `--skip ARM` leaves out an arm that was rerun (section 10's note).
skip = {sys.argv[i + 1] for i, a in enumerate(sys.argv) if a == "--skip"}
rows = []
for f in sorted(glob.glob(root + "/*/*.csv")):
    if f.endswith("status.csv"):
        continue
    got = list(csv.DictReader(open(f)))
    if len(got) != 1:
        sys.exit(f"{f}: one row expected")
    got[0]["arm"] = f.split("/")[-2]
    if got[0]["arm"] in skip:
        continue
    if discard:
        kept = np.array(got[0]["step_ms_blocks"].split(";"), float)[discard:]
        got[0]["step_ms_blocks"] = ";".join(str(x) for x in kept)
        got[0]["step_ms_min"] = str(kept.min())
    rows.append(got[0])
# Since the amendment of 2026-10-02 every arm has its own baseline on its own
# node, and each point is read against it. Before, one baseline per base config.
same_node = {r["arm"] for r in rows if r["ntags"] == "0"} == {r["arm"] for r in rows}
base = {}
for r in rows:
    if r["ntags"] == "0":
        k = r["arm"] if same_node else r["base"]
        if k in base:
            sys.exit(f"two baselines for {k}")
        base[k] = r
def baseline(r):
    return base[r["arm"] if same_node else r["base"]]
groups = defaultdict(list)
for r in rows:
    if r["variant"] == "none" and r["ntags"] != "0":
        groups[(r["family"], r["base"], r["mode"], r["precip"])].append(r)
def fit(ns, ys):
    k, a = np.polyfit(np.log(ns), np.log(ys), 1)
    return k
print("base, mode, precip: exponent of added step time | of build time | local exponents of added step time")
for key, pts in sorted(groups.items()):
    pts.sort(key=lambda r: int(r["ntags"]))
    ns = np.array([int(r["ntags"]) for r in pts], float)
    add = np.array([float(r["step_ms_min"]) - float(baseline(r)["step_ms_min"]) for r in pts])
    build = np.array([float(r["build_s"]) for r in pts])
    if len(ns) < 2:
        print(key, "N=%s" % [int(n) for n in ns], "one point, no fit; added step %.3f ms" % add[0])
        continue
    loc = [np.log(add[i + 1] / add[i]) / np.log(ns[i + 1] / ns[i]) for i in range(len(ns) - 1)]
    print(key, "N=%s" % [int(n) for n in ns], "k_step=%.2f" % fit(ns, add), "k_build=%.2f" % fit(ns, build),
          "local", [round(x, 2) for x in loc])
    # spread of the block ratios, dropping nothing
    for r in pts:
        q = np.array(r["step_ms_blocks"].split(";"), float) / np.array(baseline(r)["step_ms_blocks"].split(";"), float)
        q4 = q[1:]  # with --discard, these are the measured blocks after the first kept one
        print("   N=%s ratio blocks %s spread %.1f%% (blocks 2-5 %.1f%%)" % (r["ntags"], np.round(q, 2),
              100 * (q.max() / q.min() - 1), 100 * (q4.max() / q4.min() - 1)))
