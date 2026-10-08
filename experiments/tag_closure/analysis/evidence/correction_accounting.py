"""Native accounting of finalized, weighted application evidence.

This reader extends the submission manifest. It does not produce runtime
observations, assign integration weights from call counts, or store events in
a new database. A bounded producer must finalize a step receipt after trial
acceptance, and export native arrays before any signed aggregation.
"""

import json
from dataclasses import dataclass
from zipfile import BadZipFile

import numpy as np

from acceptance_data import (DataError, NotAssessable, aligned, density, finite,
                             integrate, require, same_bits, window)


COUNTERS = ("fallback", "bound", "clamp", "zero_normalization")
ROLES = {"final_map", "explicit", "implicit", "post_newton"}
QUANTITIES = {
    "water_increment": ("kg m^-3", "1"),
    "water_tendency": ("kg m^-3 s^-1", "s"),
    "energy_increment": ("J m^-3", "1"),
    "energy_tendency": ("J m^-3 s^-1", "s"),
    "precipitation_flux": ("kg m^-2 s^-1", "s"),
}

# No verified runtime producer is supplied by this offline implementation.
# Registration is an implementation change after actual source/lifecycle,
# parent-parity and all-channel restart validation, never a manifest setting.
VERIFIED_PRODUCERS = {}

# Numerical consistency constants. No contract sets them. Each is a reading of
# native rounding, not a scientific tolerance, and a test pins each one.
# ROUNDING_ULPS: each native addition may be off by this many eps of its scale.
# It is the factor tag_event uses.
ROUNDING_ULPS = 16
# LEDGER_EXTRA_OPERATIONS: beyond one rounding per application, a ledger step
# rounds at its two endpoint density reconstructions and at their difference.
LEDGER_EXTRA_OPERATIONS = 3
# TRANSFER_OPERATIONS: a directed pair's sum rounds once per leg.
TRANSFER_OPERATIONS = 2
# HALF_QUANTUM: round to nearest loses at most half the smallest subnormal at
# each specific-ledger endpoint.
HALF_QUANTUM = 0.5
# TAG_EVENT_THRESHOLD and TAG_EVENT_ULPS copy tag_event in tag_throughput.jl.
# An application is an event above max(1e-12, 16 eps) times its writer's scale.
TAG_EVENT_THRESHOLD = 1e-12
TAG_EVENT_ULPS = 16
EVENT_CONVENTION = ("native node per element per weighted application above "
                    "max(1e-12, 16 eps(native dtype)) times the absolute writer scale "
                    "exported as __event_scale. That scale differs by writer")

# A dedicated closing ledger for rain and snow parts is accepted only if the
# closure table sums it with the rescale's ledgers. This reader checks that
# once the closing channel exists on this base.
CLOSING_LEDGER_NOTE = ("a dedicated closing ledger (q_tag_led_close) counts only if the closure table "
                       "sums it with the rescale's ledgers. This reader checks that once the closing "
                       "channel exists on this base")


def text(value):
    """A nonempty string, the only accepted identifier type in the metadata."""
    return isinstance(value, str) and bool(value)


def read_json(bundle, path):
    try:
        value = json.loads(bundle.artifact(path).read_text())
        require(isinstance(value, dict), f"{path}: expected a JSON object")
        return value
    except (ValueError, OSError) as exc:
        raise DataError(f"invalid accounting metadata {path}: {exc}") from exc


def rounding_allowance(*arrays, operations=1, precision=None, quantization=None):
    """A numerical consistency allowance, never a scientific tolerance.

    Native Float32 ledgers round on each addition
    receipts may sum in Float64.
    Scales have one physical unit and one native-cell grouping. Native
    precision is supplied separately after density reconstruction. Never mix
    density, an unweighted tendency or a different cell into this allowance.
    Native underflow loss is supplied separately, in the same amount units.
    Exact zero scale receives zero allowance.
    """
    dtypes = precision or [a.dtype for a in arrays]
    epsilon = max(float(np.finfo(dtype).eps) for dtype in dtypes)
    scale = np.maximum.reduce([np.abs(a.astype(np.float64)) for a in arrays])
    relative = ROUNDING_ULPS * epsilon * np.maximum(1, operations) * scale
    if quantization is None:
        return relative
    return relative + np.where(scale > 0, quantization, 0)


