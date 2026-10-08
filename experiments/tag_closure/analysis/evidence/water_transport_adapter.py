"""Verify optional water known-answer evidence through the existing Bundle.

Eligibility is reconstructed from equations, actual archived rung values and
per-norm errors. Submitted eligibility, convergence and floor booleans are not
inputs. This adapter is deliberately limited to the preregistered development
fixtures; it supplies no atmospheric producer or copies qualification.
"""

import json
from pathlib import Path

import numpy as np

from acceptance_data import aligned, density, require, same_bits, window
from manifest import sha256_file
from water_transport_reference import (
    BASE_COMMIT, DESIGN_SHA256, FIELD_NAMES, NativeState, analytic, case_by_id,
    closure, error_rows, load_design, numerical, prescribed_parent_trajectory,
    quadrature, rule_for,
)


SOURCE_FILES = ("water_transport_reference.py", "water_transport_adapter.py",
                "make_water_transport_fixture.py")
FIXTURE_SCOPE = "preregistered water known-answer development fixture"


def evaluator_identities():
    return {name: sha256_file(Path(__file__).with_name(name)) for name in SOURCE_FILES}


def rungs(design, case):
    grids = case["grids"] if case["grids"] is not None else [None]
    newtons = case["newton_iterations"] if case["newton_iterations"] is not None else [None]
    result = []
    for grid in grids:
        for dt in case["dt_seconds"]:
            for count in newtons:
                result.append({"kind": "numerical", "grid": grid, "dt_seconds": dt,
                               "newton_iterations": count,
                               "role": f"floor_g{grid}_dt{dt}_n{count}"})
        if case["kind"] == "periodic_smooth":
            for order in design["independent_quadrature_orders"]:
                result.append({"kind": "quadrature", "grid": grid, "order": order,
                               "role": f"quadrature_g{grid}_o{order}"})
    return result


def regenerate(design, case, rung):
    if rung["kind"] == "quadrature":
        return quadrature(design, case, rung["grid"], rung["order"])
    return numerical(design, case, rung["grid"], rung["dt_seconds"], rung["newton_iterations"])


def read_native(bundle, role, expected):
    fields, values = {}, {}
    for name in FIELD_NAMES:
        field = bundle.field(role, name)
        require(field.sampling == "instantaneous" and field.dimensions == ("z",) and
                field.weight_units == "m", f"{role}:{name}: wrong native convention")
        require(field.values.dtype == np.dtype("float64") and
                field.time.dtype == field.geometry.dtype == field.weights.dtype == np.dtype("float64"),
                f"{role}:{name}: frozen Float64 dtype required")
        require(same_bits(field.time, expected.time) and same_bits(field.geometry, expected.geometry) and
                same_bits(field.weights, expected.weights),
                f"{role}:{name}: expected exact physical time/native face geometry")
        fields[name] = field
    rho = fields["rho"]
    require(rho.units == "kg m^-3" and rho.representation == "density" and
            np.all(rho.values > 0), f"{role}: invalid native density")
    values["rho"] = rho.values.copy()
    for name in FIELD_NAMES[1:]:
        field = fields[name]
        aligned(field, rho, role + ": density weighting")
        require((field.units, field.representation) in
                (("kg m^-3", "density"), ("kg kg^-1", "specific")),
                f"{role}:{name}: wrong mass units/representation")
        values[name] = density(field, rho)
        require(np.all(values[name] >= 0), f"{role}:{name}: negative known-answer holding")
    return NativeState(rho.time.copy(), expected.faces.copy(), values, {})


def matches_measured(actual, expected, label, design):
    for name in FIELD_NAMES:
        scale = float(np.max(np.abs(expected.values[name])))
        # Relative arithmetic allowance; an expected zero requires an actual zero.
        limit = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps * scale
        require(np.max(np.abs(actual.values[name] - expected.values[name])) <= limit,
                f"{label}:{name}: archived values differ from independent equations/solve")


