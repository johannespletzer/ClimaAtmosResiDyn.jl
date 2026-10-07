# The roadmap

Moved on 2026-09-23 from the top of OPERATIONAL_TODO.md, whose original is
[archive/2026-09-23/OPERATIONAL_TODO.md](archive/2026-09-23/OPERATIONAL_TODO.md).
Only its pointers were changed. The entry point for a session is
[STATUS.md](STATUS.md).

Set on 2026-09-23. It divides what is left of the owner's goal of 2026-09-10
into milestones M0 to M8. The milestones come from
[reference/repo-operability-pathway.md](reference/repo-operability-pathway.md),
a review of 2026-09-21 that is kept as written. Its reasoning is in
[reference/untapped-potential-assessment-extended.md](reference/untapped-potential-assessment-extended.md).
The status lives here and in [STATUS.md](STATUS.md), not in those two files.

**Operational** means, in the pathway's words, that a declared configuration:
runs reproducibly; leaves the parent atmosphere unchanged by the diagnostics,
within the parity contract; meets independently justified scientific
criteria; and has a measured, affordable cost. It does not mean that every
configuration upstream supports has been validated for every diagnostic.

**Two families walk the milestones in turn.** The owner decided on 2026-09-23:

  - the tagged water tracers go first, as G3, and become operational in the
    production configuration, a sphere with EDMF and 1M;
  - the energy source tags follow, as G4, with what G3 learns.

Water has candidate references under EDMF, exact mass bookkeeping, and no
energy-offset convention. Reference eligibility is case-specific. Copies
are not a universal truth. The shared machinery is qualified there first. The
process records go with the energy family in G4.

| Milestone | Outcome                                                                                                                                                                                                                                                                              | Water tags (G3)                                                                                                                      | Energy source tags (G4)                                                                                                               |
|:--------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------- |
| M0        | Every result traceable: manifests, a verifier, a run inventory, archived data                                                                                                                                                                                                        | the tools are built (verifier, mutation tests, manifest, inventory) and serve both families; review open (G3 WP0)                    | uses G3's tools                                                                                                                       |
| M1        | Correctness gaps closed, claims narrowed                                                                                                                                                                                                                                             | refusals, known issues, EDMF support in both modes, restarts, a file-based start (G3 WP1, WP3, V-W8, V-W9)                           | #95: R3 to R6 fixed in `e71430fb`, R1 in `dbe7435c`; the partition-only factor is in `dcf7d086`, and #95 is open at `afd470e7` (G4.1) |
| M2        | The acceptance contract's verdicts per family, with accepted-step intervention metrics and the per-tag ledger (rev. 2)                                                                                                                                                               | closure on D4-W, the copies' residual, leaks named; gross accumulators for both families (G3 WP3, WP6)                               | the process budget, the residual report, warnings apart from acceptance (G4.3 to G4.6)                                                |
| M3        | A suite of small reference cases, each converged; same-parent references where tag numerics are isolated (rev. 2)                                                                                                                                                                    | D4-W and TRMM 0M, the ladder, Float32 (G3 V-W3, V-W4, V-W7)                                                                          | the R2 ladder is done (E76); the ladder at #95's merged head and the rest wait (G4.7, G4.8)                                           |
| M4        | Cost measured and budgeted, before M5: comparator feasibility at the intended tag count (OD8), cost ceilings, the sphere's run-length budget (rev. 2); the 90-day, 60-level sphere's estimate (2026-09-24, below), and a 1-2 day 60-level sphere run that measures it, after step 8a | both families, both modes (G3 WP9)                                                                                                   | from G3                                                                                                                               |
| M5        | The mixing closure and precipitation provenance chosen by experiment, under the contract; closure alone never qualifies (rev. 2)                                                                                                                                                     | exchange against copies, the follower's default, the 0M split, rain and snow tags, held-out columns (G3 WP5, WP4a, WP4b, V-W5, V-W6) | offset, placement variants, carried-over design, held-out columns, the energy default (G4.9 to G4.12)                                 |
| sphere    | Ten days in the production configuration. *Scope added (provenance pathway, 2026-09-26): superseded 2026-09-24 by OD1 and OD6, 90 days at 60 levels.*                                                                                                                                | V-W11                                                                                                                                | G4.13                                                                                                                                 |
| M6        | Devices, precision, input data and restarts at scale                                                                                                                                                                                                                                 | not started; the GPU decision belongs here                                                                                           | not started                                                                                                                           |
| M7        | A production trial and a supported envelope                                                                                                                                                                                                                                          | not started                                                                                                                          | not started                                                                                                                           |
| M8        | Extensions: air age (deferral proposed 2026-10-05), memory and forecasts. Numerical-loss diagnostics retain their gates                                                                                                                                                              | —                                                                                                                                    | memory number (G4.14). The rest later                                                                                                 |

The goals after G4 are sketched, not approved. Each needs the owner. The
plan for G3 is [G3_PLAN.md](G3_PLAN.md), reviewed and finalised, and its
to-do list is [G3_TODO.md](G3_TODO.md). G4's items are in
[G4_TODO.md](G4_TODO.md).

G1 and G2 were met before the roadmap existed. They covered parts of M1, M3
and M5 for the energy tags on D4 and on the sphere (E62 to E75), and their
numbers enter M0's inventory as historical results. The pathway puts M4
before M5, and so does rev. 2 of the work plan (2026-09-24): the default is
chosen only after the cost at the intended tag count is measured, including
the comparator's (OD8). Before rev. 2, G3 reversed the two: it chose the
closure on columns, where runs are cheap, and measured the cost before its
sphere run.

## Capability increments (2026-10-05)

This revision proposes to change the active execution order in place (proposed 2026-10-05, waiting for the owner, DECISIONS.md). The M0–M8, WP,
V-W, PX, G4 and owner-decision IDs remain the scientific work inventory.
The part numbers below are delivery boundaries, not a second programme.
The acceptance contract and decision register below remain authoritative.
The dated earlier tables describe their recorded state, not today's queue.
[PLAN_CROSSWALK.md](PLAN_CROSSWALK.md) maps their individual obligations to
the new delivery boundaries. It is a navigation and loss-check index, not
another source of scientific criteria.

**Scope.** Water is the first end-to-end qualification target. Energy's
definitions and independent reference development may proceed in parallel.
Its implementation and qualification keep their own gates. Residence-time
and air-age development is deferred. This does not remove G4.14's
instantaneous donor-loss timescale, PX19's correction-flush screen, or OD6's
long-run criterion: those diagnose numerical intervention and are not ages.
Their original triggers and validity restrictions still apply. GPU and
other previously unapproved extensions remain unapproved.

**Baseline checked 2026-10-05.** The consolidated planning head is
`claude/plan-rev2` at `58d3535467dc330f1baf1a69936d683c778a3d18`.
PR #146 is open, not merged, at
`33cbfd4fa282618788cea54de7a69696b592ead8`, against `main`
`d3c5e42f54515729f53216ae6b8ba268bea8262f`. Its tested implementation,
its merge status and scientific qualification are separate facts.
Post-#139 evidence requirements remain in force. This planning revision
executes no experiments and changes no threshold or scientific default.

### Measuring progress

Maintain one compact status row per declared capability and configuration:
current evidence level, next part, acceptance evidence, verdict, limitation.
Levels describe evidence actually available. Never infer a repository-wide
level from one successful case. Each level requires the levels below it.

