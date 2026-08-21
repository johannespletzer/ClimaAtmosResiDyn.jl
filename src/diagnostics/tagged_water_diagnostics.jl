# This file is included in Diagnostics.jl

# Tagged prognostic water tracers
#
# As for the energy tags, tag names are configuration-dependent, so the per-tag
# diagnostics cannot be registered statically when the package is loaded.
# `register_water_tagging_diagnostics!(model)` is called during simulation setup
# (see `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`), once
# the `WaterTaggingModel` is known.
#
# Naming note: this repo's `hus` diagnostic is called "Specific Humidity" but
# computes `ρq_tot / ρ`, i.e. the mass of *all* water phases (`husv` is the
# vapor-only counterpart). The tagged names below do not inherit that ambiguity:
# `q_tag_*` is explicitly total water and `qv_tag_*` is explicitly vapor.

function compute_q_tag!(out, state, cache, time, ρq_tag_name)
    ρq_tag_name in propertynames(state.c) ||
        error("$ρq_tag_name does not exist in the model")
    ᶜρq_tag = getproperty(state.c, ρq_tag_name)
    if isnothing(out)
        return specific.(ᶜρq_tag, state.c.ρ)
    else
        out .= specific.(ᶜρq_tag, state.c.ρ)
    end
end

# Vapor share of a tag under the assumption that the phases are well mixed
# within a grid cell: qv_tag = q_tag * q_v / q_t. With 0-moment microphysics
# q_liq and q_ice are the saturation-adjustment diagnosis of the *grid mean*, so
# there is no per-tag phase information available to do better than this.
# `water_tag_fraction` supplies the guarded quotient and the dry-cell fallback.
@inline function _qv_tag(ρq_tag, ρ, ρq_tot, q_liq, q_ice)
    ρq_vap = max(ρq_tot - ρ * (q_liq + q_ice), zero(ρ))
    return specific(ρq_tag, ρ) * water_tag_fraction(ρq_vap, ρq_tot)
end

function compute_qv_tag!(out, state, cache, time, ρq_tag_name)
    ρq_tag_name in propertynames(state.c) ||
        error("$ρq_tag_name does not exist in the model")
    ᶜρq_tag = getproperty(state.c, ρq_tag_name)
    (; ᶜq_liq, ᶜq_ice) = cache.precomputed
    if isnothing(out)
        return _qv_tag.(ᶜρq_tag, state.c.ρ, state.c.ρq_tot, ᶜq_liq, ᶜq_ice)
    else
        out .= _qv_tag.(ᶜρq_tag, state.c.ρ, state.c.ρq_tot, ᶜq_liq, ᶜq_ice)
    end
end

function compute_q_tag_res!(out, state, cache, time, ρq_tag_names)
    ᶜres = isnothing(out) ? similar(state.c.ρq_tot) : out
    ᶜres .= state.c.ρq_tot
    for ρq_tag_name in ρq_tag_names
        ρq_tag_name in propertynames(state.c) ||
            error("$ρq_tag_name does not exist in the model")
        ᶜres .-= getproperty(state.c, ρq_tag_name)
    end
    ᶜres .= specific.(ᶜres, state.c.ρ)
    return ᶜres
end

function compute_q_tag_fix!(out, state, cache, time, ρq_tag_name)
    ᶜfix = getproperty(cache.tagging.ᶜwater_fix, ρq_tag_name)
    if isnothing(out)
        return specific.(ᶜfix, state.c.ρ)
    else
        out .= specific.(ᶜfix, state.c.ρ)
    end
end

"""
    register_water_tagging_diagnostics!(model::AtmosModel)

Register the diagnostics associated with the tagged prognostic water tracers of
`model`. Their short names depend on the configured tag names, so this is called
during simulation setup rather than at package load time:

  - `q_tag_<name>`: tagged **total** water `ρq_tag_<name> / ρ`, for each tag;

  - `qv_tag_<name>`: tagged **vapor**, `q_tag_<name> * q_v / q_t`, under the
    assumption that the phases are well mixed within a grid cell;

  - `q_tag_res`: closure residual `(ρq_tot - Σᵢ ρq_tag_i) / ρ`, where the sum
    runs over the pure region tags (only registered when at least one exists);

  - `q_tag_fix_<name>`: water that the limiters and state constraints have moved
    into or out of each tag, cumulative since the start of the simulation
    segment. It separates "the numerics moved water" from "the transport
    operators disagree", which `q_tag_res` alone would conflate.

    Two mechanisms write to it. `repair_water_tag_partition!` runs every step
    from `constrain_state!` and contributes whenever transport has driven a
    partition tag negative, so this is generally nonzero even under stock
    settings. `rescale_water_tags!` contributes only when a limiter or state
    constraint actually corrects `ρq_tot`, which requires one of
    `apply_sem_quasimonotone_limiter: true`,
    `tracer_nonnegativity_method: vertical_water_borrowing`, an elementwise
    tracer nonnegativity constraint, or a `PrescribedFlow` setup; with none of
    those configured, everything recorded here is partition repair.

A no-op when water tagging is disabled. Per-tag entries that already exist in the
diagnostics catalog are kept (their compute function only depends on the tag
name); the `q_tag_res` entry is always dropped and re-registered, because the set
of region tags it sums over can differ between setups — including differing to
*empty*, in which case no new entry replaces the stale one.
"""
register_water_tagging_diagnostics!(model::AtmosModel) =
    register_water_tagging_diagnostics!(model.water_tagging_model)
