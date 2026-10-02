"""W53, stage A: where and when V5's `led_fix` rises at site 23 in W49.

Written after W49's runs were read. It is a measurement of existing output,
not a pre-registered test. It compares the revision (`cr_s23`, model
`0eb329b2`) with the control on `main` (`cr_s23_main`, `43b01ca1`). The two
runs' model fields are bit for bit the same (W49, V4b), so the parent is the
same in both and only the tag side differs. The two codes differ in more than
one thing (W49, "What was measured"), so a difference bounds and does not
isolate.

    python3 ledfix_s23_localise.py [OUTPUT_ROOT] [OUT_DIR]

Reads each run's `water_tag_audit.csv` and the 6-hourly fields:

  - `q_tag_led_fixgross_<tag>`: each tag's per-step gross of the repair's
    corrections, cumulative, per unit mass. Its column integral is V5's
    numerator, `led_fix_<tag>_retained`;
  - `q_tag_led_fix_<tag>`: the same, signed;
  - `q_tag_led_inc_<tag>`: the follower's moves of each tag, signed;
  - `q_tag_exp_negative` (the revision only): the gain the rule withheld;
  - `q_tag_inc_negative_gross`: the follower's negative part, gross;
  - `q_tag_negative`, `hus`, `rhoa`, and `pr` (daily).

Per 6-hour interval and level, the "extra" is the revision's increment of a
cumulative field less the control's. Column integrals use `rhoa` times a
layer depth from the midpoints between the levels. The script checks that
this reproduces the audit's `led_fix_<tag>_retained`.

Writes into OUT_DIR:

  - `ledfix_s23_localise.txt`: the summary;
  - `ledfix_s23_intervals.csv`: one row per 6-hour interval;
  - `ledfix_s23_levels.csv`: one row per level.
"""
import csv
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ["SCRATCH"], "tag_closure", "output")
OUT = sys.argv[2] if len(sys.argv) > 2 else "."
REV, CTL = "cr_s23", "cr_s23_main"
TAGS = ("pbl", "free")
DAY = 86400.0
lines = []


def say(*a):
    s = " ".join(str(x) for x in a)
    print(s)
    lines.append(s)


def field(job, var, period="6h"):
    """(time, z) array of a single-column output."""
    with nc.Dataset(os.path.join(ROOT, job, "output_0000", f"{var}_{period}_inst.nc")) as d:
        v = d[var]
        a = np.asarray(v[:], dtype=np.float64)
        dims = v.dimensions
        a = np.moveaxis(a, [dims.index("time"), dims.index("z")], [0, 1])
        assert a.ndim == 2, (var, a.shape)
        return a


def audit(job):
    with open(os.path.join(ROOT, job, "output_0000", "water_tag_audit.csv")) as f:
        rows = list(csv.DictReader(f))
    return {k: np.array([float(r[k]) for r in rows]) for k in rows[0] if k}


with nc.Dataset(os.path.join(ROOT, REV, "output_0000", "hus_6h_inst.nc")) as d:
    z = np.asarray(d["z"][:], dtype=np.float64)
    t = np.asarray(d["time"][:], dtype=np.float64) / DAY
zf = np.concatenate([[0.0], (z[1:] + z[:-1]) / 2, [z[-1] + (z[-1] - z[-2]) / 2]])
dz = np.diff(zf)
rho = field(REV, "rhoa")
assert np.array_equal(rho, field(CTL, "rhoa")), "rhoa differs: not the same atmosphere"
assert np.array_equal(field(REV, "hus"), field(CTL, "hus")), "hus differs"
weight = rho * dz  # column integral per unit area, approximate layer depth
tend = t[1:]  # each interval by its end


def col(job, var):
    return field(job, var) * weight


def inc(job, var):
    """Per interval and level, the increment of a cumulative field, integrated."""
    return np.diff(col(job, var), axis=0)


A = {REV: audit(REV), CTL: audit(CTL)}
assert np.allclose(A[REV]["time"] / DAY, t) and np.allclose(A[CTL]["time"] / DAY, t)

