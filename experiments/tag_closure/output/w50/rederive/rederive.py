"""W50, re-derived independently from W25_ISOLATION.md sections 4 and 8.

Written without reading analysis/water/w50_score.py. Definitions used:

  - OD2's window (ROADMAP.md, approved 2026-09-24), reimplemented here: the
    untagged twin's column water W = sum(rho q dz) at its 10-minute outputs;
    the tendency |dW|/dt over each interval; the level is 10% of the largest
    tendency among intervals that end by 6 h; startup ends at the first
    output after which three intervals in a row lie below the level.
  - L1 = sum(rho |q_d - q_c| dz) / sum(rho |q_c| dz), L_inf = max|q_d - q_c|
    / max|q_c| (G3_PLAN 6.1), copies are the reference.
  - Small tag: the copies' share sum(rho q_c dz) / sum(rho q_tot dz) under
    1%; it is judged on sum(rho |dq| dz) <= 2e-4 sum(rho q_tot dz).
  - Region tags: tropo, strat, sfc, air. Source tags: evap, evap_tropo,
    evap_strat (they carry `source: surface_flux`).
  - R4: closure CSV gross_residual; 24 h over total <= 2e-3; the second 12 h
    add no more than the first: G(24)-G(12) <= G(12)-G(0).
  - R5: audit copy_residual_relative, largest hourly value <= 2e-4; the
    copies' repair = the state ledger led_uprepair's retained gross, per day
    in established flow, <= 2e-3 of sum(rho q_tot).
  - R1: every variable of every NetCDF file the tagged run shares with its
    twin (tag files excluded), exact equality, NaN positions included.

Prints RESULT lines and writes results.json next to itself.
"""

import csv
import glob
import json
import os

import netCDF4
import numpy as np

ROOT = "/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/output"
HERE = os.path.dirname(os.path.abspath(__file__))
DAY = 86400.0

RUNGS = {"z30": ("d4w", "z30"), "z60": ("d4w", "z60"), "pulse_z30": ("d4w_pulse", "z30")}
ARMS = ("fix", "main")
MODES = ("default", "copies")
REGION_TAGS = {"tropo", "strat", "sfc", "air"}
SOURCE_TAGS = {"evap", "evap_tropo", "evap_strat"}


def run_dir(rung, mode, arm):
    case, z = RUNGS[rung]
    return os.path.join(ROOT, f"w50_{case}_{mode}_{z}_c_{arm}", "output_0000")


def twin_dir(rung):
    return os.path.join(ROOT, f"w50_d4w_untagged_{RUNGS[rung][1]}_c", "output_0000")


def read_var(path, name):
    with netCDF4.Dataset(path) as d:
        v = d[name]
        values = np.asarray(v[:], dtype=float)
        values = np.moveaxis(values, v.dimensions.index("time"), 0)
        time = np.asarray(d["time"][:], dtype=float)
        z = np.asarray(d["z"][:], dtype=float)
    return time, z, values.reshape(values.shape[0], -1)


def cell_dz(z):
    # Cell-centre heights of a uniform grid: the thickness is the spacing.
    dz = np.diff(z)
    assert np.allclose(dz, dz[0], rtol=1e-9), "grid is not uniform"
    return np.full(z.shape, dz[0])


def read_csv(path):
    with open(path) as h:
        rows = list(csv.DictReader(h))
    return {k: np.array([float(r[k]) for r in rows]) for k in rows[0]}


# ---------------------------------------------------------------- window ---
def od2_window(rung):
    d = twin_dir(rung)
    t, z, rho = read_var(os.path.join(d, "rhoa_10m_inst.nc"), "rhoa")
    t2, _, q = read_var(os.path.join(d, "hus_10m_inst.nc"), "hus")
    assert np.array_equal(t, t2)
    dz = cell_dz(z)
    water = (rho * q * dz).sum(axis=1)
    tend = np.abs(np.diff(water)) / np.diff(t)  # interval k: t[k] -> t[k+1]
    first6 = t[1:] <= 6 * 3600 + 1e-6
    level = 0.1 * tend[first6].max()
    below = tend < level
    for k in range(len(below) - 2):
        if below[k] and below[k + 1] and below[k + 2]:
            return float(t[k]), float(level), int(k)
    return None, float(level), None


