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
    and #121, which are off in this configuration.
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
    `t`, composed as the model composes the forcing: the other terms' `(dT, dq)` accumulated and converted once, then their direct parts. It uses the
    same bracket, is applied alone at `Yₖ` and is stepped by `Δt`. Its share
    is `ℓ_t = Σ_{k∈I} (ΔE_forcing − ΔE_{forcing∖t}) / R`: how much of the
    forcing's growth goes when `t` is left out. It answers what 9.4's
    one-term probes cannot, because those do not add up.
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
    6-hourly) match bit for bit at every common output time. If not, the
    probe measures another parent. Its numbers are reported, and nothing is
    attributed to W42's rises.
  - **P0b, the tags' fields against `ic_s23_c`.** Reported, not a gate. Where
    they differ, the rises may differ, and P2 says how.
  - **P1** as in 9.3.
  - **P2** as in 9.3, with the first probe's value (W47) beside W42's.
  - **P3, #118's latch.** At every step whose ratio passes `1e-4`, the latch
    reads 1 at that step's end. A failure is a defect of #118. It is
    reported, and it does not touch the attribution.

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
      + the forcing's share is below 0.5: not the forcing, and 9.5's
        "unattributed" case applies.
  - **The fourth rise** is read by the same rules as the others.

**Bounded claims,** beside 9.4's:

  - A leave-one-out probe changes the composition of the forcing, since the
    `(dT, dq)` are converted once. So `ℓ_t` bounds the term's part in the
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
synthetic inputs made from the first probe's CSV, which checks its parsing
only.

**The job:**

  - `submit_g3.sh` from the clean run tree `../ClimaAtmosResiDyn-ic-probe2-run`,
    at the commit that registers this subsection;
  - `DRIVER=experiments/tag_closure/analysis/water/ic_miss_probe2.jl`;
  - `hpda2_compute`, 2 CPUs, 48 GB, `--time=12:00:00`.

The estimate is 4 to 5 h. The first probe took 3 h 8 min, and the five
leave-one-out probes add five forcing evaluations to each window step.
`analysis/water/ic_miss_score2.py` scores it.
