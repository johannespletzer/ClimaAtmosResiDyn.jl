# Known issue 7's probe, read

Read on 2026-09-25 as `design/NEGATIVE_PARENT_WATER.md` section 5
pre-registers it. It bounds; it does not isolate a cause. The choice among B,
C and D is the owner's.

  - **Run:** `configs/lr_s23_probe_ledgers.yml`, job `13932689`
    (`hpda2_compute`, 2026-09-24 23:32 to 2026-09-25 00:31), from
    `../ClimaAtmosResiDyn-issue7-probe-run` at `09793dcd` (its provenance).
    It reached day 20. At day 20 the partition's sum exceeds the parent's
    water by 31% (`water_tag_closure.csv`, relative −0.309).
  - **Script:** `analysis/water/issue7_probe_read.py`. **Files:**
    `validity.csv`, `rates.csv` (per 6-hour interval, ledger and cell set),
    `readings.csv` (baseline, days 10 to 20, ratio, growth, first interval).

## Validity

`rhoa`, `ta` and `hus` at the daily outputs of days 1 to 20 are bit for bit
those of `lr_s23_untagged` (`output_0001`). The probe is valid.

## The readings

The parent first goes negative in the interval starting at day 9.0, in one
cell; at most four cells are negative on any day to day 20. So N is empty on
days 5 to 8, and every ratio in N is undefined (its baseline is zero). The
pre-registration does not say what "fastest" means then. Below, in N, it is
read by the absolute rate over days 10 to 20. That reading is added, not
pre-registered.

| ledger | N: first | N: rate, days 10–20 | P: first | P: ratio | next to N: first |
|:------ |:-------- |:------------------- |:-------- |:-------- |:---------------- |
| the follower's moved part | 9.0 | 36.6 | 11.5 | 38 | 9.0 |
| `led_inc`, per tag | 9.0 | 0.8 to 28.1 | 11.5 | 25 to 116 | 9.0 |
| the follower's left part | 9.0 | 6.3e-10 | 11.5 | 35 | 9.0 |
| the repair's net | 9.0 | 0.35 | (negative) | — | 9.5 |
| `led_fix`, `pbl` and `free` | 9.0 | 0.21, 0.24 | 9.5 | ∞ (zero baseline) | 9.5 |
| the repair | 11.5 | 0.052 | 11.5 | ∞ (zero baseline) | 15.75 |
| the emptying, the rescale | never | 0 | never | — | never |
| the overclaim (a stock, kg/m²) | 9.0 | 0.74 | 11.5 | 1.8e11 | 11.5 |

Rates are kg m⁻² day⁻¹ of each ledger's per-step gross. "First" is the start
day of the first 6-hour interval at which the rate passes 10 times the
baseline (in N, at which it is non-zero). "Next to N" is the supplement the
design's option C asks about ("in or next to N"); the pre-registration does
not define it. Every row in `readings.csv`.

  - **Grows.** In N every ledger that acts grows (from nothing). In P the
    follower's ledgers grow 25 to 116 times over their baseline, and the
    corrections from nothing. The emptying and the rescale never act.
  - **First.** In the interval where N first appears (day 9.0), the
    follower's moved part and `led_inc` are the largest ledgers in N, about
    120 times the repair's net (5.3e-4 against 4.5e-6 kg m⁻² day⁻¹). Next to
    N they are the only ledgers that act in that interval; the corrections
    follow half a day later. `led_inc` is the moved part split by tag, so the
    two are one ledger family, not two contenders.
  - **Fastest.** In N, by the absolute rate, the moved part (36.6) is about
    100 times the repair's net and 700 times the repair. In P, among ledgers
    with a non-zero baseline, the largest ratios are the follower's
    (`led_inc` 116, 78, 51; moved 38). The corrections' ratios in P are
    infinite, since they do not act on days 5 to 8.
  - **Where.** The overclaim grows in N and in P. Over days 10 to 20 its
    mean is 0.74 kg/m² in N, 0.49 next to N, and 1.25 farther away: 70% of
    it lies outside the negative cells.

## The mapping, as section 5's table reads

  - **B** (the emptying, the rescale or the repair first and fastest, in N):
    **not met**. The emptying and the rescale never act. The repair starts
    at day 11.5, and in N it is 700 times smaller than the follower's moved
    part.
  - **C** (the follower's moved or left part, or `led_inc`, first and
    fastest, in or next to N): **met**. They are first in N (tied in time,
    with a lead of about 120 times in size) and alone first next to N. They
    are fastest in N by rate and in P by ratio among ledgers with a
    baseline.
  - **D** (the overclaim grows in P too, and no single ledger first by a
    clear margin): **half met**. The overclaim grows in P, most of it away
    from the negative cells. But the follower's family leads the corrections
    by about 120 times at the first interval, which is a clear margin.
  - **Not bounded** (no ledger grows while the overclaim does): **not
    met**.

So the probe points to **C**. D's first condition holds as well: most of the
overclaim lies in cells whose parent is not negative. Whether C alone reaches
that part, which the tags may carry there from N, the probe does not show.
