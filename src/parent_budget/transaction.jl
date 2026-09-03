#####
##### Parent-budget ledger: transactions and the three reconciliations
#####
##### One transaction per accepted timestep. It opens on the finalized endpoint
##### of step `n`, collects legs, and closes on the finalized endpoint of step
##### `n+1`. Nothing is committed until it closes, so a step that never completes
##### leaves no entries behind.
#####
##### Three residuals answer three different questions and are never combined:
#####
#####   R_parent(q)         = ΔB(q) − Σ_c Q_envelope(q, c) − Σ_m Q_final_map(q, m)
#####   R_attribution(q, c) = Q_envelope(q, c) − Σ_{e ∈ c} Q(q, e)
#####   R_transfer(q, e, V) = Σ_{r ∈ V} Q(q, e, r)
#####
##### Every one of them is a subtraction or a sum of recorded amounts. No
##### function here creates a leg, so the ledger cannot close a budget it has not
##### accounted for, and nothing in this file knows what a ClimaAtmos process is
##### or how a collective is issued.

# ============================================================================
# Endpoints
# ============================================================================

"""
    ReservoirEndpoint(; reservoir, mass, water, energy)

The three authoritative integrals of one reservoir at one instant.

A component is `not_applicable` when the reservoir does not own that
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

Every reservoir's `ReservoirEndpoint` at one instant, tagged with the
accepted step it belongs to.
"""
struct BudgetEndpoints{FT}
    step::Int
    reservoirs::Vector{ReservoirEndpoint{FT}}
end

"""
    endpoint_reservoir(group) -> BudgetReservoir

The reservoir a packet group belongs to. The inverse of
`endpoint_group`.
"""
function endpoint_reservoir(group::Symbol)
    group === ATMOSPHERE_ENDPOINT_GROUP && return AtmosphereReservoir()
    group === SLAB_SURFACE_ENDPOINT_GROUP && return SlabSurfaceReservoir()
    return error("No reservoir owns the endpoint packet group $group.")
end

"""
    endpoint_component(packet, group, quantity)

One endpoint component read out of a reduced packet.

An applicable slot becomes a measured component whose evidence records that it
came from the packed collective. An inapplicable slot becomes
`not_applicable` and never a measured zero.
"""
function endpoint_component(
    packet::BudgetPacket,
    group::Symbol,
    quantity::Symbol,
)
    FT = BUDGET_ACCOUNTING_TYPE
    packet_applicable(packet, group, quantity) || return not_applicable(
        FT;
        reason = :not_owned_by_reservoir,
        source = group,
    )
    return measured(
        packet_value(packet, group, quantity);
        method = :authoritative_integral,
        source = group,
        route = :packed_global_reduction,
    )
end

"""
    budget_endpoints(packet, step)

Build the endpoints of one instant from an already reduced packet.

The core consumes a reduced fixed-layout buffer and issues no collective of its
own. Whoever produced the packet decided how many collectives the step spent,
and the contract asks for one.
"""
function budget_endpoints(packet::BudgetPacket, step::Int)
    packet.is_reduced || error(
        "Budget endpoints need a reduced packet. The values currently in it " *
        "are one rank's local shares, and reading them as global totals would " *
        "be wrong on every rank but the first.",
    )
    FT = BUDGET_ACCOUNTING_TYPE
    reservoirs = ReservoirEndpoint{FT}[]
    for group in packet_groups(packet)
        push!(
            reservoirs,
            ReservoirEndpoint{FT}(;
                reservoir = endpoint_reservoir(group),
                mass = endpoint_component(packet, group, :mass),
                water = endpoint_component(packet, group, :water),
                energy = endpoint_component(packet, group, :energy),
            ),
        )
    end
    return BudgetEndpoints{FT}(step, reservoirs)
end

"""
    budget_endpoints(Y, surface_temperature, microphysics_model, step)

Measure every reservoir's authoritative integrals from the state `Y`, with one
collective for the whole set.

The atmosphere always contributes. The slab surface contributes only for a
`SurfaceConditions.SlabOceanTemperature`, and then it carries energy, and
carries water and the mass that goes with it in a moist configuration.

`microphysics_model` is required rather than inferred. A slab carries
`Y.sfc.water` even in a dry run, where it holds a permanent zero, so presence of
the field cannot distinguish an inapplicable quantity from a measured one.

Endpoints are held in `BUDGET_ACCOUNTING_TYPE` whatever the state's
float type, and the widening happens pointwise inside the reduced expression
rather than afterwards. See `local_volume_integral`.
"""
budget_endpoints(Y, surface_temperature, microphysics_model, step::Int) =
    budget_endpoints(
        reduced_endpoint_packet(Y, surface_temperature, microphysics_model),
        step,
    )

