#####
##### Parent-budget ledger: the authoritative integrals
#####
##### These are the endpoint quantities the ledger reconciles against. They are
##### defined once here and used for both ends of every transaction, so a
##### change of definition cannot be applied to one end and not the other.
#####
##### All are linear extensive functionals of authoritative prognostic state,
##### which is what makes exact additive process attribution well defined. That
##### is a property of these particular integrals, so changing one reopens the
##### question. See `docs/src/parent_budget/contract.md`.

import ClimaCore.Fields as Fields
import ClimaCore.Spaces as Spaces

"""
    atmosphere_mass(Y)

Total modeled atmospheric mass ``\\int \\rho`` [kg].

`Y.c.ρ` is moist air density, and it carries the whole of `ρq_tot`, which
includes precipitating water. Every path that changes one changes the other by
the same amount: 0-moment removal, sedimentation, the surface flux, the viscous
sponge, and `enforce_mass_energy_consistency!`. That is what makes
[`atmosphere_dry_mass`](@ref) a meaningful derived invariant.
"""
atmosphere_mass(Y) = sum(Y.c.ρ)

"""
    atmosphere_water(Y)

Total atmospheric water ``\\int \\rho q_{tot}`` [kg].

`ρq_tot` is total water and it already contains precipitation. The
thermodynamic state is built from `q_liq = q_lcl + q_rai` and
`q_ice = q_icl + q_sno`, with `q_tot ≥ q_liq + q_ice`, so rain and snow sit
inside `q_tot` exactly as cloud water does.

The category fields therefore **partition** this integral and are never added to
it. `ρq_lcl`, `ρq_icl`, `ρq_rai` and `ρq_sno` are all deliberately absent here:
adding any of them would invent water every time cloud condensate became rain,
because one-moment microphysics moves the categories while applying no source at
all to `ρq_tot`.

Returns zero for a dry model, which has no water state.
"""
function atmosphere_water(Y)
    FT = Spaces.undertype(axes(Y.c))
    hasproperty(Y.c, :ρq_tot) || return zero(FT)
    return sum(Y.c.ρq_tot)
end

"""
    atmosphere_energy(Y)

Total atmospheric energy ``\\int \\rho e_{tot}`` [J].

Total energy is prognostic, so this is authoritative and nothing is
reconstructed from momentum and thermodynamic state. `ρtke`, the tagged tracers
`ρe_tag_*`, the source tags `ρe_src_*`, and the process records `prc_e_*` are
all excluded: they are diagnostics *of* the energy, not additional energy.
"""
atmosphere_energy(Y) = sum(Y.c.ρe_tot)

"""
    atmosphere_dry_mass(Y)

Dry-air mass ``\\int (\\rho - \\rho q_{tot})`` [kg].

Equivalently `atmosphere_mass(Y) - atmosphere_water(Y)`, because `ρ` carries the
whole of `ρq_tot`. It is written as one integral rather than a difference of two
global reductions so that the cancellation happens pointwise, where it is exact,
instead of between two large sums.

This is a derived invariant. Testing it is how the mass and water budgets are
checked against each other, rather than one being assumed from the other.

Equals [`atmosphere_mass`](@ref) for a dry model.
"""
function atmosphere_dry_mass(Y)
    hasproperty(Y.c, :ρq_tot) || return atmosphere_mass(Y)
    return sum(Y.c.ρ .- Y.c.ρq_tot)
end

"""
    slab_heat_capacity(slab)

Areal heat capacity ``\\rho_{ocean} c_{p,ocean} d_{ocean}`` [J m⁻² K⁻¹] of a
`SurfaceConditions.SlabOceanTemperature`.

Constant, which is what makes [`surface_energy`](@ref) linear in `Y.sfc.T`.
"""
slab_heat_capacity(slab::SurfaceConditions.SlabOceanTemperature) =
    slab.ρ_ocean * slab.cp_ocean * slab.depth_ocean

"""
    surface_energy(Y, surface_temperature)

Energy held by the prognostic surface reservoir [J], or `nothing` when there is
none.

Only a `SurfaceConditions.SlabOceanTemperature` owns surface energy. Every
other surface temperature is prescribed or diagnosed, which makes it exterior
to the model rather than a reservoir of it, so a flux into it is a boundary
crossing.

`nothing` and zero are different answers here, and the caller must keep them
apart: zero would be an energy the ledger has to reconcile, `nothing` is a
reservoir that does not exist.
"""
surface_energy(Y, ::SurfaceConditions.SurfaceTemperature) = nothing
surface_energy(Y, slab::SurfaceConditions.SlabOceanTemperature) =
    horizontal_integral_at_boundary(Y.sfc.T) * slab_heat_capacity(slab)

"""
    surface_water(Y, surface_temperature)

Water held by the prognostic surface reservoir [kg], or `nothing` when there is
none.

Present only for a `SurfaceConditions.SlabOceanTemperature` in a moist
configuration, where `Y.sfc.water` accumulates precipitation and evaporation.

This reservoir owns water and owns **no mass**. Water deposited on the slab
leaves [`atmosphere_mass`](@ref) and enters this integral, so one physical
event has a mass leg and a water leg that are not the same leg. It is the
clearest case in this model of the rule that a water increment may never be
copied into mass.
"""
surface_water(Y, ::SurfaceConditions.SurfaceTemperature) = nothing
function surface_water(Y, ::SurfaceConditions.SlabOceanTemperature)
    hasproperty(Y, :sfc) || return nothing
    hasproperty(Y.sfc, :water) || return nothing
    return horizontal_integral_at_boundary(Y.sfc.water)
end

"""
    surface_mass(Y, surface_temperature)

Mass held by the prognostic surface reservoir [kg], or `nothing` when there is
none.

Equal to [`surface_water`](@ref), and that is a measured property of this
reservoir rather than an inference. What the slab gains left the atmosphere as
`ρq_tot`, and `ρ` carries the whole of `ρq_tot`, so the same deposition is a
mass leg and a water leg of the same size. The existing `check_conservation`
relies on this too: it adds the change in surface water to the change in
``\\int \\rho`` before calling mass closed.

Everywhere else the rule stands that a water increment is never copied into
mass. The two legs are still recorded independently, so a path where they
diverge shows up rather than being defined away.
"""
surface_mass(Y, ::SurfaceConditions.SurfaceTemperature) = nothing
surface_mass(Y, slab::SurfaceConditions.SlabOceanTemperature) =
    surface_water(Y, slab)