def evaluate_water_transport(bundle, start=0, end=86400):
    """Measure this fixture's eligibility, retaining every independent rung."""
    spec = bundle.spec
    require(spec.get("claim") == {"family": "water", "scope": FIXTURE_SCOPE, "precipitation": False},
            "water transport adapter has only preregistered development-fixture scope")
    require(spec.get("case") != "D4-W", "option D excludes D4-W origin qualification")
    require(spec.get("precision") == "Float64" and spec.get("geometry_kind") == "column" and
            spec.get("end_seconds") == 86400, "water fixture precision/geometry/duration differs")
    reference = spec.get("reference", {})
    require(reference.get("kind") == "water_transport", "wrong water reference adapter kind")
    detail = json.loads(bundle.artifact(reference.get("evidence")).read_text())
    design = load_design(bundle.artifact(detail.get("design")))
    require(detail.get("design_sha256") == DESIGN_SHA256 and
            detail.get("identity") == reference.get("identity") == design["identity"],
            "water reference identity/preregistration differs")
    require(detail.get("schema_version") == 1 and detail.get("development_only") is True,
            "water known-answer scope marker missing")
    case = case_by_id(design, detail.get("case_id"))
    require(spec.get("case") == case["id"] and spec.get("resolved_settings", {}).get("physics") == case and
            spec.get("resolved_settings", {}).get("tag_definitions") == design["tags"],
            "water case/physics/config tag scope differs")
    require(spec.get("tags") == design["tags"] and detail.get("tag_names") ==
            [tag["name"] for tag in design["tags"]], "water tag kind/count/partition scope differs")
    rule = rule_for(case)
    require(spec.get("active_rules") == detail.get("active_rules") == detail.get("independent_rules") == [rule] and
            detail.get("shared_rules") == [], "shared, missing or extra active rule in water fixture")
    require(detail.get("end_seconds") == 86400 and detail.get("model_commit") ==
            bundle.manifest.get("head_sha") == BASE_COMMIT,
            "water reference model/time scope differs from exact dependency")
    require(detail.get("evaluator_files") == evaluator_identities(), "stale water reference evaluator identity")
    sources = detail.get("sources", {})
    require(set(sources) == set(SOURCE_FILES), "incomplete independent evaluator source inventory")
    for name, rel in sources.items():
        require(sha256_file(bundle.artifact(rel)) == evaluator_identities()[name],
                "archived water evaluator source differs")
    config = json.loads(bundle.artifact(detail.get("config")).read_text())
    require(config == {"schema_version": 1, "case_id": case["id"],
                       "comparison_grid": detail.get("comparison_grid"),
                       "reference_mode": detail.get("reference_mode"),
                       "reference_rung": detail.get("reference_rung"),
                       "design_sha256": DESIGN_SHA256, "scope": FIXTURE_SCOPE},
            "resolved water reference configuration differs")
    require(sha256_file(bundle.artifact(detail["config"])) == bundle.manifest.get("config", {}).get("sha256"),
            "water config differs from original submission identity")
    errors = bundle.validate()
    require(not errors, "invalid existing evidence Bundle: " + "; ".join(errors))
    # The scorer pins its own evaluator and acceptance source files too.
    from score_acceptance import local_identities
    for key, expected in local_identities().items():
        require(spec.get(key) == expected, f"stale existing {key} identity")
    truth = analytic(design, case, detail.get("comparison_grid"))
    window(truth.time, start, end)
    candidate = read_native(bundle, "candidate", truth)
    # Initial state and every excluded-process array are required, not optional flags.
    for name in FIELD_NAMES:
        limit = (design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps *
                 float(np.max(np.abs(truth.values[name][0]))))
        require(np.max(np.abs(candidate.values[name][0] - truth.values[name][0])) <= limit,
                "candidate does not match the preregistered native initial condition")
    for process in design["excluded_processes"]:
        field = bundle.field("candidate", "excluded_activity_" + process)
        aligned(field, bundle.field("candidate", "water_parent"), "excluded process accounting")
        require((field.units, field.representation, field.sampling) ==
                ("kg m^-3", "density", "cumulative") and np.array_equal(field.values, np.zeros_like(field.values)),
                "active excluded process lacks independent coverage: " + process)
    declared = detail.get("rungs")
    expected_rungs = rungs(design, case)
    require(declared == expected_rungs, "incomplete or changed full grid/time/Newton/integration ladder")
    floors = []
    measured = {}
    for rung in expected_rungs:
        expected = regenerate(design, case, rung)
        stored = read_native(bundle, rung["role"], expected)
        matches_measured(stored, expected, rung["role"], design)
        own_truth = analytic(design, case, rung["grid"])
        rows = error_rows(stored, own_truth, design)
        applicable = [row for row in rows if start <= row["endpoint_seconds"] <= end]
        floors.append({**rung, "errors": rows, "diagnostics": expected.diagnostics,
                       "eligible": bool(applicable) and all(row["floor_eligible"] for row in applicable)})
        measured[rung["role"]] = stored
    if detail.get("reference_mode") == "analytic":
        require(detail.get("reference_rung") is None, "analytic reference has no numerical rung")
        expected_reference = truth
        selected_floors = [floor for floor in floors if floor["kind"] == "quadrature" and
                           floor["grid"] == detail["comparison_grid"]]
    elif detail.get("reference_mode") == "numerical":
        selected = detail.get("reference_rung")
        require(selected in expected_rungs and selected["kind"] == "numerical" and
                selected["grid"] == detail["comparison_grid"], "selected numerical reference is outside the frozen ladder")
        expected_reference = measured[selected["role"]]
        selected_floors = [floor for floor in floors if floor["role"] == selected["role"]]
        selected_floors += [floor for floor in floors if floor["kind"] == "quadrature" and
                           floor["grid"] == detail["comparison_grid"]]
    else:
        raise ValueError("unknown water reference mode")
    reference_state = read_native(bundle, "reference", truth)
    matches_measured(reference_state, expected_reference, "reference", design)
    # Analytic boundaries/exchange have no quadrature discretization floor.
    # Their floating arithmetic is bounded explicitly in the same norm.
    eps = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps
    roundoff = NativeState(truth.time, truth.faces,
                          {name: value.copy() * (1.0 + eps) if name.startswith("tag_") else value.copy()
                           for name, value in truth.values.items()}, {})
    roundoff_rows = error_rows(roundoff, truth, design)
    eligible_rows = [row for row in roundoff_rows if start <= row["endpoint_seconds"] <= end]
    eligible = all(row["floor_eligible"] for row in eligible_rows) and all(floor["eligible"] for floor in selected_floors)
    candidate_errors = error_rows(candidate, reference_state, design)
    max_fraction = max([max(row["fraction_of_tolerance"].values()) for row in eligible_rows] +
                       [max(row["fraction_of_tolerance"].values()) for floor in selected_floors
                        for row in floor["errors"] if start <= row["endpoint_seconds"] <= end])
    bundle.reverify()
    return {"meets": bool(eligible),
            "reference_eligibility": "eligible for fixture equations only" if eligible else "ineligible",
            "metrics": {"independent_rules": [rule], "untested_or_shared_rules": [],
                        "floor_fraction_of_tolerance": max_fraction, "rungs": floors,
                        "arithmetic_bound": roundoff_rows, "candidate_errors": candidate_errors,
                        "candidate_closure": closure(candidate, design),
                        "candidate_parent_trajectory": prescribed_parent_trajectory(candidate, truth, design)},
            "limitation": "development fixture only; production coverage, copies, parent physics and held-out scope remain unqualified"}
