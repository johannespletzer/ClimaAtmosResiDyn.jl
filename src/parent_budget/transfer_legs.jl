#####
##### Parent-budget ledger: transfer legs from their own quadratures
#####
##### A transfer event moves a quantity across a boundary, and each modeled
##### side of it is measured on its own: the atmosphere's leg from the flux the
##### tendency applied at the boundary, the slab's leg from the flux the slab
##### tendency applied, each read inside the applied-update event that applied
##### it. Wherever a bracket isolates one leg, that leg is the bracket's own
##### total, what the reservoir's fields integrated: the atmosphere's side of
##### the surface flux and of precipitation, the slab's side of precipitation.
##### Where a bracket lumps several legs, radiation at the top and at the
##### surface of the atmosphere, and the slab's turbulent, radiative and
##### prescribed fluxes in one slab tendency, the legs are read from the flux
##### fields those tendencies read, and the bracket's total is kept beside
##### their sum as a check. A leg is never the negation of its counterpart.

"""
    TRANSFER_LEG_EVENTS

Which applied-update event measures each modeled leg of each transfer event,
keyed by the event id and the reservoir. The atmosphere's legs fire in the
bracket around the tendency that writes the atmosphere, the slab's in the
bracket around the slab tendency that receives them.
"""
const TRANSFER_LEG_EVENTS = Dict(
    (Symbol("xfer.surface_turbulent_flux"), ATMOSPHERE_ENDPOINT_GROUP) => :surface_flux,
    (Symbol("xfer.surface_turbulent_flux"), SLAB_SURFACE_ENDPOINT_GROUP) =>
        :surface_temperature,
    (Symbol("xfer.radiation_toa"), ATMOSPHERE_ENDPOINT_GROUP) => :radiation,
    (Symbol("xfer.radiation_surface"), ATMOSPHERE_ENDPOINT_GROUP) => :radiation,
    (Symbol("xfer.radiation_surface"), SLAB_SURFACE_ENDPOINT_GROUP) =>
        :surface_temperature,
    (Symbol("xfer.precipitation_0m"), ATMOSPHERE_ENDPOINT_GROUP) => :microphysics,
    (Symbol("xfer.precipitation_0m"), SLAB_SURFACE_ENDPOINT_GROUP) =>
        :surface_precipitation,
    (Symbol("xfer.precipitation_1m"), ATMOSPHERE_ENDPOINT_GROUP) => :precipitation,
    (Symbol("xfer.precipitation_1m"), SLAB_SURFACE_ENDPOINT_GROUP) =>
        :surface_precipitation,
    (Symbol("xfer.slab_qflux"), SLAB_SURFACE_ENDPOINT_GROUP) => :surface_temperature,
)

# The event that measures one declared leg. A leg the table does not know is a
# registry row the adapter was not written for, and is refused at setup.
function transfer_leg_event(event::Symbol, reservoir::Symbol)
    haskey(TRANSFER_LEG_EVENTS, (event, reservoir)) || error(
        "The adapter does not know which applied-update event measures the " *
        "$reservoir leg of transfer event $event.",
    )
    return TRANSFER_LEG_EVENTS[(event, reservoir)]
end

# The legs a bracket isolates, so that the leg is the bracket's own total.
const BRACKET_TOTAL_LEGS = (
    (Symbol("xfer.surface_turbulent_flux"), ATMOSPHERE_ENDPOINT_GROUP),
    (Symbol("xfer.precipitation_0m"), ATMOSPHERE_ENDPOINT_GROUP),
    (Symbol("xfer.precipitation_0m"), SLAB_SURFACE_ENDPOINT_GROUP),
    (Symbol("xfer.precipitation_1m"), ATMOSPHERE_ENDPOINT_GROUP),
    (Symbol("xfer.precipitation_1m"), SLAB_SURFACE_ENDPOINT_GROUP),
)

is_bracket_total(event::Symbol, reservoir::Symbol) =
    (event, reservoir) in BRACKET_TOTAL_LEGS

"""
    LegMeasurement

One modeled leg of one transfer event as read inside an applied-update event
at one stage, before weighting: the amounts and their arithmetic magnitudes
per quantity, and `known = false` with a `reason` when the leg could not be
read there.
"""
struct LegMeasurement
    event::Symbol
    reservoir::Symbol
    leg::Symbol
    amounts::NTuple{3, BUDGET_ACCOUNTING_TYPE}
    magnitudes::NTuple{3, BUDGET_ACCOUNTING_TYPE}
    known::Bool
    reason::Symbol
end

known_leg(event, reservoir, leg, amounts, magnitudes) =
    LegMeasurement(event, reservoir, leg, amounts, magnitudes, true, :measured)
unknown_leg(event, reservoir, leg, reason) = LegMeasurement(
    event,
    reservoir,
    leg,
    (
        zero(BUDGET_ACCOUNTING_TYPE),
        zero(BUDGET_ACCOUNTING_TYPE),
        zero(BUDGET_ACCOUNTING_TYPE),
    ),
    (
        zero(BUDGET_ACCOUNTING_TYPE),
        zero(BUDGET_ACCOUNTING_TYPE),
        zero(BUDGET_ACCOUNTING_TYPE),
    ),
    false,
    reason,
)

# ============================================================================
# Boundary quadratures
# ============================================================================

# The physical vertical component of a covariant surface flux, positive upward,
# as `surface_temp_tendency!` reads it.
upward_component(v, lg) = Geometry.WVector(v, lg).components.data.:1
abs_upward_component(v, lg) = abs(upward_component(v, lg))

# The signed integral of an upward flux over the boundary, and its magnitude.
function upward_flux_integral(field)
    lg = Fields.local_geometry_field(axes(field))
    return (
        local_boundary_integral(Base.Broadcast.broadcasted(upward_component, field, lg)),
        local_boundary_integral(
            Base.Broadcast.broadcasted(abs_upward_component, field, lg),
        ),
    )
