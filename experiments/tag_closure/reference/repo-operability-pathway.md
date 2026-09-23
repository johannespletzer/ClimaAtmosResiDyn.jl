# Repository operability pathway

> **Frozen record.** Written on 2026-09-21 and kept as written. Its code links
> pin PR #95 at `974f3e16`, which has since moved. The living plan is
> [ROADMAP.md](../ROADMAP.md), [G3_TODO.md](../G3_TODO.md) and
> [G4_TODO.md](../G4_TODO.md). Until 2026-09-23 the roadmap stood at the top of
> OPERATIONAL_TODO.md.

Prepared 2026-09-21 for `johannespletzer/ClimaAtmosResiDyn.jl`. This is an ordered implementation and validation proposal. No repository code, defaults, tolerances, GitHub state or atmospheric runs were changed by this review.

Reference code: PR #95 head `974f3e1659cddea96a69527017e30a6249ef8666`, base `c99ff7bd5005dd568a86a36b1ddff1389ac0c721`. Historical experimental context: `claude/tag-closure-experiments` at `f69ec02a6eac325b61cb6f30a6f259b1299293ec`. These are divergent branches, not interchangeable release candidates.

**Reliable operability means a declared configuration runs reproducibly, leaves the parent atmosphere unchanged by diagnostics within the supported parity contract, satisfies independently justified scientific criteria, and has an affordable measured cost.** It does not mean every configuration supported upstream has been validated for every diagnostic in this fork.

## Governing constraints

