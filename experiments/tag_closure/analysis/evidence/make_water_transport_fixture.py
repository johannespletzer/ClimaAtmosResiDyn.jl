"""Run every frozen water reference rung and save small existing-format Bundles.

    python3 make_water_transport_fixture.py NEW_DIR --config ../../configs/water_transport_known_answers.json

These are synthetic known answers, not atmospheric model runs. All numerical
rungs, including ineligible ones, are retained. Existing outputs are refused.
"""

import argparse
import copy
import difflib
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np

from acceptance_data import Bundle, require, same_bits
from manifest import sha256_file
from score_acceptance import Scorer, local_identities
from water_transport_adapter import (
    FIXTURE_SCOPE, SOURCE_FILES, evaluate_water_transport, evaluator_identities,
    read_native, regenerate, rungs,
)
from water_transport_reference import (
    BASE_COMMIT, DESIGN_PATH, DESIGN_SHA256, FIELD_NAMES, analytic, case_by_id,
    load_design, origin_swap_invariants, rule_for, swapped_origins,
)


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n")


def archive_state(path, state, excluded=()):
    data = {"time": state.time, "time_units": np.array("s"), "geometry": state.geometry,
            "weights": state.weights, "weight_units": np.array("m")}
    fields = {}
    for name in tuple(FIELD_NAMES) + tuple("excluded_activity_" + p for p in excluded):
        sampling = "cumulative" if name.startswith("excluded_activity_") else "instantaneous"
        data[name] = state.values[name] if name in state.values else np.zeros_like(state.values["water_parent"])
        data[name + "__units"] = np.array("kg m^-3")
        data[name + "__representation"] = np.array("density")
        data[name + "__sampling"] = np.array(sampling)
        data[name + "__dimensions"] = np.array(["z"])
        fields[name] = {"path": path.name, "key": name, "units": "kg m^-3",
                        "representation": "density", "sampling": sampling,
                        "weight_units": "m", "dimensions": ["z"],
                        "expected_times": state.time.tolist()}
    np.savez(path, **data)
    return fields


