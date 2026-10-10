# Part 9: the water tag producer's checks (record, skeleton)

Skeleton, 2026-10-10. Nothing here is a result yet. The
[design](../../design/PART9_PRODUCER.md) fixes the checks, the jobs and the
stop rules. PR A is #170 (`claude/part9-producer`, `2140fceaf`).

## 1. Jobs

| Run                    | Slurm ID | Node | Wall | MaxRSS | Archive |
|:---------------------- |:-------- |:---- |:---- |:------ |:------- |
| p9_trmm0m_on_6h        | pending  |      |      |        |         |
| p9_trmm0m_off_6h       | pending  |      |      |        |         |
| p9_trmm0m_newton_6h    | pending  |      |      |        |         |
| p9_trmm0m_restarted_6h | pending  |      |      |        |         |

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

Pending. H9 is falsified by any FAIL above.

## 5. Registration and the scorer rows

Pending: `register_producer` with the entry of
`water_tag_application_registry.json`, `cts_version` from the receipt pin,
then `COMMON.ACCEPTED_APPLICATION_ACTIVITY` and
`COMMON.APPLICATION_ACTIVITY.<window>` on the bundle of the design's section 9.

## 6. Cost

Estimate against measured wall per job. Pending.
