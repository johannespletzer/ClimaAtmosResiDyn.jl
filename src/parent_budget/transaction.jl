#####
##### Parent-budget ledger: transactions and reconciliation
#####
##### One transaction per accepted timestep. It opens on the endpoint state
##### after step `n` is finalized, collects legs, and closes on the endpoint
##### state after step `n+1` is finalized. Nothing is committed until it
##### closes, so a step that never completes leaves no entries behind.
#####
##### The reconciliation is one subtraction:
#####
#####     R_bookkeeping = ΔB_actual - ΣQ_recorded
#####
##### and there is deliberately no way to write it the other way round. No
##### function here creates a leg, so the ledger cannot close a budget it has
##### not accounted for.

# ============================================================================
# Endpoints
# ============================================================================

"""
    BUDGET_ACCOUNTING_TYPE

The float type the ledger does its own arithmetic in, `Float64`.

Deliberately independent of the state's float type. The contract fixes the
accounting precision at no less than `Float64` whatever the model runs in,
because the residual is a small number left over from subtracting two large
ones and a `Float32` subtraction destroys it. Every endpoint, leg amount,
cumulative total and residual is this type.

The `FT` parameter on [`BudgetComponent`](@ref), [`BudgetLeg`](@ref),
[`ReservoirEndpoint`](@ref) and [`BudgetLedger`](@ref) is this accounting type,
never the state's.
"""
const BUDGET_ACCOUNTING_TYPE = Float64

"""
    ReservoirEndpoint(; reservoir, mass, water, energy)

The three authoritative integrals of one reservoir at one instant.

A component is [`not_applicable`](@ref) when the reservoir does not own that
quantity, which is how "a dry configuration has no water" is expressed without
writing a zero that the identity would then have to reconcile.
"""
Base.@kwdef struct ReservoirEndpoint{FT}
    reservoir::BudgetReservoir
    mass::BudgetComponent{FT}
    water::BudgetComponent{FT}
    energy::BudgetComponent{FT}
end

function budget_component(endpoint::ReservoirEndpoint, quantity::Symbol)
    quantity === :mass && return endpoint.mass
    quantity === :water && return endpoint.water
    quantity === :energy && return endpoint.energy
    error("Unknown budget quantity $quantity; expected :mass, :water or :energy")
end

"""
    BudgetEndpoints(step, reservoirs)

Every reservoir's [`ReservoirEndpoint`](@ref) at one instant, tagged with the
accepted step it belongs to.
"""
struct BudgetEndpoints{FT}
    step::Int
    reservoirs::Vector{ReservoirEndpoint{FT}}
end

