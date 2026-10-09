# Part 11a: energy references, pre-registered design

Proposed 2026-10-09, for the owner. Base: `claude/plan-rev2` at `9e5155325`.
The cases moved to the fixed `c` on 2026-10-09, at `ddbafbbfe`.
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
| `heating_labels`           | 1, sections 2.1 and 2.2     | Gains by `w_kp`, region tags start at `M_k E_c(0)`   | 166764            | Swap the two source overlays        |
| `donor_cooling`            | 2, section 2.2              | `a_k(t) = a_k(0) E(t)/E(0)` under pure donor loss    | 274389            | Charge the cooling to its tag alone |
| `labelled_exchange`        | 3, section 2.3              | Gross face flows carry the donor's `ψ_k`             | 166764            | Labels from the receiver            |
| `boundary_offset_exchange` | 4, section 2.3              | `F_c = F_E + c F_M`, donor by the sign of `F_c`      | 166764            | The water donor for negative energy |
| `opposing_net_zero`        | 5, sections 4.2 and 4.3     | `+Q` and `−Q` events stay distinct                   | 166764            | Collapse the processes first        |
| `offset_change`            | 6, section 2.1              | `ΔE_c = Δρe_tot + cΔρ` on a bitwise parent           | 166764 and 333528 | Fractions held invariant across `c` |
| `inventory_edge_cases`     | 7, sections 2.2 and 4.3     | Zero share where `E_c ≤ 0`, clamps, signed inventory | 166764            | An epsilon in the share denominator |
| `radiation_record`         | 8, section 2.4              | Stage-weighted `−D_z F` and the density conversion   | none, records     | Wrong sign                          |

Each case declares `c` in the design file with `frozen: true`. The fixture
writes the convention from the design before any floor or verdict is
measured, and the adapter refuses a fixture whose convention differs. The
cases use the fixed `c` of 166,764 J/kg, dry internal energy counted from
150 K ([DECISIONS.md](../DECISIONS.md), 2026-10-09, in force). G1 and G2 keep
110,495 J/kg as historical results. E71 showed that doubling `c` moved the
region tags' integrals by 152% and 177%, so every energy verdict names its
`c`. `donor_cooling` uses `c_p,d T_0` = 274,389 J/kg, the sweep alternative of
G4.10, to show that the tools read `c` per case. Three inputs follow `c`.
`offset_change` sets its energy source to −1.5 `c` times its mass source, so
the source changes sign in `E_c` between `c` and `2c`. `inventory_edge_cases`
sets `ρe` so that its cells hold `E_c` = 130,495, 0 and −9,505 J/m³. In
`boundary_offset_exchange`, `F_c` points upward while `e_fall + c < 0`, which
holds for `c` below 3e5 J/kg. `cΔρ` enters only `boundary_offset_exchange`
and `offset_change`, the cases with a mass change. Θx is defined for `heating_labels`, `donor_cooling`,
`opposing_net_zero` and `offset_change`. Θi is computed where records exist.
The other cases have no source, so a percentage of Θx is not assessable there.

Stored-energy cases and the radiation record are separate references with
separate families. The record's stage route integrates each face flux over
the accepted stages first, then differentiates. It shares the flux, the faces
and the tableau with the candidate, so it checks the stage weights and the
order of operations, not the divergence. The continuum record is closed form
in time. It shares the faces and the `-diff/dz` operator with the stage route,
so it is independent in time only. In a flat column that operator is the
exact cell average, so nothing is wrong in 11a. No route here is an
independent divergence implementation. Its sign is scored in every cell. The window amount is
`ρ(t1) e_prc(t1) − ρ(t0) e_prc(t0)` on a changing density.

## 3. Controls

Every case has its registered mutant in the design, caught by a test in
`test_energy_reference.py` (`MutantTests`). Each mutant keeps the invariants it
declares (parent, partition closure, overlay sum, records, inputs or stage
fluxes) and fails an origin, record or classification check. A declared
invariant without a check is refused. An origin row that the scorer's reading
cannot assess never passes. It makes the candidate NOT ASSESSABLE. Further wrong implementations from
the contract are tested too: omitted offset flux, mass replaced by water, a
changed parent at `2c`, an omitted stage weight, a transported record,
specific-output differencing, a region burden pass and a duplicated restart
gross.

