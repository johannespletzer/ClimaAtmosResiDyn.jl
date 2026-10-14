# Rain and Snow Tags

`water_tag_precipitation: true` splits each water tag into three parts: the
water that is neither rain nor snow, rain, and snow. It is off by default and
Experimental. With it on, every model field that exists without the tags stays
bit for bit as in the same run without them, under the default solver settings
(see the [parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)). The tags themselves are described in
[Tagged Water Tracers](tagged_water.md).

## Rain and snow parts

Each part is a share of one compartment of the parent:

| field            | holds                              | the partition's parts sum to                                        |
|:---------------- |:---------------------------------- |:------------------------------------------------------------------- |
| `ρq_tag_<name>`  | vapour, cloud liquid and cloud ice | ``\rho q_\mathrm{tot} - \rho q_\mathrm{rai} - \rho q_\mathrm{sno}`` |
| `ρq_rtag_<name>` | rain                               | ``\rho q_\mathrm{rai}``                                             |
| `ρq_stag_<name>` | snow                               | ``\rho q_\mathrm{sno}``                                             |

So under this key `ρq_tag_<name>` holds only the non-precipitating water. The
tag's total water is the sum of its parts, and `q_tag_<name>` reports that sum.
Each part starts as its masked share of its compartment. A tag with a `source`
starts at zero in every part.

```yaml
microphysics_model: "1M"
water_tag_precipitation: true
water_tracers:
  - name: lower
    region: {type: tanh_altitude, z_center: 3000.0, width: 300.0, above: false}
  - name: upper
    region: {type: tanh_altitude, z_center: 3000.0, width: 300.0}
```

The key needs 1-moment microphysics. It is refused under
`turbconv: prognostic_edmfx` and `edonly_edmfx`, and with
`water_tag_updraft_copy: true`. A checkpoint written with the key restarts only
with it, and one written without it only without it.

## How the parts move

  - **Sedimentation.** Rain and snow fall in their own parts, by their
    species' operator and Jacobian block. The cloud falls in `ρq_tag_<name>`
    by the tag's share of the non-precipitating water.
  - **Advection.** Every part is advected as a tracer. Under
    `water_tag_transport: increment` each rain and snow part keeps its explicit
    advection and gives it back to its tag's non-precipitating part, so that
    part follows the parent's implicit increment.
  - **Diffusion.** Rain and snow take no vertical diffusion, hyperdiffusion or
    viscous sponge, so neither do their parts. The non-precipitating parts
    diffuse as the parent's diffusing water.
  - **Microphysics.** The 1-moment scheme moves water between the compartments.
    The tags follow it with six gross flows between the compartments
    ([`ClimaAtmos.WATER_TAG_FLOW_NAMES`](@ref)). Each flow carries the
    composition of the compartment it leaves, over the step. The flows sum to the
    model's tendency to rounding. The remainder, or all of the change where the
    flows are not available, moves by the net-flow rule. Under that rule, a
    compartment that loses gives its own composition, and one that gains takes the
    losers' compositions weighted by their losses. The flows are summed over the
    substeps, and the tags move once per model step.
  - **Limiters and constraints.** A correction that changes a compartment moves
    the change between the part and the tag's non-precipitating part. Floors
    keep every part non-negative. The non-precipitating parts take the change
    of ``\rho q_\mathrm{tot}`` by the rule of
    [`ClimaAtmos.rescale_water_tags!`](@ref). The changes that raise the
    non-precipitating water ``N`` go first and those that lower it last: rain
    falls, snow falls, ``\rho q_\mathrm{tot}`` rises, rain rises, snow rises,
    ``\rho q_\mathrm{tot}`` falls. So where ``N`` is positive before and
    after, it stays positive in between, and its parts keep their water. Where
    ``N`` starts below zero, the falls of rain and snow can give its parts
    water before a rise of ``\rho q_\mathrm{tot}`` reaches them. The grid-mean constraint of 1-moment microphysics clips
    the condensates each time the state is constrained, so this runs every
    step.
  - **Closing step.** After each follow, the partition's rain parts are brought
    to the non-negative part of ``\rho q_\mathrm{rai}``, and its snow parts to
    that of ``\rho q_\mathrm{sno}``
    ([`ClimaAtmos.water_tag_part_closing_shift`](@ref)). The parts take the
    difference by their own composition, or, where they hold none, by the
    non-precipitating composition. Other paths can leave the parts apart from
    their compartment where it is negative: the microphysics, the
    sedimentation, and the advection, which can take a compartment below zero
    on a sphere. The closing step changes the tags' totals. Its own ledger,
    `q_tag_led_close`, takes what it moves, beside each tag's
    `q_tag_fix_<name>`. A compartment at zero empties its parts exactly.
    Closure needs a composition to give: parts of the compartment, or
    non-precipitating parts, that hold water. Where neither does, the step
    moves nothing, and the difference stays in `q_rtag_res` or `q_stag_res`.
    Elsewhere those residuals stay at rounding after each constrained state,
    and the closing step's work shows in its ledger instead. A closed
    compartment is not a correct attribution. The closing step gives the
    missing water the composition it finds in the cell, not that of the
    transfer that left the parts short. Each tag's error is at most the
    water the step moves, so `q_tag_led_close` bounds it. In a cell whose rain
    came from one tag and whose missing rain came from the other, the step
    gives all of the missing rain to the first.
  - **Repair.** The partition repair runs on each compartment's parts, among
    themselves.
  - **Vapour nonnegativity tendency.** When it is configured, it lifts negative
    rain and snow from vapour. Their parts take the non-precipitating
    composition by the net-flow rule.