"""
    budget_endpoints(Y, surface_temperature, microphysics_model, step)

Measure every reservoir's authoritative integrals from the state `Y`.

The atmosphere always contributes. The slab surface contributes only when
[`surface_energy`](@ref) finds one, and then it carries energy, and carries
water and the mass that goes with it in a moist configuration.

`microphysics_model` is required rather than inferred. A slab carries
`Y.sfc.water` even in a dry run, where it holds a permanent zero, so presence of
the field cannot distinguish an inapplicable quantity from a measured one. See
[`surface_water`](@ref).

# Accounting arithmetic

Endpoints are held in [`BUDGET_ACCOUNTING_TYPE`](@ref), not in the state's float
type. A leg is a small increment against a large global background, and the
residual is what survives subtracting two of those backgrounds. In `Float32` the
background carries about seven significant digits, so a per-step change eight
orders below it is gone in the subtraction and the residual measures nothing but
rounding.

This widens everything the ledger itself does: the endpoint subtraction, the leg
sums, the running totals. It does **not** widen the reduction inside ClimaCore,
which still accumulates in the state's type. Narrowing that is a change where
the reduction is made, not here, and it is recorded as a blocker in the contract.

# Reduction count

Each call is a handful of separate global reductions, and it runs twice per
transaction. The contract requires one packed reduction per accepted step, which
this does not yet satisfy. Two things close the gap and neither belongs in this
PR: packing the local totals into a single collective, and reusing the previous
closing endpoint instead of measuring the opening one. The second is available
now through `open_transaction!`, with the caveat documented there. Nothing calls
this in a run yet, so the cost is currently zero.
"""
function budget_endpoints(Y, surface_temperature, microphysics_model, step::Int)
    FT = BUDGET_ACCOUNTING_TYPE
    reservoirs = ReservoirEndpoint{FT}[]
    owns_water = !(microphysics_model isa DryModel)

    push!(
        reservoirs,
        ReservoirEndpoint{FT}(;
            reservoir = AtmosphereReservoir(),
            mass = measured(FT(atmosphere_mass(Y))),
            water = owns_water ? measured(FT(atmosphere_water(Y))) :
                    not_applicable(FT),
            energy = measured(FT(atmosphere_energy(Y))),
        ),
    )

    e_sfc = surface_energy(Y, surface_temperature)
    if !isnothing(e_sfc)
        w_sfc = surface_water(Y, surface_temperature, microphysics_model)
        m_sfc = surface_mass(Y, surface_temperature, microphysics_model)
        push!(
            reservoirs,
            ReservoirEndpoint{FT}(;
                reservoir = SlabSurfaceReservoir(),
                # The slab's mass and water are one endpoint projected twice:
                # what it holds left the atmosphere as `ρq_tot`, which `ρ`
                # carries in full, and both read the same `Y.sfc.water`. They
                # cannot disagree and nothing here tests that they do. Legs are
                # where independent collection matters, not endpoints.
                mass = isnothing(m_sfc) ? not_applicable(FT) :
                       measured(FT(m_sfc)),
                water = isnothing(w_sfc) ? not_applicable(FT) :
                        measured(FT(w_sfc)),
                energy = measured(FT(e_sfc)),
            ),
        )
    end

    return BudgetEndpoints{FT}(step, reservoirs)
end

