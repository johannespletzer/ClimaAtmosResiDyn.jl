# Closure memo: what the code does and what floating-point closure would cost

This memo records the assessment behind the decision to keep the calibrated
`κ` tolerance model. It is a snapshot. Line numbers refer to `main` at
`a54ce31` and to the stack tip at `f8ceaac`, the head of the reporting step
when the assessment was made; the function names are the stable anchors. The
work that follows from it is in [closure_plan.md](closure_plan.md).

Nothing was run for this memo. The numbers come from the last completed CI
run of the `parent_budget` group on the stack at that time, job
`ci 1.11 - ubuntu-latest - parent_budget` on head `6e294d7`, which passed
94 of 94 tests. Between that head and `f8ceaac` only comments, a walltime
log line, a guard around the report write and CI wiring changed. No Float32
run existed.

"Closure" here is parent-budget closure: for each of mass `M`, total water
`W` and total energy `E`, the endpoint change of the global integral equals
the sum of recorded accepted contributions and transfers, within a declared
tolerance. Tag closure and the turbulence closures are out of scope.
"Floating-point closure" has four readings, treated apart below: (A) bitwise,
`R === 0`; (B) a provable arithmetic level, `κ` derived from the reduction;
(C) closure of the equations, the implicit solve defect at rounding level;
(D) closure for the float type the model runs by default, `Float32`.

## Part 1. Current handling

### Implementation by quantity

| Aspect           | `main`: `check_conservation` in `src/simulation/solve.jl`                                                                                                                                                    | Tip: the ledger in `src/parent_budget/`                                                                                                                                                        |
|:---------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Measures         | `sum(sol.u[end].c.X) - sum(sol.u[1].c.X)` for `ρ`, `ρq_tot`, `ρe_tot`, first and last saved state only (lines 216 to 265)                                                                                    | Per accepted step: the endpoint change from `Fields.local_sum` of the widened field (`integrals.jl` 111 to 112), reduced once (`reduction.jl` 364 to 373, `integrals.jl` 161 to 168)           |
| Compares against | `E`: the radiative flux the callback accumulated as `dt` times one sample (`callbacks.jl` 32 to 49); `M`, `W`: slab water change only. No reference for a non-slab `M` or `W`.                               | Envelopes, the tableau-weighted stage tendencies read from the stepper cache `T_exp`, `T_lim`, `T_imp` (`adapter.jl` 1653 to 1694), plus the final maps (`transaction.jl` 1497 to 1510)        |
| Precision        | The state type. The default `FLOAT_TYPE` is `Float32` (`default_config.yml` 144 to 146), so the sums and the difference are `Float32`.                                                                       | `Float64` always (`integrals.jl` 35), converted before accumulation (`integrals.jl` 111 to 112, `reduction.jl` 294), tested for a `Float32` state (`endpoint_tests.jl` 305 to 318, 408 to 429) |
| Omits            | Turbulent surface fluxes and precipitation for a non-slab surface (`contract.md` 784 to 798, `callbacks.jl` 26 to 27); the sphere cross-check confirms these are its residual (`report_tests.jl` 319 to 325) | Nothing declared, per step. Summary mode blocks attribution and transfer by name (`report_tests.jl` 201 to 209). Rows without a `κ` row are blocked: GPU, more than one rank, `Float32`        |
| On a miss        | Returns three ratios normalised by a signed total. A verdict exists only in `.buildkite/ci_driver.jl` 185 to 187 (`atol = 100 eps(FT)` and `250 eps(FT)`). Off by default (`default_config.yml` 363 to 365). | Status `:fail` in the commit (`transaction.jl` 407 to 412) and in `parent_budget_report.yaml` (`report.jl` 41 to 51); the summary is logged. The run still returns `:success`.                 |

`M`, `W` and `E` go through the same code on both sides; only the reference
terms differ. `E` gets radiation on `main`, and `W` is `:not_applicable` in
dry runs (`transaction.jl` 408).

