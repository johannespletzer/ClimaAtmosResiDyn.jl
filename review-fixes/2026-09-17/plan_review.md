# A critical review of the CI plan, and the plan as executed

Date: 2026-09-17. This reviews [`ci_pipeline_review.md`](ci_pipeline_review.md),
sections 9 to 12, from a session with Julia and GitHub API access. It checks the
review's facts again, answers its open questions with a recommendation each, and
gives the revised plan. Phase A and B of that plan are implemented in draft PR #82, branch
`claude/ci-cost-phase-a`.

## 1. Facts checked again

| claim | checked on | result |
|:--|:--|:--|
| The depot cache never restores | the repository's cache list, and job `105121736013` (`ci 1.11 - tagging_source`, run `35195622177`, the merge of #72) | Holds. The store has 12 caches, 14.7 GB, over the 10 GB limit. None was accessed after it was created. The job prints `No cache found`, then precompiles 445 dependencies in 724 s, then saves 1.23 GB. |
| Coverage is never uploaded | the same job | Holds: `Token length: 0`, then "Token required - not valid tokenless upload". |
| The two cache traps of section 10 | `julia-actions/cache@v3`, `src/post.js` | Both hold. An exact key hit skips the save (`post.js:44-46`). Old caches are only deleted off the default branch (`post.js:102-106`). |
| Branch protection might require checks (question 8) | `GET /repos/.../branches/main` and `/rules/branches/main` | `main` is not protected. No status check is required. The only ruleset ("Avoid deletion") is disabled. So no path filter can leave a pull request unmergeable. |
| `energy_source_tags_integration.jl` grew after the measurement | job `105121736013` | Holds. Its test time is now 25.8 min on 1.11 (12:14:15 to 12:40:05), against 17.3 min measured at three model types. |
| Section 7: the `MANYTESTS` sweep of `test/restart.jl` is dead | `.buildkite/full_pipeline.yml:888-898` | Only in GitHub Actions. Upstream's Buildkite runs it with `--manytests`, and this fork does not run Buildkite. The known-issues entry says so. |
| ClimaCoupler still supports 1.10 | `CliMA/ClimaCoupler.jl` `Project.toml` | `julia = "1.10"`. One version is enough for the coupler check; 1.11 is the one this repository prefers. |

## 2. Where the plan is weak

1. **Item 1 gives up too much.** It takes `Downgrade` off every source-only pull
   request. The repository's own triage guide
   (`docs/dev-guides/workflow/ci_triage.md:21`) names the usual cause of a
   downgrade failure: "new code used an API added in a later version". That is
   a source change. The weekly run would find it after the merge, with no
   pull request to blame.
   **Revision:** keep a single cheap check on every pull request. It resolves
   at minimum compat on Julia 1.10 and runs `using ClimaAtmos`. It catches
   resolution failures and anything used at load time, such as a name imported
   from a newer dependency. It costs one job of about 5 min once the cache
   works. The full matrix runs weekly, on demand, on tags, and whenever
   `Project.toml` or `downgrade.yml` changes.
2. **Item 2 misses a third trap.** Pull request runs also save caches, scoped to
   their own ref. At about 1.2 GB per version, a handful of open pull requests
   fills the 10 GB store on its own. The newest `main` cache survives, because
   every run reads it and eviction is least-recently-used. So the design still
   works, and a second push to the same pull request reuses its own cache. No
   change is needed. The point is recorded so nobody reads a full store as a
   failure.
   **Falsified on 2026-09-17, after #82 merged.** On `main`'s Downgrade run
   35227540243, the 1.10 cache saved at 13:59 was restored at 14:04 and 14:18.
   It was gone for the jobs that started from 14:34 on. At 15:36 the store held
   10 caches, 11.4 GB, all used after 15:03, and four of them belonged to pull
   requests. Where a job found the cache, it worked: `414 already precompiled`.
   **Fix, #84:** only pushes and the schedule save. Pull requests restore
   `main`'s cache and save nothing, and `load` reuses the test cache without
   saving.
3. **Item 2 may also miss a fourth trap: the CPU.** Package images are built for
   the runner's own CPU by default. GitHub's `ubuntu-latest` pool mixes AMD and
   Intel machines. Julia rejects a package image built for a CPU the current
   machine does not match, and then precompiles again. How often this happens
   here is unknown.
   **Revision:** each test job now prints its CPU model. If the first runs show
   precompiles that follow a CPU change, set `JULIA_CPU_TARGET` to a portable
   value in every job that reads or writes the cache. It is not set now,
   because a multi-target value makes every precompile slower and every cache
   larger.
4. **The `load` fix in section 10 is right, and it is cheap to keep `load`.**
   With the cache working, a syntax error would fail each test job within a
   minute or two. `load` still saves those 20-odd jobs in that case. It also
   gets its own cache name, so it no longer decides what the test jobs restore.
5. **Burst merges are not in the plan.** On 2026-09-17 three merges within
   thirty seconds started three full `ci` runs. `ci` never cancels on `main`
   (`ci.yml:13`), for the sake of the badge. The badge only shows the latest
   run, and each merged pull request was already tested on its own branch.
   **Revision:** `ci` cancels superseded runs on `main` too. A burst then costs
   one run. The price is a badge that can show "cancelled" until the newest run
   finishes.
