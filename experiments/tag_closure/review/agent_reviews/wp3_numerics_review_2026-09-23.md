# Review of WP3: water tags under prognostic EDMF

- Diff: `30dcfee9..462372f9` on `claude/water-tags-edmf-wp3`, worktree
  `../ClimaAtmosResiDyn-wedmf3`. 30dcfee9 is PR #100's head (WP1).
- Plan: `G3_PLAN.md` sections 4.1, 4.2, 4.7, 4.8 and 6.1; `G3_TODO.md` WP3.
- Reviewer: clima-numerics-reviewer agent, xhigh, 2026-09-23. It edited
  nothing and submitted no jobs. It read the running CI jobs' outputs and ran
  short login-node checks.
- The fixes are in `73fa27bd` ("address the numerics review"). What was not
  fixed is marked below, with the reason.

## Verdict

The default mode's numerics hold. The copies are complete only with the fifth
mirror, the surface moisture flux into the updraft (462372f9), which the
reviewer found on its own as well. The three CI groups failed as first
committed: on thresholds that assumed exact closure, on the missing mirror,
and on a vacuous 0M check.

## Blocking

| # | Finding | Resolution |
|:--|:--|:--|
| B1 | The closure thresholds (`1e-10`, `1e-8`) cannot hold: the column gives 3.5e-5 net and 5.4e-4 gross after an hour in the default mode, 3.7e-5 and 3.8e-4 with copies (without the fifth mirror). Keep exact claims at tendency level. | Default mode: bounds `1e-4` and `1e-3`, about twice the measured values and 20 times below V-W1's 2.2e-2 (6b687e0a). Copies: bounds set from the rerun with the fifth mirror (next commit). |
| B2 | The copies missed the updraft's share of the surface moisture flux (`surface_flux.jl:139-146`). Also: the fix writes the model's scratch `sfc_temp_C3`; nothing asserts the `evap` copy's increment. | Fixed in 462372f9. The scratch write is gone and the `evap` assert added (73fa27bd). The reviewer lists every writer of `q_totʲ` and finds no further term the copies miss. |

## Should-fix

| # | Finding | Resolution |
|:--|:--|:--|
| S1 | `water_tag_copy_sgs_names(Y)` is type-unstable and allocates 24 to 88 bytes per call, in every Jacobian update of every PrognosticEDMFX run with a passive updraft tracer, tagged or not. | Fixed: names from the model's type; a test checks `@inferred` and zero allocation. |
| S2 | The copies' sedimentation Jacobian carries the species' lateral-inflow derivative, not what the comment says; it also runs for number concentrations; the share derivative is not capped. | Fixed: the within-updraft operator only, under `condensate_phase`, capped at one, comment restated. |
| S3a | The implicit 0M rain-out mirror (the default path) never runs in CI. | Fixed: the 0M group steps implicitly; the 1M copies group explicitly, for the explicit path's parity. |
| S3b | No 0M default-mode parity run. | Not in CI: two builds per group fill the budget. V-W3's TRMM pair runs it. |
| S3c | `check_water_tag_exchange_partition` has no test. | Fixed: a unit test. |
| S3d | The parity runs switch on neither the audit nor a leak diagnostic, both of which write scratch from callbacks. | Fixed: the tagged runs of all three groups write them. |
| S3e | The one-composition tests cannot tell a swapped share in the 1M sedimentation mirror (updraft's share for falling water, environment's for inflow). | Open. Needs a manufactured test with different shares in the updraft and the environment; the mirror is correct by the reviewer's reading. |
| S3f | No restart round trip in either mode (criterion 2). | Open: V-W9 in the plan (WP4b). The guard itself is unit-tested. |
| S3g | The rebuild test compared the formula with itself. | Fixed: the rebuild on set shares against those shares. |
| S4 | The default mode has no counterpart of the fifth mirror: the plume starts at level 1 from the grid mean's composition, while the copies give the updraft's surface water to `evap` and its region. Fresh surface water is about 0.3 to 1% of the updraft's water at level 1; with `evap` at about 1% of the column in the first hour, `evap` in the updraft could differ severalfold between the modes, and fail the first-hour source-tag budget for this reason alone. Plausible, not measured. | Recorded in G3_PLAN 4.1's expected differences, for the owner. V-W3 measures it. |
| S5 | `q_tag_copy_res` and `q_tag_upfix` bound a sum, not the filter's clamps: the grid partition's residual (through entrainment, the filter's reset, the Rayleigh sponge), the Newton mismatch (`q_totʲ` couples to the condensates, the copies only diagonally), the leaks, and the rain-out's clamp. The repair runs without the filter too. The ledger is signed, so its size can understate what moved. | Docs say so (`tagged_water.md`). G3_PLAN 6.1's "holds by construction" gets a note; the budget's numbers are the owner's and unchanged. |
| S6 | Overstatements: issue 3's "the flux no longer drifts the partition" (true at a state, not over a step); the 0M mirror's "a drift decays" (the rain-out keeps `r/q_totʲ` constant); "the copies are rescaled" (the repair adds by share with a floor, and zeroes where the sum is not positive). | Fixed in the docs and the docstring. |

## Notes

| # | Finding | Resolution |
|:--|:--|:--|
| N1 | The plume's rescale overflows to NaN where the partition holds a denormal amount. | Fixed: share first, then the water; a unit test. |
| N2 | The copies' sedimentation writes the model's scratch inside the parent's species loop. Each field is rewritten before the parent next reads it, so no parity effect today. | Open: a latent hazard. Own scratch for the copies is the fix. |
| N3 | The partition refusal is rank-local under MPI; a partition that fails on some ranks only would hang the others. The energy check does the same. | Open, for both families (WP2's shared helpers). |
| N4 | `q_tag_upfix_*` was registered for source tags (always zero) and could go stale across models. | Fixed. |
| N5 | The energy copies (#95) have none of these mirrors, the surface enthalpy flux and the radiation into `mseʲ` included. | For G4: recorded in G4_TODO. |
| N6 | In copies mode the grid tags rain out by `φ̄` and the updraft copies by `φʲ`, so the environment's implied tag values can move the wrong way. | For WP4a: recorded in G3_TODO. |

## Checked and found correct

- The donor flux is built face by face as `vertical_transport` builds it, for
  all four reconstructions, and its partition sums to the parent at rounding
  (CI test at 1e-12).
- The exchange: the decomposition identity holds; over 20,000 random cases the
  zero sum held to 4.4e-16, the bound to 5.6e-17, and the environment's shares
  stayed at or above −5.6e-17. It is first-order under van Leer.
- The plume is implicit, with the factor `ρ/ρa⁰`; the rescale keeps the shares
  and mixes by mass; it uses the model's `ε + ε_turb`.
- Each copy mirror against the parent's code, term by term: the rain-out, the
  sedimentation, the relaxation and the repair.
- The copies' Jacobian: advection, diffusion, entrainment and relaxation
  diagonals match `q_totʲ`'s; no model block changed; the solver is unchanged.
- All six leak closed forms match "Σ tags minus parent" by reading.
- Parity: 15/15 in the default mode, 21/21 with copies, 13/13 under 0M.
- The restart guard and the refusals.
