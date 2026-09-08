#####
##### Parent-budget ledger: the timestepper adapter
#####
##### The one place that knows how `ClimaTimeSteppers` builds an accepted step.
##### The transaction and reconciliation code knows nothing about processes or
##### tableaus, and the journal knows nothing about the integrator; everything
##### timestepper-specific is here, so that a change in the pinned behaviour is
##### a change to one file and to the trace test that fixes it.
#####
##### The adapter sees a step twice. During the step it sits behind the `lim!`,
##### `dss!`, `constrain_state!`, `initialize_imp!` and `T_post_imp!` hooks as
##### meters that read the state before and after each call and never write it.
##### After the step it runs as the first discrete callback: it reads the stage
##### tendencies the stepper cache still holds, packs every reservoir's endpoint,
##### every channel's envelope, the final maps and whatever the meters measured
##### into one buffer, reduces that buffer once, records the legs, commits the
##### transaction, and opens the next one on the closing endpoint.
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
  - `AuditMode`: everything `SummaryMode` measures, and in addition every
    intermediate hook firing as a stage observation, the algebraic solve defect
    and the post-implicit correction of every implicit stage, and every step's
    reconciliations. It costs one extra implicit tendency evaluation per
    implicit stage and storage that grows with the run, which is why it is not
    the default.

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

Measure every firing, the solve defect and the correction, and keep every
commit. See `ParentBudgetMode`.
"""
struct AuditMode <: ParentBudgetMode end

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

The `ClimaODEFunction` hooks the adapter meters: the three that write the
state, the implicit-stage initialiser, which tells the adapter the stage's
`dtγ`, and the post-implicit correction, which is where the Newton-solved
stage is visible.
"""
const METERED_HOOKS = (:lim!, :dss!, :constrain_state!, :initialize_imp!, :T_post_imp!)

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
the final limiter, DSS and constraint on the accepted state. A first-same-as-last
tableau skips the post-Newton constraint at its last stage, because the
end-of-step firing covers the same state.
"""
function hook_template(
    tableau,
    cadence::Symbol,
    has_post_implicit::Bool,
    has_initializer::Bool,
    fsal::Bool,
)
    a_imp = tableau.a_imp.coeffs
    s = length(tableau.b_imp.coeffs)
    calls = HookCall[]
    counts = Dict{Symbol, Int}(hook => 0 for hook in METERED_HOOKS)
    implicit_stages = Int[]
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
        implicit || continue
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
    push_call!(:lim!, 0, :final)
    push_call!(:dss!, 0, :final)
    push_call!(:constrain_state!, 0, :final)
    per_hook = Dict{Symbol, Vector{Int}}(hook => Int[] for hook in METERED_HOOKS)
    for (index, call) in enumerate(calls)
        push!(per_hook[call.hook], index)
    end
    return HookTemplate(calls, per_hook, implicit_stages)
end

# ============================================================================
# The adapter
# ============================================================================

"""
    ParentBudgetAdapter

The ledger and everything it needs to run inside a simulation: the schema and
the ledger built from it, the one packet the step reduces, the hook template,
the record of the timestepper, the tolerances, what the meters measured in the
current step, and what has been committed. `last_commit`, `last_legs` and
`last_observations` hold the latest step's results in every mode; `commits`
holds every commit in `AuditMode` only. `reductions` counts the packets reduced,
which a test compares with the number of accepted steps.

The mode is a field rather than a type parameter on purpose. The adapter rides
in the cache, whose type every tendency function specialises on, so a mode in
the type would compile the whole model twice for two runs that differ only in
what they keep.

