"""G4.5: score the closure row of the acceptance contract from a run's tables.

    python3 closure_verdict.py water <output_XXXX> [--t1 86400]
    python3 closure_verdict.py energy_source <output_XXXX> [--t0 3600] [--t1 86400]

The model's closure checks warn, mark rows void, or end a run where a user
asks. None of that is acceptance (design/CLOSURE_LEVELS.md). Acceptance is
scored here, afterwards, from the closure and audit tables, against the OD3
thresholds recorded in ROADMAP.md, over a window fixed in advance.

  - water (OD3, "Closure, water", set before rev. 2): the gross at 24 h at
    most 0.2% of `∫ρq_tot`, and no more added in the second 12 h than in the
    first;
  - energy_source (OD3, "Closure, energy", approved 2026-09-24, in OD4 units):
    the gross residual's change over the window at most 0.2% of the window's
    gross source throughput. The throughput is the exact accumulator Θx, from
    the closure table's `source_throughput` or the audit's. Without Θx the
    records' estimate Θi is used (E84: an estimate, not a bound), and a
    verdict within 10% of the threshold on it is *not assessable*.

It prints one line, `closure: pass|fail|not assessable`, with the numbers
behind it, and exits 0. It refuses a run without a closure table, or one whose
table does not reach the window's end.
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "increment"))

WATER_GROSS = 2e-3
ENERGY_GROSS = 2e-3
MARGIN = 0.10


def read_table(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def at(rows, t):
    row = min(rows, key=lambda r: abs(r["time"] - t))
    if abs(row["time"] - t) > 1e-6:
        raise SystemExit(f"closure_verdict: no row at t = {t} s (nearest {row['time']} s)")
    return row


def water(run_dir, t1):
    closure = read_table(os.path.join(run_dir, "water_tag_closure.csv"))
    if not closure:
        raise SystemExit("closure_verdict: no water_tag_closure.csv")
    end, mid, start = at(closure, t1), at(closure, t1 / 2), at(closure, 0.0)
    relative = end["gross_relative"]
    first = mid["gross_residual"] - start["gross_residual"]
    second = end["gross_residual"] - mid["gross_residual"]
    ok = relative <= WATER_GROSS and second <= first
    return ("pass" if ok else "fail",
            f"gross {relative:.3e} of ∫ρq_tot at {t1:.0f} s (at most {WATER_GROSS:g}); "
            f"added {first:.3e} then {second:.3e} in the two halves")


def throughput(run_dir, closure, audit, t0, t1):
    for rows in (closure, audit):
        if rows and "source_throughput" in rows[0]:
            return at(rows, t1)["source_throughput"] - at(rows, t0)["source_throughput"], "Θx"
    import od4_restate
    od4_restate.ROOT = os.path.dirname(os.path.dirname(os.path.abspath(run_dir)))
    run = os.path.basename(os.path.dirname(os.path.abspath(run_dir)))
    index = int(os.path.basename(os.path.abspath(run_dir)).split("_")[-1])
    value, used, _ = od4_restate.throughput_interim(run, t0, t1, index)
    if not value:
        return None, "none"
    return value, "Θi (estimate)"


def energy_source(run_dir, t0, t1):
    closure = read_table(os.path.join(run_dir, "energy_source_tag_closure.csv"))
    audit = read_table(os.path.join(run_dir, "energy_source_tag_audit.csv"))
    if not closure:
        raise SystemExit("closure_verdict: no energy_source_tag_closure.csv")
    grown = at(closure, t1)["gross_residual"] - at(closure, t0)["gross_residual"]
    scale, kind = throughput(run_dir, closure, audit, t0, t1)
    if not scale:
        return ("not assessable",
                "no throughput: the run has neither the per-tag ledgers nor the process records")
    ratio = grown / scale
    detail = (f"gross grew {grown:.4e} over ({t0:.0f}, {t1:.0f}] s, "
              f"{ratio:.3e} of {kind} {scale:.4e} (at most {ENERGY_GROSS:g})")
    if kind != "Θx" and abs(ratio - ENERGY_GROSS) <= MARGIN * ENERGY_GROSS:
        return "not assessable", detail + "; within 10% of the threshold on the estimate: needs Θx"
    return ("pass" if ratio <= ENERGY_GROSS else "fail"), detail


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("family", choices=("water", "energy_source"))
    parser.add_argument("run_dir")
    parser.add_argument("--t0", type=float, default=3600.0,
                        help="the window's start, s; OD2's startup end (energy only)")
    parser.add_argument("--t1", type=float, default=86400.0, help="the window's end, s")
    args = parser.parse_args(argv)
    if os.path.basename(os.path.normpath(args.run_dir)) == "output_active":
        raise SystemExit("closure_verdict: give an explicit output_XXXX, not output_active")
    if args.family == "water":
        verdict, detail = water(args.run_dir, args.t1)
    else:
        verdict, detail = energy_source(args.run_dir, args.t0, args.t1)
    print(f"closure: {verdict}: {detail}")
    return verdict


if __name__ == "__main__":
    main()
