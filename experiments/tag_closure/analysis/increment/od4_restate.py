"""G4.3: restate the energy E-records on OD4's scale (review/od4_restatement.md).

    python3 od4_restate.py [OUTPUT_ROOT] > od4_restatement.txt

OUTPUT_ROOT defaults to $SCRATCH/tag_closure/output. Every run is read from
its own `output_XXXX` there. Nothing is rerun.

OD4's scale is the gross source throughput over the record's window: the
energy the sources put into the tags (the register, OD4). Two measures exist.

  - Exact: the audit's `source_throughput`, the partition's per-step gross of
    each tag's source ledger (#115, design/GROSS_ACCUMULATORS.md section 11).
    Only runs on #115 or later have it.
  - Interim: the process records, `Σ over output intervals and source
    processes of ∫ρ|Δe_prc|`. `precipitation` is left out, since the energy
    source tags take sedimentation as transport, not as a source.

The interim is not a lower bound of the exact measure. The records are net
over each output interval but keep the processes apart. The exact measure is
per step but nets the processes within a cell and a step. And the records
hold `Δρe_tot` only, without the offset's `c·Δρ`. So the two can differ in
either direction. The script measures their ratio where a run has both
(g411x_d4_default), and reports every percentage on both where it can.

A column's integrals are per unit area (J/m²), as the closure table's are. A
sphere's NetCDF is remapped to latitude and longitude, so its integrals use
`rhoa`, the layer thickness from `z_physical`, the planet's radius and
cos(lat): approximate, within the remap. The script checks the sphere's
integral of the partition against the closure table's `total`.
"""
import csv
import glob
import os
import sys

import netCDF4 as nc
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ.get("SCRATCH", "/dss/dsstbyfs02/scratch/0D/di38kez"),
    "tag_closure",
    "output",
)
SOURCES = ("radiation", "surface_flux", "subsidence", "microphysics",
           "large_scale_advection", "external_forcing", "held_suarez")
RADIUS = 6.371e6
CLOSURE_ENERGY = 2e-3  # OD3, closure, energy: gross ≤ 0.2% of the window's throughput


def out_dir(run, index=None):
    dirs = sorted(glob.glob(os.path.join(ROOT, run, "output_0*")))
    if not dirs:
        return None
    if index is None:
        return dirs[-1]
    return os.path.join(ROOT, run, f"output_{index:04d}")


def table(run, name, index=None):
    d = out_dir(run, index)
    path = os.path.join(d, f"energy_source_tag_{name}.csv") if d else ""
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return [{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)]


def row_at(rows, t):
    return min(rows, key=lambda r: abs(r["time"] - t))


def cadence_files(d, var):
    return sorted(glob.glob(os.path.join(d, f"{var}_*_inst.nc")))


def read(d, var):
    """Time-first values of `var`, its times, and the geometry's weights: a
    column gives dz per level (J/m² integrals); a sphere dV per point."""
    files = cadence_files(d, var)
    if not files:
        return None
    with nc.Dataset(files[0]) as ds:
        v = ds[var]
        t = np.asarray(ds["time"][:])
        values = np.moveaxis(np.asarray(v[:], dtype=np.float64),
                             v.dimensions.index("time"), 0)
        if "lat" in ds.dimensions:
            order = [v.dimensions.index(n) for n in ("time", "lon", "lat")]
            zname = [n for n in v.dimensions if n.startswith("z")][0]
            order.append(v.dimensions.index(zname))
            values = np.transpose(np.asarray(v[:], dtype=np.float64), order)
            lat = np.deg2rad(np.asarray(ds["lat"][:], dtype=np.float64))
            lon = np.deg2rad(np.asarray(ds["lon"][:], dtype=np.float64))
            zp = np.asarray(ds["z_physical"][:], dtype=np.float64)  # (z, lat, lon)
            zp = np.transpose(zp, (2, 1, 0))  # (lon, lat, z)
            faces = np.concatenate(
                (np.zeros(zp.shape[:2] + (1,)),
                 0.5 * (zp[..., 1:] + zp[..., :-1]),
                 (zp[..., -1] + 0.5 * (zp[..., -1] - zp[..., -2]))[..., None]),
                axis=-1,
            )
            dz = np.diff(faces, axis=-1)
            dlat = np.pi / len(lat)
            dlon = 2 * np.pi / len(lon)
            area = RADIUS**2 * np.cos(lat)[None, :, None] * dlat * dlon
            weight = area * dz
        elif "z" in ds.variables:
            z = np.asarray(ds["z"][:], dtype=np.float64)
            faces = np.concatenate(([0.0], 0.5 * (z[1:] + z[:-1]),
                                    [z[-1] + 0.5 * (z[-1] - z[-2])]))
            weight = np.diff(faces)
            values = values.reshape(len(t), -1)
        else:
            # A surface field of a column: per unit area already.
            weight = np.ones(1)
            values = values.reshape(len(t), -1)
    return t, values, weight


