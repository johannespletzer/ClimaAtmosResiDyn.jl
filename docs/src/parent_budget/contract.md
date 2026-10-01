# Parent Budget: Closure Contract

The parent budget is an opt-in conservation audit. It checks whether air mass
`M`, total water `W` and total energy `E` changed over each accepted time step by
what the accepted step applied, within a declared tolerance. It is off by default.
Set `parent_budget_mode` to `summary` or `audit` to switch it on. It writes
`parent_budget_report.yaml` and changes no model field. With it on, every model
field that exists without it stays bit for bit as in the same run with it off,
under the default solver settings. Only its own fields and output are added. The
[fork parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
gives the limits.

This page owns the rules: quantities, identities, supported configurations,
statuses and tolerance. The [vocabulary](vocabulary.md) explains the terms. The
[architecture](architecture.md) owns the data flow and the code map. The
[coverage registry](coverage.md) owns the list of paths and their dispositions.
The [implementation plan](plan.md) is a development record and not a rule.

The contract does not by itself establish that any quantity closes in a running
simulation. The report says what was established for one run.

## Claim levels

Six claims are kept apart. A report never presents a lower level as evidence for a
higher one.

 1. **Accepted-state reconciliation.** The endpoint change of each quantity over an
    accepted step agrees, within tolerance, with the accepted channel envelopes
    and the final maps.
 2. **Implemented-update accounting.** The amounts are what the discrete integrator
    applied, including its stage weights and the algebraic defect of an
    unconverged solve.
 3. **Process attribution.** The process contributions reproduce their channel's
    envelope.
 4. **Transfer consistency.** Independently measured legs of a modeled internal
    exchange cancel within tolerance.
 5. **Physical completeness.** The model equations contain every reservoir,
    carrier, work term and exchange the physics intends.
 6. **Provenance attribution.** Material or energy can be assigned to an origin.

The parent budget targets levels 1 to 4. Level 5 is tracked in the
[limitations register](#Limitations-register) and is never a numerical residual,
because incomplete equations close against themselves. Level 6 belongs to the
source tags. Closure is discrete and within a declared tolerance. The parent budget
does not claim exact closure.

## The three identities

Three residuals answer three questions. They are computed and reported separately
and never added together.

**Primary reconciliation.** For each parent quantity `q`, control volume and
accepted step:

```
R_parent(q) = ΔB(q) − Σ_c Q_envelope(q, c) − Σ_m Q_final_map(q, m)
```

`ΔB(q)` is the endpoint change over the step. `c` runs over the integrator's
channels and `m` over the final accepted-state maps. The envelope must come from
the update the integrator applied: the increment the channel contributed, read
from stage coefficients and applied increments. Rebuilding it by subtracting
endpoints would make `R_parent = 0` by construction.

**Process attribution.** For each quantity and channel:

```
R_attribution(q, c) = Q_envelope(q, c) − Σ_{e ∈ c} Q(q, e)
```

`e` runs over the processes assigned to the channel. A channel can reconcile at
level 1 while its attribution is unexplained, so the two residuals stay separate.

**Transfer consistency.** The schema declares an event's topology. It is never
inferred from the legs that happened to be recorded.

  - An internal or coupled transfer has only modeled participants. Every declared
    leg is required, and their signed sum over a control volume containing all of
    them is tested for cancellation:
    `R_transfer(q, e) = Σ_{r ∈ modeled(e)} Q(q, e, r)`. A nonzero result is a
    finding. A declared leg that was not recorded blocks the event and is never
    read as zero.
  - An exterior crossing has one modeled side and an unmodeled exterior: the top of
    the atmosphere, a prescribed forcing, the destination of 0-moment removal, or
    an externally imposed surface flux. The modeled leg is measured and required.
    The counterparty is named as metadata. No numerical counter-leg is created,
    because a synthesized one guarantees cancellation. The cancellation test does
    not apply, and the report says so. The signed crossing is reported as a
    boundary source or sink and contributes to the channel and the parent
    reconciliation that carry it.
  - One event can be internal in one control volume and a crossing out of another.
    Precipitation reaching a slab is internal to the coupled volume and leaves the
    atmosphere-only volume. The topology is declared per view.

**Final maps are not attribution channels.** An accepted channel is a term of the
primary identity and an attribution target. A final accepted-state map, such as a
limiter, a DSS correction, a consistency repair or a constraint, is a term of the
primary identity only. It contributes its raw before/after difference to `ΔB` and
has no envelope, decomposition or attribution residual. An operation becomes a
channel only when the schema declares it an accepted integrator channel.

**Aggregates are envelopes, never extra legs.** The whole increment one channel
applied is never summed beside its own decomposition, because that counts the same
update twice. The two are recorded together, and comparing them is the attribution
identity.

None of the three establishes physical completeness or provenance. A model that
omits a reservoir closes all three.

## Declared expectations

A schema derived from the selected model configuration declares what the parent
budget expects before collection begins. The recorded data are checked against it
and never define which channels, events or reservoirs were expected. The schema
is the executable form of the [coverage registry](coverage.md). It declares the
enabled quantities, the control volumes, the accepted channels and final maps, the
transfer events with their topology, reservoirs, counterparties and required legs,
the applicability of each quantity in each reservoir, which components carry a
proven-zero obligation, whether a channel envelope is required, and the roster of
process rows each channel's decomposition must record. Three rules follow.

  - **A missing expectation is visible.** An expected channel, event or roster row
    that recorded nothing produces a `blocked` or `fail` result that names it.
  - **An unexpected entry is refused.** A channel, event or reservoir the schema
    does not declare is an error. So is a second entry under one execution
    identity: reservoir, channel, event, leg, step, stage and occurrence.
  - **Applicability is declared, never sniffed.** The configuration decides whether
    a reservoir owns a quantity, and the existence of a field does not.
    `Y.sfc.water` exists in a dry run and holds a permanent zero.

## Supported scope

The parent quantities `M`, `W` and `E` each have their own definition,
applicability, collection path, residual, tolerance and result. They share a
journal. A component of one is never inferred from another.

**Configurations supported.** Concrete types, not families.

  - Microphysics: `DryModel`, `EquilibriumMicrophysics0M` and
    `NonEquilibriumMicrophysics1M`, on the sphere and in a single column.
  - `diff_mode` and `microphysics_tendency_timestepping`, each explicit or
    implicit.
  - Surface: every prescribed or diagnosed surface temperature, and
    `SurfaceConditions.SlabOceanTemperature`.
  - Radiation: off, `HeldSuarezForcing`, RRTMGP, the DYCOMS and ISDAC radiation
    modes and the prescribed `RadiationTRMM_LBA` heating.
  - Forcing: `LargeScaleSubsidence`, large-scale advection and the external forcing
    that reaches `apply_Tq_forcing!`. The dry-air budget of a forced run is open.
  - Callbacks: the default set, which the coverage registry lists as read-only with
    respect to `Y`.

**Configurations refused at setup.** The error names the reason.

  - `AbstractEDMF` turbulence-convection models. Whether the updraft subdomains
    sit inside the atmospheric control volume or decompose it is a modelling
    question and not a bookkeeping one.
  - `prescribed_flow` runs, which overwrite mass and energy from a prescribed field.
  - Chemistry (`GasPhaseChem`), which changes tracer composition through an
    external solver.
  - `NonEquilibriumMicrophysics2M` and `NonEquilibriumMicrophysics2MP3`, whose
    number-concentration paths have not been audited.

Every local, column or component-energy budget is out of scope.

**Custom callbacks.** `AtmosSimulation` appends the `callbacks` it is given, so a
caller can install a callback that writes `Y`. With the parent budget on, every
custom callback must be wrapped in `ReadOnlyCallback`, which declares it read-only
with respect to `Y`. Setup fails otherwise. `audit` mode checks the declaration
and `summary` mode trusts it. A callback that writes the state and supplies its own
accounting is not supported.

**Timestepping methods supported.** Every `CTS.IMEXAlgorithm` built with the
`Unconstrained` constraint, which one IMEX-ARK stepper runs. It includes `ARS343`,
the default, `ARS222`, and `CTS.ExplicitAlgorithm` with the `Unconstrained`
constraint, which builds an `IMEXAlgorithm` with identical explicit and implicit
tableaus and no Newton solver. The adapter reads the tableau from the integrator.
`SSP`-constrained tableaus and Rosenbrock algorithms run through different
steppers and are refused at setup.

All supported methods are fixed-step. `args_integrator` passes a fixed `dt` and no
controller, so there is no step rejection or retry. The journal commits only at
step end, and `abort_transaction!` discards an open transaction for a rejected
attempt that no supported configuration reaches.

The adapter relies on the stage construction and hook order of the installed
`ClimaTimeSteppers`. It records `pkgversion(ClimaTimeSteppers)` in every
report and checks the hook counts of every step. A trace test in
`test/parent_budget/envelope_tests.jl` fixes the hook order. A change in the
dependency fails the check or the test and does not silently change the meaning of
an implicit leg. The `Project.toml` compat bound is a range, and the trace test is
the pin.

## Parent quantities and authoritative integrals

```
M     = ∫ ρ                                                kg
W     = ∫ ρq_tot                                           kg
E     = ∫ ρe_tot                                           J
M_sfc = ∫_sfc sfc.water                                    kg
W_sfc = ∫_sfc sfc.water                                    kg
E_sfc = ∫_sfc sfc.T · ρ_ocean · cp_ocean · depth_ocean     J
```

The atmospheric integrals are over the global domain. The slab integrals are
horizontal integrals at the boundary.

**Total water is `ρq_tot` alone.** The water categories partition `ρq_tot` and are
never added to it. `set_precomputed_quantities!` builds `q_liq = q_lcl + q_rai` and
`q_ice = q_icl + q_sno` with `q_tot ≥ q_liq + q_ice`, so rain and snow sit inside
`q_tot`. One-moment microphysics applies no direct source to `ρq_tot` or `ρ`. It
moves the category fields. So `W = ∫ρq_tot` in every moist configuration, and
`ρq_lcl`, `ρq_icl`, `ρq_rai` and `ρq_sno` are excluded. `W` is not applicable for
`DryModel`.

**Total energy is `ρe_tot` alone.** It is prognostic and authoritative, and nothing
is reconstructed from momentum and thermodynamic state. `ρtke`, `ρe_tag_*`,
`ρe_src_*` and `prc_e_*` are diagnostics of the energy and not additional energy.
One canonical `Thermodynamics` and gravitational energy convention is used, and
every report names it.

**Dry air is a derived diagnostic.** `D = M − W = ∫ (ρ − ρq_tot)` is not a
conservation invariant and not a parent quantity. It checks the mass and water
budgets against each other and closes nothing on its own. `ρ` moves with `ρq_tot`
on the paths that move air and water together: 0-moment removal, sedimentation in
`vertical_advection_of_water_tendency!`, the surface flux, the viscous sponge and
`enforce_mass_energy_consistency!`. It does not move on these prescribed forcing
paths:

| Path                                    | Writes                                 | Writes `ρ` |
|:--------------------------------------- |:-------------------------------------- |:---------- |
| `large_scale_advection_tendency_ρq_tot` | `ρq_tot`, `ρe_tot`                     | no         |
| `subsidence_tendency!`                  | `ρq_tot`, `ρe_tot`, `ρq_lcl`, `ρq_icl` | no         |
| `apply_Tq_forcing!`                     | `ρq_tot`, `ρe_tot`                     | no         |

Each adds water to a column without adding air, so `W` moves while `M` stays and
`D` moves by `−ΔW`. A forced configuration has an open dry-air budget. A forcing
path that changes `ρq_tot` without changing `ρ` books a mass component of
`invariant zero`, because the implemented equation adds no mass. Its water and
energy components are measured independently. A mass contribution is never
manufactured from a water tendency to make `D` close. Whether the model should add
air along with prescribed moisture is a physics question for the limitations
register.

**Linearity.** `M`, `W`, `E`, `W_sfc` and `E_sfc` are linear extensive functionals
of the prognostic state, because the slab heat capacity is constant. Exact additive
process attribution is therefore well defined and needs no allocation convention.
Changing one of these integrals reopens the question.

## Reservoirs and control volumes

| Reservoir    | State         | Owns          | Exists when                              |
|:------------ |:------------- |:------------- |:---------------------------------------- |
| Atmosphere   | `Y.c`, `Y.f`  | `M`, `W`, `E` | always                                   |
| Slab surface | `Y.sfc.T`     | `E`           | `SlabOceanTemperature`                   |
| Slab surface | `Y.sfc.water` | `M`, `W`      | `SlabOceanTemperature` and a moist model |
| Exterior     | none          | none          | always                                   |

The model has no prognostic snow, soil-water, deposited-condensate or wave-energy
reservoir. Every other surface is prescribed or diagnosed and is exterior, so a
flux into it is a boundary crossing and never an internal transfer.

Two control volumes are supported. In `atmosphere_only`, the atmospheric leg of a
surface exchange is a boundary crossing. In `atmosphere_and_surface`, both legs are
inside and their sum is tested for cancellation. A control volume that names a
reservoir the configuration lacks is unavailable and not reported, because
reporting it would return the atmosphere-only numbers under the coupled name.

`Y.sfc.water` is an accounting accumulator. It integrates the water the atmosphere
delivered to the surface. It has no hydrology: it does not constrain evaporation,
run off or freeze, and nothing reads it back into a surface flux. It counts as a
reservoir because the water that enters it left the atmosphere. A report never
presents it as surface hydrology, and its incompleteness is a level-5 limitation.
Its water content is in kg m⁻², and the slab contributes the same amount to `M`
and to `W`. These are two projections of one endpoint read through one reduction.
They are not two measurements and cannot disagree.

The atmospheric side and the surface side of a surface exchange are measured
separately, from different quadratures, and may disagree. The transfer residual
measures that disagreement, so a leg is never created by negating its counterparty.

## Accepted-step boundaries

One transaction covers each accepted step. It opens on the finalized endpoint of
step `n` and closes on the finalized endpoint of step `n+1`. Finalization means the
`ClimaODEFunction` hooks that touch authoritative state, in the order
`ClimaTimeSteppers` runs them: `lim!`, `dss!`, `constrain_state!` at its configured
cadence, and `cache!`. The endpoint is read after the last of them and before any
discrete callback fires. A callback that mutates `Y` therefore belongs to
transaction `n+1`. No default callback mutates `Y`.

`update_constrain_state_every` defaults to `"step"` and accepts `"stage"` and
`"dss"`. The parent budget books one correction per firing, and a leg carries a
stage index and an occurrence beside its event and step.

Endpoint continuity is enforced. Transaction `n+1` opens on the endpoint that
transaction `n` closed on, and the parent budget checks amounts and statuses. A gap
is a change nothing accounted for. A restart compares the restored state with the
endpoint its checkpoint carries, exactly, and refuses a difference. The history
after a restart is a new segment.

## What a parent-budget amount is

A leg's amount is an accepted-step-weighted extensive contribution: the part of
`Bⁿ⁺¹ − Bⁿ` that the path is responsible for. It is neither a raw tendency nor a
raw before/after difference on an intermediate stage array, because `lim!`, `dss!`
and `constrain_state!` also run on stage arrays.

  - A final map applied to the accepted state contributes its raw before/after
    difference. That difference is part of the endpoint change.
  - An intermediate-stage map changes the array a later tendency evaluation reads.
    It enters the identity only with its exact accepted weight, which involves the
    tableau's `bᵢ` and the implicit `γᵢ`.
  - A raw intermediate-stage difference is a stage observation. It is kept where no
    projection or residual reads it, to locate which stage moved the state. It is
    evidence and never accounting.

**A decomposition amount is net.** A process row books one signed amount per
quantity, reservoir and accepted step: the integral of everything the process
applied. The identities are linear in these net amounts. Gross accounting keeps the
positive and negative parts apart as a diagnostic beside the net, at two more slots
per row, and the identities still use the net. The key `parent_budget_attribution`
takes `net`, the default, or `gross`.

**A hook folded into an aggregate is booked once.** Where the timestepper forms a
stored implicit stage tendency by differencing the stage state after the
post-implicit and post-Newton hooks, those hooks' changes are already inside the
implicit increment. Booking such a hook again as its own leg double-counts. It may
be booked independently only if the same amount is subtracted from the aggregate.
Which hooks are folded in depends on the timestepper, and the coverage registry
records what the installed one does. A folded hook is booked as a decomposition row
of the implicit channel with its accepted weight. The rows explain the aggregate
and are never added to it. Its intermediate-stage leg is `unknown` unless the
accepted weight is measured.

## Component status and evidence

Every `(M, W, E)` component of every leg and endpoint carries its own status and
evidence. Status is per component and never per leg: one event can measure energy,
prove a mass zero and have nothing to say about water.

| Status         | Amount                           | In totals | Effect on a claim                      |
|:-------------- |:-------------------------------- |:--------- |:-------------------------------------- |
| Measured       | any                              | yes       | none                                   |
| Invariant zero | exactly zero, with a named proof | yes       | none                                   |
| Not applicable | exactly zero                     | no        | none; the quantity does not exist here |
| Unknown        | exactly zero                     | no        | blocks the claim                       |

Only a measured component may carry a nonzero amount, and the code enforces it.
Unknown never contributes zero, because a missing term and a zero term look
identical in an output. An unknown component adds nothing and marks the affected
claim blocked, and the blocked result names the components that blocked it. Not
applicable is not a measured zero. A quantity that no reservoir in the view owns is
reported as inapplicable, such as water in a dry model or anything in a coupled
view of a configuration without a slab. A component's evidence names its status,
the collection or proof method, the adapter or registry entry it came from, and the
precision and reduction route where they matter. An `open` disposition in the
coverage registry demands nothing of an entry and blocks every claim it feeds.

## Output statuses

Every quantity, in every available control volume, reports exactly one status:

| Status           | Meaning                                                      |
|:---------------- |:------------------------------------------------------------ |
| `pass`           | Applicable, unblocked, and the residual is within tolerance. |
| `fail`           | Applicable, unblocked, and the residual exceeds tolerance.   |
| `blocked`        | A required component is unknown, open or missing; no claim.  |
| `not_applicable` | No reservoir in this view owns the quantity.                 |
| `reported`       | A crossing: a signed boundary flux with no verdict to give.  |

A blocked result still reports its numbers, but no closure claim may be made from
it. A crossing has nothing to cancel against, so `reported` is not a verdict, and
`not_applicable` would misdescribe its total. An unavailable control volume is not
reported at all, which differs from `not_applicable`.

## Tolerance model

A residual is judged against a tolerance built from named parts, because the parts
scale differently. For each parent quantity `q`:

```
τ_q = a_q + r_q · S_q + κ · ε_acc · ( abs(B_q ⁿ) + abs(B_q ⁿ⁺¹) + Σ_k abs(Q_q,k) )
```

  - `a_q` is an absolute floor in kg or J, and `r_q` is dimensionless.
  - `S_q` is a positive scale. It is never a signed total.
  - `ε_acc` is the epsilon of the accounting arithmetic type and not of the state's.
  - `κ` covers reduction order and rank dependence. It is calibrated and never
    chosen, and it is recorded with the result.

The endpoint magnitudes are in the last term on purpose. Bounding the residual by
the leg magnitudes alone is stricter than the subtraction supports. `abs(Q_q,k)` is
the arithmetic magnitude of a recorded amount: the integral of the absolute value of
what was summed to produce it. For a cancelling sum it is larger than the net
amount, as for the envelope of a conservative operator or the solve defect.
Rounding error scales with what was added and not with what was left. Every
measured component carries its magnitude.

The algebraic solve defect is not inside this tolerance. It is a leading-order
accounting term and is reported separately. The default `NewtonsMethod(; max_iters = 1)` against `ManualSparseJacobian(approximate_solve_iters = 1)` does not converge the
implicit stage, so the defect is first order in the accepted update and not a
rounding effect. A test sweeps `max_iters` and `approximate_solve_iters` and
requires the defect to shrink with the measured stage residual while the parent
residual stays at arithmetic level.

### Calibrating `κ`

One row of the calibration table is one backend, one state float type and one rank
count. For each row, a named configuration runs for 50 accepted steps with every
term of the parent identity measured. The largest ratio of `abs(R_q)` to the
arithmetic term of `τ_q` at `κ = 1` is recorded over the steps and quantities. The
row's `κ` is four times that ratio, rounded up to a power of two.

The table is `src/parent_budget/kappa_calibration.yaml`, read at setup by
`calibration.jl`. Each row carries the configuration name, the commit and the date
of its calibration. The named configuration is the moist DYCOMS_RF02 slab column
that `calibration_configuration()` states, run in `summary` mode. A run whose
backend, float type and rank count have no row has no tolerance, and its verdicts
are `blocked` and never `pass`. A test re-measures the serial row and requires the
ratio to stay below `κ/4`. Rows for GPU backends and for more than one rank are
measured where they run. `a_q` and `r_q` are zero unless a configuration declares a
physically motivated floor. A caller's `parent_budget_tolerances` overrides the
table. The report (`parent_budget_report.yaml`) says which of the two a run used and names the row.

### Accounting precision

The parent budget's arithmetic is independent of the state's and is at least
`Float64`. Every accumulation, reduction, endpoint, leg amount and cumulative total
uses the accounting type, also when the state is `Float32`. Conversion happens
before accumulation and before the global reduction, because casting a finished
`Float32` reduction to `Float64` has lost the information already. A `Float32`
global mass carries about seven significant digits, so a per-step change eight
orders below it vanishes. A leg is measured as an increment wherever the code
offers one and never as a difference of two large states.

### Which aggregates decide closure quality

Three cumulative numbers are kept per quantity and control volume. `max abs(Rₙ)`
names the worst single step. `Σ abs(Rₙ)` cannot cancel and bounds the total
unaccounted transfer. `Σ Rₙ` is the signed drift. The first two decide closure
quality. The drift never passes a test on its own, since `+δ` on one step and `−δ`
on the next sum to zero.

The cumulative endpoint change is also compared with an independent `Bᴺ − B⁰`
reading from the first accepted endpoint. A running sum of per-step differences
telescopes the same measurements and can only reproduce them plus rounding. The
report shows the difference as `telescoping_discrepancy`. Residuals are reported as
signed absolute values in kg and J. Normalizing by a signed total is forbidden.

`check_conservation` in `src/simulation/solve.jl` is an independent cross-check,
and a test in `test/parent_budget/report_tests.jl` compares the two. It is not
stage-integrated accounting. Its boundary term is `dt` times one sample from
`flux_accumulation!`, which holds radiation only. Its energy number divides by a
signed total, and it reports one number for the whole run.

## Cost, and the rule that accounting changes nothing

A global integral is a collective. One reduction per leg would add on the order of a
hundred collectives per step. So legs accumulate locally, and the global reduction
happens once per accepted step over one packed fixed-layout buffer.

Nothing in the parent budget writes to the state.
`test/parent_budget/envelope_tests.jl` checks that the state is bit for bit the
same with it on and off, and a residual is defined by subtraction and
never inserted as a balancing entry. `audit` mode costs more than `summary` mode.
It copies the parent tendency fields when an applied-update event opens, takes six
local integrals when it closes, adds one implicit tendency evaluation per implicit
stage, and keeps storage that grows with the run.

## Energy-reference covariance

The audit shifts the energy by `E* = E + a·M + b·W`. Every leg and residual must
transform the same way, for example `R_E* = R_E + a·R_M + b·R_W`. `a ≠ 0` is
admissible. Whether `b` is admissible is open. When a limiter moves `ρq_tot` by
`Δ`, `enforce_mass_energy_consistency!` moves `ρ` by `Δ` and `ρe_tot` by
`Δ·(uᵥ(T) + Φ)`, and it is not established that this carrier energy is consistent
with a `b·W` shift across every water leg. Re-expressing a finished journal under
the shift only checks linearity. Only a rerun with shifted thermodynamic references
can reject a `b`, and its design is unspecified: the shifted parameters, the initial
state, the boundary and carrier fluxes, and the slab, whose `E_sfc` does not see the
atmospheric reference. No covariance result may accept or reject a value of `b`
without that rerun, and no carrier-energy term the model lacks may be invented.

## Limitations register

Physical-completeness gaps at claim level 5. They are never numerical residuals, and
every report carries them.

  - Gravity-wave drag and Rayleigh damping change momentum while `ρe_tot` is
    prognostic and unchanged, so their direct energy contribution is zero by
    construction. Any intended frictional heating, stress work or solid-Earth
    exchange has no implemented counterpart.
  - Prescribed forcing adds water and energy to a column without adding air, so a
    forced run has an open dry-air budget. The parent budget books the mass
    component as an invariant zero and reports the open budget.
  - `Y.sfc.water` is an accounting accumulator with no hydrology, and the model has
    no soil, snow or deposited-condensate reservoir.
  - `flux_accumulation!` omits turbulent surface fluxes.
  - The process records cover the processes that the applied-update event wraps for
    the tags. On the implicit path they cover the microphysics sink and
    sedimentation. That set is not the parent budget's coverage set, and a process
    record is never a closure leg.

## Blockers

Each blocks a named claim and not the whole parent budget.

| Blocker                                                      | Blocks                                 | Cleared by              |
|:------------------------------------------------------------ |:-------------------------------------- |:----------------------- |
| Energy-reference `b`                                         | the covariance claim                   | open                    |
| `κ` rows for GPU backends and for more than one rank         | a numeric verdict on those backends    | measured where they run |
| Attribution and transfer legs collected in `audit` mode only | claim levels 3 and 4 in `summary` mode | a decision              |
