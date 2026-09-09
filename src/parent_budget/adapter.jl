#####
##### Parent-budget ledger: the timestepper adapter
#####
##### The one place that knows how `ClimaTimeSteppers` builds an accepted step.
##### The transaction and reconciliation code knows nothing about processes or
##### tableaus, and the journal knows nothing about the integrator; everything
##### timestepper-specific is here, so that a change in the pinned behaviour is
##### a change to one file and to the trace test that fixes it.
#####
##### The adapter runs each accepted step as the first discrete callback. It
##### reads the accepted state and the stage tendencies the stepper cache still
##### holds. It packs every reservoir's endpoint and every collected channel's
##### envelope into one buffer and reduces that buffer once. It records the
##### envelopes as legs, commits the transaction, and opens the next one on the
##### closing endpoint. It writes nothing to the state or the cache it reads.
#####
##### It collects `COLLECTED_CHANNELS`, the two explicit channels. It does not
##### collect the implicit envelope, the final maps, the rosters or the transfer
##### legs. The schema still expects them, so each is a named blocker.

# ============================================================================
# Modes
# ============================================================================

"""
    ParentBudgetMode

How much the ledger keeps.

  - `SummaryMode`: the cumulative totals and the last step's reconciliations.
    Per-step storage is bounded, so this is the mode a long run uses.
  - `AuditMode`: every step's reconciliations as well, for locating a defect.
    Storage grows with the run, which is why it is not the default.

`off` is not a mode. It is the absence of an adapter, so that a run with the
ledger off is the run without the feature.
"""
abstract type ParentBudgetMode end

"""
    SummaryMode()

Keep the cumulative totals and the latest commit. See `ParentBudgetMode`.
"""
struct SummaryMode <: ParentBudgetMode end

"""
    AuditMode()

Keep every commit as well. See `ParentBudgetMode`.
"""
struct AuditMode <: ParentBudgetMode end

"""
    parent_budget_mode(name) -> Union{Nothing, ParentBudgetMode}

Return the mode the configuration key `parent_budget_mode` names. `"off"` is
`nothing`, `"summary"` and `"audit"` are the two modes, and anything else is an
error rather than a silent `off`. A mode object, or `nothing`, passes through.
"""
parent_budget_mode(::Nothing) = nothing
parent_budget_mode(mode::ParentBudgetMode) = mode
function parent_budget_mode(name::AbstractString)
    name == "off" && return nothing
    name == "summary" && return SummaryMode()
    name == "audit" && return AuditMode()
    return error(
        "Unknown `parent_budget_mode = $(repr(name))`; expected `off`, `summary` " *
        "or `audit`.",
    )
end

# ============================================================================
# The pinned timestepper
# ============================================================================

"""
    COLLECTED_CHANNELS

The channels this adapter captures an envelope for: the two explicit channels,
each as the tableau-weighted sum of the stage tendencies the stepper cache
holds after a step. The implicit channel is not collected.
"""
const COLLECTED_CHANNELS = (:explicit_main, :explicit_limited)

"""
    TimestepperRecord

What the adapter pinned when the integrator was initialised: the
`ClimaTimeSteppers` version, the algorithm, and the accepted weights it read.
Every certificate carries this record, and the trace test fixes the behaviour
it stands for, which together are the pin the contract asks for.
"""
struct TimestepperRecord
    package_version::VersionNumber
    algorithm::Symbol
    stages::Int
    b_exp::Vector{BUDGET_ACCOUNTING_TYPE}
    b_imp::Vector{BUDGET_ACCOUNTING_TYPE}
    fsal::Bool
end

"""
    check_algorithm(alg)

Refuse an algorithm outside the contract's scope. The adapter is written
against the IMEX-ARK stepper, which every unconstrained `IMEXAlgorithm` runs;
an `SSP`-constrained tableau and a Rosenbrock method use different steppers
with different accepted increments, and reading their caches as if they were
ARK would book the wrong numbers.
"""
function check_algorithm(alg)
    alg isa CTS.IMEXAlgorithm{CTS.Unconstrained} && return nothing
    return error(
        "The parent-budget ledger supports unconstrained IMEX-ARK algorithms " *
        "only, got $(typeof(alg)). See the timestepping methods in " *
        "docs/src/parent_budget/contract.md.",
    )
end

