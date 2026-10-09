"""Independent energy references on native unit-area cells (Part 11a).

The eight cases of G4_CLAIM_CONTRACTS section 6 are fixed in the sibling
design file, each with its convention `c`. This offline module calls no model
code. It solves each case twice: in closed form, and with a separate step
allocator. Its known answers verify equations and the declared label model.
They do not qualify an atmospheric origin, radiation physics or a run.

The origin limits, the small-tag rules and OD12's quarter rule are the
scorer's named constants, imported here. The design file repeats them for the
record only, and a test checks that the two agree.
"""

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from acceptance_data import require
from score_acceptance import SMALL, SMALL_SHARE, origin_limits


# The planning tree whose scorer and approved numbers these fixtures use, and
# the model tree whose mechanisms the cases describe.
BASE_COMMIT = "ddbafbbfe2434a39b823eb76cde9de89114016cc"
MODEL_COMMIT = "bb2bedf230a70ca9d7afc293180f8d30c1a9bb88"
DESIGN_SHA256 = "2ffdaf7d308edf2ed66ad67a80e89414c9c9294a873eb47cb14cd118b46695f7"
DESIGN_PATH = Path(__file__).with_name("energy_reference_design.json")
STATUS_CODES = {"positive_parent": 0, "zero_parent": 1, "negative_parent": 2}


def load_design(path=DESIGN_PATH):
    raw = Path(path).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == DESIGN_SHA256, "energy reference design differs from the preregistration")
    return json.loads(raw)


def case_by_id(design, case_id):
    matches = [case for case in design["cases"] if case["id"] == case_id]
    if len(matches) != 1:
        raise ValueError("unknown or duplicate energy reference case")
    return matches[0]


def conventions(case):
    """The case's frozen offsets. A record case has none."""
    c = case["convention"]["c_J_kg"]
    require(case["convention"]["frozen"] is True, "the case's convention is not frozen")
    if c is None:
        return []
    return [float(v) for v in c] if isinstance(c, list) else [float(c)]


def theta_x_start(case):
    """The start of the case's declared, frozen Theta_x window. It ends at the endpoint."""
    window = case.get("theta_x_window")
    require(isinstance(window, dict) and window.get("frozen") is True and window.get("end") == "endpoint" and
            isinstance(window.get("start_seconds"), (int, float)),
            "the case declares no frozen Theta_x window ending at the endpoint")
    return float(window["start_seconds"])


def expected_not_assessable(case):
    """The origin rows the frozen design expects NOT ASSESSABLE (decision of 2026-10-09).

    Each row names its tag, endpoint and reason. A row marked `no_gain_path`
    belongs to a tag that the case gives no gain path, so the fixture checks
    that the tag reads exactly zero. The scorer is unchanged.
    """
    return case.get("expected_not_assessable", {}).get("rows", [])


def no_gain_path_tags(case):
    return sorted({row["tag"] for row in expected_not_assessable(case) if row["no_gain_path"]})


def suffixes(case):
    """Field-name suffixes, one per convention. Only the offset pair has two."""
    return ["@%d" % i for i in range(len(conventions(case)))] if len(conventions(case)) > 1 else [""]


@dataclass
class EnergyState:
    time: np.ndarray
    dz: np.ndarray
    values: dict
    diagnostics: dict


def _f(x):
    return np.asarray(x, dtype=np.float64)


def share(a, E):
    """phi = clamp(a / E_c, 0, 1) where E_c > 0, and zero where E_c <= 0 (section 2.2)."""
    a, E = np.broadcast_arrays(_f(a), _f(E))
    out = np.zeros(a.shape)
    np.divide(a, E, out=out, where=E > 0)
    return np.where(E > 0, np.clip(out, 0.0, 1.0), 0.0)


def _weight(tag, process):
    """w_kp: a pure region tag gains by its mask from every process, an overlay by its own label."""
    if not tag["sources"]:
        return _f(tag["mask"])
    if process in tag["sources"]:
        return _f(tag["mask"]) if tag["mask"] is not None else 1.0
    return 0.0


def apply_event(tags, values, E, delta, process):
    """One applied-update event with E_c tendency amount `delta` [J m^-3].

    Gains go by w_kp, losses by every tag's clamped share of the pre-event
    total. Returns the new tag values, the new total and each tag's change.
    """
    gain, loss = np.maximum(delta, 0.0), np.minimum(delta, 0.0)
    # Every change keeps the state's precision, so a Float32 rung stays Float32.
    change = {t["name"]: (_weight(t, process) * gain + share(values[t["name"]], E) * loss).astype(E.dtype)
              for t in tags}
    return {k: values[k] + change[k] for k in values}, E + delta, change


