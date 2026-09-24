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

Water has a true reference under EDMF, exact mass bookkeeping, and no offset
or sign problem. So the shared machinery is qualified there first. The
process records go with the energy family in G4.

| Milestone | Outcome                                                                       | Water tags (G3)                                                                                                                      | Energy source tags (G4)                                                                                                               |
|:--------- |:----------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------- |
| M0        | Every result traceable: manifests, a verifier, a run inventory, archived data | the tools are built (verifier, mutation tests, manifest, inventory) and serve both families; review open (G3 WP0)                    | uses G3's tools                                                                                                                       |
| M1        | Correctness gaps closed, claims narrowed                                      | refusals, known issues, EDMF support in both modes, restarts, a file-based start (G3 WP1, WP3, V-W8, V-W9)                           | #95: R3 to R6 fixed in `e71430fb`, R1 in `dbe7435c`; the partition-only factor is in `dcf7d086`, and #95 is open at `afd470e7` (G4.1) |
| M2        | The acceptance contract's verdicts per family, with accepted-step intervention metrics and the per-tag ledger (rev. 2) | closure on D4-W, the copies' residual, leaks named; gross accumulators for both families (G3 WP3, WP6)                               | the process budget, the residual report, warnings apart from acceptance (G4.3 to G4.6)                                                |
| M3        | A suite of small reference cases, each converged; same-parent references where tag numerics are isolated (rev. 2) | D4-W and TRMM 0M, the ladder, Float32 (G3 V-W3, V-W4, V-W7)                                                                          | the R2 ladder is done (E76); the ladder at #95's merged head and the rest wait (G4.7, G4.8)                                           |
| M4        | Cost measured and budgeted, before M5: comparator feasibility at the intended tag count (OD8), cost ceilings, the sphere's run-length budget (rev. 2) | both families, both modes (G3 WP9)                                                                                                   | from G3                                                                                                                               |
| M5        | The mixing closure and precipitation provenance chosen by experiment, under the contract; closure alone never qualifies (rev. 2) | exchange against copies, the follower's default, the 0M split, rain and snow tags, held-out columns (G3 WP5, WP4a, WP4b, V-W5, V-W6) | offset, placement variants, carried-over design, held-out columns, the energy default (G4.9 to G4.12)                                 |
| sphere    | Ten days in the production configuration                                      | V-W11                                                                                                                                | G4.13                                                                                                                                 |
| M6        | Devices, precision, input data and restarts at scale                          | not started; the GPU decision belongs here                                                                                           | not started                                                                                                                           |
| M7        | A production trial and a supported envelope                                   | not started                                                                                                                          | not started                                                                                                                           |
| M8        | Extensions: air age, memory and forecasts                                     | —                                                                                                                                    | memory number (G4.14); the rest later                                                                                                 |

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

## Rev. 2 of the work plan (2026-09-24)