# -------------------------------------------------------------------- R1 ---
def compare_files(a_dir, b_dir):
    """Every variable of every shared NetCDF file, tag files excluded."""
    a_files = {os.path.basename(p) for p in glob.glob(os.path.join(a_dir, "*.nc"))}
    b_files = {os.path.basename(p) for p in glob.glob(os.path.join(b_dir, "*.nc"))}
    shared = sorted(f for f in a_files & b_files if not f.startswith("q_tag_"))
    n_vars, mismatches, max_diff = 0, [], 0.0
    for f in shared:
        with netCDF4.Dataset(os.path.join(a_dir, f)) as da, netCDF4.Dataset(
            os.path.join(b_dir, f)
        ) as db:
            names = set(da.variables) | set(db.variables)
            for name in sorted(names):
                if name not in da.variables or name not in db.variables:
                    mismatches.append(f"{f}:{name}:missing")
                    continue
                x = np.asarray(da[name][:])
                y = np.asarray(db[name][:])
                n_vars += 1
                if x.shape != y.shape:
                    mismatches.append(f"{f}:{name}:shape")
                    continue
                if x.dtype.kind == "f":
                    same = np.array_equal(x, y, equal_nan=True) and x.tobytes() == y.tobytes()
                    if not same:
                        diff = np.nanmax(np.abs(x.astype(float) - y.astype(float)))
                        max_diff = max(max_diff, float(diff))
                        mismatches.append(f"{f}:{name}:{diff:.3e}")
                else:
                    if not np.array_equal(x, y):
                        mismatches.append(f"{f}:{name}")
    return len(shared), n_vars, mismatches, max_diff


# -------------------------------------------------------------------- R4 ---
def r4(rdir):
    c = read_csv(os.path.join(rdir, "water_tag_closure.csv"))
    t = c["time"]
    i0, i12, i24 = [int(np.flatnonzero(np.isclose(t, s))[0]) for s in (0, 43200, 86400)]
    g, total = c["gross_residual"], c["total"]
    first = g[i12] - g[i0]
    second = g[i24] - g[i12]
    return {
        "gross_rel_24h": float(g[i24] / total[i24]),
        "gross_rel_24h_csv": float(c["gross_relative"][i24]),
        "gross_rel_12h": float(g[i12] / total[i12]),
        "added_first_12h_rel": float(first / total[i24]),
        "added_second_12h_rel": float(second / total[i24]),
        "max_gross_rel_first_12h": float(c["gross_relative"][i0 : i12 + 1].max()),
        "max_gross_rel_second_12h": float(c["gross_relative"][i12 + 1 : i24 + 1].max()),
        "pass_24h": bool(g[i24] / total[i24] <= 2e-3),
        "pass_second_half": bool(second <= first),
        "closure_void_any": bool(c["closure_void"].max() > 0),
        "negative_water_void_any": bool(c["negative_water_void"].max() > 0),
    }


# -------------------------------------------------------------------- R5 ---
def r5(rdir, t_start):
    a = read_csv(os.path.join(rdir, "water_tag_audit.csv"))
    c = read_csv(os.path.join(rdir, "water_tag_closure.csv"))
    t = a["time"]
    assert np.array_equal(t, c["time"])
    scale = c["total"]
    # The audit's _relative columns share the closure's scale: check it.
    ok = a["led_uprepair_retained"] > 0
    scale_check = float(
        np.max(np.abs(a["led_uprepair_retained"][ok] / a["led_uprepair_retained_relative"][ok] / scale[ok] - 1))
    )
    res = a["copy_residual_relative"][t > 0]
    est = (t >= t_start - 1e-6) & (t > 0)
    i24 = int(np.flatnonzero(np.isclose(t, 86400))[0])
    retained = a["led_uprepair_retained"]

    def per_day(i0):
        span = t[i24] - t[i0]
        mean_scale = scale[i0 : i24 + 1].mean()
        return float((retained[i24] - retained[i0]) / mean_scale * DAY / span)

    # Hourly audit rows: the row at or after startup's end, and the row
    # before it; the larger per-day value is the one judged.
    i_after = int(np.flatnonzero(t >= t_start - 1e-6)[0])
    i_before = int(np.flatnonzero(t <= t_start + 1e-6)[-1])
    rep_after, rep_before = per_day(i_after), per_day(i_before)
    repair = max(rep_after, rep_before)
    upfilter = a["led_upfilter_retained"]
    out = {
        "copy_residual_max_all_hours": float(res.max()),
        "copy_residual_max_hour_s": float(t[t > 0][np.argmax(res)]),
        "copy_residual_max_established": float(a["copy_residual_relative"][est].max()),
        "repair_per_day_established": repair,
        "repair_per_day_from_row_after_start": rep_after,
        "repair_per_day_from_row_before_start": rep_before,
        "repair_rows_used_s": [float(t[i_before]), float(t[i_after])],
        "repair_per_day_whole_day": per_day(int(np.flatnonzero(t == 0)[0])),
        "repair_first_hour_rel": float(retained[int(np.flatnonzero(np.isclose(t, 3600))[0])] / scale[1]),
        "repair_24h_cum_rel": float(retained[i24] / scale[i24]),
        "copy_repair_net_24h_rel": float(a["copy_repair_relative"][i24]),
        "upfilter_24h_cum_rel": float(upfilter[i24] / scale[i24]),
        "partition_repair_24h_cum_rel": float(a["led_repair_retained"][i24] / scale[i24]),
        "scale_check_max_rel_dev": scale_check,
        "pass_residual": bool(res.max() <= 2e-4),
        "pass_repair": bool(repair <= 2e-3),
    }
    out["pass"] = out["pass_residual"] and out["pass_repair"]
    return out


