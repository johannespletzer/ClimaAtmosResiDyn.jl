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