end

# The signed integral of a scalar boundary field, and its magnitude.
function scalar_flux_integral(field)
    return (
        local_boundary_integral(field),
        local_boundary_integral(Base.Broadcast.broadcasted(abs, field)),
    )
end

# A flux integral scaled and signed, as an amount and a magnitude pair.
signed(pair, factor) = (factor * pair[1], abs(factor) * pair[2])

# The radiative flux field a flux-form mode built, on faces, positive upward.
# RRTMGP and DYCOMS keep it in the radiation cache. ISDAC builds it in scratch
# and applies its divergence at once, so it is readable only inside the
# radiation bracket; the bracket check is what guards that reading.
radiation_flux_field(p, ::RRTMGPI.AbstractRRTMGPMode, _) = p.radiation.ᶠradiation_flux
radiation_flux_field(p, ::RadiationDYCOMS, _) = p.radiation.ᶠradiation_flux
radiation_flux_field(p, ::RadiationISDAC, inside_radiation::Bool) =
    inside_radiation ? p.scratch.ᶠtemp_scalar : nothing
radiation_flux_field(p, _, _) = nothing

# The upward radiative flux at one face level as a scalar boundary field.
function radiation_level(flux, level)
    layer = Fields.level(flux, level)
    return eltype(layer) <: Geometry.AxisVector ? layer.components.data.:1 : layer
end

surface_level(Y) = half
top_level(Y) = Spaces.nlevels(axes(Y.c)) + half

# ============================================================================
# The legs each applied-update event measures
# ============================================================================

"""
    transfer_leg_measurements(schema, event, Yₜ, Y, p, surface_temperature,
                              moist, bracket) -> Vector{LegMeasurement}

Every declared leg of every transfer event that the applied-update `event`
measures, read from the flux fields inside it. `bracket` is the bracket's own
total in the leg's reservoir, `(amounts, magnitudes)` for the atmosphere and
for the slab, which is the leg for a volume sink. Legs the configuration does
not declare are not measured, and a declared leg that cannot be read here is
returned unknown with its reason.
"""
function transfer_leg_measurements(
    schema::BudgetSchema,
    event::Symbol,
    Yₜ,
    Y,
    p,
    surface_temperature,
    moist::Bool,
    bracket,
)
    legs = LegMeasurement[]
    for spec in schema.transfer_events
        for (reservoir, name) in spec.modeled_legs
            transfer_leg_event(spec.name, reservoir) === event || continue
            push!(
                legs,
                leg_measurement(
                    spec.name,
                    reservoir,
                    name,
                    Yₜ,
                    Y,
                    p,
                    surface_temperature,
                    moist,
                    bracket,
                ),
            )
        end
    end
    return legs
end

const FLUX = :flux
const NO_MASS = zero(BUDGET_ACCOUNTING_TYPE)

function leg_measurement(
    event::Symbol,
    reservoir::Symbol,
    name::Symbol,
    Yₜ,
    Y,
    p,
    surface_temperature,
    moist::Bool,
    bracket,
)
    FT = BUDGET_ACCOUNTING_TYPE
    zero3 = (zero(FT), zero(FT), zero(FT))
    sfc = p.precomputed.sfc_conditions
    if (event, reservoir) in BRACKET_TOTAL_LEGS
        amounts, magnitudes = bracket[reservoir]
        return known_leg(event, reservoir, name, amounts, magnitudes)
    end
    if event === Symbol("xfer.surface_turbulent_flux")
        # The slab's side, from the fluxes its tendency subtracts: positive
        # upward, so an upward flux is a slab loss. The water flux carries the
        # same mass.
        sign = -one(FT)
        energy = signed(upward_flux_integral(sfc.ρ_flux_h_tot), sign)
        water =
            moist ? signed(upward_flux_integral(sfc.ρ_flux_q_tot), sign) :
            (NO_MASS, NO_MASS)
        return known_leg(
            event,
            reservoir,
            name,
            (water[1], water[1], energy[1]),
            (water[2], water[2], energy[2]),
        )
    end
    if event === Symbol("xfer.radiation_toa")
        flux = radiation_flux_field(p, p.atmos.radiation_mode, true)
        isnothing(flux) && return unknown_leg(event, reservoir, name, :flux_not_stored)
        energy = signed(scalar_flux_integral(radiation_level(flux, top_level(Y))), -one(FT))
        return known_leg(
            event,
            reservoir,
            name,
            (NO_MASS, NO_MASS, energy[1]),
            (NO_MASS, NO_MASS, energy[2]),
        )
    end
    if event === Symbol("xfer.radiation_surface")
        inside_radiation = reservoir === ATMOSPHERE_ENDPOINT_GROUP
        flux = radiation_flux_field(p, p.atmos.radiation_mode, inside_radiation)
        isnothing(flux) && return unknown_leg(event, reservoir, name, :flux_not_stored)
        sign = inside_radiation ? one(FT) : -one(FT)
        energy = signed(scalar_flux_integral(radiation_level(flux, surface_level(Y))), sign)
        return known_leg(
            event,
            reservoir,
            name,
            (NO_MASS, NO_MASS, energy[1]),
            (NO_MASS, NO_MASS, energy[2]),
        )
    end
    if event === Symbol("xfer.slab_qflux")
        energy = signed(scalar_flux_integral(slab_q_flux(Y, surface_temperature)), -one(FT))
        return known_leg(
            event,
            reservoir,
            name,
            (NO_MASS, NO_MASS, energy[1]),
            (NO_MASS, NO_MASS, energy[2]),
        )
    end
    return error("The adapter has no quadrature for the $reservoir leg of $event.")
end
