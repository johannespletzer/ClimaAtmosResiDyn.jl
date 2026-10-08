"""Convert a run's model output into the bundle that score_acceptance.py reads.

    python3 convert_output.py --family water|energy_source --candidate OUTPUT_DIR
        [--untagged OUTPUT_DIR] [--reference OUTPUT_DIR] [--period 30m]
        --planning-commit SHA --scorer-commit SHA [--case NAME]
        [--end-seconds S] [--pilot-first-hour] [--same-parent] [--git-repo CLONE]
        --out NEW_DIR

Each OUTPUT_DIR is one `output_XXXX` directory of a run. It holds the NetCDF
files the model wrote, the merged config `*.yml`, `provenance.txt`, the
closure and audit tables, and the `manifest.json` that manifest.py wrote at
submission. The candidate's manifest becomes the bundle's submission record.

NAME_TABLE below maps every logical name the scorer reads to the model
variable that holds it, with its units, native geometry and weight source.
Each row resolves to an array copied bit for bit into `<role>.npz`, or it is
recorded as missing with the model variable and the reason. A missing
variable is left out of the bundle, so the scorer reports it as a data
failure under its logical name. Nothing is zero-filled, interpolated,
summed across cells or rescaled.

Weights. A column's native weight is the cell thickness Δz in m, from faces
rebuilt from the `z` centres, z_f[0] = 0 and z_f[k+1] = 2 z_c[k] - z_f[k], as
compare_runs.py does (G3_PLAN 6.1.1). The density ρ enters through the `rho`
field, which the scorer multiplies in before it integrates. So a run's
integrand weight is ρ Δz, and the reference's at a profile row is ρ_ref Δz.
Writing ρ Δz into the weights would weight twice. A sphere needs a native
cell-area variable in the output, then its weight is area × Δz in m^3.
Without one the converter refuses: the model writes remapped
longitude-latitude fields, whose quadrature is not native. A table column is
already a domain integral and has one unit weight.

Exit 0: the bundle is written and every name-table row resolved.
Exit 2: the bundle is written and names its missing variables, or the
converter refused and wrote nothing (the reason is printed).
Exit 4: the command line is invalid or the output directory exists.
"""

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from compare_runs import PARITY_ONLY_EXCLUDED_PREFIXES, parse_tag_block, yaml_flat_scalar, yaml_top_level_blocks
from manifest import sha256_file
from score_acceptance import local_identities

ROLES = ("candidate", "reference", "untagged")
TAG_KEYS = {"water": "water_tracers", "energy_source": "energy_source_tags"}
TABLES = {"water_closure": "water_tag_closure.csv", "water_audit": "water_tag_audit.csv",
          "energy_closure": "energy_source_tag_closure.csv", "energy_audit": "energy_source_tag_audit.csv"}
# Rebuilt top face against the config's z_max, relative, as compare_runs.py checks it.
TOP_FACE_RELATIVE = 1e-9
FILE_RE = re.compile(r"^(?P<short>.+)_(?P<period>\d+(?:s|m|h|d|mo|y))_(?P<reduction>inst|average)\.nc$")
DURATION_RE = re.compile(r'^"?(?P<value>\d+(?:\.\d+)?)(?P<unit>secs|mins|hours|days)"?$')
SECONDS = {"secs": 1.0, "mins": 60.0, "hours": 3600.0, "days": 86400.0}


class ConversionError(Exception):
    """The output cannot be converted. Nothing is written."""


def refuse(condition, message):
    if not condition:
        raise ConversionError(message)


@dataclass(frozen=True)
class Name:
    """One row of the name table.

    `source`: `field` is a NetCDF field on the model's levels, `surface` one
    without levels, a TABLES key is a column of that table, and `none` means
    the model writes no variable with the scorer's convention.
    `roles`: the runs whose variable the scorer reads. `all`, `candidate`,
    `untagged`, `tagged` (candidate and reference), or `reference_copies`
    (a reference run with updraft copies). `expand`: `tag`, `partition` or
    `process` repeats the row for each configured tag, partition tag or
    recorded energy process. `<amount>` units are kg m^-2 or J m^-2 on a
    column and kg or J on a sphere. `requires` names a table column that
    must be 1 at every row for the amount to mean what the scorer reads.
    """
    logical: str
    family: str
    roles: str
    source: str
    model: str
    units: str
    representation: str = ""
    sampling: str = "instantaneous"
    accumulator: str = ""
    expand: str = ""
    compartments: str = "total"
    requires: str = ""
    reason: str = ""


