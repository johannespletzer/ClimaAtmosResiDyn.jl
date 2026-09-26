# Rain and snow carry their own tags: the design note WP4b-D

Written on 2026-09-24 for G3's WP4b (G3_PLAN 4.5), which the owner added to
the session's goal that day. **Second version**, after its review by
`clima-numerics-reviewer` (xhigh,
[review/agent_reviews/wp4b_d_design_review_2026-09-24.md](../review/agent_reviews/wp4b_d_design_review_2026-09-24.md));
section 14 says how each point was taken. It proposes; it decides nothing.
**The choice of the prognostic fields is the owner's** (G3_TODO, Decisions),
and so are the points of section 15. No WP4b code is written before that.
*Decided 2026-09-25 (DECISIONS.md):* points 1 to 3 as proposed, the three
parts, `ρq_tag_<name>` the non-precipitating water, beside `ρq_rtag_<name>`
and `ρq_stag_<name>`, behind `water_tag_precipitation: true`, 1M only, the
gross flows with the net-flow rule as the fallback. Point 4 is superseded by
rev. 2's WP4c gate (`design/WP4C_GATE.md`).

**What was read.** WP3 at `4a1c91a4` (`file:line` references without a
directory are there), WP5 at `1addf74c`, V-W0c and V-W3's outputs (FINDINGS
W18, W21), the operator inventory of `clima-inventory-explorer` and the
review's additions.

## 1. What the note fixes

G3_PLAN 4.5: the prognostic fields; every operator that moves rain and snow,
with `file:line`; the attribution between non-precipitating water, rain and
snow; the updraft's rain in the default mode; sedimentation; the Jacobian;
the scratch; the audit; the cost. The review added: the name predicates (5),
the denominators (6), the constraints (8), `pr_tag` (10) and the restart guard
(11).

## 2. Why now: the leak, measured

The plan motivates the rain and snow tags by precipitation provenance and by
the `q_tot_eff` leaks of 4.2. V-W3 wrote the exact closed-form leak of the
grid-scale vertical diffusion, `q_tag_leak_vdiff`. Integrated in time level by
level, the source it adds reaches 0.44–0.46% of the column's water at 12 h and
1.07–1.14% at 24 h, confirming W18's 0.9%. Its net column total is about 1e-6,
so the path is column-neutral.

**The source is not the imprint.** The residual `e = ρq_tot − Σ ρq_tagᵢ`
obeys, for this path, `∂ₜe = D_{Kh+Ke}(e/ρ) + D_{Kh}(q_p)`, with `q_p` the rain
and snow. So in the mixed layer `e/ρ` settles near `c − q_p` for a constant `c`,
and the imprint saturates at about `∫_ML ρ |q_p − c| dz`, while the source
integral grows without bound (the reviewer's 1-D toy: a source of 1.9% a day
against a residual of 2e-5). On D4-W that estimate is 5.0e-5 to 8.4e-5 of the
column's water, largest at 3 h, and at most 7.3e-4 with a whole-column mean.
*An estimate from hourly outputs, by the reviewer; not a measurement of the
imprint.* The whole gross residual of the ten-Newton default day, 0.13% at
24 h (W21), is consistent with it, but a gross residual cannot bound one of its
parts.

**It scales with the rain in the mixed layer.** D4-W's rain water path is
about 4e-4 of its column's water; on deep cases it is about 1e-2. So the
imprint on V-W5 and V-W6's deep cases may be 25 times D4-W's, and D4-W's
smallness does not carry over.

**WP5 absorbs the implicit, column-neutral part.** Under `water_tag_transport: increment` with `implicit_diffusion: true` (D4-W sets it; the default is
explicit, `types.jl:1907`) the vertical diffusion is in the parent's implicit
increment and its leak is moved by the correction, so closure stops showing it.
The leaked water's provenance is then the donor share of the cell the
correction's flux leaves. The explicit paths stay outside the follower.

**Consequence.** Closure alone does not make the rain and snow tags necessary
on D4-W. Provenance does, and on the deep cases the leak's imprint may too.

## 3. The prognostic fields

**Recommended: three parts per tag.**

| field                  | holds                           | sums over the partition to               |
|:---------------------- |:------------------------------- |:---------------------------------------- |
| `ρq_tag_<name>` (`N`)  | vapour, cloud liquid, cloud ice | `ρq_tot − ρq_rai − ρq_sno` (`q_tot_eff`) |
| `ρq_rtag_<name>` (`R`) | rain                            | `ρq_rai`                                 |
| `ρq_stag_<name>` (`S`) | snow                            | `ρq_sno`                                 |

