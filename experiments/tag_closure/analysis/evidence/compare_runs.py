"""G3 1.2: compare two tag-closure runs against each other, explicitly.

    python compare_runs.py --reference DIR --run DIR [--hours 1,6,12,24]
                            [--tags rad,sfc,...] [--parent ta,rhoa,...]
                            [--json PATH]

DIR must be an explicit `output_XXXX` directory (an absolute or relative
path); `output_active` and a bare run root are refused, because both can
silently point at a different run tomorrow. Replaces
`analysis/increment/tag_correctness.py`, which picked the latest `output_0*`
by glob, compared only the common-length prefix of `ta` and `rhoa`, took the
reference's time index for both runs without checking timestamps, and called
`np.array_equal` "bit for bit" although it does not see a signed-zero
difference. See `untapped-potential-assessment-extended.md`, "New insight D".

What it checks, in order, and every failure exits nonzero naming the
variable and the problem:
  (a) every requested variable's file exists in both runs (and `rhoa`, always
      needed for the weights);
  (b) `time` and `date` are exactly equal. If the runs have different
      lengths, this fails unless `--hours` was given on the command line and
      every requested hour is present in both at exactly `h*3600` s; then
      only the common-length prefix is compared, and a notice says so;
  (c) `z` is exactly equal (dimensions are found by name, never by position);
  (d) only the column geometry (dimensions `z` and `time`) is supported.

Two kinds of report follow, neither of which is a hard failure by itself:
  - parent-state parity: `ta`, `rhoa` and every other non-tag variable
    present in both runs, compared bit pattern by bit pattern (so a signed
    zero shows up), with the count of differing elements, the largest
    absolute and relative difference, how many of the differences are
    signed-zero-only, and whether plain `np.array_equal` would have called
    the pair equal;
  - per-tag, per-hour metrics, mass-weighted by the reference's own `rhoa`
    and the cell thicknesses rebuilt from the `z` centres. Where the
    reference is identically zero the ratio metrics are undefined and are
    reported as "ref zero", never as 0 or NaN.

`--json PATH` writes every number above, the resolved input paths, the
sha256 of every input file this run read, and the sha256 of this script.
"""
import argparse
import hashlib
import json
import re
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from netCDF4 import Dataset

OUTPUT_DIR_RE = re.compile(r"^output_\d{4}$")

# A tag's own e_src_<name> file is a headline number; the ledger entries
# (fix_*, inc_*, res) exist for the increment accounting, not the tags
# themselves, so they are excluded from the default tag set.
EXCLUDED_TAG_PREFIXES = ("fix_", "inc_")
EXCLUDED_TAG_NAMES = ("res",)

# Everything that is a tag, a process record or a gas tracer is excluded from
# the default parent-parity set; what is left is the model's own state.
EXCLUDED_PARENT_PREFIXES = ("e_src_", "e_prc_", "q_prc_", "e_tag_", "q_tag_", "q_gas_")


def die(message):
    """Fail loudly: name the problem and exit nonzero. Never fall back silently."""
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def resolve_output_dir(raw, label):
    """Require an explicit output_XXXX directory. Refuse output_active (which
    can point at a different run tomorrow) and a bare run root (which is not
    a run at all)."""
    given = Path(raw)
    name = given.name.rstrip("/") if given.name else given.parts[-1]
    if name == "output_active":
        die(
            f"--{label} refuses 'output_active' ({raw}); pass the explicit "
            "output_XXXX directory it currently points to"
        )
    if not OUTPUT_DIR_RE.match(name):
        die(
            f"--{label} must name an explicit output_XXXX directory, not "
            f"'{raw}' (its last path component is '{name}')"
        )
    if not given.exists():
        die(f"--{label} directory does not exist: {raw}")
    resolved = given.resolve()
    if not resolved.is_dir():
        die(f"--{label} is not a directory: {resolved}")
    return resolved


def list_var_names(directory):
    """Variable stems for every '<name>_1h_inst.nc' file directly in a directory."""
    return {p.name[: -len("_1h_inst.nc")] for p in directory.glob("*_1h_inst.nc")}


def discover_default_tags(ref_dir):
    """Every e_src_<name> in the reference, excluding the ledger entries."""
    tags = []
    for p in sorted(ref_dir.glob("e_src_*_1h_inst.nc")):
        name = p.name[len("e_src_") : -len("_1h_inst.nc")]
        if name.startswith(EXCLUDED_TAG_PREFIXES) or name in EXCLUDED_TAG_NAMES:
            continue
        tags.append(name)
    if not tags:
        die(f"reference has no e_src_<name> files under {ref_dir} to default the tag set from")
    return tags


