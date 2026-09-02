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

`Y.c.ρ` is moist air density. It carries water vapour and cloud condensate but
**not** rain or snow: every tendency that changes `ρq_tot` changes `ρ` by the
same amount, and nothing adds `ρq_rai` or `ρq_sno` to it. Precipitation
formation is therefore a genuine mass sink for the atmosphere even though it is
internal to the water budget.

One consequence is worth stating where it cannot be missed. `M - W` is **not**
the dry-air mass in this model, because `W` includes precipitating water that
`M` never had. The dry-air invariant is [`atmosphere_dry_mass`](@ref).
"""
atmosphere_mass(Y) = sum(Y.c.ρ)

"""
    atmosphere_water(Y)

Total atmospheric water ``\\int (\\rho q_{tot} + \\rho q_{rai} + \\rho q_{sno})`` [kg].

The included categories must not overlap. `ρq_tot` is total water, vapour plus
cloud condensate. `ρq_lcl` and `ρq_icl` are the liquid and ice contents
*already inside* `ρq_tot`, so adding them would double-count the condensate and
they are deliberately absent here. `ρq_rai` and `ρq_sno` are outside `ρq_tot`
and are added when the microphysics model carries them.

Returns zero for a dry model, which has no water state at all.
"""
function atmosphere_water(Y)
    FT = Spaces.undertype(axes(Y.c))
    hasproperty(Y.c, :ρq_tot) || return zero(FT)
    water = sum(Y.c.ρq_tot)
    hasproperty(Y.c, :ρq_rai) && (water += sum(Y.c.ρq_rai))
    hasproperty(Y.c, :ρq_sno) && (water += sum(Y.c.ρq_sno))
    return water
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

This, and not `M - W`, is the derived invariant to test. See
[`atmosphere_mass`](@ref) for why.

Equals [`atmosphere_mass`](@ref) for a dry model.
"""
function atmosphere_dry_mass(Y)
    hasproperty(Y.c, :ρq_tot) || return atmosphere_mass(Y)
    return sum(Y.c.ρ) - sum(Y.c.ρq_tot)
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

Always `nothing`. No surface reservoir in this model owns mass.

The method exists so that the endpoint code can ask every reservoir for every
quantity and get an explicit answer, rather than the caller remembering which
combinations are meaningless.
"""
surface_mass(Y, ::SurfaceConditions.SurfaceTemperature) = nothing
