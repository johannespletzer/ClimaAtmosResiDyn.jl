# Known issues

Open problems that are understood but not yet fixed. Each entry records what is
established, so the next person does not have to re-derive it. GitHub Issues are
disabled on this repository, so this file is where they live.

Remove an entry when it is fixed. Mark it closed instead when other entries or
error messages cite its number, so that the numbers stay stable.

## 1. Tagged water closure assertions failed in the dynamics test group (closed)

**Status:** closed on 2026-09-23. The entry keeps its number because other
entries and error messages cite issues by number.

Two assertions in `test/tagged_water_integration.jl` failed on `ci 1.10 - dynamics` in run
[32335353545](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/actions/runs/32335353545):
the sphere's limiter-rescale residual (`1.17e-3` against a bound of `1e-3`) and
the 1M sedimentation `norm` (`1.00006` against `1 + 100 eps`). Neither measured
a statement the implementation makes. The repair declines to renormalize the
tags onto `ρq_tot`, so both are leakage monitors, not identities. The bounds
became `1e-2` and `1 + 1e-2`, and the shares themselves are asserted to lie in
`[0, 1]`.

Both numbers predated the fix of issue #64, which changed `rescale_water_tags!`
from scaling the tags to adding the parent's increment. After it, on `main` at
`0b2b1032` and Julia 1.11, the whole file passes, 111 tests, and the two
quantities are:

  - the sphere residual, `maximum(abs.(residual)) / scale`: `7.4e-4`;
  - the 1M sedimentation `norm`: at most `1.0003`, at least `0.9996`.

Both are well inside their bounds. The `norm` drift is larger than the
`6.0e-5` measured before the fix, and 30 times inside its bound. The test's
comments record both readings. The `tagging_water` CI group runs the file.

## 2. Levante 1/2/4 GPU scaling has not been measured

**Status:** open, needs a run on Levante.

`runscripts/xmodel.1gpu`, `xmodel.2gpus` and `xmodel.4gpus` are verified
correct on the machine — the binding report shows `MATCH` on every rank and the
CUDA/MPI device test passes — but the strong-scaling numbers they exist to
produce have not been collected. The measurement protocol is in
`runscripts/README.md`.

## 3. Tagged water: refused under AMD LES; under single-updraft PrognosticEDMFX its residual has named sources

**Status:** AMD LES guarded. Prognostic EDMF with one updraft supported, with
more than one guarded. `check_water_tracers_transport_supported`
(`config/tracer_config.jl`) refuses AMD LES, and prognostic EDMF with more than
one updraft, with a test each in `test/config/tracer_config.jl`.

**AMD LES.** `parameterized_tendencies/les_sgs_models/anisotropic_minimum_dissipation.jl:135-155`
(horizontal) and `:282-303` (vertical) recompute `ᶜD_amd` inside
`foreach_gs_tracer` from *each tracer's own* gradient. So `ρq_tot` is diffused
with `D(∇q_tot)` and each `ρq_tag_k` with `D(∇χ_k)`, and
`Σₖ ∇⋅(ρ Dₖ ∇χₖ) ≠ ∇⋅(ρ D_tot ∇q_tot)` because the operator is nonlinear. No
bracket or repair corrects that. Smagorinsky–Lilly (`smagorinsky_lilly.jl:170-178`)
shares one `ᶜD_h` and closes, as does constant horizontal diffusion.

**Single-updraft PrognosticEDMFX, now.** The tags follow the updraft's water in
one of two modes; see "Under prognostic EDMF" in `docs/src/tagged_water.md`. At
a given state the default mode's partition takes the parent's sub-grid flux
exactly, and its exchange sums to zero. The partition still parts from the
parent, by these mechanisms:

  - **The Newton iterations.** The tags' sub-grid flux has no Jacobian block and
    the parent's has, so with a fixed number of iterations the tags lag. On
    D4-W the default mode's gross residual after a day is 0.71% with one
    iteration and 0.13% with ten (V-W3). WP5's increment follower is the
    planned answer.
  - **The leaks.** Paths that move the tags on their whole value and `ρq_tot`
    without rain and snow, or relative to a reference profile.
    `q_tag_leak_<path>` gives the source each would add to an exactly closed
    partition. WP4c corrects the ones G3_PLAN 4.2's rule selects.
  - **The vertical advection split**, as without EDMF.
  - **The plume model.** The default mode's updraft composition is a steady
    entraining plume, not a prognostic field. The updraft copies audit it.

