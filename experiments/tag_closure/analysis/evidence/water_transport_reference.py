"""Bounded independent water references on native unit-area cells.

The continuum equations and all refinement rungs are fixed in the sibling
design file. This offline module calls no model transport, copies or tag
kernel. Its known answers do not qualify an atmospheric origin claim.

The OD3 profile limits, the small-tag rule and OD12's quarter rule are the
scorer's named constants, imported here. The design file repeats them for the
record only, and a test checks that the two agree.
"""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from numpy.polynomial.legendre import leggauss

from acceptance_data import require
from score_acceptance import SMALL, SMALL_SHARE, origin_limits


# The planning tree whose scorer and approved numbers these fixtures use.
BASE_COMMIT = "9c710edcea50d78e8e668e738223bc71c32a69f8"
DESIGN_SHA256 = "597e39a84a142649f5355177a2c03f74ee7d0ae0c63d05e9e04515e23ff96f37"
DESIGN_PATH = Path(__file__).with_name("water_transport_design.json")
FIELD_NAMES = ("rho", "water_parent", "tag_origin_a", "tag_origin_b",
               "tag_overlay", "tag_tiny", "tag_zero")


def load_design(path=DESIGN_PATH):
    raw = Path(path).read_bytes()
    if hashlib.sha256(raw).hexdigest() != DESIGN_SHA256:
        raise ValueError("water reference design differs from the preregistration")
    return json.loads(raw)


def case_by_id(design, case_id):
    matches = [case for case in design["cases"] if case["id"] == case_id]
    if len(matches) != 1:
        raise ValueError("unknown or duplicate water reference case")
    return matches[0]


def rule_for(case):
    return ("prescribed_reservoir_exchange" if case["kind"] == "two_reservoir_exchange"
            else "prescribed_conservative_advection")


def native_faces(case, grid=None):
    if case["kind"] == "two_reservoir_exchange":
        if grid is not None:
            raise ValueError("grid refinement is inapplicable to two fixed reservoirs")
        return np.concatenate(([0.0], np.cumsum(case["thickness_m"], dtype=np.float64)))
    if grid not in case["grids"]:
        raise ValueError("grid is outside the frozen ladder")
    return case["length_m"] * np.linspace(0.0, 1.0, grid + 1) ** case["grid_power"]


@dataclass
class NativeState:
    time: np.ndarray
    faces: np.ndarray
    values: dict
    diagnostics: dict

    @property
    def weights(self):
        return np.diff(self.faces)

    @property
    def geometry(self):
        # Both native faces are stored. Centres alone cannot define cell averages.
        return np.column_stack((self.faces[:-1], self.faces[1:]))


def _state(times, faces, rows, diagnostics=None):
    values = {name: np.asarray(rows[name], dtype=np.float64) for name in FIELD_NAMES}
    if any(value.shape != (len(times), len(faces) - 1) for value in values.values()):
        raise ValueError("invalid native state shape")
    if any(not np.isfinite(value).all() for value in values.values()):
        raise ValueError("nonfinite independent reference")
    return NativeState(np.asarray(times, dtype=np.float64), faces, values, diagnostics or {})


def _with_overlays(rho, parent, origin_a, fractions):
    return {"rho": rho, "water_parent": parent, "tag_origin_a": origin_a,
            "tag_origin_b": parent - origin_a,
            **{"tag_" + name: fraction * parent for name, fraction in fractions.items()}}


def analytic(design, case, grid=None):
    """Integrate the exact continuum solution over each native face pair."""
    faces = native_faces(case, grid)
    width = np.diff(faces)
    times = np.asarray(design["times_seconds"], dtype=np.float64)
    rows = {name: [] for name in FIELD_NAMES}
    q = case["water_specific"]
    if case["kind"] == "two_reservoir_exchange":
        rho = np.asarray(case["density_kg_m3"], dtype=np.float64)
        parent = q * rho
        amounts = parent * width
        fractions = np.asarray(case["initial_origin_a_fraction"], dtype=np.float64)
        initial = amounts * fractions
        equilibrium = np.sum(initial) / np.sum(amounts)
        decay = case["exchange_kg_m2_s"] * np.sum(1.0 / amounts)
    for time in times:
        if case["kind"] == "periodic_smooth":
            k = 2.0 * np.pi / case["length_m"]
            left, right = faces[:-1] - case["velocity_m_s"] * time, faces[1:] - case["velocity_m_s"] * time
            # Integrals of cos(k y) and sin(k y), rather than midpoint samples.
            cosine = (np.sin(k * right) - np.sin(k * left)) / k
            sine = (np.cos(k * left) - np.cos(k * right)) / k
            rho = case["density_mean"] * (width + case["density_amplitude"] * cosine) / width
            parent = q * rho
            origin_a = q * case["density_mean"] * (
                (width + case["density_amplitude"] * cosine) / 2.0 +
                case["label_amplitude"] * sine) / width
        elif case["kind"] == "labelled_inflow":
            rho = np.full(len(width), case["density_mean"], dtype=np.float64)
            parent = q * rho
            distance = min(abs(case["velocity_m_s"]) * time, case["length_m"])
            start, end = ((0.0, distance) if case["velocity_m_s"] > 0 else
                          (case["length_m"] - distance, case["length_m"]))
            intersection = np.maximum(0.0, np.minimum(faces[1:], end) - np.maximum(faces[:-1], start))
            # Divide geometry first. A fully invaded cell then has exactly
            # fraction one, avoiding a negative remainder from (parent*w)/w.
            origin_a = parent * (intersection / width)
        elif case["kind"] == "two_reservoir_exchange":
            first = (amounts[0] * equilibrium + amounts[0] * amounts[1] / np.sum(amounts) *
                     (fractions[0] - fractions[1]) * np.exp(-decay * time))
            origin_a = np.array([first, np.sum(initial) - first]) / width
        else:
            raise ValueError("unsupported frozen case")
        fields = _with_overlays(rho, parent, origin_a, design["source_fractions"])
        for name in FIELD_NAMES:
            rows[name].append(fields[name])
    return _state(times, faces, rows, {"method": "analytic native cell integrals"})


