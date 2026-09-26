# This file is included in Diagnostics.jl

# Tagged prognostic water tracers
#
# Tag names come from the configuration, as they do for the energy tags, so the
# per-tag diagnostics are registered once the `WaterTaggingModel` is known.
# `register_water_tagging_diagnostics!(model)` runs during simulation setup,
# from `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`.
#
# A note on naming. This repo's `hus` diagnostic is labelled "Specific Humidity"
# and computes `ρq_tot / ρ`, the mass of all water phases, while `husv` is the
# vapor-only counterpart. The tagged names are explicit instead: `q_tag_*` is
# total water and `qv_tag_*` is vapor.

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

# Vapor share of a tag, `qv_tag = q_tag * q_v / q_t`, assuming the phases are
# well mixed within a grid cell. With 0-moment microphysics, `q_liq` and `q_ice`
# come from saturation adjustment of the grid mean, so the grid cell is the
# finest phase information available. `water_tag_fraction` supplies the guarded
# quotient and the dry-cell fallback.
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

function compute_q_tag_upfix!(out, state, cache, time, ρq_tag_name)
    ᶜupfix = getproperty(cache.tagging.ᶜwater_upfix, ρq_tag_name)
    if isnothing(out)
        return specific.(ᶜupfix, state.c.ρ)
    else
        out .= specific.(ᶜupfix, state.c.ρ)
    end
end

function compute_q_tag_copy_res!(out, state, cache, time)
    ᶜresidual = cache.tagging.ᶜwater_copy_residual
    if isnothing(out)
        return copy(ᶜresidual)
    else
        out .= ᶜresidual
    end
end

function compute_q_tag_leak!(out, state, cache, time, path)
    if isnothing(out)
        return water_tag_leak!(similar(state.c.ρ), state, cache, path)
    else
        water_tag_leak!(out, state, cache, path)
    end
end

# What each leak diagnostic's path is, for its long name and comment.
const WATER_TAG_LEAK_DESCRIPTIONS = (;
    vdiff = ("Vertical Diffusion", "the grid mean's vertical diffusion"),
    hdiff = (
        "Horizontal Diffusion",
        "the grid mean's horizontal EDMF diffusive flux",
    ),
    hyperdiff = ("Hyperdiffusion", "the grid mean's hyperdiffusion"),
    sponge = ("Viscous Sponge", "the viscous sponge"),
    diffusion_up = (
        "Updraft Diffusion",
        "the updrafts' mirror of the EDMF diffusive fluxes on the copies",
    ),
    hyperdiff_up = (
        "Updraft Hyperdiffusion",
        "the updrafts' hyperdiffusion of the copies",
    ),
)

function compute_q_tag_fix!(out, state, cache, time, ρq_tag_name)
    ᶜfix = getproperty(cache.tagging.ᶜwater_fix, ρq_tag_name)
    if isnothing(out)
        return specific.(ᶜfix, state.c.ρ)
    else
        out .= specific.(ᶜfix, state.c.ρ)
    end
end

# A gross twin per unit mass, or a count as it is, in the model's float type.
# The cache holds both in Float64 (`tag_throughput.jl`).
function compute_tag_throughput!(out, state, fields, name, per_mass::Bool)
    ᶜfield = getproperty(fields, name)
    result = isnothing(out) ? similar(state.c.ρ) : out
    if per_mass
        @. result = ᶜfield / state.c.ρ
    else
        @. result = ᶜfield
    end
    return result
end

# One field of the increment's ledger, per unit mass.
function compute_q_tag_ledger!(out, state, cache, time, name)
    ᶜledger = getproperty(state.c, name)
    if isnothing(out)
        return specific.(ᶜledger, state.c.ρ)
    else
        out .= specific.(ᶜledger, state.c.ρ)
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

  - `q_tag_inc_left` and `q_tag_inc_moved`, under `water_tag_transport: increment` only: the increment correction's ledger per unit mass,
    cumulative since the start of the run. See
    `water_tag_increment_ledger_variables`.

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
function register_water_tagging_diagnostics!(model::AtmosModel)
    register_water_tagging_diagnostics!(model.water_tagging_model)
    register_water_tag_precipitation_diagnostics!(
        model.water_tagging_model,
        model.microphysics_model,
    )
    return nothing
end

