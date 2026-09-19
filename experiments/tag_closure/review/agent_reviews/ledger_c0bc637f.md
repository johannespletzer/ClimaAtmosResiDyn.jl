# Review of c0bc637f (enthalpy_increment and its ledger), details

Read-only review of `git diff origin/main...HEAD` in ../ClimaAtmosResiDyn-inc, with
extra care on `faa98974..c0bc637f`. No simulation was run. "Verified" means read
in the code at the cited lines, unless it says otherwise. Three checks did run
Julia, without ClimaAtmos:

  - a plain-array replica of test 1's arithmetic (B2);
  - the pinned JuliaFormatter 2.10.1, on copies of every changed file. It changed
    nothing, the test file included, so formatting is clean;
  - the D4 output (tag_closure/output/inc_d4_enthalpy_increment), read with
    netCDF4 to get the column's `ρe_tot`.

Abbreviations. EST = src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl.
TEST = test/energy_source_tags_increment_integration.jl. CTS = ClimaTimeSteppers
1.0.1 (packages/ClimaTimeSteppers/ZxgOv/src). ClimaCore = packages/ClimaCore/TKCzQ
(1.0.0, the version in .buildkite/Manifest-v1.11.toml).

## Findings by severity

| id | severity | where | what |
|----|----------|-------|------|
| B1 | blocking | EST:155,188,355,1669,1810; types.jl:2460 | 6 `@ref`s to docstrings no page renders, so the docs build fails |
| B2 | blocking | TEST:212-215 | the "moved" check's tolerance is below the rounding of `ρe_tot + δ`, so it fails |
| B3 | blocking (narrow) | integrator.jl:212-220; CTS imex_ark.jl:235 | the `-0.0` path changes the cache that `constrain_state!` and `lim!` read, so model fields move |
| S1 | should fix | utilities.jl:58; advection.jl:121; limited_tendencies.jl:88,133 | the ledger fields go through the `is_tracer_var` loops, and the records fix does not cover them |
| S2 | should fix | TEST | the ledger's main claim, the audit columns, the diagnostics and the restart check are untested |
| S3 | should fix | TEST:267-326 | the parity check is against `enthalpy`, not against a run without tags; the donor choice and the hook type are untested |
| S4 | should fix before G2 | EST:1702-1722 | the ledger records the intended move, not the actual one: deep atmosphere, and a donor with no share |
| S5 | risk, unverified | ci.yml, runtests.jl | 4 models, 2 of them EDMF, in one 90-minute job |
| N1-N9 | nit | various | docs, NEWS, docstrings, restart message, cost |

## B1 (blocking). The docs build fails on six `@ref`s

`docs/make.jl:37` runs `check_docstring_refs` before `makedocs`. It errors on
any `[`X`](@ref)` in any docstring whose target is in no `@docs` block
(`docs/check_docstring_refs.jl:83-101`). Documenter's own `:cross_references`
check is not in `warnonly` either (`make.jl:55-57`). The `@docs` block in
`docs/src/energy_source_tags.md:601-624` lists none of the new names. I
grep-checked every `docs/src/*.md`, and none of the four targets below is
rendered.

| docstring | line | target |
|-----------|------|--------|
| `energy_source_increment_ledger_variables` | EST:155 | `correct_energy_source_increment!` |
| `energy_source_increment_ledger_names` | EST:188 | `energy_source_increment_ledger_variables` |
| `energy_source_audit` (rendered) | EST:355 | `energy_source_increment_ledger_variables` |
| `correct_energy_source_increment!` | EST:1669 | `energy_source_increment_ledger_variables` |
| `energy_source_post_implicit` | EST:1810 | `EnergySourceIncrementCorrection` |
| `AbstractEnergySourceTransport` (rendered) | src/types.jl:2460 | `EnthalpyIncrementEnergySourceTransport` |

The last two came in with 35042f33/faa98974. The other four are new.

**Failure scenario.** The Documentation workflow runs on every pull request
(`docs.yml:8`) and stops at `check_docstring_refs` with "6 docstring
cross-reference(s) point at symbols that no documentation page renders".