The tag's total water `q_tag_<name>` is derived for output. What it buys:

  - Rain and snow sediment linearly in the part, by the parent's operator; the
    part's Jacobian diagonal is the parent species', value for value, so the
    parts stay split-solvable (on the grid; section 7 for the copies).
  - `N` diffuses as the parent's `q_tot_eff` on the paths that split it
    (section 4), so those leaks vanish. **Not every leak vanishes:** the
    hyperdiffusion (grid and updraft) acts on `q_tot_eff − q_tot_r(p)`, a
    reference profile (`hyperdiffusion.jl:151-165, 199-215`; WP3's diagnostic
    includes it, `tagged_water_leaks.jl:148, 198`). The exact correction is
    `Nᵢ` hyperdiffused as `∇²(Nᵢ/ρ − φᵢ q_tot_r)`, with `φᵢ` summing to one.
  - The explicit advection under the default `vanleer_limiter` is nonlinear
    per field, so `ΣRᵢ` drifts from `ρq_rai` as the total drifts today. Each
    compartment gets its own repair and residual diagnostic (`q_rtag_res`,
    `q_stag_res`).

**The cost.** Under the key `ρq_tag_<name>` holds `N`, not the total, so the
key is opt-in: `water_tag_precipitation: true`, 1M only, refused otherwise
(4.8), with the restart guard of section 11.

**The alternative** keeps the total `Tᵢ` prognostic and adds `Rᵢ`, `Sᵢ`. It
need not keep the leaks: it can diffuse `Tᵢ − Rᵢ − Sᵢ`. Its cost is the
coupling of `Tᵢ` to `Rᵢ` and `Sᵢ` in the Jacobian under stiff sedimentation
(rain Courant number about 12 on D4): a tag is no longer solvable one field at
a time, or it lags (E59). **The recommendation stands:** three parts.

## 4. Every operator that moves rain and snow

From the inventory at `4a1c91a4`, corrected and completed by the review. "N
follows" means the operator acts on `N` as on the parent's `q_tot_eff` part;
"R, S follow" means the same operator on the part.