def throughput_interim(run, t0, t1, index=None):
    """Σ over the output intervals in (t0, t1] and the source records of
    ∫ρ|Δe_prc|. Returns (value, the records used, the interval in s)."""
    d = out_dir(run, index)
    rho = read(d, "rhoa")
    if rho is None:
        return None, (), None
    t, rho_v, w = rho
    used, total = [], 0.0
    for process in SOURCES:
        r = read(d, f"e_prc_{process}")
        if r is None:
            continue
        used.append(process)
        _, e, _ = r
        for k in range(1, len(t)):
            if t0 + 1e-6 < t[k] <= t1 + 1e-6:
                total += np.sum(rho_v[k] * np.abs(e[k] - e[k - 1]) * w)
    return total, tuple(used), (t[1] - t[0]) if len(t) > 1 else None


def throughput_exact(run, t0, t1, index=None):
    audit = table(run, "audit", index)
    if not audit or "source_throughput" not in audit[0]:
        return None
    return row_at(audit, t1)["source_throughput"] - row_at(audit, t0)["source_throughput"]


def sphere_check(run):
    """The sphere's remapped integral of the partition against the closure
    table's `total`: how good the remap's integrals are."""
    d = out_dir(run)
    rho = read(d, "rhoa")
    closure = table(run, "closure")
    if rho is None or closure is None:
        return None
    t, rho_v, w = rho
    parts = [n for n in ("tropics", "extratropics", "res")
             if cadence_files(d, f"e_src_{n}")]
    k = len(t) - 1
    total = sum(np.sum(rho_v[k] * read(d, f"e_src_{n}")[1][k] * w) for n in parts)
    return total / row_at(closure, t[k])["total"]


def fmt(x):
    return "—" if x is None else f"{x:.3g}"


print("# OD4 restatement, G4.3. Scales in J/m² for columns and J for spheres.")
print(f"# Output root: {ROOT}")
print("# Θi: the interim, the process records' Σ∫ρ|Δe_prc| over output intervals.")
print("# Θx: the exact accumulator, the audit's source_throughput (#115).")
print()

# 1. The two scales where a run has both: g411x_d4_default (E83's rerun on #115).
print("## 1. The interim against the exact scale, D4 (g411x_d4_default)")
for t1 in (3600.0, 6 * 3600.0, 12 * 3600.0, 86400.0):
    ti, used, dt = throughput_interim("g411x_d4_default", 0.0, t1)
    tx = throughput_exact("g411x_d4_default", 0.0, t1)
    if ti is None or tx is None:
        print("   (not available)")
        break
    print(f"   0 to {t1 / 3600:4.0f} h: Θi {ti:.4e}, Θx {tx:.4e}, Θx/Θi {tx / ti:.4f}"
          f"  (records {', '.join(used)}; sampled every {dt:.0f} s)")
ti, _, _ = throughput_interim("g411x_d4_default", 3600.0, 86400.0)
tx = throughput_exact("g411x_d4_default", 3600.0, 86400.0)
if ti and tx:
    print(f"   1 to 24 h (OD2's D4 window): Θi {ti:.4e}, Θx {tx:.4e}, Θx/Θi {tx / ti:.4f}")
print()

# 2. The records, restated. Each entry: (record, what, run, time, where the
#    amount comes from, the value as recorded, unused).
print("## 2. The records' numbers on OD4's scale, window 0 to t unless stated")
print("record | quantity | run | t | amount | recorded | Θi | Θx | amount/Θi | amount/Θx | E/Θi")


