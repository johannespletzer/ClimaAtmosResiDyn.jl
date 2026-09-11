#####
##### Parent-budget ledger: the report and the claim certificate
#####
##### The report states what a run established. It is written once at the end
##### of the run. It says which claim levels held for which quantities in which
##### control volumes, under which configuration, and what blocked the rest.
##### It is versioned YAML beside the run's other output, with a concise human
##### summary. Nothing here is new accounting. The report reads the last
##### commit and the ledger's cumulative totals and adds nothing to them.

"""
    REPORT_VERSION

The version of the report's layout. Bumped when a key changes meaning.
"""
const REPORT_VERSION = 1

"""
    REPORT_FILE

The report's file name in the run's output directory.
"""
const REPORT_FILE = "parent_budget_report.yaml"

"""
    LIMITATIONS

The physical-completeness limitations every certificate carries, from the
contract's limitations register. Closure of the accepted discrete update is
not physical completeness. These are the places where the model does not
represent a process the physics has.
"""
const LIMITATIONS = (
    "Closure is of the accepted discrete update; a physically missing exchange has no term and produces no residual.",
    "Y.sfc.water is an accounting accumulator with no hydrology: no soil, snow or deposited-condensate reservoir.",
    "Momentum-only tendencies deposit no frictional heat; their energy contribution is exactly zero by construction.",
    "A custom callback that writes the state and supplies its own accounting is not supported.",
)

# One reconciliation's verdict and numbers as a report entry.
function parent_entry(r::ParentReconciliation)
    return Dict{String, Any}(
        "status" => String(r.status),
        "applicable" => r.applicable,
        "endpoint_change" => r.endpoint_change,
        "recorded" => r.recorded,
        "residual" => r.residual,
        "tolerance" => isnothing(r.tolerance) ? "none" : r.tolerance,
        "cumulative_residual" => r.cumulative_residual,
        "cumulative_abs_residual" => r.cumulative_abs_residual,
        "max_abs_residual" => r.max_abs_residual,
        "endpoint_change_from_initial" => r.endpoint_change_from_initial,
        "telescoping_discrepancy" => r.telescoping_discrepancy,
        "missing_expectations" => collect(r.missing_expectations),
        "blocked_by" => collect(r.blocked_by),
    )
end

# One channel's attribution verdict and numbers as a report entry.
function attribution_entry(r::AttributionReconciliation)
    return Dict{String, Any}(
        "channel" => String(r.channel),
        "status" => String(r.status),
        "envelope" => r.envelope,
        "attributed" => r.attributed,
        "residual" => r.residual,
        "tolerance" => isnothing(r.tolerance) ? "none" : r.tolerance,
        "blocked_by" => collect(r.blocked_by),
    )
end

# One transfer event's verdict and numbers as a report entry.
function transfer_entry(r::TransferReconciliation)
    return Dict{String, Any}(
        "event" => String(r.event),
        "status" => String(r.status),
        "topology" => String(r.topology),
        "expectation" => String(r.expectation),
        "counterparty" => isnothing(r.counterparty) ? "none" : String(r.counterparty),
        "total" => r.total,
        "tolerance" => isnothing(r.tolerance) ? "none" : r.tolerance,
        "leg_count" => r.leg_count,
        "missing_legs" => collect(r.missing_legs),
        "blocked_by" => collect(r.blocked_by),
    )
end

# One tolerance's four terms as a report entry.
tolerance_entry(t::BudgetTolerance) = Dict{String, Any}(
    "absolute" => t.absolute,
    "relative" => t.relative,
    "scale" => t.scale,
    "kappa" => t.kappa,
)

