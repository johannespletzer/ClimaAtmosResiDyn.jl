"""
Where the 8 + 8 point's excess over its halves sits (design/WP9_COST.md
section 12). It decides nothing.

    python3 analysis/wp9_excess.py $SCRATCH/tag_closure/output/wp9_profile_d3c5 [--out excess.md]

The argument has one directory per job (`prof88_a`, `prof88_b`). Each holds
the CSVs of `wp9_profile_driver.jl` for four points on one node: untagged,
8 water, 8 energy and 8 + 8, all on D4. For every key of a table (the phase,
the call inside the hook, the tag entry) it reads the time per step (sample
share times the point's timed step) and the bytes per step, and forms

    excess = both - water - energy + untagged,

the cost of the 8 + 8 point beyond the sum of its two halves' added costs.
The keys are ranked by their excess in time. A job's rows run until they hold
80% of the job's total excess (the timed blocks' own excess) or 12 rows. The
sampling error of a key's excess is printed beside it, from the four sample
counts, as one standard deviation of a Poisson count.

Across the jobs: a key is listed as holding the excess when it is in the 80%
rows of every job. Its share quoted is the smallest over the jobs. A profile
locates where the cost is recorded. It does not say why.
"""

import argparse
import csv
import math
import sys
from pathlib import Path

csv.field_size_limit(sys.maxsize)
POINTS = ("untagged", "water", "energy", "both")
SIGN = {"untagged": 1, "water": -1, "energy": -1, "both": 1}


def read(path):
    with open(path) as f:
        return list(csv.DictReader(f))


def job_points(d):
    pts = {}
    for s in d.glob("*_summary.csv"):
        r = read(s)[0]
        if r["ntags"] == "0":
            key = "untagged"
        elif r["ntags"] == "8":
            key = r["family"]
        else:
            sys.exit(f"{s}: unexpected tag count {r['ntags']}.")
        if key in pts:
            sys.exit(f"{d}: two {key} points.")
        pts[key] = (s, r)
    missing = set(POINTS) - set(pts)
    if missing:
        sys.exit(f"{d}: missing points {sorted(missing)}.")
    hosts = {r["host"] for _, r in pts.values()}
    commits = {r["commit"] for _, r in pts.values()}
    if len(hosts) != 1 or len(commits) != 1:
        sys.exit(f"{d}: points on {sorted(hosts)} at {sorted(commits)}; one node and one commit expected.")
    return pts


def table(pts, name):
    """key -> {point: (ms, samples, bytes)}, and each point's sample total."""
    out, totals = {}, {}
    for p, (s, r) in pts.items():
        stem = str(s)[: -len("_summary.csv")]
        totals[p] = (float(r["step_ms"]), float(r["samples"]))
        if name == "phase":
            t = {x["phase"]: x for x in read(stem + "_time_phase.csv")}
            a = {x["phase"]: x for x in read(stem + "_alloc_phase.csv")}
            for k in set(t) | set(a):
                out.setdefault(k, {})[p] = (
                    float(t[k]["ms_per_step"]) if k in t else 0.0,
                    float(t[k]["samples"]) if k in t else 0.0,
                    float(a[k]["bytes_per_step"]) if k in a else 0.0,
                )
        elif name == "frame":
            # Post hoc, added after the first job's read (section 12 note): the
            # innermost frame in `src/`, from section 8's top-80 tables. A frame
            # outside one point's top 80 reads as 0 there; the 80th row bounds it.
            t = {x["frame"]: x for x in read(stem + "_time_frame.csv")}
            a = {x["frame"]: x for x in read(stem + "_alloc_frame.csv")}
            for k in set(t) | set(a):
                out.setdefault(k, {})[p] = (
                    float(t[k]["ms_per_step"]) if k in t else 0.0,
                    float(t[k]["samples"]) if k in t else 0.0,
                    float(a[k]["bytes_per_step"]) if k in a else 0.0,
                )
        else:
            for x in read(f"{stem}_{name}.csv"):
                out.setdefault(x["key"], {})[p] = (
                    float(x["ms_per_step"]), float(x["samples"]), float(x["bytes_per_step"]))
    return out, totals


def rows_for(pts, name):
    data, totals = table(pts, name)
    total = sum(SIGN[p] * totals[p][0] for p in POINTS)
    rows = []
    for k, v in data.items():
        get = lambda p, i: v.get(p, (0.0, 0.0, 0.0))[i]
        ex = sum(SIGN[p] * get(p, 0) for p in POINTS)
        exb = sum(SIGN[p] * get(p, 2) for p in POINTS)
        # Poisson error of each count, scaled to ms by that point's ms per sample.
        sd = math.sqrt(sum((totals[p][0] / totals[p][1]) ** 2 * get(p, 1) for p in POINTS))
        rows.append((k, [get(p, 0) for p in POINTS], ex, sd, exb))
    rows.sort(key=lambda r: -r[2])
    return rows, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--frames", action="store_true", help="also the innermost frames (post hoc)")
    args = ap.parse_args()
    jobs = sorted(d for d in args.root.iterdir() if d.is_dir() and list(d.glob("*_summary.csv")))
    if not jobs:
        sys.exit("No job directories with profile summaries.")
    lines = []
    held = {}
    for d in jobs:
        pts = job_points(d)
        r0 = pts["untagged"][1]
        steps = {p: float(pts[p][1]["step_ms"]) for p in POINTS}
        bytes_ = {p: float(pts[p][1]["bytes_per_step"]) for p in POINTS}
        lines += [
            f"## Job `{d.name}`, node `{r0['host']}`, commit `{r0['commit'][:8]}`",
            "",
            "Timed block, ms per step: " + ", ".join(f"{p} {steps[p]:.3f}" for p in POINTS)
            + f". Excess {sum(SIGN[p] * steps[p] for p in POINTS):.3f} ms; bytes per step excess "
            f"{sum(SIGN[p] * bytes_[p] for p in POINTS):.0f}. Samples: "
            + ", ".join(f"{p} {float(pts[p][1]['samples']):.0f}" for p in POINTS) + ".",
            "",
        ]
        for name in ("phase", "call", "tag_entry") + (("frame",) if args.frames else ()):
            rows, total = rows_for(pts, name)
            lines += [f"### By {name.replace('_', ' ')}", "",
                      "| key | untagged ms | water ms | energy ms | both ms | excess ms | ± | share | excess B/step |",
                      "|:--|--:|--:|--:|--:|--:|--:|--:|--:|"]
            acc = 0.0
            for i, (k, v, ex, sd, exb) in enumerate(rows):
                if i >= 12 or acc >= 0.8 * total or ex <= 0:
                    break
                acc += ex
                share = ex / total if total > 0 else float("nan")
                held.setdefault((name, k), {})[d.name] = share
                lines.append(f"| {k} | " + " | ".join(f"{x:.3f}" for x in v)
                             + f" | {ex:.3f} | {sd:.3f} | {100 * share:.1f}% | {exb:.0f} |")
            lines += ["", f"These rows hold {100 * acc / total:.1f}% of the excess, {total:.3f} ms.", ""]
    lines += ["## Keys in the 80% rows of every job (smallest share over the jobs)", "",
              "| table | key | share |", "|:--|:--|--:|"]
    for (name, k), sh in sorted(held.items(), key=lambda x: -min(x[1].values())):
        if len(sh) == len(jobs):
            lines.append(f"| {name} | {k} | {100 * min(sh.values()):.1f}% |")
    text = "\n".join(lines)
    print(text)
    if args.out:
        args.out.write_text(text + "\n")


if __name__ == "__main__":
    main()
