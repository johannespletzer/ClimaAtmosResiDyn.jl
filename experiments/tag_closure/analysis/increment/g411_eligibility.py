"""G4.1 and G4.11: the energy copies' eligibility as a comparator on D4, with
and without their mirrors of mseʲ (design/ENERGY_COPY_MIRRORS.md, section 5).

    python3 g411_eligibility.py [OUTPUT_ROOT]
    G411_PREFIX=g411x python3 g411_eligibility.py   # E83's rerun

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output, with one directory per
run, `<job_id>/output_0000`, for the five `g411_d4_*` runs. It prints:
  - the window: startup ends where the domain-mean tendency of the partitioned
    total (the closure CSV's `total`, hourly) stays below 10% of its largest
    value in the first 6 hours for three outputs in a row (OD2's rule, on the
    offset total, which is what the tags partition);
  - the scale: the window's gross source throughput (OD4). Exact from the
    audit's `source_throughput` where the run has it (the per-tag source
    ledgers, design/GROSS_ACCUMULATORS.md section 11). Otherwise the interim
    the owner set (2026-09-25): the process records of the four source
    processes, whose hourly samples are net within each hour. It was taken as
    a lower bound; E84 found it 6% above the exact throughput on D4, so it is
    an estimate, and so is every percentage on it. The script says which;
  - the copies' eligibility under OD3's comparator rows, each run with copies:
    own residual (the closure's gross over the window) at most 0.02% of the
    throughput; repair (the audit's `repair_moved` over the window) at most
    0.20% a day of it; refinement: the dt 60 s twin's repair per day at most
    1.1 times dt 120 s's;
  - default against copies per tag at 24 h, L1 at most 2% and L∞ at most 5%,
    or a small tag's absolute bound, where the copies are eligible;
  - `e_src_copy_res`, where the run wrote it;
  - parity: every model field of each tagged run against the untagged twin,
    bit for bit.
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
SOURCES = ("radiation", "surface_flux", "subsidence", "microphysics")
TAGS = ("strat", "tropo", "rad", "sfc", "sub", "mp", "new_strat", "new_tropo")
PARTITION = ("strat", "tropo")
OWN_RESIDUAL, REPAIR_PER_DAY, REFINEMENT = 2e-4, 2e-3, 1.1
L1_MAX, LINF_MAX, SMALL_SHARE, SMALL_ABS = 0.02, 0.05, 0.01, 2e-4


# The run set: `g411` for the first submission, `g411x` for E83's rerun with
# OD4's exact throughput (the same configs with the per-tag ledgers on). The
# labels below keep the `g411_d4_*` names.
PREFIX = os.environ.get("G411_PREFIX", "g411")


def out_dir(job):
    return os.path.join(ROOT, job.replace("g411_", PREFIX + "_", 1), "output_0000")


def read_csv(job, name):
    path = os.path.join(out_dir(job), name)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def at(rows, time, column):
    return next(r[column] for r in rows if abs(r["time"] - time) < 1e-6)


def read_nc(job, var):
    paths = glob.glob(os.path.join(out_dir(job), f"{var}_1h_inst.nc"))
    if not paths:
        return None, None, None
    with nc.Dataset(paths[0]) as d:
        t = np.asarray(d["time"][:])
        # Time first, whatever the file's order (a column writes (z, time)).
        values = np.moveaxis(np.asarray(d[var][:]), d[var].dimensions.index("time"), 0)
        values = values.reshape(len(t), -1)
        z = np.asarray(d["z"][:]) if "z" in d.variables else None
    return t, values, z


def layer_thickness(z):
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    return np.diff(faces)


def startup_end(closure):
    t = np.array([r["time"] for r in closure])
    total = np.array([r["total"] for r in closure])
    tendency = np.abs(np.diff(total) / np.diff(t))
    peak = tendency[t[1:] <= 6 * 3600].max()
    below = tendency < 0.1 * peak
    for n in range(len(below) - 2):
        if below[n] and below[n + 1] and below[n + 2]:
            return t[n]
    return None


def throughput(job, t0, t1):
    """OD4's scale over (t0, t1]. The exact accumulator where the run has it:
    the audit's `source_throughput`, the partition's per-step gross of each
    tag's source ledger (design/GROSS_ACCUMULATORS.md, section 11). Otherwise
    the interim: Σ over hourly intervals and the four source records of
    ∫ρ|Δe_prc|dz, a lower bound, so every percentage on it is an upper bound."""
    audit = read_csv(job, "energy_source_tag_audit.csv")
    if audit and "source_throughput" in audit[0]:
        exact = at(audit, t1, "source_throughput") - at(audit, t0, "source_throughput")
        EXACT[job] = True
        return exact
    EXACT[job] = False
    t, rho, z = read_nc(job, "rhoa")
    dz = layer_thickness(z)
    total = 0.0
    for process in SOURCES:
        tp, e, _ = read_nc(job, f"e_prc_{process}")
        if e is None:
            continue
        for k in range(1, len(tp)):
            if t0 < tp[k] <= t1 + 1e-6:
                total += np.sum(rho[k] * np.abs(e[k] - e[k - 1]) * dz)
    return total


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def parity(untagged, job):
    names = sorted(os.path.basename(f) for f in glob.glob(f"{out_dir(untagged)}/*.nc"))
    differ = []
    for f in names:
        var = f.rsplit("_", 2)[0]
        other = os.path.join(out_dir(job), f)
        if not os.path.exists(other):
            differ.append(f"{var} (missing)")
            continue
        with nc.Dataset(f"{out_dir(untagged)}/{f}") as da, nc.Dataset(other) as db:
            a, b = np.asarray(da[var][:]), np.asarray(db[var][:])
        if not (a.shape == b.shape and np.array_equal(bits(a), bits(b))):
            differ.append(var)
    if not names:
        return "no fields"
    return f"{len(names)} fields: " + ("bit for bit" if not differ else "DIFFERS " + ", ".join(differ))


EXACT = {}
copies_runs = ("g411_d4_copies", "g411_d4_copies_before", "g411_d4_copies_dt60")
closure = read_csv("g411_d4_copies", "energy_source_tag_closure.csv")
t0 = startup_end(closure) if closure else None
t1 = 86400.0
if closure and t0 is None:
    # The rule finds no end where the total's tendency never falls to a tenth
    # of its early peak, as a steadily heated or cooled column's may not. Then
    # OD2's table's expectation for D4 holds: the first hour.
    t0 = 3600.0
    print("window: OD2's rule finds no end of startup; OD2's table's first hour is used")
print(f"window: startup ends at {t0} s; scored to {t1} s")

eligible = {}
repair_per_day = {}
for job in copies_runs + ("g411_d4_default",):
    closure = read_csv(job, "energy_source_tag_closure.csv")
    audit = read_csv(job, "energy_source_tag_audit.csv")
    if closure is None or audit is None or t0 is None:
        print(f"== {job}: no output")
        continue
    scale = throughput(job, t0, t1)
    days = (t1 - t0) / 86400
    own = (at(closure, t1, "gross_residual") - at(closure, t0, "gross_residual")) / scale
    repair = (at(audit, t1, "repair_moved") - at(audit, t0, "repair_moved")) / scale / days
    repair_per_day[job] = repair
    kind = "exact (the audit's source_throughput)" if EXACT[job] else "estimate (process records; not a bound, E84): percentages are estimates"
    print(f"== {job}: throughput {scale:.4e} J/m² over the window, {kind}")
    print(f"   own residual {own:.3e} of it (at most {OWN_RESIDUAL:g}); "
          f"repair {repair:.3e} a day (at most {REPAIR_PER_DAY:g})")
    if job in copies_runs:
        eligible[job] = own <= OWN_RESIDUAL and repair <= REPAIR_PER_DAY
    t, res, z = read_nc(job, "e_src_copy_res")
    if res is not None:
        _, rho, _ = read_nc(job, "rhoa")
        dz = layer_thickness(z)
        column = np.array([np.sum(rho[k] * np.abs(res[k]) * dz) for k in range(len(t))])
        print(f"   e_src_copy_res: ∫ρ|res|dz up to {column.max():.4e} J/m², "
              f"mean {column.mean():.4e}, over the throughput {column.max() / scale:.3e}")
    print(f"   parity against g411_d4_untagged: {parity('g411_d4_untagged', job)}")

if "g411_d4_copies" in repair_per_day and "g411_d4_copies_dt60" in repair_per_day:
    ratio = repair_per_day["g411_d4_copies_dt60"] / max(repair_per_day["g411_d4_copies"], 1e-300)
    ok = ratio <= REFINEMENT
    print(f"== refinement: repair per day at dt 60 s over dt 120 s = {ratio:.3f} (at most {REFINEMENT})")
    eligible["g411_d4_copies"] = eligible.get("g411_d4_copies", False) and ok

for job in ("g411_d4_copies", "g411_d4_copies_before"):
    if job not in eligible:
        continue
    print(f"== default against {job} per tag at 24 h: "
          + ("the copies are eligible" if eligible[job] else "comparator not eligible; reported, not scored"))
    _, rho, z = read_nc(job, "rhoa")
    if rho is None:
        continue
    dz = layer_thickness(z)
    scale = throughput(job, t0, t1)
    partition_total = sum(np.sum(rho[-1] * read_nc(job, f"e_src_{n}")[1][-1] * dz) for n in PARTITION)
    for name in TAGS:
        _, ref, _ = read_nc(job, f"e_src_{name}")
        _, dflt, _ = read_nc("g411_d4_default", f"e_src_{name}")
        if ref is None or dflt is None:
            continue
        q_ref, q = ref[-1], dflt[-1]
        l1 = np.sum(rho[-1] * np.abs(q - q_ref) * dz) / max(np.sum(rho[-1] * np.abs(q_ref) * dz), 1e-300)
        linf = np.max(np.abs(q - q_ref)) / max(np.max(np.abs(q_ref)), 1e-300)
        share = np.sum(rho[-1] * q_ref * dz) / partition_total
        if abs(share) < SMALL_SHARE:
            absolute = np.sum(rho[-1] * np.abs(q - q_ref) * dz) / scale
            verdict = "within" if absolute <= SMALL_ABS else "exceeds"
            print(f"   {name} (small, share {share:.3e}): ∫ρ|Δe|dz {absolute:.3e} of the throughput: {verdict}")
        else:
            verdict = "within" if (l1 <= L1_MAX and linf <= LINF_MAX) else "exceeds"
            print(f"   {name}: L1 {l1:.3e}, L∞ {linf:.3e}: {verdict}")