def closure_amount(run, t, column, index=None):
    rows = table(run, "closure", index)
    return None if rows is None else row_at(rows, t)[column]


def audit_amount(run, t, column, index=None):
    rows = table(run, "audit", index)
    return None if rows is None or column not in rows[0] else row_at(rows, t)[column]


ENTRIES = [
    # E26: form B on C6's column, 24 h (class 1).
    ("E26", "form B remainder, J/m²", "c6_column_repair", 86400.0,
     ("value", 3.3248215913772583e-7), "3.3e-7 J/m² of 1.43 MJ/m²", 1),
    # E39: the audit's gross at 1 h on C9's column (class 1; the 98% is class 4).
    ("E39", "gross at 1 h, one Newton iteration", "c9_column_enthalpy", 3600.0,
     ("closure", "gross_residual"), "2,695 J/m²", 0),
    ("E39", "gross at 1 h, converged (reviewer's stepping)", "c9_column_enthalpy", 3600.0,
     ("value", 20.5), "20.5 J/m²", 0),
    # E42, E42b: D1, an hour, tracer transport (class 2).
    ("E42", "gross at 1 h", "d1_column_1m_ice", 3600.0,
     ("closure", "gross_residual"), "3.7e-3 of the partition", 0),
    ("E42", "signed at 1 h", "d1_column_1m_ice", 3600.0,
     ("closure", "residual"), "4.5e-10 of the partition", 0),
    ("E42b", "gross at 1 h, no vertical diffusion", "d1_column_1m_ice_no_vdiff", 3600.0,
     ("closure", "gross_residual"), "2.350e6 J/m²", 0),
    # E62: the prototype on D4 (class 2 for gross_relative).
    ("E62", "gross at 24 h", "inc_d4_enthalpy_increment", 86400.0,
     ("closure", "gross_residual"), "267 J/m², 2.4e-6 of the partition", 0),
    ("E62", "base (enthalpy) gross at 24 h", "c1c_base_d4_enthalpy", 86400.0,
     ("closure", "gross_residual"), "6.32e5 J/m², 5.5e-3", 0),
    # E64: the ledger (class 1).
    ("E64", "gross at 24 h", "g1_inc_d4", 86400.0,
     ("closure", "gross_residual"), "266.942 J/m²", 0),
    ("E64", "left in place, cells' absolute", "g1_inc_d4", 86400.0,
     ("audit", "increment_left_gross"), "313 J/m²", 0),
    ("E64", "moved, cells' absolute", "g1_inc_d4", 86400.0,
     ("audit", "increment_moved_gross"), "3.3e7 J/m²", 0),
    ("E64", "gross at 24 h, ten iterations", "g1_inc_newton_d4", 86400.0,
     ("closure", "gross_residual"), "0.080 J/m²", 0),
    # E65: Float32 (class 1; the 2.3× is class 4).
    ("E65", "gross at 24 h, Float32 prototype", "g1_inc_d4_float32", 86400.0,
     ("closure", "gross_residual"), "607 J/m²", 0),
    ("E65", "gross at 24 h, Float32 base (enthalpy)", "g1_base_d4_float32", 86400.0,
     ("closure", "gross_residual"), "7.53e5 J/m²", 0),
    # E66: the reference's own residual (class 1).
    ("E66", "reference's gross at 24 h", "g1_ref_newton10_d4", 86400.0,
     ("closure", "gross_residual"), "5.99e5 J/m²", 0),
    # E71: the prototype at 2c (class 1); not listed by rev. 2.
    ("E71", "gross at 24 h, offset 2c", "g1_inc_d4_2c", 86400.0,
     ("closure", "gross_residual"), "509 J/m²", 0),
    # E73: default and copies at 24 h (class 1).
    ("E73", "default gross at 24 h", "v3_upd_default", 86400.0,
     ("closure", "gross_residual"), "267.07 J/m²", 0),
    ("E73", "copies gross at 24 h", "v3_upd_copies", 86400.0,
     ("closure", "gross_residual"), "365 J/m²", 0),
    # E74, E75: the sphere at ten days (class 2).
    ("E74", "gross at 10 d", "g2_v2_sphere_n2", 864000.0,
     ("closure", "gross_residual"), "2.01e-4 of the scale", 0),
    ("E74", "gross at 1 d", "g2_v2_sphere_n2", 86400.0,
     ("closure", "gross_residual"), "2.77e-5 of the scale", 0),
    ("E75", "gross at 10 d, with the mixing", "g2_v2_sphere_mix", 864000.0,
     ("closure", "gross_residual"), "2.003e-4 of the scale", 0),
    # E79: G4.15 on D4 (class 2).
    ("E79", "gross at 24 h, |m| rule", "g415_inc_d4_before", 86400.0,
     ("closure", "gross_residual"), "2.3e-6 of the partition", 0),
    ("E79", "gross at 24 h, same sign", "g415_inc_d4_after", 86400.0,
     ("closure", "gross_residual"), "9.2e-6 of the partition", 0),
    ("E79", "moved, |m| rule", "g415_inc_d4_before", 86400.0,
     ("audit", "increment_moved_gross"), "0.289 of the partition", 0),
    # E82: the D4 day of G4.16 (class 2).
    ("E82", "D4 gross at 24 h, blocks off", "g416_d4_off", 86400.0,
     ("closure", "gross_residual"), "2.3e-6", 0),
    ("E82", "D4 gross at 24 h, blocks on", "g416_d4_on", 86400.0,
     ("closure", "gross_residual"), "8.9e-15", 0),
    # E83: the copies' own residual and repair, already on the interim.
    ("E83", "copies with mirrors: repair at 24 h", "g411_d4_copies", 86400.0,
     ("audit", "repair_moved"), "2.9% a day of Θi over 1 to 24 h", 0),
    ("E83", "default: gross at 24 h", "g411_d4_default", 86400.0,
     ("closure", "gross_residual"), "—", 0),
]

