# Tagged water where the parent's water goes negative: options for the fix

Written on 2026-09-24, at the owner's request, for known issue 7
(`docs/known_issues.md` on `claude/water-tags-wp6-step3`). It lists options.
**The choice is the owner's.** Nothing here is built. The FINDINGS entry is the
parent session's. The fix comes before the sphere (ROADMAP.md, the execution
order, step 8a).

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
  - Every parent field is bit for bit the twin's up to each crash.

So the tags change nothing in the model until they end it. The runs used
`claude/long-run-samesign`, #102 and #103 with G4.15b.

## 2. What is not established

  - **Which operator makes the divergence.** Candidates: the follower moving
    the parent's increments where the parent is negative; the partition
    repair, which keeps the tags non-negative and their sum, so it cannot
    follow a negative parent; the limiters' emptying where the parent is
    at or below zero (`q_tag_led_empty`); the copies' repair against a
    negative `q_totʲ`. None is isolated.
  - **What ends the run.** The water closure check's `abort_above` is 1.0 by
    default. Its reason assumes a non-negative parent: non-negative tags then
    miss it by at most the parent itself. The closure at the crash is −1.02,
    past that level. Whether the check ended the run, or something else did,
    is not recorded here.

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

## 5. A probe before the choice (a proposal)

The site 23 samesign run from its day-9 checkpoint, with
`water_tag_ledger_per_tag: true` and WP6 step 3's ledgers, to day 20. Which
ledger grows as the parent turns negative (the follower's moved and left, the
repair, the emptying, the copies' repair) bounds which option acts on the
cause. It changes no code. It needs the long runs' checkpoints on scratch and a
job the owner approves.

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

 1. Which option, or which combination.
 2. Whether the probe of section 5 runs first.
 3. Whether results already recorded from runs whose parent went negative
    (site 23's long runs) are kept, flagged or voided.
