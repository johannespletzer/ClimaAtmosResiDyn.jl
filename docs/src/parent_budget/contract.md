# Parent-Budget Ledger: Budget Contract

This page freezes what the parent-budget ledger will and will not claim. It is
the artefact the rest of the work is measured against. Nothing here describes
code that exists yet. The plan that governs the implementation is
[Parent-Budget Ledger: Plan](plan.md), and the path-by-path inventory is
[Parent-Budget Ledger: Coverage Matrices](coverage.md).

## The claim

> Exact signed discrete closure for mass, total water, and total energy;
> explicit cancellation of internal transfers; exact accounting of boundaries,
> reservoirs, and state corrections; and a separately reported residual.

"Exact" means faithful to the accepted-state update the model actually
performs, within the tolerances declared below. It does **not** mean bitwise
reproducibility, and it does not mean the model's equations contain every
process a complete atmosphere would have.

### The claim ladder

Four claims are kept apart, and closing one does not establish the next.

 1. **Accepted-state reconciliation.** The endpoint change of a reservoir over
    an accepted step equals the sum of the ledger's recorded contributions plus
    a residual defined by subtraction.
 2. **Implemented-equation closure.** Those contributions reproduce the update
    the supported integrator actually applies, with the algebraic-solve defect
    reported as its own term.
 3. **Physical completeness.** Every intended work term, carrier energy,
    reservoir, and exchange is present in the model equations.
 4. **Provenance attribution.** Material or energy can be assigned uniquely to
    an origin.

Meta Step 1 targets claims 1 and 2 only. A physically missing term can leave no
residual at all, because incomplete equations still close against themselves.
Claim 3 is tracked in the limitations register, claim 4 belongs to the source-tag
work and is explicitly excluded here.

## Supported scope

### Quantities

Mass `M`, total water `W`, and total energy `E`, each with its own definition,
collection adapter, invariants, residual, and tolerance. The shared journal
coordinates coupled exchanges. It does not make the three interchangeable.

### Configurations supported at the end of Meta Step 1

Concrete types, not families. "Non-equilibrium" was ambiguous in an earlier
draft and is spelled out here.

  - Microphysics: `DryModel`, `EquilibriumMicrophysics0M`, and
    `NonEquilibriumMicrophysics1M`, on the sphere and in a single column.
  - `diff_mode` explicit and implicit.
  - `microphysics_tendency_timestepping` explicit and implicit.
  - Surface: every prescribed or diagnosed surface temperature, and
    `SurfaceConditions.SlabOceanTemperature`.
  - Radiation off, `HeldSuarezForcing`, and RRTMGP.
  - Forcing: `LargeScaleSubsidence`, large-scale advection, and the external
    forcing that reaches `apply_Tq_forcing!`. These are supported and appear in
    the tests, with the open dry-air budget recorded in the limitations
    register. An earlier draft used them in the tests without listing them here.
  - Callbacks: the default set only.

### Configurations explicitly out of scope

  - `PrognosticEDMFX` and `DiagnosticEDMFX`. The updraft subdomains carry their
    own `ρa`, `mse`, and `q_tot`, and whether those belong inside the
    atmospheric control volume or are a decomposition of it is a modelling
    question, not a bookkeeping one. Excluded until it is answered.
  - `prescribed_flow` runs. `fully_explicit_tendency!` overwrites state from a
    prescribed field, so mass and energy are imposed rather than evolved. The
    path appears in the mutation matrix and is booked as a prescribed
    overwrite, but no closure is claimed for it.
  - Chemistry (`GasPhaseChem`), which changes tracer composition through an
    external solver.
  - `NonEquilibriumMicrophysics2M` and `NonEquilibriumMicrophysics2MP3`. The
    coverage matrix and the planned tests were written against one-moment, and a
    two-moment scheme carries number concentrations whose paths have not been
    audited. Excluded rather than assumed to behave like 1M.
  - State-mutating custom callbacks. `AtmosSimulation` takes a `callbacks`
    keyword and appends whatever it is given, so a caller can install a callback
    that writes `Y`. The contract's claim that supported callbacks are read-only
    covers the **default** set, which the mutation matrix inventories. A custom
    callback must either declare itself read-only with respect to `Y` or supply
    its own ledger accounting; without one of those, no closure is claimed.
  - Every local, column, or component-energy budget.

