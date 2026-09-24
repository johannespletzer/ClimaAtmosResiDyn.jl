"""G3 1.2 / WP0: compare two tag-closure runs against each other, explicitly.

    python compare_runs.py --reference DIR --run DIR [--hours 1,6,12,24]
                            [--tags rad,sfc,...] [--parent ta,rhoa,...]
                            [--family water|energy] [--expect-parity]
                            [--allow-missing NAME ...] [--judge]
                            [--bitwise-tags]
                            [--copy-total NAME --copy-component-prefix PFX
                             --copy-rhoaup NAME --copy-arup NAME]
                            [--rain-tag-prefix PFX --rain-parent NAME
                             --snow-tag-prefix PFX --snow-parent NAME
                             --pr-tag-prefix PFX --pr-parent NAME]
                            [--ladder-share --ladder-integrals-only]
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
  (b) `time` and `date` are exactly equal, and their `units` attributes (the
      time epoch) agree. If the runs have different lengths, this fails
      unless `--hours` was given on the command line and every requested
      hour is present in both at exactly `h*3600` s; then only the
      common-length prefix is compared, and a notice says so;
  (c) `z` is exactly equal, and its `units` agree (dimensions are found by
      name, never by position);
  (d) the column geometry (dimensions `z`+`time`, or `time` alone for a
      surface field) is supported; anything else is refused;
  (e) every value read for a compared field is finite and is not the
      variable's own fill value (its `_FillValue`, or netCDF's default fill
      for its dtype) -- a run that blew up, or was cut short mid-write, is
      refused rather than silently producing a number that could pass a
      budget.

Two kinds of report follow. Parent-state parity is not a hard failure by
itself unless `--expect-parity` is given; per-tag metrics are always
reported, and `--judge` turns them into a pass/fail verdict against
G3_PLAN.md section 6.1's budgets (water family only):
  - parent-state parity: `ta`, `rhoa` and every other non-tag variable
    present in *either* run (a variable present in only one run is a hard
    failure, unless named with `--allow-missing`), compared bit pattern by
    bit pattern (so a signed zero shows up), with the count of differing
    elements, the largest absolute and relative difference, how many of the
    differences are signed-zero-only, and whether plain `np.array_equal`
    would have called the pair equal. `--expect-parity` makes any break a
    hard failure;
  - per-tag, per-hour metrics, mass-weighted by the reference's own `rhoa`
    and the cell thicknesses rebuilt from the `z` centres. Where the
    reference is identically zero the ratio metrics are undefined and are
    reported as "ref zero", never as 0 or NaN. The tag list, and whether a
    tag is a region or a source tag, comes from the run's own YAML
    (`energy_source_tags` or `water_tracers`), not from file names; the two
    runs' YAMLs must list the same tags.

`--json PATH` writes every number above, the resolved input paths, the
sha256 of every input file this run read, and the sha256 of this script,
with `allow_nan=False` (a non-finite number is refused before it gets here,
but this is the last line of defence against writing invalid JSON).
"""
import argparse
import hashlib
import json
import re
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from netCDF4 import Dataset, default_fillvals

OUTPUT_DIR_RE = re.compile(r"^output_\d{4}$")

# --- Field families (R1) ----------------------------------------------
# One table entry per tag family. Keeps the family-specific names in one
# place, so WP3 (copies) and WP4b (rain/snow/precipitation) add their real
# output names here once, instead of scattering prefixes through the file.
# "tag_yaml_key" names the merged-YAML block the tag list is read from (S5):
# a list of mappings, each with a "name" and either a "region" or a
# "source" key (the model's own region/source split, R2). "mode_key" is the
# YAML key that must read true in the reference and false in the run for a
# per-tag budget verdict (R6). "total_var" is the family's own total
# quantity, used for the share S and the closure budgets (R4, R7); energy
# has no such field, so --judge is water-only.
FAMILY_TABLES = {
    "energy": {
        "tag_var_prefix": "e_src_",
        "tag_yaml_key": "energy_source_tags",
        "residual_name": "res",
        "ledger_prefixes": ("fix_", "inc_"),
        "mode_key": "energy_source_tag_updraft_copy",
        "total_var": None,
        "unit": "J kg^-1",
        # excluded from the default parent-parity set: tags, process
        # records and vapour-share diagnostics, none of which are parent
        # state (S1). q_gas_ is NOT excluded: it is a passive tracer that
        # must be bit for bit, not a diagnostic.
        "excluded_parent_prefixes": ("e_src_", "e_prc_", "q_prc_", "e_tag_", "q_tag_", "qv_tag_", "pr_tag_", "prra_tag_", "prsn_tag_"),
    },
    "water": {
        "tag_var_prefix": "q_tag_",
        "tag_yaml_key": "water_tracers",
        "residual_name": "res",
        "ledger_prefixes": ("fix_", "upfix_"),
        "mode_key": "water_tag_updraft_copy",
        "total_var": "hus",
        "unit": "kg kg^-1",
        "excluded_parent_prefixes": ("e_src_", "e_prc_", "q_prc_", "e_tag_", "q_tag_", "qv_tag_", "pr_tag_", "prra_tag_", "prsn_tag_"),
    },
}

# R5: the budget table from G3_PLAN.md section 6.1, only the parts the
# review marks proposed are filled in here; see judge_tag_row's docstring
# for exactly which definitions are proposed.
JUDGE_HOURS = (1, 24)
JUDGE_BUDGETS = {
    24: {"region": {"L1": 0.02, "Linf": 0.05}, "source": {"L1": 0.02, "Linf": 0.05}},
    1: {"region": {"L1": 0.01, "Linf": 0.25}, "source": {"L1": 0.10, "Linf": 0.25}},
}
SMALL_TAG_SHARE = 0.01
SMALL_TAG_ABS_L1_FACTOR = 2e-4
CLOSURE_BUDGET_24H = 0.002

# S2: provenance.txt fields that must agree for a bitwise-parity claim.
MUST_MATCH_PROVENANCE_KEYS = ("machine", "ntasks")
# S2: YAML top-level keys allowed to differ between a paired reference and
# run without failing the pairing check. "toml" differs by construction
# (each run's own parameter file path) and is compared by content hash
# instead, not by this allowlist.
YAML_DIFF_ALLOWED_KEYS = {
    "energy_source_tag_updraft_copy",
    "water_tag_updraft_copy",
    "diagnostics",
    "output_dir",
    "toml",
}
# S2: booleans that break the bitwise-parity contract when on, per the
# fork's parity rule.
PARITY_BREAKING_YAML_FLAGS = ("use_krylov_method", "use_newton_rtol")

# --parity-only (criterion 3): a tagged run against its untagged twin. No
# family is known (the untagged twin has no tag block at all), so the
# tag-family output prefixes are a fixed, family-agnostic list rather than
# FAMILY_TABLES's per-family one. Covers both families' tags, ledgers and
# process records; q_tag_res and q_tag_fix_* are covered by the plain
# "q_tag_" prefix, not listed separately.
PARITY_ONLY_EXCLUDED_PREFIXES = ("q_tag_", "qv_tag_", "e_src_", "e_tag_", "e_prc_", "q_prc_", "pr_tag_", "prra_tag_", "prsn_tag_")
# The tag-family's own config keys, which legitimately differ between a
# tagged run and its untagged twin (the untagged twin has no tags to name).
PARITY_ONLY_EXTRA_ALLOWED_KEYS = {
    "water_tracers",
    "water_closure_check",
    "water_process_record",
    "energy_tracers",
    "energy_closure_check",
    "energy_source_tags",
    "energy_source_closure_check",
    "energy_process_record",
}
# The water tags' own switches (`water_tag_updraft_copy`, `water_tag_transport`)
# change only the tags, so they may differ too.
PARITY_ONLY_EXTRA_ALLOWED_PREFIXES = ("energy_source_tag_", "water_tag_")


