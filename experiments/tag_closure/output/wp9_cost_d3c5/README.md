# V-W10: the 8 + 8 point at `d3c5e42f` (design/WP9_COST.md section 11)

Model `main` `d3c5e42f`, record `e149c2382`. Three exclusive jobs on
`hpda2_compute`, 50 warm-up steps, 6 timed blocks of 20 steps with the first
discarded, and an untagged point `0` in every arm. All on D4
(`wp9_energy_d4_edmf`, 1M, EDMF), default mode.

| arm         | job      | node            | state                |
|:------------|:---------|:----------------|:---------------------|
| `both_d3c5` | 14125001 | `hpdar03c04s09` | COMPLETED, 01:25:10  |
| `water_d4`  | 14125002 | `hpdar03c05s09` | COMPLETED, 01:06:58  |
| `energy_d4` | 14125003 | `hpdar03c05s11` | COMPLETED, 01:08:48  |

`table_d3c5.md` is `wp9_cost_table.py --discard 1` over the 9 points.

## The spread rule

Section 11's rule passes at all 9 points. The largest block spread is 2.9%
and the largest ratio spread 3.2%, both at `both_d3c5`'s 8 + 8 point.

## The numbers

Ratio to the same node's untagged step, minimum and median of blocks 2 to 6.
The less favourable of the two is in bold.

| arm         | point     | min   | median    | build ×untagged | B/step    | peak GB |
|:------------|:----------|------:|----------:|----------------:|----------:|--------:|
| `both_d3c5` | 8 + 8     | 4.076 | **4.158** | 1.51            | 3,168,344 | 14.50   |
| `both_d3c5` | ledgers   | **9.098** | 9.067 | 2.14            | 6,038,456 | 13.12   |
| `water_d4`  | 8         | 1.434 | **1.441** | 1.22            | 782,568   | 12.78   |
| `water_d4`  | ledgers   | **3.154** | 3.142 | 1.39            | 2,052,376 | 12.91   |
| `energy_d4` | 8         | 1.522 | **1.526** | 1.23            | 741,432   | 13.19   |
| `energy_d4` | ledgers   | 3.532 | **3.564** | 1.51            | 2,556,184 | 13.62   |

The untagged step is 4.488, 4.518 and 4.528 ms on the three nodes (minimum),
and 560 kB are allocated per step.

## Reading

  - The 8 + 8 point adds 3.16 untagged steps per step. Its two halves alone
    add 0.44 (water) and 0.53 (energy), 0.97 together. So the joint cost is
    about 3.3 times the sum of its halves, and 1.7 times with the ledgers
    (8.10 against 2.15 + 2.56). The allocation per step grows alike: 2.61 MB
    added at 8 + 8 against 0.22 and 0.18 MB. The cause is not isolated here.
    The halves ran on other nodes than the joint point, whose untagged steps
    agree within 0.9%. A node effect on a ratio is not measured directly.
  - Section 10's `both_default` at `b34bbd8b`, on another node, gave 4.189
    and 9.037 at the minimum, 4.167 and 8.991 at the median. The two runs
    agree within 2.7% at the minimum and 0.9% at the median. Section 10's
    `energy_default` at 8 tags gave 1.579 on a node whose untagged step was
    30% shorter (3.18 ms); here 1.526. So the energy ratio at 8 moved by 3.5%
    between those two nodes and commits.