def transport_shares(tags, values, E):
    """psi_k: partition shares renormalized over the partition, overlays keep their own share."""
    phi = {t["name"]: share(values[t["name"]], E) for t in tags}
    total = sum(phi[t["name"]] for t in tags if t["partition"])
    psi = {}
    for t in tags:
        if t["partition"]:
            norm = np.zeros_like(total)
            np.divide(phi[t["name"]], total, out=norm, where=total > 0)
            psi[t["name"]] = norm
        else:
            psi[t["name"]] = phi[t["name"]]
    return psi


def initial(case, c):
    rho, dz = _f(case["rho_kg_m3"]), _f(case["dz_m"])
    rho_e = rho * _f(case["e_tot_J_kg"])
    E = rho_e + c * rho
    values = {}
    fractions = case.get("initial_overlay_fraction", {})
    for t in case["tags"]:
        if not t["sources"]:
            values[t["name"]] = _f(t["mask"]) * E
        else:
            values[t["name"]] = _f(fractions.get(t["name"], 0.0)) * E
    return rho, dz, rho_e, E, values


def _state(case, times, rows, dz, diagnostics=None):
    values = {k: np.array(v, dtype=np.float64) for k, v in rows.items()}
    if any(not np.isfinite(v).all() for v in values.values()):
        raise ValueError("nonfinite independent reference")
    return EnergyState(_f(times), _f(dz), values, diagnostics or {})


def _rows(rows, suffix, rho, rho_e, E, values, extra=None):
    for name, v in (("rho", rho), ("rho_e", rho_e), ("E_c", E), *(("tag_" + k, values[k]) for k in values),
                    *((extra or {}).items())):
        rows.setdefault(name + suffix, []).append(np.array(v, dtype=np.float64))


# Closed forms -------------------------------------------------------------

def analytic(design, case):
    """The closed-form solution of each case at the design's times."""
    kind = case["kind"]
    times = _f(design["times_seconds"])
    rows = {}
    if kind == "radiation_record":
        return _radiation_continuum(design, case)
    if kind == "admissibility":
        return classify(case)
    for suffix, c in zip(suffixes(case), conventions(case)):
        rho0, dz, rho_e0, E0, a0 = initial(case, c)
        for t in times:
            extra = {}
            rho = rho0
            if kind == "heating_labels":
                S = {p: _f(s) for p, s in case["processes"].items()}
                E = E0 + sum(S.values()) * t
                values = {tag["name"]: (_f(tag["mask"]) * E if not tag["sources"] else
                                        sum(S[p] for p in tag["sources"]) * t) for tag in case["tags"]}
                extra = {"prc_" + p: s * t for p, s in S.items()}
            elif kind == "donor_cooling":
                E = E0 * np.exp(-case["cooling_rate_per_s"] * t)
                values = {k: v * np.exp(-case["cooling_rate_per_s"] * t) for k, v in a0.items()}
                extra = {"prc_" + case["cooling_process"]: E - E0}
            elif kind == "reservoir_exchange":
                up, down = case["rate_up_per_s"], case["rate_down_per_s"]
                decay = np.exp(-(up + down) * t)

                def evolve(x):
                    amount = x * dz
                    total = amount.sum()
                    first = total * down / (up + down) + (amount[0] - total * down / (up + down)) * decay
                    return np.array([first, total - first]) / dz
                E = evolve(E0)
                values = {k: evolve(v) for k, v in a0.items()}
            elif kind == "falling_mass_boundary":
                flux_m = case["mass_flux_kg_m2_s"]
                flux_c = (case["falling_specific_energy_J_kg"] + c) * flux_m
                top = np.array([0.0, 1.0])
                rho = rho0 + top * flux_m * t / dz
                E = E0 + top * flux_c * t / dz
                psi = {k: v[0] / E0[0] for k, v in a0.items()}
                values = {k: v + top * psi[k] * flux_c * t / dz for k, v in a0.items()}
                extra = {"rho_q": _f(case["rho_q_kg_m3"]) + top * flux_m * t / dz +
                         _f(case["water_only_forcing_kg_m3_s"]) * t}
            elif kind == "opposing_net_zero":
                Q = _f(case["heating_W_m3"])
                E = E0
                values = {tag["name"]: (_f(tag["mask"]) * E0 if not tag["sources"] else
                                        (E0 * -np.expm1(-Q * t / E0) if "heat" in tag["sources"] else 0.0 * E0))
                          for tag in case["tags"]}
                extra = {"prc_heat": Q * t, "prc_cool": -Q * t}
            elif kind == "offset_change":
                m, s = _f(case["mass_source_kg_m3_s"]), _f(case["energy_source_J_m3_s"])
                delta = s + c * m
                require(np.all(delta < 0) or np.all(delta > 0), "the offset case needs one sign per convention")
                rho = rho0 + m * t
                # The parent is written from its own tendencies, never from E_c,
                # so it is the same bits at every c.
                extra = {"rho_e": rho_e0 + s * t}
                E = E0 + delta * t
                if np.all(delta < 0):
                    values = {k: v * E / E0 for k, v in a0.items()}
                else:
                    values = {tag["name"]: (_f(tag["mask"]) * E if not tag["sources"] else delta * t)
                              for tag in case["tags"]}
            else:
                raise ValueError("unsupported frozen case")
            parent_e = extra.pop("rho_e", E - c * rho)
            _rows(rows, suffix, rho, parent_e, E, values, extra)
    return _state(case, times, rows, case["dz_m"], {"method": "closed form"})


