"""V5, restart equivalence, compared without Julia.

    module load netcdf-hdf5-all/4.7_hdf5-1.8-gcc13-serial python/3.12
    python3 experiments/tag_closure/analysis/v5_compare_h5.py \
        $SCRATCH/tag_closure/output/v5_c5_continuous/output_active \
        $SCRATCH/tag_closure/output/v5_c5_restarted/output_active

The same comparison as `v5_compare.jl`, for when Julia cannot run: the login
node's one core was taken by a timing measurement. `h5dump` writes each state
as raw little-endian doubles, and NumPy compares them bit for bit, component by
component. For each component it prints the largest difference at 24 h,
relative to the component's largest value, and relative to how much the
component changed over the second 12 hours of the continuous run. The closure
and audit tables are compared row by row after the restart, as text and as a
relative difference.

The component names are those of C5's column, in state order: `ρ`, the two
components of `uₕ`, `ρe_tot`, `ρq_tot`, six tags and two records. A run without
tags has the first five. Two states with different numbers of components, a run
with tags and its twin without, are compared on the components they share,
which are the model's own. A run without tags writes no closure tables, and
then they are not compared.
"""
import csv, os, subprocess, sys, tempfile

import numpy as np

NAMES = [
    "ρ", "uₕ_1", "uₕ_2", "ρe_tot", "ρq_tot",
    "ρe_src_strat", "ρe_src_tropo", "ρe_src_rad", "ρe_src_sfc",
    "ρe_src_new_strat", "ρe_src_new_tropo",
    "prc_e_radiation", "prc_e_surface_flux",
]
RESTART_TIME = 43200.0
# Columns that start over at a restart by design: the closure check takes its
# spin-up reference again after the restart, and the repair's ledger counts
# from the start of the run segment.
BY_DESIGN = {
    "residual_at_spin_up", "residual_since_spin_up", "relative_since_spin_up",
    "repair_moved", "repair_moved_relative",
}


def dump(path, dataset):
    with tempfile.NamedTemporaryFile(suffix=".bin") as out:
        subprocess.run(
            ["h5dump", "-d", dataset, "-b", "LE", "-o", out.name, path],
            check=True, stdout=subprocess.DEVNULL,
        )
        return np.fromfile(out.name, "<f8")


def components(path):
    """The cell state as one row per component."""
    listing = subprocess.run(
        ["h5ls", f"{path}/fields/Y/c"], check=True, capture_output=True,
        text=True,
    ).stdout
    dims = [int(d) for d in listing.split("{")[1].split("}")[0].split(",")]
    return dump(path, "/fields/Y/c").reshape(dims[1], -1)


def compare_states(continuous, restarted):
    end_c = os.path.join(continuous, "day1.0.hdf5")
    end_r = os.path.join(restarted, "day1.0.hdf5")
    mid_c = os.path.join(continuous, "day0.43200.hdf5")
    a, b, m = components(end_c), components(end_r), components(mid_c)
    shared = min(len(a), len(b))
    if len(a) != len(b):
        print(f"{len(a)} against {len(b)} components; the first {shared} are compared")
    identical = True
    for i, name in enumerate(NAMES[:shared]):
        same = np.array_equal(a[i].view("<u8"), b[i].view("<u8"))
        identical &= same
        diff = np.abs(a[i] - b[i]).max()
        scale = np.abs(a[i]).max()
        change = np.abs(a[i] - m[i]).max()
        print(
            f"Y.c.{name:18s} {'bit for bit' if same else 'differs':11s} "
            f"max diff {diff:.3e}  of max {diff / scale if scale else 0:.2e}  "
            f"of the 12 h change {diff / change if change else 0:.2e}"
        )
    fa = dump(end_c, "/fields/Y/f")
    fb = dump(end_r, "/fields/Y/f")
    same = np.array_equal(fa.view("<u8"), fb.view("<u8"))
    identical &= same
    print(
        f"Y.f.u₃{'':15s} {'bit for bit' if same else 'differs':11s} "
        f"max diff {np.abs(fa - fb).max():.3e}  of max "
        f"{np.abs(fa - fb).max() / np.abs(fa).max():.2e}"
    )
    return identical


def compare_table(name, continuous, restarted):
    def load(directory):
        rows = csv.DictReader(open(os.path.join(directory, name)))
        return {float(r["time"]): r for r in rows}

    if not all(os.path.isfile(os.path.join(d, name)) for d in (continuous, restarted)):
        print(f"{name}: not in both directories, not compared")
        return
    a, b = load(continuous), load(restarted)
    times = sorted(t for t in b if t > RESTART_TIME)
    print(f"{name}: {len(times)} rows after the restart")
    if RESTART_TIME in a and RESTART_TIME in b:
        differing = [
            c for c in a[RESTART_TIME]
            if c not in BY_DESIGN and a[RESTART_TIME][c] != b[RESTART_TIME][c]
        ]
        print(f"  row at the restart, t = {RESTART_TIME:.0f} s: " + (
            "same text in every column but those that start over"
            if not differing else "DIFFERS in " + ", ".join(differing)))
    for column in a[times[0]]:
        if column == "time":
            continue
        if column in BY_DESIGN:
            print(f"  {column:28s} starts over at a restart, not compared")
            continue
        if all(a[t][column] == b[t][column] for t in times):
            print(f"  {column:28s} same text")
            continue
        worst = 0.0
        for t in times:
            x, y = float(a[t][column]), float(b[t][column])
            if x != x and y != y:
                continue
            worst = max(worst, abs(x - y) / max(abs(x), 1e-300))
        print(f"  {column:28s} largest relative difference {worst:.2e}")


def main(continuous, restarted):
    print(f"continuous: {continuous}\nrestarted:  {restarted}")
    identical = compare_states(continuous, restarted)
    compare_table("energy_source_tag_closure.csv", continuous, restarted)
    compare_table("energy_source_tag_audit.csv", continuous, restarted)
    print("states at 24 h:", "bit for bit" if identical else "NOT bit for bit")
    return identical


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(0 if main(sys.argv[1], sys.argv[2]) else 1)
