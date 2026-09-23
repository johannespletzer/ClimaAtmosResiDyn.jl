"""H3 (CONDENSE_PLAN.md): recompute the arithmetic behind W1, W3, W4, W5,
W5b, W12, W13, W14, E55 and E59 straight from the CSVs already committed
under experiments/tag_closure/output/. No netCDF, no Julia: every number
these findings quote is already reduced into a committed CSV, so this is
plain arithmetic on those files.

Run from experiments/tag_closure/ with `module load python/3.12`:

    python3 review/checks/verify_g3/recompute_water_and_energy.py

All printed numbers are meant to be compared by eye against FINDINGS.md's
W1, W3, W4, W5, W5b, W12, W13, W14, E55 and E59 entries.
"""
import csv
import math
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "output")


def read_csv(path):
    with open(os.path.join(ROOT, path)) as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines))


def summary_a():
    with open(os.path.join(ROOT, "summary_a.csv")) as f:
        return {row["run"]: row for row in csv.DictReader(f)}


def slope(dts, values):
    x = [math.log(d) for d in dts]
    y = [math.log(v) for v in values]
    n = len(x)
    mx = sum(x) / n
    my = sum(y) / n
    num = sum((xi - mx) * (yi - my) for xi, yi in zip(x, y))
    den = sum((xi - mx) ** 2 for xi in x)
    return num / den


print("=== W1: van Leer flat, first_order and none converge, dt10 ratio ===")
s = summary_a()
dt = [10.0, 5.0, 2.5]
vanleer = [float(s[f"a1_dt{t}"]["final_max_abs_q_tag_res"]) for t in ("10", "5", "2p5")]
first_order = [
    float(s[f"a2_first_order_dt{t}"]["final_max_abs_q_tag_res"]) for t in ("10", "5", "2p5")
]
none = [float(s[f"a2_none_dt{t}"]["final_max_abs_q_tag_res"]) for t in ("10", "5", "2p5")]
print(f"  vanleer slope     : {slope(dt, vanleer):.3f}   (FINDINGS: -0.011)")
print(f"  first_order slope : {slope(dt, first_order):.3f}   (FINDINGS: +0.255)")
print(f"  none slope        : {slope(dt, none):.3f}   (FINDINGS: +0.464)")
print(f"  vanleer/none @dt10: {vanleer[0] / none[0]:.2f}x  (FINDINGS: 13.8x)")

print()
print("=== W3: ledger sum is 0.0 for every water column run (11 in A1-A3) ===")
a1a2a3 = [
    "a1_dt10", "a1_dt5", "a1_dt2p5",
    "a2_first_order_dt10", "a2_first_order_dt5", "a2_first_order_dt2p5",
    "a2_none_dt10", "a2_none_dt5", "a2_none_dt2p5",
    "a3_0m_vert_diff", "a3_1m",
]
vals = [float(s[r]["final_max_abs_ledger_sum"]) for r in a1a2a3]
print(f"  {len(a1a2a3)} runs, ledger sums: {set(vals)} (FINDINGS: identically zero)")

print()
print("=== W4: Float32 vs Float64 gross_relative, same config ===")
f32 = float(s["a4_float32"]["final_gross_relative"])
f64 = float(s["a1_dt10"]["final_gross_relative"])
print(f"  a4_float32: {f32:.4e}  (FINDINGS: 2.745e-5)")
print(f"  a1_dt10   : {f64:.4e}  (FINDINGS: 2.660e-5)")
print(f"  diff      : {(f32 - f64) / f64 * 100:.1f}%  (FINDINGS: 3%)")

print()
print("=== W5 / W5b: vertical diffusion vs 1M factoring ===")
a1 = float(s["a1_dt10"]["final_max_abs_q_tag_res"])
a3_0m = float(s["a3_0m_vert_diff"]["final_max_abs_q_tag_res"])
a3_1m = float(s["a3_1m"]["final_max_abs_q_tag_res"])
print(f"  vert_diff on, 0M held (a1->a3_0m): {a3_0m / a1:.3f}  (FINDINGS: 0.037)")
print(f"  1M on, vert_diff held (a3_0m->a3_1m): {a3_1m / a3_0m:.3f}  (FINDINGS: 0.934)")
print(f"  both (a1->a3_1m): {a3_1m / a1:.3f}  (FINDINGS: 0.035, '29x below')")
print(f"  a1/a3_1m ratio: {a1 / a3_1m:.1f}x  (FINDINGS: 29x)")

