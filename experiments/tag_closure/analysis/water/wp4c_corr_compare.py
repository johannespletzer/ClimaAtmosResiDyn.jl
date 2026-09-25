"""WP4c's retained corrections: the validation's checks beside the gate score.

    python3 wp4c_corr_compare.py CORR_DIR [--startup 6600]

CORR_DIR holds the probe's output with `REFERENCE_OUTPUT=1`
(design/WP4C_CORRECTIONS.md, section 8): `<run>_gate.csv` and the reference's
diagnostics in `<run>_reference/output_0000/`. For each case it prints:
  - criterion 3, parity: every parent field the reference writes against W25's
    untagged twin, bit for bit at every output;
  - criterion 2, the reference's `q_tag_res` gross over the water at the end;
  - criterion 4, the ledgers: `∫q_tag_led_leaknet ρ dz` (and the copies'
    `upleaknet`) over the column's water at every output, and `leaknet`
    against the sum of the partition's own leak ledgers;
  - reported: the moved gross against W25's tagged run over the window, and
    the leak ledger's gross against the closed-form source in the gate CSV.
The gate's parts are scored by `wp4c_gate_score.py CORR_DIR --startup 6600`.
Nothing here is tuned after the runs. It exits 1 if a criterion fails or a
case has no output; parity is bit for bit and needs the twin to cover every
output time (fixed 2026-09-25, before V1 was recorded: it compared values
and passed with no common output time).
"""
import argparse
import csv
import glob
import os

import netCDF4 as nc
import numpy as np

SCRATCH = os.environ.get("SCRATCH", "")
UNTAGGED = os.path.join(SCRATCH, "tag_closure/output/w25i_d4w_untagged_z30_c/output_0000")
TAGGED = {
    "wp4c_corr_d4w_default": os.path.join(
        SCRATCH, "tag_closure/output/w25i_d4w_default_z30_c/output_0000"
    ),
}
DZ = 50.0  # 30 uniform levels over 1500 m
LEDGER_LIMIT = 1e-12
SUM_LIMIT = 1e-10

parser = argparse.ArgumentParser()
parser.add_argument("corr_dir")
parser.add_argument("--startup", type=float, default=6600.0)
args = parser.parse_args()


def read(directory, name):
    """A diagnostic as (time, z) or (time,), with its times in seconds."""
    (path,) = glob.glob(os.path.join(directory, f"{name}_1h_inst.nc"))
    with nc.Dataset(path) as d:
        var = d.variables[name]
        data = np.asarray(var[:], dtype=float)
        if "z" in var.dimensions:
            data = np.moveaxis(data, var.dimensions.index("time"), 0)
        return np.asarray(d.variables["time"][:], dtype=float), data


def column(directory, name, rho):
    """∫ρ·name dz per output, in kg m⁻²."""
    _, data = read(directory, name)
    return (data * rho).sum(axis=1) * DZ


def bits(a):
    return np.ascontiguousarray(a, dtype=np.float64).view(np.uint64)


def check_levels(directory):
    """DZ assumes 30 uniform levels of 50 m; stop if the output says otherwise."""
    (path,) = glob.glob(os.path.join(directory, "rhoa_1h_inst.nc"))
    with nc.Dataset(path) as d:
        z = np.asarray(d.variables["z"][:], dtype=float)
    if not np.allclose(z, DZ * (np.arange(len(z)) + 0.5)):
        raise SystemExit(f"FAIL: {directory} is not on uniform {DZ} m levels")


failures = []


def parent_names(directory):
    names = []
    for path in sorted(glob.glob(os.path.join(directory, "*_1h_inst.nc"))):
        name = os.path.basename(path)[: -len("_1h_inst.nc")]
        if not name.startswith("q_tag_"):
            names.append(name)
    return names


