#####
##### Parent-budget ledger: the transactional event journal
#####
##### One journal holds the signed legs of every event in one accepted
##### timestep. A leg says what one process did to one reservoir, and it is
##### recorded once. Control-volume totals are projections of those legs, not
##### separate entries, so an internal transfer cancels because its two legs
##### cancel and not because anything was synthesized to make it.
#####
##### The contract these types serve is in `docs/src/parent_budget/contract.md`.
##### Three rules from it are enforced here rather than documented and hoped
##### for. A residual is defined only by subtraction, so nothing in this file
##### can create a balancing entry. A component that was not measured is
##### `UnknownComponent` and blocks the claim it belongs to, so nothing here
##### turns silence into zero. And a leg is refused if one with the same event,
##### leg and step is already recorded, so a bracket that fires twice is an
##### error and not a doubled amount.
#####
##### Legs are host-side scalar records. A few dozen per timestep are created,
##### each after a global reduction that costs far more than they do, so these
##### types are written for clarity rather than for a kernel. Nothing here is
##### evaluated on the device.

# ============================================================================
# Component status
# ============================================================================

"""
    ComponentStatus

What is known about one `(ΔM, ΔW, ΔE)` component of a [`BudgetLeg`](@ref).

Every component carries one of four statuses, and the difference between them
is the whole point of the ledger.

  - [`Measured`](@ref): the amount was taken from the implemented update.
  - [`InvariantZero`](@ref): the amount is provably zero, and the evidence is
    named in the leg's `method`.
  - [`NotApplicable`](@ref): the path does not exist in this configuration.
  - [`UnknownComponent`](@ref): not yet established. It contributes nothing to
    a sum and *blocks* the closure claim for its quantity.

`UnknownComponent` exists so that an unmeasured component cannot be quietly
treated as zero. That is the failure mode a budget diagnostic is most likely to
have, because a missing term and a zero term look identical in the output.
"""
abstract type ComponentStatus end

"""
    Measured()

The component was measured from the implemented update. See
[`ComponentStatus`](@ref).
"""
struct Measured <: ComponentStatus end

"""
    InvariantZero()

The component is provably zero. See [`ComponentStatus`](@ref).
"""
struct InvariantZero <: ComponentStatus end

"""
    NotApplicable()

The path does not exist in this configuration. See [`ComponentStatus`](@ref).
"""
struct NotApplicable <: ComponentStatus end

"""
    UnknownComponent()

The component has not been established. See [`ComponentStatus`](@ref).
"""
struct UnknownComponent <: ComponentStatus end

"""
    BudgetComponent(amount, status)

One signed extensive amount together with what is known about it.

Units are `kg` for mass and water and `J` for energy, always extensive and
never normalized. Positive means addition to the reservoir the leg names.

Prefer the constructors [`measured`](@ref), [`invariant_zero`](@ref),
[`not_applicable`](@ref), and [`unknown_component`](@ref). Constructing one
directly is allowed, and the rule that only a `Measured` component may carry a
nonzero amount is enforced here rather than left to those helpers.

That enforcement is not decoration. [`is_contributing`](@ref) is true for
`InvariantZero`, so `BudgetComponent{FT}(1.0, InvariantZero())` would add a real
amount into a control-volume total while labelled as proven zero — a wrong
number wearing the one label that says it cannot be wrong. `NotApplicable` and
`UnknownComponent` amounts are never read, so a nonzero one is dead data that
misleads anyone inspecting a leg.
"""
struct BudgetComponent{FT}
    amount::FT
    status::ComponentStatus
    function BudgetComponent{FT}(amount, status::ComponentStatus) where {FT}
        a = convert(FT, amount)
        status isa Measured ||
            iszero(a) ||
            error(
                "A $(nameof(typeof(status))) component must carry exactly \
                 zero, got $a. Only a Measured component may hold a nonzero \
                 amount.",
            )
        return new{FT}(a, status)
    end
end

