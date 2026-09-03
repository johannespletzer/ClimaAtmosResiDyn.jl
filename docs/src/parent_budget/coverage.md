# Parent-Budget Ledger: Coverage Matrices

Two linked inventories, taken from the code rather than from the physics. The
[budget contract](contract.md) fixes what they are measured against, and the
[plan](plan.md) says which pull request closes each row.

Nothing here is instrumentation. The point of the matrices is that no supported
configuration may claim closure while a row that mutates authoritative state is
still `unknown`.

## How to read a status

| Status     | Meaning                                                        |
|:---------- |:-------------------------------------------------------------- |
| `measured` | The ledger records an amount taken from the implemented update |
| `zero`     | Proven invariant zero, with the evidence named in the row      |
| `n/a`      | The path does not exist in a supported configuration           |
| `unknown`  | Not yet established; blocks the affected closure claim         |

`Δ` columns are the effect on the **atmospheric** reservoir unless a row says
otherwise. Positive means addition.

## Matrix 1 — equation and exchange paths

The right-hand side has three channels, and confusing them is the first way to
lose a term.

  - `Yₜ` — the main explicit tendency, from `remaining_tendency!`.
  - `Yₜ_lim` — the *limited* explicit tendency, also from `remaining_tendency!`.
    `ClimaTimeSteppers` integrates it through the limiter, not alongside `Yₜ`.
  - `T_imp!` — `implicit_tendency!`, evaluated inside the Newton solve.

Plus `T_post_imp!`, a post-Newton correction, which is a channel of its own.

### Explicit, limited channel (`Yₜ_lim`)

| Path                                    | Fields                            | ΔM     | ΔW     | ΔE     | Notes                                                                                                          |
|:--------------------------------------- |:--------------------------------- |:------ |:------ |:------ |:-------------------------------------------------------------------------------------------------------------- |
| `horizontal_tracer_advection_tendency!` | `ρq_tot`, the categories, tracers | `zero` | `zero` | `zero` | Conservative horizontal divergence; global zero is an invariant of the operator and is **tested**, not assumed |
| `apply_tracer_hyperdiffusion_tendency!` | same                              | `zero` | `zero` | `zero` | Same test; DSS of the `∇²` cache happens inside `hyperdiffusion_tendency!`                                     |

Both rows are `unknown` for coverage purposes until PR 3 reads this channel at
all. This is the blocker the contract names: an adapter that reads only `Yₜ`
misses every row in this table.

### Explicit, main channel (`Yₜ`)

