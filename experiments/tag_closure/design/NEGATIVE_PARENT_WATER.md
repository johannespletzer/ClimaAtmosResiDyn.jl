# Tagged water where the parent's water goes negative: options for the fix

Written on 2026-09-24, at the owner's request, for known issue 7
(`docs/known_issues.md` on `claude/water-tags-wp6-step3`). It lists options.
**The choice is the owner's.** The FINDINGS entry is the parent session's. The
fix comes before the sphere (ROADMAP.md, the execution order, step 8a).

*Updated 2026-09-24, later.* The owner chose option A now, then the probe of
section 5, then a choice among B, C and D. Option A is built on
`claude/tag-closure-no-abort` (`00c9eedb`), for a PR against `main`. The probe
is pre-registered in section 5, before it runs.

## 1. The defect

A diagnostic must never end a run that upstream completes (`AGENTS.md`, "Fork
parity with upstream"). The long runs' second submission
(`INCREMENT_RULE_LONG_RUNS.md`, jobs `13917157` to `13917199`, `output_0001/`)
shows that the water tags do. The facts, as the parent session measured them:

  - At site 23 the model's own `q_tot` goes below zero from day 10, in the
    untagged twin too, down to −3.1e-3 kg/kg (day 30), on 66 of 91 daily outputs.
  - The water tags then diverge. On day 48 the copies run's column tags hold
    28 kg/m² against the parent's 13, and `q_tag_pbl` reaches 0.13 kg/kg
    against a `hus` maximum of 0.016.
  - The tagged runs end with `simulation_crashed`, the water closure at −1.02:
    the copies run at day 48, both follower rules at day 74.5
    (t = 6.4368e6 s). The untagged twin completes 90 days.
  - The ten daily output fields are bit for bit the twin's at every output
    up to each crash (prefix parity, `analysis/water/lr_parity.py`; the runs
    keep no checkpoints, so the full state is not compared directly).

So the tags change nothing in the model until they end it. The runs used
`claude/long-run-samesign`, #102 and #103 with G4.15b.

## 2. What is not established

  - **Which operator makes the divergence.** Candidates: the follower moving
    the parent's increments where the parent is negative; the partition
    repair, which keeps the tags non-negative and their sum, so it cannot
    follow a negative parent; the limiters' emptying where the parent is
    at or below zero (`q_tag_led_empty`); the copies' repair against a
    negative `q_totʲ`. None is isolated.
  - ~~**What ends the run.** Whether the check ended the run, or something
    else did, is not recorded here.~~ *Established 2026-09-24:* the water
    closure check ended both follower runs. Job `13917157`'s `.err`, line
    1401, reads "water tag closure residual 1.0194981558568388 exceeds the
    configured abort level 1.0 at t = 6.4368e6 s", from
    `tag_closure_callback!` (`tagged_tracers.jl:841`). That level, 1.0 by
    default, assumed a non-negative parent: non-negative tags then miss it by
    at most the parent itself. Here the parent is negative. What ended the
    copies run at day 48 is not quoted here.

## 3. What any fix must keep

  - The model's fields bit for bit, in every configuration. A fix touches only
    the tags, their copies, their ledgers and their checks.
  - Every new correction of the tags writes the per-mechanism and per-tag
    ledgers (WP6 step 3), so the intervention row can count it.
  - A run with a non-negative parent gives the same tags as today, bit for
    bit, unless the option says otherwise.

## 4. The options

| option                                                   | what it does                                                                                                                                                                                                                         | for                                                                                                                | against                                                                                                                                                                                                   |
|:-------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------ |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A. The tags cannot end a run**                         | The water closure check never aborts by default (`abort_above: ~`), or it does not abort where the parent's negative water explains the residual. The check still warns, and the audit flags the rows.                               | It restores the parity rule at once, whatever the cause. It changes no tag value.                                  | The tags still diverge. Every result after the divergence is void and must be flagged. It hides nothing only if the flag is read.                                                                         |
| **B. No tag water where the parent has none**            | After the constraints, where `ρq_tot ≤ 0`, every partition tag is set to zero, and every copy where `q_totʲ ≤ 0`. The change goes to `q_tag_led_empty` and the per-tag ledgers.                                                      | Tags never claim water a cell does not hold. The residual there is the parent's own negative water, bounded by it. | The provenance of water that returns to the cell is erased. It stops the column's divergence only if the divergence starts in the negative cells. Tag values change wherever the parent is ever negative. |
| **C. The tags partition the parent's non-negative part** | The partition's target is `max(ρq_tot, 0)`: the follower takes that field's increment, and the repair, the rescale and the copies' repair aim at it. The parent's negative part becomes a named field, for example `q_tag_negative`. | The partition is consistent by construction, and the remainder has a name.                                         | The largest change: the follower, the repair, the rescale and the copies. It needs its own validation, and the closure's definition changes.                                                              |
| **D. A cap**                                             | Where `Σ_P ρq_tag > max(ρq_tot, 0)(1 + ε)`, the partition is scaled down to the cap, logged in a new state ledger. It is the sphere's pointwise check (G3_PLAN 6.1) turned into a correction.                                        | Local and bounded; it shows up as intervention.                                                                    | One more correction to count. A large cap can hide a divergence it should expose.                                                                                                                         |
| **E. Stop the tags, not the run**                        | When the tags pass `abort_above`, their tendencies stop and the audit marks the time. The model runs on.                                                                                                                             | The run completes, and parity holds.                                                                               | The tags' fields stay in the state with no meaning after that time. The results after it are void. It adds a mode to every tag path.                                                                      |

The options can combine. A is the smallest change that meets the parity rule.
B, C and D act on the divergence itself. Which of them acts on its cause is not
known (section 2).

## 5. The probe, pre-registered before it runs (2026-09-24)

~~The site 23 samesign run from its day-9 checkpoint~~. *Corrected:* the long
runs keep no daily checkpoints, only an HDF5 file written at the crash, so the
probe runs from the start.

**The run.** `configs/lr_s23_probe_ledgers.yml`: `lr_s23_samesign` with
`water_tag_ledger_per_tag: true` and `energy_source_tag_ledger_per_tag: true`,
`t_end` 20 days, `radiation_reset_rng_seed: true` as before, and the ledgers
written every 6 hours. The run tree `../ClimaAtmosResiDyn-issue7-probe-run` is
the record merged with `claude/water-tags-wp6-step3` (WP6 step 3 and its
ledgers) and `claude/long-run-samesign` (the code the long runs ran). It uses
the long runs' driver, `analysis/water/d4w_driver.jl`. The closure check keeps
its old abort level of 1.0. The samesign run first passed it at day 74.5, so
the probe should not reach it; if it does, what the tables hold up to the
abort is the reading.

**Its validity.** At the daily outputs of days 1 to 20, `rhoa`, `ta` and `hus`
are bit for bit those of `lr_s23_untagged` (output_0001), compared as
`analysis/water/lr_parity.py` compares them. If not, the probe's readings do
not come from the long runs' trajectory, and it is void.

**What it reads.** For each 6-hour interval from day 5 to day 20:

  - two sets of cells: N, where `hus < 0` at either end of the interval, and P,
    the rest of the column;
  - per ledger, the interval's increment of its per-step gross, `Δ<L>_gross`,
    times `ρΔz`, summed over N and over P, in kg/m² per day. The ledgers: the
    rescale, the emptying, the repair and its net (`q_tag_led_*`), the
    follower's part left out and part moved (`q_tag_inc_left`,
    `q_tag_inc_moved`), and each tag's own `led_fix` and `led_inc` for `pbl`,
    `free`, `evap` and `fcg`;
  - the tags' overclaim, `Σ_P ρq_tag − ρq_tot` where positive, times `ρΔz`, over
    N and over P.

The baseline is each quantity's mean rate over days 5 to 8, before the parent
turns negative (W36: from day 10).

**The pre-registered readings.**

 1. *Grows.* A ledger grows when its rate over days 10 to 20, in N or in P, is
    at least 10 times its baseline rate there.
 2. *First.* The ledger whose rate first passes 10 times its baseline, by
    6-hour interval.
 3. *Fastest.* The ledger with the largest ratio of its days-10-to-20 rate to
    its baseline rate.
 4. *Where.* Whether the overclaim grows in N, in P, or in both, by the same
    10-fold rule.

**How the readings bound the options.** They bound; they do not isolate a
cause, since the probe changes nothing and compares time windows of one run.

| reading                                                                                                  | what it bounds                                                                                                   | the option it points to                                                |
|:-------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------- |
| the emptying, the rescale or the repair grows first and fastest, in N, and the overclaim grows in N      | the tags meet the negative parent through the corrections in the negative cells                                  | B: no tag water where the parent has none                              |
| the follower's moved or left part, or `led_inc`, grows first and fastest, in or next to N                | the follower carries the parent's increments of a negative field into the tags                                   | C: the tags partition the parent's non-negative part                   |
| the overclaim grows in P too, with no single ledger first by a clear margin (less than 2 times the next) | the divergence spreads beyond the negative cells                                                                 | D: a cap; B alone would not reach it                                   |
| no ledger grows by the rule while the overclaim does                                                     | the growth is in a path the ledgers do not see, such as the tags' own tendencies with shares of a negative total | none of B to D is shown to act on the cause; a further probe is needed |

The parent session brings the reading and the choice among B, C and D to the
owner.

**Cost.** The samesign run reached day 74.5 in about 2 h of wall time (its
provenance: 18:14 to 20:10, one process). Twenty days with the ledgers every
6 hours should take well under a day; the job asks for 24 h.

## 6. Tests for the fix, whichever is chosen

  - Site 23's 90-day run with tags completes. Its parent is bit for bit the
    untagged twin's at every daily output.
  - Site 26's runs give the same tags as before, bit for bit, unless the
    option changes tags where the parent is non-negative.
  - A unit test on a column whose parent goes negative in one cell: the
    option's bound holds, and every change is in the ledgers.
  - The integration groups that check the model's fields with the tags
    (`tagging_water*`), unchanged.

