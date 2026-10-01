# Parent Budget: Coverage Registry

The parent budget is an opt-in conservation audit. It is off by default, and
`parent_budget_mode: summary` or `audit` switches it on. It changes no model
field. With it on, every model field that exists without it stays bit for bit as
in the same run with it off, under the default solver settings. Only its own
fields and output are added. The
[fork parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
gives the limits.

This page lists every path that can change an authoritative parent field, with
the disposition it is expected to have and the evidence that would establish it.
The [contract](contract.md) defines the dispositions, the
[architecture](architecture.md) says how a row is collected and the
[vocabulary](vocabulary.md) defines the terms. The
[implementation plan](plan.md) is a development record.

The tables are the documentation half of the registry in
`src/parent_budget/coverage_registry.jl`. The registry holds every cell verbatim
beside the guard that selects the row, and `test/parent_budget/registry_tests.jl`
compares the page with it cell by cell. The event ids are the registry keys. For
a configuration, the schema selects the rows whose guard holds and declares them
as expectations before collection begins. A row that was expected and never
recorded therefore shows as blocked. A row with an `open` disposition blocks the
claim it feeds.

## How to read a row

Disposition and collection state are separate columns. A row can be
mathematically zero and still be uncollected, and reading one as the other turns
an unmeasured term into an assumed zero.

| Column            | Value       | Meaning                                                                   |
|:----------------- |:----------- |:------------------------------------------------------------------------- |
| Disposition M·W·E | `measured`  | Not provably zero, so the parent budget measures it.                      |
|                   | `zero`      | Invariant zero, with the proof in the proof obligation cell.              |
|                   | `n/a`       | The path does not write this parent field in any supported configuration. |
|                   | `open`      | Not established from the code.                                            |
| State             | `none`      | Not collected as its own row.                                             |
|                   | `envelope`  | Covered only by the enclosing channel envelope.                           |
|                   | `collected` | Collected as its own contribution.                                        |
|                   | `verified`  | Collected, and a passing test has established its evidence.               |
| Topology          | `internal`  | Both sides are modeled reservoirs in one control volume.                  |
|                   | `coupled`   | Both sides are modeled reservoirs in different control volumes.           |
|                   | `exterior`  | One modeled side and a counterparty the model does not carry as state.    |
| Step              | a number    | The order in which rows were added to the registry.                       |

The disposition is a proof obligation about the code. It is not a claim about
the budget. A `zero` is never by itself evidence that anything was checked at
runtime. A row that is not `collected` or `verified` is uncollected whatever its
disposition says. Disposition columns describe the effect on the atmosphere
unless the row's reservoir column says otherwise.

The **level** says which part of the nested reconciliation the row belongs to:
`envelope`, `decomposition`, `final map` or `transfer`. An envelope row is the
reference its decomposition rows are reconciled against, and it is never summed
with them. A `final map` row is a direct term in the parent identity. It is not
an attribution channel, so it creates no requirement for an envelope of its own.
The reservoirs column lists modeled reservoirs only. An exterior counterparty
has no state to integrate and is named in its own column.

The schema derives a transfer row's topology from the configuration, never from
the legs that arrived. An `internal` or `coupled` row requires every declared
leg and tests the signed sum for cancellation. An `exterior` row records its
modeled leg alone. No counter-leg is fabricated and no cancellation is tested.
A row whose topology depends on the configuration names both cases, and the
schema picks one.

The **event** of a row is not a column. A row with a `measured` disposition is
delimited in the tendency code by an applied-update event, and the registry
holds its label in code (`CoverageRow.event`). A row whose every disposition is
`zero` or `n/a` needs no event and is booked from this table, so its state is
`collected` without a measurement of its own. The identity still checks it. A
proven zero that the code does not honour appears in the channel's attribution
residual.

## Channel envelopes

The primary identity reconciles the endpoint change against these envelopes
plus the final maps. Each row is the complete update one integrator channel
applied, taken from the applied increment and never from endpoint subtraction.
The final maps are not channels. A map has no envelope for a decomposition to
explain, so it produces no attribution result. Their rows are under **Final
accepted-state maps** below. The identity sums this table and that one, never an
aggregate of either alongside its own rows.

| Event id               | Dispatch                         | Guard  | Channel  | Reservoirs                           | Parent fields                 | Disposition M·W·E              | Proof obligation                                                     | Level    | State     | Evidence required                                                     | Test                | Step |
|:---------------------- |:-------------------------------- |:------ |:-------- |:------------------------------------ |:----------------------------- |:------------------------------ |:-------------------------------------------------------------------- |:-------- |:--------- |:--------------------------------------------------------------------- |:------------------- |:---- |
| `env.explicit_main`    | accepted increment from `Yₜ`     | always | `Yₜ`     | atmosphere, and slab when configured | `ρ`, `ρq_tot`, `ρe_tot`       | measured · measured · measured | applied increment equals tableau-weighted stage sum                  | envelope | collected | accepted explicit weights from the pinned tableau                     | `envelope_tests.jl` | 3    |
| `env.explicit_limited` | accepted increment from `Yₜ_lim` | always | `Yₜ_lim` | atmosphere, and slab when configured | `ρq_tot`, categories, tracers | measured · measured · measured | limited channel integrated through the limiter, separately from `Yₜ` | envelope | collected | accepted limited-channel increment                                    | `envelope_tests.jl` | 3    |
| `env.implicit`         | accepted increment from `T_imp!` | always | `T_imp!` | atmosphere, and slab when configured | `ρ`, `ρq_tot`, `ρe_tot`       | measured · measured · measured | effective implicit increment as the pinned solver forms it           | envelope | collected | stage weights and hook-folding established against the pinned version | `envelope_tests.jl` | 3    |

The algebraic solve defect is not a separate envelope. It is part of what the
implicit channel applied, so it is inside `env.implicit` and is a term of that
envelope's decomposition. An implicit attribution residual closes only with it.
The post-implicit correction is not an envelope either. `ClimaTimeSteppers`
applies `T_post_imp!` to the Newton-solved stage state and then forms the stored
implicit stage tendency by differencing, so the correction is inside
`env.implicit`. Booking it as an envelope would count it twice. It is the
decomposition row `impl.post_implicit_correction`.

## Explicit limited channel decomposition

| Event id                               | Dispatch                                | Guard                       | Channel  | Reservoirs | Parent fields                                        | Disposition M·W·E  | Proof obligation                                                              | Level         | State     | Evidence required                         | Test                            | Step |
|:-------------------------------------- |:--------------------------------------- |:--------------------------- |:-------- |:---------- |:---------------------------------------------------- |:------------------ |:----------------------------------------------------------------------------- |:------------- |:--------- |:----------------------------------------- |:------------------------------- |:---- |
| `lim_chan.horizontal_tracer_advection` | `horizontal_tracer_advection_tendency!` | moist or tracers configured | `Yₜ_lim` | atmosphere | `ρq_tot`, categories, tracers                        | zero · zero · zero | conservative horizontal divergence, global sum zero                           | decomposition | collected | operator global-zero test on a real state | `explicit_attribution_tests.jl` | 4    |
| `lim_chan.tracer_hyperdiffusion`       | `apply_tracer_hyperdiffusion_tendency!` | `hyperdiff` configured      | `Yₜ_lim` | atmosphere | `ρq_tot`, categories, tracers, and `ρ` with `ρq_tot` | zero · zero · zero | conservative, DSS of the `∇²` cache happens inside `hyperdiffusion_tendency!` | decomposition | collected | operator global-zero test on a real state | `explicit_attribution_tests.jl` | 4    |

## Explicit main channel decomposition

| Event id                            | Dispatch                                                    | Guard                                                    | Channel | Reservoirs | Parent fields                            | Disposition M·W·E              | Proof obligation                                                                                      | Level         | State     | Evidence required                            | Test                            | Step |
|:----------------------------------- |:----------------------------------------------------------- |:-------------------------------------------------------- |:------- |:---------- |:---------------------------------------- |:------------------------------ |:----------------------------------------------------------------------------------------------------- |:------------- |:--------- |:-------------------------------------------- |:------------------------------- |:---- |
| `expl.horizontal_dynamics`          | `horizontal_dynamics_tendency!`                             | always                                                   | `Yₜ`    | atmosphere | `ρ`, `ρe_tot`, `uₕ`                      | zero · n/a · zero              | conservative transport                                                                                | decomposition | collected | operator global-zero test                    | `explicit_attribution_tests.jl` | 4    |
| `expl.explicit_vertical_advection`  | `explicit_vertical_advection_tendency!`                     | always                                                   | `Yₜ`    | atmosphere | `ρ`, `ρe_tot`, tracers, `u₃`             | zero · zero · zero             | conservative transport, closed vertical boundaries                                                    | decomposition | collected | operator global-zero test                    | `explicit_attribution_tests.jl` | 4    |
| `expl.hyperdiffusion`               | `apply_hyperdiffusion_tendency!`                            | `hyperdiff` configured                                   | `Yₜ`    | atmosphere | `ρe_tot`, `uₕ`, `ρtke`                   | n/a · n/a · zero               | conservative                                                                                          | decomposition | collected | operator global-zero test                    | `explicit_attribution_tests.jl` | 4    |
| `expl.viscous_sponge`               | `viscous_sponge_tendency_*`                                 | `viscous_sponge` configured                              | `Yₜ`    | atmosphere | `uₕ`, `u₃`, `ρe_tot`, tracers, `ρ`       | measured · measured · measured | interior numerical source; the `ρ` leg is added only for the `ρq_tot` tracer                          | decomposition | collected | applied increment per field                  | `explicit_attribution_tests.jl` | 4    |
| `expl.rayleigh_sponge`              | `rayleigh_sponge_tendency_uₕ`                               | `rayleigh_sponge` configured                             | `Yₜ`    | atmosphere | `uₕ`                                     | zero · zero · zero             | momentum only, `ρe_tot` prognostic and untouched                                                      | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.held_suarez_drag`             | `held_suarez_forcing_tendency_uₕ`                           | `HeldSuarezForcing`                                      | `Yₜ`    | atmosphere | `uₕ`                                     | zero · zero · zero             | momentum only                                                                                         | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.held_suarez_heating`          | `held_suarez_forcing_tendency_ρe_tot`                       | `HeldSuarezForcing`                                      | `Yₜ`    | atmosphere | `ρe_tot`                                 | zero · zero · measured         | idealized external heating, no mass or water term                                                     | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.prescribed_radiative_heating` | `radiation_tendency!`, `RadiationTRMM_LBA`                  | `RadiationTRMM_LBA`                                      | `Yₜ`    | atmosphere | `ρe_tot`                                 | zero · zero · measured         | prescribed heating rate with no flux form, so nothing crosses a boundary                              | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.scm_coriolis`                 | `scm_coriolis_tendency_uₕ`                                  | single column with SCM Coriolis                          | `Yₜ`    | atmosphere | `uₕ`                                     | zero · zero · zero             | momentum only                                                                                         | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.subsidence`                   | `subsidence_tendency!`                                      | `LargeScaleSubsidence`                                   | `Yₜ`    | atmosphere | `ρe_tot`, `ρq_tot`, `ρq_lcl`, `ρq_icl`   | zero · measured · measured     | writes no `ρ` term, so the mass contribution is invariant zero                                        | decomposition | collected | applied increment plus field-write inventory | `explicit_attribution_tests.jl` | 4    |
| `expl.large_scale_advection`        | `large_scale_advection_tendency_*`                          | large-scale advection configured                         | `Yₜ`    | atmosphere | `ρe_tot`, `ρq_tot`                       | zero · measured · measured     | writes no `ρ` term                                                                                    | decomposition | collected | applied increment plus field-write inventory | `explicit_attribution_tests.jl` | 4    |
| `expl.external_forcing`             | `external_forcing_tendency!`, `apply_Tq_forcing!`           | external forcing configured                              | `Yₜ`    | atmosphere | `ρe_tot`, `ρq_tot`, `uₕ`                 | zero · measured · measured     | writes no `ρ` term                                                                                    | decomposition | collected | applied increment plus field-write inventory | `explicit_attribution_tests.jl` | 4    |
| `expl.vertical_diffusion`           | `vertical_diffusion_boundary_layer_tendency!`               | `diff_mode == Explicit()`                                | `Yₜ`    | atmosphere | `ρe_tot`, tracers, and `ρ` with `ρq_tot` | measured · measured · measured | interior operator with zero flux at top and bottom faces                                              | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.smagorinsky_lilly`            | `horizontal_/vertical_smagorinsky_lilly_tendency!`          | SGS diffusion configured                                 | `Yₜ`    | atmosphere | `ρ`, `ρe_tot`, tracers                   | measured · measured · measured | diffusive; global zero only if the discrete operator has it                                           | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.amd`                          | `horizontal_/vertical_amd_tendency!`                        | AMD configured                                           | `Yₜ`    | atmosphere | `ρ`, `ρe_tot`, tracers                   | measured · measured · measured | as above                                                                                              | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.constant_diffusion`           | `horizontal_constant_diffusion_tendency!`                   | constant diffusion configured                            | `Yₜ`    | atmosphere | tracers                                  | measured · measured · measured | as above                                                                                              | decomposition | collected | applied increment                            | `explicit_attribution_tests.jl` | 4    |
| `expl.microphysics_formation`       | `microphysics_tendency!`, 1M and non-equilibrium            | `NonEquilibriumMicrophysics1M` and explicit microphysics | `Yₜ`    | atmosphere | `ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno`   | zero · zero · zero             | formation redistributes categories inside `ρq_tot` and applies no source to `ρq_tot`, `ρ` or `ρe_tot` | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.tracer_nonnegativity_vapor`   | `tracer_nonnegativity_vapor_tendency!`                      | `tracer_nonnegativity_method` vapour tendency            | `Yₜ`    | atmosphere | `ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno`   | zero · zero · zero             | category-only; writes no parent field                                                                 | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.non_orographic_gravity_wave`  | `non_orographic_gravity_wave_apply_tendency!`               | configured                                               | `Yₜ`    | atmosphere | `uₕ`                                     | zero · zero · zero             | momentum only                                                                                         | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.orographic_gravity_wave`      | `orographic_gravity_wave_apply_tendency!`                   | configured                                               | `Yₜ`    | atmosphere | `uₕ`                                     | zero · zero · zero             | momentum only                                                                                         | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.zero_velocity`                | `zero_velocity_tendency!`                                   | advection tests                                          | `Yₜ`    | atmosphere | `uₕ`, `u₃`                               | zero · zero · zero             | momentum only                                                                                         | decomposition | collected | field-write inventory                        | `explicit_attribution_tests.jl` | 4    |
| `expl.out_of_scope`                 | `edmfx_*`, `pressure_work_tendency!`, `chemistry_tendency!` | out-of-scope configurations                              | `Yₜ`    | —          | —                                        | n/a · n/a · n/a                | excluded by the contract's scope                                                                      | decomposition | none      | configuration refused at setup               | `registry_tests.jl`             | 3    |

## Implicit channel decomposition

| Event id                        | Dispatch                                                     | Guard                                                                      | Channel  | Reservoirs                           | Parent fields                            | Disposition M·W·E              | Proof obligation                                                                                                                                                      | Level         | State     | Evidence required                                                    | Test                            | Step |
|:------------------------------- |:------------------------------------------------------------ |:-------------------------------------------------------------------------- |:-------- |:------------------------------------ |:---------------------------------------- |:------------------------------ |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:------------- |:--------- |:-------------------------------------------------------------------- |:------------------------------- |:---- |
| `impl.vertical_advection`       | `implicit_vertical_advection_tendency!`                      | always                                                                     | `T_imp!` | atmosphere                           | `ρ`, `ρe_tot`, tracers, `u₃`             | zero · zero · zero             | conservative transport with closed vertical boundaries; precipitation leaves through a different operator                                                             | decomposition | collected | operator global-zero test plus accepted implicit weight              | `implicit_attribution_tests.jl` | 5    |
| `impl.water_fallout`            | `vertical_advection_of_water_tendency!`                      | `NonEquilibriumMicrophysics1M`                                             | `T_imp!` | atmosphere                           | `ρ`, `ρq_tot`, `ρe_tot`                  | measured · measured · measured | `ᶜprecipdivᵥ` of the category flux with free outflow at the lower boundary                                                                                            | transfer      | none      | applied increment with accepted implicit weight                      | `transfer_tests.jl`             | 6    |
| `impl.microphysics_removal_0m`  | `microphysics_tendency!`, 0-moment                           | `EquilibriumMicrophysics0M` and implicit microphysics                      | `T_imp!` | atmosphere                           | `ρq_tot`, `ρ`, `ρe_tot`                  | measured · measured · measured | removal out of the column; the slab leg, when configured, is the transfer row `xfer.precipitation_0m`                                                                 | transfer      | none      | applied increment with accepted implicit weight                      | `transfer_tests.jl`             | 6    |
| `impl.microphysics_formation`   | `microphysics_tendency!`, 1M                                 | `NonEquilibriumMicrophysics1M` and implicit microphysics                   | `T_imp!` | atmosphere                           | categories                               | zero · zero · zero             | redistributes inside `ρq_tot`                                                                                                                                         | decomposition | collected | field-write inventory                                                | `implicit_attribution_tests.jl` | 5    |
| `impl.vertical_diffusion`       | `vertical_diffusion_boundary_layer_tendency!`                | `diff_mode == Implicit()`                                                  | `T_imp!` | atmosphere                           | `ρe_tot`, tracers, and `ρ` with `ρq_tot` | measured · measured · measured | interior operator, zero flux at top and bottom faces                                                                                                                  | decomposition | collected | applied increment with accepted implicit weight                      | `implicit_attribution_tests.jl` | 5    |
| `impl.solve_defect`             | Newton stage residual                                        | implicit configurations                                                    | `T_imp!` | atmosphere, and slab when configured | `ρ`, `ρq_tot`, `ρe_tot`, `sfc.*`         | measured · measured · measured | leading order at `max_iters = 1`; the slab has its own, from the precipitation it receives implicitly                                                                 | decomposition | collected | independent projection of the algebraic residual                     | `implicit_attribution_tests.jl` | 5    |
| `impl.post_implicit_correction` | `correct_implicit_advection_tendency!` through `T_post_imp!` | `energy_q_tot_upwinding != Val(:none)`                                     | `T_imp!` | atmosphere                           | `ρe_tot`, `ρq_tot`                       | zero · measured · measured     | writes no `ρ` term; folded into the effective implicit increment by the stepper, so it is booked from the correction the stepper applied, with weight `dt · b_imp[i]` | decomposition | collected | the correction tendency read at the hook, weighted; one booking only | `implicit_attribution_tests.jl` | 5    |
| `impl.folded_dss`               | `dss!` on the Newton-solved stage                            | spectral element with an implicit solve                                    | `T_imp!` | atmosphere                           | `ρ`, `ρq_tot`, `ρe_tot`                  | measured · measured · measured | the stepper differences the stage after this DSS, so its change is inside the stored implicit tendency and enters the accepted update with weight `b_imp[i]/γ`        | decomposition | collected | before/after pair on the solved stage, weighted                      | `implicit_attribution_tests.jl` | 5    |
| `impl.folded_constraint`        | `constrain_state!` on the Newton-solved stage                | `update_constrain_state_every` is `stage` or `dss`, with an implicit solve | `T_imp!` | atmosphere                           | `ρ`, `ρq_tot`, `ρe_tot`                  | measured · measured · measured | as `impl.folded_dss`; skipped at the last stage of a first-same-as-last tableau, where the end-of-step firing is the final map instead                                | decomposition | collected | before/after pair on the solved stage, weighted                      | `implicit_attribution_tests.jl` | 5    |
| `impl.zero_velocity`            | `zero_velocity_tendency!`                                    | advection tests                                                            | `T_imp!` | atmosphere                           | momentum                                 | zero · zero · zero             | momentum only                                                                                                                                                         | decomposition | collected | field-write inventory                                                | `implicit_attribution_tests.jl` | 5    |
| `impl.out_of_scope`             | `edmfx_*`, `sgs_*`, `pressure_work_tendency!`                | out-of-scope configurations                                                | `T_imp!` | —                                    | —                                        | n/a · n/a · n/a                | excluded by the contract's scope                                                                                                                                      | decomposition | none      | configuration refused at setup                                       | `registry_tests.jl`             | 3    |

A process row of the implicit channel is measured as a tendency and enters the
accepted step with weight `dt · b_imp[i]`. The stepper stores the implicit stage
tendency as `(U − U_start)/dtγ`, so a change folded into stage `i`
(`impl.folded_dss`, `impl.folded_constraint`, `impl.solve_defect`) enters with
weight `b_imp[i]/γ`. For `ARS343` that is 2.7726, −1.4784 and 1 at stages 2, 3
and 4. The post-implicit correction enters with `dt · b_imp[i]`. The disposition
columns describe the change, and the adapter applies the weight when it books
the row. The two implicit rows at level `transfer` are not
decomposition rows. Their legs are collected through the transfer rows
`xfer.precipitation_1m` and `xfer.precipitation_0m`.

## Final accepted-state maps

A final map contributes its raw before and after difference on the accepted
state. The same dispatch on an intermediate stage array is a stage observation,
and it never enters the identity at its raw value.

| Event id                               | Dispatch                                                                   | Guard                          | Channel            | Reservoirs       | Parent fields                                         | Disposition M·W·E              | Proof obligation                                                                                                                             | Level     | State     | Evidence required                                                                              | Test                          | Step |
|:-------------------------------------- |:-------------------------------------------------------------------------- |:------------------------------ |:------------------ |:---------------- |:----------------------------------------------------- |:------------------------------ |:-------------------------------------------------------------------------------------------------------------------------------------------- |:--------- |:--------- |:---------------------------------------------------------------------------------------------- |:----------------------------- |:---- |
| `map.quasimonotone_limiter`            | `limiters_func!`, SEM quasimonotone limiter                                | limiter configured             | `lim!`             | atmosphere       | `ρq_tot`, categories, tracers                         | measured · measured · measured | numerical correction, not a physical tendency                                                                                                | final map | collected | ordered before/after pair on the accepted state                                                | `journal_tests.jl`            | 7    |
| `map.rescale_water_tags`               | `limiters_func!`, `rescale_water_tags!`                                    | water tags configured          | `lim!`             | atmosphere       | tag fields only                                       | zero · zero · zero             | tag-only, writes no parent field                                                                                                             | final map | collected | field-write inventory                                                                          | `journal_tests.jl`            | 7    |
| `map.mass_energy_consistency`          | `limiters_func!`, `enforce_mass_energy_consistency!`                       | moist                          | `lim!`             | atmosphere       | `ρ`, `ρe_tot`                                         | measured · zero · measured     | moves `ρ` by `Δρq_tot` and `ρe_tot` by `Δρq_tot·(uᵥ(T)+Φ)`                                                                                   | final map | collected | ordered before/after pair                                                                      | `journal_tests.jl`            | 7    |
| `map.vertical_mass_borrowing`          | `limiters_func!`, vertical mass borrowing limiter                          | configured                     | `lim!`             | atmosphere       | `ρq_tot`, categories                                  | measured · measured · measured | numerical correction                                                                                                                         | final map | collected | ordered before/after pair                                                                      | `journal_tests.jl`            | 7    |
| `map.dss`                              | `dss!`                                                                     | spectral element               | `dss!`             | atmosphere       | `ρ`, `ρq_tot`, `ρe_tot`                               | measured · measured · measured | conservative in exact arithmetic on a closed sphere, so the amount is expected at reduction level and larger is a finding                    | final map | collected | ordered before/after pair, compared against the reduction scale                                | `journal_tests.jl`            | 7    |
| `map.prescribe_flow`                   | `constrain_state!`, `prescribe_flow!`                                      | `prescribed_flow`              | `constrain_state!` | atmosphere       | `ρ`, `ρe_tot`, momentum                               | n/a · n/a · n/a                | prescribed overwrite, out of scope, never a physical tendency                                                                                | final map | none      | configuration refused at setup                                                                 | `registry_tests.jl`           | 7    |
| `map.tracer_nonneg_element_categories` | `constrain_state!`, `tracer_nonnegativity_constraint!` element variant     | `constrain_qtot = false`       | `constrain_state!` | atmosphere       | categories                                            | zero · zero · zero             | the loop skips `ρq_tot`, so no parent field is written                                                                                       | final map | collected | field-write inventory                                                                          | `journal_tests.jl`            | 7    |
| `map.tracer_nonneg_element_qtot`       | `constrain_state!`, `tracer_nonnegativity_constraint!` element variant     | `constrain_qtot = true`        | `constrain_state!` | atmosphere       | `ρq_tot`, `ρ`, `ρe_tot`                               | measured · measured · measured | clips `ρq_tot` and hands the increment to `enforce_mass_energy_consistency!`                                                                 | final map | collected | ordered before/after pair                                                                      | `journal_tests.jl`            | 7    |
| `map.tracer_nonneg_vapor`              | `constrain_state!`, `tracer_nonnegativity_constraint!` vapour variant      | moist                          | `constrain_state!` | atmosphere       | categories, and `ρq_tot` when `constrain_qtot = true` | zero · measured · zero         | at `constrain_qtot = true` it clips `ρq_tot` without calling `enforce_mass_energy_consistency!`, so water moves while stored energy does not | final map | collected | ordered before/after pair plus a physical-inconsistency note                                   | `journal_tests.jl`            | 7    |
| `map.physical_constraints`             | `constrain_state!`, `enforce_physical_constraints!` non-EDMF branch        | `NonEquilibriumMicrophysics1M` | `constrain_state!` | atmosphere       | categories                                            | zero · zero · zero             | clamps and rescales the condensate fields, reads `ρq_tot` and writes none of `ρ`, `ρq_tot`, `ρe_tot`                                         | final map | collected | field-write inventory                                                                          | `journal_tests.jl`            | 7    |
| `map.repair_water_tag_partition`       | `constrain_state!`, `repair_water_tag_partition!`                          | water tags configured          | `constrain_state!` | atmosphere       | tag fields only                                       | zero · zero · zero             | tag-only, sum preserved by construction                                                                                                      | final map | collected | field-write inventory                                                                          | `journal_tests.jl`            | 7    |
| `map.repair_energy_source_tags`        | `constrain_state!`, `repair_energy_source_tags!`                           | energy source repair on        | `constrain_state!` | atmosphere       | tag fields only                                       | zero · zero · zero             | tag-only, partition sum preserved by construction                                                                                            | final map | collected | unit test of the repair on fields                                                              | `energy_source_tags_tests.jl` | 7    |
| `map.restart_transition`               | `handle_restart`                                                           | restart                        | initialization     | atmosphere, slab | `ρ`, `ρq_tot`, `ρe_tot`, `sfc.*`                      | measured · measured · measured | a zero-duration transition of its own, never charged to the next step                                                                        | final map | collected | endpoint pair across the restart boundary, compared exactly before the first transaction opens | `restart_tests.jl`            | 7    |
| `map.initial_state`                    | `Setups.initial_state`, `overwrite_initial_state!`, `overwrite_from_file!` | initialization                 | initialization     | atmosphere, slab | all                                                   | n/a · n/a · n/a                | sets `B⁰`, outside every transaction                                                                                                         | final map | none      | first endpoint recorded as the initial one                                                     | `restart_tests.jl`            | 7    |

`update_constrain_state_every` decides how often the `constrain_state!` rows
fire. At `"step"` there is one firing per transaction, and it is a final map. At
`"stage"` and `"dss"` the same dispatch also fires on intermediate stage arrays,
where it is a stage observation and enters the identity only with its accepted
weight.

## Transfer events

Each of these moves a quantity between two modeled reservoirs or carries it out
of the modeled system, and the topology column says which. When both sides are
modeled, every declared leg is collected independently from its own quadrature,
never by negating the other, and the signed sum is tested for cancellation. When
the far side is not modeled, the modeled leg is collected, the counterparty is
named and no counter-leg is invented.

| Event id                      | Topology                                    | Modeled legs                                                                              | Exterior counterparty                               | Guard                                           | Reservoirs                           | Parent fields                                       | Disposition M·W·E              | Proof obligation                                                                       | Level    | State     | Evidence required                                            | Test                | Step |
|:----------------------------- |:------------------------------------------- |:----------------------------------------------------------------------------------------- |:--------------------------------------------------- |:----------------------------------------------- |:------------------------------------ |:--------------------------------------------------- |:------------------------------ |:-------------------------------------------------------------------------------------- |:-------- |:--------- |:------------------------------------------------------------ |:------------------- |:---- |
| `xfer.surface_turbulent_flux` | `coupled` with a slab, `exterior` otherwise | `surface_flux_tendency!`, and `surface_temp_tendency!` for a slab                         | unmodeled surface store, when no slab is configured | unless `disable_surface_flux_tendency`          | atmosphere, and slab when configured | `ρe_tot`, `ρq_tot`, `ρ`, `uₕ`, `sfc.T`, `sfc.water` | measured · measured · measured | `Yₜ.c.ρ -= btt` is the mass leg; boundary crossing in the atmosphere-only view         | transfer | collected | every declared leg measured separately                       | `transfer_tests.jl` | 6    |
| `xfer.radiation_toa`          | `exterior`                                  | `radiation_tendency!` at the model top                                                    | space above the model top                           | radiation in flux form: RRTMGP, DYCOMS or ISDAC | atmosphere                           | `ρe_tot`                                            | zero · zero · measured         | boundary crossing with no receiving reservoir                                          | transfer | collected | atmospheric leg, cross-checked against the reported TOA flux | `transfer_tests.jl` | 6    |
| `xfer.radiation_surface`      | `coupled` with a slab, `exterior` otherwise | `radiation_tendency!` at the surface, and `surface_temp_tendency!` for a slab             | unmodeled surface store, when no slab is configured | radiation in flux form: RRTMGP, DYCOMS or ISDAC | atmosphere, and slab when configured | `ρe_tot`, `sfc.T`                                   | zero · zero · measured         | separate from the TOA leg, because only one of them has a reservoir on the far side    | transfer | collected | every declared leg measured separately                       | `transfer_tests.jl` | 6    |
| `xfer.precipitation_0m`       | `coupled` with a slab, `exterior` otherwise | `microphysics_tendency!`, 0-moment, and `surface_precipitation_tendency!` for a slab      | unmodeled surface store, when no slab is configured | `EquilibriumMicrophysics0M`                     | atmosphere, and slab when configured | `ρq_tot`, `ρ`, `ρe_tot`, `sfc.T`, `sfc.water`       | measured · measured · measured | removal from the column; the slab receives the cached column integral of the same sink | transfer | collected | every declared leg measured separately                       | `transfer_tests.jl` | 6    |
| `xfer.precipitation_1m`       | `coupled` with a slab, `exterior` otherwise | `vertical_advection_of_water_tendency!`, and `surface_precipitation_tendency!` for a slab | unmodeled surface store, when no slab is configured | `NonEquilibriumMicrophysics1M`                  | atmosphere, and slab when configured | `ρq_tot`, `ρ`, `ρe_tot`, `sfc.water`, `sfc.T`       | measured · measured · measured | two quadratures of one physical flux, so the pair is measured and any mismatch kept    | transfer | collected | every declared leg measured separately                       | `transfer_tests.jl` | 6    |
| `xfer.slab_qflux`             | `exterior`                                  | `surface_temp_tendency!` Q-flux term                                                      | prescribed ocean heat transport                     | `SlabOceanTemperature` with a Q-flux            | slab                                 | `sfc.T`                                             | n/a · n/a · measured           | prescribed exterior source into the slab                                               | transfer | collected | slab leg only, exterior counterparty declared                | `transfer_tests.jl` | 6    |

A row that reads `coupled` with a slab and `exterior` otherwise is two
expectations, not one flexible one. The schema resolves it from the
configuration, and the resolved topology decides whether a cancellation test
applies.

## Non-authoritative paths

These paths were considered. None of them writes a parent field, so none is
booked.

| Event id                           | Dispatch                                                                   | Hook               | Why it is not booked                                                                         |
|:---------------------------------- |:-------------------------------------------------------------------------- |:------------------ |:-------------------------------------------------------------------------------------------- |
| `cache.precomputed`                | `set_precomputed_quantities!`                                              | `cache!`           | cache, and the velocity filter on `Y.f.u₃` at the two boundary faces, which is momentum only |
| `cache.implicit_precomputed`       | `set_implicit_precomputed_quantities!`                                     | `cache_imp!`       | cache, and the velocity filter on `Y.f.u₃` at the two boundary faces, which is momentum only |
| `cache.implicit_stage_setup`       | `initialize_implicit_stage_problem!`                                       | `initialize_imp!`  | stage setup                                                                                  |
| `cb.flux_accumulation`             | `flux_accumulation!`                                                       | discrete callback  | mutates `Ref`s in `p` only                                                                   |
| `cb.external_driven_single_column` | `external_driven_single_column!`                                           | discrete callback  | refreshes forcing caches only                                                                |
| `cb.rrtmgp_solver`                 | `rrtmgp_solver_callback!`                                                  | discrete callback  | fills the radiation cache; the state effect arrives through `radiation_tendency!`            |
| `cb.read_only`                     | `nan_checking_callback`, `checkpoint_callback`, `gc_callback`, diagnostics | discrete callbacks | read-only with respect to `Y`                                                                |

A custom callback outside this list is accepted only inside a `ReadOnlyCallback`
declaration. An undeclared one fails the configuration at setup.

## Proof obligations that need more than a cell

**Momentum-only rows.** `ρe_tot` is prognostic. A tendency that writes only `uₕ`
or `u₃` leaves it untouched, so its energy contribution is exactly zero. Where a
scheme is meant to deposit frictional heat and no implemented term does it, the
gap belongs in the contract's limitations register and never in a numerical
residual.

**Transfer legs.** A leg is measured on its own side, inside the applied-update
event of the tendency that applies it. The event's own total is the leg for the
atmosphere's side of `xfer.surface_turbulent_flux` and for both sides of
`xfer.precipitation_0m` and `xfer.precipitation_1m`. The two radiation crossings
and the slab's turbulent, radiative and prescribed fluxes are lumped in one
event each. They are read from the flux field the tendency reads, and the
event's total is kept beside their sum as a check. Zero-moment precipitation
reaches a slab through the cached column integrals of the same sink the
atmosphere applies. With a slab it is a coupled transfer, and the slab is solved
implicitly with it, which gives the slab a solve defect of its own.

**Forcing rows.** `expl.subsidence`, `expl.large_scale_advection` and
`expl.external_forcing` write `ρq_tot` and `ρe_tot` and no `ρ` term. Their mass
disposition is an invariant zero, so the dry-air budget of a forced run is open.
A mass contribution is never manufactured from the water tendency.

**Interior diffusion, fallout and removal.** `ᶜdiffdivᵥ` sets zero flux at the top
and bottom faces, so vertical diffusion carries no boundary condition and its
row is `measured` only because the discrete interior integral is not exactly
zero. `surface_flux_tendency!` carries the surface flux. One-moment formation
only redistributes categories inside `ρq_tot`. One-moment fallout
(`vertical_advection_of_water_tendency!`) is always on the implicit channel, and
its lower boundary is open, which is where 1M water leaves the atmosphere.
Zero-moment removal is a direct sink with no receiving reservoir. Its channel
follows `microphysics_tendency_timestepping`, which `implicit_microphysics`
sets and which is implicit by default.

**Category-only constraints.** A constraint that writes only `ρq_lcl`, `ρq_icl`,
`ρq_rai` and `ρq_sno` is an invariant zero for `ρ`, `ρq_tot` and `ρe_tot`.

**What the stored implicit tendency folds in.** In `ClimaTimeSteppers`' `step_u!` an implicit stage records
`U_start` before `initialize_imp!`. It then runs `initialize_imp!`, a DSS, the
`WithDSS` constraint firing, the Newton solve, `T_post_imp!`, a DSS and the
`EndOfStage` constraint firing, and only then stores `T_imp[i] = (U − U_start)/dtγ`.
Every one of those changes is inside the effective implicit increment, and none
may be booked again on its own. The DSS and constraint that run on the assembled
stage value before `U_start` is taken, and the stage-level `lim!`, are not inside
it. They reach the endpoint only through the tableau and stay stage observations.

**The velocity filter in the cache hooks.** `set_implicit_precomputed_quantities!`
and `set_precomputed_quantities!` rewrite `Y.f.u₃` at the bottom and top faces
so that the contravariant vertical velocity vanishes there. They run at every
`cache!` and `cache_imp!` call, including inside every implicit stage, where the
stepper folds the change into the effective implicit increment. They write
momentum and nothing else, so their mass, water and energy contributions are
exactly zero. A change that made them touch `ρ` would need a row.

## Open gaps and what they block

No row has an `open` disposition. Two limits remain.

| Gap                                                              | Blocks                                 |
|:---------------------------------------------------------------- |:-------------------------------------- |
| Attribution and transfer legs are collected in `audit` mode only | claim levels 3 and 4 in `summary` mode |

An open item never becomes `zero` by assumption. It becomes `measured` or `zero`
with the evidence its row names.
