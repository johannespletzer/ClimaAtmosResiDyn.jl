"""G4.6: the D4 process budget (design/D4_PROCESS_BUDGET.md), scored as
pre-registered.

    python3 process_budget.py [OUTPUT_ROOT]

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. It reads the latest
`output_XXXX` of `g46_d4_budget`, `g46_d4_budget_2c` and `g46_d4_untagged`.
Every term is per unit area (J/m²): a field per unit mass times `rhoa` and the
layer's thickness, summed over the layers for the column.

Identity II, the residual, per layer and for the column:

    R(t) − R(0) = L_R(t) + I(t) − F_S(t) + X_II(t)

Identity I, the partitioned total, for the column:

    E(t) − E(0) = B(t) + P_e,precipitation(t) + c·M_U(t) + X_I(t)

with `c·M_U = c·ΔM − (B(2c) − B(c))` from the pair. The verdicts A2 to A5 and
parity are printed last, as the note fixes them.
"""
import glob
import os
import sys

import netCDF4 as nc
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import od4_restate as od4  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else od4.ROOT
od4.ROOT = ROOT
RUNS = {"c": "g46_d4_budget", "2c": "g46_d4_budget_2c", "untagged": "g46_d4_untagged"}
OFFSET = {"c": 110495.0, "2c": 220990.0}
TIMES = (3600.0, 6 * 3600.0, 12 * 3600.0, 86400.0)
PARTITION = ("strat", "tropo")
REMAINDER_MAX = 1.0  # J/m², A2 and A3, the owner's level (E64)
REPAIR_MAX = 1.0  # J/m², A4
AGREE = (0.10, 1.0)  # A5: within 10%, or 1 J/m²
PARITY = ("rhoa", "ta", "hus", "clw", "cli", "husra", "hussn", "wa", "prra", "prsn",
          "hfls", "hfss", "lwp", "rwp", "arup", "rhoaup", "waup", "husup", "clwup",
          "cliup", "husraup", "hussnup", "tke", "edt", "evu")


def out_dir(run):
    return od4.out_dir(run)


def field(key, var, reduction="inst"):
    """Times, and the field per unit area per layer, J/m² (or kg/m² for
    water), at each output: `var` per unit mass times rhoa and dz."""
    d = out_dir(RUNS[key])
    path = glob.glob(os.path.join(d, f"{var}_1h_{reduction}.nc"))
    if not path:
        return None, None
    with nc.Dataset(path[0]) as ds:
        t = np.asarray(ds["time"][:])
        v = ds[var]
        values = np.moveaxis(np.asarray(v[:], dtype=np.float64), v.dimensions.index("time"), 0)
        values = values.reshape(len(t), -1)
        z = np.asarray(ds["z"][:], dtype=np.float64) if "z" in ds.variables else None
    if z is None:
        return t, values
    faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]), [z[-1] + 0.5 * (z[-1] - z[-2])]))
    dz = np.diff(faces)
    _, rho, _ = od4.read(d, "rhoa")
    return t, values * rho[: len(t)] * dz


def at(t, values, time):
    k = int(np.argmin(np.abs(t - time)))
    if abs(t[k] - time) > 1e-6:
        raise SystemExit(f"process_budget: no output at {time} s")
    return values[k]


def bits(a):
    a = np.ascontiguousarray(a)
    return a.view(np.uint64) if a.dtype == np.float64 else a.view(np.uint32)


def parity(key):
    """Every model field of a tagged run against the untagged twin, bit for bit."""
    differ, missing = [], []
    for var in PARITY:
        a_path = glob.glob(os.path.join(out_dir(RUNS[key]), f"{var}_1h_inst.nc"))
        b_path = glob.glob(os.path.join(out_dir(RUNS["untagged"]), f"{var}_1h_inst.nc"))
        if not a_path or not b_path:
            missing.append(var)
            continue
        with nc.Dataset(a_path[0]) as da, nc.Dataset(b_path[0]) as db:
            a, b = np.asarray(da[var][:]), np.asarray(db[var][:])
        if not (a.shape == b.shape and np.array_equal(bits(a), bits(b))):
            differ.append(var)
    return differ, missing


def budget(key):
    """The terms of both identities, per layer, at each time of TIMES."""
    t, R = field(key, "e_src_res")
    _, L_R = field(key, "e_src_led_src_res")
    _, I = field(key, "e_src_inc_left")
    F_S = sum(field(key, f"e_src_fix_{name}")[1] for name in PARTITION)
    L_part = sum(field(key, f"e_src_led_src_{name}")[1] for name in PARTITION)
    _, P_precip = field(key, "e_prc_precipitation")
    closure = od4.table(RUNS[key], "closure")
    audit = od4.table(RUNS[key], "audit")
    rows = {}
    for time in TIMES:
        dR = at(t, R, time) - R[0]
        terms = {
            "R(t) - R(0)": dR,
            "L_R, the flush": at(t, L_R, time),
            "I, left in place": at(t, I, time),
            "-F_S, the repair": -at(t, F_S, time),
        }
        terms["X_II, remainder"] = dR - terms["L_R, the flush"] - terms["I, left in place"] \
            - terms["-F_S, the repair"]
        E0 = od4.row_at(closure, 0.0)["total"]
        Et = od4.row_at(closure, time)["total"]
        rows[time] = {
            "II": terms,
            "E(t) - E(0)": Et - E0,
            "B": float(np.sum(at(t, L_part, time) + at(t, L_R, time))),
            "P_e,precipitation": float(np.sum(at(t, P_precip, time))),
            "F_S column abs": float(np.sum(np.abs(at(t, F_S, time)))),
            "throughput": (od4.row_at(audit, time)["source_throughput"]
                           if audit and "source_throughput" in audit[0] else None),
        }
    return rows