W, E, B = "water", "energy_source", "both"
NAME_TABLE = (
    Name("rho", B, "all", "field", "rhoa", "kg m^-3", "density"),
    Name("water_parent", B, "all", "field", "hus", "kg kg^-1", "specific"),
    Name("temperature", B, "all", "field", "ta", "K", "intensive"),
    Name("tag_<tag>", W, "tagged", "field", "q_tag_<tag>", "kg kg^-1", "specific", expand="tag"),
    Name("parent_N", W, "candidate", "none", "", "kg kg^-1", "specific", compartments="NRS",
         reason="no field holds q_tot - q_rai - q_sno, and the converter derives no differences"),
    Name("parent_R", W, "candidate", "field", "husra", "kg kg^-1", "specific", compartments="NRS"),
    Name("parent_S", W, "candidate", "field", "hussn", "kg kg^-1", "specific", compartments="NRS"),
    Name("tag_N_<tag>", W, "candidate", "field", "q_ntag_<tag>", "kg kg^-1", "specific", expand="tag",
         compartments="NRS"),
    Name("tag_R_<tag>", W, "candidate", "field", "q_rtag_<tag>", "kg kg^-1", "specific", expand="tag",
         compartments="NRS"),
    Name("tag_S_<tag>", W, "candidate", "field", "q_stag_<tag>", "kg kg^-1", "specific", expand="tag",
         compartments="NRS"),
    Name("led_fix_<tag>", W, "candidate", "field", "q_tag_led_fix_<tag>", "kg kg^-1", "specific",
         "cumulative", expand="tag"),
    Name("led_inc_<tag>", W, "candidate", "field", "q_tag_led_inc_<tag>", "kg kg^-1", "specific",
         "cumulative", expand="tag"),
    Name("led_fix_<tag>_applicable", W, "candidate", "water_audit", "led_fix_<tag>_applicable", "1", "flag",
         expand="tag"),
    Name("led_inc_<tag>_applicable", W, "candidate", "water_audit", "led_inc_<tag>_applicable", "1", "flag",
         expand="tag"),
    Name("negative_water_void", B, "candidate", "water_closure", "negative_water_void", "1", "flag"),
    Name("repair_retained", W, "candidate", "water_audit", "led_repair_retained", "<amount>", "amount",
         "cumulative", "retained_cell_step_repair", requires="ledger_cadence_step"),
    Name("repair_attempted", W, "candidate", "water_audit", "led_repair_attempted", "<amount>", "amount",
         "cumulative", "attempted_application_repair", requires="ledger_cadence_step"),
    Name("repair_retained", W, "reference_copies", "water_audit", "led_uprepair_retained", "<amount>", "amount",
         "cumulative", "retained_cell_step_repair", requires="ledger_cadence_step"),
    Name("repair_attempted", W, "reference_copies", "water_audit", "led_uprepair_attempted", "<amount>", "amount",
         "cumulative", "attempted_application_repair", requires="ledger_cadence_step"),
    Name("copy_residual", W, "reference_copies", "none", "", "kg kg^-1", "specific",
         reason="q_tag_copy_res is per unit mass of updraft air, and the scorer weights by the grid-mean density"),
    Name("named_remainder", W, "candidate", "none", "", "kg kg^-1", "specific",
         reason="the model writes no named-parts remainder field"),
    Name("precip_parent", W, "candidate", "surface", "pr", "kg m^-2 s^-1", "rate"),
    Name("precip_<tag>", W, "candidate", "surface", "pr_tag_<tag>", "kg m^-2 s^-1", "rate", expand="partition"),
    Name("tag_<tag>", E, "tagged", "field", "e_src_<tag>", "J kg^-1", "specific", expand="tag"),
    Name("residual", E, "tagged", "field", "e_src_res", "J kg^-1", "specific"),
    Name("led_src_<tag>", E, "tagged", "field", "e_src_led_src_<tag>", "J kg^-1", "specific", "cumulative",
         expand="tag"),
    Name("led_fix_<tag>", E, "candidate", "field", "e_src_led_fix_<tag>", "J kg^-1", "specific", "cumulative",
         expand="tag"),
    Name("led_inc_<tag>", E, "candidate", "field", "e_src_led_inc_<tag>", "J kg^-1", "specific", "cumulative",
         expand="tag"),
    Name("led_fix_<tag>_applicable", E, "candidate", "energy_audit", "led_fix_<tag>_applicable", "1", "flag",
         expand="tag"),
    Name("led_inc_<tag>_applicable", E, "candidate", "energy_audit", "led_inc_<tag>_applicable", "1", "flag",
         expand="tag"),
    Name("source_partition_valid", E, "tagged", "energy_closure", "source_partition_valid", "1", "flag"),
    Name("throughput", E, "tagged", "energy_closure", "source_throughput", "<amount>", "amount", "cumulative",
         "accepted_step_source_variation"),
    Name("repair_retained", E, "tagged", "energy_audit", "led_repair_retained", "<amount>", "amount",
         "cumulative", "retained_cell_step_repair", requires="ledger_cadence_step"),
    Name("repair_attempted", E, "tagged", "energy_audit", "led_repair_attempted", "<amount>", "amount",
         "cumulative", "attempted_application_repair", requires="ledger_cadence_step"),
    Name("record_<process>", E, "candidate", "field", "e_prc_<process>", "J kg^-1", "specific", "cumulative",
         expand="process"),
    Name("energy_parent", E, "untagged", "none", "", "J kg^-1", "specific",
         reason="no field holds the specific total energy. The closure table's total is a domain integral"),
    Name("newton_error", B, "candidate", "none", "", "1", "ratio",
         reason="the model writes no fixed-parent Newton trial error"),
    Name("process_amount", B, "candidate", "none", "", "<amount>", "weighted_applied_amount", "applied_interval",
         reason="the model writes no weighted applied process amounts"),
    Name("process_share", B, "tagged", "none", "", "1", "ratio", "applied_interval",
         reason="the model writes no applied share taken from the giving pool"),
)


