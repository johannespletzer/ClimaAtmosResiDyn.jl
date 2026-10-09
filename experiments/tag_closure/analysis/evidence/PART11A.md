# Part 11a record: energy references

Proposed 2026-10-09. The design is
[PART11A_ENERGY_REFERENCES](../../design/PART11A_ENERGY_REFERENCES.md).

## Software

`energy_reference.py`, `energy_reference_adapter.py`,
`make_energy_reference_fixture.py` and `test_energy_reference.py`. The suite
`configs/energy_reference_known_answers.json` exits 3 after review: eight
eligible references and eight mutants caught. Seven manufactured candidates
pass. For the six closed-form cases the candidate is the closed form itself,
so its pass checks the evaluator, not the equations. The stepped allocator
checks those. `opposing_net_zero` is NOT ASSESSABLE. Its overlays are small
at one hour, Θx is zero, and the scorer's small-tag rule needs a positive Θx.
`src_cool` is NOT ASSESSABLE at both endpoints and `src_heat` at one hour.
Before review such rows counted as passing.

## Not delivered

  - A per-case floor table here.
  - A Part 7 style generator for the PX22 draft. The draft names
    `g46_d4_budget`, `_2c` and `g411x_d4_untagged`, while PX22 names
    `g411x_d4_default` and its twin. No named config writes per-tag source
    ledgers for all eight tags.
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
and they run. Empty until then.