### Timestepping methods supported

Only what the model actually configures:

  - `CTS.IMEXAlgorithm(CTS.ARS343(), CTS.NewtonsMethod(...))`, the default.
  - `CTS.ExplicitAlgorithm` tableaus, for the explicit-only tests.

Both are **fixed-step**. `args_integrator` passes a fixed `dt` and no
controller, so there is no embedded error estimator, no step rejection, and no
retry. That is a scope simplification worth stating plainly: the plan's
rejection and adaptivity machinery has nothing to act on in a supported
configuration. The journal still commits only at step end, and a test asserts
that no rejection occurred, so the property is guarded rather than assumed.

## Accepted-step boundaries

One transaction per accepted timestep. The interval runs from immediately after
all finalization for accepted state `n` to immediately after all finalization
for accepted state `n+1`.

Finalization for ClimaAtmos means the `ClimaODEFunction` hooks that touch
authoritative state, in the order `ClimaTimeSteppers` runs them: `lim!`
(`limiters_func!`), `dss!`, `constrain_state!` at its configured cadence, and
`cache!`. Discrete callbacks fire after the step. The endpoint used by the
ledger is the state after the last of these, so a callback that mutates `Y` is
inside transaction `n+1`, not outside every transaction.

`update_constrain_state_every` defaults to `"step"` but accepts `"stage"` and
`"dss"`. The ledger reads the configured cadence rather than assuming one, and
records one correction leg per firing. A leg's identity therefore carries an
execution identity, stage index and occurrence, alongside its event and step:
without it the same correction firing at four ARS343 stages would collide as one
leg and be refused.

**Where the boundary falls, stated once.** The endpoint is read after the
integrator's own hooks for the step (`lim!`, `dss!`, `constrain_state!`,
`cache!`) and **before** any discrete callback fires. Discrete callbacks
therefore belong to transaction `n+1`, the one that opens on that endpoint, and
never to the step whose hooks just finished. In every supported configuration no
discrete callback mutates `Y` — they write cache `Ref`s, radiation fields, files
and diagnostics — so the choice is currently unobservable. It is fixed here so
that a callback which does mutate state later falls on one side of the boundary
by rule rather than by accident.

### What a leg's amount is

A leg's `amount` is an **accepted-step-weighted extensive contribution**: the
part of `Bⁿ⁺¹ − Bⁿ` that this path is responsible for. It is not a raw tendency,
and it is not a raw before/after difference taken on an intermediate stage
array. Those three are different numbers and the schema must not let them be
mixed.

The distinction has teeth because `lim!`, `dss!` and `constrain_state!` run on
intermediate stage arrays as well as on the final accepted state.

  - A map applied to the **final accepted state** contributes its raw change.
    That change *is* part of the endpoint difference.
  - A map applied to an **intermediate stage** does not. It changes the array a
    later tendency evaluation reads, so its effect on the endpoint is mediated
    by the tableau, not added to it. Booking its raw before/after difference in
    the parent identity is wrong by construction, whatever the number happens
    to look like.

So an intermediate-stage map enters the identity only with its exact accepted
weight, generally involving the tableau's `bᵢ` and the implicit `γᵢ`. And where
the timestepper forms the stored implicit stage tendency by differencing the
stage state *after* the post-implicit correction and post-Newton hooks have
run, those hooks' changes are already inside the effective implicit increment;
booking them again as separate legs double-counts, so a separately booked hook
must be subtracted back out of the aggregate.

That last mechanism is the reviewer's diagnosis of current
`ClimaTimeSteppers`, and it is **not verified here** — the package source is not
available in this environment. PR 5 must confirm the stage-tendency form
against the pinned version before any implicit decomposition is booked. The
rule above does not depend on the answer; only the size of the correction does.

Until PR 5 freezes that decomposition against the actual hook order, every
intermediate-stage leg is `unknown`, never `measured`. Raw stage observations
are still worth collecting — they localize a defect — but they live in a
separate audit structure that is never summed into the parent identity.

PR 5 must test all three `update_constrain_state_every` cadences, `"step"`,
`"stage"` and `"dss"`, because they place the same map on different sides of
this distinction.

## Reservoir graph

The graph is much smaller than a coupled land–ocean model's, and saying so
precisely is part of the contract.

