# Closure plan: the calibrated `κ` model, `Float32`, and the remaining rows

This page turns the recommendation of [closure_memo.md](closure_memo.md)
into work items with their edit points, acceptance tests and approvals, so
the work can be resumed without repeating the assessment.

## Decision

The tolerance model stays as the contract defines it: a calibrated `κ` on an
arithmetic term, never a derived or an exact one. Readings (A), (B) and (C)
of the memo are not pursued, for the reasons given there. The work below adds
what the model lacks for the float type and the backends the model runs on,
and it makes two claims that are currently asserted into tested ones.

## Status of this page

This page and the memo are the framework. Of the six items below only W5,
the warn-level log, is implemented. Nothing here changes a tolerance, a
table row or a trajectory. Every item that does is marked as needing the
owner's approval, following the agent autonomy rules of the developer
guides.

## Work items

| Id | Item                                     | Changes                                                | Approval needed                    |
|:-- |:---------------------------------------- |:------------------------------------------------------ |:---------------------------------- |
| W1 | The `ε_state` term in the tolerance      | Contract, `BudgetTolerance`, table schema, certificate | Yes, a formula and contract change |
| W2 | A `Float32` row, after one measurement   | `kappa_calibration.yaml`, one test                     | Yes, a calibrated artifact         |
| W3 | GPU and multi-rank rows                  | `kappa_calibration.yaml`, run on Buildkite or Levante  | Yes, calibrated artifacts          |
| W4 | The solve-defect sweep asserts the ratio | `implicit_attribution_tests.jl`                        | No                                 |
| W5 | Log a `:fail` at warn level              | `report.jl`, `solve.jl`                                | No; done in this pull request      |
| W6 | Small findings from the memo             | `vocabulary.md`, `calibration.jl`, the summary         | No                                 |

### W1. The `ε_state` term

The formula becomes

```
τ_q = a_q + r_q · S_q
    + κ · ε_acc · (|B_qⁿ| + |B_qⁿ⁺¹| + Σ_k |Q_q,k|)
    + κ_state · ε_state · (|B_qⁿ| + |B_qⁿ⁺¹|)
```

with `ε_state` the epsilon of the state float type. For a `Float64` state
`ε_state = ε_acc`, and `κ_state = 0` reproduces today's `τ` exactly, so the
committed `Float64` row keeps its meaning and every existing test result
stays bit-identical. The term bounds the rounding the state update itself
carries, which the reduction's `ε_acc` term cannot see once the state is
`Float32`.

Edit points, at the stack tip:

  - `src/parent_budget/transaction.jl`: `struct BudgetTolerance{FT}` gains
    `kappa_state` and `state_eps`, both checked by `check_tolerance_field`,
    with the keyword constructor defaulting them to `0` and `eps(FT)`.
    `tolerance_value(tolerance, opening, closing, recorded_magnitude)` adds
    `kappa_state * state_eps * (abs(opening) + abs(closing))`. The docstring
    above it states the formula; update it and the formula in the contract's
    "Tolerance model" together.
  - `src/parent_budget/calibration.jl`: `CalibrationRow` gains `kappa_state`,
    optional in the file and `0` when absent so version 1 rows still load.
    `read_calibration_table` validates it like `kappa`: zero or a power of
    two. `calibrated_tolerances(context, float_type)` passes
    `kappa_state = row.kappa_state` and `state_eps = eps(float_type)`.
    `protocol_tolerances()` grows a second protocol, see W2.
  - `src/parent_budget/adapter.jl`, `build_parent_budget`: the state float
    type is already known there from `Spaces.undertype(axes(Y.c))`; nothing
    else changes.
  - `src/parent_budget/report.jl`, `tolerance_entry`: write `kappa_state`
    and `state_eps` beside `kappa`.
  - `src/parent_budget/kappa_calibration.yaml`: `version: 2`, and
    `kappa_state` on every row.
  - Docs: `contract.md` "Tolerance model" and "Calibrating `κ`",
    `architecture.md` where the tolerance is described, and a
    `vocabulary.md` entry for the state term.
  - Tests: the tolerance tests in `journal_tests.jl` gain a case with a
    nonzero `kappa_state`; the table tests in `report_tests.jl` (the
    hand-written bad tables around lines 92 to 101) gain the new key; the
    certificate test checks the new fields.

Acceptance: with `kappa_state = 0` the whole `parent_budget` and
`infrastructure` groups pass unchanged, and the certificate shows the two
new fields.

### W2. The `Float32` row

The measurement comes first, because it is the one the memo names as able to
change the recommendation. Run the protocol column at `Float32`: take
`calibration_configuration()` with `"FLOAT_TYPE" => "Float32"`, step it
`CALIBRATION_STEPS` times under `protocol_tolerances()` (`κ = 1`,
`κ_state = 0`), and read `worst_parent_ratio` of the last commit. The testset
"The serial row is re-measured" in `report_tests.jl` is the template; a copy
with the float type changed is the whole experiment.

