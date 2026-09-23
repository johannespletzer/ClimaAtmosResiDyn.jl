# Rain and snow carry their own tags: the design note WP4b-D

Written on 2026-09-24 for G3's WP4b (G3_PLAN 4.5), which the owner added to
the session's goal that day. It proposes; it decides nothing. **The choice of
the prognostic fields is the owner's** (G3_TODO, Decisions). No code is written
before this note is reviewed by `clima-numerics-reviewer` (xhigh).

**What was read.** The WP3 branch `claude/water-tags-edmf-wp3` at `4a1c91a4`
(`file:line` references without a directory are there), WP5's branch
`claude/water-tags-edmf-wp5` at `1addf74c`, V-W0c and V-W3's outputs on
scratch (FINDINGS W18, W21), and the operator inventory of section 4, made by
`clima-inventory-explorer`.

**What was computed.** One number is new: section 2's time integral of the
exact leak diagnostic `q_tag_leak_vdiff` over V-W3's days. Everything else is
cited. Where a statement is an inference, it says so.

## 1. What the note must fix

G3_PLAN 4.5 lists it: the prognostic fields; every operator that moves the
parent's rain and snow, with `file:line`; the net-flow attribution between
non-precipitating water, rain and snow; the updraft's rain composition in the
default mode; sedimentation by the parent's flux split; the Jacobian entries;
the scratch the tags own; the audit's method; the cost. Section 2 adds what
V-W3 and WP5 changed about the question.

## 2. Why now, and what changed since the plan

The plan motivates the rain and snow tags by two things: precipitation
provenance (`pr_tag`), and the `q_tot_eff` leaks of 4.2, which they remove by
construction. Three measurements since then change the second argument's
weight. None changes the first.

  - **The leak's source is large; its imprint is small.** V-W3's default and
    copies days wrote the exact closed-form leak of the grid-scale vertical
    diffusion, `q_tag_leak_vdiff` (hourly means). Integrated in time level by
    level, the source it adds to the residual reaches 0.53% of the column's
    water at 12 h and 1.1% at 24 h (gross over the levels, the same in all
    four runs to 10%). W18's estimate from `edt`, 0.9%, is confirmed. Its net
    column total is below 1e-6, so the path is column-neutral. But the whole
    gross closure residual of the ten-Newton default day is 0.13% at 24 h, and
    of the copies 0.18% (W21). So the tags' own diffusion mixes out most of
    what the leak puts in, level by level, before it accumulates. *Inference:*
    the leak's imprint on the residual is at most those 0.13%, well inside the
    0.2% budget, while its source integral is 55 times 4.2's threshold (a
    tenth of the budget).
  - **4.2's rule measures the wrong thing.** It gives a path its correction
    "when its leak exceeds a tenth of the closure budget". Measured as the
    source integral, the vertical diffusion needs one on D4-W. Measured by its
    imprint on the residual, it may not. The note proposes to measure the
    imprint directly (section 9) and asks the owner to restate the rule.
  - **WP5 absorbs the implicit leaks.** Under `water_tag_transport: increment`
    the tags take the parent's implicit increment of `ρq_tot`. With
    `implicit_diffusion: true` the vertical diffusion is in that increment
    (`implicit_tendency.jl`, the `diff_mode == Implicit()` branch), and its
    leak is column-neutral, so the correction moves it and closure holds. The
    provenance of the leaked water is then the donor share of the cell the
    correction's flux leaves, not the composition of the rain that should not
    have diffused. The explicit paths (hyperdiffusion, the sponge, the
    updrafts' hyperdiffusion) stay outside the follower. So under WP5 closure
    stops showing the implicit leaks, and only a comparison of provenance can.

The consequence for the choice: closure alone no longer makes the rain and snow
tags necessary on the column. Provenance does: on a deep precipitating case
the rain falling through a level carries the composition of where it formed,
and the total-water tags give it the composition of each level it passes
(4.5, the principle). D4-W cannot show that (W18: its updraft holds under
0.01% of the rain, and there is no snow). V-W5 and V-W6's deep cases can.

## 3. The prognostic fields

**Recommended, as in the plan: three prognostic parts per tag.**

| field | holds | sums over the tags to |
|:----- |:----- |:--------------------- |
| `ρq_tag_<name>` | the tag's non-precipitating water `N`: vapour, cloud liquid, cloud ice | `ρq_tot − ρq_rai − ρq_sno` (the parent's `q_tot_eff`) |
| `ρq_rtag_<name>` | the tag's rain `R` | `ρq_rai` |
| `ρq_stag_<name>` | the tag's snow `S` | `ρq_sno` |

