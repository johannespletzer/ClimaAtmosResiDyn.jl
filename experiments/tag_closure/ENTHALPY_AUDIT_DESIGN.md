# Moving the energy source tags as enthalpy: design for the audit switch

A design for the owner's OK, written on 2026-09-11. No model code is written.
The owner decided that the tags stay passive tracers by default, and that
enthalpy-form transport is an audit, switched on per run. After C6 the owner
approved building it once the sphere was measured, and asked for this design
first.

## Why

The tags' closure residual grows because the parent moves enthalpy, `h_tot`,
while the tags move energy as passive tracers. On the column, after its first
ten minutes, pressure work is the whole of that growth (FINDINGS E25). On the
sphere it is at least 93%. There the per-tag limiter is 2e-4 and hyperdiffusion
2.4% (E31).

With the switch on, transport adds nothing to `e_src_res` by construction. What
the residual still shows is then the attribution, the processes the tags do not
see, and the timing of the step. A pair of runs, switch off and on, on the same
atmosphere separates the two.

## What it changes

One config key, `energy_source_tag_transport`, which takes `tracer`, the
default, or `enthalpy`. It becomes a type parameter of `EnergySourceTaggingModel`.
So the choice folds away at compile time, and the default path stays today's
code.

Under `enthalpy`, three transport terms of the tags are replaced. Each shares
out the parent's own flux of `E = ρe_tot + c·ρ`, so the partition tags' fluxes
add up to the parent's.

| term | today, `tracer` | `enthalpy` |
|:-- |:-- |:-- |
| vertical advection, explicit (`advection.jl:249`) | `vertical_transport(ρ, u³, χₖ, dt, tracer_upwinding)` | the face flux `ᶠρ · scheme(u³, h_tot + c)` times the upwind cell's share `sₖ`, with the parent's `energy_q_tot_upwinding` |
| horizontal advection (`advection.jl:121`) | `-split_divₕ(ρu, χₖ)` | `-split_divₕ(ρu, sₖ (h_tot + c))` |
| hyperdiffusion (`hyperdiffusion.jl:527`) | `-ν₄ wdivₕ(ρ gradₕ ∇²χₖ)` | `-ν₄ wdivₕ(sₖ F_h)`, with `F_h` the parent's enthalpy hyperdiffusion flux |

  - **The shares** are sedimentation's. A partition tag's clamped fraction of
    `E` is divided by the partition's sum, so the shares add up to one. A tag
    with a source keeps its plain clamped fraction. `energy_source_share_norm!`
    already computes the denominator.
  - **Vertically** it shares the flux, not a specific value. The van Leer
    reconstruction is not linear, so moving each tag with its own van Leer
    would not sum to the parent's flux. Sharing the parent's face flux by the
    upwind cell's shares keeps the sum exact at every face. A constant passes
    through van Leer unchanged, so the scheme applied to `h_tot + c` is the
    parent's flux of `ρe_tot` plus `c` times its mass flux.
  - **Horizontally** `split_divₕ` is linear in the value it moves. So moving each
    tag with `sₖ (h_tot + c)` sums to the parent's `h_tot` term plus `c` times
    the mass term, exactly.
  - **Hyperdiffusion.** The parent's flux is a vector at cell centers before
    `wdivₕ` takes its divergence, so each tag takes it times its share. `ρ` is
    not hyperdiffused, so `c` adds nothing here.
  - **The cost of exactness.** The shares are taken from the upwind cell, first
    order, so a region's edge smears more than under van Leer. For an audit that
    is acceptable, because the question it answers is closure, not sharpness.

## What it does not change

  - The default. `tracer` is today's code.
  - The model. The tags never act on it, so its state is bit for bit the same
    with the switch on and off. A test asserts that.
  - Everything else the tags see: the brackets, the repair, sedimentation, which
    already shares a flux, vertical diffusion, the sponge and the SGS closures.
    Those stay in tracer form. The transport ledger keeps them in `other`, so
    they are measured, not removed.
  - The Jacobian. The tags' vertical transport is explicit today and stays so.

## What is left in the residual by design

The parent moves `ρe_tot` vertically in the implicit step, with the upwind
correction after the Newton solve. The tags move explicitly, at the stage state.
So their fluxes add up to the parent's flux at the explicit state, not at the
solved one. That timing gap is bounded. The ledger's `unexplained`, 1.4% on the
column and 5.3% on the sphere, is of the same kind, and the ledger would measure
it with the switch on.

## Tests

  - **Unit:** the upwind share at a face, by the sign of `u³`, with exact zeros on
    a step partition, as for sedimentation.
  - **Integration, the DYCOMS column with an offset.** Under `enthalpy`, the
    partition's vertical tendency equals the parent's vertical transport of `E`
    at the same state, to 100 eps. The model's state is the same with the switch
    on and off. That costs one more compile.
  - **Integration, a small sphere** (`h_elem` 2). The horizontal and
    hyperdiffusion sums, each to 100 eps. That costs another compile, about four
    minutes.

## Runs, each needing its own approval

  - **C9, column:** `c6_column_no_repair` with `enthalpy`, a day. Pressure work
    is the whole of the column's residual growth (E25), so the gross residual
    should fall by about that much.
  - **C9, sphere:** `c7_sphere_mp` with `enthalpy`, a day, with `ta` checked
    against C7's.

## Size

About 250 lines of model code with docstrings, and 200 of tests. That is an
estimate. The agent's was 500 and 300, for a design that also carried a
Jacobian block.

## Decisions for the owner

 1. The key and its values: `energy_source_tag_transport: tracer | enthalpy`.
 2. Without an offset, the shares are zero wherever `E` is not positive, and
    there the tags would not move. Refuse `enthalpy` without an offset at
    configuration time, or warn and run.
 3. Scope: vertical and horizontal advection and hyperdiffusion, or advection
    only.
 4. The vertical reconstruction: the parent's `energy_q_tot_upwinding`, which is
    what "moving like the parent" means, or the tags' own `tracer_upwinding`.

**Decided on 2026-09-11.** The owner took all four as proposed:

  - the key is `energy_source_tag_transport`, `tracer` by default or `enthalpy`;
  - `enthalpy` without `energy_source_tag_offset` is refused at configuration;
  - the switch replaces vertical and horizontal advection and hyperdiffusion;
  - the vertical flux uses the parent's `energy_q_tot_upwinding`.
