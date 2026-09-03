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
    ReservoirEndpoint(; reservoir, mass, water, energy)

The three authoritative integrals of one reservoir at one instant.

A component is [`not_applicable`](@ref) when the reservoir does not own that
quantity, which is how "the slab holds no mass" is expressed without writing a
zero that the identity would then have to reconcile.
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
    budget_endpoints(Y, surface_temperature, step)

Measure every reservoir's authoritative integrals from the state `Y`.

The atmosphere always contributes. The slab surface contributes only when
[`surface_energy`](@ref) finds one, and then it carries energy, possibly water,
and never mass.

Each call is a handful of global reductions. It runs twice per transaction, at
the two endpoints, and never per leg.
"""
function budget_endpoints(Y, surface_temperature, step::Int)
    FT = Spaces.undertype(axes(Y.c))
    reservoirs = ReservoirEndpoint{FT}[]

    push!(
        reservoirs,
        ReservoirEndpoint{FT}(;
            reservoir = AtmosphereReservoir(),
            mass = measured(FT(atmosphere_mass(Y))),
            water = hasproperty(Y.c, :ρq_tot) ?
                    measured(FT(atmosphere_water(Y))) : not_applicable(FT),
            energy = measured(FT(atmosphere_energy(Y))),
        ),
    )

    e_sfc = surface_energy(Y, surface_temperature)
    if !isnothing(e_sfc)
        w_sfc = surface_water(Y, surface_temperature)
        m_sfc = surface_mass(Y, surface_temperature)
        push!(
            reservoirs,
            ReservoirEndpoint{FT}(;
                reservoir = SlabSurfaceReservoir(),
                # The slab's mass and water are the same amount: what it holds
                # left the atmosphere as `ρq_tot`, which `ρ` carries in full.
                # They are measured separately anyway, so a path where they
                # diverge would show rather than be defined away.
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
    last_closing::Union{Nothing, BudgetEndpoints{FT}}
    legs::Vector{BudgetLeg{FT}}
    recorded_keys::Set{Tuple{Symbol, Symbol, Int, Int, Int}}
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
    BudgetLeg{FT}[],
    Set{Tuple{Symbol, Symbol, Int, Int, Int}}(),
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
step numbers and every reservoir's contributing amount must agree exactly.
Exactly, not within a tolerance: a reduction over an unchanged state is
deterministic, so any difference is a real change that happened between the two
transactions and that nothing recorded.
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
            (is_contributing(b) && is_contributing(a)) || continue
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
    empty!(ledger.legs)
    empty!(ledger.recorded_keys)
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

The third is the one worth having. A doubled leg does not fail any closure test
that a correct ledger passes, because it changes the recorded sum and the
residual together only if the amount happens to be zero. Refusing it here is
cheaper than finding it in a residual.
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
    push!(ledger.recorded_keys, key)
    push!(ledger.legs, leg)
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
    empty!(ledger.recorded_keys)
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
        cumulative_residual,
        cumulative_abs_residual,
        max_abs_residual,
        blocked_by,
    )
end

"""
    commit_transaction!(ledger, closing; control_volumes)

Close the transaction and return one [`BudgetReconciliation`](@ref) per
quantity and control volume.

The closing endpoints must be for the step the transaction opened, which is the
check that catches a missed or a doubled step. Cumulative totals are updated
here and only here, so an aborted transaction contributes nothing to them.
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

    reconciliations = BudgetReconciliation{FT}[]
    for cv in control_volumes, quantity in BUDGET_QUANTITIES
        r = reconcile(ledger, closing, quantity, cv)
        key = (quantity, cv.name)
        ledger.cumulative_change[key] = r.cumulative_endpoint_change
        ledger.cumulative_residual[key] = r.cumulative_residual
        ledger.cumulative_abs_residual[key] = r.cumulative_abs_residual
        ledger.max_abs_residual[key] = r.max_abs_residual
        push!(reconciliations, r)
    end

    ledger.is_open = false
    ledger.opening = nothing
    ledger.last_closing = closing
    ledger.committed_steps += 1
    empty!(ledger.legs)
    empty!(ledger.recorded_keys)
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

`found` is false when `event` has no legs at all. It stays true for an event
whose legs are all unknown, and `blocked_by` then names them: "the legs cancel",
"there were no legs" and "nobody measured the legs" are three different answers
and the caller has to be able to tell them apart.
"""
function transfer_mismatch(
    ledger::BudgetLedger{FT},
    event::Symbol,
    quantity::Symbol,
) where {FT}
    total = zero(FT)
    found = false
    blocked_by = String[]
    for leg in ledger.legs
        leg.event === event || continue
        found = true
        c = budget_component(leg, quantity)
        is_blocking(c) && push!(blocked_by, leg_label(leg))
        is_contributing(c) || continue
        total += c.amount
    end
    return (; total, found, blocked_by)
end
