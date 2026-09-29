"""C's revision: the probe's windows, scored as pre-registered
(design/NEGATIVE_PARENT_WATER.md, section 11.7).

    python3 cr_windows_score.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds `cr_probe_s23/output_0000/`,
the probe of section 9.7 rerun on the revision's code, and W48's
`ic_miss_probe2_s23/output_0000/`. Every share divides by W48's rise `R48`,
the sum of W48's per-step `ref_total` over the rise, since the revision
should remove the rises and a share of a rise near zero has no meaning.

  - W0: the model's twelve field files match W48's bit for bit at every
    common output time, and all are there in both runs (9.7.3's P0a).
  - W1: the forcing's bracket applied alone gives no growth of the excess in
    the mechanism's cells (parent at or below zero before and after while the
    region tags gain): `probe_forcing_M5_up` and `probe_forcing_M5_down` are
    0 at every step of both windows.
  - W2: per rise, the forcing's bracket applied alone grows the excess by
    less than 0.1 of R48, section 9.4's level below which a share does not
    contribute.
  - W3, reported: per rise, the reference's rise `R` over the water beside
    W48's, its split in N, P and X, and each probe's share of R48. The rule
    "the rise goes if R <= 0.1 R48" is proposed and waits for the owner; it
    is printed, not scored.
  - W4, reported: per rise, the whole explicit tendency's growth over R48.
It exits 1 if W0, W1 or W2 fails or the data are missing.
"""
import csv
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
PROBE = os.path.join(ROOT, "cr_probe_s23", "output_0000")
W48 = os.path.join(ROOT, "ic_miss_probe2_s23", "output_0000")
DAY = 86400.0
RISES = [
    (30.50, 30.75, "no ledger"),
    (30.75, 31.00, "the control: follower ledgers"),
    (52.50, 52.75, "no ledger"),
    (52.75, 53.00, "no ledger, no candidate in W47"),
    (53.00, 53.25, "no ledger"),
]
WINDOWS = [(30.3, 31.0), (52.4, 53.3)]
# Section 9.4's level below which a share does not contribute, unchanged.
CONTRIBUTES = 0.1
# Proposed in section 11.7, waiting for the owner: printed, not scored.
PROPOSED_RISE_GOES = 0.1
MODEL_FIELDS = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")
MODEL_FILES = tuple(f"{v}_1d_inst.nc" for v in MODEL_FIELDS) + ("rhoa_6h_inst.nc", "hus_6h_inst.nc")
failed = []


def verdict(rule, ok):
    if not ok:
        failed.append(rule)
    return "pass" if ok else "FAIL"


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def same_file(path, other, var):
    with nc.Dataset(path) as a, nc.Dataset(other) as b:
        ta, tb = np.asarray(a["time"][:]), np.asarray(b["time"][:])
        n = min(len(ta), len(tb))
        va = np.moveaxis(np.asarray(a[var][:]), a[var].dimensions.index("time"), 0)[:n]
        vb = np.moveaxis(np.asarray(b[var][:]), b[var].dimensions.index("time"), 0)[:n]
        return n > 0 and np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(va), bits(vb))


def w0():
    missing = [f for f in MODEL_FILES
               if not (os.path.exists(os.path.join(PROBE, f)) and os.path.exists(os.path.join(W48, f)))]
    differ = [f for f in MODEL_FILES if f not in missing
              and not same_file(os.path.join(PROBE, f), os.path.join(W48, f), re.sub(r"_(1d|6h)_inst\.nc$", "", f))]
    print(f"W0, the model's fields are W48's: {len(MODEL_FILES) - len(missing)} of {len(MODEL_FILES)} files "
          f"compared, missing: {missing or 'none'}, differing: {differ or 'none'}: "
          f"{verdict('W0', not missing and not differ)}")
    tags = sorted(set(os.path.basename(p) for p in glob.glob(os.path.join(PROBE, "q_tag_*.nc")))
                  & set(os.path.basename(p) for p in glob.glob(os.path.join(W48, "q_tag_*.nc"))))
    tag_differ = [f for f in tags
                  if not same_file(os.path.join(PROBE, f), os.path.join(W48, f), re.sub(r"_(1d|6h)_inst\.nc$", "", f))]
    print(f"    reported: {len(tag_differ)} of {len(tags)} water tag files differ from W48's")