def close(a, b, *scales, operations=1, precision=None, quantization=None):
    allowance = rounding_allowance(a, b, *scales, operations=operations, precision=precision,
                                  quantization=quantization)
    require(np.all(np.abs(a.astype(np.float64) - b.astype(np.float64)) <= allowance),
            "accepted contributions do not match native retained ledger")
    return allowance


def amount(values, weights):
    """A finite native amount. Overflow is a data failure, not a JSON crash."""
    with np.errstate(over="ignore", invalid="ignore"):
        total = np.sum(integrate(values, weights), dtype=np.float64)
    finite(total, "integrated application amount")
    return float(total)


def count_total(values):
    """Sum counters as Python integers, without unsigned-to-int64 overflow."""
    return sum(int(v) for v in values.flat)


@dataclass
class Receipt:
    metadata: dict
    bounds: np.ndarray
    records: dict


def read_receipt(bundle, path, channel_ids):
    """Validate finalized trial decisions and one final evaluation per application."""
    r = read_json(bundle, path)
    require(r.get("schema_version") == 1 and r.get("semantics") == "weighted_final_additive_updates",
            "missing final additive acceptance semantics")
    require(r.get("model_commit") == bundle.manifest.get("head_sha") and
            r.get("model_diff_sha256") == bundle.manifest.get("diff_sha256"),
            "application receipt model identity differs")
    require(r.get("kind") in ("synthetic", "runtime_capture"), "unknown receipt kind")
    pin = r.get("integrator_pin", {})
    require(isinstance(pin, dict) and pin.get("algorithm") == "unconstrained_imex_ark" and
            pin.get("package") == "ClimaTimeSteppers" and pin.get("version"),
            "missing supported timestepper lifecycle pin")
    coefficients = {}
    for name in ("b_exp", "b_imp", "implicit_diagonal"):
        raw = pin.get(name)
        require(isinstance(raw, list) and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in raw),
                "invalid accepted tableau pin")
        value = np.asarray(raw, dtype=np.float64)
        require(value.ndim == 1 and len(value) > 0 and np.isfinite(value).all(), "invalid accepted tableau pin")
        coefficients[name] = value
    require(len({len(v) for v in coefficients.values()}) == 1, "accepted tableau dimensions differ")
    steps = r.get("steps")
    require(isinstance(steps, list) and steps, "empty accepted-step receipt")
    require(len(set(channel_ids)) == len(channel_ids) and channel_ids, "empty/duplicate accounting channel roster")
    records = {c: [] for c in channel_ids}
    step_ids, trial_ids, record_ids = set(), set(), set()
    bounds = []
    for index, step in enumerate(steps):
        require(isinstance(step, dict), "invalid accepted step")
        sid = step.get("id")
        require(isinstance(sid, str) and sid and sid not in step_ids, "missing/duplicate accepted step ID")
        step_ids.add(sid)
        a, b = step.get("start_seconds"), step.get("end_seconds")
        require(isinstance(a, (int, float)) and isinstance(b, (int, float)) and
                np.isfinite([a, b]).all() and 0 <= a < b, "invalid accepted-step bounds")
        require(not bounds or bounds[-1][1] == a, "receipt step gap/overlap")
        bounds.append((a, b))
        trials = step.get("trials")
        require(isinstance(trials, list) and trials, "missing trial decisions")
        decisions = {}
        for trial in trials:
            require(isinstance(trial, dict), "invalid trial decision")
            tid, decision = trial.get("id"), trial.get("decision")
            require(isinstance(tid, str) and tid and tid not in trial_ids, "missing/duplicate trial ID")
            require(decision in ("accepted", "rejected"), "provisional/unknown trial decision")
            trial_ids.add(tid)
            decisions[tid] = decision
        require(sum(v == "accepted" for v in decisions.values()) == 1, "step must have one accepted trial")
        require(text(step.get("accepted_trial")) and step["accepted_trial"] in decisions and
                decisions[step["accepted_trial"]] == "accepted", "accepted trial identity differs")
        applications = step.get("applications")
        require(isinstance(applications, list), "missing application inventory")
        seen_applied, seen_evaluations, observed = set(), set(), set()
        for app in applications:
            require(isinstance(app, dict), "invalid application receipt")
            c, rid, tid = app.get("channel"), app.get("record_id"), app.get("trial")
            require(text(c) and c in records and text(rid) and rid not in record_ids,
                    "unknown channel or missing/duplicate application record")
            require(text(tid) and tid in decisions, "application has unknown trial")
            aid, eid = app.get("application_id"), app.get("evaluation_id")
            require(isinstance(aid, str) and aid and isinstance(eid, str) and eid,
                    "missing application/evaluation identity")
            ekey = (c, tid, aid, eid)
            require(ekey not in seen_evaluations, "duplicate application evaluation")
            seen_evaluations.add(ekey)
            disposition = app.get("disposition")
            require(disposition in ("applied", "rejected", "superseded"), "unfinalized application disposition")
            require((disposition == "rejected") == (decisions[tid] == "rejected"),
                    "application disposition disagrees with trial acceptance")
            coefficient = app.get("coefficient")
            require(isinstance(coefficient, (int, float)) and not isinstance(coefficient, bool) and
                    np.isfinite(coefficient), "missing/nonfinite final integration coefficient")
            require(app.get("coefficient_units") in ("1", "s"), "missing integration coefficient units")
            require(text(app.get("role")) and app["role"] in ROLES,
                    "nonadditive stage observation cannot be an accepted application")
            if disposition == "applied":
                akey = (c, tid, aid)
                require(akey not in seen_applied, "multiple Newton evaluations counted as accepted application")
                seen_applied.add(akey)
                observed.add(c)
                if app["role"] == "final_map":
                    require(coefficient == 1 and app["coefficient_units"] == "1", "final-map weight must be one")
                else:
                    stage = app.get("stage")
                    require(isinstance(stage, int) and not isinstance(stage, bool) and
                            1 <= stage <= len(coefficients["b_exp"]), "application lacks valid tableau stage")
                    if app["role"] in ("explicit", "implicit"):
                        require(app["coefficient_units"] == "s", "accepted tendency must use dt*b in seconds")
                        tableau = "b_exp" if app["role"] == "explicit" else "b_imp"
                        expected = (b - a) * coefficients[tableau][stage - 1]
                    else:
                        require(app["coefficient_units"] == "1", "post-Newton map needs b_imp/gamma weight")
                        gamma = coefficients["implicit_diagonal"][stage - 1]
                        require(gamma != 0, "post-Newton map has no implicit solve")
                        expected = coefficients["b_imp"][stage - 1] / gamma
                    require(coefficient == expected, "application weight disagrees with accepted tableau pin")
            attempted = app.get("attempted_coefficient")
            if attempted is not None:
                require(isinstance(attempted, (int, float)) and not isinstance(attempted, bool) and
                        np.isfinite(attempted), "invalid attempted-update coefficient")
            record_ids.add(rid)
            records[c].append({**app, "step_index": index})
        require(observed == set(channel_ids),
                "missing observed channel in accepted step. Explicit zero application required")
    return Receipt(r, np.asarray(bounds, dtype=np.float64), records)


