"""W63, reported and not pre-registered: S with the negative part's give first.

    python3 ledfix_overdraw_givefirst.py [OUTPUT_ROOT]

In each cell-step, the repair the give could explain, max(-G, 0), is taken
out of r before the overdraw E is counted. This ordering favours the other
channel, so it gives a lower bound on S. It reuses the functions of
`ledfix_overdraw_score.py`.
"""
import os
import sys

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "ledfix_overdraw_score.py")).read().split("if CHECK:")[0]
sys.argv = ["ledfix_overdraw_score.py"] + sys.argv[1:2]
exec(src)

rec = {run: cell_steps(run) for run in (REV, SWITCH)}
X, R = {}, {}
for run, r in rec.items():
    rp = np.maximum(r["r_free"], 0)
    rest = np.maximum(rp - np.maximum(-r["G_free"], 0), 0)
    X[run] = np.minimum(r["E_free"], rest).sum()
    R[run] = rp.sum()
    ev = rp > 0
    print(f"{run}: give-first explained {X[run]:.4e} of R {R[run]:.4e}; "
          f"over the events give {r['G_free'][ev].sum():.4e}, outflow {r['O_free'][ev].sum():.4e}")
print(f"S give-first {(X[REV] - X[SWITCH]) / (R[REV] - R[SWITCH]):.3f}")