for reference in sorted(glob.glob(os.path.join(args.corr_dir, "*_reference/output_0000"))):
    run = os.path.basename(os.path.dirname(reference))[: -len("_reference")]
    print(f"== {run}")
    t, rho = read(reference, "rhoa")
    if len(t) == 0:
        print("  no output yet -> FAILS (not scored)")
        failures.append(f"{run}: no output")
        continue
    check_levels(reference)
    water = column(reference, "hus", rho)

    # Criterion 3: parity with the untagged twin, bit for bit, at every output
    # the reference wrote. The twin must have written each of those times; a
    # field compared at no time fails.
    mismatches, compared = [], 0
    for name in parent_names(reference):
        if not glob.glob(os.path.join(UNTAGGED, f"{name}_1h_inst.nc")):
            continue
        t_ref, a = read(reference, name)
        t_twin, b = read(UNTAGGED, name)
        n = len(t_ref)
        compared += 1
        if n == 0 or len(t_twin) < n or a.shape[1:] != b.shape[1:]:
            mismatches.append(f"{name} (times {n} against the twin's {len(t_twin)})")
        elif not (np.array_equal(bits(t_ref), bits(t_twin[:n])) and np.array_equal(bits(a), bits(b[:n]))):
            mismatches.append(name)
    holds = compared > 0 and not mismatches
    print(f"  criterion 3 (parity): {compared} fields against the untagged twin, bit for bit, "
          f"to {t[-1]/3600:.0f} h; mismatches: {mismatches or 'none'} -> {'holds' if holds else 'FAILS'}")
    if not holds:
        failures.append(f"{run}: parity")

    # Criterion 2: the partition's residual at the end.
    _, res = read(reference, "q_tag_res")
    gross = np.abs(res * rho).sum(axis=1) * DZ
    print(f"  criterion 2 (closure): q_tag_res gross at {t[-1]/3600:.0f} h = {gross[-1]/water[-1]:.3e} "
          f"of the water -> {'holds' if gross[-1] / water[-1] <= 2e-3 else 'FAILS'} (0.2% budget; part 1 in the gate score)")
    if not gross[-1] / water[-1] <= 2e-3:
        failures.append(f"{run}: closure")

    # Criterion 4: the ledgers.
    net = column(reference, "q_tag_led_leaknet", rho)
    worst = np.max(np.abs(net) / water)
    _, leaknet = read(reference, "q_tag_led_leaknet")
    _, tropo = read(reference, "q_tag_led_leak_tropo")
    _, strat = read(reference, "q_tag_led_leak_strat")
    scale = np.max(np.abs(leaknet))
    sum_gap = np.max(np.abs(leaknet - tropo - strat)) / scale if scale > 0 else np.nan
    holds = worst <= LEDGER_LIMIT and sum_gap <= SUM_LIMIT
    line = (f"  criterion 4 (ledgers): max |∫leaknet ρ dz| / water = {worst:.2e} (<= {LEDGER_LIMIT}); "
            f"leaknet against tropo + strat {sum_gap:.2e} (<= {SUM_LIMIT})")
    if glob.glob(os.path.join(reference, "q_tag_led_upleaknet_1h_inst.nc")):
        upworst = np.max(np.abs(column(reference, "q_tag_led_upleaknet", rho)) / water)
        holds = holds and upworst <= LEDGER_LIMIT
        line += f"; max |∫upleaknet dz| / water = {upworst:.2e}"
    print(line + f" -> {'holds' if holds else 'FAILS'}")
    if not holds:
        failures.append(f"{run}: ledgers")

    # Reported: the window's grosses per day over the water at the end.
    window = t >= args.startup
    first, last = np.argmax(window), len(t) - 1
    days = (t[last] - t[first]) / 86400
    per_day = lambda x: (x[last] - x[first]) / water[last] / days
    ledger_gross = per_day(column(reference, "q_tag_led_leaknet_gross", rho))
    gate_csv = os.path.join(args.corr_dir, f"{run}_gate.csv")
    if os.path.exists(gate_csv):
        with open(gate_csv) as f:
            rows = [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]
        in_window = [r for r in rows if t[first] < r["t_seconds"] <= t[last]]
        source = sum(r["vdiff_source_gross"] for r in in_window) / water[last] / days
        print(f"  reported: leaknet's gross {ledger_gross:.3e} of the water a day, closed-form source "
              f"{source:.3e}, ratio {ledger_gross / source:.3f} (expected within 10%)")
    else:
        print(f"  reported: leaknet's gross {ledger_gross:.3e} of the water a day (no gate CSV)")
    moved = per_day(column(reference, "q_tag_inc_moved_gross", rho))
    line = f"  reported: the reference's moved gross {moved:.3e} of the water a day"
    if run in TAGGED:
        t_w, rho_w = read(TAGGED[run], "rhoa")
        moved_w = column(TAGGED[run], "q_tag_inc_moved_gross", rho_w)
        water_w = column(TAGGED[run], "hus", rho_w)
        w_first, w_last = np.argmax(t_w >= t[first]), np.argmin(np.abs(t_w - t[last]))
        moved_w = (moved_w[w_last] - moved_w[w_first]) / water_w[w_last] / days
        line += f"; without the correction (W25) {moved_w:.3e}; fall {moved_w - moved:+.3e}"
    print(line + f", over {t[first]/3600:.1f} h to {t[last]/3600:.1f} h")

for f in failures:
    print("FAIL " + f)
raise SystemExit(1 if failures else 0)
