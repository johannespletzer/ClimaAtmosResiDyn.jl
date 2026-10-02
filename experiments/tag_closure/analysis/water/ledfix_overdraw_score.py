"""W63: the scores of design/NEGATIVE_PARENT_WATER.md section 11.13.

    python3 ledfix_overdraw_score.py [OUTPUT_ROOT] [check]

Reads the arms `lf_od_rev_s23` and `lf_od_switch_s23` under
OUTPUT_ROOT/<run>/output_0000/: their step traces (`<run>_trace.csv`) and
stage traces (`<run>_stages.csv`), written by `ledfix_overdraw.jl`. Prints:

  - C1, C2: each arm's NetCDF files and audit rows against W49's `cr_s23`
    (arm rev) and W53's `lf_switch_s23` (arm switch), bit for bit;
  - V0: in every traced cell and stage, the follower's four parts add up to
    its ledger increment;
  - V1: the stages, weighted as ARS222 weights them, add up to the step's
    change of the follower's ledger;
  - V2: every traced step has two stages;
  - S: the share of the extra repair of `free` that the outflow beyond the
    tag's content accounts for, rev less switch, and the reported numbers.

With `check`, it reads `lf_od_rev_check` and prints V0 to V2 only.

A line `RESULT <name> <value>` per score, so that the numbers can be parsed.
"""
import csv
import math
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
CHECK = len(sys.argv) > 2 and sys.argv[2] == "check"
REV, SWITCH = "lf_od_rev_s23", "lf_od_switch_s23"
CHECK_RUN = "lf_od_rev_check"
REFERENCE = {REV: "cr_s23", SWITCH: "lf_switch_s23"}
TAGS = ("free", "pbl")
DAY = 86400.0
# ARS222: the step adds dt * b_imp[i] * T_imp[i], and T_imp[i] holds the
# follower's tendency c_i. The trace records x_i = dtγ * c_i, with
# dtγ = dt * a_imp[i, i]. So the step's part is x_i * b_imp[i] / a_imp[i, i]:
# (1 − γ) / γ for the second tableau stage (the first one recorded) and 1 for
# the third. The first tableau stage has no solve and no follower.
GAMMA = 1 - math.sqrt(2) / 2
WEIGHTS = {1: (1 - GAMMA) / GAMMA, 2: 1.0}
WINDOW_STARTS = (11.25, 15.75, 55.75)
W53_LEVELS = (8, 9, 10, 11, 12, 13, 14)


def out(run):
    return os.path.join(ROOT, run, "output_0000")


def result(name, value):
    print(f"RESULT {name} {value}")


# C1, C2.
def read_nc(run, fname):
    with nc.Dataset(os.path.join(out(run), fname)) as d:
        var = fname.rsplit("_", 2)[0]
        return np.asarray(d["time"][:], dtype=np.float64), np.asarray(d[var][:])


def compare_run(run, ref):
    files = sorted(f for f in os.listdir(out(run)) if f.endswith("_inst.nc"))
    equal, differ, missing = 0, [], []
    counts = set()
    for f in files:
        if not os.path.exists(os.path.join(out(ref), f)):
            missing.append(f)
            continue
        ta, va = read_nc(run, f)
        tb, vb = read_nc(ref, f)
        common = np.intersect1d(ta, tb)
        xa = np.take(va, np.searchsorted(ta, common), axis=list(va.shape).index(len(ta)))
        xb = np.take(vb, np.searchsorted(tb, common), axis=list(vb.shape).index(len(tb)))
        if len(common) > 0 and xa.shape == xb.shape and np.array_equal(xa, xb, equal_nan=True):
            equal += 1
            counts.add(len(common))
        else:
            differ.append(f)
    with open(os.path.join(out(run), "water_tag_audit.csv")) as f:
        ra = list(csv.DictReader(f))
    with open(os.path.join(out(ref), "water_tag_audit.csv")) as f:
        rb = list(csv.DictReader(f))
    n = min(len(ra), len(rb))
    audit_equal = n > 0 and all(ra[i] == rb[i] for i in range(n))
    print(f"  {run} against {ref}: {equal} of {len(files)} NetCDF files bit for bit "
          f"(outputs per file {sorted(counts)}), {len(differ)} differ, {len(missing)} missing; "
          f"audit rows equal in all {n} common rows: {audit_equal}")
    for f in differ[:8]:
        print(f"    differs: {f}")
    return not differ and not missing and audit_equal and equal > 0


# The traces.
def load(path):
    with open(path) as f:
        header = f.readline().strip().split(",")
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=2)
    return {h: data[:, i] for i, h in enumerate(header)}


