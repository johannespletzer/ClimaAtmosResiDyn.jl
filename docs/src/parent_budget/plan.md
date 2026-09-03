# Parent-Budget Ledger: Plan

This is the single, consolidated plan for Meta Step 1, parent-budget closure. It
supersedes the earlier phase-numbered plan and the PR-numbered revision of it.
Where those two differed, this one decides; where the code contradicted both,
the code wins and the change is marked **[revised]** with its reason.

The frozen definitions live in the [budget contract](contract.md). The
path-by-path inventory lives in the [coverage matrices](coverage.md). This page
is the sequence of work.

## Target

Exact signed discrete closure for mass, total water, and total energy, with
internal transfers cancelled explicitly, boundaries and reservoirs accounted
exactly, state corrections visible, and a residual reported separately.

Physical completeness and provenance attribution are distinct, stronger claims
and are not made here.

## What this is not

  - Not a fixer. The ledger never changes the trajectory, and that is tested
    rather than asserted.
  - Not a claim about configurations outside the supported list.
  - Not source-tag closure. `ρq_tag_*`, `ρe_src_*`, and `ρe_tag_*` are excluded
    from the parent identity, and their sum-to-parent properties are separate
    audits in a later meta step. A finished parent ledger may later help explain
    a tag residual. Tag closure may never be used to certify the parent.
  - Not a component-energy, column, or local budget. Those come after the
    global parent budget is correct.

## Foundation

Built on `main`, which now carries the process-record work: PR 41, plus PR 46,
plus the closure and diagnostics fixes in PR 47, all merged through PR 40.

**[revised]** The earlier plan said "build on PR 41 after incorporating PR 46,
or on main after that work merges", and for a while neither was available: PRs
41, 42, 43, 46 and 47 were all closed without merging, and their content
survived only on branches. PR 40 was the merge point for the whole stack, and
merging it made the second option real. Nothing about the design depended on
which of the two it turned out to be.

PR 40 also brought in the energy source tags of PRs 42 and 43, which this plan
said not to build the parent budget on. That exclusion is unchanged and is
architectural rather than a matter of what is on `main`: `ρe_src_*` stays out of
the parent identity, and its own closure is a separate audit in a later meta
step.

What is reused:

  - The prognostic, untransported `prc_e_<process>` and `prc_q_<process>` fields
    and their restart persistence.
  - The snapshot-and-difference bracket pattern around explicit process blocks.
  - The timestepper integration of a record's tendency, which is what makes a
    record a time integral rather than a sum that scales with `dt`.

What is not reused, and must not be implied:

  - The process record is not a closed budget. It is a partial signed history of
    configured, bracketed processes, and its public meaning stays that. Its
    bracket set is not the ledger's coverage set: brackets exist only where
    `snapshot_tags!` and `attribute_tags!` are called, which is the explicit
    path and one implicit water block.
  - The `e_prc_*` and `q_prc_*` diagnostics divide by current density. The raw
    `prc_e_*` and `prc_q_*` state is the extensive quantity. Only the raw fields
    are budget amounts.

## Architecture

One transactional event journal holding actual reservoir-specific legs. Each leg
carries event and leg identity, the affected reservoir, signed extensive `ΔM`,
`ΔW`, `ΔE`, a per-component status, update path and process classification,
accepted-step and execution-phase identity, measurement method, and units.

Mass, water, and energy keep separate definitions, adapters, invariants,
residuals, tolerances, and tests. The journal coordinates coupled exchanges. It
does not make the three budgets one budget.

No component is ever inferred from another. Water is not copied into mass.
Energy carried by water is not inferred from the water leg. An unmeasured
component is `unknown`, never zero.

Legs are recorded once, per reservoir. Control-volume views are projections. No
net-transfer entry is stored and no equal-and-opposite leg is manufactured, so
an implemented mismatch stays visible.

### The identity

```
ΔB_actual = ΣQ_equation + ΣQ_map + ΣQ_correction + ΣQ_solve_defect + R_bookkeeping
R_bookkeeping = ΔB_actual − ΣQ_recorded
```

The residual is defined by subtraction and by nothing else.

## The pull requests

### PR 1 — Budget contract and coverage matrices

Documentation and architecture only, no instrumentation.

Freezes control volumes, reservoir ownership, quantities, signs, units, energy
reference, supported methods, and tolerances. Inventories every equation and
state-mutation path, separates authoritative from temporary mutations, and gives
every `(M, W, E)` component a status and a proposed measurement.

Delivered as [contract](contract.md), [coverage](coverage.md), and this page.

### PR 2 — Core journal and endpoint reconciliation

Implements the event and leg schema, the authoritative atmosphere and slab
integrals, accepted-step transactions, control-volume projections, endpoint
changes, and the bookkeeping residual.