@dataclass
class Applications:
    values: np.ndarray
    weighted: np.ndarray
    attempted: np.ndarray
    events: np.ndarray
    counters: dict
    applied: np.ndarray
    attempted_mask: np.ndarray
    records: list
    weights: np.ndarray
    geometry: np.ndarray
    weight_units: str


def read_applications(bundle, descriptor, records, native=None):
    """Read one channel before aggregating cells, signs or applications."""
    require(isinstance(descriptor, dict), "invalid application descriptor")
    quantity = descriptor.get("quantity")
    require(text(quantity) and quantity in QUANTITIES, "unknown application quantity")
    units, coefficient_units = QUANTITIES[quantity]
    require(descriptor.get("units") == units, "application units differ")
    path = bundle.artifact(descriptor.get("path"))
    prefix = descriptor.get("prefix")
    require(isinstance(prefix, str) and prefix, "missing native application prefix")
    try:
        with np.load(path, allow_pickle=False) as archive:
            values = archive[prefix + "__values"].copy()
            require(values.dtype in (np.dtype("float32"), np.dtype("float64")) and values.ndim == 2,
                    "application array must be native float32/float64 record x cell")
            expected_dtype = np.dtype("float32" if bundle.spec.get("precision") == "Float32" else "float64")
            require(values.dtype == expected_dtype, "application precision differs from submission")
            ids = archive[prefix + "__record_ids"]
            require(ids.dtype.kind in "US" and ids.tolist() == [r["record_id"] for r in records],
                    "application array record identity/order differs")
            for key, expected in (("quantity", quantity), ("units", units)):
                require(str(archive[prefix + "__" + key].item()) == expected, "embedded application convention differs")
            weights, geometry = archive["weights"].copy(), archive["geometry"].copy()
            weight_units = str(archive["weight_units"].item())
            require(weights.shape == (values.shape[1],) and geometry.shape[0] == values.shape[1],
                    "application native cells/weights/coordinates differ")
            finite(weights, "application weights")
            finite(geometry, "application geometry")
            require(np.all(weights > 0), "nonpositive application native weights")
            total = archive[prefix + "__event_scale"].copy()
            require(total.shape == values.shape and total.dtype == values.dtype, "event scale native shape/precision differs")
            counters = {}
            for name in COUNTERS:
                count = archive[prefix + "__" + name].copy()
                require(count.shape == values.shape and count.dtype.kind in "iu" and np.all(count >= 0),
                        "missing/invalid application counter: " + name)
                counters[name] = count
    except DataError:
        raise
    except (KeyError, ValueError, TypeError, OSError, EOFError, BadZipFile) as exc:
        raise DataError(f"invalid native application archive: {exc}") from exc
    finite(values, "application values")
    finite(total, "application event scale")
    require(len(values) == len(records), "application records/arrays truncated")
    require(all(r["coefficient_units"] == coefficient_units for r in records), "application coefficient dimension differs")
    if native is not None:
        require(same_bits(weights, native.weights) and same_bits(geometry, native.geometry) and
                weight_units == native.weight_units, "application and ledger native geometry differ")
    coefficients = np.asarray([r["coefficient"] for r in records], dtype=np.float64)
    attempted_coefficients = np.asarray([r.get("attempted_coefficient") or 0 for r in records], dtype=np.float64)
    weighted = values.astype(np.float64) * coefficients[:, None]
    attempted = values.astype(np.float64) * attempted_coefficients[:, None]
    finite(weighted, "weighted accepted contributions")
    finite(attempted, "attempted contributions")
    applied = np.asarray([r["disposition"] == "applied" for r in records])
    attempted_mask = np.asarray([r.get("attempted_coefficient") is not None for r in records])
    floor = max(TAG_EVENT_THRESHOLD, TAG_EVENT_ULPS * np.finfo(values.dtype).eps)
    events = np.abs(weighted) > floor * np.abs(total.astype(np.float64))
    return Applications(values, weighted, attempted, events, counters, applied,
                        attempted_mask, records, weights, geometry, weight_units)


