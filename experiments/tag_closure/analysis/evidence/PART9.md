# Part 9: the water tag producer's checks (record, skeleton)

Skeleton, 2026-10-10. Nothing here is a result yet. The
[design](../../design/PART9_PRODUCER.md) fixes the checks, the jobs and the
stop rules. PR A is #170 (`claude/part9-producer`, `59216edef`).

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

## 2. Model identity

`head_sha` of each manifest, `model_commit` and `model_diff_sha256` of each
receipt, the producer source hash against the registry config. Pending.

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