"""
    endpoint_total(endpoints, quantity, control_volume)

Sum one quantity over the reservoirs of `control_volume`.

Returns `(; total, magnitude, applicable, blocked_by)`. A reservoir outside the
control volume is skipped entirely, so it can neither contribute nor block.

`applicable` is false when no reservoir in the view owns the quantity at all,
which is not the same as a total of zero. Water in a dry model, or anything at
all in the coupled view of a configuration with no slab, would otherwise be
reported as an ordinary closed budget at zero — a claim the ledger never made.

`magnitude` is the sum of absolute endpoint values, which the tolerance needs
and which a signed total cannot supply.

`blocked_by` names the reservoirs whose component was unknown, so a blocked
report says what would unblock it instead of only that it is blocked.
"""
function endpoint_total(
    endpoints::BudgetEndpoints{FT},
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    total = zero(FT)
    magnitude = zero(FT)
    applicable = false
    blocked_by = String[]
    for endpoint in endpoints.reservoirs
        is_inside(cv, endpoint.reservoir) || continue
        c = budget_component(endpoint, quantity)
        is_applicable(c) && (applicable = true)
        if is_contributing(c)
            total += c.amount
            magnitude += abs(c.amount)
        end
        if is_blocking(c)
            push!(blocked_by, "$(reservoir_name(endpoint.reservoir)) endpoint")
        end
    end
    return (; total, magnitude, applicable, blocked_by)
end

"""
    control_volume_available(endpoints, control_volume) -> Bool

Whether every reservoir named by `control_volume` is present in `endpoints`.

`ATMOSPHERE_AND_SURFACE` in a configuration with no slab is the case this exists
for. The atmosphere is present and owns all three quantities, so a naive
projection returns the atmosphere-only numbers under the coupled name: a view
the contract says is unavailable, reported as though it had been computed. The
totals would even look right, which is worse, because a surface exchange would
read as internal to a coupled system that does not exist.

An unavailable view is not emitted at all. That is different from a view that is
available and inapplicable for one quantity.
"""
function control_volume_available(endpoints::BudgetEndpoints, cv::ControlVolume)
    for reservoir in cv.reservoirs
        any(e -> e.reservoir === reservoir, endpoints.reservoirs) ||
            return false
    end
    return true
end

"""
    check_endpoint_layout(opening, closing)

Verify that the closing endpoints describe the same reservoirs, in the same
order, owning the same quantities as the opening ones.

A supported configuration has a static reservoir graph, so a reservoir that
appears, disappears, or changes what it owns part way through a step is a
defect. Checking it here means a malformed closing endpoint is refused before
`commit_transaction!` has advanced anything, which is part of what lets
the commit be atomic.
"""
function check_endpoint_layout(opening::BudgetEndpoints, closing::BudgetEndpoints)
    length(opening.reservoirs) == length(closing.reservoirs) || error(
        "The budget reservoir set changed within step $(closing.step), from " *
        "$(length(opening.reservoirs)) reservoirs to " *
        "$(length(closing.reservoirs)).",
    )
    for (before, after) in zip(opening.reservoirs, closing.reservoirs)
        before.reservoir === after.reservoir ||
            error("The budget reservoir order changed within a step.")
        for quantity in BUDGET_QUANTITIES
            b = component_status(budget_component(before, quantity))
            a = component_status(budget_component(after, quantity))
            typeof(b) === typeof(a) || error(
                "Budget component status for $quantity in " *
                "$(reservoir_name(after.reservoir)) changed within step " *
                "$(closing.step), from $(nameof(typeof(b))) to " *
                "$(nameof(typeof(a))).",
            )
        end
    end
    return nothing
end

# ============================================================================
# Tolerance
# ============================================================================

"""
    BudgetTolerance(; absolute, relative, scale, kappa)

The tolerance one quantity's residual is judged against.

```
τ = absolute + relative · scale + kappa · eps(FT) · (abs(Bⁿ) + abs(Bⁿ⁺¹) + Σ abs(Q))
```

  - `absolute` is a floor in the units of the quantity, kg or J.
  - `relative` is dimensionless.
  - `scale` is a positive scale for the relative term. It is **never** a signed
    total: a signed scale can pass through zero, and it hides the sign the
    ledger exists to expose.
  - `kappa` covers reduction order and rank dependence.

`kappa` has no default on purpose. It must be calibrated against measured serial
and distributed runs and recorded with the result, and a guessed value presented
as universal is not a tolerance. Until it is calibrated, a reconciliation
computed without a tolerance reports `blocked` rather than `pass`.
"""
struct BudgetTolerance{FT}
    absolute::FT
    relative::FT
    scale::FT
    kappa::FT
    function BudgetTolerance{FT}(absolute, relative, scale, kappa) where {FT}
        scale >= 0 || error(
            "BudgetTolerance scale must be non-negative. A signed total is " *
            "not a scale: it can pass through zero and it hides the sign.",
        )
        absolute >= 0 || error("BudgetTolerance absolute must be non-negative.")
        relative >= 0 || error("BudgetTolerance relative must be non-negative.")
        kappa >= 0 || error("BudgetTolerance kappa must be non-negative.")
        return new{FT}(absolute, relative, scale, kappa)
    end
end

function BudgetTolerance(; absolute, relative, scale, kappa)
    a, r, s, k = promote(absolute, relative, scale, kappa)
    return BudgetTolerance{typeof(a)}(a, r, s, k)
end

"""
    tolerance_value(tolerance, opening, closing, recorded_magnitude)

Evaluate the tolerance for one step.

The endpoint magnitudes are inside the arithmetic term deliberately. Bounding a
residual by the recorded magnitudes alone is a stricter claim than the endpoint
subtraction supports, and it fails on a step whose legs are tiny against the
background.
"""
function tolerance_value(
    tolerance::BudgetTolerance{FT},
    opening,
    closing,
    recorded_magnitude,
) where {FT}
    relative_term = tolerance.relative * tolerance.scale
    magnitudes = abs(opening) + abs(closing) + recorded_magnitude
    arithmetic_term = tolerance.kappa * eps(FT) * magnitudes
    return tolerance.absolute + relative_term + arithmetic_term
end

"""
    claim_status(applicable, blocked_by, residual, tolerance) -> Symbol

One of `:pass`, `:fail`, `:blocked` or `:not_applicable`, in that order of
precedence.

A view that owns nothing is `:not_applicable` before anything else is
considered. An unknown component blocks whatever the numbers look like. Only
then does the residual meet a tolerance.
"""
function claim_status(applicable::Bool, blocked_by, residual, tolerance)
    applicable || return :not_applicable
    isempty(blocked_by) || return :blocked
    return abs(residual) <= tolerance ? :pass : :fail
end

# The blocker a reconciliation carries when it was asked for a verdict with no
# calibrated tolerance. Written once so a report can match on it.
const UNCALIBRATED_TOLERANCE_BLOCKER = "tolerance not declared; kappa is uncalibrated"

# ============================================================================
# The ledger
# ============================================================================

"""
    BudgetLedger{FT}()

The open transaction and the running cumulative totals.

A ledger is opened on an endpoint, collects legs, and is committed on the next
endpoint.

Three cumulative residuals are kept per quantity and control volume, not one,
because a signed sum cancels the very failure the ledger exists to expose: `+δ`
on one step and `−δ` on the next sums to zero and reports a perfectly closed run
that closed on neither step. `cumulative_residual` is the signed drift.
`cumulative_abs_residual` cannot cancel and bounds the total unaccounted
transfer. `max_abs_residual` names the worst single step. Closure quality is
decided by the last two; the signed sum is reported and never passes a test on
its own.

The ledger is a diagnostic. Nothing in it writes to the state, and a run with it
enabled must produce the same trajectory as one without it.
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
    envelope_keys::Set{Tuple{Symbol, Symbol, Int}}
    event_levels::Dict{Tuple{Symbol, Int}, Symbol}
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
    Set{Tuple{Symbol, Symbol, Int}}(),
    Dict{Tuple{Symbol, Int}, Symbol}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    Dict{Tuple{Symbol, Symbol}, FT}(),
    0,
)

"""
    clear_open_transaction!(ledger)

Drop everything belonging to the open transaction.

Per-step storage is bounded because this runs on every commit and every abort. A
long run keeps the fixed set of cumulative totals and nothing that grows with
the number of steps.
"""
function clear_open_transaction!(ledger::BudgetLedger)
    empty!(ledger.legs)
    empty!(ledger.observations)
    empty!(ledger.recorded_keys)
    empty!(ledger.envelope_keys)
    empty!(ledger.event_levels)
    return nothing
end

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
        before.reservoir === after.reservoir ||
            error("The budget reservoir order changed between transactions.")
        for quantity in BUDGET_QUANTITIES
            b = budget_component(before, quantity)
            a = budget_component(after, quantity)
            typeof(component_status(b)) === typeof(component_status(a)) || error(
                "Budget endpoint status changed for $quantity in " *
                "$(reservoir_name(after.reservoir)) at step $(opening.step): " *
                "the previous transaction closed as " *
                "$(nameof(typeof(component_status(b)))) and this one opens as " *
                "$(nameof(typeof(component_status(a)))). What a reservoir owns " *
                "may not change mid-run without being represented as a " *
                "transition.",
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

The first opening endpoint is also kept as the initial one, so that `Bᴺ − B⁰`
can later be read directly rather than telescoped out of the per-step
differences.
"""
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
    clear_open_transaction!(ledger)
    return nothing
end

"""
    open_transaction!(ledger)

Open the next transaction on the endpoint the previous one closed, without
measuring the state again.

Measuring the opening endpoint repeats, identically, the reduction the previous
commit already performed, so reusing it halves the endpoint collectives per
step.

**It also gives up the only check that would catch an unrecorded change between
steps.** `check_endpoint_continuity` exists because the closing state of
step `n` and the opening state of step `n+1` are read at different moments with
discrete callbacks in between, and comparing them is what turns a callback that
quietly mutates `Y` into an error instead of a silent gap in the cumulative
total. Reuse makes that comparison compare a value with itself.

The trade is sound exactly while no callback mutates the state, which is a
property of the model established by the coverage registry rather than a
property of the ledger. It is therefore opt-in and the measured path stays the
default.

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

"""
    record_leg!(ledger, leg)

Add `leg` to the open transaction.

Refused, loudly, in five cases.

  - There is no open transaction, so the leg belongs to no accepted step.
  - The leg's `step` disagrees with the open one, which means a stage or a
    callback is writing into the wrong transaction.
  - The leg names a channel that is not one of `BUDGET_CHANNELS`. An
    unrecognized channel would take part in no attribution identity and would
    disappear from every total, so it fails closed.
  - A leg with the same `execution_identity` is already recorded, which
    is how a bracket that fires twice at the same point shows up. A correction
    that legitimately fires once per stage carries a different `stage` and is not
    a duplicate.
  - The same event is already recorded at a different `CollectionLevel`,
    or a second envelope is offered for a channel and reservoir that already has
    one.

The last one is worth stating precisely, because the contract's rule is about
sums rather than about recording. An envelope and its decomposition are
*supposed* to be recorded together: comparing them is the attribution identity.
What must never happen is both landing in one total, and that is prevented by
`enters_parent_identity` rather than by refusing the recording. What is
refused here is one event claiming to be two different kinds of thing, which is
a classification error and would make both identities wrong.

Why keep the duplicate guard, given that a duplicated nonzero leg does move the
residual and does fail closure. It localizes the fault at the second recording
rather than in a residual a whole step later. It catches a doubled leg whose
amount happens to be zero, which genuinely would pass every closure test. And it
forces each firing of a repeating path to carry a distinct execution identity,
which is what makes a per-stage correction legible at all.
"""
function record_leg!(ledger::BudgetLedger{FT}, leg::BudgetLeg{FT}) where {FT}
    ledger.is_open || error(
        "No open budget transaction; cannot record leg $(leg.event)/$(leg.leg).",
    )
    leg.step == ledger.step || error(
        "Leg $(leg.event)/$(leg.leg) is for step $(leg.step), but the open " *
        "transaction is step $(ledger.step).",
    )
    leg.channel in BUDGET_CHANNELS || error(
        "Leg $(leg_label(leg)) names channel $(leg.channel), which is not one " *
        "of $(BUDGET_CHANNELS). An unrecognized channel belongs to no " *
        "attribution identity and would vanish from every total.",
    )

    key = execution_identity(leg)
    key in ledger.recorded_keys && error(
        "Leg $(leg_label(leg)) is already recorded. A leg is recorded once; " *
        "control-volume totals are projections of it. A path that legitimately " *
        "fires more than once in a step distinguishes its firings with `stage` " *
        "and `occurrence`.",
    )

    event_key = (leg.event, leg.step)
    level = level_name(leg.level)
    recorded_level = get(ledger.event_levels, event_key, level)
    recorded_level === level || error(
        "Leg $(leg_label(leg)) records event $(leg.event) at level $level, but " *
        "it is already recorded at level $recorded_level in this step. An " *
        "event is one kind of thing: an envelope, a decomposition, a final " *
        "map, or a transfer leg.",
    )

    if leg.level isa ChannelEnvelope
        envelope_key = (leg.channel, reservoir_name(leg.reservoir), leg.step)
        envelope_key in ledger.envelope_keys && error(
            "Leg $(leg_label(leg)) is a second envelope for channel " *
            "$(leg.channel) in $(reservoir_name(leg.reservoir)) at step " *
            "$(leg.step). A channel applies one accepted update to one " *
            "reservoir, so a second envelope for it double-counts that update.",
        )
        push!(ledger.envelope_keys, envelope_key)
    end

    ledger.event_levels[event_key] = level
    push!(ledger.recorded_keys, key)
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
the accepted endpoint, and the safest way to keep it out of the identities is to
make it something `record_leg!` will not take.

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

This exists for the rejected-attempt rule, not because a supported configuration
reaches it. `args_integrator` passes a fixed `dt` and no controller, so the IMEX
integrator never rejects a step and never retries. If an adaptive controller is
added, this is the hook that keeps a rejected attempt from committing, and the
rollback of the *state* becomes real work that the contract does not currently
cover.
"""
function abort_transaction!(ledger::BudgetLedger)
    ledger.is_open = false
    ledger.opening = nothing
    clear_open_transaction!(ledger)
    return nothing
end

# ============================================================================
# Projections
# ============================================================================

"""
    project_parent(ledger, quantity, control_volume)

Sum the primary identity's recorded terms for one quantity over one control
volume.

Returns `(; envelopes, final_maps, recorded, magnitude, applicable, blocked_by)`.

Only `ChannelEnvelope` and `FinalMap` legs are summed. A
decomposition or transfer leg explains an envelope rather than adding to it, so
including it here would count the same update twice; that is where the rule
against summing an aggregate with its own decomposition is enforced.

A leg outside the control volume is skipped, which is what makes a surface
exchange a boundary crossing in one view and an internal transfer in another
without recording it twice.
"""
function project_parent(
    ledger::BudgetLedger{FT},
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    envelopes = zero(FT)
    final_maps = zero(FT)
    magnitude = zero(FT)
    applicable = false
    blocked_by = String[]
    for leg in ledger.legs
        is_inside(cv, leg.reservoir) || continue
        enters_parent_identity(leg.level) || continue
        c = budget_component(leg, quantity)
        is_applicable(c) && (applicable = true)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        is_contributing(c) || continue
        magnitude += abs(c.amount)
        if leg.level isa ChannelEnvelope
            envelopes += c.amount
        else
            final_maps += c.amount
        end
    end
    recorded = envelopes + final_maps
    return (; envelopes, final_maps, recorded, magnitude, applicable, blocked_by)
end

"""
    project_attribution(ledger, quantity, control_volume, channel)

Sum one channel's envelope and its explaining legs for one quantity over one
control volume.

Returns `(; envelope, attributed, magnitude, found, applicable, blocked_by)`.
`found` is false when the channel has no envelope in this view, which is
different from an envelope of zero.
"""
function project_attribution(
    ledger::BudgetLedger{FT},
    quantity::Symbol,
    cv::ControlVolume,
    channel::Symbol,
) where {FT}
    envelope = zero(FT)
    attributed = zero(FT)
    magnitude = zero(FT)
    found = false
    applicable = false
    blocked_by = String[]
    for leg in ledger.legs
        leg.channel === channel || continue
        is_inside(cv, leg.reservoir) || continue
        c = budget_component(leg, quantity)
        is_applicable(c) && (applicable = true)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        if leg.level isa ChannelEnvelope
            found = true
            is_contributing(c) || continue
            envelope += c.amount
            magnitude += abs(c.amount)
        elseif explains_envelope(leg.level)
            is_contributing(c) || continue
            attributed += c.amount
            magnitude += abs(c.amount)
        end
    end
    return (; envelope, attributed, magnitude, found, applicable, blocked_by)
end

"""
    event_reservoirs(ledger, event) -> Vector{BudgetReservoir}

Every reservoir the recorded legs of `event` touch, in recording order.
"""
function event_reservoirs(ledger::BudgetLedger, event::Symbol)
    reservoirs = BudgetReservoir[]
    for leg in ledger.legs
        leg.event === event || continue
        any(r -> r === leg.reservoir, reservoirs) || push!(reservoirs, leg.reservoir)
    end
    return reservoirs
end

"""
    transfer_expectation(ledger, event, control_volume) -> Symbol

`:cancellation` when every reservoir the event touches lies inside the control
volume, `:boundary_crossing` otherwise.

The same event is both, depending on the view. Precipitation reaching a slab is
internal to the coupled volume and its legs are expected to cancel; in the
atmosphere-only volume it crosses the boundary and a nonzero total is the
boundary flux, not a failure. Stating which one is expected is what stops a
report reading a boundary flux as a broken cancellation.
"""
function transfer_expectation(
    ledger::BudgetLedger,
    event::Symbol,
    cv::ControlVolume,
)
    reservoirs = event_reservoirs(ledger, event)
    all(r -> is_inside(cv, r), reservoirs) && return :cancellation
    return :boundary_crossing
end

"""
    project_transfer(ledger, event, quantity, control_volume)

Sum every recorded leg of `event` for one quantity over one control volume.

Returns `(; total, magnitude, leg_count, applicable, status_counts, blocked_by)`.

Four answers have to stay distinguishable, and a bare total tells none of them
apart. "The legs cancel" is a total of zero with legs found, applicable, and no
blockers. "There were no legs" is `leg_count == 0`. "Nobody measured the legs" is
legs found with `blocked_by` naming them. And "this quantity does not exist for
this event", as water does not for a dry-model exchange, is `applicable = false`,
which would otherwise look exactly like a measured cancellation.

`status_counts` gives the tally per status, so a partially inapplicable event is
legible rather than collapsed into one flag.
"""
function project_transfer(
    ledger::BudgetLedger{FT},
    event::Symbol,
    quantity::Symbol,
    cv::ControlVolume,
) where {FT}
    total = zero(FT)
    magnitude = zero(FT)
    leg_count = 0
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
        is_inside(cv, leg.reservoir) || continue
        leg_count += 1
        c = budget_component(leg, quantity)
        status_counts[status_name(component_status(c))] += 1
        is_applicable(c) && (applicable = true)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        is_contributing(c) || continue
        total += c.amount
        magnitude += abs(c.amount)
    end
    return (; total, magnitude, leg_count, applicable, status_counts, blocked_by)
end

# ============================================================================
# Reconciliation results
# ============================================================================

"""
    ParentReconciliation

What one quantity did over one accepted step in one control volume, and whether
the recorded accepted updates account for it.

`residual` is `endpoint_change - recorded` and nothing else. `recorded` is the
sum of the channel envelopes and the final maps, never of their decompositions.

`endpoint_change_from_initial` is read directly from the first accepted
endpoint. `cumulative_endpoint_change` telescopes the per-step differences
instead, and `telescoping_discrepancy` is what separates them. The telescoped
sum reproduces the same measurements plus the rounding of every intermediate
addition, so it can never contradict them; the direct reading shares no
arithmetic with it and can.

`status` is one of `:pass`, `:fail`, `:blocked` or `:not_applicable`. A blocked
reconciliation still reports its numbers, because they are informative, but no
closure claim may be made from it.
"""
Base.@kwdef struct ParentReconciliation{FT}
    quantity::Symbol
    control_volume::Symbol
    step::Int
    status::Symbol
    applicable::Bool
    endpoint_change::FT
    envelopes::FT
    final_maps::FT
    recorded::FT
    residual::FT
    tolerance::Union{Nothing, FT}
    cumulative_endpoint_change::FT
    endpoint_change_from_initial::FT
    telescoping_discrepancy::FT
    cumulative_residual::FT
    cumulative_abs_residual::FT
    max_abs_residual::FT
    blocked_by::Vector{String}
end

"""
    AttributionReconciliation

Whether one channel's classified events explain the whole of its accepted
envelope, for one quantity in one control volume.

`residual` is `envelope - attributed`. A channel can reconcile perfectly in the
primary identity while its attribution is entirely unexplained, which is why
this is a separate result and not a field of `ParentReconciliation`.
"""
Base.@kwdef struct AttributionReconciliation{FT}
    quantity::Symbol
    control_volume::Symbol
    channel::Symbol
    step::Int
    status::Symbol
    applicable::Bool
    envelope::FT
    attributed::FT
    residual::FT
    tolerance::Union{Nothing, FT}
    blocked_by::Vector{String}
end

"""
    TransferReconciliation

Whether the independently measured legs of one event agree, for one quantity in
one control volume.

`expectation` is `:cancellation` when the control volume holds every reservoir
the event touches, and `:boundary_crossing` otherwise. Only a cancellation is
judged against a tolerance. A boundary crossing has no cancellation to claim, so
its `status` is `:not_applicable` and its `total` is the boundary flux, which is
not expected to vanish. Reading `status` without `expectation` would make that
flux look like a budget nobody owned.

A nonzero cancellation is a finding, not permission to synthesize a
counter-entry. It names lagged coupling, clipping, inconsistent quadrature, or a
reservoir the model does not represent.
"""
Base.@kwdef struct TransferReconciliation{FT}
    quantity::Symbol
    event::Symbol
    control_volume::Symbol
    step::Int
    status::Symbol
    expectation::Symbol
    applicable::Bool
    total::FT
    leg_count::Int
    tolerance::Union{Nothing, FT}
    status_counts::Dict{Symbol, Int}
    blocked_by::Vector{String}
end

"""
    is_blocked(reconciliation) -> Bool

Whether the reconciliation's status is `:blocked`.
"""
is_blocked(r::ParentReconciliation) = r.status === :blocked
is_blocked(r::AttributionReconciliation) = r.status === :blocked
is_blocked(r::TransferReconciliation) = r.status === :blocked

"""
    BudgetCommit

The three families of reconciliation produced by one committed step, kept apart.

They answer different questions and are never added together: `parent` asks
whether accounting reproduced the accepted state transition, `attribution`
whether the classified paths explained each channel, and `transfer` whether
independently measured legs of one exchange agreed. None of the three
establishes physical completeness or provenance.
"""
Base.@kwdef struct BudgetCommit{FT}
    step::Int
    parent::Vector{ParentReconciliation{FT}}
    attribution::Vector{AttributionReconciliation{FT}}
    transfer::Vector{TransferReconciliation{FT}}
end

# ============================================================================
# Reconciliation
# ============================================================================

"""
    quantity_tolerance(tolerances, quantity)

The `BudgetTolerance` declared for `quantity`, or `nothing`.

`tolerances` is a mapping from quantity to tolerance, or `nothing` when none has
been declared. There is no default: `kappa` has to be calibrated, and a
reconciliation asked for a verdict without one reports `blocked`.
"""
quantity_tolerance(::Nothing, ::Symbol) = nothing
quantity_tolerance(tolerances, quantity::Symbol) =
    get(tolerances, quantity, nothing)

# Evaluate a tolerance if one was declared, and otherwise record why no verdict
# is available. Returning the blocker rather than a permissive default is what
# keeps an uncalibrated run from reporting `pass`.
function resolve_tolerance(tolerance, blocked_by, opening, closing, magnitude)
    isnothing(tolerance) || return (
        tolerance_value(tolerance, opening, closing, magnitude),
        blocked_by,
    )
    return (nothing, vcat(blocked_by, [UNCALIBRATED_TOLERANCE_BLOCKER]))
end

"""
    reconcile_parent(ledger, closing, quantity, control_volume; tolerances)

Compute one `ParentReconciliation` from the open transaction and the
closing endpoints. Pure; it does not mutate the ledger.
"""
function reconcile_parent(
    ledger::BudgetLedger{FT},
    closing::BudgetEndpoints{FT},
    quantity::Symbol,
    cv::ControlVolume;
    tolerances = nothing,
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

    projected = project_parent(ledger, quantity, cv)
    residual = endpoint_change - projected.recorded

    key = (quantity, cv.name)
    cumulative_change =
        get(ledger.cumulative_change, key, zero(FT)) + endpoint_change

    initial = ledger.initial
    from_initial = if isnothing(initial)
        endpoint_change
    else
        after.total - endpoint_total(initial, quantity, cv).total
    end

    applicable = before.applicable || after.applicable
    blocked_by = vcat(before.blocked_by, after.blocked_by, projected.blocked_by)
    cumulative_residual = get(ledger.cumulative_residual, key, zero(FT)) + residual
    previous_abs = get(ledger.cumulative_abs_residual, key, zero(FT))
    previous_max = get(ledger.max_abs_residual, key, zero(FT))
    tolerance, blocked_by = resolve_tolerance(
        quantity_tolerance(tolerances, quantity),
        blocked_by,
        before.total,
        after.total,
        projected.magnitude,
    )

    return ParentReconciliation{FT}(;
        quantity,
        control_volume = cv.name,
        step = ledger.step,
        status = claim_status(applicable, blocked_by, residual, tolerance),
        applicable,
        endpoint_change,
        envelopes = projected.envelopes,
        final_maps = projected.final_maps,
        recorded = projected.recorded,
        residual,
        tolerance,
        cumulative_endpoint_change = cumulative_change,
        endpoint_change_from_initial = from_initial,
        telescoping_discrepancy = cumulative_change - from_initial,
        cumulative_residual,
        cumulative_abs_residual = previous_abs + abs(residual),
        max_abs_residual = max(previous_max, abs(residual)),
        blocked_by,
    )
end

"""
    reconcile_attribution(ledger, quantity, control_volume, channel; tolerances)

Compute one `AttributionReconciliation`. Pure.
"""
function reconcile_attribution(
    ledger::BudgetLedger{FT},
    quantity::Symbol,
    cv::ControlVolume,
    channel::Symbol;
    tolerances = nothing,
) where {FT}
    projected = project_attribution(ledger, quantity, cv, channel)
    residual = projected.envelope - projected.attributed
    blocked_by = projected.blocked_by
    projected.found || push!(
        blocked_by,
        "channel $channel has no envelope in $(cv.name)",
    )
    tolerance, blocked_by = resolve_tolerance(
        quantity_tolerance(tolerances, quantity),
        blocked_by,
        projected.envelope,
        projected.attributed,
        projected.magnitude,
    )
    return AttributionReconciliation{FT}(;
        quantity,
        control_volume = cv.name,
        channel,
        step = ledger.step,
        status = claim_status(
            projected.applicable,
            blocked_by,
            residual,
            tolerance,
        ),
        applicable = projected.applicable,
        envelope = projected.envelope,
        attributed = projected.attributed,
        residual,
        tolerance,
        blocked_by,
    )
end

"""
    reconcile_transfer(ledger, event, quantity, control_volume; tolerances)

Compute one `TransferReconciliation`. Pure.

A boundary crossing gets no verdict against a tolerance, because its total is
the boundary flux rather than a residual. Its status is `:not_applicable`, with
`expectation` carrying the reason, so that nothing downstream mistakes it for a
passed cancellation or a failed one.
"""
function reconcile_transfer(
    ledger::BudgetLedger{FT},
    event::Symbol,
    quantity::Symbol,
    cv::ControlVolume;
    tolerances = nothing,
) where {FT}
    projected = project_transfer(ledger, event, quantity, cv)
    expectation = transfer_expectation(ledger, event, cv)

    if expectation === :boundary_crossing
        # There is no cancellation to claim in a view the event crosses out of,
        # so the cancellation claim is inapplicable and the total reported is
        # the boundary flux. `expectation` is what says which of the two a
        # `:not_applicable` here means.
        status = isempty(projected.blocked_by) ? :not_applicable : :blocked
        return TransferReconciliation{FT}(;
            quantity,
            event,
            control_volume = cv.name,
            step = ledger.step,
            status,
            expectation,
            applicable = projected.applicable,
            total = projected.total,
            leg_count = projected.leg_count,
            tolerance = nothing,
            status_counts = projected.status_counts,
            blocked_by = projected.blocked_by,
        )
    end

    tolerance, blocked_by = resolve_tolerance(
        quantity_tolerance(tolerances, quantity),
        projected.blocked_by,
        zero(FT),
        zero(FT),
        projected.magnitude,
    )
    return TransferReconciliation{FT}(;
        quantity,
        event,
        control_volume = cv.name,
        step = ledger.step,
        status = claim_status(
            projected.applicable,
            blocked_by,
            projected.total,
            tolerance,
        ),
        expectation,
        applicable = projected.applicable,
        total = projected.total,
        leg_count = projected.leg_count,
        tolerance,
        status_counts = projected.status_counts,
        blocked_by,
    )
end

"""
    recorded_channels(ledger) -> Vector{Symbol}

The channels the open transaction has legs for, in `BUDGET_CHANNELS`
order so the result does not depend on recording order.
"""
recorded_channels(ledger::BudgetLedger) =
    [c for c in BUDGET_CHANNELS if any(leg -> leg.channel === c, ledger.legs)]

"""
    transfer_events(ledger) -> Vector{Symbol}

The events recorded at `ReservoirTransfer` level, in recording order.
"""
function transfer_events(ledger::BudgetLedger)
    events = Symbol[]
    for leg in ledger.legs
        leg.level isa ReservoirTransfer || continue
        leg.event in events || push!(events, leg.event)
    end
    return events
end

"""
    commit_transaction!(ledger, closing; control_volumes, tolerances)

Close the transaction and return a `BudgetCommit` holding the parent,
attribution and transfer reconciliations for every quantity and available
control volume.

The closing endpoints must be for the step the transaction opened, which is the
check that catches a missed or a doubled step. Cumulative totals are updated
here and only here, so an aborted transaction contributes nothing to them.

A control volume whose reservoirs are not all present is **not emitted**. In a
configuration with no slab the coupled view would otherwise silently return the
atmosphere-only numbers under the coupled name.

The commit is **atomic**. Every reconciliation is computed into a temporary
first, and the ledger is not touched until all of them have succeeded. Updating
the cumulative totals inside the loop would leave an error raised part way
through with some quantities already advanced in a transaction that was still
open — a ledger that had half-counted a step it never committed, with no way to
tell from its own state.
"""
function commit_transaction!(
    ledger::BudgetLedger{FT},
    closing::BudgetEndpoints{FT};
    control_volumes = (ATMOSPHERE_ONLY, ATMOSPHERE_AND_SURFACE),
    tolerances = nothing,
) where {FT}
    ledger.is_open || error("No open budget transaction to commit.")
    closing.step == ledger.step || error(
        "Closing endpoints are for step $(closing.step), but the open " *
        "transaction is step $(ledger.step).",
    )

    check_endpoint_layout(ledger.opening, closing)

    # Compute everything before changing anything. The reconcile functions read
    # the cumulative dictionaries but never write them, so this section is free
    # of side effects and may fail part way through without consequence.
    available =
        filter(cv -> control_volume_available(closing, cv), control_volumes)
    channels = recorded_channels(ledger)
    events = transfer_events(ledger)

    parent = ParentReconciliation{FT}[]
    attribution = AttributionReconciliation{FT}[]
    transfer = TransferReconciliation{FT}[]
    for cv in available, quantity in BUDGET_QUANTITIES
        push!(
            parent,
            reconcile_parent(ledger, closing, quantity, cv; tolerances),
        )
        for channel in channels
            push!(
                attribution,
                reconcile_attribution(ledger, quantity, cv, channel; tolerances),
            )
        end
        for event in events
            push!(
                transfer,
                reconcile_transfer(ledger, event, quantity, cv; tolerances),
            )
        end
    end

    # Past here nothing can fail, so the ledger may be advanced.
    for r in parent
        key = (r.quantity, r.control_volume)
        ledger.cumulative_change[key] = r.cumulative_endpoint_change
        ledger.cumulative_residual[key] = r.cumulative_residual
        ledger.cumulative_abs_residual[key] = r.cumulative_abs_residual
        ledger.max_abs_residual[key] = r.max_abs_residual
    end

    commit = BudgetCommit{FT}(; step = ledger.step, parent, attribution, transfer)
    ledger.is_open = false
    ledger.opening = nothing
    ledger.last_closing = closing
    ledger.committed_steps += 1
    clear_open_transaction!(ledger)
    return commit
end
