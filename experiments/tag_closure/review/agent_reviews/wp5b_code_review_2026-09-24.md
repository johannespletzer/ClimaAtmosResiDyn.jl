# Review of #105 (WP5b) at 0aad20ee

By `clima-numerics-reviewer` at xhigh, 2026-09-24. Kept as it was returned, apart from
the indentation. The responses are at the end.


On the default solver (split `ManualSparseJacobian`), parity holds. I found no path there where the new blocks or the new rule change a model field. The cross block is the right derivative. The back-substitution solves the right system. What is wrong is the unsplit path, the tests, and several claims in the docs.

## Blocking

**B1. The unsplit solver no longer builds under PrognosticEDMFX with the SGS mass flux, 1M and water tags. The design says the opposite.**
- Mechanism:
  - The falling species' rows carry `(ρqₚ, f.u₃)` blocks (`manual_sparse_jacobian.jl:432`, `sgs_massflux_jacobian_blocks`).
  - The arrowhead preconditioner forms `A₂₂ − A₂₁ P₁₁⁻¹ A₁₂`. The new `(tag, ρqₚ)` blocks therefore create `(tag, f.u₃)`.
  - `velocity_alg` (`:570`) leaves `f.u₃` and the tags to a `BlockDiagonalSolve`, whose check rejects that block.
- Evidence (computed):
  - On the real DYCOMS EDMF 1M column with 2 tags, `jacobian_cache(...; split_uncoupled_fields = false)` fails. The error: `BlockDiagonalSolve cannot be used because A has entries at the following off-diagonal keys: (@name(c.ρq_tag_tropo), @name(f.u₃)) and (@name(c.ρq_tag_strat), @name(f.u₃))`.
  - The same script against the control worktree at `f8da0913` (no cross blocks) builds a `FieldMatrixWithSolver`. Both took about 460 s.
  - The synthetic column reproduces the failure only when the species has a `u₃` block.
- Consequence:
  - `AutoSparseJacobian` always takes this path (`auto_sparse_jacobian.jl:103-107`).
  - So the shipped `config/model_configs/prognostic_edmfx_bomex_column_sparse_autodiff.yml` (PrognosticEDMFX, SGS mass flux, 1M) plus `water_tracers` built at #102 and crashes now.
  - The unsplit reference that the split was validated against (`energy_source_tags_integration.jl:269`) cannot be built for this case.
  - Design §3 and the `SplitJacobianSolver` docstring (`:797-801`) say this path is fine.
- This is not a parity break of the default solver. It does break a combination that worked before.
- Fix: allocate the tags' cross blocks only when the split will solve them. For example, pass `split_uncoupled_fields` into `sedimentation_jacobian_blocks`, or strip `(tag, species)` pairs in `build_unsplit_jacobian_solver`.
- Test: build the unsplit cache for PrognosticEDMFX with the SGS mass flux, 1M and tags. In the synthetic unit test, also compare split against unsplit with a `(ρq_rai, u₃)` block.

**B2 (pending). `tagged_water_increment_integration.jl` at 0aad20ee has not finished.**
- Job 13893926 is still on its first simulation.
- Section 2 (implicit path, now also with cross blocks) asserts `abs(left) > 0.5 * closure.gross_residual` (`:356`). This was calibrated before WP5b; the comment at `:351` ("with it, 4.1e-5") is stale.
- On the explicit probe the same ratio is |left|/gross = 2.12e-8 / 5.70e-8 = 0.37 (copies: 0.22). If the implicit path now behaves similarly, `:356` fails.
- Nothing in the WP5b test run covers `tagged_water_edmf_integration.jl`, `tagged_water_edmf_copies_integration.jl` (explicit 1M) or `tagged_water_integration.jl`. All three now get cross blocks.

## Should fix

**S1. The tests do not pin the cross block itself.**
- The unit test from design §4 ("the partition tags' cross blocks sum to the parent's") is missing.
- The integration closure under `increment` only sees the column total. The follower absorbs any error with zero column sum.
  - So a wrong interior row, a share taken at the receiving cell, or a missing species that never reaches the surface all pass the 1e-6 bound.
  - A wrong share placement is not small: my toy gives 12% for the receiving-cell version.
