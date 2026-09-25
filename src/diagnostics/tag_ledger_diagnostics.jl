# The tags' state ledgers per mechanism and the per-step gross of every state
# ledger (WP6, step 2). Their names depend on the model, so
# `register_tag_ledger_diagnostics!(model)` runs during simulation setup, after
# the families' own registrations.

# The ledgers of both families that any model can have, so that a stale entry
# from an earlier model in this process is dropped.
const _ALL_TAG_STATE_LEDGER_NAMES = (
    WATER_TAG_ALL_MECHANISM_NAMES...,
    :q_tag_inc_left,
    :q_tag_inc_moved,
    ENERGY_SOURCE_MECHANISM_NAMES...,
    :e_src_inc_left,
    :e_src_inc_moved,
)

_is_water_ledger(name) = startswith(string(name), "q_tag_")

# What each new state ledger holds, for its comments.
const _TAG_MECHANISM_TEXT = (;
    q_tag_led_rescale = "the partition's share of the limiters' and " *
                        "constraints' change of ρq_tot where the parent held " *
                        "water (rescale_water_tags!)",
    q_tag_led_empty = "the partition's water removed where the parent held " *
                      "none (rescale_water_tags!)",
    q_tag_led_repair = "the water the partition repair moved between the " *
                       "tags, half the sum of the tags' changes less their " *
                       "net (repair_water_tag_partition!)",
    q_tag_led_repairnet = "the water the partition repair added where it " *
                          "zeroed every tag, the net of its changes",
    q_tag_led_uprepair = "the residual that the copies' repair handed to the " *
                         "partition's copies, times ρaʲ " *
                         "(repair_water_tag_copies!)",
    q_tag_led_upfilter = "the updraft filter's change of the partition " *
                         "copies' water, Δ(ρaʲ Σ χᵢʲ), net over the copies",
    e_src_led_repair = "the energy the partition repair moved between the " *
                       "tags, half the sum of the tags' changes less their " *
                       "net (repair_energy_source_tags!)",
    e_src_led_repairnet = "the energy the partition repair added where it " *
                          "zeroed every tag, the net of its changes",
)

# A state ledger per unit mass.
function compute_tag_state_ledger!(out, state, name)
    ᶜledger = getproperty(state.c, name)
    result = isnothing(out) ? similar(state.c.ρ) : out
    @. result = ᶜledger / state.c.ρ
    return result
end

# The per-step gross of a state ledger, per unit mass, from the Float64 cache.
function compute_tag_ledger_gross!(out, state, cache, name)
    (; ᶜgross) = getproperty(cache.tagging.tag_ledger_steps.ledgers, name)
    result = isnothing(out) ? similar(state.c.ρ) : out
    @. result = ᶜgross / state.c.ρ
    return result
end

# The per-step column gross of a state ledger, per unit area.
function compute_tag_ledger_colgross!(out, state, cache, name)
    (; colgross) = getproperty(cache.tagging.tag_ledger_steps.ledgers, name)
    result =
        isnothing(out) ? Fields.Field(eltype(state.c.ρ), axes(colgross)) : out
    @. result = colgross
    return result
end

# What a state ledger's writers attempted, per unit mass (WP6, step 3).
function compute_tag_ledger_attempted!(out, state, cache, name)
    ᶜattempted = getproperty(cache.tagging.tag_ledger_steps.attempted, name)
    result = isnothing(out) ? similar(state.c.ρ) : out
    @. result = ᶜattempted / state.c.ρ
    return result
end

# The name of a diagnostic of kind `kind` (`gross`, `colgross`, `attempted`) of
# the state ledger `name`. For a tag's own ledger the kind goes before the tag's
# name, `q_tag_led_fixgross_<tag>`, so that no tag's name can make it collide
# with another tag's ledger; the tag names `led_*` are reserved.
function tag_ledger_diagnostic_name(name, kind)
    long = string(name)
    for prefix in ("q_tag_led_", "e_src_led_"), part in ("fix_", "inc_", "src_")
        startswith(long, prefix * part) || continue
        tag = chopprefix(long, prefix * part)
        return "$(prefix)$(chopsuffix(part, "_"))$(kind)_$(tag)"
    end
    return "$(long)_$(kind)"
end