def read_rows(path):
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def in_interval(rows, a, b):
    return [r for r in rows if a * DAY < r["t_seconds"] <= b * DAY + 1e-6]


def w1(rows):
    for a, b in WINDOWS:
        sel = in_interval(rows, a, b)
        bad = [r for r in sel if r["probe_forcing_M5_up"] != 0 or r["probe_forcing_M5_down"] != 0]
        print(f"W1, window {a}-{b} days: {len(sel)} steps, the forcing's mechanism part not 0 at {len(bad)}: "
              f"{verdict(f'W1 {a}-{b}', bool(sel) and not bad)}")


def score_rise(a, b, kind, rows, rows48):
    sel, sel48 = in_interval(rows, a, b), in_interval(rows48, a, b)
    print(f"\n== rise {a:.2f}-{b:.2f} days ({kind}), {len(sel)} steps (W48: {len(sel48)})")
    if not sel or len(sel) != len(sel48):
        print(f"  the steps do not match W48's: {verdict(f'W2 {a}-{b}', False)}")
        return
    S = lambda c: sum(r[c] for r in sel)
    R48 = sum(r["ref_total"] for r in sel48)
    R = S("ref_total")
    water, water48 = sel[-1]["water"], sel48[-1]["water"]
    forcing = S("probe_forcing_total") / R48
    print(f"  W2: the forcing's bracket alone grows the excess by {forcing:+.3e} of W48's rise: "
          f"{verdict(f'W2 {a}-{b}', forcing < CONTRIBUTES)}")
    goes = R <= PROPOSED_RISE_GOES * R48
    print(f"  W3 (reported): rise {R / water:+.3e} of the water, W48 {R48 / water48:+.3e}; R/R48 {R / R48:+.3e}; "
          f"proposed rule R <= {PROPOSED_RISE_GOES} R48, waiting for the owner: {'met' if goes else 'not met'}")
    print(f"    of R48: in N {S('ref_N') / R48:+.3e}, in P {S('ref_P') / R48:+.3e}, in X {S('ref_X') / R48:+.3e}; "
          f"the mechanism's cells in the reference's step {(S('ref_M5_up') + S('ref_M5_down')) / R48:+.3e}")
    probes = sorted({c[len("probe_"): -len("_total")] for c in sel[0] if c.startswith("probe_") and c.endswith("_total")})
    print("    probes' growth of the excess over R48: "
          + ", ".join(f"{o} {S(f'probe_{o}_total') / R48:+.3g}" for o in probes if o != "explicit"))
    print(f"  W4 (reported): the whole explicit tendency alone {S('probe_explicit_total') / R48:+.3e} of R48")
    ledgers = [c for c in sel[0] if c.startswith("ledger_")]
    print("    ledgers, per-step change in the cells with an excess, over R48: "
          + ", ".join(f"{c[len('ledger_'): -len('_in_excess')]} {S(c) / R48:.3g}" for c in ledgers))


def main():
    steps = os.path.join(PROBE, "cr_probe_s23_steps.csv")
    steps48 = os.path.join(W48, "ic_miss_probe2_s23_steps.csv")
    if not (os.path.exists(steps) and os.path.exists(steps48)):
        print(f"missing: {steps if not os.path.exists(steps) else steps48}")
        sys.exit(1)
    w0()
    rows, rows48 = read_rows(steps), read_rows(steps48)
    w1(rows)
    for a, b, kind in RISES:
        score_rise(a, b, kind, rows, rows48)
    print("\nRESULT", "W0 to W2 pass" if not failed else f"failed: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
