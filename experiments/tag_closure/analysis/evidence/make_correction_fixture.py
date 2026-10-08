"""Create a separately identified cancellation example, never runtime evidence.

    python3 make_correction_fixture.py NEW_DIRECTORY [--family water|energy_source]

Every accepted hour contains +1 then -1 in each of two unit-volume cells.
Over 24 hours signed S and retained H are zero
accepted application A is 96.
The production completeness gate remains blocked because this is synthetic.
"""

import argparse
import json
from pathlib import Path

import numpy as np

from make_acceptance_fixture import write_fixture
from manifest import sha256_file
from score_acceptance import local_identities


def attach_fixture(manifest, *, records=None, ledgers=None, family="water", dtype=np.float64,
                   counters=None, receipt_pin=None, quantity=None):
    """Attach explicitly supplied native ledgers/records to an analytic bundle.

    Tests supply ledger arrays independently of their application arrays.
    This routine assembles files
    it is not an expected-value oracle.
    """
    manifest = Path(manifest)
    root = manifest.parent
    data = json.loads(manifest.read_text())
    spec = data["acceptance"]
    spec["precision"] = "Float32" if np.dtype(dtype) == np.dtype("float32") else "Float64"
    with np.load(root / "candidate.npz", allow_pickle=False) as archive:
        candidate = {k: archive[k].copy() for k in archive.files}
    # Native arrays retain their dtype. Geometry and quadrature stay Float64.
    for k, value in candidate.items():
        if (value.ndim == 2 and value.dtype.kind == "f" and not k.endswith("__bounds") and
                k not in ("geometry", "scalar_geometry")):
            candidate[k] = value.astype(dtype)
    times = candidate["time"]
    pin = receipt_pin or {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers",
                          "version": "synthetic-0.10", "b_exp": [1.0], "b_imp": [1.0], "implicit_diagonal": [1.0]}
    records = records or {"fix.pbl.total": [[{"values": [1, 1]}, {"values": [-1, -1]}] for _ in range(24)]}
    ledgers = ledgers or {"fix.pbl.total": np.zeros((25, 2), dtype=dtype)}
    quantity = quantity or ("water_increment" if family == "water" else "energy_increment")
    unit = "kg m^-3" if family == "water" else "J m^-3"
    if quantity.endswith("tendency"):
        app_unit = unit + " s^-1"
    else:
        app_unit = unit
    receipt = {"schema_version": 1, "semantics": "weighted_final_additive_updates", "kind": "synthetic",
               "model_commit": data["head_sha"], "model_diff_sha256": data["diff_sha256"],
               "integrator_pin": pin, "steps": []}
    native = {"weights": candidate["weights"], "geometry": candidate["geometry"],
              "weight_units": candidate["weight_units"]}
    coverage = []
    for channel, step_records in records.items():
        prefix = channel.replace(".", "_")
        rid_list, values_list, counter_lists = [], [], {k: [] for k in ("fallback", "bound", "clamp", "zero_normalization")}
        for n, entries in enumerate(step_records):
            if len(receipt["steps"]) <= n:
                receipt["steps"].append({"id": f"step{n}", "start_seconds": float(times[n]),
                                         "end_seconds": float(times[n + 1]), "accepted_trial": f"trial{n}",
                                         "trials": [{"id": f"trial{n}", "decision": "accepted"}], "applications": []})
            step = receipt["steps"][n]
            for m, entry in enumerate(entries):
                rid = channel + f".{n}.{m}"
                record = {"channel": channel, "record_id": rid, "trial": f"trial{n}",
                          "application_id": f"app{m}", "evaluation_id": f"eval{m}",
                          "disposition": "applied", "role": "final_map", "coefficient": 1,
                          "coefficient_units": "1", "attempted_coefficient": 1}
                record.update({k: v for k, v in entry.items() if k != "values"})
                step["applications"].append(record)
                rid_list.append(rid)
                values_list.append(entry["values"])
                for k in counter_lists:
                    counter_lists[k].append((counters or {}).get(channel, {}).get(k, [0, 0]))
        native[prefix + "__values"] = np.asarray(values_list, dtype=dtype)
        native[prefix + "__record_ids"] = np.asarray(rid_list)
        native[prefix + "__quantity"] = np.asarray(quantity)
        native[prefix + "__units"] = np.asarray(app_unit)
        native[prefix + "__event_scale"] = np.full_like(native[prefix + "__values"], 100)
        for k, values in counter_lists.items():
            native[prefix + "__" + k] = np.asarray(values, dtype=np.int64)
        field_name = "application_ledger_" + prefix
        candidate[field_name] = np.asarray(ledgers[channel], dtype=dtype)
        candidate[field_name + "__units"] = np.asarray(unit)
        candidate[field_name + "__representation"] = np.asarray("density")
        candidate[field_name + "__sampling"] = np.asarray("cumulative")
        candidate[field_name + "__dimensions"] = np.asarray(["z"])
        spec["runs"]["candidate"]["fields"][field_name] = {
            "path": "candidate.npz", "key": field_name, "units": unit, "representation": "density",
            "sampling": "cumulative", "weight_units": "m", "dimensions": ["z"], "cadence": 3600}
        parts = channel.split(".")
        coverage.append({"id": channel, "mechanism": parts[0], "tag": parts[1], "compartment": parts[2],
                         "status": "observed", "ledger": field_name,
                         "applications": {"path": "applications.npz", "prefix": prefix, "quantity": quantity, "units": app_unit}})
    np.savez(root / "candidate.npz", **candidate)
    np.savez(root / "applications.npz", **native)
    (root / "application_receipt.json").write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    spec["correction_accounting"] = {"schema_version": 1, "required_channels": list(records),
                                    "coverage": coverage, "receipt": "application_receipt.json"}
    for name in ("candidate.npz", "applications.npz", "application_receipt.json"):
        spec["artifacts"][name] = sha256_file(root / name)
    spec.update(local_identities())
    manifest.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n")
    return manifest


def write_correction_fixture(root, family="water"):
    manifest = write_fixture(root, family)
    return attach_fixture(manifest, family=family)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory")
    parser.add_argument("--family", choices=("water", "energy_source"), default="water")
    args = parser.parse_args()
    print(write_correction_fixture(args.directory, args.family))


if __name__ == "__main__":
    main()
