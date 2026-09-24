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
| 11 | Ten days on the sphere, a copies twin, a restart                                       | open                     |
| 12 | Reviews, CI, draft PRs, docs                                                           | open                     |

## Decisions

  - [x] G3 is water and G4 is energy; production target; precipitation
    provenance with rain and snow tags; exchange by default with copies as the
    audit; the partition-only factor; this session runs G3's jobs. All decided
    by the owner on 2026-09-23.
  - [x] **The budgets of plan 6.1**, set by the owner on 2026-09-23: per tag
    2% and 5% at 24 h with G1's first-hour split; closure 0.2% with at most
    1e-6 left after the named parts; convergence as robustness; rain and snow
    as proposed; the sphere's form.
  - [ ] **The sphere's numbers**, set by the owner before V-W11, in the form of
    plan 6.1.
  - [ ] **The default mode's cost budget**, proposed from V-W10's first
    measurements and set by the owner before V-W11.
  - [ ] **WP5's default transport under EDMF**, by the rule fixed in plan 4.3,
    after V-W3. V-W3 has run: the one-iteration part is 5.8e-3, twelve times
    the rule's threshold, so the rule selects the follower (FINDINGS W21).
    The owner confirms.
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
    diagonal alone.
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
  - [ ] Tests at `63a1ddaa`, and the review's explicit-path parity script
    (`analysis/water/wp4a_explicit_parity.jl`), running.
  - [ ] Draft PR-W4a; CI; the TRMM validation (`configs/w4a_trmm0m_*.yml`).

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
    runs without rain and snow tags.

  - [ ] Review (xhigh) of each stage.

  - [ ] **V-W5:**

      + the 0M split on and off;
      + rain and snow tags on and off, on a 1M column without EDMF and on
        D4-W in both modes;
      + the audit;
      + `Σ pr_tag = pr`.

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
restated claims. Its tests and the review's cadence script
(`analysis/water/wp6_cadence_checks.jl`) are running. Step 3, the
per-mechanism report and the checkpointed cache ledgers, waits on the owner's
points in the note's section 8.

  - [ ] A design note, then the code:

      + absolute repair and fix throughput, with event counts;
      + per-step `|m_left|`;
      + positive and negative loss, for τ;
      + attempted against retained changes;
      + restart segments.

    Tests: alternating signs, invariance under the output interval, restart
    stitching, model fields unchanged. Review (high).

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

## The sphere

  - [ ] The sphere's numbers, set by the owner before V-W11 (plan 6.1 fixes the form).
  - [ ] **V-W11**:
      + ten days of `g2_v2_sphere_n2` with water, rain and snow tags under the
        chosen default;
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
