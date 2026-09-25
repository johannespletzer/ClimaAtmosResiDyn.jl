"""WP4c's entry gate: score the probe's output against design/WP4C_GATE.md.

    python3 wp4c_gate_score.py GATE_DIR [--startup SECONDS] [--untagged DIR]

GATE_DIR holds `<case>_gate.csv` and `<case>_gate_profiles.csv` from
`wp4c_gate_probe.jl`, for one or both cases. The window's boundary is
`--startup`, or else read from the untagged run's 10-minute `rhoa` and `hus`
by OD2's rule (`--untagged`, by default W25's untagged 30-level run). Per case
and operator it prints, over established flow and, beside it, over startup:
  - the source, the actual growth and the remainder, net and gross, per day,
    over the water `W` at the window's end, and growth over source;
  - part 1: the remainder against 0.02% of `W` a day;
  - part 2a: the follower's moved gross, on minus off, against 0.5% a day;
  - part 2b: per tag, its own follower ledger, on minus off, against 2% of the
    tag's inventory over the window;
  - part 3 (`vdiff`): per tag, `D` at the end against the reference's profile,
    L1 against 2% and L∞ against 5%, or a small tag's absolute bound.
The thresholds are the design note's section 4. Nothing here is tuned after
the runs.
"""
import argparse
import csv
import glob
import os

import numpy as np

PART1 = 2e-4
PART2A = 5e-3
PART2B = 0.02
L1_MAX, LINF_MAX = 0.02, 0.05
SMALL_SHARE, SMALL_ABS = 0.01, 2e-4

parser = argparse.ArgumentParser()
parser.add_argument("gate_dir")
parser.add_argument("--startup", type=float, default=None)
parser.add_argument(
    "--untagged",
    default=os.path.join(
        os.environ.get("SCRATCH", ""),
        "tag_closure/output/w25i_d4w_untagged_z30_c/output_0000",
    ),
)
args = parser.parse_args()


def read_rows(path):
    with open(path) as f:
        reader = csv.DictReader(f)
        return [{k: float(v) for k, v in row.items()} for row in reader]


def od2_boundary(untagged):
    """OD2: startup ends at the first output after which the domain-mean
    tendency of ∫ρq_tot stays below 10% of its largest value in the first 6
    hours for three outputs in a row."""
    import netCDF4 as nc

    def read(var):
        (path,) = glob.glob(os.path.join(untagged, f"{var}_10m_inst.nc"))
        with nc.Dataset(path) as d:
            values = np.asarray(d[var][:])
            # The column output is stored (z, time). Put time first, as the
            # rest assumes; a plain reshape would scramble levels and times.
            if d[var].dimensions[0] != "time":
                values = np.moveaxis(values, d[var].dimensions.index("time"), 0)
            return np.asarray(d["time"][:]), values.reshape(len(d["time"]), -1)

    t, rho = read("rhoa")
    _, hus = read("hus")
    water = (rho * hus).sum(axis=1)  # uniform levels, so the weight cancels
    tendency = np.abs(np.diff(water) / np.diff(t))
    peak = tendency[t[1:] <= 6 * 3600].max()
    below = tendency < 0.1 * peak
    for n in range(len(below) - 2):
        if below[n] and below[n + 1] and below[n + 2]:
            return t[n]
    return None


startup = args.startup
if startup is None:
    startup = od2_boundary(args.untagged)
    print(f"startup ends at {startup} s (OD2's rule, from {args.untagged})")
else:
    print(f"startup ends at {startup} s (given)")

