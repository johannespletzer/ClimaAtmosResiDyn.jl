"""Independent small water-transfer equations, never a model-rate oracle.

Native amounts are kg m^-2, rates kg m^-2 s^-1. Positive compartments and
complete origins include separately tracked boundary sinks. Source overlays
are unnormalized independent labels. No production attribution helper runs.
"""

import copy
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from acceptance_data import require, same_bits
from manifest import sha256_file

BASE_COMMIT = "9344147c69f4c58eb1197adf84f3b7b98df65440"
DESIGN_PATH = Path(__file__).with_name("water_transfer_design.json")
DESIGN_SHA256 = "2f57920536d142dca834ed67df9ed0f6e09305ec11833b484f8b200849238a42"
PARTS = ("N", "R", "S")


def load_design(path=DESIGN_PATH):
    require(sha256_file(path) == DESIGN_SHA256, "changed water transfer preregistration")
    return json.loads(Path(path).read_text())


def case_by_id(design, identity):
    found = [c for c in design["cases"] if c["id"] == identity]
    require(len(found) == 1, "unknown/duplicate transfer case")
    return found[0]


def initial(case):
    mass = np.asarray(case["initial_amounts"], dtype=np.float64)
    count = len(mass) + len(case.get("boundary_sinks", []))
    parent = np.zeros(count)
    parent[:len(mass)] = mass
    parts = np.asarray(case["fractions"], dtype=np.float64) * mass
    labels = np.zeros((6, count))
    labels[:3, :len(mass)] = parts
    labels[3] = .45 * labels[0] + .25 * parent
    labels[4] = .001 * parent
    require(np.all(parent >= 0) and np.all(labels >= 0), "negative physical initial water")
    require(np.allclose(labels[:3].sum(axis=0), parent, rtol=0, atol=2e-15), "initial partition differs")
    return parent, labels


def rule_for(case):
    return "independent rain/snow donor sedimentation and export" if case.get("boundary_sinks") else \
        "independent directed compartment donor attribution"


@dataclass
class TransferState:
    time: np.ndarray
    faces: np.ndarray
    rho: np.ndarray
    parent: np.ndarray       # time x compartment, absorbing exports last
    labels: np.ndarray       # time x tag x compartment
    activity: np.ndarray     # time x directed edge, nonnegative integrated water
    label_activity: np.ndarray  # time x tag x directed edge, applied label amount
    diagnostics: dict
    applications: list

    @property
    def internal_count(self):
        return 3 * (len(self.faces) - 1)

    @property
    def weights(self):
        return np.diff(self.faces)

    @property
    def geometry(self):
        return np.column_stack((self.faces[:-1], self.faces[1:]))


def _generator(case):
    """Reference assembly; the RK4 derivative separately traverses each edge."""
    parent, _ = initial(case)
    n, ecount = len(parent), len(case["edges"])
    generator, flux = np.zeros((n, n)), np.zeros((ecount, n))
    for e, flow in enumerate(case["edges"]):
        d, r, value = flow["donor"], flow["recipient"], flow["value"]
        require(value >= 0, "physical directed rates must be nonnegative")
        if flow["kind"] == "coefficient":
            coefficient = value
        else:
            require(parent[d] > 0, "nonzero fixed outflow from empty donor")
            coefficient = value / parent[d]
        generator[d, d] -= coefficient
        generator[r, d] += coefficient
        flux[e, d] = coefficient
    return generator, flux


def _exp_action(matrix, time, values):
    """96-term scaled Taylor exponential accumulated in longdouble.

    This is an independent small solver. Its measured RK4/known-answer floor
    decides eligibility; the fixed series count is not a truth declaration.
    """
    work = np.asarray(matrix, dtype=np.longdouble) * np.longdouble(time)
    norm = float(np.max(np.sum(np.abs(work), axis=0))) if len(work) else 0.
    scale = max(0, int(np.ceil(np.log2(norm / .5)))) if norm > .5 else 0
    work /= np.longdouble(2) ** scale
    term = np.eye(len(work), dtype=np.longdouble)
    result = term.copy()
    for order in range(1, 97):
        term = (term @ work) / np.longdouble(order)
        result += term
    for _ in range(scale):
        result = result @ result
    return np.asarray(result @ np.asarray(values, dtype=np.longdouble), dtype=np.float64)


