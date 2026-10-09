"""Produce and check the declared eligibility of the energy known-answer fixtures.

This module is the producing script that an energy fixture's evidence file
names and hashes. It regenerates every archived rung from the independent
equations, measures each floor and writes the declared eligibility. Rerun on a
finished fixture, it is the producer's internal check: it refuses a
declaration that differs from its recompute. The scorer does not import it.

The fixtures are self-contained directories, not the scorer's Bundles. The
scorer has no energy known-answer hook, and Part 11a changes no scorer code.
Its declared fields use the scorer's names, so a later converter can carry
them into a Bundle unchanged.
"""

import io
import json
from pathlib import Path

import numpy as np

from acceptance_data import require
from manifest import sha256_file
from score_acceptance import FLOOR_FRACTION_MAX, OD12_FLOOR_SOURCES, SECOND_HALF_TIE, approved_numbers_sha256
from energy_reference import (
    BASE_COMMIT, DESIGN_SHA256, MODEL_COMMIT, EnergyState, analytic, case_by_id, classify,
    conventions, evaluate_candidate, floor_rows, load_design, numerical, origin_rows,
    stage_record, stage_reference,
)


SOURCE_FILES = ("energy_reference.py", "energy_reference_adapter.py", "make_energy_reference_fixture.py")
FIXTURE_SCOPE = "preregistered energy known-answer development fixture"
PRODUCER = "energy_reference_adapter.py"
# The fields this producer declares in the evidence file. The scorer's names
# are identity, independent_rules, producer, floors, converged,
# mirrors_complete and jacobian_complete. The basis fields say what each
# value rests on. The convention is declared and frozen per case.
DECLARED_FIELDS = ("identity", "independent_rules", "convention", "producer", "floors", "floor_basis",
                   "converged", "mirrors_complete", "jacobian_complete", "eligibility_basis")
STATED_FLOORS = {
    "source_injection": "Stated, not measured. Sources are prescribed exact rates or prescribed increments.",
    "initialization": "Stated, not measured. The producer refuses a candidate whose initial state differs "
                      "from the frozen initial values by more than the roundoff allowance.",
    "parent_solve": "Stated, not measured. The parent is prescribed in closed form. A stepped rung's parent "
                    "defect is reported beside its floor.",
    "contamination": "Stated, not measured. No other process acts. Every excluded process reads a zero "
                     "cumulative array in the candidate.",
}
# One rule name per case. A reference validates only the rule it does not share (OD12).
RULES = {
    "heating_labels": "declared_source_allocation",
    "donor_cooling": "donor_loss_allocation",
    "reservoir_exchange": "donor_transport_share",
    "falling_mass_boundary": "offset_boundary_flux",
    "opposing_net_zero": "sequential_event_allocation",
    "offset_change": "fixed_offset_representation",
    "admissibility": "share_admissibility",
    "radiation_record": "radiation_divergence",
}
# A floor that rises by at most this much along a ladder is a tie, not a
# rise. Part 6's rule (decision of 2026-10-08), reused for energy.
LADDER_TIE = SECOND_HALF_TIE


def evaluator_identities():
    return {name: sha256_file(Path(__file__).with_name(name)) for name in SOURCE_FILES}


def producer_identity():
    return {"script": PRODUCER, "sha256": sha256_file(Path(__file__))}


def rule_for(case):
    return RULES[case["kind"]]


def converges(values, tie=LADDER_TIE):
    """True when no refinement step raises the floor by more than the tie."""
    return not any(later > earlier + tie for earlier, later in zip(values, values[1:]))


def rungs(case):
    """Every retained rung, coarse to fine. The classifier case has none."""
    if case["kind"] == "admissibility":
        return []
    result = [{"kind": "numerical", "dt_seconds": dt, "dtype": "float64", "role": f"rung_dt{dt}"}
              for dt in sorted(case["dt_seconds"], reverse=True)]
    if "float32_rung_dt_seconds" in case:
        dt = case["float32_rung_dt_seconds"]
        result.append({"kind": "numerical", "dt_seconds": dt, "dtype": "float32", "role": f"rung_dt{dt}_float32"})
    return result


def regenerate(design, case, rung):
    if case["kind"] == "radiation_record":
        return stage_record(design, case, rung["dt_seconds"])
    return numerical(design, case, rung["dt_seconds"], dtype=np.dtype(rung["dtype"]).type)


def reference_for(design, case):
    """The selected reference. A closed form, or the independent stage route for the record."""
    if case["kind"] == "radiation_record":
        return stage_reference(design, case, case["reference_dt_seconds"])
    return analytic(design, case)


def candidate_for(design, case):
    """The manufactured candidate: the exact answer in the model's arrangement."""
    if case["kind"] == "radiation_record":
        return stage_record(design, case, case["reference_dt_seconds"])
    if case["kind"] == "admissibility":
        return classify(case)
    return analytic(design, case)


