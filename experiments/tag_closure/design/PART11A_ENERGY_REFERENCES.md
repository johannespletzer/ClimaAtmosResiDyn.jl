# Part 11a: energy references, pre-registered design

Proposed 2026-10-09, for the owner. Base: `claude/plan-rev2` at `9e5155325`.
The model code the cases describe is `main` at `bb2bedf23`. No run, threshold,
default, tolerance or scorer change is part of this design.

## 1. Question

Can each origin rule of the energy tags be tested against an answer that does
not share the rule? Each case is a known answer. It verifies the equations and
the declared label model. It does not qualify atmospheric origins.

## 2. Cases

The frozen design is `analysis/evidence/energy_reference_design.json`. Its
hash is pinned in `energy_reference.py` and in
`configs/energy_reference_known_answers.json`. The hash shows integrity only.

| Case                       | Contract row (G4 section 6) | Identity tested                                      | c [J/kg]          | Registered wrong-origin mutant      |
|:-------------------------- |:--------------------------- |:---------------------------------------------------- |:----------------- |:----------------------------------- |
| `heating_labels`           | 1, sections 2.1 and 2.2     | Gains by `w_kp`, region tags start at `M_k E_c(0)`   | 110495            | Swap the two source overlays        |
| `donor_cooling`            | 2, section 2.2              | `a_k(t) = a_k(0) E(t)/E(0)` under pure donor loss    | 274388            | Charge the cooling to its tag alone |
| `labelled_exchange`        | 3, section 2.3              | Gross face flows carry the donor's `ψ_k`             | 110495            | Labels from the receiver            |
| `boundary_offset_exchange` | 4, section 2.3              | `F_c = F_E + c F_M`, donor by the sign of `F_c`      | 110495            | The water donor for negative energy |
| `opposing_net_zero`        | 5, sections 4.2 and 4.3     | `+Q` and `−Q` events stay distinct                   | 110495            | Collapse the processes first        |
| `offset_change`            | 6, section 2.1              | `ΔE_c = Δρe_tot + cΔρ` on a bitwise parent           | 110495 and 220990 | Fractions held invariant across `c` |
| `inventory_edge_cases`     | 7, sections 2.2 and 4.3     | Zero share where `E_c ≤ 0`, clamps, signed inventory | 110495            | An epsilon in the share denominator |
| `radiation_record`         | 8, section 2.4              | Stage-weighted `−D_z F` and the density conversion   | none, records     | Wrong sign                          |

Each case declares `c` in the design file with `frozen: true`. The fixture
writes the convention from the design before any floor or verdict is
measured, and the adapter refuses a fixture whose convention differs. 110 495
J/kg is the convention of the previous runs, a historical baseline, not an
approved universal choice. E71 showed that doubling `c` moved the region tags'
integrals by 152% and 177%, so every energy verdict names its `c`.
`donor_cooling` uses `c_p,d T_0` (G4.10) to show that the tools read `c` per
case. `cΔρ` enters only `boundary_offset_exchange` and `offset_change`, the
cases with a mass change. Θx is defined for `heating_labels`, `donor_cooling`,
`opposing_net_zero` and `offset_change`. Θi is computed where records exist.
The other cases have no source, so a percentage of Θx is not assessable there.

Stored-energy cases and the radiation record are separate references with
separate families. The record case is tested against an independent route:
it integrates each captured face flux over the accepted stages first, then
differentiates. The continuum record is closed form. The window amount is
`ρ(t1) e_prc(t1) − ρ(t0) e_prc(t0)` on a changing density.

## 3. Controls

Every case has its registered mutant in the design, caught by a test in
`test_energy_reference.py` (`MutantTests`). Each mutant keeps the invariants it
declares (parent, partition closure, inputs or stage fluxes) and fails an
origin, record or classification check. Further wrong implementations from
the contract are tested too: omitted offset flux, mass replaced by water, a
changed parent at `2c`, an omitted stage weight, a transported record,
specific-output differencing, a region burden pass and a duplicated restart
gross.

## 4. Floors, ladder and tie

Floors follow OD12, one per source. Four are stated with their basis. The
reference-discretization floor is measured. For the stored cases it is a
fraction of the scorer's origin tolerance, in the scorer's energy reading, and
must be at most `FLOOR_FRACTION_MAX`. For the record no tolerance is approved
(EA-ACCURACY), so its floor is relative to the record's window amount and is
reported only. Each case also runs a step ladder of three rungs, and
`heating_labels` a Float32 rung. A floor that rises by at most
`SECOND_HALF_TIE` along the ladder is a tie (Part 6's rule). Excluded processes
must read zero arrays in the candidate.

## 5. Proposed choices, 2026-10-09

  - The fixtures are self-contained directories, not scorer Bundles. The scorer
    has no energy known-answer hook and is unchanged.
  - The Θx window of the small-tag rule is `[0, endpoint]` in these fixtures.
  - The surface donor of the boundary case is the bottom cell.
  - `donor_cooling` uses `c = 274388` J/kg.
  - The record floor is reported relative to the record, never scored.
  - Rule names per case in `energy_reference_adapter.RULES`.

## 6. What stays a design

OD7 is deferred, so PX15 and the follower's split stay designs. OD9 to OD11
stay proposed, so every conditional source test states its convention. The
PX22 draft is in `configs/part11a_px22_draft/`. It needs the owner's per-run
approval.

## 7. Falsification

A case fails if its exact candidate fails a check, if its mutant passes, or
if its reference floor exceeds the quarter rule. Any of these blocks the case
as a reference.
