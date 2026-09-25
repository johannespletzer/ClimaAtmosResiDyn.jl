"""Read `wp4c_diag_probe.jl`'s tables: why WP4c's correction raises part 2a.

    python3 wp4c_diag_read.py DIAG_DIR [--dt 120]

For each `<run>_<set>_diag_steps.csv` and its `_diag_cells.csv` in DIAG_DIR it
prints, over the sampled steps, per day and over the water `W` at the last
sampled step:
  - X, V1's part 2a per step (moved, A − C); X + L, W40's (B − C); L, what the
    correction takes out of the moved part (B − A); the closed-form leak and
    the part of it the correction cannot take (the residual leak);
  - the rise, Σ|X| − Σ|X + L|, and how it splits by stage;
  - per stage and part, the gross of the part of X and of L, the part's
    projection on −L (its share of what L cancels), and its marginal effect on
    Σ|X| (Σ|X| − Σ|X − part|);
  - the probe's checks: the re-solve and linearity errors, the stage weights,
    and how much of each stage's X the parts leave unexplained.
The parts are the probe's (its header comment). Nothing here sets a threshold.
"""
import argparse
import csv
import glob
import os

import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("diag_dir")
parser.add_argument("--dt", type=float, default=120.0)
args = parser.parse_args()

PARTS = ["tend", "filt_q", "filt_T", "lin_o", "jac", "post_diff", "constr_diff"]


def read(path):
    with open(path) as f:
        reader = csv.reader(f)
        header = next(reader)
        data = np.array([[float(v) for v in row] for row in reader])
    return header, data


for steps_path in sorted(glob.glob(os.path.join(args.diag_dir, "*_diag_steps.csv"))):
    name = os.path.basename(steps_path)[: -len("_diag_steps.csv")]
    header, S = read(steps_path)
    col = {h: i for i, h in enumerate(header)}
    cheader, Cc = read(steps_path.replace("_diag_steps.csv", "_diag_cells.csv"))
    ccol = {h: i for i, h in enumerate(cheader)}
    n = len(S)
    W = S[-1, col["water"]]
    days = n * args.dt / 86400
    per_day = lambda x: x / W / days
    print(f"\n== {name}: {n} sampled steps from t = {S[0, 0]:.0f} s to {S[-1, 0]:.0f} s, "
          f"{days:.4f} days, W = {W:.6g} kg m-2 (per day, over W)")
    for q in ("X", "XL", "L", "leak", "leak_residual"):
        print(f"   {q:14s} gross {per_day(S[:, col[q + '_gross']].sum()):.4e}   "
              f"net {per_day(S[:, col[q + '_net']].sum()):+.3e}")
    rise = S[:, col["X_gross"]].sum() - S[:, col["XL_gross"]].sum()
    print(f"   rise, Σ|X| − Σ|X + L|: {per_day(rise):+.4e}")
    print(f"   check: stage weights reproduce A's moved to {S[:, col['A_stage_weight_error']].max():.2e} kg m-3")

    # Cells: weights J make Σ f J the column integral; checked against the
    # steps table.
    t = Cc[:, ccol["t_seconds"]]
    J = Cc[:, ccol["J"]]
    X = Cc[:, ccol["X"]]
    L = Cc[:, ccol["L"]]
    ratio = np.sum(np.abs(X) * J) / S[:, col["X_gross"]].sum()
    print(f"   check: Σ|X|J over the cells / the steps' X gross = {ratio:.12f}")
    ip = lambda a, b: float(np.sum(a * b * J))
    LL = ip(L, L)
    print(f"   X against −L: projection ⟨X, −L⟩/⟨L, L⟩ = {ip(X, -L) / LL:+.3f}; "
          f"cells where X and L have opposite signs hold "
          f"{np.sum(np.abs(X[(X * L) < 0]) * J[(X * L) < 0]) / np.sum(np.abs(X) * J):.1%} of Σ|X|")
    # The rise per stage: the stage's own X against its own X + L.
    stages = sorted({h.split("_")[0] for h in cheader if h.startswith("s") and h.endswith("_Xm")})
    for s in stages:
        XA = Cc[:, ccol[f"{s}_A_Xm"]]
        XB = Cc[:, ccol[f"{s}_B_Xm"]]
        Ls = XB - XA
        print(f"-- stage {s[1:]} (weighted as in the step): Σ|X_s| {per_day(np.sum(np.abs(XA) * J)):.4e}, "
              f"Σ|X_s + L_s| {per_day(np.sum(np.abs(XB) * J)):.4e}, Σ|L_s| {per_day(np.sum(np.abs(Ls) * J)):.4e}, "
              f"stage rise {per_day(np.sum((np.abs(XA) - np.abs(XB)) * J)):+.4e}")
        if f"{s}_A_tend" not in ccol:
            print("   (no decomposition in this set)")
            continue
        errs = [S[:, col[f"{s}_{lab}_resolve_error"]].max() for lab in "AB"]
        lins = [S[:, col[f"{s}_{lab}_linearity_error"]].max() for lab in "AB"]
        unexp = [per_day(S[:, col[f"{s}_{lab}_unexplained_gross"]].sum()) for lab in "AB"]
        print(f"   checks: re-solve error {max(errs):.2e}, linearity error {max(lins):.2e} kg m-3; "
              f"unexplained gross A {unexp[0]:.2e}, B {unexp[1]:.2e} of W a day")
        print(f"   {'part':12s} {'Σ|part of X|':>13s} {'Σ|part of L|':>13s} {'⟨part,−L⟩/⟨L,L⟩':>16s} "
              f"{'Σ|X|−Σ|X−part|':>15s}")
        for part in PARTS:
            pA = Cc[:, ccol[f"{s}_A_{part}"]]
            pB = Cc[:, ccol[f"{s}_B_{part}"]]
            pL = pB - pA
            marginal = np.sum(np.abs(X) * J) - np.sum(np.abs(X - pA) * J)
            print(f"   {part:12s} {per_day(np.sum(np.abs(pA) * J)):13.4e} "
                  f"{per_day(np.sum(np.abs(pL) * J)):13.4e} {ip(pA, -L) / LL:+16.3f} "
                  f"{per_day(marginal):+15.4e}")
