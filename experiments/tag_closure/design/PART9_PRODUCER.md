# Part 9: the water tag producer's runtime checks (design, 2026-10-10)

Pre-registered before any job. PR A (#170, `claude/part9-producer` at
`59216edef`, not on `main`) adds the key `water_tag_applications`. PR B (this
design and its tools) converts the producer's output for the part 5 reader,
checks it on the cluster in six named checks, and assembles the proof that
the reader's production gate reads. The owner decided the constants of
section 6 and the inputs of section 11 on 2026-10-10 (DECISIONS.md,
"2026-10-10, part 9 PR B").

## 1. Question

Does the producer at `59216edef`, in the part 8 default case (TRMM 0M, 6 h,
tags `pbl` and `free` by region and `evap` by source, increment transport,
ARS222, dt 150 s), write every accepted application of the water tags'
corrections with the reader's weights, leave the parent's fields bit for bit
unchanged, and restart exactly?

Hypothesis H9: yes. Any one of the six checks printing FAIL on the job set of
section 5 falsifies it. A job that does not finish leaves H9 open, not
falsified.

## 2. What PR A writes, and the converter

The producer writes `water_tag_application_receipt.jsonl` (a header line, then
one line per accepted step) and `water_tag_applications.nc`. The header holds
`model_commit`, `model_dirty`, `model_diff_sha256` (sha256 of
`git diff HEAD --binary --no-ext-diff --no-textconv`), the `integrator_pin`,
the roster as a list of channel ids under `water_tag_application_roster`,
each channel's description under `water_tag_application_channels`, and
`water_tag_application_unsupported`.

`analysis/evidence/water_tag_applications_convert.py` maps them for the reader:

| Reader input                                               | From                                                                                               |
|:---------------------------------------------------------- |:-------------------------------------------------------------------------------------------------- |
| `application_receipt.json`                                 | the header as written, plus `steps` = the step lines. `model_diff_sha256` copied, never recomputed |
| `applications.npz`, `PREFIX__values`, `__event_scale`      | `record_values`, `record_event_scale`, the rows of the channel in receipt order                    |
| `__fallback`, `__bound`, `__clamp`, `__zero_normalization` | bits 0 to 3 of `record_flags`                                                                      |
| `__record_ids`, `__quantity`, `__units`                    | `record_id`, the channel's quantity and units                                                      |
| `weights`, `geometry`, `weight_units`                      | the NetCDF's, geometry transposed to (cell, coord)                                                 |
| ledger `application_ledger_<prefix>`                       | `ledger[:, c, :]`, Float64, at `ledger_time` = the receipt edges                                   |
| `rho` at every edge                                        | the run's `rhoa` diagnostic at 150 s, with the producer's weights and geometry                     |

It refuses, with the reason, a roster that is not an id list, a non-empty
unsupported list, a model identity that differs from the run's manifest,
steps that are not contiguous, ledger times other than the receipt edges,
record ids that differ between the two files, and a `rhoa` whose `z` is not
the producer's cell centres to 4 eps of its dtype. Nothing is zero-filled
or interpolated.

The kept 60 s output (scratchpad `p9/keep_out/step`) came from an earlier
commit of PR A. Its roster is an object, its step lines carry
`unattributed_calls`, and its header lacks the channels, unsupported,
`producer` and `native_arrays` keys. The tests use a synthetic fixture in the
`59216edef` format instead (`make_water_tag_application_fixture.py`).

## 3. The six checks

`analysis/evidence/water_tag_application_checks.py`, one subcommand per check.
Each prints `CHECK <key>: PASS` or `CHECK <key>: FAIL <reason>`, then INFO
lines. The registry's `check_log_pattern` is
`^CHECK (?P<check>[a-z_]+): (?P<result>PASS|FAIL)\b`.

