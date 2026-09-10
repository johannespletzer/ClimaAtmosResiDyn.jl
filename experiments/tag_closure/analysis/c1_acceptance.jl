#=
C1's acceptance test, with the parameters built the way a run builds them.

`toml/tag_closure_c1_reference.toml` moves the thermodynamic reference
temperature and two latent heats together. The claim is that this changes the
energy reference and nothing else. This script tests that claim in
Thermodynamics, on the parameter set a run with `toml:` pointing at that file
would use:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/c1_acceptance.jl

The parameters are built as `AtmosConfig` builds them, in
`src/config/atmos_config.jl:161-167`: `CP.merge_toml_files` over the `toml:`
list, then `CP.create_toml_dict(FT; override_file)`. So an entry that would not
bind in a run does not bind here either.

The acceptance test written into the TOML's header cannot do this, for two
reasons. It does `import Thermodynamics`, which `.buildkite` does not list as a
direct dependency, so it stops at `Package Thermodynamics not found`. And past
that, it builds `ThermodynamicsParameters(Float64)`, which reads the ClimaParams
defaults and never opens the override file. So it would print the unshifted
values whatever the file says.

## What it checks

 1. The three entries bound, and nothing else moved. `T_triple` stays at
    273.16 and `T_freeze` at 273.15, and every heat capacity is unchanged.
 2. Every latent heat and every saturation vapour pressure is unchanged at every
    temperature from 150 K to 330 K. The three before-values recorded in
    `C1_reference_shift.md` are three of those points.
 3. Each specific internal energy moves by what the map predicts. Dry air moves
    by `cp_d·|δ|`. Vapour, liquid and ice all move by `cp_l·|δ|`, because the
    co-adjusted latent heats cancel each phase's own heat capacity.
 4. `total_energy` on moist states moves by `((1 - q_tot)·cp_d + q_tot·cp_l)·|δ|`.
 5. `air_temperature` inverts the shifted energy back to the same temperature.
    That inverse is how a run gets `T` from `ρe_tot`.
 6. The surface energy flux per unit evaporation moves by `cp_l·|δ|`, the same
    as the vapour it adds. That is the amount a relabelling needs, because the
    model also adds the evaporated mass to `ρ` (`surface_flux.jl`). The flux is
    `shf + lhf` from SurfaceFluxes, whose evaporation part is
    `(vapor_static_energy + LH_v0)·E`.

It exits non-zero if any check fails.

## What it cannot check

Whether every model term that moves energy together with water uses the same
reference. Checks 3 and 6 cover the 0M precipitation sink and the surface flux,
because both are built from these functions. Hyperdiffusion, the implicit
solver's Jacobian and any other path are not covered. Only two runs compared
field by field can show that the shift changes no physical state.
=#

import ClimaParams as CP

# Thermodynamics is not a direct dependency of `.buildkite`, so it is reached
# through ClimaAtmos. That is also the copy a run uses.
import ClimaAtmos as CA
const TD = CA.TD
const TP = CA.TD.Parameters

const REPO = normpath(joinpath(@__DIR__, "..", "..", ".."))
const SHIFT_TOML = joinpath(REPO, "toml", "tag_closure_c1_reference.toml")

# The shift the TOML is written for, in kelvin. Every expected value below is
# derived from it and from the unshifted parameters, and none is typed in.
const δ = -110.0

# Latent heats, energies and pressures are compared relative to their size. The
# shifted and unshifted values are computed through different intermediate
# numbers, so they agree to rounding and not bit for bit.
const RTOL = 1e-12

"""
    thermodynamics_parameters(toml_files)

The thermodynamic parameters a run with `toml: toml_files` would use.

Built exactly as `AtmosConfig` builds them, so a mistyped table header is left
at its default here just as it would be in a run.
"""
function thermodynamics_parameters(toml_files)
    override_file = CP.merge_toml_files(toml_files)
    toml_dict = CP.create_toml_dict(Float64; override_file)
    return TP.ThermodynamicsParameters(toml_dict)
end

const FAILED = String[]

"""
    report(label, ok, detail)

Print one check's outcome and remember it if it failed.
"""
function report(label, ok, detail)
    println(rpad(ok ? "ok" : "FAIL", 6), rpad(label, 44), detail)
    ok || push!(FAILED, label)
    return ok