def write_fixture(root, case_id, comparison_grid=64, reference_mode="analytic", dt=30, newton=4):
    """Create one immutable development Bundle with every case rung."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    design = load_design()
    case = case_by_id(design, case_id)
    grid = None if case["grids"] is None else comparison_grid
    truth = analytic(design, case, grid)
    declarations = rungs(design, case)
    selected = None
    if reference_mode == "numerical":
        selected = next((r for r in declarations if r["kind"] == "numerical" and
                         r["grid"] == grid and r["dt_seconds"] == dt and
                         r["newton_iterations"] == (newton if case["newton_iterations"] else None)), None)
        require(selected is not None, "numerical reference selection is outside the frozen ladder")
    else:
        require(reference_mode == "analytic", "unknown reference mode")
    config = {"schema_version": 1, "case_id": case_id, "comparison_grid": grid,
              "reference_mode": reference_mode, "reference_rung": selected,
              "design_sha256": DESIGN_SHA256, "scope": FIXTURE_SCOPE}
    write_json(root / "resolved_config.json", config)
    shutil.copyfile(DESIGN_PATH, root / DESIGN_PATH.name)
    sources = {}
    for name in SOURCE_FILES:
        destination = root / ("source_" + name)
        shutil.copyfile(Path(__file__).with_name(name), destination)
        sources[name] = destination.name
    runs = {}
    all_states = {}
    for rung in declarations:
        state = regenerate(design, case, rung)
        all_states[rung["role"]] = state
        fields = archive_state(root / (rung["role"] + ".npz"), state)
        runs[rung["role"]] = {"fields": fields}
    reference_state = truth if selected is None else all_states[selected["role"]]
    parent_fields = ["rho", "water_parent"]
    same_parent = all(same_bits(truth.values[name], reference_state.values[name])
                      for name in parent_fields)
    for role, state in (("candidate", truth), ("reference", reference_state),
                        ("untagged", truth), ("origin_swap", swapped_origins(truth))):
        fields = archive_state(root / (role + ".npz"), state,
                               design["excluded_processes"] if role in ("candidate", "origin_swap") else ())
        runs[role] = {"fields": fields}
    # A dirty offline evaluator has exact file hashes, never a fabricated git branch.
    current = Path(__file__).with_name("score_acceptance.py")
    original = current.parents[5] / "original" / current.relative_to(current.parents[4])
    patch = ("".join(difflib.unified_diff(original.read_text().splitlines(True),
                                         current.read_text().splitlines(True),
                                         fromfile="a/experiments/tag_closure/analysis/evidence/score_acceptance.py",
                                         tofile="b/experiments/tag_closure/analysis/evidence/score_acceptance.py"))
             if original.is_file() else "offline fixture; scorer identity pinned by SHA256\n")
    identities = evaluator_identities()
    untracked = [{"path": name, "sha256": identities[name]} for name in SOURCE_FILES]
    submission = {"head_sha": BASE_COMMIT, "status_lines": ["offline partial source materialization; no local git branch"],
                  "diff": patch, "diff_sha256": hashlib.sha256(patch.encode()).hexdigest(),
                  "untracked": {"count": len(untracked), "files": untracked},
                  "config": {"path": "resolved_config.json", "sha256": sha256_file(root / "resolved_config.json")},
                  "buildkite_files": {}, "julia_version": "not executed; known-answer Python fixture",
                  "hostname": "offline-known-answer-fixture", "env_vars": {}, "julia_binary": "not executed",
                  "julia_channel": "not executed", "loaded_modules": [], "model_runtime_executed": False}
    write_json(root / "submission.json", submission)
    for role, run in runs.items():
        if role != "candidate":
            run.update(manifest="submission.json", model_commit=BASE_COMMIT,
                       config_sha256=submission["config"]["sha256"])
    detail = {"schema_version": 1, "identity": design["identity"], "development_only": True,
              "case_id": case_id, "comparison_grid": grid, "reference_mode": reference_mode,
              "reference_rung": selected, "design": DESIGN_PATH.name, "design_sha256": DESIGN_SHA256,
              "config": "resolved_config.json", "evaluator_files": identities, "sources": sources,
              "model_commit": BASE_COMMIT, "tag_names": [tag["name"] for tag in design["tags"]],
              "end_seconds": 86400, "active_rules": [rule_for(case)], "independent_rules": [rule_for(case)],
              "shared_rules": [], "rungs": declarations,
              "limitation": "Candidate is a manufactured exact answer. Agreement is not production coverage."}
    write_json(root / "water_reference_evidence.json", detail)
    artifacts = {path.name: sha256_file(path) for path in sorted(root.iterdir()) if path.is_file()}
    spec = {"schema_version": 1, "experiment_commit": "local-uncommitted", "scorer_commit": "local-uncommitted",
            "acceptance_commit": BASE_COMMIT, **local_identities(), "artifacts": artifacts,
            "submission_files": {"config": "resolved_config.json", **sources},
            "resolved_settings": {"solver": "independent offline analytic/upwind/implicit-Newton",
                                  "seed": "none", "physics": case, "diagnostics": list(FIELD_NAMES),
                                  "tag_definitions": design["tags"], "fixture_only": True},
            "precision": "Float64", "process_count": 1, "geometry_kind": "column", "case": case_id,
            "claim": {"family": "water", "scope": FIXTURE_SCOPE, "precipitation": False},
            "runs": runs, "tags": design["tags"], "required_parent_fields": parent_fields,
            "parent_capture_scope": "exported", "same_parent_comparisons": same_parent,
            "end_seconds": 86400, "profile_times": [3600, 86400], "active_rules": [rule_for(case)],
            "reference": {"identity": design["identity"], "evidence": "water_reference_evidence.json",
                          "kind": "water_transport"}}
    write_json(root / "extension.json", spec)
    write_json(root / "manifest.json", {**submission, "acceptance": spec})
    mutant = copy.deepcopy(spec)
    mutant["runs"]["candidate"] = copy.deepcopy(runs["origin_swap"])
    mutant["runs"]["candidate"].pop("manifest", None)
    write_json(root / "manifest_origin_swap.json", {**submission, "acceptance": mutant})
    return root / "manifest.json"


def evaluate_fixture(manifest):
    bundle = Bundle(manifest)
    measured = evaluate_water_transport(bundle)
    scorer = Scorer(bundle)
    profiles = [{"tag": tag["name"], "endpoint_seconds": time, **scorer.profile(tag, time)}
                for time in (3600, 86400) for tag in bundle.spec["tags"]]
    mutant_bundle = Bundle(Path(manifest).with_name("manifest_origin_swap.json"))
    mutant = evaluate_water_transport(mutant_bundle)
    mutant_scorer = Scorer(mutant_bundle)
    mutant_profiles = [{"tag": tag["name"], "endpoint_seconds": time, **mutant_scorer.profile(tag, time)}
                       for time in (3600, 86400) for tag in mutant_bundle.spec["tags"]]
    fails_origin = any(row.get("meets") is False and row["tag"] in ("origin_a", "origin_b") for row in mutant_profiles)
    design = load_design()
    case = case_by_id(design, bundle.spec["case"])
    grid = bundle.field("candidate", "rho").values.shape[1] if case["grids"] else None
    truth = analytic(design, case, grid)
    invariants = origin_swap_invariants(read_native(mutant_bundle, "candidate", truth),
                                       read_native(bundle, "candidate", truth), design)
    result = {"schema_version": 1, "scope": FIXTURE_SCOPE, "scientific_qualification": "NOT QUALIFIED",
              "manifest": Path(manifest).name, "measured_reference": measured,
              "candidate_profiles": profiles,
              "candidate_verdict": ("PASS" if measured["metrics"]["candidate_closure"]["meets"] and
                                    measured["metrics"]["candidate_parent_trajectory"]["meets"] and
                                    all(row.get("meets") for row in profiles) else "FAIL")
              if measured["meets"] else "NOT ASSESSABLE",
              "origin_swap": {"closure": mutant["metrics"]["candidate_closure"],
                              "parent_trajectory": mutant["metrics"]["candidate_parent_trajectory"],
                              "invariants": invariants,
                              "profiles": mutant_profiles, "origin_failure_measured": fails_origin,
                              "mutation_verified": bool(mutant["metrics"]["candidate_closure"]["meets"] and
                                                        mutant["metrics"]["candidate_parent_trajectory"]["meets"] and
                                                        invariants["meets"] and fails_origin)
                              if measured["meets"] else None},
              "artifacts": dict(sorted(bundle.used.items()))}
    bundle.reverify()
    mutant_bundle.reverify()
    return result


def run_suite(root, config):
    design = load_design()
    require(config.get("schema_version") == 1 and config.get("design_sha256") == DESIGN_SHA256 and
            config.get("scope") == FIXTURE_SCOPE and config.get("retain_all_rungs") is True and
            config.get("mutant") == design["mutation"]["kind"] and
            config.get("case_ids") == [case["id"] for case in design["cases"]],
            "suite config differs from the frozen complete development scope")
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    write_json(root / "suite_config.json", config)
    results = []
    for case_id in config["case_ids"]:
        manifest = write_fixture(root / case_id, case_id, config["comparison_grid"], config["reference_mode"],
                                 config.get("reference_dt_seconds", 30), config.get("reference_newton_iterations", 4))
        result = evaluate_fixture(manifest)
        result["case_id"] = case_id
        write_json(manifest.with_name("known_answer_results.json"), result)
        results.append({"case_id": case_id, "reference_eligible": result["measured_reference"]["meets"],
                        "candidate_verdict": result["candidate_verdict"],
                        "origin_swap_verified": result["origin_swap"]["mutation_verified"],
                        "result": case_id + "/known_answer_results.json"})
    code = (1 if any(row["candidate_verdict"] == "FAIL" or row["origin_swap_verified"] is False for row in results)
            else 3 if any(not row["reference_eligible"] for row in results) else 0)
    report = {"schema_version": 1, "design_sha256": DESIGN_SHA256, "cases": results, "exit_code": code,
              "scientific_qualification": "NOT QUALIFIED", "scope": FIXTURE_SCOPE,
              "limitation": "Every output is synthetic; native atmospheric runtime/producer obligations remain open."}
    write_json(root / "suite_results.json", report)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory")
    parser.add_argument("--config", required=True)
    args = parser.parse_args(argv)
    report = run_suite(args.directory, json.loads(Path(args.config).read_text()))
    print(json.dumps(report, sort_keys=True, indent=2))
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