results = []
for record, what, run, t, (kind, key), recorded, _ in ENTRIES:
    if kind == "closure":
        amount = closure_amount(run, t, key)
    elif kind == "audit":
        amount = audit_amount(run, t, key)
    else:
        amount = key
    ti, used, _ = throughput_interim(run, 0.0, t)
    tx = throughput_exact(run, 0.0, t)
    partition = closure_amount(run, t, "total")
    ratio_i = None if (amount is None or not ti) else abs(amount) / ti
    ratio_x = None if (amount is None or not tx) else abs(amount) / tx
    e_over = None if (partition is None or not ti) else partition / ti
    results.append((record, what, run, t, amount, ratio_i, ratio_x))
    print(f"{record} | {what} | {run} | {t / 3600:.0f} h | {fmt(amount)} | {recorded} | "
          f"{fmt(ti)} | {fmt(tx)} | {fmt(ratio_i)} | {fmt(ratio_x)} | {fmt(e_over)}")
print()

# 3. E83's windowed numbers on both scales, where the rerun has both.
print("## 3. E83 on both scales, window 1 to 24 h (OD2's first hour)")
for run in ("g411x_d4_default", "g411x_d4_copies", "g411x_d4_copies_before",
            "g411x_d4_copies_dt60", "g411_d4_copies", "g411_d4_copies_before",
            "g411_d4_copies_dt60", "g411_d4_default"):
    closure = table(run, "closure")
    audit = table(run, "audit")
    if not closure or not audit or row_at(closure, 86400.0)["time"] < 86400.0 - 1:
        print(f"   {run}: not finished or not present")
        continue
    ti, _, _ = throughput_interim(run, 3600.0, 86400.0)
    tx = throughput_exact(run, 3600.0, 86400.0)
    own = row_at(closure, 86400.0)["gross_residual"] - row_at(closure, 3600.0)["gross_residual"]
    rep = row_at(audit, 86400.0)["repair_moved"] - row_at(audit, 3600.0)["repair_moved"]
    days = (86400.0 - 3600.0) / 86400.0
    line = f"   {run}: own {own / ti:.3e} of Θi, repair {rep / ti / days:.3e} a day of Θi"
    if tx:
        line += f"; own {own / tx:.3e} of Θx, repair {rep / tx / days:.3e} a day of Θx"
    print(line)
print()

# 4. The sphere's remap check.
print("## 4. The sphere's remapped integral of the partition over the closure's total")
for run in ("g2_v2_sphere_n2", "g2_v2_sphere_mix"):
    check = sphere_check(run)
    print(f"   {run}: " + ("—" if check is None else f"{check:.5f}"))
