# The updraft gap

Written on 2026-09-19, to prepare the reading of V2 (G2). It is the sub-grid
mass flux's counterpart of the mixing question in
[TRACER_AND_FLUX.md](TRACER_AND_FLUX.md), and it belongs to step 4(b) of the
attribution path ([ATTRIBUTION_PATH.md](ATTRIBUTION_PATH.md)). It is a question
of correctness, not of closure.

## What it is

Under `prognostic_edmfx` the energy source tags have no copy in the updraft.
So `sgs_mass_flux_of_energy_source_tags!` (C1b) rebuilds the parent's sub-grid
flux of `E`, for the updraft and for the environment. At each face it gives
every tag the share it has in the cell the flux leaves. The function's
docstring says it: "A tag's composition in an updraft is taken as that of the
cell it leaves. So the flux moves the energy convection carries, but it does
not mix provenance the way it mixes the air."

With the mass flux `M = ρaʲ(wʲ − w̄)`:

  - the parent moves `M·(hʲ − h̄)`, the updraft's excess;
  - with an updraft copy, tag `k` would move `M·(φʲ_k·Eʲ − φ̄_k·Ē)`, with `φʲ_k`
    its share of the updraft's own energy;
  - as built, tag `k` moves `φ̄_k(donor)·M·(Eʲ − Ē)`;
  - the difference is about `M·(φʲ_k − φ̄_k)·Eʲ` per tag.

## Why it is large and yet invisible

  - **It sums to zero over the tags,** because the shares add up to one. So the
    closure, `e_src_res` and the prototype's ledger never see it.
  - **It is gross exchange against net flux.** The updraft lifts air and the
    environment sinks to compensate. Air of different provenance swaps places,
    each with its whole energy content: about 66 kJ/kg on D4 with the offset,
    about 83 kJ/kg on V2's sphere. The net energy flux carries only the excess,
    1 to 10 kJ/kg. So the provenance the exchange moves is roughly 10 to 80
    times what the net flux moves. This is an estimate.
  - **In shares it is an exchange of mass.** It moves shares at the rate `M`, as
    a passive tracer's mixing ratio would move. That does not depend on the
    offset `c`.
  - **It is non-local.** An updraft takes the surface layer's composition to
    cloud base, or higher in deep convection, in one pass. Local eddy diffusion
    does not. On V2's sphere in its first days the tropical updrafts end at 1.8
    to 2.6 km, so there the gap acts in the lowest few kilometres.

## How it meets the prototype

  - The prototype's correction fixes only the net mismatch. The tags' own tracer
    diffusion mixes provenance locally.
  - In D4's shallow boundary layer, that local mixing largely hides the gap by
    24 h: the surface's energy is spread evenly, about 17% from the surface to
    cloud top (E66).
  - Early on the gap shows. At 6 h under the base, the `sfc` tag fell 4.8 times
    between 25 m and 275 m while the air was well mixed (ATTRIBUTION_PATH.md,
    summary).
  - It shows most where the mass flux dominates the eddy diffusion: in cumulus
    layers, in deep convection, and above the boundary layer. On V2's sphere,
    90 to 93% of the tropical area turns over the air below its updraft's top
    within a day in the first four days, and 61 to 75% after. Outside the
    tropics the share grows from 2 to 4% to 20 to 43% (E72).
  - It is measured on D4 by V3 (FINDINGS E68): 58 points of share at the
    inversion after an hour, and about 3 points through the boundary layer
    after a day.

## What to expect in V2

  - **Affected:**
      + where the surface's energy sits: too much of it low in convective regions,
        too little in the middle and upper troposphere;
      + through the loss rule, which takes energy from what is present where a
        loss happens: radiative cooling aloft removes region and initial tags
        instead, so `sfc` and the `new_*` tags stay longer. Their ten-day
        integrals come out too large;
      + region tags aloft in convective regions, whose shares come out too large.
  - **Not affected:**
      + V2's closure and residual;
      + the process records;
      + the horizontal split between `tropics` and `extratropics`, except through
        the loss effect above;
      + the converged twin, which has the same convention and so cannot measure
        this either.
  - V2's per-tag results should therefore state their convention: tracer eddy
    diffusion, and the donor cell's shares for the mass flux.

