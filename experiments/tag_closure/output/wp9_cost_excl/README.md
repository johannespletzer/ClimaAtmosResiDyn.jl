# V-W10, the exclusive rerun (design/WP9_COST.md section 7)

Model `43b01ca1` (before the upstream merge, PR #139), record `a7784bdbf`. All
numbers carry that model commit. Nine jobs on `hpda2_compute`, each with
`--exclusive` on its own node. All COMPLETED on 2026-10-01. The 1-minute load
average at each point was 1.00 to 1.16.

| arm                 | job      | node            | elapsed  | Slurm MaxRSS |
|:--------------------|:---------|:----------------|:---------|-------------:|
| `water_default`     | 14005213 | `hpdar09c05s12` | 01:59:46 |      9.27 GiB |
| `water_default_32`  | 14005214 | `hpdar10c01s01` | 00:22:59 |      8.26 GiB |
| `water_copies`      | 14005215 | `hpdar03c02s07` | 01:21:51 |     11.02 GiB |
| `water_1m_off`      | 14005216 | `hpdar03c02s08` | 01:27:37 |      7.36 GiB |
| `water_1m_on`       | 14005217 | `hpdar03c02s09` | 02:16:23 |     24.11 GiB |
| `energy_default`    | 14005218 | `hpdar03c06s08` | 03:08:47 |     13.66 GiB |
| `energy_default_32` | 14005219 | `hpdar03c06s09` | 00:55:42 |     12.32 GiB |
| `energy_copies`     | 14005220 | `hpdar03c06s10` | 02:27:52 |     13.70 GiB |
| `energy_copies_32`  | 14005221 | `hpdar07c02s08` | 04:00:22 |     11.12 GiB |

Energy copies at 32 tags timed out at the 4 h build limit again (exit 124).

Files: one CSV per point and a `status.csv` per arm, copied from
`$SCRATCH/tag_closure/output/wp9_cost_excl/` (each under 1 KB). The point logs
(`<point>.log`) and the job logs
(`$SCRATCH/tag_closure/logs/wp9_cost_excl/`) stay on scratch.

  - `table_excl.md`: `analysis/wp9_cost_table.py output/wp9_cost_excl`.
  - `fit_excl.txt`: `analysis/wp9_cost_fit.py output/wp9_cost_excl`. The
    energy copies' exponent is `nan`, because their added step time at 2 tags
    is negative.
  - `compare_passes.md`: `analysis/wp9_cost_compare.py output/wp9_cost
    output/wp9_cost_excl`. Its columns beyond the registered ones were
    written after the rerun. They are a reading aid, not a registered measure.

## The spread check

The registered measure is the spread of a point's five blocks, max over min.
It passes 10% at 24 of the 29 finished tagged points (first pass: 25 of 29).
Read as the ratio to the baseline block by block, it passes 10% at 21 of 29
(first pass: 17).

The excess sits in the first block (EDMF water, 1M) or the first two blocks
(energy). It shows in the untagged baselines too. Over blocks 3 to 5, every
point spreads by at most 2.4%, and its ratio to the baseline by at most 2.5%.
The median exceeds the minimum by at most 2.4%. The driver recorded up to
0.05 s of compile time in a timed block. It warned of a block over 5% compile
at every EDMF point except energy default at 32 tags, and at no 1M point.
That bounds part of the first block's excess. It does not explain the second
energy block, nor the 1M arms' first block.

Section 7 says a rerun point over 10% is reported with its spread and not
rerun without the owner. So nothing was submitted again.

## Points that ran on another node than their baseline

The copies arms, the `_32` arms and `water_1m_on` have no baseline of their
own, so their ratios are read across two nodes. In the rerun the energy copies
at 2 tags step faster than the untagged baseline (ratio 0.855). So the node
difference in that pair is at least 17% if the copies cost nothing. A ratio
across nodes bounds the cost. It does not isolate it.

Seven points differ between the passes by more than the rerun's own spread
(`beyond` in `compare_passes.md`). The less favourable ratio is the one to
quote (section 7).
