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

Each decision's current state is in
[ROADMAP.md's register](ROADMAP.md#the-decision-register), the single source.
This list names what is still open. Classified on 2026-09-25 against the
record; the answered and superseded entries are in the next section.

  - **OD7**, G4.15's rule for energy: same sign or |m|. Deferred by the owner
    on 2026-09-24, until the long runs can be scored at site 23.
    [Register](ROADMAP.md#the-decision-register)
  - ~~**Known issue 7: the choice among B, C and D.**~~ *Answered 2026-09-25:
    option C* (below).
  - ~~**R2, the Newton row, on D4-W.**~~ *Answered 2026-09-25: the row is
    revised* (below).
  - **WP4a's two points:**
      + known issue 4's Jacobian, either the pair of entries or the diagonal
        alone as a test;
      + where the copies' part of issue 4 goes.

    [G3T](G3_TODO.md#decisions)
  - **WP6's three points.** Step 3 took the conservative default for each
    ([design/GROSS_ACCUMULATORS.md](design/GROSS_ACCUMULATORS.md), 10.6):
      + whether a pre-WP6 checkpoint is refused or zero-filled (refused);
      + whether loss and τ move to WP4a and WP4b (not in WP6);
      + whether the transfer ledgers stay as they are or go per tag (as they
        are, with the per-tag ledgers beside them).

    [G3T](G3_TODO.md#decisions)
  - **The explicit-1M water default, at M5.** W33's verdict is decided (it
    stays a failure, W35 beside it; 2026-09-24). The default itself is decided
    at M5 under the contract. [G3T](G3_TODO.md#decisions)
  - **W21's surface rule in the first hour:** whether the plume's start
    should model the surface flux (plan 4.1, review S4). Rev. 2 sets the
    first-hour budget (OD3's provenance rows) but not this rule.
    [G3T](G3_TODO.md#decisions)
  - **G4.3 to G4.6's seven points** (raised 2026-09-25 with #120 and E86;
    the proposals are in `review/od4_restatement.md` and the design notes it
    names):
      + whether the register's interim rule should now say that values on the
        process records are estimates, not bounds (E84);
      + whether an aggregate intervention threshold applies to energy. At
        water's 0.5% a day, D4 (7.3%) and the sphere (2.6%) fail (E86);
      + `throughput_tolerance`'s levels: 5e-2 for `enthalpy_increment`, 0.3
        for `enthalpy`, none for `tracer`; or leave it off (#120);
      + water's warning default (1e-10) fires on every run with the follower,
        and a healthy D4-W day reaches 1.35e-4. Set a default per transport,
        or leave it?
      + whether A5 reads "its group's sum" as the partition's sum
        (`design/RESIDUAL_REPORT.md`);
      + a warning on the settling ratio: yes or no;
      + once G4.6 measures C4, share it as transport, or document its size.
        *Measured (E87):* 0.55% of the day's Θx on D4, and not in the
        residual.

    [G4T](G4_TODO.md)
  - **WP4b stage 1's points** (raised 2026-09-25 with #121 and W43; the
    design note's section 17):
      + whether each gross flow carrying its donor's composition over the
        step stands as the reading of section 9;
      + the rain and snow parts get no increment follower, since their
        implicit terms are their species' by construction, while section 6's
        table lists a mismatch for them;
      + the audit is always on with the key: should it get its own sub-key?
      + the hyperdiffusion correction is built, but no run exercises it yet;
      + `follow_water_tag_precipitation!` in the limiters and constraints is
        not in the parent-budget coverage registry (it writes tag fields
        only).

    [G3T](G3_TODO.md)

## Answered or superseded, moved from the waiting list (2026-09-25)

Each entry as it stood in the waiting list, classified. The dates are those
of the answers.

  - **Rev. 2's register, OD1 to OD6 and OD8.** *Answered* 2026-09-24; OD3's
    draft approved later that day. OD7 stays open (above).
    [Register](ROADMAP.md#the-decision-register)
  - **Known issue 7's fix, which option.** *Answered in part* 2026-09-24:
    option A now, then the probe. The choice among B, C and D stays open
    (above).
  - **OD4's throughput source** for the existing records. *Answered*
    2026-09-25: an exact per-tag, per-step accumulator; the process records'
    figure is the interim, an estimate: E84 found it 6% above the exact
    throughput on D4, so it is not a lower bound, and the direction of its
    error is not established. [Register](ROADMAP.md#the-decision-register)
  - **W33's verdict**, after the same-atmosphere check passed (W35).
    *Answered* 2026-09-24: W33 stays a failure. The default at M5 stays open
    (above).
  - **The sphere's numbers**, in the form G3_PLAN 6.1 fixes, before V-W11.
    *Superseded* by OD6 (2026-09-24: 90 days to saturation, its ceiling
    approved with OD3) and by the owner's short-run decision of 2026-09-24 (a
    1 to 2 day run measures the cost first).
    [Register](ROADMAP.md#the-decision-register)
  - **The default mode's cost budget**, proposed from V-W10's first
    measurements. *Answered* 2026-09-24 by OD3's cost rows (build and step at
    most twice the untagged, at 8 + 8 tags).
    [ROADMAP.md, "The OD3 thresholds"](ROADMAP.md#the-od3-thresholds-approved-2026-09-24)
  - **The prognostic fields of the rain and snow tags** (WP4b-D). *Answered*
    2026-09-25: the three parts, the gross flows, point 4 superseded by the
    WP4c gate. [ROADMAP.md, "The owner's answers, 2026-09-25"](ROADMAP.md#the-owners-answers-2026-09-25)
  - **The copies' repair over its bound** (W21). *Superseded* by rev. 2's
    comparator eligibility (OD3's comparator rows, 2026-09-24): a copies run
    whose repair exceeds 0.20% a day is not an eligible comparator, and
    provenance there is *not assessable*. W25's scoring applied it
    ([output/w25i/](output/w25i/README.md)).
  - **When to investigate V-W4's two breaks** (W25). *Superseded* by W25's
    isolation, rev. 2's step 2: pre-registered on 2026-09-24
    ([design/W25_ISOLATION.md](design/W25_ISOLATION.md)) and scored on
    2026-09-25.

The list as it stood before this classification, kept as written:

>   - **Rev. 2's register, OD1 to OD8**: the production envelope, the windows,
>     the thresholds, the energy scale, *not assessable* at M5, the sphere,
>     G4.15, and the audit's feasibility. ~~**Waiting.**~~ Answered on
>     2026-09-24 (below), except:
>       + ~~**the OD3 draft**, with OD2's levels, OD6's ceiling and the 60-level
>         stretching: **waiting for approval**. Step 2 waits for it.~~
>         **Approved** 2026-09-24 (below).
>         [ROADMAP.md, "The OD3 thresholds"](ROADMAP.md#the-od3-thresholds-approved-2026-09-24)
>       + **OD7**: **open, deferred**.
>     [ROADMAP.md, "The decision register"](ROADMAP.md#the-decision-register)
>   - **Known issue 7's fix**, one of the options in
>     `design/NEGATIVE_PARENT_WATER.md`, before the sphere. ~~**Waiting.**~~
>     A chosen 2026-09-24 (below). **Waiting:** the choice among B, C and D,
>     after the probe.
>   - ~~**OD4's throughput source** for the existing records: the process records
>     as a lower bound, or a new per-step accumulator. **Waiting.**~~ Decided
>     2026-09-25 (below): an exact accumulator.
>     [review/od4_denominator_audit.md](review/od4_denominator_audit.md)
>   - ~~**W33's verdict**, after the same-atmosphere check passed (W35).
>     **Waiting.**~~ Decided 2026-09-24 (below).
>     [G3T](G3_TODO.md#wp5b-v-the-explicit-1m-default)
>   - **The sphere's numbers**, in the form G3_PLAN 6.1 fixes, before V-W11.
>     **Waiting.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
>   - **The default mode's cost budget**, proposed from V-W10's first
>     measurements, set before V-W11. **Waiting.** [G3_PLAN 6.1](G3_PLAN.md#61-budgets-fixed-before-the-runs)
>   - ~~**The prognostic fields of the rain and snow tags**, settled in design note
>     WP4b-D and its review. Recommended: the non-precipitating, rain and snow
>     parts. Three further points of the note's section 15 go with it.
>     **Waiting.**~~ Decided 2026-09-25 (below): the three parts, gross flows.
>     [G3T](G3_TODO.md#decisions)
>   - **WP4a's two points:**
>       + known issue 4's Jacobian, either the pair of entries or the diagonal
>         alone as a test;
>       + where the copies' part of issue 4 goes.
>
>     **Waiting.** [G3T](G3_TODO.md#decisions)
>   - **WP6's three points:**
>       + whether a pre-WP6 checkpoint is refused or zero-filled;
>       + whether loss and τ move to WP4a and WP4b;
>       + whether the transfer ledgers stay as they are or go per tag.
>
>     **Waiting.** [G3T](G3_TODO.md#decisions)
>   - **The copies' repair over its bound, and the surface rule in the first
>     hour** (W21). **Waiting.** [G3T](G3_TODO.md#decisions)
>   - **When to investigate V-W4's two breaks:** the partition at 120 levels,
>     and the copies under first-order upwinding (W25). **Waiting.**
>     [FINDINGS W25](FINDINGS.md)

## 2026-09-25

  - **The owner's answers, later on 2026-09-25.** **In force.**
    [ROADMAP.md, "The owner's answers, later on 2026-09-25"](ROADMAP.md#the-owners-answers-later-on-2026-09-25)
      + **Known issue 7: option C.** The partition tags partition
        `max(ρq_tot, 0)`; the follower takes its increment; the repair, the
        rescale and the copies' repair aim at it; the negative part is the
        named field `q_tag_negative`. Validation pre-registered in
        [design/NEGATIVE_PARENT_WATER.md](design/NEGATIVE_PARENT_WATER.md),
        section 8.
      + **R2: measure three and four Newton iterations first** (job
        `13944802`). The threshold stays. The choice between raising OD1's
        count and revising the row waits on that result. *Done:* see the
        next entry.
      + **R2: the Newton row is revised** (after W38 and W41). The parent's
        `E` levels off near 2e-3 (1.2e-2, 4.1e-3, 2.3e-3, 1.9e-3 with 1 to
        4 iterations). `E` is always reported. The row gates only verdicts
        that compare runs with different parents (full-run comparisons,
        provenance against copies from a separate run). Same-parent verdicts
        go ahead. Nothing is rescored; W38's R2 verdicts are read under the
        revised scope, where every W25 verdict is same-parent except R7.
        **In force.** [ROADMAP.md, the OD3 table](ROADMAP.md#the-od3-thresholds-approved-2026-09-24)
      + **A persistent parent-validity flag, B and D together.** B,
        `negative_water_void`: a latch per family, key
        `negative_water_void_above` (default 1e-4, water only), set at the
        checks when the raw `ρq_tot`'s `N / ∫ρq_tot` passes the level, with
        the ratio in its own column and the latch carried through
        checkpoints. It reads OD3's negative-water row online; offline
        scoring stays the reference. D: a per-cell cumulative negative-water
        ledger, updated every accepted step and carried through restarts.
        Built by another agent on a branch stacked on #116, which also makes
        the water audit's `nonpositive_mass` read the raw parent again
        (under option C it read 0 by construction). **In force.**
        [ROADMAP.md, the OD3 table](ROADMAP.md#the-od3-thresholds-approved-2026-09-24)
      + **The per-tag intervention row applies to all tags** (from the
        review of #109), with two denominators: a pure region tag
        `retained / ∫tag`, with a positive inventory as precondition; a
        source-labelled or signed tag `retained / ∫|tag|`, the absolute
        burden. Below the small-tag bound (2e-4 of the parent, OD4 units for
        energy) "not applicable", reported explicitly. Both ratios and a
        parent-scale ratio are reported. Built on #109 by another agent.
        **In force.** [ROADMAP.md, the OD3 table](ROADMAP.md#the-od3-thresholds-approved-2026-09-24)

  - **The owner's answers of 2026-09-25** (through the parent session).
    **In force.**
    [ROADMAP.md, "The owner's answers, 2026-09-25"](ROADMAP.md#the-owners-answers-2026-09-25)
      + **WP4b-D:** the three parts as the note names them. `ρq_tag_<name>`
        holds the non-precipitating part, beside `ρq_rtag_<name>` and
        `ρq_stag_<name>`, behind `water_tag_precipitation: true`, 1M only.
        The microphysics by the gross flows, the net-flow rule the fallback
        where per-process terms are not available. The note's section 15,
        point 4 (4.2's rule restated), is superseded by rev. 2's WP4c gate.
        Steps 7, 8 and 8b are unblocked; a separate agent builds step 7,
        stage 1. [design/RAIN_SNOW_TAGS.md](design/RAIN_SNOW_TAGS.md)
      + **OD4's quantity:** an exact accumulator, per tag and per step, of the
        gross source into each energy source tag, carried through restarts,
        as WP6 did for the ledgers. The process records' figure is the
        interim until it lands. *Corrected after E84:* an estimate, not a
        lower bound; a per-process comparison against the accumulator is
        open on #115.
        [design/GROSS_ACCUMULATORS.md](design/GROSS_ACCUMULATORS.md)
      + **The WP4c gate's reading of OD3, confirmed:** part 1, the remainder
        above 0.02% of the water; part 2, `led_inc` per tag above 2% of the
        tag's inventory, taken as the difference between two runs. The
        per-tag intervention row's 2% is used here too.
        [design/WP4C_GATE.md](design/WP4C_GATE.md)
      + **The energy copies' surface relaxation: by composition**, as built.
        [design/ENERGY_COPY_MIRRORS.md](design/ENERGY_COPY_MIRRORS.md)

## 2026-09-24

  - **The owner's answers, later on 2026-09-24.** **In force.**
    [ROADMAP.md, "The owner's answers, later on 2026-09-24"](ROADMAP.md#the-owners-answers-later-on-2026-09-24)
      + OD3: approved as drafted. Every row of the threshold table is a
        scoring threshold from 2026-09-24, its numbers unchanged. Step 2 is
        unblocked.
      + OD2's window rule and OD6's ceiling: approved as drafted.
      + The sphere's cost: a 1 to 2 day run of the 60-level sphere on the
        proposed grid, untagged and with 8 water and 8 energy tags, measures
        step time, memory per rank and the ranks needed, before the 90-day
        run is planned. After step 8a, within step 9.
      + Known issue 7: option A now (the tags cannot end a run), then the
        probe, then a choice among B, C and D, which the parent session
        brings back.

  - **The owner's answers to rev. 2's register** (evening, through the parent
    session). **In force**, each as recorded in
    [ROADMAP.md, "The owner's answers"](ROADMAP.md#the-owners-answers-2026-09-24):
      + OD1: production is `g2_v2_sphere_n2` at 60 levels instead of 10, the
        rest of that configuration unchanged (`h_elem` 6, `z_max` 30 km,
        `dt` 20 s, ARS222, two Newton iterations, 1M implicit, the default
        SGS reconstruction). W25's 60-level misses are the main case. The
        stretching was not set; the agent proposes one.
      + OD2: windows are physical. Startup ends when the parent's
        domain-mean tendency, or the source pulse, falls below a set level;
        the levels are part of the OD3 draft.
      + OD3: the agent drafts, the owner approves. No run is scored before.
      + OD4: the cumulative gross energy the sources put into the tags over
        the same window. Also audit the existing E-records' denominators.
      + OD5: *not assessable* blocks M5 for that configuration unless the
        Insight 10 tests pass their OD3 thresholds; then it qualifies as
        "provenance bounded, not validated".
      + OD6: the sphere runs 90 days to saturation and is judged by the level
        observed, not by projection. A ceiling relative to the smallest
        analysed tag is still needed. The 90-day, 60-level sphere's cost goes
        into M4 as an estimate.
      + OD7: to be decided by the registered rule. The analysis is done: by
        that rule same sign is kept (both criteria hold for energy at both
        sites and for water at site 26; water at site 23 breaks the budget
        under both rules). The owner **deferred** the decision, for example
        until the site 23 defect is fixed and site 23 can be scored. **Open.**
      + OD8: 8 water and 8 energy tags; copies at 8 are the direct audit where
        they pass eligibility; no aggregation bridge for qualification; 32
        tags stay a WP9 cost item and are not qualified.
      + W33 stays a failure, W35 beside it. The explicit-1M water default is
        decided at M5 under the contract.
      + The site 23 tag crash is a defect, a diagnostic ending a run that
        upstream completes, fixed before the sphere. Known issue 7; the fix's
        option is the owner's.
      + The per-tag ledgers stay off by default and are on in every
        validation and qualification run. The fraction uses the tag's current
        inventory, with the absolute value beside it.
      + 2M and P3 stepped explicitly are refused until measured, for both
        families' followers. The water tags already refuse 2M and P3.
      + Draft PRs when green; the parent session opens them.

  - **Rev. 2 of the work plan** ("Simulation-results synthesis and in-place
    work-plan revision"). The owner's plan decides, in force from its step 0:
      + results are reported by the acceptance contract's verdicts; closure
        never substitutes for provenance;
      + copies are a provenance comparator only where they pass eligibility
        in that run; otherwise provenance is *not assessable*;
      + W33 stays a failure, and no result from a different parent
        atmosphere is a tag-error reference;
      + `enthalpy_increment` with 1M stepped explicitly is refused until
        G4.16 passes, with an explicit opt-in for development runs (G4.16's
        open question);
      + M4 stays before M5; the audit's feasibility (OD8) is decided before
        WP5b-C and G4.1/G4.11;
      + WP4c's corrections pass an operator-decomposition gate; the ones not
        retained are deferred, not deleted;
      + the sphere's "plateau after day one" is replaced by OD6's ceiling and
        growth bound.

    **In force.** Its open decisions are OD1 to OD8.
    [ROADMAP.md, "Rev. 2 of the work plan"](ROADMAP.md#rev-2-of-the-work-plan-2026-09-24)
  - **The followers' placement rule (same sign or |m|) is decided after long
    runs**, not after a day. G4.15 is split: G4.15a (the partition check and
    the audit names) goes ahead; G4.15b (the same-sign rule for energy) waits.
    The long runs' setup is approved: the GCM-driven column, 90 days, sites
    23 and 26, `design/INCREMENT_RULE_LONG_RUNS.md`. **In force; running.**

  - **Batch 3 approved (about 15:45):** WP5b-V, WP4a-V, WP5b-C, WP5b-P, the
    WP9 cost items (the plume, the copies' build time) and G4.15, done as WP
    PR batches. Where a criterion was left to the owner (WP4a-V's "material",
    WP5b-P's per-source bound), the design note proposes a value, fixed in the
    record before the runs; the owner may change it before a merge. **In
    force.**

  - **The explicit-1M path under the follower: the tags get the parent's
    sedimentation cross blocks**, not a route through the bottom face. Until
    then the follower is refused there (#102). **In force; in progress.**
    [G3T](G3_TODO.md#decisions), the owner's review of #102, point 3
  - **With 1M stepped explicitly the follower stays opt-in** until a
    precipitating case on a timestep and Newton ladder passes (WP5b-V). The
    owner's review of #105, finding 2, offered this or the evidence first.
    **In force** (#105 at `c446fe91`).
  - **#104's scope excludes known issue 4's Jacobian switch** (now WP4a-J)
    and the test of the default mode's reconstruction against a converged
    reference (WP4a-V), each with criteria in G3_TODO. The owner's review of
    #104, findings 2 and 6, asked for the boundary. Proposed in the reply;
    the owner may object.
  - **WP5's default transport under EDMF is applied.** `increment` is the
    default in the default mode under prognostic EDMF, where the
    configuration supports it; `tracer` elsewhere and with copies. The
    owner's review of #102 asked for G3_PLAN 4.3's rule to take effect.
    **Done** (#102 at `a3a23d80`).
  - **The owner's review of #102, points 2 and 4 to 7, as proposed:**
      + the partition tolerance at 100 rounding units;
      + the column's total left out only where the mismatch has its sign;
      + the net-over-time audit columns renamed;
      + the docs qualified;
      + the W24 evidence pinned under the tag `evidence/w24`.

    **Done** (#102), W28.
  - **A checklist runs at each WP milestone and each goal's end**: STATUS,
    `output/`, FINDINGS, RUNS, the TODO file, reviews, and a push.
    **In force.** [README.md, "Closing a work package or a goal"](README.md#closing-a-work-package-or-a-goal)
  - **The session goal extends** (late on 2026-09-23 and early on 2026-09-24):
      + WP5;
      + WP4b-D, the rain and snow tags' design note;
      + Batch 2: V-W8, WP6, WP4a and V-W4.

    Jobs within these have standing approval. **In force.** Memory:
    `session-goal-wp0-wp1.md`

## 2026-09-23

  - **The session goal extends to WP3** (18:20): draft PR-W3 with the switch,
    both modes, the restart guard, the refusals lifted for one updraft, bound
    activation, leak diagnostics and the CI group, reviewed and green; V-W3
    validates it. **In force.** Memory: `session-goal-wp0-wp1.md`
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
