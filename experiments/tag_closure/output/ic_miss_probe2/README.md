# Option C's miss at site 23, the extended probe on `main` (W48)

Job `13996867`, run on 2026-09-28/29 from the run tree at `e09e0986` (`main`'s
code at `cfc2152c`, with the record), and scored on 2026-09-29.
`design/NEGATIVE_PARENT_WATER.md` section 9.7 registers it, and 9.7.7 amended
it before the run.

- `score.txt`: the output of `analysis/water/ic_miss_score2.py`. The script
  is as amended at `6eae646f`, before the job started.
- `ic_miss_probe2_s23_levels.csv`: the per-level sums per 6-hour interval
  (section 9.7.2, item 4).
- `provenance.txt`, `manifest.json`, `job_13996867.out`: the run's
  provenance, its manifest (clean, head `e09e0986`) and its Slurm stdout. The
  Julia log, `tag-closure-c-13996867.err` (384 kB), stays in
  `$SCRATCH/tag_closure/logs/`.
- `water_tag_closure.csv`, `water_tag_audit.csv`: the reference's tables.

Not in git, because it is 21 MB: the per-step table the score reads,
`ic_miss_probe2_s23_steps.csv` (13,824 steps). It is in
`$SCRATCH/tag_closure/output/ic_miss_probe2_s23/output_0000/`, and synced to
the archive's `scratch_tag_closure/output/` on 2026-09-29. Its SHA-256 is
`85298c390891d999d0a898608ca3d84526d212855fd8d39567de1273bb9fba6f`.

The check job `13996777` (section 9.7.6) wrote
`$SCRATCH/tag_closure/output/ic_miss_probe2_check/`: six steps and both
CSVs.
