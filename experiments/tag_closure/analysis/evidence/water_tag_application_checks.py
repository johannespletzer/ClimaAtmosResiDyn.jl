"""The six runtime checks of the water tag producer (part 9, design/PART9_PRODUCER.md).

    python3 water_tag_application_checks.py accepted_weights RUN [--ode-algo ARS222] [--roles final_map,implicit]
    python3 water_tag_application_checks.py trial_rollback RUN [--dt 150]
    python3 water_tag_application_checks.py newton_replacement RUN [--expect-post-newton]
    python3 water_tag_application_checks.py complete_active_roster RUN
    python3 water_tag_application_checks.py parent_bitwise_parity ON_RUN OFF_RUN
    python3 water_tag_application_checks.py restart CONTINUOUS_RUN RESTARTED_RUN

RUN is a run's output directory with the producer's receipt and NetCDF, its
merged config `*.yml`, its diagnostics and its checkpoints, or a directory
written by water_tag_applications_convert.py (its `source_run` then names the
run). Each command prints one line `CHECK <key>: PASS` or
`CHECK <key>: FAIL <reason>`, which the registry's check_log_pattern reads,
then INFO lines. Exit 0 on PASS, 1 on FAIL, 2 when an input is unreadable
(printed as FAIL too). The restart command reports the registry's key
`all_channel_checkpoint_restart`.
"""

import argparse
import json
import math
import re
import sys
import tempfile
from pathlib import Path

import numpy as np

from acceptance_data import Bundle, DataError
from compare_runs import parse_tag_block
from correction_accounting import LEDGER_EXTRA_OPERATIONS, ROUNDING_ULPS, channel_metrics, read_receipt
import water_tag_applications_convert as wc

CHECK_KEYS = {"accepted_weights": "accepted_weights", "trial_rollback": "trial_rollback",
              "newton_replacement": "newton_replacement", "complete_active_roster": "complete_active_roster",
              "parent_bitwise_parity": "parent_bitwise_parity", "restart": "all_channel_checkpoint_restart"}
# The registry's check_log_pattern (water_tag_application_registry.json) reads these lines.
LOG_PATTERN = r"^CHECK (?P<check>[a-z_]+): (?P<result>PASS|FAIL)\b"
# The model's own ledgers, per tag, and the mechanisms each one sums
# (test/water_tag_applications_common.jl, check_model_ledgers, at 59216edef).
MODEL_LEDGERS = (("q_tag_led_fix_", ("rescale", "empty", "repair", "close")),
                 ("q_tag_led_inc_", ("inc", "negative")))
# Proposed, 2026-10-10. A model ledger diagnostic is written as L/rho in the
# run's precision and multiplied back by rhoa here: two operations beyond the
# reader's LEDGER_EXTRA_OPERATIONS.
DIAGNOSTIC_OPERATIONS = 2
# Fields the producer adds to a checkpoint. Everything else is the parent's.
PRODUCER_CHECKPOINT_PREFIX = "tag_ledger.applications."


class CheckFailed(Exception):
    pass


def need(condition, message):
    if not condition:
        raise CheckFailed(message() if callable(message) else message)


def first_bad(run, bad):
    return run.steps[int(np.argwhere(bad)[0][0])]["id"]


# ---------------------------------------------------------------- inputs


def ars222():
    g = 1 - math.sqrt(2) / 2
    d = 1 - 1 / (2 * g)
    return {"b_exp": [d, 1 - d, 0.0], "b_imp": [0.0, 1 - g, g], "implicit_diagonal": [0.0, g, g]}


# ClimaTimeSteppers 1.0.1, the version the run tree pins (.buildkite/Manifest-v1.11.toml),
# solvers/imex_tableaus.jl, IMEXTableau(::ARS222):
# b = the last row of a, as IMEXTableau's defaults set it.
REFERENCE_TABLEAUS = {"ARS222": ars222}


