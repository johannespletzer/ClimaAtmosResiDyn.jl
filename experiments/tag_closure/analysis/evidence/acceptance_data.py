"""Strict offline evidence readers and narrow shared accounting operations.

The acceptance extension lives in the existing submission manifest. It
names immutable artifacts; no simulation checkout or mutable latest-run
link is used. Native NPZ exports, numeric CSV columns and existing NetCDF
outputs are supported. NetCDF requires the verifier's existing netCDF4.
"""

import csv
import hashlib
import json
import re
from dataclasses import dataclass, replace
from pathlib import Path
from zipfile import BadZipFile

import numpy as np

from manifest import sha256_file


class DataError(ValueError):
    """Required evidence is absent, inconsistent or corrupt."""


class NotAssessable(ValueError):
    """A scientific prerequisite is unavailable."""


def require(condition, message):
    if not condition:
        raise DataError(message)


def finite(value, name):
    require(np.isfinite(value).all(), f"{name}: NaN/Inf or invalid value")


def at(time, endpoint):
    """Select an exact physical endpoint. Do not truncate or interpolate."""
    hits = np.flatnonzero(time == endpoint)
    require(len(hits) == 1, f"missing or duplicate endpoint {endpoint:g} s")
    return int(hits[0])


def window(time, start, end):
    require(np.isfinite([start, end]).all() and 0 <= start < end,
            "invalid physical window")
    return at(time, start), at(time, end)


def same_bits(a, b):
    """WP0's bit-pattern convention, including signed zero and NaN payloads.

    NaNs are data failures before parity scoring. Thus the successful
    finite comparison agrees with Julia isequal, which also distinguishes
    signed zero. No dtype conversion is performed.
    """
    return (a.shape == b.shape and a.dtype == b.dtype and
            np.array_equal(np.ascontiguousarray(a).view(np.uint8),
                           np.ascontiguousarray(b).view(np.uint8)))


@dataclass
class Field:
    time: np.ndarray
    values: np.ndarray
    weights: np.ndarray
    geometry: np.ndarray
    units: str
    representation: str
    sampling: str
    weight_units: str
    dimensions: tuple
    evidence: tuple
    accumulator_kind: str = ""
    bounds: np.ndarray | None = None

    def validate(self, name, cadence=None):
        require(self.time.ndim == 1 and len(self.time) > 0,
                f"{name}: empty/non-vector time coordinate")
        finite(self.time, name + " time")
        require(np.all(np.diff(self.time) > 0),
                f"{name}: duplicate or unordered time coordinate")
        if cadence is not None:
            require(cadence > 0 and np.all(np.diff(self.time) == cadence),
                    f"{name}: missing sample or wrong cadence")
        require(self.values.ndim == 2 and len(self.values) == len(self.time),
                f"{name}: expected time × native-cell array")
        require(self.weights.shape == (self.values.shape[1],),
                f"{name}: weights do not match native cells")
        require(self.geometry.shape[0] == self.values.shape[1],
                f"{name}: native coordinates do not match cells")
        finite(self.values, name)
        finite(self.weights, name + " weights")
        finite(self.geometry, name + " coordinates")
        require(np.all(self.weights > 0), f"{name}: nonpositive native weights")
        if self.dimensions == ("scalar",):
            require(self.values.shape[1] == 1 and self.weight_units == "1" and
                    np.array_equal(self.weights, np.ones(1)),
                    f"{name}: an integrated scalar requires one unit-weighted cell")
        if self.bounds is not None:
            require(self.bounds.shape == (len(self.time), 2),
                    f"{name}: invalid interval bounds")
            finite(self.bounds, name + " interval bounds")


def aligned(a, b, name):
    require(same_bits(a.time, b.time), f"{name}: times/dtypes differ")
    require(same_bits(a.geometry, b.geometry), f"{name}: geometry/dtypes differ")
    require(same_bits(a.weights, b.weights), f"{name}: native weights/dtypes differ")
    require(a.weight_units == b.weight_units and a.dimensions == b.dimensions,
            f"{name}: geometry units/dimensions differ")
    require(a.values.shape == b.values.shape, f"{name}: field shapes differ")


def integrate(values, weights):
    """Integrate a density over native cell volumes or unit-area thickness."""
    return np.sum(values * weights, axis=-1, dtype=np.float64)