def parse_hour(raw):
    """One --hours entry. A whole number becomes a plain int, exactly as
    before (so JSON keys, dict lookups and the printed table's "%4d" are
    unchanged for every existing caller). A fractional hour (the V-W0a 2h
    runs write every 360 s = 0.1 h) stays a float; format_hour below prints
    it without assuming an int."""
    value = float(raw)
    return int(value) if value.is_integer() else value


def format_hour(hour):
    """Right-justified, width 4, for both the int and float cases (the old
    code used a bare '%4d', which cannot format a float)."""
    return f"{hour!s:>4}"


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


# The model names each diagnostic file '<name>_<period>_inst.nc', with the
# period the config asked for: '1h' for hourly output, '5m' for a
# five-minute one. Both runs must use one period, and a directory with more
# than one is refused, since hour h would then have two readings.
SUFFIX = "_1h_inst.nc"
_SUFFIX_RE = re.compile(r"^.+(_\d+[a-z]+_inst\.nc)$")


def output_suffix(directory, label):
    """The one '_<period>_inst.nc' suffix of a run's diagnostic files."""
    suffixes = {m.group(1) for p in directory.glob("*_inst.nc") if (m := _SUFFIX_RE.match(p.name))}
    if len(suffixes) != 1:
        die(f"{label} has {len(suffixes)} kinds of instantaneous output ({sorted(suffixes)}); expected one")
    return suffixes.pop()


def set_suffix(ref_dir, run_dir):
    """Fix SUFFIX for this comparison from the two runs, which must agree."""
    global SUFFIX
    ref_suffix = output_suffix(ref_dir, "reference")
    run_suffix = output_suffix(run_dir, "run")
    if ref_suffix != run_suffix:
        die(f"the runs write different output periods: {ref_suffix} and {run_suffix}")
    SUFFIX = ref_suffix


def list_var_names(directory):
    """Variable stems for every '<name><SUFFIX>' file directly in a directory."""
    return {p.name[: -len(SUFFIX)] for p in directory.glob(f"*{SUFFIX}")}


# --- Minimal YAML reading ---------------------------------------------
# No YAML library is available here (numpy, netCDF4 and stdlib only), and
# the merged configs this reads are machine-written by one generator, with
# a fixed, simple shape: flat "key: value" lines, and block keys (a list of
# mappings) whose children are indented under them. These helpers parse
# exactly that shape. They are not a general YAML parser and must not be
# used as one.


def yaml_flat_scalar(text, key):
    """A top-level 'key: value' line's value, or None if the key is absent
    or is a block key (no value on its own line)."""
    m = re.search(rf"^{re.escape(key)}:[ \t]*(\S.*?)[ \t]*$", text, re.MULTILINE)
    return m.group(1) if m else None


def yaml_top_level_blocks(text):
    """Every top-level ('key:' at column 0) key, mapped to its own line plus
    every following more-indented line, in file order. Good enough for this
    config format; never a general YAML parser."""
    blocks = {}
    order = []
    current = None
    for line in text.splitlines():
        if line and not line[0].isspace() and re.match(r"^[A-Za-z0-9_]+:", line):
            current = line.split(":", 1)[0]
            blocks[current] = [line]
            order.append(current)
        elif current is not None:
            blocks[current].append(line)
    return {k: "\n".join(v) for k, v in blocks.items()}, order


def parse_tag_block(text, key):
    """Parse a 'key:' block of '- name: "..."' mappings, each with either a
    'region:' or a 'source: "..."' child (or both, R2's 'a tag that is a
    source and a region at once'). Returns an ordered list of
    (name, is_region, is_source) tuples, or None if the key is absent."""
    blocks, order = yaml_top_level_blocks(text)
    if key not in blocks:
        return None
    lines = blocks[key].splitlines()[1:]  # drop the 'key:' line itself
    tags = []
    name = None
    has_region = has_source = False
    for line in lines:
        m_name = re.match(r'^  - name:\s*"?([^"]+)"?\s*$', line)
        if m_name:
            if name is not None:
                tags.append((name, has_region, has_source))
            name, has_region, has_source = m_name.group(1), False, False
            continue
        if name is None:
            continue
        if re.match(r"^    region:\s*$", line):
            has_region = True
        elif re.match(r"^    source:\s*\S", line):
            has_source = True
    if name is not None:
        tags.append((name, has_region, has_source))
    return tags


def read_yaml_file(directory, label, file_hashes):
    """The run's single merged-config YAML, its text, and its path. Dies if
    there is not exactly one (ambiguous or none)."""
    ymls = sorted(directory.glob("*.yml"))
    if not ymls:
        die(f"{label}: no YAML file under {directory}; the tag list and pairing checks need it")
    if len(ymls) > 1:
        die(f"{label}: {directory} has more than one YAML file: {[p.name for p in ymls]}; ambiguous")
    path = ymls[0]
    file_hashes[str(path)] = sha256_file(path)
    return path.read_text(), path


def detect_family(text):
    """Autodetect the tag family from which tag block the YAML actually
    lists tags in, per R1's table. Both keys are always present in a merged
    config (the unused one is written 'key: ~'), so this checks for a
    non-empty tag list, not just key presence. Dies if both or neither are
    non-empty, since --family must then be given explicitly."""
    has = [name for name, table in FAMILY_TABLES.items() if parse_tag_block(text, table["tag_yaml_key"])]
    if len(has) != 1:
        die(
            "cannot autodetect --family: the YAML has non-empty tag lists for "
            f"{has or 'neither energy_source_tags nor water_tracers'}; pass --family explicitly"
        )
    return has[0]


def discover_tags(ref_text, run_text, family_table):
    """S5: the tag list comes from the run's own YAML, and the two runs'
    YAMLs must list the same tags (same names, same region/source split).
    Returns (tag_names, region_tags, source_tags)."""
    key = family_table["tag_yaml_key"]
    ref_tags = parse_tag_block(ref_text, key)
    run_tags = parse_tag_block(run_text, key)
    if ref_tags is None or run_tags is None:
        die(f"tags: '{key}' is missing from {'the reference' if ref_tags is None else 'the run'} YAML")
    ref_named = {name: (region, source) for name, region, source in ref_tags}
    run_named = {name: (region, source) for name, region, source in run_tags}
    if ref_named != run_named:
        only_ref = sorted(set(ref_named) - set(run_named))
        only_run = sorted(set(run_named) - set(ref_named))
        differ = sorted(n for n in set(ref_named) & set(run_named) if ref_named[n] != run_named[n])
        die(
            "tags: reference and run YAMLs list different tags "
            f"(only in reference: {only_ref}; only in run: {only_run}; "
            f"same name but different region/source: {differ})"
        )
    names = [name for name, _, _ in ref_tags]
    # R2/R5: a tag that has both a region and a source counts as a source
    # tag (proposed). A tag is a region tag only when it has a region and
    # no source.
    region_tags = {n for n, region, source in ref_tags if region and not source}
    source_tags = {n for n, region, source in ref_tags if source or (region and source)}
    return names, region_tags, source_tags


