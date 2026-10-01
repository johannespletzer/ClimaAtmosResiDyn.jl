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