BudgetComponent(amount::FT, status::ComponentStatus) where {FT} =
    BudgetComponent{FT}(amount, status)

"""
    measured(amount)

A [`BudgetComponent`](@ref) holding a measured signed amount.
"""
measured(amount::FT) where {FT} = BudgetComponent{FT}(amount, Measured())

"""
    invariant_zero(FT)

A [`BudgetComponent`](@ref) that is provably zero. The amount is exactly zero,
which is what makes it safe to include in a sum.
"""
invariant_zero(::Type{FT}) where {FT} =
    BudgetComponent{FT}(zero(FT), InvariantZero())

"""
    not_applicable(FT)

A [`BudgetComponent`](@ref) for a path that does not exist in this
configuration. It contributes nothing and blocks nothing.
"""
not_applicable(::Type{FT}) where {FT} =
    BudgetComponent{FT}(zero(FT), NotApplicable())

"""
    unknown_component(FT)

A [`BudgetComponent`](@ref) that has not been established. It contributes
nothing to a sum and blocks the closure claim for its quantity.
"""
unknown_component(::Type{FT}) where {FT} =
    BudgetComponent{FT}(zero(FT), UnknownComponent())

"""
    is_contributing(c) -> Bool

Whether the [`BudgetComponent`](@ref) `c` may be added into a control-volume
total.

True for [`Measured`](@ref) and [`InvariantZero`](@ref). False for
[`NotApplicable`](@ref) and [`UnknownComponent`](@ref), whose amounts are zero
anyway; the distinction matters because only `UnknownComponent` also blocks.
"""
is_contributing(c::BudgetComponent) =
    c.status isa Measured || c.status isa InvariantZero

"""
    is_blocking(c) -> Bool

Whether the [`BudgetComponent`](@ref) `c` blocks the closure claim for its
quantity. True only for [`UnknownComponent`](@ref).
"""
is_blocking(c::BudgetComponent) = c.status isa UnknownComponent

# ============================================================================
# Reservoirs and control volumes
# ============================================================================

"""
    BudgetReservoir

A place the ledger can add to or take from.

The graph is small and saying so is part of the contract. The atmosphere always
exists. The slab surface exists only for a
`SurfaceConditions.SlabOceanTemperature`, and it owns energy, water, and mass;
its mass and water legs are equal because what it gains left the atmosphere as
`ρq_tot`, which `ρ` carries in full. Everything else is exterior: its state is
not owned by the model, so a flux into it is a boundary crossing and never an
internal transfer.
"""
abstract type BudgetReservoir end

"""
    AtmosphereReservoir()

The atmospheric column state, `Y.c` and `Y.f`. See [`BudgetReservoir`](@ref).
"""
struct AtmosphereReservoir <: BudgetReservoir end

"""
    SlabSurfaceReservoir()

The slab surface state, `Y.sfc`. Owns energy, water, and mass. See
[`BudgetReservoir`](@ref).
"""
struct SlabSurfaceReservoir <: BudgetReservoir end

"""
    ExteriorReservoir()

Everything outside the model, including a prescribed surface. See
[`BudgetReservoir`](@ref).
"""
struct ExteriorReservoir <: BudgetReservoir end

"""
    ControlVolume(name, reservoirs)

A named set of reservoirs to project the journal onto.

The two supported views are [`ATMOSPHERE_ONLY`](@ref) and
[`ATMOSPHERE_AND_SURFACE`](@ref). A leg counts toward a view when its reservoir
is inside it, so a surface exchange is a boundary crossing in the first view
and an internal transfer in the second, from the same recorded legs.
"""
struct ControlVolume{N}
    name::Symbol
    reservoirs::NTuple{N, BudgetReservoir}
end

"""
    ATMOSPHERE_ONLY

The atmosphere alone. Every surface exchange is a boundary crossing.
"""
const ATMOSPHERE_ONLY = ControlVolume(:atmosphere_only, (AtmosphereReservoir(),))