def _exact_at(case, seconds):
    m0, x0 = initial(case)
    edges = case["edges"]
    ne = len(edges)
    if case["id"] in ("single_transfer", "depleted_donor", "zero_activity"):
        m, x = m0.copy(), x0.copy()
        a, ax = np.zeros(ne), np.zeros((6, ne))
        for k, edge in enumerate(edges):
            d, r = edge["donor"], edge["recipient"]
            a[k] = seconds * edge["value"]
            require(a[k] <= m0[d] + 16 * np.finfo(float).eps * m0[d], "one-way donor depleted before endpoint")
            remaining = 1 - a[k] / m0[d]
            ax[:, k] = (1 - remaining) * x0[:, d]
            m[d] = remaining * m0[d]; m[r] += a[k]
            x[:, d] = remaining * x0[:, d]; x[:, r] += ax[:, k]
        return m, x, a, ax
    generator, flux = _generator(case)
    n = len(m0)
    augmented = np.zeros((n + ne, n + ne))
    augmented[:n, :n], augmented[n:, :n] = generator, flux
    parent_result = _exp_action(augmented, seconds, np.r_[m0, np.zeros(ne)])
    label_result = _exp_action(augmented, seconds, np.c_[x0, np.zeros((6, ne))].T).T
    m, x = parent_result[:n], label_result[:, :n]
    a, ax = parent_result[n:], label_result[:, n:]
    if case["parent_mode"] == "constant_balanced":
        m = m0.copy()
        a = np.asarray([seconds * edge["value"] for edge in edges])
    if case["id"] in ("opposing_net_zero", "stiff_opposing_floor"):
        water_rate = edges[0]["value"]
        decay = np.exp(-water_rate * (1 / m0[0] + 1 / m0[1]) * seconds)
        mean = (x0[:, 0] + x0[:, 1]) / (m0[0] + m0[1])
        difference = (x0[:, 0] / m0[0] - x0[:, 1] / m0[1]) * m0[0] * m0[1] / (m0[0] + m0[1])
        x[:, 0] = m0[0] * mean + difference * decay
        x[:, 1] = x0[:, 0] + x0[:, 1] - x[:, 0]
        x[:, 2] = x0[:, 2]
    elif case["id"] == "three_compartment_cycle":
        theta = edges[0]["value"] / m0[0] * seconds
        damping = np.exp(-1.5 * theta)
        probabilities = [(1 + 2 * damping * np.cos(np.sqrt(3) * theta / 2 - 2 * np.pi * j / 3)) / 3
                         for j in range(3)]
        x = sum(p * np.roll(x0, j, axis=1) for j, p in enumerate(probabilities))
    return m, x, a, ax


def _assemble(design, case, rows, diagnostics=None, applications=None):
    return TransferState(np.asarray(design["times_seconds"], dtype=np.float64),
                         np.asarray(case["cells"], dtype=np.float64),
                         np.asarray(case["rho"], dtype=np.float64),
                         np.asarray([r[0] for r in rows]), np.asarray([r[1] for r in rows]),
                         np.asarray([r[2] for r in rows]), np.asarray([r[3] for r in rows]),
                         diagnostics or {}, applications or [])


def exact(design, case):
    return _assemble(design, case, [_exact_at(case, t) for t in design["times_seconds"]],
                     {"solver": "closed forms / independent longdouble scaled Taylor exponential",
                      "series_terms": 96, "precision": str(np.dtype(np.longdouble))})


def _rhs(case, time, mass, labels):
    """Simultaneous ODE assembly, independent of the exponential generator."""
    dm, dx = np.zeros_like(mass), np.zeros_like(labels)
    water, tagged, shares = [], [], []
    m0, x0 = initial(case)
    for edge in case["edges"]:
        d, r, value = edge["donor"], edge["recipient"], edge["value"]
        require(mass[d] >= 0, "negative physical donor requires a separate numerical rule")
        if edge["kind"] == "coefficient":
            flow, carried = value * mass[d], value * labels[:, d]
            fraction = labels[:, d] / mass[d] if mass[d] > 0 else np.zeros(6)
        else:
            flow = value
            if case.get("endpoint_empty_donor_limit") and time == 86400:
                fraction = x0[:, d] / m0[d]
            elif mass[d] > 0:
                fraction = labels[:, d] / mass[d]
            else:
                require(case.get("endpoint_empty_donor_limit") and time == 86400,
                        "outflow from an empty/negative physical donor")
                fraction = x0[:, d] / m0[d]
            carried = flow * fraction
        require(np.isfinite(carried).all() and flow >= 0, "invalid physical transfer")
        dm[d] -= flow; dm[r] += flow
        dx[:, d] -= carried; dx[:, r] += carried
        water.append(flow); tagged.append(carried); shares.append(fraction)
    return dm, dx, np.asarray(water), np.asarray(tagged).T.reshape(6, -1), shares


def _prescribed_parent(case, time):
    """Fixed rates prescribe the parent; avoid accumulated endpoint drift.

    This independently assembles the affine water balance. Labels still use
    the RK4 derivative and retain their measured arithmetic residuals.
    """
    mass, _ = initial(case)
    if case["parent_mode"] == "constant_balanced":
        return mass
    change = np.zeros_like(mass)
    for edge in case["edges"]:
        require(edge["kind"] == "rate", "affine parent needs prescribed rates")
        change[edge["donor"]] -= edge["value"]
        change[edge["recipient"]] += edge["value"]
    for donor in np.flatnonzero(change < 0):
        mass[donor] *= 1 + time * change[donor] / mass[donor]
    receivers = change >= 0
    mass[receivers] += time * change[receivers]
    require(np.all(mass >= 0), "prescribed donor depleted before endpoint")
    return mass