def discover_default_parent(ref_dir, run_dir, family_table, allow_missing):
    """S1: the union of the two runs' variables, excluding tags, process
    records and vapour-share diagnostics; a variable present in only one
    run is a hard failure unless named with --allow-missing."""
    ref_vars, run_vars = list_var_names(ref_dir), list_var_names(run_dir)
    excluded = family_table["excluded_parent_prefixes"]
    candidates = {n for n in (ref_vars | run_vars) if not n.startswith(excluded)}
    only_ref = sorted((candidates & ref_vars) - run_vars)
    only_run = sorted((candidates & run_vars) - ref_vars)
    unexplained = sorted((set(only_ref) | set(only_run)) - set(allow_missing))
    if unexplained:
        die(
            "parent parity: variable(s) present in only one run: "
            f"{unexplained} (pass --allow-missing NAME to accept a field only "
            "one run writes)"
        )
    return sorted((candidates & ref_vars & run_vars) | ({"ta", "rhoa"} & candidates))


def require_file(directory, stem, label, file_hashes):
    """Check (a): the file must exist. Record its hash now so a later
    failure elsewhere still reports what this run actually read."""
    path = directory / f"{stem}{SUFFIX}"
    if not path.is_file():
        die(f"{label} is missing '{stem}': no file at {path}")
    file_hashes[str(path)] = sha256_file(path)
    return path


class RunCoords:
    """One run's own time/date/z (and their units), fixed by the first file
    opened for it. Every later file for the same run is checked against
    these, so an internally inconsistent run directory is caught, not just a
    mismatch between the two runs."""

    def __init__(self, label):
        self.label = label
        self.time = self.date = self.z = None
        self.time_units = self.date_units = self.z_units = None

    def check_or_set(self, time, date, z, time_units, date_units, z_units, source):
        if self.time is None:
            self.time, self.date, self.z = time, date, z
            self.time_units, self.date_units, self.z_units = time_units, date_units, z_units
            return
        if not np.array_equal(self.time, time):
            die(f"{self.label}: '{source}' has a different time array than the run's other files")
        if not np.array_equal(self.date, date):
            die(f"{self.label}: '{source}' has a different date array than the run's other files")
        if self.z is not None and z is not None and not np.array_equal(self.z, z):
            die(f"{self.label}: '{source}' has a different z array than the run's other files")
        if self.time_units != time_units:
            die(f"{self.label}: '{source}' has a different time units than the run's other files")
        if self.date_units != date_units:
            die(f"{self.label}: '{source}' has a different date units than the run's other files")


def default_fill_for(dtype):
    key = dtype.str[1:]  # e.g. 'f8', 'f4', 'i4'
    return default_fillvals.get(key)


def check_finite(data, var, varname, label, source):
    """B2: die on NaN, Inf, or a fill value anywhere in a compared field.
    Names the variable and the index of the first bad value (the index
    tuple, read against the variable's own dimensions, names the level and
    hour). Never let a non-finite or fill value reach a metric or a budget
    check silently."""
    bad = ~np.isfinite(data)
    fill = getattr(var, "_FillValue", None)
    if fill is None:
        fill = default_fill_for(data.dtype)
    if fill is not None:
        bad = bad | (data == fill)
    if np.any(bad):
        first = tuple(int(i) for i in np.argwhere(bad)[0])
        die(
            f"{label}: '{source}' variable '{varname}' has a non-finite or "
            f"fill value at index {first} of dims {var.dimensions}"
        )


def open_var(path, varname, label, coords, file_hashes, require_z=True):
    """Open one '<var><SUFFIX>' file and return (data, dims, units).
    Dimensions are matched by name, never by position, so a file that
    happens to write (time, z) is still read correctly. Supports the column
    geometry ('z','time') and a surface field ('time',) alone; anything else
    is refused. Checks (e): every value read must be finite and not a fill
    value."""
    file_hashes[str(path)] = sha256_file(path)
    with Dataset(path) as ds:
        ds.set_auto_mask(False)  # a plain ndarray, so a signed zero is not lost to masking
        needed_coords = ("time", "date") + (("z",) if require_z else ())
        for coord in needed_coords:
            if coord not in ds.variables:
                die(f"{label}: '{path.name}' has no '{coord}' coordinate variable")
        if varname not in ds.variables:
            die(f"{label}: '{path.name}' has no variable '{varname}'")
        var = ds.variables[varname]
        dims = var.dimensions
        if set(dims) == {"z", "time"}:
            data = np.array(var[:])
            if dims != ("z", "time"):
                data = np.moveaxis(data, dims.index("z"), 0)  # canonical (z, time)
            dims = ("z", "time")
        elif set(dims) == {"time"}:
            data = np.array(var[:])
            dims = ("time",)
        else:
            die(
                f"{label}: '{path.name}' variable '{varname}' has dimensions "
                f"{dims}; only ('z','time') or ('time',) is supported "
                "(unsupported geometry)"
            )
        check_finite(data, var, varname, label, path.name)
        units = getattr(var, "units", None)
        time = np.array(ds.variables["time"][:])
        date = np.array(ds.variables["date"][:])
        time_units = getattr(ds.variables["time"], "units", None)
        date_units = getattr(ds.variables["date"], "units", None)
        if "z" in ds.variables:
            z = np.array(ds.variables["z"][:])
            z_units = getattr(ds.variables["z"], "units", None)
            if not np.all(np.isfinite(z)):
                die(f"{label}: '{path.name}' has a non-finite z coordinate value")
        else:
            z = z_units = None
    coords.check_or_set(time, date, z, time_units, date_units, z_units, path.name)
    return data, dims, units


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

    # S4: the time epoch. Units differing means two runs' clocks start from
    # different dates, so a numerically equal 'time' array means two
    # different instants.
    if ref_coords.time_units != run_coords.time_units:
        die(f"units: time differs between reference ({ref_coords.time_units!r}) and run ({run_coords.time_units!r})")
    if ref_coords.date_units != run_coords.date_units:
        die(f"units: date (the epoch) differs between reference ({ref_coords.date_units!r}) and run ({run_coords.date_units!r})")

    if not np.array_equal(ref_coords.z, run_coords.z):
        die("z: reference and run coordinates differ")
    if ref_coords.z_units != run_coords.z_units:
        die(f"units: z differs between reference ({ref_coords.z_units!r}) and run ({run_coords.z_units!r})")

    idx = {}
    for h in hours:
        target = h * 3600
        hits = np.nonzero(ref_coords.time[:overlap] == target)[0]
        if hits.size == 0:
            die(f"time: hour {h} (t={target}s) is not present in the compared range of {overlap} times")
        idx[h] = int(hits[0])
    return idx, overlap


def find_yaml_z_max(text):
    """The grid's declared top face, from the run's own YAML. A flat
    top-level 'z_max: <value>' key; the config format has no nesting here."""
    raw = yaml_flat_scalar(text, "z_max")
    if raw is None:
        print("NOTICE: YAML has no top-level 'z_max' key; skipping the top-face check")
        return None
    return float(raw)


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