"""
    register_tag_ledger_diagnostics!(model::AtmosModel)

Register the tags' state ledgers per mechanism and the per-step gross of every
state ledger:

  - `<L>` for each ledger per mechanism, `q_tag_led_*` and `e_src_led_*`: what
    the steps retained, per unit mass, cumulative since the start of the run;
  - `<L>_gross`: the sum over the steps of `|ΔL|` per cell, per unit mass, for
    these and for the increment corrections' ledgers;
  - `<L>_colgross`: the sum over the steps of `|∫ΔL dz|` per column.

The grosses are carried through a restart by the checkpoint (WP6, step 3).
See `tag_ledger_step_cache`.
"""
function register_tag_ledger_diagnostics!(model::AtmosModel)
    names = tag_state_ledger_names(model)
    attempted_names = tag_attempted_ledger_names(model)
    for name in _ALL_TAG_STATE_LEDGER_NAMES
        name in WATER_TAG_ALL_MECHANISM_NAMES ||
            name in ENERGY_SOURCE_MECHANISM_NAMES ||
            continue
        delete!(ALL_DIAGNOSTICS, string(name))
    end
    for name in _ALL_TAG_STATE_LEDGER_NAMES
        delete!(ALL_DIAGNOSTICS, "$(name)_gross")
        delete!(ALL_DIAGNOSTICS, "$(name)_colgross")
        delete!(ALL_DIAGNOSTICS, "$(name)_attempted")
    end
    # Each tag's own ledgers are named by the tags of an earlier model too.
    for short_name in collect(keys(ALL_DIAGNOSTICS))
        any(
            prefix -> startswith(short_name, prefix),
            (
                "q_tag_led_fix",
                "q_tag_led_inc",
                "e_src_led_fix",
                "e_src_led_inc",
                "e_src_led_src",
            ),
        ) && delete!(ALL_DIAGNOSTICS, short_name)
    end
    for name in names
        water = _is_water_ledger(name)
        (units, what) = water ? ("kg kg^-1", "Water") : ("J kg^-1", "Energy")
        if name == ENERGY_SOURCE_RESIDUAL_LEDGER
            add_diagnostic_variable!(;
                short_name = string(name),
                units,
                long_name = "Change of the Energy Source Tags' Residual by the Sources",
                comments = "What the sources' attribution brackets did to " *
                           "e_src_res, the energy the partition's tags did not " *
                           "take: with masks that sum to one, the loss rule's " *
                           "flush of the residual. The stepper weights this " *
                           "state field as it weights the tags. Per unit mass, " *
                           "cumulative since the start of the run (G4.4).",
                compute! = (out, u, p, t) ->
                    compute_tag_state_ledger!(out, u, name),
            )
        elseif is_tag_per_tag_ledger_name(name)
            writer =
                occursin("_led_fix_", string(name)) ?
                "limiters' rescale and the partition repair " :
                occursin("_led_src_", string(name)) ?
                "sources' attribution brackets (OD4's throughput) " :
                "correction after each implicit solve "
            add_diagnostic_variable!(;
                short_name = string(name),
                units,
                long_name = occursin("_led_src_", string(name)) ?
                            "$what Put into One Tag by the Sources" :
                            "$what Retained by the Corrections of One Tag",
                comments = "What the " * writer *
                           "changed this tag by, as the steps retained it: " *
                           "the stepper weights this state field as it " *
                           "weights the tag. Per unit mass, cumulative since " *
                           "the start of the run (WP6, step 3).",
                compute! = (out, u, p, t) ->
                    compute_tag_state_ledger!(out, u, name),
            )
        end
        if name in attempted_names
            add_diagnostic_variable!(;
                short_name = tag_ledger_diagnostic_name(name, "attempted"),
                units,
                long_name = "Attempted Change of a Tag Ledger",
                comments = "The sum over every call of the absolute value " *
                           "of what the writers of $name added, including " *
                           "calls on stage values the stepper discards, per " *
                           "unit mass at the current density. Carried " *
                           "through a restart (WP6, step 3).",
                compute! = (out, u, p, t) ->
                    compute_tag_ledger_attempted!(out, u, p, name),
            )
        end
    end
    for name in names
        water = _is_water_ledger(name)
        (units, area_units, what) =
            water ? ("kg kg^-1", "kg m^-2", "Water") :
            ("J kg^-1", "J m^-2", "Energy")
        if haskey(_TAG_MECHANISM_TEXT, name)
            add_diagnostic_variable!(;
                short_name = string(name),
                units,
                long_name = "$what Retained by a Tag Correction",
                comments = "$(getproperty(_TAG_MECHANISM_TEXT, name)), as " *
                           "the steps retained it: the stepper weights this " *
                           "state field as it weights the tags. Per unit " *
                           "mass, cumulative since the start of the run.",
                compute! = (out, u, p, t) ->
                    compute_tag_state_ledger!(out, u, name),
            )
        end
        add_diagnostic_variable!(;
            short_name = tag_ledger_diagnostic_name(name, "gross"),
            units,
            long_name = "Gross per Step of a Tag Ledger",
            comments = "The sum over the steps of |ΔL| per cell, for the " *
                       "state ledger $name, per unit mass at the current " *
                       "density. Carried through a restart.",
            compute! = (out, u, p, t) ->
                compute_tag_ledger_gross!(out, u, p, name),
        )
        add_diagnostic_variable!(;
            short_name = tag_ledger_diagnostic_name(name, "colgross"),
            units = area_units,
            long_name = "Column Gross per Step of a Tag Ledger",
            comments = "The sum over the steps of |∫ΔL dz| per column, for " *
                       "the state ledger $name. Carried through a " *
                       "restart.",
            compute! = (out, u, p, t) ->
                compute_tag_ledger_colgross!(out, u, p, name),
        )
    end
    return nothing
end
