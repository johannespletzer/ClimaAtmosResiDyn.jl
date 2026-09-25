# Which per-tag ledger ratio stays readable through a zero crossing (E85)

`design/LEDGER_RATIO_ZERO_CROSSING.md`, four runs of a day. Each run's
`output_0000/`.

| File | What it is |
|:--|:--|
| `<run>/` | per run: the energy closure and audit CSVs, the config it ran, `provenance.txt`, `manifest.json` |
| `score.txt`, `score.csv` | `analysis/increment/ledger_ratio_score.py`: the preconditions and rules (a) to (c) per ratio |
| `SHA256SUMS` | every file above |

Jobs `13948351` to `13948354`, run tree `../ClimaAtmosResiDyn-ledgerratio-run`
at `f4c21ad0` (the record with #109 at `6695a5c7`), every manifest clean. The
hourly NetCDF output (`ta`, `rhoa`, `hus` for the parity precondition) stays
on `$SCRATCH/tag_closure/output/<run>/output_0000/` until the archive is
synced.