# The record, read from the integrator once the cache exists. The weights come
# from the cache's tableau rather than the algorithm's. The cache holds the
# tableau cast to the state's float type, and that is the one the stepper
# applies.
function timestepper_record(integrator)
    alg = integrator.alg
    check_algorithm(alg)
    tableau = integrator.cache.tableau
    b_exp = tableau.b_exp.coeffs
    b_imp = tableau.b_imp.coeffs
    return TimestepperRecord(
        pkgversion(CTS),
        isnothing(alg.name) ? :tableau : nameof(typeof(alg.name)),
        length(b_exp),
        collect(BUDGET_ACCOUNTING_TYPE, b_exp),
        collect(BUDGET_ACCOUNTING_TYPE, b_imp),
        CTS.is_fsal(alg),
    )
end

# ============================================================================
# The adapter
# ============================================================================

"""
    ParentBudgetAdapter

The ledger and everything it needs to run inside a simulation: the schema and
the ledger built from it, the one packet the step reduces, the channels the
adapter collects, the record of the timestepper, and what has been committed.

`reductions` counts the packets this adapter has reduced, which a test compares
with the number of accepted steps. `commits` holds every commit in `AuditMode`
and stays empty in `SummaryMode`; `last_commit` is the latest either way.

The mode is a field rather than a type parameter on purpose. The adapter rides
in the cache, whose type every tendency function specialises on, so a mode in
the type would compile the whole model twice for two runs that differ only in
what they keep.
"""
mutable struct ParentBudgetAdapter{S, C}
    mode::ParentBudgetMode
    schema::BudgetSchema
    surface_temperature::S
    context::C
    ledger::BudgetLedger{BUDGET_ACCOUNTING_TYPE}
    layout::BudgetPacketLayout
    packet::BudgetPacket
    channels::Tuple{Vararg{Symbol}}
    timestepper::Union{Nothing, TimestepperRecord}
    tolerances::Nothing
    steps_committed::Int
    reductions::Int
    last_commit::Union{Nothing, BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
    commits::Vector{BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
end

"""
    build_parent_budget(mode, atmos, Y; ode_config, restart) -> Union{Nothing, ParentBudgetAdapter}

Build the adapter for a run, or return `nothing` when `mode` is `off`.

Everything the ledger expects is fixed here, before the cache is built and
before the first step. The configuration is checked against the supported
scope. The schema is built from the coverage registry. The packet layout
follows from the schema and the collected channels.

A restart is refused. A restored state is a transition no transaction
produced, and the ledger has no transaction to book it in. Reading a restart
file into a fresh ledger would either charge the restoration to the first step
or silently absorb it.
"""
build_parent_budget(mode, atmos, Y; kwargs...) =
    build_parent_budget(parent_budget_mode(mode), atmos, Y; kwargs...)
build_parent_budget(::Nothing, atmos, Y; kwargs...) = nothing
function build_parent_budget(
    mode::ParentBudgetMode,
    atmos,
    Y;
    ode_config,
    restart::Bool,
)
    restart && error(
        "The parent-budget ledger does not support restarts yet: a restored " *
        "state is a transition no transaction produced, and the ledger has no " *
        "transaction to book it in. Pass `parent_budget_mode = \"off\"` for this run.",
    )
    check_algorithm(ode_config)
    implicit_solve = !isnothing(ode_config.newtons_method)
    schema = budget_schema(atmos; dss = do_dss(axes(Y.c)), implicit_solve, restart)
    layout = budget_packet_layout(schema, COLLECTED_CHANNELS)
    return ParentBudgetAdapter(
        mode,
        schema,
        atmos.surface.temperature,
        budget_context(Y),
        BudgetLedger{BUDGET_ACCOUNTING_TYPE}(schema),
        layout,
        BudgetPacket(layout),
        COLLECTED_CHANNELS,
        nothing,
        nothing,
        0,
        0,
        nothing,
        BudgetCommit{BUDGET_ACCOUNTING_TYPE}[],
    )
end

"""
    parent_budget_callbacks(adapter) -> Tuple

Return the discrete callback that drives the ledger, as a one-element tuple to
splice in front of every other callback, or an empty tuple for `nothing`.

The callback's `initialize` reads the opening endpoint after the integrator has
initialised its cache and before any other callback has run, which is where
`B⁰` is defined. Its `affect!` commits every accepted step. Its condition is
always true. The ledger has no cadence of its own, because a step it skipped
would be a change nobody accounted for.
"""
parent_budget_callbacks(::Nothing) = ()
function parent_budget_callbacks(adapter::ParentBudgetAdapter)
    condition = (u, t, integrator) -> true
    affect! = integrator -> commit_step!(adapter, integrator)
    initialize = (cb, u, t, integrator) -> initialize_ledger!(adapter, integrator)
    return (CTS.DiscreteCallback(condition, affect!; initialize),)
end

# The first transaction opens on a measured endpoint: there is no previous
# closing endpoint to reuse. This is one collective, paid once per run.
function initialize_ledger!(adapter::ParentBudgetAdapter, integrator)
    adapter.timestepper = timestepper_record(integrator)
    endpoints = budget_endpoints(
        integrator.u,
        adapter.schema,
        adapter.surface_temperature,
        0,
    )
    adapter.reductions += 1
    open_transaction!(adapter.ledger, endpoints)
    return nothing
end

"""
    commit_step!(adapter, integrator)

Account for the accepted step the integrator has just finished.

Runs before every other callback, so the state it reads is the finalized
accepted state and the stage tendencies in the stepper cache are this step's.
The packet is reset, filled with every reservoir's endpoint and every collected
channel's envelope, and reduced once. The closing endpoints are unpacked from
it, the envelopes are recorded as legs, and the transaction is committed. The
commit is kept, and the next transaction opens on the closing endpoint without
measuring it again.
"""
function commit_step!(adapter::ParentBudgetAdapter, integrator)
    (; schema, ledger, packet, surface_temperature) = adapter
    step = ledger.step
    Y = integrator.u

    reset_packet!(packet)
    for spec in schema.reservoirs
        fill_endpoint_slots!(packet, Y, schema, spec, surface_temperature)
    end
    fill_envelope_slots!(packet, adapter, integrator)
    reduce_packet!(adapter.context, packet)
    adapter.reductions += 1

    closing = budget_endpoints(packet, schema, step)
    record_envelopes!(adapter, packet, step)
    commit = commit_transaction!(ledger, closing; tolerances = adapter.tolerances)

    adapter.last_commit = commit
    adapter.mode isa AuditMode && push!(adapter.commits, commit)
    adapter.steps_committed += 1
    open_transaction!(ledger)
    return nothing
end

# ============================================================================
# Envelopes from the stepper cache
# ============================================================================

# The stages whose weight is nonzero, and the weights themselves with `dt`
# folded in, as tuples so the weighted sum below is a fixed-size loop. A stage
# with a nonzero weight is always stored in the cache: the stepper allocates
# storage for every stage whose column or weight is nonzero.
function stage_weights(coefficients, dt)
    indices = Tuple(findall(!iszero, coefficients))
    weights = map(
        i -> BUDGET_ACCOUNTING_TYPE(dt) * BUDGET_ACCOUNTING_TYPE(coefficients[i]),
        indices,
    )
    return indices, weights
end

# The pointwise accepted increment of one field: each stage value widened to the
# accounting type before it is weighted, so the accumulation happens there.
@inline function weighted_stage_value(
    weights::NTuple{N, BUDGET_ACCOUNTING_TYPE},
    values::Vararg{Any, N},
) where {N}
    total = zero(BUDGET_ACCOUNTING_TYPE)
    for k in 1:N
        total += weights[k] * BUDGET_ACCOUNTING_TYPE(values[k])
    end
    return total
end

# A lazy broadcast of the weighted sum over the stage fields, for one local
# reduction. The closure captures the weights, which are plain numbers, so the
# broadcast is as cheap on a device as any other pointwise expression.
function weighted_stage_sum(weights, fields)
    return Base.Broadcast.broadcasted(
        (values...) -> weighted_stage_value(weights, values...),
        fields...,
    )
end

# The prognostic field one parent quantity is integrated from.
atmosphere_field_name(quantity::Symbol) =
    quantity === :mass ? :ρ : quantity === :water ? :ρq_tot : :ρe_tot

# The local, accounting-precision integral of a channel's accepted increment in
# one reservoir for one quantity. `tendencies` is the cache's container of stage
# tendencies for the channel, indexed by stage.
function local_envelope(
    tendencies,
    indices,
    weights,
    reservoir::Symbol,
    quantity::Symbol,
    surface_temperature,
)
    if reservoir === ATMOSPHERE_ENDPOINT_GROUP
        name = atmosphere_field_name(quantity)
        fields = map(i -> getproperty(tendencies[i].c, name), indices)
        return local_volume_integral(weighted_stage_sum(weights, fields))
    end
    if quantity === :energy
        fields = map(i -> tendencies[i].sfc.T, indices)
        return local_boundary_integral(weighted_stage_sum(weights, fields)) *
               to_accounting(slab_heat_capacity(surface_temperature))
    end
    # The slab's water and its mass are one field seen twice.
    fields = map(i -> tendencies[i].sfc.water, indices)
    return local_boundary_integral(weighted_stage_sum(weights, fields))
end

# The stepper cache's container of stage tendencies for a collected channel.
function channel_tendencies(cache, channel::Symbol)
    channel === :explicit_main && return cache.T_exp
    channel === :explicit_limited && return cache.T_lim
    return error("The adapter does not collect channel $channel from the stepper cache.")
end

# Every collected channel's envelope in every reservoir it writes, as local
# values, into the packet. Applicability comes from the schema: a quantity the
# reservoir does not own gets an inapplicable slot, never a zero.
function fill_envelope_slots!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    integrator,
)
    (; schema, surface_temperature) = adapter
    cache = integrator.cache
    dt = float(integrator.dt)
    indices, weights = stage_weights(cache.tableau.b_exp.coeffs, dt)
    for channel in adapter.channels
        tendencies = channel_tendencies(cache, channel)
        for reservoir in channel_spec(schema, channel).reservoirs
            group = envelope_group(channel, reservoir)
            for quantity in BUDGET_QUANTITIES
                if quantity_applicable(schema, reservoir, quantity)
                    value = local_envelope(
                        tendencies,
                        indices,
                        weights,
                        reservoir,
                        quantity,
                        surface_temperature,
                    )
                    set_local!(packet, group, quantity, value)
                else
                    set_inapplicable!(packet, group, quantity)
                end
            end
        end
    end
    return nothing
end

# One envelope leg per collected channel and reservoir, from the reduced packet.
function record_envelopes!(adapter::ParentBudgetAdapter, packet::BudgetPacket, step::Int)
    (; schema, ledger) = adapter
    FT = BUDGET_ACCOUNTING_TYPE
    for channel in adapter.channels
        source = Symbol("adapter.", channel)
        for reservoir in channel_spec(schema, channel).reservoirs
            group = envelope_group(channel, reservoir)
            component(quantity) =
                quantity_applicable(schema, reservoir, quantity) ?
                measured(
                    packet_value(packet, group, quantity);
                    method = :tableau_weighted_stage_sum,
                    source,
                    route = :packed_global_reduction,
                ) : not_applicable(FT; source = :schema)
            leg = BudgetLeg{FT}(;
                event = Symbol("env.", channel),
                leg = :envelope,
                reservoir = endpoint_reservoir(reservoir),
                channel,
                level = ChannelEnvelope(),
                mass = component(:mass),
                water = component(:water),
                energy = component(:energy),
                path = EquationTerm(),
                process = :envelope,
                phase = channel,
                step,
                measured_at = :accepted_increment,
            )
            record_leg!(ledger, leg)
        end
    end
    return nothing
end

# ============================================================================
# Reading the results
# ============================================================================

"""
    latest_commit(adapter) -> Union{Nothing, BudgetCommit}

Return the reconciliations of the last accepted step, or `nothing` before the
first.
"""
latest_commit(adapter::ParentBudgetAdapter) = adapter.last_commit

"""
    parent_status(adapter, quantity, control_volume) -> Symbol

Return the parent claim's status for one quantity in one control volume at the
last commit: `:pass`, `:fail`, `:blocked` or `:not_applicable`.
"""
function parent_status(
    adapter::ParentBudgetAdapter,
    quantity::Symbol,
    control_volume::Symbol,
)
    commit = latest_commit(adapter)
    isnothing(commit) && error("No step has been committed yet.")
    for r in commit.parent
        r.quantity === quantity && r.control_volume === control_volume && return r.status
    end
    return error("No parent reconciliation for $quantity in $control_volume.")
end
