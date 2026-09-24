# W29's evidence: the tags' sedimentation cross blocks on W23's explicit column

Pinned for the owner's review of #105 (finding 4), 2026-09-24. The annotated
tag `evidence/wp5b-w29` points at the record commit that adds this file.
`SHA256SUMS` hashes every file listed here.

## What ran

Eight runs of `analysis/water/wp5b_probe.jl` (its header gives the column,
DYCOMS RF02, 1M, prognostic EDMF, microphysics explicit, ARS222, `dt` 120 s,
one Newton iteration, one hour; the configuration is the `Dict` in the
script). Each is one Slurm job of `probe_job.sh`, with the environment:

    sbatch -J wp5b-$LABEL-$MODE-$TRANSPORT -A hpda-c -p hpda2_compute -c 2 --mem=48G \
      --export=ALL,MODE=$MODE,TRANSPORT=$TRANSPORT,NEWTON=1,LABEL=$LABEL probe_job.sh

for `LABEL` in `off`, `on`, `MODE` in `default`, `copies`, and `TRANSPORT` in
`tracer`, `increment`. Jobs `13892249` to `13892256`, all started
2026-09-24 09:31:53 (CEST) on `hpda2_compute`, Julia 1.11.9.

## Code

| label | worktree                              | commit     | what                                           |
|:----- |:------------------------------------- |:---------- |:---------------------------------------------- |
| off   | `ClimaAtmosResiDyn-wedmf5b-off`        | `f8da0913` | #102's head `e29384ee` with the refusal lifted |
| on    | `ClimaAtmosResiDyn-wedmf5b`            | `c2bf8a62` | the cross blocks                               |

Both were committed at 09:30:52, a minute before the jobs started. `src/` is
the same at `c2bf8a62` and at `0aad20ee`, the head the owner reviewed
(`git diff c2bf8a62 0aad20ee -- src` is empty); the commits between touch
tests and docs only. The probe printed `commit=?`, because `git` does not run
in the jobs; the table above replaces it.

## Environment

`env/on/` and `env/off/` hold each run's `Project.toml`,
`Manifest-v1.11.toml` and `LocalPreferences.toml`. The manifests differ only
in the `ClimaAtmos` path (line 347). Depot:
`/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu`.

## Results

  - `logs/*.out`: each job's `RESULT` lines (closure, smallest tag, repair,
    audit);
  - `wp5b_<label>_<mode>_<transport>_n1.csv`: the final column of the parent
    and the tags, each value as `repr` wrote it;
  - `results.txt`, `compare.txt`: the output of
    `python3 analysis/water/wp5b_compare.py output/wp5b_probe <logs>`.

FINDINGS W29 reads these. It validates the closure and the lag the blocks
remove on this one column, not the provenance of each tag (the owner's review
of #105, finding 3).