# `pr_tag_<name>`, `prra_tag_<name>` and `prsn_tag_<name>`: each tag's part of
# the surface precipitation, under 0M only, where the rain-out is the only
# sink (WP4a). Under 1M the rain and snow parts of WP4b will give it. With a
# region tag, `pr_tag_res` is `pr` less the region tags' parts. Every entry of
# an earlier model is dropped first, whatever its tag's name, since each holds
# its model's tag and would compute that tag's part here. All of them read one
# batch per output time (`update_water_tag_rainouts!`), so their cost is linear
# in the number of tags.
const WATER_TAG_PRECIPITATION_PREFIXES = ("pr_tag_", "prra_tag_", "prsn_tag_")
function register_water_tag_precipitation_diagnostics!(model, microphysics_model)
    for short_name in collect(keys(ALL_DIAGNOSTICS))
        any(prefix -> startswith(short_name, prefix), WATER_TAG_PRECIPITATION_PREFIXES) &&
            delete!(ALL_DIAGNOSTICS, short_name)
    end
    microphysics_model isa EquilibriumMicrophysics0M || return nothing
    tags = isnothing(model) ? () : model.tags
    for tag in tags
        name = tag_name(tag)
        for (prefix, phase, what) in (
            ("pr_tag", Val(:all), "Precipitation"),
            ("prra_tag", Val(:rain), "Rainfall Flux"),
            ("prsn_tag", Val(:snow), "Snowfall Flux"),
        )
            short_name = "$(prefix)_$name"
            add_diagnostic_variable!(;
                short_name,
                units = "kg m^-2 s^-1",
                long_name = "Tagged $what ($name)",
                comments = "The part of the 0M rain-out that the water tag " *
                           "`$name` loses, integrated over the column as " *
                           "`pr` integrates the sink: upward-positive, so " *
                           "negative. Under prognostic EDMF each subdomain's " *
                           "part goes by that subdomain's composition: the " *
                           "copies' with updraft copies, and in the default " *
                           "mode one reconstructed from the exchange's plume. " *
                           "Both signs are attributed, so a subdomain whose " *
                           "area is negative in the state gives a gain. Over " *
                           "a closed partition the tags' sum is `pr` less " *
                           "`pr_tag_res`. The rate at the output's state.",
                compute = (state, cache, time) ->
                    water_tag_precipitation!(
                        cache.scratch.ᶠtemp_field_level,
                        state,
                        cache,
                        time,
                        tag,
                        phase,
                    ),
            )
        end
    end
    !isnothing(model) && !isempty(water_region_tag_state_names(model)) &&
        add_diagnostic_variable!(;
            short_name = "pr_tag_res",
            units = "kg m^-2 s^-1",
            long_name = "Precipitation Not Taken by the Region Water Tags",
            comments = "`pr` less the sum of the region tags' `pr_tag`: the part " *
                       "of the 0M rain-out that no region tag takes. It is the " *
                       "rain-out times one less the partition's sum of shares, " *
                       "in each subdomain under prognostic EDMF. So it follows " *
                       "the partition's residual and, with updraft copies, the " *
                       "copies' own. Upward-positive, as `pr`.",
            compute = (state, cache, time) -> water_tag_precipitation_residual!(
                cache.scratch.ᶠtemp_field_level,
                state,
                cache,
                time,
            ),
        )
    return nothing
end
# Water tagging is off. As for the energy tags, the per-tag entries can stay
# but a stale `q_tag_res` cannot: it would report a residual over a partition
# this model does not have. See the enabled path below.
function register_water_tagging_diagnostics!(::Nothing)
    delete!(ALL_DIAGNOSTICS, "q_tag_res")
    return nothing