def theta_x(design, case, start, end, index=0):
    """OD4's exact discrete scale on [start, end], in closed form for these cases.

    Every tag's source-ledger increment keeps one sign in every step here, so
    the sum of absolute increments equals the absolute total. Cases without a
    source have Theta_x = 0, and a percentage of it is not assessable.
    """
    dz = _f(case["dz_m"])
    span = end - start
    kind = case["kind"]
    if kind == "heating_labels":
        return float(np.sum(dz * sum(_f(s) for s in case["processes"].values())) * span)
    if kind == "donor_cooling":
        _, _, _, E0, _ = initial(case, conventions(case)[0])
        lam = case["cooling_rate_per_s"]
        return float(np.sum(dz * E0 * (np.exp(-lam * start) - np.exp(-lam * end))))
    if kind == "offset_change":
        c = conventions(case)[index]
        delta = _f(case["energy_source_J_m3_s"]) + c * _f(case["mass_source_kg_m3_s"])
        return float(np.sum(dz * np.abs(delta)) * span)
    return 0.0


# Separate step allocators -------------------------------------------------

def numerical(design, case, dt, dtype=np.float64, donor="declared"):
    """Step every applied-update event with the independent allocator.

    `donor` other than "declared" builds a registered wrong-origin mutant.
    Every step runs, and the endpoints must be exact steps.
    """
    kind = case["kind"]
    require(dt in case["dt_seconds"], "the time step is outside the frozen ladder")
    times = design["times_seconds"]
    require(all(t % dt == 0 for t in times) and times[0] == 0, "every endpoint must be an exact step")
    if kind == "radiation_record":
        return stage_record(design, case, dt)
    require(kind != "admissibility", "the classifier case has no time steps")
    rows, diagnostics = {}, {"dt_seconds": dt, "dtype": np.dtype(dtype).name, "donor": donor}
    for suffix, c in zip(suffixes(case), conventions(case)):
        rho, dz, rho_e, E, values = (np.asarray(x, dtype=dtype) if not isinstance(x, dict) else
                                     {k: np.asarray(v, dtype=dtype) for k, v in x.items()}
                                     for x in initial(case, c))
        c = dtype(c)
        tags = case["tags"]
        partition = [t["name"] for t in tags if t["partition"]]
        records = {}
        theta, activity, executed = 0.0, 0.0, 0
        extra = {}
        if kind == "falling_mass_boundary":
            extra = {"rho_q": np.asarray(case["rho_q_kg_m3"], dtype=dtype)}
        _rows(rows, suffix, rho, rho_e, E, values, {**{"prc_" + p: np.zeros_like(E) for p in _processes(case)}, **extra})
        for step in range(1, int(times[-1] / dt) + 1):
            t0 = (step - 1) * dt
            ledger = {k: np.zeros_like(E) for k in partition}
            events = []
            if kind == "heating_labels":
                events = [(p, np.asarray(s, dtype=dtype) * dtype(dt), 0.0) for p, s in case["processes"].items()]
            elif kind == "donor_cooling":
                lam = case["cooling_rate_per_s"]
                E0 = np.asarray(initial(case, float(c))[3], dtype=dtype)
                target = E0 * np.exp(-lam * (t0 + dt))
                events = [(case["cooling_process"], target - E, 0.0)]
            elif kind == "opposing_net_zero":
                Q = np.asarray(case["heating_W_m3"], dtype=dtype) * dtype(dt)
                if donor == "collapse":
                    events = [("net", Q - Q, 0.0)]
                else:
                    events = [("heat", Q, 0.0), ("cool", -Q, 0.0)]
            elif kind == "offset_change":
                m = np.asarray(case["mass_source_kg_m3_s"], dtype=dtype) * dtype(dt)
                s = np.asarray(case["energy_source_J_m3_s"], dtype=dtype) * dtype(dt)
                events = [(case["source_process"], s, m)]
            for process, energy, mass in events:
                # delta_p = delta_p^rho e + c delta_p^rho (section 2.1). Mass is not water.
                delta = energy + c * mass
                values, E, change = apply_event(tags, values, E, delta, process)
                rho = rho + mass
                rho_e = rho_e + energy
                records["prc_" + process] = records.get("prc_" + process, 0.0) + energy
                activity += float(np.sum(dz * np.abs(delta)))
                for k in partition:
                    ledger[k] = ledger[k] + change[k]
            if kind == "reservoir_exchange":
                # Energy moves without mass, so rho e_tot changes by the E_c change.
                old = E
                values, E = _exchange_step(case, tags, values, E, dz, dt, donor)
                rho_e = rho_e + (E - old)
            if kind == "falling_mass_boundary":
                values, E, rho, rho_e, extra = _boundary_step(case, tags, values, E, rho, rho_e, extra, dz, dt, c, donor)
            theta += sum(float(np.sum(dz * np.abs(ledger[k]))) for k in partition)
            executed += 1
            if step * dt in times[1:]:
                _rows(rows, suffix, rho, rho_e, E, values,
                      {**{"prc_" + p: records.get("prc_" + p, np.zeros_like(E)) for p in _processes(case)}, **extra})
        diagnostics["executed_steps" + suffix] = executed
        diagnostics["theta_x_whole_run" + suffix] = theta
        diagnostics["application_activity_whole_run" + suffix] = activity
    return _state(case, times, rows, case["dz_m"], diagnostics)


