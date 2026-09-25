# G4.5: warnings, abort rules and acceptance kept apart; U2's calibration

Written on 2026-09-25. Both families' closure checks carry levels. Rev. 2 asks
that a warning level, a rule that ends or voids a run, and an acceptance
threshold never stand in for one another. This note says what each is, where
it lives, and how U2's tolerance is calibrated per transport (B11). It fits
#112 (option A, `claude/tag-closure-no-abort`), whose commit is cherry-picked
onto `claude/energy-claims-budget` as its first commit.

## 1. Four levels, for both families

| level | lives in | passing it | default | set by |
|:----- |:-------- |:---------- |:------- |:------ |
| `tolerance` | the model's check | warns, every time | water 1e-10; `energy_tracers` 1e-6; energy source tags per transport (section 2) | configuration |
| `throughput_tolerance` (energy source tags) | the model's check | warns, every time | `~` | configuration; no level approved |
| `void_above` (#112) | the model's check | warns once; this row and every later one void | water 1.0; energy `~` | configuration |
| `abort_above` | the model's check | ends the run | `~`, every family (#112) | configuration |
| acceptance | `analysis/evidence/closure_verdict.py` | pass, fail or not assessable | the OD3 rows | the register, before the run |

  - **A warning** says the residual passed a level set for this check. Its text
    now says so and adds that it is not an acceptance threshold. Before, the
    tolerance warning said "the tags no longer account for the field", which
    is the void level's meaning.
  - **The void level** says the tags no longer describe the field (#112).
  - **The abort** ends a run only where a user sets it (#112).
  - **Acceptance** is never a level in the model. It is scored afterwards, from
    the closure and audit tables, over OD2's window, against the OD3 row
    recorded before the run: water, the gross at 24 h at most 0.2% of
    `∫ρq_tot` with no more added in the second 12 h; energy, the gross's
    growth over the window at most 0.2% of the window's throughput, on the
    exact scale Θx. On the records' estimate Θi (E84), a verdict within 10% of
    the threshold is *not assessable*.

**What changed in the model** (`claude/energy-claims-budget`):

  - the tolerance warning's text; the docstrings and
    `docs/src/tracer_configuration.md` carry the table above;
  - the energy source closure table gains `source_throughput` and
    `gross_over_throughput`, the gross residual over the throughput since the
    start, where the tags keep their ledgers per tag (#115). They sit with
    G4.4's headroom, after the spin-up columns and before `void`;
  - `throughput_tolerance`, a second warning level on `gross_over_throughput`.
    It needs `energy_source_tag_ledger_per_tag: true`, and is refused without
    it. Default `~`.

Nothing here changes a model field or whether a run ends.

## 2. U2's calibration per transport (B11)

`analysis/increment/u2_calibration.py` reads every run on scratch with an
energy source closure table (`output/od4_restatement/u2_calibration.txt`).
B11 names V2 and V3. V2 is the production sphere under `enthalpy_increment`
(`g2_v2_sphere*`). B11's V3 is E45's, C7's sphere in Float32 under `tracer`
(`v3_sphere_float32`); the D4 twins of E68 and E73 (`v3_upd_*`) are listed too.

| transport | default `tolerance` | largest `gross_relative`, V2 and V3 | margin | largest over all healthy runs | margin |
|:--------- | -------------------:|:----------------------------------- | ------:|:----------------------------- | ------:|
| `enthalpy_increment` | 0.01 | 2.01e-4 (V2, `g2_v2_sphere_n2`, 10 d) | 50 | the same | 50 |
| `tracer` | 1.0 | 5.9e-3 (V3, `v3_sphere_float32`) | 170 | 5.5e-2 (`lr_s26_copies`, 90 d) | 18 |
| `enthalpy` | 0.1 | no V2 or V3 run | — | 6.6e-3 (`g1_base_d4_float32`) | 15 |

  - **The defaults stand.** V2 and V3 sit 50 and 170 times below them, and no
    healthy run on scratch comes within a factor of 15. The code's own table
    (`ENERGY_SOURCE_CLOSURE_TOLERANCES`) quotes a margin of 7.1 for `tracer`
    over 59 runs, some of which are no longer on scratch; the least favourable
    margin is that one.
  - **Left out**, as defects the warning must catch: the explicit 1M hour
    without G4.16's blocks (1.8e-4 and 2.1e-4 of the partition in an hour,
    E80, E82), and C1c's shelved placements (up to 5.9e-2, E59).
  - **The residual grows with the run's length** (E74), so a level that suits
    a day is loose for an hour and tight for a season. The long runs reach
    7.6e-12 under `enthalpy_increment` in 90 days (E81), and 5.5e-2 under
    `tracer` with copies.

**In OD4 units.** `gross_over_throughput` does not depend on the offset, as
`gross_relative` does (E15). The largest over the healthy runs, on Θx where a
run has it and on Θi otherwise:

  - `enthalpy_increment`: 4.5e-3, in V2's first two hours; 1.6e-3 at day 1 and
    7.9e-4 at day 10. The ratio falls as the run goes on, since the
    throughput grows with time and the gross does not keep pace;
  - `enthalpy`: 3.4e-2 (`g1_base_d4_float32`);
  - `tracer`: 26 (`d1_column_1m_ice_no_vdiff`, an hour). Under `tracer` the
    gross is transport error (E42b), which does not scale with the sources.
    A level in these units means nothing for `tracer`.

**Proposed, not set** (the owner's): `throughput_tolerance` 5e-2 under
`enthalpy_increment` and 0.3 under `enthalpy`, ten times the largest healthy
value, and none under `tracer`. Such a warning sits 25 to 150 times above
OD3's acceptance threshold (2e-3 over the window). That is on purpose: it
catches a runaway, and acceptance is scored apart.

## 3. Water

The water check's `tolerance` defaults to 1e-10. Under the follower
(`water_tag_transport: increment`) a healthy D4-W day reaches 1.35e-4 (W28),
so the warning fires in every such run. That is a warning calibrated for the
tracer path only. A per-transport default, as energy has, is a tolerance, so
the owner's (question 2). Nothing is changed for water here beyond the
warning's text.

## 4. Tests

  - `test/config/tracer_config.jl`, "Closure levels kept apart (G4.5)":
    `throughput_tolerance` off by default, read when set, refused without the
    ledgers and at zero, unknown to the water block; each warning in its own
    words; silent below the level; the column in the table.
  - `test/energy_source_tags_tests.jl`: the closure table's column order
    (spin-up at 10 to 12, the family's columns, `void` last).
  - `analysis/evidence/test_closure_verdict.py`: the scorer's pass, fail and
    not-assessable cases on synthetic tables, and its refusals (no table, a
    table that stops early, `output_active`). On real runs it gives E84's
    default a pass (8.7e-6 of Θx), and the `enthalpy` audit on D4 a fail
    (2.2e-2 of Θi).

## 5. For the owner

 1. `throughput_tolerance`'s levels: 5e-2 (`enthalpy_increment`), 0.3
    (`enthalpy`), none for `tracer`; or keep it off.
 2. Water's warning under the follower: a per-transport default, or leave
    1e-10.
 3. Whether the default warning should move from `gross_relative` to OD4
    units once the per-tag ledgers are on by default. Today they are off by
    default (the owner, 2026-09-24).