"""
    ATMOSPHERE_AND_SURFACE

The atmosphere together with the slab surface. A surface exchange is internal,
and its two legs are expected to cancel. The expectation is tested, never
imposed.
"""
const ATMOSPHERE_AND_SURFACE = ControlVolume(
    :atmosphere_and_surface,
    (AtmosphereReservoir(), SlabSurfaceReservoir()),
)

"""
    reservoir_name(reservoir) -> Symbol

A short label for `reservoir`, used when a report has to name which reservoir
blocked a claim.
"""
reservoir_name(::AtmosphereReservoir) = :atmosphere
reservoir_name(::SlabSurfaceReservoir) = :slab_surface
reservoir_name(::ExteriorReservoir) = :exterior

"""
    is_inside(control_volume, reservoir) -> Bool

Whether `reservoir` is one of the reservoirs `control_volume` contains.
"""
is_inside(cv::ControlVolume, reservoir::BudgetReservoir) =
    any(r -> r === reservoir, cv.reservoirs)

# ============================================================================
# Update paths
# ============================================================================

"""
    UpdatePath

Which term of the accounting identity a leg belongs to.

```
ΔB_actual = ΣQ_equation + ΣQ_map + ΣQ_correction + ΣQ_solve_defect + R_bookkeeping
```

The four subtypes are the four `Q` terms. The residual is not one of them: it
is defined by subtraction in [`reconcile`](@ref) and has no leg, because a
residual with a leg is a fixer.
"""
abstract type UpdatePath end

"""
    EquationTerm()

`Q_equation`: accepted integration of an explicit or implicit equation term.
"""
struct EquationTerm <: UpdatePath end

"""
    DiscreteMap()

`Q_map`: an accepted sequential, split, coupling, callback, or post-solve map.
"""
struct DiscreteMap <: UpdatePath end

"""
    NumericalCorrection()

`Q_correction`: a limiter, clipping, projection, or consistency repair. These
are numerical corrections and are never reported as physical tendencies.
"""
struct NumericalCorrection <: UpdatePath end

"""
    AlgebraicSolveDefect()

`Q_solve_defect`: an independently derived projection of an incomplete
algebraic solve.

This is not a small term in ClimaAtmos. The default
`NewtonsMethod(max_iters = 1)` against an approximate Jacobian does not
converge the implicit stage, so the defect is leading order and the identity
cannot close without it. See the tolerance model in the contract.
"""
struct AlgebraicSolveDefect <: UpdatePath end

# ============================================================================
# Legs
# ============================================================================

"""
    BudgetLeg(; event, leg, reservoir, mass, water, energy, path, process, phase, step, method)

One signed contribution to one reservoir, recorded once.

`event` is shared by every leg of one physical exchange, so the atmospheric and
surface halves of a surface flux carry the same `event` and different `leg`.

`(event, leg, step, stage, occurrence)` is the identity the journal refuses to
record twice, and the last two are why it is not just `(event, leg, step)`. A
correction can fire several times within one accepted step:
`update_constrain_state_every` accepts `"stage"` and `"dss"`, and at `"stage"`
the same `constrain_state!` correction fires once per ARS343 stage. Each firing
is its own leg, so without a stage index the four would collide and three of
them would be refused as duplicates. `occurrence` covers a path that fires more
than once within a single stage.

`stage` is zero for anything that happens once per accepted step rather than per
stage, and `occurrence` counts from one.

`process` names the physics, `phase` names where in the step it happened, and
`method` names how the amount was obtained or, for an [`InvariantZero`](@ref)
component, what makes it zero.

# What the amounts mean

A leg's components are **accepted-step-weighted extensive contributions**: the
part of `Bⁿ⁺¹ - Bⁿ` this path is responsible for. They are not raw tendencies,
and they are not raw before/after differences taken on an intermediate stage
array. Those three are different numbers and must never be added together.

The distinction bites because `lim!`, `dss!` and `constrain_state!` run on
intermediate stage arrays as well as on the accepted state. A map applied to the
accepted state contributes its raw change, because that change *is* part of the
endpoint difference. A map applied to an intermediate stage does not: it changes
the array a later tendency evaluation reads, so the tableau mediates its effect
on the endpoint. Booking its raw difference here is wrong however plausible the
number looks.

`weight` records the accepted-step coefficient already applied to reach that
contribution — `1` for a whole-step map, and otherwise a tableau coefficient,
generally involving `bᵢ` and the implicit `γᵢ`. `measured_at` records where the
amount was taken. Both exist so that a weighting can be audited instead of
trusted.

A raw stage difference belongs in a `StageObservation`, which is a separate type
precisely so that it cannot be passed to [`record_leg!`](@ref) or reach a
projection.

`aggregate` marks a leg that carries a whole accepted update rather than one
path's share of it — the IMEX accepted increment, for instance. An aggregate is
the reconciliation envelope and may stand in for attribution that does not exist
yet, but it must never be summed alongside its own decomposition. The journal
refuses that combination rather than trusting the caller to avoid it.
"""
Base.@kwdef struct BudgetLeg{FT}
    event::Symbol
    leg::Symbol
    reservoir::BudgetReservoir
    mass::BudgetComponent{FT}
    water::BudgetComponent{FT}
    energy::BudgetComponent{FT}
    path::UpdatePath
    process::Symbol
    phase::Symbol
    step::Int
    stage::Int = 0
    occurrence::Int = 1
    method::Symbol
    weight::FT = one(FT)
    measured_at::Symbol = :accepted_state
    aggregate::Bool = false
