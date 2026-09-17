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

## Where things stand (2026-09-16, after the reviews)

Merged into `main`: #65 and the offset (#68); #69, the implicit bracket and the
repair (`08682fd8`); #70, sedimentation as transport, the EDMF refusal and the
label warnings (`3b4b6056`); #73, the docs deploy (`327cd207`); #80,
`SeasonalSST` removed (`2f60df85`).

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

CI is slow. At the last check nothing had failed except `Downgrade 1.11 -
parent_budget` on #72: `implicit_attribution_tests.jl:241` found the defect of
three Newton iterations larger than that of one (5.37e-7 against 3.43e-7).
That test is on `main`, #72 does not touch it, the same job passed at #72's
previous head with the same `src/`, and it passes on #74 and #75. The runner
was in another Azure region, so the test looks hardware-sensitive (decision 13).
A `gh run rerun` failed with a permission error. It most likely went to
`CliMA/ClimaAtmos.jl`, as the first PR attempt did (section 0); not retried.
Whether the
recursion removes #76's 1,056 bytes on Julia 1.10 is also for CI to show.

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

  - **CI** on the seven open PRs. Nothing runs on Slurm.
  - Nothing runs locally.
  - **One PR to open,** by the owner: decision 12's upstream fix. Decision
    13's test is draft #81.
  - **`gh` and the `upstream` remote.** With no default repository, `gh`
    prefers a remote named `upstream`. So `gh pr create` without `-R` went to
    `CliMA/ClimaAtmos.jl` and failed with "Resource not accessible by personal
    access token"; the token was fine. The fork is now `gh`'s default for this
    clone (`gh repo set-default`, 2026-09-17). Pass
    `-R johannespletzer/ClimaAtmosResiDyn.jl` anyway in other clones.
  - **New worktrees:** `../ClimaAtmosResiDyn-defect` (decision 13) and
    `../ClimaAtmos-upstream-vwb` (decision 12, on the new `upstream` remote).

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

## 1. Decisions for the owner

 1. **Merges:** #73, #72 and #74 are ready. #75, #76 and #77 after their CI.
    #76's EDMF validation is done (E44e); it can come out of draft.
 2. **#77's three choices, for review in the PR:**
      - A2 warns only in a run with at least one per-process tag, and a tag
        listing `all` counts as following no process. Otherwise a run with
        region tags alone would warn about every process.
      - The default check has no tolerance and never warns. The old default,
        1e-6, warned at every check of every run (24 times a day on C7).
      - After a restart, the spin-up reference is taken again one `spin_up`
        after the restart.
 3. **#76 uses ClimaCore `MatrixFields` internals,** since the public
    `FieldMatrixWithSolver` cannot solve on part of a state. Whether to keep
    that, or also ask ClimaCore upstream to make its name-set work scale (N).
    A draft of that issue, with a ClimaCore-only reproducer, is in
    [CLIMACORE_ISSUE_DRAFT.md](CLIMACORE_ISSUE_DRAFT.md). It is not filed.
 4. **A4.** Signed overlay shares under the audit: model code and a C9 twin.
 5. **V1's scope.** A 0M 10-day sphere is not production physics. Either fold
    it into a 10-day Float32 run with V2's physics, or make it S.
 6. **The design's open decisions:** 5, whether to share the SGS diffusive
    flux under `enthalpy` (C1c); 6, who lifts the 2M gate and fixes the
    parent's P3, and whether the tags refuse P3 until then.
 7. **Phase B.** FINDINGS §8 item 4 still lists it as the owner's call.
 8. **Runs not yet approved:** V2, V6, and a second node for MP1.
 9. **Docs:** whether to move `USER_GUIDE_DRAFT.md` into `docs/src/` (D1).
10. **The named regions' width.** E48: with `tropics` and `extratropics` 10°
    wide instead of 2°, no region tag goes negative on the 5° sphere, and the
    repair trades nothing between them, against ±30,915 J/kg. The price is
    blurrier provenance: a 10° mask leaves 3.6% of the total in the extratropics
    tag at the equator. Options: keep 2°; widen the named regions; or tie the
    width to the grid spacing. Changing it is a default.
11. **C2's design,** [RESTART_GUARD_DESIGN.md](RESTART_GUARD_DESIGN.md), for
    review before the code: the keys, where they are read, the error texts,
    and four questions (the records, #77's spin-up reference, an override, and
    tags from a restart without them).