| Reservoir    | State         | Owns          | Exists when                              |
|:------------ |:------------- |:------------- |:---------------------------------------- |
| Atmosphere   | `Y.c`, `Y.f`  | `M`, `W`, `E` | always                                   |
| Slab surface | `Y.sfc.T`     | `E`           | `SlabOceanTemperature`                   |
| Slab surface | `Y.sfc.water` | `M`, `W`      | `SlabOceanTemperature` and a moist model |
| Exterior     | none          | —             | always                                   |

There is **no** prognostic snow, soil-water, or deposited-condensate reservoir,
and no wave-energy reservoir. Every other surface is prescribed or diagnosed
and is therefore exterior, not a reservoir: its state is not owned by the model,
so a flux into it is a boundary crossing and not an internal transfer.

`Y.sfc.water` owns mass as well as water, because the water it gains left the
atmosphere as `ρq_tot` and therefore also as `ρ`. See the integrals below for
why that is so, and for why the coincidence of its two legs is measured here
rather than assumed anywhere else.

## Authoritative integrals

For the atmosphere, over the global domain:

```
M = ∫ ρ            [kg]
W = ∫ ρq_tot       [kg]
E = ∫ ρe_tot       [J]
```

For the slab surface, as a horizontal integral at the boundary:

```
M_sfc = ∫_sfc  sfc.water                                   [kg]
W_sfc = ∫_sfc  sfc.water                                   [kg]
E_sfc = ∫_sfc  sfc.T · ρ_ocean · cp_ocean · depth_ocean     [J]
```

### What is and is not in each

**`ρq_tot` is total water, precipitation included.** The categories partition it
and are never added to it. `set_precomputed_quantities!` builds the
thermodynamic state as `q_liq = q_lcl + q_rai`, `q_ice = q_icl + q_sno`, and
`q_tot ≥ q_liq + q_ice`, so rain and snow are inside `q_tot` exactly as cloud
water is. One-moment microphysics says so in its own words: it moves the
category fields and applies "no direct sources to `ρq_tot`, `ρ`". So `W = ∫ρq_tot`
in every moist configuration, and `ρq_lcl`, `ρq_icl`, `ρq_rai` and `ρq_sno` are
all excluded from it.

| Model                       | `W`        |
|:--------------------------- |:---------- |
| `DryModel`                  | `n/a`      |
| `EquilibriumMicrophysics0M` | `∫ ρq_tot` |
| non-equilibrium             | `∫ ρq_tot` |
| one-moment                  | `∫ ρq_tot` |

**`D` is a derived diagnostic, not a conservation invariant.** The dry-air mass

```
D = M − W = ∫ (ρ − ρq_tot)      [kg]
```

is well defined, and the two forms are the same number because the integral is
linear. That is all the identity asserts. `D` is **not** conserved, and an
earlier draft of this contract wrongly said it was.

`ρ` does track `ρq_tot` on the paths that move air and water together:
0-moment removal (`Yₜ.c.ρq_tot += ρ_dq_tot_dt` beside `Yₜ.c.ρ += ρ_dq_tot_dt`),
sedimentation in `vertical_advection_of_water_tendency!` (`Yₜ.c.ρ += vtt`
beside `Yₜ.c.ρq_tot += vtt`), surface flux, the viscous sponge, and
`enforce_mass_energy_consistency!`.

It does not track it on the prescribed forcing paths, all three of which are in
scope:

| Path                                    | Writes                                 | Writes `ρ` |
|:--------------------------------------- |:-------------------------------------- |:---------- |
| `large_scale_advection_tendency_ρq_tot` | `ρq_tot`, `ρe_tot`                     | no         |
| `subsidence_tendency!`                  | `ρq_tot`, `ρe_tot`, `ρq_lcl`, `ρq_icl` | no         |
| `apply_Tq_forcing!`                     | `ρq_tot`, `ρe_tot`                     | no         |

Each adds water to a column without adding air to it, so `W` moves while `M`
stays put and `D` moves by `−ΔW`. Any forced configuration therefore has a
dry-air budget that is open by construction.

What the ledger does about it: these paths record a mass component of
`InvariantZero` — the implemented equation adds no mass, and that zero is the
measured truth about the code — with their water and energy components measured
independently. A mass leg is never manufactured from a water leg to make `D`
close.