The tag's total water, `q_tag_<name>` in the output, is derived as the sum.
What that buys:

  - **Sedimentation is linear in each part.** A rain part falls with the
    parent's rain flux, `ρ wᵣ R/ρ`: the terminal velocity is the parent's,
    set by `ρq_rai`, and the part enters linearly. No share, no
    renormalization, no share derivative.
  - **Its Jacobian block is the parent species'.** The rain part's diagonal
    block is `ρq_rai`'s own sedimentation block, value for value. So the
    parts stay split-solvable (#76's `SplitJacobianSolver`), and a part's
    Newton update is the parent's for the same increment.
  - **The non-precipitating part diffuses as the parent.** The parent
    diffuses `q_tot_eff`, which is exactly `Σ N`. So each path of 4.2 moves
    `N` as the parent moves `q_tot_eff`, and the rain and snow parts as the
    parent moves rain and snow. The leaks vanish by construction, on both the
    implicit and the explicit paths.
  - **Cloud liquid and ice sediment too**, slowly (`fixed_terminal_velocity_liquid:
    false`). They stay inside `N`, which takes that flux by its donor share,
    as the tags take all sedimentation today (`sediment_water_tags!`). It is
    the only share-based term left, and the smallest.

**The cost of the choice.** With the key on, `ρq_tag_<name>` changes meaning,
from total to non-precipitating water. So the key is opt-in,
`water_tag_precipitation: true`, under 1M only, with a restart guard that
refuses a change (4.7). A run without the key is unchanged, bit for bit.

**The alternative: the total stays prognostic and the rain and snow parts are
added.** Then the non-precipitating part is the difference. A tag's rain
falls out of its total, so the total's sedimentation depends on the rain part:
an off-diagonal block between a tag's two fields, under stiff sedimentation
(rain Courant number about 12 on D4, 4.5). Without the block the total lags the
rain part in every Newton iteration, which is E59's mechanism again. With it,
the tags are no longer split-solvable one field at a time. The leaks stay,
since the total still diffuses on its whole value, and need WP4c.

**The recommendation stands:** three parts, `water_tag_precipitation` opt-in.
*For the owner:* the name change of `ρq_tag_<name>` under the key.

## 4. Every operator that moves rain and snow

From `clima-inventory-explorer`'s inventory of 2026-09-24 at `4a1c91a4`,
with three of its open points checked by hand (marked ✓). "Grid" is the grid
mean, "up" the updraft. `N`, `R`, `S` are a tag's three parts; `Nʲ`, `Rʲ`,
`Sʲ` their copies.

| # | operator | where (`file:line`) | path | Jacobian | parent's rain and snow | parent's `q_lcl`, `q_icl` | the parts follow by |
|:--|:---------|:--------------------|:-----|:---------|:-----------------------|:--------------------------|:--------------------|
| 1 | 1M sources, grid | `microphysics/tendency.jl:153-162` | implicit by default (`implicit_tendency.jl:69-76`), explicit `remaining_tendency.jl:230-238` | none | net `dq_rai_dt`, `dq_sno_dt` | net `dq_lcl_dt`, `dq_icl_dt` | the net-flow rule, section 5 |
| 2 | 1M sources, EDMF | `tendency.jl:164-191` | as 1 | none | env `ρa⁰`-weighted and updraft `ρaʲ`-weighted into the grid; the updraft's own `q_raiʲ`… unweighted (185-188) | the same | section 5 per subdomain; copies take the updraft's |
| 3 | sedimentation, grid | `implicit_tendency.jl:277-300`, with `water_advection.jl:41-118` for `ρ`, `ρq_tot`, `ρe_tot` | implicit, not gated by the microphysics path | `update_sedimentation_jacobian!`, `manual_sparse_jacobian.jl:1192-1267` | `ᶜprecipdivᵥ(ρ ᶠtop_bias(−wₛ qₛ))` | the same with `wₗ`, `wᵢ` | R, S: the same operator on the part, linear, the parent's block; N: its cloud condensate by share, as `sediment_water_tags!` today (`tagged_water.jl:558-618`) |
| 4 | sedimentation's energy correction, EDMF | `water_advection.jl:174-232` | implicit | none, by design (`manual_sparse_jacobian.jl:1246-1253`) | energy only | energy only | not needed: no water moves |
| 5 | sedimentation, updraft | `advection.jl:384-458`, `updraft_sedimentation!` `advection.jl:554` | implicit (`edmfx_sgs_vertical_advection_tendency!`) | `manual_sparse_jacobian.jl:1741-1806` | within the updraft, with the lateral term `α_lat` | the same | copies: the operator on `Rʲ`, `Sʲ` (linear); default mode: the parent's flux split by subdomain (section 6). Today's copies' block: `manual_sparse_jacobian.jl:1808-1840` |
| 6 | hyperdiffusion | `hyperdiffusion.jl:151-168`, `492-534` (grid), `199-215`, `551-621` (up) | explicit | none | **none**: excluded (`_microphysics_names`, 531-544) | a share of the `q_tot_eff` tendency by `clip(q/q_tot_eff)` | N: the generic operator on `N`, which is `q_tot_eff`'s part; R, S: none, as the parent |
| 7 | vertical diffusion, grid | `vertical_diffusion_boundary_layer.jl:105-146`, `ᶜdiffusing_water` `eddy_diffusion_closures.jl:926-938` | implicit when `diff_mode` is implicit (default) | the generic diffusion blocks (not traced) | **none** | a share of `q_tot_eff`'s | N: on `N`; R, S: none |
| 8 | EDMF diffusive flux, vertical | `edmfx_sgs_flux.jl:262-371` (`K_h` on `q_tot_eff`), `385-420` ✓ (every grid tracer: `α·K_h + K_e`, `α = 0` for microphysics species) | implicit with `diff_mode` | `manual_sparse_jacobian.jl:1877-1931`, `K_e` diagonal only | `K_e` only | `K_h` share of `q_tot_eff` plus `K_e` | N: `K_h + K_e`; R, S: `K_e` only. Today the tags take `K_h + K_e` on their whole value: that is the vertical leak |
| 9 | EDMF diffusive flux, updraft mirror | `edmfx_sgs_flux.jl:328-333`, `349-369` | implicit, with `edmfx_vertical_diffusion` | none beyond 8 | none | `K_h` share | copies: `Nʲ` as `q_totʲ`'s `q_tot_eff` part; `Rʲ`, `Sʲ`: none |
| 10 | EDMF diffusive flux, horizontal | `edmfx_sgs_flux.jl:444-571` | explicit, the sphere only | none | none | `q_tot_eff` share | N only |
| 11 | viscous sponge | `sponge/viscous_sponge.jl:166-222` | explicit | none | none | `q_tot_eff` share | N only |
| 12 | subsidence | `forcing/subsidence.jl:86-107` | explicit | none | **none** | first-order upwind | N only (as the tags today, through the bracket) |
| 13 | SGS mass flux | `edmfx_sgs_flux.jl:26-175` (every SGS tracer, 134-171) | implicit | mass-flux blocks (not traced) | `ρᵏaᵏ(u³ᵏ−u³)(χᵏ−χ)` | the same | default: each part by its share of the parent species' flux, as `sgs_mass_flux_of_water_tags!` does for the total; copies: the model's flux of `Rʲ`, `Sʲ` |
| 14 | entrainment and detrainment | `edmfx_entr_detr.jl:620-624` | implicit | `manual_sparse_jacobian.jl:1949-1990` | toward the environment's value | the same | copies: generic, as today's copies |
| 15 | grid constraints | `mass_flux_closures.jl:211-231` (floor at 0, rescale by `min(1, ρq_tot/Σρq_cond)`) | `constrain_state!` | none | clipped and rescaled | the same | R, S: rescaled by the parent's factor, the rest to N, then the partition repair per part |
| 16 | updraft constraints | `mass_flux_closures.jl:267-340` | `constrain_state!`, with the filter | none | floored, rescaled by `q_totʲ/q_cond` | the same | copies: as 15 per updraft, then the copies' repair per part |
| 17 | nonnegativity constraint | `constrain_state.jl:101-141` | `constrain_state!` | none | element-wise or vapour borrowing | the same | as 15 |
| 18 | nonnegativity tendency | `moisture_fixers.jl:74-105`, called ✓ `remaining_tendency.jl:309` | explicit | none | borrows from vapour | the same | the net-flow rule: vapour (N) gives its composition to the species it restores |
| 19 | file-based start | `overwrite_from_file.jl:288-332` | initialization | — | set from the file | the same | each part starts as the parent species times the tag's region mask (4.1's rebuild rule, per part) |
| 20 | analytic start | `prognostic_variables.jl:134-186`, `300-330` | initialization | — | set | set | as 19 |