def discover_default_parent(ref_dir, run_dir):
    """ta, rhoa, and every other variable present in both runs that is not a
    tag, a process record or a gas tracer."""
    common = list_var_names(ref_dir) & list_var_names(run_dir)
    others = {n for n in common if not n.startswith(EXCLUDED_PARENT_PREFIXES)}
    return sorted(others | {"ta", "rhoa"})


def require_file(directory, stem, label, file_hashes):
    """Check (a): the file must exist. Record its hash now so a later
    failure elsewhere still reports what this run actually read."""
    path = directory / f"{stem}_1h_inst.nc"
    if not path.is_file():
        die(f"{label} is missing '{stem}': no file at {path}")
    file_hashes[str(path)] = sha256_file(path)
    return path


class RunCoords:
    """One run's own time/date/z, fixed by the first file opened for it.
    Every later file for the same run is checked against these, so an
    internally inconsistent run directory is caught, not just a mismatch
    between the two runs."""

    def __init__(self, label):
        self.label = label
        self.time = None
        self.date = None
        self.z = None

    def check_or_set(self, time, date, z, source):
        if self.time is None:
            self.time, self.date, self.z = time, date, z
            return
        if not np.array_equal(self.time, time):
            die(f"{self.label}: '{source}' has a different time array than the run's other files")
        if not np.array_equal(self.date, date):
            die(f"{self.label}: '{source}' has a different date array than the run's other files")
        if not np.array_equal(self.z, z):
            die(f"{self.label}: '{source}' has a different z array than the run's other files")


def open_var(path, varname, label, coords, file_hashes):
    """Open one '<var>_1h_inst.nc' file and return its field as a plain
    (z, time) ndarray. Dimensions are matched by name, never by position, so
    a file that happens to write (time, z) is still read correctly, and a
    file with any other geometry (e.g. the sphere's columns) is refused."""
    file_hashes[str(path)] = sha256_file(path)
    with Dataset(path) as ds:
        ds.set_auto_mask(False)  # a plain ndarray, so a signed zero is not lost to masking
        for coord in ("z", "time", "date"):
            if coord not in ds.variables:
                die(f"{label}: '{path.name}' has no '{coord}' coordinate variable")
        if varname not in ds.variables:
            die(f"{label}: '{path.name}' has no variable '{varname}'")
        var = ds.variables[varname]
        dims = var.dimensions
        if set(dims) != {"z", "time"}:
            die(
                f"{label}: '{path.name}' variable '{varname}' has dimensions "
                f"{dims}; only the column geometry ('z','time') is supported "
                "(unsupported geometry)"
            )
        data = np.array(var[:])
        if dims != ("z", "time"):
            data = np.moveaxis(data, dims.index("z"), 0)  # canonical (z, time)
        time = np.array(ds.variables["time"][:])
        date = np.array(ds.variables["date"][:])
        z = np.array(ds.variables["z"][:])
    coords.check_or_set(time, date, z, path.name)
    return data


def check_time_and_z(ref_coords, run_coords, hours, hours_given):
    """Checks (b) and (c). Returns the hour -> time-index map and the number
    of leading times that were actually compared."""
    n_ref, n_run = len(ref_coords.time), len(run_coords.time)
    if n_ref == n_run:
        if not np.array_equal(ref_coords.time, run_coords.time):
            die("time: reference and run have the same length but disagree somewhere in the array")
        if not np.array_equal(ref_coords.date, run_coords.date):
            die("date: reference and run have the same length but disagree somewhere in the array")
        overlap = n_ref
    else:
        if not hours_given:
            die(
                f"time: reference has {n_ref} times, run has {n_run}; lengths "
                "differ and --hours was not given, so refusing to guess a prefix"
            )
        overlap = min(n_ref, n_run)
        if not np.array_equal(ref_coords.time[:overlap], run_coords.time[:overlap]):
            die(f"time: reference and run disagree within their common {overlap}-time prefix")
        if not np.array_equal(ref_coords.date[:overlap], run_coords.date[:overlap]):
            die(f"date: reference and run disagree within their common {overlap}-time prefix")
        print(
            f"NOTICE: reference has {n_ref} times, run has {n_run}; only the "
            f"common prefix of {overlap} times was compared (--hours given)"
        )

    if not np.array_equal(ref_coords.z, run_coords.z):
        die("z: reference and run coordinates differ")

    idx = {}
    for h in hours:
        target = h * 3600
        hits = np.nonzero(ref_coords.time[:overlap] == target)[0]
        if hits.size == 0:
            die(f"time: hour {h} (t={target}s) is not present in the compared range of {overlap} times")
        idx[h] = int(hits[0])
    return idx, overlap