Tests journal mechanics, component status, reservoir projection, and duplicate
prevention. Does not claim process coverage.

**[revised]** No rollback implementation. Fixed-step IMEX never rejects a step,
so a rollback path would be untested code guarding an unreachable state.
Instead the transaction commits only at step end, and an assertion fails loudly
if a rejection ever occurs. If an adaptive controller is added later, rollback
becomes real work and reopens this.

**[added]** The ledger is off by default behind its own configuration key, and
legs accumulate into fields so the global reduction happens once per step over a
packed buffer. Reason: a leg-per-`sum()` implementation would add on the order
of a hundred MPI reductions per timestep on four ARS343 stages. This is a design
constraint, not an optimization to defer.

### PR 3 — Explicit equation accounting

Accumulates the explicit right-hand-side contributions the timestepper actually
consumes, with accepted-solution weights rather than raw tendency counts or `dt`
times one sample. Adds independently measured mass components. Ensures nothing
is committed outside an accepted step.

**[added]** Covers **both** explicit channels. `remaining_tendency!` accumulates
into `Yₜ` and `Yₜ_lim`, and `ClimaTimeSteppers` integrates the limited channel
through the limiter. Horizontal tracer advection and tracer hyperdiffusion live
only in `Yₜ_lim`, so an adapter reading `Yₜ` alone silently loses them. Neither
earlier plan mentioned this channel; it is the largest single coverage hole
found in PR 1.

Where a fused operator cannot expose a defensible split, records an aggregate
contribution and marks finer attribution unavailable rather than inventing one.

Tests that enabling collection leaves the parent trajectory bitwise unchanged,
and that existing process-record configuration and diagnostic semantics are
untouched.

### PR 4 — Boundaries and reservoir transfers

Records the atmospheric and slab legs of each exchange under one event identity:
radiation, turbulent surface exchange, precipitation deposition, slab Q-flux,
and prescribed boundaries. Adds global transport boundary accounting, or the
proven-global-zero test where the operator has that invariant.

Avoids double-counting the atmospheric tendency, the boundary flux, and the
surface state change. Tests the atmosphere-only and coupled projections, and
preserves any implemented coupling mismatch instead of forcing cancellation.

**[sharpened]** The specific mismatch to look for is known from PR 1. The
atmospheric precipitation sink is in `microphysics_tendency!` while the surface
gain is in `surface_precipitation_tendency!`, and depending on
`microphysics_tendency_timestepping` the two are called from different channels.
Whether they carry the same amount is a measurement this PR makes, and the
coupled-view cancellation claim is blocked until it does.

### PR 5 — Implicit and post-implicit accounting

A method-specific adapter for `IMEXAlgorithm(ARS343, NewtonsMethod)`. Collects
converged-stage contributions with the coefficients the accepted solution used,
preferring a side channel over data already computed by the solve. Records
`correct_implicit_advection_tendency!` as its own leg, never folded into the
implicit terms.

Derives the algebraic solve defect independently from the integrator's residual
equations.

**[revised]** The nonlinear-tolerance sweep is replaced by an iteration sweep.
The default is `NewtonsMethod(max_iters = 1)` against
`ManualSparseJacobian(approximate_solve_iters = 1)`, so there is no tolerance to
tighten and the stage is not converged. Two consequences the earlier plans
missed:

 1. `Q_solve_defect` is a **leading-order term**, not a small correction. The
    identity cannot close without it in any implicit configuration.
 2. The test sweeps `max_iters ∈ {1, 2, 4}` and `approximate_solve_iters`, and
    requires `Q_solve_defect` to shrink with the measured stage residual while
    `R_bookkeeping` stays at arithmetic level throughout.

If prognostic record fields ever enter the implicit solve, their complete
cross-Jacobian coupling must be correct first, and a fallback identity block is
not sufficient. Until then they stay out of it.

**Open, and the first thing this PR settles:** whether the accepted-solution
weights are readable from the `ClimaTimeSteppers` cache without re-evaluating a
stage. If they are not, this PR reports aggregate closure and says so, rather
than assuming a textbook tableau.

### PR 6 — Numerical corrections and discrete maps

Covers the limiters, `enforce_mass_energy_consistency!`, the vertical mass
borrowing limiter, `dss!`, and each of the four `constrain_state!` steps, each
measured from the same ordered before-and-after authoritative state pair.

Distinguishes accepted-state maps from temporary-stage modifiers. Covers the
prescribed-flow overwrite as a prescribed map, never as a physical tendency.
Defines the restart transition as a zero-duration transaction of its own, so
restart repair is never charged to the next timestep.

Classifies every entry as numerical or prescribed. A correction that changes
water while leaving the stored energy variable unchanged records an energy
component of zero and a physical-inconsistency note. It does not get an invented
energy contribution.