**What the table shows.** Every operator that moves the parent's rain and snow
is linear in the species and has no `q_tot_eff` split: sedimentation, the
updraft's sedimentation, `K_e` diffusion, the mass flux and entrainment. So the
rain and snow parts follow each by the same operator on the part, and their
sums equal the parent's without a share. The nonlinear pieces are the
constraints (15-17) and the microphysics (1, 2, 18), where the parts need a
rule: a common factor per compartment for the constraints, the net-flow rule
for the microphysics. The `q_tot_eff` operators (6-11) touch only `N`, which is
what makes the leaks vanish.

**Open, from the inventory, for the review:** the Jacobian blocks of the
vertical diffusion (7) and the mass flux (13) were not traced line by line;
whether the tags are in `microphysics_tracer_names` (`utils/tracer_processes.jl:307`)
decides row 8's `α` for the new parts, and they must not be, except `R` and
`S`, which must be treated like the species.

## 5. Microphysics: the net-flow attribution

1M exposes one net tendency per species and subdomain: the grid mean's
`ᶜmp_tendency` without EDMF, the environment's `ᶜmp_tendency⁰` and each
updraft's `ᶜmp_tendencyʲs` with it (`microphysics/tendency.jl:153-191`). The
gross processes behind a net change (autoconversion, accretion, evaporation,
deposition, sublimation, melting) are not stored. So the three compartments
exchange by the net-flow donor rule of 4.5, in each subdomain and cell:

  - `ΔR = ρ·dq_rai_dt·Δt`-like increments, `ΔS` likewise, and
    `ΔN = −ΔR − ΔS`, since 1M conserves `q_tot` in the microphysics.
  - A compartment that loses gives its own composition: `−ΔX⁻ φᵢˣ`.
  - A compartment that gains takes the losers' compositions, weighted by
    their losses: `ΔX⁺ Σ_Y (ΔY⁻ φᵢʸ) / Σ_Y ΔY⁻`.