| Path                                                        | Fields                                 | ΔM                   | ΔW                   | ΔE                   | Classification                                                                                                                                                                                                                                                                   |
|:----------------------------------------------------------- |:-------------------------------------- |:-------------------- |:-------------------- |:-------------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `horizontal_dynamics_tendency!`                             | `ρ`, `ρe_tot`, `uₕ`                    | `zero`               | —                    | `zero`               | conservative transport, tested                                                                                                                                                                                                                                                   |
| `explicit_vertical_advection_tendency!`                     | `ρ`, `ρe_tot`, tracers, `u₃`           | `zero`               | `zero`               | `zero`               | conservative transport, tested                                                                                                                                                                                                                                                   |
| `apply_hyperdiffusion_tendency!`                            | `ρe_tot`, `uₕ`, `ρtke`                 | —                    | —                    | `zero`               | conservative, tested                                                                                                                                                                                                                                                             |
| `viscous_sponge_tendency_*`                                 | `uₕ`, `u₃`, `ρe_tot`, tracers, `ρ`     | `measured`           | `measured`           | `measured`           | interior numerical source; the `ρ` leg is added only for the `ρq_tot` tracer                                                                                                                                                                                                     |
| `rayleigh_sponge_tendency_uₕ`                               | `uₕ`                                   | `zero`               | `zero`               | `zero`               | momentum only, `ρe_tot` prognostic and untouched — see the completeness note below                                                                                                                                                                                               |
| `held_suarez_forcing_tendency_uₕ`                           | `uₕ`                                   | `zero`               | `zero`               | `zero`               | as above                                                                                                                                                                                                                                                                         |
| `held_suarez_forcing_tendency_ρe_tot`                       | `ρe_tot`                               | `zero`               | `zero`               | `measured`           | idealized external heating                                                                                                                                                                                                                                                       |
| `scm_coriolis_tendency_uₕ`                                  | `uₕ`                                   | `zero`               | `zero`               | `zero`               | momentum only                                                                                                                                                                                                                                                                    |
| `subsidence_tendency!`                                      | `ρe_tot`, `ρq_tot`                     | `unknown`            | `measured`           | `measured`           | prescribed large-scale input; whether it moves `ρ` with `ρq_tot` must be read, not assumed                                                                                                                                                                                       |
| `large_scale_advection_tendency_*`                          | `ρe_tot`, `ρq_tot`                     | `unknown`            | `measured`           | `measured`           | same                                                                                                                                                                                                                                                                             |
| `external_forcing_tendency!`                                | `ρe_tot`, `ρq_tot`, `uₕ`               | `unknown`            | `measured`           | `measured`           | nudging and relaxation; signed external input                                                                                                                                                                                                                                    |
| `vertical_diffusion_boundary_layer_tendency!`               | `ρe_tot`, tracers                      | `measured`           | `measured`           | `measured`           | only when `diff_mode == Explicit()`; carries the surface boundary condition                                                                                                                                                                                                      |
| `surface_flux_tendency!`                                    | `ρe_tot`, `ρq_tot`, `ρ`, `uₕ`          | `measured`           | `measured`           | `measured`           | **boundary crossing**; `Yₜ.c.ρ -= btt` is the mass leg                                                                                                                                                                                                                           |
| `radiation_tendency!`                                       | `ρe_tot`                               | `zero`               | `zero`               | `measured`           | boundary crossing at TOA and surface                                                                                                                                                                                                                                             |
| `microphysics_tendency!`, 0-moment                          | `ρq_tot`, `ρ`, `ρe_tot`                | `measured`           | `measured`           | `measured`           | Removal straight out of the column. `Yₜ.c.ρq_tot` and `Yₜ.c.ρ` take the same sink, so it is a **boundary crossing** for M and W both, with no receiving reservoir                                                                                                                |
| `microphysics_tendency!`, 1-moment and non-equilibrium      | `ρq_lcl`, `ρq_icl`, `ρq_rai`, `ρq_sno` | `zero`               | `zero`               | `zero`               | Formation only redistributes the categories *inside* `ρq_tot`. It applies no source to `ρq_tot`, `ρ` or `ρe_tot`, so it is internal to all three. The fallout is a separate path, below                                                                                          |
| `vertical_advection_of_water_tendency!`                     | `ρ`, `ρq_tot`, `ρe_tot`                | `measured`           | `measured`           | `measured`           | **Sedimentation and fallout.** `ᶜprecipdivᵥ` of the category flux, with free outflow at the lower boundary, so this is where 1-moment water actually leaves the atmosphere. A **boundary leg paired with the surface deposition leg**; the pair is measured, never assumed equal |
| `non_orographic_gravity_wave_apply_tendency!`               | `uₕ`                                   | `zero`               | `zero`               | `zero`               | momentum only                                                                                                                                                                                                                                                                    |
| `orographic_gravity_wave_apply_tendency!`                   | `uₕ`                                   | `zero`               | `zero`               | `zero`               | momentum only                                                                                                                                                                                                                                                                    |
| `surface_temp_tendency!`                                    | `Y.sfc.T`                              | `n/a`                | `n/a`                | `measured` (surface) | the surface leg of the radiative and turbulent exchange                                                                                                                                                                                                                          |
| `surface_precipitation_tendency!`                           | `Y.sfc.water`, `Y.sfc.T`               | `measured` (surface) | `measured` (surface) | `measured` (surface) | The surface leg of fallout, paired with `vertical_advection_of_water_tendency!`. Built from the cached surface rain and snow fluxes, a different quadrature from the atmospheric leg, so the pair is measured and any mismatch kept                                              |
| `horizontal_/vertical_smagorinsky_lilly_tendency!`          | `ρ`, `ρe_tot`, tracers                 | `measured`           | `measured`           | `measured`           | diffusive; global zero only if the discrete operator has it, so measured                                                                                                                                                                                                         |
| `horizontal_/vertical_amd_tendency!`                        | `ρ`, `ρe_tot`, tracers                 | `measured`           | `measured`           | `measured`           | as above                                                                                                                                                                                                                                                                         |
| `horizontal_constant_diffusion_tendency!`                   | tracers                                | `measured`           | `measured`           | `measured`           | as above                                                                                                                                                                                                                                                                         |
| `tracer_nonnegativity_vapor_tendency!`                      | `ρq_tot`, species                      | `zero`               | `zero`               | `unknown`            | moves water between categories at the cost of vapour; the energy leg must be read                                                                                                                                                                                                |
| `zero_velocity_tendency!`                                   | `uₕ`, `u₃`                             | `zero`               | `zero`               | `zero`               | momentum only, advection tests                                                                                                                                                                                                                                                   |
| `edmfx_*`, `pressure_work_tendency!`, `chemistry_tendency!` | —                                      | `n/a`                | `n/a`                | `n/a`                | out of scope, see the contract                                                                                                                                                                                                                                                   |

