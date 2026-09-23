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

### G4.1 #95's follow-ups

D1 with D3 closes when #95 merges. U5, a clear error when the tag list
changes across a restart.

  - **B12, D1: the user guide into the docs, with D3** (`OT-B12`; OT section 2,
    item 12; also Plan C.4, `OT-PC4`). #95 carries the guide,
    `docs/src/energy_source_tags_guide.md`.

  - **D3, the caveats** (OT section 3, "With D1"): C1 and C4, what is
    untested, stitching `e_src_fix` across restarts, choosing `c`, and ice
    passing provenance upward (E41).

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

### G4.5 Warnings, abort rules and acceptance kept apart

For both families' closure checks. U2's calibration.

  - **B11, calibrate U2's tolerance per transport** from V2 and V3, and add the
    warning (`OT-B11`; OT section 2, item 11; also Plan C.4, `OT-PC4`).

### G4.6 The D4 process budget

With every record and the ledger (synergy 6, C4's `c Δρ`, repair never a
parent source). The offline EDMF column budget.

  - **Synergy 6, one combined budget of records, ledger and repair**
    (`OT-SYN6`; OT section 7, prepared, revised after the review of PR #98). A
    new question with an acceptance test set in advance. It does not explain
    E23's remainder, which E26 settled. Design at the end of this file.
  - **C4, `c·Δρ` from processes the tags do not bracket**: vertical diffusion,
    sponges, hyperdiffusion, EDMF, LES (`OT-C4`; OT section 3). Measure it,
    then share it as transport or document its size.
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

### G4.8 A surface pulse, and convection switched on and off, for energy

### G4.9 Alternative placements of the increment correction on a shared parent

  - **The attribution path, question 3** (`OT-PA3`; Plan A.3): whether the
    correction may bring `e_src_res` to rounding by construction. The owner
    decided on 2026-09-19 to keep it as built (DECISIONS.md). G4.9 tests the
    alternatives.

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

### G4.11 Carried over from G3

  - the plume rescale, to `Aʲ`;
  - one surface rule;
  - the per-subdomain split for precipitation energy and EDMF's sedimentation
    corrections;
  - compartments for the energy falling water carries.

Related, but beyond G4 (M8, in BACKLOG.md): how much provenance ice moves
upward where it lasts (open question 3, FQ-10's remainder).

### G4.12 Held-out columns for energy, a red team, and the owner's choice of the energy default

### G4.13 Ten days of the energy sphere at the chosen default, against E75

### G4.14 A loss timescale for every run, after WP6

  - **Synergy 5, a loss timescale for every run**, τ = E/L (`OT-SYN5`; OT
    section 7, prepared, revised after the review of PR #98). It needs WP6's
    per-step gross-loss accumulators and passes an output-cadence test first.
    It is an instantaneous loss timescale, not a residence time. Design at the
    end of this file.

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
