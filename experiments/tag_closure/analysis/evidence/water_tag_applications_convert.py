"""Convert the water tag producer's output into what the part 5 reader reads.

    python3 water_tag_applications_convert.py RUN_DIR --out NEW_DIR [--manifest MANIFEST] [--rho FILE]

RUN_DIR is one run's output directory. It holds the producer's two files,
`water_tag_application_receipt.jsonl` and `water_tag_applications.nc`, written
by `water_tag_applications: true` (PR #170, claude/part9-producer at 2c63c5c53),
and the model's diagnostics. NEW_DIR receives:

  - `application_receipt.json`: the receipt header as written, with `steps`
    the receipt's step lines in order. `model_diff_sha256` is copied from the
    header and never recomputed.
  - `applications.npz`: `weights`, `geometry`, `weight_units`, and per channel
    prefix (the channel id with dots as underscores) `__values`,
    `__record_ids`, `__quantity`, `__units`, `__event_scale` and the four
    counters `__fallback`, `__bound`, `__clamp`, `__zero_normalization`.
  - `application_ledgers.npz`: per channel the producer's cumulative Float64
    ledger `application_ledger_<prefix>` at every receipt edge, and `rho`, the
    model's `rhoa` at the same edges, with the producer's weights and geometry.
  - `correction_accounting.json`: the reader's section (roster, coverage,
    receipt) and the field descriptors for the ledgers and `rho`.

`standalone_bundle` wraps NEW_DIR in a manifest that the reader's `Bundle`
opens, so read_receipt, read_applications and channel_metrics run on it. The
scorer's full bundle is built by convert_output.py. `attach` merges a
converted directory into such a bundle and refuses one whose candidate `rho`
is not sampled at the receipt edges.

The producer writes the NetCDF with Julia's dimension order, so Python reads
`record_values` as (record, cell), `geometry` as (coord, cell) and `ledger`
as (edge, channel, cell). `record_channel` is a 1-based channel index.
Counter k of a record and cell is bit k of `record_flags`.

Nothing is zero-filled, interpolated or rescaled. A missing or inconsistent
input is refused with its reason, exit 2. Exit 0 when written. Exit 4 when the
output directory exists.
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np

from correction_accounting import COUNTERS, QUANTITIES
from manifest import sha256_file

RECEIPT_FILE = "water_tag_application_receipt.jsonl"
ARRAYS_FILE = "water_tag_applications.nc"
ROSTER_KEY = "water_tag_application_roster"
CHANNELS_KEY = "water_tag_application_channels"
UNSUPPORTED_KEY = "water_tag_application_unsupported"
PRODUCER = "climaatmos.water_tag_applications"
# Bit k of `record_flags` is counter k, as the NetCDF's `flags` attribute says.
FLAGS_ATTRIBUTE = "fallback + 2 bound + 4 clamp + 8 zero_normalization"
LEDGER_PREFIX = "application_ledger_"
LEDGER_UNITS = "kg m^-3"
OUT_RECEIPT = "application_receipt.json"
OUT_APPLICATIONS = "applications.npz"
OUT_LEDGERS = "application_ledgers.npz"
OUT_SECTION = "correction_accounting.json"
# rhoa's z must match the producer's cell centres to this many eps of the
# file's z dtype times the largest |z|. An identity check of two copies of the
# same coordinate, not a scientific tolerance.
Z_MATCH_ULPS = 4


class ConversionError(ValueError):
    pass


def refuse(condition, message):
    if not condition:
        raise ConversionError(message)


def prefix(channel_id):
    return channel_id.replace(".", "_")


def read_receipt_lines(run_dir):
    """The header and the step lines of the producer's receipt."""
    path = Path(run_dir) / RECEIPT_FILE
    refuse(path.is_file(), f"no {RECEIPT_FILE} in {run_dir}")
    lines = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    refuse(lines, f"{RECEIPT_FILE} is empty")
    header, steps = lines[0], lines[1:]
    refuse("steps" not in header and "applications" not in header, "the receipt's first line is not a header")
    refuse(steps, f"{RECEIPT_FILE} has no accepted step")
    for key, value in (("schema_version", 1), ("semantics", "weighted_final_additive_updates"),
                       ("kind", "runtime_capture"), ("producer", PRODUCER), ("roster_key", ROSTER_KEY),
                       ("native_arrays", ARRAYS_FILE)):
        refuse(header.get(key) == value, f"receipt header {key} is {header.get(key)!r}, not {value!r}")
    roster = header.get(ROSTER_KEY)
    refuse(isinstance(roster, list) and roster and all(isinstance(c, str) and c for c in roster)
           and len(set(roster)) == len(roster), f"receipt header {ROSTER_KEY} is not a list of unique channel ids")
    channels = header.get(CHANNELS_KEY)
    refuse(isinstance(channels, list) and [c.get("id") for c in channels] == roster,
           f"receipt header {CHANNELS_KEY} differs from the roster")
    refuse(header.get(UNSUPPORTED_KEY) == [],
           f"the producer lists unsupported mechanisms: {header.get(UNSUPPORTED_KEY)!r}")
    diff = header.get("model_diff_sha256")
    refuse(isinstance(diff, str) and len(diff) == 64, "receipt header has no model_diff_sha256")
    refuse(header.get("precision") in ("Float32", "Float64"), "receipt header has no precision")
    return header, steps


