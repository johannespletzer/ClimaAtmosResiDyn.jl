# Long runs: where the followers leave out the column's total, same sign or |m|

Written on 2026-09-24, before any run, at the owner's request (G4.15's choice
"might be better answered after long simulation runs of weeks to months";
the setup approved the same day). This commit fixes the case, the runs and
the decision rule. The runs start after it.

## 1. The question

Both families' increment followers leave out of the tags, each step, the part
of the mismatch that changes a column's total, `M = ∫m`. The two rules leave
out the same amount and differ only in where it lands:
  - **same sign** (#102 for water, G4.15b for energy): over the cells whose `m`
    has `M`'s sign, in proportion to `m` there; no cell leaves out or moves
    more than its own mismatch;
  - **|m|** (before the owner's review of #102): over every cell, in
    proportion to `|m|`.

Over a day (W28 water, E79 energy) the differences were small and went both
ways: water's moved ledger halved under same sign; energy's gross closure
residual rose fourfold. Whether the residual grows, wanders or saturates over
weeks decides which rule is safer, and a day cannot show it.

## 2. The case

The GCM-driven column (`config/model_configs/prognostic_edmfx_gcmdriven_column.yml`,
as V-W8 ran it): HadGEM2-A AMIP July forcing, time-mean profiles and a constant
sun (`GCMColumnData.jl`), so it can run for months; prognostic EDMF with the
SGS mass flux, 0M microphysics, all-sky radiation, 60 stretched levels to
40 km, `dt` 10 s, ARS222, one Newton iteration. **90 days.**

Two sites of the forcing file, in contrasting regimes:
  - **site 23** (17°N, 211°E): subsidence of 26 hPa/day at 5.5 km, sea at
    298 K, trade cumulus; V-W8's site;
  - **site 26** (8°N, 199°E): ascent of 81 hPa/day at 5.5 km, sea at 301 K,
    the strongest ascent in the file, deep convection. If its untagged twin
    fails, site 32 (2°S, 156°E, ascent 68 hPa/day) replaces it; if that fails
    too, site 23 stands alone.

Tags, both families in every tagged run, as V-W8: water `pbl` and `free` (a
region below and above 1 km), `evap` (surface flux), `fcg` (forcing); energy
`pbl`, `free`, `sfc`, `rad`, offset 110495 J/kg. The water tags follow the
increment (`water_tag_transport: increment`), the energy tags too
(`energy_source_tag_transport: enthalpy_increment`).

## 3. The runs, per site

| run          | code                                           | what                                |
|:------------ |:---------------------------------------------- |:----------------------------------- |
| `samesign`   | `claude/long-run-samesign` (`746cbf0f`)        | both families under same sign       |
| `absm`       | `claude/long-run-absm` (`7fd0ffab`)            | the same code with the weight `|m|` |
| `untagged`   | `claude/long-run-samesign`                     | parity twin                         |
| `copies`     | `claude/long-run-samesign`                     | the copies of both families, the per-tag reference |

`claude/long-run-samesign` is G4.15b (on G4.15a, on #102) merged with WP6
(#103), for the per-step gross accumulators. `claude/long-run-absm` differs
from it only in `water_increment_left_weight`, which returns `abs(m)`; both
families call it. Neither branch is for merge.

## 4. What is measured, per family and run

  - the net and gross closure residual every 6 hours;
  - the gross's growth: the slope of `log(gross)` against `log(t)` over days
    30 to 90 (about 1 growing, 0.5 wandering, 0 saturated);
  - the part left out (`increment_left`), and per step the gross of what was
    left out and moved (WP6's `*_inc_left_gross`, `*_inc_moved_gross`);
  - the partition repair's ledger and the smallest tag value;
  - each tag's L1 against the copies at days 10, 30 and 90;
  - parity: the untagged twin's fields bit for bit in both tagged runs.

## 5. The decision rule, per family

Keep **same sign** if both hold:
  1. its gross closure residual at day 90 is within the family's budget:
     water 0.2% of `∫ρq_tot` (G3_PLAN 6.1); energy 1e-4 of `∫(ρe_tot + cρ)`,
     **a proposal**, since no energy budget of this form is set;
  2. it grows no faster than under `|m|`: its slope over days 30 to 90 is at
     most `|m|`'s plus 0.25.

Otherwise that family takes the rule with the smaller gross at day 90. The
agreement with the copies is reported, and breaks a tie (both within 10% of
each other at day 90). A site that did not run to 90 days counts only up to
where it stopped, and says so. If neither rule meets the budget at a site,
that is reported, and nothing is chosen from that site.

## 6. What follows

The result decides G4.15b for energy, and confirms or reopens #102's rule for
water. The owner makes both calls.
