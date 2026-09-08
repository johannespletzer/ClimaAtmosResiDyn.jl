#####
##### Parent-budget ledger: the timestepper adapter
#####
##### The one place that knows how `ClimaTimeSteppers` builds an accepted step.
##### The transaction and reconciliation code knows nothing about processes or
##### tableaus, and the journal knows nothing about the integrator; everything
##### timestepper-specific is here, so that a change in the pinned behaviour is
##### a change to one file and to the trace test that fixes it.
#####
##### The adapter sees a step twice. During the step it sits behind the
##### explicit tendency, the `lim!`, `dss!`, `constrain_state!`,
##### `initialize_imp!` and `T_post_imp!` hooks as meters that read the state
##### before and after each call and never write it, and in audit mode it
##### listens to the applied-update events the tendency code brackets its
##### processes with. After the step it runs as the first discrete callback: it
##### reads the stage tendencies the stepper cache still holds, packs every
##### reservoir's endpoint, every channel's envelope, the final maps, the
##### process rows and whatever the meters measured into one buffer, reduces
##### that buffer once, records the legs, commits the transaction, and opens
##### the next one on the closing endpoint.
#####
##### Which hook call is the final map and which is a stage firing is decided
##### by position in the step, never by time: the last stage and the final
##### assembly share the same `t`. The positions come from a template built from
##### the tableau and the constraint cadence, and the meters check the stepper
##### against it as it runs.

# ============================================================================
# Modes
# ============================================================================

"""
    ParentBudgetMode

How much the ledger measures and keeps.

  - `SummaryMode`: the endpoints, the channel envelopes and the final maps, which
    is what the parent identity needs, plus the cumulative totals and the last
    step's reconciliations. Per-step storage is bounded, so this is the mode a
    long run uses.
  - `AuditMode`: everything `SummaryMode` measures, and in addition the
    process rows of every collected channel from the applied-update events the
    tendency code brackets them with, every intermediate hook firing as a stage
    observation, the algebraic solve defect and the post-implicit correction of
    every implicit stage, and every step's reconciliations. It costs two local
    integrals per bracketed process and stage, one extra implicit tendency
    evaluation per implicit stage, and storage that grows with the run, which
    is why it is not the default.

`off` is not a mode. It is the absence of an adapter, so that a run with the
ledger off is the run without the feature.
"""
abstract type ParentBudgetMode end

"""
    SummaryMode()

Measure what the parent identity needs and keep the latest commit. See
`ParentBudgetMode`.
"""
struct SummaryMode <: ParentBudgetMode end

"""
    AuditMode()

Measure every firing, every bracketed process, the solve defect and the
correction, and keep every commit. See `ParentBudgetMode`.
"""
struct AuditMode <: ParentBudgetMode end

"""
    parent_budget_attribution(name) -> Symbol

The attribution the configuration key `parent_budget_attribution` names:
`:net` books each process row's signed amount, `:gross` keeps its positive
and negative parts beside it. Anything else is an error rather than a silent
default.
"""
function parent_budget_attribution(name)
    attribution = Symbol(name)
    attribution in (:net, :gross) && return attribution
    return error(
        "Unknown `parent_budget_attribution = $(repr(name))`; expected `net` " *
        "or `gross`.",
    )
end

"""
    parent_budget_mode(name) -> Union{Nothing, ParentBudgetMode}

The mode the configuration key `parent_budget_mode` names: `"off"` is
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

The channels the adapter captures an envelope for, each as the tableau-weighted
sum of the stage tendencies the stepper cache holds after a step: the two
explicit channels with the explicit weights, and the implicit channel with the
implicit weights applied to the stored effective implicit tendencies.
"""
const COLLECTED_CHANNELS = (:explicit_main, :explicit_limited, :implicit)

"""
    METERED_HOOKS

The `ClimaODEFunction` hooks the adapter meters: the explicit tendency, whose
position says which stage's applied-update events are being measured, the
three hooks that write the state, the implicit-stage initialiser, which tells
the adapter the stage's `dtγ`, and the post-implicit correction, which is
where the Newton-solved stage is visible.
"""
const METERED_HOOKS = (
    :T_exp_T_lim!,
    :lim!,
    :dss!,
    :constrain_state!,
    :initialize_imp!,
    :T_post_imp!,
)

"""
    FINAL_MAP_HOOKS

The hooks whose last call of a step is a final accepted-state map.
"""
const FINAL_MAP_HOOKS = (:lim!, :dss!, :constrain_state!)

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
# from the cache's tableau rather than the algorithm's, because that is the one
# the stepper applies when a tableau is cast to the state's float type.
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
# The hook template
# ============================================================================

"""
    HookCall

One expected firing of a metered hook within an accepted step: which hook, on
which stage (`0` for the final assembly), in which role, and as which
occurrence of that hook in the step.

The roles say what the firing's change means:

  - `:stage` is the limiter on a stage value, `:pre_solve` the DSS and
    constraint on the assembled stage value, and `:post_init` the DSS and
    constraint after the implicit-stage initialiser. None of these is additive:
    each changes the array a later evaluation reads and reaches the endpoint
    only through the tableau. They are stage observations.
  - `:post_newton` is the DSS or constraint on the Newton-solved stage. The
    stepper differences the stage after it, so its change is inside the stored
    implicit tendency and enters the accepted update with weight `b_imp[i]/γ`.
  - `:initialize` and `:correction` are the initialiser and the post-implicit
    correction, metered for the stage's `dtγ` and for the solved stage.
  - `:evaluate` is the explicit tendency evaluation of a stage, inside which
    the applied-update events of that stage fire.
  - `:final` is the last call of a state-writing hook, on the accepted state.
"""
struct HookCall
    hook::Symbol
    stage::Int
    role::Symbol
    occurrence::Int
end

"""
    HookTemplate

The metered hook firings of one accepted step, in order, as
`ClimaTimeSteppers` 0.10 runs them for an unconstrained IMEX-ARK tableau. Built
once from the tableau, the constraint cadence and which hooks are wired, and
checked against the stepper as it runs: a hook that fires more often than the
template says, or fewer times by the end of the step, is an error, because the
meaning of every measured firing rests on its position.
"""
struct HookTemplate
    calls::Vector{HookCall}
    per_hook::Dict{Symbol, Vector{Int}}
    implicit_stages::Vector{Int}
    explicit_stages::Vector{Int}
end

# Whether the constraint handler fires on a signal, following the signal
# hierarchy `EndOfStep <: EndOfStage <: WithDSS`.
function constraint_fires(cadence::Symbol, signal::Symbol)
    cadence === :dss && return true
    cadence === :stage && return signal in (:end_of_stage, :end_of_step)
    return signal === :end_of_step
end

"""
    hook_template(tableau, cadence, has_post_implicit, has_initializer, fsal)

The template for one step. Mirrors `step_u!` in `imex_ark.jl`: for every stage
after the first, the limiter and the DSS on the assembled value; for an implicit
stage, the initialiser, a DSS, the Newton solve, the correction when wired, and
the post-Newton DSS, each with the constraint firings the cadence selects; then
the explicit tendency evaluation of the stage, wherever a later stage or the
accepted update reads it; then the final limiter, DSS and constraint on the
accepted state. A first-same-as-last tableau skips the post-Newton constraint
at its last stage, because the end-of-step firing covers the same state.

`explicit_stages` are the stages whose explicit tendency enters the accepted
update with a nonzero weight, which is where a process row of an explicit
channel is booked; `implicit_stages` are the stages with an implicit solve.
"""
function hook_template(
    tableau,
    cadence::Symbol,
    has_post_implicit::Bool,
    has_initializer::Bool,
    fsal::Bool,
)
    a_exp = tableau.a_exp.coeffs
    b_exp = tableau.b_exp.coeffs
    a_imp = tableau.a_imp.coeffs
    s = length(tableau.b_imp.coeffs)
    calls = HookCall[]
    counts = Dict{Symbol, Int}(hook => 0 for hook in METERED_HOOKS)
    implicit_stages = Int[]
    explicit_stages = Int[]
    push_call!(hook, stage, role) =
        push!(calls, HookCall(hook, stage, role, counts[hook] += 1))
    for i in 1:s
        implicit = !iszero(a_imp[i, i])
        if i != 1
            push_call!(:lim!, i, :stage)
            push_call!(:dss!, i, :pre_solve)
            top_signal = implicit ? :with_dss : :end_of_stage
            constraint_fires(cadence, top_signal) &&
                push_call!(:constrain_state!, i, :pre_solve)
        end
        if implicit
            push!(implicit_stages, i)
            if has_initializer
                push_call!(:initialize_imp!, i, :initialize)
                push_call!(:dss!, i, :post_init)
                constraint_fires(cadence, :with_dss) &&
                    push_call!(:constrain_state!, i, :post_init)
            end
            has_post_implicit && push_call!(:T_post_imp!, i, :correction)
            push_call!(:dss!, i, :post_newton)
            if !(i == s && fsal)
                constraint_fires(cadence, :end_of_stage) &&
                    push_call!(:constrain_state!, i, :post_newton)
            end
        end
        # The explicit tendency of a stage is evaluated when a later stage or
        # the accepted update reads it, as `evaluate_stage_tendencies!` does.
        if any(!iszero, a_exp[:, i]) || !iszero(b_exp[i])
            push_call!(:T_exp_T_lim!, i, :evaluate)
        end
        iszero(b_exp[i]) || push!(explicit_stages, i)
    end
    push_call!(:lim!, 0, :final)
    push_call!(:dss!, 0, :final)
    push_call!(:constrain_state!, 0, :final)
    per_hook = Dict{Symbol, Vector{Int}}(hook => Int[] for hook in METERED_HOOKS)
    for (index, call) in enumerate(calls)
        push!(per_hook[call.hook], index)
    end
    return HookTemplate(calls, per_hook, implicit_stages, explicit_stages)
end

# ============================================================================
# Process rows and applied-update events
# ============================================================================

"""
    EVENT_PREFIXES

The coverage registry's event-id prefix of each collected channel, so that a
decomposition leg's event is the row's id in the coverage table.
"""
const EVENT_PREFIXES = Dict(
    :explicit_main => "expl.",
    :explicit_limited => "lim_chan.",
    :implicit => "impl.",
)

# Which metered evaluation feeds a channel: the explicit tendency evaluation
# writes both explicit channels, the audit evaluation at the solved stage the
# implicit one.
evaluation_kind(channel::Symbol) = channel === :implicit ? :implicit : :explicit

# A roster row the adapter measures through an applied-update event, as
# opposed to one it books from the registry's declaration or meters at a hook.
measured_row(row::ProcessRowSpec) =
    !isnothing(row.event) && :measured in row.dispositions

# A hook-metered row of the implicit channel, booked by `record_audit_legs!`.
is_stage_row(row::ProcessRowSpec) = row.process in STAGE_ROWS

# The stages a measured row of a channel is booked at: the weighted explicit
# stages for an explicit channel, the solved stages for the implicit one.
row_stages(template::HookTemplate, channel::Symbol) =
    channel === :implicit ? template.implicit_stages : template.explicit_stages

# The accepted weight of a stage's applied update in a channel.
function row_weight(tableau, channel::Symbol, stage::Int, dt)
    coefficients = channel === :implicit ? tableau.b_imp.coeffs : tableau.b_exp.coeffs
    return BUDGET_ACCOUNTING_TYPE(dt) * BUDGET_ACCOUNTING_TYPE(coefficients[stage])
