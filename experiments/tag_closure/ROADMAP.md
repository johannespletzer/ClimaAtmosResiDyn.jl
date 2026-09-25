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
| M4        | Cost measured and budgeted, before M5: comparator feasibility at the intended tag count (OD8), cost ceilings, the sphere's run-length budget (rev. 2); the 90-day, 60-level sphere's estimate (2026-09-24, below), and a 1-2 day 60-level sphere run that measures it, after step 8a | both families, both modes (G3 WP9)                                                                                                   | from G3                                                                                                                               |
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
scored against the value recorded at that time, as W33 is. **This register is
the single source of each decision's current state.** STATUS, DECISIONS, the
TODO files and G3_PLAN point here and do not restate it. **OD7 is the only
open numbered decision.** The owner's other open choices have no OD number;
they are listed below the table. No agent fills one in.

| ID  | Decision                                                                                                                                                                                  | Needed before                                          | Notes                                                                                                                                                                  | Status                              |
|:--- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------------------------------------------------ |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:----------------------------------- |
| OD1 | The production envelope: vertical levels, SGS reconstruction, Δt, Newton count, microphysics (0M or 1M, explicit or implicit sedimentation), the intended water and energy tag counts | W25 isolation (step 2); OD8                            | If production uses ≥ 60 levels or first-order SGS, W25's failures are the main case                                                                                     | ~~OWNER DECISION REQUIRED (OD1)~~ **Decided** 2026-09-24: `g2_v2_sphere_n2` at 60 levels; its stretching chosen the same day |
| OD2 | The window boundaries per case: startup or source pulse, established flow, long run                                                                                                      | The first run scored by window                         | Include the WP4b held-out case                                                                                                                                          | ~~OWNER DECISION REQUIRED (OD2)~~ **Decided** 2026-09-24: physical windows; the window rule approved the same day |
| OD3 | Thresholds: parent-validity checks; provenance (L1, L∞, absolute error for small tags); intervention (aggregate and per tag); comparator eligibility; refinement; aggregation tolerance; cost (build time, peak memory, per-step time) | The first run each threshold judges                    | Existing numbers carry over unchanged: water closure 0.2% day-scale, copies' repair 0.20%/day, and the existing time-step, Newton and first-hour budgets (G3_PLAN 6.1) | ~~OWNER DECISION REQUIRED (OD3)~~ **Decided** 2026-09-24: approved as drafted. Its WP4c reading confirmed 2026-09-25 |
| OD4 | The offset-invariant scale for every energy percentage                                                                                                                                  | Energy thresholds in OD3; G4.3 to G4.6                 | Candidate: the cumulative gross source throughput into the tags over the same window. First audit the denominators of the existing E-records                          | ~~OWNER DECISION REQUIRED (OD4)~~ **Decided:** the scale is the gross source throughput (2026-09-24); the quantity is an exact per-tag, per-step accumulator (2026-09-25), being built. **Interim**, until it lands and for runs that predate it: the process records' lower bound, with every such percentage labelled an upper bound. Earlier E-records are restated with it, and rerun only where the contract needs an exact value |
| OD5 | How *not assessable* is treated at M5                                                                                                                                                  | M5                                                     | Proposed: it blocks M5 for that configuration unless the Insight 10 tests pass their thresholds; the configuration is then labelled "provenance bounded, not validated" | ~~OWNER DECISION REQUIRED (OD5)~~ **Decided** 2026-09-24 |
| OD6 | The sphere: an absolute ceiling relative to the smallest analysed tag; a growth-rate or loss-timescale bound; the run length                                                            | Water sphere (step 9); energy sphere (step 11)          | Run length budgeted under M4. G3_PLAN 6.1's "plateau after day one" is replaced by this                                                                                | ~~OWNER DECISION REQUIRED (OD6)~~ **Decided** 2026-09-24: 90 days to saturation; its ceiling approved; a 1 to 2 day run measures the cost first |
| OD7 | G4.15: bounded local movement (the same-sign rule), or the fourfold increase in gross residual it measured (E79)                                                                       | The G4.7 and G4.8 runs; the energy default             | Water's same-sign choice is not inherited. The owner decided on 2026-09-24 to choose after the long runs (DECISIONS.md, `design/INCREMENT_RULE_LONG_RUNS.md`)         | ~~OWNER DECISION REQUIRED (OD7)~~ **OPEN**: deferred by the owner on 2026-09-24, until the long runs can be scored at site 23 (known issue 7) |
| OD8 | Audit feasibility: copies as the reference at the intended tag count, or copies at the largest buildable count plus the aggregation bridge                                             | WP5b-C at those counts; G4.1 and G4.11                 | Measured on TRMM's column: 699 s at 8 copies, 2417 s at 16, no build within 4 h at 32 (W30, W34); an 8 h build of 32 is running (job `13911480`)                     | ~~OWNER DECISION REQUIRED (OD8)~~ **Decided** 2026-09-24: 8 water and 8 energy tags, copies at 8 |