The hyperdiffusion takes each non-precipitating part as a passive tracer, on
``\rho q_{\mathrm{tag},i}/\rho``, and gives it its share ``\varphi_i`` of the
reference profile's term, ``\varphi_i \nu_4 \nabla\cdot(\rho \nabla\nabla^2 q_\mathrm{tot,r})``
([`ClimaAtmos.apply_water_tag_hyperdiffusion!`](@ref)). The parent
hyperdiffuses ``q_\mathrm{tot,eff} - q_\mathrm{tot,r}``, so where the
partition's non-precipitating parts sum to their compartment, they sum to its
tendency. Where they do not, the parent also hyperdiffuses the residual
`q_ntag_res` and the tags do not, so the sums differ by that residual's
hyperdiffusion. The share stays outside the operator. Inside it, a
tag's composition would mix against its gradient wherever
``q_\mathrm{tot,eff}`` is below ``q_\mathrm{tot,r}``. ``q_\mathrm{tot,r}`` is
zero above the 250 hPa level, so that happens below it, in air drier than the
reference profile. The share's term is not in flux form. So the hyperdiffusion
does not keep each tag's global inventory. Tag ``i`` gains
``\int \varphi_i \nu_4 \nabla\cdot(\rho \nabla\nabla^2 q_\mathrm{tot,r})\,dV``,
and these gains sum to zero over the partition where it holds water.
The tags' sum does not follow the parent's hyperdiffusion in two cases. One is where the partition holds none of the non-precipitating water,
so every share is zero and the tags take no part of the reference profile. The
other is where the non-precipitating water is negative, so its parts partition
zero and the tags do not diffuse its negative part. `q_tag_leak_hyperdiff`
reports the rate that results. The second case is not special to the
hyperdiffusion. The vertical diffusion and the viscous sponge also take the
parts on their values and the parent on the diffusing water, so where that
water is negative they too move the parent by its negative part and the tags
not. `q_tag_leak_vdiff` and `q_tag_leak_sponge` report those rates. The other
leak diagnostics read zero, since EDMF and the copies are refused with the key.
Each leak is the raw difference, as without the key: the path's tendency of the
parts' sum minus its tendency of the parent. It is taken where the parts sum to
the target ``\max(N, 0)``, with ``N`` the water that is neither rain nor snow.
So it includes the path's transport of the negative part, and it is the path's
source of `q_tag_res + q_tag_negative`, with the opposite sign. For the
hyperdiffusion it also holds ``1 - \sum_i \varphi_i`` times the reference
profile's term.

