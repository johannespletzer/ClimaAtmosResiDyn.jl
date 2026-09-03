#####
##### Parent-budget ledger: the transactional event journal
#####
##### One journal holds the signed legs of every event in one accepted timestep.
##### A leg says what one event did to one reservoir, and it is recorded once.
##### Control-volume totals are projections of those legs, not separate entries,
##### so an internal transfer cancels because its two legs cancel and not because
##### anything was synthesized to make it.
#####
##### Three rules from `docs/src/parent_budget/contract.md` are enforced here
##### rather than documented and hoped for. Only a measured component may carry a
##### nonzero amount. A component that was not established is unknown and blocks
##### the claim it belongs to, so nothing turns silence into zero. And an event
##### is recorded at one collection level, so an envelope and its own
##### decomposition can be compared but can never land in the same sum.
#####
##### Legs are host-side scalar records built after the step's one collective, so
##### these types are written for clarity rather than for a kernel. Nothing here
##### is evaluated on the device.

# ============================================================================
# Component status and evidence
# ============================================================================

"""
    ComponentStatus

What is known about one component of a `BudgetComponent`.

  - `Measured`: the amount was taken from the implemented update.
  - `InvariantZero`: the amount is provably zero, and the proof is named.
  - `NotApplicable`: the quantity does not exist here in this
    configuration.
  - `UnknownComponent`: not established. It contributes nothing to a sum
    and *blocks* the claim for its quantity.

`UnknownComponent` exists so that an unestablished component cannot be quietly
treated as zero. That is the failure mode a budget diagnostic is most likely to
have, because a missing term and a zero term look identical in the output.
"""
abstract type ComponentStatus end

"""
    Measured()

The component was measured from the implemented update. See
`ComponentStatus`.
"""
struct Measured <: ComponentStatus end

"""
    InvariantZero()

The component is provably zero, and its evidence names the proof. See
`ComponentStatus`.
"""
struct InvariantZero <: ComponentStatus end

"""
    NotApplicable()

The quantity does not exist for this path or reservoir in this configuration.
Excluded from every total, and never a measured zero. See
`ComponentStatus`.
"""
struct NotApplicable <: ComponentStatus end

"""
    UnknownComponent()

The component has not been established, and blocks the claim it belongs to. See
`ComponentStatus`.
"""
struct UnknownComponent <: ComponentStatus end

"""
    status_name(status) -> Symbol

A short label for a `ComponentStatus`, used when a report tallies
statuses rather than naming each one.
"""
status_name(::Measured) = :measured
status_name(::InvariantZero) = :invariant_zero
status_name(::NotApplicable) = :not_applicable
status_name(::UnknownComponent) = :unknown

"""
    BudgetEvidence(; status, method, source, route)

How one component came to have the status it has.

Evidence is **per component**, never per leg. One event routinely measures
energy, proves a mass zero, and has nothing to say about water, so a single
per-leg record would misdescribe two of the three.

  - `status` is the `ComponentStatus`.
  - `method` is how the amount was obtained, or, for an `InvariantZero`,
    the proof that makes it zero.
  - `source` names the adapter or coverage-registry entry it came from.
  - `route` names the precision and reduction path, where that matters. An
    endpoint measured through the packed collective and a leg taken from an
    applied increment are different routes and a report should be able to say
    which.

This is what lets a failing budget be localized. Without it a missing leg, a
duplicated leg and a mismatched pair all look the same afterwards.
"""
Base.@kwdef struct BudgetEvidence
    status::ComponentStatus
    method::Symbol = :unspecified
    source::Symbol = :unspecified
    route::Symbol = :unspecified
end

