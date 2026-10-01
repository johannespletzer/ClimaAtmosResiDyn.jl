# This file is included in Diagnostics.jl

# Tagged prognostic water tracers
#
# Tag names come from the configuration, as they do for the energy tags. So the
# per-tag diagnostics are registered once the `WaterTaggingModel` is known.
# `register_water_tagging_diagnostics!(model)` runs during simulation setup,
# from `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`.
#
# The tagged names say what they hold. `q_tag_*` is total water and `qv_tag_*`
# is vapor. The repo's `hus` is labelled "Specific Humidity" and computes
# `ρq_tot / ρ`, the mass of all water phases. `husv` is its vapor-only
# counterpart.

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

# Under `water_tag_precipitation: true` the vapour is in the tag's
# non-precipitating part only, so its share is taken of that compartment,
# `ρq_tot - ρq_rai - ρq_sno`, not of all the water. `q_liq` and `q_ice` include
# rain and snow, so the vapour is the same as without the key.
@inline function _qv_tag_part(ρq_tag, ρ, ρq_tot, ρq_nonprecip, q_liq, q_ice)
    ρq_vap = max(ρq_tot - ρ * (q_liq + q_ice), zero(ρ))
    return specific(ρq_tag, ρ) * water_tag_fraction(ρq_vap, ρq_nonprecip)
end

function compute_qv_tag_part!(out, state, cache, time, ρq_tag_name)
    ᶜρq_tag = getproperty(state.c, ρq_tag_name)
    (; ᶜq_liq, ᶜq_ice) = cache.precomputed
    ᶜnonprecip = water_tag_part_parent(state.c, NonPrecipitatingPart())
    result = isnothing(out) ? similar(state.c.ρ) : out
    @. result = _qv_tag_part(
        ᶜρq_tag,
        state.c.ρ,
        state.c.ρq_tot,
        ᶜnonprecip,
        ᶜq_liq,
        ᶜq_ice,
    )
    return result
end

# A tag's total water under `water_tag_precipitation: true`: the sum of its
# three parts, per unit mass.
function compute_q_tag_total!(out, state, cache, time, part_names)
    result = isnothing(out) ? similar(state.c.ρ) : out
    result .= zero(eltype(result))
    for name in part_names
        result .+= getproperty(state.c, name)
    end
    result .= specific.(result, state.c.ρ)
    return result
end

# The residual of one compartment: the compartment's non-negative part less the
# partition's parts of it, per unit mass. The parts partition that non-negative
# part.
function compute_q_tag_part_res!(out, state, cache, time, part_names, part)
    result = isnothing(out) ? similar(state.c.ρ) : out
    result .= water_tag_part_target(state.c, part)
    for name in part_names
        result .-= getproperty(state.c, name)
    end
    result .= specific.(result, state.c.ρ)
    return result
end

# A tag's surface precipitation, `water_tag_precipitation_flux!`.
function compute_pr_tag!(out, state, cache, time, tag)
    result = isnothing(out) ? similar(cache.precomputed.surface_rain_flux) : out
    return water_tag_precipitation_flux!(result, state, cache, tag)
end

function compute_q_tag_res!(out, state, cache, time, ρq_tag_names, model)
    ᶜres = isnothing(out) ? similar(state.c.ρq_tot) : out
    # Against the partition's target, the parent's non-negative water. Under
    # `water_tag_precipitation: true` it is the sum of the three compartments'
    # non-negative parts.
    ᶜres .= water_partition_target(state.c, model)
    for ρq_tag_name in ρq_tag_names
        ρq_tag_name in propertynames(state.c) ||
            error("$ρq_tag_name does not exist in the model")
        ᶜres .-= getproperty(state.c, ρq_tag_name)
    end
    ᶜres .= specific.(ᶜres, state.c.ρ)
    return ᶜres
end