for path in sorted(glob.glob(os.path.join(args.gate_dir, "*_gate.csv"))):
    case = os.path.basename(path)[: -len("_gate.csv")]
    rows = read_rows(path)
    profiles = read_rows(os.path.join(args.gate_dir, f"{case}_gate_profiles.csv"))
    header = list(rows[0].keys())
    operators = [c[: -len("_source_net")] for c in header if c.endswith("_source_net")]
    dt = rows[1]["t_seconds"] - rows[0]["t_seconds"]
    J = np.array([p["J"] for p in profiles])
    rho = np.array([p["rho"] for p in profiles])
    tags = [c[: -len("_final")] for c in profiles[0] if c.endswith("_final")]
    inventory = {t: float(np.sum(np.array([p[f"{t}_final"] for p in profiles]) * J)) for t in tags}
    print(f"\n== {case}: {len(rows)} steps, operators {operators}")
    for label, keep in (
        ("established flow", lambda r: r["t_seconds"] > startup),
        ("startup (not scored)", lambda r: r["t_seconds"] <= startup),
    ):
        kept = [r for r in rows if keep(r)]
        if not kept:
            continue
        W = kept[-1]["water"]
        days = len(kept) * dt / 86400
        per_day = lambda col: sum(r[col] for r in kept) / W / days
        print(f"-- {label}: {len(kept)} steps, {days:.3f} days, W = {W:.6g} kg")
        for o in operators:
            src_n, src_g = per_day(f"{o}_source_net"), per_day(f"{o}_source_gross")
            gro_n, gro_g = per_day(f"{o}_growth_net"), per_day(f"{o}_growth_gross")
            rem_n, rem_g = per_day(f"{o}_remainder_net"), per_day(f"{o}_remainder_gross")
            print(f"   {o}: source {src_n:+.3e} (gross {src_g:.3e}), growth {gro_n:+.3e} "
                  f"(gross {gro_g:.3e}), remainder {rem_n:+.3e} (gross {rem_g:.3e}) of W a day")
            if np.isfinite(src_g) and src_g > 0:
                print(f"      growth over source, gross: {gro_g / src_g:.3f}")
            if not label.startswith("established"):
                continue
            part1 = max(abs(rem_n), rem_g) > PART1
            print(f"      part 1 (remainder > {PART1:g} of W a day): {'holds' if part1 else 'no'}")
            moved = f"{o}_ledger_q_tag_inc_moved_gross"
            part2a = moved in header and per_day(moved) > PART2A
            if moved in header:
                print(f"      part 2a (follower's moved, gross {per_day(moved):.3e} > {PART2A:g}): "
                      f"{'holds' if part2a else 'no'}")
            part2b = False
            for t in tags:
                name = t.replace("ρq_tag_", "")
                col = f"{o}_ledger_q_tag_led_inc_{name}_gross"
                if col not in header or inventory[t] == 0:
                    continue
                fraction = sum(r[col] for r in kept) / abs(inventory[t])
                part2b |= fraction > PART2B
                print(f"      part 2b, {name}: {fraction:.3e} of its inventory over the window")
            print(f"      part 2b (> {PART2B:g} for any tag): {'holds' if part2b else 'no'}")
            part3 = False
            if o == "vdiff":
                partition_total = sum(abs(inventory[t]) for t in tags)
                total_water = float(np.sum(np.array([p["rho_q_tot"] for p in profiles]) * J))
                for t in tags:
                    D = np.array([p[f"{t}_D_vdiff"] for p in profiles])
                    q = np.array([p[f"{t}_final"] for p in profiles])
                    l1 = np.sum(np.abs(D) * J) / max(np.sum(np.abs(q) * J), 1e-300)
                    linf = np.max(np.abs(D / rho)) / max(np.max(np.abs(q / rho)), 1e-300)
                    small = abs(inventory[t]) < SMALL_SHARE * partition_total
                    if small:
                        absolute = np.sum(np.abs(D) * J) / total_water
                        exceeds = absolute > SMALL_ABS
                        print(f"      part 3, {t} (small): ∫|D|dz {absolute:.3e} of the water, "
                              f"L1 {l1:.3e}, L∞ {linf:.3e}: {'exceeds' if exceeds else 'within'}")
                    else:
                        exceeds = l1 > L1_MAX or linf > LINF_MAX
                        print(f"      part 3, {t}: L1 {l1:.3e}, L∞ {linf:.3e}: {'exceeds' if exceeds else 'within'}")
                    part3 |= exceeds
                print(f"      part 3: {'holds' if part3 else 'no'}")
            else:
                print("      part 3: not assessable for this operator")
            verdict = "retain" if (part1 or part2a or part2b or part3) else "defer"
            why = [n for n, v in (("1", part1), ("2a", part2a), ("2b", part2b), ("3", part3)) if v]
            print(f"      VERDICT {o}: {verdict}" + (f" (parts {', '.join(why)})" if why else ""))
