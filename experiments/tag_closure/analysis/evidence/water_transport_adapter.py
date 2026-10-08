"""Produce and check the declared eligibility of the water known-answer fixtures.

This module is the producing script that a water fixture's manifest names and
hashes. It regenerates every archived rung from the independent equations,
measures each floor in OD3's norms and writes the declared eligibility file
that the scorer's own eligibility reader reads. Rerun on a finished bundle, it
is the producer's internal check: it refuses a declaration that differs from
its recompute. The scorer itself does not import this module.

It is limited to the preregistered development fixtures. It supplies no
atmospheric producer or copies qualification.
"""

import json
from pathlib import Path

import numpy as np

from acceptance_data import aligned, density, require, same_bits, window
from manifest import sha256_file
from score_acceptance import FLOOR_FRACTION_MAX, local_identities
from water_transport_reference import (
    BASE_COMMIT, DESIGN_SHA256, FIELD_NAMES, NativeState, analytic, case_by_id,
    closure, error_rows, floor_fraction, load_design, numerical,
    prescribed_parent_trajectory, quadrature, rule_for,
)


SOURCE_FILES = ("water_transport_reference.py", "water_transport_adapter.py",
                "make_water_transport_fixture.py")
FIXTURE_SCOPE = "preregistered water known-answer development fixture"
PRODUCER = "water_transport_adapter.py"
# The fields this producer declares in the evidence file. The scorer reads
# producer, floors, converged, mirrors_complete and jacobian_complete. The
# basis fields say what each value rests on.
DECLARED_FIELDS = ("producer", "floors", "floor_basis", "converged", "mirrors_complete",
                   "jacobian_complete", "eligibility_basis")
STATED_FLOORS = {
    "source_injection": "Stated, not measured. The frozen equations have no source term. "
                        "The inflow label is a prescribed exact boundary value.",
    "initialization": "Stated, not measured. The producer refuses a candidate whose initial "
                      "state differs from the closed-form initial cell integrals by more than "
                      "the roundoff allowance.",
    "parent_solve": "Stated, not measured. The parent is prescribed. An upwind reference that "
                    "moves the parent carries that error inside its reference-discretization floor.",
    "contamination": "Stated, not measured. No other process acts. Every excluded process "
                     "reads a zero cumulative array in the candidate.",
}


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
        # Relative arithmetic allowance. An expected zero requires an actual zero.
        limit = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps * scale
        require(np.max(np.abs(actual.values[name] - expected.values[name])) <= limit,
                f"{label}:{name}: archived values differ from independent equations/solve")


def producer_identity():
    return {"script": PRODUCER, "sha256": sha256_file(Path(__file__))}


def rung_floor(rows, case, start, end):
    """The largest floor fraction of a rung's rows inside the window."""
    applicable = [row for row in rows if start <= row["endpoint_seconds"] <= end]
    require(applicable, "no approved endpoint inside the reference window")
    return max(floor_fraction(row, case) for row in applicable)


def ladder_axes(case, selected, expected_rungs):
    """Each refinement axis through the selected rung, ordered coarse to fine.

    Only the rungs up to the selected one count, since a reference is judged
    at the rung it uses.
    """
    numerical_rungs = [rung for rung in expected_rungs if rung["kind"] == "numerical"]
    keys = ("grid", "dt_seconds", "newton_iterations")
    axes = {}
    for key, ladder_key in zip(keys, ("grids", "dt_seconds", "newton_iterations")):
        ladder = case[ladder_key]
        if ladder is None:
            continue
        chain = []
        for value in ladder[:ladder.index(selected[key]) + 1]:
            matches = [rung for rung in numerical_rungs if rung[key] == value and
                       all(rung[k] == selected[k] for k in keys if k != key)]
            require(len(matches) == 1, "refinement axis is outside the frozen ladder")
            chain.append(matches[0])
        axes[key] = chain
    return axes