**[added]** `dss!` is in scope. Weighted DSS is conservative in exact arithmetic
on a closed sphere but not bitwise, so its leg is measured and its expected size
is reduction level. A `dss!` leg above that is a finding.

### PR 7 — Integrated verification and the supported closure claim

Replaces the skipped placeholders in `test/conservation/mass_conservation.jl`
and `test/conservation/energy_conservation.jl` with real timestepper tests.

Covers per-step and cumulative reconciliation across dry, moist, phase-change,
precipitating, surface-coupled, forced, implicit, correction, and mixed-process
cases; restart; CPU against GPU; serial against MPI; and energy-reference
covariance.

Compares the ledger against `check_conservation` as an independent cross-check,
while treating that check as a cross-check only. The contract lists four
specific reasons it is not authoritative, including that its boundary term is
`dt` times one sampled radiative flux and that it omits turbulent surface fluxes
entirely.

Publishes the supported-configuration list, the tolerance model, the residuals,
and the limitations register.

**[added]** Two trajectory-invariance tests, because "the ledger is not a fixer"
has to be checkable: the ledger off must match a build without the feature, and
the ledger on must match the ledger off, both bitwise.

**[corrected]** The dry-mass invariant is `D = M − W`, as the original plan
said. An earlier revision of this page claimed otherwise, on the reading that
`ρ` excludes precipitating water. It does not: `ρq_tot` already contains rain
and snow, `ρ` tracks `ρq_tot` on every path that changes it, and `M − W` and
`∫(ρ − ρq_tot)` are the same number. The correction is recorded rather than
quietly removed, because the wrong version was used to justify a wrong `W`.

## Acceptance criteria

Meta Step 1 is complete only when all of the following hold.

  - Every authoritative accepted-state mutation in each supported configuration
    has exactly one disposition.
  - Temporary-stage changes are distinguished from accepted-state increments,
    and nothing is booked twice.
  - Every `(M, W, E)` component is `measured`, `zero`, `n/a`, or an explicit
    `unknown`, and an `unknown` blocks the claim it affects.
  - Exact per-process attribution is claimed only where the functional is linear
    and the update algebra makes it well defined.
  - Contributions use the accepted stages, weights, and split order.
  - Rejected attempts commit nothing, which at fixed step means the assertion
    that none occurred.
  - Reservoir legs are recorded once and net transfers are derived.
  - Internal cancellations are measured, never imposed.
  - Numerical corrections and the independently derived solve defect stay
    visible.
  - Signed per-step and cumulative residuals are reported separately for `M`,
    `W`, and `E`, never normalized by a signed total.
  - Energy-reference covariance holds under the documented admissible shifts, or
    the failing shift is reported as a finding.
  - Residuals meet the declared arithmetic, reduction, and solver-defect model.
  - The ledger changes neither the trajectory nor solver convergence, tested
    bitwise.
  - Existing process-record semantics remain backward compatible.
  - The documentation limits the claim to the implemented discrete system in the
    named configurations.

## Summary of revisions to the earlier plans

| Change                                                         | Reason                                                                         |
|:-------------------------------------------------------------- |:------------------------------------------------------------------------------ |
| Base is `main` once PR 40 merged, not PR 41 or a branch        | PRs 41-47 were closed unmerged until PR 40 carried them to `main`              |
| Rejection and adaptivity machinery reduced to an assertion     | fixed-step IMEX with no controller never rejects                               |
| Nonlinear-tolerance sweep replaced by an iteration sweep       | `max_iters = 1` leaves no tolerance to tighten                                 |
| Solve defect promoted to a leading-order term                  | one Newton iteration against an approximate Jacobian                           |
| `Yₜ_lim` added as a first-class channel                        | horizontal tracer advection and tracer hyperdiffusion live only there          |
| `D = M − W` stands, as originally written                      | `ρq_tot` contains rain and snow and `ρ` tracks it, so the two forms are equal  |
| `W = ∫ρq_tot` alone, no category added                         | `q_liq = q_lcl + q_rai` and `q_ice = q_icl + q_sno` in the thermodynamic state |
| Reservoir graph reduced to atmosphere plus one slab            | no prognostic snow, soil, or deposited-condensate state exists                 |
| `Y.sfc.water` owns mass as well as water                       | what it gains left the atmosphere as `ρq_tot` and so also as `ρ`               |
| EDMF, chemistry, and prescribed flow excluded from the claim   | their control-volume membership is a modelling question                        |
| Reduction cost made a design constraint, ledger off by default | four stages times dozens of legs is a hundred reductions per step              |
| `dss!` added to the mutation matrix                            | it mutates authoritative state                                                 |
| `b` in `E* = E + aM + bW` left open, not set to zero           | `enforce_mass_energy_consistency!` makes it a real question                    |
| Four named defects in `check_conservation` recorded            | so the ledger does not inherit them                                            |
