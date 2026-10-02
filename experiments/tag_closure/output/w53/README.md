# V5's `led_fix` at site 23 (W53)

Where and when the repair's corrections of `pbl` and `free` rise in W49's
revision run at site 23, against `main`. FINDINGS W53 reads these files.

| File | What it is |
|:--|:--|
| `ledfix_s23_localise.txt` | stage A, `analysis/water/ledfix_s23_localise.py`, written after W49's runs were read and not pre-registered: the mechanism, the timing, the levels, the direction and what co-varies, `cr_s23` against `cr_s23_main` |
| `ledfix_s23_intervals.csv` | the same script, one row per 6-hour interval: each tag's `led_fix` increment in both runs and the extra, the net repair, the column growth of `q_tag_exp_negative` and of the follower's negative part, the signed extras of the repair and the follower for `free`, and the parent's negative levels |
| `ledfix_s23_levels.csv` | the same script, one row per level, summed over 90 days |

Run it in this directory:

    python3 ../../analysis/water/ledfix_s23_localise.py $SCRATCH/tag_closure/output .

It reads each run's `output_0000/` on `$SCRATCH/tag_closure/output/`, which
is not durable until the archive is synced: `water_tag_audit.csv`, the
6-hourly `rhoa`, `hus`, `q_tag_negative`, `q_tag_led_fix_<tag>`,
`q_tag_led_fixgross_<tag>`, `q_tag_led_inc_<tag>`, `q_tag_exp_negative`,
`q_tag_inc_negative_gross`, and the daily `pr`. Column integrals use `rhoa`
times a layer depth from the level midpoints. They reproduce the audit's
`led_fix_<tag>_retained` to 0.2% (the script prints the check).

## Stage B, the probe (design 11.12)

| File | What it is |
|:--|:--|
| `ledfix_score.txt`, `ledfix_score.err` | `analysis/water/ledfix_score.py`, the pre-registered scores: B1 to B4, P1, P2. Run it in this directory with `$SCRATCH/tag_closure/output` as its argument |
| `<run>/` | for `lf_switch_check`, `lf_rev_s23` and `lf_switch_s23`: the config the model ran, `manifest.json`, `provenance.txt`, and the water closure and audit CSVs. `lf_switch_check/` adds its trace |
| `job_exit_check.txt` | `sacct` for the three jobs, and the count of lines with "error" or "exception" in each `.err` log |
| `SHA256SUMS` | every file in this directory |

| Runs | Jobs | Run tree | Commit |
|:--|:--|:--|:--|
| `lf_switch_check` (config in `$SCRATCH/claude_work/ledfix/`), `lf_rev_s23`, `lf_switch_s23` | `14063995`, `14074174`, `14074175` | `../ClimaAtmosResiDyn-ledfix-run` | `e524dbac` (W49's `b6d452b5`, model `0eb329b2`, with the driver and two configs) |

Not copied: the NetCDF output and the two arms' traces, which stay on
`$SCRATCH/tag_closure/output/<run>/output_0000/` until the archive is synced.

  - `lf_rev_s23_trace.csv` (17.8 MB), SHA-256
    `b0cbcab69ecb22e38414b20df43d3996b8cdc97728c1d9e49815a1541141d93f`;
  - `lf_switch_s23_trace.csv` (17.2 MB), SHA-256
    `fe49640ed330fdf74f8b165ded00ef04e1143568fda6ff3ab4c840a2651abd01`.
