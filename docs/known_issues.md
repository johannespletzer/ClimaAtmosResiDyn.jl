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

## 3. Tagged water does not close under AMD LES or under PrognosticEDMFX

**Status:** guarded. Both combinations are refused at configuration by
`check_water_tracers_transport_supported` (`config/tracer_config.jl`), with a
test each in `test/config/tracer_config.jl`. The refusal under prognostic EDMF
lasts until the tags follow the updrafts.

Two transport paths move `ρq_tot` in ways the water tags do not follow, so
`Σᵢ ρq_tag_i = ρq_tot` stops holding. Both are properties of the tagged-water
implementation rather than of any particular run, and both predate the merge of
the passive-tracer line.

  - **AMD LES.** `parameterized_tendencies/les_sgs_models/anisotropic_minimum_dissipation.jl:135-155`
    (horizontal) and `:282-303` (vertical) recompute `ᶜD_amd` inside
    `foreach_gs_tracer` from *each tracer's own* gradient. So `ρq_tot` is
    diffused with `D(∇q_tot)` and each `ρq_tag_k` with `D(∇χ_k)`, and
    `Σₖ ∇⋅(ρ Dₖ ∇χₖ) ≠ ∇⋅(ρ D_tot ∇q_tot)` because the operator is nonlinear.
    This is not transport "the tags receive in their own right" — it is a
    genuine break of the partition that no bracket or repair corrects.
    Smagorinsky–Lilly (`smagorinsky_lilly.jl:170-178`) shares one `ᶜD_h` and
    does close, as does constant horizontal diffusion.

  - **PrognosticEDMFX.** The SGS mass-flux loop over tracers in
    `edmfx_sgs_flux.jl:134-171` is driven by `sgs_tracer_names(Y)`. Tags have
    no `sgsʲs` entries, so they are skipped. That is safe, but they never
    receive that first-order water transport. Their sedimentation still
    closes: under 1M `ρq_tot` sediments with the grid mean's flux only, and
    the tags' fluxes sum to it (`water_advection.jl:85-95`). The EDMF
    corrections to sedimentation (`:117-213`) change only `ρe_tot` and the
    energy source tags. So the updraft's rain falls with the grid mean's
    composition, which affects provenance, not closure. The claim in
    `tagged_tracers/tagged_water.jl:23-24` that the implicit/explicit
    vertical-advection split is "the one unavoidable source of closure drift"
    is not true under EDMF.

The combination used to be accepted silently, because
`check_water_tagging_supported` screens only the microphysics model. The new
check is separate from it, since that function also gates
`water_process_record`, whose records are not transported and stay allowed.
The refusal under prognostic EDMF lifts when the tags take their share of the
updraft's water flux.

## 4. The implicit water-microphysics attribution has no Jacobian diagonal

**Status:** diagnosed and measured; not visible in the answer on a raining 0M
column. Not fixed.

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

**Measured on 2026-09-23.** The DYCOMS RF02 column under 0M without EDMF, at
`dt` 120 s, rains out its initial cloud (0.15 kg m⁻² of liquid) in the first
hour. Four runs covered that hour: implicit or explicit microphysics, each
with 1 and 10 Newton iterations. With explicit microphysics the sink is off the
Newton path, so that pair is the control. The region tags' shares differ
between 1 and 10 iterations by 1e-3 to 2e-3 in L1, 25 times more than
`ρq_tot` itself. But the implicit and explicit pairs differ from each other by
less than 4% of that, with no fixed sign. So the missing diagonal is not what
makes the tags sensitive to the Newton count. A proportional loss leaves each
cell's shares unchanged, so a missing derivative of it acts only through what
else changes the shares within the step, which fits a small effect. The
sensitivity itself matches the change in `q_tag_res`, which is larger with the
converged solve: the split between the parent's implicit and the tags'
explicit vertical advection. The runs and their analysis are in the fork's
tag-closure record (`experiments/tag_closure/FINDINGS.md`, W15 and W16, on the
branch `claude/tag-closure-record`). A 1M column and a sphere were not
measured. No GitHub CI job reaches this path.

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