def converges(axes, floor_by_role, tie):
    """True when no refinement step toward the selected rung raises the floor.

    A rise within the frozen roundoff allowance is a tie, not a rise.
    """
    reasons = []
    for axis, chain in axes.items():
        values = [floor_by_role[rung["role"]] for rung in chain]
        if any(later > earlier * (1.0 + tie) for earlier, later in zip(values, values[1:])):
            reasons.append(f"The floor rises along {axis} " +
                           " -> ".join(f"{rung[axis]}: {value:.6g}" for rung, value in zip(chain, values)))
    return not reasons, reasons


def first_iteration_at_roundoff(residuals, allowance):
    """A complete Jacobian of a linear system leaves only roundoff after one iteration."""
    return len(residuals) > 1 and residuals[1] <= allowance


def evaluate_water_transport(bundle, declared=True):
    """Measure the fixture's eligibility from its archived rungs.

    With `declared`, the evidence file must hold this producer's declaration
    and it must equal the recompute. The producer itself runs with
    `declared=False` before it writes the declaration. The declaration covers
    the claim's whole day. The scorer reads the same floors for every OD2
    window, so a window inherits the largest floor of the day.
    """
    start, end = 0, 86400
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
    require(not errors, "invalid existing evidence Bundle: " + ". ".join(errors))
    # The scorer pins its own evaluator files and approved numbers too.
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
    declared_rungs = detail.get("rungs")
    expected_rungs = rungs(design, case)
    require(declared_rungs == expected_rungs, "incomplete or changed full grid/time/Newton/integration ladder")
    tie = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps
    floors, measured, floor_by_role = [], {}, {}
    for rung in expected_rungs:
        expected = regenerate(design, case, rung)
        stored = read_native(bundle, rung["role"], expected)
        matches_measured(stored, expected, rung["role"], design)
        own_truth = analytic(design, case, rung["grid"])
        rows = error_rows(stored, own_truth, design)
        value = rung_floor(rows, case, start, end)
        floor_by_role[rung["role"]] = value
        floors.append({**rung, "errors": rows, "diagnostics": expected.diagnostics,
                       "floor_fraction": value, "eligible": value <= FLOOR_FRACTION_MAX})
        measured[rung["role"]] = stored
    quadrature_floors = [floor["floor_fraction"] for floor in floors if floor["kind"] == "quadrature" and
                         floor["grid"] == detail["comparison_grid"]]
    # The roundoff bound is constructed, not measured. Every tag of the closed
    # form is scaled by (1 + 128 eps) and compared with the closed form.
    eps = design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps
    roundoff = NativeState(truth.time, truth.faces,
                          {name: value.copy() * (1.0 + eps) if name.startswith("tag_") else value.copy()
                           for name, value in truth.values.items()}, {})
    roundoff_rows = error_rows(roundoff, truth, design)
    constructed = rung_floor(roundoff_rows, case, start, end)
    mode = detail.get("reference_mode")
    if mode == "analytic":
        require(detail.get("reference_rung") is None, "analytic reference has no numerical rung")
        expected_reference = truth
        discretization = max([constructed] + quadrature_floors)
        discretization_basis = (
            "Measured and constructed. Independent Gauss quadrature at every frozen order on the "
            "comparison grid, and the constructed roundoff bound." if quadrature_floors else
            "Constructed, not measured. The answer is a closed-form cell integral. The floor is the "
            "error of a 128 eps relative perturbation of every tag.")
        converged, converged_basis = True, (
            "Inapplicable. A closed-form answer has no refinement ladder. The independent numerical "
            "route is reported in closed_form_cross_check and gates nothing.")
        jacobian, jacobian_basis = True, "Inapplicable. The closed form has no implicit tag solve."
    elif mode == "numerical":
        selected = detail.get("reference_rung")
        require(selected in expected_rungs and selected["kind"] == "numerical" and
                selected["grid"] == detail["comparison_grid"], "selected numerical reference is outside the frozen ladder")
        expected_reference = measured[selected["role"]]
        discretization = max([constructed, floor_by_role[selected["role"]]] + quadrature_floors)
        discretization_basis = ("Measured. The selected rung against the closed form on its own grid, "
                                "with the initial-state quadrature and the constructed roundoff bound.")
        converged, reasons = converges(ladder_axes(case, selected, expected_rungs), floor_by_role, tie)
        converged_basis = ("Measured. No refinement step toward the selected rung raises its floor."
                           if converged else "Measured. " + ". ".join(reasons) + ".")
        if case["kind"] == "two_reservoir_exchange":
            residuals = floors[expected_rungs.index(selected)]["diagnostics"]["max_residual_by_iteration_kg_m2"]
            scale = float(np.max(np.abs(truth.values["water_parent"] * truth.weights)))
            jacobian = first_iteration_at_roundoff(residuals, eps * scale)
            jacobian_basis = (f"Measured. The largest residual after the first Newton iteration is "
                              f"{residuals[1]:.3g} kg m^-2 against a roundoff allowance of {eps * scale:.3g}.")
        else:
            jacobian, jacobian_basis = True, "Inapplicable. The explicit upwind has no implicit tag solve."
    else:
        raise ValueError("unknown water reference mode")
    reference_state = read_native(bundle, "reference", truth)
    matches_measured(reference_state, expected_reference, "reference", design)
    declaration = {
        "producer": producer_identity(),
        "floors": {"reference_discretization": discretization, **{source: 0.0 for source in STATED_FLOORS}},
        "floor_basis": {"reference_discretization": discretization_basis, **STATED_FLOORS},
        "converged": bool(converged),
        # Source mirrors are a copies condition (G3_PLAN 6.1.2). This reference
        # has no source to mirror. That absence is read from the zero
        # excluded-process arrays above, not assumed.
        "mirrors_complete": True,
        "jacobian_complete": bool(jacobian),
        "eligibility_basis": {
            "converged": converged_basis, "jacobian_complete": jacobian_basis,
            "mirrors_complete": "Inapplicable. Source-free equations, and every excluded process reads zero.",
        },
    }
    # The scorer's own reading of a declaration (score_acceptance.py, reference_eligibility).
    eligible = (bool(set(detail.get("independent_rules")) & set(spec.get("active_rules", []))) and
                declaration["converged"] is True and
                all(0 <= value <= FLOOR_FRACTION_MAX for value in declaration["floors"].values()) and
                declaration["mirrors_complete"] is True and declaration["jacobian_complete"] is True)
    if declared:
        for key in DECLARED_FIELDS:
            require(detail.get(key) == declaration[key],
                    f"declared eligibility differs from the producer's recompute: {key}")
        require(reference.get("producer") == declaration["producer"],
                "the manifest does not name this producer and its sha256")
    cross_check = {}
    for floor in floors:
        if floor["kind"] == "numerical":
            cross_check.setdefault(f"dt{floor['dt_seconds']}_n{floor['newton_iterations']}", []).append(
                {"grid": floor["grid"], "floor_fraction": floor["floor_fraction"]})
    if eligible and mode == "analytic":
        verdict = ("constructed eligibility, fixture equations only: a closed-form answer with a constructed "
                   "roundoff floor" + (" and a measured quadrature floor" if quadrature_floors else ""))
    elif eligible:
        verdict = "measured eligibility, fixture equations only: the selected rung meets the quarter rule"
    else:
        verdict = "ineligible"
    candidate_errors = error_rows(candidate, reference_state, design)
    bundle.reverify()
    return {"meets": bool(eligible), "reference_eligibility": verdict, "declaration": declaration,
            "metrics": {"independent_rules": [rule], "untested_or_shared_rules": [],
                        "reference_discretization_floor": discretization, "rungs": floors,
                        "closed_form_cross_check": cross_check,
                        "arithmetic_bound": roundoff_rows, "candidate_errors": candidate_errors,
                        "candidate_closure": closure(candidate, design),
                        "candidate_parent_trajectory": prescribed_parent_trajectory(candidate, truth, design)},
            "limitation": "development fixture only. Production coverage, copies, parent physics and held-out scope remain unqualified"}