def name_table_sha256():
    text = json.dumps([asdict(n) for n in NAME_TABLE], sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode()).hexdigest()


def seconds(raw, what):
    m = DURATION_RE.match(raw or "")
    refuse(m is not None, f"cannot read {what} {raw!r} as a duration")
    return float(m["value"]) * SECONDS[m["unit"]]


def faces_and_thickness(z_centres, z_max):
    """Faces from the centres, which are exact where centres are face midpoints."""
    z = np.asarray(z_centres, dtype=np.float64)
    refuse(z.ndim == 1 and len(z) > 0 and np.isfinite(z).all(), "z centres are empty or not finite")
    faces = np.empty(len(z) + 1, dtype=np.float64)
    faces[0] = 0.0
    for k in range(len(z)):
        faces[k + 1] = 2.0 * z[k] - faces[k]
    dz = np.diff(faces)
    refuse(np.all(dz > 0), f"non-positive cell thickness at levels {np.flatnonzero(dz <= 0).tolist()}")
    refuse(z_max is not None, "the config names no z_max to check the rebuilt top face against")
    refuse(abs(faces[-1] - z_max) <= TOP_FACE_RELATIVE * abs(z_max),
           f"rebuilt top face {faces[-1]} differs from z_max {z_max}")
    return faces, dz


