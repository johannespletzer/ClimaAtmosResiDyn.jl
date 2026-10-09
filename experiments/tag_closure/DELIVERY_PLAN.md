# Delivery plan for parts 8 to 12d

Proposed 2026-10-08, waiting for the owner. Base: `claude/plan-rev2` at
`7c96c2046`, which contains `main` at `b7db975e7`. Parts 1 to 6 are merged.
Part 7's PR is pending.

This plan sequences one PR per remaining part of the
[capability increments](ROADMAP.md#capability-increments-2026-10-05). For each
part it gives the agent brief, the gate to clear before starting, what the PR
contains, what stays out, which runs need an approval, and the budget. It adds
no scientific criterion and changes no threshold. ROADMAP.md, the water contract
([G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)), the
[energy matrix](design/G4_CLAIM_CONTRACTS.md#5-energy-acceptance-matrix),
DECISIONS.md and PLAN_CROSSWALK.md stay authoritative. Where this plan and a
source differ, the source wins and the difference is a defect of this plan.

## 1. Decisions this plan rests on (owner, 2026-10-08)

  - **Executor.** Claude agents in the owner's session prepare every PR. Author
    and reviewer are separate agents with separate contexts.
  - **PR content.** A part's PR holds the pre-registered design, the tooling with
    tests, the job scripts and the status updates. It executes no model run.
  - **Runs.** Every job runs on the LRZ Slurm cluster after the owner approves
    that job. Results, converter bundles and scorer verdicts land in a follow-up
    PR that closes the part.
  - **Sequence.** Roadmap order, one PR per part: 8, 9, 10, 11a, 11b, 11c, 11d,
    12a, 12b, 12c, 12d. Part 9 and 11c are queues. Their count follows from the
    baseline parts 8 and 11b. 11a may run beside the water parts.
  - **Branches.** Model code targets `main`. Planning documents and records
    target `claude/plan-rev2`. A code PR gets a small follow-up on `plan-rev2`
    for its status, crosswalk and record updates.
  - **Budget.** Each part states its estimate before the author stage and the
    owner approves it. The session stops and reports when a part reaches its
    estimate.
  - **Timing.** The part 8 brief is written now and starts after part 7 merges.
    Open owner items are inputs with a default each, not blockers.

## 2. The pipeline for every part

| Stage             | Who                                                                                                                                        | Produces                                                                                                                                                                                                       |
|:----------------- |:------------------------------------------------------------------------------------------------------------------------------------------ |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A Preflight       | Session (Opus)                                                                                                                             | The gate row in section 3 checked against the tree, the brief instantiated with SHAs and paths, the open inputs with defaults, the budget estimate for the owner.                                              |
| B Author          | `clima-reviewer` (Opus high) for a design PR. `clima-numerics-reviewer` (Opus xhigh) for code that touches tendencies, parity or defaults. | A draft PR from the brief: design document, tooling with tests, job scripts with cost estimates, status rows. At most two `worker` (Sonnet high) inventories as helpers.                                       |
| C Review          | `worker` (Sonnet high) finder, then `clima-reviewer` or `clima-numerics-reviewer` confirmation                                             | Findings as {file, line, claim, evidence, severity}, with single-constant mutation runs on every new script. The Opus stage classifies blocking, patch now, owner decision, nit. It applies patches and tests. |
| D Owner decisions | Session, after an xhigh adversarial challenge of each recommendation                                                                       | One question per item with a background brief, options and a recommendation. Answers go to DECISIONS.md and the register CSV on the PR branch.                                                                 |
| E Merge           | Owner for `main`. Session pushes merge commits on `plan-rev2`.                                                                             | One consolidated PR comment: verdict, confirmed list, patches with commits, owner items, nits, agents used.                                                                                                    |
| F Runs and record | Session submits each approved job. `worker` runs the converter and scorer.                                                                 | Output under `$SCRATCH/tag_closure/output`, synced to the archive before scratch is cleaned. A follow-up PR with the record `analysis/evidence/PARTn.md`, the STATUS row and the verdict.                      |

Rules that apply at every stage:

  - The author ticks no completion mark, runs no model job and changes no
    threshold, default or tolerance. A proposal is marked proposed with a date.
  - Every new script has tests. Every threshold a script reads is pinned by a
    test, which the mutation run in stage C checks.
  - Every PR states parity evidence where code changes, restart and schema checks
    where state changes, and the CI groups it ran. The Julia 1.10 precipitation
    group is the memory-critical one on the 16 GiB runner.
  - Runs in the energy family have no standing approval. Any set over 12 jobs or
    24 hours goes to the owner first. Multi-node, GPU and the 90-day sphere are
    not approved until the owner says so for the named run.
  - Existing evidence is reused as scoped. A rerun is proposed only where the
    changed code, physics or claim invalidates it. W54 to W62 and E87 to E90 were
    measured before PR #146 and ClimaParams 1.3.0, so the baseline parts measure
    again on the current `main` and label the earlier numbers as prior.
  - Cost per PR, from parts 1 to 6: a design PR about 0.8 to 1.0M subagent tokens
    (author 300 to 400k, finder 150 to 250k, confirmation 200 to 300k, challenge
    50 to 100k). A code PR about 1.0 to 1.3M. A follow-up record PR about 0.3M.

## 3. Sequence and gates

| Part | PR base                          | Starts when                                                                                               | Blocked today by                                                                                    | Estimate      |
|:---- |:-------------------------------- |:--------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------- |:------------- |
| 8    | `plan-rev2`                      | Part 7 merged. PX12 run, since it gates the first-hour row.                                               | Part 7 not started. W58 not archived. PROCESS_WEIGHTED rows blocked behind REFERENCE.PARENT_PARITY. | 0.9M + 0.3M   |
| 9    | `main`, follow-up on `plan-rev2` | Part 8's dominant-error table. Reference-demonstrated small fixes may start after parts 6 and 7.          | Part 8. The walk fix goes upstream by the owner's decision.                                         | 1.2M per fix  |
| 10   | `plan-rev2`                      | Part 9's queue done, including the walk fix and its post-fix cost measurement. PX11 and PX24 before PX23. | Parts 8 and 9. Criterion 10 at 4.16x against OD3's 2x until the walk fix is measured.               | 0.9M + 0.3M   |
| 11a  | `plan-rev2`                      | Now, beside the water parts.                                                                              | Nothing. Floors and the accepted-stage flux reference are its own deliverables.                     | 0.9M          |
| 11b  | `plan-rev2`                      | Part 9's shared-code PRs and the walk fix merged. 11a merged.                                             | Parts 9 and 11a. Converter producers for E87 (source_partition_valid, six of eight tags).           | 0.9M + 0.3M   |
| 11c  | `main`, follow-up on `plan-rev2` | 11b's defect table.                                                                                       | 11b. OD7 for the follower.                                                                          | 1.2M per fix  |
| 11d  | `plan-rev2`                      | 11b and 11c done. Owner's accuracy, scope and cost choices for energy made.                               | 11b, 11c. EA-ACCURACY and EA-COST lapsed with EA-USE, so a stored-source claim needs fresh choices. | 0.8M + 0.3M   |
| 12a  | `plan-rev2`, `main` if code      | Part 10 or 11d delivered.                                                                                 | 10, 11d. Rain/snow Float32 closure waits for WP4b stage 2.                                          | 0.8M + 0.3M   |
| 12b  | `main`, follow-up on `plan-rev2` | Relevant qualification. Multi-node approval for MP1 beyond two nodes.                                     | 10. Multi-node not approved.                                                                        | 0.9M          |
| 12c  | `main`, follow-up on `plan-rev2` | Part 10 delivered. The walk fix is part 9's item, not 12c's.                                              | 10.                                                                                                 | 1.0M per item |
| 12d  | `plan-rev2`                      | The 1-2-day pilot after part 8's contract exists. The 90-day run after 12a, 12b and 12c.                  | 8 for the pilot. 12a to 12c and the run approval for the 90 days.                                   | 0.8M + 0.3M   |

Reading the table: 11a starts now. Part 8 starts after part 7. Everything else
waits for a baseline or a qualification. The walk fix has one place: it is an
item of part 9's queue, with its post-fix cost measurement, because part 10
needs that measurement for criterion 10 and 11b starts after it. Part 12c holds
the remaining optimizations after part 10. The chain 10 to 12a to 12d and 10 to
12c to 12d is serial by the owner's 2026-10-07 decision, so the 90-day run is
last.

## 4. Housekeeping before part 8

The inventory for this plan found statements that contradict the tree or each
other. One small document PR against `plan-rev2` fixes them before the part 8
brief is instantiated, so the author reads a consistent base. Done on
2026-10-09 in the housekeeping PR, except the archive sync and the owner's word
on the `wp9_cost_namewalk` runs. The check found two of the items overstated,
and the corrected wording is below.

  - ROADMAP, G3_TODO, G3_PLAN and STATUS still call PR #146 open. It is merged at
    `12377fb88`, as PART5.md says.
  - The crosswalk rows for PX1, PX8, PX7, PX11, PX24 and PX12 still route to
    part 6. The 2026-10-08 decision moved those runs to part 7. PX3, PX5 and PX9
    are not named by the decision and keep their rows.
  - PART5.md says the energy cancellation-safe accounting condition waits for the
    owner. DECISIONS.md of 2026-10-08 has it in force.
  - STATUS.md says OD7 is the only open numbered decision. OD9 to OD11 and OD15
    are proposed.
  - The 1-2-day sphere pilot sits beside part 8 in one roadmap row and as the
    first step of 12d in another. This plan reads it as 12d work that may start
    once part 8's contract exists, and says so in both briefs.
  - The scratch runs `wp9_cost_namewalk` and `wp9_cost_namewalk2` (2026-10-02 and
    2026-10-03) are in no register. RUNS.md gets a row that names them as
    unregistered attempts, pending the owner's word on what they were.
  - The tools `sub_probe.jl`, `tag_process_probe.jl` and `perturb_probe.jl` are
    named in the PX designs and do not exist. Part 7 owns the first two with PX8
    and PX24. The third belongs to PX9, which is conditional and not assigned.
    The crosswalk rows that name them say so.
  - W58's outputs exist on scratch only. The archive sync is a prerequisite of
    part 8 and is done before its rerun.

## 5. Briefs

Each brief has the same shape: goal, scope, inputs with defaults, deliverables,
runs, out of scope, acceptance of the PR, budget. The author receives the brief,
the SHAs filled in at preflight, and nothing else. Sources are named by file and
section, not pasted.

### Part 8: Water baseline and cost pilot

**Goal.** A baseline of the initial useful water workflow on the current
`main`, with the dominant error ranked and the cost measured at the intended
count, so that part 9 knows which fix buys the most. A baseline is not a
qualification and raises no level.

**Scope.**

  - Workflow: the TRMM_LBA 0M EDMF column, three tags (pbl, free, evap), Float64,
    six hours, the W58 configurations `configs/g3b_trmm0m_*_6h.yml`, with an
    untagged twin. Candidate closures compared: `default` and `copies`. The
    explicit-1M rule is compared in part 7 by WP5b-V's rule, not here.
  - Observables and rows: the contract in G3_PLAN 6.1.1 and 6.1.2. The first-hour
    row is scored after PX12 says which comparator is eligible. The six-hour rows
    are reported, not scored, as WA-SCOPE says. The OD2 window is read on the
    untagged run with its output cadence before any scoring.
  - Dominant error: one ranked table of the error terms per mode: closure
    residual, repair activity (PX5's reading), per-tag first-hour L1 against the
    references parts 6 and 7 made eligible, intervention counts from the part 5
    reader, and the parent Newton error (W57's finding). Each row names the fix
    candidate in part 9's queue that addresses it, or says none is known.
  - Cost: build, step and peak memory on the current `main` for the pilot and for
    8 + 8 tags on D4-W, both modes, with the WP9 driver and the diagnostics the
    contract requires. E88 and E90 stay the prior measurement. The walk fix is
    not measured here, since its post-fix measurement is pre-registered under
    the WP9 spread rule in 12c.

**Inputs with defaults.**

  - OD9 to OD11 proposed: the labels stay proposed, the table uses them with that
    mark.
  - Validity of W54 to W62 after #146 and ClimaParams 1.3.0: the reruns answer
    it. Any changed number is reported next to the prior.
  - The missing six-hour, three-tag and 0M precipitation tolerances: not set
    here. Rows without a tolerance are reported.
  - The 1-2-day sphere pilot: not in this PR. Its brief is in 12d. It may be
    submitted once this PR's contract is merged.

**Deliverables.** `design/PART8_BASELINE.md` pre-registered before any job:
configuration, modes, observables, scored and reported rows, thresholds cited
by ID, runs with cost estimates. Job scripts under `runscripts/`. The converter
and scorer wired for the pilot's bundle. A test that the scorer reproduces the
recorded W58 verdict from the archived output. A STATUS row, the crosswalk rows
the part takes, and the skeleton of `analysis/evidence/PART8.md`.

**Runs.** The W58 trio on the current `main` (three jobs). The WP9 cost pairs
at 8 + 8 on D4-W, both modes, untagged twin (six jobs). All inside the standing
G3 approval, each submitted after the owner's approval. PX12 belongs to part 7.

**Out of scope.** Fixes, thresholds, level raises, the sphere pilot, energy.

**Acceptance.** The design is complete before the first job. Every job has a
cost estimate. The scorer test on W58 passes. The ranked table has a source
for every number. The prek and evidence tests pass.

**Budget.** 0.9M for the PR, 0.3M for the follow-up record.

### Part 9: Targeted water fixes (template, one PR per fix)

**Goal.** One demonstrated mechanism defect, or one inseparable coupled
change, fixed with independent regression evidence that shows the improvement
without breaking parity.

**Scope.** The defect comes from part 8's ranked table or from a reference in
parts 6 and 7 that demonstrated it. The PR states the mechanism, the change,
the regression test that fails before and passes after, and parent parity: a
matched tags-on against tags-off comparison of the parent prognostic fields in
the same configuration, precision and rank count, under the comparison rule
the contract prescribes. Two untagged runs do not show it. Where state or
checkpoint behaviour changes, a restart check. And the 1.10 memory of the
precipitation group, since the #146 precedent raised its peak to 20.8 GiB on
this fork.

**Queue, seeded from the inventory, in part 8's order once known.**

  - WP4b EDMF precipitation stages 2 and 3, required for criterion 7's claim.
  - WP4c leak corrections for runs without rain or snow tags, gated by PX7 and
    PX2.
  - WP5b-C cross blocks for copies, WP5b-P precipitation-weighted errors.
  - WP4a-J and UP1 after PX12's result, by UP1's own rule.
  - The refusals of WP1, retained until supported.
  - WP2 shared helpers only where a fix needs them.
  - The walk fix, as this queue's item and nowhere else: upstream in ClimaCore
    or ClimaAtmos by the owner's decision, with the post-fix measurement
    pre-registered under WP9's spread rule and the OD3 copies row re-measured.
    A fork patch only as a second named departure, bit-for-bit tested. Part 10
    scores criterion 10 on that measurement.
  - PP-SUB and the probe PRs only after PX8 and OD13.

**Inputs with defaults.** WP5's `increment` default under EDMF, unconfirmed:
kept. Option C questions Q2 to Q9: open, the fix does not touch option C.

**Deliverables.** The code PR against `main`. A follow-up on `plan-rev2` with
the STATUS row, the crosswalk rows and the G3_TODO reference. After a fix that
changes answers, part 8's pilot jobs are resubmitted and the baseline record is
amended.

**Out of scope.** A second mechanism in the same PR. Upstream model changes.
Tolerance changes.

**Acceptance.** Regression, parity, restart and CI evidence in the PR. The
numerics reviewer confirms the mechanism reading.

**Budget.** 1.2M per fix.

### Part 10: Water qualification

**Goal.** The fixed criteria applied to the corrected configuration and the
held-out cases, and a published statement of supported uses, operating limits
and unresolved failures.

**Scope.** The claim configuration recorded first: tag count, interval,
observable, required rows, as the overall decision in G3_PLAN 6.1.2 asks.
Held-out cases V-W6: RICO 1M 24 h as the named held-out case under OD14, BOMEX,
ARM SGP and the GCM-driven 0M column, default and copies each. PX23 after PX11
and PX24. V-W9 restart round trips on D4-W in both modes and with rain and snow
tags. A red team by the numerics reviewer before the default is confirmed. The
cost row at 8 + 8 against OD3's 2x with the post-fix measurement. Criterion 12's
CI and reviews.

**Inputs with defaults.** OD9 to OD11: without them nothing is called
validated for a named rule, the statement says so. Rain and snow under EDMF in
the claim: yes if WP4b stage 2 merged, otherwise criterion 7 stays reported
accounting. The path from the three-tag pilot to the eight-tag qualified
workflow is not written down: the design proposes it for the owner.

**Deliverables.** `design/PART10_QUALIFICATION.md`, the held-out job scripts,
scorer wiring for the held-out rows, the limitations statement as a draft, the
STATUS row and crosswalk rows.

**Runs.** The held-out columns, inside the standing G3 approval, each after
the owner's approval. Over 12 jobs goes to the owner first as a set.

**Out of scope.** Retuning on held-out cases. Any level raise above what the
rows show. The sphere.

**Acceptance.** Two outcomes, recorded separately. Assessment complete: every
applicable criterion has a row with pass, fail or not assessable, each with a
source. Configuration qualified: every mandatory gate passes for the declared
scope, including independent provenance evidence, the cancellation-safe
correction accounting in force since 2026-10-08, parity, restart coverage and
the applicable cost criteria. A failed assessment publishes its limitations and
unlocks no production expansion for the failed scope. Unresolved origins are
listed, not waved through.

**Budget.** 0.9M plus 0.3M.

### Part 11a: Energy references

**Goal.** The discriminating energy cases and an independent accepted-stage
flux reference, built offline like part 6, so that energy origins can be tested
rather than only closed.

**Scope.** The eight cases of G4_CLAIM_CONTRACTS section 6 as known-answer
tools under `analysis/evidence/`. Each declares its convention c and freezes it
before any deciding evidence is evaluated. 110 495 J/kg is the convention of
the previous runs, a historical baseline, not an approved universal choice,
and the decision record notes the sensitivity of the energy scale and the
regional tags to c. cΔρ and the OD4 discrete scales apply only to the cases for
which they are defined. Stored-energy references and radiation-record
references are kept apart. The radiation record against an independent
accepted-stage flux, with the density conversion. The G4.7 ladder and G4.8
pulse reused as scoped. PX22's design with stored-tag eligibility under OD7 and
OD11. Floors, shared rules and inactive exclusions declared under OD12 and
frozen before any deciding evidence.

**Inputs with defaults.** OD7 deferred: PX15 and the follower stay designs.
OD9 to OD11 proposed: conditional source tests state the convention they use.

**Deliverables.** The tools with tests, `design/PART11A_ENERGY_REFERENCES.md`,
the PX22 pre-registration, the STATUS row, crosswalk rows.

**Runs.** None in the PR. PX22 needs the owner's per-run approval and is
submitted after merge if approved.

**Out of scope.** Baseline measurements, fixes, the record-only pilot's
qualification (EA-USE).

**Acceptance.** Every case has a wrong-origin mutant the tool catches. Tests
pass.

**Budget.** 0.9M.

### Part 11b: Energy baseline

**Goal.** The post-#139 energy baseline: parity, process budget, C4 per layer,
the A5 investigation and the 8 + 8 cost after the walk fix.

**Scope.** Reuse E87 from the archive with the converter's producer gaps
closed (`source_partition_valid`, the six tags missing from diagnostics). The
G4.6 A5 partition-sum failure investigated. C4 per layer with the surface
precipitation offset separated, single-column scope. The seven-point levels 2,
3, 4 and 6 proposed from this evidence for the owner. The Float64 twin as a
precision screen. G4.1, G4.11 and G4.16 inventories reused.

**Inputs with defaults.** Levels: proposed, not set. Legacy interim: labelled
estimate.

**Deliverables.** `design/PART11B_ENERGY_BASELINE.md`, converter fixes with
tests, job scripts, the STATUS row, crosswalk rows.

**Runs.** The post-#139 reruns of E87's trio and the 8 + 8 cost pair. Each
needs the owner's approval, since energy has no standing approval.

**Out of scope.** Fixes, qualification, the G4.13 sphere.

**Acceptance.** Scorer energy rows run on the reruns. Ineligible copies are
never used as truth.

**Budget.** 0.9M plus 0.3M.

### Part 11c: Energy fixes (template, one PR per fix)

As part 9's template, for the energy defects 11b demonstrates: missing mirrors,
cross blocks, subsidence (E66's +18%), G4.9 placements as comparisons only, and
the follower under OD7. The UG1 to UG13 documentation items form one
documentation PR. Unsupported-mode guards stay. No offset change, comparator
promotion or tolerance relaxation. Budget 1.2M per fix.

### Part 11d: Energy qualification

**Goal.** G4.12 held-out evidence for the stored-source energy tags, the fixed
convention and the supported-use statement.

**Scope.** An energy held-out case the owner names under OD14. The matrix
applied only after the owner's accuracy, scope and cost choices, since
EA-ACCURACY and EA-COST lapsed. Record-only and source-provenance outcomes
reported separately. C4 and the other limits preserved. No qualification
inherited from water.

**Deliverables.** `design/PART11D_ENERGY_QUALIFICATION.md`, job scripts, the
limitations statement, the STATUS row.

**Acceptance.** The same two outcomes as part 10. Assessment complete when
every energy row has a source. Configuration qualified only when every
mandatory gate passes for the declared scope, including the energy
cancellation-safe accounting in force since 2026-10-08, independent provenance
evidence, parity, restart coverage and cost. A failed assessment publishes its
limitations and unlocks nothing.

**Runs.** Per-run approval. **Budget.** 0.8M plus 0.3M.

### Part 12a: Precision and refinement

**Goal.** The qualified envelope extended to Float32 and refinement.

**Scope.** V-W7 reused: W60's failed verdict preserved, W62's narrower pass as
is. Rain and snow Float32 closure once WP4b stage 2 exists. Long Float32 on the
sphere, since the kept sphere configuration is Float32. Refinement ladders with
the unresolved convergence floor retained. Grid-rung stability from WA-GATES.
The owner's rounding floor only for fresh pre-registered evidence.

**Deliverables.** `design/PART12A_PRECISION.md`, scripts, the STATUS row.
Code against `main` only if a Float32 defect is demonstrated.

**Runs.** Inside G3's approval for V-W7's kind, each after approval.
**Budget.** 0.8M plus 0.3M.

### Part 12b: MPI and restart at scale

**Goal.** Rank-count parity and restart coverage at scale, separated from
tagged-untagged parity within one rank count.

**Scope.** W59 and its moist addendum reused. V-W9 round trips. MP1 beyond two
nodes only with the owner's multi-node approval. E58's restart drift diagnosed
upstream, no parent change. MPI and restart changes split when independently
reviewable.

**Deliverables.** `design/PART12B_MPI_RESTART.md`, the MPI job scripts, code
against `main` where a defect is shown. **Runs.** Two-rank pairs inside G3's
approval. Multi-node needs its own. **Budget.** 0.9M.

### Part 12c: Production performance

**Goal.** One bounded optimization per PR with unchanged qualified answers.

**Scope.** After part 10, with the walk fix already measured in part 9. The
WP9 sub-items: the plume growth in default mode, the 32-tag tuple map, copies
at 32 tags. P2 and P3 only if the profile shows them. Each with its own
pre-registered measurement under WP9's spread rule. GPU stays gated.

**Deliverables.** Per PR: the change, the measurement, the parity evidence.
**Budget.** 1.0M per item.

### Part 12d: Long-run qualification

**Goal.** The 1-2-day sphere pilot, then the 90-day 60-level sphere.

**Scope.** The pilot first: untagged and 8 + 8 tagged, a one-day copies twin,
a restart after day one, a two-rank parity pair. It measures step time, memory
per rank and the ranks needed, and runs PX20's census inside it. It is
authorized since 2026-09-24 and may run once part 8's contract is merged. The
90-day design after 12a to 12c: cost estimate (about 37 days on 24 ranks and
2.3 TiB if cost scales in proportion), chained segments, PX19 if a flush screen
is needed, G4.13's ten energy days against E75, OD6's ceiling. Option C's Q2 to
Q9 must be answered before its 90-day validation.

**Deliverables.** `design/PART12D_LONG_RUN.md` in two sections, pilot and
90 days. Job scripts. The supported envelope as a draft.

**Runs.** The pilot after the owner's approval of the job. The 90-day run only
after the owner's explicit run approval. **Budget.** 0.8M plus 0.3M.

## 6. Open owner items by the part they gate

| Item                                        | Gates         | Default in the briefs                               |
|:------------------------------------------- |:------------- |:--------------------------------------------------- |
| OD7, the energy follower                    | 11a, 11c      | Deferred. Designs only.                             |
| OD9 to OD11, labels and rule classification | 8, 10, 11a    | Proposed. Nothing is called validated for a rule.   |
| OD15, PX25 acceptance                       | 7, 9, 10      | Decided at PX25's pre-registration in part 7.       |
| W33 revisit and the explicit-1M default     | 7, 9          | Decided beside part 7 by WP5b-V's rule.             |
| Option C questions Q2 to Q9                 | 12d           | Open. The 6 h pilot is unaffected.                  |
| Seven-point levels 2, 3, 4 and 6            | 11b           | Proposed from 11b's evidence.                       |
| Levels 0 to 4 of the roadmap                | all           | Proposed. Status rows report evidence, not a level. |
| Walk fix placement, ClimaCore or ClimaAtmos | 9, 10, 11b    | Upstream. No fork patch without a second decision.  |
| Multi-node, GPU, the 90-day sphere          | 12b, 12c, 12d | Not approved.                                       |
| The three-tag pilot to eight-tag claim path | 10            | The part 10 design proposes it.                     |
| The unregistered `wp9_cost_namewalk` runs   | housekeeping  | Named as unregistered until the owner says.         |
| PX3, PX5 and PX9 routing                    | 8, 9          | Not named by the 2026-10-08 decision. Unchanged.    |

## 7. Records

Each part keeps the conventions of parts 4 to 6: `analysis/evidence/PARTn.md`
for the record, one STATUS row per capability it touches, the crosswalk rows it
takes marked with the PR, and the consolidated PR comment. Decisions go to
DECISIONS.md's dated section and the register CSV. Outputs are synced to the
archive before scratch is cleaned, and the archive README says how.
