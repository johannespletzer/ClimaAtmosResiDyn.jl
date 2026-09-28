"""Option C's miss at site 23: the extended probe's score, as pre-registered
(design/NEGATIVE_PARENT_WATER.md, section 9.7).

    python3 ic_miss_score2.py [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds the extended probe's
`ic_miss_probe2_s23/output_0000/` (its two CSVs and the reference's NetCDF),
`ic_s23_c/output_0000/` and the first probe's `ic_miss_probe_s23/output_0000/`.
It prints:
  - P0a: the model's own fields, every NetCDF both runs write, bit for bit
    against `ic_s23_c` at every common output time; P0b: the tags' fields,
    reported, not a gate;
  - per rise: P1 and P2 as section 9.3 has them, P2 also against the first
    probe; section 9.4's shares and verdict, read as `ic_miss_score.py` reads
    them; section 9.7's leave-one-out shares, candidate 5's mechanism cell by
    cell, the levels that hold the rise, and the reading for the fix's scope;
  - per window: P3, #118's latch against the per-step ratio.
The thresholds are the sections'. Nothing here is tuned after the run.
"""
import csv
import glob
import os
import re
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
PROBE = os.path.join(ROOT, "ic_miss_probe2_s23", "output_0000")
RUN = os.path.join(ROOT, "ic_s23_c", "output_0000")
FIRST = os.path.join(ROOT, "ic_miss_probe_s23", "output_0000", "ic_miss_probe_s23_steps.csv")
DAY = 86400.0
RISES = [
    (30.50, 30.75, "no ledger"),
    (30.75, 31.00, "the control: follower ledgers"),
    (52.50, 52.75, "no ledger"),
    (52.75, 53.00, "no ledger, no candidate in W47"),
    (53.00, 53.25, "no ledger"),
]
WINDOWS = [(30.3, 31.0), (52.4, 53.3)]
# Section 9.4's thresholds, unchanged, and section 9.7's.
ATTRIBUTES, CONTRIBUTES, P1_MAX, P2_MAX = 0.5, 0.1, 0.1, 0.1
CARRIES, MECHANISM, LEVEL_HALF = 0.5, 0.5, 0.5
NEGATIVE_WATER_LEVEL = 1e-4
TRANSPORT_PROBES = ("forcing_subsidence", "subsidence")
LOCAL_PROBES = (
    "forcing_horizontaladvection",
    "forcing_verticalfluctuation",
    "forcing_nudging",
    "surface_flux",
    "large_scale_advection",
)
# The model's own fields among the reference's outputs; every other file is a
# tag's or a ledger's.
MODEL_FIELDS = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def compare(path, other, var):
    with nc.Dataset(path) as a, nc.Dataset(other) as b:
        if var not in a.variables or var not in b.variables:
            return None
        ta, tb = np.asarray(a["time"][:]), np.asarray(b["time"][:])
        n = min(len(ta), len(tb))
        va = np.moveaxis(np.asarray(a[var][:]), a[var].dimensions.index("time"), 0)[:n]
        vb = np.moveaxis(np.asarray(b[var][:]), b[var].dimensions.index("time"), 0)[:n]
        same = np.array_equal(bits(ta[:n]), bits(tb[:n])) and np.array_equal(bits(va), bits(vb))
        scale = max(np.max(np.abs(vb)), np.finfo(float).tiny) if vb.size else 1.0
        return same, (float(np.max(np.abs(va - vb)) / scale) if va.size else 0.0)


def p0():
    model, model_differ, tags, tags_differ = 0, [], 0, []
    for path in sorted(glob.glob(os.path.join(PROBE, "*.nc"))):
        name = os.path.basename(path)
        other = os.path.join(RUN, name)
        if not os.path.exists(other):
            continue
        var = re.sub(r"_(1d|6h)_(inst|average)\.nc$", "", name)
        result = compare(path, other, var)
        if result is None:
            continue
        same, rel = result
        if var in MODEL_FIELDS:
            model += 1
            if not same:
                model_differ.append(f"{name} ({rel:.1e})")
        else:
            tags += 1
            if not same:
                tags_differ.append(f"{name} ({rel:.1e})")
    ok = model > 0 and not model_differ
    print(f"P0a, the model's fields are ic_s23_c's: {model} files compared, differing: "
          f"{model_differ or 'none'}: {'pass' if ok else 'FAIL'}")
    print(f"P0b, the tags' fields against ic_s23_c (reported): {tags} files compared, "
          f"differing: {len(tags_differ)}" + (f": {', '.join(tags_differ)}" if tags_differ else ""))
    return ok


def w42_rises():
    """W42's 6-hourly excess fraction, from ic_s23_c's output, as
    ic_miss_score.py computes it."""
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


