# WP4c's retained corrections: the validation (W45)

`design/WP4C_CORRECTIONS.md` section 8. V1 is the gate's default case with
`water_tag_leak_correction: true`. V2, the copies, is added when it finishes.

| File | What it is |
|:--|:--|
| `v1_gate_score.txt` | `analysis/water/wp4c_gate_score.py --startup 6600` on V1 |
| `v1_compare.txt` | `analysis/water/wp4c_corr_compare.py --startup 6600` on V1: criteria 2 to 4 and the reported numbers |
| `wp4c_corr_d4w_default_gate.csv` | the probe's per-step table for V1 |
| `wp4c_corr_d4w_default_gate_reference.yml`, `water_tag_closure.csv`, `water_tag_audit.csv` | the reference's config and tables |
| `v1_log_tail.txt` | the probe's last lines |
| `SHA256SUMS` | every file above |

Job `13973348`, run tree `../ClimaAtmosResiDyn-wp4c-corr-run` at `90f32566`.
The probe does not go through `submit_g3.sh`, so there is no manifest. The run
tree was clean at submission (the design note, section 8). The hourly NetCDF
output stays on `$SCRATCH/tag_closure/output/wp4c_corr/` until the archive is
synced. To score only V1 while V2 runs, the scripts were pointed at a
directory holding links to V1's files.
