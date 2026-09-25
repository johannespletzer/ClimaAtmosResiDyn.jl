# G4.6, the D4 process budget (E87)

`design/D4_PROCESS_BUDGET.md`. The build check came first
(`g46_build_check.log`, `g46_build_check_summary.txt`); then the three runs.

| File | What it is |
|:--|:--|
| `process_budget.txt` | `analysis/increment/process_budget.py`: parity, identity II per layer and for the column, identity I, C4, and the verdicts A2 to A5 |
| `<run>/` | per run: the config, `provenance.txt`, `manifest.json`, and the energy closure and audit tables |
| `SHA256SUMS` | every file above |

Jobs `13975411`, `13975417`, `13975419`, run tree `../ClimaAtmosResiDyn-g46-run`
at `0164c2fd`, every manifest clean. The NetCDF output stays on
`$SCRATCH/tag_closure/output/g46_d4_*/output_0000/` until the archive is
synced.