def rk4(design, case, substeps):
    require(substeps in design["substep_ladder"], "unregistered transfer refinement")
    mass, labels = initial(case)
    activity, label_activity = np.zeros(len(case["edges"])), np.zeros((6, len(case["edges"])))
    rows, apps = [(mass.copy(), labels.copy(), activity.copy(), label_activity.copy())], []
    times = design["times_seconds"]
    for left, right in zip(times, times[1:]):
        step = (right - left) / substeps
        for index in range(substeps):
            start = left + index * step
            fixed = case["kind"] == "constant"
            if fixed: mass = _prescribed_parent(case, start)
            middle_mass = _prescribed_parent(case, start + step / 2) if fixed else None
            end_mass = _prescribed_parent(case, start + step) if fixed else None
            k1 = _rhs(case, start, mass, labels)
            k2 = _rhs(case, start + step / 2, middle_mass if fixed else mass + step / 2 * k1[0], labels + step / 2 * k1[1])
            k3 = _rhs(case, start + step / 2, middle_mass if fixed else mass + step / 2 * k2[0], labels + step / 2 * k2[1])
            k4 = _rhs(case, start + step, end_mass if fixed else mass + step * k3[0], labels + step * k3[1])
            for stage, (result, weight, t) in enumerate(zip((k1, k2, k3, k4), (1/6, 1/3, 1/3, 1/6),
                                                            (start, start + step/2, start + step/2, start + step))):
                for edge_id, edge in enumerate(case["edges"]):
                    apps.append({"edge": edge_id, "time": t, "start": start, "end": start + step,
                                 "stage": stage, "amount": step * weight * result[2][edge_id],
                                 "fractions": np.asarray(result[4][edge_id]).tolist(),
                                 "sampling": "RK4 stage donor"})
            for target, index_result in ((mass, 0), (labels, 1), (activity, 2), (label_activity, 3)):
                target += step / 6 * (k1[index_result] + 2*k2[index_result] + 2*k3[index_result] + k4[index_result])
            if fixed: mass = end_mass
        rows.append((mass.copy(), labels.copy(), activity.copy(), label_activity.copy()))
    return _assemble(design, case, rows, {"solver": "independently assembled RK4", "substeps_per_interval": substeps,
                                         "rhs_evaluations": 4 * substeps * (len(times) - 1)}, apps)


def pool_replay(design, case, substeps):
    """Declared coarse candidate rule, deliberately separate from the oracle."""
    require(case["kind"] == "constant", "frozen constant-rate pool replay only")
    require(substeps in design["substep_ladder"], "unregistered pool replay")
    mass, labels = initial(case)
    activity, label_activity = np.zeros(len(case["edges"])), np.zeros((6, len(case["edges"])))
    rows, apps = [(mass.copy(), labels.copy(), activity.copy(), label_activity.copy())], []
    for left, right in zip(design["times_seconds"], design["times_seconds"][1:]):
        h = (right - left) / substeps
        for k in range(substeps):
            start, end = left + k*h, left + (k+1)*h
            matrix = np.diag(mass.copy())
            rhs = labels.T.copy()
            for edge in case["edges"]:
                d, r, q = edge["donor"], edge["recipient"], h*edge["value"]
                matrix[r, r] += q; matrix[r, d] -= q
            for d in range(len(mass)):
                if matrix[d, d] == 0:
                    require(np.all(matrix[d] == 0) and np.all(rhs[d] == 0), "singular active empty pool")
                    matrix[d, d] = 1
            psi = np.linalg.solve(matrix, rhs).T
            dm, dx = np.zeros_like(mass), np.zeros_like(labels)
            for e, edge in enumerate(case["edges"]):
                d, r, q = edge["donor"], edge["recipient"], h*edge["value"]
                carried = q*psi[:, d]
                dm[d] -= q; dm[r] += q; dx[:, d] -= carried; dx[:, r] += carried
                activity[e] += q; label_activity[:, e] += carried
                apps.append({"edge":e,"time":(start+end)/2,"start":start,"end":end,"stage":0,
                             "amount":q,"fractions":psi[:, d].tolist(),"sampling":"whole-substep pool effective share"})
            mass += dm; labels += dx
            mass = _prescribed_parent(case, end)
        rows.append((mass.copy(), labels.copy(), activity.copy(), label_activity.copy()))
    return _assemble(design, case, rows, {"solver":"declared whole-substep pool diagnostic","substeps":substeps,
                                         "rate_validity":"conditional frozen rates only"}, apps)