class Run:
    """One run: its raw directory and its converted bundle."""

    def __init__(self, path, workdir):
        path = Path(path)
        if (path / wc.OUT_SECTION).is_file():
            self.converted = path
            self.raw = Path(json.loads((path / wc.OUT_SECTION).read_text())["source_run"])
        else:
            self.raw = path
            self.converted = Path(workdir) / (path.name + "_converted")
            manifest = path / "manifest.json"
            wc.convert(path, self.converted, manifest if manifest.is_file() else None)
        self.header, self.steps = wc.read_receipt_lines(self.raw)
        self.arrays = wc.read_arrays(self.raw)
        self.section = json.loads((self.converted / wc.OUT_SECTION).read_text())
        if not (self.converted / "manifest.json").is_file():
            wc.standalone_bundle(self.converted)
        self.bundle = Bundle(self.converted / "manifest.json")
        self.roster = self.header[wc.ROSTER_KEY]
        self.edges = wc.edges_of(self.steps)

    def receipt(self):
        return read_receipt(self.bundle, wc.OUT_RECEIPT, self.roster)

    def records(self):
        """Every record with its step index, values row and weighted Float64 values."""
        index = {rid: r for r, rid in enumerate(self.arrays["record_id"])}
        for n, step in enumerate(self.steps):
            for app in step["applications"]:
                v = self.arrays["record_values"][index[app["record_id"]]]
                yield n, app, v, app["coefficient"] * v.astype(np.float64)

    def config(self):
        ymls = sorted(self.raw.glob("*.yml"))
        need(len(ymls) == 1, f"{self.raw}: expected one merged config *.yml, found {len(ymls)}")
        return ymls[0].read_text()