def read_rows(path):
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def first_probe_rises():
    if not os.path.exists(FIRST):
        return {}
    rows = read_rows(FIRST)
    out = {}
    for a, b, _ in RISES:
        sel = [r for r in rows if a * DAY < r["t_seconds"] <= b * DAY + 1e-6]
        if sel:
            out[(a, b)] = sum(r["ref_total"] for r in sel) / sel[-1]["water"]
    return out


def read_levels(path):
    """{interval start in days: {quantity: (z, values per level)}}."""
    by_interval = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            start = round(float(r["interval_start_days"]), 4)
            acc = by_interval.setdefault(start, {"z": [], "values": {}})
            acc["z"].append(float(r["z_m"]))
            for k, v in r.items():
                if k in ("interval_start_days", "level", "z_m"):
                    continue
                acc["values"].setdefault(k, []).append(float(v))
    return {s: (np.array(a["z"]), {k: np.array(v) for k, v in a["values"].items()}) for s, a in by_interval.items()}


def share_label(x, high, low):
    return "attributes" if x >= high else "contributes" if x >= low else ""


def score_rise(a, b, kind, rows, levels, frac42, first):
    sel = [r for r in rows if a * DAY < r["t_seconds"] <= b * DAY + 1e-6]
    if not sel:
        print(f"\n== rise {a:.2f}-{b:.2f} ({kind}): no steps in the CSV")
        return
    cols = rows[0].keys()
    trials = sorted({c[: -len("_total")] for c in cols if c.endswith("_total") and not c.startswith(("ref", "probe"))})
    every = sorted({c[len("probe_"): -len("_total")] for c in cols if c.startswith("probe_") and c.endswith("_total")})
    # Section 9.4 reads the first probe's set; the leave-one-out probes are 9.7's.
    probes = [o for o in every if not o.startswith("forcing_without_")]
    without = [o for o in every if o.startswith("forcing_without_")]
    ledgers = [c for c in cols if c.startswith("ledger_")]
    S = lambda c: sum(r[c] for r in sel)
    R = S("ref_total")
    water = sel[-1]["water"]
    w42 = frac42.get(round(b, 4), np.nan) - frac42.get(round(a, 4), np.nan)
    print(f"\n== rise {a:.2f}-{b:.2f} days ({kind}), {len(sel)} steps")
    rel = R / water
    p2 = abs(rel - w42) <= P2_MAX * abs(w42)
    first_rel = first.get((a, b), np.nan)
    print(f"  P2: rise {R:.4e} kg/m², {rel:.3e} of the water; W42 {w42:.3e}: "
          f"{'pass' if p2 else 'outside 10%, reported beside'}; the first probe {first_rel:.3e}")
    p1 = abs(S("on_total") - R) <= P1_MAX * abs(R)
    print(f"  P1: on {S('on_total'):.4e} against the reference {R:.4e}: {'pass' if p1 else 'trials not assessable'}; "
          f"largest step gaps q_tot {max(r['on_gap_q_tot'] for r in sel):.2e}, tags {max(r['on_gap_tags'] for r in sel):.2e}")
    print(f"  where: N {S('ref_N') / R:.2f}, P {S('ref_P') / R:.2f}, X {S('ref_X') / R:.2f} of the rise")
    print("  ledgers, per-step change in the cells with an excess, summed, over the rise: "
          + ", ".join(f"{c[len('ledger_'): -len('_in_excess')]} {S(c) / R:.3g}" for c in ledgers))
    # Section 9.4, as ic_miss_score.py reads it.
    verdicts = []
    for o in probes:
        share = S(f"probe_{o}_total") / R
        tot = S(f"probe_{o}_total")
        n_share = S(f"probe_{o}_N") / tot if tot else np.nan
        p_share = S(f"probe_{o}_P") / tot if tot else np.nan
        print(f"  probe {o}: share {share:+.3f}; of it in N {n_share:.2f}, in P {p_share:.2f} "
              f"{share_label(share, ATTRIBUTES, CONTRIBUTES)}")
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
            print(f"  trial {tr}: share {share:+.3f}; of it in P {p_share:.2f} {share_label(share, ATTRIBUTES, CONTRIBUTES)}")
            if share >= ATTRIBUTES:
                if tr == "off_sgs_mass_flux" and p_share >= 0.5:
                    verdicts.append("candidate 1 (the SGS mass flux)")
                if tr in ("off_sgs_mass_flux", "off_sgs_diffusive_flux"):
                    verdicts.append(f"candidate 2 ({tr})")
                if tr == "tracer":
                    verdicts.append("candidate 3 (the follower)")
    if S("ref_X") / R >= 0.5:
        verdicts.append("candidate 4 is consistent (class X holds half the rise; a location, not a mechanism)")
    attributed = any(S(f"probe_{o}_total") / R >= ATTRIBUTES for o in probes) or (
        p1 and any((S("on_total") - S(f"{tr}_total")) / R >= ATTRIBUTES for tr in trials if tr != "on"))
    print(f"  VERDICT 9.4: {'; '.join(verdicts) if verdicts else 'no candidate supported'}"
          + ("" if attributed else "; the rise is UNATTRIBUTED (no probe and no trial reaches 0.5)"))
    # Section 9.7.4: leave-one-out.
    F = S("probe_forcing_total")
    carries = []
    for o in without:
        term = o[len("forcing_without_"):]
        ell = (F - S(f"probe_{o}_total")) / R
        label = "carries" if ell >= CARRIES else "contributes" if ell >= CONTRIBUTES else ""
        print(f"  leave-one-out {term}: {ell:+.3f} {label}")
        if ell >= CARRIES:
            carries.append(term)
    # Section 9.7.4: candidate 5's mechanism, cell by cell.
    ref_m5 = (S("ref_M5_up") + S("ref_M5_down")) / R
    f_m5 = (S("probe_forcing_M5_up") + S("probe_forcing_M5_down")) / F if F else np.nan
    f_up = S("probe_forcing_M5_up") / F if F else np.nan
    shown = ref_m5 >= MECHANISM and f_m5 >= MECHANISM
    print(f"  mechanism, cell by cell: reference {ref_m5:.2f} of the rise (parent rising {S('ref_M5_up') / R:.2f}); "
          f"forcing {f_m5:.2f} of its own growth (parent rising {f_up:.2f}): "
          f"{'shown' if shown else 'not shown'}")
    # Section 9.7.4: the levels that hold the rise.
    starts = [s for s in levels if a - 1e-4 <= s < b - 1e-4]
    if starts:
        z = levels[starts[0]][0]
        tot = {q: sum(levels[s][1][q] for s in starts) for q in levels[starts[0]][1]}
        ref = tot["ref"]
        order = np.argsort(-ref)
        held, k = 0.0, 0
        while k < len(order) and held < LEVEL_HALF * ref.sum():
            held += ref[order[k]]
            k += 1
        top = order[:k]
        pos = np.maximum(ref, 0)
        overlap = np.minimum(pos, np.maximum(tot["forcing"], 0)).sum() / pos.sum() if pos.sum() else np.nan
        print(f"  levels holding half the rise: {k}, at z = {', '.join(f'{z[i]:.0f}' for i in sorted(top))} m; "
              f"the forcing's growth overlaps the reference's by {overlap:.2f}")
        for q in sorted(tot):
            if q.startswith("forcing_") and not q.startswith("forcing_without_") and q != "forcing_M5":
                print(f"    {q}: {tot[q][top].sum() / R:+.3f} of the rise in those levels")
    else:
        print("  levels: none in the levels CSV")
    # Section 9.7.4: the reading for the fix's scope.
    if any(t.startswith("subsidence") for t in carries):
        scope = "subsidence carries it (" + ", ".join(carries) + "): a fix must cover subsidence"
    elif carries:
        scope = "local terms carry it (" + ", ".join(carries) + "): a fix of the local terms covers it"
    elif F / R >= ATTRIBUTES:
        scope = "no term carries it alone, the forcing as a whole does: a fix at the forcing's bracket"
    else:
        scope = "the forcing does not attribute it"
    print(f"  READING 9.7: {scope}; mechanism {'shown' if shown else 'not shown'} cell by cell")