def _processes(case):
    kind = case["kind"]
    if kind == "heating_labels":
        return list(case["processes"])
    if kind == "donor_cooling":
        return [case["cooling_process"]]
    if kind == "opposing_net_zero":
        return ["heat", "cool"]
    return []


def _exchange_step(case, tags, values, E, dz, dt, donor):
    """Two gross face flows, each carrying its donor's transport shares."""
    up = case["rate_up_per_s"] * E[0] * dz[0] * dt
    down = case["rate_down_per_s"] * E[1] * dz[1] * dt
    psi = transport_shares(tags, values, E)
    # The registered wrong donor takes each flow's labels from its receiver.
    src_up, src_down = (0, 1) if donor == "declared" else (1, 0)
    new = {}
    for k, v in values.items():
        moved_up, moved_down = up * psi[k][src_up], down * psi[k][src_down]
        new[k] = v + np.array([moved_down - moved_up, moved_up - moved_down]) / dz
    return new, E + np.array([down - up, up - down]) / dz


def _boundary_step(case, tags, values, E, rho, rho_e, extra, dz, dt, c, donor):
    """Falling mass with F_c = F_E + c F_M. The donor follows the sign of F_c."""
    flux_m = case["mass_flux_kg_m2_s"] * dt
    flux_e = case["falling_specific_energy_J_kg"] * flux_m
    flux_c = flux_e + c * flux_m
    psi = transport_shares(tags, values, E)
    # Upward F_c at the inner face: the lower cell donates. The water donor
    # (the mutant) is the upper cell, where the mass falls from.
    inner = 0 if (flux_c > 0) == (donor == "declared") else 1
    new = {}
    for k, v in values.items():
        surface = flux_c * psi[k][0]  # the bottom cell is the declared surface donor
        through = flux_c * psi[k][inner]
        new[k] = v + np.array([surface - through, through]) / dz
    top = np.array([0.0, 1.0])
    rho_q = extra["rho_q"] + top * flux_m / dz + np.asarray(case["water_only_forcing_kg_m3_s"]) * dt
    return (new, E + top * flux_c / dz, rho + top * flux_m / dz, rho_e + top * flux_e / dz,
            {"rho_q": rho_q})


# The radiation record ----------------------------------------------------

def _faces(case):
    return np.concatenate(([0.0], np.cumsum(_f(case["dz_m"]))))


def _flux(case, z, t):
    H = _faces(case)[-1]
    profile = case["flux_surface_W_m2"] + case["flux_gain_W_m2"] * (z / H) ** 2
    omega = 2.0 * np.pi / case["period_seconds"]
    return profile * (1.0 + case["flux_modulation"] * np.sin(omega * t))


