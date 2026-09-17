# Review of the GitHub Actions test pipeline

Date: 2026-09-17. Scope: the workflows in `.github/workflows/`, the test groups in
`test/runtests.jl`, and the test files they run. The Buildkite pipeline belongs to
upstream ClimaAtmos and is not run by this repository, so it is out of scope.

This is a review, not a change. Nothing in the workflows or tests was modified. Every
number below comes from the GitHub Actions API and from the job logs of two `main` runs
(the merge of #80: `ci` run 35121778373, `Downgrade` run 35121778370) plus the
`Documentation`, `Downstream` and `Invalidations` runs of the same day. Every code claim
comes from reading the files named. Julia was not available where this was written, so
nothing was executed locally; the section "What still needs a machine with Julia" says
what a local run should add.

## 1. Summary

One pull request costs about 1740 runner-minutes in about 64 jobs. Since the fourteenth
test group landed on 2026-09-17 it is about 1820 and 68, see section 3. A pull request
that is merged pays the whole set twice, once on its own branch and once on the `main`
push. Only `ci-decide` can skip a repeat, and only for a merge-queue build.

The run measured took 9 h 06 min of wall time in `ci` and 8 h 16 min in `Downgrade`.
Almost all of that was queueing. Jobs waited 44 to 276 min in `ci` and 166 to 457 min in
`Downgrade` for a runner. At most 10 of the 54 test and preflight jobs ran at once, 5
within `ci` and 6 within `Downgrade`, while three other pull requests shared the same
queue. The wall time is therefore an artefact of how many jobs the account can run at
once, and the metric that drives it is runner-minutes and job count per pull request.

Where the minutes go, per pull request:

| item | minutes | share |
|---|---|---|
| dependency precompilation repeated in every job because the depot cache never restores | about 460 | 27 % |
| the tests themselves, of which 90 to 100 % is compilation of fresh model types | about 1030 | 59 % |
| checkout, package download, artifact download, coverage processing, cache save | about 120 | 7 % |
| Documentation, Downstream, Invalidations, prek | about 140 | 8 % |

Three facts found in the logs change the picture the repository's own comments paint:

1. **The Julia depot cache never restores.** All 54 test and preflight jobs of the two
   runs print `No cache found` and start from an empty depot. Each then re-precompiles
   the 400 to 450 dependencies of the test environment, 4.4 to 6.2 min on Julia 1.10 and
   7.8 to 12.5 min on 1.11. Each then saves its own 0.8 to 1.9 GB cache, 65.6 GB per push
   in total, against GitHub's 10 GB per-repository limit. The caches evict each other
   before the next run can read them.
2. **Coverage is collected and thrown away.** All 26 `ci` test jobs print `Token length:
   0` and Codecov answers "Token required - not valid tokenless upload". `Downgrade`
   never uploads at all. So the `coverage: true` default of `julia-runtest` costs compile
   time in 52 jobs and reaches nobody.
3. **The test minutes are compilation.** The `@time include` lines in the logs show 90
   to 100 % compilation for nearly every file. Weighted by time it is 97 % on the `ci`
   jobs of both versions. Shrinking grids or step counts therefore saves 1 to 2 min per
   job at best. Fewer distinct model types per file and fewer jobs are the levers that
   work.

The ranked list in section 9 reaches about 470 runner-minutes and 29 jobs per pull
request, a 73 % cut. It keeps every assertion. It keeps both Julia versions on the
fork-owned groups, minimum-compat testing weekly and on dependency changes, and the
coupler check. Most of the saving comes from two workflow changes: fixing the cache,
which loses nothing, and taking `Downgrade` off the per-PR path, which gives up
minimum-compat testing on source-only pull requests.

## 2. What must be kept ("the core")

The fork develops tagged tracers, tagged water, energy source tags, process records,
stratospheric passive tracers with the online tropopause, the parent-budget ledger and
diagnostics (`README.md:11`, `NEWS.md:22-26`, `NEWS.md:84-87`). Everything else tracks
upstream. The proposal, for the owner to confirm:

- Fork-owned groups run on both Julia versions of the compat range (`Project.toml:95`,
  `julia = "1.10"`): `tagging_energy`, `tagging_water`, `tagging_source`,
  `tagging_record`, `tagging_source_float32`, `parent_budget`, `diagnostics`,
  `infrastructure`. Julia 1.10 gave a version-specific signal this week, the 1056-byte
  solve allocation of #76, so it earns its place on these groups.
- Upstream-owned groups run on one version per pull request: `dynamics`,
  `dynamics_tracers`, `dynamics_edmfx`, `restarts`, `era5`. They stay in PR CI because
  they exercise the fork's tendency bracket. A 1.10-versus-1.11 divergence inside
  upstream code is upstream's to find.
- `parameterizations` is mixed, so it stays on both versions for now. Its heaviest file
  is `test/parameterized_tendencies/chemistry/passive_stratospheric_tracers.jl`
  (`runtests.jl:213`), the fork's stratospheric passive tracer test, about a third of the
  group's test time. Upstream has neither that file nor
  `src/parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl`. Moving it
  into a fork-owned group would let the rest run on one version.
- `using ClimaAtmos` on both versions stays (the `load` preflight, `ci.yml:56-76`).
- Minimum-compat resolution (`Downgrade`) runs weekly and whenever `Project.toml` or a
  manifest changes, not on every pull request.
- The coupler integration (`Downstream`) runs on one version with a timeout.

## 3. Measured cost per pull request

Runner minutes per workflow (job minutes are `completed_at - started_at` from the API):

| workflow | jobs | runner minutes | timeout | trigger gate |
|---|---|---|---|---|
| `ci.yml` (13 groups x 2 versions, 2 `load`, `ci-decide`, `ci-required`) | 30 | 800 | 90 min | none (`ci-decide` only skips merge-queue repeats) |
| `downgrade.yml` (the same 13 groups x 2 versions) | 26 | 803 | none (360 default) | none |
| `downstream.yml` (ClimaCoupler AMIP environment, 2 versions) | 2 | 103 to 118 | none | none |
| `docs.yml` | 4 | 20 | 60 min | `docs-decide`, merge-queue only |
| `Invalidations.yml` | 1 | 6 | none | base branch is default |
| `run-prek.yml`, `manifest-compat.yml` | 1 to 3 | about 2 | none | paths filter on manifest-compat only |
| total | about 64 | about 1740 | | |

Per group, minutes as job / dependency precompile inside `Pkg.test` / test wall time
(`Testing Running tests...` to `Testing ClimaAtmos tests passed`):

| group | ci 1.10 | ci 1.11 | Downgrade 1.10 | Downgrade 1.11 | 4-job total |
|---|---|---|---|---|---|
| infrastructure | 24.3 / 5.8 / 16.5 | 35.5 / 12.1 / 21.2 | 29.2 / 6.5 / 20.3 | 37.9 / 10.0 / 25.6 | 126.9 |
| parent_budget | 32.9 / 6.0 / 24.9 | 54.7 / 11.7 / 40.8 | 33.8 / 6.9 / 24.7 | 56.8 / 13.0 / 41.0 | 178.2 |
| diagnostics | 32.9 / 4.9 / 26.2 | 42.0 / 11.6 / 27.9 | 40.2 / 6.7 / 31.3 | 43.0 / 12.4 / 27.9 | 158.1 |
| dynamics | 13.6 / 6.1 / 5.7 | 21.7 / 12.5 / 6.9 | 14.2 / 6.7 / 5.5 | 17.2 / 9.6 / 5.4 | 66.7 |
| dynamics_tracers | 50.3 / 5.8 / 42.6 | 39.0 / 9.4 / 27.6 | 48.1 / 6.9 / 39.1 | 43.5 / 11.1 / 30.0 | 180.9 |
| dynamics_edmfx | 55.3 / 5.9 / 47.4 | 44.2 / 12.4 / 29.2 | 45.6 / 5.3 / 38.3 | 41.7 / 12.3 / 26.9 | 186.8 |
| tagging_energy | 21.6 / 5.8 / 14.0 | 36.4 / 11.8 / 22.0 | 16.3 / 5.0 / 9.2 | 37.2 / 12.5 / 21.9 | 111.5 |
| tagging_water | 21.0 / 4.4 / 14.9 | 52.7 / 9.1 / 41.6 | 27.6 / 6.9 / 18.7 | 44.8 / 12.6 / 29.2 | 146.1 |
| tagging_source | 15.4 / 4.6 / 8.8 | 31.6 / 12.1 / 17.3 | 21.1 / 7.0 / 12.1 | 31.8 / 12.4 / 16.9 | 99.9 |
| tagging_record | 12.5 / 5.9 / 4.6 | 22.4 / 12.2 / 7.7 | 10.3 / 5.0 / 3.5 | 22.7 / 12.5 / 7.7 | 67.9 |
| parameterizations | 17.9 / 5.9 / 9.8 | 20.3 / 9.2 / 9.1 | 14.7 / 5.3 / 7.6 | 19.5 / 8.9 / 8.3 | 72.4 |
| restarts | 31.2 / 6.1 / 23.1 | 37.6 / 12.0 / 23.1 | 31.4 / 6.5 / 22.7 | 38.5 / 12.4 / 23.4 | 138.7 |
| era5 | 9.6 / 5.9 / 1.8 | 11.4 / 7.8 / 1.7 | 13.0 / 5.7 / 5.5 | 22.8 / 12.3 / 7.9 | 56.8 |
| total | 338 / 73 / 240 | 449 / 144 / 276 | 346 / 81 / 239 | 457 / 152 / 272 | 1590 |

The remainder in each column, 25 to 33 min per 13 jobs, is checkout, package and artifact
download, coverage processing and the cache save. The `julia-buildpkg` step inside it is
only 0.5 to 0.9 min, because it downloads the packages and leaves precompilation to
`Pkg.test`. The two `load` jobs add 6.0 and 5.9 min. Of that, `using ClimaAtmos` is 5.2
and 4.4 min, which is the same cold precompile again.

Since the measured run, #75 (merged 2026-09-17) added a fourteenth group,
`tagging_source_float32`, to both matrices (`runtests.jl:186-190`, one file,
`energy_source_tags_float32_integration.jl`). On the pull requests running today its
jobs take 12 to 18 min on 1.10 and about 28 min on 1.11, so the per-PR cost is now about
80 min and 4 jobs higher than the tables above, 1820 min and 68 jobs. Everything below
uses the measured 13-group numbers; the new group belongs with the tagging groups in
every item.

Readings from the table:

- `era5` builds no simulation and downloads nothing. Its data is synthetic NetCDF written
  by `test/test_helpers.jl:432`. Its 1.7 min of tests sit inside a 9.6 to 22.8 min job.
  The rest is the floor every job pays, precompile plus download plus cache save. So a
  job removed saves about 8 min today, and about 3 min once the cache works, whatever it
  contains.
- On the fork-owned groups Julia 1.11 costs 1.1 to 2.8 times the 1.10 test time, from
  1.07 on `diagnostics` to 2.80 on `tagging_water`. `runtests.jl:146-149` measured the
  cause, "about 7 minutes per simulation on 1.11 against 1 to 2 minutes on 1.10".
- On `dynamics_tracers` and `dynamics_edmfx` the order flips. There 1.10 takes 1.54 and
  1.62 times the 1.11 test time. Section 5 explains why.
- Dependency precompile alone is 73 + 144 + 81 + 152 + 9 = about 460 min per pull
  request. That is more than the upstream half of the test minutes, 448, though less
  than the fork-owned half, 578.

## 4. Where the test minutes go, file by file

`runtests.jl` wraps every file in `@time include(...)`, so each log carries the file's
seconds and its compilation share. The sixteen most expensive files on `ci 1.11`, with
the cumulative minutes:

| min | group | file (testset label) | compile | cumulative |
|---|---|---|---|---|
| 41.6 | tagging_water | Tagged water integration | 99 % | 42 |
| 23.1 | diagnostics | Diagnostics unit tests | 100 % | 65 |
| 22.0 | tagging_energy | Tagged tracers integration | 98 % | 87 |
| 20.3 | dynamics_tracers | Tracer/mass transport consistency | 100 % | 107 |
| 19.3 | restarts | Restarts | 85 % | 126 |
| 17.6 | dynamics_edmfx | EDMFX horizontal diffusive flux | 100 % | 144 |
| 17.3 | tagging_source | Energy source tags integration | 99 % | 161 |
| 11.5 | dynamics_edmfx | EDMFX SGS diffusive flux | 99 % | 173 |
| 9.3 | parent_budget | Parent-budget report | 95 % | 182 |
| 9.1 | parent_budget | Parent-budget envelopes | 99 % | 191 |
| 8.7 | parent_budget | Parent-budget transfers | 100 % | 200 |
| 8.7 | parent_budget | Parent-budget implicit attribution | 100 % | 208 |
| 7.7 | tagging_record | Process record integration | 99 % | 216 |
| 5.9 | infrastructure | Presets | 100 % | 222 |
| 4.8 | dynamics_tracers | Enforce physical constraints | 100 % | 227 |
| 4.5 | parameterizations | Microphysics tendency tests | 100 % | 231 |

Sixteen of the 74 files that ran carry 231 of the 275 test minutes on 1.11. On 1.10 the
order changes. There EDMFX horizontal diffusion takes 33.1 min, tracer/mass consistency
26.8, diagnostics unit tests 21.0, restarts 19.7 and tagged water 14.8. The shares do not
change: everything above 5 min is 85 to 100 % compilation. The exceptions are on
`Downgrade`, where `Aqua` (9 min at 3 %) and the two ERA5 files (5 to 8 min at 20 to
30 %) are run time rather than compilation. The full per-file table for all four job
variants is in appendix A.

The next table says what the top files build. `Builds` counts `get_simulation` and
`AtmosSimulation` calls. `Types` counts distinct `AtmosModel` and `AtmosCache`
signatures, which is the unit of recompilation.

| file | builds | types | note |
|---|---|---|---|
| `test/tagged_water_integration.jl` | 5 | 4 | four tag signatures on two geometries, one sphere; fork-owned |
| `test/diagnostics/unit_diagnostics.jl` | 0 | 15 | 17 `build_state_cache` calls over 15 model types, Float32. Cache only, no solve |
| `test/tagged_tracers_integration.jl` | 4 | 3 | one sphere with 5 tags, two DYCOMS columns; `NEWS.md:39` measured 36m57s at 99 % compilation |
| `test/prognostic_equations/tracer_mass_consistency_tests.jl` | 2 | 2 | one is a full prognostic-EDMFX 1M column with 10 implicit steps; upstream |
| `test/restart.jl` | 3 | 1 | the `amip_target` model, the heaviest single model in the suite; upstream |
| `test/prognostic_equations/edmfx_horizontal_diffusion_tests.jl` | 5 | 4 | plus 3 construction-failure paths; upstream |
| `test/energy_source_tags_integration.jl` | 6 | 5 | base, with offset, 1M with offset, enthalpy transport with offset, and a sphere with enthalpy transport (`:101`, `:201`, `:275`, `:374`, `:513`). The offset, the microphysics and the transport are all type parameters (`:38-45`). The 17.3 min was measured at commit 2f60df8, when the file had 3 types. #72 added the last two compiles after that run, so expect 30 min or more on 1.11 |
| `test/parent_budget/*.jl` (6 files) | about 45 | about 8 | dozens of identical-type `column_simulation()` calls (cheap) plus 5 `get_simulation` configs and the `ARS222`, slab-surface and gross-attribution variants |
| `test/process_record_integration.jl` | 2 | 1 | designed as one record set (`:28-29`) |
| `test/presets.jl` | ? | ? | 4.5 to 5.9 min at 100 % compilation inside `infrastructure`. Worth a look, ownership to check |
| `test/surface_albedo.jl` | 3 | 3 | three albedo constructors, each built to a full simulation for what are constructor assertions (`:22`, `:34`, `:47`), 112 to 152 s at 99 % compilation |

## 5. Compile flags and the coverage mechanism

`ci.yml:124` and `downgrade.yml:64` call `julia-actions/julia-runtest` with no `with:`
block. The action's `action.yml` defaults are `check_bounds: yes`, `coverage: true`,
`depwarn: yes`. What that does, verified in the sources:

- `Pkg.test(coverage=true)` passes `--code-coverage=@<package dir>` to the test process
  (Pkg `src/Operations.jl`, `gen_subprocess_flags`), the tracked-path mode, not `user`.
  Pkg also passes `--check-bounds=yes` on its own, so the action's `check_bounds` input
  only restates the default.
- On Julia 1.10, `src/jloptions.c:862-868` sets `use_pkgimages = 0` whenever coverage or
  allocation tracking is on. Every 1.10 test job therefore loads no native code from any
  package image and compiles the whole ClimaCore stack again at test time. That is why
  the test time of `dynamics_tracers` and `dynamics_edmfx` on 1.10 is 1.54 and 1.62 times
  the 1.11 time in `ci`, against the trend on the tagged groups. In whole job minutes the
  ratio is only 1.1 to 1.3, because the 1.11 jobs spend longer precompiling.
- On Julia 1.11, `base/loading.jl:1210-1224` and `pkg_tracked` (`:1901-1924`, called at
  `:1219`) drop native code only for the tracked package, ClimaAtmos itself. Dependencies
  keep their images. So turning coverage off helps 1.11 less.
- `--check-bounds=yes` is one of the pkgimage cache flags (`jl_cache_flags` in
  `src/staticdata_utils.c`), so the test environment always needs its own precompiled
  variant, separate from the one the `load` job or `julia-buildpkg` builds. Today this
  does not matter, because nothing is cached anyway. Once the cache works it means the
  first test job per version has to build the variant and save it.
- Coverage is uploaded only by `ci.yml:125-129`, and the upload fails in all 26 jobs
  (`Token length: 0`, "Token required - not valid tokenless upload", the step still
  reports success). `Downgrade` generates coverage and never uploads it. The README
  badge (`README.md:17`) shows whatever Codecov last received.

## 6. Duplication between `ci.yml` and `downgrade.yml`

The two matrices are byte-identical, `ci.yml:101-114` against `downgrade.yml:38-51`, 13
groups times 2 versions in each. `Downgrade` differs by `julia-downgrade-compat@v2` in
`forcedeps` mode and by the `CLIMAATMOS_DOWNGRADE_CI` variable. That variable is read in
exactly two places, `test/aqua.jl:32` and `test/dependencies.jl:37`, both to switch a
check off. Its signal is that the package resolves and runs at minimum compat bounds, a
class of failure that surfaces in any one group, almost always at resolution or package
load. `Downgrade` has no gate, no path filter and no timeout, so a hung job can burn six
hours.

Three details from its logs and its file:

- `Aqua` takes 5.5 to 9 min there against 0.7 to 0.9 min in `ci`, at 3 % compilation. The
  `persistent_tasks` subprocess is precompiling the downgraded environment a second time.
- The `era5` tests run three to five times slower on the minimum NetCDF stack, 224 + 104 s
  against 79 + 25 s on 1.10 and 324 + 147 s against 79 + 21 s on 1.11.
- `downgrade.yml:54, 63, 64` pin `setup-julia`, `julia-buildpkg` and `julia-runtest` to
  `@latest`, where `ci.yml:70, 74, 124` pin `@v3` and `@v1`. The two workflows can
  therefore drift apart without any change in this repository.

## 7. Artifacts: leftover tests and duplicated work

The owner's word "artifacts" meant leftover tests and duplicated work. The findings, all
in upstream-owned files unless noted:

- **Dead in CI.** `test/restart.jl:192-266`, the `MANYTESTS` sweep over sphere, box and
  column configurations, is unreachable. `test/restart_utils.jl:29` defaults `MANYTESTS`
  to false and CI passes no `--manytests`, so only the `else` branch at `:267` runs.
  `test/restart_AtmosSimulation.jl` and `test/restart_utils.jl`'s other callers are not
  referenced by `runtests.jl` at all (`docs/known_issues.md:191-194, 205-211` already
  record the orphans and the duplicated restart contract).
- **Same-type duplicate builds.** `test/prognostic_equations/edmfx_horizontal_diffusion_tests.jl:57`
  and `:242` build the identical `box_config_dict()`;
  `test/prognostic_equations/enforce_physical_constraints_tests.jl:33-192` builds one
  dict eight times under eight job ids;
  `test/prognostic_equations/vertical_water_borrowing_tests.jl:34` and `:59` are the same
  config; `test/parameterized_tendencies/microphysics/allocations.jl:296-376` rebuilds
  the three models of `tendency.jl:89-218`. Each repeat costs seconds, not minutes,
  because the type is already compiled. The `@time` shares above confirm it.
- **A stale label.** `runtests.jl:236` calls `era5` "(heavy)". It builds nothing.
- **GitHub Actions artifacts.** No hand-written workflow uploads or downloads any. The
  only `actions/upload-artifact` uses are inside the generated `pr-review.lock.yml`,
  which runs on the `/agent_review` command only.
- **CliMA data artifacts.** Only `restarts` (`test/restart.jl:274-318`: orography,
  aerosols, ozone, CO2, RRTMGP tables; `test/test_init_with_file.jl:6`: the DYAMOND
  initial condition) and two `infrastructure` files with `rad: clearsky`
  (`test/surface_albedo.jl:15`, `test/coupler_compatibility.jl:123`, RRTMGP tables)
  download anything. Nothing in `era5` touches `Artifacts.toml`.

The leftovers are real, and they are not where the minutes are. Removing them would edit
upstream files, which `docs/known_issues.md:159-167` rules out because every future merge
would then conflict. The place to record them is that same list, under the existing
heading at `docs/known_issues.md:159`.

## 8. Gating, timeouts, caching

- `timeout-minutes` exists only at `ci.yml:61` (`load`, 30), `ci.yml:89` (`test`, 90)
  and `docs.yml:50` (60). `Downgrade`, `Downstream`, `Invalidations` and prek fall back
  to GitHub's 360 min.
- A `paths:` filter exists only in `manifest-compat.yml:16-20`. Every other workflow
  runs the full matrix for a docs-only or test-only change.
- `julia-actions/cache@v3` is present in `ci.yml`, `downgrade.yml`, `docs.yml`,
  `downstream.yml` and `manifest-compat.yml`, absent from `Invalidations.yml`. It never
  restores anywhere (section 1). Its key is
  `julia-cache;workflow=ci;job=test;os=Linux;version=1.11;os=ubuntu-latest;test_group=<group>;run_id=<id>;run_attempt=1`
  and the restore prefix drops the run id and the attempt, so a job can only ever reuse a
  cache saved by the same group and version in an earlier run. Each job saves 0.8 to
  1.9 GB, from the `Sent ... of ...` line in the post step, and 54 jobs saved 65.6 GB in
  one push. GitHub keeps 10 GB per repository and evicts the least recently used. The
  `Downstream` jobs sit on the same cold start, with 44 to 59 min of `Pkg.instantiate`
  for the coupler environment, and so does the docs build, with 11 min of "Install
  dependencies". The cache API is not reachable from here, so the repository's Actions
  "Caches" page is where to confirm what survives.
- `ci` runs on `main` never cancel (`ci.yml:13`). `Downgrade`, `Downstream` and the docs
  build do cancel unconditionally (`downgrade.yml:16`, `downstream.yml:16`,
  `docs.yml:13`). On 2026-09-17 three merges within thirty seconds (#72, #74, #75)
  therefore started three full `ci` runs, while their `Downgrade`, `Downstream` and docs
  runs cancelled each other.

## 9. Ranked simplifications

Savings are runner-minutes per pull request, measured or derived from the tables above.
"Alone" is the saving against today's 1740 with nothing else changed. "In sequence" is
the additional saving once the items above are in place, so that column adds up to the
end state. Where a group is folded into another rather than dropped, the saving is the
job overhead only, because the tests move with it.

Two preconditions apply to items 1 and 8. Branch protection must not require any job that
a `paths` filter would skip, or a filtered pull request waits forever on an "Expected"
check. And the `push` trigger on `main` has to be filtered too, otherwise every merge
still pays the full matrix.

| # | change | saves alone | in sequence | kept / lost | upstream-merge risk | effort | confidence |
|---|---|---|---|---|---|---|---|
| 1 | Take `Downgrade` off the per-PR path. Weekly `schedule`, `workflow_dispatch`, and `pull_request` plus `push` filtered with `paths: [Project.toml, .github/workflows/downgrade.yml]`. Add `timeout-minutes: 90` and `coverage: false` | 803, 26 jobs | 803, 26 jobs | keeps minimum-compat testing weekly and on compat changes. Loses it on source-only pull requests, which `docs/dev-guides/workflow/ci_triage.md:21` says is where downgrade failures usually come from. Such a failure would then surface in the weekly `main` run, after the merge, with no attribution to the pull request | none | small | high |
| 2 | Make the depot cache restore. One cache per Julia version, shared by every group, so a push saves about 3 GB instead of 65 GB | about 460 across the 54 jobs. `Downstream` and `docs` need their own change, worth 50 to 70 more | about 226, the `ci` share | loses nothing. A stale cache costs one re-precompile | none | small, but read section 10 first | the miss is measured in all 54 logs and the saving equals the measured precompile minutes |
| 3 | Run the five upstream-owned groups on Julia 1.11 only, with a matrix `exclude` in `ci.yml` | 160, 5 jobs | about 130, 5 jobs | keeps both versions for fork-owned groups, for `parameterizations` and for `load`. Loses a 1.10 divergence inside upstream code. Becomes 178 and 6 jobs once `passive_stratospheric_tracers.jl` moves out of `parameterizations` | none. Update `docs/clima_atmos_specific.md:54-64` and `AGENTS.md:20` | small | numbers high, the policy is the owner's |
| 3b | Alternative to 3. Drop 1.10 from pull-request CI entirely and run it weekly beside `Downgrade` | 344, 14 jobs | about 265, 14 jobs | loses 1.10 on the fork's own code while `Project.toml:95` still promises it. 1.10 found the #76 allocation | none, but the compat entry should then be raised or the weekly run kept | small | low as policy |
| 4 | `coverage: false` in `ci.yml`, and in `Downgrade` through item 1, until a Codecov token exists. With a token, keep coverage on the 1.11 jobs only | 48 to 96 on the 1.10 jobs, 20 to 40 % of their 240 test minutes, less the pkgimage emission the first uncached run pays | about 30 to 55 | loses nothing today, because every upload already fails. With a token it would lose 1.10 coverage and keep 1.11 | none | trivial | mechanism verified, magnitude to be read off the first run after the change |
| 5 | Fewer distinct model types in the heaviest fork-owned files. `tagged_water_integration.jl` (4 types, 41.6 min), `energy_source_tags_integration.jl` (5 types, 17.3 min measured at 3), `diagnostics/unit_diagnostics.jl` (15 cache types, 23 min), `tagged_tracers_integration.jl` (3 types, 22 min), `surface_albedo.jl` (3 types, 2.5 min) | 7 to 10 min per removed solve type on 1.11 and 3 to 5 on 1.10. A cache-only Float32 model is worth about 1.5 min | about 30 to 60 | each removed type is one tag or diagnostics configuration no longer built. Assertions that stay can often move onto a type that is built anyway (`runtests.jl:157-160`) | none, fork-owned | medium, needs Julia | high on the mechanism, per-file decisions needed |
| 6 | Fold `era5` into `dynamics` in `runtests.jl` and both matrices | about 40, 4 jobs. 57 job minutes go, 17 min of tests move into `dynamics` | about 2 to 3, 1 job | keeps every assertion. Loses a separate failure label for two files that build nothing | none | small | high |
| 7 | Fold `tagging_record` into `tagging_source`, which uses the same DYCOMS column geometry (`process_record_integration.jl:35-59` against `energy_source_tags_integration.jl:73-99`). `runtests.jl:176-185` already argues against folding the new `tagging_source_float32` group, because its model configures tags and records together and shares a type with neither file, so leave that one alone | about 44, 4 jobs. 68 job minutes go, 24 min of tests move into `tagging_source` | about 5, 2 jobs | keeps every assertion. Bends the one-file-per-tagging-group rule of `runtests.jl:151-160` and the headroom comment at `ci.yml:86-88`, both of which need updating with `docs/clima_atmos_specific.md:52, 76-96`. The two files build different model types, so the merged job is the plain sum, and `energy_source_tags_integration.jl` has grown to five types since it was measured | none | small | medium, re-time first |
| 8 | `Downstream` on one version, with `timeout-minutes: 120` and `paths` on `src/**`, `ext/**`, `Project.toml` | 55 to 110, 1 job | about 20, 1 job | loses the 1.10 coupler check and the check on test-only pull requests | none | small | high |
| 9 | `Downgrade` only: `persistent_tasks = false` in downgrade mode (`test/aqua.jl:33-37`) | 5 to 9 per `Downgrade` infrastructure job | 0 on the PR path after item 1 | loses Aqua's persistent-task check at minimum bounds | none | trivial | medium |
| 10 | Shrink grids and step counts, for example the three sphere runs at h_elem 4, z_elem 10 and 12 steps, or the `t_end` values the tests never reach | 1 to 2 min per job at most | a few | tolerances measured at the current settings would need re-measuring. `parent_budget/report_tests.jl:273` asserts `commits == 12`, which is `t_end/dt`, so that file's step count and its assertion move together | high for upstream files | medium | low value, not recommended |
| 11 | Documentation: `doctest` (`docs/make.jl:40`) on `main` only. Invalidations: add the cache step | a few of the 20 min | a few | per-pull-request doctests, per-pull-request invalidation attribution | none | small | lowest. `linkcheck` (`docs/make.jl:54`) is not worth touching, `docs/make.jl:49-56` says it costs seconds |
| 12 | Record the dead scaffolding and same-type duplicate builds of section 7 in the upstream list at `docs/known_issues.md:159` | 0 | 0 | nothing CI runs | high if the files are edited, none if only recorded | small | document only |

Three candidates were rejected:

- Merging `dynamics` into `dynamics_edmfx`. The merged `ci 1.10` job would run about
  53 min of tests, 47.4 plus 5.7 measured, and take about 60 min in all. That is over the
  "under half the 90-minute limit" rule of `runtests.jl:112-122` and the headroom comment
  at `ci.yml:84-89`.
- `check_bounds: 'no'`. It buys no compile time once the cache works, and it gives up
  bounds checking in the tests.
- Treating `Invalidations.yml` as expensive. It is 6 min.

Conflicts between the items:

- 3 and 3b are alternatives.
- 4 loses most of its value under 3b, because no 1.10 job would be left.
- 7 bends the one-file-per-tagging-group rule.
- 1 already includes coverage off in `Downgrade`.

End state with items 1, 2, 3, 4, 5, 6, 7 and 8: about 470 runner-minutes and 29 jobs per
pull request, against 1740 and 64 today. With 3b instead of 3 it is about 370 and 21.
Wall time to green falls with the job count, because the queue is the bottleneck, and
every remaining job is 5 to 12 min shorter from the cache alone.

Phased order:

- Phase A, one pull request, workflow files only: items 1, 2, 4, 6, 8. Item 2 loses
  nothing and item 4 loses nothing today. Items 1 and 8 give up the coverage named in
  their kept/lost cells, and both need the required-checks question answered first. The
  first `main` run after this measures item 2 directly, from the `Cache restored from key`
  line and the "already precompiled" count, and item 4 from the 1.10 test minutes against
  the table in section 3.
- Phase B, after the owner decides the 1.10 policy: item 3 or 3b.
- Phase C, needs Julia: item 5, one file at a time, each with its own run.
- Phase D, if the numbers still justify it: items 7, 9, 11.

## 10. Design notes for the cache fix (item 2)

The action keys the cache by the matrix (`include-matrix: true` by default), so each
group saves its own copy of the same depot. Two designs, in order of preference:

1. Keep `julia-actions/cache@v3` and give every test job of a version the same name,
   `cache-name: julia-cache;version=${{ matrix.version }}` with `include-matrix: false`.
   The action builds its key as `<cache-name>;os=<os>;<matrix>;run_id=..;run_attempt=..`
   and its restore key without the last two fields, so one name per version is all it
   takes. `downgrade.yml` needs its own name, because its depot is the downgraded one.

   Two traps here. The first is the `load` job. `test` needs `load` (`ci.yml:80`), so
   `load` always saves first, every test job then hits its key exactly, and the action
   skips the test job's own save with "Cache hit occurred on the exact key, not saving
   cache". That depot has no `--check-bounds=yes` variant, which is what `Pkg.test`
   precompiles, so the test-environment precompile would survive and `ci` would keep its
   217 min. Give `load` a different `cache-name`, or drop its cache step, so the first
   test job to finish is the one that saves.

   The second is `delete-old-caches`. It does not clean up on the default branch, so
   `main` accumulates about 1.3 GB per version and workflow on every push until GitHub
   evicts the least recently used. The newest cache is always the one restored, so this
   works, but expect about 5 GB per push rather than one cache per name.

   On the first run, check two lines: `Cache restored from key: ...` in the cache step,
   and a `Pkg.test` precompile line that reports most dependencies as already
   precompiled. The second only happens if the saved depot came from a job that ran
   `Pkg.test` with the same flags, which is the `check_bounds` variant of section 5.
2. If the action cannot be made to share, use `actions/cache/restore` and
   `actions/cache/save` directly, with `save` conditioned on `github.ref ==
   'refs/heads/main'` and a key built from the version and the hash of `Project.toml`.
   This also stops pull requests from filling the cache, since a branch cache is scoped
   to its branch and counts against the same 10 GB.

`downstream.yml:33` and `docs.yml:61` have the same problem and need the same treatment
to earn the 50 to 70 min in item 2's "alone" column. Either design should be measured on
the run that introduces it, before item 5 starts, because a working cache changes what
"expensive" means for every file.

## 11. Open questions for the owner

1. Is Codecov used for anything but the README badge? If not, coverage can stay off; if
   yes, the `CODECOV_TOKEN` secret needs to be set, and coverage kept on 1.11 only.
2. Is Julia 1.10 a commitment (users on 1.10) or inertia? It decides between items 3 and
   3b and whether `Project.toml:95` moves.
3. Is a weekly `Downgrade` plus a run on every dependency change acceptable?
4. Does the fork's work reach ClimaCoupler at all? If not, `Downstream` could run on
   `main` and weekly only.
5. Do upstream test files stay untouched even where they cost minutes
   (`edmfx_horizontal_diffusion_tests.jl`, `tracer_mass_consistency_tests.jl`,
   `restart.jl`)? The review assumes yes, per `docs/known_issues.md:159-167`.
6. What ceiling replaces "under half the limit" for merged groups (items 6 and 7)?
7. Are bursts of merges to `main` typical? There were three in thirty seconds today. If
   so, a merge queue would avoid the triple `ci` runs, and the unconditional
   `cancel-in-progress` in the other three workflows means their results for the first
   two merges were thrown away.
8. Which status checks does branch protection require? Items 1 and 8 add `paths` filters,
   and a required check that never runs leaves a pull request unmergeable.

## 12. What still needs a machine with Julia (handover brief)

This session had no Julia. A local agent with Julia 1.11 (and 1.10 if the policy keeps
it) should take over from here, on a branch off `main`, with this file as the brief.

Do first, without Julia, as one pull request (Phase A):

- `.github/workflows/downgrade.yml`: put the `paths` list of item 1 on both the
  `pull_request` and the `push` trigger, add `schedule: cron: '0 3 * * 1'` and
  `workflow_dispatch`, add `timeout-minutes: 90` to the job, and pass `coverage: false`
  to `julia-runtest`. Leaving the `push` trigger open would keep all 26 jobs on every
  merge.
- `.github/workflows/ci.yml` and `downgrade.yml`: the cache change of section 10,
  design 1, in the `load` and `test` jobs. Pass `coverage: false` to `julia-runtest`
  (item 4) until a Codecov token exists.
- `test/runtests.jl` and both matrices: move the two `era5` files into the `dynamics`
  block and delete the `era5` group from `KNOWN_TEST_GROUPS` and both `test_group`
  lists (item 6). Fix the "(heavy)" comment while there.
- `.github/workflows/downstream.yml`: one version, `timeout-minutes: 120`, `paths`
  (item 8).
- `docs/clima_atmos_specific.md:54-64` and `:97-104`: the group table and the
  single-group instructions must match the new lists.

Then measure on the first `main` run, which needs no Julia. Item 2 has worked when the
cache step prints `Cache restored from key: ...` and the `Pkg.test` precompile line
reports most dependencies as already precompiled, which should take the precompile line
from 4 to 12 min down to under a minute. Item 4 has worked when the 1.10 test minutes
fall below the table in section 3 by more than the 3 min of extra precompile that
emitting pkgimages costs on an uncached run.

Then, with Julia (Phase C, item 5), one file per pull request:

- `test/tagged_water_integration.jl`: list the four tag signatures (lines 105, 244, 352,
  453) and decide which assertions can move onto a signature that is built anyway. The
  sphere limiter case (`:244`) is the only extruded-space coverage in the file and
  should stay. Run the file alone (`TEST_GROUP=tagging_water julia --project -e 'using
  Pkg; Pkg.test()'`) before and after and record `@time` and the compile share.
- `test/diagnostics/unit_diagnostics.jl`: 15 model types at `:161-337`, used by 17
  `build_state_cache` calls, all cache-only. Group the diagnostics by the model features
  they need and build one model per feature set. This file is the fork's own diagnostics
  work, so it is in scope, unlike the upstream files in the same groups.
- `test/tagged_tracers_integration.jl` (`:90`, `:164`, `:224`) and
  `test/energy_source_tags_integration.jl` (`:101`, `:201`, `:275`, `:374`, `:513`).
  Same procedure. Time the energy source file first, because #72 took it from three
  model types to five after the measurement in this review, and the sphere at `:513` is
  the newest and probably the most expensive. The offset variant at `:201` exists only
  because the offset is a type parameter, so a test of the offset logic that needs no
  full solve is the first candidate to drop.
- `test/surface_albedo.jl` (`:22`, `:34`, `:47`): three full simulations for three
  albedo constructors. Check whether the assertions need a solved simulation at all.
- Item 7 only after that, with the merged group timed once.

Validation for every step: `Pkg.test()` with the group's `TEST_GROUP` locally, the
formatter from `.dev/format` (`prek run julia-formatter --all-files`), and one CI run
read back against the tables here.

## Appendix A. Per-file seconds and compilation share, all four variants

Seconds of `@time include` per file, with the compilation share in parentheses. A dash
means the file did not run in that variant. The `Restarts` file wraps a second `@time`
inside, and the inner number is the one shown. The table has 74 rows, one per file the
measured runs executed. Two files of today's `runtests.jl` are missing from it, because
they landed after the measurement: `Seasonal SST` (`runtests.jl:69`) and the whole
`tagging_source_float32` group.

| group | file (testset label) | ci 1.10 | ci 1.11 | Downgrade 1.10 | Downgrade 1.11 |
|---|---|---|---|---|---|
| infrastructure | Aqua | 40 (24 %) | 52 (34 %) | 331 (3 %) | 546 (3 %) |
| infrastructure | Dependencies | 0 (94 %) | 1 (96 %) | 0 (94 %) | 0 (96 %) |
| infrastructure | Callbacks | 1 (97 %) | 1 (98 %) | 1 (98 %) | 1 (98 %) |
| infrastructure | Configuration tests | 5 (96 %) | 7 (98 %) | 6 (97 %) | 7 (98 %) |
| infrastructure | Grids | 17 (100 %) | 20 (100 %) | 15 (100 %) | 16 (100 %) |
| infrastructure | Utilities | 87 (98 %) | 115 (99 %) | 85 (99 %) | 94 (99 %) |
| infrastructure | Variable manipulations | 5 (95 %) | 4 (94 %) | 6 (97 %) | 4 (95 %) |
| infrastructure | Tracer processes | 13 (98 %) | 16 (98 %) | 14 (98 %) | 14 (98 %) |
| infrastructure | Tagged tracers | 7 (96 %) | 11 (98 %) | 7 (97 %) | 9 (98 %) |
| infrastructure | Tagged water | 8 (97 %) | 15 (98 %) | 8 (97 %) | 12 (99 %) |
| infrastructure | Energy source tags | 8 (97 %) | 15 (98 %) | 7 (97 %) | 12 (99 %) |
| infrastructure | Process records | 2 (96 %) | 3 (97 %) | 2 (96 %) | 3 (97 %) |
| infrastructure | Parent-budget packets | 3 (96 %) | 4 (97 %) | 3 (97 %) | 3 (98 %) |
| infrastructure | Parent-budget registry | 9 (97 %) | 13 (98 %) | 9 (97 %) | 10 (98 %) |
| infrastructure | Parent-budget journal | 5 (69 %) | 5 (72 %) | 5 (72 %) | 4 (77 %) |
| infrastructure | Parent-budget endpoints | 14 (98 %) | 17 (98 %) | 13 (98 %) | 14 (99 %) |
| infrastructure | Parameter tests | 14 (82 %) | 17 (87 %) | 13 (83 %) | 13 (87 %) |
| infrastructure | Check TOML path | 96 (100 %) | 116 (100 %) | 93 (100 %) | 94 (100 %) |
| infrastructure | Radiation interface tests | 6 (98 %) | 10 (99 %) | 5 (98 %) | 7 (99 %) |
| infrastructure | Coupler compatibility | 212 (100 %) | 249 (100 %) | 201 (100 %) | 200 (100 %) |
| infrastructure | Surface albedo tests | 112 (99 %) | 152 (99 %) | 100 (98 %) | 129 (99 %) |
| infrastructure | Larcform1 setup | 32 (100 %) | 46 (100 %) | 31 (100 %) | 39 (100 %) |
| infrastructure | SlabOcean SST warning | 1 (92 %) | 2 (93 %) | 1 (90 %) | 1 (94 %) |
| infrastructure | Model getters | 0 (30 %) | 0 (37 %) | 0 (16 %) | 0 (38 %) |
| infrastructure | Tracer config | 13 (95 %) | 19 (97 %) | 14 (94 %) | 16 (96 %) |
| infrastructure | AtmosModel Constructor | 1 (95 %) | 2 (96 %) | 1 (93 %) | 2 (97 %) |
| infrastructure | Presets | 271 (100 %) | 354 (100 %) | 240 (100 %) | 278 (100 %) |
| infrastructure | Topography tests | 3 (96 %) | 3 (97 %) | 3 (97 %) | 4 (98 %) |
| parent_budget | Parent-budget envelopes | 329 (99 %) | 544 (99 %) | 317 (99 %) | 593 (99 %) |
| parent_budget | Parent-budget implicit attribution | 315 (100 %) | 521 (100 %) | 308 (100 %) | 539 (100 %) |
| parent_budget | Parent-budget explicit attribution | 130 (99 %) | 155 (99 %) | 128 (99 %) | 158 (99 %) |
| parent_budget | Parent-budget transfers | 248 (100 %) | 523 (100 %) | 247 (100 %) | 496 (100 %) |
| parent_budget | Parent-budget restarts | 103 (99 %) | 143 (100 %) | 106 (99 %) | 137 (100 %) |
| parent_budget | Parent-budget report | 368 (97 %) | 559 (95 %) | 373 (97 %) | 533 (94 %) |
| diagnostics | Diagnostics unit tests | 1257 (100 %) | 1388 (100 %) | 1528 (100 %) | 1371 (100 %) |
| diagnostics | DiagnosticsConfig | 0 (85 %) | 0 (87 %) | 0 (85 %) | 0 (86 %) |
| diagnostics | COSP subcolumn tests | 263 (92 %) | 245 (93 %) | 290 (92 %) | 252 (92 %) |
| diagnostics | COSP CloudSat optics tests | 31 (73 %) | 23 (71 %) | 35 (72 %) | 28 (71 %) |
| diagnostics | COSP CloudSat reflectivity tests | 5 (62 %) | 8 (78 %) | 6 (63 %) | 9 (78 %) |
| diagnostics | COSP CloudSat cloud fraction tests | 6 (36 %) | 6 (43 %) | 9 (43 %) | 8 (46 %) |
| diagnostics | COSP CloudSat CFAD tests | 6 (89 %) | 6 (90 %) | 7 (88 %) | 6 (90 %) |
| dynamics | Prognostic equations | 7 (46 %) | 8 (39 %) | 7 (46 %) | 6 (38 %) |
| dynamics | Advection operators | 138 (100 %) | 164 (100 %) | 133 (100 %) | 129 (100 %) |
| dynamics | Post-Newton implicit-advection correction | 151 (100 %) | 178 (100 %) | 143 (100 %) | 134 (100 %) |
| dynamics | Vertical diffusion tendency | 32 (99 %) | 51 (99 %) | 34 (99 %) | 42 (99 %) |
| dynamics | Eddy diffusion closures | 11 (97 %) | 14 (94 %) | 11 (98 %) | 10 (98 %) |
| dynamics_tracers | Tracer/mass transport consistency | 1606 (100 %) | 1219 (100 %) | 1601 (100 %) | 1360 (100 %) |
| dynamics_tracers | Vertical water borrowing limiter | 262 (100 %) | 146 (100 %) | 216 (100 %) | 153 (100 %) |
| dynamics_tracers | Enforce physical constraints | 687 (99 %) | 291 (100 %) | 530 (100 %) | 285 (100 %) |
| dynamics_edmfx | EDMFX SGS diffusive flux | 849 (100 %) | 691 (99 %) | 621 (99 %) | 614 (99 %) |
| dynamics_edmfx | EDMFX horizontal diffusive flux | 1988 (100 %) | 1059 (100 %) | 1675 (100 %) | 996 (100 %) |
| tagging_energy | Tagged tracers integration | 838 (98 %) | 1318 (98 %) | 552 (98 %) | 1310 (98 %) |
| tagging_water | Tagged water integration | 891 (98 %) | 2494 (99 %) | 1124 (98 %) | 1750 (98 %) |
| tagging_source | Energy source tags integration | 529 (98 %) | 1036 (99 %) | 726 (99 %) | 1010 (99 %) |
| tagging_record | Process record integration | 276 (98 %) | 463 (99 %) | 211 (98 %) | 463 (99 %) |
| parameterizations | Sponge layers | 41 (90 %) | 36 (89 %) | 33 (90 %) | 35 (89 %) |
| parameterizations | Microphysics tendency tests | 306 (100 %) | 269 (100 %) | 231 (100 %) | 247 (100 %) |
| parameterizations | Microphysics wrappers tests | 4 (95 %) | 3 (96 %) | 3 (95 %) | 3 (96 %) |
| parameterizations | SGS quadrature tests | 14 (93 %) | 11 (93 %) | 11 (93 %) | 12 (93 %) |
| parameterizations | SGS moments tests | 3 (96 %) | 2 (96 %) | 2 (96 %) | 2 (96 %) |
| parameterizations | Tendency limiters tests | 0 (32 %) | 0 (34 %) | 0 (33 %) | 0 (35 %) |
| parameterizations | Moisture fixers tests | 1 (95 %) | 1 (96 %) | 0 (95 %) | 1 (97 %) |
| parameterizations | Cloud fraction tests | 1 (78 %) | 1 (84 %) | 0 (79 %) | 1 (83 %) |
| parameterizations | SGS saturation tests | 2 (96 %) | 2 (97 %) | 2 (96 %) | 2 (97 %) |
| parameterizations | BMT integration tests | 4 (96 %) | 4 (96 %) | 3 (95 %) | 4 (96 %) |
| parameterizations | Allocation tests | 2 (86 %) | 2 (89 %) | 2 (85 %) | 2 (89 %) |
| parameterizations | Chemistry tendency tests | 6 (13 %) | 7 (10 %) | 5 (11 %) | 6 (8 %) |
| parameterizations | Passive stratospheric tracers | 200 (97 %) | 189 (97 %) | 157 (97 %) | 173 (97 %) |
| parameterizations | Beres NOGW unit tests | 4 (93 %) | 13 (97 %) | 3 (92 %) | 9 (96 %) |
| restarts | Restarts | 1184 (91 %) | 1155 (85 %) | 1166 (90 %) | 1179 (85 %) |
| restarts | Reproducibility infra | 31 (96 %) | 40 (97 %) | 30 (97 %) | 41 (97 %) |
| restarts | Init with file | 135 (95 %) | 145 (91 %) | 132 (94 %) | 150 (91 %) |
| era5 | ERA5 forcing | 79 (90 %) | 79 (93 %) | 224 (23 %) | 324 (29 %) |
| era5 | Column datasets | 25 (95 %) | 21 (96 %) | 104 (19 %) | 147 (23 %) |

## Appendix B. How to reproduce the numbers

The parsed measurement sits beside this file: `ci_job_timings.tsv` with one row per job,
`ci_file_timings.tsv` with one row per test file per job variant, and `parse_logs.py`,
the parser that produced them. The sources are below.

- Job minutes and queue waits: `GET /repos/johannespletzer/ClimaAtmosResiDyn.jl/actions/runs/<run>/jobs?per_page=100`
  for runs 35121778373 (`ci`), 35121778370 (`Downgrade`), 35121778624 and 35195666887
  (`Downstream`), 35121778393 and 35195666804 (`Documentation`), 35196935505
  (`Invalidations`). Runtime is `completed_at - started_at` per job, queue wait
  `started_at - created_at`.
- Per-file seconds and compilation shares: each job's log, the line matching
  `<seconds> seconds (... % compilation time)` that precedes a `Test Summary:` header;
  the file's label is the first column of the line after the header.
- Precompile inside `Pkg.test`: the line `N dependencies successfully precompiled in S
  seconds. M already precompiled`. Cache outcome: the line after `Restore key:` in the
  `julia-actions/cache` step. Coverage: the `Token length:` line in the Codecov step.
- Flag mechanism: `julia-actions/julia-runtest` `action.yml` (defaults), Pkg
  `src/Operations.jl` `gen_subprocess_flags` (release-1.11), Julia `src/jloptions.c`
  (release-1.10, lines 862-868) and `base/loading.jl` (release-1.11, `pkg_tracked` at
  `:1901-1924`).