**Fix.** Add `EnthalpyIncrementEnergySourceTransport`,
`energy_source_increment_ledger_variables`, `correct_energy_source_increment!`
and `EnergySourceIncrementCorrection` to the `@docs` block. It would also be
worth adding `follows_implicit_increment`, `snapshot_energy_source_increment!`,
`check_energy_source_increment_supported` and `energy_source_post_implicit`.
The other way is to write the targets as plain code.

## B2 (blocking). Test 1's "moved" check fails on rounding

TEST:212-215 compares `dtγ·dY.moved` with `δ - left_expected` to a tolerance
of `100·eps·max|δ| = 2.66e-12`. But the code's mismatch is not `δ`. It is
`m = fl(ρe_tot + δ) - ρe_tot = δ + ε`, with `|ε|` up to half an ulp of
`ρe_tot`. Verified at EST:1684-1690. The partition part is exactly 0, because
`P_U` and `P_snap` are the same sum in the same order. `ρ`'s part is `c·0.0`.

  - On the D4 column, `|ρe_tot|` lies between 42,100 and 52,000 J/m³ at every
    level and every hour. I derived it as `ρ·(e_src_strat + e_src_tropo +
    e_src_res - c)` from the output. The test's EDMF column is the same case
    after 1 h. So every cell is in the binade [2^15, 2^16), where half an ulp is
    3.64e-12.
  - The error of "moved" is `ε(1 - r·sign δ) - Δr·|δ|`, with `r ≈ 0.31`. In the
    13 cells where `δ < 0` (z = 825 to 1425 m), it reaches 1.31 × 3.64e-12 =
    4.8e-12, which is above the tolerance. The "left" check (TEST:208-211) has
    error `r·ε`, which is at most 1.1e-12, so it passes.
  - Plain-array replica (30 cells, J = 50, the test's `δ` and `dtγ`, `ρe_tot`
    uniform in [-5.2e4, -4.2e4]): the left check passed 10,000 of 10,000
    trials, and the moved check passed 0 of 10,000. With `|ρe_tot|` below
    32,768 both checks always pass.
  - Not confirmed by running TEST. Job 13504842 was still running when I wrote
    this. Its stdout is buffered: in `sphere_rec_inc-13504848.out` the "Test
    Failed" line only appeared at exit. So the missing failure line in its
    current output proves nothing.

**Fix.** Take the expected values from the increment that was actually
applied: `ᶜΔ = U.c.ρe_tot .- Y₀.c.ρe_tot`, which is exact by Sterbenz. Use it
for `ᶜleft`, the moved check and `δ_total`. In the replica, that passed 10,000
of 10,000 with the same tolerance. The other option is to scale the tolerance
with `eps·maximum(abs, ρe_tot)`, but that tests less.

## B3 (blocking for the rule, narrow). The `-0.0` path moves model fields when a constraint or limiter reads the cache

CTS calls `cache_imp!(U)` before any post-solve hook (imex_ark.jl:235). With
`energy_q_tot_upwinding: none`, upstream has no hook. So this refresh of the
implicit cache is new, and it happens on the solved state. The previous review
(F3) said everything else it writes is refilled before it is read. That is not
true in two cases, because CTS runs the constraint before the cache refresh:

  - **FSAL tableaux** (ARS222, the test's and D4's algorithm; `is_fsal`:
    `b = a[end, :]` on both sides, imex_tableaus.jl:59). At the last stage the
    post-Newton `constrain_state!`/`cache!` are skipped (:247). Then `step_u!`
    runs `lim!(temp, p, t_final, u)` (:87), `dss!`, `constrain_state!(u)`
    (:100, at the default `update_constrain_state_every: step`), and only then
    `cache!(u)` (:101). Upstream's `p.precomputed` there holds the last Newton
    iterate before its update: `solve_newton!` does not call `prepare_for_f!`
    after `x .-= Δx` (newtons_method.jl:798-806). The fork's holds the solved
    state.
  - **`update_constrain_state_every: stage` or `dss`**, any tableau.
    `constrain_state!(U)` runs at :249, before the refresh at :250-253.

