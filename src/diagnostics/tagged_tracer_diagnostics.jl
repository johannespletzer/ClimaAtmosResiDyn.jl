# This file is included in Diagnostics.jl

# Tagged prognostic energy tracers
#
# Tag names are configuration-dependent, so the per-tag diagnostics cannot be
# registered statically when the package is loaded. Instead,
# `register_tagging_diagnostics!(model)` is called during simulation setup
# (see `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`),
# once the `TaggingModel` is known.

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
register_tagging_diagnostics!(::Nothing) = nothing
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
    if !isempty(region_names)
        delete!(ALL_DIAGNOSTICS, "e_tag_res")
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