| #  | operator                                   | where                                                                                                                                      | path                                                                                           | Jacobian                                                               | parent's rain, snow                             | parent's cloud                                        | the parts                                                                                                          |
|:-- |:------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------ |:---------------------------------------------------------------------------------------------- |:---------------------------------------------------------------------- |:----------------------------------------------- |:----------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------ |
| 1  | 1M sources, grid                           | `microphysics/tendency.jl:153-162`                                                                                                         | implicit by default (`implicit_tendency.jl:69-76`), explicit (`remaining_tendency.jl:234-252`) | none; rates frozen in the solve (`microphysics_cache.jl:731-748`)      | net `dq_rai_dt`, `dq_sno_dt`                    | net `dq_lcl_dt`, `dq_icl_dt`                          | the net-flow rule (9)                                                                                              |
| 2  | 1M sources, EDMF                           | `tendency.jl:164-191`                                                                                                                      | as 1                                                                                           | none                                                                   | per subdomain, updraft's own `q_raiʲ` (185-188) | the same                                              | 9, per subdomain                                                                                                   |
| 3  | grid-scale advection                       | `advection.jl:121-127` (horizontal), `253-262` (vertical, explicit tracers); `ρq_tot` vertically implicit (`implicit_tendency.jl:263-269`) | explicit for species and tags                                                                  | none for tracers                                                       | `vertical_transport` with `tracer_upwinding`    | the same                                              | R, S follow; N: section 6                                                                                          |
| 4  | updraft advection                          | `advection.jl:130-144, 373-382`                                                                                                            | explicit / implicit as the updraft's scalars                                                   | updraft blocks                                                         | the updraft's `q_raiʲ`                          | the same                                              | copies follow                                                                                                      |
| 5  | sedimentation, grid                        | `implicit_tendency.jl:277-300`; `water_advection.jl:41-136` for `ρ`, `ρq_tot`, `ρe_tot`                                                    | implicit                                                                                       | `update_sedimentation_jacobian!` `manual_sparse_jacobian.jl:1192-1267` | `ᶜprecipdivᵥ(ρ ᶠtop_bias(−wₛ qₛ))`              | the same with `wₗ`, `wᵢ`                              | R, S follow, the parent's block; N: its cloud by share                                                             |
| 6  | sedimentation's energy correction, EDMF    | `water_advection.jl:137-215`                                                                                                               | implicit                                                                                       | none by design (1246-1253)                                             | energy only                                     | energy only                                           | nothing                                                                                                            |
| 7  | sedimentation, updraft                     | `advection.jl:384-458`, `updraft_sedimentation!` 554-580 (lateral inflow 421-424)                                                          | implicit                                                                                       | `manual_sparse_jacobian.jl:1741-1806`                                  | within the updraft, lateral term `α_lat`        | the same                                              | copies follow linearly; default mode: section 7                                                                    |
| 8  | hyperdiffusion                             | `hyperdiffusion.jl:151-168, 492-534` (grid), `199-215, 551-621` (up)                                                                       | explicit                                                                                       | none                                                                   | **none** (`_microphysics_names`, 531-544)       | share of `q_tot_eff − q_tot_r` by `clip(q/q_tot_eff)` | N: the exact form of section 3; R, S: none                                                                         |
| 9  | vertical diffusion, grid                   | `vertical_diffusion_boundary_layer.jl:105-154`, `ᶜdiffusing_water` `eddy_diffusion_closures.jl:926-938`                                    | implicit with `diff_mode: Implicit` (not the default)                                          | generic diffusion blocks `manual_sparse_jacobian.jl:211-255`           | **none**                                        | share of `q_tot_eff`                                  | N follows; R, S none                                                                                               |
| 10 | EDMF diffusive flux, vertical              | `edmfx_sgs_flux.jl:262-371` (K_h on `q_tot_eff`), `385-420` (every grid tracer `α·K_h + K_e`, `α = 0` for species)                         | with `diff_mode`                                                                               | grid `manual_sparse_jacobian.jl:1535-1553`; updraft 1877-1931          | K_e only                                        | K_h share, plus K_e                                   | N: K_h + K_e; R, S: K_e only, α = 0                                                                                |
| 11 | EDMF diffusive flux, updraft mirror        | `edmfx_sgs_flux.jl:328-333, 349-369, 410-418`                                                                                              | with `edmfx_vertical_diffusion`                                                                | updraft block                                                          | K_e through the loop                            | K_h share                                             | copies: `Nʲ` as `q_totʲ`'s part; `Rʲ`, `Sʲ` K_e                                                                    |
| 12 | EDMF diffusive flux, horizontal            | `edmfx_sgs_flux.jl:444-571`                                                                                                                | explicit, sphere                                                                               | none                                                                   | none                                            | `q_tot_eff` share                                     | N only                                                                                                             |
| 13 | viscous sponge                             | `sponge/viscous_sponge.jl:166-229`                                                                                                         | explicit                                                                                       | none                                                                   | none                                            | `q_tot_eff` share                                     | N only                                                                                                             |
| 14 | Rayleigh sponge, updraft species           | `remaining_tendency.jl:149-161`                                                                                                            | explicit                                                                                       | none                                                                   | relaxes `q_raiʲ`                                | the same                                              | copies follow                                                                                                      |
| 15 | Smagorinsky, constant horizontal diffusion | `smagorinsky_lilly.jl:170-177, 227-235`, `constant_horizontal_diffusion.jl:39-46`                                                          | explicit, LES                                                                                  | none                                                                   | one diffusivity, every tracer                   | the same                                              | generic: every part as its parent                                                                                  |
| 16 | subsidence                                 | `forcing/subsidence.jl:86-107`                                                                                                             | explicit                                                                                       | none                                                                   | **none**                                        | first-order upwind                                    | N only (bracketed today)                                                                                           |
| 17 | SGS mass flux                              | `edmfx_sgs_flux.jl:26-175`                                                                                                                 | implicit                                                                                       | mass-flux blocks (`sgs_massflux_jacobian_blocks` 402-411)              | `ρᵏaᵏ(u³ᵏ−u³)(χᵏ−χ)`                            | the same                                              | default: each part by its share of its parent species' flux, plus an R exchange term (7); copies: the model's flux |
| 18 | entrainment, detrainment                   | `edmfx_entr_detr.jl:620-624`                                                                                                               | implicit                                                                                       | 1949-1990                                                              | toward the environment                          | the same                                              | copies follow                                                                                                      |
| 19 | limiters                                   | `limited_tendencies.jl:74-154` (SEM, vertical borrowing, species `~` = all)                                                                | every stage but the first, and the step's end                                                  | none                                                                   | limited per field                               | the same                                              | 8, additively                                                                                                      |
| 20 | grid constraints                           | `mass_flux_closures.jl:211-231`                                                                                                            | `constrain_state!`                                                                             | none                                                                   | floor, rescale by `min(1, ρq_tot/Σρq_cond)`     | the same                                              | 8                                                                                                                  |
| 21 | updraft constraints                        | `mass_flux_closures.jl:267-340`                                                                                                            | `constrain_state!`, the filter                                                                 | none                                                                   | floor, rescale by `q_totʲ/q_cond`               | the same                                              | 8, per updraft                                                                                                     |
| 22 | nonnegativity constraint                   | `constrain_state.jl:101-141`                                                                                                               | `constrain_state!`                                                                             | none                                                                   | element-wise or vapour borrowing                | the same                                              | 8                                                                                                                  |
| 23 | nonnegativity tendency                     | `moisture_fixers.jl:71-99`, called `remaining_tendency.jl:309`                                                                             | explicit                                                                                       | none                                                                   | borrows from vapour                             | the same                                              | 9: vapour (N) gives its composition                                                                                |
| 24 | DSS                                        | the stepper's `dss!`                                                                                                                       | every stage                                                                                    | —                                                                      | linear                                          | linear                                                | every part, linearly                                                                                               |
| 25 | starts                                     | `overwrite_from_file.jl:288-332`, `prognostic_variables.jl:134-186, 300-330`                                                               | initialization                                                                                 | —                                                                      | set                                             | set                                                   | each part = its parent × the tag's mask                                                                            |

