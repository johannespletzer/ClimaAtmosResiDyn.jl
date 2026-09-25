# W25's isolation, scored

Scored on 2026-09-25 against `design/W25_ISOLATION.md`, section 4, and the
OD3 rows approved on 2026-09-24. Nothing was tuned after the runs.

## Runs, code and scripts

  - **Jobs** (`hpda2_compute`, 2026-09-24/25): P4 `13932703` to `13932720`
    (untagged twins, default, copies; 6 rungs), P1 `13932721` to `13932732`,
    P2 `13932733` to `13932744`, P3 `13932745` to `13932748`. 44 of 46
    completed. P1 at `z120_fo` failed in both modes (`13932726`, `13932732`;
    below).
  - **Code:** the run tree `../ClimaAtmosResiDyn-w25i-run` at `705c8ed0` (the
    record + #109 + #105 + #112). The P4 runs' `provenance.txt` name it; the
    probes ran from the same tree (no git on the compute nodes).
  - **Scripts:** `analysis/water/w25_score.py` (this scoring),
    `analysis/water/w25_compare.py` (OD2's window, P3), and
    `analysis/evidence/compare_runs.py --judge` (R7).
    `w25_compare.py window` read a column's `(z, time)` file as `(time, z)`.
    That was fixed before any window was read; the rule is unchanged.
  - **Files:** `w25_scores.csv` (every rule, rung, mode and metric, with the
    value, threshold, verdict and OD3 row), `windows.csv`, `first_step.csv`,
    `verifier/r7_*.json`, `data/` (P2 and P3 CSVs, P4 closure CSVs), and
    `SHA256SUMS_scratch_inputs` for the inputs left on scratch.

## OD2's windows

| rung | z30_c | z30_fo | z60_c | z60_fo | z120_c | z120_fo |
|:---- |:----- |:------ |:----- |:------ |:------ |:------- |
| startup ends | 1.83 h | none | 2.0 h | 21.0 h | 2.33 h | 0.67 h |

On the first-order rungs the column water's 10-minute tendency stays above a
tenth of its early peak most of the day (97% and 93% of the outputs after the
first hour at `z30_fo` and `z60_fo`). The rule then finds no end, or a late
one. Window-based rules there are *not assessable*; the whole-period value is
in the CSV as `reported`.

## Verdicts

| rule | mode | z30_c | z30_fo | z60_c | z60_fo | z120_c | z120_fo |
|:---- |:---- |:----- |:------ |:----- |:------ |:------ |:------- |
| R1 parity | default | pass | pass | pass | pass | pass | pass |
| R1 parity | copies | pass | pass | pass | pass | pass | pass |
| R2 Newton | parent | fail | n/a | fail | n/a | fail | n/a |
| R3 temperature, negative water | both | pass | pass | pass | pass | pass | pass |
| R4 closure | default | pass | fail | pass | fail | fail | fail |
| R4 closure | copies | pass | fail | pass | fail | fail | fail |
| R5 comparator residual, repair | copies | fail | fail | fail | fail | fail | fail |
| R6 comparator refinement | copies | pass | fail | pass | fail | pass | fail |
| R7 provenance | default vs copies | n/a | n/a | n/a | n/a | n/a | n/a |
| R8 intervention | default | pass | n/a | pass | pass | pass | fail |
| R8 intervention | copies | pass | n/a | pass | fail | pass | fail |
| R9 refinement | default | pass | pass | pass | flag | pass | pass |
| R10 refinement | default | pass | n/a | pass | n/a | pass | n/a |
| R10 refinement | copies | pass | n/a | pass | n/a | pass | n/a |

A cell is its worst row. R9's "pass" includes vacuous rows, where the
partition repair moved nothing in hour 6 to 7 on either rung.

  - **R1** (parity): every model field of all 12 tagged runs is bit for bit
    its untagged twin's, every hour.
  - **R2** (Newton, at most 1e-3): the parent's one-step `E` at two
    iterations is 1.1e-2 (`z30_c`), 4.1e-3 (`z60_c`), 1.7e-2 (`z120_c`) in
    established flow; at one iteration 1.2e-2 to 2.5e-2. D4-W's parent fails
    this row on every assessable rung. The reference is 10 iterations, so
    these are distances to it, not to a converged solve.
  - **R3**: no point at 150 K; the top level moves at most 2.1 K (`z120_c`);
    the parent has no negative water.
  - **R4** (0.2% at 24 h; the second 12 h no more than the first): the
    default is at 7.2e-6 to 3.0e-5 at 24 h on every rung, within budget. It
    fails the second-half rule on the four rungs `z30_fo`, `z60_fo`, `z120_c`
    and `z120_fo`, by at most 1.7e-5 of the water (`z120_fo`). The copies lose
    their partition on the first-order rungs: 1.06 (`z30_fo`), 0.71, 0.60 at
    24 h; 4.1e-3 at `z120_c`; 1.6e-3 to 1.9e-3 elsewhere.
  - **R5** (own residual 0.02%; repair 0.20% a day): the copies' repair
    exceeds its row on every rung: 0.66% (`z60_c`), 0.69% (`z30_c`) and
    2.1% (`z120_c`) a day in established flow, up to 176% (`z60_fo`). Their
    own residual passes on the centred rungs (at most 1.7e-4) and fails on
    the first-order ones (up to 1.0e-2).
  - **R6** (at most 1.1): centred rungs pass (worst 1.06, `z60_c`, dt 60
    over 120 s); first-order rungs fail under the time step (up to 2.18,
    `z60_fo`). Most finer variants' parent moved more than 1% within the
    hour; those rows are marked.
  - **R7:** *not assessable* on every rung, since R5 fails everywhere. The
    unscored numbers are in the CSV: at `z60_c` the default would fail the
    first hour (`strat` L1 1.36%, `evap` 11.8%) and pass at 24 h.
  - **R8** (0.5% a day; 2% per tag): in established flow the partition
    repair moves nothing on the centred rungs; it moves 0.87% a day in the
    default at `z120_fo` and 11% to 17% in the copies at first order. `strat`'s
    `led_fix` is 3.6% of its inventory at `z120_fo` (default).
  - **R9** (at most 0.75; above 0.9 structural): `inc_left` falls on every
    rung (worst 0.51, `z60_fo`). The partition repair rises under refinement
    at `z60_fo` (3.8, 1.3 and 1.3): flagged structural.
  - **R10** (at most 0.75): every tag's `E` falls with the second iteration
    on every assessable rung (worst 0.49).

## The three failures of W25, bounded

  - **60 levels, the first hour.** R5 fails at 60 levels, so the first-hour
    comparison is not assessable: W25's miss was measured against an
    ineligible comparator. R10 passes in the startup window (0.16 to 0.27).
    P3 does not bring the first hour within budget: `evap`'s L1 is 11.7%,
    10.9% with the converged first step, 11.2% with tags rebuilt after it.
    So the miss is not bounded to the first step.
  - **120 levels, the partition.** The default now closes at 120 levels
    (2.6e-5 centred, 3.0e-5 first order, at 24 h), where W25 lost 3.0e-2 by
    12 h. The code differs from W25's by #105's cross blocks, #109 and #112,
    so this bounds, not isolates, what changed. `inc_left` falls under R9
    and every tag's `E` under R10 at `z120_c`: the remaining loss is the
    tags' lag.
  - **First order, the copies.** The copies' repair grows under R6 on the
    first-order rungs and not on the centred ones. By the design's rule the
    copies are not an eligible comparator under first-order reconstruction,
    and W25's break is bounded to the comparator. The default meets the 24 h
    budget there. It fails the second-half rule, by at most 1.7e-5.

## The failed P1 probes at `z120_fo`

Both failed in the 10-iteration reference's own step, at step 9 (16 min):
`w25_probes.jl:132` is `CA.CTS.step!(reference)`. The error is a
`DomainError` with −1.93 in `log`, in `exner_given_pressure` via `theta_v`
(`refstate_thermodynamics.jl:61`), from the implicit tendency. The reference
is built from the P4 configuration with only `max_newton_iters_ode: 10`, no
diagnostics and no closure check. It starts as the P4 driver starts, and the
probe never writes into it. The trials, stepped from its copies, took eight
steps without error. The P4 runs at one iteration completed, and P2's
10-iteration variant, started from the 6 h state, completed at `z120_fo`.

So this is the model, not the probe's setup. Ten Newton iterations at 120
levels with first-order reconstruction diverge in the first 20 minutes.
The design has no rule for a failed probe. By section 4's last line, R2 and
R10 at `z120_fo` are *not assessable* and the rung's P1 reading is *not
isolated*. There is no probe bug to fix, and nothing to resubmit. A reference
at fewer iterations or a shorter step would be a new pre-registration.
