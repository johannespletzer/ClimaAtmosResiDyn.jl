# Bringing the energy source tags and the process records to operation

The owner's goal, set on 2026-09-10, is to keep both families and make them
operational. This list names what is left. It merges four reviews made on
2026-09-11 (readiness, form A, the leftover residuals, and sub-grid transport
with ice and the other microphysics schemes). On 2026-09-14 it was rebuilt as a
list of what remains, and an Opus agent reviewed it against the repository.
Its findings are folded in; its report is
[TODO_REVIEW_2026-09-14.md](TODO_REVIEW_2026-09-14.md).

Production, as the owner decided on 2026-09-11, is a GPU sphere in Float32,
with EDMF and 1M. The GPU check comes last, once the physics is robust and
complete.

Nothing here is approved unless it says so. Model code, a default, a tolerance,
an energy reference and every run need the owner's approval before they are
written or submitted. The standing approvals of 2026-09-14 are listed under
"Decided".

Priorities: **B** blocks operation, **S** should be fixed, **N** is nice to
have. Sizes: S is under a day, M one to three days, L several PRs or a
campaign.

## Where things stand (2026-09-18)

Merged into `main`:

  - **Before the review round:** #65 and the offset (#68); #69, the implicit
    bracket and the repair (`08682fd8`); #70, sedimentation as transport, the
    EDMF refusal and the label warnings (`3b4b6056`); #73, the docs deploy
    (`327cd207`); #80, `SeasonalSST` removed (`2f60df85`).
  - **2026-09-17:** #72, the enthalpy audit; #74, the docs after #70; #75, the
    Float32 group; #78, the allocation checks; #81, the defect test on the
    moist column; and the CI work, #82, #83 and #84.
  - **2026-09-18:** #86, Aqua held below 0.8.17; #85, one moist column in the
    `parent_budget` group; #79, the parity rule (`730b5b18`).

Also on 2026-09-18: #87, the parity exception recorded; #77, the safe
defaults (`2eb7b4a9`); #76, the split solver (`38661891`). #89 is open as a
draft: the merge of upstream v0.42.11 (see section 0). #76 and #77 were merged a minute apart, each tested on its own branch,
so `main`'s run at `38661891` is the first to test them together.

The table below is the review round of 2026-09-16, kept for its record.

On 2026-09-16 each open PR got a review, and the owner had another session
push patches for the findings with a clear fix (the record is on
`claude/review-open-prs-tasks-wxiw0k`, `review-fixes/2026-09-16/`). Nobody had
run those patches. This session added the findings that needed a Julia run,
and ran the patched files locally.

| PR  | What                                                                  | Review patches, then this session                                                                 | Local runs, this session                  |
|:--- |:--------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------- |:----------------------------------------- |
| #72 | The enthalpy audit, `energy_source_tag_transport`, with its docs      | `uₕ` compared, both refusals tested, two transport sentences; then every model field with `isequal`, the vertical and horizontal checks against the parent's own terms, three doc sentences | integration 70/70, config 15 sets         |
| #74 | D2: the energy source tag docs brought up to date after #70           | three sentences; its clash with #77 is fixed on #77                                               | docs only                                 |
| #75 | T2: a Float32 integration test of the tags and records, own CI group  | whole state on restart, the repair after the solve; then `isequal`                                 | Float32 integration 51/51                 |
| #76 | P4's fix: tags and records solved apart from the Jacobian's solver    | docs entries, a recursion for the 1.10 allocation; then a tridiagonal two-iteration unit test, the iteration count taken from the algorithm, `isequal` | unit 229/229, integration 52/52           |
| #77 | B9: the offset required, the closure check and label check by default | docs entries, NEWS, the zero guard, five passages; then tests of the audit columns and the spin-up, R3 on both limiters, the tolerance sentences | unit 250/250, config 15 sets, integration 52/52 |
| #78 | T3: the tag and record code allocates nothing                         | `Vararg{Any, N}`, comments and docs                                                               | records 17/17, source tags 52/52          |
| #79 | The parity rule, now with a test per family                           | known departures, `isequal`, scope; then an on/off test in each of the four tag and record families | records 22/22, source tags 53/53, water 111/111, energy tags 32/32 |

The fragile defect test that failed `Downgrade 1.11 - parent_budget` on #72
(decision 13) is fixed by #81. The token cannot write to Actions on the fork
(`gh run rerun` and `gh run cancel` get HTTP 403), so the owner reruns,
cancels and dispatches runs.

Measured so far: 0M on a column and a sphere, and 1M on a warm column, a day
each (E26 to E39, E43); 1M with ice on a cold column for an hour, with a twin
without vertical diffusion (E42, E42b); the EDMF build time with and without
tags, why it grows and the fix (E44 to E44e); C7's sphere in Float32 (E45) and
on 4 MPI ranks (E47), each closing as C7 does, to rounding; the tag cost on that
sphere, 1.46× (T9); where the repair's trades sit (E46), and that 10° masks
remove them (E48).