print()
print("=== W12: pre-fix ledger, extratropics/tropics, factor ===")
before = read_csv("a5_sphere_limiter/before_issue_64_fix/operator_residual.csv")
last = before[-1]
tropics = float(last["max_abs_q_tag_fix_tropics"])
extratropics = float(last["max_abs_q_tag_fix_extratropics"])
print(f"  extratropics @24h: {extratropics:.3e}  (FINDINGS: 1.027e115)")
print(f"  tropics @24h     : {tropics:.3e}  (FINDINGS: 4.55e109)")
print(f"  ratio            : {extratropics / tropics:.2e}  (FINDINGS: 2e5)")

print()
print("=== W13/W14: post-fix operator_residual.csv, 6h/17h/24h ===")
after = read_csv("a5_sphere_limiter/operator_residual.csv")
byt = {float(r["time"]): r for r in after}
for h, t in [(6, 21600.0), (17, 61200.0), (24, 86400.0)]:
    r = byt[t]
    print(
        f"  t={h:2d}h  q_tag_res={float(r['max_abs_q_tag_res']):.3e}  "
        f"ledger_sum={float(r['max_abs_ledger_sum']):.3e}"
    )
last = byt[86400.0]
ratio = float(last["max_abs_ledger_sum"]) / float(last["max_abs_q_tag_res"])
print(f"  ledger/q_tag_res @24h = {ratio:.1f}x  (FINDINGS W14: '32x')")

print()
print("=== E55: D4-vd Float32 vs Float64, mean/range/ratio over the day ===")


def stats(path, key, skip_t0=True):
    rows = read_csv(path)
    vals = [float(r[key]) for r in rows if not (skip_t0 and float(r["time"]) == 0.0)]
    return min(vals), max(vals), sum(vals) / len(vals)


f32 = stats("d4_column_edmf_vd_float32/energy_source_tag_closure.csv", "gross_relative")
f64 = stats("d4_column_edmf_vd/energy_source_tag_closure.csv", "gross_relative")
print(f"  f32 gross_relative range/mean: {f32}  (FINDINGS: 1.7e-3 to 7.7e-3, mean 4.68e-3)")
print(f"  f64 gross_relative range/mean: {f64}  (FINDINGS: 1.5e-3 to 8.6e-3, mean 4.80e-3)")


def overclaim_ratio_stats(path):
    rows = read_csv(path)
    ratios = [
        float(r["overclaimed"]) / float(r["untagged"])
        for r in rows
        if float(r["time"]) != 0.0
    ]
    return min(ratios), max(ratios), sum(ratios) / len(ratios), sum(1 for x in ratios if x > 1)


f32r = overclaim_ratio_stats("d4_column_edmf_vd_float32/energy_source_tag_audit.csv")
f64r = overclaim_ratio_stats("d4_column_edmf_vd/energy_source_tag_audit.csv")
print(f"  f32 overclaimed/untagged: range {f32r[0]:.2f}-{f32r[1]:.2f}, mean {f32r[2]:.2f}, "
      f"net-overclaimed {f32r[3]}/24 hours  (FINDINGS: 0.91-1.14, mean 1.02, 12/24)")
print(f"  f64 overclaimed/untagged: range {f64r[0]:.2f}-{f64r[1]:.2f}, mean {f64r[2]:.2f}, "
      f"net-overclaimed {f64r[3]}/24 hours  (FINDINGS: 0.73-0.99, mean 0.85, 0/24)")

print()
print("=== E59: C1c gross residual/relative, base vs opt1/opt2/opt3 ===")
hours = {1: 3600.0, 4: 14400.0, 12: 43200.0, 24: 86400.0}
for name in ("c1c_base_d4_enthalpy", "c1c_opt1_d4_enthalpy", "c1c_opt2_d4_enthalpy", "c1c_opt3_d4_enthalpy"):
    rows = read_csv(f"{name}/energy_source_tag_closure.csv")
    byt = {float(r["time"]): r for r in rows}
    parts = [f"h{h}={float(byt[t]['gross_residual']):.3e}" for h, t in hours.items()]
    grel24 = float(byt[86400.0]["gross_relative"])
    print(f"  {name:24s} " + " ".join(parts) + f"  grel24={grel24:.3e}")
base24 = float(read_csv("c1c_base_d4_enthalpy/energy_source_tag_closure.csv")[-1]["gross_residual"])
e53_24 = float(read_csv("d4_column_edmf_enthalpy/energy_source_tag_closure.csv")[-1]["gross_residual"])
print(f"  base/E53 ratio: {base24 / e53_24:.3f} -> {(base24 / e53_24 - 1) * 100:.1f}% above "
      f"(FINDINGS: '17% above')")