def read_arrays(run_dir):
    """The producer's NetCDF, in Python's (record, cell) order."""
    from netCDF4 import Dataset
    path = Path(run_dir) / ARRAYS_FILE
    refuse(path.is_file(), f"no {ARRAYS_FILE} in {run_dir}")
    with Dataset(path) as ds:
        ds.set_auto_mask(False)
        refuse(ds.getncattr("flags") == FLAGS_ATTRIBUTE, "the NetCDF's flags attribute differs")
        out = {name: np.asarray(ds[name][:]) for name in (
            "weights", "geometry", "coord_name", "channel_id", "channel_quantity", "channel_units",
            "record_values", "record_event_scale", "record_flags", "record_channel", "record_id",
            "ledger", "ledger_time")}
        out["weight_units"] = str(ds.getncattr("weight_units"))
        out["precision"] = str(ds.getncattr("precision"))
    out["geometry"] = np.ascontiguousarray(out["geometry"].T)
    for name in ("coord_name", "channel_id", "channel_quantity", "channel_units", "record_id"):
        out[name] = [str(v) for v in out[name].tolist()]
    return out


def edges_of(steps):
    return np.asarray([steps[0]["start_seconds"]] + [s["end_seconds"] for s in steps], dtype=np.float64)


def find_diagnostic(run_dir, short, times):
    """A diagnostic's values at `times`, from the `<short>_*_inst.nc` file that holds them all."""
    from netCDF4 import Dataset
    found = []
    for path in sorted(Path(run_dir).glob(f"{short}_*_inst.nc")):
        with Dataset(path) as ds:
            if short not in ds.variables or "time" not in ds.variables:
                continue
            t = np.asarray(ds["time"][:], dtype=np.float64)
            if not np.isin(times, t).all():
                continue
            var = ds[short]
            ds.set_auto_mask(False)
            raw = np.moveaxis(np.asarray(var[:]), var.dimensions.index("time"), 0)
            rows = [int(np.flatnonzero(t == x)[0]) for x in times]
            z = np.asarray(ds["z"][:]) if "z" in ds.variables else None
            found.append((path, raw[rows].reshape(len(times), -1), z, getattr(var, "units", None)))
    refuse(found, f"no {short}_*_inst.nc in {run_dir} holds every receipt edge")
    return found[0]


