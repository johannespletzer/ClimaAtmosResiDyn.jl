# V-W10 at `b34bbd8b` (design/WP9_COST.md section 9): the spread rule fails

Model `main` `b34bbd8b` (new physics, after #139, #140 and #141), record
`5a65bbf83`. Check jobs 14103199 to 14103201 on `hpda2_test` all passed
(`output/wp9_check_b34/`, 1 warm-up step, 2 blocks of 3 steps). The rerun has
nine exclusive jobs on `hpda2_compute`, 50 warm-up steps, and an untagged
point `0` in every arm.

| arm                 | job      | node            | state                   |
|:--------------------|:---------|:----------------|:------------------------|
| `water_default`     | 14112139 | `hpdar07c04s03` | COMPLETED, 01:13:54     |
| `water_default_32`  | 14112140 | `hpdar07c04s08` | COMPLETED, 00:17:49     |
| `water_copies`      | 14112141 | `hpdar09c01s05` | COMPLETED, 01:01:27     |
| `water_1m_off`      | 14112142 | `hpdar09c01s06` | COMPLETED, 00:53:45     |
| `water_1m_on`       | 14112143 | `hpdar09c01s07` | COMPLETED, 01:43:46     |
| `energy_default`    | 14112144 | `hpdar09c01s08` | COMPLETED, 02:11:51     |
| `energy_default_32` | 14112145 | `hpdar09c01s09` | COMPLETED, 00:52:38     |
| `energy_copies`     | 14112146 | `hpdar09c01s10` | COMPLETED, 02:59:05     |
| `both_default`      | 14112147 | `hpdar09c01s11` | COMPLETED, 01:24:42     |

`table_b34.md` and `fit_b34.txt` are the tools of section 9, run on this
directory, over all 40 points (31 tagged, 9 baselines). The stop below was
first read on 37 points, while `energy_default` and `energy_copies` were still
running (`061967cad`). Their last points were added on 2026-10-02 for
completeness. The owner then chose a rerun with a discarded block (section
10), so these data count for nothing beyond this record.

## The spread rule

Section 9's rule: each point's block spread, and each tagged point's ratio
spread against its arm's baseline, at most 10%. **It fails at 39 of the 40
points** (36 of 37 at the stop). As section 9 says, nothing was rerun and no finding is
drafted. The work stops for the owner.

What the blocks show:

  - Block 1 is the slowest block at 39 of 40 points. It exceeds the median of
    blocks 2 to 5 by up to 65%, in the baselines too.
  - Over blocks 2 to 5, every point spreads by at most 2.7%. Its ratio to the
    baseline spreads by at most 2.5%.
  - No timed block had over 5% compile time. The driver did not warn at any
    point. In the rerun at `43b01ca1` it warned at most EDMF points.
  - The warm-up was 10 steps at `43b01ca1` and 50 here. In both, the excess
    sits in the first timed block, whatever model time that block covers.
    Two runs at two commits bound this. They do not explain it. The model time
    and the physics changed between the two runs together.
  - The ratio spread fails more often than the block spread. One reason is
    that a baseline's block 1 can carry a larger share of excess than its
    tagged point's block 1 (the combined arm: 65% in the baseline, 3.6% at
    8 + 8).

## Node to node

The untagged TRMM column steps in 2.72 ms on `hpdar07c04s08`
(`water_default_32`) and in 4.22 to 4.23 ms on two other nodes. That is the same
config, commit and settings, at load 1.0. So two nodes can differ by at least
55% for one config. Ratios are read against the same node's baseline, as
section 9 set. A ratio across nodes is not reported.

## Numbers, not qualified

The minimum block is block 2, 3, 4 or 5 at every point. These numbers do not
meet the rule and are not quoted in a finding. Ratio to the same node's
untagged column, minimum block:

  - water under EDMF, default: 1.153, 1.234, 1.421 and 7.141 at 2, 4, 8 and 32
    tags; 2.436 with ledgers at 8;
  - water, copies: 1.176, 1.368, 1.687 at 2, 4, 8;
  - 1M, no rain and snow: 1.222, 1.395, 1.770, 14.28; with them: 1.675,
    4.727, 11.85, 246.3;
  - energy, default: 1.157, 1.267, 1.508 at 2, 4, 8, and 8.080 at 32; 3.565
    with ledgers and 1.530 with records at 8;
  - energy, copies: 1.186, 1.343 at 2, 4;
  - 8 water + 8 energy on D4: 4.163, and 9.053 with ledgers.

*Corrected 2026-10-02 (review of W52 and E88):* the lists above first gave
water's and energy's EDMF numbers under each other's name. They now follow
`table_b34.md`. These data still count for nothing beyond this record.