The composition of the compartment a flow leaves is taken over the step
([`ClimaAtmos.water_tag_pool_shares`](@ref)): the compartment's water at the
start, mixed with what flowed into it during the step. Water can pass through a
compartment within one step, as rain that forms and evaporates again. The start
alone would give an empty compartment no composition to pass on.

## Outputs

  - `q_tag_<name>`, `q_ntag_<name>`, `q_rtag_<name>` and `q_stag_<name>`: the
    tag's total water and its three parts.
  - `pr_tag_<name>`: the tag's share of `pr`. It is the flux of its rain and
    snow parts and of its share of the cloud at the bottom face, built from the
    same level-1 values, terminal velocities and extrapolated surface density
    as `pr`. The partition's `pr_tag` sums to `pr` wherever its rain and snow
    parts sum to ``\rho q_\mathrm{rai}`` and ``\rho q_\mathrm{sno}`` at the
    lowest level.
  - `q_tag_res`, `q_ntag_res`, `q_rtag_res` and `q_stag_res`: `q_tag_res` and
    the closure check sum all three parts of the partition. Each compartment
    has its own residual.
  - `q_rtag_aud_<name>` and `q_stag_aud_<name>`: audit fields. The microphysics
    writes, per tag, the net-flow rule's change of its rain and snow parts less
    the change the gross flows gave. Where rain forms and evaporates in one
    step, the net-flow rule gives the evaporated water the rain's composition
    only for the net, and the audit shows the difference. The fields are
    cumulative and carried through restarts. They are state fields, on by
    default. `water_tag_precipitation_audit: false` leaves them and their two
    extra solves per tag out. The parts are the same either way.

With first-order tracer upwinding the rain and snow parts' transport is linear,
and each compartment closes to rounding under `increment` on a column. The
default `vanleer_limiter` is nonlinear per field, so the parts drift from
their species as the tags drift from ``\rho q_\mathrm{tot}``. The closing
step brings the rain and snow parts back each time the state is constrained.
The non-precipitating parts keep their drift, which `q_ntag_res` reports. The
repair only removes negative parts.

## Negative water

`ρq_tot` is not kept non-negative by default. The water tags partition its
non-negative part, and where it is negative they partition zero (see
[Configuring Tracers](tracer_configuration.md)). Under this key the same rule
applies to each part separately. The non-precipitating parts partition the
non-negative part of
``\rho q_\mathrm{tot} - \rho q_\mathrm{rai} - \rho q_\mathrm{sno}``, the rain
parts that of ``\rho q_\mathrm{rai}`` and the snow parts that of
``\rho q_\mathrm{sno}``. Where a correction takes rain or snow across zero at
fixed ``\rho q_\mathrm{tot}``, the non-precipitating parts also take the
change of that compartment's negative part, by their composition. So the tags'
totals change by it. This is a numerical convention, not a physical pathway.

`q_tag_negative` is the sum of the three compartments' negative parts. It can
be non-zero where ``\rho q_\mathrm{tot}`` is positive, for example where rain
is slightly negative. Without the key it is the negative part of
``\rho q_\mathrm{tot}`` alone, so its values with and without the key do not
compare. `q_tag_res`, `q_tag_negative` and the partition's parts add up to
``q_\mathrm{tot}``, to rounding. The water closure check's
`negative_water_void` reads the raw ``\rho q_\mathrm{tot}`` only, by the
owner's decision of 2026-09-25. So negative rain or snow in a cell whose
``\rho q_\mathrm{tot}`` is positive does not void the check. It shows in
`q_tag_negative` and in each compartment's residual. Under `water_tag_transport: increment` the
correction after each solve takes the increment of the non-precipitating water's
target, and `q_tag_inc_negative` holds what it gives the tags for that water's negative
part. Where no compartment is negative, nothing changes, bit for bit.