def tag_row_metrics(tag, hour, e_ref, e_run, w, w_run=None):
    """The reported quantities for one tag at one hour. Where the reference
    is identically zero the ratio metrics have no defined value: report
    that fact, never a stray 0 or NaN.

    S3: `w` is rho_ref * dz (the reference's own atmosphere); it is what the
    L1/Linf/rel_integral_change budgets use, and is right whenever the two
    runs share one atmosphere (default vs. copies). `integral_run` is
    labelled for what it is: the run's field integrated with the
    reference's weights, not the run's own column integral. `w_run`, when
    given (the run's own rho * dz), adds the run's own-atmosphere integral
    alongside it, for a pair that does not share one atmosphere (the ladder,
    a Float32 twin, a restart pair)."""
    integral_ref = float(np.sum(e_ref * w))
    integral_run_ref_weighted = float(np.sum(e_run * w))
    delta = e_run - e_ref
    max_abs_error = float(np.max(np.abs(delta)))  # well-defined regardless of ref
    abs_ref_weighted = float(np.sum(np.abs(e_ref) * w))
    abs_l1 = float(np.sum(np.abs(delta) * w))  # R4: absolute L1, same units as integral_ref
    max_abs_ref = float(np.max(np.abs(e_ref)))
    ref_zero = max_abs_ref == 0.0  # w_k > 0 everywhere, so this iff e_ref is all zero
    row = {
        "tag": tag,
        "hour": hour,
        "integral_ref": integral_ref,
        "integral_run_ref_weighted": integral_run_ref_weighted,
        "max_abs_error": max_abs_error,
        "abs_L1": abs_l1,
        "ref_zero": ref_zero,
    }
    if w_run is not None:
        row["integral_run_own_atmosphere"] = float(np.sum(e_run * w_run))
    if ref_zero:
        row["run_zero"] = bool(np.all(e_run == 0))
        row["rel_integral_change"] = None
        row["L1_mass_weighted"] = None
        row["Linf_peak_normalized"] = None
    else:
        row["run_zero"] = False
        row["rel_integral_change"] = (integral_run_ref_weighted - integral_ref) / integral_ref
        row["L1_mass_weighted"] = float(abs_l1 / abs_ref_weighted)
        row["Linf_peak_normalized"] = float(np.max(np.abs(delta)) / max_abs_ref)
    return row


def format_tag_row(row):
    tag, hour = row["tag"], row["hour"]
    if row["ref_zero"]:
        note = f"ref zero (run {'zero' if row['run_zero'] else 'nonzero'})"
        return (
            f"{tag:10s} {format_hour(hour)}   {row['integral_ref']:10.4e}  {note:>28s} "
            f"{row['max_abs_error']:10.4e}"
        )
    return (
        f"{tag:10s} {format_hour(hour)}   {row['integral_ref']:10.4e}  "
        f"{row['rel_integral_change']:+10.2e} {row['L1_mass_weighted']:9.2e} "
        f"{row['Linf_peak_normalized']:9.2e}  {row['max_abs_error']:10.4e}"
    )


# --- Pairing (S2) -------------------------------------------------------


def read_provenance(directory, label):
    """provenance.txt as a flat dict of key: value strings. Missing file is
    not fatal (older runs may lack it) but is noted, since pairing checks
    against it are then skipped."""
    path = directory / "provenance.txt"
    if not path.is_file():
        print(f"NOTICE: {label} has no provenance.txt under {directory}; pairing checks against it are skipped")
        return {}
    fields = {}
    for line in path.read_text().splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fields[k.strip()] = v.strip()
    return fields


def toml_paths_from_yaml(text):
    blocks, _ = yaml_top_level_blocks(text)
    if "toml" not in blocks:
        return []
    return re.findall(r'^\s*-\s*"(.+)"\s*$', blocks["toml"], re.MULTILINE)


def check_pairing(
    ref_dir,
    run_dir,
    ref_prov,
    run_prov,
    ref_yaml_text,
    run_yaml_text,
    expect_parity,
    extra_allowed_keys=(),
    extra_allowed_prefixes=(),
):
    """S2: can this pair be compared at all? Refuses the same directory
    twice unconditionally. Everything else that must match only for a
    bitwise-parity claim is a NOTICE without --expect-parity, and a hard
    failure with it. `extra_allowed_keys`/`extra_allowed_prefixes` widen the
    YAML-diff allowlist for --parity-only (a tagged run against its
    untagged twin legitimately differs in every tag-family config key, not
    just the mode key). Returns the list of mismatch messages found (empty
    if none)."""
    if ref_dir == run_dir:
        die(f"--reference and --run resolve to the same directory: {ref_dir}")

    mismatches = []
    for key in MUST_MATCH_PROVENANCE_KEYS:
        r, u = ref_prov.get(key), run_prov.get(key)
        if r is not None and u is not None and r != u:
            mismatches.append(f"provenance '{key}': reference={r!r} run={u!r}")

    ref_float = yaml_flat_scalar(ref_yaml_text, "FLOAT_TYPE")
    run_float = yaml_flat_scalar(run_yaml_text, "FLOAT_TYPE")
    if ref_float is not None and run_float is not None and ref_float != run_float:
        mismatches.append(f"YAML 'FLOAT_TYPE': reference={ref_float!r} run={run_float!r}")

    for flag in PARITY_BREAKING_YAML_FLAGS:
        for label, text in (("reference", ref_yaml_text), ("run", run_yaml_text)):
            val = yaml_flat_scalar(text, flag)
            if val and val.strip().lower() == "true":
                mismatches.append(f"YAML '{flag}' is true in the {label}; breaks the bitwise-parity contract")

    ref_blocks, _ = yaml_top_level_blocks(ref_yaml_text)
    run_blocks, _ = yaml_top_level_blocks(run_yaml_text)
    for key in sorted(set(ref_blocks) | set(run_blocks)):
        if key == "toml":
            ref_paths = toml_paths_from_yaml(ref_yaml_text)
            run_paths = toml_paths_from_yaml(run_yaml_text)
            ref_hashes = sorted(sha256_file(p) for p in ref_paths if Path(p).is_file())
            run_hashes = sorted(sha256_file(p) for p in run_paths if Path(p).is_file())
            if ref_hashes != run_hashes:
                mismatches.append("YAML 'toml': the referenced parameter files' content differs")
            continue
        if key in YAML_DIFF_ALLOWED_KEYS or key in extra_allowed_keys or key.startswith(tuple(extra_allowed_prefixes)):
            continue
        if ref_blocks.get(key) != run_blocks.get(key):
            mismatches.append(f"YAML '{key}' differs between reference and run (outside the allowed keys)")

    if mismatches:
        if expect_parity:
            die("pairing (--expect-parity): " + "; ".join(mismatches))
        for m in mismatches:
            print(f"NOTICE: pairing: {m}")
    return mismatches


# --- Water extension: --judge (R5, R7) ----------------------------------


def classify_tag(tag, region_tags, source_tags):
    return "region" if tag in region_tags else "source"


def judge_tag_row(tag, hour, row, kind, total_ref):
    """R5: the budget verdict for one tag at one judged hour (1 h or 24 h).

    Definitions the review marked proposed, which the owner accepted on
    2026-09-23 (recorded in G3_PLAN.md section 6.1):
      - S (the tag's share) is computed from the reference at this hour;
      - a small tag (S < 1%, or the reference is zero here) is judged on
        abs_L1 <= 2e-4 * total_ref alone -- L1 and Linf are still reported;
      - a tag with both a region and a source counts as a source tag
        (handled in discover_tags, not here);
      - a non-finite value or a missing hour is a failure -- enforced
        upstream (B2's check_finite, and the hour-presence check in
        check_time_and_z), so this function never sees one.
    """
    share = None if total_ref == 0 else row["integral_ref"] / total_ref
    small = row["ref_zero"] or (share is not None and share < SMALL_TAG_SHARE)
    if small:
        bound = SMALL_TAG_ABS_L1_FACTOR * total_ref
        passed = row["abs_L1"] <= bound
        reason = f"small tag (share={share}): abs_L1={row['abs_L1']:.3e} <= {bound:.3e}"
    else:
        budget = JUDGE_BUDGETS[hour][kind]
        l1_ok = row["L1_mass_weighted"] <= budget["L1"]
        linf_ok = row["Linf_peak_normalized"] <= budget["Linf"]
        passed = l1_ok and linf_ok
        reason = (
            f"{kind} tag: L1={row['L1_mass_weighted']:.3e} (budget {budget['L1']}), "
            f"Linf={row['Linf_peak_normalized']:.3e} (budget {budget['Linf']})"
        )
    return {"tag": tag, "hour": hour, "kind": kind, "share": share, "small": small, "passed": bool(passed), "reason": reason}