say("W53 stage A: V5's led_fix at site 23, the revision (cr_s23) against main (cr_s23_main)")
say(f"OUTPUT_ROOT {ROOT}; {len(t)} outputs, days {t[0]:g} to {t[-1]:g}; {len(z)} levels")
say("hus and rhoa: bit for bit the same in both runs at every 6-hourly output (asserted)")

# 1. Which mechanism. The audit's per-mechanism gross since the start.
say("")
say("1. The mechanism, from the audit at day 90 (gross since the start, as the audit integrates)")
for k in (
    "led_fix_pbl_retained",
    "led_fix_free_retained",
    "led_repair_retained",
    "led_repairnet_retained",
    "led_rescale_retained",
    "led_empty_retained",
    "led_fix_pbl_inventory_fraction",
    "led_fix_free_inventory_fraction",
):
    r, c = A[REV][k][-1], A[CTL][k][-1]
    say(f"   {k:34s} rev {r:.4e}  main {c:.4e}  rev-main {r - c:+.4e}  rev/main {r / c if c else float('nan'):.3f}")

# Check the column reconstruction against the audit.
for tag in TAGS:
    g = col(REV, f"q_tag_led_fixgross_{tag}").sum(axis=1)
    a = A[REV][f"led_fix_{tag}_retained"]
    ok = a > 0
    ratio = a[ok] / g[ok]
    say(f"   check: audit led_fix_{tag}_retained over the column integral of q_tag_led_fixgross_{tag}: "
        f"{ratio.min():.5f} to {ratio.max():.5f} over {ok.sum()} outputs")

# 2. When.
say("")
say("2. When: per 6-hour interval, the increment of led_fix_<tag>_retained (audit), rev less main")
rows = {}
for tag in TAGS:
    k = f"led_fix_{tag}_retained"
    dr, dc = np.diff(A[REV][k]), np.diff(A[CTL][k])
    ex = dr - dc
    rows[tag] = (dr, dc, ex)
    first = int(np.argmax(ex != 0))
    order = np.argsort(-ex)
    share = np.cumsum(ex[order]) / ex.sum()
    say(f"   {tag}: extra at day 90 {ex.sum():.4e} (rev {dr.sum():.4e}, main {dc.sum():.4e}); "
        f"first nonzero in the interval ending day {tend[first]:.2f}; "
        f"intervals with extra > 0: {(ex > 0).sum()}, < 0: {(ex < 0).sum()}, of {len(ex)}")
    say(f"     the largest 1, 5, 10, 20 intervals carry {share[0]:.3f}, {share[4]:.3f}, {share[9]:.3f}, {share[19]:.3f} of the extra; "
        f"50% needs {int(np.argmax(share >= 0.5)) + 1}, 80% needs {int(np.argmax(share >= 0.8)) + 1}")
    bins = [ex[(tend > a) & (tend <= a + 10)].sum() for a in range(0, 90, 10)]
    say("     extra per 10 days (0-10, ..., 80-90): " + ", ".join(f"{b:.4f}" for b in bins))
    binr = [dr[(tend > a) & (tend <= a + 10)].sum() for a in range(0, 90, 10)]
    binc = [dc[(tend > a) & (tend <= a + 10)].sum() for a in range(0, 90, 10)]
    say("     rev per 10 days:  " + ", ".join(f"{b:.4f}" for b in binr))
    say("     main per 10 days: " + ", ".join(f"{b:.4f}" for b in binc))
    if tag == "pbl":
        top = order[:10]
ex_pbl, ex_free = rows["pbl"][2], rows["free"][2]
say(f"   pbl's extra less free's extra, summed: {ex_pbl.sum() - ex_free.sum():+.3e}; "
    f"largest per interval {np.abs(ex_pbl - ex_free).max():.3e}")

