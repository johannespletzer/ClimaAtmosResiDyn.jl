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

The column's restart 14191518 (17:46, 11:38 start) and the Newton rerun
14191544 (18:14, 11:43 start, `output_0001`) completed. The check script
ran on 2026-10-11 13:15 over the ten runs: `accepted_weights` PASS on the
column's on run (final_map, implicit, 13274 records) and on the TRMM on run
(implicit), `trial_rollback` PASS, `complete_active_roster` PASS,
`parent_bitwise_parity` PASS in both precisions,
`all_channel_checkpoint_restart` PASS on the column's pair. The record
logs: the TRMM pair fails the producer's restart check and the model-only
comparison, the off pair fails the model-only comparison the same way, the
column's model-only restart passes. `newton_replacement` printed FAIL in
its ledger tie for `evap` at the first step: 145 cells over 77 steps hold
specks between 1e-49 and 4e-19 of the column's largest ledger value and
miss the per-cell allowance by relative 3e-14 to 2e-11, the follower's
cancellation of the parent's water change. Section 15 (owner, 2026-10-11)
takes the tie's maxima over the step's column. With it every tie of both
cases passes, the largest discrepancy at 2 percent of its allowance, and
the check script ran again: the six checks PASS on 2026-10-11 13:4x (logs
under the check directory, copied into the proof).

Registration dry run, 2026-10-11: the two scorer bundles were built from
the on run (`convert_output.py`, 30 min and 150 s, record commit
`885364263`), the converted directory attached to the 150 s bundle, the
proof built in it (six PASS, `model_commit` `2c63c5c53`, pin version
`1.0.1`), the producer source hash equal to the registry's, and the registry
entry turned to `registered` with `cts_version` `1.0.1`. The scorer then
left `COMMON.ACCEPTED_APPLICATION_ACTIVITY` NOT ASSESSABLE on the 150 s
bundle: its prerequisites `COMMON.ROSTER` (no `tag_pbl` at 150 s) and
`COMMON.NEGATIVE_WATER` (closure table rows at 30 min) fail there. The
30 min bundle passes both but fails every row that needs the untagged twin,
which part 9 did not run. Section 16 (owner, 2026-10-11) adds the tags and
the closure check at 150 s to the four Float64 TRMM configs, samples tables
at the field times in the bundle converter, and reruns on, off and the two
restarts. The wave 5 directories of the four are kept under
`output/p9_wave5_trmm_30min_tables/`.