Not yet run: EDMF with tags past its build, a restart, anything longer than a
day, 2M and P3, more than one node, and the GPU.

## 0. In flight

  - **#89, the merge of upstream v0.42.11** (d331fe30), opened on 2026-09-18 as
    a draft on `claude/merge-upstream-v0.42.11`. It replaces #88, whose head
    was upstream's own `main`. Two commits: the resolutions of 12 conflicting
    files, then the port that the merge forces (13 test files off the removed
    `AtmosModel(; …)` and `AtmosSimulation{FT}(; …)`, and two names ClimaCore
    1.0 removed). Aqua takes upstream's bound. Upstream moved its own output
    (`ref_counter` 409 to 413), so the parity reference becomes d331fe30.
    Before it leaves draft: CI, the owner's manual `ci.yml` run, and a bitwise
    run against d331fe30 on one machine. C1b is rebased onto it afterwards,
    where `sgs_mass_flux` becomes a `Bool`.
  - **CI:** `main`'s run at `38661891` tests #76 and #77 together, and
    `Downstream` runs there for the first time under its new trigger.
  - **#76's allocation, settled:** on Julia 1.11 the split and the unsplit
    solve allocate nothing; on 1.10 both allocate 1,056 bytes, which ClimaCore's
    own coupled solve does and the split does not add to. The test marks
    "split allocates zero" broken on 1.10 only. Its comment still says the
    unsplit solve allocates 48 bytes on 1.11; it measured 0 (run 35310991660).
  - **B1 ran** on 2026-09-18 as job 13501290 on `hpda2_test` (2 CPUs,
    32 GB), in 69 minutes (E50, `output/b1_base/`). Model code `main` at `38661891`, from the worktree
    `../ClimaAtmosResiDyn-b1`; its driver, runscript, configuration and
    `runscripts/terrabyte_stacks.env` are copied in from this branch at
    `58d9b0c8`, because `main` has none of them. Output:
    `$SCRATCH/tag_closure/output/b1_base/`.
  - **C1b is draft PR #91** (`fe69cd06`, six commits). The work:
      + B1, B2 and B4;
      + the refusal narrowed to `updraft_number` > 1;
      + T6, `test/energy_source_tags_edmf_integration.jl`, in a new group
        `tagging_source_edmf`;
      + T5, item 11 of the source-tag integration test;
      + M3.

    Locally, T6 passes 41 of 41, T5 10 of 10, and the configuration and
    species-list tests 282 of 282. Without tags it is bit for bit `main`
    (E51). Its validation ran on 2026-09-18, 4 of the 5 approved jobs: the D4
    pair, D4 with the updrafts' vertical diffusion, and D5 (E53). All four
    finished in 23 minutes. The residual is zero-sum at about 0.5%, and the
    records close the column. After #89 merges it is rebased, and
    `sgs_mass_flux isa Val{true}` becomes a `Bool` test.
  - **C2 is draft PR #92** (`e0813505`, from `main` at `23a57f02`). It passes
    locally: unit tests 291 of 291, the source-tag integration file 105 of 105.
    It unlocks V5, restart equivalence (up to 2 jobs, approved). After #89 it
    needs a small rebase, because the merge changes the lines beside both call
    sites.
  - **The pause of 2026-09-18 at about 12:15** ended the same afternoon. #90,
    untracking `.buildkite/LocalPreferences.toml`, is merged (`23a57f02`).
  - **This branch has `main` merged in** (`5db75854`, main at `38661891`), so
    runs launched from here use current model code. Every conflict took
    `main`'s side, with the owner's agreement for the two protected pages,
    which now match `main` exactly.
  - **`gh` and the `upstream` remote.** With no default repository, `gh`
    prefers a remote named `upstream`. So `gh pr create` without `-R` went to
    `CliMA/ClimaAtmos.jl` and failed with "Resource not accessible by personal
    access token"; the token was fine. The fork is now `gh`'s default for this
    clone (`gh repo set-default`, 2026-09-17). Pass
    `-R johannespletzer/ClimaAtmosResiDyn.jl` anyway in other clones.
  - **CI cost.** The CI review and its plan are on
    `claude/review-open-prs-tasks-wxiw0k` (`review-fixes/2026-09-17/`,
    `plan_review.md` sections 1 to 5, with the owner's decisions). `main` has
    no branch protection.
      + **Merged:**
          * #82: shared caches, no coverage, upstream groups on 1.11 only, a
            per-PR minimum-compat load, `Downgrade` weekly, `era5` folded into
            `dynamics`.
          * #83: instantiate before that load.
          * #84: only `main` saves caches; `JULIA_CPU_TARGET:
            'haswell,-rdrnd'`, also part of the cache names; Downstream and
            Manifest compat keep no cache; Downstream runs on `main`, weekly
            and on demand; a manual `ci` run tests every group on both
            versions.
          * #85, the first phase C step: the `parent_budget` group builds one
            moist column, the calibration one, compiled once per ledger mode.
            Its test time on `ci 1.11` fell from 41m01s to 36m20s, which is
            under half of the 90-minute limit, so the group needs no split.
          * #86: Aqua held at `0.8.9 - 0.8.16`. Aqua 0.8.17 walks each
            `[deps]` section with `Base.locate_package` and does not skip the
            names that also stand in `[weakdeps]`, so both `infrastructure`
            jobs failed. Naming the missing packages one by one did not end
            (`ChangesOfVariables`, then `RecipesBase`).
      + **Measured:** on `main` after #84, cache restores reused over 400
        packages on Intel and AMD runners alike, so the CPU target works.
        #84's manual trigger runs the upstream groups on 1.10, as #76's run
        shows. The job rows are in the session scratchpad,
        `cache_check/after84_main.tsv`.
      + **Next:**
          * Measured on #77's run of 2026-09-18: 571 runner-minutes in 33
            jobs, against about 1,820 in 68 before (`plan_review.md`
            section 6). Under the 600 target.
          * Phase C on the tagging files, one PR per file, each reviewed by
            the owner, after #76 and #77 merge, since both edit
            `energy_source_tags_integration.jl`. First
            `tagged_water_integration.jl`, whose restart can move onto the
            tag set of `:105`.
  - **#77:** the "under the default `tracer` transport" qualifier is in
    (`7d6cec6b`).

## Decided

On 2026-09-11:

  - **Production** is a GPU sphere in Float32, with EDMF and 1M.
  - **EDMF:** refuse `prognostic_edmfx` with tags now (C1a, done in #70), and
    build the sharing later (C1b): under both transports, in the implicit
    tendency, with the guard of the shared loop (B4).

On 2026-09-14:

  - **The offset (U1):** required whenever energy source tags are set. An
    explicit `0` keeps today's behaviour. The refusal quotes the tested values:
    110,495 J/kg, and the smallest offsets that made the total positive, 45.4
    kJ/kg on the DYCOMS column and 100.4 kJ/kg on the moist sphere (E6).
    How to choose it for a long run is open: U8.
  - **The closure check (U2, R1):** on by default whenever the tags are set,
    daily, reported from a spin-up reference, report-only until V2 and V3
    calibrate a tolerance per transport.
  - **The per-process checks (A2, A3):** the label check at configuration now.
    A2's runtime part and A3, form A online, later, as optional validation
    features.
  - **The S items,** grouped: now C5, P1, D2 (all done or in a PR); with B9 U3,
    U4, R3, T4; with C1b M3, T5; before the GPU T3; with V2 C4, V6; with D1 D3.
    A4, A5 and A7 move to N.
  - **Merges:** the owner merged #69 and #70, and approved pushing #72's docs,
    retargeting it to `main` and taking it out of draft, and opening #74.
  - **Standing approvals,** so that the work runs without stopping. The main
    session takes P4 and every task that needs approval; an agent took T2.
      - **P4 jobs:** up to 8 on `hpda2_test`, at most 2 CPUs, 48G and 2 h
        each. 7 used: 3 inference profiles, 2 cancelled validations of the
        first commit, 2 validations (E44e). 1 left.
      - **Code, as draft PRs to `main`, merged only by the owner:** P4's fix
        (#76); B9 with U3, U4, R3 and T4 (#77); C2's restart guard with T1,
        after #72 merges; C1b, after #76 and #72 merge.
      - **Runs at their predecessors' settings:** the C6 twin with a 10° mask
        (done, E48); V5, restart equivalence (up to 2 jobs, after C2); C1b's
        validation (up to 5 jobs: the D4 pair, D4 with
        `edmfx_vertical_diffusion: true`, D5).
      - **Pushes:** the main session's branches and T2's, as draft PRs.
  - **Parity with upstream, a boundary condition.** Simulation results from
    ClimaAtmos and from this fork must be binary identical: the fork develops
    a diagnostic only. With a diagnostic on, every field upstream has stays bit
    for bit the same. Written into `AGENTS.md` and
    `docs/clima_atmos_specific.md` ("Fork parity with upstream"), on this
    branch and in #79 for `main`.
  - **`SeasonalSST` is removed entirely** (#80, and on this branch in
    `c00aca1e`). It was new physics. The transient stratospheric tracer
    examples use `PrescribedSST` again.
  - **The binary comparison against an upstream checkout is skipped for now**
    (P6).

On 2026-09-17:

  - **The fragile defect test (decision 13):** the convergence check stays on
    the moist DYCOMS column. A dry column with implicit diffusion never stood
    above rounding in 64 runs. Merged as #81.
  - **The CI plan** (`plan_review.md` section 5):
      + fork-owned groups keep Julia 1.10 and 1.11, upstream groups run on
        1.11, and a manual `ci` run covers 1.10 for a PR that edits upstream
        code;
      + `Downstream` runs after merges, weekly and on demand;
      + package images are built for a portable CPU target, now;
      + the `parent_budget` group gets a type audit before any split.
  - **Aqua:** first add the missing weak dependency as a test extra. When the
    walk stopped at the next package, the bound on Aqua replaced it (#86).

On 2026-09-18, going through section 1 with the owner:

  - **#77's three choices** (decision 2): accepted as written.
  - **C2's design** (decision 11): approved, minimal.
      + The check also covers the process-record fields.
      + The spin-up reference follows #77: it is taken again after a
        restart.
      + No override key.
      + Starting tags from a tagless checkpoint is an N item, U7.
  - **The parity break** (decision 12): `dd06318f` stays as a named exception.
    No upstream PR is opened. The local branch `upstream-vwb-species-guard` and
    [UPSTREAM_VWB_PR_DRAFT.md](UPSTREAM_VWB_PR_DRAFT.md) stay as a record.
  - **ClimaCore** (decision 3): #76 keeps the `MatrixFields` internals. The
    drafted issue is not filed.
  - **The named regions' width** (decision 10): 2° stays. The docs should say
    that a mask narrower than the grid spacing makes the repair trade, and
    that a 10° mask avoids it on coarse grids (with D3).
  - **V1** (decision 5): folded into V2, which becomes a 10-day Float32 run.
  - **Phase B** (decision 7): B1 is approved, one job, at the plan's
    settings.
  - **Runs** (decision 8): V2 and V6 are approved, to run once C1b is merged.
    MP1 on two nodes is not.
  - **B3** (decision 6, the design's decision 5): extend the audit to the SGS
    diffusive flux, as C1c, after C1b. This changes the decision of 2026-09-11.
  - **2M and P3** (decision 6, the design's decision 6): upstream lifts the
    model's gate. When it does, the tags accept 2M and refuse P3 at
    configuration until the parent's P3 sedimentation is fixed.
  - **A4** (decision 4): later, as N.
  - **D1** (decision 9): after V2.
  - **Aqua's walk upstream** (14): not reported.
  - **One moist model in `parent_budget`** (15): no.
  - **#80's NEWS entry:** none.
  - **Worktrees:** the 17 whose branches are merged are removed.
  - **CI minutes:** collected from #77's run and recorded in `plan_review.md`.

## 1. Decisions for the owner

None open. Every decision of this section was made on 2026-09-18; see
"Decided". #76, #77 and #87 merged the same day.

## 2. Blocking operation (B), in dependency order

 1. ~~**Merge #70.**~~ Done (`3b4b6056`).
 2. ~~**Merge #72.**~~ Done on 2026-09-17. C2 and C1b can build on
    `energy_source_tag_transport` now.
 3. **P4, the EDMF build time with tags.** The D4 column with 8 tags and 5
    records did not build in two hours (E44, E44b). E44d names the cause:
    ClimaCore builds the implicit Jacobian's nested solver with compile-time
    work on the names of every field, which grows much faster than their
    number. #76 solves the tags and records apart, and builds the rest over the
    other fields only. On the 0M column with 8 tags the increments are
    identical to the unsplit solver's, with and without implicit diffusion, and
    the Jacobian cache builds in 20.8 s against 97.4 s. On the EDMF column with
    8 tags and 5 records the whole build now takes 21 minutes, and 8 tags add
    37 s to `get_simulation` against 1,891 s before (E44e). Merged as #76 on
    2026-09-18.
 4. **C1b, share EDMF's sub-grid fluxes among the tags** (design option B).
    Needs #72 and #76 merged.
      - B1, the SGS mass flux, with the donor from the sign of the flux of `E`;
        B2, each species' whole sedimentation face flux, the corrections
        included; B4, a guard in the shared tracer loop,
        `edmfx_sgs_flux.jl:403-409`.
      - Both transports, in the implicit tendency. About 220 lines and 200 of
        tests.
      - T6, an EDMF integration item: the partition's tendencies from the SGS
        mass flux and sedimentation match the parent's to 100 eps. It adds an
        EDMF compile to CI.
      - Validation (approved): the D4 pair, D5, and D4 with
        `edmfx_vertical_diffusion: true`, the shipped setting.
      - Then narrow C1a's refusal to `updraft_number > 1`.
      - Size M.
 5. **C2, a restart guard** (approved, after #72). Write the offset, the tag
    set, the transport and the repair setting into the checkpoint, and fail with
    a named key on a mismatch (`restart.jl:34-39`). With T1. Size S to M.
 6. **V5, restart equivalence** (approved, after C2). Two segments against one
    run, with the offset and the repair. Size S.
 7. **Float32.** ~~V3~~ is done (E45). ~~T2~~, the Float32 test group, is
    merged (#75). Runs longer than a day are untested; that is U6. Size S.
 8. ~~**MP1, more than one process.**~~ Done (E47): on 4 ranks C7's sphere
    closes as on one process, to rounding. More than one node is untested.
 9. **The decided defaults and checks (B9).** Written: U1, the offset
    required; U2 with R1, the closure check on by default, daily, report-only,
    with a spin-up reference at 1 h and `false` to switch it off; A2, a warning
    at configuration for a process that runs with no tag following it (flags
    subsidence on C5's column and microphysics on C6's sphere, nothing on C7).
    With U3, U4, R3 and T4. Merged as #77 on 2026-09-18, with its three
    choices accepted.
10. **V2, the production physics on a sphere:** EDMF with
    `edmfx_vertical_diffusion: true`, vertical diffusion, sponges, topography
    and 1M, with `analysis/transport_ledger.jl`. It sizes C4. Needs C1b and
    #76. Approved on 2026-09-18 as a ten-day Float32 run, with V1 folded in
    and V6.
11. **Calibrate** U2's tolerance per transport from V2 and V3, and add the
    warning.
12. **D1, the user guide into the docs,** with D3.
13. **The GPU, last.** Run the diagnostic on a GPU on Levante, with Float32 and
    T3, and fix what that forces.

## 3. Should fix (S)

Done or in a pull request:

  - ~~**C5.**~~ Where the repair's large trades sit: just beyond the 20° edge
    where the region tags meet (E46). With 10° masks there are none (E48).
  - ~~**P1.**~~ The tag cost on a sphere: 1.46× (T9).
  - ~~**D2,**~~ the stale docs: merged in #74 (fixes 3, 7, 9, 10) and #72
    (fixes 5, 7). Fix 4 needs no change.
  - **U3,** `e_src_fix_<name>` in the default output when the repair is on;
    **U4,** the source tags' negative parts and minimum, and the energy the
    repair moved, in the audit table; **R3,** a warning when clipping `ρq_tot`
    changes `ρe_tot` outside every bracket; **T4,**
    `config/model_configs/baroclinic_wave_energy_source_tags.yml`. All in #77.

With C1b (B4):

  - **M3.** A test that `water_advection.jl:51-56` and
    `gs_sedimenting_mass_candidates` list the same species. Written, and
    committed only locally, on `claude/energy-source-tag-species-lists`
    (`68cfe17f`), to open with C1b. Four mutations of the source each fail
    it.
  - **T5.** The cold column as an integration item, from
    `analysis/subgrid_check_cold.jl`, covering both sedimentation branches.

Before the GPU (B13):

  - ~~**T3.**~~ In #78: the tag and record code allocates nothing in a tendency
    evaluation or in the repair. #76's split solver allocates nothing either
    (a check added to #76).

With V2 (B10):

  - **C4.** `c·Δρ` from processes the tags do not bracket: vertical diffusion,
    sponges, hyperdiffusion, EDMF, LES (`energy_source_tags.jl:102-111`).
    Measure on V2, then share them as transport or document the size.
  - **V6.** Topography.

With D1 (B12):

  - **D3, caveats:** C1 and C4, what is untested, stitching `e_src_fix` across
    restarts, choosing `c`, and ice passing provenance upward (E41).

Found on 2026-09-18:

  - **P7. The fork builds the EDMF column 2.5 times slower than upstream,**
    with no diagnostic on: 635 s against 249 s, almost all of it in building
    the tendency function, 397 s against 22 s (E52). `main` before the merge
    took 413 s there too. Candidates: #76's split-solver construction and the
    ledger's meters. First step: time `get_jacobian` alone in both checkouts
    on the login node. Every EDMF build pays it, in CI and in production. The
    measurement was approved on 2026-09-18 and runs as a background agent,
    with scratch copies only. The fix needs the owner's go-ahead, because it
    touches the solver.
  - **P8. #89 makes CI's test groups slower.** Measured on 2026-09-18 by
    comparing #89's run at `c068d564` with `main`'s at `38661891`. On
    identical runner CPUs #89's jobs took 1.4 to 2.1 times as long, in six
    pairs; for example, `tagging_source` on 1.10 took 44 minutes against 21.
    Precompiling the new package versions adds only 1.5 to 2.5 minutes, and
    that goes once `main` saves a cache after the merge. The rest is in the
    tests: `tagging_source` on 1.11 tested for 61 minutes against 35. The EDMF
    column's tendency function built as fast after the merge as before it on
    the login node (397 s against 413 s), so the time goes elsewhere. Whether
    upstream v0.42.11 and ClimaCore 1.0 cause it, or the fork's code on them,
    is not known. `ci 1.11 parent_budget` took 72 minutes and `tagging_source`
    on 1.11 64, near the 90-minute limit. #91 adds a sixth compile to
    `tagging_source` and a group that builds the EDMF column twice. **Accepted
    for now by the owner on 2026-09-18:** watch #91's first run after the
    rebase. The options, if it goes over: raise the limit, or split the two
    groups, in a PR of their own.

## 4. Nice to have (N)

  - **ClimaCore upstream.** Its field-name sets check every pair against every
    other at compile time (E44d). Scaling that down would help every model
    with many tracers, and would let #76 use public API only.
  - **A4.** Signed overlay shares (decision 4). Accept when a C9 twin gives form
    A of at most 5 J/kg, or at most 1e-6 with the loss signed too, and `sfc` no
    longer freezes at a node, with `ta` and the partition residual unchanged.
  - **A5.** An overlay-bound diagnostic: the mass fraction where an overlay is
    negative, and where a member exceeds its group's sum.
  - ~~**A7.**~~ Done (E49): a transport error cancels along the direction it
    moved, and a process no tag follows, or the repair, keeps its sum.
  - **Parity checks (P6).** The on/off half is merged (#79): each tag and
    record family now runs the same column with and without it and compares
    every model field with `isequal`, as the ledger's envelope test already
    did. All four match bit for bit locally. Still open: the stratospheric
    passive tracers have no such test, and nothing compares the fork with an
    upstream checkout. That run sets a reproducibility reference, and the
    owner chose on 2026-09-14 to skip it for now. Besides `dd06318f`
    (decision 12), a first read of the 14 files in `src/` where the fork
    rewrites upstream lines, against `v0.42.9`, found nothing else that acts
    without a diagnostic. The files the fork only adds to were not read for
    this. `SeasonalSST` is gone (#80).
  - **P5.** The explicit tendency's generic tracer loops allocate, with or
    without tags, and each tag adds to it: 22,576 bytes per call without tags
    and 58,160 with four on a 1M column (#78's description). Shared model
    code, not tag code.
  - **A2's runtime part and A3,** as optional validation features: ∫Δ⁺ per
    label at runtime, and form A as a global integral online. Accept A3 at
    about 1.2e-3 on a C6-type run and at most 1e-4 on C7, C9 and C10 at 24 h.
  - **The region masks' width.** With 10° masks the repair never trades between
    the region tags, against ±30,915 J/kg with the named regions' 2° (E48). A
    wider mask blurs provenance: each region tag keeps a few percent of the
    other region's energy. Decided on 2026-09-18: 2° stays, and the docs say
    so with D3.
  - **C1c.** B3, the SGS diffusive flux under `enthalpy`. Approved on
    2026-09-18, after C1b (plan C4).
  - **C1d.** Option C, per-updraft tag shares; about three times B.
  - **C6.** Review leftovers: `isfinite` before the conversion to `FT`, `nothing`
    inside a broadcast at init, `parent` shadowed in tests. The Float32 rounding
    floor stays N (E45).
  - **C7.** Jacobian blocks for the tags' sedimentation and the implicit
    bracket.
  - **A6.** A tag-only vertical upwinding key (E37).
  - **P2.** Compute `energy_source_share_norm!` once per evaluation, and skip it
    when nothing sediments. **P3.** A string allocation per tracer per
    evaluation under the audit (`energy_source_tags.jl:148`).
  - **U7. Start tagging from a checkpoint, a future opportunity.** Today the
    tags can start only at t = 0. A restart cannot switch them on. C2's guard
    (#92) refuses a checkpoint whose tag fields differ from the configuration,
    and nothing gives a tag a value from a restored state. So a climate run
    cannot spin up for months or years without tags and then start tagging.
    The opportunity is a new tag experiment whose clock starts at the restart,
    with an offset of its own (U8). It needs:
      + an explicit start mode, off by default. In it a pure region tag starts
        as its mask times `E` of the restored state, and a source tag at zero,
        as at t = 0 (`tag_initial_value`);
      + the process records started at zero the same way;
      + the guard to accept a checkpoint without these fields in that mode
        only, and to record the settings from that start on.

    Changing the settings of tags already in a checkpoint stays refused. Model
    code: the initialization path and the guard. Out of C2's scope (C2's
    question 4). Size M. Added on 2026-09-18 at the owner's request, not to be
    built now.
  - **U5.** A clear error when the tag list changes across a restart (C2 covers
    most of it). **U6.** Records in Float64, or reset at each output, for long
    Float32 runs; over a day they match Float64 to 4e-4 at 24 h (E45).
  - **U8. Choosing the offset, options.** The offset `c` belongs to a tag
    experiment. It is fixed at t = 0 and kept through every restart, which
    C2's guard enforces. The atmosphere does not depend on it (E17), but the
    tags do (E19).
      + **The risk.** The guidance today is the 110,495 J/kg the experiments
        used, and the refusal message quotes the minima of two initial
        states. On the moist sphere that leaves about 10 kJ/kg. For dry, still
        air, `e_tot + c > 0` needs `T > T₀ − (c − R_d T₀ − g z) / cv_d`. At
        110,495 J/kg that is 228 K at sea level, 215 K at 1 km and 187 K at
        3 km. A production run over a continental winter can plausibly go
        colder near the surface. No run with an offset has crossed yet, but
        none lasted more than a day.
      + **What happens there.** The shares are zero where `e_tot + c ≤ 0`. The
        tags stop losing energy but keep gaining it. Sedimentation, the EDMF
        sub-grid flux and the `enthalpy` audit move no tag out of such a
        cell. The repair does not act there. The residual shows all of it. By
        the formula, the overclaim outlasts the cold spell, and later losses
        relax it only in part. That is not measured.
      + **Option 1: choose `c` from a temperature floor** over the whole run,
        not from the initial state: `c ≥ R_d T₀ + cv_d (T₀ − T_floor) − g z`.
        The refusal message and the docs would say so. 150 kJ/kg keeps dry air
        at sea level positive down to 173 K. The cost, measured for a doubled
        `c` (E19): the source tag moves by about 1%, and the region tags'
        negative undershoots grow 1.5 times, which the repair absorbs.
      + **Option 2: one `c` for every setup whose tags are compared,** since
        the tags depend on it. It is reported with the results, as part of
        the energy reference.
      + **A new `c` needs a new tag experiment,** from t = 0, or from a
        checkpoint with U7. A new `c` at a restart would leave
        `(c_new − c_old)·ρ` that no tag holds.

    `c` is an energy reference, so this needs the owner's approval. Decide
    before the first production run that spans a winter. Added on 2026-09-18,
    not to be built now.
  - **U9. The offset's headroom in the closure table.** Today the table shows
    only `nonpositive_fraction`. So a drift toward `e_tot + c = 0` shows only
    once a cell has crossed. A column with the domain's minimum of `e_tot + c`
    shows the margin before that. It needs a minimum reduced across
    processes, and it changes the table's column count, which parsers notice.
    Optionally, add an `abort_above` for `nonpositive_fraction`. A run with
    only source tags has no closure check by default. It is checked only when
    the cache is built, at the start and at each restart. Size S. Added on
    2026-09-18, not to be built now.
  - **R5.** A converged Newton solve for closure studies; its cost is not
    measured.
  - **M4,** when 2M returns: D2 and one integration item. **M5,** when the
    parent's P3 is fixed: D3.

## 5. Housekeeping

  - **Worktrees** beside the repository. Each has a copied
    `.buildkite/LocalPreferences.toml`, which `main` tracks: never commit it.
    Checked on 2026-09-18 against `origin/main`.
      + **Removed on 2026-09-18, their branch merged:** `-audit` (#72),
        `-docs` (#74), `-float32` (#75), `-t3` (#78), `-parity` (#79),
        `-noseasonal` (#80), `-defect` (#81), `-ci-phase-a` (#82 to #84, #86),
        `-pb-audit` (#85), `-docsfix` (#73), `-repair` (#70), `-offset` (#68),
        `-pr65`, `-split`, `-b3` and `-b5`; also `-c1b-check`, a detached
        scratch merge. None held uncommitted work; the ignored files were
        manifests, a docs build and local test output.
      + **Also removed on 2026-09-18:** `-buildtime` (#76), `-defaults` (#77)
        and `-parity-doc` (#87).
      + **Keep:** `-buildtime-edmf` (#76's validation, detached, with a
        local change that must never be committed; C1b's validation may
        reuse it); `-m3` (M3, local only, until C1b); `-p4` (detached
        at `edd44e1d`, P4's diagnosis); `-ci-review` (the CI review's branch);
        `../ClimaAtmos-upstream-vwb` (decision 12).
  - ~~**The known defects** in `LEVANTE_TASKS.md`.~~ Fixed on 2026-09-14: the
    validator now follows the model's `if`/`elseif` chain, so ISDAC skips the
    `implicit_diffusion` rule, and it checks the ISDAC and prescribed-flow
    asserts too; `output/c0_sphere_deep/` has a provenance reconstructed from
    its logs, and the analysis skips a run whose provenance records a failed
    exit with a note instead of a warning.
  - **`analysis/phase_c.jl`** reads only runs named `c*`; the D, P, V and MP
    runs are in FINDINGS only.
  - ~~**NEXT_SESSION.md** needs the day's state.~~ It points here, with a
    summary of the day.

## 6. Open questions, not blocking

  - What makes D1's zero-sum gross residual (E42, E42b). Candidate: pressure
    work in grid-mean vertical advection under tracer transport. An audit twin
    of D1 would test it.
  - What the sphere's remaining 17% of the audit's first-hour residual is
    (E39b).
  - How much provenance the upward branch moves where ice persists (D5, after
    C1b).
  - E14, E16's remainder and E24.

## Plan

### A. Waiting for the owner

 1. #89's manual `ci.yml` run, which the token cannot start.
 2. C1b's validation submissions, once C1b is pushed: each is prepared
    and shown first.

Every other decision was made on 2026-09-18.

### B. Can be done now, without a new approval

None of these writes model code, a default or a tolerance, or submits a run.
All seven were done on 2026-09-14.

 1. ~~**T3.**~~ #78: the tag and record code allocates nothing, checked in the
    integration files' own simulations, so CI compiles nothing more. #76 got
    the same check for its split solver: its update and its solve allocate
    nothing, while the unsplit solve allocates 48 bytes per call. That check is
    on #76 (`41432652`); its integration file passes 52 of 52 locally (T10).
 2. ~~**M3.**~~ Written, committed locally on
    `claude/energy-source-tag-species-lists`, to open with C1b. It reads the
    two species lists from `water_advection.jl` and fails on each of four
    mutations.
 3. ~~**C2's design.**~~ [RESTART_GUARD_DESIGN.md](RESTART_GUARD_DESIGN.md)
    (decision 11). The hash that `restart.jl` compares is stable across
    processes and changes with the offset, a region and the repair, but only
    warns.
 4. ~~**C1b's plan against #72 and #76.**~~ A new last section of
    `SUBGRID_AND_MICROPHYSICS_DESIGN.md`: the two PRs merge cleanly, B's anchors
    are where the design says, no tag gains a Jacobian block, and T6 should
    assert the split solver's uncoupled list on the EDMF column.
 5. ~~**A7.**~~ E49, `output/a7_gap_cancellation/`.
 6. ~~**Housekeeping.**~~ See section 5.
 7. ~~**A draft of the ClimaCore issue.**~~
    [CLIMACORE_ISSUE_DRAFT.md](CLIMACORE_ISSUE_DRAFT.md), with a ClimaCore-only
    reproducer (`analysis/climacore_nameset_repro.jl`). Not filed.

### C. Unlocked by merges, already approved

 1. **Now:** C2, the restart guard with T1, as a draft PR (#72 merged, design
    approved on 2026-09-18); then V5, restart equivalence, up to 2 jobs.
 2. ~~**B1**~~, phase B's ten-day run of the energy tag family: ran on
    2026-09-18 (E50).
 3. **Now, #76 merged:** C1b, the EDMF sharing, with T6 and T5, as a draft PR; then
    its validation, up to 5 jobs: the D4 pair, D4 with
    `edmfx_vertical_diffusion: true`, D5. With those, the D4 column's residual
    under EDMF can be measured for the first time.
 4. **After C1b:**
      + C1c, the audit's share of the SGS diffusive flux, as a draft PR;
      + V2 as a ten-day Float32 run with the production physics, V1 folded in,
        and V6, topography (both approved);
      + then the calibration of U2's tolerance, and D1 with D3.
 5. **Done on 2026-09-18:** the worktrees of merged branches are removed
    (section 5).

### D. Needs a new approval

 1. **A4,** signed overlay shares: model code and a C9 twin (N, later).
 2. **Runs:** MP1 on more than one node; an audit twin of D1 (section 6).
 3. **The N items that change model code:** C6's leftovers, C7, A6, P2, P3,
    U5, U6, U7, R5, A2's runtime part and A3.
 4. **The GPU,** last, with T3.

## Done, for reference

  - **Model:** C1a and M2 (#70); C3 and R2's timing (#72); the #69 help text
    and records comment; the runscript's `srun --mpi=pmix`.
  - **Runs and analyses:** D1 and its twin (E42, E42b); R4 (E39b, E43); the D4
    pair (E40, E44); the D4 build control (E44); P4's split test (E44b) and
    stage timing (E44c); P4's inference profiles (E44d); P4's fix on EDMF
    (E44e); V3 (E45); C5's repair
    trades (E46); MP1 (E47); the 10° mask twin (E48); P1 (T9).
  - **Docs:** the guide's fixes 1, 2, 6 and 8 (#69, #70); 3, 5, 7, 9 and 10
    (#72, #74).
  - **Pull requests opened on 2026-09-14:** #74 (D2), #75 (T2), #76 (P4's
    fix), #77 (B9).
  - **Merged on 2026-09-17 and 2026-09-18:** #72, #74, #75, #76, #77, #78,
    #79, #81, #85, #87; the CI work #82, #83, #84 and #86.
  - #72 merged into this branch (`57ed9c1f`).