# `q_tag_negative`: the parent's negative water, the remainder the partition
# leaves. Under `water_tag_precipitation: true` it is the sum of the three
# compartments' negative parts.
function compute_q_tag_negative!(out, state, cache, time, model)
    result = isnothing(out) ? similar(state.c.ρ) : out
    ᶜnegative = water_partition_negative_part(state.c, model)
    @. result = specific(ᶜnegative, state.c.ρ)
    return result
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

  - `q_tag_<name>`: tagged **total** water `ρq_tag_<name> / ρ`, for each tag.
    Under `water_tag_precipitation: true` it is the sum of the tag's three
    parts, `(ρq_tag_<name> + ρq_rtag_<name> + ρq_stag_<name>) / ρ`;

  - `qv_tag_<name>`: tagged **vapor**, `q_tag_<name> * q_v / q_t`, under the
    assumption that the phases are well mixed within a grid cell. Under
    `water_tag_precipitation: true` the vapour's share is taken of the tag's
    non-precipitating part and its compartment: `q_ntag_<name>` times `q_v`
    over `q_tot - q_rai - q_sno`;

  - `q_tag_res`: closure residual `(max(ρq_tot, 0) - Σᵢ ρq_tag_i) / ρ`, where
    the sum runs over the pure region tags (only registered when at least one
    exists), and under `water_tag_precipitation: true` over their three parts.
    The tags partition the parent's non-negative water. Under the key that is
    the sum of the three compartments' non-negative parts;

  - under `water_tag_precipitation: true` only: `q_ntag_<name>`,
    `q_rtag_<name>` and `q_stag_<name>`, each part per unit mass;
    `q_ntag_res`, `q_rtag_res` and `q_stag_res`, each compartment's
    non-negative part less the partition's parts of it; `pr_tag_<name>`, the
    tag's share of the surface precipitation `pr`
    (`water_tag_precipitation_flux!`); and `q_rtag_aud_<name>` and
    `q_stag_aud_<name>`, the microphysics audit
    (`water_tag_microphysics_audit`);

  - `q_tag_negative`: the parent's negative water, `min(ρq_tot, 0) / ρ`, which
    the partition leaves. Under `water_tag_precipitation: true` it is the sum
    of the three compartments' negative parts. So `q_tag_res`,
    `q_tag_negative` and the region tags add up to `q_tot`;

  - `q_tag_inc_left`, `q_tag_inc_moved` and `q_tag_inc_negative`, under `water_tag_transport: increment` only: the increment ledger per unit mass,
    cumulative since the start of the run. See
    `water_tag_increment_ledger_variables`.

  - `q_tag_exp_negative`, and under `water_tag_precipitation: true`
    `q_tag_exp_negative_precip`: the gain withheld from the tags where the
    parent is below zero, per unit mass, cumulative. They and their per-step
    grosses are registered with the other state ledgers
    (`register_tag_ledger_diagnostics!`).

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
diagnostics catalog are kept where their compute function only depends on the
tag name. `q_tag_<name>` and `qv_tag_<name>` depend on
`water_tag_precipitation` too, so they are dropped and re-registered, as are the
entries of the rain and snow parts. The `q_tag_res` entry is always dropped and
re-registered, because the set of region tags it sums over can differ between
setups — including differing to *empty*, in which case no new entry replaces
the stale one.
"""
function register_water_tagging_diagnostics!(model::AtmosModel)
    # The 0M entries come first. They drop every `pr_tag_*`, `prra_tag_*` and
    # `prsn_tag_*` entry of an earlier model. Under `water_tag_precipitation:
    # true`, which needs 1M, the tags' own `pr_tag_<name>` is registered after.
    register_water_tag_precipitation_diagnostics!(
        model.water_tagging_model,
        model.microphysics_model,
    )
    register_water_tagging_diagnostics!(model.water_tagging_model)
    return nothing
end

# `pr_tag_<name>`, `prra_tag_<name>` and `prsn_tag_<name>`: each tag's part of
# the surface precipitation, under 0M, where the rain-out is the only sink.
# Under 1M, `water_tag_precipitation: true` gives `pr_tag_<name>` alone,
# from the tag's rain and snow parts. The method for the tagging model
# registers it after this. With a region tag, `pr_tag_res` is `pr` less the
# region tags' parts. Every entry of an earlier model is dropped first, whatever
# its tag's name, since each holds its model's tag and would compute that tag's
# part here. All of them read one batch per output time
# (`update_water_tag_rainouts!`), so their cost is linear in the number of tags.
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
    precipitation = has_water_tag_precipitation(model)
    for tag in model.tags
        name = tag_name(tag)
        ρq_tag_name = Symbol(:ρq_tag_, name)
        part_names = (ρq_tag_name, Symbol(:ρq_rtag_, name), Symbol(:ρq_stag_, name))

        # Its compute depends on `water_tag_precipitation`, so a stale entry
        # from an earlier model is dropped first.
        total_compute(out, u, p, t) =
            precipitation ? compute_q_tag_total!(out, u, p, t, part_names) :
            compute_q_tag!(out, u, p, t, ρq_tag_name)
        vapor_compute(out, u, p, t) =
            precipitation ? compute_qv_tag_part!(out, u, p, t, ρq_tag_name) :
            compute_qv_tag!(out, u, p, t, ρq_tag_name)
        short_name = "q_tag_$name"
        delete!(ALL_DIAGNOSTICS, short_name)
        add_diagnostic_variable!(;
            short_name,
            units = "kg kg^-1",
            long_name = "Tagged Total Water Content ($name)",
            comments = "Grid-mean mass of all water phases carried by the " *
                       "tag `$name`, per unit mass of moist air. Not to be " *
                       "confused with vapor: see `qv_tag_$name`." *
                       (
                           precipitation ?
                           " The sum of the tag's non-precipitating, rain and " *
                           "snow parts (`water_tag_precipitation: true`)." : ""
                       ),
            compute! = total_compute,
        )

        short_name = "qv_tag_$name"
        delete!(ALL_DIAGNOSTICS, short_name)
        add_diagnostic_variable!(;
            short_name,
            units = "kg kg^-1",
            long_name = "Tagged Water Vapor Content ($name)",
            comments = "Vapor share of the tag `$name`, computed as " *
                       (
                           precipitation ?
                           "q_ntag * q_v / (q_tot - q_rai - q_sno), from " *
                           "the tag's non-precipitating part. " :
                           "q_tag * q_v / q_t. "
                       ) *
                       "This assumes the water phases " *
                       "are well mixed within a grid cell: the tags " *
                       "partition total water, so they carry no phase " *
                       "information of their own. Attribution assumption, " *
                       "not a model prognostic.",
            compute! = vapor_compute,
        )

        # The three parts, the tag's surface precipitation and the audit,
        # under `water_tag_precipitation: true` only. A stale entry from an
        # earlier model would read fields this model does not have.
        for (short_name, long_name, what, field_name) in (
            (
                "q_ntag_$name",
                "Tagged Non-Precipitating Water Content ($name)",
                "The vapour, cloud liquid and cloud ice carried by the tag " *
                "`$name`, per unit mass of moist air: its part of " *
                "`q_tot - q_rai - q_sno`.",
                ρq_tag_name,
            ),
            (
                "q_rtag_$name",
                "Tagged Rain Content ($name)",
                "The rain carried by the tag `$name`, per unit mass of moist " *
                "air: its part of `q_rai`.",
                Symbol(:ρq_rtag_, name),
            ),
            (
                "q_stag_$name",
                "Tagged Snow Content ($name)",
                "The snow carried by the tag `$name`, per unit mass of moist " *
                "air: its part of `q_sno`.",
                Symbol(:ρq_stag_, name),
            ),
            (
                "q_rtag_aud_$name",
                "Microphysics Audit of the Tagged Rain ($name)",
                "The change of the rain part of the tag `$name` that the " *
                "net-flow rule would give, less the change the gross flows " *
                "gave, per unit mass of moist air, cumulative since the " *
                "start of the run. The non-precipitating part's difference " *
                "is minus the sum of this and `q_stag_aud_$name` only " *
                "while no compartment of the cell is negative.",
                Symbol(:q_rtag_aud_, name),
            ),
            (
                "q_stag_aud_$name",
                "Microphysics Audit of the Tagged Snow ($name)",
                "The same as `q_rtag_aud_$name`, for the snow part.",
                Symbol(:q_stag_aud_, name),
            ),
        )
            delete!(ALL_DIAGNOSTICS, short_name)
            precipitation || continue
            add_diagnostic_variable!(;
                short_name,
                units = "kg kg^-1",
                long_name,
                comments = what * " Only under water_tag_precipitation: true.",
                compute! = (out, u, p, t) ->
                    compute_q_tag_ledger!(out, u, p, t, field_name),
            )
        end
        # Under the key only. Without it `pr_tag_<name>` is the 0M rain-out's
        # entry, which `register_water_tag_precipitation_diagnostics!` owns.
        # That function also drops the entries of an earlier model.
        if precipitation
            short_name = "pr_tag_$name"
            delete!(ALL_DIAGNOSTICS, short_name)
            add_diagnostic_variable!(;
                short_name,
                units = "kg m^-2 s^-1",
                long_name = "Tagged Precipitation ($name)",
                comments = "The tag `$name`'s share of the surface " *
                           "precipitation `pr`: the flux of its rain and snow " *
                           "parts and of its share of the cloud at the bottom " *
                           "face, built as `pr` is, upward positive. The " *
                           "partition's fluxes sum to `pr` where its rain and " *
                           "snow parts sum to the model's at the lowest level. " *
                           "Only under water_tag_precipitation: true.",
                compute! = (out, u, p, t) ->
                    compute_pr_tag!(out, u, p, t, tag),
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
                           "constraints. Cumulative since the start of the " *
                           "run and carried through a restart, so the " *
                           "change over an interval is the difference of two " *
                           "outputs, and a time average of this variable is " *
                           "not meaningful. For a partition tag (a region, no " *
                           "source), partition repair writes here whenever " *
                           "transport has driven any partition tag negative, " *
                           "even with no limiter configured. A source tag gets " *
                           "only the rescale that follows a limiter, " *
                           "nonnegativity constraint or prescribed flow " *
                           "correcting `ρq_tot`, so it stays zero without one " *
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
                           "Cumulative since the start of the run and " *
                           "carried through a restart. It counts what was " *
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
                           "start of the run and carried through a " *
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
                           ". Cumulative since the start of the run and " *
                           "carried through a restart; every call counts.",
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
    # partition from the parent. The updrafts' paths only with copies.
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
            comments = "The rate at which $what moves the sum of a " *
                       "partition of water tags away from total water, per " *
                       "unit mass of grid-mean air, in closed form from the " *
                       "state. It is the raw difference: the path's tendency " *
                       "of the tags' sum minus its tendency of total water. " *
                       "It is taken where the partition is closed to option " *
                       "C's target, max(ρq_tot, 0), and on the updrafts' " *
                       "paths max(q_totʲ, 0). The path moves the tags " *
                       "on their whole value, and total water only by the " *
                       "water that diffuses, without rain and snow. The " *
                       "hyperdiffusion also takes total water as a " *
                       "perturbation from a reference profile. Where total " *
                       "water is negative, the closed partition differs from " *
                       "it by the negative part, and the leak includes the " *
                       "path's transport of that difference. It does not " *
                       "include the transport of any other residual. So it " *
                       "is the path's source of q_tag_res + q_tag_negative, " *
                       "with the opposite sign. Under " *
                       "`water_tag_precipitation: true` the tags' " *
                       "non-precipitating parts diffuse as that water, and " *
                       "the target is the non-negative part of the water " *
                       "that is neither rain nor snow. Then only the " *
                       "vertical diffusion, the hyperdiffusion and the " *
                       "sponge leak. Zero where the path is off. See " *
                       "`water_tag_leak!`.",
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
        (
            "q_tag_inc_negative",
            "Given to the Water Tags for the Parent's Negative Part",
            "gave the tags, or took from them, because the parent's negative " *
            "part changed: the tags partition max(ρq_tot, 0), whose column " *
            "total grows by the negative water a solve creates. Zero where " *
            "the parent stays non-negative (known issue 7, option C). It " *
            "also holds the positive part of a crossing whose gain the rule " *
            "withheld inside the solve, which the tags take in that cell." *
            (
                precipitation ?
                " Under water_tag_precipitation: true the same holds for the " *
                "water that is neither rain nor snow." : ""
            ),
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

    # Each compartment's residual under `water_tag_precipitation: true`,
    # against its non-negative part.
    for (short_name, title, part) in (
        ("q_ntag_res", "Non-Precipitating Water", NonPrecipitatingPart()),
        ("q_rtag_res", "Rain", RainPart()),
        ("q_stag_res", "Snow", SnowPart()),
    )
        delete!(ALL_DIAGNOSTICS, short_name)
        (precipitation && has_partition) || continue
        prefix =
            part isa NonPrecipitatingPart ? :ρq_tag_ :
            part isa RainPart ? :ρq_rtag_ : :ρq_stag_
        compartment_names = Tuple(
            Symbol(prefix, chopprefix(string(region_name), "ρq_tag_")) for
            region_name in region_names
        )
        add_diagnostic_variable!(;
            short_name,
            units = "kg kg^-1",
            long_name = "Tagged $title Closure Residual",
            comments = "The non-negative part of the parent's " *
                       "$(lowercase(title)) less the sum of the region " *
                       "tags' parts of it, per unit mass of moist air. The " *
                       "parts partition that non-negative part (known issue " *
                       "7, option C, per compartment). Only under " *
                       "water_tag_precipitation: true.",
            compute! = (out, u, p, t) -> compute_q_tag_part_res!(
                out,
                u,
                p,
                t,
                compartment_names,
                part,
            ),
        )
    end

    # Drop any stale entry first, then decide whether to register a new one. An
    # earlier simulation in this process may have registered `q_tag_res` over a
    # different set of region tags. If every tag in this model carries a
    # `source`, a leftover entry would let a config ask for a closure residual
    # summed over tags that never partitioned this model's water. That returns a
    # wrong number and no error, so clear it.
    delete!(ALL_DIAGNOSTICS, "q_tag_res")
    delete!(ALL_DIAGNOSTICS, "q_tag_negative")
    if !isempty(region_names)
        partition_names = water_partition_state_names(model)
        add_diagnostic_variable!(;
            short_name = "q_tag_negative",
            units = "kg kg^-1",
            long_name = "Negative Total Water Left Out of the Water Tags",
            comments = "The parent's negative water, min(ρq_tot, 0) / ρ. " *
                       "The region tags partition the non-negative part, " *
                       "max(ρq_tot, 0), so this is the remainder they leave, " *
                       "beside q_tag_res (known issue 7, option C). Zero " *
                       "wherever q_tot is not negative." *
                       (
                           precipitation ?
                           " Under water_tag_precipitation: true each " *
                           "compartment's parts partition its own " *
                           "non-negative part, and this is the sum of the " *
                           "negative parts of the water that is neither rain " *
                           "nor snow, of rain and of snow. It is then zero " *
                           "wherever no compartment is negative." : ""
                       ),
            compute! = (out, u, p, t) -> compute_q_tag_negative!(out, u, p, t, model),
        )
        add_diagnostic_variable!(;
            short_name = "q_tag_res",
            units = "kg kg^-1",
            long_name = "Tagged Water Closure Residual",
            comments = "Total water's non-negative part minus the sum of the " *
                       "region tags, (max(ρq_tot, 0) - Σᵢ ρq_tag_i) / ρ. " *
                       "Where ρq_tot is negative, the tags aim at zero, and " *
                       "the negative water is q_tag_negative. " *
                       (
                           precipitation ?
                           "Under water_tag_precipitation: true the sum runs " *
                           "over all three parts of each tag, and the " *
                           "non-negative part is the sum of the three " *
                           "compartments' non-negative parts. " : ""
                       ) *
                       "One contributor is the " *
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
                compute_q_tag_res!(out, u, p, t, partition_names, model),
        )
    end
    return nothing
end