end

process_row_group(channel::Symbol, process::Symbol, stage::Int) =
    Symbol("row.", channel, ".", process, ".", stage)
gross_group(channel::Symbol, process::Symbol, stage::Int, part::Symbol) =
    Symbol("gross.", part, ".", channel, ".", process, ".", stage)

# The packet group holding the arithmetic magnitudes of a measured group.
magnitude_group(group::Symbol) = Symbol("magnitude.", group)

# The slots of one measured group and of its magnitudes.
function push_measured_group!(slots, group::Symbol)
    for quantity in BUDGET_QUANTITIES
        push!(slots, (group, quantity))
    end
    for quantity in BUDGET_QUANTITIES
        push!(slots, (magnitude_group(group), quantity))
    end
    return nothing
end

# Every roster row with a measured quantity is either metered at a hook or
# named by an event that brackets it in the atmosphere's explicit or implicit
# tendency. A row that is neither could never be recorded, and the schema
# would block on it forever without saying why, so it is refused here.
function check_roster_events(schema::BudgetSchema)
    for channel in COLLECTED_CHANNELS
        has_channel(schema, channel) || continue
        for row in channel_spec(schema, channel).processes
            is_stage_row(row) && continue
            :measured in row.dispositions || continue
            isnothing(row.event) && error(
                "Coverage row $(row.process) of channel $channel declares a " *
                "measured quantity but names no applied-update event, so " *
                "nothing could ever record it.",
            )
            row.reservoir === ATMOSPHERE_ENDPOINT_GROUP || error(
                "Coverage row $(row.process) of channel $channel is measured " *
                "in $(row.reservoir), and the adapter measures events in the " *
                "atmosphere only.",
            )
            channel === :explicit_limited && error(
                "Coverage row $(row.process) of the limited channel is " *
                "measured, but an applied-update event reads the main " *
                "explicit tendency and not the limited one.",
            )
        end
    end
    return nothing
end

# The labels whose brackets the adapter integrates: those measuring a roster
# row or a transfer leg in this configuration. Every other label is checked
# and skipped, so a bracket around a process the configuration does not run
# costs nothing.
function active_events(schema::BudgetSchema)
    events = Set{Symbol}()
    for channel in COLLECTED_CHANNELS
        has_channel(schema, channel) || continue
        for row in channel_spec(schema, channel).processes
            measured_row(row) && push!(events, row.event)
        end
    end
    for spec in schema.transfer_events, (reservoir, _) in spec.modeled_legs
        push!(events, transfer_leg_event(spec.name, reservoir))
    end
    return events
end

# The evaluation a transfer leg is measured in follows the channel the schema
# applies it through, and the bracket that measures it must fire there.
leg_evaluation(spec::TransferEventSpec, reservoir::Symbol, leg::Symbol) =
    evaluation_kind(leg_channel(spec, reservoir, leg))

# The channel a bracket's own total in one evaluation belongs to.
evaluation_channel(kind::Symbol) = kind === :implicit ? :implicit : :explicit_main

transfer_leg_group(event::Symbol, reservoir::Symbol, leg::Symbol, stage::Int) =
    Symbol("leg.", event, ".", reservoir, ".", leg, ".", stage)
bracket_group(label::Symbol, reservoir::Symbol, stage::Int) =
    Symbol("bracket.", label, ".", reservoir, ".", stage)

# Every (label, reservoir) pair under which some declared transfer leg is read
# from a flux field, with the evaluation it fires in: the bracket's own total
# there is kept beside the legs as a check. A leg that is the bracket's total
# needs no check against itself.
function bracket_totals(schema::BudgetSchema)
    totals = Dict{Tuple{Symbol, Symbol}, Symbol}()
    for spec in schema.transfer_events, (reservoir, leg) in spec.modeled_legs
        is_bracket_total(spec.name, reservoir) && continue
        label = transfer_leg_event(spec.name, reservoir)
        kind = leg_evaluation(spec, reservoir, leg)
        current = get(totals, (label, reservoir), kind)
        current === kind || error(
            "The applied-update event $label measures legs in $reservoir " *
            "from both the explicit and the implicit evaluation.",
        )
        totals[(label, reservoir)] = kind
    end
    return totals
end

"""
    TransferCheck

The bracket's own total in one reservoir at one stage beside the sum of the
transfer legs read from flux fields inside it, both weighted as they enter
the accepted step: radiation's two crossings against what the atmosphere
integrated, and the slab's turbulent, radiative and prescribed fluxes against
what the slab tendency applied. Their difference is kept, never absorbed, and
no identity reads it.
"""
struct TransferCheck{FT}
    event::Symbol
    reservoir::Symbol
    stage::Int
    bracket::NTuple{3, FT}
    legs::NTuple{3, FT}
end

"""
    Measurement

Two triples in `BUDGET_QUANTITIES` order: what a meter measured, and the
arithmetic magnitude of each amount, which is the integral of the absolute
value of what was summed to produce it. A before/after difference of two
stage integrals has the magnitude of both integrals; an applied update
measured pointwise has the integral of its absolute value. The magnitudes
travel with the amounts into the packet and onto the legs, where the
tolerance's arithmetic term reads them.

For an applied-update event the two triples are its positive and negative
parts instead, from which the amount and the magnitude follow as their sum
and their difference.
"""
const Measurement = NTuple{2, NTuple{3, BUDGET_ACCOUNTING_TYPE}}

"""
    GrossRecord

The positive and negative parts of one process row's applied update at one
stage, weighted as the row's leg is, kept under
`parent_budget_attribution = gross`. A diagnostic beside the leg, never a term:
the parts sum to the leg's net amount and the identities use the net. The
parts are those of the weighted contribution, so `positive` is never negative
whatever the sign of the stage weight.
"""
struct GrossRecord{FT}
    event::Symbol
    channel::Symbol
    process::Symbol
    stage::Int
    weight::FT
    positive::NTuple{3, FT}
    negative::NTuple{3, FT}
end

# ============================================================================
# The adapter
# ============================================================================

