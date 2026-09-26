# G4: the energy source tags, after G3

G4 brings the energy source tags and the process records to operation, with
what G3 learns about the water tags. It waits for G3, except the job session's
work on PR #95 and the ladder at #95's merged head. E76 is the ladder at
`dcf7d086`. The roadmap is
[ROADMAP.md](ROADMAP.md). What G3 hands over, and what is energy-specific, is
in [G3_PLAN.md, section 9](G3_PLAN.md#9-g4-the-energy-source-tags-with-what-g3-learns).

This file holds:

  - G4.1 to G4.14, moved from G3_TODO.md on 2026-09-23 (only their layout and
    pointers changed);
  - under each, the open energy items of the former OPERATIONAL_TODO (sections
    2 to 7 and the Plan, A to D) and of the original FINDINGS section 7 (its
    live queue is [FINDINGS section 13](FINDINGS.md#13-what-is-not-established))
    that belong to it;
  - the energy items within M1 to M5 that no G4.n takes up yet;
  - the items that G3 takes up;
  - the prepared designs of section 7 of the former OPERATIONAL_TODO.

Each item keeps its original ID. The register ID from
`review/register/items.csv` follows in code font. "OT" is the archived
[OPERATIONAL_TODO.md](archive/2026-09-23/OPERATIONAL_TODO.md), and "FQ" is an
open question from the archived FINDINGS' section 7, "What is not
established". The live queue is
[FINDINGS section 13](FINDINGS.md#13-what-is-not-established). Open items beyond G4 (M6 to
M8, upstream, CI, outside) are in [BACKLOG.md](BACKLOG.md).

The full re-check of the energy findings moves to the start of G4, by the
owner's decision of 2026-09-23 (CONDENSE_PLAN decision 1). It starts from the
22 rows of `review/register/conflicts.csv`: 11 are settled in FINDINGS §12, and
11 were found while condensing (marked H4-B) and stand unmarked in FINDINGS
until then. Among them: ±30,920 against ±30,915 J kg⁻¹ (E27 and E35 against
E46 and E48); 17 ms against 13.7 and 14.7 ms (E44b against E44c); and E58's
restart differences, which it calls the same as E54's but which differ by
orders of magnitude.

## G4.1 to G4.14

These items come from the former G3 and from plan section 9. They wait for
G3, except where the job session runs them now.

*Rev. 2 of the work plan (2026-09-24)* changes G4.1, G4.3 to G4.8, G4.11,
G4.15 and G4.16 in place, each marked "rev. 2". Its step 10 orders G4:
G4.16's cross blocks, then G4.1 and G4.11's mirrors at the tag counts OD8
keeps, G4.3 to G4.6 with offset-invariant scales (OD4), the G4.15 decision
(OD7), G4.7 and G4.8, and the energy default. The energy sphere, G4.13, comes
last (OD6). ROADMAP.md, "Rev. 2 of the work plan", holds the contract and the
register.

*Scope added (provenance pathway, 2026-09-26, pending OD9 to OD14):* the
provenance pathway, [PROVENANCE_PATHWAY.md](PROVENANCE_PATHWAY.md), applies
in OD4's units with `c` stated. `c` is a convention: it is bracketed by the
`c`/2`c` pair and never bounded. On D4 the pathway expects Val-2 (bounded) at
most, since energy has no passive truth and its copies are ineligible (E84).
What G4 takes from G3 is in the pathway's section 10.

### G4.1 #95's follow-ups

D1 with D3 closes when #95 merges. U5, a clear error when the tag list
changes across a restart.

  - **B12, D1: the user guide into the docs, with D3** (`OT-B12`; OT section 2,
    item 12; also Plan C.4, `OT-PC4`). #95 carries the guide,
    `docs/src/energy_source_tags_guide.md`.

  - **D3, the caveats** (OT section 3, "With D1"): C1 and C4, what is
    untested, stitching `e_src_fix` across restarts, choosing `c`, and ice
    passing provenance upward (E41).

  - **The energy copies' missing mirrors** (WP3's numerics review, N5;
    `review/agent_reviews/wp3_numerics_review_2026-09-23.md`). #95's updraft
    copies get nothing of what `mseʲ` gets and a tracer does not: the surface
    enthalpy flux into the updraft (`surface_flux.jl`, the counterpart of the
    water's fifth mirror, W20), the radiation into `mseʲ`, the buoyancy and
    pressure-work terms. List every writer of `mseʲ`, as the review listed
    those of `q_totʲ`, and mirror or bound each.
    *Scope added (rev. 2, 2026-09-24):* all the `mseʲ` source mirrors are
    complete before energy copies serve as the audit in held-out cases, at
    the tag counts OD8 keeps (with G4.11). Until then the default-against-
    copies `sfc` gaps of E76, and of E73 at the baseline, are labelled
    "comparator not eligible". Rev. 2 also names E39 here; E39 measures the
    audit's closure against the Newton count and has no copies, so the label
    does not apply to it. *2026-09-24 (OD8):* the tag count is 8, and copies
    at 8 are the direct audit where they pass eligibility.
    *2026-09-25:* the inventory and the design,
    [design/ENERGY_COPY_MIRRORS.md](design/ENERGY_COPY_MIRRORS.md). Four
    writers of `mseʲ` had no mirror: the surface enthalpy flux into the
    updraft, the surface relaxation, RRTMGP radiation and the 0M rain-out.
    Built on `claude/energy-copies-mirrors` (from `main` at `3eac4d44`; not
    pushed), with a residual diagnostic `e_src_copy_res` for what is not
    mirrored. #114. The surface relaxation shares the buoyant excess by
    composition, as the owner decided on 2026-09-25. The validation on D4 at 8 tags is pre-registered
    (`configs/g411_d4_*.yml`, `analysis/increment/g411_eligibility.py`).
    *Run 2026-09-25 (jobs `13944458` to `13944462`; FINDINGS E83, the parent
    session's):* the energy copies are not an eligible comparator on D4.
    Their repair is 2.9% of the throughput a day with the mirrors and 2.6%
    without, against 0.20%, on the process records' figure. *E84 (the parent
    session's), on the exact throughput:* 3.1% and 2.7%. The records' figure
    was 6% above it, so E83's percentages were estimates, not upper bounds.
    Their own residual (1.1e-5) and refinement
    (0.65) pass. The mirrors bring the modes closer (`sfc` L∞ 2.5% to 0.86%).
    Open: what makes the copies' repair; provenance against them stays *not
    assessable* on D4.
    *Scope added (provenance pathway, 2026-09-26):* port PX5's reading (the
    filter's gross against the repair's, by level and `dt`) to the energy
    copies.

  - **The region masks' width in the docs** (decision 10 of 2026-09-18,
    `OT-regionmask`): 2° stays. Say that a mask narrower than the grid spacing
    makes the repair trade, and that a 10° mask avoids it on coarse grids
    (E48).

  - **U5** (`OT-U5U6`; OT section 4): a clear error when the tag list changes
    across a restart. C2 covers most of it. G3 WP3 does the same for water.
    U6, the other half of that row, is in BACKLOG.md (M6).

  - **What the user guide draft has that #95's pages do not.** The draft is
    [archive/2026-09-23/USER_GUIDE_DRAFT.md](archive/2026-09-23/USER_GUIDE_DRAFT.md)
    (2026-09-11). It was checked on 2026-09-23 against #95 at `dcf7d086`:
    `docs/src/energy_source_tags_guide.md` and its reference
    `energy_source_tags.md`. Where `process_record.md` or
    `tracer_configuration.md` on #95 covers a point, it is not listed. Not
    covered:

      + UG1. A support table by configuration: what runs, what has been
        measured, and what is refused, for 0M, 1M, dry, 2M, P3, `edonly_edmfx`
        and `prognostic_edmfx`. In particular, a dry run has never been measured
        for this family, and P3 has gaps in the parent's own sedimentation
        beyond the 2M gate. The guide lists only 2M among the untested ground.
      + UG2. The smallest offsets that made `E` positive: 45.4 kJ/kg on the
        DYCOMS column and 100.4 kJ/kg on the moist sphere (E6). The refusal
        message quotes them; the pages do not.
      + UG3. What the options cost: three tags with an hourly check, 1.32× a
        column (T4); a check every step dominates everything else (T2, T3); the
        offset, nothing measurable (T7); the repair, about 1% (T8); the
        `enthalpy` audit, about 5% per step (E34). And the advice that follows:
        check hourly or daily, never every step, since each distinct tag set is
        a new model type and a full compile (T1).
      + UG4. Output advice: write `ta` in one run of a pair and check that it is
        bit for bit the other's; `output_default_diagnostics: false`; sample the
        ledgers instantaneously, since they are running sums.
      + UG5. A source tag cannot show where its process removed energy. Where
        radiation cools most on the DYCOMS column, the radiation tag holds
        0.004 J/kg against a record of −20,566 J/kg (E22). To see cooling, read
        the record.
      + UG6. How to read the repair's ledger. The repair keeps the partition's
        sum, so `e_src_res` is the same with it on or off (E35). The region tags'
        ledgers add to zero in each cell, except where every tag is set to zero.
        An overlay's ledger only grows. Large region ledgers mean large transport
        undershoots (E27, E35).
      + UG7. The region masks' width, as in the item above (E48).
      + UG8. `gross_relative` shrinks as `c` grows, for the same miss (E15). So
        across runs with different offsets, compare `gross_residual`. The guide
        says the offset enters the denominator, but not this advice.
      + UG9. The initial-energy check: `<region> − new_<region>` is what was in
        a region at the start, and on a column its integral can only fall (E21).
      + UG10. Which check to trust where: closure residual, form A pointwise,
        form A integrated and form B, on a column and a sphere, under `tracer`
        and `enthalpy`. In particular, form B is not available on a sphere,
        because the lat-lon output gives no domain integral. And E38's global
        integrals are approximate, with a hydrostatic density on the remapped
        grid. The reference gives the audit's numbers but not this table.
      + UG11. A table of the startup messages, with what to do about each, and
        the full list of refusals at startup: an offset or a transport without
        tags, a closure check without its family, a family with only overlays,
        a tag named `res`. The reference mentions some warnings in passing.
      + UG12. The open part of the residual under `tracer` on a cold column: a
        zero-sum 3.7e-3 in an hour, not from vertical diffusion (E42, E42b), with
        pressure work in the vertical advection as the next candidate. This may
        not matter under `enthalpy_increment`; the guide could say so either way.
      + UG13. A tool for forms A and B. The draft pointed to
        `experiments/tag_closure/analysis/c5_process_closure.jl`. The reference
        says the model does not compute them, and names no script.

    The draft's other points are covered, or no longer hold: its EDMF refusal
    (C1b and #95 replaced it), "grid-scale only" (the exchange and the copies
    replaced it), and `enthalpy` alone needing the offset (U1 now requires it
    always). Its ten proposed fixes to existing pages were all made in #69,
    #70, #72 and #74, or needed no change.

### G4.2 The early-warning probe, looking back

Synergy 1: does `increment_left` flag V2's one-iteration collapse against the
two-iteration run?

  - **Synergy 1, the increment ledger as a diagnostic of the parent's own
    solver** (`OT-SYN1`; OT section 7, prepared). Its prepared design is at the
    end of this file.

### G4.3 Claim contracts

Claim contracts for energy source tags, process records and the parent-budget
ledger.

*Scope added (provenance pathway, 2026-09-26, pending OD11):*

  - [ ] The energy rule classification for OD11, as in the pathway's
    section 4.
      + Definitional: `c`, donor loss, the masks, the `sub` tag's subsidence
        and radiation's granularity.
      + Assumed: the exchange and θ, the repair, the follower's placement,
        the copies' surface relaxation (mirror M2 of
        `design/ENERGY_COPY_MIRRORS.md`) and the upward ice branch.
      + A gap: `C4`'s per-tag outflow.
  - [ ] The `U` row from `fixgross`, the repair's gross (factor 2).

*Scope added (rev. 2, 2026-09-24), for G4.3 to G4.6:* these items refer to the
acceptance contract in ROADMAP.md and do not restate it. Process records stay
apart from the stored source provenance: a source tag cannot show where its
process removed energy (E22). Every energy percentage is restated against an
offset-invariant scale (OD4). The first step is an audit of the denominators
of the existing E-records, E39, E62 to E66, E73 to E76, E79 and E80 first.
*2026-09-24:* the OD3 energy rows (closure, small tags, the comparator's
repair, in OD4 units) are approved with the rest of the table.
*Set on 2026-09-24 (OD4):* the scale is the cumulative gross energy the
sources put into the tags over the same window. The audit's first pass sorts
the records' denominators into four classes and restates no number yet
([review/od4_denominator_audit.md](review/od4_denominator_audit.md)). The
throughput needs the process records, then taken as a lower bound, or a new
per-step accumulator; which one is the owner's. *Decided 2026-09-25 (the state and
the interim are in [the register](ROADMAP.md#the-decision-register)):* an exact
per-tag, per-step accumulator, carried through restarts; the process records'
figure is the interim. Built on `claude/energy-source-throughput`
([design/GROSS_ACCUMULATORS.md](design/GROSS_ACCUMULATORS.md), section 11).
*Corrected after E84 (2026-09-25):* that interim is an estimate. On D4 it came
out 6% above the exact accumulator, so it is not a lower bound, and a
percentage on it is not an upper bound. The direction of its error is not
established. A per-process comparison against the accumulator is open on #115.
*Decided 2026-09-25 (review of #109; the register):* OD3's per-tag
intervention row (2%) applies to every energy source tag too: a pure region
tag against `∫tag`, with a positive inventory as precondition; a source tag
against `∫|tag|`. Below the small-tag bound, 2e-4 of the parent in OD4 units,
"not applicable", reported explicitly. Both ratios and a parent-scale ratio
are reported. Another agent builds it on #109.

  - [ ] **The process records against OD4's accumulator, per process** (#115,
    after E84). The records' sum of the four source processes came out 6%
    above the exact per-tag throughput on D4. Either the records count
    something the tags do not take, or the accumulator misses a source.
    Compare them per process on one run, and say which.

*2026-09-25, done on `claude/plan-rev2-g4`:*

  - [x] The claim contracts:
    [design/G4_CLAIM_CONTRACTS.md](design/G4_CLAIM_CONTRACTS.md). The tags
    claim stored provenance, the records what each process did, the
    parent-budget ledger its levels 1 to 4 (not assessable under EDMF). Every
    energy percentage names its scale.
  - [x] The restatement, [review/od4_restatement.md](review/od4_restatement.md),
    from the runs' own output (`analysis/increment/od4_restate.py`). Nothing
    rerun. On D4 the records' interim differs from the exact throughput by 6%
    (E84), so a value on it is an estimate, not a bound. On OD4's scale the
    closure verdicts change for the `enthalpy` audit, D1 under `tracer` and
    the explicit hour without G4.16's blocks (fail); the prototype and the
    sphere pass. The default's repair, never scored, is 7.3% of Θx a day on
    D4. E80, E81 and E39b cannot be restated without a rerun. Proposed
    FINDINGS entry: E86 (proposed as E85 in the review's section 6;
    E85 went to the ledger-ratio test).

### G4.4 The residual report

Rate and settling forecast (synergy 4), vertical and local maxima, headroom
(U9), overlay bounds (A5).

  - **Synergy 4, the closure check as a forecast** (`OT-SYN4`; OT section 7,
    prepared). Design at the end of this file.
  - **U9, the offset's headroom in the closure table** (`OT-U9`; OT section 4;
    also Plan A.4, `OT-PA4`): a minimum of `e_tot + c` reduced across
    processes, and optionally an `abort_above` for `nonpositive_fraction`.
  - **A5, an overlay-bound diagnostic** (`OT-A5`; OT section 4): the mass
    fraction where an overlay is negative, and where a member exceeds its
    group's sum.
  - [x] *2026-09-25:* designed in
    [design/RESIDUAL_REPORT.md](design/RESIDUAL_REPORT.md) and built on
    `claude/energy-claims-budget` (#115 with #112's commit; draft PR #120): the residual's
    own source ledger `e_src_led_src_res` (the flush, exact per step), the
    forecast columns, the local and vertical maxima, U9's headroom in the
    closure table (no abort, under #112), A5 read against the partition's
    sum. Unit tests pass on the login node (section 5 of the note). [ ] The
    integration group `tagging_water_increment`, a compute-node job (47 min
    for #115's run of it).

### G4.5 Warnings, abort rules and acceptance kept apart

For both families' closure checks. U2's calibration.

  - **B11, calibrate U2's tolerance per transport** from V2 and V3, and add the
    warning (`OT-B11`; OT section 2, item 11; also Plan C.4, `OT-PC4`).
  - [x] *2026-09-25:* [design/CLOSURE_LEVELS.md](design/CLOSURE_LEVELS.md).
    The four levels kept apart for both families; acceptance scored only by
    `analysis/evidence/closure_verdict.py`, with its tests. B11: the
    per-transport defaults stand, 50 times above V2 and 170 above V3
    (`analysis/increment/u2_calibration.py`). A warning in OD4 units,
    `throughput_tolerance`, off by default; its levels are the owner's.

### G4.6 The D4 process budget

With every record and the ledger (synergy 6, C4's `c Δρ`, repair never a
parent source). The offline EDMF column budget.

  - **Synergy 6, one combined budget of records, ledger and repair**
    (`OT-SYN6`; OT section 7, prepared, revised after the review of PR #98). A
    new question with an acceptance test set in advance. It does not explain
    E23's remainder, which E26 settled. Design at the end of this file.
  - [x] *2026-09-25, pre-registered before any run:*
    [design/D4_PROCESS_BUDGET.md](design/D4_PROCESS_BUDGET.md), with C4. Three
    D4 days, `configs/g46_d4_*.yml`, scored by
    `analysis/increment/process_budget.py` (tested on synthetic runs,
    `test_process_budget.py`). The three configurations build and take two
    steps on the login node at `1cc40e23` (`analysis/increment/g46_build_check.jl`,
    all checks pass; the budget's build 889 s, the untagged twin's 262 s;
    `output/g46/`). [x] The jobs, from the run tree
    `../ClimaAtmosResiDyn-g46-run` at `0164c2fd` (the record with
    `claude/energy-claims-budget`), submitted 2026-09-25: `13975411`
    (`g46_d4_budget`), `13975417` (`_2c`), `13975419` (`_untagged`); #120's
    increment integration test `13975420` (153/153). [x] Their score
    (E87): parity holds; A2, A3, A4 pass; A5 fails. C4, `c·M_U` = −1.15e5
    J/m² a day (0.55% of Θx), does not land in the residual (28 J/m²).
  - **C4, `c·Δρ` from processes the tags do not bracket**: vertical diffusion,
    sponges, hyperdiffusion, EDMF, LES (`OT-C4`; OT section 3). Measure it,
    then share it as transport or document its size.
    *Scope added (provenance pathway, 2026-09-26):*
    the committed process budget gives `C4`'s size from the `c`/2`c` pair:
    `c·M_U` is −1.15e5 J/m² a day, 0.55% of the throughput (E87,
    `output/g46/process_budget.txt`). The records' estimate printed beside it
    (+1.06e4 J/m²) has the opposite sign. Where `C4` goes, per tag, needs a
    bottom-face outflow probe (Fid-2, priority 3).
  - **If G4.6 names them, these close too.** Otherwise they stay open for a
    later goal (ROADMAP, M2, "later"):
      + open question 1: what makes D1's zero-sum gross residual (E42, E42b).
        Candidate: pressure work in the grid-mean vertical advection under
        tracer transport (`OT-Q1`; OT section 6; the same question is FQ-11,
        `FQ-11`). An audit twin of D1 would test it (Plan D.2, `OT-PD2`);
      + open question 2: what the sphere's remaining 17% of the audit's
        first-hour residual is (E39b): 4.24e19 J at 1 h, made in the first step
        (`OT-Q2`; FQ-17, `FQ-17`).

### G4.7 The energy reference suite

  - the R2 ladder (the job session's runs, redone at #95's merged head);
  - 60 and 120 levels, and Newton 4 and 10;
  - a Float64 twin;
  - the cold precipitating column;
  - a forced column without EDMF.

State on 2026-09-23: the job session reran the ladder's default runs at
#95's head `dcf7d086` (jobs `13782601` to `13782605`) and recorded the result
as E76 (`8726d2cb`, ported to the record branch as `eec7f363`). #95 has not merged yet, so the
ladder at the merged head is still to do.

*Scope added (rev. 2, 2026-09-24), for G4.7 and G4.8:* each reference case
gets a startup or source-pulse window with boundaries fixed beforehand (OD2),
fixed-parent trial-step comparisons where tag numerics are isolated, and the
two first-step probes of Insight 4: the first step fully converged, and the
tags started after it. E39 found that 98% of the audit's first-hour residual
is made in the first 10 s step. Full-run comparisons stay, reported as
configuration outcomes. They run after G4.16, the mirrors and OD7.

*Scope added (provenance pathway, 2026-09-26):* PX15 (the energy follower's
split) and PX10 (the energy repair on and off) come before G4.7. The energy
pulse inherits PX13's surface bracket; energy has no passive truth.

### G4.8 A surface pulse, and convection switched on and off, for energy

### G4.9 Alternative placements of the increment correction on a shared parent

  - **The attribution path, question 3** (`OT-PA3`; Plan A.3): whether the
    correction may bring `e_src_res` to rounding by construction. The owner
    decided on 2026-09-19 to keep it as built (DECISIONS.md). G4.9 tests the
    alternatives.

*Scope added (provenance pathway, 2026-09-26):* the placements are read as `L`,
the spread between rules that both close. They are an input to OD7, not a
decision.

### G4.10 The offset sweep (U8), and a check for leaving the tested regime

  - **U8, choosing the offset** (`OT-U8`; OT section 4; also Plan A.4,
    `OT-PA4`). The options: a temperature-floor rule, or one `c` for every
    setup whose tags are compared. At c = 110,495 J/kg dry, still air leaves
    the tested regime below about 228 K at sea level. Decide before the first
    production run that spans a winter (that choice belongs to M7).
  - **The attribution path, question 2** (`OT-PA3`; Plan A.3): the conventions.
    The owner decided on 2026-09-19 to keep c = 110,495 J/kg for G1 and G2
    and the hybrid mixing (DECISIONS.md). Still recorded as a recommendation:
    `c = c_p,d·T₀` = 274,388 J/kg, which counts dry internal energy from 0 K.
  - **FQ-24, whether C1's suppression cost (R11) matters in practice**
    (`FQ-24`): measured on C4 as about 1% over a day (E19). Its impact over
    long runs is open.
  - *Scope added (provenance pathway, 2026-09-26):* the `c`/2`c` pair is the
    convention bracket for every energy conclusion.

### G4.11 Carried over from G3

  - the plume rescale, to `Aʲ`;
  - one surface rule;
  - the per-subdomain split for precipitation energy and EDMF's sedimentation
    corrections;
  - compartments for the energy falling water carries.

Related, but beyond G4 (M8, in BACKLOG.md): how much provenance ice moves
upward where it lasts (open question 3, FQ-10's remainder).

### G4.12 Held-out columns for energy, a red team, and the owner's choice of the energy default

*Scope added (provenance pathway, 2026-09-26):* the default is chosen at its
ladder level, with OD14's held-out hygiene.

### G4.13 Ten days of the energy sphere at the chosen default, against E75

*Superseded 2026-09-24 (OD1, OD6):* ninety days of `g2_v2_sphere_n2` at 60
levels, with 8 energy tags, judged by the level observed against OD6's
ceiling. Step 11 of the revised order. The short 60-level run of step 9
measures the cost first (the owner, 2026-09-24).

### G4.14 A loss timescale for every run, after WP6

  - **Synergy 5, a loss timescale for every run**, τ = E/L (`OT-SYN5`; OT
    section 7, prepared, revised after the review of PR #98). It needs WP6's
    per-step gross-loss accumulators and passes an output-cadence test first.
    It is an instantaneous loss timescale, not a residence time. Design at the
    end of this file.

### G4.15 The energy follower after the owner's review of #102

*Scope added (rev. 2, 2026-09-24):* water's same-sign choice is not inherited
automatically. The current comparison stays, and the owner chooses (OD7)
before the G4.7 and G4.8 runs, after the long runs (DECISIONS.md,
2026-09-24). The aggregation test's departure is reported for the chosen
rule: a sign-dependent rule is not linear in the tags, so some departure is
expected, and its size is evidence.

*OD7, 2026-09-24: open, deferred.* Its current state is in
[the register](ROADMAP.md#the-decision-register). Analysis done: by the registered rule
(`design/INCREMENT_RULE_LONG_RUNS.md`) same sign is kept. Both criteria hold
for energy at both sites and for water at site 26. Water at site 23 breaks the
budget under both rules. The owner deferred the decision, for example until the
site 23 defect (known issue 7) is fixed and site 23 can be scored. G4.15b
waits. The metrics are in the parent session's FINDINGS entries.
*Prepared 2026-09-25:* site 23's rerun with option C, pre-registered in
`design/INCREMENT_RULE_LONG_RUNS.md`, section 8: four runs on
`claude/long-run-c-samesign` and `claude/long-run-c-absm`, submitted only
after option C passes its validation. Site 26 is not rerun if option C's V3
holds bit for bit. *2026-09-25:* option C's V3 holds (site 26 not rerun), but
its V2 fails at site 23 (W42). The rerun is not submitted; it waits on the
owner's decision on option C.

Added on 2026-09-24. The review of the water follower (#102) changed three
things that the energy source tags' `enthalpy_increment` still does the old
way:
  - its partition check accepts a 1% gap (`_check_increment_partition`); the
    water check now accepts 100 rounding units;
  - it spreads the column's total mismatch by |m|; the water follower now
    leaves it out only where the mismatch has its sign, which halved the water
    moved on D4-W (FINDINGS W28);
  - its audit's `increment_*_gross` columns are net over time; water's are now
    named `_net_abs`, and WP6 gives both families a per-step throughput.

Changing the first two changes the energy tags' results, so each needs its own
validation against the G2 runs.

A fourth, from the review of #105 (N5): under 1M stepped explicitly, the
water tags now carry sedimentation cross blocks, and the energy source tags
do not. Nothing refuses `enthalpy_increment` there, and no run measures it.
Measure it on W23's explicit column before either is decided.

  - [x] Built on `claude/energy-follower-review` (`2b43580d`, on #102): the
    100-unit partition check, the same-sign rule, the `_net_abs` names. Unit
    tests pass.
  - [x] Validated against E64's D4 day (FINDINGS E79): the model bit for bit
    the same; the part left out the same; the moved ledger the same (not
    halved, as for water); the gross closure residual 2.3e-6 → 9.2e-6.
    **For the owner:** keep the same-sign rule for its bound (no cell corrects
    more than its own mismatch) at a fourfold gross, or keep |m| for energy.
  - [x] N5 measured (FINDINGS E80): 2.1e-4 an hour on the explicit path with
    one iteration, 1.5e-6 implicit. The fix is G4.16.
  - [ ] PR, after the owner's choice above. With the same-sign rule,
    `energy_source_tags_increment_integration.jl:347` (`|left| > 0.5 ×
    gross`) fails on its hour-long EDMF column: `|left|` is 85.7 J/m² and
    the gross 176 (a ratio of 0.49), since the rule raises the gross as on D4
    (E79). The other 98 checks pass. Recalibrate it with the choice.
  - [x] Split at the owner's request (DECISIONS, 2026-09-24).
      + **G4.15a**, the check and the names, which change no result: draft
        PR #107 on #102 (`60a60373`). The unit tests pass (426/426), and so
        does the increment integration test (96/96).
      + **G4.15b**, the same-sign rule (`claude/energy-follower-review`,
        `d6e4021e`, on G4.15a). It waits on the long runs
        (`design/INCREMENT_RULE_LONG_RUNS.md`). The first submission
        (`13915221` to `13915228`) is void: without a reset of the radiation's
        seed the runs did not share an atmosphere (section 7). The second is
        jobs `13917157` to `13917199`, output in `output_0001/`.

*Scope added (provenance pathway, 2026-09-26):* OD7's provenance side, proposed:
water's PX3 (the placement pair), the energy spread `L` from E79's run pair,
and PX15. E79's left-out part is not a bound, because the moved part can also
change with the placement (PT6). An aggregation departure of the
sign-dependent rule would be Fid-1 evidence.

### G4.16 Sedimentation cross blocks for the energy source tags

*Scope added (rev. 2, 2026-09-24):* G4.16 moves ahead of G4.7 and of the
energy-default choice. It reuses the water tags' block and back-substitution
design (#105), with energy's own finite-difference, partition-sum, offset and
explicit-against-implicit validation. Its interim guard is step 0 of the
revised order, below. The guard is removed only when G4.16 passes.

Added on 2026-09-24, at the owner's request. The water tags' rows now carry the
parent's sedimentation cross block to each falling species, times the tag's
share (WP5b, #105); the energy source tags' rows do not. Under
`enthalpy_increment` on W23's column (DYCOMS RF02, 1M, EDMF, an hour) the
energy tags' closure residual is 2.1e-4 with the microphysics explicit and one
Newton iteration, 1.5e-6 with it implicit, and 4.9e-12 with ten iterations
(the N5 measurement of G4.15, configs `g415_n5_*`). So the energy tags lag the
parent's sedimentation on the explicit path as the water tags did (W23).

  - [x] Design: `ρe_tot`'s row has the cross block `∂(ρe_tot)ₜ/∂ρqₚ`, the
    sedimentation energy flux (`update_sedimentation_jacobian!`); each energy
    tag's row gets it times the tag's share, solved after the model's fields
    by the split solver's back-substitution, as the water tags' are. Mind
    B1: only with the split, and the offset `c·ρ` in the total `E`.
    *2026-09-25:* built on `claude/energy-tags-sed-cross` (`939fd9b1`, from
    #105 at `464f6fd0`; not pushed). The tags share the block of `E`, the
    parent's `ρe_tot` block plus `c` times its `ρ` block. Ice and snow carry
    energy below `-c` even with the offset, so their faces take the cell
    below's share. [design/ENERGY_SEDIMENTATION_CROSS_BLOCKS.md](design/ENERGY_SEDIMENTATION_CROSS_BLOCKS.md)
  - [x] Tests as #105's: the assembled blocks against a finite difference of
    the tags' real tendency, both float types; the partition's sum against
    the parent's. *2026-09-25:* and the blocks only with the split. Pass on
    the login node (216 and 22), with the rest of the energy and water tests.
  - [ ] Measure on W23's explicit column, one iteration, against 2.1e-4.
    *Pre-registered 2026-09-25* (the design note, section 6): nine runs,
    `configs/g416_*.yml`, from two run trees; pass at a gross of at most
    1e-7, with parity bit for bit. `analysis/increment/g416_compare.py`.
  - [x] Until then, `enthalpy_increment` with 1M stepped explicitly: refuse,
    or document the lag. The owner decided in rev. 2 (2026-09-24): refuse,
    with an explicit opt-in for development runs, off by default, and a test
    that the default configuration errors. Built on
    `claude/energy-explicit-1m-guard` (`33eeb5cd`, from `main` at
    `0b2b1032`; not pushed). The opt-in key's name is a proposal:
    `energy_source_tag_increment_allow_explicit_1m`. It is documented in
    `default_config.yml`, `energy_source_tags.md`, the guide and NEWS. The
    config test passes on the login node (`output/g416_guard/`). The
    record's `g415_n5_explicit_*` configs set this combination, so they need the key
    to run on a branch with the guard. [ ] A PR to `main`.
  - [x] *The owner, 2026-09-24: 2M and P3 stepped explicitly are refused
    until measured.* The guard now covers 1M, 2M and 2MP3 stepped explicitly
    (`e55ae293`). The key's name generalizes; the proposal is
    `energy_source_tag_increment_allow_explicit_microphysics`, and
    ~~`energy_source_tag_increment_allow_explicit_1m`~~ (`33eeb5cd`) is
    superseded. 0M sediments nothing and stays allowed. The config test
    passes on the login node (testset 36/36). A draft PR to `main` when its
    jobs are green. Water tags refuse 2M and P3 already (G3_TODO,
    Decisions).

## Energy items within M1 to M5 that no G4.n takes up yet

ROADMAP.md lists these as "later" within their milestones. They need a new
approval before any model code (Plan D, `OT-PD1`, `OT-PD3`).

| ID     | Register          | What                                                                                                                                                                                                       | Milestone | Status                                       | Source                                   |
|:------ |:----------------- |:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:--------- |:-------------------------------------------- |:---------------------------------------- |
| A2, A3 | `OT-A2A3`         | A2's runtime part (∫Δ⁺ per label at runtime) and A3 (form A as a global integral online), as optional validation features. Accept A3 at about 1.2e-3 on a C6-type run and ≤ 1e-4 on C7, C9 and C10 at 24 h | M2        | open                                         | OT section 4; decision of 2026-09-14     |
| C6     | `OT-C6leftover`   | C6's review leftovers: `isfinite` before the conversion to `FT`, `nothing` inside a broadcast at init, `parent` shadowed in tests. The Float32 rounding floor stays N (E45)                                | M1        | open                                         | OT section 4                             |
| A4     | `OT-A4`, `OT-PD1` | Signed overlay shares. Accept when a C9 twin gives form A ≤ 5 J/kg (or ≤ 1e-6 with the loss signed too), and `sfc` no longer freezes at a node                                                             | M5        | shelved (decision 4, later)                  | OT section 4; Plan D.1                   |
| FQ-15  | `FQ-15`           | Whether the audit's transport clamp is the whole of its form-A gap on the sphere (E36). A4's C9 twin would decide it                                                                                       | M5        | open                                         | archived FINDINGS §7; live: FINDINGS §13 |
| A6     | `OT-A6`           | A tag-only vertical upwinding key (E37)                                                                                                                                                                    | M3 to M5  | shelved                                      | OT section 4                             |
| C7     | `OT-C7jac`        | Jacobian blocks for the tags' sedimentation and the implicit bracket                                                                                                                                       | M3 to M5  | shelved                                      | OT section 4                             |
| C1c    | `OT-C1c`          | B3, the SGS diffusive flux under `enthalpy`. Built, and each of three placements made D4's residual larger (E59). Not to be opened in this form. Tagged `archive/c1c-sgs-diffusion`                        | M3 to M5  | shelved; the increment prototype replaced it | OT section 4                             |

*Scope added (provenance pathway, 2026-09-26):*

  - [ ] **Energy subsidence, the `sub` tag.** E66 found `sub` +18% in its
    integral against the donor reference. The parent subsides `h_tot`, so
    the energy tags have no faithful counterpart for it: it stays a
    convention. Water's PX8 at the same 750 m split of DYCOMS RF02 sizes
    it.

## Items that G3 takes up

| ID        | Register  | What                                                                                                                                                               | Where in G3                            |
|:--------- |:--------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:-------------------------------------- |
| synergy 2 | `OT-SYN2` | A two-hour Float64 twin as a standard recipe. Its prepared design is at the end of this file                                                                       | G3 WP0, the Float64-twin helper        |
| synergy 3 | `OT-SYN3` | The updraft exchange for the water tags                                                                                                                            | G3 itself                              |
| P2, P3    | `OT-P2P3` | P2: compute `energy_source_share_norm!` once per evaluation, and skip it when nothing sediments. P3: a string allocation per tracer per evaluation under the audit | G3 WP9, only if the profile shows them |
| R5        | `OT-R5`   | A converged Newton solve for closure studies; its cost is not measured                                                                                             | G3 V-W4 records each rung's wall time  |
| B14       | `OT-B14`  | Fixed on 2026-09-20. No run from a file has been made with tags on                                                                                                 | G3 V-W8, with water and energy tags    |
| FQ-22     | `FQ-22`   | Whether 1M changes the residual (W5): 7% down on a column (W5b); a sphere is open                                                                                  | G3 V-W11                               |
| FQ-21     | `FQ-21`   | Float32 on a sphere: settled for a day (E45). Longer runs, the audit and 1M in Float32 are open                                                                    | G3 V-W7 for water; U6 in BACKLOG.md    |
| FQ-23     | `FQ-23`   | The tag cost beyond one column: 1.46× on a sphere (T9). EDMF is open; the GPU is in BACKLOG.md                                                                     | G3 WP9 and V-W10, both families        |

## Prepared designs

Moved from section 7 of the former OPERATIONAL_TODO, written on 2026-09-20.
Item 3 of that section is G3 itself and had no prepared design. Item 2 serves
G3 WP0 first.

### Prepared: item 1, the ledger as a solver diagnostic

  - **What to build.** A probe configuration and a warning. The probe is the
    cheapest tag set that makes the ledger meaningful: two region tags that
    partition the domain, no source tags, `energy_source_tag_transport: enthalpy_increment`. The warning fires when `increment_left`, over the
    partitioned total, passes a level, or when it grows over a run.
  - **Where.** The audit already carries `increment_left` and
    `increment_left_gross` (`energy_source_tags.jl`,
    `_energy_source_ledger_audit`). The check would sit beside the closure
    check's warning, in `get_callbacks.jl`, with its own key.
  - **Calibration.** D4 with one iteration gives 313 J/m² gross in a day and
    0.094 with ten iterations (E64); V2's sphere gives 37% of the residual
    with two iterations (E74). So the level is a fraction of the partitioned
    total, and the growth matters more than the size.
  - **Cost.** Small: no new state, one reduction per check.
  - **Beyond this repo.** Upstream has no such monitor. Offering it would need
    the probe to be described in the tags' own terms, since the ledger only
    exists with the tags on.

### Prepared: item 2, the Float64 twin as a precision-sensitivity screen

*Revised on 2026-09-23 after the owner's review of PR #98. The original text is in the archived OPERATIONAL_TODO, section 7.*

  - **What to build.** A documented recipe and a helper. Given a run's config,
    the helper writes the twin: `FLOAT_TYPE: Float64`, `t_end` two hours, one
    process, everything else the same. The comparison reads both closure
    tables and reports the residual in each, and their ratio.
  - **Where.** `experiments/tag_closure/analysis/increment/float64_twin.py`
    for the comparison, and a section in
    `docs/src/energy_source_tags_guide.md` under "Is the answer
    trustworthy?".
  - **What it shows, and what it does not.** It is a screen for precision
    sensitivity. If the residual falls by orders of magnitude in Float64, the
    Float32 residual is sensitive to precision. On the sphere it closed to
    5.7e-15 against 3.85e-6 in Float32 (E70). If it hardly falls, most of the
    residual is not. On D4 the Float32 residual is 2.3 times the Float64 one
    (E65). The twin does not decide a cause:
      + Float64 also changes the parent's trajectory;
      + a small residual in either run does not show that the tags' provenance
        is right.
  - **For a causal conclusion,** add, at each precision:
      + a tagged and an untagged run, whose parent fields must be bit for bit
        within that precision;
      + the difference between the two precisions' parent states, reported;
      + a refinement of the time step or the solver;
      + a per-tag comparison against a reference.
  - **Cost.** An hour of wall time per configuration, and no model code, for
    the screen.

### Prepared: item 4, the closure check as a forecast

  - **What to build.** Two more columns in the audit table: the flush rate the
    loss rule gives, and the level the residual would settle at, `G*`, with
    the ratio to the present residual.
  - **How.** `analysis/increment/v2_sphere.py` already computes both from the
    closure and audit tables. The first step is to lift that computation into
    a helper the repository owns, so the experiment scripts and the docs share
    it. The second, if it proves stable, is to compute the flush rate in the
    run itself from the tags' own losses, which the attribution rule already
    sums, and write it to the audit table.
  - **What it needs to be honest about.** The rate is not constant: on V2 it
    ran from 0.0105 to 0.0165 a day (E74). The forecast is an order of
    magnitude, not a number.
  - **Cost.** Analysis only for the first step.

### Prepared: item 5, a loss timescale for every run

*Revised on 2026-09-23 after the owner's review of PR #98. The original text is in the archived OPERATIONAL_TODO, section 7.*

  - **What it is.** `τ = E / L`: the partitioned total over the rate at which
    the loss rule takes from it, in days. It is an instantaneous loss
    timescale under donor-proportional loss, local to a cell and a moment. It
    is not a residence time, nor an air age, and it leaves out transport. E60
    estimated it by hand: 4 to 20 days on D4, about zero in the surface layer,
    and 1 to 2 years above 10 km on C9's sphere. The initial-energy tags lose
    8.6% and 12.3% a day on D4, a timescale of 8 to 11 days.
  - **It depends on WP6.** `L` must be the gross loss, accumulated at each
    accepted step. WP6 of G3 builds the positive and negative loss
    accumulators, per cell and for both families. A net process record can
    hold a gain and a loss that cancel between two outputs. `L` taken from
    the negative parts of net records is then too small and `τ` too large, in
    the limit infinite. So an estimate from the records is never reported as
    `τ`.
  - **The output-cadence test, before any use in guidance.** `L` from the
    accumulators must not change when the output interval changes from one
    step to one hour, on a column with alternating signs and on D4. The
    estimate from net records is the test's control: it should underestimate
    `L`, and by more at the longer interval. Scripts: an accumulator reader,
    and `analysis/increment/memory_time.py` for the control over the runs that
    already carry records and tags (`c6_column_repair`,
    `c1c_base_d4_enthalpy`, `c5_sphere_gray`).
  - **Its own check.** `τ` must scale with `e + c`: doubling the offset should
    multiply it by about 2.6 on D4 (E60's formula, E71's run; `g1_inc_d4` and
    `g1_inc_d4_2c`).
  - **Then, in the run.** Once the test passes, `τ` joins the audit table beside
    item 4's forecast. The guide reads it as "the loss rule takes about 1/N of
    a tag's energy a day here", not as how long energy stays.
  - **Cost.** One audit column on top of WP6's accumulators. The test is two
    short runs.

### Prepared: item 6, one combined budget: records, ledger and repair

*Revised on 2026-09-23 after the owner's review of PR #98. The original text is in the archived OPERATIONAL_TODO, section 7.*

  - **The question.** On an EDMF column under `enthalpy_increment`, does the
    change of the partitioned total `E` over an interval equal the sum of:

      + what each process did, from the process records, each with `c` times
        its change of mass;
      + what the implicit solve left, from the increment ledger;
      + what the repair moved, from `e_src_fix_<name>`;
      + a named remainder?

    No run has combined the full records with the ledger. The runs with every
    record used the `tracer` or `enthalpy` transport, which has no ledger
    (`c1c_base_d4_enthalpy`, `c6_column_repair`). The runs with the ledger
    record only precipitation (`g1_inc_d4`). This is a new question. E23's
    1.37 MJ/m² is not part of it: E26 settled that amount to the joule, as
    subsidence's −1,277,826 J/m² and the rain-out's −87,651.

  - **The acceptance test, set by the owner on 2026-09-23 before the run.**

      + Every term is named, and reported with its sign, per layer and for the
        column.
      + At 24 h on the D4 column, the unexplained remainder is at most
        1 J/m², the level of G1's criterion 2 (E64).
      + The identity also holds at the offset 2c. E71 showed that the
        remainder scales with `c`, so this is where a missing `c Δρ` shows.

  - **The run.** One D4 day with
    `energy_source_tag_transport: enthalpy_increment` and
    `energy_process_record` listing every process the column has, and the same
    at 2c. About 40 minutes each.

  - **What to build.** `analysis/increment/process_budget.py`. It reads the
    records, the ledger, the repair's ledger and the closure table, and prints
    the budget per layer and for the column, with the remainder named.

  - **Cost.** Two short runs and one analysis script.
