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

## 7. Addendum after the first submission (2026-09-24, before the second)

The first submission (jobs `13915221` to `13915228`, output in each run's
`output_0000/`) is void. Every tagged run's model fields differed from its
untagged twin's from the first daily output on. The runs under the two rules,
and the copies, differed from each other too. The cause is in the
configuration: all-sky radiation samples the cloud optics at random, and
`radiation_reset_rng_seed` was left `false`, so each run drew its own numbers.
The comparison in section 5 needs one atmosphere for all four runs of a site,
and criterion 4 of section 4 needs parity. So the configurations now set
`radiation_reset_rng_seed: true`, the upstream option that seeds each call
with the step number. Nothing else changes. The runs were cancelled after
about 12 days at site 23 and 9 at site 26. The second submission writes to
`output_0001/`.

One thing the first submission showed is added as **reported, not a
criterion**, because it was seen before this addendum. At site 23 the parent's
own specific humidity went below zero (to −8e-4 kg/kg) from about day 9 in
every run, the untagged twin included. Both rules' water closure then jumped
from 1e-13 to 1e-1. Tags repaired to non-negative values cannot hold negative
parent water. So each run reports, every 6 hours, the parent's negative water
(`Σ ρ min(q_tot, 0)` over `∫ρq_tot`, from the output) beside its closure. The
decision rule of section 5 is unchanged. If negative parent water puts both
rules over the budget at a site, section 5 already says nothing is chosen from
that site.

## 8. Addendum: site 23's rerun with option C, for OD7 (2026-09-25, before any run)

W36 could not score site 23. From day 10 the parent's own water went negative,
the water tags drifted from it, and every tagged run crashed (known issue 7).
The owner deferred OD7 until site 23 can be scored, and on 2026-09-25 chose
option C: the partition tags partition `max(ρq_tot, 0)`, and the negative part
is a named field (`design/NEGATIVE_PARENT_WATER.md`, section 8). This addendum
registers site 23's rerun with option C. Nothing below changes after the runs.

**When.** Only after option C passes its validation
(`design/NEGATIVE_PARENT_WATER.md`, section 8.3: V1 to V4; V5 is reported).
If C fails it, nothing here is submitted, and the owner decides.

**The runs.** Site 23, 90 days, W36's configurations with the radiation's seed
reset (section 7). Each differs from its `lr_s23_*.yml` only in the job id and
in the daily outputs `q_tag_negative` and, under the follower,
`q_tag_inc_negative`. No tag keeps its own ledgers, as in W36.

| run | code | config |
|:--- |:---- |:------ |
| `samesign` | `claude/long-run-c-samesign` (`f13649da`) | `configs/lrc_s23_samesign.yml` |
| `absm` | `claude/long-run-c-absm` (`4244e8ab`) | `configs/lrc_s23_absm.yml` |
| `untagged` | `claude/long-run-c-samesign` | `configs/lrc_s23_untagged.yml` |
| `copies` | `claude/long-run-c-samesign` | `configs/lrc_s23_copies.yml` |

`claude/long-run-c-samesign` is option C (#116 at `49d29435`) merged with
`claude/long-run-samesign` (`746cbf0f`, section 3). One conflict, in the energy
follower's ledger, was resolved as the issue 7 probe's run tree resolved it:
#109's per-tag ledger and attempted totals, with G4.15b's same-sign weight.
`claude/long-run-c-absm` adds `claude/long-run-absm`'s one change, the weight
`|m|` in `water_increment_left_weight`. Neither branch is for merge. The run
trees are `../ClimaAtmosResiDyn-lrc-run` and `../ClimaAtmosResiDyn-lrc-absm-run`,
each the record merged with its branch. Output in each run's `output_0000/`.

**What differs from W36's code.** Only the tags:
  - option C, water only: the target, the follower's entry for the negative
    part's change, the rescale's and the copies' repair's aim, and the closure
    check against the target;
  - #109 (WP6 step 3) and #112 (no abort by default), which option C's branch
    carries. The per-tag ledgers stay off;
  - under `absm`, the weight `|m|` also places option C's negative-part entry,
    since that entry and the part left out share `water_increment_left_weight`.
    So `absm` is `|m|` wherever the water follower places a column total.

**The decision rule.** Section 5, unchanged, per family. Water's criterion 1
reads the closure check as option C writes it: the partition against the
target, relative to `∫max(ρq_tot, 0)`, against the same 0.2%. This is option
C's V2 measure. The energy tags are untouched by option C, and their budget,
1e-4, stays a proposal. Section 4's measurements and section 7's negative
water are reported as before, with `q_tag_negative` and the per-step gross of
`q_tag_inc_negative` beside them. Parity (section 4) is each tagged run's
fields against `lrc_s23_untagged`, bit for bit. As a further check, reported,
`lrc_s23_untagged` against W36's `lr_s23_untagged`, bit for bit, since no code
difference reaches the parent.

**Site 26 is not rerun if option C's V3 holds by its first branch**: `ic_s26_c`'s
water tags bit for bit `ic_s26_before`'s at every daily output. Site 26's parent
had no negative water on any of W36's 91 daily outputs, and every change of
option C is a no-op where the parent stays non-negative. So W36's site 26
verdicts, same sign kept for both families, stand. If V3 holds only by its
second branch, differences where the parent was negative, site 26 is rerun on
the same trees with `lrc_s26_*` configurations written the same way.

**The scripts.** `analysis/water/lr_rule_metrics.py` and `lr_parity.py` take
the rerun's names from the environment, `LR_PREFIX=lrc LR_OUTPUT=output_0000
LR_SITES=23`. Their defaults still reproduce W36 (`lr_parity.py` passes on
W36's 60 fields).

**The jobs.** From each run tree's root, with `submit_g3.sh`,
`DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl`, `hpda2_compute`,
2 CPUs, 48 GB, `--time=08:00:00`: four jobs. Every configuration builds its
model on the login node first.