# 3. Where, per level, from the 6-hourly fields.
say("")
say("3. Where: per level, the increments of q_tag_led_fixgross_<tag>, rev less main, over 90 days")
G = {tag: (inc(REV, f"q_tag_led_fixgross_{tag}"), inc(CTL, f"q_tag_led_fixgross_{tag}")) for tag in TAGS}
F = {tag: (inc(REV, f"q_tag_led_fix_{tag}"), inc(CTL, f"q_tag_led_fix_{tag}")) for tag in TAGS}
I = {tag: (inc(REV, f"q_tag_led_inc_{tag}"), inc(CTL, f"q_tag_led_inc_{tag}")) for tag in TAGS}
bands = ((0, 1000), (1000, 2000), (2000, 1e9))
for tag in TAGS:
    gr, gc = G[tag]
    ex = gr - gc
    lv = ex.sum(axis=0)
    tot = ex.sum()
    say(f"   {tag}: extra {tot:.4e} (column units); shares by band "
        + ", ".join(f"{a:g}-{b:g} m {lv[(z >= a) & (z < b)].sum() / tot:.3f}" for a, b in bands))
    say(f"     rev's own gross below 1 km {gr.sum(axis=0)[z < 1000].sum() / gr.sum():.3f}, main's {gc.sum(axis=0)[z < 1000].sum() / gc.sum():.3f}")
    o = np.argsort(-np.abs(lv))[:6]
    say("     largest levels (z m: share): " + ", ".join(f"{z[j]:.0f}: {lv[j] / tot:.3f}" for j in o))

# 4. Direction: which tag the repair raised.
say("")
say("4. Direction: the signed repair ledgers, rev less main, summed (column units)")
for tag in TAGS:
    fr, fc = F[tag]
    gr, gc = G[tag]
    say(f"   {tag}: signed extra {(fr - fc).sum():+.4e}, gross extra {(gr - gc).sum():.4e}; "
        f"rev signed {fr.sum():+.4e}, main signed {fc.sum():+.4e}")
say("   (a positive signed value is water the repair added to the tag: the tag had gone below zero)")

# 5. What co-varies, per interval and level.
say("")
say("5. Co-variation, per (interval, level) cell, of pbl's extra gross")
ex = G["pbl"][0] - G["pbl"][1]
tot = ex.sum()
dexp = inc(REV, "q_tag_exp_negative")
dneg_r = inc(REV, "q_tag_inc_negative_gross")
dneg_c = inc(CTL, "q_tag_inc_negative_gross")
qneg = field(REV, "q_tag_negative")
negcell = (qneg[:-1] < 0) | (qneg[1:] < 0)
say(f"   share in cells where the rule withheld a gain (q_tag_exp_negative grew): {ex[dexp > 0].sum() / tot:.3f} "
    f"({(dexp > 0).sum()} of {dexp.size} cells)")
say(f"   share in cells where the follower's negative part moved (q_tag_inc_negative_gross grew, rev): {ex[dneg_r > 0].sum() / tot:.3f}")
say(f"   share in cells whose parent is negative at either end of the interval: {ex[negcell].sum() / tot:.3f}")
say(f"   share in cells with none of the three: {ex[(dexp <= 0) & (dneg_r <= 0) & ~negcell].sum() / tot:.3f}")
say(f"   the follower's negative part, column gross per interval: rev equals main in {int(np.sum(np.isclose(dneg_r.sum(1), dneg_c.sum(1), rtol=1e-6, atol=0)))} of {len(tend)} intervals; "
    f"per cell they differ by up to {np.abs(dneg_r - dneg_c).max():.3e}")
say(f"   q_tag_exp_negative's column increment over 90 days: {dexp.sum():.4e}; pbl's extra repair gross: {tot:.4e}")
# The follower's per-tag moves in the same cells.
xfix_free = F["free"][0] - F["free"][1]
xinc_free = I["free"][0] - I["free"][1]
xinc_pbl = I["pbl"][0] - I["pbl"][1]
say(f"   the follower's extra signed move of free, summed over all cells {xinc_free.sum():+.4e}, of pbl {xinc_pbl.sum():+.4e}")

# 6. The largest intervals, one by one.
say("")
say("6. The ten intervals with pbl's largest extra (audit), with the cell that carries most of it")
say("   end day | extra pbl | rev | main | top level z, its share | at that cell: extra fix free, extra follower free, extra follower pbl, exp_negative growth | column: exp_negative growth, follower negative gross | parent negative at an end")
for j in top:
    e = ex[j]
    L = int(np.argmax(np.abs(e)))
    say(f"   {tend[j]:6.2f} | {rows['pbl'][2][j]:.4e} | {rows['pbl'][0][j]:.4e} | {rows['pbl'][1][j]:.4e} | {z[L]:.0f} m, {e[L] / e.sum():.2f} | "
        f"{xfix_free[j, L]:+.3e}, {xinc_free[j, L]:+.3e}, {xinc_pbl[j, L]:+.3e}, {dexp[j, L]:.3e} | "
        f"{dexp[j].sum():.3e}, {dneg_r[j].sum():.3e} | {bool(negcell[j].any())}")