"""
    endpoint_total(endpoints, quantity, control_volume)

Sum one quantity over the reservoirs of `control_volume`.

Returns `(; total, applicable, blocked_by)`. A reservoir outside the control
volume is skipped entirely, so it can neither contribute nor block.

`applicable` is false when no reservoir in the view owns the quantity at all,
which is not the same as a total of zero. Water in a dry model, or anything at
all in the coupled view of a configuration with no slab, would otherwise be
reported as an ordinary closed budget at zero — a claim the ledger never made.

`blocked_by` names the reservoirs whose component was unknown, so a blocked
report says what would unblock it instead of only that it is blocked.
"""
function endpoint_total(
    endpoints::BudgetEndpoints{FT},
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    total = zero(FT)
    applicable = false
    blocked_by = String[]
    for endpoint in endpoints.reservoirs
        is_inside(cv, endpoint.reservoir) || continue
        c = budget_component(endpoint, quantity)
        c.status isa NotApplicable || (applicable = true)
        is_contributing(c) && (total += c.amount)
        if is_blocking(c)
            push!(blocked_by, "$(reservoir_name(endpoint.reservoir)) endpoint")
        end
    end
    return (; total, applicable, blocked_by)
end

# ============================================================================
# The ledger
# ============================================================================

"""
    BudgetLedger{FT}()

The open transaction and the running cumulative totals.

A ledger is opened on an endpoint, collects legs, and is committed on the next
endpoint.

Three cumulative residuals are kept per quantity and control volume, not one,
because a signed sum cancels the very failure the ledger exists to expose:
`+δ` on one step and `−δ` on the next sums to zero and reports a perfectly
closed run that closed on neither step. `cumulative_residual` is the signed
total, the drift. `cumulative_abs_residual` cannot cancel and bounds the total
unaccounted transfer. `max_abs_residual` names the worst single step. A
tolerance is checked against the last two; the signed sum is reported and never
passes a test on its own.

The ledger is a diagnostic. Nothing in it writes to the state, and a run with
it enabled must produce the same trajectory as one without it.
"""
mutable struct BudgetLedger{FT}
    step::Int
    is_open::Bool
    opening::Union{Nothing, BudgetEndpoints{FT}}
    initial::Union{Nothing, BudgetEndpoints{FT}}
    last_closing::Union{Nothing, BudgetEndpoints{FT}}
    legs::Vector{BudgetLeg{FT}}
    observations::Vector{StageObservation{FT}}
    recorded_keys::Set{Tuple{Symbol, Symbol, Int, Int, Int}}
    aggregate_events::Set{Tuple{Symbol, Int}}
    decomposed_events::Set{Tuple{Symbol, Int}}
    cumulative_residual::Dict{Tuple{Symbol, Symbol}, FT}
    cumulative_abs_residual::Dict{Tuple{Symbol, Symbol}, FT}
    max_abs_residual::Dict{Tuple{Symbol, Symbol}, FT}
    cumulative_change::Dict{Tuple{Symbol, Symbol}, FT}
    committed_steps::Int
end

BudgetLedger{FT}() where {FT} = BudgetLedger{FT}(
    0,
    false,
    nothing,
    nothing,
    nothing,
    BudgetLeg{FT}[],
    StageObservation{FT}[],
    Set{Tuple{Symbol, Symbol, Int, Int, Int}}(),
    Set{Tuple{Symbol, Int}}(),
    Set{Tuple{Symbol, Int}}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    0,
)

"""
    check_endpoint_continuity(ledger, opening)

Verify that `opening` is the endpoint the previous transaction closed on.

The first transaction has nothing to compare against and passes. Afterwards the
step numbers, the reservoir set, every component's **status**, and every
contributing amount must agree exactly. Exactly, not within a tolerance: a
reduction over an unchanged state is deterministic, so any difference is a real
change that happened between the two transactions and that nothing recorded.

Status is checked as well as amount because comparing amounts alone lets a
reservoir change what it owns without anyone noticing. A quantity that was
measured and is now unknown, or was inapplicable and is now measured, would slip
through a check that skips any pair where one side does not contribute — which
is precisely the pair a status change produces. A configuration transition
mid-run is not supported, so a status change is a defect until it is
deliberately represented.
"""
function check_endpoint_continuity(
    ledger::BudgetLedger{FT},
    opening::BudgetEndpoints{FT},
) where {FT}
    previous = ledger.last_closing
    isnothing(previous) && return nothing
    previous.step == opening.step || error(
        "Budget transaction opens on step $(opening.step) but the previous " *
        "one closed on step $(previous.step).",
    )
    length(previous.reservoirs) == length(opening.reservoirs) || error(
        "The budget reservoir set changed between transactions, from " *
        "$(length(previous.reservoirs)) reservoirs to " *
        "$(length(opening.reservoirs)).",
    )
    for (before, after) in zip(previous.reservoirs, opening.reservoirs)
        before.reservoir === after.reservoir || error(
            "The budget reservoir order changed between transactions.",
        )
        for quantity in BUDGET_QUANTITIES
            b = budget_component(before, quantity)
            a = budget_component(after, quantity)
            typeof(b.status) === typeof(a.status) || error(
                "Budget endpoint status changed for $quantity in " *
                "$(reservoir_name(after.reservoir)) at step $(opening.step): " *
                "the previous transaction closed as " *
                "$(nameof(typeof(b.status))) and this one opens as " *
                "$(nameof(typeof(a.status))). What a reservoir owns may not " *
                "change mid-run without being represented as a transition.",
            )
            is_contributing(a) || continue
            b.amount == a.amount || error(
                "Budget endpoint discontinuity in $quantity for " *
                "$(reservoir_name(after.reservoir)) at step $(opening.step): " *
                "the previous transaction closed on $(b.amount) and this one " *
                "opens on $(a.amount), a gap of $(a.amount - b.amount) that " *
                "no transaction accounts for.",
            )
        end
    end
    return nothing
end

"""
    open_transaction!(ledger, endpoints)

Begin the transaction for the step `endpoints.step + 1`.

`endpoints` is the state after accepted step `n` was finalized, and the
transaction it opens ends after accepted step `n + 1` is finalized. Opening
while a transaction is already open is an error, because it would mean the
previous step neither committed nor aborted.

Continuity with the previous transaction is checked rather than assumed: these
opening endpoints must equal the ones the last transaction closed on. A gap
between them is a change that nothing accounted for, and it would otherwise
disappear from the cumulative total without leaving a residual anywhere.
"""
"""
    open_transaction!(ledger)

Open the next transaction on the endpoint the previous one closed, without
measuring the state again.

This is the reduction the contract's cost rule most wants back: measuring the
opening endpoint repeats, identically, the reduction the previous commit already
performed. Reusing it halves the endpoint reductions per step.

**It also gives up the only check that would catch an unrecorded change between
steps.** [`check_endpoint_continuity`](@ref) exists because the closing state of
step `n` and the opening state of step `n+1` are read at different moments with
discrete callbacks in between, and comparing them is what turns a callback that
quietly mutates `Y` into an error instead of a silent gap in the cumulative
total. Reuse makes that comparison compare a value with itself.

The trade is sound only while no callback mutates the state. That holds in every
supported configuration today, and the mutation matrix in the coverage document
is what establishes it — but it is an assumption about the model rather than a
property of the ledger, so it is opt-in and the measured path stays the default.

Errors when there is no previous closing endpoint, which is the first step.
"""
function open_transaction!(ledger::BudgetLedger)
    previous = ledger.last_closing
    isnothing(previous) && error(
        "No previous closing endpoint to reuse; the first transaction has to " *
        "measure its opening endpoint.",
    )
    return open_transaction!(ledger, previous)
end

function open_transaction!(
    ledger::BudgetLedger{FT},
    endpoints::BudgetEndpoints{FT},
) where {FT}
    ledger.is_open && error(
        "A budget transaction for step $(ledger.step) is already open. " *
        "Commit or abort it before opening another.",
    )
    check_endpoint_continuity(ledger, endpoints)
    ledger.step = endpoints.step + 1
    ledger.is_open = true
    ledger.opening = endpoints
    isnothing(ledger.initial) && (ledger.initial = endpoints)
    empty!(ledger.legs)
    empty!(ledger.observations)
    empty!(ledger.recorded_keys)
    empty!(ledger.aggregate_events)
    empty!(ledger.decomposed_events)
    return nothing
end

"""
    record_leg!(ledger, leg)

Add `leg` to the open transaction.

Refused, loudly, in three cases. There is no open transaction, so the leg
belongs to no accepted step. The leg's `step` disagrees with the open one, which
means a stage or a callback is writing into the wrong transaction. Or a leg with
the same `(event, leg, step, stage, occurrence)` is already recorded, which is
how a bracket that fires twice at the same point shows up. A correction that
legitimately fires once per stage carries a different `stage` each time and is
not a duplicate.

It also refuses a leg that would be booked alongside its own aggregate, or an
aggregate booked alongside its decomposition, for the same `(event, step)`.
Recording both counts the same update twice.

Why keep the duplicate guard, stated correctly this time. An earlier version of
this docstring claimed a doubled leg does not fail closure. That is wrong: a
duplicated nonzero leg increases the recorded sum, so the residual moves by the
same amount with the opposite sign, and closure fails. The guard earns its place
for three other reasons. It localizes the fault at the second recording rather
than in a residual a whole step later. It catches a doubled leg whose amount
happens to be zero, which genuinely would pass every closure test. And it forces
each firing of a repeating path to carry a distinct execution identity, which is
what makes a per-stage correction legible at all.
"""
function record_leg!(ledger::BudgetLedger{FT}, leg::BudgetLeg{FT}) where {FT}
    ledger.is_open || error(
        "No open budget transaction; cannot record leg $(leg.event)/$(leg.leg).",
    )
    leg.step == ledger.step || error(
        "Leg $(leg.event)/$(leg.leg) is for step $(leg.step), but the open " *
        "transaction is step $(ledger.step).",
    )
    key = leg_identity(leg)
    key in ledger.recorded_keys && error(
        "Leg $(leg_label(leg)) is already recorded. A leg is recorded once; " *
        "control-volume totals are projections of it. A path that legitimately " *
        "fires more than once in a step distinguishes its firings with `stage` " *
        "and `occurrence`.",
    )
    event_key = (leg.event, leg.step)
    if leg.aggregate
        event_key in ledger.decomposed_events && error(
            "Leg $(leg_label(leg)) is an aggregate for event $(leg.event), " *
            "but that event already has decomposed legs in this step. An " *
            "aggregate is the reconciliation envelope and is never summed " *
            "alongside its own decomposition.",
        )
    else
        event_key in ledger.aggregate_events && error(
            "Leg $(leg_label(leg)) decomposes event $(leg.event), but an " *
            "aggregate leg for that event is already recorded in this step. " *
            "Recording both counts the same update twice.",
        )
    end
    push!(ledger.recorded_keys, key)
    push!(leg.aggregate ? ledger.aggregate_events : ledger.decomposed_events, event_key)
    push!(ledger.legs, leg)
    return nothing
end

"""
    record_observation!(ledger, observation)

Add a `StageObservation` to the open transaction's audit trail.

Observations are evidence, never accounting. They are stored apart from the
legs, no projection iterates them, and no residual is computed from them, so
recording one cannot move a budget. That is the whole reason the type is
separate: an intermediate-stage difference is not an additive contribution to
the accepted endpoint, and the safest way to keep it out of the identity is to
make it something [`record_leg!`](@ref) will not take.

Unlike a leg, an observation is not deduplicated. Observing the same map at the
same stage twice is a reading, not a double count.
"""
function record_observation!(
    ledger::BudgetLedger{FT},
    observation::StageObservation{FT},
) where {FT}
    ledger.is_open || error(
        "No open budget transaction; cannot record observation " *
        "$(observation.event)/$(observation.observation).",
    )
    observation.step == ledger.step || error(
        "Observation $(observation.event)/$(observation.observation) is for " *
        "step $(observation.step), but the open transaction is step " *
        "$(ledger.step).",
    )
    push!(ledger.observations, observation)
    return nothing
end

"""
    abort_transaction!(ledger)

Discard the open transaction without committing anything.

This exists for the rejected-attempt rule, not because a supported
configuration reaches it. `args_integrator` passes a fixed `dt` and no
controller, so the IMEX integrator never rejects a step and never retries. If an
adaptive controller is added, this is the hook that keeps a rejected attempt
from committing, and the rollback of the *state* becomes real work that the
contract does not currently cover.
"""
function abort_transaction!(ledger::BudgetLedger)
    ledger.is_open = false
    ledger.opening = nothing
    empty!(ledger.legs)
    empty!(ledger.observations)
    empty!(ledger.recorded_keys)
    empty!(ledger.aggregate_events)
    empty!(ledger.decomposed_events)
    return nothing
end

# ============================================================================
# Projection and reconciliation
# ============================================================================

"""
    project_legs(ledger, quantity, control_volume)

Sum the recorded legs of one quantity over one control volume.

Returns a `NamedTuple` with the four identity terms, their total, and which
legs carried an unknown component:

`(; equation, map, correction, solve_defect, recorded, blocked_by)`

A leg outside the control volume is skipped, which is what makes a surface
exchange a boundary crossing in one view and an internal transfer in another
without recording it twice.

`blocked_by` holds the labels of the legs whose component was unknown, so a
blocked report names what would unblock it rather than only that it is blocked.
"""
function project_legs(
    ledger::BudgetLedger{FT},
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    equation = zero(FT)
    map_term = zero(FT)
    correction = zero(FT)
    solve_defect = zero(FT)
    blocked_by = String[]
    for leg in ledger.legs
        is_inside(cv, leg.reservoir) || continue
        c = budget_component(leg, quantity)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        is_contributing(c) || continue
        if leg.path isa EquationTerm
            equation += c.amount
        elseif leg.path isa DiscreteMap
            map_term += c.amount
        elseif leg.path isa NumericalCorrection
            correction += c.amount
        elseif leg.path isa AlgebraicSolveDefect
            solve_defect += c.amount
        else
            error("Leg $(leg.event)/$(leg.leg) has unclassified path $(leg.path)")
        end
    end
    recorded = equation + map_term + correction + solve_defect
    return (;
        equation,
        map = map_term,
        correction,
        solve_defect,
        recorded,
        blocked_by,
    )
end

"""
    BudgetReconciliation

What one quantity did over one accepted step in one control volume.

`residual` is `endpoint_change - recorded` and nothing else.
`discrepancy_before_defect` is what the residual would have been without the
algebraic solve defect, reported separately because the default Newton
configuration makes that defect a leading-order term rather than a small
correction.

Three cumulative residuals are carried, not one. `cumulative_residual` is the
signed drift, `cumulative_abs_residual` cannot cancel, and `max_abs_residual`
names the worst single step. A tolerance is checked against the last two.

`applicable` is false when no reservoir in this view owns the quantity, which is
different from a total of zero: there is no budget here to close, so there is no
claim either way. `blocked_by` names the endpoints and legs whose component was
unknown. A blocked reconciliation still reports its numbers, because they are
informative, but no closure claim may be made from it.
"""
Base.@kwdef struct BudgetReconciliation{FT}
    quantity::Symbol
    control_volume::Symbol
    step::Int
    applicable::Bool
    endpoint_change::FT
    equation::FT
    map::FT
    correction::FT
    solve_defect::FT
    recorded::FT
    residual::FT
    discrepancy_before_defect::FT
    cumulative_endpoint_change::FT
    endpoint_change_from_initial::FT
    telescoping_discrepancy::FT
    cumulative_residual::FT
    cumulative_abs_residual::FT
    max_abs_residual::FT
    blocked_by::Vector{String}
end

"""
    is_blocked(reconciliation) -> Bool

Whether any endpoint or leg carried an unknown component, so that no closure
claim may be made from this reconciliation.
"""
is_blocked(r::BudgetReconciliation) = !isempty(r.blocked_by)

"""
    reconcile(ledger, closing, quantity, control_volume)

Compute one [`BudgetReconciliation`](@ref) from the open transaction and the
closing endpoints. Pure; it does not mutate the ledger.
"""
function reconcile(
    ledger::BudgetLedger{FT},
    closing::BudgetEndpoints{FT},
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    opening = ledger.opening
    isnothing(opening) && error("No open budget transaction to reconcile.")
    control_volume_available(opening, cv) || error(
        "Control volume $(cv.name) is unavailable in this configuration: it " *
        "names a reservoir the state does not have. Projecting it anyway " *
        "would report another view's numbers under this view's name.",
    )

    before = endpoint_total(opening, quantity, cv)
    after = endpoint_total(closing, quantity, cv)
    endpoint_change = after.total - before.total

    projected = project_legs(ledger, quantity, cv)
    residual = endpoint_change - projected.recorded
    discrepancy_before_defect =
        endpoint_change - (projected.recorded - projected.solve_defect)

    key = (quantity, cv.name)
    cumulative_change =
        get(ledger.cumulative_change, key, zero(FT)) + endpoint_change

    # The contract asks for `Bᴺ - B⁰`, and a running sum of per-step
    # differences is not that. It telescopes the same measurements, so it can
    # only reproduce them plus the rounding of every intermediate addition, and
    # it can never contradict them. Holding the first accepted endpoint gives a
    # second reading that shares no arithmetic with the first, and their
    # difference is a measurement of the accumulation error rather than a
    # rederivation of it.
    initial = ledger.initial
    from_initial =
        isnothing(initial) ? endpoint_change :
        after.total - endpoint_total(initial, quantity, cv).total
    cumulative_residual =
        get(ledger.cumulative_residual, key, zero(FT)) + residual
    cumulative_abs_residual =
        get(ledger.cumulative_abs_residual, key, zero(FT)) + abs(residual)
    max_abs_residual =
        max(get(ledger.max_abs_residual, key, zero(FT)), abs(residual))

    blocked_by = vcat(before.blocked_by, after.blocked_by, projected.blocked_by)

    return BudgetReconciliation{FT}(;
        quantity,
        control_volume = cv.name,
        step = ledger.step,
        applicable = before.applicable || after.applicable,
        endpoint_change,
        equation = projected.equation,
        map = projected.map,
        correction = projected.correction,
        solve_defect = projected.solve_defect,
        recorded = projected.recorded,
        residual,
        discrepancy_before_defect,
        cumulative_endpoint_change = cumulative_change,
        endpoint_change_from_initial = from_initial,
        telescoping_discrepancy = cumulative_change - from_initial,
        cumulative_residual,
        cumulative_abs_residual,
        max_abs_residual,
        blocked_by,
    )
end

"""
    control_volume_available(endpoints, control_volume) -> Bool

Whether every reservoir named by `control_volume` is present in `endpoints`.

`ATMOSPHERE_AND_SURFACE` in a configuration with no slab is the case this
exists for. The atmosphere is present and owns all three quantities, so a naive
projection returns the atmosphere-only numbers under the coupled name: a view
the contract says is unavailable, reported as though it had been computed. The
totals would even look right, which is worse, because a surface exchange would
read as internal to a coupled system that does not exist.

An unavailable view is not emitted at all. It is not the same as a view that is
available and inapplicable for one quantity.
"""
control_volume_available(endpoints::BudgetEndpoints, cv::ControlVolume) = all(
    r -> any(e -> e.reservoir === r, endpoints.reservoirs),
    cv.reservoirs,
)

"""
    check_endpoint_layout(opening, closing)

Verify that the closing endpoints describe the same reservoirs, in the same
order, owning the same quantities as the opening ones.

A supported configuration has a static reservoir graph, so a reservoir that
appears, disappears, or changes what it owns part way through a step is a
defect. Checking it here means a malformed closing endpoint is refused before
[`commit_transaction!`](@ref) has advanced anything, which is what lets the
commit be atomic.
"""
function check_endpoint_layout(
    opening::BudgetEndpoints,
    closing::BudgetEndpoints,
)
    length(opening.reservoirs) == length(closing.reservoirs) || error(
        "The budget reservoir set changed within step $(closing.step), from " *
        "$(length(opening.reservoirs)) reservoirs to " *
        "$(length(closing.reservoirs)).",
    )
    for (before, after) in zip(opening.reservoirs, closing.reservoirs)
        before.reservoir === after.reservoir ||
            error("The budget reservoir order changed within a step.")
        for quantity in BUDGET_QUANTITIES
            b = budget_component(before, quantity)
            a = budget_component(after, quantity)
            typeof(b.status) === typeof(a.status) || error(
                "Budget component status for $quantity in " *
                "$(reservoir_name(after.reservoir)) changed within step " *
                "$(closing.step), from $(nameof(typeof(b.status))) to " *
                "$(nameof(typeof(a.status))).",
            )
        end
    end
    return nothing
end

"""
    commit_transaction!(ledger, closing; control_volumes)

Close the transaction and return one [`BudgetReconciliation`](@ref) per
quantity and control volume.

The closing endpoints must be for the step the transaction opened, which is the
check that catches a missed or a doubled step. Cumulative totals are updated
here and only here, so an aborted transaction contributes nothing to them.

A control volume whose reservoirs are not all present is **not emitted**. In a
configuration with no slab the coupled view would otherwise silently return the
atmosphere-only numbers under the coupled name. See
[`control_volume_available`](@ref).

The commit is **atomic**. Every reconciliation is computed into a temporary
first, and the ledger is not touched until all of them have succeeded. An
earlier version updated the cumulative dictionaries inside the loop, so an error
raised while reconciling the fifth quantity left the first four already advanced
in a transaction that was still open — a ledger that had half-counted a step it
never committed, with no way to tell from its own state.
"""
function commit_transaction!(
    ledger::BudgetLedger{FT},
    closing::BudgetEndpoints{FT};
    control_volumes = (ATMOSPHERE_ONLY, ATMOSPHERE_AND_SURFACE),
) where {FT}
    ledger.is_open || error("No open budget transaction to commit.")
    closing.step == ledger.step || error(
        "Closing endpoints are for step $(closing.step), but the open " *
        "transaction is step $(ledger.step).",
    )

    check_endpoint_layout(ledger.opening, closing)

    # Compute everything before changing anything. `reconcile` reads the
    # cumulative dictionaries but does not write them, so this loop is free of
    # side effects and may fail part way through without consequence.
    available = filter(cv -> control_volume_available(closing, cv), control_volumes)
    reconciliations = BudgetReconciliation{FT}[]
    for cv in available, quantity in BUDGET_QUANTITIES
        push!(reconciliations, reconcile(ledger, closing, quantity, cv))
    end

    # Past here nothing can fail, so the ledger may be advanced.
    for r in reconciliations
        key = (r.quantity, r.control_volume)
        ledger.cumulative_change[key] = r.cumulative_endpoint_change
        ledger.cumulative_residual[key] = r.cumulative_residual
        ledger.cumulative_abs_residual[key] = r.cumulative_abs_residual
        ledger.max_abs_residual[key] = r.max_abs_residual
    end

    ledger.is_open = false
    ledger.opening = nothing
    ledger.last_closing = closing
    ledger.committed_steps += 1
    empty!(ledger.legs)
    empty!(ledger.observations)
    empty!(ledger.recorded_keys)
    empty!(ledger.aggregate_events)
    empty!(ledger.decomposed_events)
    return reconciliations
end

"""
    transfer_mismatch(ledger, event, quantity)

The signed sum of every recorded leg of `event`, over all reservoirs.

Returns `(; total, found, blocked_by)`.

An internal transfer between two included reservoirs is expected to sum to
zero. That expectation is a testable invariant and this is how it is tested. It
is not permission to synthesize a counter-entry: a nonzero result is a finding,
and it names lagged coupling, clipping, inconsistent quadrature, or a reservoir
the model does not represent.

Returns `(; total, found, applicable, status_counts, blocked_by)`.

Four answers have to stay distinguishable, and a bare total tells them apart
from none of the others. "The legs cancel" is `found`, `applicable`, no
blockers, total zero. "There were no legs" is `found = false`. "Nobody measured
the legs" is `found` with `blocked_by` naming them. And "this quantity does not
exist for this event" — every matching component inapplicable, as water is for a
dry-model exchange — is `applicable = false`, which previously returned
`found = true` with a total of zero and no blockers, exactly like a measured
cancellation.

`status_counts` gives the tally per status, so a partially inapplicable event is
legible rather than collapsed into one flag.
"""
function transfer_mismatch(
    ledger::BudgetLedger{FT},
    event::Symbol,
    quantity::Symbol,
) where {FT}
    total = zero(FT)
    found = false
    applicable = false
    status_counts = Dict(
        :measured => 0,
        :invariant_zero => 0,
        :not_applicable => 0,
        :unknown => 0,
    )
    blocked_by = String[]
    for leg in ledger.legs
        leg.event === event || continue
        found = true
        c = budget_component(leg, quantity)
        status_counts[status_name(c.status)] += 1
        c.status isa NotApplicable || (applicable = true)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        is_contributing(c) || continue
        total += c.amount
    end
    return (; total, found, applicable, status_counts, blocked_by)
end
