# The follower's outflow beyond `free`'s content at site 23 (W63)

W53's follow-up, design `NEGATIVE_PARENT_WATER.md` section 11.13,
pre-registered before any job (commit `7a169230`). FINDINGS W63 reads these
files.

| File | What it is |
|:--|:--|
| `ledfix_overdraw_score.txt`, `ledfix_overdraw_score.err` | `analysis/water/ledfix_overdraw_score.py`, the pre-registered checks and score: C1, C2, V0 to V2, S, and the reported numbers |
| `ledfix_overdraw_givefirst.txt` | `analysis/water/ledfix_overdraw_givefirst.py`, not pre-registered: S with the negative part's give taken first |
| `<run>/` | for `lf_od_rev_check`, `lf_od_rev_s23` and `lf_od_switch_s23`: the config the model ran, `manifest.json`, `provenance.txt`, and the water closure and audit CSVs. `lf_od_rev_check/` adds its two traces |
| `job_exit_check.txt` | `sacct` for the three jobs, and the count of lines with "error" or "exception" in each `.err` log |
| `SHA256SUMS` | every file in this directory |

Run the scripts in this directory with `$SCRATCH/tag_closure/output` as
their argument (the check: add `check`).

| Runs | Jobs | Run tree | Commit |
|:--|:--|:--|:--|
| `lf_od_rev_check` (config in `$SCRATCH/claude_work/ledfix/`), `lf_od_rev_s23`, `lf_od_switch_s23` | `14126834`, `14126889`, `14126890` | `../ClimaAtmosResiDyn-ledfix-od-run` | `bda3f660` (W53's `e524dbac`, model `0eb329b2`, with the driver and two configs) |

Not copied: the NetCDF output and the two arms' traces, which stay on
`$SCRATCH/tag_closure/output/<run>/output_0000/` until the archive is synced.

  - `lf_od_rev_s23_trace.csv` (51 MB), SHA-256 `5db3c60424bb5638e4022f7ce1c2ac3de64e927c574c72c7e3ff5fc4dfd3a9db`
  - `lf_od_rev_s23_stages.csv` (171 MB), SHA-256 `2a68bb35db59c18a535261478b3c27e793748b4ea476ecfd17eb62ff7e4dd960`
  - `lf_od_switch_s23_trace.csv` (50 MB), SHA-256 `389bcc14bc90a35419ab9df98c5201790a7d6300f893da67ce8fbecd439cea73`
  - `lf_od_switch_s23_stages.csv` (171 MB), SHA-256 `b6eddc86116a1933bfbc774b362bb4b6eb4d8d8d74280fa9ef9399537168317b`