"""
    budget_report(adapter; job_id = "", float_type = "") -> Dict{String, Any}

Return the claim certificate of a run as a nested dictionary ready to be
written. It holds the configuration the ledger ran under, the tolerances and
their source, and the restart segmentation. For every control volume and
quantity it holds the parent verdict with cumulative totals, the attribution
verdict of every channel and the transfer verdict of every event, all from the
last accepted step. Before the first commit the claims section is empty and
`last_step` is 0.
"""
function budget_report(adapter::ParentBudgetAdapter; job_id = "", float_type = "")
    (; schema, ledger) = adapter
    commit = latest_commit(adapter)
    record = adapter.timestepper
    context = adapter.context
    report = Dict{String, Any}(
        "version" => REPORT_VERSION,
        "job_id" => String(job_id),
        "generated" => string(Dates.now(Dates.UTC)),
        "configuration" => Dict{String, Any}(
            "mode" => adapter.mode isa AuditMode ? "audit" : "summary",
            "attribution" => String(adapter.attribution),
            # Out-of-scope runs are refused at setup, so a run that reports
            # passed the scope check.
            "scope" => "supported",
            "backend" => backend_name(context),
            "ranks" => ClimaComms.nprocs(context),
            "float_type" => String(float_type),
            "accounting_type" => String(nameof(BUDGET_ACCOUNTING_TYPE)),
            "adapter_version" =>
                string(pkgversion(parentmodule(parentmodule(@__MODULE__)))),
            "timestepper" =>
                isnothing(record) ? "not initialised" :
                Dict{String, Any}(
                    "package_version" => string(record.package_version),
                    "algorithm" => String(record.algorithm),
                    "stages" => record.stages,
                    "fsal" => record.fsal,
                ),
            "moist" => adapter.moist,
            "slab" => adapter.slab,
            "reservoirs" =>
                [String(reservoir_name(s.reservoir)) for s in schema.reservoirs],
            "control_volumes" => [String(cv.name) for cv in schema.control_volumes],
            "channels" => [String(c.name) for c in schema.channels],
            "transfer_events" => [String(e.name) for e in schema.transfer_events],
        ),
        "tolerances" => Dict{String, Any}(
            "source" => String(adapter.tolerance_source),
            "values" =>
                isnothing(adapter.tolerances) ? "none" :
                Dict{String, Any}(
                    String(q) => tolerance_entry(t) for (q, t) in adapter.tolerances
                ),
        ),
        "restart" =>
            isnothing(adapter.transition) ? "none" :
            Dict{String, Any}(
                "transition" => String(adapter.transition.status),
                "checkpoint_step" => adapter.transition.checkpoint_step,
                "segmented" => true,
            ),
        "steps_committed" => adapter.steps_committed,
        "reductions" => adapter.reductions,
        "limitations" => collect(LIMITATIONS),
    )
    claims = Dict{String, Any}()
    if !isnothing(commit)
        for cv in schema.control_volumes
            view = Dict{String, Any}()
            for quantity in BUDGET_QUANTITIES
                parent = only(
                    filter(
                        r -> r.quantity === quantity && r.control_volume === cv.name,
                        commit.parent,
                    ),
                )
                view[String(quantity)] = Dict{String, Any}(
                    "parent" => parent_entry(parent),
                    "attribution" => [
                        attribution_entry(r) for r in commit.attribution if
                        r.quantity === quantity && r.control_volume === cv.name
                    ],
                    "transfer" => [
                        transfer_entry(r) for r in commit.transfer if
                        r.quantity === quantity && r.control_volume === cv.name
                    ],
                )
            end
            claims[String(cv.name)] = view
        end
    end
    report["claims"] = claims
    report["last_step"] = isnothing(commit) ? 0 : commit.step
    return report
end

"""
    write_budget_report(adapter, output_dir; job_id = "", float_type = "") -> String

Write the certificate as `parent_budget_report.yaml` in `output_dir` and
return its path. The caller writes on the root process only.
"""
function write_budget_report(adapter::ParentBudgetAdapter, output_dir; kwargs...)
    path = joinpath(output_dir, REPORT_FILE)
    YAML.write_file(path, budget_report(adapter; kwargs...))
    return path
end

"""
    budget_summary(adapter) -> String

Return a concise human-readable summary of the last accepted step. It has one
line per control volume and quantity with the parent verdict and residual.
Then come the attribution and transfer verdicts that are not `pass`,
`reported` or `not_applicable`, each with what blocks or fails it.
"""
function budget_summary(adapter::ParentBudgetAdapter)
    commit = latest_commit(adapter)
    io = IOBuffer()
    println(io, "Parent-budget ledger, ", adapter.mode isa AuditMode ? "audit" : "summary",
        " mode, ", adapter.steps_committed, " accepted step(s), tolerances from ",
        adapter.tolerance_source)
    isnothing(adapter.transition) ||
        println(io, "Restarted: transition ", adapter.transition.status,
            ", checkpoint step ", adapter.transition.checkpoint_step, ", record segmented")
    if isnothing(commit)
        println(io, "No step committed yet.")
        return String(take!(io))
    end
    for cv in adapter.schema.control_volumes
        println(io, "Control volume ", cv.name)
        for r in commit.parent
            r.control_volume === cv.name || continue
            println(io, "  parent ", rpad(String(r.quantity), 7),
                rpad(String(r.status), 15),
                "residual ", r.residual, "  cumulative |residual| ",
                r.cumulative_abs_residual)
            for b in r.blocked_by
                println(io, "    blocked by: ", b)
            end
        end
        for r in commit.attribution
            r.control_volume === cv.name || continue
            r.status in (:pass, :not_applicable) && continue
            println(io, "  attribution ", r.channel, " ", r.quantity, " ", r.status,
                " residual ", r.residual)
            for b in r.blocked_by
                println(io, "    blocked by: ", b)
            end
        end
        for r in commit.transfer
            r.control_volume === cv.name || continue
            r.status in (:pass, :reported, :not_applicable) && continue
            println(
                io,
                "  transfer ",
                r.event,
                " ",
                r.quantity,
                " ",
                r.status,
                " total ",
                r.total,
            )
            for b in r.blocked_by
                println(io, "    blocked by: ", b)
            end
        end
    end
    return String(take!(io))
end

"""
    failed_claims(adapter) -> Vector{String}

Return one line per claim of the last accepted step whose status is `:fail`,
naming the control volume, the claim, the channel or event where the claim
has one, and the quantity. The vector is empty when nothing failed or when
no step has been committed. The caller logs the lines at warn level, so a
failed identity is visible in a run's log and not only in the certificate.
"""
function failed_claims(adapter::ParentBudgetAdapter)
    commit = latest_commit(adapter)
    failed = String[]
    isnothing(commit) && return failed
    for r in commit.parent
        if r.status === :fail
            push!(failed, "$(r.control_volume) parent $(r.quantity)")
        end
    end
    for r in commit.attribution
        if r.status === :fail
            push!(failed, "$(r.control_volume) attribution $(r.channel) $(r.quantity)")
        end
    end
    for r in commit.transfer
        if r.status === :fail
            push!(failed, "$(r.control_volume) transfer $(r.event) $(r.quantity)")
        end
    end
    return failed
end
