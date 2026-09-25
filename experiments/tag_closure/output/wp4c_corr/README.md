# WP4c's retained corrections: the validation (W45)

`design/WP4C_CORRECTIONS.md` section 8. V1 is the gate's default case, and V2
its copies case, each with `water_tag_leak_correction: true`.

| File | What it is |
|:--|:--|
| `gate_score.txt` | `analysis/water/wp4c_gate_score.py --startup 6600` on both cases |
| `compare.txt` | `analysis/water/wp4c_corr_compare.py --startup 6600` on both: criteria 2 to 4 and the reported numbers. It exits 1: V2's criterion 4 |
| `v1_gate_score.txt`, `v1_compare.txt` | the same on V1 alone, scored while V2 ran |
| `wp4c_corr_d4w_{default,copies}_gate.csv` | the probe's per-step tables |
| `v1/`, `v2/` | each reference's config and closure and audit tables |
| `v1_log_tail.txt`, `v2_log_tail.txt` | each probe's last lines |
| `SHA256SUMS` | every file above |

Jobs `13973348` (V1) and `13973349` (V2), run tree
`../ClimaAtmosResiDyn-wp4c-corr-run` at `90f32566`. The probe does not go
through `submit_g3.sh`, so there is no manifest. The run tree was clean at
submission (the design note, section 8). The hourly NetCDF output stays on
`$SCRATCH/tag_closure/output/wp4c_corr/` until the archive is synced.