class Run:
    """One output directory with its config, manifest and provenance.txt."""

    def __init__(self, role, directory):
        self.role = role
        self.dir = Path(directory)
        refuse(self.dir.is_dir(), f"{role}: no output directory {directory}")
        manifest = self.dir / "manifest.json"
        refuse(manifest.is_file(), f"{role}: no manifest.json from manifest.py in {directory}")
        self.manifest_path = manifest
        self.manifest = json.loads(manifest.read_text())
        ymls = sorted(self.dir.glob("*.yml"))
        refuse(len(ymls) == 1, f"{role}: expected one merged config *.yml, found {[p.name for p in ymls]}")
        self.yml_path = ymls[0]
        self.yml = self.yml_path.read_text()
        self.header = {}
        if (self.dir / "provenance.txt").is_file():
            for line in (self.dir / "provenance.txt").read_text().splitlines():
                key, _, value = line.partition(":")
                self.header[key.strip()] = value.strip()
        self.files = {}
        for path in self.dir.glob("*.nc"):
            m = FILE_RE.match(path.name)
            if m:
                self.files[(m["short"], m["period"], m["reduction"])] = path
        self.period = None

    def config(self, key):
        value = yaml_flat_scalar(self.yml, key)
        return None if value in (None, "~") else value.strip('"')

    def tags(self, family):
        parsed = parse_tag_block(self.yml, TAG_KEYS[family]) or []
        # A tag with a source is a source tag, as compare_runs.py reads it.
        return [{"name": n, "kind": "source" if source else "region", "partition": bool(region and not source)}
                for n, region, source in parsed]

    def processes(self):
        blocks, _ = yaml_top_level_blocks(self.yml)
        return re.findall(r'^\s+- "([^"]+)"\s*$', blocks.get("energy_process_record", ""), re.MULTILINE)

    def diagnostics(self):
        blocks, _ = yaml_top_level_blocks(self.yml)
        return sorted(set(re.findall(r'^\s+- "([^"]+)"\s*$', blocks.get("diagnostics", ""), re.MULTILINE)))

    def periods(self):
        return sorted({p for (_, p, r) in self.files if r == "inst"})


class Geometry:
    """A run's native weights and coordinates, from its own output only."""

    def __init__(self, run, kind):
        self.run, self.kind = run, kind
        self.z = None
        self.dz = None
        self.top_face = None
        self.area = None
        if kind == "sphere":
            refuse(str(run.config("deep_atmosphere")).lower() != "true",
                   f"{run.role}: a deep-atmosphere sphere scales cell area with height. No native volume is written")
            self.area = self.find_area()

    def find_area(self):
        from netCDF4 import Dataset
        for path in sorted(self.run.dir.glob("*.nc")):
            with Dataset(path) as ds:
                for name, var in ds.variables.items():
                    tagged = getattr(var, "standard_name", "") == "cell_area" or name in ("area", "cell_area")
                    if tagged and getattr(var, "units", "") == "m^2" and "time" not in var.dimensions:
                        values = np.asarray(var[:], dtype=np.float64)
                        refuse(np.isfinite(values).all() and np.all(values > 0),
                               f"{self.run.role}: cell areas in {path.name} are not finite and positive")
                        return var.dimensions, values
        raise ConversionError(f"{self.run.role}: sphere output has no native cell-area variable. "
                              "The model writes remapped longitude-latitude fields, so the converter refuses "
                              "rather than invent quadrature weights")

    def set_levels(self, z):
        z = np.asarray(z, dtype=np.float64)
        if self.z is None:
            refuse(str(self.run.config("topography") or "NoWarp") == "NoWarp",
                   f"{self.run.role}: faces rebuilt from centres assume a flat surface at z = 0")
            z_max = self.run.config("z_max")
            faces, self.dz = faces_and_thickness(z, float(z_max) if z_max is not None else None)
            self.z, self.top_face = z, float(faces[-1])
        refuse(np.array_equal(self.z.view(np.uint8), z.view(np.uint8)),
               f"{self.run.role}: native fields have different z coordinates")

    def weights(self, dims, coords):
        """Native weights and coordinates for a field with these non-time dimensions."""
        if not dims:
            return np.ones(1), np.zeros((1, 1)), "1", ("scalar",)
        shape = [len(coords[d]) for d in dims]
        weight = np.ones(shape, dtype=np.float64)
        if "z" in dims:
            self.set_levels(coords["z"])
            axis = dims.index("z")
            weight = weight * self.dz.reshape([-1 if i == axis else 1 for i in range(len(dims))])
        horizontal = [d for d in dims if d != "z"]
        if horizontal:
            refuse(self.kind == "sphere", f"{self.run.role}: horizontal dimensions {horizontal} on a column")
            area_dims, area = self.area
            refuse(sorted(area_dims) == sorted(horizontal),
                   f"{self.run.role}: cell areas on {area_dims} do not match field dimensions {horizontal}")
            area = np.transpose(area, [area_dims.index(d) for d in horizontal])
            index = [dims.index(d) for d in horizontal]
            # The horizontal axes keep the field's order, so inserting the level axis aligns them.
            weight = weight * np.expand_dims(area, [i for i in range(len(dims)) if i not in index])
        grids = np.meshgrid(*[np.asarray(coords[d], dtype=np.float64) for d in dims], indexing="ij")
        geometry = np.stack([g.reshape(-1) for g in grids], axis=1)
        if self.kind == "column":
            units = "m"
        else:
            units = "m^3" if "z" in dims else "m^2"
        return weight.reshape(-1), geometry, units, tuple(dims)


