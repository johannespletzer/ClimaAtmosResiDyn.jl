"""C's revision: how the stages split a step that crosses zero
(design/NEGATIVE_PARENT_WATER.md, section 11.2).

    python3 cr_crossing_check.py

The revised bracket gives the partition a process's gain where the parent is
at or above zero at the state the tendency is evaluated at, and nothing where
it is below zero. The stepper evaluates the explicit tendency at each stage
and adds the stages with the tableau's weights `b`. So in a step that crosses
zero, the partition's gain is `h Δ Σ_i b_i [x_i >= 0]`, where the target's is
`max(x_n + h Δ, 0) - max(x_n, 0)`.

This takes one process at a constant rate `Δ > 0` and nothing else, so the
stage states are `x_i = x_n + c_i h Δ`. It puts the step's start at
`x_n = -a h Δ` for `a` from -0.5 to 2, and prints the partition's gain less
the target's, in units of `h Δ`: the largest overclaim, the largest shortfall
and the integral over `a`. It does the same for the alternative that section
11.2 does not choose: at each stage, the target's gain over a whole step from
that stage's state, `max(Δ + x_i / h, 0)`.

An illustration, not a bound for the model: there, other processes and the
implicit solve move the parent within the step too. The tableaux are those of
ClimaTimeSteppers 1.0.1 (`src/solvers/imex_tableaus.jl`).
"""
import numpy as np


def ars222():
    g = 1 - np.sqrt(2) / 2
    d = 1 - 1 / (2 * g)
    a = np.array([[0, 0, 0], [g, 0, 0], [d, 1 - d, 0]])
    return a, a[-1]


def ars343():
    g = 0.4358665215084590
    a42 = 0.5529291480359398
    a43 = a42
    b1 = -3 / 2 * g**2 + 4 * g - 1 / 4
    b2 = 3 / 2 * g**2 - 5 * g + 5 / 4
    a31 = ((1 - 9 / 2 * g + 3 / 2 * g**2) * a42 + (11 / 4 - 21 / 2 * g + 15 / 4 * g**2) * a43
           - 7 / 2 + 13 * g - 9 / 2 * g**2)
    a32 = ((-1 + 9 / 2 * g - 3 / 2 * g**2) * a42 + (-11 / 4 + 21 / 2 * g - 15 / 4 * g**2) * a43
           + 4 - 25 / 2 * g + 9 / 2 * g**2)
    a41 = 1 - a42 - a43
    a = np.array([[0, 0, 0, 0], [g, 0, 0, 0], [a31, a32, 0, 0], [a41, a42, a43, 0]])
    return a, np.array([0, b1, b2, g])


def miss(a_start, c, b, rule):
    x = -a_start[:, None] + c[None, :]
    rate = np.where(x >= 0, 1.0, 0.0) if rule == "stage sign" else np.where(x >= 0, 1.0, np.maximum(1 + x, 0))
    gain = (b[None, :] * rate).sum(axis=1)
    target = np.maximum(1 - a_start, 0) - np.maximum(-a_start, 0)
    return gain - target


def main():
    a_start = np.linspace(-0.5, 2.0, 2_500_001)
    da = a_start[1] - a_start[0]
    for name, (a, b) in (("ARS222", ars222()), ("ARS343", ars343())):
        c = a.sum(axis=1)
        print(f"{name}: c = {np.round(c, 4)}, b = {np.round(b, 4)}, "
              f"sum b c = {b @ c:.12f}, sum |b| = {np.abs(b).sum():.4f}")
        for rule in ("stage sign", "whole step from the stage"):
            e = miss(a_start, c, b, rule)
            print(f"    {rule:26s} largest overclaim {e.max():.4f}, largest shortfall {-e.min():.4f}, "
                  f"integral over the crossing point {e.sum() * da:+.2e}")


if __name__ == "__main__":
    main()