### Implicit channel (`T_imp!`)

| Path                                          | Fields                       | ΔM                   | ΔW                   | ΔE                   | Classification                                                                                                                                                                                                            |
|:--------------------------------------------- |:---------------------------- |:-------------------- |:-------------------- |:-------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `implicit_vertical_advection_tendency!`       | `ρ`, `ρe_tot`, tracers, `u₃` | `zero`               | `zero`               | `zero`               | Conservative transport, tested. The global zero covers this operator only. Precipitation leaves through `vertical_advection_of_water_tendency!`, whose lower boundary is open, and that is booked as its own boundary leg |
| `microphysics_tendency!`, 0-moment            | `ρq_tot`, `ρ`, `ρe_tot`      | `measured`           | `measured`           | `measured`           | The **default** path, since `implicit_microphysics` defaults on. Removal straight out of the column                                                                                                                       |
| `microphysics_tendency!`, 1-moment            | the categories               | `zero`               | `zero`               | `zero`               | Redistributes inside `ρq_tot`; the fallout leg is explicit, in `vertical_advection_of_water_tendency!`                                                                                                                    |
| `surface_precipitation_tendency!`             | `Y.sfc.*`                    | `measured` (surface) | `measured` (surface) | `measured` (surface) | The implicit counterpart of the same surface leg                                                                                                                                                                          |
| `vertical_diffusion_boundary_layer_tendency!` | `ρe_tot`, tracers            | `measured`           | `measured`           | `measured`           | only when `diff_mode == Implicit()`                                                                                                                                                                                       |
| `zero_velocity_tendency!`                     | momentum                     | `zero`               | `zero`               | `zero`               |                                                                                                                                                                                                                           |
| `edmfx_*`, `sgs_*`, `pressure_work_tendency!` | —                            | `n/a`                | `n/a`                | `n/a`                | out of scope                                                                                                                                                                                                              |

Every implicit row is `unknown` for *stage weighting* until PR 5 establishes
that the accepted-solution coefficients can be read. The effect columns above
describe the tendency, not yet the accepted increment.

### Post-implicit channel (`T_post_imp!`)

| Path                                   | Fields             | ΔM        | ΔW        | ΔE        | Classification                                                                                                                           |
|:-------------------------------------- |:------------------ |:--------- |:--------- |:--------- |:---------------------------------------------------------------------------------------------------------------------------------------- |
| `correct_implicit_advection_tendency!` | `ρe_tot`, `ρq_tot` | `unknown` | `unknown` | `unknown` | Post-Newton upwind correction. Wired only when `energy_q_tot_upwinding != Val(:none)`. Its own leg, never folded into the implicit terms |

### A note on momentum-only tendencies

Every `zero` in the `ΔE` column for a drag or sponge row is exact by
construction, and the reason is worth stating once. `ρe_tot` is prognostic. A
tendency that changes only `uₕ` or `u₃` leaves `ρe_tot` untouched, so the total
energy contribution is exactly zero, and the diagnosed kinetic-energy change is
balanced by an equal and opposite diagnosed internal-energy change.

That is a statement about the implemented equations, not about the physics. If
a scheme is meant to deposit frictional heat, there is no implemented term
doing it. That belongs in the limitations register as a completeness gap, and
never in the numerical residual.

## Matrix 2 — state-mutation paths

The distinction that matters here is **authoritative** state against
**temporary** state. A change to a stage array, a work array, a cache, or a
diagnostic is not an endpoint source, even when it changes what a later
right-hand side computes. Booking it both as a correction and through the
resulting accepted right-hand side is double-counting.

