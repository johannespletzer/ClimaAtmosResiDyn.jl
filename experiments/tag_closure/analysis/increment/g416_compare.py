"""G4.16's validation: the energy source tags' sedimentation cross blocks.

    python3 g416_compare.py [OUTPUT_ROOT]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It holds one directory per
run, `<job_id>/output_0000`, for the nine runs of
design/ENERGY_SEDIMENTATION_CROSS_BLOCKS.md, section 6. For each case (the
explicit and the implicit hour, the D4 day) it prints:
  - the closure (net and gross, relative) at the last output, blocks on and
    off, and E80's or G4.15's value for reference;
  - the verdict against the bands pre-registered in section 6;
  - parity: every model field the untagged twin writes, against the on and
    the off run, bit for bit (bit patterns, so signed zeros count), at every
    output time; and every field the on and off runs both write, except the
    tags' own (`e_src_*`), on against off.
Nothing here is tuned after the runs. The bands are the design note's.
"""
import csv
import glob
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ["SCRATCH"], "tag_closure", "output"
)

# Section 6 of the design note. `reference` is the earlier measurement of the
# same case without the blocks (E80; G4.15's D4 day).
CASES = {
    "expl_n1": {"end": 3600.0, "reference": (1.5e-4, 2.1e-4)},
    "impl_n1": {"end": 3600.0, "reference": (-7.7e-7, 1.5e-6)},
    "d4": {"end": 86400.0, "reference": (9.5e-8, 9.2e-6)},
}
PASS_GROSS = 1e-7
PARTIAL_GROSS = 1e-6


def output_dir(job):
    return os.path.join(ROOT, job, "output_0000")


def closure_at(job, end):
    path = os.path.join(output_dir(job), "energy_source_tag_closure.csv")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        rows = [r for r in csv.DictReader(f)]
    rows = [r for r in rows if abs(float(r["time"]) - end) < 1e-6]
    if not rows:
        return None
    r = rows[-1]
    return float(r["relative"]), float(r["gross_relative"])


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def variable(path):
    # `<short_name>_<period>_<reduction>.nc`
    return os.path.basename(path).rsplit("_", 2)[0]


def parity(a_job, b_job, skip_tags):
    a_dir, b_dir = output_dir(a_job), output_dir(b_job)
    if not (os.path.isdir(a_dir) and os.path.isdir(b_dir)):
        return "missing"
    a_files = {os.path.basename(f) for f in glob.glob(f"{a_dir}/*.nc")}
    b_files = {os.path.basename(f) for f in glob.glob(f"{b_dir}/*.nc")}
    names = sorted(a_files & b_files)
    if skip_tags:
        names = [f for f in names if not variable(f).startswith("e_src_")]
    missing = sorted(a_files - b_files) if not skip_tags else []
    differ = []
    times = 0
    for f in names:
        var = variable(f)
        with nc.Dataset(f"{a_dir}/{f}") as da, nc.Dataset(f"{b_dir}/{f}") as db:
            a = np.asarray(da[var][:])
            b = np.asarray(db[var][:])
            ta = np.asarray(da["time"][:])
            tb = np.asarray(db["time"][:])
        times = max(times, len(ta))
        same_time = ta.shape == tb.shape and np.array_equal(bits(ta), bits(tb))
        same = a.shape == b.shape and a.dtype == b.dtype and np.array_equal(bits(a), bits(b))
        if not (same and same_time):
            gap = np.max(np.abs(a - b)) if a.shape == b.shape else "shape"
            differ.append(f"{var} (max |diff| {gap})")
    if not names:
        return "no fields in common"
    verdict = "bit for bit" if not differ and not missing else "DIFFERS"
    line = f"{len(names)} fields over {times} outputs: {verdict}"
    if missing:
        line += f"; missing in {b_job}: {missing}"
    if differ:
        line += "; " + ", ".join(differ)
    return line


def band(gross):
    if gross is None:
        return "no result"
    if gross <= PASS_GROSS:
        return "pass"
    if gross <= PARTIAL_GROSS:
        return "partial: decompose before any claim (section 6)"
    return "fail"


for case, spec in CASES.items():
    print(f"== {case}")
    on = closure_at(f"g416_{case}_on", spec["end"])
    off = closure_at(f"g416_{case}_off", spec["end"])
    ref_net, ref_gross = spec["reference"]
    print(f"   reference without blocks: net {ref_net:+.2e} gross {ref_gross:.2e}")
    for label, value in (("off", off), ("on", on)):
        if value is None:
            print(f"   {label:3s}: no closure at t = {spec['end']:.0f} s")
        else:
            print(f"   {label:3s}: net {value[0]:+.2e} gross {value[1]:.2e}")
    if case == "expl_n1":
        print(f"   V1 (on, gross <= {PASS_GROSS:g}): {band(on and on[1])}")
        if off is not None:
            close = abs(off[1] - ref_gross) <= 0.1 * ref_gross
            print(f"   control (off within 10% of E80's gross): {'yes' if close else 'NO'}")
    else:
        if on is not None and off is not None:
            no_worse = on[1] <= max(off[1], PASS_GROSS)
            print(f"   V2/V4 (on no worse than max(off, {PASS_GROSS:g})): {'yes' if no_worse else 'NO'}")
    untagged = f"g416_{case}_untagged"
    for label in ("on", "off"):
        print(f"   parity, untagged against {label}: {parity(untagged, f'g416_{case}_{label}', False)}")
    print(f"   parity, on against off (all but e_src_*): {parity(f'g416_{case}_on', f'g416_{case}_off', True)}")

expl_on = closure_at("g416_expl_n1_on", 3600.0)
impl_off = closure_at("g416_impl_n1_off", 3600.0)
if expl_on is not None and impl_off is not None:
    ok = expl_on[1] <= impl_off[1]
    print(f"== V3: the explicit hour with the blocks, gross {expl_on[1]:.2e}, "
          f"against the implicit hour without them, {impl_off[1]:.2e}: "
          f"{'no worse' if ok else 'WORSE'}")