def select_steps(receipt, start, end):
    edges = np.concatenate((receipt.bounds[:1, 0], receipt.bounds[:, 1]))
    i, j = window(edges, start, end)
    return i, j


def totals(apps, receipt, start, end):
    i, j = select_steps(receipt, start, end)
    steps = np.asarray([r["step_index"] for r in apps.records])
    inside = (steps >= i) & (steps < j)
    selected = inside & apps.applied
    attempted = inside & apps.attempted_mask
    values = apps.weighted[selected]
    result = {
        "signed": amount(values, apps.weights),
        "accepted_activity": amount(np.abs(values), apps.weights),
        "accepted_positive": amount(np.maximum(values, 0), apps.weights),
        "accepted_negative": amount(np.minimum(values, 0), apps.weights),
        "attempted_update_activity": amount(np.abs(apps.attempted[attempted]), apps.weights),
        "accepted_cell_application_events": int(np.count_nonzero(apps.events[selected])),
        "applied_records": int(np.count_nonzero(selected)),
        "discarded_evaluations": int(np.count_nonzero(inside & ~apps.applied)),
        "evaluation_only_records": int(np.count_nonzero(inside & ~apps.attempted_mask)),
        "accepted_counters": {k: count_total(v[selected]) for k, v in apps.counters.items()},
        "attempted_update_counters": {k: count_total(v[attempted]) for k, v in apps.counters.items()},
        "event_convention": EVENT_CONVENTION,
    }
    step_delta = np.zeros((j - i, apps.values.shape[1]), dtype=np.float64)
    for n in range(i, j):
        step_delta[n - i] = np.sum(apps.weighted[apps.applied & (steps == n)], axis=0, dtype=np.float64)
    finite(step_delta, "accepted step contribution sum")
    result["retained_activity_from_applications"] = amount(np.abs(step_delta), apps.weights)
    return result, step_delta