def save_state(path, state, excluded=()):
    data = {"time": state.time, "dz": state.dz,
            "diagnostics": np.array(json.dumps(state.diagnostics, sort_keys=True, default=float))}
    for name, value in state.values.items():
        data["field__" + name] = np.asarray(value, dtype=np.float64)
    for process in excluded:
        data["excluded_activity__" + process] = np.zeros((len(state.time), len(state.dz)))
    buffer = io.BytesIO()
    np.savez(buffer, **data)
    Path(path).write_bytes(buffer.getvalue())


def load_state(path):
    with np.load(path) as raw:
        values = {key[len("field__"):]: raw[key].copy() for key in raw.files if key.startswith("field__")}
        excluded = {key[len("excluded_activity__"):]: raw[key].copy() for key in raw.files
                    if key.startswith("excluded_activity__")}
        state = EnergyState(raw["time"].copy(), raw["dz"].copy(), values, json.loads(str(raw["diagnostics"])))
    return state, excluded


def _same(design, a, b, label):
    require(set(a.values) == set(b.values) and np.array_equal(a.time, b.time) and np.array_equal(a.dz, b.dz),
            f"{label}: archived fields, times or cells differ from the recompute")
    for name in b.values:
        scale = float(np.max(np.abs(b.values[name]))) if b.values[name].size else 0.0
        limit = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps * scale
        require(np.max(np.abs(a.values[name] - b.values[name])) <= limit,
                f"{label}:{name}: archived values differ from the independent equations")


def _record_floor(state, truth):
    """The record's relative and absolute floor against the continuum, worst endpoint."""
    dz = truth.dz
    rows = []
    for j in range(1, len(truth.time)):
        delta = state.values["prc_radiation"][j] - truth.values["prc_radiation"][j]
        amount = float(np.sum(dz * np.abs(truth.values["prc_radiation"][j])))
        rows.append({"endpoint_seconds": float(truth.time[j]), "absolute_J_m2": float(np.sum(dz * np.abs(delta))),
                     "relative_to_record": float(np.sum(dz * np.abs(delta))) / amount})
    return max(row["relative_to_record"] for row in rows), rows


def measure(design, case, stored=None):
    """Floors of every rung, the constructed roundoff bound and the declaration's basis."""
    truth = analytic(design, case)
    eps = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps
    floors, floor_by_role = [], {}
    for rung in rungs(case):
        state = stored[rung["role"]] if stored else regenerate(design, case, rung)
        if case["kind"] == "radiation_record":
            value, rows = _record_floor(state, truth)
            floors.append({**rung, "floor_relative_to_record": value, "endpoints": rows})
        else:
            rows, defect = floor_rows(state, truth, design, case)
            fractions = [row["worst_fraction"] for row in rows if row.get("meets") is not None]
            value = max(fractions) if fractions else 0.0
            floors.append({**rung, "floor_fraction": value, "parent_defect": defect,
                           "not_assessable_rows": sum(row.get("meets") is None for row in rows)})
        floor_by_role[rung["role"]] = value
    float64 = [floor_by_role[r["role"]] for r in rungs(case) if r["dtype"] == "float64"]
    if case["kind"] == "radiation_record":
        selected = floor_by_role[f"rung_dt{case['reference_dt_seconds']}"]
        converged = converges(float64)
        return {"reference_discretization": selected, "rungs": floors, "converged": converged,
                "basis": ("Measured. The stage-weighted record at the reference step against the closed-form "
                          "continuum record, relative to the record's window amount. No record tolerance is "
                          "approved (EA-ACCURACY), so this floor is reported and never a fraction of one."),
                "converged_basis": ("Measured. The floor does not rise along the step ladder "
                                    + " -> ".join(f"{v:.6g}" for v in float64) + "." if converged else
                                    "Measured. The floor rises along the step ladder.")}
    if case["kind"] == "admissibility":
        constructed, basis = 0.0, ("Constructed, not measured. The classifier's answers are exact integers and "
                                   "exact shares. There is no discretization.")
    else:
        perturbed = EnergyState(truth.time, truth.dz,
                                {k: v * (1.0 + eps) if k.startswith("tag_") else v for k, v in truth.values.items()}, {})
        rows = origin_rows(perturbed, truth, design, case)
        constructed = max([row["worst_fraction"] for row in rows if row.get("meets") is not None] or [0.0])
        basis = ("Constructed, not measured. The answer is a closed form. The floor is the error of a 128 eps "
                 "relative perturbation of every tag. The stepped rungs are a cross-check and gate nothing.")
    return {"reference_discretization": constructed, "rungs": floors, "converged": True,
            "cross_check_converged": converges(float64), "basis": basis,
            "converged_basis": "Inapplicable. A closed-form answer has no refinement ladder."}


