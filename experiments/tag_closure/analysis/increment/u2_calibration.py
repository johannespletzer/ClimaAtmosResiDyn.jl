"""G4.5, B11: calibrate the energy source tags' closure warning per transport.

    python3 u2_calibration.py [OUTPUT_ROOT] > u2_calibration.txt

Reads every run on scratch that wrote `energy_source_tag_closure.csv` (the
latest `output_XXXX` of each). For each it prints its transport, its length,
the largest `gross_relative` over its rows (the quantity the model's
`tolerance` is compared with), and the gross residual over the throughput
since the start, on the exact scale Θx where the audit has
`source_throughput`, and on the records' estimate Θi otherwise
(`od4_restate.py`; E84: an estimate, not a bound).

Then, per transport: the largest value over the runs this file counts as
healthy, against the model's default (`ENERGY_SOURCE_CLOSURE_TOLERANCES`), and
the margin. B11 names V2 and V3: V2 is `g2_v2_sphere*`, under `enthalpy_increment`, and
B11's V3 is E45's, `v3_sphere_float32`, under `tracer`. The D4 twins of E68
and E73 (`v3_upd_*`) are marked apart. `enthalpy` is calibrated from the other
runs.

A run is left out of the calibration, and listed with its reason, where the
record found a defect in it: the explicit 1M path without G4.16's blocks
(E80, E82's control), and C1c's shelved placements (E59). Warnings are runaway
guards (G4.5), so a defect run is what they must catch, not what sets them.
"""
import csv
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from od4_restate import ROOT as DEFAULT_ROOT  # noqa: E402
import od4_restate as od4  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ROOT
od4.ROOT = ROOT
DEFAULTS = {"tracer": 1.0, "enthalpy": 0.1, "enthalpy_increment": 0.01}
DEFECTS = {
    "g416_expl_n1_off": "explicit 1M without the cross blocks (E82's control)",
    "g415_n5_explicit_n1": "explicit 1M without the cross blocks (E80)",
    "c1c_opt1_d4_enthalpy": "C1c option 1, shelved (E59)",
    "c1c_opt2_d4_enthalpy": "C1c option 2, shelved (E59)",
    "c1c_opt3_d4_enthalpy": "C1c option 3, shelved (E59)",
    "c1c_opt1_newton_d4_enthalpy": "C1c option 1, shelved (E59, E61)",
}


def transport(run):
    d = od4.out_dir(run)
    configs = glob.glob(os.path.join(d, "*.yml"))
    for path in configs:
        with open(path) as f:
            for line in f:
                if line.strip().startswith("energy_source_tag_transport:"):
                    return line.split(":", 1)[1].strip().strip('"')
    return "tracer"


def label(run):
    # B11's V3 is E45's: C7's sphere in Float32. The D4 twins of E68 and E73
    # share the name and are marked apart.
    if run.startswith("g2_v2_sphere"):
        return "V2"
    if run == "v3_sphere_float32":
        return "V3"
    if run.startswith("v3_"):
        return "V3 (D4 twin)"
    return ""


runs = sorted(
    os.path.basename(os.path.dirname(os.path.dirname(p)))
    for p in glob.glob(os.path.join(ROOT, "*", "output_0*", "energy_source_tag_closure.csv"))
)
runs = sorted(set(runs))
print(f"# U2's calibration, G4.5. Output root: {ROOT}")
print("run | B11 | transport | length, h | max gross_relative | gross/Θ at the end | scale")
per_transport = {}
for run in runs:
    closure = od4.table(run, "closure")
    if not closure or len(closure) < 2:
        continue
    t_end = closure[-1]["time"]
    worst = max(r["gross_relative"] for r in closure)
    kind = transport(run)
    tx = od4.throughput_exact(run, 0.0, t_end)
    scale, over = "—", None
    if tx:
        over, scale = closure[-1]["gross_residual"] / tx, "Θx"
    else:
        ti, used, _ = od4.throughput_interim(run, 0.0, t_end)
        if ti:
            over, scale = closure[-1]["gross_residual"] / ti, "Θi (estimate)"
    print(f"{run} | {label(run)} | {kind} | {t_end / 3600:.1f} | {worst:.3g} | "
          + ("—" if over is None else f"{over:.3g}") + f" | {scale}")
    if run in DEFECTS:
        continue
    entry = per_transport.setdefault(kind, {"worst": (0.0, ""), "over": (0.0, ""),
                                            "B11": (0.0, "")})
    if worst > entry["worst"][0]:
        entry["worst"] = (worst, run)
    if over is not None and over > entry["over"][0]:
        entry["over"] = (over, run)
    if label(run) in ("V2", "V3") and worst > entry["B11"][0]:
        entry["B11"] = (worst, run)

print()
print("## Left out of the calibration")
for run, why in DEFECTS.items():
    if run in runs:
        print(f"   {run}: {why}")
print()
print("## Per transport, over the healthy runs")
for kind, entry in sorted(per_transport.items()):
    default = DEFAULTS.get(kind)
    worst, run = entry["worst"]
    b11, b11_run = entry["B11"]
    over, over_run = entry["over"]
    print(f"   {kind}: largest gross_relative {worst:.3g} ({run}); "
          f"default tolerance {default}, margin {default / worst:.3g}" if default and worst
          else f"   {kind}: no healthy run")
    if b11:
        print(f"      V2 and V3 alone: largest {b11:.3g} ({b11_run}), margin {default / b11:.3g}")
    if over:
        print(f"      gross over the throughput since the start: largest {over:.3g} ({over_run})")
