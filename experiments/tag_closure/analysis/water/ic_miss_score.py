"""Option C's miss at site 23: the probe's score, as pre-registered
(design/NEGATIVE_PARENT_WATER.md, section 9).

    python3 ic_miss_score.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds the probe's
`ic_miss_probe_s23/output_0000/` (its steps CSV and the reference's NetCDF)
and `ic_s23_c/output_0000/`. It prints:
  - P0: every NetCDF field both runs write, at every common output time, bit
    for bit;
  - per rise of W42 inside the windows: P2 (the rise from the per-step sum
    against W42's 6-hourly value), P1 (the `on` trial against the reference),
    where the rise lies (N, P, X), each explicit probe's and each trial's
    share, each ledger's change in the cells with an excess, and the verdict
    by section 9.4's rules.
The thresholds are the section's. Nothing here is tuned after the run.
"""
import csv
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
PROBE = os.path.join(ROOT, "ic_miss_probe_s23", "output_0000")
RUN = os.path.join(ROOT, "ic_s23_c", "output_0000")
DAY = 86400.0
# W42's rises inside the windows, days, and whether a ledger carried them.
RISES = [
    (30.50, 30.75, "no ledger"),
    (30.75, 31.00, "the control: follower ledgers"),
    (52.50, 52.75, "no ledger"),
    (52.75, 53.00, "no ledger"),
    (53.00, 53.25, "no ledger"),
]
ATTRIBUTES, CONTRIBUTES, P1_MAX, P2_MAX = 0.5, 0.1, 0.1, 0.1
TRANSPORT_PROBES = ("forcing_subsidence", "subsidence")
LOCAL_PROBES = (
    "forcing_horizontaladvection",
    "forcing_verticalfluctuation",
    "forcing_nudging",
    "surface_flux",
    "large_scale_advection",
)


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def p0():
    compared, differ = 0, []
    for path in sorted(glob.glob(os.path.join(PROBE, "*.nc"))):
        name = os.path.basename(path)
        other = os.path.join(RUN, name)
        if not os.path.exists(other):
            continue
        var = re.sub(r"_(1d|6h)_(inst|average)\.nc$", "", name)
        with nc.Dataset(path) as a, nc.Dataset(other) as b:
            if var not in a.variables or var not in b.variables:
                continue
            ta, tb = np.asarray(a["time"][:]), np.asarray(b["time"][:])
            n = min(len(ta), len(tb))
            va = np.moveaxis(np.asarray(a[var][:]), a[var].dimensions.index("time"), 0)[:n]
            vb = np.moveaxis(np.asarray(b[var][:]), b[var].dimensions.index("time"), 0)[:n]
            compared += 1
            if not (np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(va), bits(vb))):
                differ.append(name)
    ok = compared > 0 and not differ
    print(f"P0, the reference is ic_s23_c: {compared} files compared at their common times, "
          f"differing: {differ or 'none'}: {'pass' if ok else 'FAIL'}")
    return ok


def w42_rises():
    """W42's 6-hourly excess fraction, from ic_s23_c's output, as
    ic_overclaim_where.py computes it."""
    def read(name):
        with nc.Dataset(os.path.join(RUN, f"{name}_6h_inst.nc")) as d:
            v = np.moveaxis(np.asarray(d[name][:]), d[name].dimensions.index("time"), 0)
            return np.asarray(d["time"][:]), v.reshape(v.shape[0], -1), np.asarray(d["z"][:])
    t, q, z = read("hus")
    _, rho, _ = read("rhoa")
    region = read("q_tag_pbl")[1] + read("q_tag_free")[1]
    with open(os.path.join(RUN, "ic_s23_c.yml")) as f:
        top = float(re.search(r'^z_max:\s*"?([0-9.eE+-]+)', f.read(), re.M).group(1))
    faces = [0.0]
    for c in z:
        faces.append(2 * c - faces[-1])
    assert abs(faces[-1] - top) <= 1e-6 * top
    w = rho * np.diff(faces)
    target = np.maximum(q, 0)
    frac = (w * np.maximum(region - target, 0)).sum(axis=1) / (w * target).sum(axis=1)
    return {round(tt / DAY, 4): f for tt, f in zip(t, frac)}