def _density(case, t):
    omega = 2.0 * np.pi / case["period_seconds"]
    return _f(case["rho0_kg_m3"]) * (1.0 + case["density_amplitude"] * np.sin(omega * t))


def _record_rows(case, times, records):
    rho = np.array([_density(case, t) for t in times])
    P = np.array(records)
    return {"rho": rho, "prc_radiation": P, "e_prc_radiation": P / rho}


def _radiation_continuum(design, case):
    times = _f(design["times_seconds"])
    z = _faces(case)
    H = z[-1]
    omega = 2.0 * np.pi / case["period_seconds"]
    profile = case["flux_surface_W_m2"] + case["flux_gain_W_m2"] * (z / H) ** 2
    divergence = -np.diff(profile) / _f(case["dz_m"])
    records = [divergence * (t + case["flux_modulation"] * (1.0 - np.cos(omega * t)) / omega) for t in times]
    return _state(case, times, _record_rows(case, times, records), case["dz_m"], {"method": "closed form"})


def stage_record(design, case, dt, weights=None, sign=1.0):
    """The record a stepper accumulates: dt sum_s b_s (-D_z F) at each stage, cell by cell."""
    tableau = case["stage_tableau"]
    b = _f(tableau["b"] if weights is None else weights)
    times = design["times_seconds"]
    z, dz = _faces(case), _f(case["dz_m"])
    P = np.zeros(len(dz))
    records = [P.copy()]
    for step in range(1, int(times[-1] / dt) + 1):
        t0 = (step - 1) * dt
        for c_s, b_s in zip(tableau["c"], b):
            F = _flux(case, z, t0 + c_s * dt)
            P = P + sign * dt * b_s * (-(F[1:] - F[:-1]) / dz)
        if step * dt in times[1:]:
            records.append(P.copy())
    return _state(case, _f(times), _record_rows(case, times, records), dz,
                  {"method": "stage-weighted cell divergence", "dt_seconds": dt})


def stage_reference(design, case, dt):
    """The independent route: integrate each face flux over the accepted stages, then differentiate.

    The boundary integral sum(dz P) = -(G_top - G_surface) is returned beside it.
    """
    tableau = case["stage_tableau"]
    times = design["times_seconds"]
    z, dz = _faces(case), _f(case["dz_m"])
    G = np.zeros(len(z))
    face_integrals = [G.copy()]
    for step in range(1, int(times[-1] / dt) + 1):
        stages = np.array([(step - 1) * dt + c_s * dt for c_s in tableau["c"]])
        G = G + dt * np.tensordot(_f(tableau["b"]), np.array([_flux(case, z, t) for t in stages]), axes=1)
        if step * dt in times[1:]:
            face_integrals.append(G.copy())
    records = [-np.diff(g) / dz for g in face_integrals]
    state = _state(case, _f(times), _record_rows(case, times, records), dz,
                   {"method": "face time integrals, then divergence", "dt_seconds": dt})
    state.diagnostics["boundary_integral_J_m2"] = [float(-(g[-1] - g[0])) for g in face_integrals]
    return state


def window_amount(state, i, j, method="density_conversion"):
    """Delta P over a window from the specific output (section 2.4).

    `specific_difference`, rho(t1) [e(t1) - e(t0)], is the wrong reading the
    record case must reject while the density changes.
    """
    rho, e = state.values["rho"], state.values["e_prc_radiation"]
    if method == "density_conversion":
        return rho[j] * e[j] - rho[i] * e[i]
    if method == "specific_difference":
        return rho[j] * (e[j] - e[i])
    raise ValueError("unknown window reading")


# The classifier case ------------------------------------------------------