"""
    BudgetComponent(amount, evidence)

One signed extensive amount together with the evidence for it.

Units are kg for mass and water and J for energy, always extensive and never
normalized. Positive means addition to the reservoir the leg names.

Prefer the constructors `measured`, `invariant_zero`,
`not_applicable` and `unknown_component`. Two rules are enforced
here rather than left to them.

**Only a measured component may carry a nonzero amount.**
`is_contributing` is true for `InvariantZero`, so a nonzero one would
add a real amount into a total while labelled as proven zero — a wrong number
wearing the one label that says it cannot be wrong. A nonzero `NotApplicable` or
`UnknownComponent` amount is never read, so it is dead data that misleads anyone
inspecting a leg.

**An invariant zero must name its proof.** A zero with no proof is an assumption,
and an assumed zero is exactly what the `UnknownComponent` status exists to keep
out of the totals.
"""
struct BudgetComponent{FT}
    amount::FT
    evidence::BudgetEvidence
    function BudgetComponent{FT}(amount, evidence::BudgetEvidence) where {FT}
        a = convert(FT, amount)
        status = evidence.status
        if !(status isa Measured) && !iszero(a)
            error(
                "A $(nameof(typeof(status))) component must carry exactly " *
                "zero, got $a. Only a Measured component may hold a nonzero " *
                "amount.",
            )
        end
        if status isa InvariantZero && evidence.method === :unspecified
            error(
                "An InvariantZero component must name the proof that makes it " *
                "zero. A zero with no proof is an assumption, and an assumed " *
                "zero is what UnknownComponent exists to keep out of a total.",
            )
        end
        return new{FT}(a, evidence)
    end
end

BudgetComponent(amount::FT, evidence::BudgetEvidence) where {FT} =
    BudgetComponent{FT}(amount, evidence)

"""
    component_status(component) -> ComponentStatus

The status of one `BudgetComponent`.
"""
component_status(c::BudgetComponent) = c.evidence.status

"""
    component_method(component) -> Symbol

How the amount was obtained, or the proof of an `InvariantZero`.
"""
component_method(c::BudgetComponent) = c.evidence.method

"""
    component_source(component) -> Symbol

The adapter or coverage-registry entry the amount came from.
"""
component_source(c::BudgetComponent) = c.evidence.source

"""
    component_route(component) -> Symbol

The precision and reduction path the amount travelled.
"""
component_route(c::BudgetComponent) = c.evidence.route

"""
    measured(amount; method, source = :unspecified, route = :unspecified)

A `BudgetComponent` holding a measured signed amount. `method` is
required: an amount with no account of where it came from cannot be audited.
"""
measured(
    amount::FT;
    method::Symbol,
    source::Symbol = :unspecified,
    route::Symbol = :unspecified,
) where {FT} = BudgetComponent{FT}(
    amount,
    BudgetEvidence(; status = Measured(), method, source, route),
)

"""
    invariant_zero(FT; proof, source = :unspecified)

A `BudgetComponent` that is provably zero. The amount is exactly zero,
which is what makes it safe to include in a sum, and `proof` names why.
"""
invariant_zero(
    ::Type{FT};
    proof::Symbol,
    source::Symbol = :unspecified,
) where {FT} = BudgetComponent{FT}(
    zero(FT),
    BudgetEvidence(; status = InvariantZero(), method = proof, source),
)

"""
    not_applicable(FT; reason = :not_in_configuration, source = :contract)

A `BudgetComponent` for a quantity this configuration does not own. It
contributes nothing, blocks nothing, and is not a measured zero.
"""
not_applicable(
    ::Type{FT};
    reason::Symbol = :not_in_configuration,
    source::Symbol = :contract,
) where {FT} = BudgetComponent{FT}(
    zero(FT),
    BudgetEvidence(; status = NotApplicable(), method = reason, source),
)

"""
    unknown_component(FT; reason = :not_established, source = :unspecified)

A `BudgetComponent` that has not been established. It contributes
nothing to a sum and blocks the closure claim for its quantity.
"""
unknown_component(
    ::Type{FT};
    reason::Symbol = :not_established,
    source::Symbol = :unspecified,
) where {FT} = BudgetComponent{FT}(
    zero(FT),
    BudgetEvidence(; status = UnknownComponent(), method = reason, source),
)