def flat(text, key):
    m = re.search(rf"^{re.escape(key)}:\s*\"?([^\"\n#]*)\"?", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def expected_roster(config_text):
    """The channels water_tag_application_channels builds for this config, in its order."""
    tags = parse_tag_block(config_text, "water_tracers") or []
    need(tags, "the config names no water tags")
    precip = (flat(config_text, "water_tag_precipitation") or "false").lower() == "true"
    increment = (flat(config_text, "water_tag_transport") or "").strip() == "increment"
    n = "nonprecipitating" if precip else "total"
    roster = []
    for name, region, source in tags:
        # A tag without a source is a region tag, which partitions the parent.
        partition = not source
        roster += [f"rescale.{name}.{n}", f"empty.{name}.{n}"]
        if partition:
            roster += [f"repair.{name}.{c}" for c in ((n, "rain", "snow") if precip else (n,))]
        if precip:
            if partition:
                roster += [f"close.{name}.rain", f"close.{name}.snow"]
            roster += [f"follow.{name}.{c}" for c in (n, "rain", "snow")]
        # The increment follower and the negative giver meter every tag, source
        # tags included.
        if increment:
            roster += [f"inc.{name}.{n}", f"negative.{name}.{n}"]
    return roster, [t[0] for t in tags]


def allowance(dtype, operations, *scales):
    eps = float(np.finfo(dtype).eps)
    return ROUNDING_ULPS * eps * operations * np.maximum.reduce([np.abs(s) for s in scales])


# ---------------------------------------------------------------- checks


def accepted_weights(run, ode_algo="ARS222", roles=("final_map", "implicit")):
    run.receipt()
    pin = run.header["integrator_pin"]
    need(pin.get("tableau") == ode_algo, f"the pin's tableau is {pin.get('tableau')}, the config's {ode_algo}")
    need(ode_algo in REFERENCE_TABLEAUS, f"no reference tableau for {ode_algo}")
    reference = REFERENCE_TABLEAUS[ode_algo]()
    for name, value in reference.items():
        need(pin[name] == value, f"pin {name} {pin[name]} differs from {ode_algo}'s {value}")
    need(pin["b_exp"] != pin["b_imp"], "b_exp equals b_imp, so a swap of the two would pass unseen")
    quantities = {c["id"]: c["quantity"] for c in run.header[wc.CHANNELS_KEY]}
    seen = set()
    for n, app, v, w in run.records():
        a, b = run.steps[n]["start_seconds"], run.steps[n]["end_seconds"]
        role = app["role"]
        tendency = quantities[app["channel"]] == "water_tendency"
        need(tendency == (role in ("implicit", "explicit")), f"{app['record_id']}: role {role} for a "
             f"{quantities[app['channel']]} channel")
        if role == "final_map":
            expected = 1
        elif role == "post_newton":
            expected = pin["b_imp"][app["stage"] - 1] / pin["implicit_diagonal"][app["stage"] - 1]
        else:
            expected = (b - a) * pin["b_imp" if role == "implicit" else "b_exp"][app["stage"] - 1]
        need(app["coefficient"] == expected, f"{app['record_id']}: weight {app['coefficient']} is not {expected}")
        if np.any(v != 0):
            seen.add(role)
    missing = set(roles) - seen
    need(not missing, f"no nonzero applied record with role {', '.join(sorted(missing))}")
    return f"{sum(len(s['applications']) for s in run.steps)} records, roles {sorted(seen)}, pin = {ode_algo}"


def trial_rollback(run, dt=None):
    for step in run.steps:
        trials = step["trials"]
        need(len(trials) == 1 and trials[0]["decision"] == "accepted" and step["accepted_trial"] == trials[0]["id"],
             f"step {step['id']}: not one accepted trial")
        need(all(a["disposition"] == "applied" and a["trial"] == trials[0]["id"] for a in step["applications"]),
             f"step {step['id']}: an application outside the accepted trial")
    lengths = np.diff(run.edges)
    need(np.all(lengths == lengths[0]) and (dt is None or lengths[0] == dt),
         f"accepted steps are not all {dt if dt is not None else lengths[0]} s")
    ledger = run.arrays["ledger"]
    if run.header["ledger_start"] == "zero":
        need(np.all(ledger[0] == 0), "the ledger does not start at zero")
    for c, cid in enumerate(run.roster):
        delta = np.zeros((len(run.steps), ledger.shape[2]))
        activity = np.zeros_like(delta)
        count = np.zeros(len(run.steps))
        for n, app, _, w in run.records():
            if app["channel"] == cid:
                delta[n] += w
                activity[n] += np.abs(w)
                count[n] += 1
        L = ledger[:, c, :]
        bound = allowance(np.float64, (count + 1)[:, None], L[:-1], L[1:], activity)
        bad = np.abs(L[1:] - L[:-1] - delta) > bound
        need(not bad.any(), lambda: f"{cid}: the ledger moves without an applied record at step "
             f"{first_bad(run, bad)}")
    return f"{len(run.steps)} steps of {lengths[0]} s, one accepted trial each, ledgers = applied records"


def newton_replacement(run, expect_post_newton=False):
    run.receipt()
    pin = run.header["integrator_pin"]
    implicit_stages = {i + 1 for i, g in enumerate(pin["implicit_diagonal"]) if g != 0}
    seen, post = set(), 0
    for n, app, _, _ in run.records():
        if app["role"] in ("implicit", "post_newton"):
            key = (n, app["channel"], app["role"], app["stage"])
            need(key not in seen, f"{app['record_id']}: a second {app['role']} record of stage {app['stage']}")
            seen.add(key)
            need(app["stage"] in implicit_stages, f"{app['record_id']}: stage {app['stage']} has no implicit solve")
            post += app["role"] == "post_newton"
    need(not expect_post_newton or post > 0, "no post_newton record, though the run updates at stage cadence")
    tie = model_ledger_tie(run, mechanisms=("inc", "negative"))
    return f"{len(seen)} implicit or post_newton records, one per stage, {post} post_newton. {tie}"


def model_ledger_tie(run, mechanisms=None):
    """Applied records per tag against the step changes of the model's own ledgers."""
    _, tags = expected_roster(run.config())
    rho = wc.find_diagnostic(run.raw, "rhoa", run.edges)[1].astype(np.float64)
    checked = 0
    for name, mechs in MODEL_LEDGERS:
        mechs = [m for m in mechs if mechanisms is None or m in mechanisms]
        if not mechs:
            continue
        for tag in tags:
            _, q, _, _ = wc.find_diagnostic(run.raw, name + tag, run.edges)
            density = q.astype(np.float64) * rho
            delta = np.zeros((len(run.steps), q.shape[1]))
            activity = np.zeros_like(delta)
            count = np.zeros(len(run.steps))
            for n, app, _, w in run.records():
                m, t = app["channel"].split(".")[:2]
                if m in mechs and t == tag:
                    delta[n] += w
                    activity[n] += np.abs(w)
                    count[n] += 1
            ops = (count + LEDGER_EXTRA_OPERATIONS + DIAGNOSTIC_OPERATIONS)[:, None]
            bound = allowance(q.dtype, ops, density[:-1], density[1:], activity)
            bad = np.abs(np.diff(density, axis=0) - delta) > bound
            need(not bad.any(), lambda: f"records of {'+'.join(mechs)} for tag {tag} differ from the model's "
                 f"{name}{tag} at step {first_bad(run, bad)}")
            checked += 1
    return f"{checked} model ledgers tie to the records"


def complete_active_roster(run):
    expected, _ = expected_roster(run.config())
    need(run.roster == expected, f"roster {run.roster} differs from the config's {expected}")
    need(run.header[wc.UNSUPPORTED_KEY] == [], "the producer lists unsupported mechanisms")
    receipt = run.receipt()
    start, end = float(run.edges[0]), float(run.edges[-1])
    for channel in run.section["correction_accounting"]["coverage"]:
        try:
            channel_metrics(run.bundle, channel, receipt, start, end)
        except DataError as exc:
            raise CheckFailed(f"{channel['id']}: {exc}") from exc
    tie = model_ledger_tie(run)
    return f"{len(expected)} channels as the config builds them, each with a record every step, ledger tie PASS. {tie}"


def read_checkpoint(path):
    """Every variable of an HDF5 checkpoint as {path: array}, read through netCDF4."""
    from netCDF4 import Dataset
    out = {}

    def walk(group, prefix):
        group.set_auto_mask(False)
        for name, var in group.variables.items():
            out[prefix + name] = np.asarray(var[:])
        for name, sub in group.groups.items():
            walk(sub, prefix + name + "/")

    with Dataset(path) as ds:
        walk(ds, "")
        out["@time"] = np.asarray(float(ds.getncattr("time")))
    return out


def bitwise(a, b):
    return a.dtype == b.dtype and a.shape == b.shape and a.tobytes() == b.tobytes()


def compare(a, b, what, skip=lambda k: False):
    keys_a = {k for k in a if not skip(k)}
    keys_b = {k for k in b if not skip(k)}
    need(keys_a == keys_b, f"{what}: field sets differ, {sorted(keys_a ^ keys_b)[:5]}")
    for k in sorted(keys_a):
        need(bitwise(a[k], b[k]), f"{what}: {k} differs bitwise")
    return len(keys_a)


def diagnostics(raw):
    return {p.name: p for p in sorted(raw.glob("*.nc")) if p.name != wc.ARRAYS_FILE}


def read_nc(path):
    from netCDF4 import Dataset
    with Dataset(path) as ds:
        ds.set_auto_mask(False)
        return {k: np.asarray(v[:]) for k, v in ds.variables.items()}


def read_nc_dims(path):
    """Each variable with its dimension names, so the time axis is found by name."""
    from netCDF4 import Dataset
    with Dataset(path) as ds:
        ds.set_auto_mask(False)
        return {k: (np.asarray(v[:]), tuple(v.dimensions)) for k, v in ds.variables.items()}


def parent_bitwise_parity(on, off):
    need(not (off / wc.RECEIPT_FILE).exists(),
         f"{off} has a receipt, so the key was on")
    need((on / wc.RECEIPT_FILE).exists(), f"{on} has no receipt")
    cp_on, cp_off = sorted(on.glob("day*.hdf5")), sorted(off.glob("day*.hdf5"))
    need(cp_on and [p.name for p in cp_on] == [p.name for p in cp_off], "checkpoint sets differ or are empty")
    fields, dtypes = 0, set()
    for a, b in zip(cp_on, cp_off):
        A, B = read_checkpoint(a), read_checkpoint(b)
        need(any(k.startswith("fields/" + PRODUCER_CHECKPOINT_PREFIX) for k in A),
             f"{a.name}: the run with the key has no producer ledgers")
        fields += compare(A, B, a.name, skip=lambda k: k.startswith("fields/" + PRODUCER_CHECKPOINT_PREFIX))
        dtypes |= {str(v.dtype) for k, v in B.items() if k.startswith("fields/Y/")}
    d_on, d_off = diagnostics(on), diagnostics(off)
    need(d_on and set(d_on) == set(d_off), "diagnostic file sets differ or are empty")
    for name in d_on:
        fields += compare(read_nc(d_on[name]), read_nc(d_off[name]), name)
    return f"{len(cp_on)} checkpoints and {len(d_on)} diagnostic files, {fields} arrays bitwise, state dtypes {sorted(dtypes)}"


def restart(continuous, restarted):
    header_c, steps_c = wc.read_receipt_lines(continuous)
    header_r, steps_r = wc.read_receipt_lines(restarted)
    t0 = header_r["segment_start_seconds"]
    need(header_r["ledger_start"] == "checkpoint", f"the restarted ledgers start as {header_r['ledger_start']!r}")
    need(t0 > header_c["segment_start_seconds"], "the restarted segment does not start later")
    same = {k: v for k, v in header_c.items() if k not in ("segment_start_seconds", "ledger_start")}
    need(same == {k: v for k, v in header_r.items() if k not in ("segment_start_seconds", "ledger_start")},
         "receipt headers differ beyond the segment start")
    tail = [s for s in steps_c if s["start_seconds"] >= t0]
    need(tail and tail == steps_r, f"step lines after {t0} s differ ({len(tail)} against {len(steps_r)})")
    A, B = wc.read_arrays(continuous), wc.read_arrays(restarted)
    rows = {rid: r for r, rid in enumerate(A["record_id"])}
    need(all(r in rows for r in B["record_id"]), "the restarted run has records the continuous run lacks")
    sel = np.asarray([rows[r] for r in B["record_id"]], dtype=np.int64)
    for name in ("record_values", "record_event_scale", "record_flags", "record_channel"):
        need(bitwise(np.ascontiguousarray(A[name][sel]), np.ascontiguousarray(B[name])), f"{name} differs")
    edges = np.flatnonzero(A["ledger_time"] >= t0)
    need(np.array_equal(A["ledger_time"][edges], B["ledger_time"]), "ledger times differ")
    need(bitwise(np.ascontiguousarray(A["ledger"][edges]), np.ascontiguousarray(B["ledger"])),
         "the ledgers after the restart differ")
    cps = [p.name for p in sorted(restarted.glob("day*.hdf5"))
           if (continuous / p.name).exists() and read_checkpoint(p)["@time"] > t0]
    need(cps, "no common checkpoint after the restart")
    fields = 0
    for name in cps:
        fields += compare(read_checkpoint(continuous / name), read_checkpoint(restarted / name), name)
    dc, dr = diagnostics(continuous), diagnostics(restarted)
    need(dc and set(dc) == set(dr), "diagnostic file sets differ or are empty")
    for name in dc:
        a, b = read_nc_dims(dc[name]), read_nc_dims(dr[name])
        need(set(a) == set(b), f"{name}: variable sets differ, {sorted(set(a) ^ set(b))[:5]}")
        need("time" in a, f"{name}: no time coordinate")
        ta, tb = a["time"][0], b["time"][0]
        common = np.intersect1d(ta[ta > t0], tb)
        need(common.size, f"{name}: no common time after {t0} s")
        ia, ib = np.searchsorted(ta, common), np.searchsorted(tb, common)
        for k in sorted(a):
            (va, da), (vb, db) = a[k], b[k]
            need(da == db, f"{name}: {k} has dims {da} against {db}")
            if "time" in da:
                va, vb = np.take(va, ia, axis=da.index("time")), np.take(vb, ib, axis=db.index("time"))
            need(bitwise(np.ascontiguousarray(va), np.ascontiguousarray(vb)),
                 f"{name}: {k} after the restart differs")
            fields += 1
    return f"{len(steps_r)} step lines, {len(B['record_id'])} records, {len(edges)} ledger edges, {fields} arrays bitwise"


def run_check(command, paths, options):
    key = CHECK_KEYS[command]
    try:
        with tempfile.TemporaryDirectory() as work:
            if command == "parent_bitwise_parity":
                info = parent_bitwise_parity(Path(paths[0]), Path(paths[1]))
            elif command == "restart":
                info = restart(Path(paths[0]), Path(paths[1]))
            else:
                run = Run(paths[0], work)
                if command == "accepted_weights":
                    info = accepted_weights(run, options.ode_algo, tuple(options.roles.split(",")))
                elif command == "trial_rollback":
                    info = trial_rollback(run, options.dt)
                elif command == "newton_replacement":
                    info = newton_replacement(run, options.expect_post_newton)
                else:
                    info = complete_active_roster(run)
    except CheckFailed as exc:
        print(f"CHECK {key}: FAIL {exc}")
        return 1
    except (DataError, wc.ConversionError, OSError, KeyError, ValueError, IndexError) as exc:
        print(f"CHECK {key}: FAIL unreadable input: {type(exc).__name__}: {exc}")
        return 2
    print(f"CHECK {key}: PASS")
    print(f"INFO {key}: {info}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in CHECK_KEYS:
        p = sub.add_parser(name)
        p.add_argument("paths", nargs=2 if name in ("parent_bitwise_parity", "restart") else 1)
        if name == "accepted_weights":
            p.add_argument("--ode-algo", default="ARS222")
            p.add_argument("--roles", default="final_map,implicit")
        if name == "trial_rollback":
            p.add_argument("--dt", type=float)
        if name == "newton_replacement":
            p.add_argument("--expect-post-newton", action="store_true")
    args = parser.parse_args(argv)
    return run_check(args.command, args.paths, args)


if __name__ == "__main__":
    sys.exit(main())