def p3(rows):
    for a, b in WINDOWS:
        sel = [r for r in rows if a * DAY < r["t_seconds"] <= b * DAY + 1e-6]
        if not sel:
            print(f"P3, window {a}-{b}: no steps")
            continue
        over = [r for r in sel if r["negative_water_relative"] > NEGATIVE_WATER_LEVEL]
        wrong = [r for r in over if r["latch"] != 1.0]
        print(f"P3, window {a}-{b} days: largest per-step ratio {max(r['negative_water_relative'] for r in sel):.3e}, "
              f"{len(over)} of {len(sel)} steps above {NEGATIVE_WATER_LEVEL:g}, latch 0 at {len(wrong)} of them: "
              f"{'pass' if not wrong else 'FAIL'}")


def main():
    ok0 = p0()
    rows = read_rows(os.path.join(PROBE, "ic_miss_probe2_s23_steps.csv"))
    levels = read_levels(os.path.join(PROBE, "ic_miss_probe2_s23_levels.csv"))
    p3(rows)
    frac42 = w42_rises()
    first = first_probe_rises()
    for a, b, kind in RISES:
        score_rise(a, b, kind, rows, levels, frac42, first)
    if not ok0:
        print("\nP0a fails: the probe measured another parent, and nothing is attributed to W42's rises.")


if __name__ == "__main__":
    main()