def mutation(design, case, baseline):
    mutant = copy.deepcopy(baseline)
    if case["id"] == "single_transfer":
        m0, x0 = initial(case)
        for t, seconds in enumerate(baseline.time[1:], 1):
            q = seconds * case["edges"][0]["value"]
            wrong = x0[:, 1] / m0[1]
            mutant.labels[t, :3, 0] = x0[:3, 0] - q*wrong[:3]
            mutant.labels[t, :3, 1] = x0[:3, 1] + q*wrong[:3]
            mutant.label_activity[t, :3, 0] = q*wrong[:3]
    elif case["id"] == "opposing_net_zero":
        mutant.labels[1:, :3] = baseline.labels[0, :3]
        mutant.label_activity[1:, :3] = 0
    elif case.get("boundary_sinks"):
        m0, x0 = initial(case)
        for t in range(1, len(baseline.time)):
            mutant.labels[t, :3] = x0[:3]
            for e, edge in enumerate(case["edges"]):
                d, r = edge["donor"], edge["recipient"]
                local_n = (d // 3)*3
                fraction = x0[:3, local_n] / m0[local_n]
                carried = baseline.activity[t, e]*fraction
                mutant.labels[t, :3, d] -= carried
                mutant.labels[t, :3, r] += carried
                mutant.label_activity[t, :3, e] = carried
    else:
        mutant.labels[1:, :3] = np.roll(baseline.labels[1:, :3], 1, axis=1)
        mutant.label_activity[1:, :3] = np.roll(baseline.label_activity[1:, :3], 1, axis=1)
    return mutant


def state_fields(state, design, case):
    """Export native density/specific convention and paired scalar boundaries."""
    n = state.internal_count
    levels = n // 3
    out = {"rho": (np.broadcast_to(state.rho, (len(state.time), levels)).copy(), "kg m^-3", "density", "instantaneous", "native")}
    mass = state.parent[:, :n].reshape(len(state.time), levels, 3)
    labels = state.labels[:, :, :n].reshape(len(state.time), 6, levels, 3)
    divisor = state.weights[None, :, None]
    out["water_parent"] = (mass.sum(axis=2)/state.weights, "kg m^-3", "density", "instantaneous", "native")
    for j, part in enumerate(PARTS):
        out["water_"+part] = (mass[:, :, j]/state.weights, "kg m^-3", "density", "instantaneous", "native")
    for i, tag in enumerate(design["tags"]):
        out["tag_"+tag["name"]] = (labels[:, i].sum(axis=2)/state.weights, "kg m^-3", "density", "instantaneous", "native")
        for j, part in enumerate(PARTS):
            out["tag_"+tag["name"]+"_"+part] = (labels[:, i, :, j]/state.weights, "kg m^-3", "density", "instantaneous", "native")
    for sink in case.get("boundary_sinks", []):
        index, species = sink["index"], sink["species"]
        out["export_water_"+species] = (state.parent[:, index:index+1], "kg m^-2", "amount", "cumulative", "scalar")
        for i, tag in enumerate(design["tags"]):
            out["export_"+tag["name"]+"_"+species] = (state.labels[:, i, index:index+1], "kg m^-2", "amount", "cumulative", "scalar")
    exports = state.parent[:, n:].sum(axis=1, keepdims=True)
    out["precipitation_accumulated"] = (exports, "kg m^-2", "amount", "cumulative", "scalar")
    flux = np.zeros((len(state.time), 1))
    tag_flux = np.zeros((len(state.time), 6))
    for e in case["edges"]:
        if e["recipient"] >= n:
            d = e["donor"]
            flux[:, 0] -= e["value"]*state.parent[:, d]
            tag_flux -= e["value"]*state.labels[:, :, d]
    out["precipitation"] = (flux, "kg m^-2 s^-1", "amount", "instantaneous", "scalar")
    for i, tag in enumerate(design["tags"]):
        out["precipitation_accumulated_"+tag["name"]] = (state.labels[:, i, n:].sum(axis=1, keepdims=True), "kg m^-2", "amount", "cumulative", "scalar")
        out["precip_"+tag["name"]] = (tag_flux[:, i:i+1], "kg m^-2 s^-1", "amount", "instantaneous", "scalar")
    return out


def error_rows(candidate, reference, design):
    """Per tag and part, absolute/native/specific norms with explicit scales."""
    require(same_bits(candidate.time, reference.time) and same_bits(candidate.faces, reference.faces) and
            same_bits(candidate.rho, reference.rho), "transfer error native coordinates/density differ")
    n, cells = reference.internal_count, len(reference.weights)
    rows = []
    for j, seconds in enumerate(reference.time[1:], 1):
        m = reference.parent[j, :n].reshape(cells, 3)
        a = candidate.labels[j, :, :n].reshape(6, cells, 3)
        b = reference.labels[j, :, :n].reshape(6, cells, 3)
        for part_id, part in enumerate(("total",) + PARTS):
            aa = a.sum(axis=2) if part == "total" else a[:, :, part_id-1]
            bb = b.sum(axis=2) if part == "total" else b[:, :, part_id-1]
            mass = m.sum(axis=1) if part == "total" else m[:, part_id-1]
            for i, tag in enumerate(design["tags"]):
                difference = aa[i] - bb[i]
                absolute = float(np.abs(difference).sum())
                burden = float(np.abs(bb[i]).sum())
                parent_scale = float(m.sum())
                part_scale = float(mass.sum())
                maximum = float(np.max(np.abs(difference) / (reference.weights * reference.rho)))
                peak = float(np.max(np.abs(bb[i]) / (reference.weights * reference.rho)))
                small = burden / parent_scale < .01
                hour = seconds == 3600
                applicable = seconds in (3600, 86400)
                l1_tolerance = (.01 if tag["kind"] == "region" else .10) if hour else .02
                linf_tolerance = .25 if hour else .05
                limits = {"absolute":2e-4*parent_scale} if small else {"L1":l1_tolerance,"Linf":linf_tolerance}
                metrics = {"absolute":absolute, "L1":absolute/burden if burden else (0. if absolute == 0 else None),
                           "Linf":maximum/peak if peak else (0. if maximum == 0 else None)}
                fractions = {key:metrics[key]/limit if metrics[key] is not None else None for key,limit in limits.items()}
                meets = all(value is not None and value <= 1 for value in fractions.values())
                floor = all(value is not None and value <= .25 for value in fractions.values())
                rows.append({"tag":tag["name"],"compartment":part,"endpoint_seconds":float(seconds),
                             **metrics,"max_specific_error":maximum,"reference_absolute_inventory":burden,
                             "parent_scale":parent_scale,"compartment_scale":part_scale,
                             "absolute_parent_fraction":absolute/parent_scale,
                             "absolute_compartment_fraction":absolute/part_scale if part_scale else None,
                             "normalization_status":"positive" if part_scale else "zero compartment; ratio not applicable",
                             "small":bool(small),"tolerances":limits,"fraction_of_tolerance":fractions,
                             "meets":bool(meets) if applicable else None,"floor_eligible":bool(floor) if applicable else None,
                             "decision_status":"approved original hour/day profile" if part == "total" else
                             "development engineering compartment-origin check; atmospheric threshold unavailable"})
    return rows


def closure(state, design):
    n = state.internal_count
    residual = state.parent - state.labels[:, :3].sum(axis=1)
    scale = np.maximum(np.abs(state.parent), np.abs(state.labels[:, :3]).sum(axis=1))
    # A depleted endpoint retains an arithmetic bound from the positive
    # amounts previously operated on; it gains no negative-water composition.
    scale = np.maximum.accumulate(scale, axis=0)
    allowance = design["profile_rules"]["roundoff_multiplier"] * np.finfo(float).eps * scale
    per_part = residual[:, :n].reshape(len(state.time), -1, 3)
    label_inventory = state.labels.sum(axis=2)
    defect = label_inventory - label_inventory[0]
    inventory_scale = np.maximum(np.abs(label_inventory), np.abs(label_inventory[0]))
    inventory_ok = np.all(np.abs(defect) <= 128*np.finfo(float).eps*inventory_scale)
    physical = np.all(state.parent >= 0) and np.all(state.labels >= -allowance[:, None, :])
    return {"meets":bool(np.all(np.abs(residual) <= allowance) and physical),
            "complete_label_conservation":bool(inventory_ok),
            "max_label_inventory_defect":float(np.max(np.abs(defect))),
            "boundary_exports_included":True,"minimum_parent_amount":float(state.parent.min()),
            "minimum_label_amount":float(state.labels.min()),
            "max_native_partition_defect":float(np.max(np.abs(residual))),
            "signed_residual":per_part.tolist(),
            "per_compartment_gross":np.abs(per_part).sum(axis=1).tolist(),
            "sum_per_compartment_gross":np.abs(per_part).sum(axis=(1,2)).tolist(),
            "gross_of_compartment_sum":np.abs(per_part.sum(axis=2)).sum(axis=1).tolist(),
            "boundary_signed_residual":residual[:, n:].tolist(),
            "units":"kg m^-2", "scope":"arithmetic implementation verification; no production closure tolerance"}


def parent_trajectory(candidate, expected, design):
    results, maximum = [], 0.
    for a,b in ((candidate.parent,expected.parent),(candidate.rho,expected.rho)):
        allowance = design["profile_rules"]["roundoff_multiplier"] * np.finfo(float).eps * np.abs(b)
        results.append(np.all(np.abs(a-b) <= allowance))
        maximum = max(maximum,float(np.max(np.abs(a-b))))
    return {"meets":bool(all(results)),"maximum_native_error":maximum,
            "scope":"prescribed exported parent equation, not atmospheric all-state parity"}


def directed_balance(state, case, design):
    """Reconcile native endpoints to all directed cumulative amounts.

    The arithmetic allowance uses only the initial compartment magnitude and
    its own absolute operated amounts. This is an internal consistency check,
    not a new scientific tolerance or a substitute for donor-origin error.
    """
    parent = np.broadcast_to(state.parent[0],state.parent.shape).copy()
    labels = np.broadcast_to(state.labels[0],state.labels.shape).copy()
    parent_scale = np.abs(parent)
    label_scale = np.abs(labels)
    for e,edge in enumerate(case["edges"]):
        d,r = edge["donor"],edge["recipient"]
        amount = state.activity[:,e]-state.activity[0,e]
        carried = state.label_activity[:,:,e]-state.label_activity[0,:,e]
        parent[:,d] -= amount;parent[:,r] += amount
        labels[:,:,d] -= carried;labels[:,:,r] += carried
        parent_scale[:,d] += np.abs(amount);parent_scale[:,r] += np.abs(amount)
        label_scale[:,:,d] += np.abs(carried);label_scale[:,:,r] += np.abs(carried)
    rounding = design["profile_rules"]["roundoff_multiplier"]*np.finfo(float).eps
    parent_error = np.abs(state.parent-parent)
    label_error = np.abs(state.labels-labels)
    return {"meets":bool(np.all(parent_error<=rounding*parent_scale) and
                         np.all(label_error<=rounding*label_scale)),
            "parent_absolute_residual":parent_error.tolist(),
            "label_absolute_residual":label_error.tolist(),
            "parent_arithmetic_allowance":(rounding*parent_scale).tolist(),
            "label_arithmetic_allowance":(rounding*label_scale).tolist(),
            "units":"kg m^-2",
            "scope":"native directed-amount endpoint consistency, including boundary sinks"}


def application_error(state, case):
    """Compare before netting edges/stages. Pool means are applied mean shares.

    For a pool's one additive application the reference share is its exact
    integrated label export divided by that same directed water amount.
    RK4 uses the actual stage sampling time. These are distinct declared
    temporal observables, not a continuum time-L1 bound or rate validation.
    """
    apps = state.applications
    if not apps:
        apps = []
        for j in range(1,len(state.time)):
            for e in range(len(case["edges"])):
                amount = state.activity[j,e] - state.activity[j-1,e]
                carried = state.label_activity[j,:,e] - state.label_activity[j-1,:,e]
                apps.append({"edge":e,"start":state.time[j-1],"end":state.time[j],"amount":amount,
                             "fractions":(carried/amount if amount > 0 else np.zeros(6)).tolist(),
                             "sampling":"exact integrated synthetic interval share"})
    numerator, maximum, denominator = np.zeros(6), np.zeros(6), 0.
    cache = {}
    for app in apps:
        amount, edge = float(app["amount"]), case["edges"][app["edge"]]
        require(np.isfinite(amount) and amount >= 0, "negative/nonfinite applied transfer weight")
        if amount == 0:
            continue
        def point(t):
            if t not in cache: cache[t] = _exact_at(case,t)
            return cache[t]
        if app["sampling"] == "RK4 stage donor":
            m,x,_,_ = point(app["time"])
            donor = edge["donor"]
            if m[donor] > 0: ref = x[:,donor]/m[donor]
            else:
                require(case.get("endpoint_empty_donor_limit") and app["time"] == 86400,
                        "active reference stage has empty donor")
                m0,x0=initial(case);ref=x0[:,donor]/m0[donor]
        else:
            _,_,a0,b0=point(app["start"]);_,_,a1,b1=point(app["end"])
            expected_amount=a1[app["edge"]]-a0[app["edge"]]
            require(expected_amount > 0, "active application lacks reference transfer")
            ref=(b1[:,app["edge"]]-b0[:,app["edge"]])/expected_amount
        difference=np.abs(np.asarray(app["fractions"])-ref)
        numerator += amount*difference;maximum=np.maximum(maximum,difference);denominator += amount
    return {"applicability":"applicable" if denominator > 0 else "not applicable",
            "weighted_share_error":(numerator/denominator).tolist() if denominator else [None]*6,
            "absolute_applied_label_mismatch":numerator.tolist(),"maximum_share_error":maximum.tolist() if denominator else [None]*6,
            "transfer_amount_Q":denominator,"donor_recipient_leg_activity_2Q":2*denominator,
            "normalization":"sum of nonnegative applied native directed amounts before edge/stage netting",
            "units":"kg m^-2","sampling":[*sorted({a["sampling"] for a in apps})],
            "meets":bool(np.all(numerator/denominator <= .05)) if denominator else None,
            "floor_eligible":bool(np.all(numerator/denominator <= .0125)) if denominator else None,
            "rate_validation":False}


def boundary_error_rows(state, truth, design, case):
    """Same engineering budgets on each exact integrated exterior owner."""
    result = []
    for j, seconds in enumerate(truth.time[1:], 1):
        scale = float(truth.parent[j, :truth.internal_count].sum())
        for sink in case.get("boundary_sinks", []):
            for i, tag in enumerate(design["tags"]):
                expected = abs(float(truth.labels[j, i, sink["index"]]))
                absolute = abs(float(state.labels[j, i, sink["index"]] - truth.labels[j, i, sink["index"]]))
                small = expected / scale < design["profile_rules"]["small_inventory_fraction"]
                tolerance = ((.01 if tag["kind"] == "region" else .10) if seconds == 3600 else .02)
                limit = 2e-4 * scale if small else tolerance * expected
                fraction = absolute / limit
                applicable = seconds in (3600, 86400)
                result.append({"tag":tag["name"],"boundary":sink["species"],"endpoint_seconds":float(seconds),
                               "absolute_native_error":absolute,"reference_absolute_inventory":expected,
                               "parent_scale":scale,"boundary_parent_scale":float(truth.parent[j,sink["index"]]),
                               "small":bool(small),"native_tolerance":limit,"fraction_of_tolerance":fraction,
                               "floor_eligible":fraction <= .25 if applicable else None,
                               "meets":fraction <= 1 if applicable else None,"units":"kg m^-2",
                               "decision_status":"development engineering export-origin check; no atmospheric approval"})
    return result


def floor_result(state, truth, design, case):
    errors=error_rows(state,truth,design)
    process=application_error(state,case)
    check=closure(state,design)
    balance=directed_balance(state,case,design)
    applicable=[r for r in errors if r["floor_eligible"] is not None]
    arithmetic=design["profile_rules"]["roundoff_multiplier"]*np.finfo(float).eps
    perturbed=copy.deepcopy(truth)
    perturbed.labels += arithmetic*np.maximum.accumulate(np.abs(truth.labels),axis=0)
    bounds=error_rows(perturbed,truth,design)
    fractions=[]
    for row,bound in zip(errors,bounds):
        row["arithmetic_fraction_of_tolerance"]=bound["fraction_of_tolerance"]
        row["combined_floor_fraction"]={k:(v+bound["fraction_of_tolerance"][k] if v is not None else None)
                                        for k,v in row["fraction_of_tolerance"].items()}
        if row["floor_eligible"] is not None:
            fractions.extend(row["combined_floor_fraction"].values())
    exports=boundary_error_rows(state,truth,design,case)
    export_bounds=boundary_error_rows(perturbed,truth,design,case)
    for row,bound in zip(exports,export_bounds):
        row["arithmetic_fraction_of_tolerance"]=bound["fraction_of_tolerance"]
        row["combined_floor_fraction"]=row["fraction_of_tolerance"]+bound["fraction_of_tolerance"]
        if row["floor_eligible"] is not None: fractions.append(row["combined_floor_fraction"])
    if process["applicability"] == "applicable":
        shares=np.divide(truth.labels,truth.parent[:,None,:],out=np.zeros_like(truth.labels),where=truth.parent[:,None,:]>0)
        process["arithmetic_share_bound"]=(arithmetic*np.max(np.abs(shares),axis=(0,2))).tolist()
        process["combined_floor_fraction"]=[(v+b)/.05 for v,b in zip(process["weighted_share_error"],process["arithmetic_share_bound"])]
        fractions.extend(process["combined_floor_fraction"])
    else:
        process["arithmetic_share_bound"]=[None]*6
        process["combined_floor_fraction"]=[None]*6
    max_fraction=max((v for v in fractions if v is not None),default=None)
    eligible=bool(applicable and all(v is not None and v <= .25 for v in fractions) and check["meets"] and
                  check["complete_label_conservation"] and balance["meets"])
    return {"eligible":eligible,"errors":errors,"process":process,"closure":check,
            "boundary_errors":exports,
            "directed_balance":balance,
            "maximum_fraction_of_tolerance":max_fraction,"arithmetic_relative_bound":arithmetic,
            "arithmetic_scope":"128 eps64 times retained positive native magnitudes, separately evaluated in each compared norm",
            "diagnostics":state.diagnostics}


def mutation_invariants(actual, baseline, case, design):
    expected=mutation(design,case,baseline)
    checks={}
    for key in ("time","faces","rho","parent","activity"):
        checks[key]=same_bits(getattr(actual,key),getattr(baseline,key))
    checks["initial_labels"]=same_bits(actual.labels[0],baseline.labels[0])
    checks["source_overlays"]=same_bits(actual.labels[:,3:],baseline.labels[:,3:])
    checks["source_applied_amounts"]=same_bits(actual.label_activity[:,3:],baseline.label_activity[:,3:])
    checks["registered_mutation"]=same_bits(actual.labels,expected.labels) and same_bits(actual.label_activity,expected.label_activity)
    return {"meets":bool(all(checks.values())),"checks":checks,
            "parent_rates_and_boundary_conditions":"unchanged pinned case and directed activity",
            "kind":"isolated actual wrong donor/reset/net-flow" if case["id"] in
            ("single_transfer","opposing_net_zero","rain_snow_sedimentation") else "declared origin-permutation corruption"}


def net_replay(design,case,substeps):
    require(case["kind"] == "constant", "net diagnostic needs frozen rates")
    state=pool_replay(design,case,substeps)
    mass,labels=initial(case)
    rows=[labels.copy()]
    for left,right in zip(state.time,state.time[1:]):
        h=(right-left)/substeps
        for _ in range(substeps):
            delta=np.zeros_like(mass)
            for edge in case["edges"]:
                q=h*edge["value"];delta[edge["donor"]]-=q;delta[edge["recipient"]]+=q
            losses=np.maximum(-delta,0)
            positive=mass>0
            fractions=np.zeros_like(labels)
            fractions[:,positive]=labels[:,positive]/mass[positive]
            mix=(fractions*losses).sum(axis=1)/losses.sum() if losses.sum()>0 else np.zeros(6)
            labels += fractions*np.minimum(delta,0) + mix[:,None]*np.maximum(delta,0)
            mass += delta
        rows.append(labels.copy())
    return np.asarray(rows)-state.labels



def signed_audit_activity(audit):
    """Native per-tag endpoint and retained variation before any tag sum."""
    values=np.asarray(audit,dtype=float)
    require(values.ndim==3 and len(values)>=2 and np.isfinite(values).all(), "invalid native audit trajectory")
    endpoint=np.abs(values[-1]-values[0])
    variation=np.abs(np.diff(values,axis=0)).sum(axis=0)
    return {"endpoint_absolute":endpoint.tolist(),"retained_step_variation":variation.tolist(),
            "per_tag_endpoint_integral":endpoint.sum(axis=1).tolist(),
            "per_tag_variation_integral":variation.sum(axis=1).tolist(),
            "summed_tags_not_a_proof":True,"units":"native amount"}


def audit_report(design,case,substeps):
    audit=net_replay(design,case,substeps)
    Q=sum(e["value"] for e in case["edges"])*86400
    activity=signed_audit_activity(audit)
    end=np.asarray(activity["endpoint_absolute"]);variation=np.asarray(activity["retained_step_variation"])
    return {"per_tag_endpoint_absolute":end.tolist(),"per_tag_step_variation":variation.tolist(),
            "max_endpoint_per_tag":end.max(axis=1).tolist(),"integrated_endpoint_per_tag":end.sum(axis=1).tolist(),
            "integrated_variation_per_tag":variation.sum(axis=1).tolist(),
            "endpoint_over_gross_transfer":(end.sum(axis=1)/Q).tolist() if Q else [None]*6,
            "variation_over_gross_transfer":(variation.sum(axis=1)/Q).tolist() if Q else [None]*6,
            "gross_transfer_Q":Q,"net_vs_pool_rule_spread":True,"reference_error":False,
            "precipitation_normalization":"unavailable: this closed frozen-rate replay exports no precipitation",
            "decision_status":"REPORTED ONLY; OD15 audit normalization/trend pending",
            "units":"kg m^-2","substeps":substeps,
            "limitation":"output-interval retained variation; unobserved accepted applications remain blocked"}


def declared_negative_map(raw_mass,labels,flows,dt):
    """Documented numerical stage convention, not physical negative provenance.

    Inputs are three raw compartment amounts and a signed rate matrix with
    nominal donor in the row. Only a pair touching negative raw water may
    reverse a signed rate. Negative targets retain no label; their pool
    passes on at most the labelled inflow, and withheld label is reported.
    """
    raw=np.asarray(raw_mass,dtype=float);x=np.asarray(labels,dtype=float);F=np.asarray(flows,dtype=float)
    require(raw.shape==(3,) and x.ndim==2 and x.shape[1]==3 and F.shape==(3,3) and dt>0,
            "invalid declared negative rule inputs")
    require(np.isfinite(raw).all() and np.isfinite(x).all() and np.isfinite(F).all() and
            np.all(np.diag(F)==0) and np.all(x>=0), "nonfinite/invalid declared rule")
    negative=raw<0;target=np.maximum(raw,0)
    require(np.all(x[:,negative]==0), "negative numerical target must hold zero labels")
    oriented=np.zeros_like(F)
    for a in range(3):
        for b in range(a+1,3):
            if negative[a] or negative[b]:
                oriented[a,b]=max(F[a,b],0)+max(-F[b,a],0)
                oriented[b,a]=max(F[b,a],0)+max(-F[a,b],0)
            else:
                require(F[a,b]>=0 and F[b,a]>=0, "negative flow outside negative-rule scope")
                oriented[a,b],oriented[b,a]=F[a,b],F[b,a]
    incoming,outgoing=oriented.sum(axis=0),oriented.sum(axis=1)
    passes=np.ones(3)
    held=negative & (outgoing>incoming)
    passes[held]=incoming[held]/outgoing[held]
    matrix=np.diag(target+dt*incoming)-dt*oriented.T*passes[None,:]
    rhs=x.T.copy()
    for row in range(3):
        if target[row]+dt*incoming[row]==0:
            matrix[row]=0;matrix[row,row]=1;rhs[row]=0
    shares=np.linalg.solve(matrix,rhs).T
    export=shares*passes
    changes=dt*(export@oriented-export*outgoing)
    withheld=dt*np.maximum(incoming-outgoing,0)*shares*negative
    changes[:,negative]=0
    return {"label_change":changes,"withheld_labels":withheld,"withheld_water":dt*np.maximum(incoming-outgoing,0)*negative,
            "oriented_flows":oriented,"physical_composition":False,"decision_status":"declared numerical-rule test only"}
