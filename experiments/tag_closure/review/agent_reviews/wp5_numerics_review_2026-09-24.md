# Numerics review of #102 (WP5), 2026-09-24

`clima-numerics-reviewer`, effort xhigh, on `claude/water-tags-edmf-wp5` at
`867a5264`, stacked on #101 at `06adcf1c`. Condensed; the reviewer's
`file:line` evidence is kept. How each point was taken, with the commit, is in
the last column.

**Verdict: nothing blocking.** Parity holds by construction. The correction's
arithmetic, sign and ledger split are right and mirror
`correct_energy_source_increment!` line by line, without `ρ` and the offset.

**Computed by the reviewer:** the flux and the ledger on a stretched 30-level
toy column (the partition's change equals the moved part to 1.9e-15 of
max|m|; the moved part's column sum about 1e-16; Σleft = M); where the left
part lands; a pinned residual; the CTS 1.0.1 tableaus through
`IMEXAlgorithm` (ARS343 b/aᵢᵢ = [—, 2.773, −1.478, 1.0], ARS222 [—, 2.414, 1.0],
SSP333 refused); the energy refusal message evaluated old and new, identical;
the name predicate's allocation (32 B per call).

| point | finding | taken as |
|:----- |:------- |:-------- |
| S1 | The follower never changes the partition's column total (the flux vanishes at both boundaries, `tagged_water_increment.jl:218-229, 240-246`; `ᶜadvdivᵥ`, `abbreviations.jl:106-109`; normalized shares, `tagged_water.jl:450-452`). So W23's net part, 7.7e-3 of 1.6e-2 gross (default) and 7.8e-3 of 9.7e-3 (copies), stays; the follower removes at most about half the gross there. W23 and the PR overstated it. Options: route `M` through the bottom face with the lowest cell's shares, or give the tags' sedimentation rows the one-way cross blocks (`manual_sparse_jacobian.jl:1283-1288`) | docstring, docs, PR, W23 and G3_PLAN 4.3 state the invariant (`fd07d902`, the record); the explicit-path probe with the follower measures it; the two options go to the owner |
| S2 | "Left where it arises" is false: the left part is spread by `|m|`, dominated by the parent's advection, which the tags no longer take (`advection.jl:258-260`). Toy: 0.6% of it in the bottom cell where the lag arose, 39% above 1000 m; in 16 of 30 cells opposite in sign to `m`, so the moved part reaches 2|m|. Same claim in the energy docstring | both docstrings corrected (`fd07d902`); the arithmetic kept identical to the energy follower's, the owner-approved design; a sign-restricted allocation (`|moved| ≤ |m|`) offered for both families |
| S3 | Under `increment` a residual pinned in a cell stays, and a draining cell's partition can go negative (toy: −0.1 while the parent holds 0.2), since normalized shares send the parent's whole flux | documented; the D4-W validation records the partition's minimum, the repair's throughput (WP6) and the bound activation; un-normalized clamped shares offered |
| S4 | No run exercises both families' hook; the ledger's restart guard untested | the integration test's tagged run carries energy source tags under `enthalpy_increment`; the guard tested both ways (`fd07d902`) |
| M1 | The parent's post-solve correction is exercised only indirectly | a cell-by-cell check with it (`fd07d902`) |
| M2 | ARS343, the parent-budget meters, Float32, the config refusal without tags untested | the config refusal tested; the others noted |
| M3 | No docs section | added |
| M4 | `string(::Symbol)` in the skip's predicate, 32 B per tracer and call | resolved at compile time for a `FieldName` |
| M5 | `q_tag_dtγ` is FT, the stepper's `dtγ` Float64 | harmless, as the energy follower's; noted |
| M6 | The skip and the hook are wired apart | the integrator refuses a stepper without the tags' hook |
| M7 | Under `dss` the constraints enter the mismatch | documented |
| M8 | First-order donor-share upwinding of provenance; `increment_moved_gross` dominated by advection | noted for the validation's per-tag comparison against the copies |
