# OD4: the energy records restated on the gross source throughput

Written on 2026-09-25 for G4.3. It finishes the first pass,
[od4_denominator_audit.md](od4_denominator_audit.md), which sorted the
denominators into four classes and restated nothing. The numbers here come
from the runs' own output on scratch. Nothing was rerun.

  - Script: `analysis/increment/od4_restate.py`.
  - Its output: `output/od4_restatement/od4_restatement.txt`.
  - FINDINGS.md is not changed here. The entries this proposes are at the end.

## 1. The scale, and a correction to its interim label

OD4's scale is the gross energy the sources put into the tags over the window
(the register, OD4). Two measures exist:

  - **Θx, exact.** The audit's `source_throughput`, from each partition tag's
    source ledger, per step (#115; `design/GROSS_ACCUMULATORS.md` section 11).
  - **Θi, interim.** From the process records: over the output intervals and
    the source processes, `Σ ∫ρ|Δe_prc|`. `precipitation` is left out, since
    the energy source tags take sedimentation as transport.

The register labels every percentage on Θi an *upper bound*. That holds only
if Θi ≤ Θx. It does not hold in general, and not on D4:

  - Θi keeps the processes apart but is net over each output interval.
  - Θx is per step but nets the processes within a cell and a step: a cell
    heated at the surface and cooled by radiation in one step counts once.
  - Θi has no `c·Δρ`, since an energy record holds `Δρe_tot` only.

So neither bounds the other. One run has both, E83's rerun on #115
(`g411x_d4_default`, job `13944940`, not yet in FINDINGS):

| D4, window | Θi, J/m² | Θx, J/m² | Θx/Θi |
|:---------- | --------:| --------:| -----:|
| 0 to 1 h   | 8.97e5   | 8.84e5   | 0.986 |
| 0 to 6 h   | 5.48e6   | 5.15e6   | 0.941 |
| 0 to 24 h  | 2.21e7   | 2.09e7   | 0.945 |
| 1 to 24 h (OD2's window) | 2.12e7 | 2.00e7 | 0.944 |

**So on D4 a percentage on Θi is 6% smaller than on Θx, not larger.** Below,
every percentage on Θi is labelled *interim*. The least favourable reading
multiplies it by 1.06 on D4. Elsewhere the direction is not known. This is an
owner question (section 5).

## 2. The restatement table

Classes as in the first pass: 1 absolute, 2 of the partitioned total, 3 per tag
against a reference, 4 a ratio of residuals. The window is 0 to the record's
time. OD3's energy closure row is "gross at most 0.2% of the window's gross
source throughput". `E/Θi` converts a class-2 number: multiply by it.

| record | number as recorded | class | run | on OD4's scale (Θi, interim) | OD3 closure row (≤ 2e-3) | verdict change |
|:------ |:------------------ |:----- |:--- |:---------------------------- |:------------------------ |:-------------- |
| E22 | `rad` holds 7.1e-8 of the cell's total where radiation cools | pointwise share | C5 | not a closure number; offset-invariant in substance | — | none. The claim stands |
| E26 | form B 3.3e-7 J/m² of 1.43 MJ/m² | 1 | `c6_column_repair` | 1.3e-14 of Θi (2.59e7 J/m²) | — (form B is a records identity) | none |
| E39 | 2,695 J/m² at 1 h, one iteration; 20.5 converged; "98%" | 1, 4 | `c9_column_enthalpy` | 3.0e-3 and 2.3e-5 of Θi (8.89e5, one hourly interval) | fail, pass | **new: the one-iteration first hour fails**, by 1.5×. It is startup, which OD2 does not score |
| E39b | 2.54e20 J at 1 h; "83%" | 1, 4 | `c9_sphere_enthalpy` | cannot be restated: the run wrote no `rhoa` | — | none; no percentage to restate |
| E42 | gross 2.37e6 J/m² at 1 h, 3.7e-3 of the partition; signed 4.5e-10 | 2 | `d1_column_1m_ice` | gross **24.9 times** Θi (9.51e4, minute records); signed 3.0e-6 | **fail** by 1.2e4 | **changes.** "The column stays closed" holds for the signed residual only. The zero-sum gross is 25 times what the sources gave in the hour |
| E42b | gross 2.350e6 J/m² at 1 h | 1 | `d1_column_1m_ice_no_vdiff` | 26.3 times Θi | **fail** | as E42 |
| E62 | 267 J/m², 2.4e-6 of the partition | 2 | `inc_d4_enthalpy_increment` | 1.2e-5 of Θi (2.21e7) | pass, margin 165× | none |
| E62, base | `enthalpy` audit 6.32e5 J/m², 5.5e-3 | 2 | `c1c_base_d4_enthalpy` | **2.9e-2** of Θi | **fail** by 14× | **new: the `enthalpy` audit fails closure on D4** |
| E64 | 266.942 J/m²; left 313 (gross); moved 3.3e7 (gross) | 1 | `g1_inc_d4` | 1.2e-5; 1.4e-5; **1.49** of Θi | pass | none. The correction moves 1.5 times the day's throughput |
| E64, 10 iterations | 0.080 J/m² | 1 | `g1_inc_newton_d4` | 3.6e-9 | pass | none |
| E65 | Float32 607 J/m²; base 7.53e5; "2.3×" | 1, 4 | `g1_inc_d4_float32`, `g1_base_d4_float32` | 2.7e-5; base **3.4e-2** | pass; base **fail** | base as E62's |
| E66 | per tag L1 (class 3); the reference's own 5.99e5 J/m² | 3, 1 | `g1_ref_newton10_d4` | reference **2.7e-2** of Θi | reference **fail** | the reference fails closure. Its L1 rows were already "the convention" |
| E71 | remainder 509 against 267 J/m² at 2c | 1 | `g1_inc_d4_2c` | not listed by rev. 2; 2.3e-5 of Θi at 2c | pass | none |
| E73 | default 267.07, copies 365 J/m²; per tag L1 | 1, 3 | `v3_upd_default`, `v3_upd_copies` | 1.2e-5, 1.7e-5 | pass | none. L1 stays per tag, at c = 110,495 J/kg |
| E74 | gross 2.01e-4 of the scale at 10 d; 2.77e-5 at 1 d | 2 | `g2_v2_sphere_n2` | **7.9e-4** at 10 d (Θi 1.12e23 J); **1.6e-3** at 1 d | pass, margin 2.5× at 10 d, **1.24× at 1 d** | none, but the margin is small. At 1 d on Θx, if D4's ratio held, 1.7e-3 |
| E75 | 2.003e-4 of the scale at 10 d; per tag L1 | 2, 3 | `g2_v2_sphere_mix` | 7.8e-4 | pass | none |
| E76 | per tag L1 on the ladder | 3 | `v3_upd_*` | stays per tag | — | none for L1; see section 3 for the rows it can now score |
| E79 | gross 2.3e-6 (\|m\|) and 9.2e-6 (same sign) of the partition; moved 0.289 | 2 | `g415_inc_d4_before`, `_after` | 1.2e-5 and **4.7e-5**; moved 1.49 | pass both | none. OD7's comparison reads the same on either scale (a fourfold gross) |
| E80 | 2.1e-4 of the energy an hour (explicit, one iteration); 1.5e-6 implicit | 2 | `g415_n5_*` | **cannot be restated**: no records, no surface fluxes written. E82's twin below is the estimate | — | see E82 |
| E81 | gross ≤ 7.6e-12 of `∫(ρe_tot + cρ)` at 90 d | 2 | `lr_s2*_*` | **cannot be restated**: the long runs wrote no records. A bound decides it: the gross would need Θ below 3.8e-9 of the partition over 74 days to reach 2e-3 | pass | none |
| E82, explicit hour | blocks off 1.8e-4, on 1.4e-15 of the partition | 2 | `g416_expl_n1_off`, `_on` | no records. Partial scale, the surface enthalpy flux alone (3.92e5 J/m²): off **5.1e-2**, on 3.9e-13. Against D4's first-hour Θx (8.84e5) off **2.2e-2** | off **fail** by 11 to 25×; on pass | **changes:** without the blocks the explicit hour fails closure on OD4's scale. The blocks pass |
| E82, implicit hour | off 8.1e-7, on 1.2e-15 | 2 | `g416_impl_n1_*` | off 2.3e-4 of the surface flux alone | pass | none |
| E82, D4 day | off 2.3e-6, on 8.9e-15 | 2 | `g416_d4_off`, `_on` | 1.2e-5, 4.6e-14 | pass | none |
| E83 | own residual 1.1e-5, 1.2e-5, 2.7e-6; repair 2.9%, 2.6%, 1.9% a day, all on Θi | interim | `g411_d4_*` | on Θx (default rerun only): own 8.7e-6 against 8.2e-6 on Θi, repair 7.3% against 6.9% a day. The copies' reruns were still running | — | none: the copies stay not eligible. Their percentages on Θx are about 1.06 times larger, not smaller |

## 3. Rows the records never scored, now assessable from the same output

Rev. 2's contract adds intervention and convergence rows. The audits of these
runs already hold the repair's ledger, `repair_moved`: over the cells and tags
of `|ledger|`, net over time in each cell, so a lower bound of the repair's
gross. Per day over Θi, window 1 h to the end:

| run | repair a day, of Θi |
|:--- | -------------------:|
| before the exchange (E68, `04d63916`) | 0 (0.83 J/m² in a day) |
| the exchange, E73's run (`e010f780`) | 1.8% |
| the exchange at `846ef55d` (E73's rerun) | 1.7% |
| E76, 120 s, at `dcf7d086` (#95's fixes) | **6.9%** (7.3% of Θx, `g411x_d4_default`) |
| E76, 60 s | 6.3% |
| E76, 30 s | 4.2% |
| E76, two Newton iterations | 7.7% |
| E76, first-order upwind | 3.5% |
| E73's copies, 120 s | 2.6% |
| E76's copies, 60 s and 30 s | 1.6%, 0.70% |
| E74, the sphere, 10 d | 2.6% |
| E75, the sphere with the mixing | 2.5% |

  - **Intervention, aggregate.** OD3's row names water only: the partition
    repair's retained gross at most 0.5% of `∫ρq_tot` a day. No energy value
    is approved. So for energy the row is *not assessable*. Read by analogy in
    OD4 units, the default exchange on D4 would fail by 14×, and the sphere
    by 5×. Owner question.
  - **Intervention, per tag.** Only `g411x_d4_default` keeps each tag's own
    ledger. Its `led_fix` inventory fractions over the day: `sub` **3.1%**,
    `new_strat` **2.2%**, `strat` 1.4%, `tropo` 1.2%, the rest below 0.2%.
    OD3's per-tag row (at most 2%) does not name a family. Read for energy,
    `sub` and `new_strat` fail.
  - **Refinement.** OD3: the repair's throughput per unit time at the finer
    rung at most 0.75 times the coarser rung's, and above 0.9 a structural
    cause. The default's repair a day: 60 s over 120 s **0.91** (fails, and
    flags a structural cause); 30 s over 60 s 0.67 (passes).
  - **What the repair is.** The repair moved 0.83 J/m² a day before the
    exchange and 1.4e6 J/m² after #95's fixes. Between those runs the exchange
    and other code changed. So this bounds when the repair grew; it does not
    isolate why. In `g411x_d4_default` nearly all of it is a trade between
    `strat` and `tropo` (6.9e5 J/m² each way).

## 4. What cannot be restated without a rerun

  - **E80**: the explicit and implicit hours wrote neither records nor surface
    fluxes. E82's twins give the estimate above.
  - **E81**: the long runs wrote no records. The verdict cannot change (the
    bound above).
  - **E39b**: the sphere wrote no `rhoa`. Its numbers are class 1 and 4.
  - **Every exact value.** Only runs on #115 with the per-tag ledgers on have
    Θx. Today that is `g411x_*`, and only the default had finished when this
    was written. The contract needs an exact value only where a verdict turns
    on it (the register, OD4). None does here: the closest is E74's first day,
    1.6e-3 of Θi against 2e-3, which passes on Θx too if D4's ratio holds.
  - **Class 3** (E66, E73, E75, E76 per tag) is not restated. It is a per-tag
    measure. Each such result states its `c`, here 110,495 J/kg (E71).

## 5. For the owner

 1. **The interim's label.** The register calls percentages on the records'
    lower bound upper bounds. On D4 they are 6% below the exact ones. The
    conservative default taken here: call them *interim*, quote the least
    favourable reading (×1.06 on D4), and rerun with #115 where a verdict is
    within that margin.
 2. **An energy intervention threshold.** OD3's aggregate row is water's
    0.5% a day. Does it apply to energy in OD4 units? If it does, the default
    exchange fails on D4 (6.9% a day) and on the sphere (2.6%).
 3. **The per-tag intervention row for energy.** It names no family. Read for
    energy, `sub` (3.1%) and `new_strat` (2.2%) fail on D4.

## 6. Proposed FINDINGS entry (for the parent)

**E84. On OD4's scale the energy records' verdicts hold for the prototype and
the sphere, and fail for the `enthalpy` audit, for D1 under `tracer`, and for
the explicit hour without G4.16's blocks. The records' interim scale is 6%
above the exact one on D4, so its percentages are not upper bounds there.**
The gross closure residual over the window's throughput Θi (process records):
D4 prototype 1.2e-5 at 24 h (E62, E64, E73, E79 same sign 4.7e-5), the sphere
7.9e-4 at 10 days and 1.6e-3 at day 1 (E74, against 2e-3); the `enthalpy`
audit on D4 2.7e-2 to 3.4e-2 (E62's base, E65's base, E66's reference); D1
24.9 times Θi in its hour (E42); the explicit hour without blocks 2.2e-2 of
D4's first-hour Θx, 5.1e-2 of the surface flux alone (E82's control). On
`g411x_d4_default` Θx/Θi is 0.945 at 24 h. The default's repair, never scored
before, moves 6.9% of Θi a day on D4 at `dcf7d086` and 2.6% on the sphere;
its ratio at 60 s over 120 s is 0.91. *`analysis/increment/od4_restate.py`;
`output/od4_restatement/`; runs as each record, and `g411x_d4_default`
(job `13944940`).*