def declaration(design, case, measured):
    radiation = case["kind"] == "radiation_record"
    floors = {"reference_discretization": measured["reference_discretization"],
              **{source: 0.0 for source in STATED_FLOORS}}
    require(set(floors) == set(OD12_FLOOR_SOURCES), "one floor per OD12 source is required")
    return {
        "identity": design["identity"],
        "independent_rules": [rule_for(case)],
        "convention": case["convention"],
        "producer": producer_identity(),
        "floors": floors,
        "floor_basis": {"reference_discretization": measured["basis"], **STATED_FLOORS},
        "converged": bool(measured["converged"]),
        "mirrors_complete": True,
        "jacobian_complete": True,
        "eligibility_basis": {
            "converged": measured["converged_basis"],
            "mirrors_complete": "Inapplicable. No copies and no sub-grid rule. Every excluded process reads zero.",
            "jacobian_complete": "Inapplicable. No implicit tag solve.",
            "floors": ("Relative to the record's window amount, not to a tolerance." if radiation else
                       "Fractions of the scorer's origin tolerance, in its energy reading."),
        },
    }


def eligible(case, declared):
    """The scorer's reading of a declaration. A record floor is reported, not compared."""
    common = (declared["converged"] is True and declared["mirrors_complete"] is True and
              declared["jacobian_complete"] is True and bool(declared["independent_rules"]))
    if case["kind"] == "radiation_record":
        return common and declared["independent_rules"] == ["radiation_divergence"]
    return common and all(0 <= v <= FLOOR_FRACTION_MAX for v in declared["floors"].values())


def evaluate_energy_reference(root, declared=True, candidate_name="candidate.npz"):
    """Check one fixture directory and evaluate its candidate against the reference."""
    root = Path(root)
    detail = json.loads((root / "evidence.json").read_text())
    design = load_design(root / detail.get("design", "missing"))
    require(detail.get("design_sha256") == DESIGN_SHA256 and detail.get("identity") == design["identity"],
            "energy reference identity or preregistration differs")
    require(detail.get("schema_version") == 1 and detail.get("development_only") is True and
            detail.get("scope") == FIXTURE_SCOPE, "energy known-answer scope marker missing")
    require(detail.get("planning_commit") == BASE_COMMIT and detail.get("model_commit") == MODEL_COMMIT,
            "energy fixture planning or model commit differs")
    require(detail.get("approved_numbers_sha256") == approved_numbers_sha256(),
            "the scorer's approved numbers changed since the fixture was made")
    require(detail.get("evaluator_files") == evaluator_identities(), "stale energy reference evaluator identity")
    for name, rel in detail.get("sources", {}).items():
        require(sha256_file(root / rel) == evaluator_identities()[name], "archived energy evaluator source differs")
    require(set(detail.get("sources", {})) == set(SOURCE_FILES), "incomplete evaluator source inventory")
    for name, digest in detail.get("artifacts", {}).items():
        require(sha256_file(root / name) == digest, f"artifact {name} differs from its recorded hash")
    case = case_by_id(design, detail.get("case_id"))
    # The convention is part of the frozen design. A fixture cannot carry another.
    require(detail.get("convention") == case["convention"] and case["convention"]["frozen"] is True,
            "the fixture's convention differs from the frozen design")
    conventions(case)
    rule = rule_for(case)
    require(detail.get("active_rules") == [rule] and detail.get("shared_rules") == [],
            "shared, missing or extra active rule in the energy fixture")
    require(detail.get("rungs") == rungs(case), "incomplete or changed ladder")
    stored = {}
    for rung in rungs(case):
        state, _ = load_state(root / (rung["role"] + ".npz"))
        _same(design, state, regenerate(design, case, rung), rung["role"])
        stored[rung["role"]] = state
    reference = reference_for(design, case)
    archived_reference, _ = load_state(root / "reference.npz")
    _same(design, archived_reference, reference, "reference")
    candidate, excluded = load_state(root / candidate_name)
    require(set(excluded) == set(design["excluded_processes"]), "the excluded-process roster is incomplete")
    for process, activity in excluded.items():
        require(np.array_equal(activity, np.zeros_like(activity)),
                "active excluded process lacks independent coverage: " + process)
    for name in reference.values:
        require(name in candidate.values, f"candidate lacks field {name}")
        first = reference.values[name][0]
        limit = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps * float(np.max(np.abs(first)))
        require(np.max(np.abs(candidate.values[name][0] - first)) <= limit,
                "candidate does not match the preregistered initial state")
    measured = measure(design, case, stored)
    declared_now = declaration(design, case, measured)
    if declared:
        for key in DECLARED_FIELDS:
            require(detail.get(key) == declared_now[key],
                    f"declared eligibility differs from the producer's recompute: {key}")
    is_eligible = eligible(case, declared_now)
    evaluation = evaluate_candidate(design, case, candidate, reference)
    return {"meets": bool(is_eligible), "case_id": case["id"], "declaration": declared_now,
            "reference_eligibility": ("measured eligibility, fixture equations only" if is_eligible else "ineligible"),
            "metrics": {"independent_rules": [rule], "untested_or_shared_rules": [], "floors": measured},
            "candidate": evaluation,
            "limitation": "development fixture only. Atmospheric producers, EDMF, copies, radiation physics "
                          "and held-out scope remain unqualified"}
