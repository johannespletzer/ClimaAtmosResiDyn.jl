# V-W10 at `b34bbd8b`, first block discarded (design/WP9_COST.md section 10): the rule fails in one arm

Model `main` `b34bbd8b`, record `ed9db0b10`. Ten exclusive jobs on
`hpda2_compute`, 50 warm-up steps, 6 timed blocks of 20 steps with the first
discarded, and an untagged point `0` in every arm.

| arm                 | job      | node            | state at writing                      |
|:--------------------|:---------|:----------------|:--------------------------------------|
| `water_default`     | 14121227 | `hpdar03c04s09` | COMPLETED, 01:15:01                   |
| `water_default_32`  | 14121228 | `hpdar03c06s06` | COMPLETED, 00:24:24                   |
| `water_copies`      | 14121229 | `hpdar07c05s08` | COMPLETED, 00:44:15                   |
| `water_1m_off`      | 14121230 | `hpdar10c04s08` | COMPLETED, 00:53:28                   |
| `water_1m_on`       | 14121231 | `hpdar12c01s04` | COMPLETED, 01:44:03                   |
| `energy_default`    | 14121232 | `hpdar12c04s06` | COMPLETED, 01:34:50                   |
| `energy_default_32` | 14121233 | `hpdar12c05s01` | COMPLETED, 00:52:47                   |
| `energy_copies`     | 14121234 | `hpdar12c05s03` | COMPLETED                             |
| `both_default`      | 14121235 | `hpdar07c04s03` | COMPLETED, 01:23:29                   |
| `energy_copies_32`  | 14121236 | `hpdar07c04s04` | COMPLETED, 08:19:00; point 32 timed out at 8 h |

`table_b34d_partial.md` and `fit_b34d_partial.txt` are
`wp9_cost_table.py --discard 1` and `wp9_cost_fit.py --discard 1` over the
39 points that had finished (29 tagged, 10 baselines).

## The spread rule

Section 10's rule is applied on blocks 2 to 6. **It fails at 5 of the 39
points, all in one arm, `water_copies`.** Its untagged point has one slow
block, block 4, at 4.287 ms against 2.906 to 2.928 ms for the other four
measured blocks: a block spread of 47.5%. The arm's four tagged points spread
by at most 1.8% themselves. Against that baseline, their ratio spreads are 47%
to 48%. As section 10 says, nothing is rerun, no finding is drafted, and the
work stops for the owner.

The other 34 points pass. Over them the largest block spread is 3.9% and the
largest ratio spread 4.4%. (Section 9's 40 points failed at 39, with block 1
the slowest at 39.)

## Node to node, again

The untagged TRMM column steps in 2.906 ms on `hpdar07c05s08` and in 4.204 to
4.227 ms on two other nodes. The untagged D4 column steps in 3.176 ms on
`hpdar12c04s06` and in 4.471 to 4.505 ms on four others. So nodes differ by up
to 45% for one config at load 1.0. The ratios here are read on one node each.
Whether a tag's cost scales with the node's speed as the baseline does is not
measured: no point was run on two nodes.

## Numbers, not qualified

These numbers do not meet the rule as a whole and are not quoted in a
finding. Ratio to the same node's untagged column, minimum of blocks 2 to 6:

  - water under EDMF, default: 1.154, 1.230, 1.426, 7.381 at 2, 4, 8, 32
    tags; 2.423 with ledgers at 8;
  - water, copies (the failing arm): 1.184, 1.381, 1.690 at 2, 4, 8;
  - 1M, no rain and snow: 1.208, 1.381, 1.727, 14.14; with them: 1.683,
    4.717, 11.98, 245.3;
  - energy, default: 1.157, 1.266, 1.575 at 2, 4, 8, and 8.091 at 32; 3.513
    with ledgers and 1.575 with records at 8;
  - energy, copies: 1.189, 1.349 at 2, 4;
  - 8 water + 8 energy on D4: 4.189, and 9.037 with ledgers.

## Final, 2026-10-02 (after `water_copies_r2` and `energy_copies_32`)

`water_copies_r2` (14122295, `hpdar03c05s09`, record `59b41a62f`) reran the
failing arm alone, as section 10's note says. `energy_copies_32` ended at
8 h 19 min: its point `0` finished, and point `32` timed out at the 8 h build
limit (exit 124). Its log shows the cache built in 168 s. The build had not
finished when it was stopped.

`table_b34d.md` and `fit_b34d.txt` are `wp9_cost_table.py --discard 1 --skip
water_copies` and `wp9_cost_fit.py --discard 1 --skip water_copies` over all
41 finished points. **Section 10's rule passes at every one of them.** The
largest block spread is 3.9% and the largest ratio spread 4.4%. The partial
files of the stop are kept beside them.

The fit script fits the added step time in ms. Where one count series ran on
two nodes (energy default: 2 to 8 on `hpdar12c04s06`, 32 on `hpdar12c05s01`,
whose untagged steps differ by 41%), that mixes the nodes. W52 and E88 quote
exponents fitted on `ratio - 1` instead: water 1.37 (1.95 from 8 to 32),
energy 1.40 (1.81), 1M without rain and snow 1.51 (2.09), with them 2.08
(2.24).