| Level                | Evidence required                                                                                                    |
|:-------------------- |:-------------------------------------------------------------------------------------------------------------------- |
| 0 Defined            | Label meaning, intended scientific use, observable, assumptions and supported configuration are explicit.            |
| 1 Operational        | That configuration runs and has the required parent parity, restart and reproducibility evidence (part 4's records). |
| 2 Accounted          | Relevant transfers, numerical intervention and unexplained discrepancies are measured.                               |
| 3 Attribution tested | Eligible independent references test individual origins for explicitly named active rules.                           |
| 4 Qualified          | Predefined criteria and measured cost pass in the declared operating range, with the applicable held-out evidence.   |

These are delivery labels, not replacements for the contract's separate
pass/fail/not-assessable rows or the pathway's Fid/Val proposals. OD9–OD11
remain proposed. In particular, a configuration accepted under OD5's
historical phrase "provenance bounded, not validated" is not promoted to
level 3 or 4 without independent attribution evidence. Preserve that owner
decision and report its meaning explicitly. Its wording does not establish
a mathematical error bound. Parts 2 and 3 must present any proposed change
to that terminology for owner resolution, not silently rewrite OD5.

Keep parent parity and parent validity, accounting/closure, origin,
comparator eligibility, intervention, convergence, aggregation,
reproducibility and cost visible separately. A pass in one cannot compensate
for a failure or missing prerequisite in another. Preserve the distinction
between implementation verification, testing of the declared labelling
model, and evidence for real atmospheric origins.

### Acceptance specifications and PR boundaries

Before the deciding experiment, each part records its user value, scope,
baseline limitation, observable and window, acceptance evidence and existing
threshold source, dependencies, exclusions, and a reviewable deliverable.
Parts 2 and 3 explain the scientific rationale for each use-specific
tolerance. They propose missing values to the owner rather than choose
values that make existing results pass. Retain small-tag absolute errors,
energy's fixed convention and OD4 scales, and OD2's sensitivity row.

A reference declares which rules it shares, which it tests independently,
its floors, excluded processes and convergence evidence. Analytic and
manufactured cases, and independently implemented transfers of known composition,
verify specified equations. They do not by themselves validate their physics.
New benchmark designs reuse PX11/PX24 and PX14/PX25 where suitable. New
experiments outside existing approvals need an explicit design and owner
decision before execution.

Every implementation PR includes relevant tests, parent-parity evidence,
restart/schema checks where state changes, documentation, and an update to
the existing status and crosswalk. Split independent mechanisms into
separate PRs. An investigation can finish with a negative result that rules
out an option. It must not raise the capability's qualification level.
Freeze held-out cases before tuning, and measure cost before choosing a
default or commissioning the long runs. Existing passed work is reused.
Rerun only where the changed code, physics or claim invalidates its evidence.

### Part 2 water specification (2026-10-06)

The water observables, equations, required evidence and
acceptance matrix are in
[G3_PLAN 6.1.1–6.1.5](G3_PLAN.md#611-water-observables-and-accounting-conventions-part-2). Conditions beyond the approved register wait for the owner (DECISIONS, WA-GATES).
Its [initial-use proposal](G3_PLAN.md#21-part-2-the-first-useful-water-workflow-proposed-2026-10-06)
and twelve-criterion disposition retain the full G3 objective. The general
verdict rows and OD3 decision/threshold table below still own their approved
numbers. The water matrix interprets applicability without changing them.

Part 2 proposes TRMM_LBA 0M's six-hour, three-tracer baseline as the first pilot (WA-SCOPE, waiting).
`pbl`/`free` partition entry-labelled water (initial masks plus later
mask-weighted gains). `evap` is an overlapping surface-source tracer, not a
third partition tag. Inventory and precipitation attribution are separate
claims. W58 records parity/accounting, with origins reported only. PX12's
eligibility/refinement and independent active-rule coverage remain required.
A clean transport reference does not qualify precipitating EDMF. Current
rain/snow tagging refuses EDMF and copies. WP4b stages 2/3 stay open.

[DECISIONS' Part 2 proposals](DECISIONS.md#part-2-proposals-2026-10-06-waiting)
name the unresolved initial qualified-use scope/count/window and scientific
accuracy rationale, additional 0M precipitation rule, and any missing local
cost/memory cap. They do not approve new tolerances or defaults. Six-hour
origin differences are not scored by transplanting the 24-hour row.
Three-tag evidence does not qualify OD8's eight-tag target. OD5's historical
verdict is retained without implying a mathematical error bound. OD9–OD11
remain proposed, OD15 remains a PX25 preregistration decision, and option D
keeps D4-W criteria 3/4/9/10 without origin qualification.

Part 2's documentation deliverable is complete after its independent review
and consistency checks resolve concrete findings. Pending owner choices keep
affected scientific claims blocked. The next executable obligations stay in
G3_TODO: Part 4 data/window/denominator scoring, Part 5 cancellation-safe
accounting, Parts 6/7 references, Part 8 integrated baseline/cost, Part 9
targeted fixes, Part 10 scoped qualification and Part 12 production expansion.
No simulations, executable changes or branch/PR publication belong to this
Part 2 handout.

### Part 3 energy specification (2026-10-06)

The canonical energy meanings, equations, normalizations and
[acceptance matrix](design/G4_CLAIM_CONTRACTS.md#5-energy-acceptance-matrix)
are in [G4_CLAIM_CONTRACTS](design/G4_CLAIM_CONTRACTS.md). OD3 and the
register below retain their approved numerical authority. The contract
separates stored source ancestry, signed process increments and accepted
parent-budget reconstruction; none is a causal counterfactual.

The proposed first useful energy question is a signed radiation
heating/cooling profile and day-integrated amount on a non-EDMF DYCOMS RF02
0M column, with one radiation record and zero source tags. Its fixed
reference, configuration, excluded claims, startup/sensitivity windows and
independent accepted-stage flux route are
[specified there](design/G4_CLAIM_CONTRACTS.md#3-one-first-useful-energy-workflow-a-signed-radiation-record).
EA-USE, EA-ACCURACY and EA-COST (record pilot), plus EA-STATE (additional stored-state criterion), remain
[owner proposals](DECISIONS.md#part-3-proposals-2026-10-06-waiting).
This pilot could qualify its process-record question only; stored energy
provenance and the full eight-tag G4 objective remain separate obligations.

The offset identity uses `c Δρ`; a water record is a mass proxy only after a
process-specific discrete proof. OD4's exact quantity is cellwise absolute
**accepted-step** source-ledger change summed over partition tags and steps;
within-step process/stage cancellation remains. Offline interim records
and runtime fallback are different estimates. Reconstruction of cumulative
specific outputs requires density at both endpoints. Source-state residual
and its window change are reported separately; the approved closure-growth
reading is preserved, and a proposed scored state requirement needs EA-STATE.
A small change cannot establish a small retained residual. These demonstrated scorer/accounting gaps go to
Parts 4/5, not executable changes in this part.

Preserve the decided seven-point definitions and C4's documented size;
points 2/3/4/6 levels need post-#139 evidence. OD7 and proposed OD9–11 remain
gated; OD12–14 reference/probe/held-out restrictions remain accepted.
Mirrors, sedimentation cross blocks and unsupported-mode guards are reused
at the actual baseline. D4 copies are still ineligible; water's passing
rules and qualifications are not inherited. Full source-tag conditional
tests state fixed `c` and source/loss conventions; the offset sweep is a
convention comparison, not a reference or error bound.

Part 3 completes after independent review and source/decision/threshold/
link/crosswalk validation resolve concrete findings. Missing evidence and
owner decisions continue to block affected scientific claims. G4_TODO
routes independent energy references to 11a, process/integrated baseline
and measured cost to 11b, evidenced fixes to 11c, scoped qualification to
11d and expanded/production qualification to 12. No simulations,
executable changes, scientific default changes or publishing belong here.

## Rev. 2 of the work plan (2026-09-24)

The owner revised the work plan on 2026-09-24 ("Simulation-results synthesis
and in-place work-plan revision, rev. 2"). It adds no work package and no
milestone. It changes the order and the acceptance logic, so that closure
cannot stand in for provenance, an ineligible audit cannot select a default,
and criteria are fixed before the runs they judge. This file hosts its
acceptance contract, its decision register and its execution order. The
report of steps 0 and 1 is
[review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md](review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md).

*Scope added (provenance pathway, 2026-09-26, pending OD9 to OD11; OD12 to
OD14 accepted 2026-10-02; revised after the owner's review the same day):* a
proposed fourth aim. Provenance
evidence is reported per tag as a fidelity level, an observed spread and an
exposure screen. The observed spread is the realized difference between
admissible rules on the same parent. The exposure screen flags the rules not
yet validated whose exposure could matter. Neither is an error interval or a
certificate. A rule counts as validated only where it was active and a
reference that does not share it tested it. A lower rung is never evidence for
a higher one, and agreement between references that share a rule is never
evidence for that rule. The pathway, its theories and its gated experiments
are in [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md).

**What changes per milestone.**

  - **M2.** *Scope added (rev. 2):* the single verdict "independent
    accounting, gross diagnostics" is replaced by the contract's verdicts
    below. They include accepted-step intervention metrics and the per-tag
    ledger (G3 WP6 step 3).
    *Scope added (provenance pathway, 2026-09-26, pending OD10):*
    the Invariants and Ledger-completeness rows proposed below the contract.
  - **M3.** *Scope added (rev. 2):* a reference that isolates tag numerics
    shares the parent. A run with another Newton count or time step is a
    different atmosphere. It is a configuration comparison, not a tag-error
    reference (W33 against W35).
    *Scope added (provenance pathway, 2026-09-26, pending OD10):*
    exact per-tag counterparts on the same state (PROVENANCE_PATHWAY PX8),
    and a sampled amplification `K̂` only if a screen needs it (PX9,
    deferred).
  - **M4.** *Scope added (rev. 2):* M4 stays before M5. It adds the
    comparator's feasibility at the intended tag count (OD8), cost ceilings
    fixed before the held-out and default-selection runs (OD3), and the
    sphere's run-length budget (OD6).
  - **M5.** *Scope added (rev. 2):* a default is selected, for each
    configuration in the envelope (OD1), only if it passes parent validity,
    closure and intervention, and provenance. Provenance passes against an
    eligible comparator with process-weighted evidence. Where no comparator is
    eligible, the Insight 10 tests (refinement, per-tag intervention,
    aggregation) must pass under OD5, and the result is labelled "provenance
    bounded, not validated". Closure alone never qualifies.
    *Scope added (provenance pathway, 2026-09-26, pending OD9):*
    OD5's "bounded" keeps its decided meaning. OD9 proposes that the
    pathway's labels are reported beside it, and that the label "validated
    for named rules" means Val-3: each named rule was active in the case and
    passed a reference that does not share it. The label does not redefine
    rev. 2's verdicts. Copies that are eligible validate only the rules they
    do not share.

### The acceptance contract

Every result reports each row that applies as **pass**, **fail** or **not
assessable**. *Not assessable* names the missing prerequisite, for example "no
eligible comparator: copies repair 0.60%/day against a 0.20%/day bound"
(W21). Its treatment at M5 follows OD5. G3_PLAN 6.1, M2 and G4.3 to G4.6 refer to this table and do not restate it. [G3_PLAN's water matrix](G3_PLAN.md#612-water-acceptance-matrix-authoritative-part-2-specification) maps these rows to water observables and applicability without restating their thresholds (Part 2, proposed). [G4_CLAIM_CONTRACTS](design/G4_CLAIM_CONTRACTS.md#5-energy-acceptance-matrix) maps them to the energy observables (Part 3, proposed). A row that an approved rule excludes is reported as not applicable (OD3, 2026-09-25), never as a pass. Missing or non-finite data fails (G3_PLAN 6.1).

| Verdict                | Required evidence                                                                                                                                                                                         | Threshold                                                                                                   |
|:---------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------- |
| Parent validity        | Tagged/untagged parity, and the physical and numerical validity of the shared parent trajectory                                                                                                           | Parity: bitwise. Validity checks: OD3                                                                       |
| Closure                | Net and gross partition residual                                                                                                                                                                          | Water: 0.2% day-scale unless explicitly revised (G3_PLAN 6.1). Energy: OD3, in offset-invariant units (OD4) |
| Provenance             | Region and source L1 and L∞ against an eligible comparator; absolute error for small source tags; process- or precipitation-weighted comparisons where they apply                                         | OD3                                                                                                         |
| Comparator eligibility | In the same run: the comparator's closure, its repair throughput, Newton and time-step stability (repair must not grow under refinement), complete mirrors and the Jacobian terms that matter             | Water copies' repair: 0.20%/day (G3_PLAN 6.1). Others: OD3                                                  |
| Intervention           | Accepted-step gross repair and follower transfer; per-tag cumulative correction relative to the tag's inventory; event counts; attempted against retained change; clamps and zero-normalization fallbacks | OD3, aggregate and per tag                                                                                  |
| Convergence            | Fixed-parent trial-step error where tag numerics are isolated; the refinement test of follower and repair throughput; full-run differences reported apart                                                 | OD3                                                                                                         |
| Aggregation            | A run at the intended tag count summed into nested groups, against a run of those groups                                                                                                                  | Roundoff, or the solver's tolerance; any departure explained (OD3)                                          |
| Reproducibility        | An immutable SHA or tag, the exact configuration, the manifest, the verifier's output and machine-readable results                                                                                        | Complete, or fail                                                                                           |
| Cost                   | Build time, peak memory and per-step scaling at the intended tag count, the comparator included; the sphere's run length within budget                                                                    | OD3; OD6                                                                                                    |

Closure never substitutes for provenance. Where no comparator is eligible, the convergence, intervention and aggregation rows can bound the default's provenance but not validate it. *Part 2 reading, proposed (DECISIONS, WA-GATES (d)):* these rows are OD5's conditional evidence for its "provenance bounded, not validated" verdict. They do not by themselves establish a mathematical error bound.

A copies run is a provenance comparator only if, in that run, it passes its
own closure criterion, the repair-throughput criterion and Newton and time-step
stability, and has the source mirrors and Jacobian terms it needs. Otherwise
the provenance verdict is *not assessable*. A default is never chosen because
it is closest to a failed comparator's repaired output.

**Proposed rows.** *Scope added (provenance pathway, 2026-09-26, pending OD9 to
OD11; OD12 accepted 2026-10-02; revised after the owner's review):* they are
reported, not scored, until
the owner approves them. Section 2 of
[PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md) maps them onto the evidence
levels.

| Verdict             | Required evidence                                                                                                                                                                                                                                                  | Threshold                                                                               |
|:------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:--------------------------------------------------------------------------------------- |
| Invariants          | Uniform composition; permutation and duplicate tags; proportionality of tags whose sources differ only by a fixed mask; overlay at most parent; source integral at most production; superposition with distinct footprints                                         | Rounding, except at logged bound and fix events (OD10)                                  |
| Ledger completeness | Per-tag, per-process accounting from the same state: each tag's change equals the sum of its named parts                                                                                                                                                           | Rounding (OD10)                                                                         |
| Exposure screen     | Per tag, the gross same-state defect of each listed rule not yet validated, summed over the rules and reported per rule, times a sampled amplification `K̂` (1 until PX9 runs), plus `F`; the exact per-tag counterpart for bracketed transport such as subsidence | Reported, never scored; a screen, not a bound; OD5's "bounded" is unchanged (OD9, OD10) |
| Observed spread     | The realized same-parent difference between the admissible alternatives of each material rule, listed before the run                                                                                                                                               | Reported; "convention-sensitive" where it exceeds the approved row (OD11)               |
| Reference validity  | Each reference's floors (surface, initialization, parent error, contamination), the excluded processes measured inactive, and the rules active in the case that it does not share                                                                                  | Floors at most a quarter of the budget (OD12)                                           |

Notes on the existing rows, proposed and marked the same way:

  - **Provenance:** each result would also state per tag its fidelity level,
    observed spread and exposure screen, with the pathway's verdict record
    (the active, shared and untested rules). The approved thresholds apply
    unchanged. An eligible comparator validates only the active rules it does
    not share (OD12).
  - **Comparator eligibility:** plus the list of rules it does not share.
  - **Convergence:** plus the follower's split into lag and structure (PX7,
    whose result will be W46).
  - **Aggregation:** stays reported, as approved. A band region (PP-BAND) is
    deferred until a measured result needs it. A departure where the
    exchange's θ binds or the repair acts is expected by construction.

Four rules under the table, proposed and marked the same way:

  - A net first-order counterfactual sum, such as WP4c's part 3, is an
    estimate of an observed spread. It is never a bound or a certificate.
  - A rule's own ledgered gross gives its screen term only where the
    faithful counterpart is a composition times the same gross mass. A
    bracket that sees a small net while labels move (subsidence) needs its
    exact counterpart.
  - A realized difference above its screen shows that the rule list or `K̂`
    is incomplete, and voids the screen for that configuration.
  - Conventions (`c`, mask gain, donor loss, bracket granularity) are
    reported as spreads, apart from the approved rows. They are never bounded
    and never pass or fail.

### The decision register

Each decision is recorded here before the first run it judges. Results are
scored against the value recorded at that time, as W33 is. **This register is
the single source of each decision's current state.** STATUS, DECISIONS, the
TODO files and G3_PLAN point here and do not restate it. **OD7 is the only
open numbered decision.** The owner's other open choices have no OD number;
they are listed below the table. No agent fills one in.

*Scope added (provenance pathway, 2026-09-26):* OD9 to OD14 at the end of the
table are proposals from [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md). They
are not yet open. Each becomes open when the owner accepts it onto the register.
Until then, OD7 is still the only open numbered decision.

*Update 2026-10-02 (walk-through, option B):* the owner accepted OD12, OD13
and OD14 now, because they gate runs. OD9 to OD11 stay proposed until a gated
result exists. OD15 is answered at PX25's pre-registration. Gated runs use
post-#139 `main` (`24c1aaa0` or later). Numbers measured on the old physics
count as prior evidence only.

*Scope added (provenance pathway, 2026-09-27, from the owner's review of
#121):* OD15 at the end of the table is proposed the same way. It is not yet
open.

| ID   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Needed before                                        | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
|:---- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| OD1  | The production envelope: vertical levels, SGS reconstruction, Δt, Newton count, microphysics (0M or 1M, explicit or implicit sedimentation), the intended water and energy tag counts                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | W25 isolation (step 2); OD8                          | If production uses ≥ 60 levels or first-order SGS, W25's failures are the main case                                                                                                                                                                                                                                                                                                                                                  | ~~OWNER DECISION REQUIRED (OD1)~~ **Decided** 2026-09-24: `g2_v2_sphere_n2` at 60 levels; its stretching chosen the same day                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| OD2  | The window boundaries per case: startup or source pulse, established flow, long run                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | The first run scored by window                       | Include the WP4b held-out case                                                                                                                                                                                                                                                                                                                                                                                                       | ~~OWNER DECISION REQUIRED (OD2)~~ **Decided** 2026-09-24: physical windows; the window rule approved the same day                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| OD3  | Thresholds: parent-validity checks; provenance (L1, L∞, absolute error for small tags); intervention (aggregate and per tag); comparator eligibility; refinement; aggregation tolerance; cost (build time, peak memory, per-step time)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | The first run each threshold judges                  | Existing numbers carry over unchanged: water closure 0.2% day-scale, copies' repair 0.20%/day, and the existing time-step, Newton and first-hour budgets (G3_PLAN 6.1)                                                                                                                                                                                                                                                               | ~~OWNER DECISION REQUIRED (OD3)~~ **Decided** 2026-09-24: approved as drafted. Its WP4c reading confirmed 2026-09-25                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| OD4  | The offset-invariant scale for every energy percentage                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Energy thresholds in OD3; G4.3 to G4.6               | Candidate: the cumulative gross source throughput into the tags over the same window. First audit the denominators of the existing E-records                                                                                                                                                                                                                                                                                         | ~~OWNER DECISION REQUIRED (OD4)~~ **Decided:** the scale is the gross source throughput (2026-09-24); the quantity is an exact per-tag, per-step accumulator (2026-09-25), being built. **Interim**, until it lands and for runs that predate it: the process records' figure. *Corrected after E84 (2026-09-25):* the interim is an estimate. On D4 it came out 6% above the exact accumulator, so it is not a lower bound, and a percentage on it is not an upper bound. The direction of its error is not established. A per-process comparison against the accumulator is open on #115. Earlier E-records are restated with it, labelled estimates, and rerun only where the contract needs an exact value |
| OD5  | How *not assessable* is treated at M5                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | M5                                                   | Proposed: it blocks M5 for that configuration unless the Insight 10 tests pass their thresholds; the configuration is then labelled "provenance bounded, not validated". *Scope added (provenance pathway, 2026-09-26): kept as decided; the pathway's labels would be reported beside it (OD9), not in its place.*                                                                                                                  | ~~OWNER DECISION REQUIRED (OD5)~~ **Decided** 2026-09-24                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| OD6  | The sphere: an absolute ceiling relative to the smallest analysed tag; a growth-rate or loss-timescale bound; the run length                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Water sphere (step 9); energy sphere (step 11)       | Run length budgeted under M4. G3_PLAN 6.1's "plateau after day one" is replaced by this                                                                                                                                                                                                                                                                                                                                              | ~~OWNER DECISION REQUIRED (OD6)~~ **Decided** 2026-09-24: 90 days to saturation; its ceiling approved; a 1 to 2 day run measures the cost first                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| OD7  | G4.15: bounded local movement (the same-sign rule), or the fourfold increase in gross residual it measured (E79)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | The G4.7 and G4.8 runs; the energy default           | Water's same-sign choice is not inherited. The owner decided on 2026-09-24 to choose after the long runs (DECISIONS.md, `design/INCREMENT_RULE_LONG_RUNS.md`). *Scope added (provenance pathway, 2026-09-26): PX3, deferred until the owner takes up OD7, would measure the water side. The E79 run pair gives the energy side's observed spread. No bound exists, because the moved part can also change with the placement (PT6).* | ~~OWNER DECISION REQUIRED (OD7)~~ **OPEN**: deferred by the owner on 2026-09-24, until the long runs can be scored at site 23 (known issue 7); on 2026-09-28, kept deferred until C is fixed and site 23's long runs are scored                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| OD8  | Audit feasibility: copies as the reference at the intended tag count, or copies at the largest buildable count plus the aggregation bridge                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | WP5b-C at those counts; G4.1 and G4.11               | Measured on TRMM's column: 699 s at 8 copies, 2417 s at 16, no build within 4 h at 32 (W30, W34); an 8 h build of 32 is running (job `13911480`)                                                                                                                                                                                                                                                                                     | ~~OWNER DECISION REQUIRED (OD8)~~ **Decided** 2026-09-24: 8 water and 8 energy tags, copies at 8                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| OD9  | The evidence labels: the fidelity levels, "observed spread", "exposure screen", "validated for named rules" (each named rule active in the case and tested by a reference that does not share it) and "held out", reported beside rev. 2's verdicts with the verdict record; they change no OD3 threshold and do not amend OD5; the aggregation row stays reported                                                                                                                                                                                                                                                                                                                                                                                                                 | Any label is reported                                | PROVENANCE_PATHWAY.md, sections 2 and 9; revised after the owner's review of 2026-09-26                                                                                                                                                                                                                                                                                                                                              | **PROPOSED** 2026-09-26 (provenance pathway), not yet accepted; the owner kept it proposed on 2026-10-02, until a gated result exists; OWNER DECISION REQUIRED (OD9) once accepted                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| OD10 | The screen arithmetic: gross, not net; the exact form for bracketed transport; `K̂` from spike arms if PX9 runs, else 1, said each time; a screen is never a bound; the exploratory numbers under "Provenance pathway: exploratory numbers and proposals", after the OD3 section, only decide what to propose next                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Any Val-2 label                                      | PROVENANCE_PATHWAY.md, section 3                                                                                                                                                                                                                                                                                                                                                                                                     | **PROPOSED** 2026-09-26 (provenance pathway), not yet accepted; the owner kept it proposed on 2026-10-02, until a gated result exists; OWNER DECISION REQUIRED (OD10) once accepted                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| OD11 | The rule classification in the claim contracts (G3 criterion 12, G4.3), and the admissible alternatives of each rule, including whether ψ is admissible for the leak; for energy, the fixed `c` (110,495 J/kg unless the owner names another) and the source convention for the conditional budget tests                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Any Val-1, Val-2 or convention-sensitive label; PX22 | PROVENANCE_PATHWAY.md, sections 1 and 4                                                                                                                                                                                                                                                                                                                                                                                              | **PROPOSED** 2026-09-26 (provenance pathway), not yet accepted; the owner kept it proposed on 2026-10-02, until a gated result exists; OWNER DECISION REQUIRED (OD11) once accepted                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| OD12 | Reference validity: a reference validates only rules active in the case that it does not share; the excluded processes measured inactive; floors (surface, initialization, parent error, contamination) at most a quarter of the budget; copies validate sub-grid rules only; the air twin validates transport rules only without sinks, subsidence or sedimentation; and a proposed reading of the Newton row: separate runs whose parents are bit for bit the same untagged twin count as same-parent, since the parent's error cancels exactly. Arms that solve their own transport (the copies, tracer mode, a passive tracer) stay gated unless the parent's error is at most 1e-3                                                                                            | PX11's score                                         | PROVENANCE_PATHWAY.md, sections 2, 5 and 9                                                                                                                                                                                                                                                                                                                                                                                           | **Accepted** 2026-10-02 (walk-through, option B), because it gates runs; gated runs use post-#139 `main`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| OD13 | The diagnostic-only probe PRs: PP-SUB (per-tag subsidence) only, and only after PX8 finds subsidence material; PP-TRACER, PP-BAND, PP-SFC, PP-FACE, PP-JAC and PP-SRCOFF deferred until a measured result needs them; probe accounting instead of new state ledgers                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | PX16 (step 7b)                                       | PROVENANCE_PATHWAY.md, section 8                                                                                                                                                                                                                                                                                                                                                                                                     | **Accepted** 2026-10-02 (walk-through, option B), because it gates runs; gated runs use post-#139 `main`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| OD14 | Held-out hygiene: one held-out case, its window and its metrics, named before any rule is tuned on PX11's result, with a reference valid there; the owner stated on 2026-09-26 that criterion 8's GCM-driven column, which starts from site 23, does not count as held out for a rule developed using site 23, so Val-4 stays not assessable until an independent case and its reference are fixed; Soares, TRMM 0M and sites 23 and 26 are development cases; a held-out case never develops a rule; by analogy with the owner's statement, the pathway asks whether RICO 1M, the fallback WP4b held-out case, still counts as held out for a mode PX25 recommends (added 2026-09-27)                                                                                             | PX23; step 8b                                        | PROVENANCE_PATHWAY.md, section 9                                                                                                                                                                                                                                                                                                                                                                                                     | **Accepted** 2026-10-02 (walk-through, option B), because it gates runs; gated runs use post-#139 `main`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| OD15 | WP4b's acceptance for precipitation provenance, from the owner's review of #121 (item 5, open question 2): PX25's cases and length, and whether item 5's longer run is assessable; how day-scale rows and R9's proposed hourly reading are read on a shorter case; whether a van Leer arm is held to G3_PLAN 6.1's rain and snow row (1e-8 relative) or to a tolerance the owner names; which row, if any, holds `q_ntag_res` over its compartment; whether accumulated `Σ pr_tag` is scored; whether the audit's ratio to the gross transfer gets a tolerance; whether PX25's trend rule is adopted, and how it reads sub-steps; whether the pool rule's ordering error is measured in runs (added after #121's `3681fc2`). OD3's approved rows and OD2's windows stay as decided | PX25's first run; step 8b                            | PROVENANCE_PATHWAY.md, PX25 and section 9                                                                                                                                                                                                                                                                                                                                                                                            | **PROPOSED** 2026-09-27 (provenance pathway, from the owner's review of #121), not yet accepted; the owner will answer it at PX25's pre-registration (2026-10-02); OWNER DECISION REQUIRED (OD15) once accepted                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

**The owner's other open choices** (no OD number), each with its entry in
[DECISIONS.md](DECISIONS.md), "Waiting for the owner":

  - ~~known issue 7's option among B, C and D~~ **decided 2026-09-25: option
    C** (below); its validation is pre-registered
    (`design/NEGATIVE_PARENT_WATER.md`, section 8);
  - ~~**R2, the Newton row, on D4-W**~~ **decided 2026-09-25: the row is
    revised** (below). Three and four iterations level off near 2e-3 (W41);
  - ~~WP4a's two points~~ **decided 2026-09-28:** build the pair behind a
    switch, which WP4a-J measures; the copies' part follows WP4a-J (below);
  - ~~WP6's three points~~ **confirmed as built on `main`, 2026-09-28**
    (below);
  - the explicit-1M water default, decided at M5 under the contract (W33
    stays a failure);
  - ~~W21's surface rule in the first hour~~ **decided 2026-09-28:** model
    the surface flux at the plume's start (below);
  - ~~**option C's revision after W47**~~ **built, validated and merged
    2026-10-01** (#137, `b4ebfca5`). The owner chose on 2026-09-28 to probe
    more first (`design/NEGATIVE_PARENT_WATER.md`, section 9.7). W49's V2
    counts as C's validation. V5's `led_fix` fails at site 23 and stays an
    open failure, which a follow-up probe traces (section 11.10, item 10);
  - ~~**OD9 to OD15, G4.3 to G4.6's seven points and WP4b stage 1's five
    points**~~ **walked through 2026-10-02, the recommended option on all
    five items** (DECISIONS.md): OD12 to OD14 accepted, OD9 to OD11
    proposed, OD15 at PX25's pre-registration; one WP4b fix PR; W50's
    copies rerun, then PX12; the G4 definitions, with the levels set at G4's
    start; the KI4 probe folded into PX12.

### The owner's answers, 2026-09-24

The owner answered the register on 2026-09-24, after the report of steps 0 and
1, and added five points. Each earlier value they change is kept where it
stands, marked as superseded.

  - *Superseded later the same day: see the register.* **OD1, set: the sphere at 60 levels.** Production is `g2_v2_sphere_n2` at
    60 levels instead of 10. Everything else stays as that configuration has
    it: `h_elem` 6, `z_max` 30 km, `dt` 20 s, ARS222, two Newton iterations,
    1M stepped implicitly, the default SGS reconstruction. So W25's 60-level
    misses are the main case. W25's 60 levels were a uniform 25 m grid over
    1.5 km, so they are the nearest measured rung, not the same grid. The tag
    count comes from OD8. The owner did not set the stretching: the OD3 draft
    proposes one.
  - *Superseded later the same day: see the register.* **OD2, set in form: windows are physical.** Startup ends when the parent's
    domain-mean tendency, or the source pulse, falls below a set level. The
    levels are in the OD3 draft.
  - *Superseded later the same day: see the register.* **OD3: drafted at the owner's request; pending the owner's approval.** The
    owner chose "I draft, you approve". One threshold table, below, every
    number a proposal. No run is scored before the owner approves it, so step
    2 stays blocked.
  - *Completed on 2026-09-25: see the register.* **OD4, set: gross source throughput.** An energy percentage is restated
    against the cumulative gross energy the sources put into the tags over the
    same window. The denominators of the existing E-records are audited:
    first pass, [review/od4_denominator_audit.md](review/od4_denominator_audit.md).
  - **OD5, set: bounded passes.** *Not assessable* blocks M5 for that
    configuration unless the Insight 10 tests pass their OD3 thresholds. Then
    the configuration qualifies as "provenance bounded, not validated".
  - *Superseded later the same day: see the register.* **OD6, set in form: run to saturation, 90 days.** The sphere is judged by
    the level it reaches, observed over 90 days, not by a projection. A
    ceiling relative to the smallest analysed tag is still needed; its value
    is in the OD3 draft. The 90-day, 60-level sphere's cost enters M4 as an
    estimate (below).
  - **OD7, open, deferred.** Analysis done: by the registered rule
    (`design/INCREMENT_RULE_LONG_RUNS.md`) same sign is kept. Both criteria
    hold for energy at both sites and for water at site 26. Water at site 23
    breaks the budget under both rules. The owner deferred the decision, for
    example until the site 23 defect is fixed and site 23 can be scored.
    G4.15b waits. The metrics are the parent session's FINDINGS entries.
  - **OD8, set: 8 tags, copies at 8.** The tags qualify for 8 water and 8
    energy tags. Copies at 8 are the direct audit, where they pass eligibility.
    No aggregation bridge is needed for qualification. 32 tags stay a WP9 cost
    item and are not qualified.
  - **W33: opt-in until M5.** W33 stays a failure, and W35 is recorded beside
    it. The explicit-1M water default is decided at M5 under the contract.
  - *Superseded later the same day: see the register.* **Known issue 7, the site 23 crash: a defect, fixed before the sphere.**
    At site 23 the parent's own water goes negative from day 10, the water
    tags diverge, and the tagged runs end while the untagged twin completes 90
    days. A diagnostic ends a run that upstream completes: a parity-class
    defect. Step 8a; the options are in
    [design/NEGATIVE_PARENT_WATER.md](design/NEGATIVE_PARENT_WATER.md), and the
    choice is the owner's.
  - **Per-tag ledgers: off by default, as built.** They are on in every
    validation and qualification run. The fraction uses the tag's current
    inventory, and the absolute amount, `<L>_retained`, is reported beside it
    in the same audit row.
  - **2M and P3 stepped explicitly: refused until measured.** The energy guard
    now refuses `enthalpy_increment` with 1M, 2M or P3 stepped explicitly
    (`claude/energy-explicit-1m-guard`, `e55ae293`), under the proposed key
    `energy_source_tag_increment_allow_explicit_microphysics`. The water tags
    already refuse 2M and P3 at configuration, whatever the transport
    (`check_water_tagging_supported`), so water is unchanged.
  - **PRs: draft PRs when green.** The parent session opens them after the
    validation jobs pass.

### The OD3 thresholds (approved 2026-09-24)

**Approved by the owner on 2026-09-24, as drafted.** Every row is a scoring
threshold from that date, with its numbers exactly as drafted. Step 2 is
unblocked. The draft's heading and first sentences, kept as written: "The OD3
threshold draft (pending the owner's approval). ~~Every number here is a
proposal. Step 2 and every scored run wait for the owner's approval of this
table.~~" Where a threshold was set before (G3_PLAN 6.1, 2026-09-23), it
carries over and is marked so. The measured values are the nearest the record
holds; none was measured for the production sphere.

| row                             | threshold (approved 2026-09-24, or set earlier where marked)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | reason                                                                                                                                          | nearest measured                                                                                                                    |
|:------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------------------- |
| Parent validity: parity         | bit for bit (set, the parity rule)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | the fork's rule                                                                                                                                 | every tagged run so far, up to the site 23 crashes                                                                                  |
| Parent validity: temperature    | no point at the 150 K floor, and the top level's mean moves less than 5 K in the first day (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | E69's one-Newton collapse is the failure this catches                                                                                           | E69: 156 K and 18% at the floor at 6 h with one iteration; E74: 218 to 220 K over ten days with two                                 |
| Parent validity: negative water | the parent's negative water, `Σ ρ min(q_tot, 0) dV`, stays below 1e-4 of `∫ρq_tot`; above it the run's water results are not scored (approved 2026-09-24). *Read online from 2026-09-25 (the owner):* the closure tables carry a persistent flag, B, `negative_water_void`, a latch per family set at the checks when the raw `ρq_tot`'s `N / ∫ρq_tot` passes `negative_water_void_above` (default 1e-4, water only), with the ratio in its own column and the latch carried through checkpoints; and D, a per-cell cumulative negative-water ledger, updated every accepted step and carried through restarts, which makes "never negative" exact. Offline scoring from the output stays the reference | a negative parent voids the partition's meaning (known issue 7)                                                                                 | site 23: `q_tot` below zero from day 10, to −3.1e-3 kg/kg (day 30); the negative part at worst 11% of the column's water (W36)      |
| Parent validity: Newton         | the parent's one-step error at the production Newton count, W35's `E`, at most 1e-3 (approved 2026-09-24). *Revised 2026-09-25, after W38 and W41:* `E` is always reported, and the row gates only verdicts that compare runs with different parents (full-run comparisons, provenance against copies from a separate run). Same-parent verdicts go ahead                                                                                                                                                                                                                                                                                                                                               | a tenth of a percent of a step's increment keeps the parent's solve out of the tags' error; in a same-parent verdict the parent's error cancels | W35, TRMM 1M, 120 s: 4.9e-3 with one iteration, 6.3e-4 with two. W41, D4-W at 60 levels: 1.2e-2, 4.1e-3, 2.3e-3, 1.9e-3 with 1 to 4 |
| Closure, water                  | gross at 0.2% of `∫ρq_tot` at 24 h, no more in the second 12 h (set, G3_PLAN 6.1)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | a tenth of the per-tag L1 budget                                                                                                                | D4-W under the follower 1.35e-4 (W28), 7.3e-6 with the cross blocks (W31)                                                           |
| Closure, energy                 | gross at most 0.2% of the window's gross source throughput (OD4 units) (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | water's budget in the new scale                                                                                                                 | not yet in OD4 units; E79: 2.3e-6 of the partitioned energy on D4; E74: 2.0e-4 of the scale at ten days                             |
| Provenance, per tag at 24 h     | L1 ≤ 2%, L∞ ≤ 5% (set)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | G1's criterion 4b                                                                                                                               | D4-W: 0.25/0.41/0.42% (W28), against copies that are not eligible (W21)                                                             |
| Provenance, first hour          | L1 ≤ 1% region, ≤ 10% source, L∞ ≤ 25% (set)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | G1's split                                                                                                                                      | W21's pulse: `sfc` 14.4% (fails)                                                                                                    |
| Provenance, small tags          | `∫ρ|Δq|dz ≤ 2e-4 ∫ρq_tot` for a tag under 1% (set); energy the same in OD4 units (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | 6.1's small-tag rule                                                                                                                            | —                                                                                                                                   |
| Provenance, process-weighted    | per tag, `Σ|Pₖ||φ − φ_ref| / Σ|Pₖ|` ≤ 0.05 against an eligible comparator (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | lies above what the reconstruction reached and well below the grid rule                                                                         | W32: reconstruction 0.014 to 0.038, grid rule 0.15 to 0.19 (`pbl`)                                                                  |
| Comparator: its own residual    | at most 0.02% of `∫ρq_tot` (set)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | a tenth of the closure budget                                                                                                                   | D4-W 1.0e-5 (W21)                                                                                                                   |
| Comparator: its repair          | at most 0.20% of `∫ρq_tot` a day (set); energy the same in OD4 units (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | 6.1                                                                                                                                             | D4-W 0.60% (fails), TRMM below 1e-5, W32 9.5e-10                                                                                    |
| Comparator: refinement          | at each halving of `dt` or doubling of Newton count, the repair per day is at most 1.1 times the coarser rung's (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | "must not grow"; 10% allows for the atmosphere's own change between rungs                                                                       | W25: dt 0.60, 1.6, 1.8% (grows, fails); Newton 0.60, 0.30, 0.28% (passes)                                                           |
| Intervention, aggregate         | the partition repair's retained gross at most 0.5% of `∫ρq_tot` a day (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | a quarter of the per-tag L1 budget                                                                                                              | D4-W 0.29% a day (W24, net over time, a lower bound)                                                                                |
| Intervention, per tag           | each tag's `led_fix` `_inventory_fraction` at most 2% over the window; `led_inc` reported, judged only through the refinement test (approved 2026-09-24); also WP4c gate part 2, `led_inc` per tag between two runs (2026-09-25). *Revised 2026-09-25 (the owner, from #109's review):* it applies to every tag, with two denominators: a pure region tag `retained / ∫tag`, with a positive inventory as its precondition; a source-labelled or signed tag `retained / ∫|tag|`, the absolute burden. Below the small-tag bound (2e-4 of the parent, OD4 units for energy) the row is "not applicable", reported explicitly. Both ratios and a parent-scale ratio are reported                          | a correction as large as the per-tag L1 budget could alone use it up; `led_inc` holds the parent's vertical advection                           | none yet (WP6 step 3 is new); aggregate moved 2.4% a day on D4-W (W28)                                                              |
| Refinement                      | the repair's and `inc_left`'s throughput per unit time at the finer rung at most 0.75 times the coarser rung's; above 0.9 flags a structural cause (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | lag shrinks with the step or the iterations; a plateau is not lag                                                                               | W35: one-step `E` halves at half the step (0.50, 0.47); follower gross 1.5e-4, 8.2e-5, 2.3e-5 at 120, 60, 30 s (W24, W25)           |
| Aggregation                     | the 8 tags summed into groups against a run of the groups: relative L∞ at most 1e-10 at 24 h, Float64; reported, since OD8 needs no bridge (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | roundoff over a day's steps                                                                                                                     | not run                                                                                                                             |
| Cost, default mode, 8 + 8 tags  | build at most twice the untagged build; step time at most twice the untagged step (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | measured ratios at fewer tags, with room for 16 tags                                                                                            | build: D4 untagged 410 s (E44), with 8 energy tags 600 s (E73); step: 1.43× with 4 + 4 tags (W22)                                   |
| Cost, copies at 8               | build within 4 h, both families' copies in one model (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | the tested limit; 32 did not build in 4 h                                                                                                       | TRMM, 8 water copies 699 s (W34); D4, 8 energy copies 3504 s (E73)                                                                  |
| Cost, sphere                    | memory per rank and wall time within the M4 estimate below (approved 2026-09-24)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | the owner budgets it                                                                                                                            | E75: 16.5 h, 500 GB, 24 ranks, 10 days at 10 levels                                                                                 |

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* a note on the approved row "Provenance, per tag at 24 h", which is
not rewritten. The row comes from G1's criterion 4b. G3_PLAN 6.1 argued against
a looser budget, which would let the default's error exceed "the spread from
the mixing convention alone, about 1% in L1 (E66)". E66's L1 row is in
fractions: 0.08 and 0.12 for the region tags, 0.68 to 1.26 for the source tags,
so 8% to 126%. E66's reference also keeps 5.99e5 J/m² of its own residual, and
fails closure on OD4's scale (E86). So E66's difference is not a pure
convention effect, and that argument did not hold. At the owner's request the
sentence in G3_PLAN 6.1 is replaced (2026-09-26). The row stands as approved,
and so does
OD5, until the owner amends them. E66's measured spread is reported apart from
the row, labelled as convention plus the reference's residual.

**OD2's windows, per case: approved 2026-09-24, as drafted.** Startup ends at the first output after which the
parent's domain-mean tendency of `∫ρq_tot` (water) or `∫ρe_tot` (energy),
averaged over the output interval, stays below 10% of its largest value in the
first 6 hours for three outputs in a row. For a case with a source pulse,
startup also lasts until the pulse's source rate falls below 10% of its peak.
Each case's boundary is read from its untagged run before its first scored
run.

| case                                   | startup (expected)                                                                 | established flow                                                                   | long run                |
|:-------------------------------------- |:---------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------- |:----------------------- |
| D4-W, DYCOMS RF02 1M, 24 h             | about the first hour; E39 found 98% of the first hour's residual in the first step | from startup's end to 24 h                                                         | —                       |
| TRMM_LBA 0M and 1M, 6 h                | until the rule's time; rain starts about 3 h (W26)                                 | from startup's end to 6 h; the rain is scored here only if it starts after startup | —                       |
| The GCM-driven column, 3 h and 90 days | the first half hour: V-W8's energy residual was nearly all made then (W22)         | to 1 day                                                                           | days 1 to 90            |
| The WP4b held-out case                 | TRMM_LBA 1M, if its rain starts after startup; otherwise RICO 1M, 24 h             | as the case gives                                                                  | —                       |
| The sphere, 90 days                    | the first hour; E39b found the first step made most of the first hour's residual   | days 1 to 10                                                                       | days 10 to 90           |
| DYCOMS 0M                              | the whole rain event, which ends within the first hour (W15)                       | —                                                                                  | — (not a held-out case) |

**OD6's ceiling: approved 2026-09-24, as drafted.** At every output of the 90 days, the gross residual is below
`max(0.02 S_min, 2e-4)` of the partition, and never above the family's closure
budget (water 0.2% of `∫ρq_tot`; energy in OD4 units). `S_min` is the smallest
analysed tag's share of the partition at that output. The reason: a residual
`R` shifts the shares by about `R` (G3_PLAN 6.1), so 2% of `S_min` is the
per-tag L1 budget of the smallest tag, and 2e-4 is the small-tag absolute rule.
The level is observed, not projected. The gross's growth over days 30 to 90 is
reported beside it, as the long runs report it. Nearest measured: E74's energy
sphere, 2.0e-4 of the scale at day 10, still growing; V-W8's water, 4.2e-4 at
3 h, before the follower (W22).

*Superseded later the same day: see the register.* **OD1's stretching, a proposal.** The GCM-driven column's rule, scaled to
30 km: `z_stretch: true`, `dz_bottom` 30 m, 60 elements to 30 km. ClimaCore's
`HyperbolicTangentStretching` then gives 30 m at the bottom, 116 m at 1 km and
1313 m at the top, with 16 levels below 1 km and 27 below 3 km. The GCM column
itself gives 30 m, 117 m and 1865 m to 40 km. Today's 10-level sphere has 500 m
at the bottom and 6270 m at the top. Computed on the login node with
ClimaCore 1.0.0; no run has used this grid. *2026-09-24:* the owner chose
this grid for the short 60-level sphere run below.

**The 90-day, 60-level sphere in M4, an estimate.** V-W11's basis is E75: 16.5 h
and 500 GB for 10 days at 10 levels on 24 ranks, each rank peaking at 16.0 GiB.
If the cost grows in proportion to days and to levels, 90 days at 60 levels take
16.5 h × 9 × 6 = 891 h, about 37 days on 24 ranks *(derived)*. Memory grows at
most sixfold, to about 2.3 TiB *(derived)*, more than one node's 1 TB. So the
run needs more ranks and nodes, and chained segments through checkpoints (WP6
step 3 carries the ledgers through them). The qualification run carries 8
water and 8 energy tags and the per-tag ledgers, more fields than E75's seven
tags, so this is a lower bound on the fields. A short 60-level sphere run
would replace the estimate with a measurement.

*The owner, 2026-09-24: measure a short run first.* Before the 90-day,
60-level sphere is planned, the 60-level sphere on the proposed grid (60
elements to 30 km, `dz_bottom` 30 m) runs for 1 to 2 days, untagged and with
8 water and 8 energy tags. It measures the step time, the memory per rank and
the ranks needed. It runs after step 8a, as part of step 9, not as a new work
package.

### Provenance pathway: exploratory numbers and proposals (2026-09-26)

*Scope added (provenance pathway, 2026-09-26; revised after the owner's
review):* materiality and the per-rule allotments are exploratory. They decide
only what the pathway proposes to look at next, and none is a certification
threshold. The rounding row is a proposal under OD10. The floor row follows
OD12, which the owner accepted on 2026-10-02. They apply only once the owner
accepts the decision each rests on. None of these numbers
changes an approved row.

| number                                                                    | value                                                                           | use                                                                                                                                                                              | nearest measured (prior only)                                                                                           |
|:------------------------------------------------------------------------- |:------------------------------------------------------------------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------- |
| Materiality                                                               | a rule's screen above 0.2% of the tag's inventory a day, over the scored window | decides whether PX16 is proposed after PX8; a PX1 result above it is a reason to go on, and one below it is not assessable; a tenth of the per-tag L1 row, as the closure budget | W24: the repair's ledger 2.9e-3 of the column's water in a day                                                          |
| Per-rule allotment, 24 h                                                  | 0.5% L1 and 1.25% L∞                                                            | exploratory, used by no gate; four material rules would fit within the 2% and 5% row                                                                                             | W40: the leak's first-order part 3, `tropo` 2.4% L1 and 6.2% L∞                                                         |
| Per-rule allotment, first hour                                            | 0.25% L1 region, 2.5% source, 6% L∞                                             | exploratory, used by no gate; a quarter of the first-hour row                                                                                                                    | W38's P3: `evap` 11.7% between the modes                                                                                |
| Invariants and ledger completeness                                        | rounding, 1e-10 relative in Float64                                             | exact identities; proposed under OD10                                                                                                                                            | W33: the clamp's cut 1.2e-15 under the follower                                                                         |
| Reference floors                                                          | at most a quarter of the budget they judge                                      | a validity condition for a reference; OD12, accepted 2026-10-02                                                                                                                  | —                                                                                                                       |
| The follower's part 2b per tag, D4-W (it understates the worst-case form) | reported                                                                        | shows why the screen exceeds the row there                                                                                                                                       | `tropo`: 3.23% (`vdiff`) and 3.97% (`sgs_mass_flux`) over 0.924 days; `strat` about 2.0% (`output/wp4c_gate/score.txt`) |

### The owner's answers, later on 2026-09-24

  - **OD3: approved as drafted.** Every row of the threshold table is a scoring
    threshold from 2026-09-24, with its numbers unchanged. Step 2 is
    unblocked.
  - **OD2's window rule and OD6's ceiling: approved as drafted.**
  - **The sphere's cost: measure a short run first.** A 1 to 2 day run of the
    60-level sphere on the proposed grid, untagged and with 8 water and 8
    energy tags, measures step time, memory per rank and the ranks needed,
    before the 90-day run is planned. It runs after step 8a, within step 9.
  - **Known issue 7: option A now, then the probe, then a choice.** Option A,
    the tags cannot end a run, is built. The probe of
    `design/NEGATIVE_PARENT_WATER.md` section 5 then shows which ledger grows,
    and the parent session brings the choice among B, C and D back to the
    owner. What ended the runs was the closure check: job `13917157`'s
    `.err`, line 1401, "water tag closure residual 1.0194981558568388 exceeds
    the configured abort level 1.0 at t = 6.4368e6 s", from
    `tag_closure_callback!`.

### The owner's answers, 2026-09-25

  - **WP4b-D: the three parts, as the note names them.** `ρq_tag_<name>` holds
    the non-precipitating part, beside `ρq_rtag_<name>` and `ρq_stag_<name>`,
    behind `water_tag_precipitation: true`, 1M only. The microphysics goes by
    the **gross flows**, with the net-flow rule as the fallback where the
    per-process terms are not available. Point 4 of the note's section 15
    (4.2's rule restated) is superseded by rev. 2's WP4c gate. Steps 7, 8 and
    8b are unblocked. A separate agent builds step 7, stage 1.
  - **OD4's quantity: an exact accumulator.** A per-tag, per-step gross source
    accumulator for the energy source tags, `Σ|source into tag i|` over the
    steps, carried through restarts, as WP6 did for the ledgers. The process
    records' figure stays as the interim until it lands. *After E84:* that
    figure is an estimate, not a lower bound (the register, OD4).
  - **The WP4c gate's reading of OD3: confirmed as proposed.** Retention part
    1: the remainder above 0.02% of the water. Part 2: `led_inc` per tag above
    2% of the tag's inventory, taken as the difference between two runs. The
    per-tag intervention row's 2% is used here too.
  - **The mirrors' surface relaxation: by composition**, as built (#114).

### The owner's answers, later on 2026-09-25

  - **Option C after its validation (W42): probe the miss first.** V2
    failed at site 23 (2.2% against 0.2%), wholly past day 10, where the
    contract's negative-water row already leaves site 23's water unscored. In
    four of the ten largest 6-hourly rises of the miss no ledger records it.
    The owner chose to find what grows it before anything else: a
    pre-registered probe (`design/NEGATIVE_PARENT_WATER.md`, section 9), then
    C validated again. Site 23's long-run rerun, and with it OD7, waits.
    Kept C over dropping it or accepting it as is.
    *Probed (job `13987196`), scored on 2026-09-28 (W47):* three of the four
    unrecorded rises go to candidate 5, the forcing's vertical fluctuation,
    in class-N cells (parent at or below zero). In the fourth no candidate
    is supported. The forcing as a whole attributes it (1.000, as in every
    rise). The owner decides the revision of C (section 9.5). *2026-09-28:*
    the owner chose to probe more first, and to rerun the probe on `main`
    (below). *Probed on `main` (job `13996867`), scored on 2026-09-29
    (W48):* by leave-one-out, subsidence carries every rise, and the
    mechanism is shown cell by cell. The owner decides C's revision.
    *Decided 2026-09-29 (section 10, option 1):* the explicit brackets give
    the region tags the target's gain, for every explicit process.

  - **Known issue 7: option C.** The partition tags partition the parent's
    non-negative water, `max(ρq_tot, 0)`. The follower takes that field's
    increment; the repair, the rescale and the copies' repair aim at it. The
    negative part becomes a named field, `q_tag_negative`. Built on
    `claude/water-tags-negative-parent`; its validation is pre-registered in
    `design/NEGATIVE_PARENT_WATER.md`, section 8.

  - **R2, the Newton rule: measure three and four iterations first.** The
    threshold stays as approved. Job `13944802` runs W25's fixed-parent probe
    on `w25i_d4w_default_z60_c` with `TRIALS=1,2,3,4`, output in
    `$SCRATCH/tag_closure/output/w25i_probes/fixed_parent_newton34/`. Raising
    OD1's Newton count or revising the row follows its result.

  - **R2, the Newton row: revised** (after W38 and W41). The job measured the
    parent's `E` after startup at 1.2e-2, 4.1e-3, 2.3e-3 and 1.9e-3 with 1,
    2, 3 and 4 iterations, so it levels off near 2e-3. The parent's `E` is
    always reported. The row gates only verdicts that compare runs with
    different parents: full-run comparisons, and provenance against copies
    from a separate run. Same-parent verdicts go ahead. OD1's Newton count
    stays. Nothing is rescored. W38's R2 verdicts stand as scored and are
    read under the revised scope: every W25 verdict is same-parent except
    R7, the provenance against copies.

  - **A persistent parent-validity flag in the closure tables: B and D
    together.** B, `negative_water_void`: a latch per family, with the key
    `negative_water_void_above` (default 1e-4, water only). It is set at the
    checks when the raw `ρq_tot`'s negative water `N / ∫ρq_tot` passes the
    level; the ratio has its own column on every row; the latch is carried
    through checkpoints. It reads the contract's negative-water row online;
    offline scoring stays the reference. D: a per-cell cumulative
    negative-water ledger, updated every accepted step and carried through
    restarts, so "never negative" is exact, not sampled. Another agent builds
    both on a branch stacked on #116, which also fixes #116's water audit:
    under option C `nonpositive_mass` read 0 by construction, and it will
    read the raw parent again.

  - **The per-tag intervention row, revised** (from the review of #109). OD3's
    per-tag row (2%) applies to all tags, with two denominators:

      + a pure region tag: `retained / ∫tag`, with a positive inventory as its
        precondition;
      + a source-labelled or signed tag: `retained / ∫|tag|`, the absolute
        burden;
      + below the small-tag bound (2e-4 of the parent, OD4 units for energy):
        "not applicable", reported explicitly.

    Both ratios and a parent-scale ratio are reported. Another agent builds
    it on #109.

### The owner's answers, 2026-09-28

Asked with a short background, options and a recommendation each
(DECISIONS.md, 2026-09-28):

  - **Option C after W47:** probe more before any fix, the fourth rise and
    cell by cell. Rerun the probe on `main` now, with #118's check at every
    accepted step. Pre-registered as section 9.7 of
    `design/NEGATIVE_PARENT_WATER.md` before it runs. No fix is chosen yet.
  - **W45's investigation** waits until C's revision.
  - **OD7** stays deferred until C is fixed and site 23's long runs are
    scored.
  - **WP4a:** known issue 4's Jacobian gets the pair (the diagonal and the
    cross term, with the split solver's back-substitution) behind a switch.
    WP4a-J's experiment measures it. The copies' part follows WP4a-J.
  - **W21:** model the surface flux at the plume's start, then measure the
    first hour again.
  - **WP6's three points:** confirmed as built on `main`. An old checkpoint
    without the accumulators restarts them at zero with a warning, and a
    partial one is refused. Loss and τ stay out of WP6. The transfer ledgers
    stay as they are, with the per-tag ledgers beside them.
  - **The #119 and #121 follow-ups** on the backups go to `main` as two PRs.
    The backups stay as they are.
  - **OD9 to OD15, G4.3 to G4.6's seven points, and WP4b stage 1's five
    points:** walked through on 2026-10-02 (DECISIONS.md). *Replaces "walked
    through later":* the recommended option on all five items.

### The execution order

Proposed 2026-10-05, waiting for the owner: once adopted, this is the active delivery sequence. It supersedes the
earlier step ordering, not its scientific requirements or recorded results.
Step numbers elsewhere in these documents are the earlier order's. The old steps are mapped in [PLAN_CROSSWALK.md](PLAN_CROSSWALK.md). Their
original text is available at the pinned baseline. The contract, OD register,
G3_PLAN §6.1 and existing designs supply thresholds. A part number authorizes
neither an undecided convention nor an unapproved run.

| Part / PR boundary                       | Value, scope and existing work to reuse                                                                                                                                                                                                                                                                       | Dependencies and acceptance evidence                                                                                                                                                                                                                                                                            |
|:---------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 Plan reconciliation                    | One queue and a complete crosswalk. Preserve every WP/PX/G4 item, decision and failed result. Documentation only.                                                                                                                                                                                             | Loss check, link checks, independent review. No implementation or runs.                                                                                                                                                                                                                                         |
| 2 Water acceptance contract              | Define one useful initial water workflow, its observables and scientific tolerance rationale. Reuse G3's twelve criteria, OD1–OD3/OD5/OD8/OD12–OD15 and the claim contract. Propose missing tolerances without changing existing ones.                                                                        | Part 1. Separate missing-owner-decision list. Scope may be narrower than G3's full production target, which stays open.                                                                                                                                                                                         |
| 3 Energy acceptance contract | Canonical [G4 contract/matrix](design/G4_CLAIM_CONTRACTS.md#5-energy-acceptance-matrix), signed radiation-record pilot proposal and EA-USE/EA-ACCURACY/EA-COST. Distinguish stored labels, records and parent accounting; define cΔρ, OD4 discrete scales, window state residuals and cancellation. | Parts 1/2 source work reused; may run beside water. Independent doc review and preservation checks. Missing scientific choices/evidence stay blocked; no code or runs. |
| 4 Common evidence and scoring            | Reuse WP0, manifests, verifier, archive, WP6 outputs and verdict records. Fill demonstrated gaps only. PX0, PX21 when triggered, and fault injection remain.                                                                                                                                                  | Parts 2/3 determine applicable outputs. A missing reference produces not assessable. Missing or non-finite data fails (G3_PLAN 6.1, 2026-09-23). Neither is an omitted row. Exact code/configuration, environment, window, results and checksum evidence.                                                       |
| 5 Correction accounting                  | Reuse WP6 and G4.6. Distinguish signed accounting from absolute correction activity before summing events, cells or compartments. Resolve the PR #146 signed closing-ledger interpretation. Prefer probes to new state fields (OD13).                                                                         | Part 4. Alternating signs, simultaneous rain/snow corrections and restart stitching must reveal cancellation. No cumulative origin-error bound is claimed without support. Energy uses OD4.                                                                                                                     |
| 6 Independent water transport references | Reuse PX1/PX8, PX7, PX11/PX24 and existing mixing tests. Run PX12, the scheduled 0M eligibility test. Add only missing analytic/manufactured or independent transport references after design.                                                                                                                | Parts 2, 4, applicable 5. OD12 floors and parent validity first. Wrong-origin mutants fail despite closed totals. Report shared operators. PX16 (PP-SUB) goes to part 9, only after PX8's trigger and OD13.                                                                                                     |
| 7 Independent water-transfer references  | Reuse WP4a-V/J, WP4b-D, PX14/PX25. Known compositions of the giving pool distinguish transfer attribution from compartment closure, including rain/snow, export, empty/negative pools and simultaneous flows.                                                                                                 | Parts 2, 4, applicable 5. OD15 before scoring PX25. Independent rates/solver and temporal convention stated. Unavailable references remain not assessable. Do not presume EDMF stage 2/3 already built.                                                                                                         |
| 8 Water baseline and cost pilot          | Assess one useful integrated workflow. Reuse W54–W62 and WP9 where applicable. Measure dominant errors, intervention and intended-count cost before selecting fixes/defaults. This is the column cost pilot. The owner's 1–2-day sphere pilot is M4 work and may run once part 8's contract exists (see 12d). | Parts 6/7 for relevant active processes, contract and parent parity. Eligible comparator or explicit limitation. Build/step/memory measurement. Baseline is not qualification.                                                                                                                                  |
| 9 Targeted water fixes                   | One demonstrated defect or inseparable coupled change per PR. Reuse WP1/3/5/5b/4a/4b/4c designs. Include required EDMF precipitation stages. Retain refusals until supported. Shared-helper consolidation (WP2) only where justified.                                                                         | Part 8 identifies priority. Small reference-demonstrated fixes may proceed after 6/7. Independent regression, parity, restart and relevant CI. No upstream-model changes. Re-establish baseline after changes.                                                                                                  |
| 10 Water qualification                   | One scoped, usable water workflow with published limitations. Reuse V-W6, PX23 and the applicable V-W8/V-W9/WP8 evidence. Keep the broader G3 target open if not covered.                                                                                                                                     | Parts 8/9, cost ceilings fixed by the owner (the WP9 budget is waiting, criterion 10 fails against OD3's 2×), OD14 held-out hygiene. All applicable criteria pass. Unresolved origins cannot be called validated. No retuning on held-out data.                                                                 |
| 11a Energy references | [Discriminating energy cases](design/G4_CLAIM_CONTRACTS.md#6-discriminating-reference-work-for-later-parts), radiation record versus independent accepted-stage flux, heating/loss/work/boundary and fixed-convention tests; reuse G4.7/8 and PX22. | Parts 3/4 and applicable 5. Freeze reference/floors/owner accuracy before deciding evidence. Stored-tag PX22 retains OD7/OD11 and active nonshared-rule eligibility; the record-only pilot does not inherit source-tag gates. |
| 11b Energy baseline | Reuse G4.1/6/7/10/11/15/16 and post-#139 reruns; separate record pilot, process-budget and stored-source evidence. Measure current parity/restart, exact scale/correction activity, eligible references and cost. | 11a for the named claim; record pilot EA choices, stored-source OD7/OD11 and seven-point levels where applicable. Legacy interim is labelled, not a new qualified scale. Do not use ineligible copies as truth. |
| 11c Energy fixes                         | Separate PR per evidenced defect. Mirrors, cross blocks, subsidence and choices for the correction after each solve only where baseline/design justifies them.                                                                                                                                                | 11b. Retain unsupported-mode guards, require independent regression and parity. G4.9 placement and offset sweeps are comparisons, not automatic bounds.                                                                                                                                                         |
| 11d Energy qualification                 | G4.12 held-out evidence, fixed convention and supported-use statement. Preserve C4 and other limits.                                                                                                                                                                                                          | 11b/11c, energy criteria and cost. No qualification inherited from water. G4.13 long sphere belongs to 12d.                                                                                                                                                                                                     |
| 12a Precision and refinement             | Extend the qualified envelope. Reuse V-W7/W60/W62, refinement ladders and long-Float32 requirements.                                                                                                                                                                                                          | Relevant 10 or 11d. Existing failures preserved, named owner-approved rounding rule used only as authorized. Rain/snow coverage remains explicit.                                                                                                                                                               |
| 12b MPI and restart at scale             | Reuse W59, V-W9, MP1 and restart/forcing checks. Split MPI and restart changes if independently reviewable.                                                                                                                                                                                                   | Relevant qualification. Baseline parity/restart checks are required earlier too. Distinguish rank-to-rank differences from tagged/untagged parity within a rank count. Multi-node approval remains required.                                                                                                    |
| 12c Production performance               | Reuse WP9, P2/P3, compiler/allocation findings and measured tag-count scaling. One bounded optimization per PR. GPU remains gated.                                                                                                                                                                            | Part 8's cost pilot and scientific baseline. Build/step/memory results and unchanged qualified answers. No hidden loosening of cost criteria.                                                                                                                                                                   |
| 12d Long-run qualification               | Preserve OD1/OD6's 90-day, 60-level target and G4.13. First the authorized 1–2-day cost pilot. PX19/PX20 retain their triggers and limitations. Publish supported envelope.                                                                                                                                   | The 90-day run: relevant qualification, 12a–c, parent validity and affordable cost. The 1–2-day pilot keeps its earlier gate (OD6, after the negative-parent fix, merged as #137) and comes before M5 selection, as M4 requires. Explicit owner/run approvals remain. No new residence-time or air-age feature. |

Parts 2 and 3 may run together, and 11a may follow its own prerequisites while
water advances. Parts 4 and 5 should be split into family-specific PRs if
necessary. Part 9 and 11c are queues of bounded fixes, not single omnibus
PRs. Engineering checks required by a particular earlier claim must happen
there. Placing expanded coverage in part 12 does not postpone those checks. Parts 12a–d also hold M6 and M7 work: multi-node runs, devices, a production trial and the supported envelope. That work stays sketched and not approved, as above. Each such item needs the owner before it starts. The G3 items these parts reuse (V-W7, V-W9, WP9, OD1/OD6's sphere) keep their existing approval and gates.

**Value and effort.** Parts 2–4 are the first priority: small documentation
and evidence-tool increments prevent expensive but uninterpretable runs.
Part 5 and the smallest useful reference in 6 or 7 are next: medium effort,
high value because they can expose wrong origins even when totals close.
Part 8 is a bounded pilot that determines which fixes in 9 offer the largest
measured benefit. Parts 10/11d deliver the usable capability, and 12a–d expand
its operating range only after the earlier evidence and cost gates. These
are relative planning estimates, not measured developer time or run cost.
A part can close with documented reuse when its required evidence already
exists. It need not create new machinery to count as progress.

**Immediate progress.** Finish the contracts and reuse the evidence tools,
then resolve the smallest independent-reference gaps that unlock water
attribution assessment. PX12 remains the scheduled 0M eligibility and
KI4-COPIES/UP1 probe. D4-W's ineligible comparator is not reopened without
the owner (option D). PR #146 implementation does not close WP4b's EDMF or
origin qualification obligations. The known signed-ledger cancellation
concern belongs to part 5, which delivers accounting that shows cancellation. Part 7's known-composition tests then check the closing rule's attribution. Part 7 needs part 5's outputs, not a part 5 verdict on the closing rule.

**Stop rules.** An agent stops at a part whose owner decision is open and asks the owner. Default selection (M5) follows rev. 2's rules as approved, within the cost ceilings. If the owner adopts OD9, it also needs OD11, and the verdict records are reported beside it. An unavailable independent reference blocks the corresponding
validated claim. A parent defect goes to UPSTREAM_REQUIREMENTS, not a fork
physics change. Retain deferred PX/PP triggers, guards, owner decisions and
failed experiments. Any narrower initial workflow is an increment toward,
not a replacement for, G3/G4 production goals.

## Where the open items go

An agent matched every open item of OPERATIONAL_TODO's sections 2 to 7 and of
its Plan to a milestone on 2026-09-23. This session checked the doubtful ones.
Items marked "G3 …" are in [G3_TODO.md](G3_TODO.md), and items marked "G4.n"
in [G4_TODO.md](G4_TODO.md). The rest wait for a later goal or lie outside the
roadmap. They are in [BACKLOG.md](BACKLOG.md), except the energy items within
M1 to M5, which are at the end of G4_TODO.md. Each keeps its original ID there.
Beware of reused names:

  - the milestones M3 to M5 are not the N items M3 to M5 of the archived
    OPERATIONAL_TODO's section 4;
  - PR #95's review items R1 to R6 are not this list's R items;
  - G3's work packages WP0 to WP9 are not the water findings W1 to W14.

| Milestone | Open items                                                                                                                                                                                                                                 |
|:--------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| M0        | synergy 2, the Float64 twin (G3 WP0); synergy 1, the early warning (G4.2); `analysis/phase_c.jl`, which reads only `c*` runs, is replaced by the verifier (done)                                                                           |
| M1        | the file-based run of item 14, B14 (G3 V-W8, water and energy tags); U5 (G4.1, and G3 WP3 for water); D1 with D3 (G4.1, closes with #95). Later: C6's leftovers, a parity test for the stratospheric tracers (P6)                          |
| M2        | C4 and synergy 6 (G4.6); synergy 5 (G4.14, after G3 WP6); U9, A5 and synergy 4 (G4.4); U2's calibration, item 11 (G4.5). Later: A2's runtime part and A3; the open questions on D1's residual and the sphere's 17%, unless G4.6 names them |
| M3 to M5  | R5 (G3 V-W4 records each rung's cost); U8 (G4.10, while the choice for a winter run belongs to M7); P2 and P3 (G3 WP9). Later: A4, A6, C7, P7's optional fix. C1c stays shelved, since the increment prototype replaced it                 |
| M6        | MP1 on more than one node, U6, the model's own restart drift (E58), the GPU (item 13)                                                                                                                                                      |
| M8        | ice provenance where ice lasts (open question 3), C1d, U7. Synergy 3, the water tags in the updrafts, is now G3 itself                                                                                                                     |
| outside   | upstream: the ClimaCore issue, P5, the `ShipwayHill2012VelocityProfile` report, the N items M4 and M5 (2M and P3); CI: P8, Plan A.2's manual run; too terse to place: open question 4                                                      |

**Done, not yet struck through in the archived OPERATIONAL_TODO:**

  - C1b (#91) and C2 (#92), in section 2, items 4 and 5;
  - V2 (E74, E75), in item 10;
  - item 15 (#93);
  - B9 and the items bundled with it (#77);
  - T6: `test/energy_source_tags_edmf_integration.jl` on `main` checks the
    partition against the parent to 100 eps;
  - the N item M3: `test/tracer_processes_tests.jl` on `main`;
  - Plan A.1 (G1 is met), A.3 (questions 2 and 3, decided on 2026-09-19), A.4's
    NaN decision (fixed on 2026-09-20), and C.4 (V2 and V6 ran).

They are not carried into G4_TODO.md or BACKLOG.md. The archived original
keeps them where they stood.

## The current goal: G3, the water tags under EDMF

The owner set G3 on 2026-09-23 and re-scoped it the same day. The tagged water
tracers are brought to work under prognostic EDMF, in both modes: the exchange
by default, updraft copies as the audit. Precipitation provenance is included,
with rain and snow carrying their own tags. The water tags become operational
in the production configuration.

The plan, with twelve criteria, the design, work packages, experiments,
budgets and the review's findings, is [G3_PLAN.md](G3_PLAN.md). The to-do
list is [G3_TODO.md](G3_TODO.md). The owner approved every job within G3, and
the agents listed there.

**The next goal, G4: the energy source tags,** with what G3 learns. Its
items are listed in [G4_TODO.md](G4_TODO.md). The job session carries #95 to its
merge, and runs the ladder at the merged head.
