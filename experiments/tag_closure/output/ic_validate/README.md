# Known issue 7, option C: its validation (W42)

`design/NEGATIVE_PARENT_WATER.md` section 8, 90 days at sites 23 and 26. Each
run's `output_0000/`.

| File | What it is |
|:--|:--|
| `<run>/` | per run: the closure and audit CSVs the model wrote, the config it ran (`<run>.yml`), `provenance.txt`, and `manifest.json`, stamped on the login node at submission |
| `score.txt` | `analysis/water/ic_validate.py`: rules V1 to V5 |
| `overclaim_where.txt` | `analysis/water/ic_overclaim_where.py`: where site 23's excess sits, and each ledger's change at its ten largest 6-hourly rises |
| `SHA256SUMS` | every file above |

| Runs | Jobs | Run tree | Commit |
|:--|:--|:--|:--|
| `ic_s23_c`, `ic_s23_untagged`, `ic_s26_c`, `ic_s26_untagged` | `13944928`, `13944929`, `13944930`, `13944931` | `../ClimaAtmosResiDyn-ic-c-run` | `e6bab0fc` |
| `ic_s23_before`, `ic_s26_before` | `13944932`, `13944933` | `../ClimaAtmosResiDyn-ic-before-run` | `078c122c` |

Every manifest shows a clean worktree: no status lines, no untracked files,
the empty diff. The daily and 6-hourly NetCDF output the scripts read stays on
`$SCRATCH/tag_closure/output/<run>/output_0000/`, which is not durable, until
the archive is synced.
