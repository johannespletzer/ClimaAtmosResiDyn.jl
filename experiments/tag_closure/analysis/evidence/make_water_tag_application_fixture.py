"""Write a synthetic run directory in the water tag producer's format. Never runtime evidence.

    python3 make_water_tag_application_fixture.py NEW_DIRECTORY [--float32]

The format follows the writer of claude/part9-producer at 59216edef
(src/parameterized_tendencies/tagged_tracers/water_tag_applications.jl,
`_start_water_tag_applications!` and `finalize_water_tag_applications!`):
the receipt header keys, the step lines, the record ids, and the NetCDF
variables in Julia's dimension order. The values are random numbers, the
tableau is ClimaTimeSteppers' ARS222, the roster is the one the part 8
default case builds (TRMM 0M, tags pbl and free by region, evap by source,
increment transport, no precipitation parts). The model's diagnostics
(`rhoa`, `q_tag_led_fix_<tag>`, `q_tag_led_inc_<tag>`) and the checkpoints
(`day0.<s>.hdf5`, groups `fields/Y`) are made consistent with the records.
The manifest says `synthetic fixture` in julia_version and fixture.

The kept 60 s output of an earlier PR A commit (scratchpad p9/keep_out/step)
is not used: its roster is an object, not an id list, its step lines carry
`unattributed_calls`, and its header lacks the channels, unsupported,
producer and native_arrays keys.
"""

import argparse
import json
import math
from pathlib import Path

import numpy as np

COMMIT = "59216edef02a07d672d6aa4d113d4c7cb3822925"
DIFF = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
CONFIG = """job_id: "fixture"
water_tracers:
  - name: pbl
    region: {type: tanh_altitude, z_center: 1000.0, width: 200.0, above: false}
  - name: free
    region: {type: tanh_altitude, z_center: 1000.0, width: 200.0}
  - name: evap
    source: surface_flux
water_tag_transport: "increment"
water_tag_ledger_per_tag: true
water_tag_applications: true
ode_algo: "ARS222"
dt: 150secs
"""
TAGS = (("pbl", True), ("free", True), ("evap", False))
CELLS, STEPS, DT = 6, 4, 150.0
FLAGS = "fallback + 2 bound + 4 clamp + 8 zero_normalization"


def ars222_pin():
    g = 1 - math.sqrt(2) / 2
    d = 1 - 1 / (2 * g)
    return {"algorithm": "unconstrained_imex_ark", "package": "ClimaTimeSteppers", "version": "0.10.7",
            "tableau": "ARS222", "b_exp": [d, 1 - d, 0.0], "b_imp": [0.0, 1 - g, g],
            "implicit_diagonal": [0.0, g, g], "fsal": False}


def channels():
    out = []
    for tag, partition in TAGS:
        names = ["rescale", "empty"] + (["repair"] if partition else []) + ["inc", "negative"]
        for m in names:
            tendency = m in ("inc", "negative")
            out.append({"id": f"{m}.{tag}.total", "mechanism": m, "tag": tag, "compartment": "total",
                        "quantity": "water_tendency" if tendency else "water_increment",
                        "units": "kg m^-3 s^-1" if tendency else "kg m^-3",
                        "event_scale": "rho_q_tot" if tendency else ("partition_positive_part" if m == "repair"
                                                                      else "rho_q_tot_before"),
                        "status": "observed"})
    return out