"""
    is_contributing(component) -> Bool

Whether the component may be added into a total.

True for `Measured` and `InvariantZero`. False for
`NotApplicable` and `UnknownComponent`, whose amounts are zero
anyway; the distinction matters because only `UnknownComponent` also blocks.
"""
is_contributing(c::BudgetComponent) =
    component_status(c) isa Measured || component_status(c) isa InvariantZero

"""
    is_blocking(component) -> Bool

Whether the component blocks the claim for its quantity. True only for
`UnknownComponent`.
"""
is_blocking(c::BudgetComponent) = component_status(c) isa UnknownComponent

"""
    is_applicable(component) -> Bool

Whether the quantity exists here at all. False only for `NotApplicable`.
"""
is_applicable(c::BudgetComponent) = !(component_status(c) isa NotApplicable)

# ============================================================================
# Reservoirs and control volumes
# ============================================================================

"""
    BudgetReservoir

A place the model owns state in, which can gain or lose a parent quantity.

The graph is small and saying so is part of the contract. The atmosphere always
exists. The slab surface exists only for a
`SurfaceConditions.SlabOceanTemperature`. Everything else is exterior: its state
is not owned by the model, so a flux into it is a boundary crossing and never an
internal transfer.
"""
abstract type BudgetReservoir end

"""
    AtmosphereReservoir()

The atmospheric column state, `Y.c` and `Y.f`. See `BudgetReservoir`.
"""
struct AtmosphereReservoir <: BudgetReservoir end

"""
    SlabSurfaceReservoir()

The slab surface state, `Y.sfc`. Owns energy, and in a moist configuration water
and the mass that goes with it. See `BudgetReservoir`.
"""
struct SlabSurfaceReservoir <: BudgetReservoir end

"""
    ExteriorReservoir()

Everything outside the model, including a prescribed surface. It has no
endpoint, because the model does not own its state. See
`BudgetReservoir`.
"""
struct ExteriorReservoir <: BudgetReservoir end

"""
    reservoir_name(reservoir) -> Symbol

A short label for `reservoir`.

The atmosphere and slab labels are the same symbols the endpoint packet uses as
group names, which is what ties a reservoir to its slots. See
`ATMOSPHERE_ENDPOINT_GROUP`.
"""
reservoir_name(::AtmosphereReservoir) = ATMOSPHERE_ENDPOINT_GROUP
reservoir_name(::SlabSurfaceReservoir) = SLAB_SURFACE_ENDPOINT_GROUP
reservoir_name(::ExteriorReservoir) = :exterior

"""
    endpoint_group(reservoir) -> Symbol

The packet group holding `reservoir`'s endpoint slots.

Errors for `ExteriorReservoir`, which has no endpoint at all. Asking for
one is a category error rather than a missing value, so it is refused rather
than returned as `nothing`.
"""
endpoint_group(r::Union{AtmosphereReservoir, SlabSurfaceReservoir}) =
    reservoir_name(r)
endpoint_group(::ExteriorReservoir) = error(
    "The exterior has no endpoint. Its state is not owned by the model, so a " *
    "flux into it is a boundary crossing and there is nothing to measure.",
)

"""
    ControlVolume(name, reservoirs)

A named set of reservoirs to project the journal onto.

The two supported views are `ATMOSPHERE_ONLY` and
`ATMOSPHERE_AND_SURFACE`. A leg counts toward a view when its reservoir
is inside it, so a surface exchange is a boundary crossing in the first view and
an internal transfer in the second, from the same recorded legs.
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

The atmosphere together with the slab surface. A surface exchange is internal
and its legs are expected to cancel. The expectation is tested, never imposed.
"""
const ATMOSPHERE_AND_SURFACE = ControlVolume(
    :atmosphere_and_surface,
    (AtmosphereReservoir(), SlabSurfaceReservoir()),
)

"""
    is_inside(control_volume, reservoir) -> Bool

Whether `reservoir` is one of the reservoirs `control_volume` contains.
"""
is_inside(cv::ControlVolume, reservoir::BudgetReservoir) =
    any(r -> r === reservoir, cv.reservoirs)