Whether the model *ought* to add mass along with prescribed moisture is a
question about the physics, not about the bookkeeping. The ledger's job is to
report what the discrete equations do. It is listed in the limitations register
so that the answer, if it ever changes, changes there and not here.

**The slab owns mass as well as water.** `Y.sfc.water` is a water content in
`kg m⁻²`, and the water it gains left the atmosphere as `ρq_tot` and therefore
also as `ρ`. The existing `check_conservation` already reflects this: it adds
the change in surface water to the change in `∫ρ` before calling mass closed.
So in the coupled view the slab contributes to `M` and to `W`, with the same
amount, and it is the one reservoir where those two legs coincide. In the
atmosphere-only view the deposition is a boundary crossing for both.

That the two legs coincide *here* is a measured property of this reservoir, not
a licence to infer one from the other elsewhere. The rule that a water increment
is never copied into mass still holds for every other path, and the mass and
water legs are still recorded independently.

**`E` is `ρe_tot` alone.** Total energy is prognostic, so it is authoritative
and nothing is reconstructed from momentum and thermodynamic state. `ρtke`, the
tagged tracers `ρe_tag_*`, the source tags `ρe_src_*`, and the process records
`prc_e_*` are all excluded: they are diagnostics of the energy, not additional
energy.

### Linearity

`M`, `W`, `E`, `W_sfc`, and `E_sfc` are all linear extensive functionals of
authoritative prognostic state. `E_sfc` is linear because the slab heat capacity
is constant. Exact additive process attribution is therefore well defined, and
no allocation convention is needed. This answers the plan's first question
affirmatively for every supported configuration, and the answer is a property of
the chosen integrals, so any later change to them reopens it.

## Conventions

  - **Sign.** Positive means addition to the named reservoir.
  - **Units.** Extensive SI, `kg` and `J`. Normalized views are secondary and
    are never formed by dividing by a signed total.
  - **Energy reference.** Set by `Thermodynamics`, with latent heat carried in
    `ρe_tot`.
  - **Geometry.** The same `ClimaCore` integrals, ownership, and decomposition
    the endpoint diagnostics use, so a distributed run reduces once over owned
    degrees of freedom.
  - **Density-weighted fields only.** The raw `prc_e_*` and `prc_q_*` state is
    extensive. The `e_prc_*` and `q_prc_*` diagnostics divide by current
    density and are not budget amounts.

### Energy-reference covariance

The admissible shift is audited as

```
E* = E + a·M + b·W
```

with the requirement that every leg and residual transforms as
`Q_E* = Q_E + a·Q_M + b·Q_W` and `R_E* = R_E + a·R_M + b·R_W`.

`a ≠ 0` is admissible. `b` is **an open question, not a settled zero**, and the
reason is `enforce_mass_energy_consistency!`: when a limiter moves `ρq_tot` by
`Δ`, it moves `ρ` by `Δ` and `ρe_tot` by `Δ·(uᵥ(T) + Φ)`. Whether that carrier
energy is consistent with a `b·W` shift across *every* water leg, including
precipitation fallout and surface deposition, is what the audit is for.

**Two different things are called covariance, and only one of them can settle
`b`.** An earlier draft ran them together.

*Algebraic re-expression.* Take a completed ledger and apply
`Q_E* = Q_E + a·Q_M + b·Q_W` to every amount. The residual then transforms the
same way for any `a` and `b` whatever, because the ledger is linear and the
substitution is exact. This is a **tautology**. It is worth running as a
self-check that the implementation really is linear and that no leg was stored
in a way that breaks the substitution, and it is worth nothing as evidence about
which `b` the model admits.

*Physical reference experiment.* Rerun the model with shifted thermodynamic
references and compare the two ledgers. This one can reject a `b`, and it is an
intervention, so it has to be specified before it is run. PR 7 must fix all
four pieces:

  - which `Thermodynamics` parameters are shifted, and by how much;
  - how the initial state is transformed, so the two runs start at states that
    correspond rather than at two unrelated states;
  - how the boundary and carrier fluxes transform, in particular the energy
    carried by a water flux across the surface;
  - how the slab reservoir transforms, since `E_sfc` is built from `Y.sfc.T` and
    a constant heat capacity and does not see the atmospheric reference at all.