# Daily precipitation against the daily extra (both instantaneous at the day's end).
with nc.Dataset(os.path.join(ROOT, REV, "output_0000", "pr_1d_inst.nc")) as d:
    pr = np.asarray(d["pr"][:], dtype=np.float64).reshape(len(d["time"]), -1)[:, 0]
day_ex = np.array([rows["pbl"][2][(tend > d - 1) & (tend <= d)].sum() for d in range(1, 91)])
say("")
say("7. Precipitation (pr, instantaneous at the end of each day, not an accumulation)")


def ranks(x):
    r = np.empty(len(x))
    r[np.argsort(x, kind="stable")] = np.arange(len(x))
    return r


m = len(day_ex)
say(f"   Spearman rank correlation of the daily extra with |pr| at the day's end: {np.corrcoef(ranks(day_ex), ranks(np.abs(pr[1 : m + 1])))[0, 1]:+.3f} (90 days)")
top_days = np.argsort(-day_ex)[:5] + 1
say("   the five days with the largest extra and their |pr| rank of 90 (1 = largest): "
    + ", ".join(f"day {d}: {int(m - ranks(np.abs(pr[1 : m + 1]))[d - 1])}" for d in top_days))

with open(os.path.join(OUT, "ledfix_s23_localise.txt"), "w") as f:
    f.write("\n".join(lines) + "\n")

with open(os.path.join(OUT, "ledfix_s23_intervals.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow([
        "end_day",
        "led_fix_pbl_rev", "led_fix_pbl_main", "led_fix_pbl_extra",
        "led_fix_free_rev", "led_fix_free_main", "led_fix_free_extra",
        "repairnet_rev", "repairnet_main",
        "exp_negative_growth_col", "inc_negative_gross_rev_col", "inc_negative_gross_main_col",
        "extra_fix_free_signed_col", "extra_inc_free_signed_col",
        "levels_parent_negative_at_end", "min_hus_at_end",
    ])
    rn_r, rn_c = np.diff(A[REV]["led_repairnet_retained"]), np.diff(A[CTL]["led_repairnet_retained"])
    hus = field(REV, "hus")
    for j in range(len(tend)):
        w.writerow([
            f"{tend[j]:.2f}",
            *(f"{x:.6e}" for x in (rows["pbl"][0][j], rows["pbl"][1][j], rows["pbl"][2][j],
                                  rows["free"][0][j], rows["free"][1][j], rows["free"][2][j],
                                  rn_r[j], rn_c[j], dexp[j].sum(), dneg_r[j].sum(), dneg_c[j].sum(),
                                  xfix_free[j].sum(), xinc_free[j].sum())),
            int((qneg[j + 1] < 0).sum()),
            f"{hus[j + 1].min():.6e}",
        ])

with open(os.path.join(OUT, "ledfix_s23_levels.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["level", "z_m", "fixgross_pbl_rev", "fixgross_pbl_main", "fixgross_pbl_extra",
                "fixgross_free_rev", "fixgross_free_main", "fixgross_free_extra",
                "fix_free_signed_extra", "inc_free_signed_extra", "exp_negative_growth",
                "intervals_parent_negative"])
    for L in range(len(z)):
        w.writerow([L + 1, f"{z[L]:.1f}",
                    *(f"{x:.6e}" for x in (G["pbl"][0][:, L].sum(), G["pbl"][1][:, L].sum(), (G["pbl"][0] - G["pbl"][1])[:, L].sum(),
                                          G["free"][0][:, L].sum(), G["free"][1][:, L].sum(), (G["free"][0] - G["free"][1])[:, L].sum(),
                                          xfix_free[:, L].sum(), xinc_free[:, L].sum(), dexp[:, L].sum())),
                    int(negcell[:, L].sum())])