# ============================================================================
# Channels, update paths and collection levels
# ============================================================================

"""
    BUDGET_CHANNELS

The update channels the primary identity reconciles against.

`remaining_tendency!` writes two explicit channels, not one: `Yₜ` and the
*limited* `Yₜ_lim`, which `ClimaTimeSteppers` integrates through the limiter.
Horizontal tracer advection and tracer hyperdiffusion live only in the limited
one, so an adapter reading `Yₜ` alone loses them silently. `:finalization`
carries the accepted-state maps, which are not a tendency channel but do enter
the identity in their own right.
"""
const BUDGET_CHANNELS =
    (:explicit_main, :explicit_limited, :implicit, :post_implicit, :finalization)

"""
    UpdatePath

What kind of update a leg records. This classifies the *nature* of a
contribution; `CollectionLevel` says which identity it belongs to.
"""
abstract type UpdatePath end

"""
    EquationTerm()

Accepted integration of an explicit or implicit equation term.
"""
struct EquationTerm <: UpdatePath end

"""
    DiscreteMap()

An accepted sequential, split, coupling, callback, or post-solve map.
"""
struct DiscreteMap <: UpdatePath end

"""
    NumericalCorrection()

A limiter, clipping, projection, or consistency repair. These are numerical
corrections and are never reported as physical tendencies.
"""
struct NumericalCorrection <: UpdatePath end

"""
    AlgebraicSolveDefect()

An independently derived projection of an incomplete algebraic solve.

Not a small term in ClimaAtmos. The default `NewtonsMethod(max_iters = 1)`
against an approximate Jacobian does not converge the implicit stage, so the
defect is leading order and an implicit channel's attribution cannot close
without it.
"""
struct AlgebraicSolveDefect <: UpdatePath end

"""
    CollectionLevel

Which of the three nested identities a leg takes part in.

  - `ChannelEnvelope` and `FinalMap` are the terms of the
    **primary** identity.
  - `ProcessDecomposition` and `ReservoirTransfer` explain an
    envelope rather than adding to it, so they are the terms of the
    **attribution** identity.
  - `ReservoirTransfer` additionally takes part in the **transfer**
    identity.

This is how the contract's rule that an aggregate is never summed alongside its
own decomposition is enforced. The two are deliberately recorded together, since
comparing them is the whole point of attribution, and it is the *sums* that are
kept apart: `enters_parent_identity` admits only envelopes and final
maps, and no other total mixes the levels.
"""
abstract type CollectionLevel end

"""
    ChannelEnvelope()

The complete update one channel applied to one reservoir, taken from the applied
increment. A term of the primary identity, and the reference its decomposition
is reconciled against. See `CollectionLevel`.
"""
struct ChannelEnvelope <: CollectionLevel end

"""
    ProcessDecomposition()

One classified process's share of a channel. Explains an envelope; never added
to one. See `CollectionLevel`.
"""
struct ProcessDecomposition <: CollectionLevel end

"""
    FinalMap()

A map applied to the accepted state itself, contributing its raw before/after
difference. A term of the primary identity. See `CollectionLevel`.
"""
struct FinalMap <: CollectionLevel end

"""
    ReservoirTransfer()

One reservoir's leg of an exchange. Explains a channel like a decomposition, and
additionally takes part in the transfer identity. See `CollectionLevel`.
"""
struct ReservoirTransfer <: CollectionLevel end

"""
    level_name(level) -> Symbol

A short label for a `CollectionLevel`.
"""
level_name(::ChannelEnvelope) = :envelope
level_name(::ProcessDecomposition) = :decomposition
level_name(::FinalMap) = :final_map
level_name(::ReservoirTransfer) = :transfer

"""
    enters_parent_identity(level) -> Bool

Whether a leg at this level is one of the primary identity's recorded terms.

True for `ChannelEnvelope` and `FinalMap`. False for the two
levels that explain an envelope instead of adding to it, which is what makes it
impossible to sum an aggregate alongside its own decomposition.
"""
enters_parent_identity(::ChannelEnvelope) = true
enters_parent_identity(::FinalMap) = true
enters_parent_identity(::ProcessDecomposition) = false
enters_parent_identity(::ReservoirTransfer) = false