Until those four are written down, no covariance result may be used to accept or
reject a value of `b`.

Both audits are checks on the implemented model. Neither is permission to invent
a carrier-energy term the model does not have.

## Control volumes

Legs are recorded once, per reservoir. Views are projections of those legs.

  - **Atmosphere only.** The atmospheric leg of a surface exchange is a boundary
    crossing.
  - **Atmosphere plus slab surface.** Both legs are inside, and their sum is
    tested for cancellation.
  - **Prescribed surface.** Only the atmospheric leg exists; the counterparty is
    exterior.

No net-transfer entry is stored, and no equal-and-opposite leg is manufactured.
Where the implemented legs differ, the mismatch is the finding.

## The accounting identity

For each accepted step, control volume `C`, and `B ∈ {M, W, E}`:

```
ΔB_actual,C = B_C(after finalization of step n+1) − B_C(after finalization of step n)

ΔB_actual,C = ΣQ_equation + ΣQ_map + ΣQ_correction + ΣQ_solve_defect + R_bookkeeping
```

with

```
R_bookkeeping = ΔB_actual − ΣQ_recorded
```

and nothing else. The residual is defined by subtraction and is never an entry
that forces closure. `Q_solve_defect` is included only when it is derived
independently from the integrator's own residual equations.

A projection reports more than a number and a Boolean. Collapsing status into
"blocked or not" loses two things that matter. A quantity no reservoir in the
view owns — water in a dry model, anything at all in the coupled view of a
configuration with no slab — would otherwise read as an ordinary closed budget
at zero, which is a claim the ledger never made. And a blocked projection has to
name *which* components blocked it, or the report says a claim is unavailable
without saying what would make it available. So each projection carries whether
the quantity is applicable in that view at all, and the identities of the
components that blocked it.

Reported per step and cumulatively: endpoint change, sum of entries, solve
defect, bookkeeping residual, the discrepancy before the solve defect is
included, and the cumulative ledger against the independent run-segment
difference `B^N − B^0`.

The signed cumulative residual is not enough on its own, and "per-step values
are also reported" understates the problem. `Σ Rₙ` cancels exactly the failure
this ledger exists to expose: `+δ` on one step and `−δ` on the next sums to zero
and reports a perfectly closed run that closed on neither step. So the ledger
keeps three cumulative numbers per quantity and control volume, not one:

  - `Σ Rₙ`, the signed total, which is the drift.
  - `Σ |Rₙ|`, which cannot cancel and bounds the total unaccounted transfer.
  - `max |Rₙ|`, which names the worst single step.

A tolerance is checked against the magnitude aggregates. The signed sum is
reported, never used to pass a test on its own.

**Endpoint continuity is enforced, not assumed.** Transaction `n+1` opens on the
same endpoint that transaction `n` closed on. The ledger checks that rather than
trusting the caller, because a gap between them is a change nothing accounted
for, and it would otherwise vanish from the cumulative total without trace.

## Tolerance model

Four sources are budgeted separately, because they scale differently and
conflating them is how a real defect gets absorbed.

| Source                              | Expectation                                                                     |
|:----------------------------------- |:------------------------------------------------------------------------------- |
| Local arithmetic and reconstruction | `O(ε)` relative to the sum of absolute contributions, never to the signed total |
| Parallel reduction order            | grows with rank count; measured, not promised bitwise                           |
| Algebraic solve defect              | **leading order, not small** — see below                                        |
| Endpoint subtraction                | cancellation in `Bⁿ⁺¹ − Bⁿ`; scales with the endpoint magnitudes, not the legs  |
| Approximate collection              | none; the ledger has no intentionally approximate leg                           |

The solve-defect row is the important one. The default is

```
CTS.NewtonsMethod(; max_iters = 1, update_j = CTS.UpdateEvery(CTS.NewNewtonIteration))
```

with `ManualSparseJacobian(approximate_solve_iters = 1)`. One Newton iteration
against an approximate Jacobian does not converge the implicit stage. The
algebraic residual is therefore a first-order term in the accepted update, not a
rounding effect, and the identity **cannot close without `Q_solve_defect`** in
any implicit configuration.