**The owner's other open choices** (no OD number), each with its entry in
[DECISIONS.md](DECISIONS.md), "Waiting for the owner":

  - ~~known issue 7's option among B, C and D~~ **decided 2026-09-25: option
    C** (below); its validation is pre-registered
    (`design/NEGATIVE_PARENT_WATER.md`, section 8);
  - ~~**R2, the Newton row, on D4-W**~~ **decided 2026-09-25: the row is
    revised** (below). Three and four iterations level off near 2e-3 (W41);
  - WP4a's two points: known issue 4's Jacobian, and the copies' part of it;
  - WP6's three points, where step 3 took the conservative defaults
    (`design/GROSS_ACCUMULATORS.md` 10.6);
  - the explicit-1M water default, decided at M5 under the contract (W33
    stays a failure);
  - W21's surface rule in the first hour: whether the plume's start models
    the surface flux.

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

| row | threshold (approved 2026-09-24, or set earlier where marked) | reason | nearest measured |
|:--- |:---------------------------------- |:------ |:---------------- |
| Parent validity: parity | bit for bit (set, the parity rule) | the fork's rule | every tagged run so far, up to the site 23 crashes |
| Parent validity: temperature | no point at the 150 K floor, and the top level's mean moves less than 5 K in the first day (approved 2026-09-24) | E69's one-Newton collapse is the failure this catches | E69: 156 K and 18% at the floor at 6 h with one iteration; E74: 218 to 220 K over ten days with two |
| Parent validity: negative water | the parent's negative water, `Σ ρ min(q_tot, 0) dV`, stays below 1e-4 of `∫ρq_tot`; above it the run's water results are not scored (approved 2026-09-24) | a negative parent voids the partition's meaning (known issue 7) | site 23: `q_tot` below zero from day 10, to −3.1e-3 kg/kg (day 30); the negative part at worst 11% of the column's water (W36) |
| Parent validity: Newton | the parent's one-step error at the production Newton count, W35's `E`, at most 1e-3 (approved 2026-09-24). *Revised 2026-09-25, after W38 and W41:* `E` is always reported, and the row gates only verdicts that compare runs with different parents (full-run comparisons, provenance against copies from a separate run). Same-parent verdicts go ahead | a tenth of a percent of a step's increment keeps the parent's solve out of the tags' error; in a same-parent verdict the parent's error cancels | W35, TRMM 1M, 120 s: 4.9e-3 with one iteration, 6.3e-4 with two. W41, D4-W at 60 levels: 1.2e-2, 4.1e-3, 2.3e-3, 1.9e-3 with 1 to 4 |
| Closure, water | gross at 0.2% of `∫ρq_tot` at 24 h, no more in the second 12 h (set, G3_PLAN 6.1) | a tenth of the per-tag L1 budget | D4-W under the follower 1.35e-4 (W28), 7.3e-6 with the cross blocks (W31) |
| Closure, energy | gross at most 0.2% of the window's gross source throughput (OD4 units) (approved 2026-09-24) | water's budget in the new scale | not yet in OD4 units; E79: 2.3e-6 of the partitioned energy on D4; E74: 2.0e-4 of the scale at ten days |
| Provenance, per tag at 24 h | L1 ≤ 2%, L∞ ≤ 5% (set) | G1's criterion 4b | D4-W: 0.25/0.41/0.42% (W28), against copies that are not eligible (W21) |
| Provenance, first hour | L1 ≤ 1% region, ≤ 10% source, L∞ ≤ 25% (set) | G1's split | W21's pulse: `sfc` 14.4% (fails) |
| Provenance, small tags | `∫ρ|Δq|dz ≤ 2e-4 ∫ρq_tot` for a tag under 1% (set); energy the same in OD4 units (approved 2026-09-24) | 6.1's small-tag rule | — |
| Provenance, process-weighted | per tag, `Σ|Pₖ||φ − φ_ref| / Σ|Pₖ|` ≤ 0.05 against an eligible comparator (approved 2026-09-24) | lies above what the reconstruction reached and well below the grid rule | W32: reconstruction 0.014 to 0.038, grid rule 0.15 to 0.19 (`pbl`) |
| Comparator: its own residual | at most 0.02% of `∫ρq_tot` (set) | a tenth of the closure budget | D4-W 1.0e-5 (W21) |
| Comparator: its repair | at most 0.20% of `∫ρq_tot` a day (set); energy the same in OD4 units (approved 2026-09-24) | 6.1 | D4-W 0.60% (fails), TRMM below 1e-5, W32 9.5e-10 |
| Comparator: refinement | at each halving of `dt` or doubling of Newton count, the repair per day is at most 1.1 times the coarser rung's (approved 2026-09-24) | "must not grow"; 10% allows for the atmosphere's own change between rungs | W25: dt 0.60, 1.6, 1.8% (grows, fails); Newton 0.60, 0.30, 0.28% (passes) |
| Intervention, aggregate | the partition repair's retained gross at most 0.5% of `∫ρq_tot` a day (approved 2026-09-24) | a quarter of the per-tag L1 budget | D4-W 0.29% a day (W24, net over time, a lower bound) |
| Intervention, per tag | each tag's `led_fix` `_inventory_fraction` at most 2% over the window; `led_inc` reported, judged only through the refinement test (approved 2026-09-24); also WP4c gate part 2, `led_inc` per tag between two runs (2026-09-25) | a correction as large as the per-tag L1 budget could alone use it up; `led_inc` holds the parent's vertical advection | none yet (WP6 step 3 is new); aggregate moved 2.4% a day on D4-W (W28) |
| Refinement | the repair's and `inc_left`'s throughput per unit time at the finer rung at most 0.75 times the coarser rung's; above 0.9 flags a structural cause (approved 2026-09-24) | lag shrinks with the step or the iterations; a plateau is not lag | W35: one-step `E` halves at half the step (0.50, 0.47); follower gross 1.5e-4, 8.2e-5, 2.3e-5 at 120, 60, 30 s (W24, W25) |
| Aggregation | the 8 tags summed into groups against a run of the groups: relative L∞ at most 1e-10 at 24 h, Float64; reported, since OD8 needs no bridge (approved 2026-09-24) | roundoff over a day's steps | not run |
| Cost, default mode, 8 + 8 tags | build at most twice the untagged build; step time at most twice the untagged step (approved 2026-09-24) | measured ratios at fewer tags, with room for 16 tags | build: D4 untagged 410 s (E44), with 8 energy tags 600 s (E73); step: 1.43× with 4 + 4 tags (W22) |
| Cost, copies at 8 | build within 4 h, both families' copies in one model (approved 2026-09-24) | the tested limit; 32 did not build in 4 h | TRMM, 8 water copies 699 s (W34); D4, 8 energy copies 3504 s (E73) |
| Cost, sphere | memory per rank and wall time within the M4 estimate below (approved 2026-09-24) | the owner budgets it | E75: 16.5 h, 500 GB, 24 ranks, 10 days at 10 levels |