def classify(case, epsilon_denominator=False, burden_for_regions=False, duplicate_restart=False):
    """Independent admissibility, normalization and accounting classification.

    The keyword arguments build the wrong implementations the case must catch.
    """
    c = conventions(case)[0]
    rho, rho_e, dz = _f(case["rho_kg_m3"]), _f(case["rho_e_J_m3"]), _f(case["dz_m"])
    E = rho_e + c * rho
    status = np.where(E > 0, STATUS_CODES["positive_parent"],
                      np.where(E == 0, STATUS_CODES["zero_parent"], STATUS_CODES["negative_parent"]))
    values = {"E_c": E[None, :], "status": status[None, :].astype(np.float64), "rho": rho[None, :]}
    inventory = {}
    partition = case["partition"]
    tags = case["tag_values_J_m3"]
    total = sum(float(np.sum(dz * _f(tags[k]))) for k in partition)
    for name, a in tags.items():
        a = _f(a)
        phi = a / (E + case["epsilon"]) if epsilon_denominator else share(a, E)
        values["share_" + name] = phi[None, :]
        signed, burden = float(np.sum(dz * a)), float(np.sum(dz * np.abs(a)))
        region = name in partition
        basis = burden if (burden_for_regions or not region) else signed
        inventory[name] = {
            "signed_inventory": signed, "absolute_burden": burden,
            "negative_cells": int(np.sum((a < 0) & (E > 0))), "clamped_high_cells": int(np.sum((a > E) & (E > 0))),
            "undefined_origin_cells": int(np.sum((E <= 0) & (a != 0))),
            "positive_inventory_precondition": bool(basis > 0),
            "share_of_partition": signed / total, "small": bool(signed / total < SMALL_SHARE)}
    corrections = _f(case["corrections_J_m3"])
    retained = np.cumsum(corrections.sum(axis=1))
    segments = case["restart_gross"]
    first, second = segments["segment_1"], segments["segment_2"]
    require(second[0] == first[-1], "restored gross differs from the checkpoint")
    stitched = first + second[1:]
    gross = (first[-1] - first[0]) + second[-1] if duplicate_restart else stitched[-1] - stitched[0]
    diagnostics = {
        "method": "independent classifier",
        "inventory": inventory,
        "corrections": {"signed_change": float(retained[-1]),
                        "retained_variation": float(np.sum(np.abs(np.diff(np.concatenate(([0.0], retained)))))),
                        "application_activity": float(np.sum(np.abs(corrections)))},
        "restart": {"stitched": stitched, "gross": gross}}
    return EnergyState(_f([0.0]), dz, values, diagnostics)


# Registered wrong-origin mutants -------------------------------------------

def mutant(design, case, baseline, dt=None):
    """The case's registered wrong implementation, built from the baseline answer."""
    kind = case["mutant"]["kind"]
    dt = dt or min(case.get("dt_seconds") or [None])
    values = {k: v.copy() for k, v in baseline.values.items()}
    if kind == "swap_source_overlays":
        values["tag_src_a"][1:], values["tag_src_b"][1:] = (baseline.values["tag_src_b"][1:].copy(),
                                                            baseline.values["tag_src_a"][1:].copy())
    elif kind == "charge_cooling_tag_alone":
        lost = baseline.values["E_c"] - baseline.values["E_c"][0]
        values["tag_src_rad"] = baseline.values["tag_src_rad"][0] + lost
        values["tag_src_sfc"] = np.repeat(baseline.values["tag_src_sfc"][:1], len(baseline.time), axis=0)
    elif kind in ("receiver_donor", "water_donor"):
        # The wrong donor's composition, laid on the exact parent. Partition
        # shares are normalized over the partition, so the partition closes.
        wrong = numerical(design, case, dt, donor=kind.split("_")[0])
        partition = sum(wrong.values["tag_" + t["name"]] for t in case["tags"] if t["partition"])
        for t in case["tags"]:
            norm = partition if t["partition"] else wrong.values["E_c"]
            values["tag_" + t["name"]] = wrong.values["tag_" + t["name"]] / norm * baseline.values["E_c"]
    elif kind == "collapse_processes_first":
        wrong = numerical(design, case, dt, donor="collapse")
        values["tag_src_heat"] = wrong.values["tag_src_heat"]
    elif kind == "invariant_fractions":
        for t in case["tags"]:
            values["tag_" + t["name"] + "@1"] = (baseline.values["tag_" + t["name"] + "@0"] /
                                                 baseline.values["E_c@0"] * baseline.values["E_c@1"])
    elif kind == "epsilon_denominator":
        return classify(case, epsilon_denominator=True)
    elif kind == "wrong_sign":
        values["prc_radiation"] = -baseline.values["prc_radiation"]
        values["e_prc_radiation"] = -baseline.values["e_prc_radiation"]
    else:
        raise ValueError("unknown registered mutant")
    return EnergyState(baseline.time.copy(), baseline.dz.copy(), values, {"mutation": kind})


# The tool: checks of a candidate against a reference -----------------------

def _allowance(design, *arrays):
    scale = max(float(np.max(np.abs(a))) for a in arrays)
    return design["profile_rules"]["roundoff_multiplier"] * np.finfo(np.float64).eps * scale


def _match(design, a, b):
    return bool(np.max(np.abs(a - b)) <= _allowance(design, b))