That also retires the plan's nonlinear-tolerance sweep, which assumes a
tolerance to tighten. The replacement test sweeps `max_iters ∈ {1, 2, 4}` and
`approximate_solve_iters`, and requires `Q_solve_defect` to shrink with the
measured stage residual while `R_bookkeeping` stays at arithmetic level
throughout. A residual that does not move under that sweep is a bookkeeping bug
wearing a solver's clothes.

### Accounting precision

The ledger's arithmetic precision is **independent of the state's** and is at
least `Float64`. Every reduction, endpoint, leg accumulator and cumulative total
is `Float64` even when the state is `Float32`.

This is not a refinement, it is what makes the residual mean anything. A leg is
a small increment against a global background: a `Float32` global mass is
carried to about seven significant digits, so a per-step change eight orders
below it vanishes entirely in the subtraction. Accumulating in `Float64` keeps
the endpoints and the legs exact enough that what is left is bookkeeping error
rather than accumulation noise.

For the same reason a leg is measured as an **increment** wherever the code
offers one, never as a difference of two large states. A difference inherits the
cancellation of its operands even in `Float64`.

### The pass criterion

With the residual of step `n` defined as the endpoint change minus the sum of
that step's legs, define three positive scales: `S_endpoint`, the sum of the two
endpoint magnitudes; `S_legs`, the sum of the leg magnitudes; and `S`, their
total. Then require, for the arithmetic part of the budget,

```
abs(Rₙ) ≤ κ · ε_acc · S
```

where `ε_acc` is the accounting epsilon, `eps(Float64)`, and `κ` covers
reduction-order and rank dependence. `κ = 64·√(N_ranks)` is a **provisional**
starting value, to be calibrated in PR 7 against measured serial and MPI runs
and then frozen. It is written down now so that PR 7 replaces a number rather
than inventing a criterion.

`S` includes `S_endpoint` deliberately. Bounding the residual by the leg
magnitudes alone would be a stricter claim than the subtraction can support, and
would fail on a step whose legs are tiny against the background.

The solve defect is **not** inside this criterion. It is a leading-order
physical-accounting term with its own row above, reported separately and swept
with `max_iters`, never absorbed into an arithmetic tolerance.

PR 7 tests this on a small increment over a realistic global background, in
`Float32` and `Float64` states alike, since that is the case the criterion
exists for.

Residuals are always reported as signed absolute values in `kg` and `J`. A
relative view may be added against a documented positive scale such as `S`.
Normalizing by signed total energy is forbidden, which is one of the defects in
the existing check described below.

## Cost, and the rule that diagnostics change nothing

A global integral is an MPI reduction. ARS343 has four stages and the coverage
matrices list dozens of paths, so a naive leg-per-`sum()` implementation would
add on the order of a hundred reductions per timestep. That is a blocker for
using the ledger in a long run, and it is not something to discover in PR 7.

Two rules follow, and they are part of the contract:

 1. Legs accumulate into fields where the quantity is a field, and the global
    reduction happens once per step over a packed buffer of all legs.
 2. The ledger is off by default, behind its own configuration key. A run with
    it off must produce a bitwise-identical trajectory to the same run built
    without the feature, and a run with it on must produce the same trajectory
    as the same run with it off. Both are tested.

The second rule is what makes "the ledger is not a fixer" checkable rather than
merely stated.

## What the existing conservation check is, and is not

`check_conservation` in `src/simulation/solve.jl` is the current endpoint check,
run from `.buildkite/ci_driver.jl`. It is a useful independent cross-check and
PR 7 compares against it. It is **not** stage-integrated accounting, for four
specific reasons that the ledger must not inherit:

 1. Its boundary term comes from `flux_accumulation!`, which adds
    `Δt × horizontal_integral_at_boundary(ᶠradiation_flux, ...)` once per step.
    That is `dt` times one sample, not the stage-weighted flux the integrator
    actually applied.
 2. `flux_accumulation!` accumulates **radiation only**. Turbulent surface
    fluxes of heat and moisture never enter the accumulator, so for a
    non-slab surface the energy check is closing against an incomplete
    boundary term.
 3. `energy_conservation` divides by `sum(ρe_tot)`, a signed total. The
    normalization is meaningless if the total passes near zero and it hides
    sign information that the ledger exists to expose.
 4. It reports one number for the whole run, so a per-step defect that changes
    sign is invisible. Cancellation over a long run is not closure.