end

"""
    StageObservation(; event, observation, reservoir, mass, water, energy,
                     process, step, stage, occurrence, method)

A raw before/after difference taken on an intermediate stage array.

This is deliberately **not** a [`BudgetLeg`](@ref) and shares no supertype with
one. An intermediate-stage change is not an additive contribution to the
accepted endpoint, so it has no place in the accounting identity, and the
cheapest way to guarantee that is to make it a different type that
[`record_leg!`](@ref) will not accept and no projection iterates.

It is still worth collecting. When a residual appears, knowing which stage and
which map moved the state is what turns "the step does not close" into a
located defect. It is evidence, not accounting.

There is no `path` field, because `UpdatePath` names a term of the identity and
an observation is not one. There is no `weight`, because nothing has been
weighted.
"""
Base.@kwdef struct StageObservation{FT}
    event::Symbol
    observation::Symbol
    reservoir::BudgetReservoir
    mass::BudgetComponent{FT}
    water::BudgetComponent{FT}
    energy::BudgetComponent{FT}
    process::Symbol
    step::Int
    stage::Int
    occurrence::Int = 1
    method::Symbol
end

"""
    leg_identity(leg) -> Tuple

The tuple the journal deduplicates on: event, leg, step, stage, occurrence.
"""
leg_identity(leg::BudgetLeg) =
    (leg.event, leg.leg, leg.step, leg.stage, leg.occurrence)

"""
    leg_label(leg) -> String

A human-readable identity for `leg`, used when a report has to name which legs
blocked a claim.
"""
leg_label(
    leg::BudgetLeg,
) = "$(leg.event)/$(leg.leg)@step $(leg.step) stage $(leg.stage) #$(leg.occurrence)"

"""
    budget_component(leg, quantity) -> BudgetComponent

The `quantity` component of `leg`, where `quantity` is `:mass`, `:water`, or
`:energy`.
"""
function budget_component(leg::Union{BudgetLeg, StageObservation}, quantity::Symbol)
    quantity === :mass && return leg.mass
    quantity === :water && return leg.water
    quantity === :energy && return leg.energy
    error("Unknown budget quantity $quantity; expected :mass, :water or :energy")
end

"""
    BUDGET_QUANTITIES

The three quantities the ledger tracks, each with its own definition,
invariants, residual, and tolerance. They share a journal so that coupled
exchanges stay coordinated. They are never interchangeable.
"""
const BUDGET_QUANTITIES = (:mass, :water, :energy)