**OD2's windows, per case: approved 2026-09-24, as drafted.** Startup ends at the first output after which the
parent's domain-mean tendency of `∫ρq_tot` (water) or `∫ρe_tot` (energy),
averaged over the output interval, stays below 10% of its largest value in the
first 6 hours for three outputs in a row. For a case with a source pulse,
startup also lasts until the pulse's source rate falls below 10% of its peak.
Each case's boundary is read from its untagged run before its first scored
run.

| case | startup (expected) | established flow | long run |
|:---- |:------------------ |:---------------- |:-------- |
| D4-W, DYCOMS RF02 1M, 24 h | about the first hour; E39 found 98% of the first hour's residual in the first step | from startup's end to 24 h | — |
| TRMM_LBA 0M and 1M, 6 h | until the rule's time; rain starts about 3 h (W26) | from startup's end to 6 h; the rain is scored here only if it starts after startup | — |
| The GCM-driven column, 3 h and 90 days | the first half hour: V-W8's energy residual was nearly all made then (W22) | to 1 day | days 1 to 90 |
| The WP4b held-out case | TRMM_LBA 1M, if its rain starts after startup; otherwise RICO 1M, 24 h | as the case gives | — |
| The sphere, 90 days | the first hour; E39b found the first step made most of the first hour's residual | days 1 to 10 | days 10 to 90 |
| DYCOMS 0M | the whole rain event, which ends within the first hour (W15) | — | — (not a held-out case) |

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
    records' lower bound stays as the interim until it lands.
  - **The WP4c gate's reading of OD3: confirmed as proposed.** Retention part
    1: the remainder above 0.02% of the water. Part 2: `led_inc` per tag above
    2% of the tag's inventory, taken as the difference between two runs. The
    per-tag intervention row's 2% is used here too.
  - **The mirrors' surface relaxation: by composition**, as built (#114).

### The owner's answers, later on 2026-09-25

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

### The execution order

Each step names the decisions it needs. An agent stops at a step whose
decision is open and asks the owner.