The per-step fields are cleared at every commit, so their storage is bounded
by the template and never by the run's length.
"""
mutable struct ParentBudgetAdapter{S, C, T}
    mode::ParentBudgetMode
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
    scratch_tendency::T
    timestepper::Union{Nothing, TimestepperRecord}
    stepper_cache::Any
    # Per-step meter state.
    calls::Dict{Symbol, Int}
    before::NTuple{3, BUDGET_ACCOUNTING_TYPE}
    dtγ::Dict{Int, BUDGET_ACCOUNTING_TYPE}
    final_changes::Dict{Symbol, NTuple{3, BUDGET_ACCOUNTING_TYPE}}
    folded::Vector{Tuple{Symbol, Int, NTuple{3, BUDGET_ACCOUNTING_TYPE}}}
    observations::Vector{Tuple{HookCall, NTuple{3, BUDGET_ACCOUNTING_TYPE}}}
    defects::Vector{Tuple{Int, NTuple{3, BUDGET_ACCOUNTING_TYPE}}}
    corrections::Vector{Tuple{Int, NTuple{3, BUDGET_ACCOUNTING_TYPE}}}
    # Results.
    steps_committed::Int
    reductions::Int
    last_commit::Union{Nothing, BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
    last_legs::Vector{BudgetLeg{BUDGET_ACCOUNTING_TYPE}}
    last_observations::Vector{StageObservation{BUDGET_ACCOUNTING_TYPE}}
    commits::Vector{BudgetCommit{BUDGET_ACCOUNTING_TYPE}}
end

is_audit(adapter::ParentBudgetAdapter) = adapter.mode isa AuditMode

"""
    parent_budget_tolerances(tolerances) -> Union{Nothing, Dict}

Check a caller's tolerance table: `nothing`, or a mapping from a subset of
`BUDGET_QUANTITIES` to `BudgetTolerance`s in the accounting type. Until the
calibration table of stack step 8 exists, this is the only way a run gets a
tolerance, and a run without one reports every verdict as `blocked`.
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

function stage_rows(schema::BudgetSchema)
    has_channel(schema, :implicit) || return Symbol[]
    spec = channel_spec(schema, :implicit)
    return [
        process for process in STAGE_ROWS if
        !isnothing(process_row(spec, process, ATMOSPHERE_ENDPOINT_GROUP))
    ]
end

# A final map that some configured path writes is measured; one that writes no
# parent field is booked as the invariant zero its rows prove.
hook_is_measured(schema::BudgetSchema, hook::Symbol) =
    :measured in final_map_spec(schema, hook).dispositions

final_map_group(hook::Symbol) = Symbol("finalmap.", hook)
stage_row_group(process::Symbol, stage::Int) = Symbol("decomp.", process, ".", stage)
observation_group(call::HookCall) =
    Symbol("obs.", call.hook, ".", call.role, ".", call.stage, ".", call.occurrence)

# Whether a firing of a state-writing hook is a stage observation rather than a
# final map or a folded contribution.
is_observation(call::HookCall) =
    call.hook in FINAL_MAP_HOOKS && call.role in (:stage, :pre_solve, :post_init)

"""
    adapter_packet_layout(schema, template, mode)

The layout of the one packet an accepted step reduces: the endpoint slots, the
envelope slots of every collected channel in every reservoir it writes, the
slots of the final maps that are measured, and in `AuditMode` the slots of the
per-stage implicit rows and of every stage observation. Fixed from the schema,
the template and the mode, so every rank builds the same layout before the
first step.
"""
function adapter_packet_layout(
    schema::BudgetSchema,
    template::HookTemplate,
    mode::ParentBudgetMode,
)
    layout = budget_packet_layout(schema, COLLECTED_CHANNELS)
    slots = copy(layout.slots)
    for hook in FINAL_MAP_HOOKS
        hook_is_measured(schema, hook) || continue
        for quantity in BUDGET_QUANTITIES
            push!(slots, (final_map_group(hook), quantity))
        end
    end
    if mode isa AuditMode
        for process in stage_rows(schema), stage in template.implicit_stages
            for quantity in BUDGET_QUANTITIES
                push!(slots, (stage_row_group(process, stage), quantity))
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
                        tolerances = nothing) -> Union{Nothing, ParentBudgetAdapter}

The adapter for a run, or `nothing` when `mode` is `off`.

Everything the ledger expects is fixed here, before the cache is built and
before the first step: the configuration is checked against the supported
scope, the schema is built from the coverage registry, the hook template from
the tableau and the cadence, and the packet layout from all three.

