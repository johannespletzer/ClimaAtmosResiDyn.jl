# Part 9: the water tag producer's checks (record, skeleton)

Skeleton, 2026-10-10. Nothing here is a result yet. The
[design](../../design/PART9_PRODUCER.md) fixes the checks, the jobs and the
stop rules. PR A is #170 (`claude/part9-producer`, `2c63c5c53`), merged into
`main` as `6a8fc6fb7` on 2026-10-10.

## 1. Jobs

| Run                    | Slurm ID | Node | Wall | MaxRSS | Archive |
|:---------------------- |:-------- |:---- |:---- |:------ |:------- |
| p9_trmm0m_on_6h        | pending  |      |      |        |         |
| p9_trmm0m_off_6h       | pending  |      |      |        |         |
| p9_trmm0m_newton_6h    | pending  |      |      |        |         |
| p9_trmm0m_restarted_6h | pending  |      |      |        |         |
| p9_trmm0m_on_f32_6h    | pending  |      |      |        |         |
| p9_trmm0m_off_f32_6h   | pending  |      |      |        |         |

First wave, 2026-10-10 07:30, producer at `648fad788`: jobs 14185494 (on),
14185495 (off), 14185496 (newton), 14185497 (on_f32) and 14185498 (off_f32).
The two off runs completed (13 and 12 min, 9.2 GB). The three on runs failed at
their first step with `KeyError: key (:inc, :evap, :total)`: the roster gave
`inc` and `negative` to partition tags alone, while the increment follower runs
for every tag. Fixed in PR A at `59216edef` with a source tag in the test. The
wave's outputs are under `output/p9_wave1_failed_roster/`, its logs and
manifests keep their job ids. Every job reruns at the new head.

Second wave, 2026-10-10 11:54, producer at `59216edef`: jobs 14186068 (on,
14:03, 9.0 GB), 14186069 (off, 12:30, 7.8 GB), 14186070 (newton, 12:52,
9.3 GB), 14186071 (on_f32, 13:00, 9.0 GB), 14186072 (off_f32, 12:38, 7.7 GB)
and 14186200 (restarted, 12:30, 9.2 GB), all completed. Every receipt carries
`model_commit` and `model_diff_sha256` as "unknown": git is not on the compute
node's PATH, as the provenance states. The converter refuses such a receipt by
design. The job script now loads `git/2.49.0`. The outputs are under
`output/p9_wave2_unknown_identity/`. Every job reruns at `2c63c5c53`, PR A's
head after the merge of `main` and the 1.11-only CI list.

Third wave, 2026-10-10 13:17, producer at `2c63c5c53`: the on job 14186477
completed (14:20, 9.0 GB) with the identity still "unknown". The git module
had been added to `g3base_check.sh`, which the part 9 jobs do not run. They
run `phase_c.sh` through `tag_closure_common.sh`, whose terrabyte branch now
loads `git/2.49.0`. Jobs 14186479 to 14186481 were cancelled, 14186478 (off)
ran to completion. The outputs are under `output/p9_wave3_unknown_identity/`.
Every job reruns at `2c63c5c53`.

Fourth wave, 2026-10-10 14:52, producer at `2c63c5c53`: jobs 14187046 (on,
13:23, 16:37 start), 14187047 (off, 12:33), 14187048 (newton, 12:51), 14187049
(on_f32, 12:36), 14187050 (off_f32, 12:25) and 14188441 (restarted, 13:24,
19:44 start), all completed. Every receipt carries `model_commit`
`2c63c5c53`, `model_dirty` false and the empty diff's hash. The converter
refused the on run all the same: it compared the receipt with the job
manifest's `head_sha`, and that is the record tree that submitted the job
(`6f2e2f5b2`, the restart `c3e248217`), not the run tree. The design had
assumed one tree for model and record. Since the decision of 2026-10-08 the
model runs from a second worktree at `main`, and `manifest.py` did not record
it. The tool now takes `--model-repo`, which `submit_g3.sh` passes from
`g3base_submit.sh`'s run tree, and records that tree under `model`. The
converter compares the receipt with `model` when it is present and writes the
model identity into the bundle, with the record tree's commit beside it. The
outputs are under `output/p9_wave4_record_manifest/`. Every job reruns at
`2c63c5c53` with the new manifest (owner, 2026-10-10).