"""
    ParentBudgetAdapter

The ledger and everything it needs to run inside a simulation: the schema and
the ledger built from it, the one packet the step reduces, the hook template,
the record of the timestepper, the tolerances, what the meters and the
applied-update events measured in the current step, and what has been
committed. `last_commit`, `last_legs`, `last_observations` and `last_gross`
hold the latest step's results in every mode; `commits` holds every commit in
`AuditMode` only. `reductions` counts the packets reduced, which a test
compares with the number of accepted steps.

`tolerance_source` says where the tolerances came from: `:explicit` from
the caller, `:calibration_table` from the committed κ table, `:none`.
`restart` says the run restored a checkpoint, `checkpoint` holds the
endpoints that checkpoint carried, and `transition` what the first
transaction found when it compared the restored state with them. `events`
are the applied-update labels that measure a roster row in this
configuration. `evaluation`, `evaluation_stage`, `open_event` and `seen`
say which tendency evaluation is being metered, if any, and which events it
has opened, which is how a nested, repeated or unknown bracket is refused
where it happens. `snapshot` holds the copies of the parent tendency fields an
open event is differenced against, the slab's included when there is one.
`legs` are the transfer legs read inside the events of the current step, and
`last_transfer_checks` the bracket checks of the last one. `fault` is test
instrumentation, see `inject_fault!`.

The mode is a field rather than a type parameter on purpose. The adapter rides
in the cache, whose type every tendency function specialises on, so a mode in
the type would compile the whole model twice for two runs that differ only in
what they keep.

The per-step fields are cleared at every commit, so their storage is bounded
by the template and never by the run's length.
"""
mutable struct ParentBudgetAdapter{S, C, T, G}
    mode::ParentBudgetMode
    attribution::Symbol
    schema::BudgetSchema
    surface_temperature::S
    context::C
    moist::Bool
    ledger::BudgetLedger{BUDGET_ACCOUNTING_TYPE}
    template::HookTemplate
    layout::BudgetPacketLayout
    packet::BudgetPacket
    channels::Tuple{Vararg{Symbol}}
    tolerances::Union{Nothing, Dict{Symbol, BudgetTolerance{BUDGET_ACCOUNTING_TYPE}}}
    tolerance_source::Symbol
    scratch_tendency::T
    snapshot::G
    slab::Bool
    events::Set{Symbol}
    restart::Bool
    checkpoint::Union{Nothing, CheckpointEndpoints}
    transition::Union{Nothing, RestartTransition}
    timestepper::Union{Nothing, TimestepperRecord}
    stepper_cache::Any
    # Per-step meter state. A measurement is a triple of amounts and a triple
    # of arithmetic magnitudes, see `Measurement`.
    calls::Dict{Symbol, Int}
    before::NTuple{3, BUDGET_ACCOUNTING_TYPE}
    dtγ::Dict{Int, BUDGET_ACCOUNTING_TYPE}
    final_changes::Dict{Symbol, Measurement}
    folded::Vector{Tuple{Symbol, Int, Measurement}}
    observations::Vector{Tuple{HookCall, NTuple{3, BUDGET_ACCOUNTING_TYPE}}}
    defects::Vector{Tuple{Int, Measurement}}
    slab_defects::Vector{Tuple{Int, Measurement}}
    corrections::Vector{Tuple{Int, Measurement}}
    # Per-step event state, keyed by evaluation kind, event and stage: the
    # positive and negative parts of what the event applied.
    parts::Dict{Tuple{Symbol, Symbol, Int}, Measurement}
    slab_parts::Dict{Tuple{Symbol, Symbol, Int}, Measurement}
    unmeasured::Vector{Tuple{Symbol, Symbol, Int}}
    # Per-step transfer legs, keyed by event id, reservoir, leg and stage.
    legs::Dict{Tuple{Symbol, Symbol, Symbol, Int}, LegMeasurement}
    # The evaluation being metered, if any.
    evaluation::Symbol
    evaluation_stage::Int
    open_event::Symbol
    seen::Set{Symbol}
    fault::Union{Nothing, Tuple{Symbol, Symbol}}
    # Results.
    steps_committed::Int
    reductions::Int
    last_commit::Union{Nothing, BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
    last_legs::Vector{BudgetLeg{BUDGET_ACCOUNTING_TYPE}}
    last_observations::Vector{StageObservation{BUDGET_ACCOUNTING_TYPE}}
    last_gross::Vector{GrossRecord{BUDGET_ACCOUNTING_TYPE}}
    last_transfer_checks::Vector{TransferCheck{BUDGET_ACCOUNTING_TYPE}}
    commits::Vector{BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
end

is_audit(adapter::ParentBudgetAdapter) = adapter.mode isa AuditMode

"""
    parent_budget_tolerances(tolerances) -> Union{Nothing, Dict}

Check a caller's tolerance table: `nothing`, or a mapping from a subset of
`BUDGET_QUANTITIES` to `BudgetTolerance`s in the accounting type. A caller's
table overrides the committed calibration table; without either a run
reports every numeric verdict as `blocked`.
"""
parent_budget_tolerances(::Nothing) = nothing
function parent_budget_tolerances(tolerances)
    table = Dict{Symbol, BudgetTolerance{BUDGET_ACCOUNTING_TYPE}}()
    for (quantity, tolerance) in pairs(tolerances)
        quantity in BUDGET_QUANTITIES || error(
            "Parent-budget tolerance for $quantity, which is not one of " *
            "$(BUDGET_QUANTITIES).",
        )
        tolerance isa BudgetTolerance || error(
            "Parent-budget tolerance for $quantity is a $(typeof(tolerance)); " *
            "expected a BudgetTolerance.",
        )
        table[quantity] = BudgetTolerance(;
            absolute = BUDGET_ACCOUNTING_TYPE(tolerance.absolute),
            relative = BUDGET_ACCOUNTING_TYPE(tolerance.relative),
            scale = BUDGET_ACCOUNTING_TYPE(tolerance.scale),
            kappa = BUDGET_ACCOUNTING_TYPE(tolerance.kappa),
        )
    end
    return table
end

# The rows of the implicit channel's roster the adapter books per stage, in the
# order their slots are laid out. Only the rows the schema declares exist.
const STAGE_ROWS =
    (:solve_defect, :post_implicit_correction, :folded_dss, :folded_constraint)

function stage_rows(schema::BudgetSchema, reservoir::Symbol = ATMOSPHERE_ENDPOINT_GROUP)
    has_channel(schema, :implicit) || return Symbol[]
    spec = channel_spec(schema, :implicit)
    return [
        process for process in STAGE_ROWS if
        !isnothing(process_row(spec, process, reservoir))
    ]
end

# A final map that some configured path writes is measured; one that writes no
# parent field is booked as the invariant zero its rows prove.
hook_is_measured(schema::BudgetSchema, hook::Symbol) =
    :measured in final_map_spec(schema, hook).dispositions

final_map_group(hook::Symbol) = Symbol("finalmap.", hook)
stage_row_group(process::Symbol, stage::Int) = Symbol("decomp.", process, ".", stage)
stage_row_group(process::Symbol, stage::Int, reservoir::Symbol) =
    reservoir === ATMOSPHERE_ENDPOINT_GROUP ? stage_row_group(process, stage) :
    Symbol("decomp.", process, ".", reservoir, ".", stage)
observation_group(call::HookCall) =
    Symbol("obs.", call.hook, ".", call.role, ".", call.stage, ".", call.occurrence)

# Whether a firing of a state-writing hook is a stage observation rather than a
# final map or a folded contribution.
is_observation(call::HookCall) =
    call.hook in FINAL_MAP_HOOKS && call.role in (:stage, :pre_solve, :post_init)

"""
    adapter_packet_layout(schema, template, mode, attribution)

The layout of the one packet an accepted step reduces: the endpoint slots, the
envelope slots of every collected channel in every reservoir it writes, the
slots of the final maps that are measured, and in `AuditMode` the slots of the
per-stage implicit rows, of every measured process row at every stage it is
booked at, with its gross parts under `:gross`, and of every stage
observation. Every measured group except the endpoints and the observations
has a magnitude group beside it. Fixed from the schema, the template, the
mode and the attribution, so every rank builds the same layout before the
first step.
"""
function adapter_packet_layout(
    schema::BudgetSchema,
    template::HookTemplate,
    mode::ParentBudgetMode,
    attribution::Symbol,
)
    layout = budget_packet_layout(schema, COLLECTED_CHANNELS)
    slots = copy(layout.slots)
    for channel in COLLECTED_CHANNELS
        for reservoir in channel_spec(schema, channel).reservoirs,
            quantity in BUDGET_QUANTITIES

            push!(slots, (magnitude_group(envelope_group(channel, reservoir)), quantity))
        end
    end
    for hook in FINAL_MAP_HOOKS
        hook_is_measured(schema, hook) || continue
        push_measured_group!(slots, final_map_group(hook))
    end
    if mode isa AuditMode
        for process in stage_rows(schema), stage in template.implicit_stages
            push_measured_group!(slots, stage_row_group(process, stage))
        end
        for process in stage_rows(schema, SLAB_SURFACE_ENDPOINT_GROUP),
            stage in template.implicit_stages

            push_measured_group!(
                slots,
                stage_row_group(process, stage, SLAB_SURFACE_ENDPOINT_GROUP),
            )
        end
        for channel in COLLECTED_CHANNELS
            has_channel(schema, channel) || continue
            for row in channel_spec(schema, channel).processes
                measured_row(row) || continue
                for stage in row_stages(template, channel)
                    push_measured_group!(
                        slots,
                        process_row_group(channel, row.process, stage),
                    )
                    attribution === :gross || continue
                    for part in (:positive, :negative), quantity in BUDGET_QUANTITIES
                        push!(
                            slots,
                            (gross_group(channel, row.process, stage, part), quantity),
                        )
                    end
                end
            end
        end
        for spec in schema.transfer_events, (reservoir, leg) in spec.modeled_legs
            channel = leg_channel(spec, reservoir, leg)
            for stage in row_stages(template, channel)
                push_measured_group!(
                    slots,
                    transfer_leg_group(spec.name, reservoir, leg, stage),
                )
            end
        end
        for ((label, reservoir), kind) in bracket_totals(schema)
            for stage in row_stages(template, evaluation_channel(kind))
                push_measured_group!(slots, bracket_group(label, reservoir, stage))
            end
        end
        for call in template.calls
            is_observation(call) || continue
            for quantity in BUDGET_QUANTITIES
                push!(slots, (observation_group(call), quantity))
            end
        end
    end
    return BudgetPacketLayout(slots)
end

"""
    build_parent_budget(mode, atmos, Y; ode_config, restart, constraint_cadence,
                        attribution = :net, tolerances = nothing,
                        checkpoint = nothing)
        -> Union{Nothing, ParentBudgetAdapter}

The adapter for a run, or `nothing` when `mode` is `off`.

Everything the ledger expects is fixed here, before the cache is built and
before the first step: the configuration is checked against the supported
scope, the schema is built from the coverage registry, every measured roster
row is checked to name the event that measures it, the hook template is built
from the tableau and the cadence, and the packet layout from all of them.

`attribution` is `:net` or `:gross`; `:gross` needs `AuditMode`, since the
process rows it splits are collected there only, and is refused otherwise.
`tolerances` overrides the committed κ calibration table, whose row for the
run's backend, float type and rank count is used otherwise; a run with
neither reports every numeric verdict as `blocked`.

A restarted run passes `restart = true` and the endpoints its checkpoint
carried as `checkpoint`, read by `read_checkpoint_endpoints`, or `nothing`
for a checkpoint written without a ledger. The first transaction then checks
the restored state against them exactly before it opens, see
`check_restart_transition`, and the record after the restart is a new segment.
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
    constraint_cadence::Symbol,
    attribution = :net,
    tolerances = nothing,
    checkpoint = nothing,
    calibration_rows = read_calibration_table(),
)
    attribution = parent_budget_attribution(attribution)
    attribution === :gross && !(mode isa AuditMode) &&
        error(
            "`parent_budget_attribution = \"gross\"` splits the process rows, " *
            "which only `parent_budget_mode = \"audit\"` collects.",
        )
    restart || isnothing(checkpoint) ||
        error(
            "Checkpoint endpoints were passed to a run that is not a restart.",
        )
    check_algorithm(ode_config)
    implicit_solve = !isnothing(ode_config.newtons_method)
    dss = do_dss(axes(Y.c))
    schema = budget_schema(atmos; dss, implicit_solve, restart, constraint_cadence)
    check_roster_events(schema)
    has_post_implicit =
        implicit_solve && atmos.numerics.energy_q_tot_upwinding != Val(:none)
    template = hook_template(
        ode_config.tableau,
        constraint_cadence,
        has_post_implicit,
        true,
        CTS.is_fsal(ode_config),
    )
    layout = adapter_packet_layout(schema, template, mode, attribution)
    scratch_tendency = mode isa AuditMode ? similar(Y) : nothing
    # A caller's tolerances first, then the committed calibration table's row
    # for this backend, float type and rank count, and otherwise none.
    context = budget_context(Y)
    tolerance_table, tolerance_source = if !isnothing(tolerances)
        parent_budget_tolerances(tolerances), :explicit
    else
        calibrated = calibrated_tolerances(
            context,
            Spaces.undertype(axes(Y.c));
            rows = calibration_rows,
        )
        calibrated, isnothing(calibrated) ? :none : :calibration_table
    end
    moist = owns_atmosphere_water(atmos.microphysics_model)
    slab = has_surface_reservoir(atmos.surface.temperature)
    snapshot = mode isa AuditMode ? snapshot_fields(Y, moist, slab) : nothing
    bracket_totals(schema)
    FT = BUDGET_ACCOUNTING_TYPE
    return ParentBudgetAdapter(
        mode,
        attribution,
        schema,
        atmos.surface.temperature,
        context,
        moist,
        BudgetLedger{FT}(schema),
        template,
        layout,
        BudgetPacket(layout),
        COLLECTED_CHANNELS,
        tolerance_table,
        tolerance_source,
        scratch_tendency,
        snapshot,
        slab,
        active_events(schema),
        restart,
        checkpoint,
        nothing,
        nothing,
        nothing,
        Dict{Symbol, Int}(hook => 0 for hook in METERED_HOOKS),
        (zero(FT), zero(FT), zero(FT)),
        Dict{Int, FT}(),
        Dict{Symbol, Measurement}(),
        Tuple{Symbol, Int, Measurement}[],
        Tuple{HookCall, NTuple{3, FT}}[],
        Tuple{Int, Measurement}[],
        Tuple{Int, Measurement}[],
        Tuple{Int, Measurement}[],
        Dict{Tuple{Symbol, Symbol, Int}, Measurement}(),
        Dict{Tuple{Symbol, Symbol, Int}, Measurement}(),
        Tuple{Symbol, Symbol, Int}[],
        Dict{Tuple{Symbol, Symbol, Symbol, Int}, LegMeasurement}(),
        :none,
        0,
        :none,
        Set{Symbol}(),
        nothing,
        0,
        0,
        nothing,
        BudgetLeg{FT}[],
        StageObservation{FT}[],
        GrossRecord{FT}[],
        TransferCheck{FT}[],
        BudgetCommit{FT}[],
    )
end

# The fields an event's applied update is differenced against: a copy of each
# parent tendency field, taken when the event opens. Reading the update
# pointwise, rather than as a difference of two integrals of the accumulated
# tendency, is what keeps its rounding error the size of the update itself.
snapshot_fields(Y, moist::Bool, slab::Bool) = (;
    ρ = similar(Y.c.ρ),
    ρq_tot = moist ? similar(Y.c.ρq_tot) : nothing,
    ρe_tot = similar(Y.c.ρe_tot),
    sfc_T = slab ? similar(Y.sfc.T) : nothing,
    sfc_water = slab && moist ? similar(Y.sfc.water) : nothing,
)

# Everything the meters recorded during a step, cleared once it is committed.
function clear_step_state!(adapter::ParentBudgetAdapter)
    for hook in METERED_HOOKS
        adapter.calls[hook] = 0
    end
    empty!(adapter.dtγ)
    empty!(adapter.final_changes)
    empty!(adapter.folded)
    empty!(adapter.observations)
    empty!(adapter.defects)
    empty!(adapter.slab_defects)
    empty!(adapter.corrections)
    empty!(adapter.parts)
    empty!(adapter.slab_parts)
    empty!(adapter.unmeasured)
    empty!(adapter.legs)
    adapter.evaluation = :none
    adapter.open_event = :none
    empty!(adapter.seen)
    return nothing
end

# ============================================================================
# The meters
# ============================================================================

# The local integrals of the three parent quantities in the atmosphere, in the
# accounting type, with no communication. Water is zero for a dry model and is
# never read there: the schema says the quantity is not applicable.
function parent_integrals(adapter::ParentBudgetAdapter, Y)
    water = adapter.moist ? local_atmosphere_water(Y) : zero(BUDGET_ACCOUNTING_TYPE)
    return (local_atmosphere_mass(Y), water, local_atmosphere_energy(Y))
end

# The local integrals of the absolute values of the three parent fields: the
# arithmetic magnitude of `parent_integrals` of the same array.
function parent_magnitudes(adapter::ParentBudgetAdapter, Y)
    FT = BUDGET_ACCOUNTING_TYPE
    integral(field) = local_volume_integral(Base.Broadcast.broadcasted(abs, field))
    water = adapter.moist ? integral(Y.c.ρq_tot) : zero(FT)
    return (integral(Y.c.ρ), water, integral(Y.c.ρe_tot))
end

# A before/after difference of two integrals, with the magnitude of both.
difference(before, after) = (after .- before, abs.(before) .+ abs.(after))

# The slab's three parent integrals of a state or tendency array, in the
# accounting type: its water twice, as the slab's water and its mass, and its
# energy through the areal heat capacity. Water is zero and never read in a
# dry model.
function slab_integrals(adapter::ParentBudgetAdapter, Y)
    FT = BUDGET_ACCOUNTING_TYPE
    capacity = to_accounting(slab_heat_capacity(adapter.surface_temperature))
    water = adapter.moist ? local_boundary_integral(Y.sfc.water) : zero(FT)
    return (water, water, local_boundary_integral(Y.sfc.T) * capacity)
end

function slab_magnitudes(adapter::ParentBudgetAdapter, Y)
    FT = BUDGET_ACCOUNTING_TYPE
    capacity = to_accounting(slab_heat_capacity(adapter.surface_temperature))
    integral(field) = local_boundary_integral(Base.Broadcast.broadcasted(abs, field))
    water = adapter.moist ? integral(Y.sfc.water) : zero(FT)
    return (water, water, integral(Y.sfc.T) * capacity)
end

# The template entry for the next firing of `hook`. One firing more than the
# template holds means the stepper ran a hook order the adapter was not written
# for, and every measurement's meaning would be wrong from here on.
function next_call!(adapter::ParentBudgetAdapter, hook::Symbol)
    count = adapter.calls[hook] += 1
    indices = adapter.template.per_hook[hook]
    count <= length(indices) || error(
        "The parent-budget adapter saw $hook fire $count times in one accepted " *
        "step, but the pinned ClimaTimeSteppers hook order has " *
        "$(length(indices)) firings. The stepper's stage construction is not " *
        "the one the adapter was written against.",
    )
    return adapter.template.calls[indices[count]]
end

# Whether this firing's change is measured. In summary mode only a measured
# final map is; in audit mode every state-writing firing is.
function measures(adapter::ParentBudgetAdapter, call::HookCall)
    call.hook in FINAL_MAP_HOOKS || return false
    is_audit(adapter) && return true
    return call.role === :final && hook_is_measured(adapter.schema, call.hook)
end

# Book a measured change where its role says it belongs. An observation keeps
# the change alone: it enters no identity and needs no magnitude.
function book_change!(adapter::ParentBudgetAdapter, call::HookCall, change::Measurement)
    if call.role === :final
        adapter.final_changes[call.hook] = change
    elseif call.role === :post_newton
        push!(adapter.folded, (call.hook, call.stage, change))
    else
        push!(adapter.observations, (call, change[1]))
    end
    return nothing
end

"""
    ExplicitMeter

The explicit tendency wrapped so the adapter knows which stage's tendency is
being evaluated and, in `AuditMode`, meters the applied-update events inside
it. The wrapped function receives exactly what the stepper passed; the meter
only reads.
"""
struct ExplicitMeter{F, A}
    f::F
    adapter::A
end

function (meter::ExplicitMeter)(Yₜ, Yₜ_lim, Y, p, t)
    adapter = meter.adapter
    call = next_call!(adapter, :T_exp_T_lim!)
    metering = is_audit(adapter)
    metering && begin_evaluation!(adapter, :explicit, call.stage)
    meter.f(Yₜ, Yₜ_lim, Y, p, t)
    metering && end_evaluation!(adapter)
    return nothing
end

"""
    HookMeter

A state-writing hook wrapped so the adapter can read the state before and after
it. The wrapped function receives exactly what the stepper passed; the meter
only reads.
"""
struct HookMeter{F, A}
    hook::Symbol
    f::F
    adapter::A
end

function (meter::HookMeter)(Y, p, t, args...)
    adapter = meter.adapter
    call = next_call!(adapter, meter.hook)
    measure = measures(adapter, call)
    measure && (adapter.before = parent_integrals(adapter, Y))
    meter.f(Y, p, t, args...)
    measure &&
        book_change!(
            adapter,
            call,
            difference(adapter.before, parent_integrals(adapter, Y)),
        )
    return nothing
end

"""
    InitializeMeter

The implicit-stage initialiser wrapped so the adapter learns the stage's `dtγ`,
which is what the solve defect and the folded hooks are weighted with.
"""
struct InitializeMeter{F, A}
    f::F
    adapter::A
end

function (meter::InitializeMeter)(Y, p, dtγ)
    adapter = meter.adapter
    call = next_call!(adapter, :initialize_imp!)
    adapter.dtγ[call.stage] = BUDGET_ACCOUNTING_TYPE(dtγ)
    meter.f(Y, p, dtγ)
    return nothing
end

"""
    PostImplicitMeter

The post-implicit correction wrapped so that, in `AuditMode`, the adapter can
measure the algebraic solve defect and the correction itself.

The correction is called with the Newton-solved stage `U*`, after the stepper
has refreshed the implicit cache for it, so this is the one point in a stage
where `U*` is visible with a cache that matches it. The defect is
`r = U₀ + dtγ · T_imp(U*) − U*`, with `U₀` the stage value the stepper stored
before the solve; its integrals need one extra implicit tendency evaluation,
which is why only `AuditMode` pays for it. The correction's integral is read
from the tendency the hook returns.

Neither measurement writes anything the stepper reads afterwards: the extra
evaluation writes the adapter's own scratch tendency and the cache's temporary
fields, which every consumer refills before use.
"""
struct PostImplicitMeter{F, T, A}
    f::F
    implicit_tendency::T
    adapter::A
end

function (meter::PostImplicitMeter)(Yₜ, U, p, t)
    adapter = meter.adapter
    call = next_call!(adapter, :T_post_imp!)
    if is_audit(adapter)
        dtγ = adapter.dtγ[call.stage]
        tendency = adapter.scratch_tendency
        # The one implicit tendency evaluation the adapter owns is also where
        # the implicit channel's process rows are measured.
        begin_evaluation!(adapter, :implicit, call.stage)
        meter.implicit_tendency(tendency, U, p, t)
        end_evaluation!(adapter)
        start = parent_integrals(adapter, adapter.stepper_cache.temp)
        applied = parent_integrals(adapter, tendency)
        solved = parent_integrals(adapter, U)
        residual = start .+ dtγ .* applied .- solved
        # Three integrals of a stage state cancel to a small residual, so its
        # magnitude is theirs.
        magnitude =
            abs.(start) .+ dtγ .* parent_magnitudes(adapter, tendency) .+ abs.(solved)
        push!(adapter.defects, (call.stage, (residual, magnitude)))
        if adapter.slab
            # The slab is solved in the same stage, with the precipitation it
            # receives implicitly, so it has a defect of its own.
            slab_start = slab_integrals(adapter, adapter.stepper_cache.temp)
            slab_applied = slab_integrals(adapter, tendency)
            slab_solved = slab_integrals(adapter, U)
            slab_residual = slab_start .+ dtγ .* slab_applied .- slab_solved
            slab_magnitude =
                abs.(slab_start) .+ dtγ .* slab_magnitudes(adapter, tendency) .+
                abs.(slab_solved)
            push!(adapter.slab_defects, (call.stage, (slab_residual, slab_magnitude)))
        end
    end
    meter.f(Yₜ, U, p, t)
    is_audit(adapter) && push!(
        adapter.corrections,
        (call.stage, (parent_integrals(adapter, Yₜ), parent_magnitudes(adapter, Yₜ))),
    )
    return nothing
end

"""
    meter_explicit(adapter, f)
    meter_hook(adapter, hook, f)
    meter_initialize(adapter, f)
    meter_post_implicit(adapter, f, implicit_tendency)

The hook `f` behind the adapter's meter, or `f` itself when there is no adapter,
so `args_integrator` wires the same names whether the ledger is on or off.
"""
meter_explicit(::Nothing, f) = f
meter_explicit(adapter::ParentBudgetAdapter, f) = ExplicitMeter(f, adapter)
meter_hook(::Nothing, ::Symbol, f) = f
meter_hook(adapter::ParentBudgetAdapter, hook::Symbol, f) = HookMeter(hook, f, adapter)
meter_initialize(::Nothing, f) = f
meter_initialize(adapter::ParentBudgetAdapter, f) = InitializeMeter(f, adapter)
meter_post_implicit(::Nothing, f, _) = f
meter_post_implicit(::ParentBudgetAdapter, ::Nothing, _) = nothing
meter_post_implicit(adapter::ParentBudgetAdapter, f, implicit_tendency) =
    PostImplicitMeter(f, implicit_tendency, adapter)

# ============================================================================
# The applied-update events
# ============================================================================

# The adapter meters an evaluation between these two calls: every event opened
# in it is integrated for the channel `kind` feeds, at `stage`.
function begin_evaluation!(adapter::ParentBudgetAdapter, kind::Symbol, stage::Int)
    adapter.evaluation = kind
    adapter.evaluation_stage = stage
    adapter.open_event = :none
    empty!(adapter.seen)
    return nothing
end

function end_evaluation!(adapter::ParentBudgetAdapter)
    adapter.open_event === :none || error(
        "The $(adapter.evaluation) tendency evaluation ended with the " *
        "applied-update event $(adapter.open_event) still open.",
    )
    adapter.evaluation = :none
    return nothing
end

"""
    open_ledger_event!(adapter, Yₜ, event)
    close_ledger_event!(adapter, Yₜ, Y, p, event)

The adapter's half of an applied-update event; see `open_applied_update!`.

Outside a metered evaluation both return at once, which covers every tendency
evaluation in `SummaryMode`, every Newton iteration and every Jacobian
evaluation. Inside one, the label is checked against the registry, against
nesting and against a second opening in the same evaluation, and if a roster
row or a transfer leg of this configuration is measured by it, the parent
tendency fields are copied when it opens and the parts of what it applied are
integrated when it closes. The transfer legs the event measures are then
read from their own flux fields in the cache, see `transfer_legs.jl`. Nothing
is written.
"""
function open_ledger_event!(adapter::ParentBudgetAdapter, Yₜ, event::Symbol)
    adapter.evaluation === :none && return nothing
    event in REGISTRY_EVENTS || error(
        "The applied-update event $event is not one the coverage registry " *
        "names. Add the process to the registry before bracketing it.",
    )
    adapter.open_event === :none || error(
        "The applied-update event $event was opened while " *
        "$(adapter.open_event) is open. Events do not nest: what a nested " *
        "bracket measured would be counted by both.",
    )
    event in adapter.seen && error(
        "The applied-update event $event was opened twice in one " *
        "$(adapter.evaluation) tendency evaluation. A process is bracketed " *
        "once per evaluation; a second bracket would book its update twice.",
    )
    adapter.open_event = event
    push!(adapter.seen, event)
    event in adapter.events || return nothing
    take_snapshot!(adapter, Yₜ)
    return nothing
end

function close_ledger_event!(adapter::ParentBudgetAdapter, Yₜ, Y, p, event::Symbol)
    adapter.evaluation === :none && return nothing
    adapter.open_event === event || error(
        "The applied-update event $event was closed while " *
        "$(adapter.open_event === :none ? "no event" : adapter.open_event) " *
        "is open.",
    )
    adapter.open_event = :none
    event in adapter.events || return nothing
    kind, stage = adapter.evaluation, adapter.evaluation_stage
    positive, negative = applied_parts(adapter, Yₜ)
    fault = adapter.fault
    faulted = !isnothing(fault) && fault[2] === event
    if faulted && fault[1] === :missing
        return nothing
    elseif faulted && fault[1] === :sign_reversed
        # The parts of the negated update are the negated parts, swapped.
        positive, negative = .-negative, .-positive
    end
    adapter.parts[(kind, event, stage)] = (positive, negative)
    bracket =
        Dict(ATMOSPHERE_ENDPOINT_GROUP => (positive .+ negative, positive .- negative))
    if adapter.slab
        slab_positive, slab_negative = slab_applied_parts(adapter, Yₜ)
        adapter.slab_parts[(kind, event, stage)] = (slab_positive, slab_negative)
        bracket[SLAB_SURFACE_ENDPOINT_GROUP] =
            (slab_positive .+ slab_negative, slab_positive .- slab_negative)
    end
    for leg in transfer_leg_measurements(
        adapter.schema,
        event,
        Yₜ,
        Y,
        p,
        adapter.surface_temperature,
        adapter.moist,
        bracket,
    )
        spec = transfer_event_spec(adapter.schema, leg.event)
        leg_evaluation(spec, leg.reservoir, leg.leg) === kind || error(
            "The applied-update event $event measured the $(leg.reservoir) " *
            "leg of $(leg.event) in the $kind evaluation, but the schema " *
            "applies that leg through channel " *
            "$(leg_channel(spec, leg.reservoir, leg.leg)). The registry and " *
            "the code disagree about where the leg is applied.",
        )
        if faulted && fault[1] === :leg_missing
            continue
        elseif faulted && fault[1] === :leg_sign_reversed
            leg = LegMeasurement(
                leg.event,
                leg.reservoir,
                leg.leg,
                .-leg.amounts,
                leg.magnitudes,
                leg.known,
                leg.reason,
            )
        end
        adapter.legs[(leg.event, leg.reservoir, leg.leg, stage)] = leg
    end
    return nothing
end

function take_snapshot!(adapter::ParentBudgetAdapter, Yₜ)
    snapshot = adapter.snapshot
    snapshot.ρ .= Yₜ.c.ρ
    adapter.moist && (snapshot.ρq_tot .= Yₜ.c.ρq_tot)
    snapshot.ρe_tot .= Yₜ.c.ρe_tot
    if adapter.slab
        snapshot.sfc_T .= Yₜ.sfc.T
        adapter.moist && (snapshot.sfc_water .= Yₜ.sfc.water)
    end
    return nothing
end

# The slab's parts of what an event applied: the temperature tendency times
# the areal heat capacity for energy, the water tendency for water and again
# for the mass it carries.
function slab_applied_parts(adapter::ParentBudgetAdapter, Yₜ)
    FT = BUDGET_ACCOUNTING_TYPE
    snapshot = adapter.snapshot
    capacity = to_accounting(slab_heat_capacity(adapter.surface_temperature))
    part(f, after, before) =
        local_boundary_integral(Base.Broadcast.broadcasted(f, after, before))
    water(f) = adapter.moist ? part(f, Yₜ.sfc.water, snapshot.sfc_water) : zero(FT)
    positive_water, negative_water = water(positive_part), water(negative_part)
    positive = (
        positive_water,
        positive_water,
        part(positive_part, Yₜ.sfc.T, snapshot.sfc_T) * capacity,
    )
    negative = (
        negative_water,
        negative_water,
        part(negative_part, Yₜ.sfc.T, snapshot.sfc_T) * capacity,
    )
    return (positive, negative)
end

# The pointwise parts of an applied update, widened before the difference.
positive_part(after, before) =
    max(to_accounting(after) - to_accounting(before), zero(BUDGET_ACCOUNTING_TYPE))
negative_part(after, before) =
    min(to_accounting(after) - to_accounting(before), zero(BUDGET_ACCOUNTING_TYPE))

# The local integrals of the positive and negative parts of what an event
# applied to each parent field, against the copies taken when it opened. The
# amount is their sum and the arithmetic magnitude their difference.
function applied_parts(adapter::ParentBudgetAdapter, Yₜ)
    FT = BUDGET_ACCOUNTING_TYPE
    snapshot = adapter.snapshot
    part(f, after, before) =
        local_volume_integral(Base.Broadcast.broadcasted(f, after, before))
    water(f) = adapter.moist ? part(f, Yₜ.c.ρq_tot, snapshot.ρq_tot) : zero(FT)
    positive = (
        part(positive_part, Yₜ.c.ρ, snapshot.ρ),
        water(positive_part),
        part(positive_part, Yₜ.c.ρe_tot, snapshot.ρe_tot),
    )
    negative = (
        part(negative_part, Yₜ.c.ρ, snapshot.ρ),
        water(negative_part),
        part(negative_part, Yₜ.c.ρe_tot, snapshot.ρe_tot),
    )
    return (positive, negative)
end

"""
    inject_fault!(adapter, kind, event)
    clear_fault!(adapter)

Test instrumentation: make the adapter's half of the applied-update `event`
misbehave in a named way, so a test can show what the ledger does with a
measurement that is missing or has the wrong sign. `kind` is `:missing`, which
drops the event's increment, `:sign_reversed`, which negates it,
`:leg_missing`, which drops the transfer legs the event measures, or
`:leg_sign_reversed`, which negates them. Nothing at runtime sets a fault.
"""
function inject_fault!(adapter::ParentBudgetAdapter, kind::Symbol, event::Symbol)
    kind in (:missing, :sign_reversed, :leg_missing, :leg_sign_reversed) || error(
        "Unknown fault $kind; expected :missing, :sign_reversed, :leg_missing " *
        "or :leg_sign_reversed.",
    )
    adapter.fault = (kind, event)
    return nothing
end

function clear_fault!(adapter::ParentBudgetAdapter)
    adapter.fault = nothing
    return nothing
end

# Whether the post-implicit correction hook is wired, which is the one point
# where the adapter can evaluate the implicit tendency at the solved stage.
has_post_implicit_evaluation(adapter::ParentBudgetAdapter) =
    !isempty(adapter.template.per_hook[:T_post_imp!])

# ============================================================================
# The callback
# ============================================================================

"""
    parent_budget_callbacks(adapter) -> Tuple

The discrete callback that drives the ledger, as a one-element tuple to splice
in front of every other callback, or an empty tuple for `nothing`.

The callback's `initialize` reads the opening endpoint after the integrator has
initialised its cache and before any other callback has run, which is where
`B⁰` is defined. Its `affect!` commits every accepted step. Its condition is
always true: the ledger has no cadence of its own, because a step it skipped
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
# closing endpoint to reuse. This is one collective, paid once per run. The
# cache the integrator built is checked against the template built earlier,
# and a restored state against the endpoints its checkpoint carried.
function initialize_ledger!(adapter::ParentBudgetAdapter, integrator)
    adapter.timestepper = timestepper_record(integrator)
    adapter.stepper_cache = integrator.cache
    stages = length(integrator.cache.tableau.b_imp.coeffs)
    expected = length(adapter.template.implicit_stages)
    found = count(i -> !iszero(integrator.cache.tableau.a_imp.coeffs[i, i]), 1:stages)
    found == expected || error(
        "The integrator's tableau has $found implicit stages, the adapter's " *
        "template $expected. The template was built from the algorithm passed " *
        "at setup, which is not the one the integrator runs.",
    )
    b_exp = integrator.cache.tableau.b_exp.coeffs
    findall(!iszero, b_exp) == adapter.template.explicit_stages || error(
        "The integrator's tableau weights the explicit stages " *
        "$(findall(!iszero, b_exp)), the adapter's template " *
        "$(adapter.template.explicit_stages).",
    )
    for i in findall(!iszero, integrator.cache.tableau.b_imp.coeffs)
        i in adapter.template.implicit_stages || error(
            "The tableau gives the implicit tendency of stage $i a nonzero " *
            "weight, but that stage has no implicit solve, so the stepper " *
            "evaluates the implicit tendency there explicitly. The adapter " *
            "attributes the implicit channel at solved stages only.",
        )
    end
    clear_step_state!(adapter)
    endpoints = budget_endpoints(
        integrator.u,
        adapter.schema,
        adapter.surface_temperature,
        0,
    )
    adapter.reductions += 1
    adapter.restart && (
        adapter.transition =
            check_restart_transition(adapter.schema, endpoints, adapter.checkpoint)
    )
    open_transaction!(adapter.ledger, endpoints)
    return nothing
end

"""
    restart_transition(adapter) -> Union{Nothing, RestartTransition}

What the ledger found when it opened on a restored state, or `nothing` for a
run that did not restart.
"""
restart_transition(adapter::ParentBudgetAdapter) = adapter.transition

"""
    declared_callbacks(adapter, callbacks) -> Tuple

The user callbacks a run may install beside the ledger. Without a ledger they
pass through. With one, each must be a `ReadOnlyCallback`; the declaration is
unwrapped, and in `AuditMode` every firing is checked against it by reading
the parent integrals of the state around the call, locally, with no collective.
"""
declared_callbacks(::Nothing, callbacks) = callbacks
function declared_callbacks(adapter::ParentBudgetAdapter, callbacks)
    return Tuple(declared_callback(adapter, callback) for callback in callbacks)
end

declared_callback(::ParentBudgetAdapter, callback) = error(
    "The parent-budget ledger accepts a custom callback only inside a " *
    "ReadOnlyCallback declaration, got $(typeof(callback)). A callback that " *
    "writes the state between two transactions is a change nothing accounts " *
    "for, and a callback that supplies its own accounting is not supported yet.",
)
function declared_callback(adapter::ParentBudgetAdapter, declared::ReadOnlyCallback)
    inner = declared.callback
    is_audit(adapter) || return inner
    affect! =
        integrator -> begin
            before = parent_integrals(adapter, integrator.u)
            inner.affect!(integrator)
            after = parent_integrals(adapter, integrator.u)
            before == after || error(
                "A callback declared read-only changed the state: the parent " *
                "integrals moved by $(after .- before) across its firing.",
            )
            return nothing
        end
    return CTS.DiscreteCallback(
        inner.condition,
        affect!;
        initialize = inner.initialize,
        finalize = inner.finalize,
    )
end

"""
    commit_step!(adapter, integrator)

Account for the accepted step the integrator has just finished.

Runs before every other callback, so the state it reads is the finalized
accepted state and the stage tendencies in the stepper cache are this step's.
One packet, one collective, then the legs are recorded, envelopes, final maps,
the audit rows and the process rows, the transaction is committed, the hook
counts are checked against the template, and the next transaction opens on
the closing endpoint without measuring it again.
"""
function commit_step!(adapter::ParentBudgetAdapter, integrator)
    (; schema, ledger, packet, surface_temperature) = adapter
    step = ledger.step
    Y = integrator.u

    check_hook_counts(adapter)

    reset_packet!(packet)
    for spec in schema.reservoirs
        fill_endpoint_slots!(packet, Y, schema, spec, surface_temperature)
    end
    fill_envelope_slots!(packet, adapter, integrator)
    fill_final_map_slots!(packet, adapter)
    if is_audit(adapter)
        fill_audit_slots!(packet, adapter, integrator)
        fill_process_slots!(packet, adapter, integrator)
        fill_transfer_slots!(packet, adapter, integrator)
    end
    reduce_packet!(adapter.context, packet)
    adapter.reductions += 1

    closing = budget_endpoints(packet, schema, step)
    record_envelopes!(adapter, packet, step)
    record_final_maps!(adapter, packet, step)
    is_audit(adapter) && record_audit_legs!(adapter, packet, integrator, step)
    record_process_legs!(adapter, packet, integrator, step)
    is_audit(adapter) && record_transfer_legs!(adapter, packet, integrator, step)
    # The commit clears the transaction, so the step's records are kept here
    # for the report and the tests. Bounded by the template, not the run.
    copy!(adapter.last_legs, ledger.legs)
    copy!(adapter.last_observations, ledger.observations)
    commit = commit_transaction!(ledger, closing; tolerances = adapter.tolerances)

    adapter.last_commit = commit
    is_audit(adapter) && push!(adapter.commits, commit)
    adapter.steps_committed += 1
    clear_step_state!(adapter)
    open_transaction!(ledger)
    return nothing
end

# Every metered hook fired exactly as often as the template says. Fewer firings
# mean the stepper skipped a hook the adapter counts on, such as a final map.
function check_hook_counts(adapter::ParentBudgetAdapter)
    for hook in METERED_HOOKS
        expected = length(adapter.template.per_hook[hook])
        adapter.calls[hook] == expected || error(
            "The parent-budget adapter saw $hook fire $(adapter.calls[hook]) " *
            "times in an accepted step, but the pinned ClimaTimeSteppers hook " *
            "order has $expected firings.",
        )
    end
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

# The arithmetic magnitude of the same increment: every term of the weighted
# sum taken in absolute value.
@inline function weighted_stage_magnitude(
    weights::NTuple{N, BUDGET_ACCOUNTING_TYPE},
    values::Vararg{Any, N},
) where {N}
    total = zero(BUDGET_ACCOUNTING_TYPE)
    for k in 1:N
        total += abs(weights[k]) * abs(BUDGET_ACCOUNTING_TYPE(values[k]))
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

function weighted_stage_magnitudes(weights, fields)
    return Base.Broadcast.broadcasted(
        (values...) -> weighted_stage_magnitude(weights, values...),
        fields...,
    )
end

# The prognostic field one parent quantity is integrated from.
atmosphere_field_name(quantity::Symbol) =
    quantity === :mass ? :ρ : quantity === :water ? :ρq_tot : :ρe_tot

# The local, accounting-precision integral of a channel's accepted increment in
# one reservoir for one quantity, and its arithmetic magnitude. `tendencies` is
# the cache's container of stage tendencies for the channel, indexed by stage.
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
        return (
            local_volume_integral(weighted_stage_sum(weights, fields)),
            local_volume_integral(weighted_stage_magnitudes(weights, fields)),
        )
    end
    if quantity === :energy
        fields = map(i -> tendencies[i].sfc.T, indices)
        capacity = to_accounting(slab_heat_capacity(surface_temperature))
        return (
            local_boundary_integral(weighted_stage_sum(weights, fields)) * capacity,
            local_boundary_integral(weighted_stage_magnitudes(weights, fields)) * capacity,
        )
    end
    # The slab's water and its mass are one field seen twice.
    fields = map(i -> tendencies[i].sfc.water, indices)
    return (
        local_boundary_integral(weighted_stage_sum(weights, fields)),
        local_boundary_integral(weighted_stage_magnitudes(weights, fields)),
    )
end

# The stepper cache's container of stage tendencies and the weights for a
# collected channel. The implicit tendencies are the effective ones the stepper
# stored, so the implicit envelope is the whole of what the implicit stages
# applied, hooks and defect included.
function channel_tendencies(cache, channel::Symbol)
    channel === :explicit_main && return cache.T_exp, cache.tableau.b_exp.coeffs
    channel === :explicit_limited && return cache.T_lim, cache.tableau.b_exp.coeffs
    channel === :implicit && return cache.T_imp, cache.tableau.b_imp.coeffs
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
    for channel in adapter.channels
        tendencies, coefficients = channel_tendencies(cache, channel)
        indices, weights = stage_weights(coefficients, dt)
        for reservoir in channel_spec(schema, channel).reservoirs
            group = envelope_group(channel, reservoir)
            for quantity in BUDGET_QUANTITIES
                if quantity_applicable(schema, reservoir, quantity)
                    value, magnitude = local_envelope(
                        tendencies,
                        indices,
                        weights,
                        reservoir,
                        quantity,
                        surface_temperature,
                    )
                    set_local!(packet, group, quantity, value)
                    set_local!(packet, magnitude_group(group), quantity, magnitude)
                else
                    set_inapplicable!(packet, group, quantity)
                    set_inapplicable!(packet, magnitude_group(group), quantity)
                end
            end
        end
    end
    return nothing
end

# A slot per quantity from a measured triple, honouring the reservoir's
# applicability.
function set_triple!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    group::Symbol,
    values;
    reservoir::Symbol = ATMOSPHERE_ENDPOINT_GROUP,
)
    for (k, quantity) in enumerate(BUDGET_QUANTITIES)
        if quantity_applicable(adapter.schema, reservoir, quantity)
            set_local!(packet, group, quantity, values[k])
        else
            set_inapplicable!(packet, group, quantity)
        end
    end
    return nothing
end

# A measurement's amounts into its group and its magnitudes beside them.
function set_measurement!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    group::Symbol,
    measurement::Measurement;
    reservoir::Symbol = ATMOSPHERE_ENDPOINT_GROUP,
)
    set_triple!(packet, adapter, group, measurement[1]; reservoir)
    set_triple!(packet, adapter, magnitude_group(group), measurement[2]; reservoir)
    return nothing