def quadrature(design, case, grid, order):
    """Independent Gauss integration of the smooth pointwise mass profiles.

    This intentionally does not call the analytic antiderivatives. The
    duplicated pointwise continuum equation is the only shared physics.
    """
    if case["kind"] != "periodic_smooth" or order not in design["independent_quadrature_orders"]:
        raise ValueError("quadrature is only applicable at frozen smooth-case orders")
    faces = native_faces(case, grid)
    nodes, weights = leggauss(order)
    x = (faces[:-1, None] + faces[1:, None]) / 2.0 + np.diff(faces)[:, None] * nodes / 2.0
    rows = {name: [] for name in FIELD_NAMES}
    for time in design["times_seconds"]:
        phase = 2.0 * np.pi * (x - case["velocity_m_s"] * time) / case["length_m"]
        point_rho = case["density_mean"] * (1.0 + case["density_amplitude"] * np.cos(phase))
        point_parent = case["water_specific"] * point_rho
        point_a = (point_parent / 2.0 + case["water_specific"] * case["density_mean"] *
                   case["label_amplitude"] * np.sin(phase))
        fields = _with_overlays(point_rho, point_parent, point_a, design["source_fractions"])
        for name in FIELD_NAMES:
            rows[name].append(np.sum(fields[name] * weights, axis=1) / 2.0)
    return _state(design["times_seconds"], faces, rows, {"method": "independent Gauss quadrature", "order": order})


def _initial_numeric(design, case, grid):
    if case["kind"] == "periodic_smooth":
        # Initial cell integrals have a measured independent quadrature floor.
        initial = quadrature(design, case, grid, max(design["independent_quadrature_orders"]))
        return np.stack([initial.values[name][0] for name in FIELD_NAMES])
    width = np.diff(native_faces(case, grid))
    if case["kind"] == "labelled_inflow":
        rho = np.full(len(width), case["density_mean"])
        parent = case["water_specific"] * rho
        first = np.zeros_like(parent)
    else:
        rho = np.asarray(case["density_kg_m3"], dtype=np.float64)
        parent = case["water_specific"] * rho
        first = parent * np.asarray(case["initial_origin_a_fraction"])
    fields = _with_overlays(rho, parent, first, design["source_fractions"])
    return np.stack([fields[name] for name in FIELD_NAMES])


def refinement_rungs(case):
    """The (grid, dt) pairs of a case's refinement ladder, coarse to fine.

    An advective case refines the grid and the time step together at one
    fixed CFL number. Rung i pairs grids[i] with dt_seconds[i], and every
    pair has the same product grid * dt. Two fixed reservoirs have no grid,
    so the exchange case refines the time step alone.
    """
    if case["kind"] == "two_reservoir_exchange":
        if case["ladder"] != "time_step_only":
            raise ValueError("the exchange ladder must refine the time step alone")
        return [(None, dt) for dt in case["dt_seconds"]]
    if case["ladder"] != "fixed_cfl" or len(case["grids"]) != len(case["dt_seconds"]):
        raise ValueError("an advective ladder must pair each grid with one time step")
    if any(grid * dt != case["grid_times_dt_seconds"] for grid, dt in zip(case["grids"], case["dt_seconds"])):
        raise ValueError("an advective ladder must keep the CFL number fixed")
    return list(zip(case["grids"], case["dt_seconds"]))


