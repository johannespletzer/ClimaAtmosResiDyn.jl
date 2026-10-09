# Part 11a record: energy references

Proposed 2026-10-09. The design is
[PART11A_ENERGY_REFERENCES](../../design/PART11A_ENERGY_REFERENCES.md).

## Software

`energy_reference.py`, `energy_reference_adapter.py`,
`make_energy_reference_fixture.py` and `test_energy_reference.py`. The suite
`configs/energy_reference_known_answers.json` exits 0 on the author's run:
eight eligible references, eight exact candidates pass, eight mutants caught.

## Measured: reference floors

Filled by the suite's `known_answer_results.json` per case, after review.

## Measured: PX22

Filled after the owner approves the three jobs of `configs/part11a_px22_draft/`
and they run. Empty until then.
