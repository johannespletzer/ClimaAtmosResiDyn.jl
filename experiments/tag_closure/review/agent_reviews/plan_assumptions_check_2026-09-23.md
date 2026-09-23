# G3_PLAN against the merged #95: the assumptions check (WP0)

G3 WP0's first item. On 2026-09-23, after #95 merged (`0b2b1032`, head
`b9c6e7b0`), a `clima-inventory-explorer` agent checked G3_PLAN's assumptions
and file:line citations in sections 0, 3, 4.1 to 4.8 and 8 against `src/` at
that commit. It read only. This session wrote up its report, and fixed
G3_PLAN where noted at the end.

## What holds

Every citation of section 3's table holds at its line or within three lines:

  - the SGS mass flux, `edmfx_sgs_flux.jl:28-175`, called at
    `implicit_tendency.jl:118`, with a tracer loop (`:134-171`) that the
    water tags never enter, since they have no updraft field;
  - the SGS diffusive flux, `:213-427`, with `q_tot_eff` at `:315-333`, the
    tags' generic path at `:390-400`, and the updraft-mirror gate
    `apply_sgs_updraft` at `:231-233`, applied at `:328-333` and `:410-418`;
  - hyperdiffusion `hyperdiffusion.jl:496` against `:548`, and in the updraft
    `:555` against `:618`; the sponge `viscous_sponge.jl:197` against `:228`;
  - the copies' clamp `mass_flux_closures.jl:301-314` (the plan said
    `303-316`), a generic loop that would cover copies unchanged;
  - the updraft's 1M sedimentation, `advection.jl:439-440`,
    `updraft_sedimentation!` at `:539`, and its lateral term at `:561`;
  - 0M microphysics `microphysics/tendency.jl:101-133` and 1M `:153-191`;
  - water sedimentation, `water_advection.jl:41-218`. The water tags get only
    `sediment_water_tags!` (`:95`), the grid mean's flux. The EDMF corrections
    (`:137-215`) call the energy tags' version (`:204-213`) and have no
    counterpart for water;
  - the surface boundary, `edmfx_boundary_condition.jl:337-384`;
  - vertical advection, `implicit_tendency.jl:252` and `:395`;
  - the order in `constrain_state!`: the rescale inside
    `tracer_nonnegativity_constraint!` (`constrain_state.jl:44`), then the
    physical constraints (`:45`), then the repair (`:48`);
  - the implicit `ρa` overwrite at `initialize_implicit_problem.jl:291`,
    documented at `:260-277`;
  - the snapshot at `implicit_tendency.jl:66` and the sedimentation call at
    `:340`.

**No Jacobian block for the tags' SGS mass flux.** `sgs_massflux_jacobian_blocks`
(from `manual_sparse_jacobian.jl:394`) loops over the microphysics and
sedimenting species only. The parent's `(ρq_tot, q_totʲ)` block is at
`:2133-2136`.

**#95's exchange is as decision 5 says.** In `energy_source_tags.jl`:
`sgs_exchange_of_energy_source_tags!` (`:1797`), the plume `_plume_level` and
`_plume_step` (`:1974`, `:1986`), `_exchange_room` (`:2013`),
`_exchange_energy_ratio` (`:2022`), `ShareDifferences` (`:2032-2066`),
`_partition_blend_factor` (`:2071`) and `_blend_factor` (`:2082`). The partition
tags share one factor, and each source tag has its own. The scratch
(`:448-468`) holds the environment's density, the room and the energy ratio:
three scalars, written at `:1822-1823` and `:1896-1899`. `ShareDifferences`,
the partition totals, `_subdomain_share`, the upwinding and the face flux do
not depend on the weight, so the water tags can reuse them (plan 4.6). The
moist static energy, `c` and the offset are energy's alone.

**No per-subdomain split of the 0M sink exists.** The water tags bracket the
whole cell's `Δ` and split it by sign only (`tagged_water.jl:301-334`), while
`microphysics_tendency!` does form the `ρa⁰` and `ρaʲ` parts (plan 4.4).

**None of WP1's refusals exist yet.** `check_water_tagging_supported`
(`tagged_water.jl:157`, `:175-191`) dispatches on the microphysics model only.
Nothing refuses `water_tracers` under `prognostic_edmfx` or AMD LES, and
nothing warns under `PrescribedFlow`. Only `res` is a reserved tag name
(`tracer_config.jl:508-519`). The diagnostics `q_tag_fix_<name>`
(`tagged_water_diagnostics.jl:150`) and `e_src_fix_<name>`, `e_src_inc_left`,
`e_src_inc_moved` (`energy_source_tag_diagnostics.jl:82`, `:143`, `:162`)
already exist, so the collisions the plan names are real today.

## What does not hold, most consequential first

 1. **Plan 4.3 cites `advection.jl:124` for the skipped vertical advection.**
    That line skips the energy tags in `horizontal_tracer_advection_tendency!`.
    The vertical skip that WP5 mirrors is at `advection.jl:257`, in
    `explicit_vertical_advection_tendency!`.
 2. **No restart guard exists for `water_tracers`.** `restart.jl:63-90` calls
    only `check_energy_source_checkpoint`, which checks the energy families and
    `water_process_record` (`energy_source_checkpoint.jl:182-185`). A restart
    with changed water tags is not refused today. Plan 4.7 reads as if a water
    guard existed to extend. WP3 has to build it.
 3. **A refusal in `check_water_tagging_supported` would also refuse
    `water_process_record`.** It is called from `tracer_config.jl:1368` for the
    tags and `:1442` for the records. Plan 4.8 keeps the records allowed, so
    WP1's refusals need their own check.
 4. **A sixth `q_tot_eff` leak path, on the sphere only:** the horizontal SGS
    diffusive flux, `edmfx_sgs_flux.jl:444-595`, with `q_tot_eff` at `:488-498`
    and the tags' generic path at `:556-571`, and the same updraft-mirror gate.
    A column has no horizontal gradient, so V-W0c cannot size it.
 5. **The water tags already have a sedimentation Jacobian diagonal**
    (`manual_sparse_jacobian.jl:1265-1329`,
    `update_water_tag_sedimentation_jacobian!`). "No Jacobian block" is true
    for the SGS mass flux and the exchange only. WP3 and WP4b extend that
    diagonal rather than create one.
 6. **The known issues live in `docs/known_issues.md`,** not under
    `docs/src/`. Issue 3 cites `edmfx_sgs_flux.jl:106` and `:121`, which have
    moved. WP1 refreshes them when it restates the issue.
 7. **"ARS222 passes the stepper check"** is not asserted in code.
    `check_energy_source_increment_supported` (`energy_source_tags.jl:2318-2389`)
    names ARS222 as an example only. It is true in practice, since D4's
    increment runs used ARS222, but WP5 should test it.
 8. Line drifts of one to three lines, which change no claim:
    `mass_flux_closures.jl`, `advection.jl:440`, `manual_sparse_jacobian.jl:2136`.

The plan's §1 numbers from the review (the inventory bound, the zero sums)
cannot be checked from code.

## What this session changed in G3_PLAN

  - 4.3 cites `advection.jl:257` for the vertical skip.
  - 4.7 says no water-tag restart guard exists and WP3 builds it.
  - 4.8 says WP1's refusals get their own check, apart from
    `check_water_tagging_supported`.
  - 4.2 names the sixth leak path, for the sphere.
  - 4.1 notes the existing sedimentation diagonal.