| Path                                                                         | Hook                | Authoritative? | ΔM         | ΔW         | ΔE         | Classification                                                                                                                               |
|:---------------------------------------------------------------------------- |:------------------- |:-------------- |:---------- |:---------- |:---------- |:-------------------------------------------------------------------------------------------------------------------------------------------- |
| IMEX accepted update                                                         | integrator          | yes            | `measured` | `measured` | `measured` | `Q_equation`                                                                                                                                 |
| `initialize_implicit_stage_problem!`                                         | `initialize_imp!`   | no             | —          | —          | —          | stage setup                                                                                                                                  |
| Newton stage solve                                                           | `T_imp!` + Jacobian | stage          | `measured` | `measured` | `measured` | `Q_solve_defect` carries the unconverged part                                                                                                |
| `limiters_func!` → SEM quasimonotone limiter                                 | `lim!`              | yes            | `measured` | `measured` | `measured` | `Q_correction`                                                                                                                               |
| `limiters_func!` → `rescale_water_tags!`                                     | `lim!`              | yes            | `zero`     | `zero`     | `zero`     | tag-only, sums to the parent by construction                                                                                                 |
| `limiters_func!` → `enforce_mass_energy_consistency!`                        | `lim!`              | yes            | `measured` | `zero`     | `measured` | `Q_correction`; moves `ρ` by `Δρq_tot` and `ρe_tot` by `Δρq_tot·(uᵥ(T)+Φ)`                                                                   |
| `limiters_func!` → vertical mass borrowing limiter                           | `lim!`              | yes            | `measured` | `measured` | `measured` | `Q_correction`                                                                                                                               |
| `dss!`                                                                       | `dss!`              | yes            | `measured` | `measured` | `measured` | conservative in exact arithmetic on a closed sphere, so the measured amount is expected at reduction level and is a **finding if it is not** |
| `constrain_state!` → `prescribe_flow!`                                       | `constrain_state!`  | yes            | `n/a`      | `n/a`      | `n/a`      | prescribed overwrite; out of scope, never a physical tendency                                                                                |
| `constrain_state!` → `tracer_nonnegativity_constraint!`                      | `constrain_state!`  | yes            | `measured` | `measured` | `unknown`  | `Q_correction`; the energy leg must be read, not inferred                                                                                    |
| `constrain_state!` → `enforce_physical_constraints!`                         | `constrain_state!`  | yes            | `measured` | `measured` | `measured` | `Q_correction`                                                                                                                               |
| `constrain_state!` → `repair_water_tag_partition!`                           | `constrain_state!`  | yes            | `zero`     | `zero`     | `zero`     | tag-only, sum preserved by construction                                                                                                      |
| `set_precomputed_quantities!`                                                | `cache!`            | no             | —          | —          | —          | cache; never booked                                                                                                                          |
| `set_implicit_precomputed_quantities!`                                       | `cache_imp!`        | no             | —          | —          | —          | cache; never booked                                                                                                                          |
| `flux_accumulation!`                                                         | discrete callback   | no             | —          | —          | —          | mutates `Ref`s in `p` only                                                                                                                   |
| `external_driven_single_column!`                                             | discrete callback   | no             | —          | —          | —          | refreshes forcing caches only                                                                                                                |
| `rrtmgp_solver_callback!`                                                    | discrete callback   | no             | —          | —          | —          | fills the radiation cache; the state effect arrives through `radiation_tendency!`                                                            |
| `nan_checking_callback`, `checkpoint_callback`, `gc_callback`, diagnostics   | discrete callbacks  | no             | —          | —          | —          | read-only with respect to `Y`                                                                                                                |
| `Setups.initial_state` / `overwrite_initial_state!` / `overwrite_from_file!` | initialization      | yes            | `n/a`      | `n/a`      | `n/a`      | sets `B⁰`; outside every transaction                                                                                                         |
| `handle_restart`                                                             | initialization      | yes            | `measured` | `measured` | `measured` | a **zero-duration transition** of its own, never charged to the next step                                                                    |

`update_constrain_state_every` decides how often the `constrain_state!` rows
fire. At the default `"step"` there is one firing per transaction. At `"stage"`
there is one per stage, and each is its own leg.

## What is not yet covered, and what it blocks

| Gap                                               | Blocks                                                                     |
|:------------------------------------------------- |:-------------------------------------------------------------------------- |
| `Yₜ_lim` channel unread                           | water closure, and energy closure wherever a limited tracer carries energy |
| Implicit accepted-stage weights unestablished     | ladder rung 2 for implicit terms                                           |
| `correct_implicit_advection_tendency!` unmeasured | closure in every configuration with upwinding on, which is the default     |
| Energy leg of the nonnegativity paths unread      | energy closure in moist configurations                                     |
| Coupled surface legs unmeasured                   | the coupled-view cancellation claim                                        |
| `ΔM` of the prescribed forcing paths unread       | mass closure in forced single-column runs                                  |

Every one of these is a `unknown` that a later pull request turns into
`measured` or `zero`. None of them is allowed to become `zero` by assumption.