def compute_closure(abs_residual_by_hour, total_ref_by_hour, remainder_ref_by_hour, remainder_fields):
    """R7: closure, criterion 4. G(t) = sum(|q_tag_res| w) / total_ref(t).
    The owner accepted these definitions on 2026-09-23 (G3_PLAN.md 6.1):
      - the budget is G(24h) <= 0.002;
      - "the second 12h add no more than the first" is
        G(24) - G(12) <= G(12) - G(0) (needs hours 0, 12 and 24 present);
      - the remainder after the named parts is <= 1e-6 * total_ref at 24h,
        where "the named parts" is the list of fields passed in
        --closure-remainder-fields (WP3/WP4b have not fixed their output
        names yet, so the verifier takes the list from the caller instead
        of a fixed table entry)."""
    G = {
        h: (abs_res / total_ref_by_hour[h] if total_ref_by_hour.get(h) else None)
        for h, abs_res in abs_residual_by_hour.items()
    }
    result = {"G": G}
    if 24 in G and G[24] is not None:
        result["budget_24h_ok"] = bool(G[24] <= CLOSURE_BUDGET_24H)
    if 24 in G and 12 in G and 0 in G and None not in (G[24], G[12], G[0]):
        result["second_half_not_worse_ok"] = bool((G[24] - G[12]) <= (G[12] - G[0]))
    if remainder_fields:
        remainder_24h = remainder_ref_by_hour.get(24)
        total_24h = total_ref_by_hour.get(24)
        if remainder_24h is not None and total_24h:
            result["remainder_fields"] = remainder_fields
            result["remainder_24h"] = remainder_24h
            result["remainder_budget_ok"] = bool(remainder_24h <= 1e-6 * total_24h)
    return result


# --- R12: the convergence ladder's share metric --------------------------


