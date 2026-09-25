# Which per-tag ledger ratio stays readable through a zero crossing

Written on 2026-09-25, before any run, after the owner's review of #109
(finding 2) and the owner's decision the same day: the per-tag intervention
row applies to all tags, with two denominators. Region tags use `retained /
∫tag`; source-labelled or signed tags use `retained / ∫|tag|`; below the
small-tag bound the row is "not applicable". #109 (`6695a5c7`) reports all
three ratios per tag: `_inventory_fraction` (over `∫tag`), `_burden_fraction`
(over `∫|tag|`), `_parent_fraction` (over the parent scale), and
`_applicable`.

## The question

Which ratio stays readable through a zero crossing, without hiding a large
retained correction?

## The runs

Two pairs that differ only in `energy_source_tag_repair`, each a day under
`enthalpy_increment` (so the increment ledger moves with the repair off),
with the partition tags plus `sfc` (the heating surface flux) and `rad` (the
cooling radiation), the per-tag ledgers, the process records and an hourly
audit:

| config | case | repair |
|:------ |:---- |:------ |
| `ledger_ratio_d4_repair_on`      | D4, `g1_inc_d4`'s EDMF column, `dt` 120 s, DYCOMS radiation | on  |
| `ledger_ratio_d4_repair_off`     | the same                                                      | off |
| `ledger_ratio_sphere_repair_on`  | C6's small sphere, `dt` 400 s, gray radiation               | on  |
| `ledger_ratio_sphere_repair_off` | the same                                                      | off |

The radiation in all four is deterministic, so each pair's model fields can
be compared bit for bit.

## Precondition (else the pair is inconclusive)

  - `ta`, `rhoa` and `hus` are bit for bit the same within each pair;
  - in the repair-off run, `sfc` or `rad` reaches `∫tag ≤ 0`, or `∫|tag|/∫tag
    ≥ 10`, at a row where `_applicable` is 1;
  - in the repair-on run, `led_fix_sfc` or `led_fix_rad` retains more than 0.

## Pass rule, per ratio

Over every row from 1 h on where `_applicable` is 1, in both arms of both
pairs, a ratio passes when it:

  a. is finite;
  b. never rises more than 10 times from one hourly row to the next while
     `_retained` rises less than 2 times;
  c. never sits below its own pass level (2%, or 2e-4 for the parent ratio)
     where `_burden_fraction` is at least 2%. By construction (c) can fail only
     for the parent ratio.

**Prediction:** the burden ratio passes; the inventory ratio fails with the
repair off; the parent ratio fails (c) with the repair on. If the burden ratio
fails (b), the choice goes back to the owner.

The code is #109 at `6695a5c7`, run from a run tree of the record with it.
The configs are checked by `analysis/increment/ledger_ratio_check_configs.jl`
(each builds its model and registers every diagnostic it asks for). The
energy parent scale here is OD4's interim, which is an estimate (E84); only
the parent ratio uses it.