end
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

        # The gross twin and the count of `q_tag_fix_<name>`, keyed by the tag
        # name alone, as the ledger is.
        for (short_name, what, per_mass, units) in (
            (
                "q_tag_fixgross_$name",
                "the absolute value of every change the limiters and state " *
                "constraints made to the tag `$name`, per unit mass of moist " *
                "air",
                true,
                "kg kg^-1",
            ),
            (
                "q_tag_fixcount_$name",
                "the number of times a limiter or state constraint changed " *
                "the tag `$name` in this cell by more than rounding",
                false,
                "1",
            ),
        )
            haskey(ALL_DIAGNOSTICS, short_name) && continue
            add_diagnostic_variable!(;
                short_name,
                units,
                long_name = "Gross Tagged Water Numerical Correction ($name)",
                comments = "Beside q_tag_fix_$name, which is signed: $what. " *
                           "Cumulative since the start of the simulation " *
                           "segment and reset on restart. It counts what was " *
                           "attempted, every call, including changes inside a " *
                           "step that the stepper discards. A transfer " *
                           "between tags counts once out and once in.",
                compute! = (out, u, p, t) -> compute_tag_throughput!(
                    out,
                    u,
                    per_mass ? p.tagging.ᶜwater_fix_gross :
                    p.tagging.ᶜwater_fix_count,
                    ρq_tag_name,
                    per_mass,
                ),
            )
        end

        # The copies' repair moves only the partition's copies. A stale entry
        # from an earlier model with copies would read a ledger this model
        # does not have, so it is dropped first, as for `q_tag_copy_res`.
        short_name = "q_tag_upfix_$name"
        delete!(ALL_DIAGNOSTICS, short_name)
        if has_water_tag_updraft_copies(model) &&
           ρq_tag_name in water_region_tag_state_names(model)
            add_diagnostic_variable!(;
                short_name,
                units = "kg kg^-1",
                long_name = "Cumulative Tagged Water Updraft Copy Repair ($name)",
                comments = "Water moved into (positive) or out of (negative) " *
                           "the updraft copy of the tag `$name` by the " *
                           "copies' repair after the updraft filter, times " *
                           "the updraft's density-area `ρaʲ`, per unit mass " *
                           "of grid-mean moist air. Cumulative since the " *
                           "start of the simulation segment and reset on " *
                           "restart. Written only under " *
                           "`water_tag_updraft_copy: true`, for the tags of " *
                           "the partition.",
                compute! = (out, u, p, t) ->
                    compute_q_tag_upfix!(out, u, p, t, ρq_tag_name),
            )
        end
        # Its gross twin and count, under the same conditions.
        for (short_name, per_mass, units) in (
            ("q_tag_upfixgross_$name", true, "kg kg^-1"),
            ("q_tag_upfixcount_$name", false, "1"),
        )
            delete!(ALL_DIAGNOSTICS, short_name)
            (
                has_water_tag_updraft_copies(model) &&
                ρq_tag_name in water_region_tag_state_names(model)
            ) || continue
            add_diagnostic_variable!(;
                short_name,
                units,
                long_name = "Gross Tagged Water Updraft Copy Repair ($name)",
                comments = "Beside q_tag_upfix_$name, which is signed: " *
                           (
                               per_mass ?
                               "the absolute value of every change the copies' " *
                               "repair made to the updraft copy of `$name`, " *
                               "times ρaʲ, per unit mass of grid-mean moist air" :
                               "the number of times the copies' repair changed " *
                               "the updraft copy of `$name` in this cell by more " *
                               "than rounding"
                           ) *
                           ". Cumulative since the start of the simulation " *
                           "segment and reset on restart; every call counts.",
                compute! = (out, u, p, t) -> compute_tag_throughput!(
                    out,
                    u,
                    per_mass ? p.tagging.ᶜwater_upfix_gross :
                    p.tagging.ᶜwater_upfix_count,
                    ρq_tag_name,
                    per_mass,
                ),
            )
        end
    end

    # The diagnostics below describe a partition: the region tags without
    # sources. A model with source tags only has none, so they are not
    # registered, as `q_tag_res` is not. A stale entry from an earlier model
    # would report a residual this model does not have, so each is dropped
    # first.
    region_names = water_region_tag_state_names(model)
    has_partition = !isempty(region_names)
    delete!(ALL_DIAGNOSTICS, "q_tag_copy_res")
    if has_water_tag_updraft_copies(model) && has_partition
        add_diagnostic_variable!(;
            short_name = "q_tag_copy_res",
            units = "kg kg^-1",
            long_name = "Tagged Water Updraft Copy Residual",
            comments = "The updraft's water minus the sum of the partition's " *
                       "updraft copies, `q_totʲ - Σᵢ χᵢʲ`, per unit mass of " *
                       "updraft air, as the copies' repair found it after " *
                       "the updraft filter at the last state constraint, " *
                       "before repairing it.",
            compute! = (out, u, p, t) ->
                compute_q_tag_copy_res!(out, u, p, t),
        )
    end

    # The rate at which each path that moves the tags on their whole value,
    # and the parent on its diffusing water, would drift an exactly closed
    # partition from the parent (G3_PLAN 4.2). The updrafts' paths only with
    # copies.
    for path in WATER_TAG_LEAK_PATHS
        short_name = "q_tag_leak_$path"
        delete!(ALL_DIAGNOSTICS, short_name)
        has_partition || continue
        endswith(string(path), "_up") &&
            !has_water_tag_updraft_copies(model) &&
            continue
        (title, what) = getproperty(WATER_TAG_LEAK_DESCRIPTIONS, path)
        add_diagnostic_variable!(;
            short_name,
            units = "kg kg^-1 s^-1",
            long_name = "Tagged Water Leak by $title",
            comments = "The rate at which $what would move the sum of " *
                       "a partition of water tags away from total water if " *
                       "the partition were exactly closed, per unit mass of " *
                       "grid-mean air, in closed form from the state. The " *
                       "path moves the tags on their whole value, and total " *
                       "water only by the water that diffuses, without rain " *
                       "and snow. It is the source the path adds to the " *
                       "closure residual; the path's transport of a residual " *
                       "already there is not in it. Zero where the path is " *
                       "off. See `water_tag_leak!`.",
            compute! = (out, u, p, t) ->
                compute_q_tag_leak!(out, u, p, t, Val(path)),
        )
    end

    # The increment's ledger. A stale entry from an earlier model would read
    # state fields this model does not have, so each is dropped first.
    for (short_name, title, what) in (
        (
            "q_tag_inc_left",
            "Left Out of the Water Tags",
            "left out of the tags. In each column it sums to the part of the " *
            "parent's implicit increment of ρq_tot that changes the column's " *
            "total and that the tags' own implicit tendencies did not take. " *
            "It lands in q_tag_res.",
        ),
        (
            "q_tag_inc_moved",
            "Moved Among the Water Tags",
            "moved between levels. It sums to zero in each column. It is " *
            "mostly the parent's vertical advection, which the tags no longer " *
            "take explicitly, and the column-neutral part of their lag behind " *
            "the parent's other implicit terms.",
        ),
    )
        delete!(ALL_DIAGNOSTICS, short_name)
        follows_water_increment(model) || continue
        ledger_name = Symbol(short_name)
        add_diagnostic_variable!(;
            short_name,
            units = "kg kg^-1",
            long_name = "Water $title by the Increment Correction",
            comments = "The water that the water tags' increment correction " *
                       "$what Per unit mass of moist air, cumulative since " *
                       "the start of the run. Only under " *
                       "water_tag_transport: increment. Each increment is " *
                       "kept at its own step's density and divided by the " *
                       "current density here. See " *
                       "`water_tag_increment_ledger_variables`.",
            compute! = (out, u, p, t) ->
                compute_q_tag_ledger!(out, u, p, t, ledger_name),
        )
    end

    # Drop any stale entry first, then decide whether to register a new one. An
    # earlier simulation in this process may have registered `q_tag_res` over a
    # different set of region tags. If every tag in this model carries a
    # `source`, a leftover entry would let a config ask for a closure residual
    # summed over tags that never partitioned this model's water. That returns a
    # wrong number and no error, so clear it.
    delete!(ALL_DIAGNOSTICS, "q_tag_res")
    if !isempty(region_names)
        add_diagnostic_variable!(;
            short_name = "q_tag_res",
            units = "kg kg^-1",
            long_name = "Tagged Water Closure Residual",
            comments = "Total water minus the sum of the region tags, " *
                       "(ρq_tot - Σᵢ ρq_tag_i) / ρ. One contributor is the " *
                       "vertical advection split: the tags are advected on " *
                       "the explicit passive-tracer path while ρq_tot is " *
                       "advected implicitly with a post-Newton upwind " *
                       "correction. Others are the paths that move the tags " *
                       "on their whole value and ρq_tot without rain and " *
                       "snow, or relative to a reference profile: the " *
                       "diffusion, the hyperdiffusion, the sponge and their " *
                       "updraft counterparts, whose sources `q_tag_leak_*` " *
                       "gives. Subtract `q_tag_fix_*` to separate numerical " *
                       "corrections.",
            compute! = (out, u, p, t) ->
                compute_q_tag_res!(out, u, p, t, region_names),
        )
    end
    return nothing
end
