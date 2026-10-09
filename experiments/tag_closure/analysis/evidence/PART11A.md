# Part 11a record: energy references

Proposed 2026-10-09. The design is
[PART11A_ENERGY_REFERENCES](../../design/PART11A_ENERGY_REFERENCES.md).
Every case freezes the fixed `c` = 166,764 J/kg (DECISIONS, 2026-10-09),
except `donor_cooling` at `c_p,d T_0` = 274,389 J/kg. That case is the
per-case control (decided 2026-10-09, after PRs #166 and #167). It shows that
the adapter reads `c` per case and refuses a mismatch, so a hard-coded `c` in
a producer is caught. It is `c_p,d T_0` at ClimaParams 1.2.0 (`c_p,d` = 1004.5,
`T_0` = 273.16). The design, its hash
`24290e41…` and the fixtures moved to the fixed `c` on 2026-10-09.

## Software

`energy_reference.py`, `energy_reference_adapter.py`,
`make_energy_reference_fixture.py` and `test_energy_reference.py`. The suite
`configs/energy_reference_known_answers.json` exits 0: eight eligible
references and eight mutants caught. Seven manufactured candidates
pass. For the six closed-form cases the candidate is the closed form itself,
so its pass checks the evaluator, not the equations. The stepped allocator
checks those. `opposing_net_zero` is NOT ASSESSABLE. Its overlays are small
at one hour, Θx is zero, and the scorer's small-tag rule needs a positive Θx.
`src_cool` is NOT ASSESSABLE at both endpoints and `src_heat` at one hour.
Before review such rows counted as passing.

The frozen design lists these three rows (owner decision of 2026-10-09). The
suite exits 0 when only the listed rows are unassessable, and 3 for any other
unassessable row. The case keeps its NOT ASSESSABLE verdict in the results.
`src_cool` has no gain path, so the check `no_gain_path_zero` requires it to
read exactly zero. That check stands beside the scorer's rows and never
replaces them. The scorer is unchanged.

## Boundary case margin

The boundary case's wrong-origin mutant misses by 2.74 times the tolerance at
the fixed `c`. The margin vanishes as `c` approaches 300,000 J/kg. The owner
accepted the halved margin on 2026-10-09, after PRs #166 and #167. `c` is
fixed, so `e_fall` stays. If `c` ever rises, `e_fall` is lowered first.

## Not delivered

  - A per-case floor table here.
  - A Part 7 style generator for the PX22 draft. The three configs are
    written by hand (see below).
  - The G4.7 ladder and the G4.8 pulse. Neither is reused or routed here.
  - Case 5's temporal grouping sweep.
  - An independent divergence implementation for G4 row 8. The stage route
    shares the flux, the faces and the tableau with the candidate. The
    continuum shares the faces and the `-diff/dz` operator with the stage
    route, so it is independent in time only. EA-ACCURACY lapsed on
    2026-10-07 ([DECISIONS.md](../../DECISIONS.md), EA-USE). EA-USE sets what
    11a verifies, the record against the independent accepted-stage flux,
    and the stage route meets it. The independent divergence is required
    before any qualification.
  - Registered mutants for the other wrong implementations of the contract:
    a swapped flux direction and a missing label transport (row 3), Θx read
    as gross and a signed ledger read as zero activity (row 5), spread read as
    an error bound (row 6), hidden repair or follower activity (row 7).
  - A note in the decision record on how the energy scale and the regional
    tags depend on `c`. Section 2 of the design states it.
  - A scorer-format radiation evidence file.
  - A Float32 rung beyond `heating_labels`. The transport shares run in
    Float64, so a Float32 rung of the exchange or boundary case would not
    stay Float32.

## Measured: reference floors

Filled by the suite's `known_answer_results.json` per case, after review.

## Measured: PX22

Filled after the owner approves the three jobs of `configs/part11a_px22_draft/`
and they run. Empty until then. The configs are `px22_d4_c.yml` and
`px22_d4_2c.yml`, from `g411x_d4_default.yml` at `c` and `2c`, and
`px22_d4_untagged.yml`, from `g411x_d4_untagged.yml` (owner decision of
2026-10-09). The tagged two add each tag's ledgers, `e_src_fixgross_*`, the
water records and the averaged `pr`. The twin adds the averaged `pr`. The
per-tag identity and EA-C4 need these keys.