# -------------------------------------------------------------------- R7 ---
def tag_names(rdir):
    names = []
    for p in sorted(glob.glob(os.path.join(rdir, "q_tag_*_1h_inst.nc"))):
        n = os.path.basename(p)[len("q_tag_") : -len("_1h_inst.nc")]
        if n in REGION_TAGS or n in SOURCE_TAGS:
            names.append(n)
    return names


def load_state(rdir, tags):
    t, z, rho = read_var(os.path.join(rdir, "rhoa_1h_inst.nc"), "rhoa")
    _, _, qt = read_var(os.path.join(rdir, "hus_1h_inst.nc"), "hus")
    q = {}
    for n in tags:
        tt, _, q[n] = read_var(os.path.join(rdir, f"q_tag_{n}_1h_inst.nc"), f"q_tag_{n}")
        assert np.array_equal(tt, t)
    return t, cell_dz(z), rho, qt, q


def compare_tag(qd, qc, rho, qt, dz):
    err = np.sum(rho * np.abs(qd - qc) * dz)
    ref = np.sum(rho * np.abs(qc) * dz)
    parent = np.sum(rho * qt * dz)
    peak = np.max(np.abs(qc))
    return {
        "L1": float(err / ref) if ref > 0 else float("nan"),
        "Linf": float(np.max(np.abs(qd - qc)) / peak) if peak > 0 else float("nan"),
        "abs": float(err / parent),
        "share_ref": float(np.sum(rho * qc * dz) / parent),
        "share_other": float(np.sum(rho * qd * dz) / parent),
        "signed": float(np.sum(rho * (qd - qc) * dz) / np.sum(rho * qc * dz)),
    }


def budget(tag, when, m):
    small = m["share_ref"] < 0.01
    if when == "1h":
        l1 = 0.01 if tag in REGION_TAGS else 0.10
        linf = 0.25
    else:
        l1, linf = 0.02, 0.05
    if small:
        ok = m["abs"] <= 2e-4
        return ok, f"small tag (share {m['share_ref']:.3e}): abs {m['abs']:.3e} vs 2e-4"
    ok = m["L1"] <= l1 and m["Linf"] <= linf
    return ok, f"L1 {m['L1']:.4e} vs {l1}; Linf {m['Linf']:.4e} vs {linf}"


