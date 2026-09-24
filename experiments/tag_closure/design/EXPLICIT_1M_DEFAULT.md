# WP5b-V: does the follower become the default with 1M stepped explicitly?

Written on 2026-09-24, before any run, for the owner's review of #105 (finding
2), approved as part of Batch 3 the same day. The criteria below are fixed in
the record by this commit. The runs start after it.

## 1. The question

#105's cross blocks close W23's stratocumulus column under the follower
(W29: −2.1e-8 net, 5.7e-8 gross in an hour). One column in one regime does not
show that one Newton iteration stays within budget across the explicit-1M
EDMF runs that a default would reach. Until this passes, the follower is
opt-in there (#105 at `c446fe91`).

## 2. The case

TRMM_LBA with 1M microphysics, the upstream column
(`config/model_configs/prognostic_edmfx_trmm_column.yml`): deep convection,
rain and snow, 82 levels to 16.4 km, ARS222, 6 h. It is the sedimentation-
heaviest column the repository ships. Changed from upstream only as a tagged
run needs:
  - `implicit_microphysics: false`, the path in question;
  - water tags `pbl` and `free` (a region below and above 1 km, 200 m tanh
    edge, as W26) and `evap` (the surface flux), with
    `water_tag_transport: increment`;
  - the closure check and audit every 30 minutes, and the tags' diagnostics.

If the untagged twin fails on a rung, that rung is dropped and reported, and
no conclusion rests on it. If the case fails at `dt` 120 s untagged, the
ladder moves to 60 s and 30 s.

## 3. The rungs

| run                     | `dt`  | Newton | tags | transport |
|:----------------------- | -----:| ------:|:---- |:--------- |
| `w5v_trmm1m_dt120_n1`   | 120 s | 1      | yes  | increment |
| `w5v_trmm1m_dt120_n2`   | 120 s | 2      | yes  | increment |
| `w5v_trmm1m_dt120_n10`  | 120 s | 10     | yes  | increment |
| `w5v_trmm1m_dt60_n1`    | 60 s  | 1      | yes  | increment |
| `w5v_trmm1m_dt60_n10`   | 60 s  | 10     | yes  | increment |
| `w5v_trmm1m_dt120_n1_plain` | 120 s | 1  | no   |           |
| `w5v_trmm1m_dt60_n1_plain`  | 60 s  | 1  | no   |           |
| `w5v_trmm1m_dt120_n1_tracer` | 120 s | 1 | yes  | tracer (today's default there) |

## 4. Passes when all of these hold

1. **Budget.** On both one-iteration rungs, the partition's gross closure
   residual (`water_tag_closure.csv`, `gross_relative`) stays below 2e-3 at
   every half-hourly check through 6 h.
2. **Nonlinear convergence.** At `dt` 120 s, for `pbl` and `free`, the L1
   difference at 6 h from the Newton-10 run (`compare_runs.py`, weights
   ρ dz) is smaller with two iterations than with one.
3. **Timestep convergence.** For `pbl` and `free`, the one-iteration L1
   difference from the Newton-10 run at the same `dt` is no larger at 60 s
   than at 120 s.
4. **Parity.** Every model field of each one-iteration tagged run equals its
   untagged twin's, bit for bit.

Reported beside the verdict, not criteria:
  - the part left out (`increment_left_relative`) and the moved ledger;
  - the smallest partition tag value over the run;
  - the partition repair's ledger over the column's water;
  - at each output time, the fraction of cells, and of the column's water,
    where a share clamps (a tag above `q_tot` or below zero) and where the
    partition's norm is zero, from the output's `q_tag_*` and `hus`;
  - the tracer transport's closure at `dt` 120 s, one iteration, for scale.

## 5. What follows

Pass: a PR on #105 makes `increment` the default with 1M stepped explicitly
under the manual Jacobian, citing this run (and keeps the `use_auto_jacobian`
refusal). Fail: the follower stays opt-in, and the failing criterion and rung
go into FINDINGS and the PR thread.

The code is #105 at `1a37e43f`, run from the run tree `-wedmf5b-run` (the
record merged with it). The verifier is `analysis/evidence/compare_runs.py`;
the rule metrics are `analysis/water/w5r_rule_compare.py`'s; the clamp
statistics are `analysis/water/w5v_clamps.py`, written before the runs finish.

## 6. After the run: a check on the same atmosphere

Added on 2026-09-24, after W33 and before any run of this part, at the owner's
request ("Do check against a reference on the same atmosphere, as WP4a-V
does"). W33's criteria 2 and 3 compared runs whose atmospheres differ, since
ten Newton iterations change the model, so they mixed the atmosphere's
difference with the tags' lag. This part compares on one trajectory.

**Design.** The ten-iteration run is the reference trajectory. At every step
of it, from its own state `Yₖ`, a second integrator (the same configuration,
one Newton iteration) and a third (two iterations) each take one step. Each
result is compared with the reference's own step from `Yₖ`. So every
comparison starts from the same atmosphere, and the difference is the one-step
error of fewer iterations.

**Metric.** For each tag `i`, and for the parent `ρq_tot`, summed over the
run: `E = Σₖ Σ_cells |ρq_trial − ρq_ref| / Σₖ Σ_cells |ρq_ref − ρq(Yₖ)|`, the
local error relative to the step's own increment.

**Passes when**, for `pbl` and `free`:
  1. at `dt` 120 s, `E` with two iterations is smaller than with one;
  2. with one iteration, `E` at `dt` 60 s is no larger than at 120 s.

Reported beside it: the parent's `E` at each rung, and each tag's `E` over the
parent's. The probe is `analysis/water/w5v_same_atmosphere.jl`, run against
#105 at `1a37e43f`. If it passes, W33's verdict is revisited with the owner;
the default does not change without the owner.