def channel_metrics(bundle, channel, receipt, start, end):
    require(text(channel.get("ledger")), "missing accounting ledger name")
    ledger = bundle.field("candidate", channel["ledger"])
    rho = bundle.field("candidate", "rho")
    aligned(ledger, rho, "accounting ledger density")
    family = bundle.spec.get("claim", {}).get("family")
    specific, dens = ("kg kg^-1", "kg m^-3") if family == "water" else ("J kg^-1", "J m^-3")
    require(ledger.sampling == "cumulative" and ledger.units == (specific if ledger.representation == "specific" else dens),
            "accounting ledger convention differs")
    ledger.validate("native accepted-step ledger", bundle.spec.get("accepted_step_seconds"))
    edges = np.concatenate((receipt.bounds[:1, 0], receipt.bounds[:, 1]))
    require(np.array_equal(ledger.time, edges), "receipt/ledger accepted-step coverage differs")
    apps = read_applications(bundle, channel.get("applications", {}), receipt.records[channel["id"]], ledger)
    require(channel["applications"]["quantity"].startswith("water_" if family == "water" else "energy_"),
            "application quantity family differs")
    result, step_delta = totals(apps, receipt, start, end)
    i, j = window(ledger.time, start, end)
    values = density(ledger, rho)
    native_delta = np.diff(values[i:j + 1], axis=0)
    edges_scale = np.maximum(np.abs(values[i:j]), np.abs(values[i + 1:j + 1]))
    step_indices = np.asarray([r["step_index"] for r in apps.records])
    # Native additions may lose a small stage between opposing larger stages.
    # Keep its rounding scale in this step and cell, before cancellation.
    step_activity = np.zeros_like(step_delta)
    quantization = np.zeros_like(step_delta)
    for n in range(i, j):
        contributions = apps.weighted[apps.applied & (step_indices == n)]
        step_activity[n - i] = np.sum(np.abs(contributions), axis=0, dtype=np.float64)
        # Below the native normal range, a weighted native contribution may
        # round to zero. Account for that actual local cast loss rather than
        # admitting an absolute floor for every density ledger and cell.
        subnormal = np.where(np.abs(contributions) < np.finfo(apps.values.dtype).tiny,
                             contributions, 0)
        loss = np.abs(subnormal - subnormal.astype(apps.values.dtype).astype(np.float64))
        quantization[n - i] = np.sum(loss, axis=0, dtype=np.float64)
    finite(step_activity, "accepted step absolute contribution sum")
    precision = (ledger.values.dtype, apps.values.dtype)
    if ledger.representation == "specific":
        # Division while exporting a specific ledger can underflow at either
        # endpoint. Convert each half-subnormal quantum back to density units
        # with its own density. Density-ledger exports have no such division.
        quantum = float(np.nextafter(ledger.values.dtype.type(0), ledger.values.dtype.type(1)))
        quantization += (quantum * rho.values[i:j].astype(np.float64) * HALF_QUANTUM +
                         quantum * rho.values[i + 1:j + 1].astype(np.float64) * HALF_QUANTUM)
        precision += (rho.values.dtype,)
    finite(quantization, "native underflow allowance")
    operations = (np.bincount(step_indices[apps.applied], minlength=len(receipt.bounds))[i:j] +
                  LEDGER_EXTRA_OPERATIONS)[:, None]
    allowance = close(step_delta, native_delta, edges_scale, step_activity, operations=operations,
                      precision=precision, quantization=quantization)
    signed = amount(values[j] - values[i], ledger.weights)
    retained = amount(np.abs(native_delta), ledger.weights)
    # Use the same channel/cell decomposition for all three amounts.
    integral_allowance = amount(allowance, ledger.weights)
    require(abs(signed) <= retained + integral_allowance and
            retained <= result["accepted_activity"] + integral_allowance,
            "same-decomposition |signed| <= retained <= accepted activity failed")
    result.update(signed=signed, retained_activity=retained,
                  consistency_allowance=integral_allowance,
                  grouping="one mechanism/tag/compartment. Absolute before applications and native cells",
                  mechanism=channel.get("mechanism"), tag=channel.get("tag"),
                  compartment=channel.get("compartment"))
    return result, apps