def find_yaml_z_max(directory, file_hashes):
    """The grid's declared top face, from the run's own YAML copy. A flat
    top-level 'z_max: <value>' key; the config format has no nesting here."""
    ymls = sorted(directory.glob("*.yml"))
    if not ymls:
        print(f"NOTICE: no YAML file under {directory}; skipping the top-face check against z_max")
        return None
    if len(ymls) > 1:
        die(f"{directory} has more than one YAML file: {[p.name for p in ymls]}; ambiguous")
    path = ymls[0]
    file_hashes[str(path)] = sha256_file(path)
    for line in path.read_text().splitlines():
        m = re.match(r"^z_max:\s*(\S+)\s*$", line)
        if m:
            return float(m.group(1))
    print(f"NOTICE: '{path.name}' has no top-level 'z_max' key; skipping the top-face check")
    return None


def compute_faces_and_dz(z_centers, label):
    """Rebuild cell faces from centres: z_f[0] = 0, z_f[k+1] = 2 z_c[k] - z_f[k].
    A non-positive thickness means the centres are not a valid cell-centre
    sequence, which the caller must not silently paper over."""
    faces = np.empty(len(z_centers) + 1, dtype=np.float64)
    faces[0] = 0.0
    for k in range(len(z_centers)):
        faces[k + 1] = 2.0 * float(z_centers[k]) - faces[k]
    dz = np.diff(faces)
    bad = np.nonzero(dz <= 0)[0]
    if bad.size:
        die(f"{label}: non-positive cell thickness at level(s) {bad.tolist()} (dz={dz[bad].tolist()})")
    return faces, dz


def check_top_face(top_face, z_max):
    if z_max is None:
        return
    denom = abs(z_max) if z_max != 0 else 1.0
    rel = abs(top_face - z_max) / denom
    if rel > 1e-9:
        die(
            f"z: rebuilt top face {top_face} disagrees with the YAML's z_max "
            f"{z_max} (relative difference {rel:.3e} > 1e-9)"
        )


def bit_compare(a, b, name):
    """Compare two arrays bit pattern by bit pattern, so a signed-zero
    difference is not lost the way plain '==' loses it."""
    if a.shape != b.shape:
        die(f"{name}: shape mismatch, reference {a.shape} vs run {b.shape}")
    if a.dtype != b.dtype:
        die(f"{name}: dtype mismatch, reference {a.dtype} vs run {b.dtype}")
    utype = f"u{a.dtype.itemsize}"
    bits_a, bits_b = a.view(utype), b.view(utype)
    diff_mask = bits_a != bits_b
    n_diff = int(np.count_nonzero(diff_mask))
    would_array_equal = bool(np.array_equal(a, b, equal_nan=True))
    if n_diff == 0:
        return {
            "identical": True,
            "n_diff": 0,
            "n_total": int(a.size),
            "max_abs_diff": 0.0,
            "max_rel_diff": 0.0,
            "signed_zero_only": 0,
            "would_array_equal": would_array_equal,
        }
    af, bf = a.astype(np.float64), b.astype(np.float64)
    delta = np.abs(af - bf)
    max_abs_diff = float(np.max(delta))
    nonzero_ref = a != 0
    max_rel_diff = (
        float(np.max(delta[nonzero_ref] / np.abs(af[nonzero_ref]))) if np.any(nonzero_ref) else None
    )
    signed_zero_only = int(np.count_nonzero(diff_mask & (a == 0) & (b == 0)))
    return {
        "identical": False,
        "n_diff": n_diff,
        "n_total": int(a.size),
        "max_abs_diff": max_abs_diff,
        "max_rel_diff": max_rel_diff,
        "signed_zero_only": signed_zero_only,
        "would_array_equal": would_array_equal,
    }


