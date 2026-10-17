#####
##### The fork's steps in upstream's checkpoint, restart and solve
#####
##### Upstream's `save_state_to_disk_func`, `AtmosSimulation`, `handle_restart`
##### and `solve_atmos!` each call one function here. Each of them calls the
##### tags' and the parent budget's own functions in a fixed order.

"""
    write_fork_checkpoint_attributes!(file, p) -> Nothing

Write the parent budget's and the tags' attributes into the checkpoint `file`,
before the state. Called by `save_state_to_disk_func`. A restart that changes
the energy source tags or the water tags is refused (see
[`write_energy_source_checkpoint_attributes!`](@ref) and
[`write_water_tag_checkpoint_attributes!`](@ref)). The closure checks' void
flags let a restarted run keep marking its rows (see
[`write_tag_closure_void_attributes!`](@ref)), and so does the water check's
negative water flag (see [`write_negative_water_void_attributes!`](@ref)).
"""
function write_fork_checkpoint_attributes!(file, p)
    # The parent budget's endpoint of this state, for the restart check.
    Internals.ParentBudget.write_checkpoint_attributes!(file, p.parent_budget)
    # The energy source tags' settings, for the restart guard.
    write_energy_source_checkpoint_attributes!(file, p.atmos.energy_source_tagging_model)
    # The water tags' definitions, for their restart guard.
    write_water_tag_checkpoint_attributes!(file, p.atmos.water_tagging_model)
    # The closure checks' void flags and the water check's negative water
    # flag, which a restart reads back.
    write_tag_closure_void_attributes!(file, p.tagging)
    write_negative_water_void_attributes!(file, p.tagging)
    return nothing
end

"""
    restore_fork_checkpoint!(p, restart_file, context) -> Nothing

Read the tags' accumulators, the closure checks' void flags and the water
check's negative water flag back from `restart_file` into the cache `p`. A
no-op when `restart_file` is `nothing`. `AtmosSimulation` calls it after the
cache is built and before the integrator, whose start runs the first closure
check. See [`restore_tag_closure_void!`](@ref) and
[`restore_negative_water_void!`](@ref).
"""
function restore_fork_checkpoint!(p, restart_file, context)
    isnothing(restart_file) && return nothing
    restore_tag_ledger_checkpoint!(p.tagging, restart_file, context)
    restore_tag_closure_void!(p.tagging, restart_file, context)
    restore_negative_water_void!(p.tagging, restart_file, context)
    return nothing
end

"""
    check_fork_checkpoint(restart_file, model, Y, context) -> Nothing

Refuse a restart that changes what the energy source tags, the process records
or the water tags in `restart_file` mean. `Y` is the state read from the file.
Called by `handle_restart`, before the cache is built. See
[`check_energy_source_checkpoint`](@ref) and
[`check_water_tag_checkpoint`](@ref).
"""
function check_fork_checkpoint(restart_file, model, Y, context)
    check_energy_source_checkpoint(restart_file, model, Y, context)
    check_water_tag_checkpoint(restart_file, model, Y, context)
    return nothing
end

"""
    finalize_fork_outputs!(simulation, comms_ctx) -> Nothing

Write the parent budget's report after a successful solve, with
`write_parent_budget_report`. A failure to write it is logged as an error and
does not change the return code. Called by `solve_atmos!`.
"""
function finalize_fork_outputs!(simulation, comms_ctx)
    # The certificate is a diagnostic of a run that has already finished.
    # A failure to write it must not turn that run into a reported crash.
    try
        write_parent_budget_report(simulation, comms_ctx)
    catch report_error
        @error "Writing the parent-budget report failed; the run itself succeeded" exception =
            (report_error, catch_backtrace())
    end
    return nothing
end

"""
    write_parent_budget_report(simulation, comms_ctx)

Write the parent budget's claim certificate into the output directory
on the root process and log its summary, when the run has a parent budget. It is
called at the end of a successful solve. A crashed run writes none.
"""
function write_parent_budget_report(simulation, comms_ctx)
    adapter = simulation.integrator.p.parent_budget
    isnothing(adapter) && return nothing
    PB = Internals.ParentBudget
    ClimaComms.iamroot(comms_ctx) || return nothing
    float_type = String(nameof(eltype(simulation.integrator.u)))
    path = PB.write_budget_report(
        adapter,
        simulation.output_dir;
        job_id = simulation.job_id,
        float_type,
    )
    @info "Parent-budget report written" path
    @info PB.budget_summary(adapter)
    # A failed identity is a finding about the run, so it is raised above the
    # summary. The return code does not change: the parent budget is a diagnostic.
    failed = PB.failed_claims(adapter)
    isempty(failed) ||
        @warn "Parent-budget claims failed on the last accepted step" failed
    return nothing
end
