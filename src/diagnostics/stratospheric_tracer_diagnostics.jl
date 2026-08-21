# This file is included in Diagnostics.jl

# Tropopause height and stratospheric passive tracers.
#
# The tracer-budget callback, not these diagnostics, writes the global burden,
# source and loss that the lifetime is computed from. Those are scalars per
# tracer rather than fields (see `stratospheric_passive_tracers.jl`).
#
# The per-tracer variables are registered at simulation setup by
# `register_stratospheric_tracer_diagnostics!`, not at load time, because the
# source-region grid is configuration-dependent.

###
# Tropopause height (2d)
###
"""
    tropopause_parameters(chemistry_model)

The `TropopauseParameters` the
tropopause diagnostic should use. A model that carries its own — the
stratospheric passive tracers, whose sink is defined by it — supplies them, so
that the diagnostic reports exactly the surface the tracers see. Everything
else falls back to the defaults.
"""
tropopause_parameters(chemistry_model) = TropopauseParameters{Float64}()
tropopause_parameters(chemistry_model::StratosphericPassiveTracers) =
    chemistry_model.tropopause

"""
    compute_ztrop!(out, state, cache, time)

WMO lapse-rate tropopause height, in m. Also the lower boundary of the
stratospheric passive tracers, which are removed at and below it.
"""
function compute_ztrop!(out, state, cache, time)
    ᶜz_tropopause = cache.scratch.ᶜtemp_scalar_2
    set_tropopause_height!(
        ᶜz_tropopause,
        cache.scratch.ᶜtemp_scalar,
        cache.precomputed.ᶜT,
        tropopause_parameters(cache.atmos.chemistry_model),
    )
    # `ᶜz_tropopause` holds the same value at every level of a column, so any
    # level carries the answer. Copy the lowest one onto the surface space used
    # by the other 2d diagnostics. This goes through the data layouts because
    # the center and face level spaces are distinct objects over the same
    # horizontal grid.
    surface = cache.scratch.ᶠtemp_field_level
    Fields.field_values(surface) .=
        Fields.field_values(Fields.level(ᶜz_tropopause, 1))
    isnothing(out) && return copy(surface)
    out .= surface
    return out
end

add_diagnostic_variable!(
    short_name = "ztrop",
    long_name = "Tropopause Height",
    standard_name = "tropopause_altitude",
    units = "m",
    comments = "Height of the WMO lapse-rate (thermal) tropopause: the lowest \
                level above 5 km where the lapse rate falls to 2 K/km and the \
                mean lapse rate over the next 2 km stays below it. Columns \
                where no such level exists fall back to a latitude-dependent \
                climatology.",
    compute! = compute_ztrop!,
)

###
# Stratospheric passive tracers (3d)
###

# `ρq_gas_y01z03` -> "q_gas_y01z03"
specific_tracer_short_name(ρχ_name) =
    String(ρχ_name)[(ncodeunits("ρ") + 1):end]

"""
    compute_stratospheric_tracer(state, cache, time, Val(ρχ_name))

Mass fraction of one stratospheric passive tracer. `ρχ_name` is wrapped in a
`Val` when the diagnostic is registered, so the property lookup specializes
per tracer.
"""
function compute_stratospheric_tracer(
    state,
    cache,
    time,
    ::Val{ρχ_name},
) where {ρχ_name}
    hasproperty(state.c, ρχ_name) || error_diagnostic_variable(
        "Cannot compute $(specific_tracer_short_name(ρχ_name)): the state has \
        no $ρχ_name. The stratospheric passive tracer grid is set by \
        tracer_source_latitude_bands and tracer_source_height_bands.",
    )
    ᶜρχ = getproperty(state.c, ρχ_name)
    return @. lazy(specific(ᶜρχ, state.c.ρ))
end

"""
    register_stratospheric_tracer_diagnostics!(model::AtmosModel)

Register one `q_gas_y<i>z<k>` diagnostic per stratospheric passive tracer of
`model`, the mass fraction of the tracer fed by source region `(i, k)`.

Which tracers exist depends on the configured source-region grid, so this is
called during simulation setup rather than at package load time (see
`setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`).
Registering from the model is what lets the grid be any size: a fixed set
registered at load time would have to cap it.

A no-op unless the chemistry model is `StratosphericPassiveTracers`. Entries
that already exist are kept, since a tracer's compute function depends only on
its name.
"""
register_stratospheric_tracer_diagnostics!(model::AtmosModel) =
    register_stratospheric_tracer_diagnostics!(model.chemistry_model)
register_stratospheric_tracer_diagnostics!(_) = nothing
function register_stratospheric_tracer_diagnostics!(
    chemistry_model::StratosphericPassiveTracers,
)
    names = stratospheric_tracer_symbols(chemistry_model)
    for tracer_index in 1:n_tracers(chemistry_model)
        ρχ_name = names[tracer_index]
        short_name = specific_tracer_short_name(ρχ_name)
        # Delete rather than skip: a previous simulation in this process
        # may have registered this short name with different box edges,
        # and the stale entry would keep reporting them in its `comment`.
        delete!(ALL_DIAGNOSTICS, short_name)
        ρχ_key = Val(ρχ_name)

        # The box edges, rather than the band indices, are what identifies a
        # source region once the boxes need not form a latitude × height grid.
        latitude_lower = chemistry_model.latitude_lower_edges[tracer_index]
        latitude_upper = chemistry_model.latitude_upper_edges[tracer_index]
        height_lower = chemistry_model.height_lower_edges[tracer_index]
        height_upper = chemistry_model.height_upper_edges[tracer_index]

        add_diagnostic_variable!(;
            short_name,
            long_name = "Stratospheric Passive Tracer, Source Box \
                         $tracer_index",
            units = "kg kg^-1",
            comments = "Mass fraction of the inert tracer produced between \
                        $latitude_lower and $latitude_upper degrees latitude \
                        and between $height_lower and $height_upper m above \
                        the source reference height, and removed below the \
                        tropopause.",
            compute = (state, cache, time) ->
                compute_stratospheric_tracer(state, cache, time, ρχ_key),
        )
    end
    return nothing
end