The owner revised the work plan on 2026-09-24 ("Simulation-results synthesis
and in-place work-plan revision, rev. 2"). It adds no work package and no
milestone. It changes the order and the acceptance logic, so that closure
cannot stand in for provenance, an ineligible audit cannot select a default,
and criteria are fixed before the runs they judge. This file hosts its
acceptance contract, its decision register and its execution order. The
report of steps 0 and 1 is
[review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md](review/agent_reviews/plan_rev2_steps0-1_2026-09-24.md).

**What changes per milestone.**

  - **M2.** *Scope added (rev. 2):* the single verdict "independent
    accounting, gross diagnostics" is replaced by the contract's verdicts
    below. They include accepted-step intervention metrics and the per-tag
    ledger (G3 WP6 step 3).
  - **M3.** *Scope added (rev. 2):* a reference that isolates tag numerics
    shares the parent. A run with another Newton count or time step is a
    different atmosphere. It is a configuration comparison, not a tag-error
    reference (W33 against W35).
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

### The acceptance contract

Every result reports each row that applies as **pass**, **fail** or **not
assessable**. *Not assessable* names the missing prerequisite, for example "no
eligible comparator: copies repair 0.60%/day against a 0.20%/day bound"
(W21). Its treatment at M5 follows OD5. G3_PLAN 6.1, M2 and G4.3 to G4.6 refer
to this table and do not restate it.

| Verdict                | Required evidence                                                                                                                                                         | Threshold                                                                                        |
|:---------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------ |
| Parent validity        | Tagged/untagged parity, and the physical and numerical validity of the shared parent trajectory                                                                          | Parity: bitwise. Validity checks: OD3                                                            |
| Closure                | Net and gross partition residual                                                                                                                                          | Water: 0.2% day-scale unless explicitly revised (G3_PLAN 6.1). Energy: OD3, in offset-invariant units (OD4) |
| Provenance             | Region and source L1 and L∞ against an eligible comparator; absolute error for small source tags; process- or precipitation-weighted comparisons where they apply         | OD3                                                                                              |
| Comparator eligibility | In the same run: the comparator's closure, its repair throughput, Newton and time-step stability (repair must not grow under refinement), complete mirrors and the Jacobian terms that matter | Water copies' repair: 0.20%/day (G3_PLAN 6.1). Others: OD3                                       |
| Intervention           | Accepted-step gross repair and follower transfer; per-tag cumulative correction relative to the tag's inventory; event counts; attempted against retained change; clamps and zero-normalization fallbacks | OD3, aggregate and per tag                                                                       |
| Convergence            | Fixed-parent trial-step error where tag numerics are isolated; the refinement test of follower and repair throughput; full-run differences reported apart                 | OD3                                                                                              |
| Aggregation            | A run at the intended tag count summed into nested groups, against a run of those groups                                                                                  | Roundoff, or the solver's tolerance; any departure explained (OD3)                               |
| Reproducibility        | An immutable SHA or tag, the exact configuration, the manifest, the verifier's output and machine-readable results                                                       | Complete, or fail                                                                                |
| Cost                   | Build time, peak memory and per-step scaling at the intended tag count, the comparator included; the sphere's run length within budget                                  | OD3; OD6                                                                                         |

Closure never substitutes for provenance. Where no comparator is eligible, the
convergence, intervention and aggregation rows can bound the default's
provenance but not validate it.

A copies run is a provenance comparator only if, in that run, it passes its
own closure criterion, the repair-throughput criterion and Newton and time-step
stability, and has the source mirrors and Jacobian terms it needs. Otherwise
the provenance verdict is *not assessable*. A default is never chosen because
it is closest to a failed comparator's repaired output.

### The decision register

Each decision is recorded here before the first run it judges. Results are
scored against the value recorded at that time, as W33 is. Open decisions are
listed in [STATUS.md](STATUS.md). No agent fills one in.

| ID  | Decision                                                                                                                                                                                  | Needed before                                          | Notes                                                                                                                                                                  | Status                              |
|:--- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------ |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------- |
| OD1 | The production envelope: vertical levels, SGS reconstruction, Δt, Newton count, microphysics (0M or 1M, explicit or implicit sedimentation), the intended water and energy tag counts | W25 isolation (step 2); OD8                            | If production uses ≥ 60 levels or first-order SGS, W25's failures are the main case                                                                                     | OWNER DECISION REQUIRED (OD1)       |
| OD2 | The window boundaries per case: startup or source pulse, established flow, long run                                                                                                      | The first run scored by window                         | Include the WP4b held-out case                                                                                                                                          | OWNER DECISION REQUIRED (OD2)       |
| OD3 | Thresholds: parent-validity checks; provenance (L1, L∞, absolute error for small tags); intervention (aggregate and per tag); comparator eligibility; refinement; aggregation tolerance; cost (build time, peak memory, per-step time) | The first run each threshold judges                    | Existing numbers carry over unchanged: water closure 0.2% day-scale, copies' repair 0.20%/day, and the existing time-step, Newton and first-hour budgets (G3_PLAN 6.1) | OWNER DECISION REQUIRED (OD3)       |
| OD4 | The offset-invariant scale for every energy percentage                                                                                                                                  | Energy thresholds in OD3; G4.3 to G4.6                 | Candidate: the cumulative gross source throughput into the tags over the same window. First audit the denominators of the existing E-records                          | OWNER DECISION REQUIRED (OD4)       |
| OD5 | How *not assessable* is treated at M5                                                                                                                                                  | M5                                                     | Proposed: it blocks M5 for that configuration unless the Insight 10 tests pass their thresholds; the configuration is then labelled "provenance bounded, not validated" | OWNER DECISION REQUIRED (OD5)       |
| OD6 | The sphere: an absolute ceiling relative to the smallest analysed tag; a growth-rate or loss-timescale bound; the run length                                                            | Water sphere (step 9); energy sphere (step 11)          | Run length budgeted under M4. G3_PLAN 6.1's "plateau after day one" is replaced by this                                                                                | OWNER DECISION REQUIRED (OD6)       |
| OD7 | G4.15: bounded local movement (the same-sign rule), or the fourfold increase in gross residual it measured (E79)                                                                       | The G4.7 and G4.8 runs; the energy default             | Water's same-sign choice is not inherited. The owner decided on 2026-09-24 to choose after the long runs (DECISIONS.md, `design/INCREMENT_RULE_LONG_RUNS.md`)         | OWNER DECISION REQUIRED (OD7)       |
| OD8 | Audit feasibility: copies as the reference at the intended tag count, or copies at the largest buildable count plus the aggregation bridge                                             | WP5b-C at those counts; G4.1 and G4.11                 | Measured on TRMM's column: 699 s at 8 copies, 2417 s at 16, no build within 4 h at 32 (W30, W34); an 8 h build of 32 is running (job `13911480`)                     | OWNER DECISION REQUIRED (OD8)       |

### The execution order

Each step names the decisions it needs. An agent stops at a step whose
decision is open and asks the owner.

| Step | What                                                                                                                                                     | Needs          | State (2026-09-24)                                                                                                                                                             |
|:---- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0    | Guard and records, no simulations: G4.16's interim refusal and its test; STATUS; the in-place edits; this register; the comparator-eligibility annotations on W29, E39, E76 and D4-W | —              | Done. The guard is on `claude/energy-explicit-1m-guard` (`33eeb5cd`), not yet a PR                                                                                              |
| 1    | G3 WP6 step 3, with the per-tag ledger (Insight 10)                                                                                                      | —              | Built on `claude/water-tags-wp6-step3`, on #103; unit tests pass on the login node; integration tests and the check script not yet run (G3_TODO, WP6)                          |
| 2    | W25 isolation at 30, 60 and 120 levels, centred and first-order: fixed-parent probes and the refinement test first, then full matched runs              | OD1, OD2, OD3  | Waits on the owner                                                                                                                                                             |
| 3    | The audit-feasibility decision (WP9, OD8), water and energy copies at the intended tag counts; may run beside step 2                                    | OD1            | Waits on the owner                                                                                                                                                             |
| 4    | WP5b-C at the tag counts OD8 keeps; copies pass eligibility in each run before they serve as the audit                                                  | OD8            | A first build exists outside the pushed branches (G3_TODO, WP5b-C)                                                                                                            |
| 5    | WP5b-V's remaining arms: those without copies after step 2, default-against-copies arms after step 4; the explicit-1M follower stays opt-in unless it passes | step 2, step 4 | The same-atmosphere check is done and passes (W35). W33 stays a failure; the owner decides whether its verdict changes                                                        |
| 6    | The WP4c operator-decomposition gate, with the three-part retention rule; defer, don't delete                                                           | OD3            | Waits                                                                                                                                                                          |
| 7    | WP4b, judged by process-weighted same-state evidence and a held-out case that rains in established flow                                                | OD2, OD3       | Waits                                                                                                                                                                          |
| 8    | WP9's cost qualification at the intended tag count, with the comparator and the aggregation test                                                      | OD3            | Waits                                                                                                                                                                          |
| 9    | The water sphere under the revised long-run criterion                                                                                                   | OD6            | Waits                                                                                                                                                                          |
| 10   | G4: G4.16's cross blocks (the refusal stays until they pass), G4.1 and G4.11's mirrors at the OD8 counts, G4.3 to G4.6 with offset-invariant scales, the G4.15 decision, G4.7 and G4.8 with startup windows and fixed-parent comparisons, the energy default | OD4, OD7       | Waits                                                                                                                                                                          |
| 11   | The energy sphere, once its comparator, offset, cross-block, intervention and cost contracts are settled                                                | OD6            | Waits                                                                                                                                                                          |

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