The reader is `analysis/evidence/correction_accounting.py` at this branch.
The gate's rule, quoted from `production_gate` (`:450`, the per-check loop
at `:488-499`): each check needs
`result == "PASS"`, a command, an environment and a log, and the log must
record the check by name, with every named result PASS
(`require(all(r == "PASS" for r in results), ...)`).

| Check (gate key)                 | Run                          | Pass rule                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
|:-------------------------------- |:---------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `accepted_weights`               | on                           | `read_receipt` passes (`correction_accounting.py:165-271`). Its weight rule (`:255-262`): final maps weigh 1, tendencies `(b - a) * b_imp[stage-1]` in s, post-Newton maps `b_imp[stage-1] / implicit_diagonal[stage-1]`, compared with `==`. The pin's `b_exp`, `b_imp`, `implicit_diagonal` equal ClimaTimeSteppers' ARS222 exactly, and `b_exp != b_imp`. Every role matches its channel's quantity. A nonzero record exists for `final_map` and `implicit`                                                                                                                                                                                               |
| `trial_rollback`                 | on                           | Each step has one trial, accepted, and every record is applied in it. Steps are contiguous at 150 s. The producer's ledger starts at zero, and each edge equals the last plus the step's weighted records, to the allowance of section 6                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `newton_replacement`             | newton                       | `read_receipt` passes (`correction_accounting.py:165-271`, one applied record per channel, trial and application). At most one record per step, channel, role and stage for the roles `implicit` and `post_newton`, so one of each at a stage passes. Each is at a stage with an implicit solve. At least one `post_newton` record. The `inc` and `negative` records tie to the model's `q_tag_led_inc_<tag>`                                                                                                                                                                                                                                                |
| `complete_active_roster`         | on                           | The receipt roster equals the roster that `water_tag_application_channels` builds for the run's merged config, in order. Unsupported is empty. `channel_metrics` (`correction_accounting.py:385`) passes for every channel over the whole run (the ledger tie and \|signed\| <= retained <= accepted activity). For each tag the records tie to the model's `q_tag_led_fix_<tag>` (rescale, empty, repair, close) and `q_tag_led_inc_<tag>` (inc, negative) at every step                                                                                                                                                                                    |
| `parent_bitwise_parity`          | on, off, and on_f32, off_f32 | The same checkpoints exist, at least one. Every array of each checkpoint is bitwise equal (dtype, shape and bytes, so signed zeros and NaN payloads count), except the producer's `fields/tag_ledger.applications.*`, which the on run must have. The same diagnostic files exist, and every variable is bitwise equal                                                                                                                                                                                                                                                                                                                                       |
| `all_channel_checkpoint_restart` | on, restarted                | The restarted header says `ledger_start: checkpoint` and equals the continuous one but for the segment start. Its step lines equal the continuous run's after 3 h (`==` on the parsed JSON). Record values, event scales, flags and channels are bitwise equal by record id. Ledgers at every edge from 3 h are bitwise equal. Every common checkpoint after 3 h is bitwise equal, the producer's ledgers included. The same diagnostic files exist, at least one. In each, every variable is bitwise equal. A variable with a `time` dimension, found by name in any position, is compared at the common times after 3 h, and each file needs one such time |

Parity runs on the Float64 pair and on the Float32 pair of section 7. Both
results go to one log, and the gate passes the check only when both are
PASS. The tests run the check on a Float32 fixture.

## 4. Controls and fixed settings

  - Control for parity: `p9_trmm0m_off_6h`, the same config with the key
    `false`. Control for the restart: `p9_trmm0m_on_6h` itself, the continuous
    run.
  - Fixed: model `59216edef` from a clean detached tree, the part 8 default
    config otherwise unchanged (ARS222, dt 150 s, 6 h, column, 82 levels,
    Float64, Float32 in the pair of section 7), `reproducible_restart: true`
    and hourly checkpoints in all six runs, the 150 s diagnostics `rhoa`, `ta`, `hus`, `q_tag_led_fix_<tag>` and
    `q_tag_led_inc_<tag>`, one process, CPU, an exclusive node.
  - The Newton run adds `max_newton_iters_ode: 2` and
    `update_constrain_state_every: "stage"`. With the default single Newton
    iteration and step cadence, no repeated evaluation and no post-Newton map
    occurs, so the check would pass without testing anything.
  - The analysis code is this PR's commit. The manifest of each job records
    `head_sha` `59216edef`.

