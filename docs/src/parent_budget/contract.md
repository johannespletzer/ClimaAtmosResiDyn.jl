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

  - Dry, `EquilibriumMicrophysics0M`, and non-equilibrium/one-moment moist
    microphysics on the sphere and in a single column.
  - `diff_mode` explicit and implicit.
  - `microphysics_tendency_timestepping` explicit and implicit.
  - Surface: every prescribed or diagnosed surface temperature, and
    `SurfaceConditions.SlabOceanTemperature`.
  - Radiation off, `HeldSuarezForcing`, and RRTMGP.

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
records one correction leg per firing.

## Reservoir graph

The graph is much smaller than a coupled land–ocean model's, and saying so
precisely is part of the contract.

| Reservoir    | State         | Owns          | Exists when                              |
|:------------ |:------------- |:------------- |:---------------------------------------- |
| Atmosphere   | `Y.c`, `Y.f`  | `M`, `W`, `E` | always                                   |
| Slab surface | `Y.sfc.T`     | `E`           | `SlabOceanTemperature`                   |
| Slab surface | `Y.sfc.water` | `W`           | `SlabOceanTemperature` and a moist model |
| Exterior     | none          | —             | always                                   |

There is **no** prognostic snow, soil-water, or deposited-condensate reservoir,
and no wave-energy reservoir. Every other surface is prescribed or diagnosed
and is therefore exterior, not a reservoir: its state is not owned by the model,
so a flux into it is a boundary crossing and not an internal transfer.

`Y.sfc.water` is a water reservoir that owns **no mass leg**. Water deposited on
the slab leaves `M` and enters `W`. The two budgets must therefore record
different things for one physical event, which is the clearest case in this
model of the rule that a water increment may not be copied into mass.

## Authoritative integrals

For the atmosphere, over the global domain:

```
M = ∫ ρ                                  [kg]
W = ∫ (ρq_tot + ρq_rai + ρq_sno)         [kg]
E = ∫ ρe_tot                             [J]
```

For the slab surface, as a horizontal integral at the boundary:

```
W_sfc = ∫_sfc  sfc.water                                    [kg]
E_sfc = ∫_sfc  sfc.T · ρ_ocean · cp_ocean · depth_ocean      [J]
```

### What is and is not in each

**`M` excludes precipitating water.** `Y.c.ρ` is moist air density carrying
vapour and cloud condensate but not rain or snow. Every tendency that changes
`ρq_tot` changes `ρ` by the same amount, and nothing adds `ρq_rai` or `ρq_sno`
to `ρ`. Precipitation formation is therefore a genuine mass sink for the
atmosphere while being internal to the water budget.

That has a direct consequence the earlier plan got wrong. `D = M − W` is **not**
the dry-air mass in this model. The dry-air invariant is

```
D = ∫ (ρ − ρq_tot)                       [kg]
```

which is what the tests will use.

**`W` must not double-count.** `ρq_lcl` and `ρq_icl` are cloud liquid and ice
*contents already inside* `ρq_tot`. Adding them would double-count the
condensate. `ρq_rai` and `ρq_sno` are outside `ρq_tot` and must be added. The
included set by microphysics model:

| Model                             | `W`                        |
|:--------------------------------- |:-------------------------- |
| `DryModel`                        | not applicable             |
| `EquilibriumMicrophysics0M`       | `ρq_tot`                   |
| non-equilibrium, no precipitation | `ρq_tot`                   |
| one-moment                        | `ρq_tot + ρq_rai + ρq_sno` |

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
precipitation fallout and surface deposition, is exactly what the audit tests.
The audit is a check on the implemented model. It is not permission to invent a
carrier-energy term that the model does not have.

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

Reported per step and cumulatively: endpoint change, sum of entries, solve
defect, bookkeeping residual, the discrepancy before the solve defect is
included, and the cumulative ledger against the independent run-segment
difference `B^N − B^0`.

## Tolerance model

Four sources are budgeted separately, because they scale differently and
conflating them is how a real defect gets absorbed.

| Source                              | Expectation                                           |
|:----------------------------------- |:----------------------------------------------------- |
| Local arithmetic and reconstruction | `O(ε)` relative to `Σ\                                |
| Parallel reduction order            | grows with rank count; measured, not promised bitwise |
| Algebraic solve defect              | **leading order, not small** — see below              |
| Approximate collection              | none; the ledger has no intentionally approximate leg |

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

Residuals are always reported as signed absolute values in `kg` and `J`. A
relative view may be added against a documented positive scale such as
`Σ|contribution|`. Normalizing by signed total energy is forbidden, which is
one of the defects in the existing check described below.

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
 3. **Which surface states own what?** `Y.sfc.T` owns energy, `Y.sfc.water`
    owns water, neither owns mass, and only `SlabOceanTemperature` has them.
 4. **Are coupled legs derived from one amount or discretized independently?**
    Mixed, and this is a **blocker for the coupled-view cancellation claim
    until measured**. `surface_precipitation_tendency!` is called from both
    `remaining_tendency!` and `implicit_tendency!` depending on
    `microphysics_tendency_timestepping`, while the atmospheric sink is in the
    microphysics tendency. Whether the two are the same amount is a
    measurement, and PR 4 makes it one.
 5. **Which energy-reference transformations are admissible?** `a ≠ 0` yes.
    `b` open, pending the covariance audit, for the reason given above.
 6. **Can included mutations be rolled back on a rejected attempt?** The
    question does not arise in a supported configuration, because fixed-step
    IMEX never rejects. Guarded by an assertion rather than an implementation.
 7. **Which water categories are included without overlap?** `ρq_tot`,
    `ρq_rai`, `ρq_sno`. Never `ρq_lcl` or `ρq_icl`.

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
  - The process record covers only the explicitly bracketed tendency path. Its
    bracket set is not the ledger's coverage set.