def read_rho(run_dir, edges, geometry, rho_file=None):
    from netCDF4 import Dataset
    if rho_file is not None:
        with Dataset(rho_file) as ds:
            ds.set_auto_mask(False)
            t = np.asarray(ds["time"][:], dtype=np.float64)
            refuse(np.isin(edges, t).all(), f"{rho_file} lacks receipt edges")
            var = ds["rhoa"]
            raw = np.moveaxis(np.asarray(var[:]), var.dimensions.index("time"), 0)
            rows = [int(np.flatnonzero(t == x)[0]) for x in edges]
            path, values, z, units = Path(rho_file), raw[rows].reshape(len(edges), -1), np.asarray(ds["z"][:]), var.units
    else:
        path, values, z, units = find_diagnostic(run_dir, "rhoa", edges)
    refuse(units == "kg m^-3", f"rhoa in {path.name} has units {units!r}")
    refuse(values.shape[1] == geometry.shape[0], f"rhoa in {path.name} has {values.shape[1]} cells, "
           f"the producer {geometry.shape[0]}")
    refuse(z is not None and geometry.shape[1] == 1 and z.shape == (geometry.shape[0],),
           "rhoa needs one z per producer cell. Only a column is supported")
    scale = Z_MATCH_ULPS * np.finfo(z.dtype).eps * np.max(np.abs(geometry[:, 0]))
    refuse(np.all(np.abs(z.astype(np.float64) - geometry[:, 0]) <= scale),
           f"rhoa's z in {path.name} differs from the producer's cell centres")
    refuse(np.isfinite(values).all() and np.all(values > 0), "rhoa is not finite and positive")
    return values, path.name