def run_ladder_share(args):
    """R12: compare a tag's share of the total across two rungs of the
    ladder that may use different z grids (60 vs. 120 levels). Each run's
    own hour lookup and own faces/dz are used, so the runs need not share
    time length or z, unlike the rest of this file. Two proposed formulas,
    per the review, with the output stating which was used:
      - when the two runs share one z grid: the level-wise share metric,
        L1_phi = sum(|phi_run - phi_ref| * q_tot,ref * w) /
                 sum(phi_ref * q_tot,ref * w), phi = q_tag / q_tot on each
        run's own atmosphere, w = rho_ref * dz;
      - when they do not: only the column-integrated share
        phi = (integral of q_tag) / (integral of q_tot), each on its own
        atmosphere, and the plain difference of the two scalars.
    Also reports the parent's own change (hus, rhoa), since each rung is a
    different atmosphere; only defined when the grids match, for the same
    reason."""
    ref_dir = resolve_output_dir(args.reference, "reference")
    run_dir = resolve_output_dir(args.run, "run")
    set_suffix(ref_dir, run_dir)
    print(f"reference: {ref_dir}")
    print(f"run:       {run_dir}")
    if ref_dir == run_dir:
        die(f"--reference and --run resolve to the same directory: {ref_dir}")

    file_hashes = {}
    ref_yaml_text, _ = read_yaml_file(ref_dir, "reference", file_hashes)
    run_yaml_text, _ = read_yaml_file(run_dir, "run", file_hashes)
    family = args.family or detect_family(ref_yaml_text)
    family_table = FAMILY_TABLES[family]
    if not family_table["total_var"]:
        die("--ladder-share needs a family with a total field (R4's total_ref); energy has none")
    tags, _, _ = discover_tags(ref_yaml_text, run_yaml_text, family_table)
    hours = [parse_hour(h) for h in (args.hours or "1,6,12,24").split(",")]

    ref_coords, run_coords = RunCoords("reference"), RunCoords("run")
    ref_rhoa, _, _ = open_var(ref_dir / f"rhoa{SUFFIX}", "rhoa", "reference", ref_coords, file_hashes)
    run_rhoa, _, _ = open_var(run_dir / f"rhoa{SUFFIX}", "rhoa", "run", run_coords, file_hashes)
    total_var = family_table["total_var"]
    ref_total, _, _ = open_var(ref_dir / f"{total_var}{SUFFIX}", total_var, "reference", ref_coords, file_hashes)
    run_total, _, _ = open_var(run_dir / f"{total_var}{SUFFIX}", total_var, "run", run_coords, file_hashes)

    def hour_index(coords, h):
        hits = np.nonzero(coords.time == h * 3600)[0]
        if hits.size == 0:
            die(f"ladder-share: hour {h} (t={h * 3600}s) is not present in {coords.label}'s time array")
        return int(hits[0])

    ref_faces, ref_dz = compute_faces_and_dz(ref_coords.z, "reference")
    run_faces, run_dz = compute_faces_and_dz(run_coords.z, "run")
    same_grid = ref_coords.z.shape == run_coords.z.shape and np.array_equal(ref_coords.z, run_coords.z)
    mode = "level_wise_and_column_integrals" if same_grid else "column_integrals_only"
    print(f"\nladder-share mode: {mode} (same z grid: {same_grid})")

    tag_results = {}
    for tag in tags:
        stem = f"{family_table['tag_var_prefix']}{tag}"
        e_ref, _, _ = open_var(ref_dir / f"{stem}{SUFFIX}", stem, "reference", ref_coords, file_hashes)
        e_run, _, _ = open_var(run_dir / f"{stem}{SUFFIX}", stem, "run", run_coords, file_hashes)
        tag_results[tag] = {}
        for h in hours:
            i_ref, i_run = hour_index(ref_coords, h), hour_index(run_coords, h)
            w_ref = ref_rhoa[:, i_ref] * ref_dz
            w_run = run_rhoa[:, i_run] * run_dz
            tag_int_ref = float(np.sum(e_ref[:, i_ref] * w_ref))
            tot_int_ref = float(np.sum(ref_total[:, i_ref] * w_ref))
            tag_int_run = float(np.sum(e_run[:, i_run] * w_run))
            tot_int_run = float(np.sum(run_total[:, i_run] * w_run))
            phi_ref = tag_int_ref / tot_int_ref if tot_int_ref else None
            phi_run = tag_int_run / tot_int_run if tot_int_run else None
            row = {
                "hour": h,
                "phi_ref_column": phi_ref,
                "phi_run_column": phi_run,
                "share_delta_column": None if None in (phi_ref, phi_run) else phi_run - phi_ref,
            }
            if same_grid:
                phi_ref_level = e_ref[:, i_ref] / ref_total[:, i_ref]
                phi_run_level = e_run[:, i_run] / run_total[:, i_run]
                num = float(np.sum(np.abs(phi_run_level - phi_ref_level) * ref_total[:, i_ref] * w_ref))
                den = float(np.sum(phi_ref_level * ref_total[:, i_ref] * w_ref))
                row["L1_phi_level_wise"] = (num / den) if den else None
            tag_results[tag][h] = row
            extra = f" L1_phi={row['L1_phi_level_wise']:.3e}" if same_grid and row["L1_phi_level_wise"] is not None else ""
            print(f"  {tag:10s} {format_hour(h)}h  phi_ref={phi_ref}  phi_run={phi_run}  delta={row['share_delta_column']}{extra}")

    parent_l1 = {}
    if same_grid:
        for name, ref_full, run_full in (("hus" if total_var == "hus" else total_var, ref_total, run_total), ("rhoa", ref_rhoa, run_rhoa)):
            per_hour = {}
            for h in hours:
                i_ref, i_run = hour_index(ref_coords, h), hour_index(run_coords, h)
                w_ref = ref_rhoa[:, i_ref] * ref_dz
                num = float(np.sum(np.abs(run_full[:, i_run] - ref_full[:, i_ref]) * w_ref))
                den = float(np.sum(np.abs(ref_full[:, i_ref]) * w_ref))
                per_hour[h] = (num / den) if den else None
            parent_l1[name] = per_hour
        print(f"\nparent's own change (L1, same grid): {parent_l1}")
    else:
        print("\nNOTICE: z grids differ; the parent's own change is not reported (needs one grid)")

    if args.json:
        report = {
            "mode": mode,
            "same_grid": bool(same_grid),
            "hours": hours,
            "tags": tag_results,
            "parent_L1": parent_l1,
            "input_file_sha256": file_hashes,
            "script_sha256": sha256_file(Path(__file__).resolve()),
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
        print(f"json report: {Path(args.json).resolve()}")


# --- Criterion 3: --parity-only (a tagged run against its untagged twin) --


def _var_has_z(directory, name):
    with Dataset(directory / f"{name}{SUFFIX}") as ds:
        return "z" in ds.variables[name].dimensions


def run_parity_only(args):
    """Criterion 3: parent-state parity between a tagged run and its
    untagged twin. No family, no tags, no per-tag metrics -- the untagged
    twin has no tag block to detect a family from. The parent set is the
    union of both runs' fields minus every tag-family output (fixed,
    family-agnostic prefixes, since the family is not known here); a
    non-tag-family field present in only one run is a hard failure (S1's
    fix, without needing --family), and every tag-family field present in
    only one run is reported, not compared. Every compared field must be
    bit for bit, unconditionally (this mode's whole point is a parity
    claim), unlike the default main() flow where --expect-parity opts in."""
    ref_dir = resolve_output_dir(args.reference, "reference")
    run_dir = resolve_output_dir(args.run, "run")
    set_suffix(ref_dir, run_dir)
    print(f"reference: {ref_dir}")
    print(f"run:       {run_dir}")

    file_hashes = {}
    ref_yaml_text, _ = read_yaml_file(ref_dir, "reference", file_hashes)
    run_yaml_text, _ = read_yaml_file(run_dir, "run", file_hashes)
    ref_prov = read_provenance(ref_dir, "reference")
    run_prov = read_provenance(run_dir, "run")
    pairing_mismatches = check_pairing(
        ref_dir,
        run_dir,
        ref_prov,
        run_prov,
        ref_yaml_text,
        run_yaml_text,
        expect_parity=True,
        extra_allowed_keys=PARITY_ONLY_EXTRA_ALLOWED_KEYS,
        extra_allowed_prefixes=PARITY_ONLY_EXTRA_ALLOWED_PREFIXES,
    )

    ref_vars, run_vars = list_var_names(ref_dir), list_var_names(run_dir)
    only_ref = ref_vars - run_vars
    only_run = run_vars - ref_vars
    unexplained_ref = sorted(n for n in only_ref if not n.startswith(PARITY_ONLY_EXCLUDED_PREFIXES))
    unexplained_run = sorted(n for n in only_run if not n.startswith(PARITY_ONLY_EXCLUDED_PREFIXES))
    if unexplained_ref or unexplained_run:
        die(
            "--parity-only: non-tag-family field(s) present in only one run "
            f"(every one-run-only field must be a tag-family output): only "
            f"in reference: {unexplained_ref}; only in run: {unexplained_run}"
        )
    tag_only_ref = sorted(n for n in only_ref if n.startswith(PARITY_ONLY_EXCLUDED_PREFIXES))
    tag_only_run = sorted(n for n in only_run if n.startswith(PARITY_ONLY_EXCLUDED_PREFIXES))
    print(f"\nfields only in reference (tag-family, not compared): {tag_only_ref}")
    print(f"fields only in run (tag-family, not compared): {tag_only_run}")

    common_vars = {n for n in (ref_vars & run_vars) if not n.startswith(PARITY_ONLY_EXCLUDED_PREFIXES)}
    if not common_vars:
        die("--parity-only: no non-tag-family field is common to both runs; nothing to compare")
    # Open a column field first if one exists, so RunCoords fixes a real z
    # (see RunCoords.check_or_set: once time is set from a surface-only
    # field, a later column field's z would never be recorded).
    ordered_vars = sorted(common_vars, key=lambda v: (not _var_has_z(ref_dir, v), v))

    ref_coords, run_coords = RunCoords("reference"), RunCoords("run")
    parity = {}
    overlap = None
    for name in ordered_vars:
        a, a_dims, a_units = open_var(ref_dir / f"{name}{SUFFIX}", name, "reference", ref_coords, file_hashes, require_z=False)
        b, b_dims, b_units = open_var(run_dir / f"{name}{SUFFIX}", name, "run", run_coords, file_hashes, require_z=False)
        if overlap is None:
            # Checks (b)/(c): time, date and z alignment, once, from the
            # first field opened. hours=[] since --parity-only has no hour
            # lookup of its own; hours_given=True tolerates a length
            # mismatch as a compared common prefix, with a NOTICE.
            _, overlap = check_time_and_z(ref_coords, run_coords, [], True)
        if a_dims != b_dims:
            die(f"{name}: dimension mismatch, reference {a_dims} vs run {b_dims}")
        if a_units != b_units:
            die(f"units: '{name}' differs between reference ({a_units!r}) and run ({b_units!r})")
        sl = (slice(None), slice(0, overlap)) if a_dims == ("z", "time") else (slice(0, overlap),)
        result = bit_compare(a[sl], b[sl], name)
        parity[name] = result
        print("  " + format_parity_line(name, result))

    parity_breaks = [n for n, r in parity.items() if not r["identical"]]
    if parity_breaks:
        die(f"--parity-only: parent parity broke for {parity_breaks}")
    print(f"\n--parity-only: PASS ({len(parity)} fields bit for bit)")

    if args.json:
        report = {
            "mode": "parity_only",
            "resolved_paths": {"reference": str(ref_dir), "run": str(run_dir)},
            "parent_parity": parity,
            "tag_only_fields": {"reference": tag_only_ref, "run": tag_only_run},
            "pairing": {
                "reference_provenance": ref_prov,
                "run_provenance": run_prov,
                "mismatches": pairing_mismatches,
            },
            "input_file_sha256": file_hashes,
            "script_sha256": sha256_file(Path(__file__).resolve()),
            "run_context": {
                "hostname": socket.gethostname(),
                "utc_time": datetime.now(timezone.utc).isoformat(),
                "command": " ".join(sys.argv),
            },
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
        print(f"json report: {Path(args.json).resolve()}")


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
        "compare runs of different length (a common-length prefix). A "
        "fractional hour (e.g. 0.1 for a 360s output) is accepted, matched "
        "at exactly h*3600 s like a whole hour",
    )
    parser.add_argument(
        "--tags",
        default=None,
        help="comma-separated tag names; default every tag in the reference "
        "YAML's tag block (energy_source_tags or water_tracers)",
    )
    parser.add_argument(
        "--parent",
        default=None,
        help="comma-separated parent variable names; default ta, rhoa, and "
        "every other non-tag variable present in either run",
    )
    parser.add_argument(
        "--family",
        choices=["water", "energy"],
        default=None,
        help="which family table to use (R1); default: autodetect from the "
        "reference YAML's tag block",
    )
    parser.add_argument(
        "--expect-parity",
        action="store_true",
        help="S1/S2: exit nonzero on any parent-parity break, and refuse "
        "pairing when FLOAT_TYPE, machine or rank count differ",
    )
    parser.add_argument(
        "--allow-missing",
        action="append",
        default=[],
        metavar="NAME",
        help="S1: accept a parent variable present in only one run; may be given more than once",
    )
    parser.add_argument(
        "--judge",
        action="store_true",
        help="R5: judge every tag at hour 1 and hour 24 against G3_PLAN.md "
        "section 6.1's budgets (water family only; both hours must be in --hours)",
    )
    parser.add_argument(
        "--bitwise-tags",
        action="store_true",
        help="R11: also compare every tag field bit for bit, like the parent fields",
    )
    parser.add_argument(
        "--closure-remainder-fields",
        default=None,
        metavar="NAME,...",
        help="R7: comma-separated field stems already present in the run "
        "(no prefix added) whose sum with the residual should equal zero; "
        "the remainder |res_run - sum(fields)| w is judged against "
        "1e-6*total_ref at 24h. Empty by default, since WP3/WP4b have not "
        "named these fields yet (leaks, ledgers, the 10-Newton one-iteration part).",
    )
    parser.add_argument(
        "--ladder-share",
        action="store_true",
        help="R12: compare a tag's share of the total (phi = q_tag/q_tot) "
        "between two ladder rungs, which may use different z grids or time "
        "lengths; skips every other check in this file (its own mode, not "
        "combinable with --judge, --expect-parity, etc.)",
    )
    parser.add_argument(
        "--parity-only",
        action="store_true",
        help="criterion 3: a tagged run against its untagged twin. No "
        "--family, no tags, no per-tag metrics; parent parity only, over "
        "the union of both runs' fields minus every tag-family output "
        "(q_tag_*, qv_tag_*, e_src_*, e_tag_*, e_prc_*, q_prc_*, pr_tag_*), "
        "bit for bit, unconditionally fatal on any break; its own mode, "
        "like --ladder-share, not combinable with --judge/--tags/--family/etc.",
    )
    parser.add_argument("--json", default=None, help="write the full report to this path")
    return parser.parse_args()


def git_plan_commit():
    """R5: the commit of G3_PLAN.md the budgets in --judge came from, for
    the JSON record. None (with a NOTICE) if git is not reachable, e.g. on a
    compute node."""
    plan_path = Path(__file__).resolve().parents[2] / "G3_PLAN.md"
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%H", "--", str(plan_path)],
            cwd=plan_path.parent,
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip() or None
    except Exception as exc:  # noqa: BLE001 - report, do not fail the run over this
        print(f"NOTICE: could not read G3_PLAN.md's git commit ({exc}); --judge's JSON records commit=null")
        return None


def main():
    args = parse_args()
    if args.ladder_share:
        run_ladder_share(args)
        return
    if args.parity_only:
        run_parity_only(args)
        return
    ref_dir = resolve_output_dir(args.reference, "reference")
    run_dir = resolve_output_dir(args.run, "run")
    set_suffix(ref_dir, run_dir)
    print(f"reference: {ref_dir}")
    print(f"run:       {run_dir}")

    file_hashes = {}
    ref_yaml_text, ref_yaml_path = read_yaml_file(ref_dir, "reference", file_hashes)
    run_yaml_text, run_yaml_path = read_yaml_file(run_dir, "run", file_hashes)

    family = args.family or detect_family(ref_yaml_text)
    family_table = FAMILY_TABLES[family]
    print(f"family:    {family}")

    ref_prov = read_provenance(ref_dir, "reference")
    run_prov = read_provenance(run_dir, "run")
    pairing_mismatches = check_pairing(
        ref_dir, run_dir, ref_prov, run_prov, ref_yaml_text, run_yaml_text, args.expect_parity
    )

    hours_given = args.hours is not None
    hours = [parse_hour(h) for h in (args.hours if hours_given else "1,6,12,24").split(",")]
    if args.tags:
        tags = [t.strip() for t in args.tags.split(",")]
        region_tags, source_tags = set(), set(tags)  # unclassified; --judge needs discover_tags's split
    else:
        tags, region_tags, source_tags = discover_tags(ref_yaml_text, run_yaml_text, family_table)

    if args.judge:
        if family != "water":
            die("--judge implements G3_PLAN.md 6.1's budgets, which are water-only (no energy total field)")
        if args.tags:
            die("--judge needs the region/source split from the YAML's tag block; it cannot be combined with --tags")
        missing_hours = [h for h in JUDGE_HOURS if h not in hours]
        if missing_hours:
            die(f"--judge needs hour(s) {missing_hours} in --hours; it judges hour 1 and hour 24 only")

    parent_vars = (
        [p.strip() for p in args.parent.split(",")]
        if args.parent
        else discover_default_parent(ref_dir, run_dir, family_table, args.allow_missing)
    )

    # Check (a): every requested file exists in both runs, plus rhoa (and,
    # for --judge, the family's total_var), which the weights/shares need
    # even if --parent/--tags leave them out.
    prefix = family_table["tag_var_prefix"]
    required_stems = sorted({f"{prefix}{t}" for t in tags} | set(parent_vars) | {"rhoa"})
    if args.judge and family_table["total_var"]:
        required_stems = sorted(set(required_stems) | {family_table["total_var"]})
    for stem in required_stems:
        require_file(ref_dir, stem, "reference", file_hashes)
        require_file(run_dir, stem, "run", file_hashes)

    ref_coords = RunCoords("reference")
    run_coords = RunCoords("run")

    ref_rhoa, _, ref_rhoa_units = open_var(ref_dir / f"rhoa{SUFFIX}", "rhoa", "reference", ref_coords, file_hashes)
    run_rhoa, _, run_rhoa_units = open_var(run_dir / f"rhoa{SUFFIX}", "rhoa", "run", run_coords, file_hashes)
    if ref_rhoa_units != run_rhoa_units:
        die(f"units: rhoa differs between reference ({ref_rhoa_units!r}) and run ({run_rhoa_units!r})")

    # Checks (b) and (c).
    idx_map, overlap = check_time_and_z(ref_coords, run_coords, hours, hours_given)

    z_max = find_yaml_z_max(ref_yaml_text)
    faces, dz = compute_faces_and_dz(ref_coords.z, "reference")
    check_top_face(float(faces[-1]), z_max)
    run_faces, run_dz = compute_faces_and_dz(run_coords.z, "run")  # same z as ref (checked above); kept explicit

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
        a, a_dims, a_units = open_var(ref_dir / f"{name}{SUFFIX}", name, "reference", ref_coords, file_hashes, require_z=False)
        b, b_dims, b_units = open_var(run_dir / f"{name}{SUFFIX}", name, "run", run_coords, file_hashes, require_z=False)
        if a_dims != b_dims:
            die(f"{name}: dimension mismatch, reference {a_dims} vs run {b_dims}")
        if a_units != b_units:
            die(f"units: '{name}' differs between reference ({a_units!r}) and run ({b_units!r})")
        sl = (slice(None), slice(0, overlap)) if a_dims == ("z", "time") else (slice(0, overlap),)
        result = bit_compare(a[sl], b[sl], name)
        parity[name] = result
        print("  " + format_parity_line(name, result))

    parity_breaks = [n for n, r in parity.items() if not r["identical"]]
    if args.expect_parity and parity_breaks:
        die(f"--expect-parity: parent parity broke for {parity_breaks}")

    # Per-tag, per-hour metrics.
    rhoa_parity_ok = parity.get("rhoa", {}).get("identical", True)
    print(
        f"\n{'tag':10s} {'hour':>4s}   {'∫ref J/m²' if family=='energy' else '∫ref kg/m²':>10s}  "
        f"{'Δ∫/∫':>10s} {'L1':>9s} {'L∞':>9s}  {'max|Δq|':>10s}"
    )
    tag_metrics = {}
    tag_bitwise = {}
    total_ref_by_hour = {}
    if args.judge and family_table["total_var"]:
        total_full, _, _ = open_var(ref_dir / f"{family_table['total_var']}{SUFFIX}", family_table["total_var"], "reference", ref_coords, file_hashes)
        for h in hours:
            i = idx_map[h]
            total_ref_by_hour[h] = float(np.sum(total_full[:, i] * ref_rhoa[:, i] * dz))

    for tag in tags:
        stem = f"{prefix}{tag}"
        e_ref_full, _, e_ref_units = open_var(ref_dir / f"{stem}{SUFFIX}", stem, "reference", ref_coords, file_hashes)
        e_run_full, _, e_run_units = open_var(run_dir / f"{stem}{SUFFIX}", stem, "run", run_coords, file_hashes)
        if e_ref_units != e_run_units:
            die(f"units: '{stem}' differs between reference ({e_ref_units!r}) and run ({e_run_units!r})")
        if e_ref_units is not None and e_ref_units != family_table["unit"]:
            print(f"NOTICE: '{stem}' units are {e_ref_units!r}, not the expected {family_table['unit']!r}")
        tag_metrics[tag] = {}
        if args.bitwise_tags:
            tag_bitwise[tag] = bit_compare(e_ref_full[:, :overlap], e_run_full[:, :overlap], stem)
        for h in hours:
            i = idx_map[h]
            w = ref_rhoa[:, i] * dz
            w_run = None if rhoa_parity_ok else run_rhoa[:, i] * run_dz
            row = tag_row_metrics(tag, h, e_ref_full[:, i], e_run_full[:, i], w, w_run)
            tag_metrics[tag][h] = row
            print(format_tag_row(row))
        print()

    if not rhoa_parity_ok:
        print(
            "NOTICE: reference and run rhoa are not bitwise identical, so the "
            "two runs do not share one atmosphere; integral_run_ref_weighted "
            "mixes the tag's own change with rhoa's change. See "
            "integral_run_own_atmosphere for the run's own column integral."
        )

    judged = {}
    if args.judge:
        abs_residual_by_hour = {}
        res_stem = f"{prefix}{family_table['residual_name']}"
        if (ref_dir / f"{res_stem}{SUFFIX}").is_file():
            require_file(ref_dir, res_stem, "reference", file_hashes)
            require_file(run_dir, res_stem, "run", file_hashes)
            res_ref_full, _, _ = open_var(ref_dir / f"{res_stem}{SUFFIX}", res_stem, "reference", ref_coords, file_hashes)
            res_run_full, _, _ = open_var(run_dir / f"{res_stem}{SUFFIX}", res_stem, "run", run_coords, file_hashes)
            for h in hours:
                if h not in idx_map:
                    continue
                i = idx_map[h]
                w = ref_rhoa[:, i] * dz
                # The closure budget is about the run's own residual, not
                # the reference's (the reference, being the copies run, has
                # its own tiny residual from the copies' repair, R8, which
                # is a different budget).
                abs_residual_by_hour[h] = float(np.sum(np.abs(res_run_full[:, i]) * w))

            remainder_fields = (
                [f.strip() for f in args.closure_remainder_fields.split(",")]
                if args.closure_remainder_fields
                else []
            )
            remainder_ref_by_hour = {}
            if remainder_fields:
                for f in remainder_fields:
                    require_file(run_dir, f, "run", file_hashes)
                field_arrays = {
                    f: open_var(run_dir / f"{f}{SUFFIX}", f, "run", run_coords, file_hashes)[0]
                    for f in remainder_fields
                }
                for h in hours:
                    if h not in idx_map:
                        continue
                    i = idx_map[h]
                    w = ref_rhoa[:, i] * dz
                    named_sum = sum(field_arrays[f][:, i] for f in remainder_fields)
                    remainder_ref_by_hour[h] = float(np.sum(np.abs(res_run_full[:, i] - named_sum) * w))
            else:
                print(
                    "NOTICE: --judge: no --closure-remainder-fields given; "
                    "the 'what the named parts leave' remainder (R7) is skipped"
                )
            closure = compute_closure(abs_residual_by_hour, total_ref_by_hour, remainder_ref_by_hour, remainder_fields)
        else:
            print(f"NOTICE: --judge: no '{res_stem}' file; closure (R7) is skipped")
            closure = None

        rows = []
        for tag in tags:
            kind = classify_tag(tag, region_tags, source_tags)
            for h in JUDGE_HOURS:
                rows.append(judge_tag_row(tag, h, tag_metrics[tag][h], kind, total_ref_by_hour[h]))
        any_fail = (
            any(not r["passed"] for r in rows)
            or (closure and closure.get("budget_24h_ok") is False)
            or (closure and closure.get("remainder_budget_ok") is False)
        )
        judged = {
            "definitions": (
                "R5/R7 (share S, small-tag rule, source/region split, closure G(t) "
                "and its two checks, the named-parts remainder): set by the owner "
                "on 2026-09-23, recorded in G3_PLAN.md section 6.1. R8 (copies) and "
                "R9 (rain/snow/precipitation) stay proposed until WP3/WP4b name "
                "their fields."
            ),
            "g3_plan_commit": git_plan_commit(),
            "rows": rows,
            "closure": closure,
            "pass": not any_fail,
        }
        print(f"\n--judge: {'PASS' if judged['pass'] else 'FAIL'}")
        for r in rows:
            if not r["passed"]:
                print(f"  FAIL {r['tag']}@{r['hour']}h ({r['kind']}): {r['reason']}")
        if any_fail:
            print("ERROR: --judge: at least one tag failed its budget", file=sys.stderr)

    if args.json:
        report = {
            "resolved_paths": {"reference": str(ref_dir), "run": str(run_dir)},
            "family": family,
            "hours": hours,
            "hours_given": hours_given,
            "tags": tags,
            "region_tags": sorted(region_tags),
            "source_tags": sorted(source_tags),
            "parent_vars": parent_vars,
            "allow_missing": args.allow_missing,
            "time_check": {
                "n_reference_times": int(len(ref_coords.time)),
                "n_run_times": int(len(run_coords.time)),
                "overlap": int(overlap),
                "truncated": overlap != len(ref_coords.time) or overlap != len(run_coords.time),
            },
            "z_max_yaml": z_max,
            "z_top_face": float(faces[-1]),
            "weights": "w_k = rho_ref,k * dz_k, reference rhoa at each hour, both runs",
            "rhoa_parity_ok": rhoa_parity_ok,
            "parent_parity": parity,
            "tag_metrics": {tag: {str(h): row for h, row in per_hour.items()} for tag, per_hour in tag_metrics.items()},
            "tag_bitwise": tag_bitwise,
            "pairing": {
                "reference_provenance": ref_prov,
                "run_provenance": run_prov,
                "mismatches": pairing_mismatches,
                "expect_parity": args.expect_parity,
            },
            "judge": judged,
            "input_file_sha256": file_hashes,
            "script_sha256": sha256_file(Path(__file__).resolve()),
            "run_context": {
                "hostname": socket.gethostname(),
                "utc_time": datetime.now(timezone.utc).isoformat(),
                "command": " ".join(sys.argv),
            },
        }
        Path(args.json).write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
        print(f"json report: {Path(args.json).resolve()}")

    if args.judge and judged and not judged["pass"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