| Step | What                                                                                                                                                     | Needs          | State (2026-09-25)                                                                                                                                                             |
|:---- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |:-------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0    | Guard and records, no simulations: G4.16's interim refusal and its test; STATUS; the in-place edits; this register; the comparator-eligibility annotations on W29, E39, E76 and D4-W | —              | Done. The guard, extended to 1M, 2M and P3 (the owner, 2026-09-24), is draft PR #108 against `main` (`e55ae293`); its two integration jobs passed at `33eeb5cd`, before the 2M and P3 extension, which has passed its config tests only; PR CI covers the rest (`output/g416_guard/`) |
| 1    | G3 WP6 step 3, with the per-tag ledger (Insight 10)                                                                                                      | —              | Done: draft PR #109 on #103 (`claude/water-tags-wp6-step3`). Unit tests, 13 integration groups and the check script all pass (`output/wp6_step3/jobs/`) |
| 2    | W25 isolation at 30, 60 and 120 levels, centred and first-order: fixed-parent probes and the refinement test first, then full matched runs              | OD1, OD2, OD3  | Done 2026-09-25: jobs 13932703 to 748 scored against every rule (`output/w25i/`). Two P1 probes at 120 levels, first order, failed in the model (the README) |
| 3    | The audit-feasibility decision (WP9, OD8), water and energy copies at the intended tag counts; may run beside step 2                                    | OD1            | Decided (OD8): 8 water and 8 energy tags, copies at 8 as the direct audit where eligible, no aggregation bridge. 32 tags stay a WP9 cost item, not qualified                   |
| 4    | WP5b-C at the tag counts OD8 keeps; copies pass eligibility in each run before they serve as the audit                                                  | OD8            | A first build exists outside the pushed branches (G3_TODO, WP5b-C)                                                                                                            |
| 5    | WP5b-V's remaining arms: those without copies after step 2, default-against-copies arms after step 4; the explicit-1M follower stays opt-in unless it passes | step 2, step 4 | The same-atmosphere check is done and passes (W35). W33 stays a failure; the explicit-1M default is decided at M5 (the register's open choices) |
| 6    | The WP4c operator-decomposition gate, with the three-part retention rule; defer, don't delete                                                           | OD3            | Pre-registered 2026-09-25: `design/WP4C_GATE.md`, probe and score scripts, two configs. The trial configurations build on the login node. Its OD3 reading confirmed by the owner 2026-09-25. Scored (W40): `vdiff` and `diffusion_up` retained, none deferred. Both built on `claude/water-tags-leak-correction` (from #109) behind `water_tag_leak_correction`; validation pre-registered in `design/WP4C_CORRECTIONS.md`, not yet run |
| 7    | WP4b, its implementation only: the rain and snow tag fields and their diagnostics, with closure as an invariant. No held-out evaluation yet                | the owner's rain and snow decision (WP4b-D), decided 2026-09-25 | Unblocked 2026-09-25: three parts, gross flows. A separate agent builds stage 1 |
| 8    | WP9's cost qualification at the intended tag count, with WP4b's fields on, the comparator included; M4's ceilings fixed                              | OD3            | Unblocked 2026-09-25 (WP4b-D decided). At 8 tags (OD8); the aggregation test is no longer needed for qualification |
| 8a   | The fix of known issue 7: tagged water ends a run where the parent's water goes negative (site 23). Added 2026-09-24                                   | the owner's choice of option | Option A built (#112). The probe read (2026-09-25): it points to C. **Option C chosen 2026-09-25** and built (`claude/water-tags-negative-parent`); its validation pre-registered (the design note, section 8), jobs not submitted |
| 8b   | WP4b's validation, then default selection (M5): process-weighted same-state evidence and a held-out case that rains in established flow, within step 8's cost ceilings | step 8, OD2, OD3 | Unblocked 2026-09-25 (WP4b-D decided); follows step 8. The part of the former step 7 that produces M5 evidence |
| 9    | The water sphere under the revised long-run criterion                                                                                                   | OD6            | Waits. `g2_v2_sphere_n2` at 60 levels, 90 days, judged by the level it reaches (OD1, OD6); after step 8a. First a 1 to 2 day run at 60 levels, untagged and with 8 + 8 tags, measures its cost (the owner, 2026-09-24) |
| 10   | G4: G4.16's cross blocks (the refusal stays until they pass), G4.1 and G4.11's mirrors at the OD8 counts, G4.3 to G4.6 with offset-invariant scales, the G4.15 decision, G4.7 and G4.8 with startup windows and fixed-parent comparisons, the energy default | OD4, OD7       | OD4 decided (2026-09-24 and 2026-09-25; its accumulator being built); OD7 open. G4.16 (#113) and G4.1 and G4.11's mirrors (#114) built, their validations pre-registered and submitted (13944447 to 462) |
| 11   | The energy sphere, once its comparator, offset, cross-block, intervention and cost contracts are settled                                                | OD6            | Waits. The same sphere as step 9 (OD1, OD6)                                                                                                                                    |

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