def production_gate(bundle, receipt, section, roster):
    """Require runtime validation evidence. Synthetic arithmetic cannot qualify it.

    The roster is the one the reader actually evaluated. Today the gate checks a
    submitted roster against submitted proof and reads inactive evidence by hash
    only. PART5.md lists what a registered producer needs beyond that.
    """
    if (receipt.metadata.get("kind") == "synthetic" or
            bundle.spec.get("resolved_settings", {}).get("fixture") is True or
            str(bundle.manifest.get("julia_version", "")).startswith("not-run")):
        return "synthetic application evidence validates arithmetic only. Production acceptance/rollback hooks remain unavailable"
    lifecycle = section.get("lifecycle_evidence")
    if not lifecycle:
        return "missing verified producer acceptance/rollback, parent parity and restart evidence"
    proof = read_json(bundle, lifecycle)
    require(text(proof.get("producer_id")) and isinstance(proof.get("checks", {}), dict),
            "runtime lifecycle validation lacks a producer ID or checks table")
    require(proof.get("kind") == "runtime_validation" and
            proof.get("model_commit") == bundle.manifest["head_sha"] and
            proof.get("model_diff_sha256") == bundle.manifest["diff_sha256"],
            "runtime lifecycle validation identity differs")
    supported = VERIFIED_PRODUCERS.get(proof.get("producer_id"))
    if supported is None:
        return "no verified runtime application producer is registered. Metadata/log declarations cannot establish acceptance semantics"
    require(proof.get("integrator_pin") == receipt.metadata.get("integrator_pin") and
            receipt.metadata["integrator_pin"]["version"] == supported["cts_version"],
            "runtime producer timestepper pin differs from verified implementation")
    source = proof.get("producer_source")
    bundle.artifact(source)
    require(bundle.spec["artifacts"][source] == supported["source_sha256"],
            "runtime producer source differs from verified implementation")
    required = ("accepted_weights", "trial_rollback", "newton_replacement", "complete_active_roster",
                "parent_bitwise_parity", "all_channel_checkpoint_restart")
    checks = proof.get("checks", {})
    for key in required:
        check = checks.get(key, {})
        require(isinstance(check, dict), "invalid runtime lifecycle check: " + key)
        if check.get("result") != "PASS":
            return "unverified production lifecycle check: " + key
        require(check.get("command") and check.get("environment") and check.get("log"),
                "runtime lifecycle result lacks command/environment/log: " + key)
        bundle.artifact(check["log"])
    require(proof.get("scope_roster") == list(roster),
            "runtime validation does not cover declared accounting scope")
    return ""


def transfer_metrics(bundle, pair, channels, receipt, start, end):
    """Keep only the current pair's application buffers while checking its legs."""
    require(isinstance(pair, dict) and text(pair.get("donor")) and text(pair.get("receiver")),
            "directed transfer needs a giving and a receiving channel ID")
    d, r = channels.get(pair["donor"]), channels.get(pair["receiver"])
    require(d is not None and r is not None, "directed transfer lacks one observed leg")
    donor = read_applications(bundle, d["applications"], receipt.records[d["id"]], bundle.field("candidate", d["ledger"]))
    receiver = read_applications(bundle, r["applications"], receipt.records[r["id"]], bundle.field("candidate", r["ledger"]))
    require(same_bits(donor.weights, receiver.weights) and same_bits(donor.geometry, receiver.geometry),
            "directed transfer leg geometry differs")
    key = lambda app: (app["step_index"], app["trial"], app["application_id"], app["evaluation_id"],
                       app["disposition"], app["role"], app.get("stage"), app["coefficient"], app["coefficient_units"])
    require([key(app) for app in donor.records] == [key(app) for app in receiver.records],
            "directed transfer legs have different applications")
    require(np.array_equal(donor.applied, receiver.applied), "directed leg acceptance differs")
    close(donor.weighted + receiver.weighted, np.zeros_like(donor.weighted),
          np.maximum(np.abs(donor.weighted), np.abs(receiver.weighted)), operations=TRANSFER_OPERATIONS,
          precision=(donor.values.dtype, receiver.values.dtype))
    result, _ = totals(donor, receipt, start, end)
    # The giving leg loses what moves forward, so the forward amount is minus its signed change.
    return {"id": pair.get("id"), "signed_forward_amount": -result["signed"],
            "absolute_transfer_amount": result["accepted_activity"],
            "summed_leg_activity": 2 * result["accepted_activity"],
            "donor": pair["donor"], "receiver": pair["receiver"]}