12. **The one known break of parity.** `dd06318f` (2026-08-16) fixed an
    upstream defect in `limiters_func!`: the water-borrowing guard compared
    `@name(ρq_tot)` with the `Symbol`s of `vertical_water_borrowing_species`,
    so with an explicit species list upstream skips
    `enforce_mass_energy_consistency!`. The fork runs it, so `ρ` and `ρe_tot`
    differ from upstream in that configuration (upstream `v0.42.9` still has
    `@name(ρq_tot)`, `limited_tendencies.jl:97`, `:113`). No shipped config
    sets the list. Options: revert it here and fix it upstream, so that it
    comes back with the next merge, as the rule says; or keep it as a named
    exception until upstream has the fix. Upstream `main` at `eb010645`
    (2026-09-16) still has the defect, and no upstream issue names it.
    **Prepared, not opened:** an upstream fix with a test, on the local branch
    `upstream-vwb-species-guard` (`527cdf06`, worktree
    `../ClimaAtmos-upstream-vwb`). The test fails on upstream `main` (`ρ`
    misses an increment of 1e-3, `ρe_tot` misses 2,564) and passes with the
    fix, 13 of 13. The PR text and the steps are in
    [UPSTREAM_VWB_PR_DRAFT.md](UPSTREAM_VWB_PR_DRAFT.md), and the check is
    `analysis/vwb_guard_check.jl`. Opening it is the owner's call, and upstream
    may ask for a CLA.
13. **A fragile test on `main`.** `test/parent_budget/implicit_attribution_tests.jl:241`
    asserts that three Newton iterations leave a smaller defect than one. On
    one CI runner it did not (5.37e-7 against 3.43e-7). On that dry column
    both defects are about two rounding units of the column energy, so their
    order is noise (`analysis/parent_budget_defect_size.jl`). On the owner's
    request the test now runs where the defect is real: a moist DYCOMS column
    at dt 10 s, 2.5e6 rounding units at one iteration and 110 times less at
    three. The dry column keeps a check that the defect changes by at most
    eight rounding units between one and two inner iterations; on terrabyte
    it does not change at all (`analysis/parent_budget_dry_defects.jl`).
    Branch `claude/parent-budget-defect-test`, pushed, 133 of 133 locally at
    `4c15038f` and at `e88f5c31`, the fixes for the three nits of its review.
    The owner asked to move the convergence check to a dry column with
    implicit diffusion. In 64 runs it never stood above rounding (at most 8
    units): at rest, with a uniform 10 m/s wind and with a sheared wind, on
    the test grid and on a 50 m grid, for both diffusion models
    (`analysis/parent_budget_defect_dry_{diffusion,wind,shear}.jl`). A dry
    column's implicit problem is close to linear, so one Newton iteration
    already solves it. Open: how to go on.
    Draft PR #81, opened 2026-09-17; the text is also in
    [PARENT_BUDGET_DEFECT_PR.md](PARENT_BUDGET_DEFECT_PR.md).

## 2. Blocking operation (B), in dependency order

 1. ~~**Merge #70.**~~ Done (`3b4b6056`).
 2. **Merge #72.** Its docs carry E34 to E43 and the audit's scope, it targets
    `main` and is ready. It comes before C1b and C2, which both use
    `energy_source_tag_transport`. Size S; waits for the owner.
 3. **P4, the EDMF build time with tags.** The D4 column with 8 tags and 5
    records did not build in two hours (E44, E44b). E44d names the cause:
    ClimaCore builds the implicit Jacobian's nested solver with compile-time
    work on the names of every field, which grows much faster than their
    number. #76 solves the tags and records apart, and builds the rest over the
    other fields only. On the 0M column with 8 tags the increments are
    identical to the unsplit solver's, with and without implicit diffusion, and
    the Jacobian cache builds in 20.8 s against 97.4 s. On the EDMF column with
    8 tags and 5 records the whole build now takes 21 minutes, and 8 tags add
    37 s to `get_simulation` against 1,891 s before (E44e). Left: CI and the
    merge.
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
 7. **Float32.** ~~V3~~ is done (E45). T2, the Float32 test group, is draft
    #75. Runs longer than a day are untested; that is U6. Size S.
 8. ~~**MP1, more than one process.**~~ Done (E47): on 4 ranks C7's sphere
    closes as on one process, to rounding. More than one node is untested.
 9. **The decided defaults and checks (B9).** Written: U1, the offset
    required; U2 with R1, the closure check on by default, daily, report-only,
    with a spin-up reference at 1 h and `false` to switch it off; A2, a warning
    at configuration for a process that runs with no tag following it (flags
    subsidence on C5's column and microphysics on C6's sphere, nothing on C7).
    With U3, U4, R3 and T4. Draft #77; its tests pass locally (config tests,
    233 unit tests, 45 integration assertions). Left: CI, and the owner's review
    of the three choices under decision 2. Size M.