A restart is refused until stack step 7 gives the restored state its
zero-duration transition. Reading a restart file into a fresh ledger would
either charge the restoration to the first step or silently absorb it.
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
    tolerances = nothing,
)
    restart && error(
        "The parent-budget ledger does not support restarts yet: a restored " *
        "state is a transition no transaction produced, and stack step 7 gives " *
        "it one. Pass `parent_budget_mode = \"off\"` for this run.",
    )
    check_algorithm(ode_config)
    implicit_solve = !isnothing(ode_config.newtons_method)
    dss = do_dss(axes(Y.c))
    schema = budget_schema(atmos; dss, implicit_solve, restart, constraint_cadence)
    has_post_implicit =
        implicit_solve && atmos.numerics.energy_q_tot_upwinding != Val(:none)
    template = hook_template(
        ode_config.tableau,
        constraint_cadence,
        has_post_implicit,
        true,
        CTS.is_fsal(ode_config),
    )
    layout = adapter_packet_layout(schema, template, mode)
    scratch_tendency = mode isa AuditMode ? similar(Y) : nothing
    FT = BUDGET_ACCOUNTING_TYPE
    return ParentBudgetAdapter(
        mode,
        schema,
        atmos.surface.temperature,
        budget_context(Y),
        owns_atmosphere_water(atmos.microphysics_model),
        BudgetLedger{FT}(schema),
        template,
        layout,
        BudgetPacket(layout),
        COLLECTED_CHANNELS,
        parent_budget_tolerances(tolerances),
        scratch_tendency,
        nothing,
        nothing,
        Dict{Symbol, Int}(hook => 0 for hook in METERED_HOOKS),
        (zero(FT), zero(FT), zero(FT)),
        Dict{Int, FT}(),
        Dict{Symbol, NTuple{3, FT}}(),
        Tuple{Symbol, Int, NTuple{3, FT}}[],
        Tuple{HookCall, NTuple{3, FT}}[],
        Tuple{Int, NTuple{3, FT}}[],
        Tuple{Int, NTuple{3, FT}}[],
        0,
        0,
        nothing,
        BudgetLeg{FT}[],
        StageObservation{FT}[],
        BudgetCommit{FT}[],
    )
end

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
    empty!(adapter.corrections)
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

# Book a measured change where its role says it belongs.
function book_change!(adapter::ParentBudgetAdapter, call::HookCall, change)
    if call.role === :final
        adapter.final_changes[call.hook] = change
    elseif call.role === :post_newton
        push!(adapter.folded, (call.hook, call.stage, change))
    else
        push!(adapter.observations, (call, change))
    end
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
    measure && book_change!(adapter, call, parent_integrals(adapter, Y) .- adapter.before)
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
        meter.implicit_tendency(tendency, U, p, t)
        residual =
            parent_integrals(adapter, adapter.stepper_cache.temp) .+
            dtγ .* parent_integrals(adapter, tendency) .-
            parent_integrals(adapter, U)
        push!(adapter.defects, (call.stage, residual))
    end
    meter.f(Yₜ, U, p, t)
    is_audit(adapter) &&
        push!(adapter.corrections, (call.stage, parent_integrals(adapter, Yₜ)))
    return nothing
end

"""
    meter_hook(adapter, hook, f)
    meter_initialize(adapter, f)
    meter_post_implicit(adapter, f, implicit_tendency)

The hook `f` behind the adapter's meter, or `f` itself when there is no adapter,
so `args_integrator` wires the same names whether the ledger is on or off.
"""
meter_hook(::Nothing, ::Symbol, f) = f
meter_hook(adapter::ParentBudgetAdapter, hook::Symbol, f) = HookMeter(hook, f, adapter)
meter_initialize(::Nothing, f) = f
meter_initialize(adapter::ParentBudgetAdapter, f) = InitializeMeter(f, adapter)
meter_post_implicit(::Nothing, f, _) = f
meter_post_implicit(::ParentBudgetAdapter, ::Nothing, _) = nothing
meter_post_implicit(adapter::ParentBudgetAdapter, f, implicit_tendency) =
    PostImplicitMeter(f, implicit_tendency, adapter)

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
# cache the integrator built is checked against the template built earlier.
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
    clear_step_state!(adapter)
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
One packet, one collective, then the legs are recorded, the transaction is
committed, the hook counts are checked against the template, and the next
transaction opens on the closing endpoint without measuring it again.
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
    is_audit(adapter) && fill_audit_slots!(packet, adapter, integrator)
    reduce_packet!(adapter.context, packet)
    adapter.reductions += 1

    closing = budget_endpoints(packet, schema, step)
    record_envelopes!(adapter, packet, step)
    record_final_maps!(adapter, packet, step)
    is_audit(adapter) && record_audit_legs!(adapter, packet, integrator, step)
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