def evaluate_accounting(bundle, start, end):
    section = bundle.spec.get("correction_accounting")
    if section is None:
        raise NotAssessable("missing accepted application/leg accounting. Existing retained/attempted amounts cannot exclude cancellation")
    require(isinstance(section, dict) and section.get("schema_version") == 1, "invalid correction-accounting extension")
    required = section.get("required_channels")
    coverage = section.get("coverage")
    require(isinstance(required, list) and required and all(text(c) for c in required) and
            len(set(required)) == len(required), "empty/duplicate required accounting roster")
    require(isinstance(coverage, list) and all(isinstance(c, dict) for c in coverage), "invalid accounting coverage table")
    ids = [c.get("id") for c in coverage]
    require(all(text(i) for i in ids) and len(set(ids)) == len(ids) and set(ids) == set(required),
            "accounting coverage differs from required roster")
    transfers = section.get("directed_transfers", [])
    require(isinstance(transfers, list), "directed transfers must be a list")
    observed, unavailable, inactive = [], [], []
    for c in coverage:
        require(text(c.get("mechanism")) and text(c.get("tag")) and text(c.get("compartment")),
                "missing mechanism/tag/compartment identity")
        status = c.get("status")
        require(status in ("observed", "inactive", "unsupported", "missing"), "unknown accounting channel status")
        if status == "observed":
            observed.append(c)
        else:
            require(c.get("reason"), "absent/inactive channel needs a reason")
            if status == "inactive":
                require(c.get("evidence"), "inactive channel needs evidence, not inferred zero")
                bundle.artifact(c["evidence"])
                inactive.append(c)
            else:
                unavailable.append(c)
    metrics = {"coverage": coverage, "inactive_channels": [c["id"] for c in inactive],
               "unavailable_channels": [c["id"] for c in unavailable], "channels": {},
               "scientific_activity_tolerance": None, "physical_provenance_bound": None}
    limitation = ""
    if observed:
        receipt = read_receipt(bundle, section.get("receipt"), [c["id"] for c in observed])
        for channel in observed:
            result, _ = channel_metrics(bundle, channel, receipt, start, end)
            metrics["channels"][channel["id"]] = result
            del _
        channels = {c["id"]: c for c in observed}
        metrics["directed_transfers"] = [transfer_metrics(bundle, pair, channels, receipt, start, end)
                                         for pair in transfers]
        limitation = production_gate(bundle, receipt, section, required)
    else:
        limitation = "no observed accepted applications in declared accounting scope"
    if unavailable:
        limitation = "missing/unsupported accounting channels: " + ", ".join(c["id"] for c in unavailable) + (". " + limitation if limitation else "")
    metrics["observed_data_complete"] = not unavailable and bool(observed)
    metrics["production_complete"] = not limitation
    note = ""
    if bundle.spec.get("claim", {}).get("family") == "water":
        metrics["closing_ledger"] = CLOSING_LEDGER_NOTE
        note = ". Note: " + CLOSING_LEDGER_NOTE if limitation else "Note: " + CLOSING_LEDGER_NOTE
    return {"metrics": metrics, "meets": not limitation,
            "verdict": "NOT ASSESSABLE" if limitation else "PASS", "limitation": limitation + note,
            "normalization": "absolute application amounts. Approved retained ratios and OD4 remain separate"}


def application_activity(bundle, start, end):
    """The window's application activity, a reported row that never passes.

    Absolute application amounts have no scientific tolerance. A complete
    production scope is reported. An incomplete one stays not assessable.
    """
    result = evaluate_accounting(bundle, start, end)
    if result["verdict"] == "PASS":
        result["verdict"] = "REPORTED ONLY"
    return result