**What the table shows.** The operators that move the parent's rain and snow
are linear in the species: advection (up to the limiter), sedimentation, K_e
diffusion, the mass flux, entrainment, DSS. Rain and snow get no K_h
diffusion, no hyperdiffusion, no viscous sponge and no subsidence.
*G3_PLAN 4.5 says rain is hyperdiffused and sponged; the code does neither, so
the plan is corrected.* The nonlinear pieces are the limiters and constraints
(19-22) and the microphysics (1, 2, 23).

## 5. Names: which code sees which part

A new part must be seen by the tag code and not by the generic tracer code,
except where the generic code already does the right thing. The review showed
that neither extreme works: in `microphysics_tracer_names`, R and S would get
`(ρχ, χʲ)` mass-flux blocks (`manual_sparse_jacobian.jl:402-411`) and the
solver's candidate lists (545, 211-255), and stop being split-solvable; in no
list at all, they would get K_h diffusion, hyperdiffusion, the sponge,
independent limiting and a passive K_h block. So:

| predicate                                                                    | N `ρq_tag_`     | R `ρq_rtag_`                                          | S `ρq_stag_` | Nʲ, Rʲ, Sʲ    |
|:---------------------------------------------------------------------------- |:---------------:|:-----------------------------------------------------:|:------------:|:-------------:|
| `is_tagged_tracer_name` (limiters skip, split)                               | yes             | yes                                                   | yes          | —             |
| `is_water_tag_name` (today's tag code)                                       | yes             | **no**                                                | **no**       | —             |
| a new `is_water_precip_part_name`                                            | no              | yes                                                   | yes          | —             |
| `microphysics_tracer_names`                                                  | no              | **no**                                                | **no**       | no            |
| `sedimenting_water_tag_names` (share block)                                  | yes, cloud only | no                                                    | no           | —             |
| WP5's `water_tag_follows_increment`                                          | yes             | no                                                    | no           | —             |
| K_h vertical diffusion, hyperdiffusion, viscous sponge, horizontal EDMF flux | generic         | **excluded at each site**                             | excluded     | per section 7 |
| EDMF diffusion `α`                                                           | 1               | **0** (K_e only), with the K_e-only block (1535-1553) | 0            | Rʲ, Sʲ: 0     |
| Smagorinsky, constant horizontal diffusion                                   | generic         | generic                                               | generic      | —             |

**Test:** a twin in which one tag's R holds all of `ρq_rai`: every operator's
tendency on it equals `ρq_rai`'s, as WP3's copies-against-tracer test did.

## 6. Denominators, and advection under the follower

Every share in the tag code divides by `ρq_tot` today: `water_tag_fraction`
(`tagged_water.jl:280`) in the bracket loss (369-387), sedimentation (446,
461), the share norm (540), the Jacobian's share derivative (476-486) and the
rescale (797); WP3's plume rescaled to `q_totʲ`, and the exchange weights
`q_totᵏ` (`tagged_water_edmf.jl:268-299, 413-460, 535-560`); WP5's mismatch
against `ρq_tot`. Under the key each is replaced by its compartment's own:

| site                                                         | today              | N                                        | R               | S               |
|:------------------------------------------------------------ |:------------------ |:---------------------------------------- |:--------------- |:--------------- |
| bracket loss, sedimentation share, norm, derivative, rescale | `ρq_tot`           | `ρq_tot − ρq_rai − ρq_sno`               | `ρq_rai`        | `ρq_sno`        |
| plume rescale, exchange weights                              | `q_totʲ`, `q_totᵏ` | `q_tot_effʲ`, `q_tot_effᵏ`               | `q_raiʲ`        | `q_snoʲ`        |
| WP5's mismatch                                               | `Δρq_tot`          | `Δ_imp(ρq_tot) − Δ_imp(ρq_rai + ρq_sno)` | `Δ_imp(ρq_rai)` | `Δ_imp(ρq_sno)` |

with a guard where a compartment is not positive. **Advection under WP5:**
`ρq_rai` and `ρq_sno` are advected explicitly, `ρq_tot` implicitly. So `N`
skips its own explicit advection and takes `−A_exp(Rᵢ) − A_exp(Sᵢ)`, and
follows `N`'s implicit mismatch; `R` and `S` keep `A_exp` and follow their own
implicit increments. **Test:** on a 1M column under `increment` with
first-order upwinding, `ΣRᵢ − ρq_rai` and `Σ(Nᵢ+Rᵢ+Sᵢ) − ρq_tot` stay at
rounding.

## 7. EDMF

**Default mode, one rule.** The grid parts sediment by the parent's grid
operator, linearly, with the parent's block (row 5). The updraft's own rain
composition enters through the mass flux and an **R exchange term** (row 17),
from an **N plume** re-derived on `q_tot_effʲ` (not WP3's total-water plume),
in which the updraft's rain takes the composition of its non-precipitating
water where it forms and the environment's where it flows in laterally
(`advection.jl:421-424`). A split of the grid sedimentation flux by subdomain
is not used: its environment part `F_grid − F_up` can be negative (different
face densities, `water_advection.jl:85-90` against 170-176; `ρaʲqʲ > ρq_rai`
between filter calls), its diagonal is `F_env/(R − Rʲ)` rather than the
parent's, and the environment's composition is 0/0 without rain. The default
mode's rain composition is therefore an approximation, which copies mode
audits.

**Copies.** Three copies per tag. They are not split-solvable
(`is_splittable_jacobian_field` needs `c.<name>`, 712-719), so fifteen copies
risk E44b's build growth; stage 3 measures the build before anything else.
`Rʲ`, `Sʲ` get K_e-only diffusion blocks, not the passive K_h+K_e block
(1877-1947), and the species' linear sedimentation block, not the share-based
1808-1840. Three repairs replace one, and W21's repair is already over its
bound.

## 8. Limiters and constraints (rows 19-22)

Additive, at fixed `q_tot`, by the net-flow rule, as `rescale_water_tags!`
shifts today (`tagged_water.jl:725-731, 781-797`), never by a factor:

  - a compartment that decreases gives its composition to each tag's `N`;
  - a compartment that increases takes `N`'s composition;
  - a clip to zero sets each `Rᵢ` to zero and returns it to `Nᵢ`;
  - floors of `water_tag_rescale_shift`'s kind keep every part non-negative.

The snapshots before each correction live in scratch the tags own: the model
uses `ᶜtemp_scalar` and `ᶜtemp_scalar_2` in `limiters_func!` and in
`enforce_grid_mean_microphysics_constraints!` (`mass_flux_closures.jl:213-214`).
**Test:** clip, rescale, vertical borrowing and SEM each keep every part
non-negative and each compartment summing to its parent.

## 9. Microphysics: the net-flow rule, and its alternative

1M exposes one net tendency per species and subdomain. The net-flow rule: in
each cell and subdomain, `ΔN = −ΔR − ΔS` (1M conserves `q_tot`); a compartment
that loses gives its own composition; one that gains takes the losers'
compositions weighted by their losses. The reviewer checked it on 20,000
random sign cases: the sums are exact to 9e-19. Guards: an empty losing
compartment (0/0 share) gives nothing; no loss at all moves nothing; source
tags use unnormalized shares.

**Its error is not small by default.** The model's tendency is a linearized
average over `nsubs` substeps (`BulkMicrophysicsTendencies.jl:633-715`), and
two-way flow is common: at 97% relative humidity rain forms at 1.34e-7 and
evaporates at 5.6e-8 in one state, so the two-way part is 72% of the net. The
net-flow rule gives the evaporated water the rain's composition only for the
net.

**The alternative: gross flows.** Decompose each linearized step into its
process flows (`_microphysics_source_terms`, `_linearize`), which sum exactly
to the net, and attribute each flow with its donor's composition. It needs the
per-process terms inside the tendency, at a cost of the order of the
microphysics itself for the tags. *For the owner, with the audit's numbers
(section 12).*

## 10. `pr_tag`

`pr` includes the rain, snow, cloud liquid and cloud ice fluxes at the bottom
face, with a level-1 extrapolated `sfc_ρ` (`microphysics_cache.jl:1294-1346`).
So `pr_tag_<name>` is each tag's bottom-face flux of its `R`, `S` and its
cloud part of `N`, built from the same terms as `pr`. `Σ pr_tag = pr` then
tests closure at level 1 only; under EDMF it must also match the subdomain
split of `pr`.

## 11. The restart guard

Today it checks the prefixes `ρq_tag_` and `q_tag_` only
(`water_tag_checkpoint.jl:78-96`), so a checkpoint written with the key would
restart without it. The guard goes to version 2, records
`water_tag_precipitation`, checks `ρq_rtag_`, `ρq_stag_` and their copies, and
covers WP5's ledgers per compartment.

## 12. The audit

An inline diagnostic, not an offline recomputation: in each microphysics call
it decomposes the linearized step into gross flows (section 9) and writes, per
tag and part, the difference between the net-flow attribution and the gross
one, accumulated as a state record. Offline recomputation from hourly samples
cannot bound an accumulated error, instantaneous rates do not reproduce the
linearized average (3.2e-8 against 7.8e-8 at a thin-cloud state), and the
process list must include ice autoconversion, ice–rain accretion with rain
freezing, both arms of rain–snow collisions, the warm and cold arms of
liquid–snow accretion, and accretion melt. The sub-grid quadrature applies
without EDMF too (`microphysics_cache.jl:930-946`); the audit reads the model's
own quadrature-averaged terms.

## 13. Cost, and staging

**Cost.** Three fields per tag (D4-W's five tags become fifteen), three
copies per tag in copies mode. With #76's split solver, 8 tags and 5 records
added 45 s to the EDMF column's `get_simulation` (712 s to 757 s, E44e), so
fifteen split grid fields should add of the order of a minute; *an
extrapolation*. The copies are not split and must be measured (7). The gross
flows of section 9 would add of the order of the microphysics' cost.

**Staging, with the review's gates.**

 1. **A 1M column without EDMF.** The key; the three parts; sections 5, 6
    (denominators), 8, 10, 11; the hyperdiffusion correction and the
    per-compartment repair of section 3; the tests of 5, 6, 8 and parity with
    the key off and on (`isequal`). Starts after the owner's decisions.
 2. **EDMF, default mode.** Section 7's one rule and section 6's advection
    under WP5.
 3. **Copies.** After the build is measured.

The audit (12) comes with stage 1.

## 14. The review, point by point

| point                                               | taken as                                        |
|:--------------------------------------------------- |:----------------------------------------------- |
| B1 names                                            | section 5                                       |
| B2 constraints                                      | section 8                                       |
| B3 denominators                                     | section 6                                       |
| B4 three followers                                  | section 6                                       |
| B5 EDMF default mode                                | section 7, one rule                             |
| S1 the leak's imprint                               | section 2, and section 16                       |
| S2 remaining leaks, missing rows                    | sections 3, 4                                   |
| S3 the audit                                        | sections 9, 12                                  |
| S4 `pr_tag`                                         | section 10                                      |
| S5 restart guard                                    | section 11                                      |
| S6 copies                                           | section 7                                       |
| S7 scratch, parity, tests                           | sections 8, 13                                  |
| S8 guards                                           | section 9                                       |
| minor: citations                                    | section 4 corrected                             |
| minor: the alternative need not leak                | section 3                                       |
| minor: G3_PLAN 4.5 on hyperdiffusion and the sponge | section 4; the plan is corrected with this note |
| minor: Float32 in the environment's compartment     | stage 2's tests, a Float32 twin                 |

## 15. For the owner

 1. **The prognostic fields:** three parts (recommended), or total plus two.
 2. **Under the key `ρq_tag_<name>` holds the non-precipitating water.**
 3. **Microphysics:** the net-flow rule (cheap, 72% two-way error at a humid
    state) or the gross flows (exact, about the microphysics' cost again).
    Proposed: the gross flows, with the net-flow rule as the fallback where
    the per-process terms are not available.
 4. **4.2's rule restated** (section 16).

## 16. Measuring a leak, and WP4c

A leak is measured by its **imprint**: two runs on one atmosphere, one with
the path's correction (WP4c's, 4.2) and one without; the L1 of the difference
of the tags' fields (not the difference of two L1s), and its maximum over the
run (not its value at 24 h), on the deep cases of V-W5 and V-W6 as well as
D4-W. A third run with the rain and snow tags bounds the imprint; it changes
too much to isolate it. The rule then reads: a path gets its correction where
its imprint's maximum exceeds a tenth of the closure budget.

## 17. Stage 1 as built (2026-09-25)

Where the build departs from or fills in the note:

 1. **Donor composition over the step (section 9).** Each gross flow carries
    its donor's composition over the step, not at its start: the donor's water
    at the start mixed with what flowed into it during the step
    (`water_tag_pool_shares`, a 3×3 linear system per tag and cell). The model's
    linearized step lets water pass through a compartment within one step. With
    the start composition, rain that formed and evaporated in a cell without
    rain carried no composition, and on the 10 km precipitating column the rain
    parts drifted from the rain by 20 times the rain in 600 s. With the pool the
    compartments close to rounding. Where a compartment holds much more than
    passes through, the two agree. *For the owner.*
 2. **The flows** repeat CloudMicrophysics 0.40's linearized substeps
    (`_microphysics_source_terms`, `_linearize` and the substep solve) and sum
    the transfers that cross compartments into six flows. Their nets match the
    model's tendencies to the rounding of the step's water over the step, not
    bit for bit (the compiler may fuse a `muladd` differently); the rounding
    remainder moves by the net-flow rule. A CloudMicrophysics upgrade that
    changes the step shows in the unit test that compares the nets.
 3. **No follower for the rain and snow parts (section 6).** Their implicit
    terms (sedimentation with the species' block, value for value, and the
    microphysics) are the species' by construction, so their increments match
    the species' to rounding; only `ρq_tag_<name>` follows the parent's
    increment of the non-precipitating water. The integration test's rounding
    closure under `increment` is the evidence.
 4. **The audit (section 12)** keeps two state records per tag, rain and snow.
    The non-precipitating part's difference is minus their sum, since both
    rules keep each tag's total. It is always on with the key.
 5. **The restart guard (section 11)** goes to version 2. A version 1
    checkpoint reads as written without the key, rather than refused.
 6. **The hyperdiffusion correction (section 3)** takes `φᵢ` as the tag's
    normalized share of the non-precipitating water. The `q_tag_leak_*`
    diagnostics read zero under the key.
 7. **The clip rule (section 8)** runs on the whole field at each correction:
    where a compartment is not positive, its parts are returned to the tags'
    non-precipitating parts, whether or not the correction touched the cell.
 8. **The test column.** `PrecipitatingColumn` has negative total water above
    about 6.2 km (its Rico `q_tot` profile runs below zero); no partition of a
    negative parent is possible, and the repair then empties the parts. The
    test cuts the column at 6 km. This is the setup's profile, not the tags'.
 9. **Cost, one bounded measurement.** On the 6 km column (30 levels, 3 tags,
    9 parts and 6 audit records), the default transport's step took 5.6 ms
    against 3.2 ms without tags on the shared login node. How that splits
    between the flows, the parts and the audit was not measured.
10. **Default transport.** With `water_tag_transport: tracer` the rain and
    snow parts also close to rounding (1.8e-16 and 3.3e-16 of the start's
    rain and snow in 300 s). The total's residual, 3.2e-5 of the column's
    water, is the known advection split.
