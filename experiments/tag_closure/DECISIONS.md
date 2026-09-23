# The owner's decisions

Every decision of the register (`review/register/decisions.csv`), one line
each, grouped by date, newest first. Each links to where it is recorded. A
short section at the end adds decisions that the documents record but the
register does not list.

Marks: **in force**, **done** (carried out, nothing left), **superseded** (with
what replaced it), **waiting** (the owner has not decided yet).

The archived originals keep their text. Links into
`archive/2026-09-23/` point there. "Memory" means the owner's Claude project
memory, outside the repository.

Short names for the sources:

  - CP: [CONDENSE_PLAN.md, the owner's decisions of 2026-09-23](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - G3P: [G3_PLAN.md, section 0](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - G3T: [G3_TODO.md, Decisions](G3_TODO.md#decisions)
  - OT: [archived OPERATIONAL_TODO.md, "Decided"](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## Waiting for the owner

  - **The sphere's numbers**, in the form G3_PLAN 6.1 fixes, before V-W11.
    **Waiting.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
  - **The default mode's cost budget**, proposed from V-W10's first
    measurements, set before V-W11. **Waiting.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
  - **WP5's default transport under EDMF**, by the rule fixed in G3_PLAN 4.3,
    after V-W3. The rule decides; the owner confirms. **Waiting.** [G3T](G3_TODO.md#decisions)
  - **The prognostic fields of the rain and snow tags**, settled in design note
    WP4b-D and its review. Recommended: the non-precipitating, rain and snow
    parts. **Waiting.** [G3T](G3_TODO.md#decisions)

## 2026-09-23

  - **V-W8's file-based column is the GCM-driven one** (`prognostic_edmfx_gcmdriven_column`),
    not the ERA5 column, whose forcing is not on disk and has no download
    entry. Its forcing artifact was fetched the same day. **In force.**
    [G3T](G3_TODO.md#decisions), [G3_PLAN 6](G3_PLAN.md#6-experiments)
  - **How G3's budgets are read** (G3_PLAN 6.1): the share from the reference
    at the same hour; for a small tag the absolute test replaces L1 and L∞; a
    tag that is region and source is judged as a source tag; the gross
    residual is `Σ |q_tag_res| ρΔz` over the column water, and "the second 12 h
    add no more" is `G(24) − G(12) ≤ G(12) − G(0)`; the precipitation audit
    needs averaged or accumulated output. Accepted as the phase-1 review
    proposed them. **In force.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
  - **This session's goal is G3's WP0 and WP1.** Done when the plan's
    assumptions are checked against the merged #95, the verifier and tools
    are extended, V-W0a, V-W0c and V-W1 are run and recorded, and draft PR-W1
    is open, reviewed and green. Jobs stay within WP0 and WP1, and the only
    model code is WP1's. **In force.** Memory: `session-goal-wp0-wp1.md`
  - **The minimal reference datasets go to
    `~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/`**, at most 5 GB.
    **In force.** [G3T](G3_TODO.md#decisions)
  - **G3's budgets are set** (G3_PLAN 6.1). Per tag at 24 h: L1 ≤ 2%, L∞ ≤ 5%.
    First hour: L1 ≤ 1% for region tags and ≤ 10% for source tags, L∞ ≤ 25%.
    Tags below 1% of the partition pass on absolute error. Closure: 0.2% gross
    at 24 h, with no growth, and at most 1e-6 left after the named parts. The
    copies' repair moves at most 0.2%. Convergence is judged as robustness,
    not between rungs. Rain and snow: 1e-8 in Float64, and the audit within
    10% on the column without EDMF. The sphere's form is fixed, and its
    numbers come before V-W11. The default mode gets a cost budget, set
    before V-W11. **In force.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
  - **Revive the condense plan.** Results are re-checked now only where G3
    relies on them. The full re-check moves to the start of G4. **In force.**
    [CP 1](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **Rebuild the record branch on `main`** (`claude/tag-closure-record`).
    **Done.** [CP 2](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **Take the terrabyte setup to `main` in a small PR** (#96). **In force**;
    #96 was merged on 2026-09-23 (`3ecb6d25`). [CP 3](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **The durable archive is `~/git/Clima/ClimaAtmosResiDyn-archive/`.** The
    workspace `AGENTS.md` records it as an exception to "no data in `$HOME`".
    **In force.** [CP 4](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **`$HOME` holds code and configs only**, with the archive directory as the
    recorded exception. **In force.** Workspace `~/git/AGENTS.md`, "Storage"
    (outside this repository).
  - **Worktrees and branches are removed only by a list the owner approves**
    (H7). **In force.** [CP 5](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **`docs/src/tag_closure_memo.md` and `tag_closure_experiments.md` are
    marked historical**, and move to the archive later (#97). **In force.** It
    replaces the older rule that the owner is asked about each change there
    (the archived NEXT_SESSION.md, register item `NS-1`).
    [CP 6](archive/2026-09-23/CONDENSE_PLAN.md#the-owners-decisions-of-2026-09-23)
  - **Set G3**, re-scoped the same day: the water tags under EDMF, operational
    in production. G4, the energy tags, follows with G3's learnings. **In
    force.** Memory: `programme-after-g2.md`
  - **G3 is the water tags under EDMF; G4 is the energy source tags** and uses
    what G3 learns. **In force.** [G3P 1](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **The water tags become operational in the production configuration**, a
    sphere with prognostic EDMF and 1M. EDMF support is a correctness
    requirement, not an extension. **In force.** [G3P 2](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **Precipitation provenance is in scope; rain and snow carry their own
    tags** (the review's option b). Under 0M the sink is split by subdomain.
    Under 1M falling water keeps the provenance it formed with. **In force.**
    [G3P 3](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **The exchange is the default for water tags under EDMF, and updraft copies
    are the audit**, behind one switch, as for energy in #95. **In force.**
    [G3P 4](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **The bound takes its factor from the partition only, and each source tag
    gets its own**, in both families. The instruction (`2ecc1d86`) was
    carried out in #95 at `dcf7d086` and then removed at the owner's request (`a52b17f7`). Its text is kept under the tag `archive/g3-programme-2026-09-23`. **In force**; built in #95 at
    `dcf7d086`. [G3P 5](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **This session (`ClimaAtmosResiDyn-exp`) runs G3's jobs.** A separate
    session runs the energy jobs and owns PR #95. **In force.**
    [G3P 6](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **The job session is not reachable through SendMessage.** It runs the
    energy jobs and owns #95's fix (worktrees `-upd`, `-upd-run`). Findings are
    relayed through the owner. **In force.** Memory: `programme-after-g2.md`
  - **GPU is out of G3.** The sphere runs on CPU with MPI. **In force.**
    [G3P](G3_PLAN.md#0-decisions-this-plan-rests-on)
  - **G3's decisions in short**: water and energy as above, the production
    target, precipitation provenance with rain and snow tags, exchange by
    default with copies as the audit, the partition-only factor, and this
    session running G3's jobs. **In force.** [G3T](G3_TODO.md#decisions)

## 2026-09-22

  - **G2 is met (FINDINGS E75).** The standing approval for G1 and G2 ends
    there. **Done.** Memory: `goal-g1-g2.md`

## 2026-09-20

  - **Criterion 4's threshold, in two parts:** (a) the one-iteration solve's
    effect at 1 h, L1 ≤ 1% (region) and ≤ 10% (source), L∞ ≤ 25%; (b) the
    default exchange against the audit's copies at 24 h, L1 ≤ 2% and L∞ ≤ 5%.
    Both met, so **G1 is met**. **Done.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The exchange keeps the parent's face scheme**, centred where the parent
    is centred, which matches the audit most closely. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **G2 reports two ten-day runs:** `g2_v2_sphere_n2` for closure and the
    residual, then a rerun with the updraft mixing on for the per-tag numbers.
    **Done** (E74, E75). [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The short-term goal: finish G2, then the review's polish.** In order:
    `g2_v2_sphere_mix`, then three small review items and housekeeping. The GPU
    compile is dropped. Keep token use low. **Done.** The register dates this
    2026-09-19; the source says 2026-09-20.
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## 2026-09-19

  - **Standing goal: work toward G1, then G2**, and no further without asking.
    Jobs within the goals may run without asking each time. **Superseded:** G2
    was met on 2026-09-22, and the owner set G3 on 2026-09-23.
    Memory: `goal-g1-g2.md`
  - **V3 is approved:** a passive tracer with an updraft copy beside the tags
    on D4, to measure the tags' mixing against the air's own. **Done** (E68).
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Corroborate and condense the documents by CONDENSE_PLAN.md**, after V2's
    entries. Put on hold the same day at 13:10. **Superseded** by CP decision
    1 of 2026-09-23, which revived it. [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **#93 and #94 are merged**; the `enthalpy_increment` prototype is on
    `main`. **Done.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Criterion 4 of G1 waits until the updraft gap is closed** ("Accuracy is
    highly important. Lets ask that question again after the updraft gap is
    closed"). **Superseded** by criterion 4's threshold, set on 2026-09-20.
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The way to close the updraft gap: one logical switch** between updraft
    copies of the tags (audit) and a zero-sum exchange (default), as in
    [design/UPDRAFT_GAP.md](design/UPDRAFT_GAP.md), "The chosen way". **Done**:
    built as #95. [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Question 2a, the mixing convention: the hybrid, as built.** Tracer-like
    mixing for turbulent exchange, and the enthalpy flux form for resolved
    transport and pressure work. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Question 2b, the offset: keep c = 110,495 J/kg** for every G1 and G2 run,
    stated with each per-tag result. U8's temperature-floor rule comes before
    any run whose surface air could fall below about 228 K. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Question 3, the correction: keep it as built.** It moves only the
    column-local part, logged in `e_src_inc_moved`. Column totals stay visible
    in `e_src_res` and the ledger. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## 2026-09-18 (section 1 of OPERATIONAL_TODO, gone through with the owner)

  - **#77's three choices** (decision 2): accepted as written. **Done.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **C2's design** (decision 11), approved minimal: the check covers the
    process-record fields; the spin-up reference follows #77; no override key;
    starting tags from a tagless checkpoint becomes N item U7. **Done** (#92).
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The parity break `dd06318f`** (decision 12) stays as a named exception.
    No upstream PR; the tag `archive/upstream-vwb-species-guard` and the
    archived `UPSTREAM_VWB_PR_DRAFT.md` keep the record. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **ClimaCore** (decision 3): #76 keeps the `MatrixFields` internals, and the
    drafted issue is not filed. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The named regions' width** (decision 10): 2° stays. The docs should say
    that a mask narrower than the grid spacing makes the repair trade, and that
    a 10° mask avoids it on coarse grids. **In force**; the docs part is open
    in [G4_TODO.md](G4_TODO.md), G4.1. [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **V1** (decision 5) is folded into V2, a ten-day Float32 run. **Done.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Phase B** (decision 7): B1 is approved, one job, at the plan's settings.
    B1a to B1c, B2 and B3 are not. **Done** (B1 ran, E50).
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Runs** (decision 8): V2 and V6 approved once C1b is merged. MP1 on two
    nodes is not. **Done** (V2 and V6 ran). MP1 on more than one node stays not
    approved ([BACKLOG.md](BACKLOG.md)). [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **B3** (decision 6, the design's decision 5): extend the audit to the SGS
    diffusive flux, as C1c, after C1b. This changed the decision of 2026-09-11.
    **Superseded:** C1c was built and made D4's residual larger in every
    placement (E59), and was shelved. The increment prototype replaced it
    (attribution path question 1, 2026-09-19, below). `review/register/conflicts.csv`
    records this pair. [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **2M and P3** (decision 6, the design's decision 6): once upstream lifts
    the model's gate, the tags accept 2M, and refuse P3 at configuration until
    the parent's P3 sedimentation is fixed. **In force, waiting for upstream**
    (the gate is still closed). The register files it as waiting for the owner;
    nothing is the owner's to do until upstream lifts the gate. [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **A4** (decision 4): later, as an N item. **In force** (A4 is shelved in
    G4_TODO.md). [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **D1** (decision 9): after V2. Here D1 is the user guide, not the run
    `d1_column_1m_ice`. The register reads it as the run; the archived
    OPERATIONAL_TODO's section 2, item 12, "D1, the user guide into the docs",
    shows it is the guide. V2 has run. The guide is in #95 and closes when #95
    merges (G4_TODO.md, G4.1). **Done in part.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Aqua's walk upstream** (item 14): not reported. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **One moist model in `parent_budget`** (item 15): no. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **#80's NEWS entry:** none. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The 17 worktrees whose branches are merged are removed.** **Done.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## 2026-09-17

  - **The fragile defect test** (decision 13): the convergence check stays on
    the moist DYCOMS column. **Done** (#81). [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The CI plan:** fork-owned groups keep Julia 1.10 and 1.11; upstream
    groups run on 1.11, with a manual `ci` run for 1.10 on PRs that edit
    upstream code; `Downstream` after merges, weekly and on demand; package
    images for a portable CPU target; a type audit of `parent_budget` before any
    split. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Aqua:** add the missing weak dependency as a test extra first; when the
    walk stopped at the next package, bound Aqua instead (#86). **Done.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## 2026-09-16

  - **`gh repo set-default johannespletzer/ClimaAtmosResiDyn.jl`** in the main
    clone, so `gh` targets the fork and not `CliMA/ClimaAtmos.jl`. **In force.**
    The memory note dates the setting 2026-09-17. Memory:
    `gh-upstream-remote-default.md`

## 2026-09-14

  - **The offset (U1)** is required whenever energy source tags are set. An
    explicit 0 keeps the old behaviour. The refusal quotes 110,495 J/kg and the
    smallest positive-making offsets, 45.4 and 100.4 kJ/kg. **Done** (#77).
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The closure check (U2, R1)** is on by default with the tags: daily, from a
    spin-up reference, report-only until V2 and V3 calibrate a tolerance per
    transport. **Done** (#77); the calibration is G4.5.
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The per-process checks (A2, A3):** the label check at configuration now;
    A2's runtime part and A3 later, as optional validation features. **Done**
    for the label check. A2's runtime part and A3 are open (G4_TODO.md, last
    section). [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The S items, grouped for delivery:** now C5, P1, D2; with B9 U3, U4, R3,
    T4; with C1b M3, T5; before the GPU T3; with V2 C4, V6; with D1 D3. A4, A5
    and A7 move to N. **Done.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Merges:** #69 and #70 merged; push #72's docs, retarget it to `main`,
    take it out of draft; open #74. **Done.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Standing approvals:** up to 8 P4 jobs on `hpda2_test` (≤ 2 CPUs, 48G,
    2 h each); code as draft PRs to `main`, merged only by the owner; runs at
    their predecessors' settings (the C6 twin, V5, C1b's validation); pushes as
    draft PRs. **Done**: used up, and replaced by later per-run approvals.
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **Parity with upstream is a boundary condition.** With a diagnostic on,
    every field upstream has stays bit for bit the same. Written into
    `AGENTS.md` and `docs/clima_atmos_specific.md`. **In force.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **`SeasonalSST` is removed entirely** (#80). The transient stratospheric
    tracer examples use `PrescribedSST` again. **Done.**
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **The binary comparison against an upstream checkout is skipped for now**
    (P6). **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## 2026-09-11

  - **Production is a GPU sphere in Float32, with EDMF and 1M.** The GPU check
    comes last. **In force.** [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)
  - **EDMF:** refuse `prognostic_edmfx` with the tags now (C1a, done in #70);
    build the sharing later (C1b), under both transports, in the implicit
    tendency, with a guard in the shared tracer loop (B4). **Done** (#70, #91).
    Its B3 part was changed on 2026-09-18, see above.
    [OT](archive/2026-09-23/OPERATIONAL_TODO.md#decided)

## Also recorded, not in the register

These decisions are in the documents but have no row in `decisions.csv`.

  - **2026-09-23. The wider local-branch deletion of H7 is accepted, in this
    case.** All 37 merged local branches were deleted, not only the listed
    ones. Every tip is in `origin/main`. The rule that removal goes by an
    approved list stays in force. **Done.** The owner, in this session.
  - **2026-09-23. H7's list of worktree and branch fates is approved**, and
    partly carried out the same day. **In force** for what waits.
    [CONDENSE_PLAN.md, H7](archive/2026-09-23/CONDENSE_PLAN.md#h7-approved-by-the-owner-on-2026-09-23)
  - **2026-09-23. Every job within G3 is approved, and the agents as
    proposed.** Model code goes into draft PRs that only the owner merges.
    **In force.** [G3_TODO.md](G3_TODO.md)
  - **2026-09-19. Attribution path, question 1:** rebuild the tags' implicit
    channel on the parent's own increment, as the opt-in
    `enthalpy_increment`. **Done** (#94, merged). It replaced C1c.
    [archived OPERATIONAL_TODO.md, "0. In flight"](archive/2026-09-23/OPERATIONAL_TODO.md#0-in-flight)
  - **2026-09-18. P8, CI's slowdown after #89, is accepted for now.** Watch
    #91's first run. **In force.** [archived OPERATIONAL_TODO.md, section 3](archive/2026-09-23/OPERATIONAL_TODO.md#3-should-fix-s)
  - **2026-09-11. The enthalpy audit's four choices**, all as proposed: the key
    `energy_source_tag_transport` (`tracer` or `enthalpy`); `enthalpy` without
    an offset refused; vertical and horizontal advection and hyperdiffusion;
    the parent's `energy_q_tot_upwinding`. **Done** (#72).
    [archived ENTHALPY_AUDIT_DESIGN.md](archive/2026-09-23/ENTHALPY_AUDIT_DESIGN.md#decisions-for-the-owner)
  - **2026-09-10. Keep both the energy source tags and the process record**,
    and make them operational. This is the goal the roadmap divides.
    **In force.** [archived LEVANTE_TASKS.md, 1b](archive/2026-09-23/LEVANTE_TASKS.md#1b-making-the-energy-source-tags-operational)
  - **2026-09-10. C1 approved**, the first jobs an agent submitted on
    terrabyte. Approval is per job. **Done.** [archived README.md](archive/2026-09-23/README.md)
  - **Undated. B1's grid and length:** `numerics_sphere_he6ze10.yml`, ten days,
    on the shared CPU partition. **Done** (B1 ran, E50).
    [archived README.md, "Open items"](archive/2026-09-23/README.md#open-items)
