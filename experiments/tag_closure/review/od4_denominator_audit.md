# OD4: the denominators of the existing energy records, a first pass

Written on 2026-09-24. The owner set OD4 that day: an energy percentage is
restated against the cumulative gross energy the sources put into the tags
over the same window. This first pass classifies the denominators the E-records
that rev. 2 cites used. It restates no number: that needs each run's gross
source throughput, which no run reports yet.

## The classes

| class | denominator | depends on the offset `c` | records |
|:----- |:----------- |:------------------------- |:------- |
| 1. absolute | none: J/m² of the column, or J on the sphere | yes, in size: E71 found about 90% of D4's remainder is `c` times a change of mass | E39 (gross, J/m², and "98%" of it in the first step), E62 (267 J/m²), E64, E65, E71, E73's closure |
| 2. of the scale | the partitioned total, `∫(ρe_tot + cρ)`, or `∫|ρe_tot|` before the offset | yes: E15 found 2.85× of a 4.06× improvement was the scale | E62's `gross_relative`, E70 and E74 ("of the scale"), E79 ("over the partition's energy"), E80 ("of the energy"), E15 |
| 3. per tag, against a reference | the reference tag's own integral (L1) or peak (L∞) | yes for region tags (E71: `strat` +177%, `tropo` +152% when `c` doubles); source tags 4 to 6% | E66, E73, E75, E76 |
| 4. a ratio of residuals | another residual of the same run | the ratio does not, the residuals do | E39 (98%), E39b (83%), E65 (2.3×), E74's flush rate |

## What OD4 changes

  - **Class 2** is replaced by the window's gross source throughput. Each
    restatement needs that throughput for the run.
  - **Class 3** stays a per-tag measure. Its offset dependence is part of the
    result. A per-tag result states its `c`, as E71 asks. OD4 applies to the
    energy thresholds' aggregate rows, not to per-tag L1.
  - **Classes 1 and 4** carry no percentage. They stay as recorded.

## Where the throughput can come from

  - The source tags' gains: a source tag's cumulative gain is the energy its
    process put in. The tags hold what remains after the loss rule, not the
    gain, so the gain needs the process records (`e_prc_*`) or a new
    accumulator.
  - The process records, where the run kept them: D4's `g1_inc_d4` (five
    records), V2's sphere (`g2_v2_sphere_n2`: radiation, surface flux,
    microphysics, precipitation). The records are signed and net over each
    output interval (E60, G4.14's note), so their positive parts
    underestimate the gross.
  - A per-step gross accumulator of the sources, like WP6 step 3's for the
    corrections, gives the exact throughput. It does not exist yet.

## For the owner

Whether the throughput is taken from the process records for the existing
runs, as a lower bound, or from a new per-step accumulator in new runs.