def simulate(dtype, seed=7):
    """Records per step in the producer's order, and the ledgers at each edge."""
    rng = np.random.default_rng(seed)
    pin = ars222_pin()
    chans = channels()
    z = 30.0 + 60.0 * np.arange(CELLS)
    rho = np.stack([1.2 - z / 20000 + 1e-4 * n for n in range(STEPS + 1)])
    ledger = np.zeros((STEPS + 1, len(chans), CELLS))
    steps, records = [], []
    for n in range(STEPS):
        start, stop = n * DT, (n + 1) * DT
        sid = f"t{start!r}"
        trial = sid + ".trial"
        apps = []
        ledger[n + 1] = ledger[n]
        for c, ch in enumerate(chans):
            tendency = ch["quantity"] == "water_tendency"
            idle = ch["id"].startswith("empty.evap")
            slots = [] if idle else ([("implicit", 2), ("implicit", 3)] if tendency else [("final_map", 0)])
            entries = []
            for k, (role, stage) in enumerate(slots, start=1):
                v = (rng.standard_normal(CELLS) * (1e-9 if tendency else 1e-6)).astype(dtype)
                v[rng.integers(CELLS)] = 0
                flags = (rng.random(CELLS) < 0.2).astype(np.int8) * np.int8(rng.integers(1, 16))
                entries.append((k, role, stage, v, (np.abs(v) * 1e3 + 1e-3).astype(dtype), flags))
            if not entries:
                role, stage = ("implicit", 2) if tendency else ("final_map", 0)
                entries.append((0, role, stage, np.zeros(CELLS, dtype), np.zeros(CELLS, dtype),
                                np.zeros(CELLS, np.int8)))
            for k, role, stage, v, s, fl in entries:
                coef = 1.0 if role == "final_map" else (stop - start) * pin["b_imp"][stage - 1]
                rid = f"{sid}/{ch['id']}/{k}"
                rec = {"channel": ch["id"], "record_id": rid, "trial": trial, "application_id": f"a{k}",
                       "evaluation_id": f"e{k}", "disposition": "applied", "role": role, "coefficient": coef,
                       "coefficient_units": "s" if tendency else "1"}
                if role != "final_map":
                    rec["stage"] = stage
                apps.append(rec)
                records.append((rid, c, v, s, fl))
                ledger[n + 1, c] += coef * v.astype(np.float64)
        steps.append({"id": sid, "start_seconds": start, "end_seconds": stop, "accepted_trial": trial,
                      "trials": [{"id": trial, "decision": "accepted"}], "applications": apps,
                      "stage_observations": 4, "dropped_zero_applications": 0})
    return {"pin": pin, "channels": chans, "z": z, "rho": rho, "ledger": ledger, "steps": steps,
            "records": records}


def write_nc(path, variables, dims, attrs=None, groups=None):
    from netCDF4 import Dataset
    with Dataset(path, "w") as ds:
        for name, size in dims.items():
            ds.createDimension(name, size)
        for k, v in (attrs or {}).items():
            ds.setncattr(k, v)
        for name, (value, vdims, vattrs) in variables.items():
            if value.dtype.kind in "US":
                var = ds.createVariable(name, str, vdims)
                var[:] = value.astype(object)
            else:
                var = ds.createVariable(name, value.dtype, vdims)
                var[:] = value
            for k, a in (vattrs or {}).items():
                var.setncattr(k, a)