def read_field(run, short, units):
    """A NetCDF field at the run's period, time first. Returns (array, None) or (None, reason)."""
    from netCDF4 import Dataset
    path = run.files.get((short, run.period, "inst"))
    if path is None:
        return None, f"no {short}_{run.period}_inst.nc in the output"
    with Dataset(path) as ds:
        if short not in ds.variables:
            return None, f"{path.name} has no variable {short}"
        var = ds[short]
        actual = getattr(var, "units", None)
        if actual != units:
            return None, f"{short} has units {actual!r}, the name table says {units!r}"
        if "time" not in var.dimensions or str(getattr(ds["time"], "units", "")) not in ("s", "seconds"):
            return None, f"{short} has no time coordinate in physical seconds"
        raw = var[:]
        if np.ma.getmaskarray(raw).any():
            return None, f"{short} has fill values"
        values = np.moveaxis(np.asarray(raw), var.dimensions.index("time"), 0)
        dims = tuple(d for d in var.dimensions if d != "time")
        if "z" in dims and str(getattr(ds["z"], "units", "")) != "m":
            return None, f"{short}: its z coordinate is not in m"
        coords = {d: np.asarray(ds[d][:]) for d in dims}
        time = np.asarray(ds["time"][:], dtype=np.float64)
    return {"time": time, "values": values.reshape(len(time), -1), "dims": dims, "coords": coords,
            "file": path.name}, None


def read_column(run, table, column, requires=""):
    """A column of the run's closure or audit table, a domain integral at each row."""
    path = run.dir / TABLES[table]
    if not path.is_file():
        return None, f"no {path.name} in the output"
    with path.open() as stream:
        rows = list(csv.DictReader(stream))
    if not rows or column not in rows[0]:
        return None, f"{path.name} has no column {column}"
    if requires:
        flags = [r.get(requires) for r in rows]
        if any(f is None or float(f) != 1.0 for f in flags):
            return None, f"{path.name}: {requires} is not 1 at every row, so {column} is not exact per accepted step"
    try:
        time = np.array([float(r["time"]) for r in rows])
        values = np.array([[float(r[column])] for r in rows])
    except (KeyError, TypeError, ValueError) as exc:
        return None, f"{path.name}: column {column} or time is not numeric at every row ({exc})"
    return {"time": time, "values": values, "dims": (), "coords": {}, "file": path.name}, None


def expand(name, tags, processes):
    if name.expand == "tag":
        items = [t["name"] for t in tags]
    elif name.expand == "partition":
        items = [t["name"] for t in tags if t["partition"]]
    elif name.expand == "process":
        items = list(processes)
    else:
        return [(name.logical, name.model)]
    key = "<process>" if name.expand == "process" else "<tag>"
    return [(name.logical.replace(key, i), name.model.replace(key, i)) for i in items]


def applies(name, family, role, run, compartments):
    if name.family not in (family, B):
        return False
    if name.compartments == "NRS" and compartments != ["N", "R", "S"]:
        return False
    copies = str(run.config("water_tag_updraft_copy" if family == "water" else
                            "energy_source_tag_updraft_copy")).lower() == "true"
    return {"all": True, "candidate": role == "candidate", "tagged": role != "untagged",
            "untagged": role == "untagged", "reference_copies": role == "reference" and copies}[name.roles]


def cadence(time):
    steps = np.diff(time)
    if len(steps) and np.all(steps == steps[0]) and steps[0] > 0:
        return {"cadence": float(steps[0])}
    return {"expected_times": [float(t) for t in time]}


