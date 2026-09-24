# G3: water tags under EDMF

The owner set G3 on 2026-09-23 and re-scoped it the same day: **G3 brings the
tagged water tracers to work under prognostic EDMF, operational in the
production configuration (a sphere with EDMF and 1M), with precipitation
provenance.** G4, the energy source tags, follows and uses what G3 learns.

The plan is [G3_PLAN.md](G3_PLAN.md). It has been reviewed
(`review/agent_reviews/g3_water_plan_review.md`) and finalised. This list
tracks its work. Where the two differ, the plan holds. The overview is the
roadmap, [ROADMAP.md](ROADMAP.md).

**Approved by the owner on 2026-09-23:** every job within the programme, and
agents as proposed. Model code goes into draft PRs that only the owner
merges. The parity rule of `AGENTS.md` holds for every change. GPU is outside
G3.

**Who does what.** This session runs G3, including its jobs, from the worktree
`ClimaAtmosResiDyn-exp`, and records on branch `claude/tag-closure-record`. Model code goes on
`claude/water-tags-edmf`. A separate session runs the energy jobs. It owned
PR #95, which merged on 2026-09-23.

Marks: `[ ]` open, `[~]` under way, `[x]` done, `[!]` waiting for a decision.

## G3 is met when

The twelve criteria of the plan, section 2, in short:

| #  | Criterion                                                                              | Status                   |
|:-- |:-------------------------------------------------------------------------------------- |:------------------------ |
| 1  | Evidence: every headline number goes through the verifier and a manifest               | tools built; review open |
| 2  | Refusals with tests, known issues settled, a file-based start, restart round trips     | open                     |
| 3  | Parity in both modes: 1M and 0M EDMF columns, explicit microphysics, two MPI ranks     | open                     |
| 4  | Closure on D4-W, including the copies' own residual and the rain and snow parts        | open                     |
| 5  | Per-tag accuracy against the copies, at 24 h and in the first hour                     | open                     |
| 6  | Convergence of the default's error and of the copies                                   | open                     |
| 7  | Precipitation provenance: the 0M split, rain and snow tags, `Σ pr_tag = pr`, the audit | open                     |
| 8  | Held-out columns: RICO, BOMEX, ARM SGP, GCM-driven 0M                                  | open                     |
| 9  | Float32 twin                                                                           | open                     |
| 10 | Cost, both modes and both families                                                     | open                     |
| 11 | Ten days on the sphere (superseded 2026-09-24: 90 days at 60 levels), a copies twin, a restart | open                     |
| 12 | Reviews, CI, draft PRs, docs                                                           | open                     |