print()

# 5. The records without a throughput: surface fluxes only, a partial scale.
print("## 5. Runs without records: the surface enthalpy flux alone (hfss + hfls)")
for run in ("g416_expl_n1_off", "g416_expl_n1_on", "g416_impl_n1_off", "g416_impl_n1_on"):
    d = out_dir(run)
    closure = table(run, "closure")
    if d is None or closure is None:
        print(f"   {run}: not present")
        continue
    fluxes = []
    for var in ("hfss", "hfls"):
        r = read(d, var)
        if r is not None:
            fluxes.append(r)
    if len(fluxes) < 2:
        print(f"   {run}: no surface fluxes")
        continue
    t = fluxes[0][0]
    flux = fluxes[0][1][:, 0] + fluxes[1][1][:, 0]
    # The trapezoid of the upward enthalpy flux over the hour.
    surface = float(np.sum(0.5 * (flux[1:] + flux[:-1]) * np.diff(t)))
    last = closure[-1]
    print(f"   {run}: to {last['time']:.0f} s, ∫(hfss+hfls)dt {surface:.4e} J/m²; "
          f"gross {last['gross_residual']:.4e} J/m² = {last['gross_residual'] / abs(surface):.3e} "
          f"of it (recorded {last['gross_relative']:.3e} of the partition)")
print()

# 6. Rows the records never scored, now assessable on the same output: the
#    repair's energy per day over the window's throughput (intervention,
#    aggregate), and its ratio between rungs of the ladder (refinement).
#    `repair_moved` is Σ over cells and tags of |ledger|, net over time in each
#    cell, so it is a lower bound of the repair's gross.
print("## 6. The repair per day over Θi, window 1 h to the end (intervention; refinement)")
LADDER = [
    ("v3_d4_passive_tracer", None, "before the exchange (E68, 04d63916)"),
    ("v3_upd_default", 0, "the exchange, E73's run (e010f780)"),
    ("v3_upd_default", 2, "the exchange at 846ef55d (E73's rerun)"),
    ("v3_upd_default", 5, "E76, 120 s (dcf7d086)"),
    ("v3_upd_default_dt60", 2, "E76, 60 s (dcf7d086)"),
    ("v3_upd_default_dt30", None, "E76, 30 s (dcf7d086)"),
    ("v3_upd_default_newton2", 2, "E76, two Newton iterations (dcf7d086)"),
    ("v3_upd_default_upwind", 2, "E76, first-order upwind (dcf7d086)"),
    ("v3_upd_copies", 0, "E73's copies (3ec098f1)"),
    ("v3_upd_copies_dt60", None, "E76's copies, 60 s (dbe7435c)"),
    ("v3_upd_copies_dt30", None, "E76's copies, 30 s (dbe7435c)"),
    ("g411x_d4_default", None, "E83's default rerun on #115"),
    ("g2_v2_sphere_n2", None, "E74, the sphere, 10 d"),
    ("g2_v2_sphere_mix", None, "E75, the sphere with the mixing, 10 d"),
]
per_day = {}
for run, index, label in LADDER:
    audit = table(run, "audit", index)
    if not audit or "repair_moved" not in audit[0]:
        print(f"   {label}: not present")
        continue
    t1 = audit[-1]["time"]
    ti, _, _ = throughput_interim(run, 3600.0, t1, index)
    tx = throughput_exact(run, 3600.0, t1, index)
    rep = row_at(audit, t1)["repair_moved"] - row_at(audit, 3600.0)["repair_moved"]
    days = (t1 - 3600.0) / 86400.0
    value = rep / ti / days if ti else None
    per_day[(run, index)] = value
    line = f"   {label} [{run}]: repair {rep:.4e} over {days:.3f} d; {fmt(value)} a day of Θi"
    if tx:
        line += f", {rep / tx / days:.3g} a day of Θx"
    print(line)
base = per_day.get(("v3_upd_default", 5))
for key, label in ((("v3_upd_default_dt60", 2), "60 s over 120 s"),
                   (("v3_upd_default_dt30", None), "30 s over 120 s"),
                   (("v3_upd_default_newton2", 2), "two iterations over one")):
    if base and per_day.get(key):
        print(f"   ratio, {label}: {per_day[key] / base:.3f}")