def density(field, rho):
    require(field.representation in ("density", "specific"), "expected density or specific field")
    aligned(field, rho, "density reconstruction")
    require(rho.units == "kg m^-3" and rho.representation == "density",
            "rho must be a density in kg m^-3")
    finite(rho.values, "atmospheric density")
    require(np.all(rho.values > 0), "nonpositive atmospheric density")
    if field.representation == "density":
        return field.values.astype(np.float64)
    return field.values.astype(np.float64) * rho.values.astype(np.float64)


def retained(field, rho, start, end, accepted_cadence):
    """Cellwise variation after each accepted step, before space/time sums."""
    require(field.sampling == "cumulative", "retained variation needs a cumulative ledger")
    field.validate("accepted-step ledger", accepted_cadence)
    i, j = window(field.time, start, end)
    values = density(field, rho)
    delta = np.diff(values[i:j + 1], axis=0)
    return float(np.sum(integrate(np.abs(delta), field.weights))), \
        float(integrate(values[j] - values[i], field.weights))


def cumulative_amount(field, start, end, kind):
    require(field.sampling == "cumulative" and field.accumulator_kind == kind,
            f"expected {kind} cumulative amount, not a normalized ratio")
    require(field.representation == "amount" and field.weight_units == "1" and
            field.dimensions == ("scalar",) and field.values.shape[1] == 1 and
            np.array_equal(field.weights, np.ones(1)),
            "already integrated cumulative amount requires one unit-weighted scalar; native thickness/volume would double weight it")
    i, j = window(field.time, start, end)
    require(np.all(np.diff(field.values[i:j + 1], axis=0) >= 0),
            "unexplained decreasing/reset gross accumulator")
    return float(integrate(field.values[j] - field.values[i], field.weights))


def od2_start(time, amount, pulse=None):
    """OD2: three sustained intervals below 10% of first-six-hour peak.

    The boundary is the beginning of the first qualifying interval, as in
    g3base_score.py. A declared pulse must also have fallen below 10% of
    its captured peak for those intervals. An all-zero peak has no strictly
    below-peak interval and cannot invent an established window.
    """
    finite(amount, "untagged OD2 parent integral")
    require(amount.shape == time.shape and len(time) >= 4,
            "OD2 needs at least three intervals")
    require(np.all(np.diff(time) > 0), "OD2 time order")
    rate = np.abs(np.diff(amount)) / np.diff(time)
    first = time[1:] <= 21600
    require(np.any(first), "OD2 missing first-six-hour samples")
    below = rate < 0.1 * np.max(rate[first])
    if pulse is not None:
        require(pulse.shape == time.shape, "pulse time coverage differs")
        finite(pulse, "pulse")
        below &= np.abs(pulse[1:]) < 0.1 * np.max(np.abs(pulse))
    for i in range(len(below) - 2):
        if np.all(below[i:i + 3]):
            return float(time[i])
    return None


def stitch(fields, segments, name):
    """Join exact checkpoint-linked segments, preserving real boundary changes."""
    require(len(fields) == len(segments) and len(fields) > 0, "segment roster mismatch")
    seen = set()
    result = None
    previous = None
    for field, seg in zip(fields, segments):
        require(seg.get("id") and seg["id"] not in seen, "missing/duplicate segment ID")
        seen.add(seg["id"])
        field.validate(name, seg.get("cadence"))
        values = field.values.copy()
        if field.sampling == "cumulative":
            semantics = seg.get("accumulators", {}).get(name)
            require(semantics is not None, f"{name}: missing accumulator continuation metadata")
            mode = semantics.get("mode")
            require(mode in ("continued", "reset"), "unknown accumulator semantics")
            if mode == "reset":
                require(field.representation in ("amount", "density"),
                        "reset specific ledger requires density reconstruction before stitching")
                offset = np.asarray(semantics.get("offset"), dtype=np.float64)
                require(offset.shape == (values.shape[1],) and np.isfinite(offset).all(),
                        "reset accumulator requires explicit native-cell offset")
                values = values + offset.astype(values.dtype)
        field = replace(field, values=values)
        if result is None:
            require(seg.get("parent_id") is None, "first segment has unknown ancestry")
            result = field
        else:
            require(seg.get("parent_id") == previous["id"], "broken restart ancestry")
            require(seg.get("input_checkpoint") and
                    seg["input_checkpoint"] == previous.get("output_checkpoint"),
                    "restart checkpoints do not match")
            require(result.time[-1] == field.time[0], "missing/overlapping restart interval")
            require(same_bits(result.geometry, field.geometry) and
                    same_bits(result.weights, field.weights) and
                    result.units == field.units and
                    result.representation == field.representation and
                    result.sampling == field.sampling and
                    result.accumulator_kind == field.accumulator_kind and
                    result.dimensions == field.dimensions,
                    "restart field convention/geometry changed")
            require(same_bits(result.values[-1], field.values[0]),
                    "restart boundary changed; cannot deduplicate")
            bounds = None
            if result.bounds is not None or field.bounds is not None:
                raise DataError("interval averages must carry contiguous intervals in one artifact")
            result = replace(result, time=np.concatenate((result.time, field.time[1:])),
                             values=np.concatenate((result.values, field.values[1:])), bounds=bounds,
                             evidence=result.evidence + field.evidence)
        previous = seg
    return result


