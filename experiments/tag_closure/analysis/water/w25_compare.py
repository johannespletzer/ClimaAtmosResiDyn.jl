"""W25's isolation (design/W25_ISOLATION.md): two readings the probes leave.

    python3 w25_compare.py window <untagged output_XXXX>
        OD2's startup window: the first output after which the parent's
        column-water tendency, over the output interval, stays below 10% of
        its largest value in the first 6 hours for three outputs in a row.
        Reads the 10-minute `rhoa` and `hus` of an untagged twin.

    python3 w25_compare.py first_step <probe outdir> <default run> <copies run>
        The first-step probes: per variant, each tag's L1 between the default
        mode and the copies at the probe's end,
        Σ ρΔz |q_default − q_copies| / Σ ρΔz |q_copies|.

It prints RESULT lines. It needs numpy and netCDF4 (python/3.12's user site).
"""

import csv
import glob
import os
import sys

import numpy as np


def column_water(run_dir):
    import netCDF4

    def read(short):
        paths = sorted(glob.glob(os.path.join(run_dir, f"{short}_10m_inst.nc")))
        if not paths:
            raise SystemExit(f"no 10-minute {short} in {run_dir}")
        with netCDF4.Dataset(paths[0]) as data:
            values = np.asarray(data[short][:], dtype=float)
            # Time first, found by name: a column writes (z, time).
            values = np.moveaxis(values, data[short].dimensions.index("time"), 0)
            time = np.asarray(data["time"][:], dtype=float)
            z = np.asarray(data["z"][:], dtype=float)
        return time, z, values.reshape(values.shape[0], -1)

    time, z, rho = read("rhoa")
    _, _, q = read("hus")
    dz = np.gradient(z) if z.size > 1 else np.ones(1)
    return time, (rho * q * dz).sum(axis=1)


def window(run_dir):
    time, water = column_water(run_dir)
    tendency = np.abs(np.diff(water)) / np.diff(time)
    ends = time[1:]
    first6 = ends <= 6 * 3600 + 1e-6
    level = 0.1 * tendency[first6].max()
    below = tendency < level
    for i in range(len(below) - 2):
        if below[i] and below[i + 1] and below[i + 2]:
            start = ends[i - 1] if i > 0 else time[0]
            print(f"RESULT probe=window run={run_dir} startup_end_seconds={start} level={level}")
            return start
    print(f"RESULT probe=window run={run_dir} startup_end_seconds=none level={level}")
    return None


def read_profile(path):
    with open(path) as handle:
        rows = list(csv.DictReader(handle))
    return {key: np.array([float(r[key]) for r in rows]) for key in rows[0]}


def first_step(outdir, default_run, copies_run):
    for variant in ("baseline", "converged_first", "tags_after_first"):
        d = read_profile(os.path.join(outdir, f"{default_run}_first_step_{variant}.csv"))
        c = read_profile(os.path.join(outdir, f"{copies_run}_first_step_{variant}.csv"))
        dz = np.gradient(d["z"])
        parity = np.array_equal(d["rho_q_tot"], c["rho_q_tot"])
        for tag in (k for k in d if k.startswith("ρq_tag_")):
            error = np.sum(np.abs(d[tag] - c[tag]) * dz)
            reference = np.sum(np.abs(c[tag]) * dz)
            share = np.sum(c[tag] * dz) / np.sum(c["rho_q_tot"] * dz)
            print(
                f"RESULT probe=first_step variant={variant} tag={tag} "
                f"L1={error / reference if reference > 0 else float('nan')} "
                f"share={share} parent_bit_for_bit={parity}"
            )


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "window":
        window(sys.argv[2])
    elif len(sys.argv) == 5 and sys.argv[1] == "first_step":
        first_step(*sys.argv[2:])
    else:
        raise SystemExit(__doc__)