## 5. Job set and cost

`runscripts/part9_checks.sh` (dry run unless `--submit`), configs
`configs/p9_trmm0m_{on,off,newton,restarted,on_f32,off_f32}_6h.yml`. Then
`runscripts/part9_check_logs.sh` on a login node writes the six logs.

Basis: part 8's default job 14170101 (PART8.md): wall 844 s, build 209.9 s,
79.8 ms per step, MaxRSS 7.48 GiB. The 623 s of startup is kept. The build is
taken as 1.5 times and the steps as 3 times part 8's for the meter, its writes
and the 150 s output (decided 2026-10-10, not measured). The Float32 pair
is estimated as its Float64 twins.

| Job                      | Checks it feeds                            | Estimate | Limit | Memory | Node-hours (limit) |
|:------------------------ |:------------------------------------------ |:-------- |:----- |:------ |:------------------ |
| `p9_trmm0m_on_6h`        | weights, rollback, roster, parity, restart | 16 min   | 1 h   | 48G    | 0.27 (1)           |
| `p9_trmm0m_off_6h`       | parity                                     | 15 min   | 1 h   | 48G    | 0.25 (1)           |
| `p9_trmm0m_newton_6h`    | Newton replacement                         | 17 min   | 1 h   | 48G    | 0.28 (1)           |
| `p9_trmm0m_restarted_6h` | restart, after `on`                        | 16 min   | 1 h   | 48G    | 0.27 (1)           |
| `p9_trmm0m_on_f32_6h`    | parity in Float32                          | 16 min   | 1 h   | 48G    | 0.27 (1)           |
| `p9_trmm0m_off_f32_6h`   | parity in Float32                          | 15 min   | 1 h   | 48G    | 0.25 (1)           |

About 1.6 node-hours, 6 at the limits. Six jobs stay under the size at
which a set goes to the owner first: "Any set over 12 jobs or 24 hours goes
to the owner first" (`DELIVERY_PLAN.md:58-59`). The runs keep the full 6 h.
Steps are about 1% of part 8's wall, so a shorter run saves little. The
per-job arithmetic is in `runscripts/part9_checks.sh`.

## 6. Constants (decided 2026-10-10)

The owner decided these four as proposed on 2026-10-10.

  - Ledger allowances reuse the reader's `ROUNDING_ULPS` (16) and
    `LEDGER_EXTRA_OPERATIONS` (3). The producer ledger check allows
    16 eps(Float64) (k + 1) max(\|L before\|, \|L after\|, Σ\|weighted record\|)
    per cell and step, k the step's records of the channel. The model-ledger
    tie allows 16 eps(dtype) (k + 3 + 2) times the same maxima in density
    units. The 2 counts the diagnostic's division by ρ and the
    multiplication by `rhoa` (`DIAGNOSTIC_OPERATIONS`).
  - `Z_MATCH_ULPS` = 4: `rhoa`'s `z` against the producer's centres.
  - Roles that must appear with a nonzero record: `final_map` and `implicit`
    in the on run, `post_newton` in the Newton run.
  - The cost factors 1.5 (build) and 3 (steps) of section 5.