def cell_steps(run):
    """One record per traced step and level (level >= 1): the step trace's
    values before and after the step, joined with the step's two stages."""
    tr = load(os.path.join(out(run), f"{run}_trace.csv"))
    st = load(os.path.join(out(run), f"{run}_stages.csv"))
    lev_mask = tr["level"] >= 1
    step = tr["step"][lev_mask].astype(np.int64)
    level = tr["level"][lev_mask].astype(np.int64)
    end = tr["step_end"][lev_mask]
    key = step * 1000 + level
    order = np.argsort(key, kind="stable")
    index = {k: i for i, k in zip(order, key[order])}
    fields = {h: v[lev_mask] for h, v in tr.items()}

    # The step's rows (step_end == 1); the state before is the row of step - 1.
    ends = np.flatnonzero(end == 1)
    prev = np.array([index.get((step[i] - 1) * 1000 + level[i], -1) for i in ends])
    if (prev < 0).any():
        raise SystemExit(f"{run}: {int((prev < 0).sum())} steps without the state before them")
    rec = {"step": step[ends], "level": level[ends], "t": fields["t_seconds"][ends],
           "z": fields["z_m"][ends]}
    for tag in TAGS:
        q = fields[f"ρq_tag_{tag}"]
        rec[f"q0_{tag}"] = q[prev]
        rec[f"dq_{tag}"] = q[ends] - q[prev]
        rec[f"r_{tag}"] = fields[f"q_tag_led_fix_{tag}"][ends] - fields[f"q_tag_led_fix_{tag}"][prev]
        rec[f"a_{tag}"] = fields[f"q_tag_led_inc_{tag}"][ends] - fields[f"q_tag_led_inc_{tag}"][prev]
        rec[f"b_{tag}"] = rec[f"dq_{tag}"] - rec[f"r_{tag}"] - rec[f"a_{tag}"]
    rec["pos0"] = np.maximum(rec["q0_free"], 0) + np.maximum(rec["q0_pbl"], 0)

    # The stages, weighted into the step.
    skey = st["step"].astype(np.int64) * 1000 + st["level"].astype(np.int64)
    stage = st["stage"].astype(np.int64)
    ekey = rec["step"] * 1000 + rec["level"]
    pos_of = {k: i for i, k in enumerate(ekey)}
    rows = np.array([pos_of.get(k, -1) for k in skey])
    n_stages = np.bincount(rows[rows >= 0], minlength=len(ekey))
    w = np.array([WEIGHTS.get(s, np.nan) for s in stage])
    ok = rows >= 0
    rec["n_stages"] = n_stages
    rec["unmatched_stage_rows"] = int((~ok).sum())
    rec["bad_stage_index"] = int(np.isnan(w).sum())

    def weighted(x):
        y = np.zeros(len(ekey))
        np.add.at(y, rows[ok], (w * x)[ok])
        return y

    rec["OUT"] = weighted(st["outtot"])
    v0 = {}
    for tag in TAGS:
        out_s, in_s = st[f"out_{tag}"], st[f"in_{tag}"]
        give_s, cross_s, led_s = st[f"give_{tag}"], st[f"cross_{tag}"], st[f"led_{tag}"]
        v0[tag] = (np.max(np.abs(-out_s + in_s + give_s + cross_s - led_s)) if len(led_s) else 0.0,
                   np.max(np.abs(led_s)) if len(led_s) else 0.0)
        rec[f"O_{tag}"] = weighted(out_s)
        rec[f"I_{tag}"] = weighted(in_s)
        rec[f"G_{tag}"] = weighted(give_s)
        rec[f"X_{tag}"] = weighted(cross_s)
        rec[f"A_{tag}"] = weighted(led_s)
        # The stage-level variant (reported): each stage's outflow beyond the
        # tag's content in that stage's value, weighted into the step.
        rec[f"Es_{tag}"] = weighted(np.maximum(out_s - np.maximum(st[f"C_{tag}"], 0), 0))
        # The scored quantity: the step's outflow beyond the tag's content at
        # the step's start.
        rec[f"E_{tag}"] = np.maximum(rec[f"O_{tag}"] - np.maximum(rec[f"q0_{tag}"], 0), 0)
    rec["v0"] = v0
    # Window of each step, by its start time.
    t0 = rec["t"] / DAY
    rec["window"] = np.array([max([k for k, a in enumerate(WINDOW_STARTS) if a - 1e-6 <= tt] + [-1])
                              for tt in t0]) if not CHECK else np.zeros(len(t0), dtype=int)
    return rec


