# OD3's copies row at `d3c5e42f` (design/WP9_COST.md section 12.2)

Model `main` `d3c5e42f`, record `84d03ff68`. One exclusive job, `copies88`
(14125922, `hpdar09c05s06`, COMPLETED in 04:54:13): the untagged point `0`,
then 8 water and 8 energy tags in copies mode in one model, on D4. 50 warm-up
steps, 6 timed blocks of 20 steps with the first discarded, a 5 h point limit.
`table_copies88.md` is `wp9_cost_table.py --discard 1`.

## The row

**The build took 15,377 s (4 h 16 min), over OD3's 4 h by 977 s (6.8%).** So
the row fails. The first step compiled for another 996 s. The untagged point
built in 652 s on the same node, so the copies' build is 23.6 times it.

The point then stepped. Section 10's rule passes: block spread 2.9%, ratio
spread 3.3%, and 2.5% for the baseline.

| point             | step min ms | median ms | ratio (less favourable) | B/step    | peak GB |
|:------------------|------------:|----------:|------------------------:|----------:|--------:|
| untagged          | 4.547       | 4.565     |                         | 560,216   | 10.77   |
| 8 + 8, copies     | 22.030      | 22.283    | 4.881 (median)          | 4,633,016 | 21.39   |

For comparison, at `b34bbd8b` on other nodes the copies of one family at 8
tags built in 2446 s (energy, D4) and 485 s (water, TRMM's column), and the default mode's 8 + 8
point at `d3c5e42f` steps at 4.158×. OD3 sets no step ceiling for the copies.