### The tolerance as evaluated on the tip

  - Code: `τ = absolute + relative·scale + kappa·eps(FT)·(|Bⁿ| + |Bⁿ⁺¹| + Σ|Q|)`
    in `tolerance_value` (`transaction.jl` 380 to 389). `FT` is the
    tolerance's type, which the adapter fixes at `BUDGET_ACCOUNTING_TYPE`,
    `Float64`. So `ε_acc = ε₆₄` whatever the state type. This agrees with the
    contract's "Tolerance model".
  - `Σ|Q|` is `projected.magnitude` (`transaction.jl` 1537 to 1542), built
    from the arithmetic magnitudes measured beside each amount. This agrees
    with the contract.
  - Row lookup: (device type name, state float type name, `nprocs`) in
    `calibration_row` and `calibrated_tolerances`. A table row gives
    `absolute = relative = 0`, `scale = 1` and the row's `κ`. A caller's
    `parent_budget_tolerances` wins. No row means `tolerances = nothing` and
    `tolerance_source = :none`.
  - Verdict order: `not_applicable`, `blocked` (missing evidence or missing
    tolerance), `fail`, `pass` (`transaction.jl` 407 to 412, 1481 to 1487).
    `max|Rₙ|` and `Σ|Rₙ|` are kept and written; pass or fail is per step on
    `|Rₙ|` alone. This agrees with "Which aggregates decide closure quality".
  - Findings. (1) `vocabulary.md` line 56 asks whether each total changed
    "by exactly what the accepted updates say" while the contract refuses
    the word "exact". (2) A `:fail` is silent at run level: the certificate
    carries it, nothing logs at warn level, the return code is unchanged.
    (3) `read_calibration_table` enforces `κ ≥ 4 · worst_ratio` but not that
    a row's `steps` equals `CALIBRATION_STEPS`; only the test does.

### Numbers

| Run in the CI log, head `6e294d7`                                                   | `M`: last `Rₙ`, then `Σ` of the absolute values | `W`               | `E`                  |
|:----------------------------------------------------------------------------------- |:----------------------------------------------- |:----------------- |:-------------------- |
| Column certificate, dry, `Float64`, summary mode, 4 steps                           | -4.39e-14 kg, 1.06e-12 kg                       | not applicable    | 9.00e-9 J, 9.00e-8 J |
| Sphere cross-check, moist, `Float64`, audit mode, 12 steps, `h_elem` 4, `z_elem` 10 | 2460.46 kg, 20792 kg                            | 4.84 kg, 56.15 kg | 1.36e7 J, 3.46e8 J   |

The log prints no ratio, no `κ`, no `max|Rₙ|` and no tolerance, so the
reporting step's "worst ratio 0.13" on the sphere cannot be checked from CI;
the test asserts only that the ratio is at most `κ/4 = 2`. The committed row
is worst ratio 1.3834, `κ = 8`, 50 steps, and it is re-measured on every CI
run. As an estimate only: with an Earth-radius sphere `B_M ≈ 5e18 kg`,
`ε₆₄ · B_M ≈ 1e3 kg`, so 2460 kg is of order one to two `ε₆₄ · B`, which is
the arithmetic level.

### Named tests versus present tests

The tip has these test files under `test/parent_budget/`: endpoint, envelope,
explicit_attribution, implicit_attribution, journal, reduction, registry,
report, restart_ledger, transfer. The registry and `coverage.md` agree cell by
cell.

| Named file              | Covered elsewhere?                                                                                                                                                                                                                                                                                                                                                         |
|:----------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `final_map_tests.jl`    | Partly. Final-map legs exist for `lim!`, `dss!` and `constrain_state!` on a column (`implicit_attribution_tests.jl` 99 to 117); DSS is declared measured (`registry_tests.jl` 214 to 220); the sphere run passes with DSS active. Nobody asserts the DSS amount against the reduction scale, the limiter pairs, or the field-write inventories.                            |
| `scope_tests.jl`        | Yes: refusal at setup for EDMFX, prescribed flow, chemistry and 2M (`registry_tests.jl` 146 to 164, `envelope_tests.jl` 93).                                                                                                                                                                                                                                               |
| `solve_defect_tests.jl` | Mostly: the sweep in `implicit_attribution_tests.jl` 225 to 247 over `(max_iters, approximate_solve_iters)` in `{(1,1), (3,1), (1,2)}` asserts that the defect shrinks and that the parent passes. It does not assert that the parent ratio stays at arithmetic level: it runs under a provisional `κ = 64`, not the calibrated 8, and never reads `residual / tolerance`. |
| `calibration_tests.jl`  | Yes: `report_tests.jl` 62 to 103 and 142 to 165.                                                                                                                                                                                                                                                                                                                           |

