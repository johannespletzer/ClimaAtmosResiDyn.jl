# This file is included in Diagnostics.jl

# Process-change records
#
# Process names come from the configuration, so the per-process diagnostics are
# registered once the `ProcessRecordModel` is known.
# `register_process_record_diagnostics!(model)` runs during simulation setup,
# from `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`.
#
# A record is a prognostic field holding the time-integrated signed increment
# one process applied, in J/m³ or kg/m³. It is divided by the current density
# here, so like `q_tag_fix_<name>` it is not exactly the sum of the per-step
# specific increments.
#
# `ALL_DIAGNOSTICS` is a process-global registry, so an entry registered by an
# earlier simulation can outlive it. Guard on the field actually being in the
# state rather than trusting the registration.

function compute_process_record!(out, state, cache, time, field_name)
    field_name in propertynames(state.c) || error(
        "$field_name is not in the state: the process record that registered " *
        "this diagnostic is not configured for this simulation.",
    )
    ᶜrecord = getproperty(state.c, field_name)
    if isnothing(out)
        return specific.(ᶜrecord, state.c.ρ)
    else
        out .= specific.(ᶜrecord, state.c.ρ)
    end
end

"""
    register_process_record_diagnostics!(model::AtmosModel)

Register the diagnostics of the configured process records:

  - `e_prc_<process>`: the moist-energy increment that `<process>` has applied,
    per unit mass of moist air (J kg⁻¹);
  - `q_prc_<process>`: the total-water increment it has applied (kg kg⁻¹).

Both are cumulative from the start of the run and are carried through a
restart, because the records are prognostic. A budget over an interval is
therefore the difference of two outputs, and a time average of one is not
meaningful. Note this is *not* the `q_tag_fix_<name>` contract:
`q_tag_fix_<name>` lives in the cache and does restart at zero.

Short names depend on the configured processes, so this runs during simulation
setup rather than at package load time.
"""
function register_process_record_diagnostics!(model::AtmosModel)
    _register_process_record_diagnostics!(
        model.energy_process_record,
        :prc_e_,
        "e_prc",
        "J kg^-1",
        "Moist Energy",
    )
    _register_process_record_diagnostics!(
        model.water_process_record,
        :prc_q_,
        "q_prc",
        "kg kg^-1",
        "Total Water",
    )
    return nothing
end

_register_process_record_diagnostics!(
    ::Nothing,
    state_prefix,
    prefix,
    units,
    label,
) = nothing
function _register_process_record_diagnostics!(
    model::ProcessRecordModel,
    state_prefix,
    prefix,
    units,
    label,
)
    for process in model.processes
        name = process_name(process)
        field_name = Symbol(state_prefix, name)

        short_name = "$(prefix)_$name"
        haskey(ALL_DIAGNOSTICS, short_name) && continue
        add_diagnostic_variable!(;
            short_name,
            units,
            long_name = "Cumulative $label Change by $name",
            comments = "Signed $label increment applied by the process " *
                       "`$name`, per unit mass of moist air. Positive where " *
                       "the process added and negative where it removed, so " *
                       "this is a record of what the process did rather than " *
                       "a share of what is present. Cumulative since the " *
                       "start of the run and carried through a restart, " *
                       "so a budget over an interval is the difference of two " *
                       "outputs, and a time average of this variable is not " *
                       "meaningful. Only the explicit tendency path is " *
                       "recorded. `precipitation` has no explicit bracket at " *
                       "all, so an energy record listing it is always zero, " *
                       "and `microphysics` is zero on both sides under the " *
                       "default implicit microphysics timestepping.",
            compute! = (out, u, p, t) ->
                compute_process_record!(out, u, p, t, field_name),
        )
    end
    return nothing
end