def numerical(design, case, grid=None, dt=None, newton=None):
    """Separately implemented conservative upwind or implicit exchange solve.

    Every requested step is executed. Exact endpoint divisibility and CFL
    are required. No temporal interpolation or analytic evolution is used.
    """
    if (grid, dt) not in refinement_rungs(case):
        raise ValueError("grid and timestep are not a rung of the fixed-CFL ladder")
    exchange = case["kind"] == "two_reservoir_exchange"
    if (exchange and newton not in case["newton_iterations"]) or (not exchange and newton is not None):
        raise ValueError("invalid or inapplicable Newton rung")
    times = design["times_seconds"]
    if any(time % dt != 0 for time in times) or times[0] != 0:
        raise ValueError("all requested physical endpoints must be exact steps")
    faces = native_faces(case, grid)
    width = np.diff(faces)
    current = _initial_numeric(design, case, grid)
    rows = {name: [current[i].copy()] for i, name in enumerate(FIELD_NAMES)}
    initial_amounts = np.sum(current * width, axis=1)
    net_inflow = np.zeros(len(FIELD_NAMES))
    mass_defects, boundary_amounts = [], []
    residual_by_iteration = np.zeros(newton + 1 if exchange else 0)
    # Counted as they run, so a skipped step or solve shows in the diagnostics.
    executed_steps, newton_solves = 0, 0
    if exchange:
        parents = current[1] * width
        flow = case["exchange_kg_m2_s"]
        generator = np.array([[-flow / parents[0], flow / parents[1]],
                              [flow / parents[0], -flow / parents[1]]])
        jacobian = np.eye(2) - dt * generator
    else:
        velocity = case["velocity_m_s"]
        if abs(velocity) * dt / np.min(width) > 1.0:
            raise ValueError("upwind reference violates its native-cell CFL")
        # The ladder's CFL number on the nominal spacing L / grid. Equal on every rung.
        nominal_cfl = abs(velocity) * dt * grid / case["length_m"]
        incoming_rho = np.array([case["density_mean"]])
        incoming_parent = case["water_specific"] * incoming_rho
        incoming = _with_overlays(incoming_rho, incoming_parent, incoming_parent, design["source_fractions"])
        boundary = np.array([incoming[name][0] for name in FIELD_NAMES])
    for step in range(1, int(times[-1] / dt) + 1):
        if exchange:
            # rho and parent reservoirs are fixed. All tag amounts exchange.
            old = current[2:] * width
            trial = old.copy()
            residual = trial - old - dt * (trial @ generator.T)
            residual_by_iteration[0] = max(residual_by_iteration[0], float(np.max(np.abs(residual))))
            for iteration in range(newton):
                correction = np.linalg.solve(jacobian, residual.T).T
                newton_solves += 1
                trial -= correction
                residual = trial - old - dt * (trial @ generator.T)
                residual_by_iteration[iteration + 1] = max(
                    residual_by_iteration[iteration + 1], float(np.max(np.abs(residual))))
            current[2:] = trial / width
        else:
            flux = np.empty((len(FIELD_NAMES), len(width) + 1))
            if velocity > 0:
                flux[:, 1:] = velocity * current
                flux[:, 0] = flux[:, -1] if case["kind"] == "periodic_smooth" else velocity * boundary
            else:
                flux[:, :-1] = velocity * current
                flux[:, -1] = flux[:, 0] if case["kind"] == "periodic_smooth" else velocity * boundary
            net_inflow += dt * (flux[:, 0] - flux[:, -1])
            current -= dt * (flux[:, 1:] - flux[:, :-1]) / width
        executed_steps += 1
        time = step * dt
        if time in times[1:]:
            for i, name in enumerate(FIELD_NAMES):
                rows[name].append(current[i].copy())
            mass_defects.append((np.sum(current * width, axis=1) - initial_amounts - net_inflow).tolist())
            boundary_amounts.append(net_inflow.tolist())
    return _state(times, faces, rows, {
        "method": "backward Euler with actual Newton iterations" if exchange else "first-order conservative upwind",
        "grid": grid, "dt_seconds": dt, "newton_iterations": newton,
        "nominal_cfl": None if exchange else nominal_cfl,
        "executed_steps": executed_steps,
        "executed_newton_solves": newton_solves,
        "max_residual_by_iteration_kg_m2": residual_by_iteration.tolist(),
        "signed_boundary_inflow_kg_m2": boundary_amounts,
        "mass_defect_kg_m2": mass_defects,
    })