def main():
    ok0 = p0()
    with open(os.path.join(PROBE, "ic_miss_probe_s23_steps.csv")) as f:
        rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]
    cols = rows[0].keys()
    trials = sorted({c[: -len("_total")] for c in cols if c.endswith("_total") and not c.startswith(("ref", "probe"))})
    probes = sorted({c[len("probe_"): -len("_total")] for c in cols if c.startswith("probe_") and c.endswith("_total")})
    ledgers = [c for c in cols if c.startswith("ledger_")]
    frac42 = w42_rises()
    for a, b, kind in RISES:
        sel = [r for r in rows if a * DAY < r["t_seconds"] <= b * DAY + 1e-6]
        if not sel:
            print(f"\n== rise {a:.2f}-{b:.2f} ({kind}): no steps in the CSV")
            continue
        S = lambda c: sum(r[c] for r in sel)
        R = S("ref_total")
        water = sel[-1]["water"]
        w42 = frac42.get(round(b, 4), np.nan) - frac42.get(round(a, 4), np.nan)
        print(f"\n== rise {a:.2f}-{b:.2f} days ({kind}), {len(sel)} steps")
        rel = R / water
        p2 = abs(rel - w42) <= P2_MAX * abs(w42)
        print(f"  P2: rise {R:.4e} kg/m², {rel:.3e} of the water; W42 {w42:.3e}: {'pass' if p2 else 'outside 10%, reported beside'}")
        p1 = abs(S("on_total") - R) <= P1_MAX * abs(R)
        print(f"  P1: on {S('on_total'):.4e} against the reference {R:.4e}: {'pass' if p1 else 'trials not assessable'}; "
              f"largest step gaps q_tot {max(r['on_gap_q_tot'] for r in sel):.2e}, tags {max(r['on_gap_tags'] for r in sel):.2e}")
        print(f"  where: N {S('ref_N') / R:.2f}, P {S('ref_P') / R:.2f}, X {S('ref_X') / R:.2f} of the rise")
        print("  ledgers, per-step change in the cells with an excess, summed, over the rise: "
              + ", ".join(f"{c[len('ledger_'): -len('_in_excess')]} {S(c) / R:.3g}" for c in ledgers))
        verdicts = []
        for o in probes:
            share = S(f"probe_{o}_total") / R
            n_share = S(f"probe_{o}_N") / S(f"probe_{o}_total") if S(f"probe_{o}_total") else np.nan
            p_share = S(f"probe_{o}_P") / S(f"probe_{o}_total") if S(f"probe_{o}_total") else np.nan
            label = "attributes" if share >= ATTRIBUTES else "contributes" if share >= CONTRIBUTES else ""
            print(f"  probe {o}: share {share:+.3f}; of it in N {n_share:.2f}, in P {p_share:.2f} {label}")
            if share >= ATTRIBUTES and o.startswith(TRANSPORT_PROBES) and p_share >= 0.5:
                verdicts.append(f"candidate 1 ({o})")
            if share >= ATTRIBUTES and o.startswith(LOCAL_PROBES) and n_share >= 0.5:
                verdicts.append(f"candidate 5 ({o})")
        if p1:
            for tr in trials:
                if tr == "on":
                    continue
                c = S("on_total") - S(f"{tr}_total")
                share = c / R
                p_share = (S("on_P") - S(f"{tr}_P")) / c if c else np.nan
                label = "attributes" if share >= ATTRIBUTES else "contributes" if share >= CONTRIBUTES else ""
                print(f"  trial {tr}: share {share:+.3f}; of it in P {p_share:.2f} {label}")
                if share >= ATTRIBUTES:
                    if tr == "off_sgs_mass_flux" and p_share >= 0.5:
                        verdicts.append("candidate 1 (the SGS mass flux)")
                    if tr in ("off_sgs_mass_flux", "off_sgs_diffusive_flux"):
                        verdicts.append(f"candidate 2 ({tr})")
                    if tr == "tracer":
                        verdicts.append("candidate 3 (the follower)")
        if S("ref_X") / R >= 0.5:
            verdicts.append("candidate 4 is consistent (class X holds half the rise; a location, not a mechanism)")
        attributed = any(
            S(f"probe_{o}_total") / R >= ATTRIBUTES for o in probes
        ) or (p1 and any((S("on_total") - S(f"{tr}_total")) / R >= ATTRIBUTES for tr in trials if tr != "on"))
        print(f"  VERDICT: {'; '.join(verdicts) if verdicts else 'no candidate supported'}"
              + ("" if attributed else "; the rise is UNATTRIBUTED (no probe and no trial reaches 0.5)"))
    if not ok0:
        print("\nP0 fails: the probe measured another run, and nothing is attributed to W42's rises.")


if __name__ == "__main__":
    main()