Fifth wave, 2026-10-10 20:58, producer at `2c63c5c53`, PR B at `4812f5522`:
jobs 14189471 (on, 13:36, 21:32 start), 14189472 (off, 12:37), 14189473
(newton, 13:13), 14189474 (on_f32, 12:22), 14189475 (off_f32, 12:04) and
14191223 (restarted, submitted 2026-10-11 08:40), the first five completed.
The converter accepts the on and the Newton receipts against the manifests'
`model` entries. Before the restart, four checks ran on 2026-10-11:
`trial_rollback` PASS (144 steps of 150 s, one accepted trial each),
`complete_active_roster` PASS (14 channels, 6 model ledgers tie),
`accepted_weights` FAIL "no nonzero applied record with role final_map" and
`newton_replacement` FAIL "no post_newton record, though the run updates at
stage cadence". The case corrects no partition in 6 h: rescale, empty, repair
and negative write zero in every step for every tag (12 zero applications
dropped per step, 14 in the Newton run), and only `inc` writes nonzero
records, 19700 to 23616 nonzero cells per channel, all with the role
`implicit`. Every coefficient the records carry matches the reader's rule.
Part 8 had recorded `led_fix` 0 and partition repair 0 for this case. The
design's constant could not be met on it. The owner amended the design on
2026-10-11 (section 12): two jobs on the integration test's precipitating
column feed the weights check (final_map, implicit) and the Newton check,
the TRMM on run feeds the weights check for `implicit` alone, the four other
checks stay on the TRMM runs.

The restart job 14191223 completed (12:51, 08:39 start on 2026-10-11). Before
the check script, two checks ran by hand: `parent_bitwise_parity` PASS in
Float64 and in Float32 (6 checkpoints, 61 diagnostic files, 835 arrays
bitwise each), `all_channel_checkpoint_restart` FAIL "record_values differs".
The state at 3 h is bitwise the checkpoint's (every 150 s diagnostic at
10800 s equal). From the first restarted step the parent differs: `hus` by
5.4e-4 of itself at 10950 s and 1.1e-3 at 6 h, `ta` by 6.6e-5 and 6.1e-5,
`rhoa` by 6.2e-5 and 5.5e-5. The increment follower's 432 records of the
segment differ with it (the three `inc` channels, median 3% of the value),
their ledgers and the model's `inc` ledgers too, and the checkpoints at 4 h
and 6 h in `Y/c` and `Y/f`. Nothing else differs. The second wave's restart
(14186200) gave the same digits. FINDINGS E54 had found this inexact restart
of the model on 2026-09-18, BACKLOG E58 holds it as upstream's. The owner
amended the design on 2026-10-11 (section 13): the off run's restart is the
control, the restart check runs on the column's restart pair, the column
jobs were resubmitted with checkpoints. The first column on job (14191239)
had started at 09:03 and was cancelled at 09:15, so `p9_col1m_on_1h/output_0000`
holds that killed attempt without a receipt, and the run (14191396) is
`output_0001`, where `output_active` points. The check script reads the
directory `output_active` names, and the column restart config names
`output_0001`.

The control 14191395 (off restarted, 12:48, 09:20 start) completed. Its
state diverges from the off run as the on pair's does, `hus` by 5.372e-4 of
itself at 10950 s and 1.052e-3 at 6 h, the same digits: the TRMM restart's
divergence is the model's, not the producer's. The column jobs 14191396 (on,
17:45, 09:33 start, 14.8 GB) and 14191397 (newton, 17:28) completed with 31
channels each. By hand on 2026-10-11: the column's on run passes
`accepted_weights` for `final_map` and `implicit`, its Newton run passes
`accepted_weights` for all three roles (14778 records) and `trial_rollback`
(360 steps), and the TRMM on run passes `accepted_weights` for `implicit`.
`newton_replacement` first printed FAIL on the column's Newton run: two
post-Newton records of one follow channel at stage 2. The follow writes two
moves per precipitating part in one firing, each with two legs, which the
rule of section 3 did not describe. Section 14 (owner, 2026-10-11) bounds
the post-Newton count by the writer's moves: in the run at most two
post-Newton records per channel and stage, the implicit role one per stage
and tag, nothing accumulating. The check then reached its ledger tie and
refused the run, whose config had no `q_tag_led_inc_<tag>` diagnostics at
10 s. The Newton config gains them and the job reruns once.

## 2. Model identity

`model.head_sha` of each manifest (the run tree, with the record tree under
`head_sha`), `model_commit` and `model_diff_sha256` of each receipt, the
producer source hash against the registry config. Pending.

## 3. The six checks

| Check                          | Command | Result  | Log |
|:------------------------------ |:------- |:------- |:--- |
| accepted_weights               |         | pending |     |
| trial_rollback                 |         | pending |     |
| newton_replacement             |         | pending |     |
| complete_active_roster         |         | pending |     |
| parent_bitwise_parity          |         | pending |     |
| all_channel_checkpoint_restart |         | pending |     |

## 4. Verdict on H9

Pending. H9 is falsified by any FAIL above. `parent_bitwise_parity` is PASS
only when the Float64 pair and the Float32 pair both pass. If the model
refuses the stage cadence in the Newton job, `newton_replacement` is
recorded here as unverified and the registration proceeds with that stated
(owner, 2026-10-10).

## 5. Registration and the scorer rows

Pending: `register_producer` with the entry of
`water_tag_application_registry.json`, `cts_version` from the receipt pin,
then `COMMON.ACCEPTED_APPLICATION_ACTIVITY` and
`COMMON.APPLICATION_ACTIVITY.<window>` on the second bundle, converted at
150 s with the converted directory attached (design section 9). Every other
row reads the 30 min bundle.

## 6. Cost

Estimate against measured wall per job. Pending.
