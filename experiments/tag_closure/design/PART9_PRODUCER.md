# Part 9: the water tag producer's runtime checks (design, 2026-10-10)

Pre-registered before any job. PR A (#170, `claude/part9-producer` at
`2c63c5c53`, merged into `main` as `6a8fc6fb7` on 2026-10-10) adds the key
`water_tag_applications`. PR B (this
design and its tools) converts the producer's output for the part 5 reader,
checks it on the cluster in six named checks, and assembles the proof that
the reader's production gate reads. The owner decided the constants of
section 6 and the inputs of section 11 on 2026-10-10 (DECISIONS.md,
"2026-10-10, part 9 PR B").

## 1. Question

Does the producer at `2c63c5c53`, in the part 8 default case (TRMM 0M, 6 h,
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
unsupported list, a model identity that differs from the run tree the job's
manifest records under `model`,
steps that are not contiguous, ledger times other than the receipt edges,
record ids that differ between the two files, and a `rhoa` whose `z` is not
the producer's cell centres to 4 eps of its dtype. Nothing is zero-filled
or interpolated.

The kept 60 s output (scratchpad `p9/keep_out/step`) came from an earlier
commit of PR A. Its roster is an object, its step lines carry
`unattributed_calls`, and its header lacks the channels, unsupported,
`producer` and `native_arrays` keys. The tests use a synthetic fixture in the
`2c63c5c53` format instead (`make_water_tag_application_fixture.py`).

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
  - Fixed: model `2c63c5c53` from a clean detached tree, the part 8 default
    config otherwise unchanged (ARS222, dt 150 s, 6 h, column, 82 levels,
    Float64, Float32 in the pair of section 7), `reproducible_restart: true`
    and hourly checkpoints in all six runs, the 150 s diagnostics `rhoa`, `ta`, `hus`, `q_tag_led_fix_<tag>` and
    `q_tag_led_inc_<tag>`, one process, CPU, an exclusive node.
  - The Newton run adds `max_newton_iters_ode: 2` and
    `update_constrain_state_every: "stage"`. With the default single Newton
    iteration and step cadence, no repeated evaluation and no post-Newton map
    occurs, so the check would pass without testing anything.
  - The analysis code is this PR's commit. The manifest of each job records
    this record's commit under `head_sha` and the run tree under `model`,
    with `head_sha` `2c63c5c53`.

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

Section 12 adds two jobs on a second case. About 1.6 node-hours, 6 at the limits. Six jobs stay under the size at
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
    in the on run, `post_newton` in the Newton run. Amended in section 12:
    the TRMM case fires `implicit` alone, the column case the three.
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
(`water_tag_applications.jl` at `2c63c5c53`), `roster_key`
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
  - More than 6 jobs or 6 node-hours at the limits: stop and ask. Section 12
    raises this to 8 and 8, section 13 to 10 and 10 (owner, 2026-10-11).
  - The producer source hash differs from section 8: stop, redo the entry.

## 11. Owner inputs (decided 2026-10-10)

 1. The constants of section 6: as proposed.
 2. The Float32 pair of section 7: in.
 3. The second bundle at 150 s for the two scorer rows (section 9): yes.
 4. Submission of the six jobs, each with approval, `restarted` after `on`.
    The Newton job as planned, with the stop rule of section 10.

## 12. Amendment, 2026-10-11: the precipitating column for the final maps and the post-Newton maps

Written after the fifth job wave, with its data read. The TRMM 0M case
corrects no partition in 6 h: in every step and for every tag the rescale,
the empty, the repair and the negative giver write zero, the producer drops
the zero applications, and only the increment follower writes nonzero
records, all with the role `implicit`. Part 8 had recorded this for the same
case (PART8.md: `led_fix` 0 for the three tags, partition repair 0 per day).
So the constant of section 6, a nonzero `final_map` record in the on run and
a `post_newton` record in the Newton run, could not be met on this case, and
`accepted_weights` and `newton_replacement` print FAIL for that reason alone.
Every coefficient the records do carry matches the reader's rule. The design
missed this against PART8.md. The owner chose this amendment over a
registration with the two roles unverified on the cluster, and over a longer
TRMM run, on 2026-10-11 (DECISIONS.md, "2026-10-10, part 9 PR B").

### 12.1 The question, restated

Does the producer at `2c63c5c53` write the final maps and the post-Newton
maps with the reader's weights in a case that fires them? The case is the
integration test's precipitating column
(`test/water_tag_applications_common.jl` at `2c63c5c53`): `PrecipitatingColumn`,
1M microphysics, 20 levels to 6 km, dt 10 s, tags `lower` and `upper` by
region at 3 km and `evap` by source, the precipitation tags on, increment
transport, ARS222 as the TRMM case (the test runs the default ARS343). Run
for 1 h, 360 accepted steps. The roster has 31 channels, as the test expects.
H9 keeps its six checks. Any FAIL still falsifies it.

### 12.2 The jobs

`configs/p9_col1m_on_1h.yml` and `configs/p9_col1m_newton_1h.yml`, through
`runscripts/part9_checks.sh col1m_on col1m_newton`. The Newton config adds
`max_newton_iters_ode: 2` and `update_constrain_state_every: "stage"`, as
the TRMM Newton job does. Estimate 10 min each, the build and the startup
alone (not measured), 1 h limit, 48G, an exclusive node. The set is eight
jobs and 1.9 node-hours, 8 at the limits. Section 10's cap rises to 8 and 8.

### 12.3 What each check reads

  - `accepted_weights`: the column's on run for `final_map` and `implicit`,
    and the TRMM on run for `implicit` alone. Both results go into one log,
    and the gate passes the check only when every result is PASS.
  - `newton_replacement`: the column's Newton run, with `--expect-post-newton`.
  - `trial_rollback`, `complete_active_roster`, `parent_bitwise_parity` and
    `all_channel_checkpoint_restart`: the TRMM runs, unchanged.
  - The TRMM Newton run is recorded in PART9.md as the run that showed the
    gap. It is not checked. The scorer rows of section 9 keep the TRMM
    bundles.

### 12.4 Stop rules

Section 10 applies. The column case is a check job for two roles, not a
scorer case, so it has no bundle and no parity pair.

## 13. Amendment, 2026-10-11: the restart check on the column, the TRMM restart as E54

Written after the fifth wave's restart job, with its data read. The TRMM
restart pair fails `all_channel_checkpoint_restart` on the record values.
The state at 3 h is bitwise the checkpoint's, and from the first restarted
step on the parent differs (humidity by 5e-4 of itself after one step), the
increment follower's records with it, and the checkpoints at 4 h and 6 h in
`Y/c` and `Y/f`. The second wave's restart gave the same digits, so the
divergence is deterministic. The parity between the on and the off run is
exact in both precisions, so the producer leaves the parent alone within a
segment. The record already states the cause: FINDINGS E54 (2026-09-18) found
that the model does not restart a column bit for bit even with
`reproducible_restart: true`, while the tags and the records are restored
exactly, and BACKLOG E58 holds it as upstream's. The design asked for a
bitwise restart on this case against that finding. The owner chose this
amendment over a registration with the restart unverified and over a report
to PR #170 (DECISIONS.md, "2026-10-10, part 9 PR B").

### 13.1 The control

`configs/p9_trmm0m_off_restarted_6h.yml`: the off run restarted from its own
checkpoint at 3 h. Without the producer, a divergence of the same kind
attributes the TRMM restart to the model. Its state against the off run is
compared by `water_tag_application_checks.py model_restart`, the restart
check's checkpoint and diagnostic comparison alone, from 3 h. The result is
recorded in PART9.md, not gated.

### 13.2 The restart check

`all_channel_checkpoint_restart` runs on the column's restart pair,
`p9_col1m_on_1h` (checkpoints every 30 min, `reproducible_restart: true`)
and `configs/p9_col1m_restarted_1h.yml`, from 30 min to 1 h. PR A's
integration test restarts this column and finds every record, scale, flag
and ledger equal. The column has no EDMF. The TRMM pair's result under the
same check, and the model's own restart of the on run and of the column, go
to `record_*.log` beside the gate logs.

### 13.3 Jobs

Ten jobs, 2.3 node-hours, 10 at the limits. The column's on and Newton jobs
of section 12 were resubmitted with the checkpoint keys before they started.
Section 10's cap rises to 10 and 10.

## 14. Amendment, 2026-10-11: the Newton rule's count for the follow

Written after the column's Newton run (section 12), with its data read.
`newton_replacement` printed FAIL "a second post_newton record of stage 2"
on `follow.lower.nonprecipitating`. The rule of section 3, at most one
record per step, channel, role and stage, described the mechanisms that
write one application per part and firing. The follow does not
(`tagged_water_precipitation.jl` at `2c63c5c53`, `_rescale_water_tag_parts!`
and `_apply_part_follow!`): one firing moves each precipitating part twice,
where it falls and where it rises, and each move has a leg into the part and
a leg out of the non-precipitating part. The receipt names neither the hook
nor the move. In the run, the rain channels carry at most two post-Newton
records at a stage and the non-precipitating channels at most two of the
four they may, the implicit role has one record per stage and tag, and the
close and the repair one each. Nothing accumulates. The rule becomes: one
implicit record per step, channel and stage, and post-Newton records up to
the writer's count for one firing, two for the follow's rain and snow
channels, four for its non-precipitating channel, one for every other
mechanism (`records_per_firing` in the checks module, with a test). The
owner chose this over a rule for the implicit role alone and over a
producer change that names the move (DECISIONS.md, "2026-10-10, part 9
PR B"). With the count right, the check reached its ledger tie and found
that the column's Newton config had no `q_tag_led_inc_<tag>` diagnostics at
10 s, which section 12 omitted. The config gains them and the Newton job
reruns once, under section 10's first rule, with approval. The on and the
restarted column configs stay as they are, so the restart pair's diagnostic
file sets stay equal.