def convert(run_dir, out, manifest=None, rho_file=None):
    """Write the four files. Returns the section. Refuses rather than repairs."""
    run_dir, out = Path(run_dir), Path(out)
    header, steps = read_receipt_lines(run_dir)
    if manifest is not None:
        ident = model_identity(json.loads(Path(manifest).read_text()))
        refuse(header["model_commit"] == ident.get("head_sha"),
               f"receipt model_commit {header['model_commit']} is not the manifest's model head_sha "
               f"{ident.get('head_sha')}")
        refuse(header["model_diff_sha256"] == ident.get("diff_sha256"),
               "receipt model_diff_sha256 is not the manifest's model diff_sha256")
    arrays = read_arrays(run_dir)
    roster = header[ROSTER_KEY]
    refuse(arrays["channel_id"] == roster, "the NetCDF's channel ids differ from the receipt roster")
    refuse(arrays["precision"] == header["precision"], "NetCDF and receipt precision differ")
    dtype = np.dtype("float32" if header["precision"] == "Float32" else "float64")
    refuse(arrays["record_values"].dtype == dtype and arrays["record_event_scale"].dtype == dtype,
           "record arrays are not in the run's precision")
    refuse(arrays["ledger"].dtype == np.float64, "the producer's ledger is not Float64")
    edges = edges_of(steps)
    refuse(all(a["end_seconds"] == b["start_seconds"] for a, b in zip(steps, steps[1:])),
           "the receipt's steps are not contiguous")
    refuse(np.array_equal(arrays["ledger_time"], edges), "ledger_time differs from the receipt edges")
    refuse(np.array_equal(edges[:1], [header["segment_start_seconds"]]),
           "the first step does not start at the segment start")
    channels = {c["id"]: c for c in header[CHANNELS_KEY]}
    index = {rid: r for r, rid in enumerate(arrays["record_id"])}
    refuse(len(index) == len(arrays["record_id"]), "duplicate record ids in the NetCDF")
    receipt_ids = [a["record_id"] for s in steps for a in s["applications"]]
    refuse(sorted(receipt_ids) == sorted(index), "receipt and NetCDF record ids differ")
    native = {"weights": arrays["weights"].astype(np.float64), "geometry": arrays["geometry"].astype(np.float64),
              "weight_units": np.asarray(arrays["weight_units"])}
    rho, rho_source = read_rho(run_dir, edges, native["geometry"], rho_file)
    ledgers = {"time": edges, "time_units": np.asarray("s"), **native, "rho": rho,
               "rho__units": np.asarray("kg m^-3"), "rho__representation": np.asarray("density"),
               "rho__sampling": np.asarray("instantaneous"), "rho__dimensions": np.asarray(["z"])}
    cadence = float(edges[1] - edges[0])
    fields = {"rho": {"path": OUT_LEDGERS, "key": "rho", "units": "kg m^-3", "representation": "density",
                      "sampling": "instantaneous", "weight_units": arrays["weight_units"],
                      "dimensions": ["z"], "expected_times": edges.tolist(), "source": rho_source}}
    coverage = []
    for c, cid in enumerate(roster):
        ch = channels[cid]
        quantity, units = ch["quantity"], ch["units"]
        refuse(quantity in QUANTITIES and QUANTITIES[quantity][0] == units, f"{cid}: unknown quantity {quantity}")
        refuse(arrays["channel_quantity"][c] == quantity and arrays["channel_units"][c] == units,
               f"{cid}: NetCDF and receipt conventions differ")
        ids = [a["record_id"] for s in steps for a in s["applications"] if a["channel"] == cid]
        rows = np.asarray([index[i] for i in ids], dtype=np.int64)
        refuse(np.all(arrays["record_channel"][rows] == c + 1), f"{cid}: record_channel differs from the receipt")
        p = prefix(cid)
        native[p + "__values"] = arrays["record_values"][rows]
        native[p + "__record_ids"] = np.asarray(ids)
        native[p + "__quantity"] = np.asarray(quantity)
        native[p + "__units"] = np.asarray(units)
        native[p + "__event_scale"] = arrays["record_event_scale"][rows]
        flags = arrays["record_flags"][rows].astype(np.int64)
        for k, name in enumerate(COUNTERS):
            native[p + "__" + name] = (flags >> k) & 1
        key = LEDGER_PREFIX + p
        ledgers[key] = arrays["ledger"][:, c, :]
        for attr, value in (("units", LEDGER_UNITS), ("representation", "density"), ("sampling", "cumulative")):
            ledgers[key + "__" + attr] = np.asarray(value)
        ledgers[key + "__dimensions"] = np.asarray(["z"])
        fields[key] = {"path": OUT_LEDGERS, "key": key, "units": LEDGER_UNITS, "representation": "density",
                       "sampling": "cumulative", "weight_units": arrays["weight_units"], "dimensions": ["z"],
                       "cadence": cadence}
        coverage.append({"id": cid, "mechanism": ch["mechanism"], "tag": ch["tag"], "compartment": ch["compartment"],
                         "status": "observed", "ledger": key,
                         "applications": {"path": OUT_APPLICATIONS, "prefix": p, "quantity": quantity, "units": units}})
    refuse(not out.exists(), f"{out} exists")
    out.mkdir(parents=True)
    receipt = {**header, "steps": steps}
    (out / OUT_RECEIPT).write_text(json.dumps(receipt, sort_keys=True, indent=1) + "\n")
    np.savez(out / OUT_APPLICATIONS, **native)
    np.savez(out / OUT_LEDGERS, **ledgers)
    section = {"correction_accounting": {"schema_version": 1, "required_channels": roster,
                                         "receipt": OUT_RECEIPT, "coverage": coverage},
               "fields": fields, "precision": header["precision"], "accepted_step_seconds": cadence,
               "end_seconds": float(edges[-1]), "start_seconds": float(edges[0]),
               "model_commit": header["model_commit"], "model_diff_sha256": header["model_diff_sha256"],
               "source_run": str(run_dir.resolve()), "run_manifest": str(Path(manifest).resolve()) if manifest else None}
    (out / OUT_SECTION).write_text(json.dumps(section, sort_keys=True, indent=1) + "\n")
    return section


def model_identity(run_manifest):
    """The tree the model ran from. A job submitted from a record tree with the
    model in a second worktree (g3base_submit.sh) records that worktree under
    `model`. A single-tree manifest is its own model identity."""
    return run_manifest.get("model") or run_manifest