6. **Phase C is less urgent than it looks, and riskier.** Once the cache works,
   the heaviest job is about 40 min, well inside the 90-min limit. Merging model
   types in the tagging files changes the configuration each assertion runs
   under. Counting assertions is not enough to show nothing was lost: "without
   an offset only the first two hold" is itself a claim of
   `energy_source_tags_integration.jl`. Each such change needs the owner's
   review as its own pull request.
   **Revision:** Phase C waits for the Phase A measurement, as section 10
   already asks. Then it starts with the file that costs most after the cache
   fix, with a note of which claim each removed model type carried.
7. **The coverage badge advertises something that does not exist.** Codecov has
   never received an upload from this repository, so the README badge shows no
   data. **Revision:** remove the upload steps and the badge together.
   `docs/clima_atmos_specific.md` says how to bring them back.
8. **`downgrade.yml` pins `@latest`.** This is a small drift risk, and it is
   fixed in passing: `setup-julia@v3`, `julia-buildpkg@v1`,
   `julia-runtest@v1`, as in `ci.yml`.

## 3. The open questions, answered

| # | question | recommendation, now in the plan |
|:--|:--|:--|
| 1 | Is Codecov used? | No. No upload has ever succeeded. Coverage off, upload steps and badge removed. To restore: set `CODECOV_TOKEN`, then re-add the two steps on the 1.11 jobs only. |
| 2 | Is Julia 1.10 a commitment? | Yes, as long as `Project.toml` says `julia = "1.10"`, and 1.10 found the #76 allocation this week. So item 3, not 3b: fork-owned groups and `parameterizations` on both versions, upstream-owned groups on 1.11 only. |
| 3 | Weekly `Downgrade` acceptable? | Yes, with the per-PR minimum-compat load check of section 2.1. |
| 4 | Does the fork reach ClimaCoupler? | Only through `src/`, `ext/` and `Project.toml`. The parity rule keeps the model's behaviour upstream's. So `Downstream` runs on changes to those paths, on one version, with a timeout. |
| 5 | Upstream test files untouched? | Yes (`docs/known_issues.md` section 6). The leftovers of section 7 go into that list (item 12). |
| 6 | Ceiling for merged groups? | Keep "under half the 90-min limit". `dynamics` plus `era5` is about 8 min of tests. |
| 7 | Are merge bursts typical? | They happen. Let `ci` cancel on `main` (section 2.5). No merge queue for now. |
| 8 | Required status checks? | None: `main` is unprotected. Path filters are safe. If protection is added later, require `ci-required` only, which always reports. |

## 4. The revised plan

**Phase A and B, one pull request, `claude/ci-cost-phase-a`, done:**

| item | change | files |
|:--|:--|:--|
| 1 (revised) | `Downgrade`: full matrix weekly (Monday 03:00 UTC), on `workflow_dispatch`, on tags, and on pull requests and pushes that change `Project.toml` or `downgrade.yml`. A 90-min timeout, `coverage: false`, versions pinned, one shared cache per version. A new `load 1.10 minimum compat` job in `ci.yml` runs on every pull request | `downgrade.yml`, `ci.yml` |
| 2 (revised) | One test cache per Julia version (`julia-ci-test;version=…`, `include-matrix: false`), a separate one for `load`, and one for the minimum-compat load. Each test job prints its CPU model | `ci.yml`, `downgrade.yml` |
| 3 | `dynamics`, `dynamics_tracers`, `dynamics_edmfx` and `restarts` run on 1.11 only (`era5` is folded into `dynamics`, item 6) | `ci.yml` |
| 4 | `coverage: false`; the process and upload steps and the README badge removed | `ci.yml`, `README.md` |
| 5.5 | `ci` cancels superseded runs on `main` | `ci.yml` |
| 6 | `era5` folded into `dynamics`; the "(heavy)" label gone | `test/runtests.jl`, both matrices |
| 8 | `Downstream` on 1.11 only, a 120-min timeout, and only when `src/`, `ext/`, `Project.toml` or the workflow changes | `downstream.yml` |
| 12 | The unreachable `MANYTESTS` sweep and the same-type duplicate builds recorded in the upstream list | `docs/known_issues.md` |
| docs | The CI layout: groups, versions, the schedule, and how to restore coverage | `docs/clima_atmos_specific.md`, `AGENTS.md` |

Expected cost per pull request after the first cached `main` run: about 28
`ci` jobs, one docs build, and no `Downgrade` or `Downstream` on source-only
changes. That is roughly 500 to 600 runner-minutes, against about 1820 and 68
jobs today. The figure is an estimate. The measurement below replaces it.

**Measure, on the first two `main` runs after the merge:**

- The first run saves the new caches. The second one should print `Cache
  restored from key: julia-ci-test;version=…`, and its `Pkg.test` line should
  report most dependencies as already precompiled.
- If a job restores but still precompiles most dependencies, compare its
  printed CPU model with that of the job that saved. If they differ, set
  `JULIA_CPU_TARGET` (section 2.3).
- Record the new per-job minutes beside `ci_job_timings.tsv`.

**Phase C, after that measurement, one file per pull request, each reviewed by
the owner:** in the order the new timings give. Today that is
`tagged_water_integration.jl`, then `energy_source_tags_integration.jl`
(25.8 min now), then `diagnostics/unit_diagnostics.jl`. Each pull request says
which claim each removed model type carried, and where that claim is tested
now.

**Phase D, only if the numbers still call for it:** items 7, 9 and 11.
