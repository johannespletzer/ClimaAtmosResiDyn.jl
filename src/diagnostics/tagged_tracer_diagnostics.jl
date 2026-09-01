# This file is included in Diagnostics.jl

# Tagged prognostic energy tracers
#
# Tag names come from the configuration, so the per-tag diagnostics are
# registered once the `TaggingModel` is known.
# `register_tagging_diagnostics!(model)` runs during simulation setup, from
# `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`.

function compute_e_tag!(out, state, cache, time, ρe_tag_name)
    ρe_tag_name in propertynames(state.c) ||
        error("$ρe_tag_name does not exist in the model")
    ᶜρe_tag = getproperty(state.c, ρe_tag_name)
    if isnothing(out)
        return specific.(ᶜρe_tag, state.c.ρ)
    else
        out .= specific.(ᶜρe_tag, state.c.ρ)
    end
end

function compute_e_tag_res!(out, state, cache, time, ρe_tag_names)
    ᶜres = isnothing(out) ? similar(state.c.ρe_tot) : out
    ᶜres .= state.c.ρe_tot
    for ρe_tag_name in ρe_tag_names
        ρe_tag_name in propertynames(state.c) ||
            error("$ρe_tag_name does not exist in the model")
        ᶜres .-= getproperty(state.c, ρe_tag_name)
    end
    ᶜres .= specific.(ᶜres, state.c.ρ)
    return ᶜres
end

"""
    register_tagging_diagnostics!(model::AtmosModel)

Register the diagnostics associated with the tagged prognostic energy tracers
of `model`. Their short names depend on the configured tag names, so this is
called during simulation setup rather than at package load time:

  - `e_tag_<name>`: specific tagged energy `ρe_tag_<name> / ρ`, for each tag;
  - `e_tag_res`: closure residual `(ρe_tot - Σᵢ ρe_tag_i) / ρ`, where the sum
    runs over the pure region tags (only registered when at least one exists).

A no-op when tagging is disabled. Per-tag entries that already exist in the
diagnostics catalog are kept (their compute function only depends on the tag
name); the `e_tag_res` entry is replaced, because the set of region tags it
sums over can differ between setups.
"""
register_tagging_diagnostics!(model::AtmosModel) =
    register_tagging_diagnostics!(model.tagging_model)
# Tagging is off. Leftover per-tag entries are harmless — their compute
# functions depend only on the tag name, so an unrequested one costs nothing —
# but a leftover `e_tag_res` is not, for the reason the enabled path gives
# below: it would sum over region tags that never partitioned this model's
# energy. `ALL_DIAGNOSTICS` is process-global, so this matters whenever one
# process builds more than one simulation.
function register_tagging_diagnostics!(::Nothing)
    delete!(ALL_DIAGNOSTICS, "e_tag_res")
    return nothing
end
function register_tagging_diagnostics!(tagging_model::TaggingModel)
    for tag in tagging_model.tags
        name = tag_name(tag)
        short_name = "e_tag_$name"
        haskey(ALL_DIAGNOSTICS, short_name) && continue
        ρe_tag_name = Symbol(:ρe_tag_, name)
        add_diagnostic_variable!(;
            short_name,
            units = "J kg^-1",
            long_name = "Tagged Specific Total Energy ($name)",
            comments = "Grid-mean specific energy of the tagged tracer `$name`",
            compute! = (out, u, p, t) ->
                compute_e_tag!(out, u, p, t, ρe_tag_name),
        )
    end
    region_names = region_tag_state_names(tagging_model)
    # Drop any stale entry first, then decide whether to register a new one. An
    # earlier simulation in this process may have registered `e_tag_res` over a
    # different set of region tags. If this model has none, a leftover entry
    # would report a residual summed over tags that never partitioned this
    # model's energy.
    delete!(ALL_DIAGNOSTICS, "e_tag_res")
    if !isempty(region_names)
        add_diagnostic_variable!(;
            short_name = "e_tag_res",
            units = "J kg^-1",
            long_name = "Tagged Energy Closure Residual",
            comments = "Specific total energy minus the sum of the region " *
                       "tags, (ρe_tot - Σᵢ ρe_tag_i) / ρ. Grows with the " *
                       "processes that are not attributed to tags " *
                       "(diffusion-operator differences, implicit and " *
                       "unattributed tendencies, limiters).",
            compute! = (out, u, p, t) ->
                compute_e_tag_res!(out, u, p, t, region_names),
        )
    end
    return nothing
end