register_water_tagging_diagnostics!(::Nothing) = nothing
function register_water_tagging_diagnostics!(model::WaterTaggingModel)
    for tag in model.tags
        name = tag_name(tag)
        ρq_tag_name = Symbol(:ρq_tag_, name)

        short_name = "q_tag_$name"
        if !haskey(ALL_DIAGNOSTICS, short_name)
            add_diagnostic_variable!(;
                short_name,
                units = "kg kg^-1",
                long_name = "Tagged Total Water Content ($name)",
                comments = "Grid-mean mass of all water phases carried by the " *
                           "tag `$name`, per unit mass of moist air. Not to be " *
                           "confused with vapor: see `qv_tag_$name`.",
                compute! = (out, u, p, t) ->
                    compute_q_tag!(out, u, p, t, ρq_tag_name),
            )
        end

        short_name = "qv_tag_$name"
        if !haskey(ALL_DIAGNOSTICS, short_name)
            add_diagnostic_variable!(;
                short_name,
                units = "kg kg^-1",
                long_name = "Tagged Water Vapor Content ($name)",
                comments = "Vapor share of the tag `$name`, computed as " *
                           "q_tag * q_v / q_t. This assumes the water phases " *
                           "are well mixed within a grid cell: the tags " *
                           "partition total water, so they carry no phase " *
                           "information of their own. Attribution assumption, " *
                           "not a model prognostic.",
                compute! = (out, u, p, t) ->
                    compute_qv_tag!(out, u, p, t, ρq_tag_name),
            )
        end

        short_name = "q_tag_fix_$name"
        if !haskey(ALL_DIAGNOSTICS, short_name)
            add_diagnostic_variable!(;
                short_name,
                units = "kg kg^-1",
                long_name = "Cumulative Tagged Water Numerical Correction ($name)",
                comments = "Water moved into (positive) or out of (negative) " *
                           "the tag `$name` by the tracer limiters and state " *
                           "constraints, following the parent `ρq_tot` " *
                           "correction. Cumulative since the start of the " *
                           "simulation segment and reset on restart, so a " *
                           "budget over an interval is the difference of two " *
                           "outputs, and a time average of this variable is " *
                           "not meaningful. Identically zero unless a tracer " *
                           "limiter or nonnegativity constraint is configured " *
                           "(see `register_water_tagging_diagnostics!`). Each " *
                           "increment is accumulated at its own step's density " *
                           "and divided by the current density here, so this " *
                           "is not exactly the sum of the per-step specific " *
                           "corrections.",
                compute! = (out, u, p, t) ->
                    compute_q_tag_fix!(out, u, p, t, ρq_tag_name),
            )
        end
    end

    region_names = water_region_tag_state_names(model)
    # Drop any stale entry unconditionally, before deciding whether to register
    # a new one. An earlier simulation in this process may have registered
    # `q_tag_res` over a different set of region tags; if this model has none
    # (every tag carries a `source`), leaving that entry behind would let a
    # config request a "closure residual" computed over tags that are not a
    # partition of this model's water — a wrong number rather than an error.
    delete!(ALL_DIAGNOSTICS, "q_tag_res")
    if !isempty(region_names)
        add_diagnostic_variable!(;
            short_name = "q_tag_res",
            units = "kg kg^-1",
            long_name = "Tagged Water Closure Residual",
            comments = "Total water minus the sum of the region tags, " *
                       "(ρq_tot - Σᵢ ρq_tag_i) / ρ. Nonzero because the tags " *
                       "are advected vertically on the explicit passive-tracer " *
                       "path while ρq_tot is advected implicitly with a " *
                       "post-Newton upwind correction; their diffusion and " *
                       "hyperdiffusion operators, by contrast, are identical. " *
                       "Subtract `q_tag_fix_*` to isolate operator " *
                       "disagreement from numerical corrections.",
            compute! = (out, u, p, t) ->
                compute_q_tag_res!(out, u, p, t, region_names),
        )
    end
    return nothing
end