end

# A measurement scaled by an accepted weight: the amounts signed, the
# magnitudes absolute.
scale(weight, measurement::Measurement) =
    (weight .* measurement[1], abs(weight) .* measurement[2])

# The measured final maps. A hook the schema declares measured must have been
# measured on its final call; one declared zero has no slot.
function fill_final_map_slots!(packet::BudgetPacket, adapter::ParentBudgetAdapter)
    for hook in FINAL_MAP_HOOKS
        hook_is_measured(adapter.schema, hook) || continue
        haskey(adapter.final_changes, hook) || error(
            "The final $hook of the step was not measured. The template names " *
            "its position, so the stepper did not fire it where the adapter " *
            "expected.",
        )
        set_measurement!(
            packet,
            adapter,
            final_map_group(hook),
            adapter.final_changes[hook],
        )
    end
    return nothing
end

# The per-stage implicit rows and the stage observations, weighted as they
# enter the accepted update where they do, and raw where they do not.
function fill_audit_slots!(packet::BudgetPacket, adapter::ParentBudgetAdapter, integrator)
    tableau = integrator.cache.tableau
    dt = BUDGET_ACCOUNTING_TYPE(float(integrator.dt))
    rows = stage_rows(adapter.schema)
    zeros = (zero(dt), zero(dt), zero(dt))
    nothing_applied = (zeros, zeros)
    for stage in adapter.template.implicit_stages
        b = BUDGET_ACCOUNTING_TYPE(tableau.b_imp.coeffs[stage])
        γ = BUDGET_ACCOUNTING_TYPE(tableau.a_imp.coeffs[stage, stage])
        folded_weight = b / γ
        if :solve_defect in rows
            # The stored tendency is `dtγ T(U*) − r` plus the hooks, so the
            # defect enters the accepted update with weight `−b/γ`. Without
            # the correction hook the solved stage is never visible with a
            # matching cache, so the defect is not measured, its slot stays
            # zero and its leg is recorded as unknown.
            measurement = if has_post_implicit_evaluation(adapter)
                scale(-folded_weight, stage_value(adapter.defects, stage, "solve defect"))
            else
                nothing_applied
            end
            set_measurement!(
                packet,
                adapter,
                stage_row_group(:solve_defect, stage),
                measurement,
            )
        end
        if :solve_defect in stage_rows(adapter.schema, SLAB_SURFACE_ENDPOINT_GROUP)
            measurement = if has_post_implicit_evaluation(adapter)
                scale(
                    -folded_weight,
                    stage_value(adapter.slab_defects, stage, "slab solve defect"),
                )
            else
                nothing_applied
            end
            set_measurement!(
                packet,
                adapter,
                stage_row_group(:solve_defect, stage, SLAB_SURFACE_ENDPOINT_GROUP),
                measurement;
                reservoir = SLAB_SURFACE_ENDPOINT_GROUP,
            )
        end
        if :post_implicit_correction in rows
            correction = stage_value(adapter.corrections, stage, "post-implicit correction")
            set_measurement!(
                packet,
                adapter,
                stage_row_group(:post_implicit_correction, stage),
                scale(dt * b, correction),
            )
        end
        for (process, hook) in
            ((:folded_dss, :dss!), (:folded_constraint, :constrain_state!))
            process in rows || continue
            group = stage_row_group(process, stage)
            change = folded_change(adapter, hook, stage)
            # A hook the template skips at this stage, such as the constraint at
            # the last stage of a first-same-as-last tableau, contributes zero.
            measurement = isnothing(change) ? nothing_applied : scale(folded_weight, change)
            set_measurement!(packet, adapter, group, measurement)
        end
    end
    for (call, change) in adapter.observations
        set_triple!(packet, adapter, observation_group(call), change)
    end
    return nothing