def convert(args):
    family = args.family
    runs = {"candidate": Run("candidate", args.candidate)}
    for role in ("untagged", "reference"):
        if getattr(args, role):
            runs[role] = Run(role, getattr(args, role))
    cand = runs["candidate"]
    tags = cand.tags(family)
    refuse(tags, f"the candidate's config lists no {TAG_KEYS[family]}")
    if "reference" in runs:
        refuse(runs["reference"].tags(family) == tags, "the reference lists different tags from the candidate")
    config = cand.config("config")
    refuse(config in ("column", "sphere"), f"unsupported config {config!r}: only a column or a sphere")
    periods = cand.periods()
    period = args.period or (periods[0] if len(periods) == 1 else None)
    refuse(period is not None, f"the candidate writes several periods {periods}. Choose one with --period")
    for run in runs.values():
        refuse(period in run.periods(), f"{run.role}: no {period} outputs, it writes {run.periods()}")
        run.period = period
    compartments = (["N", "R", "S"] if family == "water" and
                    str(cand.config("water_tag_precipitation")).lower() == "true" else ["total"])
    processes = cand.processes() if family == "energy_source" else []
    amount = ("kg" if family == "water" else "J") + ("" if config == "sphere" else " m^-2")

    out = Path(args.out)
    out.mkdir(parents=True)
    artifacts, record, spec_runs = {}, [], {}
    try:
        for role, run in runs.items():
            geometry = Geometry(run, config)
            archive = {"time_units": np.array("s"), "scalar_weights": np.ones(1),
                       "scalar_geometry": np.zeros((1, 1)), "scalar_weight_units": np.array("1")}
            weight_keys = {}
            fields = {}

            def add(logical, data, units, representation, sampling, accumulator, entry):
                weights, coords, weight_units, dims = geometry.weights(data["dims"], data["coords"])
                if dims == ("scalar",):
                    keys = ("scalar_weights", "scalar_geometry", "scalar_weight_units")
                else:
                    label = "_".join(dims)
                    keys = weight_keys.setdefault(dims, ("weights_" + label, "geometry_" + label,
                                                         "weight_units_" + label))
                    archive[keys[0]], archive[keys[1]], archive[keys[2]] = weights, coords, np.array(weight_units)
                archive[logical] = data["values"]
                archive[logical + "__time"] = data["time"]
                for k, v in (("units", units), ("representation", representation), ("sampling", sampling)):
                    archive[logical + "__" + k] = np.array(v)
                archive[logical + "__dimensions"] = np.array(dims)
                d = {"path": role + ".npz", "key": logical, "time_key": logical + "__time", "units": units,
                     "representation": representation, "sampling": sampling, "weight_units": weight_units,
                     "dimensions": list(dims), "weights_key": keys[0], "geometry_key": keys[1],
                     "weight_units_key": keys[2], **cadence(data["time"])}
                if accumulator:
                    d["accumulator_kind"] = accumulator
                fields[logical] = d
                record.append({**entry, "status": "resolved", "file": data["file"]})

            for name in NAME_TABLE:
                if not applies(name, family, role, run, compartments):
                    continue
                for logical, model in expand(name, tags, processes):
                    units = amount if name.units == "<amount>" else name.units
                    entry = {"role": role, "logical": logical, "model": model, "source": name.source,
                             "units": units}
                    if name.source == "none":
                        record.append({**entry, "status": "missing", "reason": name.reason})
                        continue
                    if name.source in ("field", "surface"):
                        data, reason = read_field(run, model, units)
                        if data is not None and (("z" in data["dims"]) != (name.source == "field")):
                            expected = "the model's levels" if name.source == "field" else "a surface field"
                            data, reason = None, f"{model} has dimensions {data['dims']}, expected {expected}"
                    else:
                        data, reason = read_column(run, name.source, model, name.requires)
                    if data is None:
                        record.append({**entry, "status": "missing", "reason": reason})
                        continue
                    add(logical, data, units, name.representation, name.sampling, name.accumulator, entry)
            # Every other exported field is compared bit for bit with the untagged twin.
            mapped = {n.model for n in NAME_TABLE}
            for (short, p, reduction) in sorted(run.files):
                if (p != period or reduction != "inst" or short in mapped or
                        short.startswith(PARITY_ONLY_EXCLUDED_PREFIXES)):
                    continue
                from netCDF4 import Dataset
                with Dataset(run.files[(short, p, reduction)]) as ds:
                    units = getattr(ds[short], "units", "") if short in ds.variables else ""
                data, reason = read_field(run, short, units)
                entry = {"role": role, "logical": "export_" + short, "model": short, "source": "export",
                         "units": units}
                if data is None:
                    record.append({**entry, "status": "missing", "reason": reason})
                else:
                    add("export_" + short, data, units, "exported", "instantaneous", "", entry)
            np.savez(out / (role + ".npz"), **archive)
            copied = {}
            for source in (run.manifest_path, run.yml_path, run.dir / "provenance.txt"):
                if source.is_file():
                    rel = f"{role}/{source.name}"
                    (out / role).mkdir(exist_ok=True)
                    shutil.copyfile(source, out / rel)
                    copied[source.name] = rel
            spec_runs[role] = {"fields": fields, "output_directory": str(run.dir.resolve()),
                               "config_file": copied.get(run.yml_path.name),
                               "weights": {"source": "faces rebuilt from the z centres, z_f[0] = 0" if config == "column"
                                           else "native cell area times the thickness from the z centres",
                                           "top_face_m": geometry.top_face,
                                           "z_max_m": float(run.config("z_max")) if run.config("z_max") else None,
                                           "density_field": "rho (rhoa), multiplied in by the scorer"}}
            if role != "candidate":
                spec_runs[role].update(manifest=copied["manifest.json"], model_commit=run.manifest.get("head_sha"),
                                       config_sha256=run.manifest.get("config", {}).get("sha256"))
            artifacts.update({rel: None for rel in copied.values()})
            artifacts[role + ".npz"] = None

        submission, missing_files = submission_files(cand.manifest, out, args.git_repo)
        artifacts.update({rel: None for rel in submission.values()})
        dt = seconds(cand.config("dt"), "dt")
        end = args.end_seconds if args.end_seconds is not None else seconds(cand.config("t_end"), "t_end")
        ntasks = cand.header.get("ntasks")
        spec = {
            "schema_version": 1, "experiment_commit": cand.manifest.get("head_sha"),
            "scorer_commit": args.scorer_commit, "planning_commit": args.planning_commit,
            **local_identities(), "geometry_kind": config, "case": args.case or cand.dir.parent.name,
            "claim": {"family": family, "scope": "converted model output: " +
                      ", ".join(f"{r} {runs[r].dir.parent.name}" for r in runs), "precipitation": False},
            "precision": cand.config("FLOAT_TYPE"), "end_seconds": end, "accepted_step_seconds": dt,
            "resolved_settings": {
                "solver": {k: cand.config(k) for k in ("ode_algo", "dt", "max_newton_iters_ode", "newton_rtol",
                                                        "update_constrain_state_every")},
                "seed": {k: cand.config(k) for k in ("perturb_initstate", "radiation_reset_rng_seed")},
                "physics": {k: cand.config(k) for k in ("config", "initial_condition", "microphysics_model",
                                                         "z_elem", "z_max", "dz_bottom", "z_stretch")},
                "diagnostics": cand.diagnostics(), "tag_definitions": tags},
            "submission_files": submission, "tags": tags, "compartments": compartments,
            "runs": spec_runs, "required_parent_fields": parent_fields(spec_runs),
            "parent_capture_scope": "exported", "same_parent_comparisons": bool(args.same_parent),
            "conversion": {"converter_sha256": sha256_file(Path(__file__)), "name_table_sha256": name_table_sha256(),
                           "period": period, "variables": record, "missing_submission_files": missing_files},
        }
        if ntasks is not None and ntasks.isdigit():
            spec["process_count"] = int(ntasks)
        if args.pilot_first_hour:
            spec["pilot_first_hour"] = True
        if family == "energy_source":
            spec["energy_ledger_per_tag"] = str(cand.config("energy_source_tag_ledger_per_tag")).lower() == "true"
            spec["energy_offset"] = float(cand.config("energy_source_tag_offset") or 0)
            spec["throughput_accumulation"] = "accepted_step"
            recorded = [p for p in processes if "record_" + p in spec_runs["candidate"]["fields"]]
            spec["record_processes"], spec["expected_record_processes"] = recorded, processes
        (out / "conversion.json").write_text(json.dumps(spec["conversion"], sort_keys=True, indent=2) + "\n")
        artifacts["conversion.json"] = None
        spec["artifacts"] = {rel: sha256_file(out / rel) for rel in sorted(artifacts)}
        manifest = {**cand.manifest, "acceptance": spec}
        (out / "manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2, allow_nan=False) + "\n")
    except BaseException:
        shutil.rmtree(out)
        raise
    return out / "manifest.json", [r for r in record if r["status"] == "missing"], missing_files


def parent_fields(spec_runs):
    """The exported parent fields compared with the untagged twin, as compare_runs.py --parity-only does."""
    names = ["rho", "water_parent", "temperature"]
    names += sorted(n for n in spec_runs["candidate"]["fields"] if n.startswith("export_"))
    return names


def from_git(git_repo, commit, repo, path):
    """A tracked file's bytes at the submission commit, when its worktree is gone."""
    if not git_repo or not commit:
        return None
    try:
        rel = path.relative_to(repo)
    except ValueError:
        return None
    done = subprocess.run(["git", "--no-optional-locks", "-C", str(git_repo), "show", f"{commit}:{rel.as_posix()}"],
                          capture_output=True)
    return done.stdout if done.returncode == 0 else None


def submission_files(manifest, out, git_repo=None):
    """Copy the submission's config, environment and untracked files when their hashes still match.

    A file whose worktree is gone is read from `git_repo` at the submission's
    commit, and kept only if its hash matches the record.
    """
    mapping, missing = {}, []
    repo = Path(manifest.get("repo", ""))
    wanted = [("config", Path(manifest.get("config", {}).get("path", "")),
               manifest.get("config", {}).get("sha256"))]
    wanted += [(name, repo / ".buildkite" / name, sha) for name, sha in manifest.get("buildkite_files", {}).items()]
    wanted += [(item.get("path"), repo / item.get("path", ""), item.get("sha256"))
               for item in manifest.get("untracked", {}).get("files", [])]
    for key, path, sha in wanted:
        if sha is None:
            missing.append({"file": key, "reason": "the submission record holds no hash for it"})
            continue
        if path.is_file():
            content = path.read_bytes()
        else:
            content = from_git(git_repo, manifest.get("head_sha"), repo, path)
        if content is None:
            missing.append({"file": key, "reason": f"{path} no longer exists"})
        elif hashlib.sha256(content).hexdigest() != sha:
            missing.append({"file": key, "reason": f"{path} has changed since submission"})
        else:
            rel = "submission/" + key.replace("/", "_")
            (out / "submission").mkdir(exist_ok=True)
            (out / rel).write_bytes(content)
            mapping[key] = rel
    return mapping, missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--family", choices=("water", "energy_source"), required=True)
    for role in ROLES:
        parser.add_argument("--" + role, required=role == "candidate", help=f"the {role} run's output directory")
    parser.add_argument("--period", help="output period, such as 30m or 1h, when the run writes several")
    parser.add_argument("--planning-commit", required=True)
    parser.add_argument("--scorer-commit", required=True)
    parser.add_argument("--case")
    parser.add_argument("--end-seconds", type=float)
    parser.add_argument("--pilot-first-hour", action="store_true")
    parser.add_argument("--same-parent", action="store_true",
                        help="the reference shares the candidate's parent. The scorer checks it bit for bit")
    parser.add_argument("--git-repo", help="a clone holding the submission commit, for files whose worktree is gone")
    parser.add_argument("--out", required=True, help="a new bundle directory")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code == 0 else 4
    if Path(args.out).exists():
        print("not converted: the output directory exists", file=sys.stderr)
        return 4
    try:
        manifest, missing, files = convert(args)
    except ConversionError as exc:
        print("refused: " + str(exc), file=sys.stderr)
        return 2
    print(manifest)
    for m in missing:
        print(f"DATA FAILURE: {m['role']} {m['logical']} ({m['model'] or 'no model variable'}): {m['reason']}")
    for f in files:
        print(f"DATA FAILURE: submission file {f['file']}: {f['reason']}")
    return 2 if missing or files else 0


if __name__ == "__main__":
    sys.exit(main())