def standalone_bundle(out, run_manifest=None, extra=None):
    """A manifest around a converted directory that the reader's Bundle opens.

    It carries the model's identity (head_sha, diff_sha256, the pair the
    reader compares with the receipt), julia_version, the record tree's
    `record_head_sha` and `record_diff_sha256` when the job manifest names a
    separate model tree, and the acceptance keys the reader's accounting
    functions read. It is not a scorer bundle: Bundle.validate and
    score_acceptance.py need convert_output.py's full record.
    """
    out = Path(out)
    section = json.loads((out / OUT_SECTION).read_text())
    run_manifest = run_manifest or section.get("run_manifest")
    m = json.loads(Path(run_manifest).read_text()) if run_manifest else {}
    ident = model_identity(m)
    spec = {"schema_version": 1, "precision": section["precision"], "claim": {"family": "water"},
            "accepted_step_seconds": section["accepted_step_seconds"], "end_seconds": section["end_seconds"],
            "runs": {"candidate": {"fields": section["fields"]}},
            "correction_accounting": section["correction_accounting"],
            "artifacts": {name: sha256_file(out / name) for name in (OUT_RECEIPT, OUT_APPLICATIONS, OUT_LEDGERS)}}
    spec.update(extra or {})
    data = {"head_sha": ident.get("head_sha", section["model_commit"]),
            "diff_sha256": ident.get("diff_sha256", section["model_diff_sha256"]),
            "julia_version": m.get("julia_version", "unknown"), "acceptance": spec}
    if "model" in m:
        data["record_head_sha"], data["record_diff_sha256"] = m.get("head_sha"), m.get("diff_sha256")
    path = out / "manifest.json"
    path.write_text(json.dumps(data, sort_keys=True, indent=1) + "\n")
    return path


def attach(bundle_manifest, out):
    """Merge a converted directory into a scorer bundle built by convert_output.py."""
    bundle_manifest, out = Path(bundle_manifest), Path(out)
    root = bundle_manifest.parent
    data = json.loads(bundle_manifest.read_text())
    spec = data["acceptance"]
    section = json.loads((out / OUT_SECTION).read_text())
    refuse(data.get("head_sha") == section["model_commit"] and data.get("diff_sha256") == section["model_diff_sha256"],
           "the bundle's model identity differs from the receipt's")
    rho = spec["runs"]["candidate"]["fields"].get("rho", {})
    times = rho.get("expected_times")
    refuse(times == section["fields"]["rho"]["expected_times"] or rho.get("cadence") == section["accepted_step_seconds"],
           "the bundle's candidate rho is not sampled at the receipt edges. channel_metrics aligns each ledger "
           "with rho, so convert the candidate at the accepted-step period")
    for name in (OUT_RECEIPT, OUT_APPLICATIONS, OUT_LEDGERS):
        refuse(not (root / name).exists(), f"{name} exists in the bundle")
        shutil.copy2(out / name, root / name)
        spec.setdefault("artifacts", {})[name] = sha256_file(root / name)
    for key, descriptor in section["fields"].items():
        if key != "rho":
            spec["runs"]["candidate"]["fields"][key] = descriptor
    spec["correction_accounting"] = section["correction_accounting"]
    bundle_manifest.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")
    return bundle_manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_dir")
    parser.add_argument("--out", required=True)
    parser.add_argument("--manifest", help="the run's manifest.json from manifest.py, for the model identity")
    parser.add_argument("--rho", help="a NetCDF with rhoa at every receipt edge, if not in RUN_DIR")
    args = parser.parse_args(argv)
    if Path(args.out).exists():
        print(f"REFUSED: {args.out} exists", file=sys.stderr)
        return 4
    try:
        convert(args.run_dir, args.out, args.manifest, args.rho)
    except (ConversionError, KeyError, OSError) as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        return 2
    print(f"written {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