## Part 2. What each reading would require

**(A) Bitwise, `R === 0`.** This needs exact accumulation of both endpoints
and every leg, then an exact subtraction. With legs read from `Yₜ` it is
unreachable: the state update `Y += dt Σ b T` rounds per cell in the state
type before the ledger sees `Y`, so `Σ ΔY ≠ Σ dt b T` however the sums are
done. Reading the applied update as the per-cell difference `Yⁿ⁺¹ − Yⁿ` and
summing it with the same exact accumulator gives `R === 0` identically, but
then both sides read the same array and the identity is a tautology. That
contradicts the contract's rule that the endpoint reading "shares no
arithmetic" with the ledger, drops claim level 2, and cannot detect a
state-writing callback as an unaccounted transfer. It raises no claim level,
adds no state and no collectives, and leaves the trajectory unchanged. It is
not compatible with the contract as written.

**(B) A provable `κ`.** The residual has two sources of rounding: the
ledger's reductions, which can be fixed, and the model's own state-update
rounding, which the ledger cannot fix. For the first:

  - A fixed-order tree within a rank replaces `Fields.local_sum`, a mapreduce
    whose order differs between a serial CPU and a CUDA block reduction, with
    a pairwise sum in a fixed element order. Cost: a custom kernel;
    `κ_local ≤ log₂(N) · ε` analytically.
  - Compensated (Neumaier) accumulation gives a relative error of `2ε` plus
    `O(N ε²)` per slot, order-independent to that level. Cost: two `Float64`
    per slot in the packet and two to four times the reduction arithmetic.
    `reduce_accounting_sums!` stays one `allreduce!`, but `MPI_SUM` on a
    (sum, compensation) pair needs a custom operation, and MPI's reduction
    order is not fixed across rank counts, so the cross-rank `κ` stays
    empirical unless the packet is gathered and summed in rank order.
  - Exact accumulators (a Kulisch long accumulator, or error-free transforms)
    make the reduction integer addition, order- and rank-count-independent,
    with `κ_reduction = 1`. Cost: about 67 `UInt64` words per slot for a
    `Float64` long accumulator, a custom MPI operation with carries, and no
    GPU-native path in ClimaCore.

Even with exact reductions the state-update rounding remains. Per cell it is
at most `ε₆₄ |y|` per rounding, summed at most `ε₆₄ ∫|y|` per rounding, so a
provable bound is `κ` of the order of the number of roundings per cell along
the pinned ARS343 update path, about 10 as a worst case, against the measured
1.38. (B) turns `κ` from a measurement into a derivation for the reduction
part only. The claim level is unchanged, the packet doubles or grows about
67 times, one collective survives only with a custom operation, and the
trajectory is unchanged.

**(C) Converging the implicit stage.** `max_iters > 1` changes every implicit
trajectory, so every implicit reproducibility reference moves and the
reference counter must be bumped. Each extra Newton iteration costs one
implicit tendency evaluation and one Jacobian solve per implicit stage, so
the implicit stages cost roughly `max_iters` times more. With
`ManualSparseJacobian(approximate_solve_iters = 1)` convergence is linear and
the defect never reaches rounding level. This is a change to the model, which
the ledger's "not a fixer" rule forbids, and it does not change the ledger
identity: the defect is already booked with weight `−b/γ`, and the parent
residual already sits at arithmetic level with the defect present. The
cheaper improvement is the missing ratio assertion in the sweep, so that the
contract's "arithmetic level throughout" is tested rather than asserted. That
strengthens claim level 2 with no new state, no collectives and no change to
the trajectory.