def format_parity_line(name, result):
    if result["identical"]:
        return f"{name:10s} bitwise identical ({result['n_total']} elements)"
    if result["n_diff"] == result["signed_zero_only"]:
        tail = f"np.array_equal would say {'equal' if result['would_array_equal'] else 'not equal'}"
        return f"{name:10s} not bitwise, signed-zero-only ({result['n_diff']} of {result['n_total']} elements; {tail})"
    rel = "n/a (ref zero)" if result["max_rel_diff"] is None else f"{result['max_rel_diff']:.2e}"
    tail = f"np.array_equal would say {'equal' if result['would_array_equal'] else 'not equal'}"
    return (
        f"{name:10s} {result['n_diff']} of {result['n_total']} elements differ; "
        f"max|Δ|={result['max_abs_diff']:.4e}; max relative Δ={rel}; "
        f"{result['signed_zero_only']} signed-zero-only; {tail}"
    )


def tag_row_metrics(tag, hour, e_ref, e_run, w):
    """The five reported quantities for one tag at one hour. Where the
    reference is identically zero the ratio metrics have no defined value:
    report that fact, never a stray 0 or NaN."""
    integral_ref = float(np.sum(e_ref * w))
    integral_run = float(np.sum(e_run * w))
    delta = e_run - e_ref
    max_abs_error = float(np.max(np.abs(delta)))  # J/kg, well-defined regardless of ref
    abs_ref_weighted = float(np.sum(np.abs(e_ref) * w))
    max_abs_ref = float(np.max(np.abs(e_ref)))
    ref_zero = max_abs_ref == 0.0  # w_k > 0 everywhere, so this iff e_ref is all zero
    row = {
        "tag": tag,
        "hour": hour,
        "integral_ref": integral_ref,
        "integral_run": integral_run,
        "max_abs_error": max_abs_error,
        "ref_zero": ref_zero,
    }
    if ref_zero:
        row["run_zero"] = bool(np.all(e_run == 0))
        row["rel_integral_change"] = None
        row["L1_mass_weighted"] = None
        row["Linf_peak_normalized"] = None
    else:
        row["run_zero"] = False
        row["rel_integral_change"] = (integral_run - integral_ref) / integral_ref
        row["L1_mass_weighted"] = float(np.sum(np.abs(delta) * w) / abs_ref_weighted)
        row["Linf_peak_normalized"] = float(np.max(np.abs(delta)) / max_abs_ref)
    return row