The [repository parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/clima_atmos_specific.md#L219-L236) requires diagnostics to preserve parent fields bit for bit for the fixed-iteration direct solver, on the same machine, Julia/environment, precision and process count. Krylov and residual-based Newton stopping are explicitly outside that promise. Every comparison below must preserve those conditions or declare a different numerical-accuracy criterion. Changing the Newton count or timestep to establish convergence intentionally changes the reference trajectory; compare tagged and untagged variants at each identical setting.

Keep changes to upstream atmospheric physics upstream. Diagnose defects here, provide minimal reproductions, then integrate upstream fixes through the established merge process. Do not accept new reference outputs merely to make a diagnostic change pass. Code changes proposed below concern diagnostic correctness, evidence and operability unless explicitly identified as an upstream investigation.

Separate parent conservation, tag-partition closure and per-tag provenance. Source overlays are not members of the pure-region partition. The offset total `E_c = ρe_tot+cρ` is a diagnostic convention, not an independently conserved physical reservoir. [Definitions and transport](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/energy_source_tags.md#L1-L60), [parent-ledger identities](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/parent_budget/contract.md#L84-L199).

## Milestone order and dependencies

| Milestone | Outcome | Depends on |
| --- | --- | --- |
| M0 | Immutable scope, evidence and baseline inventory | None |
| M1 | Local correctness and honest documentation | M0 |
| M2 | Explicit scientific contract and independent accounting | M1 |
| M3 | Reproducible small-case reference suite | M0–M2 |
| M4 | Measured and controlled runtime cost | M3; profiling can begin at M0 |
| M5 | Closure and attribution choices qualified by experiments | M2–M4 |
| M6 | Backend, precision, input and restart qualification | M1, M3–M5 |
| M7 | Production trial and supported release envelope | M0–M6 |
| M8 | Scientific extensions with their own evidence gates | M7 for production use |

A milestone passes only when its evidence bundle and decision are recorded. “Unknown,” “not applicable” and “failed” must remain distinct. A missing measurement is not a zero residual or a successful test.

## M0 — Freeze what is being tested

Create a compact manifest for each configuration: repository/head/base/upstream SHAs, resolved dependencies and Julia version, effective merged YAML/TOML, initial-condition and forcing hashes, grid/geometry, float type, MPI/device/compiler details, thread/rank counts, seed or perturbation settings, exact launch command, checkpoint lineage, diagnostic schema and analysis version. Record a clean-tree hash or an archived patch; `commit_dirty: unknown` is insufficient for a release claim.

The current historical [provenance](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/output/v3_upd_default/head_846ef55d/provenance.txt) is useful but has unknown dirty status and leaves NetCDF/checkpoints on cluster scratch. The branch-only [comparison script](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/analysis/increment/tag_correctness.py#L19-L61) chooses latest output directories implicitly. Make run IDs explicit and archive a small immutable dataset sufficient to reproduce each headline table.

**Acceptance criteria**

- One machine-readable inventory distinguishes PR-head results, historical results, proposed runs, failed runs and superseded runs. Every headline number resolves to inputs, exact code and a result file.
- Re-analysis of the same archived inputs reproduces its table; missing variables, mismatched times/grids or truncated runs fail explicitly.
- Tag/default/copy/untagged comparisons use the same parent configuration and environment. Reference preparation preserves a full parent-state comparison, not only `ta` and `rhoa`.
- Retain historical results rather than silently replacing them with newer runs. Record the 24-file PR allowlist in the appendix below.

## M1 — Close concrete correctness gaps and narrow claims

Address the default plume's inventory/admissibility issue, the missing-updraft restart guard, and the inaccurate diagnostic guidance identified in `pr-95-review.md`. Preserve the useful initialization rebuild, partition refusal and bounded small-velocity weight.

For the default mixing reconstruction, require `0 ≤ ρaʲ εʲᵢ ≤ ρ ε̄ᵢ` and the weighted environment identity, or explicitly define a different closure with a diagnosed mismatch. Do not silently clip the environment and continue to claim the original identity. For missing checkpoint `sgsʲs`, compare expected copies with an empty actual set rather than skip the check. [Helpers](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl#L1946-L1970), [restart guard](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parameterized_tendencies/tagged_tracers/energy_source_checkpoint.jl#L155-L169).

**Acceptance criteria**

- Unit tests cover the review's positive-state counterexample, zero/near-zero inventory, vanishing updraft/environment, restarted plume, Float32 and Float64. On admissible inputs, the weighted mixture closes to a declared roundoff-scaled bound; bound violations are prevented or explicitly reported.
- Exchange fluxes/tendencies sum to zero over the partition under each supported reconstruction; test more than the existing centered-column path and the van-Leer-to-first-order dispatch.
- Restart tests reject missing updraft state, missing copies, extra copies and switch changes before cache construction; unchanged configurations round-trip correctly.
- File-based initialization tests cover energy, water and source tags and copies, including pure regions and source overlays. An actual supported file-based setup starts with finite tags and passes the first accepted-step checks.
- The guide qualifies “exact,” parity, offset range and transport-specific residual examples. `repair_moved` is described as net accumulated repair magnitude. The default tolerance factors agree with their own table.
- Relevant `infrastructure`, `tagging_source`, `tagging_source_edmf`, `tagging_source_increment`, `tagging_source_updraft` and `restarts` groups pass at the new candidate SHA. No parent-field change is accepted for a diagnostic-only patch.

## M2 — Define success before tuning closure

Publish one claim contract per diagnostic family: tagged water, signed energy tags, energy-source tags, process records, stratospheric passive tracers and parent-budget ledger. Include state variables, units, admissibility conditions, supported physical processes, how sources overlap, which corrections occur, restart semantics and what each reported residual can prove.

For energy-source tags, report signed `∫R`, gross `∫|R|`, `∫|R|/∫|E_c|`, residual rate, vertical/local errors, source-overlay negativity, minimum positive-total headroom, and signed versus gross repair/correction activity. Fix the dimensional scale and offset before selecting tolerances. Monitor subdomain margins as well as the grid mean where the exchange uses subdomain energy.

Independent accounting is a dependency, not a feature that can simply be enabled everywhere. The current [parent-budget contract excludes EDMF, 2M/P3 and local budgets](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/src/parent_budget/contract.md#L275-L288), and the [calibration table](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/parent_budget/kappa_calibration.yaml) has one CPU Float64, one-rank row. For EDMF, first decide how updrafts represent the grid mean; avoid counting them as additional atmospheric reservoirs. Until the ledger's schema and coverage are extended, use explicitly limited, independently checked offline parent budgets and retain a blocked ledger verdict.

**Acceptance criteria**

- Every process and state-writing hook in the intended envelope is measured, justified as zero/not applicable, or marked unsupported. Aggregates and their component transfers are not counted twice.
- On a small supported case, accepted-step parent change equals external transfers plus sources/maps plus a named numerical remainder. Independent endpoint and applied-increment calculations agree within a predeclared accounting bound.
- Offset attribution includes `c Δρ` consistently. Tag-only repair is not booked as a parent-energy source.
- Closure warnings, abort rules and scientific acceptance thresholds are separate. A small aggregate residual cannot make a per-tag test pass.
- Gross-intervention diagnostics pass an alternating-correction test; attempted stage/DSS repairs are distinguished from changes retained in accepted state. Signed and absolute loss measurements survive output-cadence changes and restart stitching.

## M3 — Establish a compact reference suite

Use the existing config/test ecosystem rather than an unbounded new matrix. Start with the cases below, all with immutable manifests from M0. Reuse tag names/signatures when comparing configurations to reduce recompilation.

| Case | Control / baseline | Main question and required outputs |
| --- | --- | --- |
| Source-free frozen column | Analytic or manufactured mixing; uniform composition and sharp/smooth interfaces | Null flux for identical composition; inventory bounds; correct transport direction; quadrature-weighted per-tag error |
| Forced column without EDMF | Untagged parent plus process records and each diagnostic family separately | Source/loss attribution, pressure-work mismatch, offset and mass-change accounting |
| DYCOMS RF02, one updraft, 1M | Existing PR-style column; default/copies/untagged | Early turnover, surface pulse, exchange, diffusion on/off, correction and repair |
| Cold precipitating column | Existing `PrecipitatingColumn` test plus longer persistence case | Signed ice-energy donor direction, positivity margins and sedimentation accounting |
| Small sphere, then EDMF sphere | Untagged twin at each exact solver setting | Horizontal transport, geometric weights, top-level health, MPI and accumulated residual |
| File input + interrupted continuation | Same run continuous versus checkpointed | Tag initialization, parameter identity, checkpoint state and diagnostic segment semantics |

The [new cold-column test](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/test/energy_source_tags_cold_column.jl#L1-L35) is a useful starting point; it explicitly says most ice disappears in the first minute. It does not substitute for sustained ice production or deep convection. Likewise, one-hour copy tests do not establish one-day or seasonal per-tag accuracy.

**Acceptance criteria**

- Controls distinguish diagnostic-off/on parity from comparisons of different atmospheric discretizations.
- Manufactured cases have explicit expected values, not just “nonzero” or “finite” assertions.
- Each physical case has a reference obtained by successive timestep/grid/solver refinement; declare convergence when successive changes are below a preselected fraction of the intended science error budget, not merely when Newton iterations finish.
- Record startup and later windows separately. Use physical-volume/mass weights and exact output timestamps; label peak-normalized L∞ separately from pointwise relative error and report absolute error where the reference is small.
- Archive at least one minimal reference bundle for each supported family. Record unsupported combinations rather than silently falling back.

## M4 — Make the validated path affordable

Separate setup, compilation, first-step compilation, warmed tendency/step time, diagnostics/I/O, allocations, peak resident/device memory and scaling. Compare untagged, region-only, all selected tags, copies and process-record variants. The inspected [updraft CI job](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/actions/runs/35507845575/job/106070867239) spent 99.58% of its measured test time compiling; its cumulative allocations are not peak memory and its test duration is not production throughput.

Begin with signature reuse and representative precompile workloads. Profile repeated environment thermodynamics/geometry in the donor and exchange paths before adding caches. Consider separating eligible nested passive-copy blocks from the large solver only after inspecting every dependency; the [current split eligibility](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/src/prognostic_equations/implicit/manual_sparse_jacobian.jl#L709-L745) excludes nested fields. Preserve parent arithmetic ordering and cache timing.

**Acceptance criteria**

- A benchmark report records medians and variability for repeated warmed measurements and separately reports cold starts, at 2, 8 and 32 tags on the intended representative grid.
- Each accepted optimization has a measured benefit larger than observed timing noise and no scientifically significant diagnostic regression. All parent fields remain bitwise equal in the supported same-environment tests.
- The existing allocation gates remain passing: exchange ≤8 bytes and donor-plus-exchange ≤24 bytes on the covered CPU setup, unless a separately justified change updates the contract. These are local hot-path bounds, not total model allocation budgets. [Tests](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/test/energy_source_tags_increment_integration.jl#L384-L416), [EDMF allocation test](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/test/energy_source_tags_edmf_integration.jl#L341-L361).
- Set explicit measured startup, step-time and peak-memory budgets before M5's larger runs. The representative job must fit its wall time and memory allocation with agreed headroom.
- Report strong/weak scaling separately; keep useful reductions aggregated and diagnostic cadence justified. Do not reduce scientific output needed to validate a claim merely to achieve a timing target.

## M5 — Select and qualify the residual and mixing closures

Run a staged design that distinguishes mechanisms:

1. Fix the parent trajectory for tag-only questions where feasible. Compare donor-only behavior as a historical baseline, current steady exchange, an admissible constrained reconstruction, and prognostic copies.
2. Refine timestep (initial DYCOMS ladder 120/60/30 s), vertical grid (30/60/120 levels) and fixed Newton count separately. Continue refinement if successive changes remain material. Do not call ten iterations converged without a check.
3. Compare centered and first-order exchange; include higher-order supported schemes after the basic invariants pass. Measure intervention rather than assuming repair makes an unlimited update acceptable.
4. Add a surface pulse and transient convection. Test the copy boundary convention separately from interior mixing; source-free passive mixing is the independent control.
5. Sweep offset within a documented positive-margin envelope, keeping one offset per run/restart lineage. Compare dimensional source-tag changes as well as normalized residual.
6. For the inherited increment correction, compare alternative placements of the column-total mismatch and process-resolved attribution on the same accepted parent increments. Treat sensitivity to equally conservative choices as uncertainty.

**Acceptance criteria**

- Every candidate passes zero-sum, admissibility, positivity/headroom and parent-parity gates before accuracy ranking.
- Per-tag convergence, source response, local error and intervention satisfy predeclared budgets on calibration and held-out regimes. Candidate thresholds already recorded for D4—24 h L1 ≤2% and peak-normalized L∞ ≤5%—are historical case-specific criteria, not a universal production standard. [Existing G1 criteria](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L31-L60).
- Short-time errors receive their own budget; a day-one average cannot excuse an unqualified first-hour attribution product.
- Choice of default includes an accuracy/intervention/runtime comparison. Document assumptions and a diagnostic for leaving the validated regime, such as fast-changing composition relative to plume adjustment.
- A held-out forced or transient case can reject a fitted closure. No threshold is changed after seeing a failure without recording and revalidating that decision.

## M6 — Qualify devices, precision, data inputs and continuation

Advance the qualified small cases to CPU Float32/Float64, then supported AD paths, one GPU, MPI CPU and intended GPU/MPI layouts. Exercise both exchange and copies; a compile-only test is necessary but insufficient. Test topography and deep geometry after flat-grid controls. Check that every rank agrees on configuration refusals and that collective diagnostics cannot strand ranks.

**Acceptance criteria**

- GPU scalar indexing is prohibited; kernels compile and execute with finite state. Record device allocations, memory and representative tag-count scaling. CPU `@allocated` is not used as evidence of GPU behavior.
- Precision/device comparisons use predeclared numerical tolerances informed by refined references. Bitwise equality is required for diagnostic-off/on twins within one supported environment, not across devices or rank counts.
- Continuous and restarted runs match prognostic state for both modes. Intentional reset diagnostics, including cache-held repair history, are stitched with explicit segment metadata rather than compared as if cumulative across restarts.
- At least one real file-based initialization and forcing dataset passes finite-state, physical-range and accounting checks. Archive input versions and verify the time interval actually covers the run.
- Parent-ledger tolerances for each claimed supported backend/rank/precision are calibrated by the repository protocol. Unsupported EDMF accounting remains blocked until M2's schema work is complete.
- Publish a capability matrix with tested, unsupported, and experimental entries. Topography, 2M/P3, multiple updrafts and alternate solvers gain support only through explicit qualification.

## M7 — Run a production trial before a production campaign

Use a short shakedown, then a ten-day trial, then a longer forcing period relevant to the intended science. Include startup, changing convection, cold conditions and at least one checkpoint restart. For the energy-source default, the existing ten-day sphere is insufficient because the [status record](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/f69ec02a6eac325b61cb6f30a6f259b1299293ec/experiments/tag_closure/OPERATIONAL_TODO.md#L113-L123) explicitly calls for another run with updraft mixing enabled.

**Acceptance criteria**

- No unaccounted nonfinite values, total-energy sign crossings, unexplained clipping bursts or unqualified model-top behavior. Audit parent physical health alongside tag closure.
- Predeclared dimensional and relative residual, per-tag error and intervention budgets hold over the complete interval, including restart transitions. Failures retain evidence and an explanation; no silent threshold relaxation.
- Resource budgets and checkpoint recovery work on the intended deployment configuration; a fresh environment can reproduce the documented entry command and analysis.
- Release documentation names the exact validated envelope, remaining limitations, reference/closure convention and reproducibility bundle. A successful run is not described as validated physics outside that envelope.

## M8 — Extend scientific reach without losing the controls

Prioritize water-tag convection using species-consistent inventories, paired air/energy provenance, and stratospheric pulse/age/residence diagnostics. The existing [stratospheric campaign plan](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/974f3e1659cddea96a69527017e30a6249ef8666/docs/strat_tracer_campaign_plan.md#L1-L30) provides a starting point. Add gross-loss memory diagnostics and conditional residual forecasts only after temporal cancellation and accepted-step semantics have been resolved.

**Acceptance criteria**

- Each extension declares a question and a falsifying experiment, a source-free or analytic control, and its own budget/positivity rules.
- Water-tag extensions close species and total-water budgets through phase changes and sedimentation. Energy weighting is not reused as a substitute for mass accounting.
- Air age, burden/source lifetime and energy attribution memory are reported as distinct quantities, with transient/steady assumptions stated.
- Forecasts are tested on withheld intervals and report uncertainty and invalidation conditions; they are never used to conceal an observed failed budget.

## Practical validation entry points

Use the repository's documented Julia 1.11 runtime and resolved environment. The following are **commands to run during implementation; they were not run in this review**:

```bash
TEST_GROUP=infrastructure julia +1.11 --project -e 'import Pkg; Pkg.test()'
TEST_GROUP=tagging_source_edmf julia +1.11 --project -e 'import Pkg; Pkg.test()'
TEST_GROUP=tagging_source_increment julia +1.11 --project -e 'import Pkg; Pkg.test()'
TEST_GROUP=tagging_source_updraft julia +1.11 --project -e 'import Pkg; Pkg.test()'
julia +1.11 --project=.buildkite .buildkite/ci_driver.jl --config_file <pinned-case.yml> --job_id <unique-run-id>
```

Add the other named groups only where affected or required by CI. Reuse sufficiently verified results at an unchanged tree. Dedicated artifact comparison, runtime benchmarks and GPU qualification remain separate gates rather than being inferred from green unit tests.

## Scope appendix — PR changes versus experiment-branch context

The PR review is restricted to this 24-file allowlist returned by GitHub:

| Area | Files changed by PR #95 |
| --- | --- |
| CI | `.github/workflows/ci.yml`; `.github/workflows/downgrade.yml` |
| Configuration/release | `NEWS.md`; `config/default_configs/default_config.yml`; `src/config/tracer_config.jl`; `src/types.jl` |
| Documentation | `docs/clima_atmos_specific.md`; `docs/make.jl`; `docs/src/energy_source_tags.md`; `docs/src/energy_source_tags_guide.md`; `docs/src/tracer_configuration.md` |
| Tag implementation | `src/parameterized_tendencies/tagged_tracers/energy_source_checkpoint.jl`; `src/parameterized_tendencies/tagged_tracers/energy_source_tags.jl`; `src/parameterized_tendencies/tagged_tracers/tagged_tracers.jl` |
| Wiring/setup | `src/prognostic_equations/implicit/implicit_tendency.jl`; `src/setups/Setups.jl`; `src/setups/common/prognostic_variables.jl` |
| Tests | `test/config/tracer_config.jl`; `test/energy_source_tags_cold_column.jl`; `test/energy_source_tags_edmf_integration.jl`; `test/energy_source_tags_increment_integration.jl`; `test/energy_source_tags_tests.jl`; `test/energy_source_tags_updraft_integration.jl`; `test/runtests.jl` |

The branch comparison's merge base is `38661891fac34b2a6b05470bc82199c5af9be0ec`. Experiment head has 280 unique commits; PR head has 70 unique commits. Complete tree inventories, both returned without truncation, show:

- **948 experiment-only files:** 944 under `experiments/tag_closure/` (including 715 output, 95 config and 83 analysis files), plus `runscripts/setup-julia-terrabyte.tcsh`, `runscripts/terrabyte_stacks.env`, `test/config/atmos_model_constructor.jl` and `toml/tag_closure_c1_reference.toml`.
- **7 PR-head-only files:** `docs/src/energy_source_tags_guide.md`, `src/parameterized_tendencies/tagged_tracers/energy_source_checkpoint.jl`, `test/config/atmos_model.jl`, and the cold-column, EDMF, increment and updraft energy-source integration test files.
- **139 differing common files:** include manifests, project and runtime infrastructure, physics/solver files such as `edmfx_sgs_flux.jl`, `mass_flux_closures.jl` and `manual_sparse_jacobian.jl`, and the tag implementation, tests and docs. These are two-tip differences, not 139 changes attributed to PR #95.

The GitHub commit-comparison response capped its file list at 300, so these counts were calculated from complete blob-path/SHA trees instead. [Pinned branch comparison](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/compare/974f3e1659cddea96a69527017e30a6249ef8666...f69ec02a6eac325b61cb6f30a6f259b1299293ec), [PR comparison](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/compare/c99ff7bd5005dd568a86a36b1ddff1389ac0c721...974f3e1659cddea96a69527017e30a6249ef8666).

The broader opportunities in this pathway intentionally use repository and branch context. They should not be turned into requirements that PR #95 fix unrelated pre-existing physics or infrastructure.
