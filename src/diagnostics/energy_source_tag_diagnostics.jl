# This file is included in Diagnostics.jl

# Energy source tags
#
# Tag names come from the configuration, so the per-tag diagnostics are
# registered once the `EnergySourceTaggingModel` is known.
# `register_energy_source_tagging_diagnostics!(model)` runs during simulation
# setup, from `setup_diagnostics_and_writers` in
# `simulation/AtmosSimulations.jl`.
#
# These reuse the `e_tag_*` compute functions, which only need a state field
# name. Only the names and the wording of the metadata differ, because
# `e_src_<name>` and `e_tag_<name>` are different quantities.

"""
    register_energy_source_tagging_diagnostics!(model::AtmosModel)

Register the diagnostics of the energy source tags:

  - `e_src_<name>`: specific tagged energy `ρe_src_<name> / ρ`, for each tag;
  - `e_src_res`: closure residual `(ρe_tot - Σᵢ ρe_src_i) / ρ`, summed over the
    pure region tags (only registered when at least one exists).

A no-op when energy source tagging is disabled. Per-tag entries already in the
catalog are kept, since their compute function depends only on the tag name; the
`e_src_res` entry is replaced, because the set of region tags it sums over can
differ between setups.
"""
register_energy_source_tagging_diagnostics!(model::AtmosModel) =
    register_energy_source_tagging_diagnostics!(
        model.energy_source_tagging_model,
    )
# Source tagging is off. As for the other families, the per-tag entries can
# stay — they are keyed by tag name alone — but a stale `e_src_res` cannot: it
# would report a residual over a partition this model does not have. See the
# enabled path below, which deletes it for the same reason.
function register_energy_source_tagging_diagnostics!(::Nothing)
    delete!(ALL_DIAGNOSTICS, "e_src_res")
    return nothing
end
function register_energy_source_tagging_diagnostics!(
    model::EnergySourceTaggingModel,
)
    for tag in model.tags
        name = tag_name(tag)
        short_name = "e_src_$name"
        haskey(ALL_DIAGNOSTICS, short_name) && continue
        ρe_src_name = Symbol(:ρe_src_, name)
        add_diagnostic_variable!(;
            short_name,
            units = "J kg^-1",
            long_name = "Source-Tagged Moist Energy ($name)",
            comments = "Moist energy attributed to the tag `$name`, per " *
                       "unit mass of moist air. Reads as energy present now " *
                       "traced back to that tag only where `ρe_tot` is " *
                       "positive and this field is non-negative; elsewhere " *
                       "it is a signed attribution with no amount " *
                       "interpretation. Distinct from `e_tag_$name`, which " *
                       "is a signed record of what a process did rather " *
                       "than an amount present. Moist total energy has no " *
                       "physical zero, so this value and its share of the " *
                       "total both depend on the chosen energy reference.",
            compute! = (out, u, p, t) ->
                compute_e_tag!(out, u, p, t, ρe_src_name),
        )
    end

    region_names = energy_source_region_tag_state_names(model)
    # Drop any stale entry first, then decide whether to register a new one. An
    # earlier simulation in this process may have registered `e_src_res` over a
    # different set of region tags, which would return a wrong number and no
    # error.
    delete!(ALL_DIAGNOSTICS, "e_src_res")
    if !isempty(region_names)
        add_diagnostic_variable!(;
            short_name = "e_src_res",
            units = "J kg^-1",
            long_name = "Energy Source Tag Closure Residual",
            comments = "Moist energy minus the sum of the region source " *
                       "tags, (ρe_tot - Σᵢ ρe_src_i) / ρ. A monitored " *
                       "residual, not a machine-precision identity: ρe_tot is " *
                       "transported as enthalpy including pressure work and " *
                       "has its own diffusion treatment, while the tags ride " *
                       "the generic passive-tracer path.",
            compute! = (out, u, p, t) ->
                compute_e_tag_res!(out, u, p, t, region_names),
        )
    end
    return nothing
end