def paired_precipitation(bundle, start, end):
    """Integrate signed same-update parent/tag fluxes on a native control surface."""
    section = bundle.spec.get("precipitation_applications")
    require(isinstance(section, dict) and section.get("schema_version") == 1, "missing paired accepted-application precipitation")
    channels = section.get("channels")
    partition = [t["name"] for t in bundle.spec.get("tags", []) if t.get("partition")]
    required = ["parent"] + partition
    require(isinstance(channels, dict) and set(channels) == set(required) and
            all(isinstance(v, dict) for v in channels.values()), "paired precipitation partition roster incomplete")
    receipt = read_receipt(bundle, section.get("receipt"), required)
    require(all(channels[name].get("quantity") == "precipitation_flux" for name in required),
            "paired precipitation needs same-update surface flux rates")
    parent = read_applications(bundle, channels["parent"], receipt.records["parent"])
    geometry_kind = bundle.spec.get("geometry_kind")
    require((geometry_kind == "column" and parent.weight_units == "1" and
             parent.weights.shape == (1,) and np.array_equal(parent.weights, np.ones(1))) or
            (geometry_kind == "sphere" and parent.weight_units == "m^2"), "precipitation native control surface/area units differ")
    require(section.get("sign_convention") == "upward_positive", "precipitation must declare the native upward-positive convention")
    key = lambda r: (r["step_index"], r["trial"], r["application_id"], r["evaluation_id"],
                     r["disposition"], r["role"], r.get("stage"), r["coefficient"], r["coefficient_units"])
    i, j = select_steps(receipt, start, end)
    require(receipt.bounds[0, 0] == 0 and receipt.bounds[-1, 1] == bundle.spec.get("end_seconds"),
            "paired precipitation accepted-step coverage differs from claim")
    masks = (np.asarray([r["step_index"] for r in parent.records]) >= i) & \
        (np.asarray([r["step_index"] for r in parent.records]) < j) & parent.applied
    def surface_amounts(app):
        downward = -app.weighted[masks]
        return {
            "signed_downward_amount": amount(downward, app.weights),
            "positive_downward_amount": amount(np.maximum(downward, 0), app.weights),
            "negative_downward_amount": amount(np.minimum(downward, 0), app.weights),
        }
    quantities = {"parent": surface_amounts(parent)}
    defect = parent.weighted[masks].copy()
    for tag in partition:
        other = read_applications(bundle, channels[tag], receipt.records[tag])
        require([key(r) for r in parent.records] == [key(r) for r in other.records] and
                same_bits(parent.weights, other.weights) and same_bits(parent.geometry, other.geometry) and
                parent.weight_units == other.weight_units, "parent/tag precipitation update/surface/weights differ")
        quantities[tag] = surface_amounts(other)
        defect -= other.weighted[masks]
        del other
    limitation = production_gate(bundle, receipt, section, required)
    # The defect is parent minus the tags' sum, in the downward convention of the amounts.
    # WA-PRECIP keeps this row reported accounting. An unverified producer is a
    # stated limitation, so declaring this evidence never turns the reported row
    # into a not-assessable one. Malformed evidence is still a data failure.
    return {"metrics": {"paired_amounts": quantities,
                        "signed_downward_amount": quantities["parent"]["signed_downward_amount"],
                        "signed_defect": -amount(defect, parent.weights),
                        "absolute_application_defect": amount(np.abs(defect), parent.weights),
                        "interval_bounds_seconds": [start, end], "accepted_steps": j - i,
                        "source": "paired weighted accepted applications", "production_complete": not limitation},
            "units": "kg m^-2" if geometry_kind == "column" else "kg",
            "normalization": "native signed surface amount. No precipitation accuracy tolerance added",
            "limitation": ((limitation + ". ") if limitation else "") +
                          "paired accounting alone does not validate precipitation origins against "
                          "independent references for the giving pool"}


def validate_extensions(bundle):
    """Validate declared new evidence without mistaking unsupported hooks for zero."""
    if "correction_accounting" in bundle.spec:
        evaluate_accounting(bundle, 0, bundle.spec.get("end_seconds"))
    if "precipitation_applications" in bundle.spec:
        paired_precipitation(bundle, 0, bundle.spec.get("end_seconds"))