A transfer into a negative compartment takes the target's treatment. In a cell
where a compartment is below zero, a flow that touches it is read in its actual
direction, and its parts take no microphysics change. Its pool starts empty, so
it passes on only what came in, with that water's composition. What it keeps
fills its negative part, and what it gives beyond its inflow carries no tag's
water and lands in `q_tag_res`. The net-flow rule gives a negative compartment
no gain. The ledgers `q_tag_exp_negative` and `q_tag_exp_negative_precip`
record what the negative non-precipitating water and the negative rain and
snow keep.

## Limits and cost

  - Without EDMF only. Updraft copies are refused.
  - Only 1-moment microphysics.
  - The three parts cost three fields per tag, two audit fields per tag unless
    `water_tag_precipitation_audit: false`, and the flows. The flows evaluate the microphysics rates again, so their cost is of
    the same order as the microphysics.

## Rain and snow tags API

```@docs
ClimaAtmos.has_water_tag_precipitation
ClimaAtmos.has_water_tag_precipitation_audit
ClimaAtmos.WaterTagPart
ClimaAtmos.NonPrecipitatingPart
ClimaAtmos.water_tag_part_field
ClimaAtmos.water_tag_part_parent
ClimaAtmos.water_tag_parent
ClimaAtmos.water_tag_part_target
ClimaAtmos.water_partition_target
ClimaAtmos.water_tag_part_share
ClimaAtmos.is_water_precip_part_name
ClimaAtmos.is_water_tag_audit_name
ClimaAtmos.water_tag_precip_part_state_names
ClimaAtmos.water_tag_audit_state_names
ClimaAtmos.water_partition_state_names
ClimaAtmos.water_precip_part_names
ClimaAtmos.water_tag_sedimenting_mass_names
ClimaAtmos.update_water_precip_part_sedimentation_jacobian!
ClimaAtmos.WATER_TAG_FLOW_NAMES
ClimaAtmos.WaterTagFlows1M
ClimaAtmos.water_tag_1m_flows
ClimaAtmos.water_tag_1m_flows_grid_mean
ClimaAtmos.set_water_tag_microphysics_flows!
ClimaAtmos.water_tag_gross_flow_change
ClimaAtmos.water_tag_pool_shares
ClimaAtmos.water_tag_net_flow_change
ClimaAtmos.water_tag_microphysics_change
ClimaAtmos.water_tag_oriented_flows
ClimaAtmos.water_tag_microphysics_withheld
ClimaAtmos.water_tag_negative_compartments
ClimaAtmos.water_tag_microphysics_audit
ClimaAtmos.water_tag_precipitation_microphysics_tendency!
ClimaAtmos.snapshot_water_tag_precipitation_tendency!
ClimaAtmos.snapshot_water_tag_precipitation!
ClimaAtmos.follow_water_tag_precipitation!
ClimaAtmos.water_tag_part_follow_shift
ClimaAtmos.water_tag_source_part_follow_shift
ClimaAtmos.water_tag_part_closing_shift
ClimaAtmos.water_tag_moves_precip_advection
ClimaAtmos.water_tag_precip_advection!
ClimaAtmos.water_tag_hyperdiffusion_quantities
ClimaAtmos.prep_water_tag_hyperdiffusion!
ClimaAtmos.apply_water_tag_hyperdiffusion!
ClimaAtmos.water_tag_precipitation_flux!
ClimaAtmos.water_tag_precipitation_from_config
ClimaAtmos.water_tag_precipitation_audit_from_config
ClimaAtmos.check_water_tag_precipitation_supported
ClimaAtmos.rebuild_water_tags_from_state!
ClimaAtmos.water_tag_precipitation_audit_variables
```
