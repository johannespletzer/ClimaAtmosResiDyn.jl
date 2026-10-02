"""W53, stage B: the scores of design/NEGATIVE_PARENT_WATER.md section 11.12.

    python3 ledfix_score.py [OUTPUT_ROOT]

Reads `lf_rev_s23` and `lf_switch_s23` (the probe's arms) and W49's `cr_s23`
and `cr_s23_main`, each under OUTPUT_ROOT/<run>/output_0000/. Prints:

  - B1: `lf_rev_s23`'s NetCDF files and audit rows against `cr_s23`'s, bit for
    bit, at every output both have;
  - B2: `lf_switch_s23`'s ten daily model fields and `hus`, `rhoa` 6-hourly
    against `cr_s23`'s, bit for bit;
  - B3: `lf_switch_s23`'s `q_tag_exp_negative` is zero everywhere, and so is
    its audit's `exp_negative_retained`;
  - B4 (reported): `lf_switch_s23`'s water tag files against `cr_s23_main`'s;
  - P1: f = (F_rev − F_switch) / (F_rev − F_main) at day 90, per tag;
  - P2: per arm, from `<run>_trace.csv`, φ = D_a / (D_a + D_b) over the
    cell-steps where the repair raised the tag, and the reported numbers.

A line `RESULT <name> <value>` per score, so that the numbers can be parsed.
"""
import csv
import os
import sys
from collections import defaultdict

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
REV, SWITCH, W49, MAIN = "lf_rev_s23", "lf_switch_s23", "cr_s23", "cr_s23_main"
MODEL_DAILY = ("rhoa", "ta", "hus", "clw", "cli", "wa", "pr", "lwp", "arup", "husup")
TAGS = ("pbl", "free")
DAY = 86400.0


def out(run):
    return os.path.join(ROOT, run, "output_0000")


def result(name, value):
    print(f"RESULT {name} {value}")


def read_nc(run, fname):
    with nc.Dataset(os.path.join(out(run), fname)) as d:
        var = fname.rsplit("_", 2)[0]
        return np.asarray(d["time"][:], dtype=np.float64), np.asarray(d[var][:])


def compare_files(a, b, files):
    """Bit for bit at the common times. Returns (equal, differing, missing)."""
    equal, differ, missing = [], [], []
    for f in files:
        if not os.path.exists(os.path.join(out(b), f)):
            missing.append(f)
            continue
        ta, va = read_nc(a, f)
        tb, vb = read_nc(b, f)
        common = np.intersect1d(ta, tb)
        ia = np.searchsorted(ta, common)
        ib = np.searchsorted(tb, common)
        tax_a = list(np.asarray(va.shape)).index(len(ta)) if va.ndim else 0
        tax_b = list(np.asarray(vb.shape)).index(len(tb)) if vb.ndim else 0
        xa = np.take(va, ia, axis=tax_a)
        xb = np.take(vb, ib, axis=tax_b)
        if xa.shape == xb.shape and np.array_equal(xa, xb, equal_nan=True) and len(common) > 0:
            equal.append((f, len(common)))
        else:
            diff = np.nanmax(np.abs(xa.astype(np.float64) - xb.astype(np.float64))) if xa.shape == xb.shape else np.inf
            differ.append((f, len(common), diff))
    return equal, differ, missing


def audit(run):
    with open(os.path.join(out(run), "water_tag_audit.csv")) as f:
        rows = list(csv.DictReader(f))
    return rows


def nc_files(run):
    return sorted(f for f in os.listdir(out(run)) if f.endswith("_inst.nc"))


# B1.
if os.path.isdir(out(REV)):
    eq, df, miss = compare_files(REV, W49, nc_files(REV))
    ra, wa = audit(REV), audit(W49)
    n = min(len(ra), len(wa))
    audit_equal = all(ra[i] == wa[i] for i in range(n))
    print(f"B1: {len(eq)} files equal cr_s23's bit for bit, {len(df)} differ, {len(miss)} missing in cr_s23; "
          f"audit rows equal in all {n} common rows: {audit_equal}")
    for f, k, d in df:
        print(f"    differs: {f} ({k} common outputs, largest difference {d:.3e})")
    print(f"    outputs compared per file: {sorted(set(k for _, k in eq))}")
    result("B1", "pass" if not df and not miss and audit_equal and eq else "fail")
else:
    print(f"B1: {REV} not found")
    result("B1", "missing")