end

function stage_value(records, stage::Int, what::AbstractString)
    for (recorded_stage, values) in records
        recorded_stage == stage && return values
    end
    return error("The $what of stage $stage was not measured.")
end

function folded_change(adapter::ParentBudgetAdapter, hook::Symbol, stage::Int)
    for (recorded_hook, recorded_stage, change) in adapter.folded
        recorded_hook === hook && recorded_stage == stage && return change
    end
    return nothing
end

# ============================================================================
# Legs from the reduced packet
# ============================================================================

# The three components of one atmosphere slot group, measured where the
# schema says the atmosphere owns the quantity and not applicable elsewhere.
# A group with magnitudes beside it, which is every group that enters an
# identity, reads them; an observation has none.
function atmosphere_components(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    group::Symbol;
    method::Symbol,
    source::Symbol,
    magnitudes::Bool = true,
    reservoir::Symbol = ATMOSPHERE_ENDPOINT_GROUP,
)
    FT = BUDGET_ACCOUNTING_TYPE
    function component(quantity)
        quantity_applicable(adapter.schema, reservoir, quantity) ||
            return not_applicable(FT; source = :schema)
        amount = packet_value(packet, group, quantity)
        magnitude =
            magnitudes ? packet_value(packet, magnitude_group(group), quantity) :
            abs(amount)
        return measured(
            amount;
            method,
            source,
            route = :packed_global_reduction,
            magnitude,
        )
    end
    return component(:mass), component(:water), component(:energy)
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
                    magnitude = packet_value(packet, magnitude_group(group), quantity),
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

