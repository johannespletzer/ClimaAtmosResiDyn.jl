# The long runs (W36, E81)

The second submission of `design/INCREMENT_RULE_LONG_RUNS.md`: jobs `13917157`
to `13917199`, each run's `output_0001/`. The first submission (`output_0000/`,
jobs `13915221` to `13915228`) is void (design section 7).

## What is here

| File | What it is |
|:--|:--|
| `<run>/` | per run: the closure and audit CSVs the model wrote, the config it ran (`<run>.yml`), `provenance.txt`, and `manifest.json`, stamped on the login node at submission |
| `jobs.txt` | the Slurm job of each run and how it ended |
| `metrics.txt`, `metrics.csv` | `analysis/water/lr_rule_metrics.py`: the pre-registered metrics, printed and machine-readable |
| `parity.txt`, `parity.csv` | `analysis/water/lr_parity.py`: each tagged run against its untagged twin, per field |
| `parity_mutation.txt` | the parity check on a deliberately broken copy of the output, which it must fail |
| `SHA256SUMS` | every file above |

## The revisions

| Runs | Run tree | Commit | Tag |
|:--|:--|:--|:--|
| `samesign`, `untagged`, `copies` | `../ClimaAtmosResiDyn-wedmf5r-run` | `b01f926a` | `evidence/w36-samesign` |
| `absm` | `../ClimaAtmosResiDyn-wedmf5-run` | `952d960d` | `evidence/w36-absm` |

Each run tree is the record at `ac94a422` merged with the code branch
(`claude/long-run-samesign` `746cbf0f`, `claude/long-run-absm` `7fd0ffab`).
The compute nodes have no git, so `provenance.txt` says `commit_dirty:
unknown`. The worktree's state at submission is in `manifest.json`: every
run's `head_sha` is the commit above, with `status_lines` empty, no untracked
files, and an empty diff (`diff_sha256` of the empty string,
`e3b0c442…`). The two run trees are still clean at those commits, and both
commits are pushed as the tags above.

## The NetCDF output

The daily NetCDF output (`<name>_1d_inst.nc`) that the parity check, the L1
and the negative water are computed from is not in git (about 17 MB). A
durable, checksummed copy is in the archive:

    ~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/W36_E81/<run>/output_0001/

It holds hard links into `scratch_tag_closure/output/<run>/output_0001/` there.
Each file's size and SHA-256 are in `reference_data/MANIFEST.tsv` (rows
`W36_E81`) and in the archive's `SHA256SUMS`. The runs' Slurm logs are in
`scratch_tag_closure/logs/`. The originals stay on
`$SCRATCH/tag_closure/output/`, which is not durable.

To recompute from the archive:

    python3 analysis/water/lr_parity.py ~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/W36_E81
    python3 analysis/water/lr_rule_metrics.py ~/git/Clima/ClimaAtmosResiDyn-archive/reference_data/W36_E81