What reads that cache in between (verified):

  - `enforce_edmf_updraft_constraints!` (mass_flux_closures.jl:267-300, with
    `edmfx_filter: true`) clips `ρa` to `ᶜρʲs`. Where `ρa < ϵ` it sets the
    updraft `mse` to `ᶜh_tot - ᶜK`. All three values come from the implicit
    precompute (precomputed_quantities.jl:709, :793, :812).
  - `enforce_mass_energy_consistency!` (utilities.jl:34-40) reads
    `p.precomputed.ᶜT` and writes `ρ` and `ρe_tot`. It is reached from
    `tracer_nonnegativity_method: elementwise_constraint_qtot`
    (constrain_state.jl:129), and from both limiters in `limiters_func!`
    (limited_tendencies.jl:111, :150).

**Failure scenario.** TEST's `edmf_dict` (EDMF, `edmfx_filter: true`, ARS222),
plus `energy_q_tot_upwinding: none`, run under `enthalpy_increment` and under
`enthalpy`. At the end of every step, the updraft `mse` in cells above the
updraft top (`ρa < ϵ`) is set from `ᶜh_tot - ᶜK` of different states. So
`Y.c.sgsʲs.:(1).mse` differs, then everything downstream of it. This is not
run. The two-sided code path is verified, but the size of the difference is
not.

TEST's `-0.0` case (section 3) cannot see this. It uses ARS343 (not FSAL),
the `step` cadence, no EDMF, no limiter and 0-moment microphysics. So nothing
reads the cache in between, which is why C9 came out bit for bit. With a
parent hook present (vanleer, TEST section 2, D4) the `cache_imp!` is
upstream's own, so that path is safe.