**(D) The `Float32` default.** A default run is blocked today: the table has
no `Float32` row, `calibrated_tolerances(ctx, Float32) === nothing`, the
lookup uses `Spaces.undertype(axes(Y.c))`, so `tolerance_source = :none` and
every parent verdict is `:blocked` with `UNCALIBRATED_TOLERANCE_BLOCKER`. An
`ε₆₄` term cannot bound a `Float32` residual. The endpoints are `Float32`
values summed in `Float64`, but the update was applied in `Float32`, so `ΔB`
carries rounding of order `ε₃₂ · B / √N` to `ε₃₂ · B`, while the term is
`ε₆₄ · 2B`. If the residual is dominated by state rounding the worst ratio is
about `(ε₃₂ / ε₆₄) · f = 2²⁹ · f` with `f` between `1/√N` and 1, so a
`Float32` row would come out at `κ` between about `2²⁶` and `2³¹`. That is an
estimate, not a measurement. Such a `κ` is a legal table entry, but the
tolerance then equals `ε₃₂ · B`, which no longer resolves a missing leg below
about `1e-7` of the total. A meaningful `Float32` verdict needs a formula
change: add `κ_state · ε_state · (|Bⁿ| + |Bⁿ⁺¹|)` with `ε_state` the epsilon
of the state type, calibrate `κ_state` separately, and keep `κ · ε_acc` for
the reduction. This changes the contract's tolerance section,
`BudgetTolerance`, `tolerance_value`, the table schema and the certificate.
It adds no collectives, changes no trajectory, and is what lets level 1 be
certified at all for the default float type.

## Part 3. Is it worth it

The ledger exists to certify claim levels 1 to 4 for the accepted discrete
update and to detect an unaccounted transfer above tolerance. The measured
serial ratio 1.38 and the column and sphere residuals show that level 1
already holds at arithmetic level in `Float64`, and the envelope test shows
the tolerance is far below the smallest leg (`envelope_tests.jl` 169 to 172:
the envelope exceeds `1e3 · ε · |ΔB|`).

| Path                                                                    | Gain toward the purpose                                         | Cost                                                                                           | Verdict                                                       |
|:----------------------------------------------------------------------- |:--------------------------------------------------------------- |:---------------------------------------------------------------------------------------------- |:------------------------------------------------------------- |
| Keep the model, add rows (GPU, ranks, `Float32` with an `ε_state` term) | Unblocks verdicts on the backends and float type the model runs | A calibration run per row; one formula term for `Float32`                                      | Do this                                                       |
| (B) alone                                                               | `κ_reduction` derived, not measured; cross-rank stability       | Packet growth, custom MPI operation, GPU kernel; state rounding still calibrated               | Not now; revisit if a rank-count row measures a ratio above 8 |
| (D) alone, a `Float32` row without `ε_state`                            | A legal row with `κ` about `2²⁶` to `2³¹`                       | Tolerance becomes `ε₃₂ · B`; level 1 certified but blind below about `1e-7` of `B`             | No, add the `ε_state` term instead                            |
| (C)                                                                     | A smaller booked defect                                         | Trajectory change, reference bumps, two to three times the implicit cost; breaks "not a fixer" | No; add the ratio assertion to the sweep instead              |
| (A)                                                                     | None, a tautology                                               | Breaks the no-shared-arithmetic rule and drops level 2                                         | No                                                            |

Recommendation, the same for `M`, `W` and `E` because the formula scales per
quantity and the protocol calibrates all three in one run: keep the
calibrated-`κ` model, add the `ε_state` term and a `Float32` row, add GPU and
multi-rank rows where they run, make the solve-defect sweep assert the ratio
under the calibrated `κ`, and log a `:fail` at warn level. Confidence is
medium-high for `Float64` and medium for the `Float32` estimate, which rests
on state rounding dominating. The one measurement that would change this is
the column calibration run at `Float32` with `κ = 1`. A worst ratio below
about 100 means a plain `Float32` row suffices and the `ε_state` term is
unnecessary. A ratio near `2²⁶` or above confirms the formula change. A
multi-rank row with a ratio above 8 would move (B) up the list.
