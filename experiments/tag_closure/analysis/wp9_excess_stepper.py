"""
The 8 + 8 excess of design/WP9_COST.md section 12.1, read against the
stepper's samples only. Post hoc, added by the review of E90 (2026-10-02).
It decides nothing.

    python3 analysis/wp9_excess_stepper.py output/wp9_profile_d3c5

The profile jobs ran with a second Julia thread, present after
`import ClimaAtmos` in the run tree's environment (`wp9_profile_threads.jl`).
`Profile` samples every thread at every tick, so half of each point's samples
are that thread's, and none of them has a frame in `src/`. This script takes
each point's stepper samples as half of its samples, removes that half from
the `other` phase and from `(not tag code)`, and forms the excess as
`wp9_excess.py` does, in ms of the timed step. The shares are against the
timed excess. A key's ms is its share of the stepper's samples times the timed
step, so it is only as good as the timed step is for the profiled steps.
"""

import csv
import sys
from pathlib import Path

csv.field_size_limit(sys.maxsize)
SIGN = {"untagged": 1, "water": -1, "energy": -1, "both": 1}
WALKS = (
    "utils/tracer_processes.jl:138 ",
    "utils/tracer_processes.jl:153 ",
    "utils/variable_manipulations.jl:242 ",
    "utils/variable_manipulations.jl:118 gs_tracer_names",
    "utils/tracer_processes.jl:307 microphysics_tracer_names",
    "utils/variable_manipulations.jl:272 sgs_tracer_names",
)
# The one key of each table that holds the second thread's samples.
THREAD_KEY = {"time_phase": "other", "tag_entry": "(not tag code)", "time_frame": "(outside src)"}


def points(job):
    pts = {}
    for s in job.glob("*_summary.csv"):
        r = next(csv.DictReader(open(s)))
        pts["untagged" if r["ntags"] == "0" else r["family"]] = (r, str(s)[: -len("_summary.csv")])
    if set(pts) != set(SIGN):
        sys.exit(f"{job}: points {sorted(pts)}")
    return pts


def excess(pts, table):
    out = {}
    for k, (r, stem) in pts.items():
        n, step = float(r["samples"]), float(r["step_ms"])
        for x in csv.DictReader(open(f"{stem}_{table}.csv")):
            key = x[next(iter(x))]
            s = float(x["samples"]) - (n / 2 if key == THREAD_KEY[table] else 0.0)
            out[key] = out.get(key, 0.0) + SIGN[k] * step * s / (n / 2)
    return out


def main(root):
    for job in sorted(Path(root).glob("prof88_*")):
        pts = points(job)
        total = sum(SIGN[k] * float(pts[k][0]["step_ms"]) for k in SIGN)
        print(f"## {job.name}: timed excess {total:.3f} ms\n")
        for k in SIGN:
            r = pts[k][0]
            n = float(r["samples"])
            per_ms = n / (float(r["time_steps"]) * float(r["step_ms"]))
            print(f"  - {k}: {per_ms:.2f} samples per timed ms")
        for table in ("time_phase", "tag_entry"):
            ex = excess(pts, table)
            print(f"\n{table}:")
            for key, v in sorted(ex.items(), key=lambda kv: -kv[1])[:6]:
                print(f"  - {key}: {v:.2f} ms, {100 * v / total:.1f}%")
        ex = excess(pts, "time_frame")
        walks = sum(v for key, v in ex.items() if key.startswith(WALKS))
        print(f"\nsix walk frames: {walks:.2f} ms, {100 * walks / total:.0f}% of the timed excess\n")


if __name__ == "__main__":
    main(sys.argv[1])