**Historical behavior, before the tags followed the updrafts.** The SGS
mass-flux loop over tracers in `edmfx_sgs_flux.jl` was driven by
`sgs_tracer_names(Y)`. The tags had no `sgsʲs` entries, so they were skipped and
never received that first-order water transport. Their sedimentation still
closed: under 1M `ρq_tot` sediments with the grid mean's flux only, and the
tags' fluxes sum to it (`water_advection.jl`). So the updraft's rain fell with
the grid mean's composition, which affected provenance, not closure. On D4-W
the partition drifted to 15% of the column's water in a day (V-W1). The
combination was accepted silently, because `check_water_tagging_supported`
screens only the microphysics model. The refusal was kept separate from it,
since that function also gates `water_process_record`, whose records are not
transported and stay allowed.

## 4. The implicit water-microphysics attribution has no Jacobian diagonal

**Status:** diagnosed, not fixed. Open: whether the missing entry changes the
answer after a fixed number of Newton iterations has not been isolated.

**The updraft copies under 0M are affected too.** With
`water_tag_updraft_copy: true` the copies' rain-out mirror,
`χᵢʲₜ += dq (clamp(χᵢʲ/q_totʲ, 0, 1) - χᵢʲ)`, runs on the implicit path by
default. Its diagonal, `dq (1/q_totʲ - 1)` away from the clamp, has no Jacobian
entry. That is deliberate. `q_totʲ`'s own rain-out has no entry either, and
adding one would change the model's results. Without either, the copies' rows
and `q_totʲ`'s have the same diagonal blocks, so each Newton update of the
copies sums to `q_totʲ`'s over a closed partition. An entry for the copies
alone would part them, and the repair would then reshape their provenance. So
the copies lag their implicit rain-out as `q_totʲ` does. Until a Newton ladder
on a raining 0M column (1, 2 and 10 iterations) bounds that lag for the copies,
`q_tag_copy_res` and `q_tag_upfix_*`, 0M copies are not a validated audit.

`implicit/implicit_tendency.jl:66-78` puts the `:microphysics` water bracket on
the implicit path. Its increment is `min(Δ, 0) · ρq_tag / ρq_tot`, which is
proportional to `ρq_tag`, so `∂/∂ρq_tag = Δ⁻/ρq_tot` — the same O(1/dt)
quantity the file's own positivity argument names. Nothing supplies that entry:
under 0M the tags get the ordinary passive diagonal
(`manual_sparse_jacobian.jl:216-253`, in `update_diffusion_jacobian!`), or a
plain `-I` when diffusion is explicit;
under 1M the sedimentation diagonal carries no microphysics term.

The comment at `implicit_tendency.jl:322-328` justifying the *energy* bracket's `-I` ("the attributed
increment does not depend on the tags themselves") is true for
`:precipitation` and false for the water bracket. With a fixed Newton
iteration count this is in principle error in the answer rather than only
slower convergence.