Decision rule, from the memo:

  - A worst ratio below about 100: a plain `Float32` row suffices, with
    `kappa = kappa_from_ratio(ratio)` and `kappa_state = 0`. W1 becomes
    optional.
  - A worst ratio near `2²⁶` or above: state rounding dominates. Do W1, then
    calibrate `κ_state` with a second protocol run that fixes `κ = 8` (the
    reduction part, from the `Float64` row) and sets `κ_state = 1`, records
    the largest ratio of the residual to the state term alone, and fixes
    `κ_state` at four times it rounded up to a power of two. Record both
    ratios in the row.
  - Anything in between: report the ratio and decide with the owner; the
    formula change is still the safer path because it keeps the tolerance
    able to resolve a missing leg.

The row itself: backend `CPUSingleThreaded`, float type `Float32`, ranks 1,
configuration `parent_budget_calibration_column`, steps 50, the measured
ratio, the `κ` values, the commit and the date. Only the protocol run may
write the table.

Tests: `report_tests.jl` currently asserts that
`calibrated_tolerances(ctx, Float32)` is `nothing`; that assertion flips to
a row check, and a `Float32` re-measure testset is added beside the
`Float64` one. Its cost is one more 50-step column.

### W3. GPU and multi-rank rows

The lookup key is `(backend_name(context), float type name, nprocs)`, where
`backend_name` is the device type name: `CPUSingleThreaded`,
`CPUMultiThreaded` or `CUDADevice`. Two things to settle first:

  - `ClimaComms` selects `CPUMultiThreaded` whenever Julia runs with more
    than one thread and `CLIMACOMMS_DEVICE` is unset, so a developer running
    the tests threaded gets no row today. Decide whether `calibration_row`
    lets `CPUMultiThreaded` share the serial row (the reduction order within
    a rank does not depend on the thread count for `Fields.local_sum` on the
    CPU, but that is a claim to check) or whether it gets its own row.
  - Which rank counts matter: the ones the production configurations use.
    `runscripts/README.md` describes the node layout on Levante.

Where they run: this fork's CI is GitHub Actions on CPU, so GPU and MPI rows
need Buildkite upstream or Levante. The protocol is the same on every
backend: the calibration column, 50 steps, `protocol_tolerances()`, record
`worst_parent_ratio`, add the row. Until a row exists such a run is blocked
by name, which is the intended behavior. A rank-count row with a ratio above
8 is the signal that would make reading (B) of the memo worth revisiting.

### W4. The solve-defect sweep asserts the ratio

The testset "The solve defect shrinks when the solve converges" in
`implicit_attribution_tests.jl` runs under the provisional tolerances
(`κ = 64`) and asserts only that the parent passes. The contract's claim is
stronger: the parent residual stays at arithmetic level while the defect
shrinks with `max_iters`. To test it:

  - Build the sweep simulations without `parent_budget_tolerances`, so the
    calibrated row applies (`tolerance_source === :calibration_table`).
  - For each `(max_iters, approximate_solve_iters)` and each of mass and
    energy, read the parent row and assert
    `abs(row.residual) / row.tolerance ≤ 1`; collect the ratios.
  - Assert the largest ratio over the sweep is at most 1, and log the ratios
    with `@info` so the CI log carries the numbers the memo could not verify.

The dry column differs from the calibration column, so a failure here is
information rather than a bug in the test: either the serial row is not
representative of the dry column or the column's ratio exceeds 1. Whichever
it is, the contract's claim is then measured.

### W5. Log a `:fail` at warn level

Done in this pull request. `failed_claims(adapter)` in `report.jl` returns
one line per claim of the last accepted step whose status is `:fail`, and
`write_parent_budget_report` in `solve.jl` logs them with `@warn` after the
summary. The return code is unchanged: the ledger is a diagnostic and does
not decide whether a run succeeded. A test is still to be added: inject a
fault with `inject_fault!` on a short column and check the log with
`@test_logs`.

### W6. Small findings

  - `vocabulary.md` line 56 says the ledger asks whether each total changed
    "by exactly what the accepted updates say"; the contract refuses the
    word. Reword to "by what the accepted updates say, within the declared
    tolerance".
  - `read_calibration_table` does not check that a row's `steps` equals
    `CALIBRATION_STEPS`; only the test does. Move the check into the loader.
  - The summary and the certificate print residuals but not the ratio of
    residual to tolerance, so a CI log cannot show the margin. Add the ratio
    per parent row to `budget_summary`.

## Open decisions for the owner

  - Approve the W1 formula and the version 2 table schema.
  - Confirm the W2 decision thresholds, or replace them.
  - Decide whether `CPUMultiThreaded` shares the serial row (W3).
  - Decide whether a `:fail` should ever change the return code; today it
    does not, by design.

## How to resume

  - Branch `claude/parent-budget-9-closure-plan`, stacked on
    `claude/parent-budget-8-report` (PR #60); merge the stack below first.
  - Local checks: `.dev/preflight.sh` (parse, hygiene, links, identity
    shapes, the pinned formatter), then
    `TEST_GROUP=parent_budget julia +1.11 --project -e 'import Pkg; Pkg.test()'`
    and the `infrastructure` group when the registry or the page changes.
    The docs build is `julia --project=docs docs/make.jl`.
  - Every coverage-registry cell edit must be mirrored in `coverage.md`;
    `registry_tests.jl` holds the two to exact agreement.
  - The calibration protocol and its table are described in the contract
    under "Calibrating `κ`" and in `calibration.jl`; the re-measure testset
    in `report_tests.jl` is the executable form.