## How to measure it

 1. **An estimate from V2's daily checkpoints** (`updraft_gap_estimate.jl`;
    reviewed, `review/agent_reviews/updraft_gap_bound/`). It gives the initial
    rate at which a copy would diverge, not a bound, and it cannot be added up
    over days. The checkpoints hold the whole state, including the updraft's
    `ρa`, `u₃`, `mse` and `q_tot`. Per column:

      + the mass flux `M(z)`, and the turnover time `ρH/M`;
      + the fraction `f(z)` of surface air left in the updraft, from the mixing
        line of a conserved variable (`q_tot` or `mse`);
      + an updraft share estimated as `φʲ ≈ f·φ(surface layer) + (1 − f)·φ̄(z)`,
        and from it the gap's share tendency, set against the tags' own.

    The face value is bracketed, upwind and centred as the model's own flux,
    and they differ by a factor of 2 to 4 with updrafts two to four cells deep.

 2. **V3 on D4, which measures it without model code** (ran on 2026-09-19;
    FINDINGS E68).
    `chemistry_model: passive` already carries `q_gas_A` with an updraft copy.
    A driver script sets its initial value to the `tropo` mask. The ratio
    `ψ = tropo/(tropo + strat)` changes by transport, mixing and the repair,
    and also by new energy, which the region tags take by their mask. So
    `ψ − q_gas_A` is the updraft gap plus that attribution (FINDINGS E68,
    erratum). The gap alone is the tags without copies against the tags with
    them (E73). One column job, approved by the owner.

## Ways to close it

 1. **Updraft copies of the tags.** Exact, and it mixes like the air. It costs
    one updraft field per tag, the entrainment and detrainment of each, the
    partition of the updraft's `E` kept closed, and build time (E44).
 2. **Share the updraft's flux by the shares where it starts,** for example the
    surface layer's. Cheap and closing, but approximate.
 3. **A zero-sum exchange of shares at the rate `M`** between levels (step
    4(b)'s `X_k`). Cheap and closing; it approximates the cycle of updraft and
    compensating subsidence.

Order followed: the estimate from V2's checkpoints, then V3, approved by the
owner. If the gap matters at the sphere's scale, option 1 is the principled
fix and option 3 the pragmatic one.

## The chosen way (the owner, 2026-09-19)

One logical switches between two ways, on branch
`claude/energy-source-tag-updraft` (worktree `../ClimaAtmosResiDyn-upd`):

  - **Audit mode: updraft copies of the tags.** Each tag gets a specific copy
    in every updraft, `sgsʲs.e_src_<tag>`. Any scalar there that is not `ρa`,
    `mse` or `q_tot` is already a passive SGS tracer to the model. So the
    copies get the model's own treatment: implicit advection by the updraft,
    entrainment of the environment's value, the sponge, the limiter, and the
    difference-form SGS flux `Σₖ ρᵏaᵏ(u³ᵏ − u³)(εᵏ − ε̄)` on the grid-mean tag.
    C1b's donor-share flux is then switched off, so nothing counts twice.
    Every EDMF term runs in the implicit tendency, so under
    `enthalpy_increment` the correction closes the sum after each solve. The
    mode refuses `enthalpy`, which has no correction. It measures the gap
    exactly under the hybrid convention: tracer-like exchange, and the
    parent's net flux.
  - **Default mode: a zero-sum exchange.** No new state. C1b stays, and each
    tag also takes `X_i = Σₖ Mᵏ (φᵏ_i − φ̄_i) Aᵏ` at the faces, with
    `Aᵏ = e_totᵏ + c` the subdomain's energy content. The shares sum to one in
    every subdomain, so `Σᵢ X_i = 0` and closure is untouched under every
    transport. The updraft's shares `φʲ` come from a steady entraining plume,
    marched up each column with the model's own entrainment:
    `εʲ(k) = (εʲ(k−1) + λ ε⁰(k)) / (1 + λ)`, `λ = (ε_entr + ε_turb) Δz / wʲ`,
    in specific tag contents, then normalised. The plume restarts from the
    environment where the updraft is absent. It is non-local like the updraft,
    which a local exchange between adjacent levels would not be (E72).
  - **What each approximates.** The copies ignore that the surface's buoyant
    air, injected at the lowest level, carries surface-flux energy; they take
    the environment's composition there. The plume adds the steady-state
    assumption: it is exact when the updraft adjusts faster than the shares
    change.
  - **The test:** D4 with both modes, set against each other and against V3's
    passive tracer. Then criterion 4's threshold is asked again.
