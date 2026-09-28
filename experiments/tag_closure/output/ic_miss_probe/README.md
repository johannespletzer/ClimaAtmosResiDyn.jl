# Option C's miss probe at site 23 (W47)

Job `13987196`, run on 2026-09-25 and scored on 2026-09-28.

- `score.txt`: the output of `analysis/water/ic_miss_score.py`. The script
  is unchanged since `cf4f4fa9`, which was committed 19 s before the job
  started.
- `provenance.txt`, `manifest.json`, `job_13987196.out`: the run's
  provenance, its manifest and its Slurm stdout. The Julia log,
  `tag-closure-c-13987196.err` (268 kB), stays in `$SCRATCH/tag_closure/logs/`.
- `water_tag_closure.csv`, `water_tag_audit.csv`: the reference's tables.

Not in git, because it is 15 MB: the per-step table the score reads,
`ic_miss_probe_s23_steps.csv` (13,824 steps). It is in
`$SCRATCH/tag_closure/output/ic_miss_probe_s23/output_0000/`, and synced
to the archive's `scratch_tag_closure/output/` on 2026-09-28. Its SHA-256 is
`f754b3c5d72c449a9df8f18293d54b6f58adf47abdf671863935b3b52c2a7ae6`.
