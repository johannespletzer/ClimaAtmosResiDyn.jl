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

| option | what it does | for | against |
|:------ |:------------ |:--- |:------- |
| **A. The tags cannot end a run** | The water closure check never aborts by default (`abort_above: ~`), or it does not abort where the parent's negative water explains the residual. The check still warns, and the audit flags the rows. | It restores the parity rule at once, whatever the cause. It changes no tag value. | The tags still diverge. Every result after the divergence is void and must be flagged. It hides nothing only if the flag is read. |
| **B. No tag water where the parent has none** | After the constraints, where `ρq_tot ≤ 0`, every partition tag is set to zero, and every copy where `q_totʲ ≤ 0`. The change goes to `q_tag_led_empty` and the per-tag ledgers. | Tags never claim water a cell does not hold. The residual there is the parent's own negative water, bounded by it. | The provenance of water that returns to the cell is erased. It stops the column's divergence only if the divergence starts in the negative cells. Tag values change wherever the parent is ever negative. |
| **C. The tags partition the parent's non-negative part** | The partition's target is `max(ρq_tot, 0)`: the follower takes that field's increment, and the repair, the rescale and the copies' repair aim at it. The parent's negative part becomes a named field, for example `q_tag_negative`. | The partition is consistent by construction, and the remainder has a name. | The largest change: the follower, the repair, the rescale and the copies. It needs its own validation, and the closure's definition changes. |
| **D. A cap** | Where `Σ_P ρq_tag > max(ρq_tot, 0)(1 + ε)`, the partition is scaled down to the cap, logged in a new state ledger. It is the sphere's pointwise check (G3_PLAN 6.1) turned into a correction. | Local and bounded; it shows up as intervention. | One more correction to count. A large cap can hide a divergence it should expose. |
| **E. Stop the tags, not the run** | When the tags pass `abort_above`, their tendencies stop and the audit marks the time. The model runs on. | The run completes, and parity holds. | The tags' fields stay in the state with no meaning after that time. The results after it are void. It adds a mode to every tag path. |

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

| reading | what it bounds | the option it points to |
|:------- |:-------------- |:----------------------- |
| the emptying, the rescale or the repair grows first and fastest, in N, and the overclaim grows in N | the tags meet the negative parent through the corrections in the negative cells | B: no tag water where the parent has none |
| the follower's moved or left part, or `led_inc`, grows first and fastest, in or next to N | the follower carries the parent's increments of a negative field into the tags | C: the tags partition the parent's non-negative part |
| the overclaim grows in P too, with no single ledger first by a clear margin (less than 2 times the next) | the divergence spreads beyond the negative cells | D: a cap; B alone would not reach it |
| no ledger grows by the rule while the overclaim does | the growth is in a path the ledgers do not see, such as the tags' own tendencies with shares of a negative total | none of B to D is shown to act on the cause; a further probe is needed |

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