# One final-map leg per state-writing hook, on the accepted state, with each
# quantity as the schema declares it for this configuration: measured where a
# configured path writes it, the invariant zero its rows prove where none does,
# and not applicable where the atmosphere does not own it. Wherever the hook was
# measured, a quantity declared zero is required to have moved by exactly zero,
# so a registry that has fallen behind the code is caught here.
function record_final_maps!(adapter::ParentBudgetAdapter, packet::BudgetPacket, step::Int)
    (; schema, ledger) = adapter
    FT = BUDGET_ACCOUNTING_TYPE
    for hook in FINAL_MAP_HOOKS
        spec = final_map_spec(schema, hook)
        measured_change = get(adapter.final_changes, hook, nothing)
        components = map(enumerate(BUDGET_QUANTITIES)) do (k, quantity)
            quantity_applicable(schema, ATMOSPHERE_ENDPOINT_GROUP, quantity) ||
                return not_applicable(FT; source = :schema)
            expected = expected_disposition(spec, quantity)
            if expected === :measured
                group = final_map_group(hook)
                return measured(
                    packet_value(packet, group, quantity);
                    method = :accepted_state_difference,
                    source = Symbol("adapter.", hook),
                    route = :packed_global_reduction,
                    magnitude = packet_value(packet, magnitude_group(group), quantity),
                )
            elseif expected === :invariant_zero
                if !isnothing(measured_change) && !iszero(measured_change[1][k])
                    error(
                        "The registry declares the final $hook provably zero for " *
                        "$quantity in this configuration, but it changed the " *
                        "quantity by $(measured_change[1][k]). The registry and " *
                        "the code disagree.",
                    )
                end
                return invariant_zero(
                    FT;
                    proof = :no_configured_path_writes_this_field,
                    source = :coverage_registry,
                )
            end
            # An open disposition is not established, so the component stays
            # unknown and blocks, whatever was measured.
            return unknown_component(
                FT;
                reason = :disposition_open,
                source = :coverage_registry,
            )
        end
        leg = BudgetLeg{FT}(;
            event = Symbol("map.", hook),
            leg = :final,
            reservoir = AtmosphereReservoir(),
            channel = hook,
            level = FinalMap(),
            mass = components[1],
            water = components[2],
            energy = components[3],
            path = hook === :dss! ? DiscreteMap() : NumericalCorrection(),
            process = hook,
            phase = :final,
            step,
            measured_at = :accepted_state,
        )
        record_leg!(ledger, leg)
    end
    return nothing