## 4. Floors, ladder and tie

Floors follow OD12, one per source. Four are stated with their basis. For
the six closed-form stored cases the reference-discretization floor is
constructed, not measured. It is the error of a 128 eps relative change of
every tag, about 1e-10 of the tolerance. It cannot reach the quarter rule, so
that test is empty there. The stepped rungs are measured and reported. They
gate nothing. So a closed form claims no convergence. It declares `converged`
null with the basis "Inapplicable" and reports the ladder as
`cross_check_converged`. The scorer reads null as not assessable, so a later
converter needs a rule for closed forms. For the classifier the floor is zero by construction. For the
record no tolerance is approved. EA-ACCURACY lapsed on 2026-10-07
([DECISIONS.md](../DECISIONS.md), EA-USE). EA-USE sets what 11a verifies: the
record against the independent accepted-stage flux, reported. So the record's
floor is measured relative to the record's window amount and is reported
only. Every case but
`inventory_edge_cases` runs a step ladder of three rungs, and
`heating_labels` a Float32 rung. The record's ladder is its stage ladder. A floor that rises by at most
`SECOND_HALF_TIE` along the ladder is a tie (Part 6's rule). Excluded processes
must read zero arrays in the candidate.

## 5. Proposed choices, 2026-10-09

The owner decided four choices on 2026-10-09
([DECISIONS.md](../DECISIONS.md), 2026-10-09). They are in force.

  - Decided 2026-10-09: the fixed `c` is 166,764 J/kg (OD11). Each case
    freezes it, except `donor_cooling`, which uses `c_p,d T_0` = 274,389 J/kg
    as the sweep alternative. `offset_change` adds `2c` = 333,528 J/kg.
  - Decided 2026-10-09: `opposing_net_zero` lists its expected NOT
    ASSESSABLE rows in the frozen design. They are `src_heat` at one hour and
    `src_cool` at both endpoints. `src_cool` has no gain path, so the fixture
    checks that it reads exactly zero. The suite exits 0 when only the listed
    rows are unassessable and 3 for any other. The scorer is unchanged.
  - Decided 2026-10-09: PX22 uses three new configs in
    `configs/part11a_px22_draft/`. They are `px22_d4_c.yml`, `px22_d4_2c.yml`
    and `px22_d4_untagged.yml`. They add output keys. The two tagged configs
    set the offset to `c` and `2c`.
  - Decided 2026-10-09: the stored cases keep the constructed 128 eps floor as
    their gate. The stepped rung is a cross-check only.

The choices below stay proposed.

  - The fixtures are self-contained directories, not scorer Bundles. The scorer
    has no energy known-answer hook and is unchanged.
  - The Θx window of the small-tag rule is `[0, endpoint]` in these fixtures.
    Each case declares it, frozen, as `theta_x_window` in the design. The
    code reads it, and the adapter refuses a fixture whose window is missing
    or differs.
  - The surface donor of the boundary case is the bottom cell.
  - The record floor is reported relative to the record, never scored.
  - Rule names per case in `energy_reference_adapter.RULES`.
  - The roundoff allowance of 128 eps, the use of `SECOND_HALF_TIE` as the
    ladder tie, the excluded-process roster and the falsification rule of
    section 7.

## 6. What stays a design

OD7 is deferred, so PX15 and the follower's split stay designs. OD9 and OD10
stay proposed. OD11's fixed `c` is in force, but its rule classification,
admissible alternatives and source convention stay proposed. So every
conditional source test states its convention. The
PX22 draft is in `configs/part11a_px22_draft/`. It needs the owner's per-run
approval.

## 7. Falsification

A case fails if its exact candidate fails a check, if its mutant is not
caught, or if its reference floor exceeds the quarter rule. Any of these
blocks the case as a reference. The floor test is empty for the closed-form
cases (section 4). A candidate with an unassessable origin row is NOT
ASSESSABLE, not a pass.