10. **V2, the production physics on a sphere:** EDMF with
    `edmfx_vertical_diffusion: true`, vertical diffusion, sponges, topography
    and 1M, with `analysis/transport_ledger.jl`. It sizes C4. Needs C1b and
    #76. V1 as decided. Its run is not approved yet.
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
  - **D2,** the stale docs: #74 (fixes 3, 7, 9, 10) and #72 (fixes 5, 7). Fix
    4 needs no change.
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
  - **Parity checks (P6).** The on/off half is done in #79: each tag and
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
    other region's energy. The width is a default (decision 10).
  - **C1c.** B3, the SGS diffusive flux under `enthalpy` (decision 6).
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
  - **U5.** A clear error when the tag list changes across a restart (C2 covers
    most of it). **U6.** Records in Float64, or reset at each output, for long
    Float32 runs; over a day they match Float64 to 4e-4 at 24 h (E45).
  - **R5.** A converged Newton solve for closure studies; its cost is not
    measured.
  - **M4,** when 2M returns: D2 and one integration item. **M5,** when the
    parent's P3 is fixed: D3.

## 5. Housekeeping

  - **Worktrees** beside the repository, to remove once their PRs merge:
    `-repair` (#70, merged), `-audit` (#72), `-docs` (#74), `-float32` (#75),
    `-buildtime` (#76), `-buildtime-edmf` (#76's validation, with a local
    change that must never be committed), `-defaults` (#77), and `-p4`
    (detached at `edd44e1d`, for P4's diagnosis), `-t3` (#78), `-m3` (M3,
    local only, until C1b), and `-c1b-check` (a scratch merge of #76 into #72,
    detached, removable at any time), `-parity` (#79) and `-noseasonal` (#80). Each has a copied
    `.buildkite/LocalPreferences.toml`, which `main` tracks: never commit it.
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

 1. **Merges,** in this order, each once its CI passes: #73, #72, #74, then
    #76 and #75, then #77. #72 goes before #77 and the C1b and C2 work, because
    they build on `energy_source_tag_transport`. #76 goes before C1b, whose
    validation needs the EDMF build to fit in two hours.
 2. **#76 out of draft:** its EDMF validation is done (E44e).
 3. **#77's three choices** (decision 2).
 4. **The named regions' width** (decision 10, E48).
 5. **The other decisions of section 1:** ClimaCore upstream (3), A4 (4), V1's
    scope (5), the design's decisions 5 and 6 (6), Phase B (7), the runs not
    yet approved (8), moving the guide into the docs (9), C2's design (11),
    the parity break (12, an upstream PR is ready to open), the fragile ledger
    test (13, a PR is ready to open). #80 merged without a
    NEWS entry, which its review left to the owner.

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

 1. **After #72:** C2, the restart guard with T1, as a draft PR; then V5,
    restart equivalence, up to 2 jobs.
 2. **After #72 and #76:** C1b, the EDMF sharing, with T6 and T5, as a draft PR;
    then its validation, up to 5 jobs: the D4 pair, D4 with
    `edmfx_vertical_diffusion: true`, D5. With those, the D4 column's residual
    under EDMF can be measured for the first time.
 3. **After #77 and the owner's review:** nothing further is approved; U2's
    tolerance is calibrated later, from V2 and V3.
 4. **After all merges:** remove the worktrees (section 5).

### D. Needs a new approval

 1. **V2,** the production physics on a sphere (EDMF with
    `edmfx_vertical_diffusion: true`, vertical diffusion, sponges, topography,
    1M), with C4 and V6. It needs C1b. Then the calibration of U2's tolerance.
 2. **A change of the named regions' width,** if decision 10 asks for one: a
    default.
 3. **A4,** signed overlay shares: model code and a C9 twin.
 4. **Runs:** MP1 on more than one node; an audit twin of D1 (section 6).
 5. **The N items that change model code:** C6's leftovers, C7, A6, P2, P3,
    U5, U6, R5, A2's runtime part and A3.
 6. **D1 and D3,** the user guide into the docs (decision 9).
 7. **The GPU,** last, with T3.

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
  - #72 merged into this branch (`57ed9c1f`).