end

# The per-stage rows of the implicit channel and the stage observations.
function record_audit_legs!(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    integrator,
    step::Int,
)
    (; schema, ledger) = adapter
    FT = BUDGET_ACCOUNTING_TYPE
    tableau = integrator.cache.tableau
    dt = FT(float(integrator.dt))
    rows = stage_rows(schema)
    for stage in adapter.template.implicit_stages
        b = FT(tableau.b_imp.coeffs[stage])
        γ = FT(tableau.a_imp.coeffs[stage, stage])
        for process in rows
            group = stage_row_group(process, stage)
            mass, water, energy = atmosphere_components(
                adapter, packet, group;
                method = process === :solve_defect ? :algebraic_residual_integral :
                         process === :post_implicit_correction ?
                         :correction_tendency_integral :
                         :solved_stage_difference,
                source = Symbol("adapter.", process),
            )
            if process === :post_implicit_correction
                # The correction writes no density term.
                mass =
                    quantity_applicable(schema, ATMOSPHERE_ENDPOINT_GROUP, :mass) ?
                    invariant_zero(
                        FT;
                        proof = :writes_no_density_term,
                        source = :coverage_registry,
                    ) : mass
            elseif process === :solve_defect && !has_post_implicit_evaluation(adapter)
                mass, water, energy = map(BUDGET_QUANTITIES) do quantity
                    quantity_applicable(schema, ATMOSPHERE_ENDPOINT_GROUP, quantity) ?
                    unknown_component(
                        FT;
                        reason = :no_post_implicit_evaluation,
                        source = :adapter,
                    ) : not_applicable(FT; source = :schema)
                end
            end
            leg = BudgetLeg{FT}(;
                event = Symbol("impl.", process),
                leg = :atmosphere,
                reservoir = AtmosphereReservoir(),
                channel = :implicit,
                level = ProcessDecomposition(),
                mass,
                water,
                energy,
                path = process === :solve_defect ? AlgebraicSolveDefect() :
                       process === :post_implicit_correction ? EquationTerm() :
                       process === :folded_dss ? DiscreteMap() : NumericalCorrection(),
                process,
                phase = :implicit,
                step,
                stage,
                weight = process === :post_implicit_correction ? dt * b : b / γ,
                measured_at = :solved_stage,
            )
            record_leg!(ledger, leg)
        end
        for process in stage_rows(schema, SLAB_SURFACE_ENDPOINT_GROUP)
            group = stage_row_group(process, stage, SLAB_SURFACE_ENDPOINT_GROUP)
            mass, water, energy = atmosphere_components(
                adapter, packet, group;
                method = :algebraic_residual_integral,
                source = Symbol("adapter.", process),
                reservoir = SLAB_SURFACE_ENDPOINT_GROUP,
            )
            if !has_post_implicit_evaluation(adapter)
                mass, water, energy = map(BUDGET_QUANTITIES) do quantity
                    quantity_applicable(schema, SLAB_SURFACE_ENDPOINT_GROUP, quantity) ?
                    unknown_component(
                        FT;
                        reason = :no_post_implicit_evaluation,
                        source = :adapter,
                    ) : not_applicable(FT; source = :schema)
                end
            end
            record_leg!(
                ledger,
                BudgetLeg{FT}(;
                    event = Symbol("impl.", process),
                    leg = :slab_surface,
                    reservoir = SlabSurfaceReservoir(),
                    channel = :implicit,
                    level = ProcessDecomposition(),
                    mass,
                    water,
                    energy,
                    path = AlgebraicSolveDefect(),
                    process,
                    phase = :implicit,
                    step,
                    stage,
                    weight = b / γ,
                    measured_at = :solved_stage,
                ),
            )
        end
    end
    for (call, _) in adapter.observations
        mass, water, energy = atmosphere_components(
            adapter, packet, observation_group(call);
            method = :stage_difference, source = Symbol("adapter.", call.hook),
            magnitudes = false,
        )
        observation = StageObservation{FT}(;
            event = Symbol("obs.", call.hook),
            observation = call.role,
            reservoir = AtmosphereReservoir(),
            mass,
            water,
            energy,
            process = call.hook,
            step,
            stage = call.stage,
            occurrence = call.occurrence,
        )
        record_observation!(ledger, observation)
    end
    return nothing
end

# ============================================================================
# Process rows from the applied-update events
# ============================================================================

# The measured process rows, each stage's applied update weighted as it enters
# the accepted step, and the gross parts beside them. A row whose event did
# not fire at a weighted stage gets a zero slot and is remembered as
# unmeasured, so that its leg is recorded as unknown rather than as a zero.
function fill_process_slots!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    integrator,
)
    (; schema, template) = adapter
    tableau = integrator.cache.tableau
    dt = BUDGET_ACCOUNTING_TYPE(float(integrator.dt))
    zeros = (zero(dt), zero(dt), zero(dt))
    empty!(adapter.unmeasured)
    for channel in adapter.channels
        kind = evaluation_kind(channel)
        for row in channel_spec(schema, channel).processes
            measured_row(row) || continue
            for stage in row_stages(template, channel)
                weight = row_weight(tableau, channel, stage, dt)
                parts = get(adapter.parts, (kind, row.event, stage), nothing)
                isnothing(parts) && push!(adapter.unmeasured, (channel, row.process, stage))
                positive, negative = isnothing(parts) ? (zeros, zeros) : parts
                # The amount is the sum of the parts and the magnitude their
                # difference, each weighted as the row enters the step.
                measurement = scale(weight, (positive .+ negative, positive .- negative))
                set_measurement!(
                    packet,
                    adapter,
                    process_row_group(channel, row.process, stage),
                    measurement,
                )
                adapter.attribution === :gross || continue
                # The parts of the weighted contribution: a negative stage
                # weight swaps which part is which.
                weighted_positive, weighted_negative =
                    weight >= 0 ? (weight .* positive, weight .* negative) :
                    (weight .* negative, weight .* positive)
                set_triple!(
                    packet,
                    adapter,
                    gross_group(channel, row.process, stage, :positive),
                    weighted_positive,
                )
                set_triple!(
                    packet,
                    adapter,
                    gross_group(channel, row.process, stage, :negative),
                    weighted_negative,
                )
            end
        end
    end
    return nothing
end

# One leg per declared row of every collected channel: from the registry alone
# for a row nothing measures, and in audit mode one per weighted stage from the
# packet for a row an event measures. The hook-metered rows of the implicit
# channel are recorded by `record_audit_legs!`. In summary mode a measured row
# records nothing, and the attribution is blocked naming it.
function record_process_legs!(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    integrator,
    step::Int,
)
    (; schema, ledger, template) = adapter
    FT = BUDGET_ACCOUNTING_TYPE
    tableau = integrator.cache.tableau
    dt = FT(float(integrator.dt))
    empty!(adapter.last_gross)
    for channel in adapter.channels
        for row in channel_spec(schema, channel).processes
            is_stage_row(row) && continue
            event = Symbol(EVENT_PREFIXES[channel], row.process)
            if !measured_row(row)
                record_declared_row!(adapter, row, channel, event, step)
                continue
            end
            is_audit(adapter) || continue
            for stage in row_stages(template, channel)
                weight = row_weight(tableau, channel, stage, dt)
                group = process_row_group(channel, row.process, stage)
                unmeasured = (channel, row.process, stage) in adapter.unmeasured
                mass, water, energy = map(BUDGET_QUANTITIES) do quantity
                    process_component(
                        adapter,
                        row,
                        channel,
                        packet,
                        group,
                        quantity,
                        unmeasured,
                    )
                end
                leg = BudgetLeg{FT}(;
                    event,
                    leg = :atmosphere,
                    reservoir = AtmosphereReservoir(),
                    channel,
                    level = ProcessDecomposition(),
                    mass,
                    water,
                    energy,
                    path = EquationTerm(),
                    process = row.process,
                    phase = channel,
                    step,
                    stage,
                    weight,
                    measured_at = channel === :implicit ? :solved_stage : :stage_evaluation,
                )
                record_leg!(ledger, leg)
                adapter.attribution === :gross && !unmeasured &&
                    push!(
                        adapter.last_gross,
                        gross_record(adapter, packet, row, channel, stage, weight),
                    )
            end
        end
    end
    return nothing
end

