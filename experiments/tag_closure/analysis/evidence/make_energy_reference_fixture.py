"""Run every frozen energy reference case and save small self-contained fixtures.

    python3 make_energy_reference_fixture.py NEW_DIR --config ../../configs/energy_reference_known_answers.json

These are synthetic known answers, not atmospheric model runs. Every rung,
the reference, the candidate and the case's registered wrong-origin mutant
are retained. Existing outputs are refused.

Exit codes follow the scorer's. 0: every case's checks passed with an
eligible reference and every mutant was caught. 1: a fixture check failed or
a mutant was not caught. 2: evidence is missing, corrupt or inconsistent.
3: a reference is ineligible, or a candidate has an origin row the scorer's
reading cannot assess, so that candidate is NOT ASSESSABLE. 4: nothing
was evaluated. The output exists, the command line is invalid, or the driver
itself raised an error.
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

from acceptance_data import DataError, require
from manifest import sha256_file
from score_acceptance import approved_numbers_sha256
from energy_reference import (
    BASE_COMMIT, DESIGN_PATH, DESIGN_SHA256, MODEL_COMMIT, case_by_id, evaluate_candidate, load_design, mutant,
)
from energy_reference_adapter import (
    DECLARED_FIELDS, FIXTURE_SCOPE, SOURCE_FILES, candidate_for, evaluate_energy_reference,
    evaluator_identities, load_state, reference_for, regenerate, rule_for, rungs, save_state,
)


# Check-name prefixes that each declared invariant of a mutant maps to.
# `stage_fluxes` maps to the captured parent: the state holds no face flux.
INVARIANT_CHECKS = {"parent": ("parent",), "partition": ("partition_closure",), "inputs": ("inputs",),
                    "stage_fluxes": ("parent",), "overlay_sum": ("overlay_sum",), "records": ("records",)}


def write_json(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n")


def write_fixture(root, case_id):
    """Create one immutable development fixture with every rung and the mutant."""
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    design = load_design()
    case = case_by_id(design, case_id)
    shutil.copyfile(DESIGN_PATH, root / DESIGN_PATH.name)
    sources = {}
    for name in SOURCE_FILES:
        shutil.copyfile(Path(__file__).with_name(name), root / ("source_" + name))
        sources[name] = "source_" + name
    for rung in rungs(case):
        save_state(root / (rung["role"] + ".npz"), regenerate(design, case, rung))
    reference = reference_for(design, case)
    candidate = candidate_for(design, case)
    save_state(root / "reference.npz", reference)
    save_state(root / "candidate.npz", candidate, design["excluded_processes"])
    save_state(root / "mutant.npz", mutant(design, case, candidate), design["excluded_processes"])
    artifacts = {path.name: sha256_file(path) for path in sorted(root.iterdir()) if path.suffix == ".npz"}
    # The convention and the Theta_x window are written from the frozen design
    # before any floor or candidate verdict is measured.
    detail = {"schema_version": 1, "identity": design["identity"], "development_only": True,
              "scope": FIXTURE_SCOPE, "case_id": case_id, "family": case["family"],
              "convention": case["convention"], "theta_x_window": case["theta_x_window"],
              "design": DESIGN_PATH.name, "design_sha256": DESIGN_SHA256,
              "planning_commit": BASE_COMMIT, "model_commit": MODEL_COMMIT,
              "approved_numbers_sha256": approved_numbers_sha256(),
              "evaluator_files": evaluator_identities(), "sources": sources, "artifacts": artifacts,
              "active_rules": [rule_for(case)], "shared_rules": [], "rungs": rungs(case),
              "limitation": "Candidate is a manufactured exact answer. Agreement is not production coverage."}
    write_json(root / "evidence.json", detail)
    measured = evaluate_energy_reference(root, declared=False)
    detail.update({key: measured["declaration"][key] for key in DECLARED_FIELDS})
    write_json(root / "evidence.json", detail)
    return root


def mutant_caught(case, evaluation):
    """The mutant fails, and every invariant it declares to keep still holds."""
    kept = []
    for name in case["mutant"]["preserves"]:
        require(name in INVARIANT_CHECKS, "declared invariant has no check: " + name)
        found = [ok for check, ok in evaluation["checks"].items() if check.startswith(INVARIANT_CHECKS[name])]
        require(bool(found), "declared invariant was not evaluated: " + name)
        kept += found
    return bool(evaluation["meets"] is False and all(kept))


VERDICTS = {True: "PASS", False: "FAIL", None: "NOT ASSESSABLE"}


def evaluate_fixture(root):
    root = Path(root)
    measured = evaluate_energy_reference(root)
    design = load_design()
    case = case_by_id(design, measured["case_id"])
    reference, _ = load_state(root / "reference.npz")
    wrong, _ = load_state(root / "mutant.npz")
    wrong_eval = evaluate_candidate(design, case, wrong, reference)
    return {"schema_version": 1, "scope": FIXTURE_SCOPE, "scientific_qualification": "NOT QUALIFIED",
            "case_id": case["id"], "convention": case["convention"], "measured_reference": measured,
            "candidate_verdict": VERDICTS[measured["candidate"]["meets"]] if measured["meets"] else "NOT ASSESSABLE",
            "not_assessable_rows": measured["candidate"]["not_assessable_rows"],
            "mutant": {"kind": case["mutant"]["kind"], "checks": wrong_eval["checks"],
                       "caught": mutant_caught(case, wrong_eval)}}


def run_suite(root, config):
    design = load_design()
    require(config.get("schema_version") == 1 and config.get("design_sha256") == DESIGN_SHA256 and
            config.get("scope") == FIXTURE_SCOPE and config.get("retain_all_rungs") is True and
            config.get("case_ids") == [case["id"] for case in design["cases"]],
            "suite config differs from the frozen complete development scope")
    root = Path(root)
    root.mkdir(parents=True, exist_ok=False)
    write_json(root / "suite_config.json", config)
    results = []
    for case_id in config["case_ids"]:
        fixture = write_fixture(root / case_id, case_id)
        result = evaluate_fixture(fixture)
        write_json(fixture / "known_answer_results.json", result)
        results.append({"case_id": case_id, "reference_eligible": result["measured_reference"]["meets"],
                        "candidate_verdict": result["candidate_verdict"],
                        "mutant_caught": result["mutant"]["caught"],
                        "result": case_id + "/known_answer_results.json"})
    report = {"schema_version": 1, "design_sha256": DESIGN_SHA256, "cases": results,
              "exit_code": suite_exit_code(results), "scientific_qualification": "NOT QUALIFIED",
              "scope": FIXTURE_SCOPE,
              "limitation": "Every output is synthetic. Native atmospheric producers and PX22 remain open."}
    write_json(root / "suite_results.json", report)
    return report


def suite_exit_code(results):
    """1 for a failed check or an uncaught mutant, else 3 for an ineligible reference or a
    candidate with a row the scorer's reading cannot assess, else 0."""
    if any(row["candidate_verdict"] == "FAIL" or row["mutant_caught"] is False for row in results):
        return 1
    return 3 if any(not row["reference_eligible"] or row["candidate_verdict"] != "PASS" for row in results) else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory")
    parser.add_argument("--config", required=True)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code == 0 else 4
    if Path(args.directory).exists():
        print("not evaluated: the output directory exists. Choose a new one", file=sys.stderr)
        return 4
    try:
        report = run_suite(args.directory, json.loads(Path(args.config).read_text()))
    except (DataError, json.JSONDecodeError, UnicodeDecodeError, OSError) as exc:
        print("DATA FAILURE: " + str(exc), file=sys.stderr)
        return 2
    except Exception as exc:  # A driver error is reported as such, never as bad data.
        print(f"DRIVER ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 4
    print(json.dumps(report, sort_keys=True, indent=2))
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
