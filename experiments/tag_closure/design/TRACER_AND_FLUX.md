# Tracer and flux: two ways to move the energy source tags

Written on 2026-09-19 for question 2 of the attribution path
([ATTRIBUTION_PATH.md](ATTRIBUTION_PATH.md), sections 3.2 to 3.5). It compares
the two conventions by what they assume, what they measure, and what a reader
may conclude from each. The numbers are from the D4 column (FINDINGS E59 to
E66).

## The two approaches

  - **Tracer.** Each tag moves like a passive constituent of the air, as a
    water-vapour tracer does. Advection and eddy diffusion act on each tag's own
    specific value, `ρe_src/ρ`. This is `energy_source_tag_transport: tracer`.
  - **Flux.** Each tag takes a share of the parent's own flux of
    `E = ρe_tot + c·ρ`, by its fraction of `E` in the cell the flux leaves (the
    donor). This is the `enthalpy` audit in advection and hyperdiffusion, C1b in
    the sub-grid mass flux, and C1c's option 1 in the eddy diffusion (the
    converged reference of E66).

The flux approach rebuilds the parent's fluxes in the tag code, from the same
operators and state. It does not read the parent-budget ledger
(`src/parent_budget`). That ledger is a separate, optional meter. It reads the
tags' settings to know which hooks exist, and nothing more.

## Where they differ, process by process

 1. **Resolved advection.** Both move provenance with the air, in the same
    direction.
      + The parent carries enthalpy, `h = e + p/ρ`. The flux approach carries it
        too, so it closes. The tracer approach carries `e`, so pressure work
        reaches no tag. Under `tracer` that was nearly all of the residual on a
        column and at least 93% on a sphere (E25, E31).
      + Numerically, the flux shares are first-order upwind, so region edges
        smear more than under the tracers' van Leer scheme.
 2. **Turbulent mixing.** Here the physics differs.
      + Turbulence exchanges parcels both ways. The net energy flux is the small
        difference of two large gross exchanges.
      + Tracer diffusion represents the gross exchange: provenance mixes even
        where no net energy flows.
      + The flux approach sees the net flux only. Where turbulence moves little
        net energy, provenance does not mix.
 3. **Updraft mass flux.** The flux approach shares the updraft's energy flux
    by the grid mean's shares, not by the updraft's own composition, because
    the tags have no updraft copy. Updrafts rooted at the surface carry surface
    air upward preferentially. Neither approach, as built, captures that.
 4. **Pressure work.** Only the flux form assigns it, to the provenance of the
    air that delivers the flow work. The tracer form leaves it in the residual.

## Advantages and disadvantages

|                      | Tracer                                                                                                                                                                   | Flux                                                                                                                                                     |
|:-------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Closure              | No. The form mismatches grow: the eddy diffusion's form was 44% of D4's residual (ATTRIBUTION_PATH.md, row 2), and on a sphere E60 projects at least 5% of `E` in a year | Yes, by construction, for every flux it shares                                                                                                           |
| Mixing of provenance | Physical: turbulence mixes composition                                                                                                                                   | None where the net flux is small                                                                                                                         |
| Numerics             | Each tag has its true Jacobian, so an implicit solve treats it consistently                                                                                              | Shares are nonlinear. Shared at the tendency level, a stiff implicit flux drifts, unless the solve converges or the tags follow the increment (E59, E61) |
| Pressure work        | Unattributed                                                                                                                                                             | Attributed to the donor's provenance                                                                                                                     |
| Region edges         | Sharper (van Leer)                                                                                                                                                       | Smeared (first-order upwind)                                                                                                                             |
| Negative tags        | Possible from higher-order transport, needs the repair                                                                                                                   | Not from upwind advection; still possible from centred hyperdiffusion (row 9)                                                                            |

## Where their results agree and disagree

The share of `E` attributed to the surface flux (`sfc`) and to the air that
began above the inversion (`strat`), on D4 at 24 h. "Flux" is
`g1_ref_newton10_d4`; "tracer mixing" is the prototype on the same atmosphere,
`g1_inc_newton10_d4`, whose tags diffuse as tracers.

| height              | `sfc`, flux | `sfc`, tracer mixing | `strat`, flux | `strat`, tracer mixing |
| -------------------:| -----------:| --------------------:| -------------:| ----------------------:|
| 25 m                | 89.5%       | 17.5%                | 0.0%          | 6.7%                   |
| 325 m               | 0.9%        | 16.2%                | 0.0%          | 6.8%                   |
| 625 m               | 0.0%        | 11.8%                | 3.8%          | 7.5%                   |
| 775 m (cloud top)   | 0.0%        | 9.3%                 | 23.1%         | 9.0%                   |
| 925 m (above cloud) | 0.0%        | 0.0%                 | 96.2%         | 95.9%                  |

  - **Inside the boundary layer they disagree strongly.** The flux approach
    keeps the surface's energy in the lowest cell, 90% of its `E`, and none of
    it above 300 m. The tracer approach spreads it through the boundary layer,
    about 17% everywhere. It also brings air from above the inversion down to
    the surface, 7%, which is what cloud-top entrainment does in a well-mixed
    stratocumulus layer. Pointwise the tags differ by 68 to 126% (E66).
  - **Above the boundary layer they agree:** 96% `strat` in both. No mixing
    happens there.
  - **Column totals agree broadly:** the surface's energy in the column differs
    by 2.4% at 24 h.
  - **Totals drift apart where a tag sits matters for its losses.** The loss
    rule takes energy from whatever is present where a loss happens. Cloud-top
    radiative cooling removes surface energy under tracer mixing, and not under
    the flux approach, where that energy stays low. After a day `sub` differs
    by 18% (E66). Over longer runs this grows.
  - **The process records agree exactly.** They are not transported, so they
    are the same under either convention and give a convention-free reference
    for totals.

## What this means for interpretation

  - **Robust under either convention:**
      + column- or region-integrated budgets over short times;
      + what lies above the boundary layer;
      + anything taken from the process records.
  - **Dependent on the convention:**
      + any local statement inside a turbulent layer. "x% of the near-surface
        energy came from the surface" is 90% under one convention and 17% under
        the other;
      + where energy is lost, and so the long-term totals of tags that sit where
        losses are fast or slow.
  - **What the flux approach answers:** which source's energy the net energy
    transport delivers. It is exact bookkeeping of net flows, but it
    understates mixing. So it overstates how long surface energy stays near the
    surface, and how well it is shielded from cloud-top losses.
  - **What the tracer approach answers:** what share of the air's energy
    content came from each source, if provenance mixes like a constituent. That
    is physically plausible, but the partition leaks. Its residual is energy no
    tag owns, and over long runs it is not small.

## The prototype between them

`energy_source_tag_transport: enthalpy_increment` keeps the tracer approach's
eddy diffusion of the tags, so it mixes like the tracer approach: its tags are
within 1.7% of the tracer base pointwise (E62). It adds the net mismatch as a
donor-shared flux, which gives the flux approach's closure. That mismatch is
mostly vertical advection, where the two approaches agree anyway. So the
prototype mixes like the tracer approach and closes like the flux approach.

## Recommendation, for the owner's decision

Take tracer-like mixing as the definition for turbulent exchange, as the
prototype does, and the flux form for resolved transport and pressure work.
The measurement that would settle the mixing question is V3
(ATTRIBUTION_PATH.md, section 5): a passive tracer with an updraft copy, set
to a surface source beside the tags. It shows how the air itself mixes
composition, and it would expose the updraft gap that neither approach closes
today.