Section 16 reruns, 2026-10-11 13:55, producer at `2c63c5c53`, PR B at
`e6c4cae96`: jobs 14191712 (on, 13:22, 14:37 start) and 14191713 (off,
12:29) completed, the on receipt at `2c63c5c53` clean with 14 channels, the
tags at 150 s and 146 closure rows. The restarts 14191867 (restarted) and
14191868 (off_restarted) were submitted at 15:36. Both bundles were rebuilt
from the new on run at 15:40 (record commit `e6c4cae96`), the converted
directory attached to the 150 s bundle. Before the proof, `COMMON.ROSTER`
and `COMMON.NEGATIVE_WATER` PASS on both bundles, and the two accounting
rows wait for the lifecycle proof alone ("missing verified producer
acceptance/rollback, parent parity and restart evidence").

## 2. Model identity

Every job manifest of the final set records the record tree under
`head_sha` and the run tree under `model`: `model.head_sha`
`2c63c5c53b6c1e70ae7ab3c63367fca672c6dc15`, `model.diff_sha256` the empty
diff's hash `e3b0c442...b855`, no status lines. Every receipt of the key-on
runs carries the same `model_commit` and `model_diff_sha256` with
`model_dirty` false, and the pin `ClimaTimeSteppers 1.0.1`, `ARS222`. The
producer source `water_tag_applications.jl` of the run tree hashes to
`c45fef7fbc654155ed1189169716086cc8a82222df7518f148cb06f01b98af94`, the
registry's `source_sha256`. The lifecycle proof in the 150 s bundle repeats
the commit, the diff hash and the pin.

## 3. The six checks

`runscripts/part9_check_logs.sh` on 2026-10-11 17:2x on the login node, PR B
at `e6c4cae96`, over the final set of section 6. Logs and commands under the
check directory, copied into the 150 s bundle's `lifecycle_logs/`.

| Check                          | Runs                                 | Result | Detail                                                                             |
|:------------------------------ |:------------------------------------ |:------ |:---------------------------------------------------------------------------------- |
| accepted_weights               | column on, TRMM on (implicit)        | PASS   | 13274 records with final_map and implicit, 2448 with implicit, pin ARS222          |
| trial_rollback                 | TRMM on                              | PASS   | 144 steps of 150 s, one accepted trial each, ledgers equal the applied records     |
| newton_replacement             | column Newton                        | PASS   | 4716 stage keys within the writer's count, 1500 post_newton, 3 ledgers tie         |
| complete_active_roster         | TRMM on                              | PASS   | 14 channels as the config builds them, a record every step, 6 model ledgers tie    |
| parent_bitwise_parity          | TRMM Float64 pair, TRMM Float32 pair | PASS   | 6 checkpoints and 65 diagnostic files, every array bitwise, in each pair           |
| all_channel_checkpoint_restart | column on, column restarted          | PASS   | 180 step lines, records, ledgers, checkpoints and diagnostics bitwise after 30 min |

Recorded beside the gate, not in it: the TRMM restart pair fails the
producer's restart check on the record values and the model-only comparison
on `Y/c`, the off pair fails the model-only comparison the same way, and the
column's model-only restart passes (FINDINGS E54, design section 13).

## 4. Verdict on H9

Not falsified. The six checks print PASS on the final set, under the design
as amended in sections 12 to 16 after the data of waves 5 and 6: the
precipitating column for the roles the TRMM case does not fire and for the
restart the model does not reproduce there, the Newton count by the
writer's moves, the ledger tie by the column's scale, and the 150 s outputs
the scorer's prerequisites read. Each amendment is dated and says what the
data showed first. The producer leaves the parent bit for bit unchanged in
both precisions, records every accepted application of the water tags'
corrections with the reader's weights on both cases, and restarts exactly
where the model does.

## 5. Registration and the scorer rows

`water_tag_application_registry.json` is `registered` since 2026-10-11 with
`cts_version` `1.0.1`, the receipt pin's version. `score_acceptance.py`
registers the producer from it at start. The two bundles of the on run
(record commit `e6c4cae96`, `$SCRATCH/tag_closure/part9/on_30m` and
`on_150s`), the converted directory attached to the 150 s bundle and the
lifecycle proof built in it (six PASS). Scored on 2026-10-11:

| Row                                  | 150 s bundle  | 30 min bundle  |
|:------------------------------------ |:------------- |:-------------- |
| COMMON.ROSTER                        | PASS          | PASS           |
| COMMON.NEGATIVE_WATER                | PASS          | PASS           |
| COMMON.ACCEPTED_APPLICATION_ACTIVITY | PASS          | NOT ASSESSABLE |
| COMMON.APPLICATION_ACTIVITY.startup  | REPORTED ONLY | NOT ASSESSABLE |

The two rows flip as section 9 states. On the 150 s bundle the accounting
is complete over 14 channels with no inactive or unavailable channel. Three
channels have accepted activity, `inc.pbl.total` 0.470, `inc.free.total`
0.559 and `inc.evap.total` 0.037 (the scorer's units), the eleven others
zero. The 30 min bundle has no application accounting at its cadence, as
designed. Both bundles stay `NOT QUALIFIED`: part 9 ran no untagged twin,
so every row that needs one reports a data failure, and the persistent
blocked rows wait for their parts.

## 6. Jobs and cost

The final set, fourteen jobs, all on `hpda2_compute`, one process, an
exclusive node, model `2c63c5c53`:

| Job                          | Id       | Wall  | MaxRSS  | Estimate | Record commit |
|:---------------------------- |:-------- |:----- |:------- |:-------- |:------------- |
| `p9_trmm0m_on_6h`            | 14191712 | 13:22 | 8.8 GB  | 16 min   | `e6c4cae96`   |
| `p9_trmm0m_off_6h`           | 14191713 | 12:29 | 7.3 GB  | 15 min   | `e6c4cae96`   |
| `p9_trmm0m_newton_6h`        | 14189473 | 13:13 | 8.5 GB  | 17 min   | `4812f5522`   |
| `p9_trmm0m_restarted_6h`     | 14191867 | 13:09 | 8.7 GB  | 16 min   | `e6c4cae96`   |
| `p9_trmm0m_off_restarted_6h` | 14191868 | 12:24 | 7.4 GB  | 15 min   | `e6c4cae96`   |
| `p9_trmm0m_on_f32_6h`        | 14189474 | 12:22 | 8.6 GB  | 16 min   | `4812f5522`   |
| `p9_trmm0m_off_f32_6h`       | 14189475 | 12:04 | 7.4 GB  | 15 min   | `4812f5522`   |
| `p9_col1m_on_1h`             | 14191396 | 17:45 | 14.5 GB | 10 min   | `14edd4ffd`   |
| `p9_col1m_newton_1h`         | 14191544 | 18:14 | 14.8 GB | 10 min   | `d37527b6a`   |
| `p9_col1m_restarted_1h`      | 14191518 | 17:46 | 14.1 GB | 10 min   | `1dcd4dba3`   |

The TRMM estimates of section 5 (1.5 times the build, 3 times the steps)
were about 15 percent high. The column estimate, the build and the startup
alone, was 8 min low: the 1M column with the precipitation tags builds
longer and takes 14 to 15 GB, twice the TRMM case. The final set is 2.4
node-hours. With the five superseded waves (the roster defect, two unknown
identities, the record-tree manifest, the 30 min tables) the part ran 35
jobs and about 7 node-hours. Their outputs are kept under
`output/p9_wave{1,2,3,4,5}_*/`, their logs and manifests under the job ids.