def profile_error(candidate, reference, name, endpoint, kind):
    """OD3 norms in the existing scorer's density/specific conventions.

    The limits come from the scorer's `origin_limits`, which refuses an
    unknown tag kind or an endpoint without an approved tolerance.
    """
    if not (np.array_equal(candidate.time, reference.time) and
            np.array_equal(candidate.faces, reference.faces)):
        raise ValueError("error requires the same physical times and native faces")
    hits = np.flatnonzero(reference.time == endpoint)
    require(len(hits) == 1, "error needs exactly one sample at the endpoint")
    l1_limit, linf_limit = origin_limits(kind, float(endpoint))
    j = int(hits[0])
    rho_a, rho_b = candidate.values["rho"][j], reference.values["rho"][j]
    if np.any(rho_a <= 0) or np.any(rho_b <= 0):
        raise ValueError("nonpositive density in origin comparison")
    a, b = candidate.values[name][j], reference.values[name][j]
    specific_delta = a / rho_a - b / rho_b
    absolute = float(np.sum(np.abs(specific_delta) * rho_b * reference.weights))
    burden = float(np.sum(np.abs(b) * reference.weights))
    inventory = float(np.sum(b * reference.weights))
    parent = float(np.sum(reference.values["water_parent"][j] * reference.weights))
    # A dry or zero-water reference has no parent scale. The scorer reads it
    # as bad data, so this reference does too.
    require(parent > 0, "nonpositive reference parent water")
    peak = float(np.max(np.abs(b / rho_b)))
    l1, linf = (absolute / burden if burden > 0 else None,
                float(np.max(np.abs(specific_delta))) / peak if peak > 0 else None)
    small = inventory / parent < SMALL_SHARE
    fractions = ({"absolute_L1": absolute / (SMALL * parent)} if small else
                 {"L1": l1 / l1_limit, "Linf": linf / linf_limit})
    return {"absolute_L1_kg_m2": absolute, "relative_L1": l1, "specific_Linf": linf,
            "reference_share": inventory / parent, "small_rule": small,
            "fraction_of_tolerance": fractions, "meets": max(fractions.values()) <= 1.0}


def floor_fraction(row, case):
    """A row's floor as a fraction of its tolerance, for OD12's quarter rule.

    A labelled front is judged in L1 only. The frozen design states no L∞
    requirement for a front (`front_convergence`). A candidate's own profile
    row keeps both OD3 norms.
    """
    fractions = row["fraction_of_tolerance"]
    if case["kind"] == "labelled_inflow":
        fractions = {norm: value for norm, value in fractions.items() if norm != "Linf"}
    return max(fractions.values())


def error_rows(candidate, reference, design):
    return [{"tag": tag["name"], "endpoint_seconds": endpoint,
             **profile_error(candidate, reference, "tag_" + tag["name"], endpoint, tag["kind"])}
            for endpoint in design["times_seconds"][1:] for tag in design["tags"]]


def closure(state, design):
    partition = sum(state.values["tag_" + tag["name"]] for tag in design["tags"] if tag["partition"])
    defect = float(np.max(np.abs(partition - state.values["water_parent"])))
    tolerance = float(design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps *
                      float(np.max(np.abs(state.values["water_parent"]))))
    return {"absolute_density_defect_kg_m3": defect, "roundoff_test_limit_kg_m3": tolerance,
            "meets": bool(defect <= tolerance), "scope": "fixture implementation roundoff test only"}


def prescribed_parent_trajectory(state, truth, design):
    """Check this fixture's exported parent against its prescribed equations.

    Specific origin profiles and partition closure can both hide a common
    density/parent/tag scaling. This is an offline native equation check,
    not a physical model or complete-state parity qualification.
    """
    return _trajectory_match(state, truth, ("rho", "water_parent"), design,
                             "fixture prescribed exported-parent trajectory only")


def _trajectory_match(state, expected, names, design, scope):
    if not (np.array_equal(state.time, expected.time) and np.array_equal(state.faces, expected.faces)):
        raise ValueError("trajectory comparison requires exact times and native faces")
    fields = {}
    for name in names:
        defect = float(np.max(np.abs(state.values[name] - expected.values[name])))
        tolerance = float(design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps *
                          float(np.max(np.abs(expected.values[name]))))
        fields[name] = {"absolute_density_defect_kg_m3": defect,
                        "roundoff_test_limit_kg_m3": tolerance, "meets": bool(defect <= tolerance)}
    return {"fields": fields, "meets": all(row["meets"] for row in fields.values()), "scope": scope}


def origin_swap_invariants(mutant, baseline, design):
    """Verify the actual registered swap, including unchanged parent/overlays/IC."""
    return _trajectory_match(mutant, swapped_origins(baseline), FIELD_NAMES, design,
                             "registered origin swap with parent/source/initial-state preservation")


def swapped_origins(state):
    values = {name: value.copy() for name, value in state.values.items()}
    # Preserve the initial condition and swap only the scored endpoints.
    values["tag_origin_a"][1:] = state.values["tag_origin_b"][1:]
    values["tag_origin_b"][1:] = state.values["tag_origin_a"][1:]
    return NativeState(state.time.copy(), state.faces.copy(), values, {"mutation": "origin swap"})