Each tag's three parts then change by amounts that sum to the parent's in
each compartment, and over the tags to zero net water. The rule is exact when
the flows in a cell and a step go one way. It is an approximation when rain
forms and evaporates in the same cell and step, or snow melts into rain that
evaporates. **The audit (section 8) bounds that error.**

**The rule runs inside the existing `:microphysics` bracket** on both paths
(`remaining_tendency.jl:234-252` explicit, `implicit_tendency.jl` implicit),
reading the tendency the parent wrote. Under 1M the parent's `ρq_tot` does not
change there (`check_water_tagging_supported`'s docstring), so today's
bracket attributes nothing; this is new work, not a change of it.

## 6. EDMF

**Default mode.** The rain and snow parts are grid-scale, as the tags are.

  - The updraft's rain and snow take the composition of the updraft's
    non-precipitating water from the plume, since they formed there. The plume
    already carries that composition (`sgs_exchange_of_water_tags!`, WP3). The
    environment's parts follow by subtraction, bounded as in the exchange.
  - Sedimentation uses the parent's own flux split by subdomain: the updraft's
    `ρʲaʲwᵣʲqᵣʲ` with the updraft's composition, and the rest with the
    environment's. The WP3 review showed that mass weighting gets this wrong
    when the updraft's rain falls faster.
  - The microphysics rule of section 5 runs per subdomain, the updraft's
    compartments from the plume and the environment's by subtraction.

**Copies mode.** The rain and snow parts get copies too, three per tag. Their
mirrors are those of WP3's copies (G3_PLAN 4.1), with the updraft's
sedimentation (`updraft_sedimentation!`) moving each copy's rain part
linearly, and the microphysics rule per updraft.

**Under WP5's follower.** The follower gives the partition the parent's
increment of `ρq_tot`. With three parts it becomes three followers: `N` follows
`ρq_tot − ρq_rai − ρq_sno`, `R` follows `ρq_rai` and `S` follows `ρq_sno`, each
with its own ledger. The rain part's own sedimentation block equals the
parent's, so for sedimentation the rain follower should find almost nothing;
it catches the rest of the implicit terms.

## 7. The Jacobian and the scratch

  - The rain and snow parts: the parent species' sedimentation block
    (`manual_sparse_jacobian.jl`, the sedimenting-tracer blocks), value for
    value. Split-solvable.
  - The non-precipitating part: its cloud condensate sedimentation by share,
    with the existing share-derivative block
    (`water_tag_sediment_dshare`), restricted to `ρq_lcl` and `ρq_icl`.
  - Scratch: one field per tag and part for the attribution's losses, the
    partition norms per compartment, and under EDMF the plume's values per
    part. It lives in `p.scratch` where the implicit tendency reads it with
    dual numbers, as today's snapshot does.

## 8. The audit of the net-flow rule

On a 1M column, from saved states at every output: recompute the gross 1M
process rates offline with CloudMicrophysics' own functions (autoconversion,
accretion, rain evaporation, snow deposition and sublimation, melting), with
the model's parameters. Attribute them process by process, each with its
donor's composition. Compare with the net-flow attribution the run applied,
per tag and part. Under EDMF the environment's rates come from the sub-grid
quadrature (`use_sgs_quadrature`); the offline audit evaluates the grid-mean
state of the environment instead, so there it bounds the rule's error only up
to the quadrature's effect, which is measured separately by switching the
quadrature off.