**A first measurement, 2026-09-23, which does not isolate the entry.** The
DYCOMS RF02 column under 0M without EDMF, at `dt` 120 s, rains out its initial
cloud (0.15 kg m⁻² of liquid) in the first hour. Four runs covered that hour:
implicit or explicit microphysics, each with 1 and 10 Newton iterations.

  - On this column, the region tags' difference between the 1- and
    10-iteration runs changed by at most 4% when microphysics moved from the
    implicit to the explicit path, with no fixed sign. That difference is 1e-3
    to 2e-3 in L1 of the shares, 25 times `ρq_tot`'s own.
  - The small `evap` source tag's difference changed by up to 24%, at an
    absolute size near 2e-5.
  - This comparison does not isolate the missing diagonal. Moving
    microphysics off the implicit path also changes the operator splitting and
    the discrete integration path.
  - The share differences were recomputed by the verifier
    (`experiments/tag_closure/analysis/evidence/compare_runs.py`); runs,
    manifests and output are in the fork's tag-closure record, FINDINGS W15 and
    W16, on the branch `claude/tag-closure-record`.
  - A 1M column and a sphere were not measured. No GitHub CI job reaches this
    path.

To isolate it, compare runs with the same implicit residual and time
integration that differ only in whether the analytic diagonal is present,
across a Newton-iteration ladder with a tightly converged reference and a time
step ladder, reading the region tags, the source tags, `q_tag_res` and the
nonlinear convergence.

## 5. `fill_with_nans!` would destroy the tag masks if it ever descended into the cache

**Status:** latent; harmless today.

The debug helper would overwrite the static region masks and the `ᶜwater_fix`
ledger along with everything else. It does not, only because `AtmosCache` is a
plain struct and hits the `::Any` fallback — which means the feature is a no-op
in general, not that the tags are protected. Worth knowing before anyone makes
it work.

## 6. Cleanup findings that belong to upstream ClimaAtmos, not to this fork

**Status:** verified as upstream's, deliberately unchanged here.

