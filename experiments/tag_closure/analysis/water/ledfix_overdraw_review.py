"""W63's review checks, not pre-registered.

    python3 ledfix_overdraw_review.py [OUTPUT_ROOT]

It reuses the functions of `ledfix_overdraw_score.py`, as
`ledfix_overdraw_givefirst.py` does, and prints four things:

  - S with both less favourable choices at once: the stage-level overdraw
    (`Es`, reported in 11.13.5) and the negative part's give taken out of r
    first (as `ledfix_overdraw_givefirst.py`);
  - S with the whole outflow `O` in place of `E`. It shows how much of S
    depends on the content condition;
  - in rev's repaired cell-steps, both arms: the share of free's outflow that
    exceeds free's content at the step's start, `ΣE / ΣO`;
  - the sign of the parent, `ρq_tot`, at the step's end: in each arm's
    repaired cell-steps, by count and by repair, and in all traced cell-steps;
    and whether the parent is the same in both arms' step traces.
"""
import os
import sys

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "ledfix_overdraw_score.py")).read().split("if CHECK:")[0]
sys.argv = ["ledfix_overdraw_score.py"] + sys.argv[1:2]
exec(src)

rec = {run: cell_steps(run) for run in (REV, SWITCH)}


def repair(r):
    return np.maximum(r["r_free"], 0)


def score_with(explained_of):
    X = {run: explained_of(r) for run, r in rec.items()}
    R = {run: repair(r).sum() for run, r in rec.items()}
    S = (X[REV] - X[SWITCH]) / (R[REV] - R[SWITCH])
    return S, X[REV] / R[REV], X[SWITCH] / R[SWITCH]


def give_first_stage(r):
    rest = np.maximum(repair(r) - np.maximum(-r["G_free"], 0), 0)
    return np.minimum(r["Es_free"], rest).sum()


def whole_outflow(r):
    return np.minimum(r["O_free"], repair(r)).sum()


for label, f in (
    ("S with the stage-level overdraw and the give first", give_first_stage),
    ("S with the whole outflow in place of E", whole_outflow),
):
    S, fr, fs = score_with(f)
    print(f"{label}: {S:.3f} (explained rev {fr:.3f} of R, switch {fs:.3f})")
    result(label.replace(" ", "_"), f"{S:.3f}")

rv, sw = rec[REV], rec[SWITCH]
ev = repair(rv) > 0
for run, r in ((REV, rv), (SWITCH, sw)):
    O, E = r["O_free"][ev].sum(), r["E_free"][ev].sum()
    print(f"In rev's repaired cell-steps, {run}: ΣO {O:.4e}, ΣE {E:.4e}, ΣE/ΣO {E / O:.3f}, "
          f"free at the start {r['q0_free'][ev].sum():.4e}, rest of the step Σb {r['b_free'][ev].sum():.4e}, "
          f"Σr+ {repair(r)[ev].sum():.4e}")

parents = {}
for run in (REV, SWITCH):
    tr = load(os.path.join(out(run), f"{run}_trace.csv"))
    parents[run] = tr["ρq_tot"]
    lev = tr["level"] >= 1
    ends = np.flatnonzero(tr["step_end"][lev] == 1)
    parent_end = tr["ρq_tot"][lev][ends]
    r = rec[run]
    if not (np.array_equal(r["step"], tr["step"][lev][ends].astype(np.int64))
            and np.array_equal(r["level"], tr["level"][lev][ends].astype(np.int64))):
        raise SystemExit(f"{run}: the step trace's rows do not match the cell-steps")
    e = repair(r) > 0
    neg = parent_end < 0
    print(f"{run}: ρq_tot < 0 at the step's end in {neg[e].mean():.3f} of the {int(e.sum())} repaired cell-steps, "
          f"holding {repair(r)[neg].sum() / repair(r).sum():.3f} of the repair; "
          f"in {neg.mean():.3f} of all {len(neg)} traced cell-steps")
same = parents[REV].shape == parents[SWITCH].shape and np.array_equal(parents[REV], parents[SWITCH])
print(f"ρq_tot in the step traces, every row, the same in both arms: {same}")
