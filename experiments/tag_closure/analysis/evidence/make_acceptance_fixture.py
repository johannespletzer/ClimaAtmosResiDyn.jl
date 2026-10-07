"""Create small analytic evidence fixtures. These are not atmospheric runs.

    python3 make_acceptance_fixture.py NEW_DIR [--family water|energy_source|radiation_record] [--hours 24]

Every output file is separately hashed. No repository result or golden
reference is replaced. The expected answers in the tests are hand-derived.
"""

import argparse
import copy
import json
from pathlib import Path

import numpy as np

from manifest import sha256_file
from score_acceptance import local_identities


BASE = "5dd23a8309e174592984da7d60912a4a9daaf08a"


def write_fixture(root, family="water", hours=24):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    n = hours + 1
    time = np.arange(n, dtype=np.float64) * 3600
    geometry = np.array([[500.0], [1500.0]])
    weights = np.ones(2, dtype=np.float64)
    mass = 100.0 + np.concatenate(([0.0], 100.0 + np.arange(hours)))
    water = np.repeat((mass / 2)[:, None], 2, axis=1)
    energy = water * 1000
    rho = np.ones((n, 2), dtype=np.float64)
    dimensions = ("z",)
    metadata = root / "fixture_metadata.json"
    metadata.write_text(json.dumps({"kind": "analytic fixture", "not_a_model_run": True,
                                    "native_geometry": "two unit-thickness cells",
                                    "cadence_seconds": 3600}, indent=2) + "\n")
    artifact_hashes = {metadata.name: sha256_file(metadata)}
    unit = "kg kg^-1" if family == "water" else "J kg^-1"
    amount_unit = "kg m^-2" if family == "water" else "J m^-2"
    fields = {}
    archive = {"time": time, "time_units": np.array("s"), "geometry": geometry,
               "weights": weights, "weight_units": np.array("m")}

    def add(name, values, units, sampling="instantaneous", representation="specific",
            accumulator_kind="", scalar=False, bounds=None):
        values = np.asarray(values, dtype=np.float64)
        if values.ndim == 1:
            values = values[:, None]
        dims = ("scalar",) if scalar else dimensions
        archive[name] = values
        for k, v in ("units", units), ("sampling", sampling), ("representation", representation):
            archive[name + "__" + k] = np.array(v)
        archive[name + "__dimensions"] = np.array(dims)
        d = {"path": "fields.npz", "key": name, "units": units, "sampling": sampling,
             "representation": representation, "weight_units": "1" if scalar else "m",
             "dimensions": list(dims), "cadence": 3600}
        if scalar:
            # Scalar arrays are already native integrated amounts, never density weighted again.
            archive["scalar_weights"] = np.ones(1)
            archive["scalar_geometry"] = np.zeros((1, 1))
            archive["scalar_weight_units"] = np.array("1")
            d.update(weights_key="scalar_weights", geometry_key="scalar_geometry",
                     weight_units_key="scalar_weight_units")
        if accumulator_kind:
            d["accumulator_kind"] = accumulator_kind
        if bounds is not None:
            archive[name + "__bounds"] = bounds
            d["bounds_key"] = name + "__bounds"
        fields[name] = d

    add("rho", rho, "kg m^-3", representation="density")
    add("water_parent", water, "kg kg^-1")
    add("energy_parent", energy, "J kg^-1")
    add("temperature", np.full((n, 2), 300.0), "K", representation="intensive")
    add("negative_water_void", np.zeros((n, 1)), "1", representation="flag", scalar=True)
    add("newton_error", np.full((n, 1), 1e-5), "1", representation="ratio", scalar=True)
    add("source_partition_valid", np.ones((n, 1)), "1", representation="flag", scalar=True)
    add("throughput", np.arange(n) * 10, "J m^-2", sampling="cumulative",
        representation="amount", accumulator_kind="accepted_step_source_variation", scalar=True)
    repair_increment = 0.001 if family == "water" else 0.0001
    add("repair_retained", np.arange(n) * repair_increment, amount_unit, sampling="cumulative",
        representation="amount", accumulator_kind="retained_cell_step_repair", scalar=True)
    add("repair_attempted", np.arange(n) * 2 * repair_increment, amount_unit, sampling="cumulative",
        representation="amount", accumulator_kind="attempted_application_repair", scalar=True)
    target = water if family == "water" else energy
    tags = [] if family == "radiation_record" else [
        {"name": "pbl", "kind": "region", "partition": True},
        {"name": "free", "kind": "region", "partition": True},
        {"name": "evap", "kind": "source", "partition": False}]
    for tag in tags:
        values = 0.6 * target if tag["name"] == "pbl" else (0.4 * target if tag["name"] == "free" else
                 np.ones_like(target) * (5 if family == "water" else 5000))
        add("tag_" + tag["name"], values, unit)
        for mechanism in ("led_fix", "led_inc"):
            add(mechanism + "_" + tag["name"], np.repeat((np.arange(n) * 1e-5)[:, None], 2, axis=1),
                unit, sampling="cumulative")
            add(mechanism + "_" + tag["name"] + "_applicable", np.ones((n, 1)), "1",
                representation="flag", scalar=True)
    add("copy_residual", np.zeros_like(water), "kg kg^-1")
    add("named_remainder", np.zeros_like(water), "kg kg^-1")
    add("residual", np.ones_like(energy) * 100, "J kg^-1")
    add("record_radiation", np.repeat(np.arange(n)[:, None], 2, axis=1), "J kg^-1", sampling="cumulative")
    for name, rate in (("precip_parent", -0.001), ("precip_pbl", -0.0006), ("precip_free", -0.0004)):
        add(name, np.full((n, 1), rate), "kg m^-2 s^-1", representation="rate", scalar=True)
    bounds = np.column_stack((time, time + 3600))
    add("process_amount", np.ones((n, 1)), amount_unit, sampling="applied_interval",
        representation="weighted_applied_amount", scalar=True, bounds=bounds)
    add("process_share", np.full((n, 1), 0.6), "1", sampling="applied_interval",
        representation="ratio", scalar=True, bounds=bounds)
    for role in ("candidate", "reference", "untagged"):
        filename = role + ".npz"
        np.savez(root / filename, **archive)
        artifact_hashes[filename] = sha256_file(root / filename)
    reference = {"identity": "analytic-independent-reference", "active_rules": ["transport"],
                 "tag_names": [t["name"] for t in tags], "end_seconds": hours * 3600, "model_commit": BASE,
                 "independent_rules": ["transport"], "converged": True,
                 "floor_fraction_of_tolerance": 0.0, "mirrors_complete": True,
                 "jacobian_complete": True, "repair_refinement_ratios": {"dt": 0.5, "newton": 0.5},
                 "not_a_model_run": True}
    if family == "radiation_record":
        reference["independent_rules"] = ["radiation_divergence"]
    (root / "reference_evidence.json").write_text(json.dumps(reference, indent=2) + "\n")
    artifact_hashes["reference_evidence.json"] = sha256_file(root / "reference_evidence.json")
    config_hash = sha256_file(metadata)
    submission = {"head_sha": BASE, "status_lines": [], "diff": "", "diff_sha256":
                  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                  "config": {"path": metadata.name, "sha256": config_hash}, "buildkite_files": {},
                  "julia_version": "not-run: analytic fixture", "hostname": "analytic-fixture",
                  "untracked": {"count": 0, "files": []}, "env_vars": {}, "julia_binary": "not-run",
                  "julia_channel": "not-run", "loaded_modules": []}
    (root / "submission.json").write_text(json.dumps(submission, sort_keys=True, indent=2) + "\n")
    artifact_hashes["submission.json"] = sha256_file(root / "submission.json")
    runs = {}
    for role in ("candidate", "reference", "untagged"):
        role_fields = copy.deepcopy(fields)
        for d in role_fields.values():
            d["path"] = role + ".npz"
        runs[role] = {"fields": role_fields}
        if role != "candidate":
            runs[role].update(manifest="submission.json", model_commit=BASE, config_sha256=config_hash)
    spec = {"schema_version": 1, "experiment_commit": "local-uncommitted", "scorer_commit": "local-uncommitted",
            "acceptance_commit": BASE, **local_identities(), "artifacts": artifact_hashes,
            "resolved_settings": {"fixture": True, "solver": "analytic", "seed": "none", "physics": "none",
                                  "diagnostics": list(fields), "tag_definitions": tags},
            "submission_files": {"config": metadata.name},
            "precision": "Float64", "process_count": 1, "geometry_kind": "column", "case": "analytic",
            "claim": {"family": family, "scope": "synthetic fixture", "precipitation": False},
            "runs": runs, "tags": tags,
            "required_parent_fields": ["rho", "water_parent", "energy_parent", "temperature"],
            "parent_capture_scope": "all-state", "same_parent_comparisons": True,
            "end_seconds": hours * 3600, "profile_times": [3600, 86400] if hours >= 24 else [3600],
            "accepted_step_seconds": 3600,
            "throughput_accumulation": "accepted_step", "energy_ledger_per_tag": True,
            "energy_offset": 0, "active_rules": ["transport"],
            "named_parts": ["analytic zero remainder"], "reference": {"identity": reference["identity"],
            "evidence": "reference_evidence.json", "kind": "copies" if family != "radiation_record" else "independent",
            "energy_offset": 0}, "record_processes": ["radiation"], "expected_record_processes": ["radiation"]}
    (root / "extension.json").write_text(json.dumps(spec, sort_keys=True, indent=2) + "\n")
    (root / "manifest.json").write_text(json.dumps({**submission, "acceptance": spec}, sort_keys=True, indent=2) + "\n")
    return root / "manifest.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory")
    parser.add_argument("--family", choices=("water", "energy_source", "radiation_record"), default="water")
    parser.add_argument("--hours", type=int, default=24, help="hourly outputs after the start")
    args = parser.parse_args()
    print(write_fixture(args.directory, args.family, args.hours))


if __name__ == "__main__":
    main()