# B2, B3, B4, P1.
if os.path.isdir(out(SWITCH)):
    files = [f"{v}_1d_inst.nc" for v in MODEL_DAILY] + ["hus_6h_inst.nc", "rhoa_6h_inst.nc"]
    eq, df, miss = compare_files(SWITCH, W49, files)
    print(f"B2: {len(eq)} of {len(files)} model files equal cr_s23's bit for bit; differ {[(f, d) for f, _, d in df]}; missing {miss}")
    print(f"    outputs compared per file: {sorted(set(k for _, k in eq))}")
    result("B2", "pass" if len(eq) == len(files) else "fail")

    worst = 0.0
    for f in ("q_tag_exp_negative_6h_inst.nc", "q_tag_exp_negative_1d_inst.nc",
              "q_tag_exp_negative_gross_6h_inst.nc", "q_tag_exp_negative_gross_1d_inst.nc"):
        _, v = read_nc(SWITCH, f)
        worst = max(worst, float(np.nanmax(np.abs(v))))
    sa = audit(SWITCH)
    audit_worst = max(abs(float(r["exp_negative_retained"])) for r in sa)
    print(f"B3: largest |q_tag_exp_negative| over its four files {worst:.3e}; largest audit exp_negative_retained {audit_worst:.3e} over {len(sa)} rows")
    result("B3", "pass" if worst == 0.0 and audit_worst == 0.0 else "fail")

    tagfiles = [f for f in nc_files(SWITCH) if f.startswith("q_tag_") and "exp_negative" not in f]
    eq, df, miss = compare_files(SWITCH, MAIN, tagfiles)
    print(f"B4 (reported): {len(eq)} of {len(tagfiles)} water tag files equal cr_s23_main's bit for bit; "
          f"{len(df)} differ, {len(miss)} not in cr_s23_main")
    for f, k, d in sorted(df, key=lambda x: -x[2])[:8]:
        print(f"    differs: {f} ({k} outputs, largest difference {d:.3e})")

    rows = {run: audit(run) for run in (W49, SWITCH, MAIN)}
    for run, r in rows.items():
        last = float(r[-1]["time"]) / DAY
        print(f"    {run}: last audit row at day {last:g}")
    fs = []
    for tag in TAGS:
        k = f"led_fix_{tag}_inventory_fraction"
        F = {run: float(r[-1][k]) for run, r in rows.items()}
        f = (F[W49] - F[SWITCH]) / (F[W49] - F[MAIN])
        fs.append(f)
        print(f"P1 {tag}: F_rev {F[W49]:.4e}, F_switch {F[SWITCH]:.4e}, F_main {F[MAIN]:.4e}; f = {f:.4f}; "
              f"F_switch against 2%: {'above' if F[SWITCH] > 0.02 else 'at or below'}")
        result(f"P1_f_{tag}", f"{f:.4f}")
        result(f"P1_F_switch_{tag}", f"{F[SWITCH]:.4e}")
    if all(f >= 0.9 for f in fs):
        reading = "the rule makes at least 0.9 of the extra"
    elif all(f <= 0.1 for f in fs):
        reading = "the rule makes at most 0.1 of the extra; the rest of the bundle makes the rise"
    else:
        reading = f"both, as measured; the smaller f is {min(fs):.4f}"
    print(f"P1 reading: {reading}")
    result("P1_reading", reading.replace(" ", "_"))
else:
    print(f"B2-B4, P1: {SWITCH} not found")


# P2.
def trace(run):
    path = os.path.join(out(run), f"{run}_trace.csv")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        r = csv.reader(f)
        header = next(r)
        data = np.array([[float(x) for x in row] for row in r])
    return header, data


def windows(data):
    """Split the rows into windows at each step_end == 0 row."""
    starts = np.flatnonzero((data[:, 1] == 0) & (data[:, 2] == 0))
    bounds = list(starts) + [len(data)]
    return [data[bounds[i] : bounds[i + 1]] for i in range(len(starts))]