## Answers to the questions PR 1 had to resolve

 1. **Are `M`, `W`, `E` linear in authoritative state?** Yes, in every supported
    configuration, including the slab reservoir integrals. Not established for
    EDMF, which is why EDMF is out of scope.
 2. **Which integrators and split paths are in scope, and do they expose
    accepted stages, coefficients, rejection hooks, and residuals?**
    `IMEXAlgorithm(ARS343, NewtonsMethod)` and explicit tableaus. Stages and
    coefficients are reachable from the `ClimaTimeSteppers` cache. Rejection
    hooks are moot at fixed step. Algebraic residuals are reachable from the
    implicit stage problem. **Open:** whether the accepted-solution weights can
    be read without re-evaluating a stage is the first thing PR 5 must
    establish, and if they cannot, PR 5 reports aggregate closure rather than
    fabricating a tableau.
 3. **Which surface states own what?** `Y.sfc.T` owns energy. `Y.sfc.water` owns
    water *and* mass, with the same amount, because what it gains left the
    atmosphere as `ρq_tot` and so also as `ρ`. Only `SlabOceanTemperature` has
    either.
 4. **Are coupled legs derived from one amount or discretized independently?**
    Independently, and this is a **blocker for the coupled-view cancellation
    claim until measured**. The atmospheric fallout leg is
    `ᶜprecipdivᵥ` of a sedimentation flux in
    `vertical_advection_of_water_tendency!`, with free outflow at the lower
    boundary. The surface leg is `Yₜ.sfc.water -= P_liq + P_snow` in
    `surface_precipitation_tendency!`, built from the cached surface rain and
    snow fluxes, and called from `remaining_tendency!` or `implicit_tendency!`
    depending on `microphysics_tendency_timestepping`. Two quadratures of the
    same physical flux is exactly the case the ledger must not paper over.
    PR 4 measures both and reports the difference.
 5. **Which energy-reference transformations are admissible?** `a ≠ 0` yes.
    `b` open, pending the covariance audit, for the reason given above.
 6. **Can included mutations be rolled back on a rejected attempt?** The
    question does not arise in a supported configuration, because fixed-step
    IMEX never rejects. Guarded by an assertion rather than an implementation.
 7. **Which water categories are included without overlap?** `ρq_tot` alone.
    The categories `ρq_lcl`, `ρq_icl`, `ρq_rai` and `ρq_sno` partition it and
    are never added to it.

## Blockers carried out of PR 1

These block specific claims, not the whole ledger. Each names the claim it
blocks.

  - **`Yₜ_lim` coverage.** `remaining_tendency!` accumulates into two channels,
    `Yₜ` and `Yₜ_lim`, and the limited channel carries horizontal tracer
    advection and tracer hyperdiffusion. Any explicit adapter that reads only
    `Yₜ` is silently missing them. Blocks the water closure claim until PR 3
    covers both channels.
  - **Coupled-leg symmetry.** Blocks the coupled-view internal-cancellation
    claim until PR 4 measures both legs, per question 4 above.
  - **Energy-reference `b`.** Blocks the covariance claim until PR 7's audit.
  - **Accepted-weight access.** Blocks the implemented-equation claim (ladder
    rung 2) for implicit terms until PR 5 establishes it. Rung 1 is unaffected.

## Limitations register

Started here, extended by every later PR, and published in PR 7. It holds
physical-completeness gaps, which are claim 3 and never a numerical residual.

  - Gravity-wave drag and Rayleigh damping change momentum while `ρe_tot` is
    prognostic and unchanged, so their direct energy contribution is exactly
    zero by construction. Any intended frictional heating, stress work, or
    solid-Earth exchange has no implemented counterpart. Recorded as a
    completeness gap, not as a residual.
  - `flux_accumulation!` omits turbulent surface fluxes, as above.
  - Prescribed forcing adds water and energy to a column without adding air to
    it. `large_scale_advection_tendency_ρq_tot`, `subsidence_tendency!` and
    `apply_Tq_forcing!` all write `ρq_tot` and `ρe_tot` and never write `ρ`, so
    a forced run has an open dry-air budget. This is a property of the
    implemented equations. The ledger records the mass component as an
    invariant zero and reports the open budget rather than closing it.
  - The process record covers only the explicitly bracketed tendency path. Its
    bracket set is not the ledger's coverage set.