class Bundle:
    """Read the optional acceptance section of a submission manifest."""

    def __init__(self, path):
        self.path = Path(path).resolve()
        self.root = self.path.parent
        self.manifest = json.loads(self.path.read_text())
        require(isinstance(self.manifest, dict), "submission manifest must be a JSON object")
        self.spec = self.manifest.get("acceptance", {})
        require(isinstance(self.spec, dict), "acceptance extension must be a JSON object")
        require(isinstance(self.spec.get("runs", {}), dict) and all(
            isinstance(r, dict) and isinstance(r.get("fields", {}), dict)
            for r in self.spec.get("runs", {}).values()), "invalid run/field inventory")
        require(isinstance(self.spec.get("tags", []), list) and all(
            isinstance(t, dict) for t in self.spec.get("tags", [])), "invalid tag inventory")
        self.used = {self.path.name: sha256_file(self.path)}
        self.cache = {}
        self.verified = {}

    def artifact(self, rel):
        require(isinstance(rel, str) and rel, "missing evidence path")
        path = Path(rel)
        require(not path.is_absolute() and ".." not in path.parts and
                "output_active" not in path.parts, "evidence must use immutable bundle-relative paths")
        resolved = (self.root / path).resolve()
        require(resolved.is_relative_to(self.root), "artifact escapes bundle")
        require(resolved.is_file(), f"missing artifact: {rel}")
        expected = self.spec.get("artifacts", {}).get(rel)
        require(isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected),
                f"missing SHA256: {rel}")
        stat = resolved.stat()
        stamp = (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
        cached = self.verified.get(rel)
        actual = cached[1] if cached and cached[0] == stamp else sha256_file(resolved)
        require(actual == expected, f"stale/corrupt checksum: {rel}")
        self.used[rel] = actual
        self.verified[rel] = (stamp, actual)
        return resolved

    def reverify(self):
        """Rehash used artifacts once at completion to catch concurrent changes."""
        for rel, expected in tuple(self.used.items()):
            path = self.path if rel == self.path.name else self.root / rel
            require(path.is_file() and sha256_file(path) == expected,
                    f"artifact changed during evaluation: {rel}")

    def validate(self):
        errors = []
        def check(fn):
            try:
                fn()
            except (DataError, KeyError, TypeError, ValueError, OSError) as exc:
                errors.append(str(exc))
        check(lambda: require(self.spec.get("schema_version") == 1,
                              "missing/unsupported acceptance extension; legacy evidence is incomplete"))
        for key in ("head_sha", "status_lines", "diff", "diff_sha256", "untracked", "config", "buildkite_files",
                    "julia_version", "hostname", "env_vars", "julia_binary", "julia_channel", "loaded_modules"):
            check(lambda key=key: require(key in self.manifest, f"missing submission provenance: {key}"))
        check(lambda: require(re.fullmatch(r"[0-9a-f]{40}", self.manifest.get("head_sha", "")),
                              "missing model commit"))
        check(lambda: require(hashlib.sha256(self.manifest.get("diff", "").encode()).hexdigest() ==
                              self.manifest.get("diff_sha256"), "recorded dirty patch hash differs/incomplete"))
        check(lambda: require(self.manifest.get("untracked", {}).get("count") ==
                              len(self.manifest.get("untracked", {}).get("files", [])),
                              "missing exact untracked-file inventory"))
        check(lambda: require(self.spec.get("experiment_commit") and
                              self.spec.get("resolved_settings") and self.spec.get("precision") in
                              ("Float32", "Float64") and self.spec.get("process_count", 0) > 0,
                              "missing experiment/config/precision/process provenance"))
        check(lambda: require(all(k in self.spec.get("resolved_settings", {}) for k in
                              ("solver", "seed", "physics", "diagnostics", "tag_definitions")),
                              "incomplete resolved solver/seed/physics/tag/diagnostic settings"))
        def submission_identity():
            mapping = self.spec.get("submission_files", {})
            config_path = self.artifact(mapping.get("config"))
            require(sha256_file(config_path) == self.manifest.get("config", {}).get("sha256"),
                    "archived resolved config differs from submission identity")
            for name, expected in self.manifest.get("buildkite_files", {}).items():
                require(expected is not None, f"incomplete submission environment file: {name}")
                path = self.artifact(mapping.get(name))
                require(sha256_file(path) == expected, f"environment file differs: {name}")
            for item in self.manifest.get("untracked", {}).get("files", []):
                path = self.artifact(mapping.get(item.get("path")))
                require(sha256_file(path) == item.get("sha256"), "untracked artifact differs")
        check(submission_identity)
        check(lambda: require(self.spec.get("scorer_commit") and self.spec.get("scorer_files"),
                              "missing scorer identity"))
        check(lambda: require(self.spec.get("acceptance_commit") and self.spec.get("acceptance_files"),
                              "missing acceptance specification identity"))
        check(lambda: require(self.spec.get("claim", {}).get("family") in
                              ("water", "energy_source", "radiation_record"), "unknown claim family"))
        check(lambda: require(self.spec.get("geometry_kind") in ("column", "sphere"), "unknown native geometry"))
        check(lambda: require(isinstance(self.spec.get("end_seconds"), (float, int)) and
                              np.isfinite(self.spec["end_seconds"]) and self.spec["end_seconds"] > 0,
                              "missing/invalid claim duration"))
        for rel in self.spec.get("artifacts", {}):
            check(lambda rel=rel: self.artifact(rel))
        for role, run in self.spec.get("runs", {}).items():
            if role != "candidate":
                def provenance(run=run, role=role):
                    m = json.loads(self.artifact(run["manifest"]).read_text())
                    require(m.get("head_sha") == run.get("model_commit") and
                            m.get("config", {}).get("sha256") == run.get("config_sha256"),
                            f"{role}: manifest/model/config identity mismatch")
                check(provenance)
            for name in run.get("fields", {}):
                check(lambda role=role, name=name: self.field(role, name))
        check(lambda: require("candidate" in self.spec.get("runs", {}), "missing candidate run"))
        return sorted(set(errors))

    def field(self, role, name):
        key = (role, name)
        if key in self.cache:
            return self.cache[key]
        run = self.spec.get("runs", {}).get(role, {})
        require(name in run.get("fields", {}), f"missing {role} variable: {name}")
        descriptor = run["fields"][name]
        segments = run.get("segments")
        if segments:
            for seg in segments:
                for label in ("input_checkpoint", "output_checkpoint"):
                    if seg.get(label):
                        checkpoint = self.artifact(seg.get(label + "_artifact"))
                        require(sha256_file(checkpoint) == seg[label], "restart checkpoint hash/identity mismatch")
            fields = [self.read({**descriptor, **seg.get("fields", {}).get(name, {})})
                      for seg in segments]
            field = stitch(fields, segments, name)
        else:
            field = self.read(descriptor)
        field.validate(role + ":" + name, descriptor.get("cadence"))
        if descriptor.get("expected_times") is not None:
            require(np.array_equal(field.time, np.asarray(descriptor["expected_times"])),
                    f"{role}:{name}: missing/extra expected samples")
        self.cache[key] = field
        return field

    def read(self, d):
        """Turn invalid archive/parser input into a structured data failure."""
        try:
            return self._read(d)
        except DataError:
            raise
        except (BadZipFile, EOFError, csv.Error, AttributeError, IndexError,
                KeyError, TypeError, ValueError, RuntimeError, OSError) as exc:
            raise DataError(f"invalid evidence variable/archive: {exc}") from exc

    def _read(self, d):
        path = self.artifact(d.get("path"))
        required = ("key", "units", "representation", "sampling", "weight_units", "dimensions")
        require(all(k in d for k in required), f"{path.name}: incomplete variable metadata")
        require(d.get("cadence") is not None or d.get("expected_times") is not None or
                d.get("bounds_key") is not None or d.get("bounds_columns") is not None,
                f"{d['key']}: missing expected sample cadence/times/intervals")
        kind = d.get("format", path.suffix.lstrip("."))
        bounds = None
        if kind == "npz":
            with path.open("rb") as stream, np.load(stream, allow_pickle=False) as archive:
                for attr in ("units", "representation", "sampling"):
                    k = d["key"] + "__" + attr
                    require(k in archive and str(archive[k].item()) == d[attr],
                            f"{d['key']}: embedded {attr} differs/missing")
                require(str(archive["time_units"].item()) == "s", "time must be physical seconds")
                require(str(archive[d.get("weight_units_key", "weight_units")].item()) == d["weight_units"], "weight units differ")
                require(tuple(archive[d["key"] + "__dimensions"].tolist()) == tuple(d["dimensions"]),
                        "native dimensions differ")
                time = archive[d.get("time_key", "time")].copy()
                values = archive[d["key"]].copy()
                weights = archive[d.get("weights_key", "weights")].copy()
                geometry = archive[d.get("geometry_key", "geometry")].copy()
                if d.get("bounds_key"):
                    bounds = archive[d["bounds_key"]].copy()
        elif kind == "csv":
            require(d.get("metadata_source"), "CSV units/conventions need a pinned metadata source")
            self.artifact(d["metadata_source"])
            with path.open() as stream:
                rows = list(csv.DictReader(stream))
            require(rows and d["key"] in rows[0], f"missing CSV column: {d['key']}")
            time = np.array([float(r[d.get("time_key", "time")]) for r in rows])
            values = np.array([[float(r[d["key"]])] for r in rows])
            weights, geometry = np.ones(1), np.zeros((1, 1))
            require(d["weight_units"] == "1" and tuple(d["dimensions"]) == ("scalar",),
                    "CSV columns are already integrated scalar amounts")
            if d.get("bounds_columns"):
                bounds = np.array([[float(r[k]) for k in d["bounds_columns"]] for r in rows])
        elif kind in ("nc", "netcdf"):
            try:
                from netCDF4 import Dataset
            except ImportError as exc:
                raise DataError("NetCDF evidence requires the existing verifier environment's netCDF4") from exc
            with Dataset(path) as ds:
                require(d["key"] in ds.variables, f"missing NetCDF variable: {d['key']}")
                var = ds[d["key"]]
                require(str(var.getncattr("units")) == d["units"], "NetCDF units differ")
                require("time" in var.dimensions, "missing named time dimension")
                require(tuple(x for x in var.dimensions if x != "time") == tuple(d["dimensions"]),
                        "NetCDF native dimensions differ")
                require(str(ds["time"].getncattr("units")) in ("s", "seconds"),
                        "NetCDF time must be physical seconds")
                raw = var[:]
                require(not np.ma.getmaskarray(raw).any(), "NetCDF missing/fill values")
                values = np.moveaxis(np.asarray(raw), var.dimensions.index("time"), 0)
                time = np.asarray(ds["time"][:])
                geometry = np.asarray(ds[d["geometry_key"]][:]).reshape(-1, 1)
                weights = np.asarray(ds[d["weights_key"]][:]).reshape(-1)
                require(str(ds[d["weights_key"]].getncattr("units")) == d["weight_units"],
                        "NetCDF native weights units differ")
                if d.get("bounds_key"):
                    bounds = np.asarray(ds[d["bounds_key"]][:])
        else:
            raise DataError(f"unsupported evidence format {kind}")
        values = values.reshape(len(time), -1)
        field = Field(time, values, weights, geometry, d["units"], d["representation"],
                      d["sampling"], d["weight_units"], tuple(d["dimensions"]),
                      (d["path"],), d.get("accumulator_kind", ""), bounds)
        field.validate(d["key"], d.get("cadence"))
        return field