def write_run(root, sim, dtype, key_on=True, first_step=0, model_dirs=True):
    """One run directory. first_step > 0 writes the restarted segment from that step."""
    root = Path(root)
    root.mkdir(parents=True)
    precision = "Float32" if dtype == np.float32 else "Float64"
    (root / "fixture.yml").write_text(CONFIG.replace("true\node_algo", ("true" if key_on else "false") + "\node_algo")
                                      + f'FLOAT_TYPE: "{precision}"\n')
    (root / "manifest.json").write_text(json.dumps({"head_sha": COMMIT, "diff_sha256": DIFF,
                                                    "julia_version": "synthetic fixture", "fixture": True}) + "\n")
    edges = np.arange(first_step, STEPS + 1) * DT
    steps = sim["steps"][first_step:]
    if key_on:
        chans = sim["channels"]
        header = {"schema_version": 1, "semantics": "weighted_final_additive_updates", "kind": "runtime_capture",
                  "producer": "climaatmos.water_tag_applications", "model_commit": COMMIT, "model_dirty": False,
                  "model_diff_sha256": DIFF, "integrator_pin": sim["pin"], "precision": precision,
                  "segment_start_seconds": float(edges[0]), "ledger_start": "checkpoint" if first_step else "zero",
                  "native_arrays": "water_tag_applications.nc", "roster_key": "water_tag_application_roster",
                  "water_tag_application_roster": [c["id"] for c in chans],
                  "water_tag_application_channels": chans, "water_tag_application_unsupported": []}
        lines = [header] + steps
        (root / "water_tag_application_receipt.jsonl").write_text("".join(json.dumps(x) + "\n" for x in lines))
        ids = {a["record_id"] for s in steps for a in s["applications"]}
        recs = [r for r in sim["records"] if r[0] in ids]
        write_nc(root / "water_tag_applications.nc", {
            "weights": (np.full(CELLS, 60.0), ("cell",), None),
            "geometry": (sim["z"].reshape(1, -1), ("coord", "cell"), None),
            "coord_name": (np.asarray(["z"]), ("coord",), None),
            "channel_id": (np.asarray([c["id"] for c in chans]), ("channel",), None),
            "channel_quantity": (np.asarray([c["quantity"] for c in chans]), ("channel",), None),
            "channel_units": (np.asarray([c["units"] for c in chans]), ("channel",), None),
            "record_values": (np.stack([r[2] for r in recs]), ("record", "cell"), None),
            "record_event_scale": (np.stack([r[3] for r in recs]), ("record", "cell"), None),
            "record_flags": (np.stack([r[4] for r in recs]), ("record", "cell"), None),
            "record_channel": (np.asarray([r[1] + 1 for r in recs], dtype=np.int32), ("record",), None),
            "record_id": (np.asarray([r[0] for r in recs]), ("record",), None),
            "ledger": (sim["ledger"][first_step:], ("edge", "channel", "cell"), None),
            "ledger_time": (edges, ("edge",), None),
        }, {"cell": CELLS, "coord": 1, "channel": len(chans), "record": None, "edge": None},
            {"weight_units": "m", "precision": precision, "flags": FLAGS})
    if not model_dirs:
        return root
    diag = {"rhoa": (sim["rho"], "kg m^-3")}
    for prefix, mechs in (("q_tag_led_fix_", ("rescale", "empty", "repair")), ("q_tag_led_inc_", ("inc", "negative"))):
        for tag, _ in TAGS:
            cols = [i for i, c in enumerate(sim["channels"]) if c["tag"] == tag and c["mechanism"] in mechs]
            total = sim["ledger"][:, cols, :].sum(axis=1)
            diag[prefix + tag] = (total / sim["rho"], "kg kg^-1")
    for short, (values, units) in diag.items():
        variables = {"time": (edges, ("time",), {"units": "s"}), "z": (sim["z"], ("z",), {"units": "m"}),
                     short: (values[first_step:].astype(dtype), ("time", "z"), {"units": units})}
        if short == "rhoa":
            # The model writes column diagnostics with time last, as hus (z, time).
            variables["rhoa_time_last"] = (np.ascontiguousarray(values[first_step:].astype(dtype).T),
                                           ("z", "time"), {"units": units})
        write_nc(root / f"{short}_150s_inst.nc", variables, {"time": None, "z": CELLS})
    for n in range(first_step, STEPS + 1):
        if n == 0 or n % 2:
            continue
        state = {"c_rho": sim["rho"][n].astype(dtype), "c_rho_q_tot": (sim["rho"][n] * 1e-2).astype(dtype),
                 "f_u3": np.asarray([0.0, -0.0, 1e-3, -1e-3, 0.0, 2e-3, 0.0], dtype=dtype)}
        top = {}
        if key_on:
            top = {"tag_ledger.applications." + c["id"]: (sim["ledger"][n, i], ("cell",), None)
                   for i, c in enumerate(sim["channels"])}
        top["tag_ledger.attempted.q_tag_led_rescale"] = (sim["ledger"][n, 0] * 2, ("cell",), None)
        from netCDF4 import Dataset
        with Dataset(root / f"day0.{int(n * DT)}.hdf5", "w") as ds:
            ds.setncattr("time", str(n * DT))
            f = ds.createGroup("fields")
            f.createDimension("cell", CELLS)
            for k, (v, d, _) in top.items():
                var = f.createVariable(k, v.dtype, d)
                var[:] = v
            y = f.createGroup("Y")
            y.createDimension("cell", CELLS)
            y.createDimension("face", CELLS + 1)
            for k, v in state.items():
                var = y.createVariable(k, v.dtype, ("face",) if k.startswith("f_") else ("cell",))
                var[:] = v
    return root


def write_fixture(root, dtype=np.float64, restart_step=2):
    """A key-on run, its key-off twin and a restarted segment, under root."""
    root = Path(root)
    sim = simulate(dtype)
    return {"on": write_run(root / "on", sim, dtype),
            "off": write_run(root / "off", sim, dtype, key_on=False),
            "restarted": write_run(root / "restarted", sim, dtype, first_step=restart_step)}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory")
    parser.add_argument("--float32", action="store_true")
    args = parser.parse_args()
    print(write_fixture(args.directory, np.float32 if args.float32 else np.float64))


if __name__ == "__main__":
    main()