def validity(run, rec):
    good = True
    for tag in TAGS:
        diff, scale = rec["v0"][tag]
        ok = diff <= 1e-9 * max(scale, 1e-300)
        print(f"V0 {run} {tag}: largest |out − in − give − cross + led| {diff:.3e} against largest |led| {scale:.3e}: "
              f"{'pass' if ok else 'fail'}")
        good &= ok
    for tag in TAGS:
        for k in sorted(set(rec["window"])):
            m = rec["window"] == k
            dev = np.abs(rec[f"A_{tag}"][m] - rec[f"a_{tag}"][m]).sum()
            tot = np.abs(rec[f"a_{tag}"][m]).sum()
            ok = dev <= 1e-6 * tot if tot > 0 else dev == 0
            print(f"V1 {run} {tag} window {k}: Σ|stages − step| {dev:.3e} against Σ|a| {tot:.3e}: "
                  f"{'pass' if ok else 'fail'}")
            good &= ok
    n = rec["n_stages"]
    ok = (n == 2).all() and rec["unmatched_stage_rows"] == 0 and rec["bad_stage_index"] == 0
    print(f"V2 {run}: {len(n)} cell-steps, stages per cell-step {sorted(set(n.tolist()))}, "
          f"unmatched stage rows {rec['unmatched_stage_rows']}, bad stage index {rec['bad_stage_index']}: "
          f"{'pass' if ok else 'fail'}")
    good &= ok
    return good


def explained(rec, tag, mask):
    r = np.maximum(rec[f"r_{tag}"][mask], 0)
    E = rec[f"E_{tag}"][mask]
    return np.minimum(E, r).sum(), r.sum()


if CHECK:
    rec = cell_steps(CHECK_RUN)
    good = validity(CHECK_RUN, rec)
    for tag in TAGS:
        print(f"  {CHECK_RUN} {tag}: Σ outflow {rec[f'O_{tag}'].sum():.4e}, Σ inflow {rec[f'I_{tag}'].sum():.4e}, "
              f"Σ give {rec[f'G_{tag}'].sum():.4e}, Σ cross {rec[f'X_{tag}'].sum():.4e}, Σ|a| {np.abs(rec[f'a_{tag}']).sum():.4e}, "
              f"Σ r+ {np.maximum(rec[f'r_{tag}'], 0).sum():.4e}")
    result("check", "pass" if good else "fail")
    sys.exit(0)

# C1, C2.
print("C1, C2: each arm against its reference, bit for bit at every output both have")
c = {run: compare_run(run, REFERENCE[run]) for run in (REV, SWITCH)}
result("C1", "pass" if c[REV] else "fail")
result("C2", "pass" if c[SWITCH] else "fail")

recs = {run: cell_steps(run) for run in (REV, SWITCH)}
valid = all([validity(run, recs[run]) for run in (REV, SWITCH)])
result("V", "pass" if valid else "fail")

# Both arms have the same steps: join them by step and level.
kr = recs[REV]["step"] * 1000 + recs[REV]["level"]
ks = recs[SWITCH]["step"] * 1000 + recs[SWITCH]["level"]
same_cells = np.array_equal(kr, ks)
print(f"Same cell-steps in both arms: {same_cells} ({len(kr)} and {len(ks)})")


def score(levels, windows, tag="free", label=""):
    xs, rs = {}, {}
    for run in (REV, SWITCH):
        rec = recs[run]
        m = np.isin(rec["level"], levels) & np.isin(rec["window"], windows)
        xs[run], rs[run] = explained(rec, tag, m)
    extra = rs[REV] - rs[SWITCH]
    S = (xs[REV] - xs[SWITCH]) / extra if extra > 0 else float("nan")
    print(f"{label}{tag}: R rev {rs[REV]:.4e}, switch {rs[SWITCH]:.4e}, extra {extra:.4e}; "
          f"explained rev {xs[REV]:.4e} ({xs[REV] / rs[REV] if rs[REV] else float('nan'):.3f} of R), "
          f"switch {xs[SWITCH]:.4e} ({xs[SWITCH] / rs[SWITCH] if rs[SWITCH] else float('nan'):.3f} of R); S {S:.3f}")
    return S, extra


ALL_LEVELS = sorted(set(recs[REV]["level"].tolist()))
print(f"Scored levels {ALL_LEVELS[0]} to {ALL_LEVELS[-1]}, windows {WINDOW_STARTS}")
S, extra = score(ALL_LEVELS, [0, 1, 2], label="S, all windows, ")
result("S_free", f"{S:.3f}")
result("extra_R_free", f"{extra:.4e}")
Sw = []
for k in range(3):
    s_k, e_k = score(ALL_LEVELS, [k], label=f"S, window {k} (day {WINDOW_STARTS[k]}), ")
    Sw.append(s_k)
    result(f"S_free_window{k}", f"{s_k:.3f}")
