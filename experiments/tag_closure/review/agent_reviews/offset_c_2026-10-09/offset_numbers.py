"""Numbers for the review of the energy offset `c` (2026-10-09).

Reads the archived closure tables in `experiments/tag_closure/output/` for the
D4 and sphere totals. The other inputs are values the record states, each
named where it is used: E71's percentages, R9's minima, E74's flush time,
ATTRIBUTION_PATH 3.3's surface-flux figures and E41's falling ice.
Run from anywhere: `python3 offset_numbers.py > offset_numbers.txt`.
"""

import csv
import itertools
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "output"))

# Thermodynamics defaults as the record uses them (FINDINGS R1, R4).
CP_D, R_D, T0, G = 1004.5, 287.0, 273.16, 9.81  # as in the archived parameters
CV_D = CP_D - R_D
C0 = 110495.0  # the offset every G1 and G2 run used


def t_ref(c, z=0.0):
    """Temperature where dry, still air at height z has e_tot + c = 0."""
    return T0 - (c - R_D * T0 + G * z) / CV_D


def c_of_t_ref(t):
    """The offset that counts dry internal energy at sea level from t."""
    return CP_D * T0 - CV_D * t


def rows(run):
    with open(os.path.join(OUTPUT, run, "energy_source_tag_closure.csv")) as f:
        return list(csv.DictReader(f))


def main():
    c_floor, c_abs = c_of_t_ref(150.0), CP_D * T0
    print(f"cv_d = {CV_D}, R_d*T0 = {R_D * T0:.2f}, cp_d*T0 = {c_abs:.2f}")
    print(f"cp_d * 110 K = {CP_D * 110:.1f} (the offset in use)")
    print()
    print("The family c(T_ref) = cp_d*T0 - cv_d*T_ref")
    for name, c in [
        ("in use", C0),
        ("2c (E71, E19)", 2 * C0),
        ("150 K rule", c_floor),
        ("cp_d*T0", c_abs),
    ]:
        print(
            f"  {name:14s} c = {c:9.1f}  T_ref at z=0: {t_ref(c):6.2f} K, "
            f"1 km: {t_ref(c, 1000):6.2f} K, 3 km: {t_ref(c, 3000):6.2f} K; "
            f"enthalpy zero {T0 - c / CP_D:6.2f} K"
        )
    print()

    # D4 (DYCOMS RF02, EDMF, 1M) at c and 2c: E71's pair.
    d4c, d42c = rows("g1_inc_d4"), rows("g1_inc_d4_2c")
    e1, e2 = float(d4c[-1]["total"]), float(d42c[-1]["total"])
    mass = (e2 - e1) / C0
    e_mean = e1 / mass - C0
    ratio = e2 / e1
    print(
        f"D4 at 24 h: total {e1:.5e} (c), {e2:.5e} (2c), ratio {ratio:.4f}; "
        f"column mass {mass:.1f} kg/m2; mean e_tot {e_mean:.0f} J/kg; "
        f"mean E_c/rho {e1 / mass:.0f} J/kg"
    )
    print(
        f"D4 gross residual at 24 h: {float(d4c[-1]['gross_residual']):.1f} (c), "
        f"{float(d42c[-1]['gross_residual']):.1f} (2c) J/m2"
    )

    # E71's region-tag factors, rounded to whole percent in FINDINGS.
    f_strat, f_tropo = 2.77, 2.52
    for ds, dt in itertools.product((-0.005, 0.0, 0.005), repeat=2):
        fs, ft = f_strat + ds, f_tropo + dt
        x = (ratio - ft) / (fs - ft)
        print(
            f"  E71 factors {fs:.3f}, {ft:.3f}: strat share {x:.3f} -> "
            f"{x * fs / ratio:.3f} ({fs / ratio - 1:+.2%}), tropo "
            f"{1 - x:.3f} -> {(1 - x) * ft / ratio:.3f} ({ft / ratio - 1:+.2%})"
        )
    sources = {"rad": 1.044, "sfc": 1.063, "sub": 1.045,
               "new_strat": 1.042, "new_tropo": 1.060}
    print(
        f"  E71 source tags: largest pairwise ratio change "
        f"{max(sources.values()) / min(sources.values()) - 1:.2%}"
    )
    for tau in (4.0, 8.0, 11.0, 20.0):
        print(
            f"  well-mixed estimate of a source tag's change over 1 day, "
            f"tau {tau:.0f} d: {(1 / (2 * tau)) * (1 - 1 / ratio):.2%}"
        )
    print()

    # The moist baroclinic-wave sphere of C4 at t = 0, at c and 2c.
    s1 = float(rows("c4_sphere_tag_offset")[0]["total"])
    s2 = float(rows("c4_sphere_tag_offset_2x")[0]["total"])
    smass = (s2 - s1) / C0
    se = s1 / smass - C0
    print(
        f"C4 sphere at t=0: ratio {s2 / s1:.4f}; mass {smass:.4e} kg; "
        f"mean e_tot {se:.0f} J/kg; mean E_c/rho {s1 / smass:.0f} J/kg"
    )
    print()

    print("E_c against the offset in use, mass-weighted mean")
    for name, c in [("2c", 2 * C0), ("150 K rule", c_floor), ("cp_d*T0", c_abs)]:
        print(
            f"  {name:10s} D4 x{(e_mean + c) / (e_mean + C0):.2f}, "
            f"sphere x{(se + c) / (se + C0):.2f}"
        )
    print()

    # The coldest cells at t = 0 on the sphere (FINDINGS R9).
    e_x, e_t = -100416.0, -23686.0
    print("Coldest cells at t=0 (R9): E_c/rho, extratropics and tropics")
    for name, c in [("in use", C0), ("150 K rule", c_floor), ("cp_d*T0", c_abs)]:
        print(
            f"  {name:10s} {e_x + c:8.0f} and {e_t + c:8.0f} J/kg, "
            f"ratio {(e_t + c) / (e_x + c):.2f}"
        )
    print()

    # The sphere's only measured loss timescale: E74's flush, 60 to 95 days.
    print("E74's flush time scaled by the sphere's E_c ratio, and e^(-90/tau)")
    for name, c in [("in use", C0), ("150 K rule", c_floor), ("cp_d*T0", c_abs)]:
        k = (se + c) / (se + C0)
        lo, hi = 60 * k, 95 * k
        print(
            f"  {name:10s} tau {lo:5.0f} to {hi:5.0f} d; initial part left at "
            f"day 90 {math.exp(-90 / lo):.2f} to {math.exp(-90 / hi):.2f}"
        )
    print()

    # The surface-flux tag's offset part on D4 (ATTRIBUTION_PATH 3.3).
    off, flux = 3.6e5, 9.42e6
    print("Offset part of the surface-flux tag's daily production on D4")
    for name, c in [
        ("in use", C0),
        ("150 K rule", c_floor),
        ("cp_d*T0", c_abs),
        ("water 303 kJ", C0 + 193000),
    ]:
        o = off * c / C0
        print(f"  {name:10s} {o:.2e} J/m2, {o / (flux + o):.1%}")
    print()

    # Falling ice at its most negative, PrecipitatingColumn at t = 0 (E41):
    # -193 kJ/kg with c included.
    print("Most negative falling-ice energy, PrecipitatingColumn at t=0 (E41), c included")
    for name, c in [("in use", C0), ("150 K rule", c_floor), ("cp_d*T0", c_abs)]:
        print(f"  {name:10s} {-193000 + (c - C0):8.0f} J/kg")
    print(f"  turns positive at c = {C0 + 193000:.0f} J/kg")


if __name__ == "__main__":
    main()
