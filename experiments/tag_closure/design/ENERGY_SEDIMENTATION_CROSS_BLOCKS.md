# The energy source tags' sedimentation cross blocks: the design note of G4.16

Written on 2026-09-24, before any run. It reuses the water tags' design
(`SEDIMENTATION_CROSS_BLOCKS.md`, #105) for the energy source tags. The code is
on `claude/energy-tags-sed-cross`, branched from `claude/water-tags-sed-cross`
(#105) at `464f6fd0`. `file:line` references are to that branch.

## 1. The lag

With 1M microphysics, the parent's implicit sedimentation has a cross block
from `ρe_tot` to each falling species `ρqₚ`, and one from `ρ`
(`update_sedimentation_jacobian!`). Each energy tag falls with its share of
the same energy flux (`sediment_energy_source_tags!`). Before G4.16 the tags'
rows had no block for it. So one Newton iteration moved the parent with the
updated species and the tags with the old ones. The part of that gap that
leaves through the surface changes the column's total, and the follower
cannot move it.

E80 measured it on W23's column under `enthalpy_increment`: 2.1e-4 of the
energy in an hour, with the microphysics explicit and one Newton iteration;
1.5e-6 with it implicit; 4.9e-12 with ten iterations. The guard (#108)
refuses `enthalpy_increment` with 1M, 2M or P3 stepped explicitly until G4.16
passes.

## 2. The blocks

A tag's tendency, for one species, is the divergence of its share of the
face flux of the offset total `E = ρe_tot + c·ρ`:

    (ρe_srcᵢ)ₜ = -precipdivᵥ(ᶠρ · ᶠsᵢ · ᶠtop_bias(-wₚ qₚ (hₚ + c))),

with `hₚ = e_int(T) + Φ + K`. `ᶠsᵢ` is the face's share: the cell above's, or,
on an interior face where the flux points up, the cell below's. The flux
points up where `hₚ + c < 0`. That is the case for ice and snow: near
freezing they carry about −3.3e5 J/kg, below `−c` even with the offset
(110495 J/kg). So their tags take the cell below's shares on interior faces.

Its derivative in `ρqₚ`, at fixed shares, `T` and velocities, is

    ∂(ρe_srcᵢ)ₜ/∂ρqₚ = B · Diag(ᶠsᵢ) · ᶠtop_bias · Diag(WVector(-wₚ (hₚ + c) / ρ)),

with `B = p.scratch.ᶜbidiagonal_adjoint_matrix_c3`, the matrix the parent's
blocks use (`update_energy_source_sedimentation_block!`).

**The offset.** The shares are fractions of `E`, not of `ρe_tot`. So the flux
the tags share carries `c` per unit of falling mass, and the tags' blocks are
shares of the block of `E`, not of `ρe_tot`'s. Over a closed partition the
shares add up to one on every face, whichever cell they come from. So the
partition's blocks add up to the parent's `ρe_tot` block plus `c` times its
`ρ` block. Without that `c`, the blocks would miss `c·Δρ` at the surface
outflow, and the column total would lag by `c` times the mass that leaves.

A source tag's share is its own clamped fraction, as in the tendency. The
tags keep no diagonal block of their own for sedimentation, as before. Their
diagonal is the diffusion's, or the fallback identity.

## 3. The solve

As for the water tags (#105, section 3). The tags' rows name only coupled
columns, and no other row names a tag. So the split solver solves the coupled
fields first, unchanged, and then each tag by back-substitution,
`R_tag − Σₚ C_tag,ₚ ΔYₚ`. The parent's `ΔY` is the same computation, bit for
bit. The blocks are allocated only with the split (`water_tag_cross_flag`,
from `split_uncoupled_fields`), for #105's reason B1. `jacobian_cache` refuses
a state in which another row names an energy tag that has these blocks.

The share norm is a scratch field that the tendency rebuilds before it uses
it. The Jacobian update rebuilds it for the Jacobian's state. No tendency reads
it without rebuilding it first (`water_advection.jl:70`).

## 4. What stays out

The same as the parent's block and the water tags':

  - the shares' own dependence on the state, and `e_int`'s on `T`;
  - under prognostic EDMF, the subdomain corrections, which the tendency adds
    explicitly. There the tendency takes the face's share by the direction of
    the whole flux, corrections included, and the block by the grid mean's.
    Over a closed partition both sum to the same block of `E`, so the
    column's total is not affected; only a single tag's increment is.

These are convergence-rate approximations. They do not change what is solved.

## 5. Tests on the branch

In `test/energy_source_tags_tests.jl`:

  - **The blocks, assembled.** On a 16-level column with the four masses, two
    partition tags and a source tag, in Float32 and Float64, with and without
    the offset, on a drifted partition (so the shares are renormalized):
    each tag's block against a finite difference of the tags' real tendency
    (`_sediment_energy_source_tags!`), to 1000 eps; the partition's blocks
    against the parent's `ρe_tot` block plus `c` times its `ρ` block, to 100
    eps; the upward branch runs exactly when there is no offset.
  - **Only with the split.** The cross blocks are in the split form's block
    list and not in the unsplit one's, and the tags get no diagonal from
    sedimentation.
  - The back-substitution itself is #105's unit test, which does not depend on
    the field's kind.

## 6. The validation, pre-registered

Registered on 2026-09-24, before any run. Nothing below is changed after the
runs.

**Code.** Two run trees, each the record branch merged with code:

  - *on*: `claude/plan-rev2` + `claude/energy-tags-sed-cross` + the guard
    (`claude/energy-explicit-1m-guard`);
  - *off*: `claude/plan-rev2` + `claude/water-tags-sed-cross` (#105) + the
    guard.

**Runs.** Nine, in `configs/g416_*.yml`:

| case    | what                                                                                                                                             | on      | off      | untagged twin |
|:------- |:------------------------------------------------------------------------------------------------------------------------------------------------ |:------- |:-------- |:------------- |
| expl_n1 | E80's: W23's column, 1M explicit, one Newton iteration, an hour, `strat`, `tropo`, `sfc` under `enthalpy_increment`, with the guard's opt-in key | on tree | off tree | on tree       |
| impl_n1 | the same, 1M implicit, without the key                                                                                                           | on tree | off tree | on tree       |
| d4      | G4.15's D4 day (`g415_inc_d4_after`), eight tags, 1M implicit                                                                                    | on tree | off tree | on tree       |

Every run writes the model's own fields every 10 minutes (hourly in the day)
for parity: `rhoa`, `ta`, `hus`, `clw`, `cli`, `husra`, `hussn`, `wa`,
precipitation and surface fluxes, the updraft's fields and the TKE.

**Measures.** The energy closure (`energy_source_tag_closure.csv`), net and
gross relative, at the last output. Parity with `analysis/increment/ g416_compare.py`, which compares bit patterns.

**Bands.**

| check | what                                                                         | pass                             |
|:----- |:---------------------------------------------------------------------------- |:-------------------------------- |
| V1    | expl_n1, on: the gross closure at 1 h                                        | ≤ 1e-7 (from E80's 2.1e-4)       |
| V1c   | expl_n1, off: the control reproduces E80                                     | gross within 10% of 2.1e-4       |
| V2    | impl_n1, on, against off                                                     | on ≤ max(off, 1e-7)              |
| V3    | the explicit hour with the blocks against the implicit hour without them     | expl on ≤ impl off (E80: 1.5e-6) |
| V4    | d4, on, against off, at 24 h                                                 | on ≤ max(off, 1e-7)              |
| P1    | every model field of each tagged run against its untagged twin, every output | bit for bit                      |
| P2    | on against off, every field but `e_src_*`                                    | bit for bit                      |

V1's levels:

  - gross ≤ 1e-7: pass. The water tags' blocks reached 5.7e-8 on this column
    (W29), with a remainder from the share's diagonal, which the energy tags
    do not have.
  - 1e-7 < gross ≤ 1e-6: partial. The blocks work, and a remainder stays. It is
    decomposed with the follower's ledgers (`e_src_inc_left`,
    `e_src_inc_moved`) before any claim. One candidate: the arrowhead solve's
    two iterations leave a residual in the parent's rows that the tags' exact
    back-substitution does not share.
  - gross > 1e-6: fail. The guard stays, and the blocks are checked against
    the model's own tendency on the column.

If V1c fails, the control has moved since E80, and nothing is read from V1
until that is explained.

**What passing lifts.** With V1, P1 and P2 passed, the guard (#108) may be
lifted for 1M, in a PR of its own. 2M and P3 are not measured here. They
stay refused until measured (the owner's decision of 2026-09-24).

**Jobs.** `hpda2_compute`, 2 CPUs, 48 GB. The hour runs took 32 minutes
(E80), the day 35 minutes (G4.15). From each run tree's root:

    env CONFIG=experiments/tag_closure/configs/<job>.yml \
        DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl \
        experiments/tag_closure/runscripts/submit_g3.sh \
            --account=hpda-c --partition=hpda2_compute --time=02:00:00 \
            --cpus-per-task=2 --mem=48G \
            --output=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.out \
            --error=/dss/dsstbyfs02/scratch/0D/di38kez/tag_closure/logs/%x-%j.err

with `<job>` `g416_{expl_n1,impl_n1,d4}_{on,untagged}` from the on tree and
`g416_{expl_n1,impl_n1,d4}_off` from the off tree, and `--time=04:00:00` for
the day. Then `python3 analysis/increment/g416_compare.py`.

## 7. Open points

  - **Copies.** The energy copies (`energy_source_tag_updraft_copy: true`) are
    updraft fields in the coupled system. Their cross blocks to the updraft's
    species are a second step, as WP5b-C was for water (#111).
  - **Memory.** Each tag adds four tridiagonal blocks under 1M, as #105's N2.
    Deferred with it to WP9.
  - **2M and P3.** The blocks are built for the masses
    `sedimenting_mass_names` lists, the four of 1M, which 2M has too. The
    parent's blocks cover the same list. Neither 2M nor P3 is measured here.