# One quantity of a measured row's leg at one stage. The registry's
# disposition says what the bracket must have found: a measured quantity takes
# the reduced amount, a quantity declared provably zero is required to have
# moved by exactly zero, and one the atmosphere does not own is not applicable.
# An unmeasured row is unknown in every owned quantity, with the reason, and
# blocks.
function process_component(
    adapter::ParentBudgetAdapter,
    row::ProcessRowSpec,
    channel::Symbol,
    packet::BudgetPacket,
    group::Symbol,
    quantity::Symbol,
    unmeasured::Bool,
)
    FT = BUDGET_ACCOUNTING_TYPE
    quantity_applicable(adapter.schema, ATMOSPHERE_ENDPOINT_GROUP, quantity) ||
        return not_applicable(FT; source = :schema)
    expected = expected_disposition(row, quantity)
    expected === :not_applicable && return not_applicable(FT; source = :coverage_registry)
    source = Symbol("event.", row.event)
    if unmeasured
        reason =
            channel === :implicit && !has_post_implicit_evaluation(adapter) ?
            :no_post_implicit_evaluation : :event_not_recorded
        return unknown_component(FT; reason, source)
    end
    value = packet_value(packet, group, quantity)
    if expected === :invariant_zero
        iszero(value) || error(
            "The registry declares process $(row.process) of channel $channel " *
            "provably zero for $quantity, but its applied-update event " *
            "$(row.event) moved the quantity by $value. The registry and the " *
            "code disagree.",
        )
        return invariant_zero(
            FT;
            proof = :registry_proof_checked_at_event,
            source = :coverage_registry,
        )
    end
    expected === :measured && return measured(
        value;
        method = :applied_update_integral,
        source,
        route = :packed_global_reduction,
        magnitude = packet_value(packet, magnitude_group(group), quantity),
    )
    return unknown_component(FT; reason = :disposition_open, source = :coverage_registry)
end

# A row nothing measures, booked once per step from what the registry
# declares: an invariant zero with its proof, not applicable, or unknown for a
# disposition still open. It carries no measurement and takes no stage.
function record_declared_row!(
    adapter::ParentBudgetAdapter,
    row::ProcessRowSpec,
    channel::Symbol,
    event::Symbol,
    step::Int,
)
    FT = BUDGET_ACCOUNTING_TYPE
    mass, water, energy = map(BUDGET_QUANTITIES) do quantity
        quantity_applicable(adapter.schema, row.reservoir, quantity) ||
            return not_applicable(FT; source = :schema)
        expected = expected_disposition(row, quantity)
        expected === :invariant_zero &&
            return invariant_zero(FT; proof = :registry_proof, source = :coverage_registry)
        expected === :not_applicable &&
            return not_applicable(FT; source = :coverage_registry)
        expected === :measured &&
            return unknown_component(FT; reason = :no_event, source = :coverage_registry)
        return unknown_component(
            FT;
            reason = :disposition_open,
            source = :coverage_registry,
        )
    end
    leg = BudgetLeg{FT}(;
        event,
        leg = :atmosphere,
        reservoir = endpoint_reservoir(row.reservoir),
        channel,
        level = ProcessDecomposition(),
        mass,
        water,
        energy,
        path = EquationTerm(),
        process = row.process,
        phase = channel,
        step,
        measured_at = :coverage_registry,
    )
    record_leg!(adapter.ledger, leg)
    return nothing
end

function gross_record(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    row::ProcessRowSpec,
    channel::Symbol,
    stage::Int,
    weight,
)
    FT = BUDGET_ACCOUNTING_TYPE
    value(part, quantity) =
        quantity_applicable(adapter.schema, ATMOSPHERE_ENDPOINT_GROUP, quantity) ?
        packet_value(packet, gross_group(channel, row.process, stage, part), quantity) :
        zero(FT)
    parts(part) = map(quantity -> value(part, quantity), BUDGET_QUANTITIES)
    return GrossRecord{FT}(
        row.event,
        channel,
        row.process,
        stage,
        weight,
        parts(:positive),
        parts(:negative),
    )
end

# ============================================================================
# Transfer legs from the applied-update events
# ============================================================================

# Every declared transfer leg at every stage its channel is weighted at, from
# the measurement the bracket took there, and the bracket's own totals beside
# them. A leg the bracket did not read at a weighted stage keeps a zero slot
# and is recorded as unknown.
function fill_transfer_slots!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    integrator,
)
    (; schema, template) = adapter
    tableau = integrator.cache.tableau
    dt = BUDGET_ACCOUNTING_TYPE(float(integrator.dt))
    zeros = (zero(dt), zero(dt), zero(dt))
    for spec in schema.transfer_events, (reservoir, leg) in spec.modeled_legs
        channel = leg_channel(spec, reservoir, leg)
        for stage in row_stages(template, channel)
            weight = row_weight(tableau, channel, stage, dt)
            measurement = get(adapter.legs, (spec.name, reservoir, leg, stage), nothing)
            values =
                isnothing(measurement) || !measurement.known ? (zeros, zeros) :
                scale(weight, (measurement.amounts, measurement.magnitudes))
            set_measurement!(
                packet,
                adapter,
                transfer_leg_group(spec.name, reservoir, leg, stage),
                values;
                reservoir,
            )
        end
    end
    for ((label, reservoir), kind) in bracket_totals(schema)
        channel = evaluation_channel(kind)
        store = reservoir === ATMOSPHERE_ENDPOINT_GROUP ? adapter.parts : adapter.slab_parts
        for stage in row_stages(template, channel)
            weight = row_weight(tableau, channel, stage, dt)
            parts = get(store, (kind, label, stage), nothing)
            values =
                isnothing(parts) ? (zeros, zeros) :
                scale(weight, (parts[1] .+ parts[2], parts[1] .- parts[2]))
            set_measurement!(
                packet,
                adapter,
                bracket_group(label, reservoir, stage),
                values;
                reservoir,
            )
        end
    end
    return nothing
end

# One leg per declared transfer leg and weighted stage, from the packet, with
# each quantity as the event declares it, and the bracket checks beside them.
function record_transfer_legs!(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    integrator,
    step::Int,
)
    (; schema, ledger, template) = adapter
    FT = BUDGET_ACCOUNTING_TYPE
    tableau = integrator.cache.tableau
    dt = FT(float(integrator.dt))
    empty!(adapter.last_transfer_checks)
    sums = Dict{Tuple{Symbol, Symbol, Int}, NTuple{3, FT}}()
    for spec in schema.transfer_events, (reservoir, leg) in spec.modeled_legs
        channel = leg_channel(spec, reservoir, leg)
        label = transfer_leg_event(spec.name, reservoir)
        for stage in row_stages(template, channel)
            weight = row_weight(tableau, channel, stage, dt)
            group = transfer_leg_group(spec.name, reservoir, leg, stage)
            measurement = get(adapter.legs, (spec.name, reservoir, leg, stage), nothing)
            reason = if isnothing(measurement)
                channel === :implicit && !has_post_implicit_evaluation(adapter) ?
                :no_post_implicit_evaluation : :event_not_recorded
            elseif !measurement.known
                measurement.reason
            else
                :measured
            end
            mass, water, energy = map(BUDGET_QUANTITIES) do quantity
                transfer_component(
                    adapter,
                    spec,
                    reservoir,
                    packet,
                    group,
                    quantity,
                    reason,
                    label,
                )
            end
            record_leg!(
                ledger,
                BudgetLeg{FT}(;
                    event = spec.name,
                    leg,
                    reservoir = endpoint_reservoir(reservoir),
                    channel,
                    level = ReservoirTransfer(),
                    mass,
                    water,
                    energy,
                    path = EquationTerm(),
                    process = label,
                    phase = channel,
                    step,
                    stage,
                    weight,
                    measured_at = is_bracket_total(spec.name, reservoir) ?
                                  :bracket_total : :flux_quadrature,
                ),
            )
            if reason === :measured && !is_bracket_total(spec.name, reservoir)
                key = (label, reservoir, stage)
                current = get(sums, key, (zero(FT), zero(FT), zero(FT)))
                sums[key] = current .+ (mass.amount, water.amount, energy.amount)
            end
        end
    end
    for ((label, reservoir), kind) in bracket_totals(schema)
        for stage in row_stages(template, evaluation_channel(kind))
            haskey(sums, (label, reservoir, stage)) || continue
            group = bracket_group(label, reservoir, stage)
            bracket = map(BUDGET_QUANTITIES) do quantity
                quantity_applicable(schema, reservoir, quantity) ?
                packet_value(packet, group, quantity) : zero(FT)
            end
            push!(
                adapter.last_transfer_checks,
                TransferCheck{FT}(
                    label,
                    reservoir,
                    stage,
                    bracket,
                    sums[(label, reservoir, stage)],
                ),
            )
        end
    end
    return nothing
end

# One quantity of a transfer leg at one stage: measured where the event
# declares it measured, required to be exactly zero where it declares a zero,
# not applicable where the reservoir does not own it, and unknown with the
# reason where the bracket could not read it.
function transfer_component(
    adapter::ParentBudgetAdapter,
    spec::TransferEventSpec,
    reservoir::Symbol,
    packet::BudgetPacket,
    group::Symbol,
    quantity::Symbol,
    reason::Symbol,
    label::Symbol,
)
    FT = BUDGET_ACCOUNTING_TYPE
    quantity_applicable(adapter.schema, reservoir, quantity) ||
        return not_applicable(FT; source = :schema)
    expected = expected_disposition(spec, quantity)
    expected === :not_applicable && return not_applicable(FT; source = :coverage_registry)
    source = Symbol("event.", label)
    reason === :measured || return unknown_component(FT; reason, source)
    value = packet_value(packet, group, quantity)
    if expected === :invariant_zero
        iszero(value) || error(
            "The registry declares transfer event $(spec.name) provably zero " *
            "for $quantity in $reservoir, but its leg moved the quantity by " *
            "$value. The registry and the code disagree.",
        )
        return invariant_zero(
            FT;
            proof = :registry_proof_checked_at_event,
            source = :coverage_registry,
        )
    end
    expected === :measured && return measured(
        value;
        method = :independent_quadrature,
        source,
        route = :packed_global_reduction,
        magnitude = packet_value(packet, magnitude_group(group), quantity),
    )
    return unknown_component(FT; reason = :disposition_open, source = :coverage_registry)
end

# ============================================================================
# Reading the results
# ============================================================================

"""
    latest_transfer_checks(adapter) -> Vector{TransferCheck}

The bracket checks of the last accepted step: each applied-update event's
own total in each reservoir beside the transfer legs it measured, per stage.
Empty outside `AuditMode`.
"""
latest_transfer_checks(adapter::ParentBudgetAdapter) = adapter.last_transfer_checks

"""
    latest_gross(adapter) -> Vector{GrossRecord}

The gross parts of the last accepted step's measured process rows, empty
unless `parent_budget_attribution` is `gross`.
"""
latest_gross(adapter::ParentBudgetAdapter) = adapter.last_gross

"""
    latest_commit(adapter) -> Union{Nothing, BudgetCommit}

The reconciliations of the last accepted step, or `nothing` before the first.
"""
latest_commit(adapter::ParentBudgetAdapter) = adapter.last_commit

"""
    parent_status(adapter, quantity, control_volume) -> Symbol

The parent claim's status for one quantity in one control volume at the last
commit: `:pass`, `:fail`, `:blocked` or `:not_applicable`.
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