A cleanup review of `851cafa` raised these. Each was checked against
`CliMA/ClimaAtmos.jl@main` and is still there, byte for byte. This repository
tracks upstream, so fixing them here would mean a conflict on every future
merge for no benefit to this fork. They are recorded so the next review does
not re-derive them.

  - **Circular conservation claims in the microphysics tests.**
    `test/parameterized_tendencies/microphysics/bmt_integration.jl:229-270` and
    `sgs_quadrature.jl:467-532` define the vapor tendency as the negative sum
    of the others and then only check that it is finite. That tests
    construction, not conservation. Much of `bmt_integration.jl` also exercises
    CloudMicrophysics structures directly rather than the ClimaAtmos wrappers.
  - **Gravity-wave jobs called tests.** Seven active jobs in
    `.buildkite/full_pipeline.yml:150-189` run scripts that produce plots and
    assert nothing. They pass whenever the script does not crash.
  - **Unverified downloads.** `test/artifact_funcs.jl` fetches mutable external
    files into `tempdir()` with no checksum. This fork no longer downloads them
    during unit tests (see below), but the four standalone gravity-wave scripts
    still use these functions.
  - **2M and 2MP3 microphysics advertised but rejected.**
    `src/cache/precomputed_quantities.jl:160-167` asserts against both, while
    the config parser, default help, README and microphysics documentation
    still list them as supported.
  - **Dead private functions.** `ᶠupdraft_nh_pressure_buoyancy` and
    `ᶠupdraft_nh_pressure_drag` in
    `src/prognostic_equations/mass_flux_closures.jl`, and `add_sgs_ᶜK!` in
    `src/cache/precomputed_quantities.jl` (with its commented-out call at
    `:749`), have no callers.
  - **Orphan files under `test/`.** `test/implicit/debugging_tools.jl` is
    unreferenced and says so itself;
    `test/parameterized_tendencies/gravity_wave/orographic_gravity_wave/compute_preprocessed_topography.jl`
    is a data-generation tool, not a test.
  - **Comments that record patch history.**
    `src/prognostic_equations/mass_flux_closures.jl:141` ("used to have"),
    `src/simulation/AtmosSimulations.jl:210` ("backward compatibility since"),
    `test/gpu_setups.jl:35-38`, and
    `test/prognostic_equations/tracer_mass_consistency_tests.jl:89-90`
    ("pre-fix"). The two comment sites this fork owns were rewritten.
  - **`solve_atmos!` contract.** The docstring in `src/simulation/solve.jl:99`
    says failures are caught and writers closed on every path, but the first
    `CTS.step!`, `precompile_callbacks` and `GC.gc()` all run before the
    `try` at `:128`.
  - **Restart-test duplication.** `test/restart.jl` and
    `test/restart_AtmosSimulation.jl` duplicate the checkpoint/reload/compare
    contract. Note that the review's proposed `restart_utils.jl` already
    exists; what is real is the stale signature documented at
    `test/restart_AtmosSimulation.jl:156-164`, which names
    `test_restart(simulation, model, grid; job_id, ...)` for a function that
    takes `(simulation, args; comms_ctx, more_ignore)`.
  - **Restart sweep only on Buildkite.** The sphere, box and column sweep in
    `test/restart.jl:192-266` runs only with `--manytests`, which upstream's
    Buildkite passes (`.buildkite/full_pipeline.yml:891`). This fork runs
    GitHub Actions only, so here only the `amip_target` case from `:267` runs.
  - **Test files that build the same model twice.** Found by the CI review of
    2026-09-17. `test/prognostic_equations/edmfx_horizontal_diffusion_tests.jl:57`
    and `:242` build the same `box_config_dict()`.
    `test/prognostic_equations/enforce_physical_constraints_tests.jl:33-192`
    builds the same configuration eight times.
    `test/prognostic_equations/vertical_water_borrowing_tests.jl:34` and `:59`
    build the same configuration.
    `test/parameterized_tendencies/microphysics/allocations.jl:296-376`
    rebuilds the three models of `tendency.jl:89-218`. A repeat of a type that
    is already compiled costs seconds, so these cost little CI time.
  - **Inactive pipeline history.** `.buildkite/full_pipeline.yml` carries
    several wholly commented-out jobs.
  - **`perf/flame.jl`.** The `@allocated` pass is labelled "old" and "TODO:
    remove" although it is the pass that enforces the allocation limit;
    `Profile.Allocs` only produces the report.
  - **Placeholder testsets.** `test/conservation/*.jl`,
    `test/prognostic_equations/hyperdiffusion_tests.jl` and `tendency_tests.jl`
    held twelve `@test_skip` placeholders and no assertions. They ran in this
    fork's `dynamics` group, so they were removed here; upstream still has
    them. The tests they were meant to become — global dry-air mass, total
    water mass and tracer mass conservation, hyperdiffusion tendency, and
    tendency-computation coverage — are worth writing against real reference
    values rather than restoring as scaffolds.
  - **Julia 1.9 compatibility.** Upstream still declares `julia = "1.9"` while
    testing only 1.10 and 1.11. This fork raised its own floor to 1.10.

## 7. Tagged water ends a run where the parent's water goes negative (option C built; its validation fails one rule at site 23)