# A slot per quantity from a measured triple, honouring applicability.
function set_triple!(
    packet::BudgetPacket,
    adapter::ParentBudgetAdapter,
    group::Symbol,
    values,
)
    for (k, quantity) in enumerate(BUDGET_QUANTITIES)
        if quantity_applicable(adapter.schema, ATMOSPHERE_ENDPOINT_GROUP, quantity)
            set_local!(packet, group, quantity, values[k])
        else
            set_inapplicable!(packet, group, quantity)
        end
    end
    return nothing
end

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
        set_triple!(packet, adapter, final_map_group(hook), adapter.final_changes[hook])
    end
    return nothing
end

# The per-stage implicit rows and the stage observations, weighted as they
# enter the accepted update where they do, and raw where they do not.
function fill_audit_slots!(packet::BudgetPacket, adapter::ParentBudgetAdapter, integrator)
    tableau = integrator.cache.tableau
    dt = BUDGET_ACCOUNTING_TYPE(float(integrator.dt))
    rows = stage_rows(adapter.schema)
    for stage in adapter.template.implicit_stages
        b = BUDGET_ACCOUNTING_TYPE(tableau.b_imp.coeffs[stage])
        γ = BUDGET_ACCOUNTING_TYPE(tableau.a_imp.coeffs[stage, stage])
        folded_weight = b / γ
        if :solve_defect in rows
            # The stored tendency is `dtγ T(U*) − r` plus the hooks, so the
            # defect enters the accepted update with weight `−b/γ`.
            residual = stage_value(adapter.defects, stage, "solve defect")
            set_triple!(
                packet,
                adapter,
                stage_row_group(:solve_defect, stage),
                (-folded_weight) .* residual,
            )
        end
        if :post_implicit_correction in rows
            correction = stage_value(adapter.corrections, stage, "post-implicit correction")
            set_triple!(
                packet,
                adapter,
                stage_row_group(:post_implicit_correction, stage),
                (dt * b) .* correction,
            )
        end
        for (process, hook) in
            ((:folded_dss, :dss!), (:folded_constraint, :constrain_state!))
            process in rows || continue
            group = stage_row_group(process, stage)
            change = folded_change(adapter, hook, stage)
            # A hook the template skips at this stage, such as the constraint at
            # the last stage of a first-same-as-last tableau, contributes zero.
            values =
                isnothing(change) ? (zero(dt), zero(dt), zero(dt)) : folded_weight .* change
            set_triple!(packet, adapter, group, values)
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
function atmosphere_components(
    adapter::ParentBudgetAdapter,
    packet::BudgetPacket,
    group::Symbol;
    method::Symbol,
    source::Symbol,
)
    FT = BUDGET_ACCOUNTING_TYPE
    component(quantity) =
        quantity_applicable(adapter.schema, ATMOSPHERE_ENDPOINT_GROUP, quantity) ?
        measured(
            packet_value(packet, group, quantity);
            method,
            source,
            route = :packed_global_reduction,
        ) :
        not_applicable(FT; source = :schema)
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
                return measured(
                    packet_value(packet, final_map_group(hook), quantity);
                    method = :accepted_state_difference,
                    source = Symbol("adapter.", hook),
                    route = :packed_global_reduction,
                )
            elseif expected === :invariant_zero
                if !isnothing(measured_change) && !iszero(measured_change[k])
                    error(
                        "The registry declares the final $hook provably zero for " *
                        "$quantity in this configuration, but it changed the " *
                        "quantity by $(measured_change[k]). The registry and the " *
                        "code disagree.",
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
    end
    for (call, _) in adapter.observations
        mass, water, energy = atmosphere_components(
            adapter, packet, observation_group(call);
            method = :stage_difference, source = Symbol("adapter.", call.hook),
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
# Reading the results
# ============================================================================

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