"""
    explains_envelope(level) -> Bool

Whether a leg at this level is one of the attribution identity's terms. The
complement of `enters_parent_identity`.
"""
explains_envelope(level::CollectionLevel) = !enters_parent_identity(level)

# ============================================================================
# Legs
# ============================================================================

"""
    BudgetLeg(; event, leg, reservoir, channel, level, mass, water, energy,
              path, process, phase, step, stage, occurrence, weight,
              measured_at)

One signed contribution to one reservoir, recorded once.

`event` is the stable identifier the coverage registry uses, and is shared by
every leg of one exchange, so the atmospheric and surface halves of a surface
flux carry the same `event` and different `leg`.

`channel` is one of `BUDGET_CHANNELS` and `level` is a
`CollectionLevel`. Together they place the leg in exactly one of the
three identities.

# Execution identity

`(event, leg, step, stage, occurrence)` is what the journal refuses to record
twice, and the last two are why it is not just `(event, leg, step)`. A
correction can fire several times within one accepted step:
`update_constrain_state_every` accepts `"stage"` and `"dss"`, and at `"stage"`
the same `constrain_state!` correction fires once per ARS343 stage. Each firing
is its own leg, so without a stage index the four would collide and three would
be refused as duplicates. `occurrence` covers a path that fires more than once
within a single stage.

`stage` is zero for anything that happens once per accepted step, and
`occurrence` counts from one.

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
number looks, and a raw stage difference belongs in a `StageObservation`.

`weight` records the accepted-step coefficient already applied to reach the
contribution — `1` for a whole-step map, otherwise a tableau coefficient
generally involving `bᵢ` and the implicit `γᵢ`. `measured_at` records where the
amount was taken. Both exist so a weighting can be audited instead of trusted.
"""
Base.@kwdef struct BudgetLeg{FT}
    event::Symbol
    leg::Symbol
    reservoir::BudgetReservoir
    channel::Symbol
    level::CollectionLevel
    mass::BudgetComponent{FT}
    water::BudgetComponent{FT}
    energy::BudgetComponent{FT}
    path::UpdatePath
    process::Symbol
    phase::Symbol
    step::Int
    stage::Int = 0
    occurrence::Int = 1
    weight::FT = one(FT)
    measured_at::Symbol = :accepted_state
end

"""
    StageObservation(; event, observation, reservoir, mass, water, energy,
                     process, step, stage, occurrence)

A raw before/after difference taken on an intermediate stage array.

Deliberately **not** a `BudgetLeg`, and sharing no supertype with one.
An intermediate-stage change is not an additive contribution to the accepted
endpoint, so it has no place in any of the three identities, and the cheapest way
to guarantee that is to make it a type `record_leg!` will not accept and
no projection iterates.

It is still worth collecting. When a residual appears, knowing which stage and
which map moved the state is what turns "the step does not close" into a located
defect. It is evidence, not accounting.

There is no `channel`, `level`, `path` or `weight` field, because each of those
places a contribution inside an identity and an observation is not in one.
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
end

"""
    execution_identity(leg) -> Tuple

The tuple the journal deduplicates on: event, leg, step, stage, occurrence.

Deterministic, and stable across runs, so a leg can be named in a report and
found again.
"""
execution_identity(leg::BudgetLeg) =
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
    budget_component(record, quantity) -> BudgetComponent

The `quantity` component of a leg or observation, where `quantity` is `:mass`,
`:water`, or `:energy`.
"""
function budget_component(
    record::Union{BudgetLeg, StageObservation},
    quantity::Symbol,
)
    quantity === :mass && return record.mass
    quantity === :water && return record.water
    quantity === :energy && return record.energy
    error("Unknown budget quantity $quantity; expected :mass, :water or :energy")
end