## 7. Limits carried from PR A

  - Default mode only. The leak correction is not metered and the key refuses
    it. The updraft copies are refused. Energy tags are out of scope.
  - One parity configuration in CI (the 1M column). This set adds one, TRMM 0M.
  - Float32: PR A's Float32 parity group covers the 1M column only. Decided
    2026-10-10: the set adds `p9_trmm0m_on_f32_6h` and `p9_trmm0m_off_f32_6h`,
    the on and off configs with `FLOAT_TYPE: "Float32"` and their own job ids,
    nothing else changed. `parent_bitwise_parity` runs on this pair too. Two
    more jobs, about 0.5 node-hours. The other checks stay on Float64.
  - CPU and one process. A GPU device and distributed runs are refused.
  - The output grows with records times cells. A column is small.
  - The producer's ledger is the running sum of its own records. The
    completeness evidence is the tie to the model's own ledgers, per tag.

## 8. The proof and the registry

`analysis/evidence/water_tag_application_proof.py` copies the six logs and
the producer source into the bundle and writes `lifecycle_evidence.json`:
kind `runtime_validation`, the receipt's `model_commit`,
`model_diff_sha256` and `integrator_pin`, `producer_id`
`climaatmos.water_tag_applications`, `producer_source` and the six checks
with result, command, environment and log. It then adds the new files and
their SHA256 to the bundle manifest's `artifacts` and sets
`correction_accounting.lifecycle_evidence` to the proof's name.

The registry entry is data in
`analysis/evidence/water_tag_application_registry.json`, status `pending`:
`source_sha256` `c45fef7fbc654155ed1189169716086cc8a82222df7518f148cb06f01b98af94`
(`water_tag_applications.jl` at `59216edef`), `roster_key`
`water_tag_application_roster`, `inactive_arrays`
`{"values": "values", "mark": "inactive"}`, the check log pattern of section 3,
and `cts_version` empty. `register_producer` is called only in the record
follow-up, after the six checks pass on the cluster. `cts_version` is then
the cluster receipt's pin version. A source hash other than the one above
means PR A changed, and the entry is redone before registration.

## 9. What flips in the scorer

With the registered entry, a full bundle with the accounting section and the
proof, and the `validity` and `roster` rows PASS:

  - `COMMON.ACCEPTED_APPLICATION_ACTIVITY` (score_acceptance.py:998) goes from
    NOT ASSESSABLE to PASS.
  - `COMMON.APPLICATION_ACTIVITY.<window>` (score_acceptance.py:943) goes from
    NOT ASSESSABLE to REPORTED ONLY.
  - Paired precipitation stays as it is (PART5.md). The 0M case has none.

`channel_metrics` aligns each ledger with the candidate's `rho`. The scorer's
30 min bundle has `rho` every 30 min, so `attach` refuses it. Decided
2026-10-10: a second bundle, converted by `convert_output.py --period 150s`
from the same on run, with the converted directory attached, serves the two
accounting rows `COMMON.ACCEPTED_APPLICATION_ACTIVITY` and
`COMMON.APPLICATION_ACTIVITY.<window>`. The 30 min bundle serves every other
row. The commands are in the evidence README, section "The part 9 producer
checks".

## 10. Stop rules

  - A job fails or the model refuses: stop, record it, no rerun without the
    owner. One rerun per job for an infrastructure failure, with approval.
  - A check prints FAIL: no registration. Record the log. A parity or restart
    FAIL is reported to PR #170 as blocking.
  - The Newton job is submitted as planned. If the model refuses the stage
    cadence on this case, `newton_replacement` is recorded as unverified and
    the registration proceeds with that stated (decided 2026-10-10). A Newton
    job that fails for another reason follows the first rule.
  - More than 6 jobs or 6 node-hours at the limits: stop and ask.
  - The producer source hash differs from section 8: stop, redo the entry.

## 11. Owner inputs (decided 2026-10-10)

 1. The constants of section 6: as proposed.
 2. The Float32 pair of section 7: in.
 3. The second bundle at 150 s for the two scorer rows (section 9): yes.
 4. Submission of the six jobs, each with approval, `restarted` after `on`.
    The Newton job as planned, with the stop rule of section 10.