- What the 1e-6 bound does catch: the missing blocks (8.5e-3), a wrong sign (about 1.6e-2), and a missing `/ρ` (about 1e-3).
- `:450` checks only `!isempty(field.lower)`, not that `lower` covers all 4 species.
- Fix: a block-level test on a real column (Σ partition blocks = parent's `(ρq_tot, ρqₚ)` block; source tag = parent · Diag(φ)), plus `Set(first.(lower)) == Set(sedimenting masses)`. The ready script is `blocks_real.jl`, below.

**S2. The docs and records claim more than the code or the evidence shows.**
- "closes to rounding" (`test/tagged_water_increment_integration.jl:28`): the measured gross is 5.7e-8. The model's own closure check warns at its 1e-10 tolerance in the probe's `.err`.
- `docs/src/tagged_water.md:353` quotes the net 2e-8. The gross is 5.7e-8.
- FINDINGS W29 on the record branch:
  - "The model's fields are bit for bit the same": the probe compared 5 fields, and `ρq_sno` is identically 0. The full check is the pending §4.
  - "No tag goes negative": that is the final state after repair. The cumulative `ᶜwater_fix` ledger rose 1.84e-4 → 2.22e-4 (+21%) with the cross blocks (default mode, follower). This is unexplained.
- Stale docstrings and docs:
  - `jacobian_cache` (`:635`): "which gives the same result".
  - `SplitJacobianSolver` (`:790-791`): "have only their own diagonal blocks".
  - `tagged_water.md:215-218`: says only diagonal blocks.
  - `tagged_water.md:311`: says sedimentation has blocks the tags lack.
  - `test/runtests.jl:258`: "builds the EDMF column twice"; it is four now.
  - `docs/src/implicit_solver.md:102`: a 131-character unwrapped line.

**S3. The explicit-path default rests on one column, one hour.**
- The evidence: DYCOMS, ARS222, dt 120 s, 1 Newton iteration, Float64.
- My toy supports the mechanism: the remainder is second order and grows with CFL (per step: 2e-10 at CFL 3, 4e-9 at CFL 12, 1e-8 at CFL 24).
- D4-W, the next planned check, runs the implicit path only.
- Fix: run one explicit, heavier-precipitation or multi-day column before the default ships. Otherwise, state the evidence scope in the `default_water_tag_transport` docstring (`tracer_config.jl:1414-1430`).

## Minor and notes

- **N1. The 2e-8 remainder comes from the diagonal-only share derivative, not from rounding.**
  - In the toy (one iteration, CFL 12), the column mismatch / total is:
    - no cross blocks: +1.3e-3;
    - cross blocks plus the diagonal ∂φ̂/∂ρq_tag (WP5b): −3.6e-9;
    - cross blocks without that diagonal: −1.9e-16;
    - full Jacobian: −3.2e-16.
  - Per-cell accuracy is similar with and without the diagonal (1.0e-4 vs 9.5e-5 against the full solve), and positivity is the same. Dropping the diagonal would close the column exactly. Worth a line in the design.
- **N2. Memory.** Each tag adds 12 floats per cell under 1M (4 tridiagonal blocks). Since `C_tag = C_parent · Diag(φ̂)`, storing φ̂ alone (1 float per cell per tag) and computing `C_parent (φ̂ ΔYₚ)` would do the same. Matters for GCM or GPU with many tags.
- **N3. AutoSparseJacobian coloring.** The new blocks change the column-intersection graph, so the coloring, and through pollution from entries outside the pattern the model rows' values, can change. Parity is not claimed for this solver; this is beyond B1.
- **N4. The own-row branch compares with `!=`, not overlap (`:770`).** A column naming a parent chain of the tag, such as `@name(c)`, would be accepted. Not reachable today; use `!jacobian_name_chains_overlap`.
- **N5. Energy source tags on the explicit path.** They have no sedimentation cross blocks, nothing refuses `enthalpy_increment` there, and nothing measures them. The integration test never combines them with the explicit path.
- **N6. Probe record.**
  - `commit=?` in every RESULT line.
  - The evap tag's agreement with the copies got worse: 3.8% → 5.8% (follower) and 6.2% → 6.4% (tracer). The copies lack their own cross blocks.
- **N7. CI time.** The group now compiles 4 simulations, about 28 min on 1.11 at the documented 7 min each, against a 90-min job timeout.

## Checked by reading only

- The sign.
- `dtγ` is already folded into `B`.
- The `/ρ` matches `q = ρqₚ/ρ`.
- The share is inside `top_bias`, so it is taken at the donor cell, as in `sediment_water_tags!`.
- ∂φ̂/∂ρqₚ = 0 exactly, so the block is the exact derivative up to the ∂w term the parent also drops.
- `(ρq_tot, ρqₚ)` is written only by sedimentation (`:1305`).
- `sedimenting_mass_names` equals the species with a `condensate_phase` (`tracer_processes.jl:151,217`).
- `ᶠband_matrix_wvec` is written before every read and read by nothing after the tag loop.
- GPU: no scalar indexing, no run-time `Val`, and the heterogeneous tuples are resolved by recursion.
- Newton passes distinct `Δx` and `f` (ClimaTimeSteppers `newtons_method.jl:778-780`).
- The `BlockArrowheadSolve` branch is DryModel only, so unreachable here. 0M has no cross blocks. The dense autodiff Jacobian does not use the blocks.

## Computed by the reviewer

Scratch: `/dss/dsshome1/0D/di38kez/.claude/jobs/eb4ea50c/tmp/wp5b_review/`

- **`synthetic.jl`** (Julia):
  - The split's model increments are `isequal` with and without the cross block, for n_iters 1, 2, 3, with and without a species–`u₃` block.
  - The unsplit solve without a species–`u₃` block leaves the model bitwise unchanged, and its tag equals the split's (difference 0.0).
  - The unsplit solve with a species–`u₃` block fails to build (B1).
  - The split `ldiv!` with lower blocks allocates 0 bytes on the second call.
- **`fieldlists.jl`** (real models: explicit and implicit 1M, default mode and copies, with water, energy and energy-source tags, both records and the ledgers):
  - The uncoupled set is identical to the old rule applied without the cross blocks (14/14, 10/10, 14/14).
  - The only off-diagonal blocks in splittable rows are the 12 new ones. No row names a splittable column.
- **`unsplit_edmf.jl`**: fails at 0aad20ee and builds at `f8da0913` (B1).
- **`toy_newton.py` and `toy_newton2.py`** (numpy):
  - The back-substitution matches the dense solve to 2e-19.
  - The cross block equals the parent's block · Diag(φ) to 1.3e-13.
  - The closure variants and per-cell accuracy in N1.
- **`wp5b_compare.py`** rerun on the probe: gives the ratios in B2, the repair numbers in S2 and the evap numbers in N6.
- **Not run: `blocks_real.jl`**, about 40 min of compile. It covers S1 (block sums, `lower` coverage, the tag-row residual, allocations of `update_jacobian!` and `invert_jacobian!`, and the unsplit build). Command for a compute node:
  `JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu julia +1.11 --project=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3/wp5b/testenv /dss/dsshome1/0D/di38kez/.claude/jobs/eb4ea50c/tmp/wp5b_review/blocks_real.jl`

## Verdict

#105 should not leave draft yet. In this order:
1. Fix B1, keeping the cross blocks out of the unsplit and AutoSparseJacobian paths, and add its test.
2. Get job 13893926 green, recalibrating `:351` and `:356` if needed. Run the three untested 1M water-tag integration files.
3. Add the S1 block-level test.
4. Correct the S2 wording.

S3 can follow before the default ships.

## Responses

At `11b8d875`, then `c446fe91` to `801c52dd` with the owner's review of #105:
  - B1: the blocks exist only with the split (`water_tag_cross_flag`); the
    reviewer's `unsplit_edmf.jl` (kept as `analysis/water/wp5b_unsplit_build.jl`)
    builds at `11b8d875`; unit tests on the flags and blocks.
  - B2: the 4-build increment test at `0aad20ee` passed 109/109 (job
    `13893926`); `:356` holds (|left| 3.7e-7, gross 3.2e-8 relative); the
    stale comment is updated. The three 1M files pass at `11b8d875`
    (`tagged_water_integration`, `tagged_water_edmf_integration`; the copies
    file was still running).
  - S1: the explicit group checks the blocks and `lower` on the real column,
    and a unit test assembles the real blocks against finite differences.
  - S2: wording in the tests, docs, docstrings and W29.
  - S3: the default with 1M stepped explicitly is `tracer` again until
    WP5b-V; the docstring states the evidence's scope.
  - N1, N2, N3, N5: in the design note, section 6, and G4.15. N4: overlap.
  - N6: the probe's commits are in `output/wp5b_probe/EVIDENCE.md`.
  - N7: the explicit test is its own group.