def origin_row(candidate, reference, design, case, tag, j, suffix=""):
    """One per-tag origin row in the scorer's energy reading (score_acceptance.Scorer.profile)."""
    name, t = "tag_" + tag["name"] + suffix, float(reference.time[j])
    rho_a, rho_b = candidate.values["rho" + suffix][j], reference.values["rho" + suffix][j]
    row = {"tag": tag["name"] + suffix, "endpoint_seconds": t}
    if not np.array_equal(rho_a, rho_b):
        return {**row, "verdict": "NOT ASSESSABLE", "meets": None, "why": "same-parent density required"}
    a, b, dz = candidate.values[name][j], reference.values[name][j], reference.dz
    specific = a / rho_a - b / rho_b
    absolute = float(np.sum(np.abs(specific * rho_b) * dz))
    burden, inventory = float(np.sum(np.abs(b) * dz)), float(np.sum(b * dz))
    peak = float(np.max(np.abs(b / rho_b)))
    scale = sum(float(np.sum(reference.values["tag_" + p["name"] + suffix][j] * dz))
                for p in case["tags"] if p["partition"])
    require(scale > 0, "nonpositive reference partition")
    row.update(absolute_L1=absolute, L1=absolute / burden if burden > 0 else None,
               Linf=float(np.max(np.abs(specific))) / peak if peak > 0 else None, reference_share=inventory / scale)
    if inventory < 0 or np.any(b < 0):
        return {**row, "verdict": "NOT ASSESSABLE", "meets": None, "why": "signed reference holding"}
    if inventory / scale < SMALL_SHARE:
        index = int(suffix[1:]) if suffix else 0
        theta = theta_x(design, case, theta_x_start(case), t, index)
        if theta <= 0:
            return {**row, "verdict": "NOT ASSESSABLE", "meets": None, "why": "small tag with zero Theta_x"}
        fraction = {"absolute_L1": absolute / (SMALL * theta)}
    else:
        l1, linf = origin_limits(tag["kind"], t)
        fraction = {"L1": row["L1"] / l1, "Linf": row["Linf"] / linf}
    worst = max(fraction.values())
    return {**row, "fraction_of_tolerance": fraction, "worst_fraction": worst, "meets": worst <= 1.0,
            "verdict": "PASS" if worst <= 1.0 else "FAIL"}


def floor_rows(state, truth, design, case):
    """Origin rows of a numerical rung against the closed form on the closed form's parent.

    A stepped parent differs from the closed form by accumulated roundoff,
    which the rung's `parent_defect` reports. The tags are compared on the
    closed form's density so that the rows stay assessable.
    """
    values = dict(state.values)
    for name in truth.values:
        if name.startswith("rho") and not name.startswith("rho_e"):
            values[name] = truth.values[name]
    rows = origin_rows(EnergyState(state.time, state.dz, values, state.diagnostics), truth, design, case)
    defect = max(float(np.max(np.abs(state.values[n] - truth.values[n]) / np.max(np.abs(truth.values[n]))))
                 for n in truth.values if n.split("@")[0] in ("rho", "rho_e", "E_c"))
    return rows, defect


def origin_rows(candidate, reference, design, case):
    return [origin_row(candidate, reference, design, case, tag, j, suffix)
            for suffix in suffixes(case) for j in range(1, len(reference.time)) for tag in case["tags"]]