def main():
    out = {"window": {}, "R1": {}, "R4": {}, "R5": {}, "R7": {}, "effect": {}, "parity_extra": {}}
    windows = {}
    for rung in ("z30", "z60"):
        start, level, k = od2_window(rung)
        windows[rung] = start
        out["window"][rung] = {"startup_end_s": start, "level": level}
        print(f"RESULT window rung={rung} startup_end_s={start} level={level:.6e}")
    windows["pulse_z30"] = windows["z30"]

    for rung in RUNGS:
        for arm in ARMS:
            for mode in MODES:
                rdir = run_dir(rung, mode, arm)
                key = f"{rung}/{arm}/{mode}"
                nf, nv, mism, md = compare_files(rdir, twin_dir(rung))
                out["R1"][key] = {"files": nf, "variables": nv, "mismatches": mism[:10], "n_mismatch": len(mism), "max_abs_diff": md, "pass": len(mism) == 0}
                print(f"RESULT R1 {key} files={nf} vars={nv} mismatches={len(mism)} max_abs_diff={md:.3e} pass={len(mism)==0}")
                r = r4(rdir)
                out["R4"][key] = r
                print(
                    f"RESULT R4 {key} gross24={r['gross_rel_24h']:.4e} add1={r['added_first_12h_rel']:.4e} "
                    f"add2={r['added_second_12h_rel']:.4e} pass24={r['pass_24h']} pass_half={r['pass_second_half']} "
                    f"void={r['closure_void_any']} negvoid={r['negative_water_void_any']}"
                )
            r = r5(run_dir(rung, "copies", arm), windows[rung])
            out["R5"][f"{rung}/{arm}"] = r
            print(
                f"RESULT R5 {rung}/{arm} residual_max={r['copy_residual_max_all_hours']:.4e}@{r['copy_residual_max_hour_s']:.0f}s "
                f"residual_max_est={r['copy_residual_max_established']:.4e} repair_per_day={r['repair_per_day_established']:.4e} "
                f"(after {r['repair_per_day_from_row_after_start']:.4e}, before {r['repair_per_day_from_row_before_start']:.4e}) "
                f"whole_day={r['repair_per_day_whole_day']:.4e} pass={r['pass']}"
            )

    # R7 and the rule's effect.
    for rung in RUNGS:
        states = {}
        tags = tag_names(run_dir(rung, "default", "fix"))
        for arm in ARMS:
            for mode in MODES:
                states[(arm, mode)] = load_state(run_dir(rung, mode, arm), tags)
        t = states[("fix", "default")][0]
        idx = {"1h": int(np.flatnonzero(np.isclose(t, 3600))[0]), "24h": int(np.flatnonzero(np.isclose(t, 86400))[0])}
        # Parent parity between arms and modes on the fields used here.
        base = states[("fix", "default")]
        for k2, s in states.items():
            same = np.array_equal(s[2], base[2]) and np.array_equal(s[3], base[3])
            out["parity_extra"][f"{rung}/{k2[0]}/{k2[1]}"] = bool(same)
        for arm in ARMS:
            r5pass = out["R5"][f"{rung}/{arm}"]["pass"]
            _, dz, rho, qt, qd = states[(arm, "default")]
            _, _, _, _, qc = states[(arm, "copies")]
            for tag in tags:
                for when, i in idx.items():
                    m = compare_tag(qd[tag][i], qc[tag][i], rho[i], qt[i], dz)
                    ok, note = budget(tag, when, m)
                    verdict = (
                        "not assessable (R5 fails on this rung and arm)"
                        if not r5pass
                        else "waits for R6 (P2 not rerun)"
                    )
                    m.update({"within_budget": bool(ok), "note": note, "verdict": verdict})
                    out["R7"][f"{rung}/{arm}/{tag}/{when}"] = m
                    print(
                        f"RESULT R7 {rung}/{arm} tag={tag} t={when} L1={m['L1']:.4e} Linf={m['Linf']:.4e} "
                        f"abs={m['abs']:.4e} share={m['share_ref']:.4e} within={ok} verdict={verdict}"
                    )
        # The rule's effect: each mode, fix against main, main as reference.
        for mode in MODES:
            _, dz, rho, qt, qf = states[("fix", mode)]
            _, _, _, _, qm = states[("main", mode)]
            for tag in tags:
                for when, i in idx.items():
                    m = compare_tag(qf[tag][i], qm[tag][i], rho[i], qt[i], dz)
                    out["effect"][f"{rung}/{mode}/{tag}/{when}"] = m
                    print(
                        f"RESULT effect {rung} mode={mode} tag={tag} t={when} L1(fix,main)={m['L1']:.4e} "
                        f"Linf={m['Linf']:.4e} signed_inventory={m['signed']:+.4e}"
                    )
    with open(os.path.join(HERE, "results.json"), "w") as h:
        json.dump(out, h, indent=1)


if __name__ == "__main__":
    main()