def mass(key):
    d = out_dir(RUNS[key])
    t, rho, w = od4.read(d, "rhoa")
    return t, np.sum(rho * w, axis=1)


def report():
    for key in RUNS:
        if out_dir(RUNS[key]) is None:
            print(f"process_budget: {RUNS[key]} has no output under {ROOT}")
            return
    verdicts = {}
    differ = {}
    for key in ("c", "2c"):
        bad, missing = parity(key)
        differ[key] = bad
        print(f"== parity, {RUNS[key]} against {RUNS['untagged']}: "
              + ("bit for bit" if not bad else "DIFFERS: " + ", ".join(bad))
              + (f" (missing {', '.join(missing)})" if missing else ""))
    budgets = {key: budget(key) for key in ("c", "2c")}
    t_m, M = mass("c")
    for key in ("c", "2c"):
        c = OFFSET[key]
        print(f"\n== identity II at {key} (c = {c:g} J/kg), J/m²: per layer, then the column")
        for time in TIMES:
            terms = budgets[key][time]["II"]
            print(f"   t = {time / 3600:.0f} h")
            for name, values in terms.items():
                layers = " ".join(f"{v:+.3e}" for v in values)
                print(f"     {name:18s} column {np.sum(values):+.4e} | layers {layers}")
    # Identity I, with c·M_U from the pair.
    print("\n== identity I, the column, J/m²")
    for time in TIMES:
        dM = at(t_m, M, time) - M[0]
        B_c, B_2c = budgets["c"][time]["B"], budgets["2c"][time]["B"]
        cMU = OFFSET["c"] * dM - (B_2c - B_c)
        for key in ("c", "2c"):
            row = budgets[key][time]
            scale = OFFSET[key] / OFFSET["c"]
            X_I = row["E(t) - E(0)"] - row["B"] - row["P_e,precipitation"] - scale * cMU
            print(f"   t = {time / 3600:4.0f} h, {key:2s}: ΔE {row['E(t) - E(0)']:+.4e} = "
                  f"B {row['B']:+.4e} + P_precip {row['P_e,precipitation']:+.4e} + "
                  f"c·M_U {scale * cMU:+.4e} + X_I {X_I:+.4e}")
    # C4.
    day = 86400.0
    dM = at(t_m, M, day) - M[0]
    cMU = OFFSET["c"] * dM - (budgets["2c"][day]["B"] - budgets["c"][day]["B"])
    I_c = float(np.sum(budgets["c"][day]["II"]["I, left in place"]))
    I_2c = float(np.sum(budgets["2c"][day]["II"]["I, left in place"]))
    theta = budgets["c"][day]["throughput"]
    print(f"\n== C4 at 24 h: c·M_U {cMU:+.4e} J/m²"
          + (f", {abs(cMU) / theta:.3e} of the day's Θx" if theta else "")
          + f"; I_col(2c) − I_col(c) {I_2c - I_c:+.4e}")
    # The records' estimate of the same mass change.
    q_terms = []
    for p in ("surface_flux", "subsidence", "microphysics"):
        t_q, q = field("c", f"q_prc_{p}")
        if q is not None:
            q_terms.append(float(np.sum(at(t_q, q, day))))
    t_pr, pr = field("c", "pr", "average")
    if pr is not None and q_terms:
        # `pr` is the hour's average rate, positive downward, kg/m²/s.
        surface = float(np.sum(pr[1:, 0] * np.diff(t_pr)))
        print(f"   from the records: c·(ΔM − Σ q_prc + ∫pr dt) "
              f"{OFFSET['c'] * (dM - sum(q_terms) + surface):+.4e} J/m²")

    # The verdicts.
    void = [key for key in ("c", "2c") if differ[key]]
    print("\n== verdicts (design/D4_PROCESS_BUDGET.md, section 4)")
    if void:
        print(f"   not assessable: parity fails for {', '.join(RUNS[k] for k in void)}")
        return
    for key, name in (("c", "A2"), ("2c", "A3")):
        x = float(np.sum(budgets[key][day]["II"]["X_II, remainder"]))
        ok = abs(x) <= REMAINDER_MAX
        print(f"   {name}: |X_II| at 24 h, {key}: {abs(x):.3e} J/m² (at most {REMAINDER_MAX}): "
              + ("pass" if ok else "fail"))
    repair = max(budgets[k][day]["F_S column abs"] for k in ("c", "2c"))
    print(f"   A4: ∫|F_S| dz at 24 h, the larger of the pair {repair:.3e} J/m² "
          f"(at most {REPAIR_MAX}): " + ("pass" if repair <= REPAIR_MAX else "fail"))
    gap = abs((I_2c - I_c) - cMU)
    ok = gap <= max(AGREE[0] * abs(cMU), AGREE[1])
    print(f"   A5: I_col(2c) − I_col(c) against c·M_U, differ by {gap:.3e} J/m²: "
          + ("pass" if ok else "fail"))


if __name__ == "__main__":
    report()