def evaluate_candidate(design, case, candidate, reference):
    """Every check of the case. `meets` is True only when all pass.

    Named invariant checks stay separate, so a wrong-origin mutant can be
    shown to keep its parent and closure and still fail. An origin row that
    the scorer's reading cannot assess never counts as passing. Without a
    failed check, such a row makes `meets` None, which is NOT ASSESSABLE.
    """
    require(np.array_equal(candidate.time, reference.time) and np.array_equal(candidate.dz, reference.dz),
            "comparison needs the same times and native cells")
    checks, rows = {}, []
    kind = case["kind"]
    if kind == "radiation_record":
        checks["parent"] = _match(design, candidate.values["rho"], reference.values["rho"])
        checks["record"] = _match(design, candidate.values["prc_radiation"], reference.values["prc_radiation"])
        # The stage route shares the flux with the candidate. The closed-form
        # continuum does not, so its sign is scored in every cell (finder 2.2).
        continuum = _radiation_continuum(design, case).values["prc_radiation"]
        checks["record_sign"] = bool(np.all(np.sign(candidate.values["prc_radiation"][1:]) == np.sign(continuum[1:])))
        amounts = [(window_amount(candidate, 0, j), window_amount(reference, 0, j)) for j in range(1, len(reference.time))]
        checks["window_amounts"] = all(_match(design, a, b) for a, b in amounts)
        column = [float(np.sum(candidate.dz * candidate.values["prc_radiation"][j])) for j in range(len(reference.time))]
        boundary = reference.diagnostics.get("boundary_integral_J_m2")
        require(boundary is not None and len(boundary) == len(column), "reference lacks its boundary integral")
        checks["boundary_integral"] = all(abs(a - b) <= _allowance(design, np.array(boundary))
                                          for a, b in zip(column, boundary))
    elif kind == "admissibility":
        checks["inputs"] = _match(design, candidate.values["E_c"], reference.values["E_c"])
        checks["classification"] = all(np.array_equal(candidate.values[k], reference.values[k])
                                       for k in reference.values if k.startswith("share_") or k == "status")
        checks["inventory"] = candidate.diagnostics["inventory"] == reference.diagnostics["inventory"]
        checks["accounting"] = (candidate.diagnostics["corrections"] == reference.diagnostics["corrections"] and
                                candidate.diagnostics["restart"] == reference.diagnostics["restart"])
    else:
        for suffix, c in zip(suffixes(case), conventions(case)):
            parent = all(_match(design, candidate.values[n + suffix], reference.values[n + suffix])
                         for n in ("rho", "rho_e", "E_c"))
            checks["parent" + suffix] = parent
            partition = sum(candidate.values["tag_" + t["name"] + suffix] for t in case["tags"] if t["partition"])
            checks["partition_closure" + suffix] = _match(design, partition, candidate.values["E_c" + suffix])
            identity = candidate.values["rho_e" + suffix] + c * candidate.values["rho" + suffix]
            checks["convention_identity" + suffix] = _match(design, identity, candidate.values["E_c" + suffix])
            overlays = [t["name"] for t in case["tags"] if not t["partition"]]
            checks["overlay_sum" + suffix] = _match(design, sum(candidate.values["tag_" + k + suffix] for k in overlays),
                                                    sum(reference.values["tag_" + k + suffix] for k in overlays))
        records = [name for name in reference.values if name.startswith("prc_")]
        if records:
            checks["records"] = all(_match(design, candidate.values[n], reference.values[n]) for n in records)
        if kind == "offset_change":
            checks["parent_bitwise_parity"] = all(np.array_equal(candidate.values[n + "@0"], candidate.values[n + "@1"])
                                                  for n in ("rho", "rho_e"))
        # A tag with no gain path must read exactly zero. This fixture check
        # stands beside the scorer's NOT ASSESSABLE row and never replaces it.
        zero = [("tag_" + name + suffix) for name in no_gain_path_tags(case) for suffix in suffixes(case)]
        if zero:
            require(all(np.all(reference.values[n] == 0.0) for n in zero), "a no-gain-path tag has a nonzero reference")
            checks["no_gain_path_zero"] = all(bool(np.all(candidate.values[n] == 0.0)) for n in zero)
        rows = origin_rows(candidate, reference, design, case)
        assessed = [row for row in rows if row["meets"] is not None]
        checks["origins"] = all(row["meets"] is True for row in assessed)
    unassessed = [{"tag": row["tag"], "endpoint_seconds": row["endpoint_seconds"], "why": row["why"]}
                  for row in rows if row["meets"] is None]
    meets = False if not all(checks.values()) else (None if unassessed else True)
    return {"checks": checks, "origin_rows": rows, "not_assessable_rows": unassessed, "meets": meets}


def activity_report(design, case, state, start, end):
    """Application activity, Theta_x and Theta_i on one window, kept apart (section 4.2).

    Theta_i is the interim record estimate with end density, on the window's
    two endpoints and every `prc_` field. od4_restate sums every output
    interval of its source list. The two agree here because these records
    are monotone. It omits c Delta rho. None of the three bounds another.
    """
    i, j = (int(np.flatnonzero(state.time == t)[0]) for t in (start, end))
    dz = state.dz
    theta_i = 0.0
    for name in state.values:
        if name.startswith("prc_"):
            e = state.values[name] / state.values["rho"]
            theta_i += float(np.sum(dz * state.values["rho"][j] * np.abs(e[j] - e[i])))
    activity = None
    if case["kind"] == "opposing_net_zero":
        activity = 2.0 * float(np.sum(dz * _f(case["heating_W_m3"]))) * (end - start)
    elif case["kind"] in ("heating_labels", "donor_cooling"):
        activity = theta_x(design, case, start, end)
    return {"application_activity": activity, "theta_x": theta_x(design, case, start, end), "theta_i": theta_i}