## 9. Measuring the leaks, and WP4c

Section 2 proposes to measure a leak by its imprint, not its source: two runs
on one atmosphere, one with the path's correction (WP4c's
`ρq_tagₜ −= ∇·(ρK∇(ψᵢ q_p))`, 4.2) and one without, and the difference of their
gross residuals and per-tag L1. With the rain and snow tags on, a third run
gives the exact answer, since there the leak is absent. WP4c's rule then reads
"a path gets its correction when its imprint on the residual at 24 h exceeds a
tenth of the budget". *For the owner.*

## 10. Cost

  - Fields: three per tag instead of one, and three copies per tag in copies
    mode. D4-W's five tags become fifteen fields.
  - Build: with #76's split solver the tags are solved apart, and 8 tags plus
    5 records added 45 s to the EDMF column's `get_simulation` (712 s without,
    757 s with; E44e). Fifteen split fields should add of the order of a
    minute. *An extrapolation.*
  - Step: 8 tags took the column from 13.8 to 14.7 ms a step (E44c). Fifteen
    fields, with the attribution and the per-subdomain sedimentation, should
    stay below twice the untagged cost. V-W10 measures it.

## 11. Staging and validation

 1. A 1M column without EDMF: the key, the three parts, sedimentation,
    microphysics, `pr_tag_*` with `Σ pr_tag = pr`, the restart guard, the
    audit script.
 2. EDMF, default mode.
 3. Copies.

Each stage is its own review (xhigh) and CI group. V-W5 runs them on the 1M
column and on D4-W in both modes; V-W6's deep cases show the updraft's
composition, which D4-W cannot.

## 12. For the owner

 1. The prognostic fields: three parts (recommended) or total plus two.
 2. Under the key, `ρq_tag_<name>` holds the non-precipitating water.
 3. 4.2's rule restated to measure a leak's imprint (section 9).