**Fix, simplest.** In `check_energy_source_increment_supported`, refuse
`enthalpy_increment` when there is no parent post hook (that is, upwinding is
`none`). Alternatively refuse only when the tableau is FSAL or the cadence is
`stage`/`dss`. Pass the parent's `T_post_imp!` in, and add a unit test. The
refusal concerns the diagnostic's own key, so it is allowed. If the path is
kept, add TEST's EDMF case with `energy_q_tot_upwinding: none` and ARS222
against a run without tags. Also fix docs:497 and NEWS ("The model is
untouched").

## S1 (should fix). The ledger fields go through the `is_tracer_var` loops

`is_tracer_var(:e_src_inc_left)` is true (utilities.jl:58-64). The ledger meets
the same three loops as `prc_*`:

  1. Horizontal advection, `advection.jl:121-127`, on any space with a
     horizontal divergence. The main agent's sphere check showed this for
     `prc_e_microphysics`: `moved = 2.60`, `is_tracer_var = true`
     (inc_run/sphere_rec_inc-13504848.out:70-77). `e_src_inc_*` passes the same
     filter, and `energy_source_tag_moves_as_enthalpy` is false for it.
  2. The SEM quasimonotone limiter, `limited_tendencies.jl:88-106`, with
     `apply_sem_quasimonotone_limiter: true`. It skips only
     `is_tagged_tracer_name`.
  3. Vertical water borrowing, `limited_tendencies.jl:133-139`, under
     `tracer_nonnegativity_method: vertical_water_borrowing` with the default
     `vertical_water_borrowing_species: ~`, which means every tracer. This one
     works on columns too, so on G1. It makes a signed ledger non-negative.

None of this changes a model field: each loop writes only the field it visits,
and nothing reads the ledger. But the ledger stops being the running sum of
what the correction left and moved. On a sphere, `increment_left`, a global
integral, survives advection, which is conservative. The per-column claims,
`increment_left_gross` and `increment_moved_gross` do not.

The fix on `claude/process-records-not-advected` (61d8dc3d) adds
`is_process_record_var` (`prc_*` only) to `is_tracer_var`. So after both merge,
`e_src_inc_*` is still advected and limited.

The docstring at EST:169-172 ("no transport or limiter reaches them") and the
docs repeat the claim. That is false for all three loops.

**Fix.** Exclude `is_energy_source_ledger_name` in `is_tracer_var`, and
coordinate with the records branch. A more robust rule is positive: a tracer is
a ρ-weighted name other than `ρ`, `ρe_tot` and `ρtke`, which is the
`gs_tracer_names` rule. Every upstream field of `Y.c` other than `uₕ` and
`sgsʲs` is ρ-prefixed, so upstream configurations see the same loop. Then no
future unweighted diagnostic field can fall in. Only `prc_*` and `e_src_inc_*`
are affected today. The `gs_tracer_names` loops (hyperdiffusion, vertical
diffusion, sponges, `foreach_gs_tracer`) already skip both.

## S2 (should fix). The ledger's main claim and its readers are untested

  - What the ledger is for, that the column total of `e_src_res` equals
    `Σ e_src_inc_left` plus what everything else leaves, is never asserted. At
    TEST:277-279 it is only printed. On the 0-moment column (section 3), the
    brackets close to rounding and the residual is at 1e-14 relative. There,
    `isapprox(closure.residual, sum(Y.c.e_src_inc_left); atol)` is a strong
    check. On the EDMF column, check at least that the two agree to a stated
    fraction of the gross residual, or measure first and record the gap.
  - `__energy_source_ledger_audit` (EST:409) and `compute_e_src_ledger!`
    (energy_source_tag_diagnostics.jl:182) never run in any test. The dicts
    enable no audit and no diagnostics. Call `CA.energy_source_audit(Y, p,
    model, 1.0)` and check the three columns against `sum`s of the ledger. Also
    compute one ledger diagnostic.
  - The new `check_restart_fields` call (energy_source_checkpoint.jl:144-153)
    is untested. It takes any `Y` with `.c`, so a unit test with a
    `NamedTuple` costs nothing: ledger present and not configured, and the
    reverse.
  - Weak checks: `all(isfinite, ...)` at TEST:254. And TEST:231's source-tag
    check conserves `rad` only, which may hold little energy. It passes whatever
    the donor choice.

## S3 (should fix). What the parity checks compare, and what they miss

  - The repo's rule (docs/clima_atmos_specific.md:226) is "the same column
    with a diagnostic off and on". TEST compares against `enthalpy`. The
    `enthalpy`-versus-tags-off check lives in `energy_source_tags_integration.jl`
    on another configuration, so the chain does not close for these two. In
    section 3, a run without tags costs a non-EDMF compile. It could replace the
    `enthalpy` run, keeping `closure_enthalpy` only if the budget allows.
  - Section 3 asserts only `energy_q_tot_upwinding == Val(:none)`. By
    integrator.jl:212-220 that does select `EnergySourceIncrementCorrection(nothing)`,
    so the `-0.0` path does run (verified). Pin it anyway with
    `increment.integrator.sol.prob.f.T_post_imp! isa
    CA.EnergySourceIncrementCorrection{Nothing}`.
  - The donor choice is untested. The partition's sum is the same whatever the
    donor, because the shares add up to one. Check one region tag, such as
    `ρe_src_strat`, against `-div(F·share_donor)` built in the test.
  - The `-0.0` wrapper itself (fill, then correct) is never called directly.
    One call in section 1 would cover its fill and its allocations.

## S4 (should fix before G2). The ledger records the intended move, not the actual one

`e_src_inc_moved` is `m - r|m|` (EST:1731). The partition's actual change per
cell is `-div(F·Σshare)`. The two differ in two cases.

  - **Deep atmosphere**, the default: `deep_atmosphere: true`,
    default_config.yml:442. `column_integral_indefinite!` divides by
    `ΔA_bot` (ClimaCore Operators/integrals.jl), but `ᶜadvdivᵥ` weights each
    face by its own `ΔA_f ∝ (1 + z/R)²`. So the per-cell move is off by about
    `2Δz/R·|I_f - rA_f|`. That is 1e-5 relative per stage, of one sign where the
    transport keeps one sign. It lands in `e_src_res` and in neither ledger
    field. Column totals still telescope, so `increment_left` stays right. This
    is the previous review's F7, still open. **Fix:** scale the face flux by
    `ΔA_bot/ΔA_f`, which is `(J_bot/Δz_bot)/(ᶠJ/ᶠΔz)`, before `CT3`.
  - **A donor with no share** (`ᶜe_src_share_norm = 0`, EST:902-904): that
    face's flux reaches no partition tag, but "moved" still records it. This
    is per cell only. It is rare with the repair on. Document it.

## S5 (risk, unverified). CI time and memory

Locally, `tagging_source_edmf`, with two EDMF models, took 26-27 min on Julia
1.11 at 12 GB RSS (claude_work/t6_run3.log). The new group adds two non-EDMF
models to that. Job 13504842 reported 13.0 GiB RSS after its first EDMF solve.
On CI, `tagging_source` took 20-22 min on one Julia and 40-44 min on the other
(job_1055*.log). That leaves the new group near the 90-minute budget on Julia
1.10, and near the 16 GB of a GitHub runner. Watch the first CI run, and split
the file if needed.

## Nits

  - **N1, algorithm wording.** docs:497-501, NEWS:6 and the error text say the
    mode needs "an ARS algorithm" and "refuses others". The check refuses by
    tableau structure. SSP222 and SSP332 (all implicit diagonals nonzero,
    imex_tableaus.jl:672-732) pass. Say "refuses an algorithm that uses the
    implicit tendency outside a Newton solve, such as SSP333 or the IMKG
    family". The `energy_source_tag_transport` help (default_config.yml:487)
    still does not name the requirement. docs:497-501 is one colon-joined
    sentence; split it.
  - **N2, what "moved" means.** EST:164-167 and docs:509-511 describe
    `e_src_inc_moved` as "what the tags' own implicit tendencies missed of the
    parent's vertical transport". It also carries the column-neutral part of
    local lags (sources, sedimentation, constraints). That is previous-review
    F4. Say "the part of the mismatch that sums to zero in the column, mostly
    vertical transport".
  - **N3, Float32.** The snapshot docstring (EST:1621-1622) says keeping
    `ρe_tot` and `ρ` apart avoids differencing two large totals. The partition
    side still does exactly that: `Σtags(U) - P_snap`, both of size `E`. In
    Float32 that sets a floor of about ulp(E) ≈ 0.01 J/m³ per cell and stage,
    and the ledger's gross columns will show it. Tag rounding has the same
    order, so this is acceptable, but the docstring should say it. Line 1622 is
    95 characters. `e_src_dtγ` is a `Ref{FT}` (EST:1597) while CTS's `dtγ` is
    Float64, a 2^-24 mismatch that is negligible. Storing Float64 is free.
  - **N4, a stale docstring.** `initialize_implicit_stage_problem!`
    (initialize_implicit_problem.jl:27) still says "For all other
    turbulence-convection models this is a no-op". It now also snapshots.
  - **N5, restart messages.** The ledger field check (checkpoint.jl:144) runs
    before the transport attribute check. So a switch from `enthalpy` to
    `enthalpy_increment` reports the ledger fields ("holds the fields of the
    energy source tags' increment ledger none ... configures left, moved")
    rather than the clearer transport message. Move the ledger check after
    `check_restart_setting(K.transport, ...)`, or give prefix `""` so the names
    read `e_src_inc_left`. A checkpoint from faa98974 in this mode cannot
    restart. That is fine for a prototype, but say so in NEWS.
  - **N6, cost.** The two definite integrals (EST:1695-1699) repeat the top
    face of the indefinite ones. `Fields.level(ᶠI, nlevels + half)` saves two
    column scans per stage (previous-review nit).
  - **N7, default outputs.** The ledger is not among the default outputs,
    although the records and `e_src_fix_*` are, as snapshots
    (default_diagnostics.jl:714-747). docs:514 says "reported ... as
    diagnostics". Add "on request", or schedule them as the records are.
  - **N8, names and grammar.** `__energy_source_ledger_audit` uses a double
    underscore, unusual here. The refusal text reads "stages 1 of `ode_algo`
    use" when one stage is unsolved.
  - **N9, test 3's tolerance.** `gross_relative < 1e-13` (TEST:324) is
    empirical. C9 gave 1.0e-14 at 1 h (claude_work/inc_c9_check2.log). Say that
    in a comment.

## What was checked and found right

**1. The ledger against the stepper.** In CTS, `temp = U` is taken before
`initialize_imp!` (imex_ark.jl:212), and the snapshot is the first thing in
it. The hook's `dY` is added once as `dtγ·dY` (:237) and folded into
`T_imp[i] = (U - temp)/dtγ` (:284). The ledger's Newton increment is exactly 0:
its tendency is 0 and its block is `-I`, from `fallback_identity_blocks`, split
off. So for each stage the ledger's `T_imp` equals `left/dtγ`, as the tags'
correction equals `(m - r|m|)/dtγ`. Summed with `b_imp` and `a_imp`, the
ledger's change over a step equals the implicit part of the residual's change,
to rounding. The exceptions are S1, S4 and the post-hook DSS and constraint,
which are outside by design.

  - The parent's hook zeroes `Yₜ` first (implicit_tendency.jl:380). The wrapper
    calls it before the correction, so the order is right.
  - The `-0.0` fill: `x + dtγ·(-0.0) = x` for every `x`, in Float32 too, where
    `dtγ` is Float64. Model arithmetic is exact. The issue is the cache (B3).
  - The level field broadcast against center fields is allowed. A face level's
    `LevelGrid.full_grid` is the same object as the center space's grid
    (extruded.jl:264-266; center and face spaces share one grid, :61, :71). On
    columns the `PointSpace` rule applies (Fields/broadcast.jl:228-236).
  - Reusing `ᶜe_src_abs_mismatch` after the flux is safe. The flux is
    materialised in `ᶠe_src_increment_flux` from the integral fields before
    the reuse. The ledger's `r` is the same expression as the flux's.

**2. Parity.**

  - Layout: the new fields only add components. Every CTS and ClimaCore
    operation on `Y` works element by element, and DSS works per field.
  - Jacobian: the ledger gets `-I` and is in the split's uncoupled set (the
    test asserts it).
  - `use_newton_rtol` and Krylov: the norms span the ledger, as they span the
    tags. clima_atmos_specific.md:209 accepts that. Note that the ledger grows
    without bound over a run. A `norm` over model fields in `ConvergenceChecker`
    (CTS convergence_checker.jl:76-83) would remove the exception for every
    diagnostic.
  - `gs_tracer_names` skips the ledger (it has no ρ prefix).
  - The vanleer path touches no model field and no cache the model reads.
    `p.scratch.ᶜe_src_share_norm` is recomputed by every user.

**3. Restart.** Ledger fields are checked by name and order. `enthalpy` and
`enthalpy_increment` checkpoints are refused in either direction. Pre-guard
checkpoints cannot hold ledger fields, so the audit CSV's columns cannot change
across a restart.

**4. Diagnostics and audit.**

  - Registration only in this mode.
  - A stale entry would error loudly (`getproperty`), not return a wrong
    number, so keeping it like the per-tag entries is fine.
  - Units: J kg⁻¹ for the diagnostics, J for the audit.
  - The extra audit columns depend on the transport type only, so the schema
    is fixed within a run.

**5. Tests, CI wiring and docs.**

  - Wiring: `KNOWN_TEST_GROUPS`, the runtests block, ci.yml:210,
    downgrade.yml:76 and the group list and prose in clima_atmos_specific.md
    agree.
  - The 1.10 and 1.11 matrix is right for a fork group.
  - The pinned formatter changes nothing.

**6. Docs.** The docs section sits under the enthalpy audit, before
Diagnostics, which is the right place. The diagnostics list and NEWS match the
code, except for N1, N2, N7 and the B3 and S1 claims.

**7. GPU, types, allocations.**

  - No `Ref`, closure or dynamic dispatch reaches a kernel. `dtγ` is read on
    the host.
  - The tag recursion unrolls. `follows_implicit_increment` is decided by type.
  - TEST asserts zero allocations for the correction and the snapshot.
  - The refusal check runs once, on the host.