## Decisions

  - [!] **Rev. 2's register, OD1 to OD8** (2026-09-24; ROADMAP.md, "The
    decision register"): the production envelope, the windows, the
    thresholds, the energy scale, *not assessable* at M5, the sphere, G4.15,
    and the audit's feasibility. ~~All open. Steps 2 and 3 of the revised
    order wait on OD1 to OD3.~~ *Superseded 2026-09-24:* the owner answered
    (ROADMAP.md, "The owner's answers"). Set: OD1 (the sphere at 60 levels),
    OD2 in form, OD4, OD5, OD6 in form, OD8 (8 tags, copies at 8). OD3 is a
    draft, pending the owner's approval; step 2 waits for it. OD7 is
    deferred.
  - [x] G3 is water and G4 is energy; production target; precipitation
    provenance with rain and snow tags; exchange by default with copies as the
    audit; the partition-only factor; this session runs G3's jobs. All decided
    by the owner on 2026-09-23.
  - [x] **The budgets of plan 6.1**, set by the owner on 2026-09-23: per tag
    2% and 5% at 24 h with G1's first-hour split; closure 0.2% with at most
    1e-6 left after the named parts; convergence as robustness; rain and snow
    as proposed; the sphere's form.
  - [ ] **The sphere's numbers**, set by the owner before V-W11, in the form of
    plan 6.1. *Rev. 2:* the form is now OD6's ceiling and growth bound, not a
    plateau after day one. *2026-09-24 (OD6):* 90 days, judged by the level
    observed; the ceiling's value is in ROADMAP.md's OD3 draft, ~~pending
    approval~~ approved 2026-09-24.
  - [ ] **The default mode's cost budget**, proposed from V-W10's first
    measurements and set by the owner before V-W11. *2026-09-24:* proposed in
    ROADMAP.md's OD3 draft, at 8 + 8 tags, ~~pending approval~~ approved
    2026-09-24.
  - [x] **The explicit-1M water default: opt-in until M5** (the owner,
    2026-09-24). W33 stays a failure, and W35 is recorded beside it. The
    default is decided at M5 under the contract.
  - [x] **The per-tag ledgers** (the owner, 2026-09-24): off by default, as
    built, and on in every validation and qualification run. The fraction uses
    the tag's current inventory, and the absolute amount is reported beside
    it.
  - [x] **2M and P3 stepped explicitly: refused until measured** (the owner,
    2026-09-24). Water tags already refuse 2M and P3 at configuration,
    whatever the transport (`check_water_tagging_supported`; checked on the
    login node for 2M and 2MP3 under both transports). Nothing changes for
    water. The energy guard is G4_TODO's G4.16.
  - [~] **Known issue 7's fix** (the site 23 crash): the option is the
    owner's (`design/NEGATIVE_PARENT_WATER.md`; WP3 below). *2026-09-24:* A
    now, then the probe, then a choice among B, C and D.
  - [x] **WP5's default transport under EDMF**, by the rule fixed in plan 4.3.
    The owner's review of #102 (2026-09-24) asked for it to be applied. It is
    applied in #102 where the configuration supports the follower, and
    `tracer` stays the default elsewhere and with copies.
  - [x] **The explicit-1M path under the follower** (the owner's review of
    #102, point 3). It is refused for now. The owner chose on 2026-09-24 to
    give the tags the parent's sedimentation cross blocks. That work is in
    progress, with the review's distinguishing experiment.
  - [ ] **The copies' repair** moves 0.6% of D4-W's water in a day, 0.27%
    with ten Newton iterations, over plan 6.1's 0.2%, so the audit is flagged
    (W21). Whether the audit stands as it is, or its repair's cause is
    isolated first, is the owner's.
  - [ ] **The surface rule in the first hour.** A surface-layer tag differs
    between the modes by 14% (L1) at 1 h, against a 1% budget, and meets it
    from 6 h (W21). Whether the plume's start should model the surface flux
    (plan 4.1, review S4) is the owner's.
  - [ ] **The prognostic fields of the rain and snow tags**, settled in the
    design note WP4b-D and its review. The recommended option is the
    non-precipitating, rain and snow parts. The note
    ([design/RAIN_SNOW_TAGS.md](design/RAIN_SNOW_TAGS.md), reviewed xhigh and
    revised on 2026-09-24) asks four things in its section 15: the fields;
    `ρq_tag_<name>` holding the non-precipitating water under the key; the
    microphysics attribution, net-flow rule or gross flows; and 4.2's rule
    restated to measure a leak's imprint.
  - [ ] **WP4a's two points**
    ([design/ZERO_M_SPLIT.md](design/ZERO_M_SPLIT.md), section 8, after its
    xhigh review): known issue 4's Jacobian, the pair (diagonal and cross
    term, with the split solver's back-substitution) or the diagonal alone as
    a test; the review showed the diagonal alone makes one Newton iteration
    worse and today's missing entry costs nothing for the pure sink. And the
    copies' part of issue 4, a follow-up or in WP4a.
  - [ ] **WP6's three points**
    ([design/GROSS_ACCUMULATORS.md](design/GROSS_ACCUMULATORS.md), section 8):
    a pre-WP6 checkpoint refused or zero-filled; loss and residence time moved
    to WP4a and WP4b; and, after the code review, the transfer ledgers as they
    are (exact per step at the default cadence only) or per tag (exact at
    every cadence).
  - [x] **A durable archive** for the minimal reference datasets:
    `~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/`, at most 5 GB.
    Decided by the owner on 2026-09-23.
  - [x] **The file-based column of V-W8:** the GCM-driven column, chosen by the
    owner on 2026-09-23. The ERA5 column's forcing is not on disk and has no
    download entry (CliMA provides it on its own cluster only). The GCM
    column's `cfsite_gcm_forcing` artifact was fetched into the scratch depot
    the same day (97 MB); V-W6 uses it too.

## Done before the re-scope

  - [x] Branch `claude/g3-programme`, the roadmap, the frozen assessments, the
    agent definitions in `~/.claude/agents/` (they load when a session starts).
  - [x] The evidence tools in `analysis/evidence/`:
      + `compare_runs.py`, the verifier, with 6 of 6 mutation tests;
      + E73's table reproduced exactly;
      + `manifest.py`, which detects the dirty run worktree;
      + `runs_inventory.csv`, 93 output directories, not yet classified.
  - [x] OPERATIONAL_TODO's open items matched to milestones.
  - [x] The instruction for #95's partition-only factor
    (`2ecc1d86`; carried out in #95 at `dcf7d086` and then removed at the owner's request (`a52b17f7`). Its text is kept under the tag `archive/g3-programme-2026-09-23`), passed to the job
    session through the owner.
  - [x] G3's plan, reviewed and finalised.

## WP0: foundations

  - [x] #95 merged with decision 5 on 2026-09-23 at 16:32: merge `0b2b1032`,
    head `b9c6e7b0`. The plan's assumptions were checked against the merged
    code the same day
    (`review/agent_reviews/plan_assumptions_check_2026-09-23.md`). Most
    hold; five points changed the plan: the vertical skip is at
    `advection.jl:257`, no water restart guard exists, WP1's refusals need
    their own check, a sixth leak path exists on the sphere, and the tags'
    sedimentation already has a Jacobian diagonal.
  - [x] Review the phase-1 tools (the old item 1.8), then write a FINDINGS
    entry (M8). From here on every headline number goes through the verifier.
  - [x] Extend the verifier to `q_tag_*`, the copies in `sgsʲs`, the rain and
    snow parts, and `pr_tag_*` (`clima-analysis-builder`): the water family,
    `--judge` with the owner's 6.1 definitions, `--parity-only`,
    `--ladder-share`, any output period and fractional hours; 55 tests. The
    copies, rain, snow and `pr_tag` checks are stubs until WP3 and WP4b name
    their fields; restart pairs (S6) and the checkpoint comparison stay open.
  - [x] The manifest in this session's submit path (`runscripts/submit_g3.sh`).
    Classify the run inventory (`runs_inventory.csv`, 140 rows).
  - [x] The Float64-twin helper (synergy 2), for V-W7. It is a precision-sensitivity
    screen and decides no cause (G4_TODO, prepared item 2):
    `analysis/increment/float64_twin.py`, `make` and `compare`. On E65's pair
    it gives ratios of 1.3 to 2.4 over the first eight hours. The docs section
    in `energy_source_tags_guide.md` belongs to G4.
  - [x] Check that V-W8's ERA5 forcing is on disk, and that the copies against
    tracer test (plan S3) can be configured. The forcing is not on disk and
    cannot be fetched by the package manager (the decision above). The
    tracer test can be configured: `chemistry_model: passive` gives the
    tracer an updraft copy, and `analysis/water/d4w_driver.jl` sets it; the
    water copies arrive with WP3.
  - [x] V-W0c: one untagged D4-W day with EDMF diagnostics, to size the
    updraft's rain and snow, the surface excess and the five 1M leaks (W18).
    The updraft holds under 0.01% of the rain and there is no snow, so D4-W
    cannot test the rain and snow tags' updraft composition. The updraft is
    3% moister than the environment at the surface. The vertical diffusion
    leak is about 0.9% of the column's water a day, 45 times the correction
    level, so WP4c's correction of it comes before criterion 4 on D4-W.
  - [x] V-W0a: known issue 4, a precipitating 0M column, 1 against 10 Newton
    iterations. The day-long pair rained only in its first hour (W15), so a
    controlled 2×2 over that hour followed (W16): moving microphysics off the
    implicit path changes the region tags' Newton sensitivity by at most 4%,
    and `evap`'s by up to 24% near 2e-5. That does not isolate the missing
    diagonal (W16's erratum, the owner's review of #100), so the issue stays
    open and PR-W1 states the bounded result. The sensitivity matches the
    change of the closure residual, the implicit and explicit advection
    split; WP5 addresses it. W15 to W17 went through the verifier.
  - [x] V-W1: D4-W with grid-scale tags on `main` + #95, before WP1's refusal,
    and its untagged twin: the "before" numbers (W17). The gross residual is
    15% of the column's water at 24 h, 75 times the budget; parity holds bit
    for bit in all 37 fields. The twin is V-W0c's run.
  - [x] Checksummed minimal datasets for headline tables, in the archive's
    `reference_data/`, within 5 GB: W15 to W18, E73, E76 and E62 to E66,
    901 files and 29 MB, hard links into the archive's scratch copy, with a
    `MANIFEST.tsv` of SHA-256 sums (2026-09-23).

## WP1: refusals, reserved names, known issues (draft PR-W1)

Draft PR #100 from `claude/water-tags-edmf`, opened on 2026-09-23 at `6e7264ae`.

  - [x] Refuse `water_tracers`:

      + with `prognostic_edmfx`, until WP3 lands;
      + with the AMD LES model, always.

    Warn under a prescribed flow, from `get_atmos`, so that the setup's own
    flow is caught as well as the key. Do not refuse `water_process_record`:
    the refusals have their own check, `check_water_tracers_transport_supported`.

  - [x] Reserve colliding tag names: `res`, `fix_*`, `upfix_*`, `inc_*`,
    `rtag_*`, `stag_*`.

  - [x] Known issue 1 closed with the post-#64 numbers (W19, `92696f6e` on
    #100). The CI log does not print them, since the assertions pass, so job
    `13831751` ran the integration test with the two quantities printed.
    Issues 3 and 4 are restated in the PR.

  - [x] Tests for each refusal (22, all passing locally). Review by
    `clima-reviewer` (high): nothing blocking; its two should-fix findings are
    fixed (`review/agent_reviews/wp1_refusals_review_2026-09-23.md`).

  - [ ] CI green on #100.

## WP3: total water under EDMF (draft PR-W3)

Branch `claude/water-tags-edmf-wp3`, stacked on #100. Dev runs and test
jobs from frozen snapshot worktrees under `claude_work/g3/wp3/`.

  - [x] The switch `water_tag_updraft_copy`.

  - [x] Default mode:

      + the donor share of the parent's `ρq_tot` SGS flux;
      + the exchange with weight `q_totᵏ` and decision 5's bound;
      + the water plume rescaled to `sgsʲs.q_tot` at each level, starting from
        the grid mean's composition;
      + the plume computed once, at the top of `implicit_tendency!`, into the
        tags' own scratch.

  - [x] Copies mode: `q_tag_<name>` in `sgsʲs`, with the four mirrors:

      + the updraft's 0M sink, `χᵢʲ += dq (φʲᵢ − χᵢʲ)` with φ clamped;
      + the updraft's 1M sedimentation, including the lateral inflow, with a
        diagonal Jacobian entry;
      + the surface relaxation target `q_b φ̄ᵢ`;
      + the residual repair after the filter, with its ledger `q_tag_upfix_*`
        and `r` as a diagnostic.

  - [x] Copies initialised and rebuilt as `q_totʲ φ̄ᵢ`.
  - [x] The comparison driver starts them from the plume
    (`start_water_tag_copies_from_plume!`, called by `d4w_driver.jl`).
  - [x] A fifth mirror, the surface moisture flux into the updraft
    (`water_tag_copies_surface_flux_tendency!`). 4.1 lists four; the 0M CI
    test found it (FINDINGS W20).

  - [x] The restart guard for the tags and the copies
    (`water_tag_checkpoint.jl`). Refusals:

      + `updraft_number > 1`;
      + copies without prognostic EDMF;
      + copies with unequal updraft upwinding;
      + the exchange without a region partition.

    Lift the WP1 refusal for one updraft. Done.

  - [x] Bound activation in the water audit, per source tag.

  - [x] Diagnostics of the five 1M leaks, and the sphere's horizontal EDMF
    flux, in closed form (plan 4.2): `q_tag_leak_<path>`. The hyperdiffusion
    also leaks under 0M, by the reference profile `q_tot_r(p)`.

  - [ ] CI groups `tagging_water_edmf`, `tagging_water_edmf_copies` and
    `tagging_water_edmf_0m` (Julia 1.10 and 1.11, downgrade). Three groups,
    not one: each builds the EDMF column twice, and two builds fill a job's
    budget, as for the energy source tags. The default mode under 0M runs in
    V-W3's TRMM pair, not in CI:

      + parity in both modes, on the 1M and 0M EDMF columns and with explicit
        microphysics;
      + the copies against a passive tracer at rounding, with water-specific
        terms off;
      + manufactured mixing tests on a frozen parent.

    At #101's head `4a1c91a4` the copies group fails, in CI (downgrade 1.11)
    and locally. Since `73fa27bd` it steps the microphysics explicitly, and
    the partition then misses by 0.8 to 0.9% net and 1.0% gross after an
    hour, against 1e-4 and 1e-3. Its bounds came from an implicit run
    (3.7e-5 net). The composition check also gives NaN. Probes of the
    explicit path in both modes are queued (`claude_work/g3/wp3/explicit_probe.jl`).

  - [ ] Review by `clima-numerics-reviewer` (xhigh).

  - [!] *Scope added (rev. 2, 2026-09-24): known issue 7, a parity-class
    defect.* A diagnostic ends a run that upstream completes. In the long
    runs' second submission at site 23, the parent's own `q_tot` goes below
    zero from day 10, in the untagged twin too. The water tags then diverge,
    and the tagged runs end with `simulation_crashed` (copies at day 48, both
    follower rules at day 74.5), while the untagged twin completes 90 days.
    The parent is bit for bit the twin's up to each crash. The copies, WP3's,
    and the follower, WP5's, both end the run.
      + [x] Recorded in `docs/known_issues.md`, issue 7, on
        `claude/water-tags-wp6-step3` (`18e7ef1d`). The FINDINGS entry is the
        parent session's.
      + [x] The options for the fix, `design/NEGATIVE_PARENT_WATER.md`: the
        tags cannot end a run; no tag water where the parent has none; the
        tags partition the parent's non-negative part; a cap; stop the tags,
        not the run. A probe that finds which ledger grows is proposed first.
      + [x] The owner chose on 2026-09-24: option A now, then the probe, then
        a choice among B, C and D.
      + [x] Option A: no closure check ends a run by default; water's old
        level, 1.0, is its void level, and the check marks its rows void and
        goes on. An explicit `abort_above` still ends a run.
        `claude/tag-closure-no-abort` (`00c9eedb`), from `main`, where the
        abort lives, for a PR against `main`; the water stack gets it by
        merge. Config tests pass on the login node (the new testset 9/9).
        Known issue 7 updated on `claude/water-tags-wp6-step3` (`b1b82e6a`).
      + [x] What ended the runs: the closure check (job `13917157`'s `.err`,
        line 1401).
      + [~] The probe: pre-registered (`design/NEGATIVE_PARENT_WATER.md`,
        section 5), its config `lr_s23_probe_ledgers.yml`, its run tree
        `../ClimaAtmosResiDyn-issue7-probe-run` (the record, #109 and
        `claude/long-run-samesign`; one conflict, resolved). Not submitted.
      + [ ] The owner's choice among B, C and D, then the fix and its tests,
        before the sphere (step 8a).

  - [x] **V-W3:**

      + D4-W, default against copies, each with a 10-Newton twin;
      + bound activation;
      + a surface pulse;
      + the TRMM 0M development case, default against copies.

    Record the result as a FINDINGS entry. Apply WP5's rule. Done: FINDINGS
    W21. Every tag within budget on the plain day; the default's closure
    fails at one iteration (0.71%) and passes at ten (0.13%), so the rule
    selects the follower; the copies' repair is over its bound; the pulse's
    surface tag fails its first hour.

## WP5: following the parent's increment (draft PR-W5)

  - [ ] `water_tag_transport: increment`:

      + after each solve the tags take the parent's `ρq_tot` increment;
      + the part that changes a column's total stays in place, with ledgers
        `q_tag_inc_left` and `q_tag_inc_moved`;
      + the tags' explicit vertical advection is skipped;
      + the hook composes with the energy one;
      + the stepper check is reused.

  - [ ] Its default under EDMF, by the rule in plan 4.3. The rule selects it
    (W21), and the validation (W24) supports it: D4-W closes to 1.5e-4 in a
    day with one iteration. The owner confirms.
  - [x] Built: draft PR #102 (`fd07d902`), reviewed (xhigh, nothing
    blocking; `review/agent_reviews/wp5_numerics_review_2026-09-24.md`),
    validated on D4-W (W24). Its invariant: it never changes a column's
    total, so the explicit path's net lag stays (W23, W24).

  - [ ] Review (xhigh).

  - [x] **V-W4**, the ladder, default and copies at each rung: dt 60 and 30;
    Newton 2, 4 and 10; 60 and 120 levels; first-order upwinding. Ran on
    2026-09-24, FINDINGS W25.
      + The default meets the per-tag budgets at the time-step and Newton
        rungs. At 60 levels it misses the first hour's, and at 120 levels
        every hour's.
      + At 120 levels both modes lose the partition. With first-order
        upwinding the copies do, and the default does not.
      + The copies' shares converge on the Newton ladder. On the time-step
        ladder they move as far as the atmosphere does.
      + R5, the cost, is not answered; V-W10 measures it.
  - [ ] **Follow-up from V-W4, for the owner to schedule** (not in this
    session's scope):
      + what parts the partition at 120 levels, in both modes;
      + what parts the copies under first-order upwinding.

    *Scope added (rev. 2, 2026-09-24):* this is step 2 of the revised order.
    *2026-09-24 (OD1):* the main case is now 60 levels, the production
    sphere's count. W25's 60-level rung missed the first hour's budget
    (`strat` 1.36%, `evap` 11.8%). That rung was a uniform 25 m grid over
    1.5 km, and the sphere's 60 levels are stretched over 30 km, so it is the
    nearest measured case, not the same grid. ~~Step 2 waits for the owner's
    approval of the OD3 draft.~~ *2026-09-24:* OD3 approved; step 2 is
    unblocked and pre-registered in `design/W25_ISOLATION.md`, with its
    configs (`w25i_*`), scripts (`w25_probes.jl`, `w25_compare.py`) and run
    tree (`../ClimaAtmosResiDyn-w25i-run`). Its 46 jobs are not submitted.
    It comes before WP4b and the sphere, and is scored against OD1 and OD2.
      + Fixed-parent one-step probes at 30, 60 and 120 levels, with centred
        and first-order reconstruction.
      + The refinement test (Insight 10): from one saved state, a fixed
        interval with more Newton iterations and a smaller Δt, reporting the
        follower's and the repair's throughput per unit time. It should
        shrink under refinement. A plateau means the follower compensates
        something other than lag.
      + Where the case has a source pulse, the two first-step probes
        (Insight 4): the first step fully converged, and the tags started
        after the first step.
      + Then full matched runs, reported as configuration outcomes, since
        each rung is another atmosphere.
      + Needs OD1, OD2 and OD3 before any run.

## WP5b: the tags' sedimentation cross blocks

The owner chose this on 2026-09-24 for the explicit-1M lag (W23; the owner's
review of #102, point 3). Design: `design/SEDIMENTATION_CROSS_BLOCKS.md`. The
work is on branch `claude/water-tags-sed-cross`, worktree `-wedmf5b`, stacked
on #102.
  - [x] Each tag's row gets the parent's cross block to each falling species,
    times the tag's share. The split solver solves the tags after the coupled
    fields, by back-substitution, so the parent's increments are unchanged.
    Commit `c2bf8a62`.
  - [x] For the experiment, the refusal of `increment` with 1M stepped
    explicitly is lifted (`f8da0913`, the control without the cross blocks).
  - [x] The distinguishing experiment (FINDINGS W29). With the cross blocks,
    the follower closes the explicit column to 2e-8 in an hour, and the parent
    is bit for bit the same.
  - [x] The refusal is dropped for good. The docs, the config tests and an
    integration test on the explicit column are at `0aad20ee`. Draft PR #105.
  - [x] The review (xhigh, `review/agent_reviews/wp5b_code_review_2026-09-24.md`),
    addressed at `11b8d875`: B1, the unsplit form carries no cross blocks
    (the reviewer's reproducer now builds, `analysis/water/wp5b_unsplit_build.jl`);
    S1, the blocks checked on the real column; the explicit test in its own
    group `tagging_water_increment_explicit`; S2 wording; N4.
  - [ ] The owner's review of #105 (2026-09-24, a comment on the PR; seven
    findings), addressed at `c446fe91` to `801c52dd`:
      + [x] 1: a unit test assembles the real blocks
        (`update_sedimentation_jacobian!`) in Float32 and Float64, with a drifted
        partition and binding clamps: the partition's sum is the parent's, and
        each tag's block matches a finite difference of the real tendency.
      + [x] 2: with 1M stepped explicitly the follower is opt-in again. The
        default waits on WP5b-V below.
      + [x] 3: W29 is stated as closure evidence, not provenance; WP5b-P below.
      + [x] 4: the evidence pinned, tag `evidence/wp5b-w29` (`4c7d52c8`).
      + [x] 5: the back-substitution test in both float types, an allocation
        gate, and the unsplit nested solve against the split.
      + [x] 6: the docs' numbers labelled net and gross; grid-scale tags.
      + [x] 7: the PR body; the copies' cross blocks as WP5b-C below.
      + [x] Pushed at `801c52dd` and answered on the PR. [ ] CI.
  - [x] A day of D4-W in both modes on the implicit path (FINDINGS W31): the
    gross residual falls from 1.35e-4 to 7.3e-6, the parent is bit for bit
    the same, and the agreement with the copies is unchanged.
  - [x] The three 1M integration files pass at `11b8d875`
    (`tagged_water_edmf_copies_integration` 68/68).

### WP5b-V: the explicit-1M default

The owner's review of #105, finding 2. The cross blocks close W23's column; one
stratocumulus column does not decide the default for every explicit-1M EDMF
run. Acceptance criteria, fixed before the runs:

  - [ ] A precipitating convective or sedimentation-heavy 1M column, chosen
    before any run, microphysics explicit, the follower on.
  - [ ] Newton iterations 1, 2 and a tightly converged reference (for example
    10); at least two timesteps.
  - [ ] Reported: net and gross closure, `q_tag_inc_left`, the smallest tag,
    the partition repair's volume, how often and how much the share clamps and
    the zero-normalization fallback act, and the parent's parity bit for bit.
  - [ ] Passes when one iteration stays below the 0.2% closure budget at every
    rung, and the result converges toward the reference as the timestep or
    the nonlinear error falls. Then the default takes `increment` there.
  - [x] Pre-registered (`design/EXPLICIT_1M_DEFAULT.md`, `ae18d56c`) and run
    on TRMM 1M: **fails** criterion 3 for `free` (FINDINGS W33). Budget,
    nonlinear convergence and parity pass. The follower stays opt-in there.
    Criterion 3 compared runs whose atmospheres differ; a same-atmosphere
    check would isolate the lag. For the owner.
  - [x] The same-atmosphere check (section 6, W35) **passes**: at 120 s two
    iterations cut the tags' one-step error 20-fold, and one iteration's
    halves at 60 s. [ ] The owner revisits W33's verdict; the default does not
    change before that.
  - *Scope added (rev. 2, 2026-09-24):* W33 stays recorded as a failure, and
    no new design overwrites it. The same-atmosphere check that rev. 2 asks
    to run first is W35, done. The arms still open follow rev. 2's order:
    arms without copies after W25's isolation (step 2), and any
    default-against-copies arm after WP5b-C (step 4). The explicit-1M
    follower stays opt-in unless it passes. *The owner, 2026-09-24:* it stays
    opt-in until M5, where the contract decides; W35 is recorded beside W33.

### WP5b-P: provenance, not only closure

The owner's review of #105, finding 3. Closure shows the tags sum to the water,
not that each label is right. W29's `evap` agreed less with the copies with the
cross blocks (5.8% against 3.8%), and the copies lack their own blocks.

  - [ ] A per-source acceptance criterion, set with the owner before the runs.
  - [ ] Precipitation-weighted per-tag errors, besides the column L1.
  - [ ] The comparison repeated after WP5b-C, or against a tightly converged
    reference in which neither path's sedimentation lags.

### WP5b-C: the copies' cross blocks

The second step (design note, section 5). The copies are updraft fields in the
coupled system, so their blocks to the updraft species enter the nested solve
directly. Until it lands, the copies are not a fully corrected reference on
the explicit path (the owner's review of #105, finding 7).

  - [ ] Design, with the nested solve's fill-in worked out (B1's lesson).
  - [ ] The copies' closure on W23's explicit column with one iteration
    (W23: 7.8e-3 without).
  - [ ] Parity with the untagged column.
  - *State on 2026-09-24:* a first build is in `../ClimaAtmosResiDyn-wedmf5c`
    at `d2b3dc60`, not pushed and not in FINDINGS. Its probe output is in
    `output/wp5c_probe/`. Until it is pushed and recorded, the water updraft
    copies on every pushed branch lack their own explicit-1M cross blocks.
  - *Scope added (rev. 2, 2026-09-24):* step 4 of the revised order.
    WP5b-C is complete before any use of 1M copies as the audit, at the tag
    counts OD8 keeps. With their blocks, the copies must still pass
    comparator eligibility in each run where they serve as the audit
    (ROADMAP.md, the acceptance contract). *2026-09-24 (OD8):* at 8 tags.

## WP4a: the 0M split (draft PR-W4a)

Built on `claude/water-tags-edmf-wp4a` (905b7ff5, from WP5's fd07d902) to the
revised note `design/ZERO_M_SPLIT.md`. The note replaced the first two items'
rule: each subdomain's rain-out `Δᵏ` goes by `φᵏ` for both signs (review S3).

  - [x] The split, `Σₖ Δᵏ φᵏᵢ`, in the bracket shared by the implicit and
    explicit paths: the copies' own shares in the updraft, the exchange's in
    the default mode, the grid rule elsewhere.
  - [x] `pr_tag_<name>`, `prra_tag_<name>`, `prsn_tag_<name>` under 0M.
  - [x] Under copies, one rule for the grid tags and the copies (WP3 review,
    N6): the grid tags' updraft part goes by the copies' shares.
  - [x] Known issue 4 restated in `docs/known_issues.md` (review B1).
  - [ ] Isolate known issue 4: the switch and the experiment (the note's
    sections 4 and 5), after the owner picks (i) the pair or (ii) the
    diagonal alone. Moved out of #104 to the follow-up WP4a-J below (the
    owner's review of #104, finding 6).
  - [x] Review of the code (xhigh, 2026-09-24,
    `review/agent_reviews/wp4a_code_review_2026-09-24.md`). It found no
    parity break and no wrong result. It asked for S1 to S5, taken at
    `63a1ddaa`:
      + S1: the tests take each subdomain's part from the real code and
        check it against that subdomain's shares, to rounding;
      + S2: allocation gates, the exchange bit for bit, random cells
        through `ShareDifferences`, and the grid rule for non-EDMF and
        EDOnly;
      + S3: the plume stays computed twice, and the note's sections 2 and 7
        say so, with its cost;
      + S4: the docstrings;
      + S5: `pr_tag` computes one tag, into scratch.
  - [x] Tests: at `63a1ddaa` the 0M integration passed 74/74 and the
    explicit-path parity script passed 20/20; at `b4c44841` the unit tests
    passed 499/499.
  - [x] Draft PR-W4a is #104, stacked on #102.
  - [x] The TRMM validation, 3 h and 6 h, with grid-rule twins (FINDINGS W26):
    parity bit for bit, and the split moves the tags by at most 0.47%. Both
    modes move alike, and `Σ pr_tag = pr` to 1.8e-3.
  - [x] #102's reviewed head (`e29384ee`) merged in, at `53cd2db3`
    (2026-09-24). Under EDMF the default mode now follows the increment by
    default, so the 0M test's default-mode run carries the follower's ledger,
    and its parity filter skips it. The unit tests passed 521/521 at the
    merge. The 0M integration test (job `13892718`) is running.
  - [ ] CI on #104 at `53cd2db3`.
  - [ ] The owner's review of #104 (2026-09-24, a comment on the PR; six
    findings), addressed at `8af5f6f4` to `dfd93d7c`:
      + [x] 1, `pr_tag`'s cost: one batch per output time
        (`update_water_tag_rainouts!`) does the shared work once for all
        tags. [x] The scaling benchmark at 2, 8 and 32 tags, both modes
        (W30; 32 copies did not build in 4 h).
      + [x] 3, the explicit path in CI: its own group,
        `tagging_water_edmf_0m_explicit`, both modes; 55/55 locally.
      + [x] 4, the residual identity: `pr_tag_res`; the tests check
        `pr − Σ_P pr_tag = pr_tag_res = ∫ (Δʲ (1 − Sʲ) + Δ⁰ (1 − S))` to
        rounding in both modes, and a closed partition to rounding.
      + [x] 2, the wording: the default mode's composition is called
        reconstructed. The distinguishing experiment is WP4a-V below.
      + [x] 5, the wording: the split and `pr_tag` are signed attributions.
        [x] Measured on TRMM, both modes: none (W30).
      + [x] 6: the PR body states the scope; the Jacobian switch is WP4a-J.
      + [x] Pushed at `dfd93d7c` and answered on the PR. [ ] CI.

### WP4a-V: is the default mode's reconstruction better than the grid rule?

The owner's review of #104, finding 2. W26 showed the split differs from the
grid rule by under 0.5% on TRMM, and left the default mode's agreement with the
copies as it was. That does not tell whether the reconstruction is closer to
the truth. Acceptance criteria, fixed before the runs:

  - [ ] A case with substantial updraft rain-out and a large provenance
    contrast between the updraft and the environment (for example, a region
    tag for the boundary layer under deep convection). Chosen and justified
    before any comparison.
  - [ ] A reference: the copies, converged on a Newton ladder (known issue 4
    says one iteration is not a validated audit), or another independently
    justified tracer reference.
  - [ ] The metric, per tag and subdomain: `Σ |Δᵏ| |φ_candᵏ − φ_refᵏ| / Σ |Δᵏ|`,
    for the grid rule and for the reconstruction.
  - [ ] The criterion: the reconstruction lowers the metric materially (to be
    set with the owner before the runs) on each rung of a timestep/Newton
    ladder and a resolution ladder.
  - [ ] Reported beside it: the repair's and the bound's activation, and the
    copies' residual, so that agreement does not come from the same
    regularization on both sides.

If it fails, the default mode's split is documented as a modelled estimate
only, or reverted to the grid rule, as the owner decides.

  - [x] Pre-registered (`design/ZERO_M_RECONSTRUCTION_CHECK.md`, `ae18d56c`),
    run, and **passed** on all four rungs (FINDINGS W32): `E_recon/E_grid`
    0.086 to 0.25 against the 0.75 threshold. The docs on #104 say so at
    `4d3d56b9` (pushed after the running CI).

### WP4a-J: known issue 4's Jacobian switch

The switch and the experiment of `design/ZERO_M_SPLIT.md`, sections 4 and 5,
after the owner's decision 1 ("WP4a's two points" above). Separate from #104's
scope (the split, `pr_tag` and the restatement), by the owner's review of
#104, finding 6.

## WP4b: rain and snow carry their own tags (draft PR-W4b)

  - [ ] **WP4b-D, the design note.** It fixes:

      + the prognostic fields;
      + the operator list with file:line references;
      + the net-flow attribution between non-precipitating water, rain and
        snow;
      + the updraft's rain composition in the default mode;
      + sedimentation by the parent's flux split;
      + the Jacobian entries;
      + scratch;
      + the audit's method;
      + the cost.

    Review by `clima-numerics-reviewer` (xhigh) before any code. The operator
    list comes from `clima-inventory-explorer`.

  - [ ] Stage 1: a 1M column without EDMF. The key `water_tag_precipitation`,
    with its restart guard. `pr_tag_*` and `Σ pr_tag = pr`.

  - [ ] Stage 2: EDMF, default mode.

  - [ ] Stage 3: copies of the rain and snow parts.

  - [ ] The audit script: gross 1M process rates recomputed offline for a
    column, compared with the net-flow attribution.

  - [ ] WP4c, beside it: the leak corrections that plan 4.2's rule selects, for
    runs without rain and snow tags. *Scope added (rev. 2, 2026-09-24):* the
    entry gate is plan 4.2's operator decomposition on one parent state: per
    operator, the source before the follower, the residual's growth, the
    follower's correction and the remainder. A correction is retained if it
    leaves a remainder, cuts the follower's share of that operator's transfer
    by more than the intervention threshold, or changes per-tag provenance by
    more than the provenance threshold (OD3). One retained only for
    provenance becomes a default only with an eligible comparator or a
    documented mechanistic argument. The rest are deferred with their
    numbers, not deleted. Step 6 of the revised order.

  - [ ] Review (xhigh) of each stage.

  - [ ] **V-W5:**

      + the 0M split on and off;
      + rain and snow tags on and off, on a 1M column without EDMF and on
        D4-W in both modes;
      + the audit;
      + `Σ pr_tag = pr`.

  - *Scope added (rev. 2, 2026-09-24):* the implementation stays. "The sum
    closes to precipitation" no longer validates it scientifically; closure
    stays a separate invariant. The validation is a same-state,
    process-weighted comparison in the manner of W32, against a comparator
    that passes eligibility in that run, plus one held-out case whose rain
    falls in the established-flow window. 0M DYCOMS does not qualify: it
    rains only in its first hour (W15). Needs OD2 and OD3. The
    implementation is step 7 of the revised order; the validation is step 8b,
    after WP9's cost qualification (step 8), so that cost ceilings are fixed
    before any held-out or default evidence (review of `4507e247`).

## Qualification runs

  - [ ] **V-W6**, held out, default and copies each: RICO 1M, BOMEX
    (`bomex_column` with the passive tracer), ARM SGP 1M, and the GCM-driven
    0M column.
  - [ ] Red team before the default is confirmed (`clima-numerics-reviewer`,
    xhigh).
  - [ ] **V-W7**, the Float32 twin of D4-W.
  - [x] **V-W8**, the file-based column with water and energy tags, 3 h.
    Done: FINDINGS W22. Parity bit for bit; water gross 4.2e-4 at 3 h,
    energy source 1.3e-3; `evap` and the forcing tag fill.
  - [ ] **V-W9**, restart round trips: D4-W in both modes, and with rain and
    snow tags.

## WP6: gross accumulators, both families (draft PR-W6)

Step 1, the cache ledgers' gross twins and counts, is #103. Step 2, the state
ledgers per mechanism and their gross per step (the note's sections 3.1, 3.2
and 9), was built at `bdc75731`. All its local tests passed there.

The code review (high, `review/agent_reviews/wp6_code_review_2026-09-24.md`)
found no parity defect. It found a Float32 bug in step 1's audit event total
(B1). B1, S1, S3, S4, S5, M1, M2 and M7 were taken at `e65009ef`, and S2 as
restated claims. `1b976a97` makes the gross callback allocation-free. Local
tests pass: water units 435, energy units 500, energy integration 117, energy
EDMF 53 (at `e65009ef`), and copies integration 99 (at `1b976a97`). Pushed to
#103. The review's cadence script (`analysis/water/wp6_cadence_checks.jl`)
passed 153/153 (FINDINGS W27). At `dss` the follower and the repair work far
harder than at `stage`, which is for the owner to weigh; `dss` is not the
default. #102's reviewed head (`e29384ee`) is merged in at `f22cfb27`
(2026-09-24). The audit's net-over-time columns take WP5's new names. The unit
tests passed 457/457 at the merge, and the config tests 257/257. The increment
integration test (job `13892721`) is running, and so is CI on #103. Step 3,
the per-mechanism report and the checkpointed cache ledgers, waits on the
owner's points in the note's section 8.

  - [ ] A design note, then the code:

      + absolute repair and fix throughput, with event counts;
      + per-step `|m_left|`;
      + positive and negative loss, for τ;
      + attempted against retained changes;
      + restart segments.

    Tests: alternating signs, invariance under the output interval, restart
    stitching, model fields unchanged. Review (high).

  - *Scope added (rev. 2, 2026-09-24):* step 3 comes before the sphere and
    the default decisions (step 1 of the revised order). It requires
    accepted-step gross throughput, attempted against retained transfer,
    event counts, restart stitching and a clear validity by cadence, and adds
    Insight 10's per-tag ledger: each tag's cumulative absolute correction
    against its own water. No owner decision was needed; the owner's three
    points of the note's section 8 stay open, and the code takes the
    conservative side of each.
  - [~] **Step 3, built on 2026-09-24** on `claude/water-tags-wp6-step3`
    (worktree `../ClimaAtmosResiDyn-wp6s3`, on #103 at `f22cfb27`); design
    note section 10; not pushed.
      + [x] The audit reports, per state ledger, what the accepted steps
        retained, what its writers attempted, and the events per accepted
        step. `ledger_cadence_step` marks the runs where a transfer's
        per-step change is exact.
      + [x] Each tag's own ledgers, `q_tag_led_fix_<name>` and, under the
        follower, `q_tag_led_inc_<name>`, and the energy twins: opt-in keys
        `water_tag_ledger_per_tag` and `energy_source_tag_ledger_per_tag`.
        The audit reports each against the tag's water or energy.
      + [x] The cache accumulators travel in the checkpoint. A checkpoint
        without them starts them at zero, with a warning.
      + [x] Unit tests on the login node: `tagged_water_tests.jl` 567 passed,
        `energy_source_tags_tests.jl` 548, `config/tracer_config.jl` 267
        (`output/wp6_step3/`).
      + [ ] The integration groups and the check script
        `analysis/water/wp6_step3_checks.jl` on a compute node: jobs
        `13924194` to `13924209`, submitted by the parent session. Passed by
        its report so far: `tagging_source_float32` 53/53,
        `tagging_record` 25/25, the parent budget's restart test 34/34,
        `tagging_water_edmf_0m` 22/22, `restarts` (exit 0).
      + [ ] Review (high), then a draft PR on #103 when green (the owner,
        2026-09-24).
      + [x] *The owner, 2026-09-24:* the per-tag ledgers stay off by default
        and are on in every validation and qualification run. The fraction
        uses the tag's current inventory. The audit writes the absolute
        amount, `<L>_retained` in kg or J over the domain, in the same row as
        `<L>_inventory_fraction`: checked in `tag_ledger_audit`.

## WP2, WP8, WP9: consolidation, docs, cost

  - [ ] WP2: move only the identical helpers into shared code, with a CI test
    that runs old and new side by side, bit for bit. The energy reference is a
    merged-`main` run with decision 5.
  - [ ] WP8: docs. `tagged_water.md` gets the EDMF section, precipitation, and
    the corrected claim about diffusion operators under 1M. Also a claim
    contract for tagged water, `known_issues.md` and NEWS. Review (high).
  - [ ] WP9 and **V-W10**: cost at 2, 4, 8 and 32 tags where they build in
    time, both modes, with and without rain and snow tags, both families. P2
    and P3 only if the profile shows them. Then propose the default mode's
    cost budget to the owner, before V-W11.
      + [ ] The default mode's plume (`water_exchange_inputs!`) grows from
        2.6e-5 s at 8 tags to 1.3e-3 s at 32 on TRMM's column, and the 0M
        split around it allocates 5.7 kB at 8 tags and 1.5 MB at 32 (FINDINGS
        W30). The model's exchange pays it at every implicit evaluation. Find
        where, before the cost budget.
        **Found and cut (W34, WP9a `bfd9ff08`):** one broadcast of 33
        arguments; per tag from 32 on, the inputs cost 3.4e-4 s and 189 kB at
        32 tags, bit for bit the same. Draft PR #106 on #102. [ ] The EDMF
        integration tests at `bfd9ff08`.
      + [ ] The rest at 32 tags (W34): the per-cell `map` over 32-tuples, the
        tracer name helpers, and the exchange's own work growing faster than
        the number of tags. Before the cost budget.
      + [ ] Copies mode with 32 tags did not build a TRMM column in 4 h (W30;
        8 copies take about 15 min). Measure the build time against the
        number of copies. 8 copies 699 s, 16 copies 2417 s (W34); 32 running
        with 8 h (`13911480`). *2026-09-24 (OD8):* 32 tags are a cost item
        only and are not qualified.
  - *Scope added (rev. 2, 2026-09-24):* WP9 stays before the held-out
    default selection.
      + Its first part is the audit-feasibility decision, OD8, taken before
        WP5b-C and G4.1/G4.11 (step 3 of the revised order). Copies are not
        assumed to exist at 32 tags. From 8 to 16 copies the build grew as
        about N^1.8, which projects 2.3 h at 32; the 4 h attempt did not
        build (W30, W34), so the growth steepens past that trend.
      + The cost qualification (step 8) covers build time, peak memory and
        per-step scaling at the intended tag count, for the default and the
        comparator; the aggregation test (Insight 10); and the sphere's
        run-length budget. Its ceilings are OD3's, set before the held-out and
        default-selection runs.
      + *Decided 2026-09-24 (OD8):* 8 water and 8 energy tags; copies at 8 are
        the direct audit where they pass eligibility; no aggregation bridge
        for qualification, so the aggregation test is reported, not required.
        ~~Copies at the largest buildable count plus the aggregation
        bridge~~ is not needed. 32 tags stay a cost item, not qualified.

## The sphere

  - [ ] The sphere's numbers, set by the owner before V-W11 (plan 6.1 fixes the form).
  - [ ] **V-W11**:
      + ~~ten days of `g2_v2_sphere_n2` with water, rain and snow tags under
        the chosen default~~ *superseded 2026-09-24 (OD1, OD6):* 90 days of
        `g2_v2_sphere_n2` at 60 levels (stretching proposed in ROADMAP.md),
        with 8 water and 8 energy tags and the per-tag ledgers, under the
        chosen default, judged by the level observed against OD6's ceiling;
        its cost is M4's estimate, about 37 days on 24 ranks if cost grows in
        proportion (ROADMAP.md); after known issue 7's fix;
      + *first (the owner, 2026-09-24):* a 1 to 2 day run of the 60-level
        sphere on the proposed grid, untagged and with 8 water and 8 energy
        tags, to measure step time, memory per rank and the ranks needed,
        after step 8a;
      + a one-day copies twin;
      + a restart after day 1;
      + a two-rank parity pair.
  - [ ] G3's closing entry, and the question of what comes next.

## G4: the energy source tags, after G3

G4's items, G4.1 to G4.14, are in [G4_TODO.md](G4_TODO.md), with the energy
items of the former OPERATIONAL_TODO. The prepared design of synergy 2, the
Float64 twin that WP0 builds, is at the end of that file.

## Agents

Defined in `~/.claude/agents/`. None of them submits jobs, pushes or merges.
Reports go to `review/agent_reviews/`.

| Definition                 | Model, effort             | Used for                                         |
|:-------------------------- |:------------------------- |:------------------------------------------------ |
| `clima-numerics-reviewer`  | Opus, xhigh               | WP3, WP5, WP4a, WP4b-D, WP4b, WP2, red team      |
| `clima-reviewer`           | Opus, high                | WP1, WP6, WP8                                    |
| `clima-analysis-builder`   | Sonnet, medium            | the verifier, tables, the audit's scaffolding    |
| `clima-inventory-explorer` | Sonnet, medium, read-only | the operator list for WP4b-D, the claim contract |