def format_tag_row(row):
    tag, hour = row["tag"], row["hour"]
    if row["ref_zero"]:
        note = f"ref zero (run {'zero' if row['run_zero'] else 'nonzero'})"
        return (
            f"{tag:10s} {hour:4d}   {row['integral_ref']:10.4e}  {note:>28s} "
            f"{row['max_abs_error']:10.4e}"
        )
    return (
        f"{tag:10s} {hour:4d}   {row['integral_ref']:10.4e}  "
        f"{row['rel_integral_change']:+10.2e} {row['L1_mass_weighted']:9.2e} "
        f"{row['Linf_peak_normalized']:9.2e}  {row['max_abs_error']:10.4e}"
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--reference", required=True, help="explicit output_XXXX directory")
    parser.add_argument("--run", required=True, help="explicit output_XXXX directory")
    parser.add_argument(
        "--hours",
        default=None,
        help="comma-separated hours, default 1,6,12,24; also the opt-in to "
        "compare runs of different length (a common-length prefix)",
    )
    parser.add_argument(
        "--tags",
        default=None,
        help="comma-separated tag names; default every e_src_<name> in the "
        "reference, excluding the fix_/inc_/res ledger entries",
    )
    parser.add_argument(
        "--parent",
        default=None,
        help="comma-separated parent variable names; default ta, rhoa, and "
        "every other non-tag variable present in both runs",
    )
    parser.add_argument("--json", default=None, help="write the full report to this path")
    return parser.parse_args()


def main():
    args = parse_args()
    ref_dir = resolve_output_dir(args.reference, "reference")
    run_dir = resolve_output_dir(args.run, "run")
    print(f"reference: {ref_dir}")
    print(f"run:       {run_dir}")

    hours_given = args.hours is not None
    hours = [int(h) for h in (args.hours if hours_given else "1,6,12,24").split(",")]
    tags = [t.strip() for t in args.tags.split(",")] if args.tags else discover_default_tags(ref_dir)
    parent_vars = (
        [p.strip() for p in args.parent.split(",")]
        if args.parent
        else discover_default_parent(ref_dir, run_dir)
    )

    file_hashes = {}

    # Check (a): every requested file exists in both runs, plus rhoa, which
    # the weights need even if --parent leaves it out of the parity report.
    required_stems = sorted({f"e_src_{t}" for t in tags} | set(parent_vars) | {"rhoa"})
    for stem in required_stems:
        require_file(ref_dir, stem, "reference", file_hashes)
        require_file(run_dir, stem, "run", file_hashes)

    ref_coords = RunCoords("reference")
    run_coords = RunCoords("run")

    ref_rhoa = open_var(ref_dir / "rhoa_1h_inst.nc", "rhoa", "reference", ref_coords, file_hashes)
    run_rhoa = open_var(run_dir / "rhoa_1h_inst.nc", "rhoa", "run", run_coords, file_hashes)

    # Checks (b) and (c).
    idx_map, overlap = check_time_and_z(ref_coords, run_coords, hours, hours_given)

    z_max = find_yaml_z_max(ref_dir, file_hashes)
    faces, dz = compute_faces_and_dz(ref_coords.z, "reference")
    check_top_face(float(faces[-1]), z_max)

    print(
        f"\nWeights: w_k = rho_ref,k * dz_k, using the reference's rhoa at "
        f"each hour for both runs. z faces rebuilt from centres, top face "
        f"{faces[-1]:.3f} m"
        + (f" (YAML z_max {z_max:.3f} m)" if z_max is not None else " (no YAML z_max to check against)")
        + "."
    )

    # Parent-state parity: bitwise, so a signed zero is visible.
    print("\nParent parity (bitwise, dtype-width unsigned-int view):")
    parity = {}
    for name in parent_vars:
        a = open_var(ref_dir / f"{name}_1h_inst.nc", name, "reference", ref_coords, file_hashes)
        b = open_var(run_dir / f"{name}_1h_inst.nc", name, "run", run_coords, file_hashes)
        result = bit_compare(a[:, :overlap], b[:, :overlap], name)
        parity[name] = result
        print("  " + format_parity_line(name, result))

    # Per-tag, per-hour metrics.
    print(
        f"\n{'tag':10s} {'hour':>4s}   {'∫ref J/m²':>10s}  {'Δ∫/∫':>10s} {'L1':>9s} "
        f"{'L∞':>9s}  {'max|Δe| J/kg':>10s}"
    )
    tag_metrics = {}
    for tag in tags:
        stem = f"e_src_{tag}"
        e_ref_full = open_var(ref_dir / f"{stem}_1h_inst.nc", stem, "reference", ref_coords, file_hashes)
        e_run_full = open_var(run_dir / f"{stem}_1h_inst.nc", stem, "run", run_coords, file_hashes)
        tag_metrics[tag] = {}
        for h in hours:
            i = idx_map[h]
            w = ref_rhoa[:, i] * dz
            row = tag_row_metrics(tag, h, e_ref_full[:, i], e_run_full[:, i], w)
            tag_metrics[tag][h] = row
            print(format_tag_row(row))
        print()

    if args.json:
        report = {
            "resolved_paths": {"reference": str(ref_dir), "run": str(run_dir)},
            "hours": hours,
            "hours_given": hours_given,
            "tags": tags,
            "parent_vars": parent_vars,
            "time_check": {
                "n_reference_times": int(len(ref_coords.time)),
                "n_run_times": int(len(run_coords.time)),
                "overlap": int(overlap),
                "truncated": overlap != len(ref_coords.time) or overlap != len(run_coords.time),
            },
            "z_max_yaml": z_max,
            "z_top_face": float(faces[-1]),
            "weights": "w_k = rho_ref,k * dz_k, reference rhoa at each hour, both runs",
            "parent_parity": parity,
            "tag_metrics": {tag: {str(h): row for h, row in per_hour.items()} for tag, per_hour in tag_metrics.items()},
            "input_file_sha256": file_hashes,
            "script_sha256": sha256_file(Path(__file__).resolve()),
            "run_context": {
                "hostname": socket.gethostname(),
                "utc_time": datetime.now(timezone.utc).isoformat(),
                "command": " ".join(sys.argv),
            },
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True))
        print(f"json report: {Path(args.json).resolve()}")


if __name__ == "__main__":
    main()
