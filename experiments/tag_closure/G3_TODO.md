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
    after V-W3.
  - [ ] **The prognostic fields of the rain and snow tags**, settled in the
    design note WP4b-D and its review. The recommended option is the
    non-precipitating, rain and snow parts.
  - [x] **A durable archive** for the minimal reference datasets:
    `~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/`, at most 5 GB.
    Decided by the owner on 2026-09-23.
  - [!] **ERA5 forcing for V-W8**, if it is not on disk. A download needs the
    owner.

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
  - [ ] Review the phase-1 tools (the old item 1.8), then write a FINDINGS
    entry. From here on every headline number goes through the verifier.
  - [ ] Extend the verifier to `q_tag_*`, the copies in `sgsʲs`, the rain and
    snow parts, and `pr_tag_*` (`clima-analysis-builder`).
  - [ ] The manifest in this session's submit path. Classify the run inventory.
  - [ ] The Float64-twin helper (synergy 2), for V-W7. It is a precision-sensitivity
    screen and decides no cause (G4_TODO, prepared item 2).
  - [ ] Check that V-W8's ERA5 forcing is on disk, and that the copies against
    tracer test (plan S3) can be configured.
  - [ ] V-W0c: one untagged D4-W day with EDMF diagnostics, to size the
    updraft's rain and snow, the surface excess and the five 1M leaks.
  - [ ] V-W0a: known issue 4, a precipitating 0M column, 1 against 10 Newton
    iterations. Close or restate the issue.
  - [ ] V-W1: D4-W with grid-scale tags on `main` + #95, before WP1's refusal,
    and its untagged twin: the "before" numbers.
  - [ ] Checksummed minimal datasets for headline tables, in the archive's
    `reference_data/`, within 5 GB.

## WP1: refusals, reserved names, known issues (draft PR-W1)

  - [ ] Refuse `water_tracers`:

      + with `prognostic_edmfx`, until WP3 lands;
      + with the AMD LES model, always.

    Warn under `PrescribedFlow`. Do not refuse `water_process_record`.

  - [ ] Reserve colliding tag names: `res`, `fix_*`, `upfix_*`, `inc_*`,
    `rtag_*`, `stag_*`.

  - [ ] Known issue 1 closed with the post-#64 numbers from the CI log. Issue 3
    updated.

  - [ ] Tests for each refusal. Review by `clima-reviewer` (high).

## WP3: total water under EDMF (draft PR-W3)

  - [ ] The switch `water_tag_updraft_copy`.

  - [ ] Default mode:

      + the donor share of the parent's `ρq_tot` SGS flux;
      + the exchange with weight `q_totᵏ` and decision 5's bound;
      + the water plume rescaled to `sgsʲs.q_tot` at each level, starting from
        the grid mean's composition;
      + the plume computed once, at the top of `implicit_tendency!`, into the
        tags' own scratch.

  - [ ] Copies mode: `q_tag_<name>` in `sgsʲs`, with the four mirrors:

      + the updraft's 0M sink, `χᵢʲ += dq (φʲᵢ − χᵢʲ)` with φ clamped;
      + the updraft's 1M sedimentation, including the lateral inflow, with a
        diagonal Jacobian entry;
      + the surface relaxation target `q_b φ̄ᵢ`;
      + the residual repair after the filter, with its ledger `q_tag_upfix_*`
        and `r` as a diagnostic.

  - [ ] Copies initialised and rebuilt as `q_totʲ φ̄ᵢ`. The comparison driver
    starts them from the plume.

  - [ ] The restart guard for copies. Refusals:

      + `updraft_number > 1`;
      + copies without prognostic EDMF;
      + copies with unequal updraft upwinding;
      + the exchange without a region partition.

    Lift the WP1 refusal for one updraft.

  - [ ] Bound activation in the water audit, per source tag.

  - [ ] Diagnostics of the five 1M leaks, in closed form (plan 4.2).

  - [ ] CI group `tagging_water_edmf` (Julia 1.10 and 1.11, downgrade):

      + parity in both modes, on the 1M and 0M EDMF columns and with explicit
        microphysics;
      + the copies against a passive tracer at rounding, with water-specific
        terms off;
      + manufactured mixing tests on a frozen parent.

  - [ ] Review by `clima-numerics-reviewer` (xhigh).

  - [ ] **V-W3:**

      + D4-W, default against copies, each with a 10-Newton twin;
      + bound activation;
      + a surface pulse;
      + the TRMM 0M development case, default against copies.

    Record the result as a FINDINGS entry. Apply WP5's rule.

## WP5: following the parent's increment (draft PR-W5)

  - [ ] `water_tag_transport: increment`:

      + after each solve the tags take the parent's `ρq_tot` increment;
      + the part that changes a column's total stays in place, with ledgers
        `q_tag_inc_left` and `q_tag_inc_moved`;
      + the tags' explicit vertical advection is skipped;
      + the hook composes with the energy one;
      + the stepper check is reused.

  - [ ] Its default under EDMF, by the rule in plan 4.3.

  - [ ] Review (xhigh).

  - [ ] **V-W4**, the ladder, default and copies at each rung:

      + dt 60 and 30;
      + Newton 2, 4 and 10;
      + 60 and 120 levels;
      + first-order upwinding.

    It also records the wall time of each rung (R5), and gives the copies'
    own convergence.

## WP4a: the 0M split (draft PR-W4a)

  - [ ] Production `Σₖ max(Δᵏ, 0)` by mask and loss `Σₖ min(Δᵏ, 0) φᵏ`, with
    the environment's term as the model weights it, in the implicit and
    explicit microphysics paths.
  - [ ] `pr_tag_<name>` under 0M.
  - [ ] Review (xhigh).

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
  - [ ] **V-W8**, the file-based column with water and energy tags, 3 h.
  - [ ] **V-W9**, restart round trips: D4-W in both modes, and with rain and
    snow tags.

## WP6: gross accumulators, both families (draft PR-W6)

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