## 7. For the owner

 1. ~~Which option, or which combination.~~ *2026-09-24:* A now, then the
    probe, then a choice among B, C and D.
 2. ~~Whether the probe of section 5 runs first.~~ *2026-09-24:* it does,
    after A.
 3. Whether results already recorded from runs whose parent went negative
    (site 23's long runs) are kept, flagged or voided.

## 8. Option C: its validation, pre-registered before any run (2026-09-25)

The owner chose option C on 2026-09-25, after the probe (W39): the partition
tags partition the parent's non-negative water, `max(ρq_tot, 0)`; the follower
takes that field's increment; the repair, the rescale and the copies' repair
aim at it; the negative part is a named field. Registered before any
validation run. Nothing below changes after the runs.

### 8.1 What is built

On `claude/water-tags-negative-parent`, from `claude/water-tags-wp6-step3`
(#109) with `claude/tag-closure-no-abort` (#112) merged. #109 has the follower
and each tag's own ledgers, which C must write; #112 lets a run go on past the
old abort level, so a failure shows as a number, not a crash.

  - **The target.** `water_tag_partition_target(ρq_tot) = max(ρq_tot, 0)`,
    with `-0.0` kept as `-0.0`, and the remainder
    `water_tag_negative_part(ρq_tot) = min(ρq_tot, 0)`. The diagnostic
    `q_tag_negative` is the remainder per unit mass; `q_tag_res` is the target
    less the region tags. The tag name `negative` is reserved.
  - **The follower.** Its mismatch is the target's increment less the
    partition's. The target's column total differs from the parent's by the
    negative part's change, `N = ∫ −Δ min(ρq_tot, 0)`. That part is no lag,
    so the tags take it: it goes to the cells whose mismatch has its sign, in
    proportion to it, by each cell's composition, and is recorded in a new
    ledger, `q_tag_inc_negative`. The rest of the column total is left out as
    before. Where the parent is negative at the solved stage, a cell's tags
    move by the partition's own composition: the parent's shares are
    undefined there, and without this a cell a solve took below zero could not
    give up the tags it held. That was the mechanism the probe pointed to.
  - **The rescale and the copies' repair** aim at the target: a correction
    that leaves the parent (or `q_totʲ`) negative takes the partition to zero,
    not below. The copies' residual `q_tag_copy_res` is `max(q_totʲ, 0)` less
    the copies.
  - **The closure check** compares the partition with the target
    (`water_closure_total`), and the initial and rebuilt tags partition the
    target.
  - **The repair** already keeps the partition non-negative with its sum; it
    is unchanged.
  - **Unchanged where the parent is never negative, bit for bit**: every
    change is a no-op there, including the signed zeros.

### 8.2 The runs

The GCM-driven column, W36's configuration with the radiation's seed reset
(`radiation_reset_rng_seed: true`): prognostic EDMF, 0M, 60 levels to 40 km,
`dt` 10 s, ARS222, one Newton iteration, 90 days, both families, water tags
`pbl`, `free`, `evap`, `fcg` under the follower. Each tag's own ledgers on
and written every 6 hours, as the probe had them.

| run               | site | code                     | what for                         |
|:----------------- |:---- |:------------------------ |:-------------------------------- |
| `ic_s23_c`        | 23   | option C's run tree      | V1, V2, V4, V5                   |
| `ic_s23_untagged` | 23   | option C's run tree      | V4's twin                        |
| `ic_s23_before`   | 23   | the record + #109 + #112 | reported: the same run without C |
| `ic_s26_c`        | 26   | option C's run tree      | V2, V3, V4                       |
| `ic_s26_untagged` | 26   | option C's run tree      | V4's twin                        |
| `ic_s26_before`   | 26   | the record + #109 + #112 | V3's control                     |

The energy follower on these trees is #109's (|m|), not W36's same-sign rule
(G4.15b; OD7 is open). The energy tags are not part of this validation.

### 8.3 The pass rules

| #   | what                                                                           | pass                                                                                                                                                                                                               |
|:--- |:------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| V1  | site 23 with C completes                                                       | the run reaches day 90                                                                                                                                                                                             |
| V2  | the partition against the target, at every closure check to day 90, both sites | gross relative to `∫max(ρq_tot, 0)` at most 0.2% (OD3's water closure row)                                                                                                                                         |
| V2b | the named remainder                                                            | `q_tag_res + q_tag_negative + Σ region tags = q_tot` at every daily output, to 1e-12 of the column's largest `|q_tot|` at that output (amended before any run: a cell's own `q_tot` can be near zero)              |
| V3  | site 26's water tags, `ic_s26_c` against `ic_s26_before`                       | bit for bit at every daily output; or different only in cells and after times where the parent was ever negative there, which the untagged twin shows (expected: nowhere)                                          |
| V4  | every model field of each C run against its untagged twin, every daily output  | bit for bit (the parity row)                                                                                                                                                                                       |
| V5  | intervention, both sites, from the ledgers                                     | reported: `q_tag_inc_negative`'s per-step gross per day; the partition repair's retained gross (OD3's aggregate row, at most 0.5% a day) and each tag's `led_fix` (OD3's per-tag row, 2%) scored over days 1 to 90 |

**How V2 fails, if it does.** If the gross exceeds 0.2% at site 23 while V1
passes, C keeps the run going but does not keep the partition on its target.
The ledgers (V5) then show whether the follower's negative-part entry, the
repair or neither carries the miss, and the owner decides.

### 8.4 Checks before the runs

  - Unit (`test/tagged_water_tests.jl`, both float types): on a column whose
    parent a solve takes below zero in one cell, the partition closes against
    the target cell by cell, the negative cell's partition is empty, no
    partition tag goes negative, the negative part's column total is
    `q_tag_inc_negative`'s, nothing is left out, and each tag's own ledger is
    its change bit for bit; the recovery of that cell; a parent that stays
    non-negative gives no negative-part entry; the target, the remainder and
    the rescale at their edges.
  - The existing water and config test groups, unchanged in what they check.

### 8.5 The jobs

From each run tree's root, with `submit_g3.sh` and
`DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl`, `hpda2_compute`,
2 CPUs, 48 GB, `--time=08:00:00` (the samesign run reached day 74.5 in about
2 h; the ledgers add fields).

## 9. The probe of option C's miss, pre-registered before it runs (2026-09-25)

Option C's validation failed V2 at site 23 (W42). The region tags hold more
than the target `max(ρq_tot, 0)`, by up to 2.2% of the water, and the miss is
all `overclaimed`. The owner decided on 2026-09-25: probe the miss first, and
decide the fix after. This section registers the probe. Nothing below changes
after the runs. Option C's code does not change for it.

### 9.1 The question

Which operator grows the excess where no ledger records it? W42 found four
6-hourly rises of the excess (days 30.50–30.75 and 52.50–53.25) where no
ledger changes by half the rise in the cells that hold it. A fifth rise, days
30.75–31.00, is carried by the follower's ledgers (35 times the rise). It is
the control.

The excess is `E = ∫ max(ρq_tag_pbl + ρq_tag_free − max(ρq_tot, 0), 0) dz`,
per unit area, and `W = ∫ max(ρq_tot, 0) dz` scales it.

The candidates, considered and not presumed:

 1. explicit transport moving the parent's negative water into positive
    cells, while the tags move only non-negative amounts, so the target
    shrinks and the tags do not;
 2. EDMF or diffusion;
 3. the follower's stage handling;
 4. the target's nonlinearity across a step;
 5. an explicit local process (the prescribed forcing's advection terms, its
    nudging, the surface flux) whose bracket gives a cell with a negative
    parent new region water, which the target, zero there, does not have.

The fifth is added because the code allows it and no ledger would record
it: the brackets attribute explicit processes, and the follower corrects
only the implicit increment.

### 9.2 The runs

One job, `analysis/water/ic_miss_probe.jl` as the driver of
`configs/ic_miss_probe_s23.yml`. That config is `ic_s23_c.yml` with only the
job id changed. The run tree is `ic_s23_c`'s code, `e6bab0fc`, with the
current record merged; only `experiments/` differs.

**The reference** runs the config from the start and writes its outputs, as
`ic_s23_c` did. The column has no checkpoints, so it is rerun from day 0. It
stops after day 53.3.

**The windows.** Days 30.3–31.0 and 52.4–53.3: 6048 and 7776 steps of 10 s.
They cover the no-ledger rises and the control rise, with 0.2 days before
each. Outside them the reference only steps.

**At every step `k` in a window,** from the reference's state `Yₖ`:

  - **The reference's own step.** `ΔE_ref` over the step, split by where it
    lies: cells with `ρq_tot ≤ 0` at the step's start (class N), cells with
    `ρq_tot > 0` there (class P), and, as a subset of both, the cells whose
    parent changes sign over the step (class X). Beside it, each ledger's
    change over the step in the cells that hold an excess at the step's end,
    as W42 measured it per 6 hours.
  - **Explicit probes.** Each explicit process that writes `ρq_tot` is
    evaluated alone at `Yₖ`, with the tags' bracket exactly as the model
    applies it (`open_applied_update!`, `close_applied_update!`). Its
    tendency is applied for one step, `Yₖ + Δt·T`, and the excess's change
    `ΔE_o` is taken, split as above. The processes: the external forcing as
    a whole, and each of its terms alone (horizontal advection, the vertical
    fluctuation, subsidence, nudging); the surface flux; subsidence and
    large-scale advection outside the forcing, where the model has them; and
    the whole explicit tendency (`remaining_tendency!`).
  - **Trials**, the WP4c gate's pattern: copies of `Yₖ`, each stepped once,
    with the reference's radiation flux copied in, so that every trial sees
    the radiation the reference saw. The trials: `on` (the config as it is,
    the control), `tracer` (`water_tag_transport: tracer`: the follower off),
    `off_sgs_mass_flux` (`edmfx_sgs_mass_flux: false`) and
    `off_sgs_diffusive_flux` (`edmfx_sgs_diffusive_flux: false`). A trial's
    contribution is `ΔE_on − ΔE_trial`, split as above.

Everything goes to one CSV row per step in the reference's output directory.

*Amended before the run (2026-09-25), after the login-node check:* the
forcing holds two nudging terms, one for the scalars and one for the winds.
Each is probed alone, labelled by its variables. The check's six steps (60 to
120 s) also showed the `on` trial equal to the reference bit for bit, and
the `tracer` trial growing the excess by 5.9e-4 kg m⁻² in one step, where the
reference grew it by 9e-16. So near the start the `tracer` trial's share is
dominated by the tracer transport's own departure from the parent, and it
bounds the follower's part only loosely. The rules are unchanged.

### 9.3 Validity, before any attribution

  - **P0, the reference is `ic_s23_c`.** Every field both write, at every
    6-hourly and daily output up to day 53.25, bit for bit. If not, the
    probe measures another run. Its numbers are then reported, and nothing
    is attributed to W42's rises.
  - **P1, the `on` trial is the reference's step.** Per rise, `|Σ ΔE_on − Σ ΔE_ref|` at most 10% of the rise. Where it is more, the trials'
    contributions for that rise are *not assessable*. The explicit probes
    do not depend on it.
  - **P2, the rises are W42's.** Each rise from the per-step sum,
    `Σ ΔE_ref / W`, within 10% of W42's 6-hourly value (which weighs by the
    output's `ρΔz`). A rise outside that is reported beside W42's.

### 9.4 Attribution, per rise

For each of the five rises `I`, with `R = Σ_{k∈I} ΔE_ref`:

  - an explicit probe's share `s_o = Σ_{k∈I} ΔE_o / R`;
  - a trial's share `s_τ = Σ_{k∈I} (ΔE_on − ΔE_τ) / R`;
  - where the rise lies: its shares in N, P and X.

**Rules.**

  - A share of at least 0.5 **attributes** the rise to that operator. A share
    from 0.1 to 0.5 **contributes**. Several operators can each reach 0.5;
    they interact, and each is reported.
  - The candidates map to the measures as follows:
      + candidate 1 is supported if the subsidence term or the
        `off_sgs_mass_flux` trial attributes the rise, with at least half of
        that operator's share in class P;
      + candidate 2 is supported if the `off_sgs_mass_flux` or the
        `off_sgs_diffusive_flux` trial attributes it;
      + candidate 3 is supported if the `tracer` trial attributes it;
      + candidate 4 is consistent with the rise if class X holds at least
        half of it. That is a location, not a mechanism, and it is reported
        so;
      + candidate 5 is supported if a local explicit probe (horizontal
        advection, the vertical fluctuation, nudging, the surface flux)
        attributes it, with at least half of its share in class N.
  - A rise is **unattributed** if no probe and no trial reaches 0.5.

**Bounded claims.** An explicit probe linearizes its process at the step's
start. It leaves out how the process interacts with the implicit solve and
with the other stages. A trial changes more than the operator it switches
off: its transport of the parent and of any excess already there goes with
it. So each share bounds the operator's part; none isolates a cause.

**The control.** At the follower-carried rise (days 30.75–31.00), the
per-step ledgers should move by more than the rise, as W42 found per 6 hours.
If they do not, the step-scale ledger reading differs from W42's, and that is
reported.

### 9.5 What the result means for a revision of C

  - **Candidate 5 or 1, an explicit process:** the brackets and the explicit
    transport do not follow the target. A revision would give the explicit
    attribution the target's treatment: water produced where the parent stays
    at or below zero, or the parent's negative water moved into a positive
    cell, would enter the negative part, not the region tags. The follower's
    negative-part entry is the pattern.
  - **Candidate 2 or 3, an implicit operator or the follower:** the follower's
    handling of the implicit stages misses part of the target's increment. A
    revision would correct the follower, for instance against the target at
    the step's end.
  - **Candidate 4 alone:** the target's kink at zero. A revision would treat
    the crossing cells, for instance by correcting against the target at the
    step's end.
  - **Unattributed:** the operators probed here do not carry it. The
    constraint step, the callbacks and the implicit microphysics bracket
    remain. The owner decides whether to probe them.

In every case the owner decides the fix.

### 9.6 Checks and the job

Before the job, on the login node: every trial configuration builds its
model, and the driver runs a short window near the start of the run to the
end (`IC_PROBE_WINDOWS` set to seconds, not days), writing a CSV. The job:
`submit_g3.sh` from the clean run tree `../ClimaAtmosResiDyn-ic-probe-run`,
`DRIVER=experiments/tag_closure/analysis/water/ic_miss_probe.jl`,
`hpda2_compute`, 2 CPUs, 48 GB, `--time=12:00:00`. The estimate is about 4 h:
five model builds, 53 days of stepping, and the windows' trials.
`analysis/water/ic_miss_score.py` scores it.

*Checked and submitted 2026-09-25:* the login-node check built all five
models and ran six steps (60 to 120 s) in 2946 s, writing its CSV. The job is
`13987196`, from the run tree at `49958c1b` (clean; `ic_s23_c`'s code,
`e6bab0fc`, with the record), output in
`$SCRATCH/tag_closure/output/ic_miss_probe_s23/output_0000/`.

### 9.7 The extended probe on `main`, pre-registered before it runs (2026-09-28)

W47 scored the probe of this section. Four rises lie wholly in class N, and
the forcing as a whole reproduces each of them. Three go to candidate 5, the
forcing's vertical fluctuation. In the fourth (days 52.75–53.00) no candidate
is supported, because that term only contributes (0.47). Subsidence alone
gives 5.5 to 7.9 times each rise, and the terms' shares do not add up. The
owner decided on 2026-09-28 to probe more before any fix, the fourth rise
and cell by cell. The owner also decided to rerun the probe on `main` now,
where #118 checks the parent's negative water at every accepted step. This
subsection registers that run. Nothing below changes after it. Sections 9.1
to 9.6 stand as written.

#### 9.7.1 What changes, and what stays

  - **The code is `main`'s:** `cfc2152c`, merged into the record at
    `679c52dd`. The run tree is the record at the commit that registers this
    subsection. The model's own fields should not have moved since
    `e6bab0fc`, by the fork's parity rule, and P0a checks it. The tag code has
    moved: option C's final form (#116), the per-step check (#118), and #119
    and #121, which are off in this configuration. For the energy tags,
    #113, #115 and #120 are live here under `enthalpy_increment`; #114's
    copies are off.
  - **The configuration** is `configs/ic_miss_probe2_s23.yml`,
    `ic_miss_probe_s23.yml` with only the job id changed. #118's check at
    every accepted step runs in the reference by default
    (`negative_water_void_above`, `1e-4`).
  - **The driver** is `analysis/water/ic_miss_probe2.jl`. It does everything
    `ic_miss_probe.jl` does, unchanged, and adds 9.7.2.
  - **The windows and the five rises** are those of 9.2 and 9.4.

#### 9.7.2 What is added

 1. **The parent's negative water at every step's end:** `∫max(−ρq_tot, 0)`,
    its ratio to `∫ρq_tot`, and #118's latch.
 2. **Leave-one-out probes.** For each forcing term `t`, the forcing without
    `t`, composed as the model composes the forcing: the other terms'
    `(dT, dq)` accumulated and converted once, then their direct parts. It
    uses the same bracket, is applied alone at `Yₖ` and is stepped by `Δt`.
    Its share is `ℓ_t = Σ_{k∈I} (ΔE_forcing − ΔE_{forcing∖t}) / R`: how much
    of the forcing's growth goes when `t` is left out. It is a second
    measure of a term's part, beside 9.4's one-term probes, and it does not
    add up either.
 3. **Candidate 5's mechanism, cell by cell.** A mechanism cell in a step has
    its parent at or below zero before and after the step, while the region
    tags' sum rises. The excess's change in those cells is measured for the
    reference's step, as a part of `R`, and for the forcing's probe, as a
    part of the forcing's own growth. Each is split by the sign of the
    parent's change.
 4. **Per level, summed over each 6-hour interval:**
      + the reference's change of the excess: all of it, in N, and in the
        mechanism's cells;
      + the forcing's, each term's and each leave-one-out probe's;
      + the forcing's mechanism part.

Two CSVs: `<job_id>_steps.csv` and `<job_id>_levels.csv`.

#### 9.7.3 Validity

  - **P0a, the parent is `ic_s23_c`'s.** The model's own fields (`rhoa`, `ta`,
    `hus`, `clw`, `cli`, `wa`, `pr`, `lwp`, `arup`, `husup`, daily and
    6-hourly; twelve files, all of which must be there in both runs) match
    bit for bit at every common output time. If not, the
    probe measures another parent. Its numbers are reported, and nothing is
    attributed to W42's rises.
  - **P0b, the tags' fields against `ic_s23_c`.** Reported, not a gate. Where
    they differ, the rises may differ, and P2 says how.
  - **P1** as in 9.3.
  - **P2** as in 9.3, with the first probe's value (W47) beside W42's.
  - **P3, #118's latch.** At every step whose ratio passes `1e-4`, the latch
    reads 1 at that step's end. A step within `1e-9` (relative) of the level
    is reported as at the level, not counted, since the driver computes the
    ratio itself and not with #118's function. A failure is a defect of
    #118. It is reported, and it does not touch the attribution.

#### 9.7.4 Reading, per rise

  - **9.4's shares and verdict,** read as `ic_miss_score.py` reads them,
    over 9.4's probes. The leave-one-out probes are not among them.
  - **Leave-one-out.** `ℓ_t ≥ 0.5` **carries** the rise. From 0.1 to 0.5 it
    **contributes**.
  - **The mechanism is shown cell by cell** where its cells hold at least half
    of `R` in the reference's step and at least half of the forcing probe's
    own growth. Otherwise it is **not shown**.
  - **The levels.** The fewest levels that hold half the rise, their
    heights, and each term's part of the rise in them. Also the forcing's
    growth's overlap with the reference's: the sum over levels of the
    smaller positive part, over the reference's positive part. These are
    reported, with no threshold.
  - **The fix's scope,** for the owner's choice between the whole forcing and
    its local terms:
      + subsidence carries a rise: a fix must cover subsidence;
      + only local terms carry it: a fix of the local terms covers it;
      + no term carries it, and the forcing's share is at least 0.5: the
        terms act together, and a fix belongs at the forcing's bracket as a
        whole;
      + the forcing's share is below 0.5: the forcing does not attribute it,
        and 9.4's verdict says whether the rise is unattributed.
  - **The fourth rise** is read by the same rules as the others.
  - **A rise with `R ≤ 0` on `main` is not read.** A rise outside 10% of both
    W42's value and the first probe's is read as `main`'s own rise. Its
    reading does not answer W47's question for that interval.

**Bounded claims,** beside 9.4's:

  - A leave-one-out probe is not additive either. The excess takes a `max`,
    and the bracket gives the tendency to the tags by their shares, so a
    term's effect depends on the others. `ℓ_t` bounds the term's part in the
    forcing and does not isolate it.
  - The mechanism's cells locate where the excess grows. For the reference's
    step they do not show that the forcing's bracket gave the water, since
    other processes act in the same step. For the forcing's probe, they do.

#### 9.7.5 What it means

As 9.5, with the scope of 9.7.4. The owner decides the fix.

#### 9.7.6 Checks and the job

**Before the job:** a short check job from the run tree, with
`IC_PROBE_UNIT=seconds` and a window near the start. It must build all five
models, step, and write both CSVs. `ic_miss_score2.py` must then run on
synthetic inputs made from the first probe's CSV by
`analysis/water/ic_miss_score2_synthetic.py`, which checks its parsing only.

**The job:**

  - `submit_g3.sh` from the clean run tree `../ClimaAtmosResiDyn-ic-probe2-run`,
    at the commit that registers this subsection;
  - `DRIVER=experiments/tag_closure/analysis/water/ic_miss_probe2.jl`;
  - `hpda2_compute`, 2 CPUs, 48 GB, `--time=12:00:00`.

The estimate is 4 to 5 h. The first probe took 3 h 8 min, and the five
leave-one-out probes add five forcing evaluations to each window step.
`analysis/water/ic_miss_score2.py` scores it.

#### 9.7.7 Amended before the run (2026-09-28), after an agent's review

An agent reviewed this subsection and its scripts at `e09e0986`, read-only,
before the job. These changes follow from that review. They were made before
the job was submitted, and nothing of the run had been read:

  - **9.7.4:** the last scope case now leaves "unattributed" to 9.4's
    verdict. Before, it called a forcing share below 0.5 9.5's
    "unattributed" case, which 9.4's rule does not say.
  - **9.7.4:** a rise with `R ≤ 0` is not read, and a rise far from both W42
    and the first probe is read as `main`'s own. Before, a negative `R` or
    forcing growth would have flipped every share's sign.
  - **9.7.3:** P0a needs all twelve model-field files in both runs. Before,
    one matching file passed. P3 gets a rounding band at the level.
  - **Wording:** 9.7.1 names the energy-tag PRs whose code is live. 9.7.2
    and the bounded claims no longer credit leave-one-out with additivity or
    blame the `(dT, dq)` conversion, which is linear.
  - **Committed:** `analysis/water/ic_miss_score2_synthetic.py`, the
    synthetic check that 9.7.6 calls for.
  - **Noted, unchanged:** both score scripts count `large_scale_advection`
    among the local probes, which 9.4's list does not name. This
    configuration has no such probe, so it changes nothing.

The run tree stays at `e09e0986`. The driver, the configuration and `main`'s
code at `cfc2152c` are as registered there, and the check job `13996777`
tested them. This amendment changes only the text above and
`ic_miss_score2.py`.

## 10. The revision of C: the owner's options after W47 and W48 (2026-09-29)

A brief for the owner's decision. It restates what W47 and W48 found, and
lists the options with a recommendation. Nothing here is decided.

**What was found.** At site 23 the region tags hold up to 2.2% more water
than option C's target, `max(ρq_tot, 0)`, against a 0.2% tolerance (W42). The
four rises that no ledger records lie wholly in cells whose parent is at or
below zero (W47). The external forcing's bracket, applied alone, reproduces
each rise. Without its subsidence term it keeps 5% to 16% of that growth, and
without the vertical fluctuation at least 80% (W48, leave-one-out). Cell by
cell, the growth lies where the parent rises but stays at or below zero while
the region tags gain water.

**Why, in the code.** `attribute_tagged_ρq_tot!` gives each region tag its
mask times the parent's gain, `M_k·Δ⁺`, whatever the parent's sign. Where
subsidence adds water to a cell whose parent stays at or below zero, the
region tags gain that water, but the target there stays zero. The follower
already treats the implicit part by the target (its negative-part entry). The
explicit brackets do not.

**The options**

 1. **The brackets give the region tags the target's gain, for every explicit
    process.** Recommended. Production reaches the region tags only where the
    parent is above zero. Where it is at or below zero, the gain goes to the
    negative part, which `q_tag_negative` already reports.
      + It covers subsidence and every other explicit process in one rule, at
        the one place where the gain is handed out.
      + It matches C's definition and the follower's pattern.
      + Where the parent is never at or below zero, the tags are unchanged bit
        for bit (site 26, W42), and no model field changes.
      + The design must still fix how a step that crosses zero is split. The
        bracket works on tendencies, not on a step's increment.
 2. **The same rule for the external forcing only,** subsidence included.
      + At site 23 it gives the same result, because the whole explicit
        tendency's share equals the forcing's in every rise (W47).
      + It leaves any other explicit process with the same flaw, where a
        case has one.
 3. **A correction to the target at each step's end,** with its own ledger:
    move each cell's excess over the target to the negative part.
      + It catches any source, known or not.
      + But it corrects after the fact rather than attribute correctly, and it
        hides where the excess comes from. That is the leakage monitor the
        record chose not to destroy (the partition repair's docstring).
 4. **Accept C as it is,** and document the miss.
      + Site 23's water results are not scored anyway. Its parent's negative
        water reaches 10.8% of its water in W48's windows, against the
        contract's `1e-4`, and #118's flag marks every row after it.
      + But the tags keep drifting from their target wherever the parent goes
        negative. OD7, which waits on site 23, stays blocked.

**After a choice of 1, 2 or 3:**

  - a design subsection with its pre-registered validation: section 8's rules
    V1 to V5 again at sites 23 and 26 (90 days), and the probe's windows, where
    the rises should go;
  - a PR against `main` with the rule, its unit tests and parity;
  - the validation runs.

## 11. The revision of C: the explicit brackets give the region tags the target's gain (2026-09-29)

The owner chose option 1 of section 10 on 2026-09-29 (DECISIONS.md): the
explicit brackets give the region tags only the target's gain, for every
explicit process. Where the parent is at or below zero, the gain goes to the
negative part. This section says how it is built, and registers its
validation before any run. Nothing in 11.7 to 11.9 changes after the runs.
The code is on `claude/option-c-revision`, from `main` at `43b01ca1`.

*Added 2026-09-30:* the owner extended the rule to the implicit bracket, the
source tags and the transfers under `water_tag_precipitation: true`, and asked
for a ledger of the withheld gain (11.10, questions 3 to 6). 11.11 says how.
11.7 carries the dated amendments, made before any run.

### 11.1 The rule, per bracket

Each explicit process that writes `ρq_tot` sits in a bracket
(`open_applied_update!`, `close_applied_update!`). The bracket takes the
process's tendency of `ρq_tot`, `Δ`, and gives each tag its part
(`attribute_tagged_ρq_tot!`, whose kernel is `_accumulate_water_tag!`). Until
now a partition tag `k` took

    M_k·max(Δ, 0) + φ_k·min(Δ, 0),

its mask times the gain, and its share `φ_k = ρq_tag_k / ρq_tot` of the loss.
`φ_k` is zero where `ρq_tot ≤ 0`.

The partition's target is `T = max(ρq_tot, 0)`. At the state where the
tendency is evaluated, the process changes `T` at the rate

  - `Δ` where `ρq_tot > 0`;
  - `0` where `ρq_tot < 0`;
  - `max(Δ, 0)` where `ρq_tot` is zero: a gain lifts the parent into the
    positive range, and a loss takes it below zero.

The loss half already follows this. Where the parent is positive, the shares
of a closed partition sum to one. Where it is at or below zero, they are
zero. The gain half does not follow it: it hands out `max(Δ, 0)` whatever the
parent's sign. That is the defect W47 and W48 found.

**The rule.** A partition tag's gain from a bracket is

    M_k·G(Δ, ρq_tot),   G = 0 where ρq_tot < 0, and max(Δ, 0) elsewhere.

So on a closed partition a bracket's tendency is the target's tendency, in
both halves. Where the parent is below zero, the tags do not change, and the
parent's gain fills its negative part, which `q_tag_negative` reports.

  - `G` is `water_tag_target_gain(Δ, ρq_tot)`, which is
    `ifelse(ρq_tot < 0, 0, max(Δ, 0))`. Where the parent is not negative it
    is `max(Δ, 0)`, the same operation on the same numbers as before. So the
    tags are unchanged there, bit for bit.
  - A parent of `-0.0` is not below zero, so its gain goes to the tags. The
    target keeps `-0.0` as the parent (8.1), so this is the target's gain,
    and a run whose parent is never negative is unchanged.
  - The rule applies to the partition tags only: those with a region and no
    source. A source tag, or a region tag that lists sources, keeps
    `max(Δ, 0)` (11.6). *Extended 2026-09-30 (question 4):* every tag that
    receives the label takes the rule (11.11.4).

Per bracket:

| bracket's label                | where                                          | what changes                                                                             |
|:------------------------------ |:---------------------------------------------- |:---------------------------------------------------------------------------------------- |
| `subsidence`                   | `remaining_tendency!`                          | the rule                                                                                 |
| `large_scale_advection`        | `remaining_tendency!`                          | the rule                                                                                 |
| `external_forcing`             | `remaining_tendency!`                          | the rule, on the forcing's net `Δ`: all its terms, its subsidence included               |
| `surface_flux`                 | `remaining_tendency!`                          | the rule                                                                                 |
| `microphysics`, explicit       | `remaining_tendency!`                          | the rule. Under 0M the increment is a sink, so nothing changes in practice               |
| `microphysics`, implicit       | `implicit_tendency!`                           | ~~nothing: the parent's gain, as before (11.6)~~ the rule, extended 2026-09-30 (11.11.2) |
| `microphysics`, split rain-out | `add_split_rainout!` (0M, prognostic EDMF)     | explicit, in copies mode: the rule on the updraft's part (amended, below)                |
| every other label              | radiation, Held–Suarez, the diffusion closures | nothing: they move no water, or are transport, which is never attributed                 |

The label `microphysics` runs on the explicit path only with
`implicit_microphysics: false`. The validation's runs step it implicitly and
split the rain-out.

*Amended 2026-09-30 (the review's coupling-1; the owner asked for the fix).*
The split's row read "nothing: it does not use the kernel". But with updraft
copies and the microphysics stepped explicitly, the bracket returned through
the split before the rule was read, and the copies' kernel gave each
partition tag `Δʲ·φʲ`, `φʲ = clamp(χʲ/q_totʲ)`, whatever the grid parent's
sign. `Δʲ = ρaʲ·∂ₜq_totʲ` is a gain where the updraft's area is negative.
Now the bracket's rule reaches the split. Under the explicit rule a partition
tag's gain from the updraft's part is withheld where the grid parent is below
zero (`water_tag_split_change`), and its loss is kept. A partition tag's
environment part is zero there already: its share is scaled by `S`, the grid
shares' sum, which is zero where the parent is not positive. In the default
mode every partition share carries `S`, so the split gave the partition
nothing there before and still does. On the implicit path the rule is the
parent's, as before. The copies' own terms are unchanged (11.6).

### 11.2 A step that crosses zero

The bracket works on tendencies. The stepper evaluates the explicit tendency
at each stage's state and adds the stages with the tableau's weights `b_i`.
So the rule is evaluated at each stage's parent, and the tableau splits the
step. In a step whose parent crosses zero, the stages whose parent is at or
above zero give the gain to the partition. The others give it to the negative
part.

Where the parent keeps its sign through the step, this is the target's gain
exactly: all of it, or none. Where it crosses, the partition's gain over the
step differs from the target's by a bounded amount. For one process at a
constant rate, with the crossing placed uniformly within the step
(`analysis/water/cr_crossing_check.py`), in units of the process's gain over
the step:

| tableau                    | largest overclaim | largest shortfall | mean over the crossing point |
|:-------------------------- | -----------------:| -----------------:| ----------------------------:|
| ARS222 (the validation's)  | 1.00              | 0.71              | 0                            |
| ARS343 (the model default) | 0.44              | 0.77              | 0                            |

The mean is zero because each tableau's explicit weights meet
`Σ b_i c_i = 1/2`. These numbers are for one process alone. In the model the
implicit solve and the other processes move the parent within the step too,
so they illustrate the size and do not bound it. The miss lands in
`q_tag_res`, where the closure check sees it.

*Considered and not chosen:* at each stage, give the partition the target's
gain over a whole step from that stage's parent, `max(Δ + ρq_tot/Δt, 0)`.
Its largest miss is smaller, 0.5. But it always overclaims, by 0.5 of the
gain per crossing on average, under both tableaux. W42's miss was an
overclaim. A rule biased toward it would add to it.

A loss that takes the parent below zero within a step is split by the stages
in the same way, by the loss half's zero share, and is unchanged.

*Added 2026-09-30 (the review's kernel-1), as facts of the rule as built:*

  - **The sign.** The tableaux' explicit weights include negative ones.
    ARS222 has `b = (-0.7071, 1.7071, 0)`, and ARS343
    `b = (0, 1.2085, -0.6444, 0.4359)`. So in a crossing step the partition's
    gain from a pure source can be negative, and a partition tag that holds
    nothing can end the step below zero, which `main` cannot do. With
    ARS343, a gain that lifts the parent from `-s·G·Δt`, `s` in
    `(0.436, 0.718]`, reaches only stages 3 and 4, and every partition tag
    takes `-0.2085·M_k·G·Δt`. With ARS222, a
    parent at or above zero at the step's start that another process takes
    below zero by stage 2 gives `δ·M_k·G·Δt = -0.7071·M_k·G·Δt`. The miss's
    size is within the table above (ARS343's shortfall of 0.77 is
    `(1 - 0.436) + 0.2085`). The negative values go to the partition repair
    (`led_fix`, which V5 scores) or to `q_tag_res`.
  - **The jump at zero.** With ARS222, a parent a rounding amount below zero
    at the step's start (`-1e-30`) gives the partition `1.7071·G·Δt`, while
    `+0.0` or `-0.0` gives `G·Δt`. So the mean of zero over the crossing
    point holds only where crossing points spread evenly through the step.
  - Both are pinned by a unit test that runs one ARS222 step and one ARS343
    step on a scalar cell (`test/tagged_water_tests.jl`). The rule is not
    changed: that is question 2 (11.10). One option the review names: read
    the sign once per step, from the parent at the step's start. That needs
    a tags-only cache field, and gives up the mean of zero.

### 11.3 Under `water_tag_precipitation: true`

The tags' `ρq_tag_<name>` fields then partition the non-precipitating water,
`N = ρq_tot − ρq_rai − ρq_sno`, and option C's target is per compartment
(`water_tag_part_target`). The bracketed processes write `ρq_tot` and neither
`ρq_rai` nor `ρq_sno` (read for subsidence, large-scale advection, the
external forcing and the surface flux). So a bracket's `Δ` is `N`'s change.
The kernel already divides the loss's shares by `N` (`water_tag_parent`). The
rule reads the same parent:

  - the gain reaches the `N` parts where `N ≥ 0`, and fills `N`'s negative
    part where `N < 0`, whatever the sign of `ρq_tot`;
  - the rain and snow parts take no bracketed gain, as before.

Not changed: the moves between a tag's parts. These are the microphysics'
gross flows, the net-flow rule around `tracer_nonnegativity_vapor_tendency!`
and the limiters' follow. They move water between compartments at fixed
`ρq_tot`, and are not a process's gain. Where one moves water into a rain or
snow compartment that is negative, the receiving parts still gain. Whether
these moves should also take the target's treatment is a question for the
owner (11.10). The key is refused under EDMF, so the validation's runs do not
use it. *Extended 2026-09-30 (question 5):* a transfer into a negative
compartment takes the target's treatment (11.11.5).

### 11.4 The follower, the ledgers and `q_tag_negative`

  - **The follower** is unchanged. It corrects each implicit solve's
    increment against the target (8.1). The explicit brackets add their
    parts before the solve's snapshot, so the follower does not see them, as
    before. With the rule the explicit parts follow the target's tendency and
    the follower the implicit part. So both parts of a step now aim at the
    target. *Amended 2026-09-30:* the follower reads the new ledger, and
    gives a crossing's positive part in its own cell (11.11.3).
  - **The ledgers.** The rule writes no ledger. It is not a correction: it
    changes what a bracket attributes, as the loss half's zero share already
    does where the parent is at or below zero. The intervention row counts
    corrections of the tags after the fact (the rescale, the emptying, the
    repair, the follower), and the rule adds none. The withheld gain enters
    no tag, so each tag's own ledgers still hold what their mechanisms
    moved. To measure the withheld gain over a run, a state ledger such as
    `q_tag_exp_negative` would do it, weighted by the stepper as
    `q_tag_inc_negative` is. It is proposed, not built (11.10). The
    validation measures the rule's effect in the probe's windows instead
    (11.7). *Amended 2026-09-30 (question 6):* the rule writes
    `q_tag_exp_negative`, and `q_tag_inc_negative` records the follower's
    `N'` (11.11.6).
  - **`q_tag_negative`** is unchanged: `min(ρq_tot, 0)`, per unit mass, the
    parent's own. The withheld gain raises it toward zero with the parent.
    `q_tag_res`, the target less the region tags, no longer takes the
    brackets' gains in negative cells. W42 found it down to −3.9e-4 kg/kg
    where the tags overshot.
  - **The parent's negative water accumulator and #118's check** read `ρq_tot`
    only, and are unchanged. So is the closure check, which compares the
    partition with the target.

### 11.5 Why every parent field stays bit for bit

  - The change sits in one kernel, `_accumulate_water_tag!`, which writes
    `Yₜ.c.ρq_tag_<name>` only. It reads the parent and the tags, as before.
    The only new read is the parent's sign, a field the kernel already read
    for the loss's share.
  - No model field reads a tag. The tags are passive: no tendency, limiter,
    constraint or Jacobian block of a model field reads them. The integration
    groups `tagging_water*` test this ("The model's fields do not depend on
    the tags").
  - No new state field, cache field, callback or configuration key. The
    state's layout, the Jacobian, the solver's work and the callbacks' times
    are `main`'s.
  - The implicit bracket and the rain-out split are not touched.
  - Checked (11.8): the unit tests, the integration groups `tagging_water*`,
    and a 10-day run at site 23, where the parent goes negative after day 9,
    with and without tags, on the revision and on `main` at `43b01ca1`. The
    prognostic state at day 10 and every model output field are compared
    with `isequal`.

*Amended 2026-09-30:* the extension adds state and cache fields and touches
the implicit bracket and the rain-out split. 11.11.8 gives the argument for
it, in place of the third and fourth points above.

### 11.6 Not changed, and why

  - **Source tags** (`evap`, `fcg`) and region tags that list sources. They
    are outside the partition and its target, so the approved rule does not
    reach them. They keep the parent's gain. In a cell whose parent is below
    zero such a tag gains a process's water and, since its share there is
    zero, loses none. Question for the owner (11.10). *Extended 2026-09-30
    (question 4, 11.11.4).*
  - **The implicit microphysics bracket** keeps the parent's gain. The
    approved rule covers the explicit processes. Under 0M its increment is a
    sink, except where a subdomain's area is negative outside the rain-out
    split. Under `water_tag_transport: increment` the follower corrects the
    solve's increment against the target anyway. The diagnostics' rain-out
    (`add_rainout_increments!`, for `pr_tag`) takes the rule of the
    `microphysics` bracket as the run steps it: the parent's gain when the
    microphysics is implicit, the target's when explicit. *Extended
    2026-09-30 (question 3, 11.11.2).*
  - **The 0M rain-out split under EDMF** (`add_split_rainout!`) is a signed
    attribution by subdomain and does not use the kernel. ~~Unchanged.~~
    *Amended 2026-09-30:* stepped explicitly in copies mode, it withholds a
    partition tag's gain from the updraft's part where the grid parent is
    below zero, and keeps its loss (11.1, the amendment). What the copies
    do is unchanged: each copy loses its share of `q_totʲ`'s rain-out
    (`water_tag_copies_microphysics_tendency!`), and the copies' repair
    closes them onto `max(q_totʲ, 0)` after the filter at every step. Where
    the grid parent is below zero, a loss from the updraft's part still
    takes water from the partition, by the copies' shares. The rule does
    not cover losses, so that is left as it is.
  - **The updraft copies' surface flux** (`water_tag_copies_surface_flux_tendency!`)
    is unchanged. The copies' repair closes them onto `max(q_totʲ, 0)` after
    the filter at every step (8.1).
  - **The moves between a tag's parts** under `water_tag_precipitation: true`
    (11.3). *Extended 2026-09-30 to the transfers into a negative compartment
    (question 5, 11.11.5).*

### 11.7 The validation, pre-registered before any run

The configuration is W42's (8.2): the GCM-driven column with the radiation's
seed reset, prognostic EDMF, 0M, 60 levels to 40 km, `dt` 10 s, ARS222, one
Newton iteration, 90 days, both families, the water tags `pbl`, `free`,
`evap` and `fcg` under the follower, each tag's own ledgers every 6 hours.
The configs are W42's and W48's with only the job id changed.

| run               | site | run tree       | config                | what for                            |
|:----------------- |:---- |:-------------- |:--------------------- |:----------------------------------- |
| `cr_s23`          | 23   | the revision's | `cr_s23.yml`          | V1, V2, V2b, V4, V4b, V5            |
| `cr_s23_untagged` | 23   | the revision's | `cr_s23_untagged.yml` | V4's twin                           |
| `cr_s23_main`     | 23   | `main`'s       | `cr_s23_main.yml`     | V4b's control; reported: C as it is |
| `cr_s26`          | 26   | the revision's | `cr_s26.yml`          | V2, V2b, V3, V4, V4b, V5            |
| `cr_s26_untagged` | 26   | the revision's | `cr_s26_untagged.yml` | V4's twin                           |
| `cr_s26_main`     | 26   | `main`'s       | `cr_s26_main.yml`     | V3's and V4b's control              |
| `cr_probe_s23`    | 23   | the revision's | `cr_probe_s23.yml`    | the windows, W0 to W4               |

**The run trees.** The revision's, `../ClimaAtmosResiDyn-crev-run`: the
record at the commit that registers this section, with
`claude/option-c-revision` merged in at the commit the owner approves.
`main`'s, `../ClimaAtmosResiDyn-crev-main-run`: the same record commit with
`main` at `43b01ca1` merged in. The revision branches from `43b01ca1`, so
the two trees differ only in the revision's commits. Both hold #128's cap on
ClimaParams and the same Manifest.

**The controls.** The untagged twins test the parity with the tags on (V4).
The runs on `main` are the same configuration without the revision. They
test that the revision moves no model field (V4b), and at site 26 that it
moves no tag ~~where the parent is never negative~~ before the parent is
first below zero in the column (V3, amended 2026-09-30). W48's probe is the
windows' control.

**The pass rules.** Section 8.3's, with its thresholds, and V4b:

| #   | what                                                                           | pass                                                                                                                                                                                                                                                                                                                                                        |
|:--- |:------------------------------------------------------------------------------ |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V1  | `cr_s23` completes                                                             | it reaches day 90                                                                                                                                                                                                                                                                                                                                           |
| V2  | the partition against the target, at every closure check to day 90, both sites | gross relative to `∫max(ρq_tot, 0)` at most 0.2% (OD3's water closure row)                                                                                                                                                                                                                                                                                  |
| V2b | the named remainder                                                            | `q_tag_res + q_tag_negative + Σ region tags = q_tot` at every daily output, to 1e-12 of the column's largest `|q_tot|` at that output                                                                                                                                                                                                                       |
| V3  | site 26's water tags, `cr_s26` against `cr_s26_main`                           | bit for bit at every daily output; or ~~different only in cells and after times where the untagged twin's parent was ever negative (expected: nowhere)~~ *(amended 2026-09-30, question 9)* every differing value lies at an output time at or after `t*`, the first time the parent is below zero anywhere in its column (expected: never, so bit for bit) |
| V4  | every model field of each revision run against its untagged twin               | bit for bit at every daily output                                                                                                                                                                                                                                                                                                                           |
| V4b | every model field of each revision run against the same run on `main`          | bit for bit at every daily output                                                                                                                                                                                                                                                                                                                           |
| V5  | intervention, both sites, from the ledgers                                     | reported: `q_tag_inc_negative`'s per-step gross a day; the partition repair's retained gross at most 0.5% a day; each tag's `led_fix` at most 2% of its inventory, days 1 to 90; *added 2026-09-30, reported:* `q_tag_exp_negative`'s per-step gross a day, and each source tag's negative water                                                            |

Reported beside V2: `cr_s23_main`'s largest gross, C as it is on `main`, and
the first check above 0.2% in each run. As in W42, the contract's
negative-water row leaves site 23's water results unscored above 1e-4. V2 is
registered without that exclusion, as 8.3 registered it.

**How V2 fails, if it does.** As in 8.3: the ledgers (V5) and the windows
show which path carries the rest of the miss, and the owner decides.

**The windows.** `cr_probe_s23` is the probe of 9.7 on the revision's code:
the same driver, `analysis/water/ic_miss_probe2.jl`, the same windows (days
30.3–31.0 and 52.4–53.3) and the same five rises. Each share divides by W48's
rise `R48` in that interval, from `ic_miss_probe2_s23`. The revision should
remove the rises, and a share of a rise near zero has no meaning.

| #  | what                                                                                | rule                                                                                                                                     |
|:-- |:----------------------------------------------------------------------------------- |:---------------------------------------------------------------------------------------------------------------------------------------- |
| W0 | the parent is W48's                                                                 | the model's twelve field files match `ic_miss_probe2_s23`'s bit for bit at every common output time, all there in both runs (9.7.3, P0a) |
| W1 | the forcing's bracket alone, in the mechanism's cells (9.7.2, point 3)              | its growth of the excess is 0 at every step of both windows                                                                              |
| W2 | the forcing's bracket alone, per rise                                               | its growth of the excess is below 0.1 of `R48`: it neither attributes nor contributes, by 9.4's levels                                   |
| W3 | the reference's rise, per rise                                                      | reported: `R` over the water beside W48's, its split in N, P and X, each probe's growth over `R48`                                       |
| W4 | the whole explicit tendency alone, per rise                                         | reported: its growth of the excess over `R48`                                                                                            |
| W5 | the reference's rise, per rise, the control included (added 2026-09-30, question 7) | the rise goes: `R ≤ 0.1 R48`                                                                                                             |

W1 holds by construction, if the rule is built as 11.1 says: a region tag's
tendency from the forcing's bracket is zero in a cell whose parent is below
zero, and a cell at zero whose parent stays at or below zero after the step
had no gain. So W1 tests the build in the run.

~~*Proposed, waiting for the owner:* "the rise goes" if `R ≤ 0.1 R48`, 9.4's
level for a share that does not contribute. It is printed, not scored, until
the owner sets it or another value.~~ *Set by the owner on 2026-09-30
(question 7), before any run:* W5 above, scored (the amendments below).

**The budgets.** Every threshold above is section 8.3's, OD3's or 9.4's.
~~None is new, apart from the proposal just above.~~ None is new: W5's level
is 9.4's (amended 2026-09-30).

**Scoring.** `analysis/water/cr_validate.py` scores V1 to V5 and V4b.
`analysis/water/cr_windows_score.py` scores W0 to W5. Both were run before
any run on W42's and W48's outputs in place of the new ones. `cr_validate.py`
reproduces W42's numbers (2.243e-2 at site 23, `pbl`'s `led_fix` 2.033e-2).
`cr_windows_score.py` fails W1, W2 and W5 on W48's own probe, as it should.
The amended scripts' checks, made on 2026-09-30 before any run, are in the
last item of the list below.

**Amendments of 2026-09-30, made before any run.** The owner decided
questions 6, 7 and 9 of 11.10 on 2026-09-30, and the extension of 11.11
changes what the runs carry. No run of 11.9 has been read. The 30-day parity
of 11.8 has been, at site 23, with its closure at day 30: the region tags
above the target by 4.7e-7 of it on the revision, and by 4.9e-3 on `main`.
That is 0.3 days before window 1 opens. The level `0.1 R48` was proposed on
2026-09-29 (`d719fa86`), before that result, and is unchanged. *(After the
review of 11.11's draft, which had said that nothing of any run had been
read.)*

  - **W5, question 7.** The rise goes if `R ≤ 0.1 R48`. `R` is the rise in
    `cr_probe_s23`, the sum of its per-step `ref_total` over the rise's
    interval. `R48` is the same sum in `ic_miss_probe2_s23`. 0.1 is 9.4's
    level below which a share does not contribute. W5 scores each of the five
    rises, the control included. A rise with `R ≤ 0` goes. A rise whose `R48`
    is not above zero cannot be scored, and W5 then fails for missing data.
    Expected, not shown: all five go. W48 found each rise's growth, the
    control's too, wholly in cells whose parent stays at or below zero while
    it rises and the region tags gain water (the mechanism holds 1.00 to 1.06
    of each rise). The rule withholds that gain. If a rise does not go, W3's
    split into N, P and X, W4 and the ledgers, `q_tag_exp_negative` among
    them, show where the rest lies, and the owner decides. W3 stays reported.

  - **V3, question 9.** Its fallback clause read "different only in cells and
    after times where the untagged twin's parent was ever negative". The tags
    are transported. A gain withheld in one cell changes the tags in the
    other cells of its column, whose parent was never negative. So that
    clause could fail with correct code. It now compares by column and time.
    For each column, `t*` is the first time the parent is below zero anywhere
    in it. Before `t*` the revision's water tags must be `main`'s bit for bit.
    From `t*` on, any value in that column may differ. `t*` is the earliest
    of these times:

      + the first output of `hus` with a value below zero in the column:
        `cr_s26`'s, daily and 6-hourly, and `cr_s26_untagged`'s, daily;
      + the time of the first row of `cr_s26`'s `water_tag_audit.csv` whose
        `negative_water_interval_events` is above zero. It counts the accepted
        steps' end states since the row before;
      + the time of the first row of the same table whose
        `exp_negative_retained` is above zero. Then `q_tag_exp_negative` has
        changed, so the rule withheld a gain at some stage. The rule reads the
        parent at each stage, which neither the outputs nor the steps' end
        states show;
      + if `q_tag_exp_negloss` is built (11.11.13), the first row whose
        `exp_negloss_retained` is above zero, for the same reason.

    All of them see the same parent, since V4 and V4b hold it bit for bit.
    The table's rows fall every 6 hours, on the grid of the outputs, so a
    row's time bounds the first output that can differ. The audit's times are
    global, and site 26 is one column, so they are its column's. Without a
    `t*`, V3 is bit for bit, as before. *A bound, after the review:* from `t*`
    on the fallback accepts every difference. So it cannot tell a change the
    rule makes from, say, a defect of the follower that starts after `t*`.
    The primary rule, bit for bit, is unchanged.

  - **V5, two reported items (questions 4 and 6).** `q_tag_exp_negative`'s
    per-step gross a day, from the audit's `exp_negative_retained`. And each
    source tag's negative water: the daily column integral of
    `min(ρq_src, 0)` over that of `max(ρq_src, 0)`, and the first daily output
    where it is below zero (11.11.4). No threshold. Missing data are printed,
    not failed.

  - **What V2 and W5 score (after the review).** The revision's runs carry
    the explicit rule, Q3, Q4, the follower's amendment, and
    `q_tag_exp_negloss` if built. V2 and W5 score that bundle. They bound the
    rule's part, and do not isolate it.

  - **A path named before the runs (after the review).** The follower gives
    an unshared loss in a cell below zero to the partition elsewhere in the
    column (11.11.3). That can lift the partition above its target in
    positive cells, which V2 and the windows measure. If
    `q_tag_exp_negloss` is not built and V2 or W5 fails, `q_tag_inc_negative`
    in the rise's cells is read first.

  - **The configs and the probe driver (question 6).** `cr_s23.yml`,
    `cr_s26.yml` and `cr_probe_s23.yml` add `q_tag_exp_negative` and
    `q_tag_exp_negative_gross` to their 6-hourly and daily diagnostics. The
    probe driver adds `:q_tag_exp_negative` to `LEDGERS`, a reported column
    (11.11.6). So the configs are W42's and W48's with the job id and these
    diagnostics changed.

**The score scripts' changes for these amendments.** They are made, and
checked, before any run (11.11.11, recheck 8). Items 1 to 7 are made, in the
commit that carries this text. Item 8 is run and its result is at the end of
the list. The scripts add two behaviours that the list does not state. First,
a rise with `R48 ≤ 0` also fails W2, since its share divides by `R48` and has
no meaning (the old script would divide by zero, or pass a negative share).
Second, the thickness in V5's source-tag item is rebuilt by faces half way
between the cell centres, with the end cells mirrored. On site 23 it gives
`∫ρ max(q_tot, 0) dz` within 0.4% of the closure table's `total`.

 1. `cr_windows_score.py`, its docstring: W5 is scored, with the owner's
    date, and the text "proposed … waits for the owner" goes.
    `PROPOSED_RISE_GOES` becomes `RISE_GOES = 0.1`, with the comment "Set by
    the owner on 2026-09-30 (question 7), before any run".

 2. `cr_windows_score.py`, `score_rise`: after W2,
    `goes = R48 > 0 and R <= RISE_GOES * R48`, printed as "W5: R/R48 …, the
    rise goes if R <= 0.1 R48" through `verdict(f"W5 {a}-{b}", goes)`. W3's
    line drops the proposed rule. The branch for steps that do not match
    W48's fails W5 for that rise too. The exit clause becomes "It exits 1 if
    W0, W1, W2 or W5 fails or the data are missing", and the result line "W0
    to W2 and W5 pass".

 3. `cr_validate.py`, V3: `t*` per column in place of `ever_negative` per
    cell. `hus` comes from `cr_s26`, daily and 6-hourly, and from
    `cr_s26_untagged`, daily. The vertical axis is found by the NetCDF
    dimension name `z`, and every other index but time is a column (site 26
    has one). From `cr_s26`'s `water_tag_audit.csv` it takes the first row
    with `negative_water_interval_events > 0`, the first with
    `exp_negative_retained > 0`, and the first with
    `exp_negloss_retained > 0` if that field exists. A field missing from the
    table is printed and skipped, not failed. `t*` is the earliest time
    found, or none. A tag passes if it is bit for bit, or if every differing
    value in a column lies at an output time of at least `t* − 1e-6 s`. It
    fails if a value differs and there is no `t*`, or before it. The script
    prints `t*` and its source. The docstring's V3 line follows.

 4. `cr_validate.py`, V5: the two reported items above.
    `exp_negative_retained` a day, as `per_day` computes the others. The
    source tags' negative water from the daily `q_tag_evap`, `q_tag_fcg` and
    `rhoa`, with the cells' thickness rebuilt from the cell centres. Missing
    data are printed, not failed. The docstring's V5 list follows.

 5. `ic_miss_probe2.jl` (`:55-66`): `:q_tag_exp_negative` joins `LEDGERS`.
    That gives the reported column `ledger_q_tag_exp_negative_in_excess`,
    which `cr_windows_score.py` already prints with the other ledgers. No
    scored rule changes. The driver skips a ledger that the state lacks
    (`:332`).

 6. The three configs: the diagnostics above. The `_main` and `_untagged`
    configs stay: `main` has no such field, and the untagged runs have no
    tags.

 7. New synthetic checks, committed beside the scripts as
    `ic_miss_score2_synthetic.py` was. `cr_windows_score_synthetic.py`:
    `R = 0.05 R48` and `R = 0.1 R48` pass, `R = 0.15 R48` fails, and
    `R48 ≤ 0` fails. `cr_validate_v3_synthetic.py`: bit for bit passes; a
    difference before `t*` fails; a difference at or after `t*`, in cells
    never negative, passes; a difference with no `t*` fails; a `t*` that only
    the ledger sets, with no negative `hus` and no event, lets a later
    difference pass.

 8. Before any run, both scripts run on W42's and W48's outputs in place of
    the new ones. Expected: `cr_validate.py` reproduces W42's numbers, and
    reports the audit's `exp_negative_retained` missing, without failing.
    `cr_windows_score.py` fails W1, W2 and W5 for every rise. The result goes
    into the Scoring paragraph above.

    *Result, 2026-09-30.* Run with W42's runs
    (`ic_s{23,26}_{c,untagged,before}`) standing in for
    `cr_s{23,26}{,_untagged,_main}`, and W48's probe
    for `cr_probe_s23`, through links under
    `$SCRATCH/claude_work/crev_score_smoke`. `cr_validate.py` gives the same
    lines as before its change, apart from the added ones: V2 at site 23
    2.243e-2 (fails, first above 0.2% at day 29.25), `pbl`'s `led_fix`
    2.033e-2 (fails), the control's 1.293 from day 10, V2b, V4, V4b and V3
    bit for bit at 91 outputs. The added lines say "not available" for
    `exp_negative_retained`, and skip `negative_water_interval_events` and
    `exp_negative_retained` as "not in the table". W42's audit has neither
    column. Site 26's `t*` is none. The source tags' negative water: `evap`
    at site 23 −3.9e-7 of its positive water at most, `fcg` −2.3e-2, first
    below zero at days 11 and 2. `cr_windows_score.py` passes W0 (12 of 12
    files), fails W1 in both windows, and fails W2 and W5 for all five rises
    (`R/R48` = 1, as the probe is W48's own). Its other lines are as before.
    The synthetic checks hold: `cr_windows_score_synthetic.py` (W5 passes at
    0.05, 0.10 and −1 of `R48`, fails at 0.15 and at `R48` = 0) and
    `cr_validate_v3_synthetic.py` (13 cases). Mutant M7, W5 printed but not
    scored, fails the `R = 0.15 R48` case. Mutant M9, V3's old clause per
    cell, fails 7 of the 13 cases, among them the difference after `t*` in a
    cell never negative. To exercise the fallback on a real run, V3 was also
    pointed at site 23's W42 run against its control: `t*` is day 9.25
    (`hus` 6-hourly), the first difference is at day 10, and all four tags
    pass.

### 11.8 Checks before the runs

  - **Unit tests** (`test/tagged_water_tests.jl`, both float types): the
    kernel on a column with a negative cell. The gain is zero there and bit
    for bit the old value elsewhere, `-0.0` and `+0.0` included. The source
    tags and the loss half are unchanged. Under the key the rule follows
    `N`'s sign, not `ρq_tot`'s. The implicit bracket's rule is the old one,
    bit for bit. On a closed partition, a bracket's tendency is the target's.
    One Euler step from a closed partition, with a gain in a cell that stays
    negative, leaves the partition's excess over the target where it was.
  - **A mutant:** the rule removed, in its own detached worktree. The new
    tests must fail there.
  - **The affected test files** in a local Slurm job.
  - **Parity:** site 23 for 10 days (`cr_parity_{tags,untagged}_{rev,main}.yml`),
    with the state saved at day 10 and the ten model fields every 6 hours.
    The parent first goes negative at day 9.25 (W48's closure table), ~~so the
    rule acts in the last day~~ (it did not; below). Scored by `analysis/water/cr_parity.py` (the
    output) and `analysis/water/cr_parity_state.jl` (the state): every model
    field `isequal`, the revision against `main` with and without tags, and
    tags on against off on each tree. The water tags, the revision against
    `main`, are reported: the same until the rule acts, then different.

*Checked 2026-09-29, before any validation run* (the revision at `6307091c`;
`c756390d` changes only two tests):

  - **Unit tests:** `tagged_water_tests.jl` passes (328, and the new testset
    76 of 76), and so does `tagged_water_precipitation_tests.jl` (jobs
    `13999599`, `14000300`).
  - **The mutant** (`water_tag_target_gain` returning `max(Δ, 0)`): 12 of the
    76 new tests fail, and 4 in the precipitation file. Nothing else fails
    (jobs `13999600`, `14000301`).
  - **The integration groups:** all nine `tagging_water*` files pass (jobs
    `13999601` to `13999609`).
  - **Parity:** in all four pairs, every model field is bit for bit: the 20
    model field files at every output to day 10, and the prognostic state
    at day 10 (10 model fields, `isequal`). `output/cr_parity/`.
  - **But the rule did not act in these runs.** Every water tag file, and the
    tags in the state, are the same on the revision and on `main`. The parent
    was below zero from day 9.25 on (4 closure rows, at most 0.25% of the
    water). So no explicit bracket gave a gain to a cell below zero by day 10.
    The check shows parity with the new code in place, not with the rule
    acting. When the rule first acts at site 23 is not known. W42's excess
    first passed 0.2% at day 29.25. A longer rerun waits for the owner
    (11.10).

*The 30-day rerun* (question 8, decided 2026-09-29): configs
`cr_parity30_{tags,untagged}_{rev,main}.yml`, the 10-day configs with
`t_end` and the saved state at 30 days. The run trees are the same two with
this record commit merged in, so their model code is unchanged. Scored by
`cr_parity.py OUTPUT_ROOT cr_parity30` and
`cr_parity_state.jl OUTPUT_ROOT cr_parity30 30`, with the pass rule of 11.10,
question 8.

*Result of the 30-day rerun, 2026-09-30* (jobs `14005271` to `14005274`, all
exit status 0; `output/cr_parity30/`). Two independent scorings agree on every
verdict. Against Q8's rule:

  - **Model fields: pass.** In all four pairs (revision against `main`, with
    and without tags; tags on against off, on each tree) the 20 model field
    files are bit for bit at every output to day 30. The day-30 state agrees
    in all 10 model fields. The state script compares with `isequal`. A second
    scoring found the 116 variables and the 11 state components byte
    identical.
  - **Region tags: they differ, so the rule acted.** Revision against `main`,
    tags on. The last identical outputs are day 11.0 (daily) and day 11.25
    (6-hourly). The first differing ones are day 12.0 and day 11.5. So the
    tags first differ after day 11.25 and by day 11.5. Most of the ledgers
    that differ also do so from day 11.5. The `repairnet` ledgers first
    differ at day 11.75. The closure file first differs at `t = 993600 s`,
    day 11.5. From day 11.5 the region tags differ at every 6-hourly output
    to day 30.
  - **Size.** The state at day 30, each field against `main`'s largest
    value: `ρq_tag_free` 7.2e-02, `ρq_tag_fcg` 9.8e-03, `ρq_tag_pbl`
    1.7e-03, `ρq_tag_evap` 1.2e-03. The least favourable number is in the
    state's fix ledgers: `q_tag_led_fix_pbl` and `q_tag_led_fix_free` differ
    by 6.1 of `main`'s largest value (second scoring). In the output files,
    over all outputs to day 30, it is 5.24 of the largest value for
    `q_tag_fix_free` and `q_tag_fix_pbl`, and 1.00 for `q_tag_res`. At day 30
    `q_tag_pbl` differs most at z = 435 m (second scoring). There the revision
    has 0 and `main` 2.87e-5 kg/kg, so the difference is all of `main`'s value,
    and 1.8e-3 of `main`'s column maximum. `q_tag_free`'s pointwise ratio of
    2.8e14 sits on a near-zero denominator (`main` 3.3e-32 kg/kg) and says
    little. In column totals from the day-30 state, revision minus `main`
    over `main` is -8.8e-04 for pbl and -9.7e-03 for free (second scoring,
    with `dz` rebuilt from the cell centres). The closure file at day 30 has
    the region tags above the non-negative target by 4.7e-07 of it on the
    revision and by 4.9e-03 on `main`.
  - **Not affected.** The energy tags are bit for bit. So are the evap and
    fcg fix tags and the `negative`, `led_empty` and `led_rescale` tags. The
    tags-off pairs and the tags-on-against-off pairs show no difference in
    any model field.
  - **Not known.** The source tags `q_tag_evap` and `q_tag_fcg` also differ
    from day 11.5. Section 11.6 keeps the parent's gain for them, so the
    change is indirect. Its path was not traced. `q_tag_res` differs too, but
    it is the target less the region tags (11.4), so it follows them. The
    onset is not localised inside the output spacing. The rule was not read
    from the tendency directly, only from the tags.

The rule of Q8 is met. No run was extended.

*Rechecks after the review's fixes, 2026-09-30* (`claude/option-c-revision`
at `a4b492ec`; 11.1's amendment, the split in copies mode):

  - **Unit tests:** pass (job `14010375`): 328, the bracket testset 76 of 76,
    the stage testset 20 of 20, and the precipitation file with no failure.
  - **Mutants:** the rule removed fails 12 of 76 in the bracket testset and
    the precipitation file (`14010376`; the stage testset is after the first
    failing testset and did not run on it). The explicit rule at the implicit
    site fails only the implicit-site testset (`14010378`). The split
    ignoring the rule (`14010377`) fails the two coupling-1 tests that test
    the withheld gain (lines 284 and 298 of
    `tagged_water_edmf_0m_explicit_integration.jl`), and nothing else.
  - **Integration:** eight of nine `tagging_water*` files passed first
    (`14010379` to `14010387`). `tagged_water_edmf_0m_explicit_integration.jl`
    (`14010383`) failed the new coupling-1 test at line 291. A diagnostic
    run (`14012457`, copies mode only) showed a test defect, not a code one:
    `eachindex` of the 5-d parent array gives Cartesian indices, which never
    equal the linear `k`, so the modified cell itself was among the "other"
    cells. It is the one differing cell of 30 (grid parent `-1e-6`, where the
    rules differ by design: 6.8e-8 against a scale of 1.7e-7 for `tropo`,
    7.3e-10 against 3.0e-8 for `strat`). The real state has no cell with the
    grid parent below zero. The test now compares by linear index
    (`210eeece`, the code unchanged). Rerun (`14012892`): the file passes,
    64 of 64. The mutant (`14012893`) fails exactly the withheld-gain tests
    (lines 284 and 302) and nothing else.
  - **30-day parity** (jobs `14010408` to `14010411`, `output_0001`):
    Q8's rule passes. In all four pairs every model field is bit for bit, 20
    files each to day 30, and the day-30 state is `isequal` (10 model
    fields). The region tags differ from `main`'s at the end: `q_tag_free` by
    up to 7.2% of its largest value, `q_tag_fcg` 0.98%, `q_tag_pbl` 0.17%,
    `q_tag_evap` 0.12% (in the state at day 30), so the rule acted. `output/cr_parity30b/`.
  - **Against the first 30-day run** (`output_0000`, at `cfb72587`): all 91
    files of the revision's tagged run are bit for bit equal. So the
    review's fixes, coupling-1 included, changed no tag in this
    configuration, which is not copies mode: largest difference 0.

### 11.9 The jobs

From each run tree's root, with `submit_g3.sh`,
`DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl`,
`--account=hpda-c --partition=hpda2_compute --cpus-per-task=2 --mem=48G`:
`--time=08:00:00` for the six 90-day runs, and for the probe
`DRIVER=experiments/tag_closure/analysis/water/ic_miss_probe2.jl` with
`--time=12:00:00`. W42's `ic_s23_c` took 3 h 8 min, and W48's probe 3 h 7
min. So the seven jobs take about 22 job-hours in all, on 2 CPUs each, and
about 3.5 hours when they run in parallel.

They are submitted only after the owner has reviewed this section and the
pre-registration.

*Amended 2026-10-01, before any run (a job limit, not a tolerance):* the
time limit is `--time=24:00:00` for all seven jobs, in place of 08:00:00 and
12:00:00. The partition's maximum is 10 days (`sinfo -p hpda2_compute -o
"%l"`). The 30-day parity runs of 11.8 took 1:33 h (job `14005271`, node not
shared), 3:12 h (`14005273`, node shared) and 1:44 h each (`14010408`,
`14010410`) with tags, and 0:33 to 0:37 h without. So a tagged 90-day run
needs 4.6 to 9.6 h, which can exceed 8 h. The untagged twins need about 1.7
h (3 times 0.33 to 0.37 h), but they take the same limit for one rule. The
configs `cr_s23`, `cr_s26` and `cr_parity30_tags_rev` differ only in the site
(`cr_s26`), `t_end` and the written output, so the cost per model day is
taken as the same. The probe's cost per day is `cr_s23`'s plus its driver,
and its 3 h 7 min of W48 doubles to 6.3 h on a shared node. A limit only
ends a job that is still running. It changes no model, no output and no pass
rule.

### 11.10 For the owner

 1. ~~**The rule at zero.** A parent of exactly zero gives its gain to the
    tags, since the target gains it all (11.1). The decision's words say
    "at or below zero". Confirm that the target's gain decides here.~~
    *Decided 2026-09-29 by the owner:* a parent of exactly zero counts as
    positive, as built. The tags take the whole gain there, and `-0.0` is
    treated the same.
 2. **The stages split a crossing step** (11.2): unbiased, with a miss of up
    to one step's gain per crossing. ~~Accept, or ask for another split.~~
    *Facts added 2026-09-30 (the review's kernel-1; 11.2):* the miss has
    either sign. A pure source can give the partition a negative gain over a
    crossing step (ARS343: `-0.2085·G·Δt`; ARS222, when another process
    takes the parent below zero: `-0.7071·G·Δt`), so an empty tag can end
    the step below zero. With ARS222 the gain jumps at zero: `1.7071·G·Δt`
    from `-1e-30`, `G·Δt` from `±0.0`. A unit test pins these values. The
    option of reading the sign once per step, at its start, keeps the gain
    in `[0, G·Δt]` but gives up the mean of zero. *Decided 2026-09-30 by the
    owner:* accepted.
 3. ~~**The implicit microphysics bracket** keeps the parent's gain (11.6).
    Extend the rule to it, or leave it?~~ *Decided 2026-09-30 by the owner:*
    extend the rule to it, now (11.11.2).
 4. ~~**Source tags and region tags that list sources** keep the parent's
    gain (11.6). Give them the rule too?~~ *Decided 2026-09-30 by the owner:*
    extend the rule to them, now. This needs a new design: what a source
    tag's target is where the parent is at or below zero (11.11.4).
 5. ~~**Transfers into a negative compartment** under
    `water_tag_precipitation: true` (11.3). Give them the target's treatment,
    in a later change?~~ *Decided 2026-09-30 by the owner:* give them the
    target's treatment now, in this PR (11.11.5).
 6. ~~**A ledger of the withheld gain,** `q_tag_exp_negative` (11.4). Build
    it? It adds a state field under water tags.~~ *Decided 2026-09-30 by the
    owner:* build it, a state field under water tags, carried through
    restarts (11.11.6).
 7. ~~**The windows' proposed rule,** "the rise goes" if `R ≤ 0.1 R48`
    (11.7). Set it, another value, or none.~~ *Decided 2026-09-30 by the
    owner:* set it, before the runs: the rise goes if `R ≤ 0.1 R48` (W5,
    amended in 11.7).
 8. ~~**The parity check ran to day 10, and the rule had not acted yet**
    (11.8). Rerun it longer before the validation?~~ *Decided 2026-09-29 by
    the owner:* rerun it to about 30 days, four jobs, the revision against
    `main`, with and without tags, from the same run trees. It passes if
    every model field and the day-30 state are bit for bit and a region tag
    differs from `main`'s at the end, so that the rule acted. If no tag
    differs, that is reported, and the run is not extended without the
    owner. The earlier answer of 13 days rested on a date of day 12 that
    was a misread and is replaced. For the choice: on `main`, W48's closure
    table has C's gross at 3.8e-10 at day 11.25, 1.7e-6 at day 11.5 and
    2.8e-4 at day 11.75.
 9. **V3's fallback clause** (added 2026-09-30, the review's kernel-2). V3's
    rule is bit for bit at site 26, or different "only in cells and after
    times where the untagged twin's parent was ever negative" (11.7). The
    tags are transported, so a gain withheld in one cell changes the tags in
    other cells, whose parent was never negative. So the fallback clause
    could fail at site 26 with correct code, if its parent went below zero
    in one cell once. The primary rule, bit for bit, is not affected. The
    review proposes to compare by column and time, from the first time the
    parent is negative anywhere in the column. ~~V3 is pre-registered, so it
    is not changed here. Change the fallback clause, or leave it?~~ *Decided
    2026-09-30 by the owner:* amend the fallback clause before any run: it
    compares by column and time, from the first time the parent is negative
    anywhere in the column (amended in 11.7).

*2026-09-30:* the points still open for the owner are in 11.11.13.

### 11.11 The extension, as the owner decided on 2026-09-30

The owner answered questions 2 to 7 and 9 of 11.10 on 2026-09-30. The stage
split is accepted (Q2). The rule now also reaches the implicit microphysics
bracket (Q3), the source tags and the region tags that list sources (Q4), and
the transfers into a negative compartment under
`water_tag_precipitation: true` (Q5). A ledger of the withheld gain is built
(Q6). Questions 7 and 9 amend the pre-registration before any run (11.7).

This section says how Q3 to Q6 are built. One agent drafted it and a second
agent reviewed the draft. The draft was then revised with each point of the
review that a check confirmed (11.11.12). Nothing here is built or run. The
code goes on `claude/option-c-revision` after `210eeece`, and the line numbers
below are that commit's. Where 11.1 to 11.6 say what the rule does not reach,
this section holds.

#### 11.11.1 Notation

  - `P` is the partition's parent at the state where a tendency is evaluated:
    `ρq_tot`, or under the key `N = ρq_tot − ρq_rai − ρq_sno`
    (`water_tag_parent`).
  - `Δ` is a bracket's tendency of `ρq_tot`.
  - `M_k` is tag `k`'s mask, and `φ_k = water_tag_fraction(ρq_tag_k, P)` its
    share, which is zero where `P ≤ 0`.
  - `G(Δ, P) = ifelse(P < 0, 0, max(Δ, 0))` is `water_tag_target_gain`.
  - `T = max(P, 0)` is the target, per compartment under the key.
  - `L` is the new ledger, `q_tag_exp_negative` (11.11.6). `L⁻` is the
    optional `q_tag_exp_negloss`.

A parent of `+0.0` or `-0.0` counts as positive (Q1). The target takes the
whole gain there.

#### 11.11.2 The implicit microphysics bracket (question 3)

**The rule.** At the `:microphysics` bracket in `implicit_tendency!`, a
partition tag takes `M_k·G(Δ, P) + φ_k·min(Δ, 0)`, as at the explicit
brackets.

  - Where `P > 0` this is the old value, bit for bit.
  - Where `P` is `±0` it is `M_k·max(Δ, 0)`, the whole gain (Q1).
  - Where `P < 0` it is nothing. The gain fills the negative part, and the
    loss share is zero.
  - The split rain-out in copies mode takes the same rule on this path:
    `water_tag_split_change(TargetGain(), Δʲφʲ, ρq_tot)`.
  - The default split is unchanged. It gives the partition `S·(Δʲ + Δ⁰)`,
    and `S = 0` wherever the grid parent is at or below zero. So at exactly
    `±0` it withholds a gain that Q1 would give (11.11.13).
  - The rain-out diagnostics (`add_rainout_increments!`, `pr_tag`) follow the
    bracket through `microphysics_gain_rule`. That function now returns
    `TargetGain()` on both paths.

**Where the sign is read.** At each evaluation of the implicit tendency, so
at each Newton iterate. With one iteration that is the stage's predictor. A
stage whose predictor is below zero withholds the stage's whole gain, even
where the solve lifts the parent above zero. The stage's increment enters the
step with the implicit weights: `(0, 0.7071, 0.2929)` for ARS222, and
`(0, 1.2085, −0.6444, 0.4359)` for ARS343. Under the follower the part of
such a crossing above zero goes back to the partition in its own cell
(11.11.3). Under tracer transport it lands in `q_tag_res`, at most one
stage's gain per crossing cell.

**Where in `src/`:**

  - `tagged_water.jl:415-418`: `microphysics_gain_rule(atmos) = TargetGain()`
    on both paths. The function stays, so that the bracket and `pr_tag` agree
    by construction.
  - The docstrings at `tagged_water.jl:368-385` and `:533-545`, the comment
    at `implicit_tendency.jl:96-100`, and `tagged_water_rainout.jl:88-105` and
    `:386-389`. The residual's text says that a gain stays there wherever
    either path withholds it.
  - The follower (11.11.3) and the ledger's writer (11.11.6).
  - `docs/src/tagged_water.md:109-123` and `docs/known_issues.md`, issue 7.

**What it changes.**

  - Only 0M. Under 1M and 2M the bracket's `Δ` is zero
    (`microphysics/tendency.jl:138-146`).
  - Under 0M the rain-out is a sink. It is a gain only where a subdomain's
    area is negative.
  - The validation's configuration (0M, prognostic EDMF, the SGS mass flux
    on, no copies) returns through the default split. There every tag's share
    is already zero wherever the grid parent is at or below zero. So, by
    reading the code, Q3 changes no bracket attribution in the validation.
    Only the ledger and the follower change there.

**Duals, GPU, allocation.**

  - `G` is an `ifelse` on a comparison, and a `max`. The fork's overrides
    (`implicit/autodiff_utils.jl:199-226`) compare a `Dual{Jacobian}` by its
    value. So the branch follows the value, and `max(Δ, 0)` carries `Δ`'s
    partials or none. The review checked this with `ForwardDiff` 1.4.6 and the
    overrides. A unit test pins it (11.11.10).
  - `Yₜ.c.q_tag_exp_negative` is dual-typed in `Yₜ_dual`.
  - No water-tag test runs an autodiff Jacobian today. A recheck adds one
    (11.11.11).
  - The new work is in-place broadcasts over existing fields, and one
    preallocated real cache field. The post-solve hook runs on real numbers.

#### 11.11.3 The follower, amended (required by questions 3 and 5)

**Why.** Per cell, the follower's negative part is
`n = min(P_snap, 0) − min(P_new, 0)`, and `N = ∫n dz`
(`tagged_water_increment.jl:328-333`). It assumes that the partition's own
implicit tendencies took the parent's local change. Where the implicit
bracket withholds a gain `w` inside the solve, `n` still holds `−dtγ·w`, but
the partition took nothing. So `N` takes that water from the partition a
second time, in the cells whose mismatch has `N`'s sign. A net inflow into a
negative `N` under the key (Q5) does the same. This is by reading the code,
and by the review's replica of `correct_water_tag_increment!`: in its case S1
the partition ends 0.4 below a target whose column total did not change.

**The amendment.**

  - Snapshot `L` at the stage's start, beside `ρq_tot`
    (`_snapshot_water_tag_increment!`, one new cache field).
  - After the solve, per cell:
    `δL = (U.c.q_tag_exp_negative + dtγ·dY.c.q_tag_exp_negative) − L_snap`.
    This is the gain the rule withheld inside the solve.
  - **The crossing's positive part, in its own cell:**
    `g = max(min(δL + min(P_snap, 0), T(P_new) − T(P_snap)), 0)`. This is the
    part of the withheld gain beyond the cell's deficit at the stage's start,
    and no more than the target's rise. Each partition tag takes `M_k·g` in
    that cell, by mask, as a bracket gives a gain. It enters `dY` as
    `M_k·g/dtγ`. `q_tag_inc_negative` records it, and so does each tag's own
    ledger where kept.
  - In place of `n` and `m`: `n' = n + δL − g` and `m' = m − g`. Their column
    totals, `N'` and `M'`, then go where `N` and `M` go now.
  - An `ifelse(δL == 0, old, new)` keeps every old number, signed zeros
    included, wherever the rule did not act in the stage. There `g = 0`.

*Why by mask (after the review).* The review's replica, case S2: a cell
crosses from −0.5 to 0.3 through a withheld stage gain of 0.8, and its
partition is empty. With `n' = n + δL` alone, the follower gives the 0.3 by
composition to a cell higher up, and the flux has to carry it down. It stops
at an empty cell on the way. That cell ends 0.1 above its target, and the
crossing cell 0.3 below its own. With the give by mask, the crossing cell
ends at its target, and no cell ends above its own (a rerun of the replica
with `g`). `g` assumes that the withheld gain fills the deficit first. Where
other implicit terms also lift the cell, their part goes by the flux, with
the donor's composition (the replica's case S3). The draft said that the
positive part goes by the crossing cell's own composition. The follower in
fact spreads `N` over every cell whose mismatch has its sign.

**What it cannot do.**

  - Source tags take no part of `g`. They receive the implicit bracket's gain
    only if they list `:microphysics`, and no tag of the validation does. A
    source tag that lists it misses that stage's positive part.
  - `δL` is exactly the ledger's `dtγ·w`. The parent's response to `w` is
    the solver's. The implicit transport spreads it within the column. The
    manual Jacobian has no 0M microphysics block, so there the column's
    response is `dtγ·w`, as far as the solve keeps column totals. Under the
    sparse and the dense autodiff Jacobians, `ρq_tot`'s diagonal also holds
    the rain-out's derivative. So the parent moves by about
    `dtγ·w/(1 − dtγ·∂Δ/∂P)`. The difference enters `N'`, and the follower
    gives it to the tags through `q_tag_inc_negative`, or leaves it out where
    no cell can take it. *Corrected after the review:* the draft said it
    lands in `q_tag_inc_left`, and that the tags' rows are the identity under
    0M. Under `implicit_diffusion: true` they hold diffusion blocks. The
    ledger's row is the identity, so `δL` is exact.
  - **Float32.** `δL` is a difference of a cumulative ledger. By the review's
    arithmetic, `L = 1e-2` and `dtγ·w = 1e-9` give an error of 6.9%. With
    `dtγ·w = 1e-10`, `δL` is zero, so the stage keeps `n` and the double count
    returns. After 777,600 equal gains, 90 days at 10 s, the error bound is
    about 4.6% in Float32 and 8.6e-11 in Float64. The validation runs in
    Float64. The Float32 unit tests take a tolerance. The alternative, a real
    stage cache of `w` that the bracket fills on its non-dual evaluation, is
    for the owner (11.11.13).
  - Two texts are false already wherever `N ≠ 0`, and would stay false: that
    the factors lie in `[-1, 1]` (`tagged_water_increment.jl:464-467`), and
    that no cell leaves out or moves more than its own mismatch (`:276-277`). The
    review's replica gives a factor of 3 in case S2 without the give, and
    1.33 in the loss case below. Both texts are corrected: a factor can pass
    1 where `N'` is not zero.

**A defect that predates the revision.** An unshared loss makes `n > 0`
while the partition does not change. Examples: the default split's rain-out
in a cell whose grid parent is below zero, where the loss share is zero, and
under the key water that leaves a negative `N`. `N` then gives that water to
the partition elsewhere in the column. This is not a lag. It lifts the
partition above its target in positive cells, which V2 and the windows
measure. In the review's replica, a loss of 0.4 in a negative cell and a
mismatch of ±0.3 leave one cell 0.4 above its target, moved by a factor of
1.33. The validation's configuration exercises this path. The fix is the
optional ledger `q_tag_exp_negloss` (11.11.6), with
`n' = n + δL + δL⁻ − g`. For the owner (11.11.13). 11.7 registers the path
either way.

**Where:** `_water_tag_increment_cache` (`tagged_water_increment.jl:112-133`),
`_snapshot_water_tag_increment!` (`:201-210`), `correct_water_tag_increment!`
(`:328-432`) and its docstring (`:246-291`), and the text of
`q_tag_inc_negative` (`:46-55`, and its diagnostic).

#### 11.11.4 Source tags and region tags that list sources (question 4)

The owner's decision needs a new definition: what a source tag's target is
where the parent is at or below zero.

**The definition (option A): a source tag is a part of the partition's
target, `T = max(P, 0)`.**

  - Where `P < 0` its target is zero, so it gains nothing there.
  - At `P = ±0` the target takes the whole gain (Q1), so the tag takes it.
  - The rule does not take away what the tag held before the parent went
    negative. It is attribution, not correction, as section 10 chose.

**The rule,** at every bracket of a label in `KNOWN_WATER_TAG_SOURCES`,
explicit and implicit, at each stage:

  - a tag without a region that lists the label: `G(Δ, P) + φ_s·min(Δ, 0)`;
  - a region tag that lists the label: `M_k·G(Δ, P) + φ_k·min(Δ, 0)`;
  - a tag that does not list the label: `φ·min(Δ, 0)`, as before;
  - partition tags: unchanged. They receive every label.

So every kind of tag takes the same gain function. Only the labels it
receives, and its mask, differ. `G` reads `P` at each stage (Q2) and at the
Newton iterate (Q3).

**Where:**

  - `tagged_water.jl:395`: `_tag_gain_rule(rule, tag) = rule` for every tag,
    or the function dropped.
  - `tagged_water.jl:644-663`, the kernel for a tag without a region:
    `max(ᶜΔ, 0)` becomes `water_tag_gain(rule, ᶜΔ, ᶜparent)`.
  - `tagged_water_rainout.jl:252`: in copies mode every tag's updraft part
    takes `water_tag_split_change(rule, …)`.
  - The docstrings at `tagged_water.jl:368-385`, `:641-643` and `:665-669`,
    `types.jl:2320-2337` (`WaterTag`), and `docs/src/tagged_water.md`.
  - Unchanged: the default split, whose source-tag shares are zero where
    `P ≤ 0` already (`SplitShare`), and the copies' own rain-out and surface
    flux (11.6).
  - Under the key, Q5's gates reach a source tag's parts too.

**How the rest of the code treats a source tag.**

  - Its loss, sedimentation, SGS flux and follower shares are clamped. They
    are zero where `P ≤ 0`, and zero for a negative tag (`water_tag_fraction`,
    `_water_tag_share_field`, `_water_tag_follower_share_field`).
  - The partition repair skips it (`tagged_water.jl:1538`). It has no closure
    and no term in the follower's partition sum.
  - The rescale takes `max(after, 0)` and empties the tag where the parent
    was at or below zero before (`water_tag_source_rescale_shift`). But the
    rescale runs only with a limiter, with the element constraint on
    `q_tot`, or with a prescribed flow. The validation's configuration has
    none of them: `cr_s23.yml` sets none, and the defaults are
    `apply_sem_quasimonotone_limiter: false` and
    `tracer_nonnegativity_method: ~`.
  - The ledger is parent-side (11.11.6), and partition tags receive every
    label. So a source tag's withheld gain is part of the parent's withheld
    gain in that cell and bracket.

**A crossing step, on both sides.** The stage split acts on source tags as on
partition tags (11.2).

  - A source tag that holds nothing can end a crossing step below zero:
    ARS343 gives `−0.2085·G·Δt`, and ARS222 `−0.7071·G·Δt` where another
    process takes the parent below zero by stage 2.
  - *Corrected after the review:* the draft said such a value stays "until a
    loss or the rescale's emptying reaches it". In the validation neither
    can. Its loss, follower and flux shares are zero, the rescale does not
    run, and the repair skips source tags. Only later gains in the cell offset
    it, and diffusion spreads it. In the review's toy of 40 wet and dry cycles
    (`G·Δt = 1e-6`), the tag ends each cycle at −7.3e-7 while its target is
    5.5e-16. The toy does not grow across cycles. Growth over 90 days is not
    known. With the parent's gain, the rule as it was, the same toy's tag
    grows to 1.3e-3 by cycle 40.
  - With ARS222, an up-crossing gives the tag `1.7071·G·Δt` while the target
    gains less. So a source tag can also end the step above the parent in
    that cell, by up to one step's gain (11.2's largest overclaim).
  - V5 reports the source tags' negative water (amended in 11.7). A floor is
    an option for the owner (11.11.13).

**What it changes.**

  - Where `P ≥ 0`, nothing: the same `max(Δ, 0)` on the same numbers.
  - At site 23, `evap` (`surface_flux`) and `fcg` (subsidence, large-scale
    advection and the external forcing) stop gaining in cells whose parent is
    below zero. W48 placed each rise's growth in such cells, and by its
    leave-one-out reading subsidence carries every rise. So `fcg` is where Q4
    should act most. This is not measured.
  - The 30-day parity found `evap` and `fcg` differing from `main` from day
    11.5, by a path not traced (11.8). With Q4 they also change directly.

**Duals, GPU, allocation:** the partition tags' kernel, `water_tag_gain`. No
new field and no new allocation.

**The definitions not chosen:**

  - **B, the target's gain over a whole step:**
    `ifelse(P < 0, max(Δ + P/Δt, 0), max(Δ, 0))`. It overclaims by half a
    step's gain per crossing on average (11.2). So a source tag could hold
    more than the partition in a crossing cell. The implicit stage is given
    no `Δt`, and it adds a second rule. The owner accepted the stage split
    for the partition (Q2).
  - **C, withheld at or below zero:** `ifelse(P ≤ 0, 0, max(Δ, 0))`, the
    rescale's convention. In a cell that starts at `q_tot = 0`, `fcg` would
    never take the first forcing's water while the partition takes it (Q1).
    The rule would depend on the tag's kind again.
  - **D, the parent's gain** (11.6 as it was). The owner's decision excludes
    it.
  - **E, enforce the zero target:** where `P < 0` the bracket also empties a
    source tag, with a ledger entry. It is a correction after the fact,
    which section 10 set aside for the partition (option 3). It hides where
    the water came from.

#### 11.11.5 Transfers into a negative compartment (question 5)

*Revised after the review (its blocking point).* The draft emptied a negative
compartment's pool, so that it passed on no tag water. But the pool exists for
water that passes through a compartment within the step
(`water_tag_pool_shares`' docstring). In the review's replica, snow at
−2e-7 kg/kg takes 1e-8 /s of deposition and passes it on as melt. The old code
gives the parts the target's rates exactly. The draft's rule lost the whole
flow every step, and its ledger recorded water while `min(S, 0)` did not
change. The rule below keeps the pass-through.

Under `water_tag_precipitation: true` the compartments at the stage's state
are `N`, `R = ρq_rai` and `S = ρq_sno`. A compartment `X` is negative if
`X < 0`. Neither `+0.0` nor `-0.0` is negative (Q1).

**Bit for bit elsewhere.** Where no compartment of a cell is negative, every
formula is the old one. The new form sits behind
`ifelse(N < 0 || R < 0 || S < 0, new, old)`, because reordering the sums
alone would change the rounding.

**The rule,** in a cell where some compartment is negative:

 1. **A flow that touches a negative compartment is read in its actual
    direction.** A negative flow moves water from its nominal receiver to its
    nominal donor. The 1M flows are linear in their solved donors
    (`NR = M31·q_lcl_new`, `RN = −(M33 + M43)·q_rai_new`), so a negative
    content reverses its outflows. A flow between two compartments that are
    not negative keeps the old term.
 2. **A negative compartment's own parts take no microphysics change:** no
    gain and no loss. Its target stays zero.
 3. **Its pool stays.** It starts with no tagged water (`qX = max(X, 0) = 0`),
    so its share `ψ_X` is the composition of what actually flows into it in
    the step. That is the old row, with the actual inflows.
 4. **It passes on only what came in.** Its actual outflows carry
    `ψ_X·min(1, in_X/out_X)`. So water that passes through (`in = out`)
    reaches the receivers with its donors' composition, as before.
 5. **What it keeps, `max(in_X − out_X, 0)`,** fills its negative part. Its
    donors' parts lose it, and no part gains it. The ledger records it.
 6. **What it gives beyond its inflow, `max(out_X − in_X, 0)`,** carries no
    tag water. The receivers' target gains it, and their parts do not. It
    lands in `q_tag_res`, as the old code has it where `X` has no inflow.
    `q_tag_exp_negloss`, if built, records it.
 7. **The net-flow rule** (`water_tag_net_flow_change`, for the flows'
    residual `δR`, `δS` and for the vapour bracket): a gaining compartment
    takes `max(ΔX, 0)·mix` only if it is not negative. Otherwise the gain is
    withheld and recorded. A loser keeps `min(ΔX, 0)·φ_X`, which is zero where
    `X ≤ 0`. A negative loser's water enters `mix` with `φ = 0`, so the
    gainer takes it untagged, as in point 6.
 8. **The audit** (`water_tag_microphysics_audit`) applies the same gates in
    both its terms. So it still compares the gross flows with the net-flow
    rule, not with the gate.

On a closed partition each compartment's parts then take the target's rates.
A flow that leaves `X ≥ 0` takes `F` from it, and a flow into `X ≥ 0` gives
`F`. A negative compartment's parts do not change, and only its pass-through
moves tag water. The one shortfall is point 6. The review's replica gives the
target's rates for `in = out` (ledger 0) and for `in > out` (ledger the net
inflow), and a shortfall of the net outflow for `out > in`.

**Zero and crossing.** `±0` takes its gains (Q1), and its pool works as now.
The signs are read at each stage on the explicit path, and at the Newton
iterate on the implicit path, which is the default. A compartment that
crosses zero inside the solve withholds that stage's net inflow. For `N`
under the follower, the positive part goes back by 11.11.3. `R` and `S` have
no follower, so there it lands in `q_tag_res`.

**The ledgers.** Parent-side: `ρ` times the water, whatever the tags hold.
The net inflow into `N` while `N < 0` goes to `q_tag_exp_negative`, as the
brackets' withheld gain does. The net inflow into `R` or `S` while negative
goes to `q_tag_exp_negative_precip`, a second field that exists only under
the key. They stay apart so that the follower, which corrects `N` only, reads
`N`'s alone.

**The follower.** Under the key it corrects `N`
(`_water_tag_parent_after`, `tagged_water_increment.jl:492-497`). A net
inflow into a negative `N` inside the solve enters `n'` through the ledger
(11.11.3). A pass-through leaves both `n` and `δL` at zero.

**Where** (`tagged_water_precipitation.jl`):

  - `water_tag_pool_shares` (`:970-1003`): a negative compartment's row
    takes its actual inflows. The row is not emptied.
  - `water_tag_gross_flow_change` (`:938-942`): the actual direction, the
    gated parts and the capped outflow, for flows that touch a negative
    compartment.
  - `water_tag_net_flow_change` (`:1018-1031`): the gain's gate.
  - `water_tag_microphysics_change` and the audit (`:1046-1108`): the flags
    passed on.
  - `_water_tag_precipitation_microphysics_tendency!` (`:1140-1167`): the
    flags from `Y`, and both ledgers written once per cell, before the loop
    over the tags.
  - `attribute_water_tag_precipitation_tendency!` (`:1257-1265`): the vapour
    bracket's gate and ledger.
  - Unchanged: the limiters' follow, sedimentation, the repair and the
    advection's hand-back. The follow (`water_tag_part_follow_shift`,
    `:1376-1422`) already aims at the target before, and empties a part whose
    compartment is at or below zero after.

**What it changes.**

  - Only runs with the key (1M, no EDMF, no copies), and only in cells with a
    negative compartment at a stage. The validation does not use the key.
  - The vapour-nonnegativity tendency lifts exactly the negative condensate.
    So it is a transfer into a negative compartment by construction, and its
    rain and snow parts now take nothing there.
  - Reversed flows in such a cell now carry their actual donor's
    composition. Before, where negative rain's evaporation ran backwards,
    `N`'s parts lost water by rain's pool composition.

**Duals, GPU, allocation.** The flags are `Bool`s from comparisons, which
compare duals by value. The functions still return `NTuple`s. `ifelse`
evaluates both branches, so the parts' kernel costs up to about twice as much
under the key. No new field besides the ledger, and no allocation.

#### 11.11.6 The ledger of the withheld gain (question 6)

**The definition, parent-side.**

  - At every attribution bracket, explicit and implicit, `L`'s tendency is
    `w = ifelse(P < 0, max(Δ, 0), 0)`, in kg m⁻³ s⁻¹. That is the part of the
    process's tendency that fills the parent's negative part instead of
    reaching the tags. Under the key `P` and `Δ` are `N` and `N`'s change.
  - Under the key it also takes the net inflow into a negative `N` from the
    microphysics' transfers and from the vapour bracket (11.11.5).
  - It does not depend on the tags. Partition tags receive every label, so it
    covers every source tag's withheld gain too. On a closed partition whose
    masks sum to 1 it equals the partition's withheld gain,
    `Σ_k M_k·(max(Δ, 0) − G)`.
  - The stepper weights it as it weights the tags. Each evaluation adds a
    value `≥ 0`, but with negative weights `L` can fall within a step (11.2).
  - It exists with water tags under every `water_tag_transport`, since the
    explicit brackets withhold under all of them.
  - Under the key, `q_tag_exp_negative_precip` takes the net inflow into
    negative rain or snow (11.11.5).
  - **Optional, for the owner (11.11.13):** `q_tag_exp_negloss`, the loss
    that the partition does not share. At a bracket its tendency is
    `u = ifelse(P > 0, 0, min(Δ, 0))`. Under the key `u` also takes minus
    `ρ` times the net outflow of a negative `N`. So `u ≤ 0`, and `δL⁻`
    cancels the loss in `n`. In copies mode, where `P < 0`, the partition
    keeps the updraft's loss by the copies' shares, so there `u` is the
    bracket's loss less that kept loss. *Corrected after the review:* the
    draft wrote "plus the water moved out of a negative N". Read as a positive
    amount, that doubles `n` instead of cancelling it.

**Writers.**

  - `_attribute_tagged_ρq_tot!` (`tagged_water.jl:549-576`), once per
    bracket and before the split's early return, so that the grid kernel and
    both split modes are covered:
    `@. Yₜ.c.q_tag_exp_negative += water_tag_withheld_gain(rule, ᶜΔρq_tot, ᶜparent)`.
    Here
    `water_tag_withheld_gain(::TargetGain, Δ, P) = ifelse(P < zero(P), max(Δ, zero(Δ)), zero(Δ))`,
    and `water_tag_withheld_gain(::ParentGain, Δ, P) = zero(Δ)`.
  - Under the key: `_water_tag_precipitation_microphysics_tendency!` and
    `attribute_water_tag_precipitation_tendency!` (11.11.5).
  - Nothing else writes it: not `add_rainout_increments!`, which is
    output-time scratch, and not the limiters, the constraints, the repair or
    the follower.

**Machinery,** on the pattern of the leak correction's ledger, which is also
a tendency ledger:

  - Names, predicate and zeros: `WATER_TAG_EXP_LEDGER_NAMES`,
    `water_tag_exp_ledger_names(model)`,
    `water_tag_exp_ledger_variables(ρq_tot, model)` and
    `is_water_tag_exp_ledger_name(name)`.
  - State: `setups/common/prognostic_variables.jl`, after the increment
    ledger (`:124-127`), in `ρq_tot`'s type. The name has no `ρ` prefix, so
    `gs_tracer_names` and `is_tracer_var` skip it. No transport, diffusion,
    sponge or limiter reaches it.
  - Jacobian: the predicate goes into `is_splittable_jacobian_field`
    (`manual_sparse_jacobian.jl:825-836`). `fallback_identity_blocks` then
    gives the field a `−I` block, and the split solves it apart. The sparse
    autodiff Jacobian keeps that constant block.
  - Per-step gross: the names go into `tag_state_ledger_names`
    (`tag_throughput.jl:255-263`). That gives the gross, the column gross and
    the events, which the checkpoint carries. Not into
    `tag_attempted_ledger_names`, for the reason the leak ledger's docstring
    gives (`tag_throughput.jl:138-150`).
  - Diagnostics: `q_tag_exp_negative` in kg/kg, cumulative, the ledger over
    the current `ρ`, as `q_tag_inc_negative` is, registered for every
    water-tag model. `_gross` and `_colgross` come through
    `register_tag_ledger_diagnostics!`. The names go into
    `_ALL_TAG_STATE_LEDGER_NAMES` and `_TAG_MECHANISM_TEXT`
    (`tag_ledger_diagnostics.jl:8-40`), and the imports into
    `diagnostics/Diagnostics.jl`.
  - Audit: `_tag_ledger_audit` takes it by its prefix, as the columns
    `exp_negative_retained`, `exp_negative_events` and
    `exp_negative_attempted` (NaN) (`tag_throughput.jl:1053-1080`).
  - Reserved names: `exp_` goes into `RESERVED_WATER_TAG_PREFIXES`
    (`config/tracer_config.jl:486-499`) and its docstring, so that no tag's
    `q_tag_<name>` can take these names.
  - The follower's snapshot, for `δL` (11.11.3).
  - Hand-built states in the unit tests gain the field.
  - **Per-tag ledgers, optional (11.11.13):** `q_tag_led_neg_<name>` under
    `water_tag_ledger_per_tag`, each tag's own `M_k·w`. They need `led_neg_`
    in `TAG_PER_TAG_LEDGER_PREFIXES` (`tag_throughput.jl:820-830`), in the
    prefixes that `_tag_ledger_audit` strips before it looks up the tag
    (`tag_throughput.jl:1087-1092`), and in the diagnostics' per-tag name
    parsing. *Found by the review:* without the second, the first audit row
    asks for `ρq_tag_led_neg_pbl` and fails.

**The pre-registration.** Dated 2026-09-30 amendments, made before any run
(11.7). They add reported quantities only, and change no threshold:

  - 11.4's "The rule writes no ledger" no longer holds: the rule writes
    `q_tag_exp_negative`, and `q_tag_inc_negative` records the follower's
    `N'` and `g`.
  - 11.5's points "No new state field…" and "The implicit bracket and the
    rain-out split are not touched" give way to 11.11.8.
  - V5 also reports `q_tag_exp_negative`'s per-step gross a day, and the
    source tags' negative water.
  - The configs `cr_s23.yml`, `cr_s26.yml` and `cr_probe_s23.yml` add
    `q_tag_exp_negative` and `q_tag_exp_negative_gross` to the 6-hourly and
    the daily diagnostics. The `_main` configs cannot, since `main` has no
    such field. The untagged ones have no tags.
  - The probe driver `ic_miss_probe2.jl` adds `:q_tag_exp_negative` to
    `LEDGERS` (`:55-66`), a reported column. It already skips a ledger that
    the state lacks (`:332`), so it still runs on `main`.

#### 11.11.7 The closure identity

The notation is 11.11.1's, and `Π` is the sum over the partition tags.

**(I1) Pointwise, at every output. Unchanged (V2b):**
`q_tag_res + q_tag_negative + Σ region q_tag = q_tot`. Here
`q_tag_res = (T − Π)/ρ` and `q_tag_negative = min(P, 0)/ρ`, summed over the
compartments under the key. The ledger does not enter (I1): a withheld gain
changes `q_tag_negative`, not `q_tag_res`.

**(I2) Per bracket evaluation and cell, exact up to the sign of zero:**

    Δ = Ṫ + w + u.

`Ṫ` is the target's rate: `Δ` where `P > 0`, `max(Δ, 0)` where `P = ±0`, and
`0` where `P < 0`. `w` is `L`'s tendency and `u` is `L⁻`'s. The partition's
parts sum to `Ṫ + e`. *Stated per split mode after the review:*

  - The grid kernel:
    `e = (Σ_k M_k − 1)·G + (Σ_k φ_k − [P > 0])·min(Δ, 0)`. It is zero on a
    closed partition whose masks sum to 1.
  - The default 0M split: the parts sum to `S·Δ`. So `e` is zero where
    `P < 0`, and where `P > 0` on a closed partition. At `P = ±0`, `S = 0` and
    `w = 0`, so `e = −max(Δ, 0)`: that gain is neither given nor recorded.
  - Copies mode: where `P < 0` the partition keeps the updraft's loss by the
    copies' shares, so `e` holds that loss.
  - Under the key, per compartment for Q5's transfers, `e` holds one more
    term: a negative compartment's outflow beyond its inflow, which the
    target gains and the parts do not (11.11.5, point 6).

**(I3) Per step and cell,** the tableau-weighted sum of (I2):
`ΔL = Σ_i b_i·w_i·Δt`, each stage with its explicit or its implicit weight.
Let `c = Σ_i b_i·Ṫ_i·Δt − ΔT` be the overclaim, the brackets' change of the
partition less the target's change over the step. It is zero where the parent
keeps a strict sign at every stage, and it is 11.2's miss in a crossing. Then
the brackets move `q_tag_res` by `−c − Σ_i b_i·e_i·Δt`, and the negative part
by `ΔL + ΔL⁻ + c`. The review checked this with a scalar replica of the
ARS222 stepper.

**(I4) Per implicit stage and column, under the follower:**

    N' = ∫(n + δL + δL⁻ − g) dz,   M' = ∫(m − g) dz.

  - The partition takes `g` in its own cell by mask, and `N'` by composition
    where `m'` has `N'`'s sign. Both are recorded in `q_tag_inc_negative`.
  - `M' − N'` is left out (`q_tag_inc_left`). That is the lag, and also the
    default split's gain at `P = ±0` (I2). *Corrected after the review:* the
    draft called it the lag alone.
  - Where the rule did not act in the stage, `δL = g = 0` and `N' = N`, bit
    for bit.
  - Where the parent's response to `w` differs from `δL` (the autodiff
    Jacobians, 11.11.3), the difference is in `N'`.

**(I5) No closed budget of `q_tag_negative` is claimed.** Transport, the
limiters and the parent's own processes also change the negative part, and no
single ledger sees them all. `∫L dz` is the water that the brackets and the
transfers gave the negative part instead of the tags.

#### 11.11.8 Why every model field stays bit for bit

 1. **What is written:** tag fields (`ρq_tag_*`, and under the key
    `ρq_rtag_*`, `ρq_stag_*`, `q_rtag_aud_*` and `q_stag_aud_*`), the new
    ledgers, and one tag cache field, the follower's snapshot. No model
    tendency, limiter, constraint, callback or model Jacobian block reads any
    of them.
 2. **What is read:** only signs of fields the kernels already read: `P`,
    and under the key `ρq_rai` and `ρq_sno`.
 3. **Transport:** the ledgers have no `ρ` prefix, so no transport,
    diffusion, sponge or limiter touches them.
 4. **The Jacobian.**
      + Manual: a ledger gets a `−I` block and is solved apart
        (`uncoupled_jacobian_names`), as the existing ledgers are.
      + Sparse autodiff: keeps that constant block.
      + Dense autodiff: holds the ledger's row in full. The model's rows have
        exact zeros in the ledger's column, and `parallel_lu_factorize!` does
        not pivot (`auto_dense_jacobian.jl:341-370`). So the elimination
        subtracts only products with those zeros, which leave every nonzero
        entry as it was. The sign of a zero entry can flip (`−0.0 − (−0.0)`
        is `+0.0`). Every tag field can do this already. The autodiff recheck
        compares with `isequal` and reports a signed zero apart (11.11.11).
 5. **The follower** writes only `dY`'s tag and ledger entries. The runs
    already have the post-solve hook. None is added under tracer transport,
    so the stepper's cache refresh is unchanged.
 6. **The brackets:** the extra broadcast writes `Yₜ.c.q_tag_exp_negative`
    only. The parent budget and the process records read `Yₜ`'s parent
    fields, which it does not touch.
 7. **The state's layout** grows, as it did for every earlier ledger. The
    stepper computes its increments field by field. The validation's settings
    take no norm or inner product over the whole state
    (`max_newton_iters_ode: 1`, `use_newton_rtol` and `use_krylov_method`
    false). With either, the tags and the ledgers would enter the norms
    alike. That holds for every tag field today.
 8. **Tags where the parent is not negative** stay bit for bit. `G`, Q4's
    kernel and Q5's gate reduce to the old arithmetic there, since the
    `ifelse` keeps the old branch. The follower keeps its numbers where
    `δL = 0`. So site 26's tags stay `main`'s unless the rule acts (V3).
 9. **The checks:** V4, V4b, the 30-day parity rerun, the nine
    `tagging_water*` integration groups, and a new autodiff parity check,
    since no water-tag test runs an autodiff Jacobian today.

#### 11.11.9 Restart

  - **The new state:** `q_tag_exp_negative` in every water-tag run,
    `q_tag_exp_negative_precip` under the key, and `q_tag_exp_negloss` if
    built. They are fields of `Y`, so a checkpoint carries them and a restart
    continues them. Their per-step gross, column gross and events are cache
    accumulators. `tag_ledger_checkpoint_fields` writes them for every name
    in `tag_state_ledger_names`, and `restore_tag_ledger_checkpoint!` reads
    them back (`tag_throughput.jl:1161-1290`). They have no attempted total.
    The follower's snapshot is refilled at every stage, so it is not
    carried.
  - **An old checkpoint is refused.** A new `check_restart_fields` entry in
    `check_water_tag_checkpoint` (`water_tag_checkpoint.jl`, after the
    increment ledger's at `:139-148`) uses `is_water_tag_exp_ledger_name` and
    `water_tag_exp_ledger_names`. Its message says that the file was written
    before the water tags kept the ledger of the withheld gain, and that a
    new run is needed. The generic "restart with the same `water_tracers`"
    would mislead. Zero-fill is not proposed: no restart path can add a
    missing state field, and a ledger restarted at zero would misstate the
    run's total, which the per-mechanism ledgers' policy already refuses
    (`tag_throughput.jl:641-648`). None of the planned runs restarts.
  - **The version:** `WATER_TAG_CHECKPOINT_VERSION` stays 2. Its docstring
    says that ledgers are checked by their presence in the file, and no
    recorded attribute changes meaning. The test's pin
    (`tagged_water_precipitation_tests.jl:2282`) stays. A checkpoint from
    before the revision lacks the ledger and is refused, so one run's tags are
    never attributed under two rules.
  - **Tests:** the guard refuses a state without the ledger. The round-trip
    testset (`tagged_water_integration.jl:377`) restarts with the ledger and
    its accumulators continuing. A continuous run against a restarted one
    gives the same state bit for bit.

#### 11.11.10 The tests and their mutants

Each mutant runs in its own detached worktree. The new tests must fail there,
and nothing else.

 1. **The bracket testset** (`tagged_water_tests.jl:2766`), renamed "…every
    bracket and every tag". `microphysics_gain_rule` is `TargetGain()` for
    `Implicit()` and `Explicit()`, in place of `:2780-2785`. Mutant M3,
    `_microphysics_gain_rule(::Implicit) = ParentGain()`, must fail.
 2. **Same testset, Q4.** A tag without a region (`evap`) and a region tag
    with sources (`tropical_evap`) gain nothing where `P < 0`. Elsewhere,
    `±0` included, their gain `isequal`s `max(Δ, 0)` times the mask. The loss
    half is unchanged. A tag that does not list the label takes only the
    loss. `_tag_gain_rule(TargetGain(), tag) === TargetGain()` for every kind
    of tag. This replaces the assertion that tags outside the partition keep
    the parent's gain. Mutants M4a (the kernel for tags without a region
    keeps `max(Δ, 0)`) and M4b (`_tag_gain_rule` gives `ParentGain()` to tags
    outside the partition) must fail.
 3. **Same testset, the ledger.** `attribute_tagged_ρq_tot!` writes
    `Yₜ.c.q_tag_exp_negative == ifelse(P < 0, max(Δ, 0), 0)`, written out in
    the test and not through the rule's own function. On a closed partition,
    with the grid kernel, `Δ ≈ Σ_partition Δ_k + w + u` within 10 eps (I2).
    Hand-built states gain the field. Mutant M6a, the ledger's write removed,
    must fail.
 4. **The stage testset** (`:2911`), extended to a tag without a region. One
    ARS343 step from −0.5 and from −0.6 gives it `b2 + γ ≈ −0.2085`. One
    ARS222 step with a loss outside the bracket gives `δ ≈ −0.7071`, and an
    up-crossing gives `1.7071`, above the target's gain. The ARS222 jump at
    zero is `1 − δ` against 1. Then steps with `P > 0` and a sink: the
    negative value stays, since its share is zero, as 11.11.4 says. Mutant
    M4a must fail.
 5. **`tagged_water_integration.jl`, the implicit bracket.** "The implicit
    microphysics bracket keeps the parent's gain" (`:195-230`) becomes
    "…gives the target's gain". In cell `k` the parent is made negative and
    the cached rain-out a gain. Take `implicit_tendency!` with and without
    the gain. The partition's and the source tags' tendencies at `k` do not
    change. The ledger's tendency at `k` changes by exactly the gain. Every
    other cell's tag tendencies are `isequal`. Mutants M3 and M6a must fail.
 6. **The copies.** The coupling-1 test of
    `tagged_water_edmf_0m_explicit_integration.jl` (`:270-308`): a source
    tag's updraft gain is now withheld at `k` too, in place of
    `isequal(new, old)` for source tags. The same check on the implicit path,
    in `tagged_water_edmf_copies_integration.jl`. Mutant M4b must fail.
 7. **The follower and the withheld gain,** a new testset in
    `tagged_water_tests.jl` on the harness of the option-C testset
    (`:2553-2765`), with `q_tag_exp_negative` in `ᶜnames`.
      + Case 1: a cell stays below zero. The bracket withheld `w`: `U`'s
        ledger is `Y`'s plus `dtγ·w`, the parent rises by `dtγ·w`, and the
        partition is unchanged. A transport mismatch elsewhere gives `m` of
        both signs. Expected: `q_tag_inc_negative`'s column total is zero,
        with values exact in binary or to a few ulp of `P` and `L`; the
        partition's column change equals the target's; no cell's correction
        exceeds its mismatch. *After the review:* a hand-built `U` makes `n'`
        a rounding, not an exact zero.
      + Case 2, the crossing (the review's S2): `P_snap = −0.5`, a withheld
        stage gain of 0.8, `P_new = 0.3`, and an empty partition in the
        crossing cell and in a cell above it. Expected: the crossing cell ends
        at its target, by mask; no cell ends above its target beyond a
        tolerance; `q_tag_inc_negative` records `g`.
      + Case 3, `δL = 0`: `dY` and the three increment ledgers `isequal`
        values pinned from the current code.
      + Mutant Mf (`n' = n`, no `δL`) must fail cases 1 and 2. Mutant Mg (no
        give by mask, `n' = n + δL`) must fail case 2.
 8. **Only if `q_tag_exp_negloss` is built:** an unshared loss in a negative
    cell and a transport mismatch elsewhere (the review's loss case). The
    partition's column change equals the target's, and no cell moves more
    than its mismatch. This test fails on the current code, which shows the
    defect. A copies-mode case: where `P < 0` the kept updraft loss is not in
    `u`. Mutants: Mf⁻ (no `δL⁻`), a sign-flipped transfer term in `u`, and
    `u = min(Δ, 0)` in copies mode, must each fail.
 9. **Transfers into a negative compartment,** a new testset in
    `tagged_water_precipitation_tests.jl`:
      + (a) a flow `N → R` with `R < 0` and no outflow from `R`: the `N`
        parts lose `F·ψN`, the `R` parts take 0, and the precipitation ledger
        takes `ρF`;
      + (b) the pass-through, the review's case: `S < 0` with deposition
        `N → S` and melting `S → R`, `in = out`. The parts' rates equal the
        target's (`N` −F, `R` +F, `S` 0), and the ledgers take 0;
      + (c) `S < 0` with `in > out`: the ledger takes `ρ(in − out)`, and the
        receivers take `out·ψS`. With `out > in`: the receivers take
        `in·ψS`, the ledger 0, and the receivers' parts fall short of their
        target by `out − in`;
      + (d) a reversed flow, `F.RN < 0` with `R < 0`, read as `N → R`: the `N`
        parts lose `|F|·ψN`, the `R` parts take nothing, and the ledger takes
        `ρ|F|`;
      + (e) the net-flow rule: a gaining compartment below zero takes 0, and
        the ledger takes `max(ΔX, 0)`;
      + (f) the vapour bracket lifting negative rain: the `R` parts take 0,
        the `N` parts lose `ΔR·φN`, and the precipitation ledger takes `ρΔR`;
      + (g) every compartment `≥ 0`, `±0` included: every output `isequal`s
        the old formulas, written out in the test;
      + (h) the audit is 0 where `R < 0`, and `isequal`s the old value
        elsewhere.
      + Mutants M5a (no receiver gate), M5b (the draft's empty pool,
        `full_X &= !(X < 0)`), M5c (the nominal donor's composition for a
        reversed flow) and M5d (no cap on the outflow) must each fail their
        cases. M5b must fail (b).
10. **The key under the follower** (`tagged_water_precipitation_tests.jl:1250`,
    extended): a net inflow into a negative `N` inside the solve enters `n'`
    through the ledger, and nothing is taken from the partition elsewhere. A
    pass-through leaves `n'` at zero. Mutant Mf must fail.
11. **State and names** (`tagged_water_tests.jl`, near `:1013` and `:1266`):
    `q_tag_exp_negative` exists under tracer and increment transport, and not
    without water tags. `q_tag_exp_negative_precip` exists only with the key.
    Both start at zero in `ρq_tot`'s type. `is_splittable_jacobian_field` and
    `uncoupled_jacobian_names` include them. `tag_state_ledger_names`
    includes them, and `tag_attempted_ledger_names` does not. Mutant: a field
    that exists only under increment transport must fail the tracer case.
12. **Reserved names** (`test/config/tracer_config.jl`): tags named
    `exp_negative` and `exp_x` are refused. The accumulators' checkpoint
    round trip (`:1787-1929`) includes the new ledger's gross, column gross
    and events. Mutant: `exp_` not reserved must fail.
13. **The restart guard** (`tagged_water_tests.jl:913`,
    `tagged_water_precipitation_tests.jl:2192`): a state without
    `q_tag_exp_negative` is refused, with a message that names it. The
    existing pin keeps `WATER_TAG_CHECKPOINT_VERSION` at 2. Mutant M6b, the
    `check_restart_fields` entry removed, must fail.
14. **The restart round trip** (`tagged_water_integration.jl:377`): the
    restarted run continues the ledger bit for bit against a straight run.
    Its field-name filter (`:429`) admits the ledger. So do the filters at
    `tagged_water_edmf_copies_integration.jl:471`,
    `tagged_water_increment_integration.jl:150`,
    `tagged_water_precipitation_integration.jl:136`,
    `tagged_water_edmf_0m_integration.jl:67`,
    `tagged_water_leak_correction_integration.jl:125` and
    `tagged_water_edmf_integration.jl:245`, and any energy file whose run has
    water tags. Mutant: the names left out of `tag_state_ledger_names` must
    fail the accumulators' part.
15. **Diagnostics:** `q_tag_exp_negative`, `_gross` and `_colgross` are
    registered with water tags. Registering again for a model without water
    tags drops them, as for the increment ledgers. Mutant: the name left out
    of `_ALL_TAG_STATE_LEDGER_NAMES` must fail the stale-entry check.
16. **Duals:** `_accumulate_water_tags!` and `water_tag_withheld_gain` on
    `ForwardDiff.Dual{CA.Jacobian}` inputs. The values `isequal` the Float64
    evaluation. The partials of the partition's gain are zero where `P < 0`,
    and `max(Δ, 0)`'s elsewhere. `@inferred` holds. Mutant:
    `water_tag_withheld_gain` returning `zero(Float64)` in one branch must
    fail `@inferred`.
17. **Parity:** every `tagging_water*` file's "The model's fields do not
    depend on the tags", with only the filters updated. Mutant: the ledger's
    tendency also added to `Yₜ.c.ρq_tot` must fail.
18. **A real implicit stage,** new after the review, which found that no
    test takes `δL` through a Newton solve. One increment-transport step on
    the integration column, with the implicit bracket's gain forced where the
    parent is below zero, through the split solver's `−I` row, the post-solve
    hook and the DSS. `∫q_tag_inc_negative dz` must leave out the withheld
    gain, up to the solver's response (11.11.3). How the gain is forced, by a
    negative updraft area or by a test double of the rain-out, is chosen
    when the test is written. Mutant Mf must fail.
19. **Per-tag ledgers, only if built:** an audit row with
    `water_tag_ledger_per_tag: true`. Mutant: `led_neg_` left out of the
    audit's prefixes must fail.
20. **The record's score scripts:** `cr_windows_score_synthetic.py` and
    `cr_validate_v3_synthetic.py`, with the cases of 11.7's list. Mutant M7,
    W5 printed but not scored, must fail the failing W5 case, since the
    script would exit 0. Mutant M9, V3's old clause per cell, must fail the
    case whose values differ after `t*` in cells never negative.

#### 11.11.11 The rechecks before the validation

 1. **The record.** The decisions are entered in 11.10, `DECISIONS.md`, the
    register and `STATUS.md`. 11.1 to 11.6 point to this section, and 11.7
    carries the dated amendments. All done with this section, before any
    code. 11.8 lists the tests and mutants as they run.
 2. **Unit tests** in a Slurm job, both float types:
    `tagged_water_tests.jl`, `tagged_water_precipitation_tests.jl` and
    `test/config/tracer_config.jl`. The Float32 cases of 11.11.3 take a
    tolerance.
 3. **Mutants,** each in its own detached worktree: M3, M4a, M4b, M5a to
    M5d, M6a, M6b, Mf and Mg, the three of test 8 if the ledger is built,
    and the revision's first mutant, the rule removed. The new tests must
    fail and nothing else may. The jobs are recorded as in 11.8.
 4. **Integration:** the nine `tagging_water*` files with the updated
    filters, and every `energy_source_tags*` file whose run has water tags.
 5. **Autodiff, new.** The sparse autodiff Jacobian
    (`use_auto_jacobian: true`) on the integration column, or at site 23 for
    one hour. The dense one (`use_dense_jacobian: true`) only on a small
    column, `z_elem` 10 as in the CI's dense configurations. *After the
    review:* the dense LU keeps an `N × N` static array per column, and site
    23 has about 2,500 values per column. Tags on and off. Every model field
    is `isequal`, and a signed zero is reported apart (11.11.8). The tags and
    the ledger are finite. `implicit_tendency!` runs on duals. `∫n' dz` is
    reported over the columns where the rule acted.
 6. **Restart:** a continuous run against a restarted one, tags on. The
    state, the ledger and its accumulators are bit for bit. A checkpoint
    without the ledger is refused.
 7. **The 30-day parity rerun** on the new commit, with
    `cr_parity30_{tags,untagged}_{rev,main}`. At least the revision's two
    runs. `main` is unchanged, so its outputs of jobs `14010408` to
    `14010411` stay valid, or all four run again for a clean set (about an
    hour each). It passes by Q8's rule. Also reported: the ledger is zero
    before the first tag difference and nonzero after it; `evap` and `fcg`
    now change directly; the audit has `exp_negative_retained` and
    `exp_negative_events`, which V3 and V5 read.
 8. **The score scripts, before any run:** the changes of 11.7's list, their
    synthetic checks, then `cr_validate.py` on W42's outputs and
    `cr_windows_score.py` on W48's probe. Expected: `cr_validate.py`
    reproduces W42's numbers, and the audit's `exp_negative_retained` is
    reported missing, not failed. `cr_windows_score.py` fails W1, W2 and W5
    for every rise. The result goes into 11.7's Scoring paragraph.
 9. **The probe driver:** after `:q_tag_exp_negative` joins `LEDGERS`, a
    short check job, as 9.7.6's `13996777` was. W0's P0a must hold on the new
    code.
10. **The run trees:** `../ClimaAtmosResiDyn-crev-run` at the model commit
    the owner approves, with the record commit that registers the
    amendments, and `main`'s tree with the same record commit. The Manifest
    and #128's cap on ClimaParams stay.
11. **GPU:** not available on terrabyte, so not tested, and stated so. The
    change adds in-place broadcasts and one preallocated field. A GPU job on
    Levante is optional (the owner).
12. **Allocation:** where a test group measures the tendencies' allocations
    with water tags, the numbers must not change. By reading, nothing new
    allocates.

#### 11.11.12 The review of the draft (2026-09-30)

A second agent reviewed the draft and tried to break it. It found no parity
leak. Each of its points was checked before it went in: by reading the code, or
by rerunning the review's replicas, now in `analysis/water/crev_ext_review/`
with a rerun of its follower replica with this section's change
(`follower_g.py`).

**Confirmed and folded in:**

 1. **Q5's empty pool broke the pass-through** (blocking). Checked by reading
    `water_tag_pool_shares`: the pools are `max(X, 0)`, and a row with an
    inflow is full. The replica gives the numbers. 11.11.5.
 2. **A negative source tag is not removed in the validation.** Checked by
    reading the rescale's four call sites, `cr_s23.yml` and the defaults,
    the repair's guard and the clamped shares. 11.11.4, and V5 in 11.7.
 3. **The crossing's positive part could stop at an empty cell** and leave
    an excess in a positive cell. Checked on the replica (S2) and by reading
    the follower's donor shares. 11.11.3.
 4. **The follower's loss-side defect is an excess, not a lag.** With
    `q_tag_exp_negloss`, V3's `t*` would miss a stage-only negative parent,
    and in copies mode `u` would over-correct. Replica and reading. 11.11.3,
    11.11.6 and 11.7.
 5. **"Nothing of any run has been read" was false.** The 30-day parity of
    11.8 was read on 2026-09-30 (`833cd1dc`), and the level `0.1 R48` dates
    from 2026-09-29 (`d719fa86`). By `git log`. 11.7.
 6. **The autodiff Jacobians:** the parent's response differs from `δL`,
    and the difference goes to `q_tag_inc_negative`, not `q_tag_inc_left`.
    Reading. 11.11.3.
 7. **`δL` in Float32.** Arithmetic. 11.11.3.
 8. **(I2) and (I4) held for the grid kernel only.** Reading of the split
    modes. 11.11.7.
 9. **Per-tag ledgers need `led_neg_` in the audit's prefixes.** Reading.
    11.11.6.
10. **`q_tag_exp_negloss`'s sign.** 11.11.6.
11. **The tests:** a zero that is a rounding; no test through a real solve;
    the dense Jacobian at site 23. 11.11.10 and 11.11.11.
12. **V3's fallback bounds and cannot attribute.** 11.7.

From the review's minor points, also folded in: a source tag can overclaim
in an ARS222 up-crossing (11.11.4); the tags' rows under implicit diffusion
are not the identity (11.11.3); two bound texts in the follower are false
already (11.11.3); the dense LU can flip a signed zero (11.11.8).

**Refuted:** none. The review's replicas were rerun here and give its
numbers. One qualification: it calls an empty partition next to a crossing
cell typical. That is possible, and how often it happens is not measured.

**Found while revising:**

  - The draft's score change read 6-hourly `hus` from `cr_s26_untagged`,
    which writes `hus` daily only. V3 now also reads `cr_s26`'s `hus` (11.7).
  - The draft's Q7 text said the score scripts were rerun on 2026-09-30. They
    are not changed yet, so that rerun is recheck 8.
  - The draft said the crossing's positive part goes by the crossing cell's
    own composition. The follower spreads `N` over every cell whose mismatch
    has its sign. The give by mask replaces both (11.11.3).

#### 11.11.13 For the owner

 1. **The follower's amendment goes into this PR,** as Q3 and Q5 need, with
    the crossing's positive part given in its own cell by mask (11.11.3).
    Confirm.
 2. **The loss-side defect, which predates the revision** (11.11.3). Fix it
    now with `q_tag_exp_negloss`, or register it and leave it. 11.7
    registers the path either way. If built, V3 takes a fourth source for
    `t*`, and in copies mode `u` leaves out the kept loss.
 3. **Q4's definition:** A, a source tag as a part of the target with the
    same `G` (proposed), over B, C, D and E (11.11.4).
 4. **Q4, a crossing step:** a source tag can end it below zero, or above the
    parent, and in the validation nothing removes a negative value. Proposed:
    accept it, with V5's report (11.7). Or a floor at the step's end, with a
    ledger entry.
 5. **Q5:** a negative compartment's outflow beyond its inflow carries no tag
    water, and lands in `q_tag_res`, as the old code has it where the
    compartment has no inflow. Accept (proposed), or give it by the
    receiver's composition. Flows that touch a negative compartment are read
    in their actual direction. Confirm.
 6. **Q6's names and fields:** keep the name `q_tag_exp_negative`, which now
    also covers the implicit bracket and the transfers; one field,
    `q_tag_exp_negative_precip`, for rain and snow under the key; refuse a
    checkpoint without the ledger, with `WATER_TAG_CHECKPOINT_VERSION` at 2.
    Confirm, or ask for other names or a field per compartment.
 7. **Options not proposed by default:** per-tag ledgers
    `q_tag_led_neg_<name>`; a real stage cache of `w`, for an exact `δL` in
    Float32; the rule for the source-tag copies' own surface flux and
    rain-out (11.6).
 8. **The default split at `P = ±0`** withholds a gain that Q1 gives.
    Proposed: leave it. It lands in `q_tag_inc_left` or `q_tag_res`, and
    (I2) states it. Or give it by mask.
 9. **Q7:** W5 is scored on all five rises, the control included, as 11.7
    reads "per rise". Confirm, or the four rises without a ledger only.
10. **Q9:** `t*`'s sources are `hus`, the negative-water events and the
    ledger's retained gross, which sees the rule act at a stage that the
    outputs do not show. Confirm. After `t*` the fallback accepts every
    difference, so it bounds and cannot attribute.
11. **The dated amendments in 11.7,** among them the reported items (V5, the
    configs, the probe driver), the wording on what has been read, and that
    V2 and W5 score the bundle. Review them before any run.
12. **Minor, proposed as they are:** the rescale treats zero as non-positive
    and the rule as positive. The energy source tags are not touched.
13. **Order:** the autodiff check, the restart check and the 30-day parity
    rerun, all before the 90-day runs. The runs of 11.9 are submitted only
    after the owner has reviewed this section and the amended 11.7.

*Decided 2026-09-30 by the owner, point by point:*

 1. The follower's amendment goes into this PR.
 2. The loss-side defect stays registered in 11.7. `q_tag_exp_negloss` is
    not built now.
 3. Q4 is definition A. B, C and E were walked through first; D is excluded
    by the owner's earlier decision.
 4. A crossing step's source-tag overshoot is accepted and reported in V5.
    There is no floor.
 5. Q5: the outflow beyond the inflow lands in `q_tag_res`. Flows are read
    in their actual direction.
 6. Q6 as proposed: `q_tag_exp_negative`, one `q_tag_exp_negative_precip`,
    old checkpoints refused, the version stays 2.
 7. The options not proposed stay off.
 8. The default split at `P = ±0` is left as it is.
 9. Q7: W5 is scored on all five rises, the control included.
10. Q9: `t*`'s three sources, as proposed.
11. The dated amendments in 11.7 are accepted as recorded. The owner
    accepted "the remaining proposals as recorded"; the 90-day runs still
    wait for the rechecks of point 13.
12. The minor points are left as proposed.
13. The order is as proposed: the autodiff check, the restart check and the
    30-day parity rerun before the 90-day runs.
