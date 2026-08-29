# This file is included in Diagnostics.jl

# Process-change records
#
# Process names come from the configuration, so the per-process diagnostics are
# registered once the `ProcessRecordModel` is known.
# `register_process_record_diagnostics!(model)` runs during simulation setup,
# from `setup_diagnostics_and_writers` in `simulation/AtmosSimulations.jl`.
#
# A record holds the signed increment one process applied, accumulated in the
# cache. It is divided by the current density here, so like `q_tag_fix_<name>`
# it is not exactly the sum of the per-step specific increments.

function compute_process_record!(out, state, cache, time, records, field_name)
    ᶜrecord = getproperty(getproperty(cache.tagging, records), field_name)
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

Both are cumulative since the start of the simulation segment and restart at
zero, so a budget over an interval is the difference of two outputs and a time
average of one is not meaningful. This is the same contract `q_tag_fix_<name>`
follows.

Short names depend on the configured processes, so this runs during simulation
setup rather than at package load time.
"""
function register_process_record_diagnostics!(model::AtmosModel)
    _register_process_record_diagnostics!(
        model.energy_process_record,
        :ᶜenergy_prc,
        "e_prc",
        "J kg^-1",
        "Moist Energy",
    )
    _register_process_record_diagnostics!(
        model.water_process_record,
        :ᶜwater_prc,
        "q_prc",
        "kg kg^-1",
        "Total Water",
    )
    return nothing
end

_register_process_record_diagnostics!(::Nothing, records, prefix, units, label) =
    nothing
function _register_process_record_diagnostics!(
    model::ProcessRecordModel,
    records,
    prefix,
    units,
    label,
)
    for process in model.processes
        name = process_name(process)
        field_name = Symbol(:prc_, name)

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
                       "start of the simulation segment and reset on restart, " *
                       "so a budget over an interval is the difference of two " *
                       "outputs, and a time average of this variable is not " *
                       "meaningful. Only the explicit tendency path is " *
                       "recorded. `precipitation` has no explicit bracket at " *
                       "all, so an energy record listing it is always zero, " *
                       "and `microphysics` is zero on both sides under the " *
                       "default implicit microphysics timestepping.",
            compute! = (out, u, p, t) ->
                compute_process_record!(out, u, p, t, records, field_name),
        )
    end
    return nothing
end