**Status:** option C is built and unit-tested (below). Option A keeps the
check from ending the run; this branch has it by merge of #112, which is not
merged into `main`. Whether C keeps the tags on their target over the long runs
was the record branch's pre-registered validation
(`design/NEGATIVE_PARENT_WATER.md`, section 8). It ran on 2026-09-25 (the
record's FINDINGS W42). Site 23 now runs 90 days, the model fields match the
untagged twin bit for bit, and site 26's tags are unchanged bit for bit. But
at site 23 the region tags overshoot the target by up to 2.2% of the water,
against a budget of 0.2%. What follows is the owner's decision.

A diagnostic must never end a run that upstream completes. This one does.
The tag-closure long runs (the record branch's
`design/INCREMENT_RULE_LONG_RUNS.md`, second submission, jobs `13917157` to
`13917199`) ran the GCM-driven column for 90 days at site 23. They ran
`claude/long-run-samesign`, which is #102 and #103 with the energy follower's
same-sign rule, and its `|m|` twin.

  - **The parent.** The model's own `q_tot` goes below zero from day 10, in
    the untagged twin too, down to −3.1e-3 kg/kg (day 30), on 66 of 91 daily outputs.
    That is upstream's behavior at this site, not the tags'.
  - **The tags.** The water tags then diverge. On day 48 the copies run's
    column tags hold 28 kg/m² of water against the parent's 13, and
    `q_tag_pbl` reaches 0.13 kg/kg against a `hus` maximum of 0.016.
  - **The end.** The tagged runs stop with `simulation_crashed`, the water
    closure at −1.02: the copies run at day 48, and both follower rules at
    day 74.5 (t = 6.4368e6 s). The untagged twin completes 90 days.
  - **Parity holds until then.** The ten daily output fields (density,
    temperature, humidity, cloud water and ice, vertical velocity,
    precipitation, liquid water path, updraft area and humidity) are bit for
    bit the untagged twin's at every output up to each crash. The runs keep
    no checkpoints, so the full state is compared only through these.

**What ended the runs:** the water closure check. Job `13917157`'s `.err`,
line 1401, reads "water tag closure residual 1.0194981558568388 exceeds the
configured abort level 1.0 at t = 6.4368e6 s", from `tag_closure_callback!`.
That level assumed a non-negative parent: then non-negative tags miss it by at
most the parent itself. Here the parent is negative.

**Option A, chosen, in this branch by merge** (the owner's choice of
2026-09-24): #112, `claude/tag-closure-no-abort`, a PR against `main` that is
not merged. This branch has it at `1b096d77`. With it, no closure check ends a
run by default. Past water's old level, 1.0, is its `void_above`: the check
warns once and marks this and every later row `closure_void` in the closure and
audit tables, through restarts, and the run goes on. An explicit `abort_above`
still ends a run.

**The probe** (the record's FINDINGS W39) read the per-tag ledgers over 20
days at site 23. When the parent first goes negative, the follower's moved
part is about 120 times the corrections, and 70% of the tags' overclaim lies
outside the negative cells. It pointed to option C.

**Option C, done** (the owner's choice of 2026-09-25): the partition tags
partition the parent's non-negative water, `max(ρq_tot, 0)`, and the negative
part is a named remainder, `q_tag_negative`.

  - The follower takes the non-negative part's increment. The part of its
    column total that is the negative water a solve creates goes to the tags,
    in the new ledger `q_tag_inc_negative`, and not into `q_tag_res`.
  - Where the parent is negative, a cell's tags move by the partition's own
    composition, so a cell overdrawn by a solve gives up the tags it held.
    Before, its shares were zero and the tags stayed.
  - The limiters' rescale and the copies' repair aim at the non-negative part.
  - The closure check and `q_tag_res` compare the partition with it.
  - Where the parent is never negative, nothing changes, bit for bit.

**The parent's negative water, flagged** (the owner's choice of 2026-09-25,
on `claude/water-tags-negative-water-flag`, stacked on option C). Under C the
closure can pass while the parent itself is negative, so `closure_void` stays
0. The water closure check now also reads the parent's own negative water,
from the raw `ρq_tot`:

  - `negative_water_relative`, on every closure row, is
    `∫max(-ρq_tot, 0) dV / ∫ρq_tot dV`. It is the tag-closure contract's row
    "Parent validity: negative water", read at the checks.
  - `negative_water_void` latches at 1 once that passes
    `negative_water_void_above`, `1e-4` by default, the contract's level. It
    stays 1 after the parent recovers, and the checkpoint carries it through a
    restart.
  - The checks see the state at their own times only. So a ledger in the cache
    adds `max(-ρq_tot, 0) Δt` after every accepted step, and counts the
    negative cells. The water audit reports its change per interval. An
    interval whose event count is 0 had no negative water at the end of any
    step.
  - The audit's `nonpositive_mass` had read the target `max(ρq_tot, 0)` under
    C, and so was 0 by construction. It reads the raw `ρq_tot` again.

The flag and the ledger live in the cache, never in the model's state. See
`docs/src/tracer_configuration.md`, "The parent's negative water".