score(list(W53_LEVELS), [0, 1, 2], label="Reported, W53's levels 8 to 14, ")
s_pbl, _ = score(ALL_LEVELS, [0, 1, 2], tag="pbl", label="Reported, ")

if not (extra > 0):
    reading = "void (no extra repair of free to explain)"
elif S >= 0.8:
    reading = "the mechanism is confirmed at site 23 (S >= 0.8)"
elif S < 0.5:
    reading = "not the mechanism (S < 0.5)"
else:
    reading = "partly (0.5 <= S < 0.8)"
if not (c[REV] and c[SWITCH] and valid):
    reading += "; a validity check failed, so S is reported, not read"
print(f"Reading: {reading}. Least favourable window: {min(Sw):.3f}")
result("reading", reading.replace(" ", "_"))

# Reported, not scored.
print("\nReported (not scored), free, all scored levels and windows:")
rv, sw = recs[REV], recs[SWITCH]
ev = np.maximum(rv["r_free"], 0) > 0
for run, rec in ((REV, rv), (SWITCH, sw)):
    e = np.maximum(rec["r_free"], 0) > 0
    Da = np.minimum(rec["a_free"][e], 0).sum()
    print(f"  {run}: events {int(e.sum())}; over them Σ(−O) {-rec['O_free'][e].sum():.4e}, ΣI {rec['I_free'][e].sum():.4e}, "
          f"ΣG {rec['G_free'][e].sum():.4e}, ΣX {rec['X_free'][e].sum():.4e}, Σb {rec['b_free'][e].sum():.4e}, "
          f"D_a {Da:.4e}, ΣE {rec['E_free'][e].sum():.4e}, ΣEs (stage variant) {rec['Es_free'][e].sum():.4e}")
    print(f"    all cell-steps: Σ outflow {rec['O_free'].sum():.4e}, ΣE {rec['E_free'].sum():.4e}, Σr+ {np.maximum(rec['r_free'], 0).sum():.4e}")
Da_r = np.minimum(rv["a_free"][ev], 0).sum()
es = np.maximum(sw["r_free"], 0) > 0
Da_s = np.minimum(sw["a_free"][es], 0).sum()
Qa = (rv["E_free"][ev].sum() - sw["E_free"][es].sum()) / (Da_s - Da_r) if Da_s != Da_r else float("nan")
print(f"  Q_a, the extra ΣE over the events against the extra drain D_a: {Qa:.3f}")
xs_r = np.minimum(rv["Es_free"], np.maximum(rv["r_free"], 0)).sum()
xs_s = np.minimum(sw["Es_free"], np.maximum(sw["r_free"], 0)).sum()
print(f"  S with the stage variant: {(xs_r - xs_s) / extra if extra > 0 else float('nan'):.3f}")
if same_cells:
    print(f"  In rev's events, the same cell-steps in both arms: outflow rev {rv['O_free'][ev].sum():.4e}, "
          f"switch {sw['O_free'][ev].sum():.4e}; whole flux out rev {rv['OUT'][ev].sum():.4e}, switch {sw['OUT'][ev].sum():.4e}; "
          f"free at the start rev {rv['q0_free'][ev].sum():.4e}, switch {sw['q0_free'][ev].sum():.4e}; "
          f"E rev {rv['E_free'][ev].sum():.4e}, switch {sw['E_free'][ev].sum():.4e}")
for run, rec in ((REV, rv), (SWITCH, sw)):
    pe = rec["E_free"] > 0
    if pe.any():
        empty = rec["OUT"] >= rec["pos0"]
        frac = rec["E_free"][pe & empty].sum() / rec["E_free"][pe].sum()
        share = rec["q0_free"][pe] / np.where(rec["pos0"][pe] > 0, rec["pos0"][pe], np.nan)
        ratio = rec["OUT"][pe] / np.where(rec["pos0"][pe] > 0, rec["pos0"][pe], np.nan)
        print(f"  {run}: {int(pe.sum())} cell-steps with E > 0; their E's share where the whole outflow ≥ the partition's "
              f"water at the start {frac:.3f}; median free's share of the partition {np.nanmedian(share):.4f}, "
              f"median whole outflow over the partition's water {np.nanmedian(ratio):.2f}")
    lev = {}
    for l in ALL_LEVELS:
        m = rec["level"] == l
        lev[l] = np.maximum(rec["r_free"][m], 0).sum()
    top = sorted(lev.items(), key=lambda x: -x[1])[:4]
    print(f"  {run}: Σr+ by level, largest four: " + ", ".join(f"{l}: {v:.3e}" for l, v in top))
print("Reading of S (11.13.5): S >= 0.8 confirmed at site 23; S < 0.5 not the mechanism; otherwise partly.")
