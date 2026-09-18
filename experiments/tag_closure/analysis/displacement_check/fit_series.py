"""Fit simple growth models to the gross closure residual of every tag run.

Read-only on the repo. Writes a table to stdout.
Models are fitted on t >= 1 h (the spin-up hour excluded), in hours, as
G(t) = a + f(t - 1) so the value at 1 h is a free intercept.
"""
import csv, glob, math, os, sys
import numpy as np

OUT = "/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn.jl/experiments/tag_closure/output"


def read(path):
    with open(path) as fh:
        rows = [r for r in csv.reader(fh) if r and not r[0].startswith("#")]
    head = rows[0]
    data = {k: [] for k in head}
    for r in rows[1:]:
        for k, v in zip(head, r):
            try:
                data[k].append(float(v))
            except ValueError:
                data[k].append(float("nan"))
    return {k: np.array(v) for k, v in data.items()}


def lsq(X, y):
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    r = y - X @ beta
    return beta, float(r @ r)


def aic(rss, n, k):
    return n * math.log(max(rss, 1e-300) / n) + 2 * k


def fits(t, y):
    """t in hours since 1 h, y gross residual."""
    n = len(t)
    one = np.ones_like(t)
    out = {}
    b, rss = lsq(one[:, None], y)
    out["const"] = (rss, 1, b)
    b, rss = lsq(np.c_[one, t], y)
    out["linear"] = (rss, 2, b)
    b, rss = lsq(np.c_[one, np.sqrt(t)], y)
    out["sqrt"] = (rss, 2, b)
    best = None
    for tau in np.geomspace(0.25, 500, 400):
        X = np.c_[one, 1 - np.exp(-t / tau)]
        bb, r = lsq(X, y)
        if best is None or r < best[0]:
            best = (r, tau, bb)
    out["satexp"] = (best[0], 3, (*best[2], best[1]))
    return out, n


def main():
    runs = sorted(
        d for d in os.listdir(OUT)
        if os.path.exists(os.path.join(OUT, d, "energy_source_tag_closure.csv"))
    )
    print(
        f"{'run':28s} {'G1h':>9s} {'G6h':>9s} {'G12h':>9s} {'G24h':>9s} "
        f"{'gr24':>8s} {'s1-12':>8s} {'s12-24':>8s} {'best':>7s} "
        f"{'dAIC':>28s} {'tau_h':>6s} {'cv_last12':>9s} {'trend_p':>7s}"
    )
    for run in runs:
        c = read(os.path.join(OUT, run, "energy_source_tag_closure.csv"))
        t = c["time"] / 3600.0
        G = c["gross_residual"]
        gr = c["gross_relative"]
        sel = t >= 1.0 - 1e-9
        if sel.sum() < 5:
            continue
        tt = t[sel] - 1.0
        yy = G[sel]
        fs, n = fits(tt, yy)
        a = {k: aic(v[0], n, v[1]) for k, v in fs.items()}
        best = min(a, key=a.get)
        daic = " ".join(f"{k[:3]}{a[k]-a[best]:+.0f}" for k in ["const", "linear", "sqrt", "satexp"])
        tau = fs["satexp"][2][2]

        def at(h):
            i = np.argmin(abs(t - h))
            return G[i] if abs(t[i] - h) < 1e-6 else float("nan")

        # slopes in J/m^2 (or J) per hour over 1-12 h and 12-24 h
        def slope(h0, h1):
            m = (t >= h0 - 1e-9) & (t <= h1 + 1e-9)
            if m.sum() < 3:
                return float("nan")
            return np.polyfit(t[m], G[m], 1)[0]

        s1 = slope(1, 12)
        s2 = slope(12, 24)
        last = G[(t >= 12 - 1e-9)]
        cv = last.std() / last.mean() if len(last) > 2 else float("nan")
        # Kendall tau on the last 12 h as trend test
        if len(last) > 3:
            conc = 0
            m = len(last)
            for i in range(m):
                for j in range(i + 1, m):
                    conc += np.sign(last[j] - last[i])
            var = m * (m - 1) * (2 * m + 5) / 18
            z = (conc - np.sign(conc)) / math.sqrt(var)
            p = math.erfc(abs(z) / math.sqrt(2))
        else:
            p = float("nan")
        print(
            f"{run:28s} {at(1):9.3g} {at(6):9.3g} {at(12):9.3g} {at(24):9.3g} "
            f"{gr[-1]:8.2e} {s1:8.2e} {s2:8.2e} {best:>7s} {daic:>28s} {tau:6.1f} {cv:9.3f} {p:7.3f}"
        )


if __name__ == "__main__":
    main()