end

relative_change(before, after) = abs(after - before) / abs(before)

"""
    worst_relative_change(f, base, shifted, temperatures)

The largest relative change of `f(params, T)` over `temperatures`, and the
temperature where it occurs.
"""
function worst_relative_change(f, base, shifted, temperatures)
    changes = [relative_change(f(base, T), f(shifted, T)) for T in temperatures]
    worst, i = findmax(changes)
    return worst, temperatures[i]
end

function main()
    isfile(SHIFT_TOML) || error("The shift file is not there: $SHIFT_TOML")
    base = thermodynamics_parameters(String[])
    shifted = thermodynamics_parameters([SHIFT_TOML])

    cp_d = TP.cp_d(base)
    cp_v = TP.cp_v(base)
    cp_l = TP.cp_l(base)
    cp_i = TP.cp_i(base)
    shift_dry = -cp_d * δ
    shift_water = -cp_l * δ

    println("C1 acceptance test for $(relpath(SHIFT_TOML, REPO)), δ = $δ K")
    println()

    println("1. The entries bound, and nothing else moved")
    bound = (
        ("T_0", TP.T_0, TP.T_0(base) + δ),
        ("LH_v0", TP.LH_v0, TP.LH_v0(base) + (cp_v - cp_l) * δ),
        ("LH_s0", TP.LH_s0, TP.LH_s0(base) + (cp_v - cp_i) * δ),
    )
    for (name, getter, expected) in bound
        value = getter(shifted)
        report(
            "$name moved to its target",
            isapprox(value, expected; atol = 1e-9),
            "$(getter(base)) -> $value, target $expected",
        )
    end
    # LH_f0 is derived as LH_s0 - LH_v0, so it is not in the TOML. The map
    # needs it to move by (cp_l - cp_i)·δ, and it gets that for free.
    report(
        "LH_f0 followed without being set",
        isapprox(
            TP.LH_f0(shifted),
            TP.LH_f0(base) + (cp_l - cp_i) * δ;
            atol = 1e-9,
        ),
        "$(TP.LH_f0(base)) -> $(TP.LH_f0(shifted))",
    )
    untouched = (
        ("T_triple", TP.T_triple),
        ("T_freeze", TP.T_freeze),
        ("press_triple", TP.press_triple),
        ("R_d", TP.R_d),
        ("R_v", TP.R_v),
        ("cp_d", TP.cp_d),
        ("cp_v", TP.cp_v),
        ("cp_l", TP.cp_l),
        ("cp_i", TP.cp_i),
    )
    for (name, getter) in untouched
        report(
            "$name unchanged",
            getter(shifted) == getter(base),
            "$(getter(base)) -> $(getter(shifted))",
        )
    end
    println()

    println("2. Latent heats and saturation pressures, 150 K to 330 K")
    temperatures = collect(150.0:0.5:330.0)
    invariants = (
        ("LH_v", TD.latent_heat_vapor),
        ("LH_s", TD.latent_heat_sublim),
        ("LH_f", TD.latent_heat_fusion),
        ("p_sat over liquid", (p, T) -> TD.saturation_vapor_pressure(p, T, TD.Liquid())),
        ("p_sat over ice", (p, T) -> TD.saturation_vapor_pressure(p, T, TD.Ice())),
        ("p_sat over the mixture ramp", TD.saturation_vapor_pressure),
    )
    for (name, f) in invariants
        worst, at = worst_relative_change(f, base, shifted, temperatures)
        report("$name unchanged", worst <= RTOL, "worst relative change $worst at $at K")
    end
    # The three before-values recorded in C1_reference_shift.md, read back.
    recorded = (
        ("LH_v(288.3) recorded value", TD.latent_heat_vapor(shifted, 288.3), 2.46564492e6),
        ("LH_f(273.16) recorded value", TD.latent_heat_fusion(shifted, 273.16), 333600.0),
        (
            "p_sat(288.3) recorded value",
            TD.saturation_vapor_pressure(shifted, 288.3, TD.Liquid()),
            1721.1532852305072,
        ),
    )
    for (name, value, before) in recorded
        report(
            name,
            relative_change(before, value) <= RTOL,
            "recorded $before, shifted $value",
        )
    end
    println()

    println("3. Each phase's internal energy moves by the predicted amount")
    phases = (
        ("dry air", TD.internal_energy_dry, shift_dry),
        ("vapour", TD.internal_energy_vapor, shift_water),
        ("liquid", TD.internal_energy_liquid, shift_water),
        ("ice", TD.internal_energy_ice, shift_water),
    )
    for (name, f, expected) in phases
        moves = [f(shifted, T) - f(base, T) for T in temperatures]
        worst = maximum(abs.(moves .- expected)) / expected
        report(
            "$name moves by $(round(expected; digits = 3))",
            worst <= RTOL,
            "measured $(moves[1]) at $(temperatures[1]) K, worst relative miss $worst",
        )
    end
    # The recorded before-value, and the after-value LEVANTE_TASKS.md quotes.
    e_dry = TD.internal_energy_dry(shifted, 288.3)
    report(
        "internal_energy_dry(288.3) after",
        isapprox(e_dry, 42961.03; atol = 1e-6),
        "-67533.97 -> $e_dry",
    )
    println()

    # T, q_tot, q_liq, q_ice, z. Dry, moist, saturated with liquid, mixed
    # phase, and cold, so that every phase's term is exercised.
    states = (
        (220.0, 0.0, 0.0, 0.0, 12000.0),
        (288.3, 0.00945, 0.0, 0.0, 25.0),
        (300.0, 0.018, 0.0, 0.0, 0.0),
        (285.0, 0.012, 0.0015, 0.0, 800.0),
        (265.0, 0.004, 0.0004, 0.0003, 3000.0),
        (235.0, 0.0006, 0.0, 0.0002, 8000.0),
    )
    e_kin = 12.5

    println("4. total_energy moves by ((1 - q_tot)·cp_d + q_tot·cp_l)·|δ|")
    for (T, q_tot, q_liq, q_ice, z) in states
        e_pot = 9.81 * z
        before = TD.total_energy(base, e_kin, e_pot, T, q_tot, q_liq, q_ice)
        after = TD.total_energy(shifted, e_kin, e_pot, T, q_tot, q_liq, q_ice)
        expected = -((1 - q_tot) * cp_d + q_tot * cp_l) * δ
        miss = abs((after - before) - expected) / expected
        report(
            "T = $T, q_tot = $q_tot",
            miss <= RTOL,
            "moved $(after - before), expected $expected",
        )
    end
    println()

    println("5. air_temperature inverts the shifted energy to the same T")
    for (T, q_tot, q_liq, q_ice, _) in states
        e_int = TD.total_energy(shifted, 0.0, 0.0, T, q_tot, q_liq, q_ice)
        T_back = TD.air_temperature(shifted, e_int, q_tot, q_liq, q_ice)
        report(
            "T = $T, q_tot = $q_tot",
            relative_change(T, T_back) <= RTOL,
            "returned $T_back",
        )
    end
    println()

    println("6. Surface energy flux per unit evaporation moves by cp_l·|δ|")
    for (T_sfc, z) in ((300.0, 0.0), (271.0, 0.0), (288.3, 25.0))
        e_pot = 9.81 * z
        per_kg(p) = TD.vapor_static_energy(p, T_sfc, e_pot) + TP.LH_v0(p)
        moved = per_kg(shifted) - per_kg(base)
        report(
            "T_sfc = $T_sfc",
            abs(moved - shift_water) / shift_water <= RTOL,
            "moved $moved, expected $shift_water",
        )
    end
    # The dry part of the sensible heat flux is a difference of dry static
    # energies, so the reference cancels in it.
    ΔDSE(p) =
        TD.dry_static_energy(p, 290.0, 9.81 * 20) - TD.dry_static_energy(p, 300.0, 0.0)
    report(
        "the sensible-heat difference is unchanged",
        relative_change(ΔDSE(base), ΔDSE(shifted)) <= RTOL,
        "$(ΔDSE(base)) -> $(ΔDSE(shifted))",
    )
    println()

    if isempty(FAILED)
        println("All checks passed. The shift moves the energy reference and, as far")
        println("as Thermodynamics can say, nothing else.")
    else
        println("$(length(FAILED)) check(s) failed:")
        foreach(label -> println("  ", label), FAILED)
        exit(1)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