def p2(run):
    tr = trace(run)
    if tr is None:
        print(f"P2 {run}: no trace")
        return None
    header, data = tr
    col = {h: i for i, h in enumerate(header)}
    sums = {}
    for tag in TAGS:
        tot = defaultdict(float)
        for w in windows(data):
            t0 = w[0, 0] / DAY
            levels = sorted(set(w[:, 2].astype(int)) - {0})
            for lev in levels:
                x = w[w[:, 2] == lev]
                x = x[np.argsort(x[:, 0], kind="stable")]
                q = x[:, col[f"ρq_tag_{tag}"]]
                fix = x[:, col[f"q_tag_led_fix_{tag}"]]
                inc = x[:, col[f"q_tag_led_inc_{tag}"]]
                pbl = x[:, col["ρq_tag_pbl"]]
                free = x[:, col["ρq_tag_free"]]
                dq, r, a = np.diff(q), np.diff(fix), np.diff(inc)
                b = dq - r - a
                ev = r > 0
                key = f"{t0:.2f}"
                tot[(key, "D_a")] += np.minimum(a[ev], 0).sum()
                tot[(key, "D_b")] += np.minimum(b[ev], 0).sum()
                tot[(key, "R")] += r[ev].sum()
                tot[(key, "gross")] += np.abs(r).sum()
                tot[(key, "events")] += ev.sum()
                part = pbl[:-1] + free[:-1]
                share = np.where(part > 0, free[:-1] / np.where(part > 0, part, 1), np.nan)
                tot[(key, "share_sum")] += np.nansum(share[ev])
                tot[(key, "share_n")] += np.sum(ev & np.isfinite(share))
        keys = sorted(set(k for k, _ in tot))
        D_a = sum(tot[(k, "D_a")] for k in keys)
        D_b = sum(tot[(k, "D_b")] for k in keys)
        phi = D_a / (D_a + D_b) if (D_a + D_b) != 0 else float("nan")
        for k in keys:
            da, db = tot[(k, "D_a")], tot[(k, "D_b")]
            ph = da / (da + db) if (da + db) != 0 else float("nan")
            sn = tot[(k, "share_n")]
            print(f"P2 {run} {tag} window from day {k}: events {int(tot[(k, 'events')])}, Σr {tot[(k, 'R')]:.4e}, "
                  f"gross {tot[(k, 'gross')]:.4e}, D_a {da:.4e}, D_b {db:.4e}, φ {ph:.3f}, "
                  f"mean free share at the start {tot[(k, 'share_sum')] / sn if sn else float('nan'):.3e}")
        print(f"P2 {run} {tag} all windows: D_a {D_a:.4e}, D_b {D_b:.4e}, φ {phi:.3f}")
        result(f"P2_phi_{run}_{tag}", f"{phi:.3f}")
        sums[tag] = {k: tot[(k, "gross")] for k in keys}
    return sums


s_rev = p2(REV)
s_sw = p2(SWITCH)


def sixhourly_gross(run, tag, a_day, b_day, levels):
    """The 6-hourly `q_tag_led_fixgross_<tag>` increment over [a, b] at the
    traced levels, times `rhoa` at b, summed: kg m^-3, as the trace's."""
    if not os.path.exists(os.path.join(out(run), f"q_tag_led_fixgross_{tag}_6h_inst.nc")):
        return float("nan")
    t, g = read_nc(run, f"q_tag_led_fixgross_{tag}_6h_inst.nc")
    _, rho = read_nc(run, "rhoa_6h_inst.nc")
    ia, ib = np.searchsorted(t, a_day * DAY), np.searchsorted(t, b_day * DAY)
    if ib >= len(t) or abs(t[ib] - b_day * DAY) > 1 or abs(t[ia] - a_day * DAY) > 1:
        return float("nan")
    lev = np.array(levels) - 1
    return float(((g[lev, ib] - g[lev, ia]) * rho[lev, ib]).sum())


WINDOW_DAYS = ((11.25, 11.75), (15.75, 16.0), (55.75, 56.25))
LEVELS = (8, 9, 10, 11, 12, 13, 14)
for tag in TAGS:
    for a, b in WINDOW_DAYS:
        k = f"{a:.2f}"
        tr_rev = s_rev[tag].get(k, float("nan")) if s_rev else float("nan")
        tr_sw = s_sw[tag].get(k, float("nan")) if s_sw else float("nan")
        six_rev = sixhourly_gross(W49, tag, a, b, LEVELS)
        six_sw = sixhourly_gross(SWITCH, tag, a, b, LEVELS)
        print(f"P2 {tag} days {a}-{b}, repair gross at the traced levels (kg m^-3, summed over levels): "
              f"trace rev {tr_rev:.4e}, switch {tr_sw:.4e}, difference {tr_rev - tr_sw:.4e}; "
              f"6-hourly cr_s23 {six_rev:.4e}, switch {six_sw:.4e}, difference {six_rev - six_sw:.4e}")
print("P2 reading: φ ≥ 2/3 the follower; φ ≤ 1/3 everything else in the step; otherwise both (11.12.5)")
