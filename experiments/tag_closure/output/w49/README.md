# Option C's revision: its 90-day validation (W49)

`design/NEGATIVE_PARENT_WATER.md` section 11.7, 90 days at sites 23 and 26.
FINDINGS W49 reads these files. Each run's `output_0000/` is the source.

| File | What it is |
|:--|:--|
| `<run>/` | per run: the water closure and audit CSVs the model wrote, the config it ran (`<run>.yml`), `provenance.txt`, and `manifest.json`, stamped on the login node at submission. The two untagged twins write no water CSV. `cr_probe_s23/` adds `cr_probe_s23_levels.csv` |
| `cr_validate.txt`, `cr_validate.err` | `analysis/water/cr_validate.py`: rules V1 to V5 |
| `cr_windows_score.txt`, `cr_windows_score.err` | `analysis/water/cr_windows_score.py`: windows W0 to W5 (W3 reports each probe's growth over `R48`) |
| `w49_scores.json` | the two scripts' printed lines, parsed, with their exit codes |
| `w49_supplement.py`, `.txt`, `.json`, `w49_supplement_step.json` | not a pre-registered script. First exceedance of the 2% limit, the day each tag stays above it, V2's largest gross day, and the day-30.75 to 31.5 `led_fix` values with the inventory split (retained divided by fraction) for `cr_s23` and `cr_s23_main`. Run it in this directory |
| `rederive.py`, `rederive.log` | an independent re-derivation of V2, V4 and V4b, written from 11.7's text and the model source only. It comes from `$SCRATCH/claude_work/w49_rederive/`. It gives the "179 of 361" checks above 2e-3 for the control, the 5.2e-5 part of the gross where the tags sit above the target, the 8e-17 agreement of the closure table with the fields, and the twelve-file V4b (the ten daily files and `hus`, `rhoa` 6-hourly, 361 of 361 outputs) |
| `job_exit_check.sh`, `job_exit_check.txt` | the command behind the exit check and its output: `sacct`, each log's driver exit status, and a search of the `.err` logs for "error" or "exception" |
| `SHA256SUMS` | every file above and in the run directories |

| Runs | Jobs | Run tree | Commit |
|:--|:--|:--|:--|
| `cr_s23`, `cr_s23_untagged`, `cr_s26`, `cr_s26_untagged`, `cr_probe_s23` | `14015465`, `14015466`, `14015467`, `14015468`, `14015471` | `../ClimaAtmosResiDyn-crev-run` | `b6d452b5` (model `0eb329b2`, source `c7c77faf`) |
| `cr_s23_main`, `cr_s26_main` | `14015469`, `14015470` | `../ClimaAtmosResiDyn-crev-main-run` | `d2ceaa48` (`main` at `43b01ca1`) |

Every manifest shows a clean worktree: no status lines, no untracked files,
the empty diff. The owner approved model commit `0eb329b2` for these runs on
2026-10-01, through the coordinating session (11.11.11, item 10).

Not copied, because they are large or not read by the scores:

- The daily and 6-hourly NetCDF output the scripts read stays on
  `$SCRATCH/tag_closure/output/<run>/output_0000/`, which is not durable,
  until the archive is synced.
- The energy tag CSVs of each run.
- `cr_probe_s23_steps.csv` (19.5 MB), the probe's per-step ledgers.
  Its SHA-256 is
  `7a3a712920f16c9908b22b97ace66d956d12f2d5f51efb228aaca328ab12b3de`.
