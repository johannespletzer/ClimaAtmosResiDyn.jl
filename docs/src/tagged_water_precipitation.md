# Rain and Snow Tags

This page describes the rain and snow parts of the water tags, which
`water_tag_precipitation: true` switches on. The tags themselves are described
in [Tagged Water Tracers](tagged_water.md).

## Rain and snow parts

`water_tag_precipitation: true` gives each tag three parts, as the design note
WP4b-D recommends (`design/RAIN_SNOW_TAGS.md` on the record branch):

| field            | holds                              | the partition's parts sum to                                        |
|:---------------- |:---------------------------------- |:------------------------------------------------------------------- |
| `ρq_tag_<name>`  | vapour, cloud liquid and cloud ice | ``\rho q_\mathrm{tot} - \rho q_\mathrm{rai} - \rho q_\mathrm{sno}`` |
| `ρq_rtag_<name>` | rain                               | ``\rho q_\mathrm{rai}``                                             |
| `ρq_stag_<name>` | snow                               | ``\rho q_\mathrm{sno}``                                             |

So under the key `ρq_tag_<name>` holds only the non-precipitating water. The
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
`water_tag_updraft_copy: true`: those are stages 2 and 3 of the note. A
checkpoint written with the key restarts only with it, and one written without
it only without it.

What moves the parts:

  - **Sedimentation.** Rain falls in each tag's rain part and snow in its snow
    part, by the species' own operator applied to the part, as if the part
    were the species. That is linear, so each part's Jacobian block is its
    species' block, value for value, and the split solver solves each part
    apart. The cloud falls in `ρq_tag_<name>` by the tag's share of the
    non-precipitating water, with cross blocks to the cloud species only.

  - **Advection.** Every part is advected as a tracer, as rain and snow are.
    Under `water_tag_transport: increment` the non-precipitating parts follow
    the parent's implicit increment of ``\rho q_\mathrm{tot} - \rho q_\mathrm{rai} - \rho q_\mathrm{sno}``. ``\rho q_\mathrm{tot}`` is advected
    implicitly with its rain and snow, while ``\rho q_\mathrm{rai}`` and
    ``\rho q_\mathrm{sno}`` are advected explicitly. So each rain and snow part
    keeps its explicit advection and gives it back to its tag's
    non-precipitating part. The rain and snow parts follow their own implicit
    terms, which are their species' by construction.

  - **Diffusion.** Rain and snow take no vertical diffusion, hyperdiffusion or
    viscous sponge, so neither do their parts. The non-precipitating parts
    diffuse as the parent's diffusing water ``q_\mathrm{tot,eff}``, so the
    paths `q_tag_leak_<path>` measures are designed to leak nothing through
    the rain and snow. The hyperdiffusion takes each non-precipitating part as
    ``\nabla^2(\rho q_{\mathrm{tag},i}/\rho - \varphi_i q_\mathrm{tot,r})``,
    with ``\varphi_i`` its share of the compartment, as the parent takes
    ``q_\mathrm{tot,eff} - q_\mathrm{tot,r}``. Two gaps remain there. Where
    the partition holds none of the non-precipitating water, because it is
    not positive or every tag's part of it is at or below zero, every
    partition tag's share is zero. There the tags take no part of the
    reference profile ``q_\mathrm{tot,r}``. And where the non-precipitating
    water is negative, its parts partition zero (see *Negative water* below),
    so the tags do not diffuse its negative part. In both, the tags' sum does
    not follow the parent's hyperdiffusion. `q_tag_leak_hyperdiff` reports
    that rate under the key, from both gaps. It is not yet measured in a run.
    The other leak diagnostics read zero.

  - **Microphysics.** The 1-moment scheme moves water between the
    compartments. `water_tag_1m_flows` repeats the model's linearized
    substeps and decomposes each into six flows between the compartments:
    rain and snow formation, evaporation, sublimation, deposition, melting and
    the rain–snow collisions. Each flow carries its donor compartment's
    composition (the design note's section 9, the gross flows). The flows'
    net is the model's tendency to rounding. The rounding remainder moves by
    the net-flow rule. Where the flows are not available, that rule moves all
    of it.

    The flows are summed over the substeps, and the tags are moved once per
    model step. That is this key's definition of provenance over one step. It
    is coarser than moving the tags after every substep. Tests compare the
    two. On synthetic kinetics the difference falls by at least 1.8 each time
    the step halves. On the 1-moment scheme it does not fall at the steps
    tested. With 3 or 10 substeps, the largest difference over random states
    is up to 1.3% of the water the flows move at steps of 30 to 120 s. At
    15 s it is up to 5.0%, and 3.0% with 10 substeps. The mean is 0.06% to
    0.24%. It is not rounding: where it is largest it is at least 10⁷ times
    the test's tolerance. Moving the tags per substep would cost one
    composition solve per substep. Whether that is needed is to be decided
    from runs. No run reports this difference yet.

    The donor's composition is taken over the step, not only at its start
    (`water_tag_pool_shares`): the compartment's water at the start, mixed
    with what flowed into it during the step. The model's step lets water pass
    through a compartment, such as rain that forms and evaporates again, or
    snow that forms and melts. With the start alone, a compartment empty at
    the start passes on no composition, and on the integration test's column
    the rain parts then drifted from the rain by 20 times the rain. Where a
    compartment holds much more than passes through it, the two agree.

  - **Limiters and constraints.** A correction that changes a compartment
    moves the change between the part and the tag's non-precipitating part
    (section 8): a compartment that shrinks gives its own composition back,
    one that grows takes the non-precipitating composition, and a clip to
    zero returns the part to its tag's non-precipitating part. Floors keep
    every part non-negative. Then the non-precipitating parts take the change
    of ``\rho q_\mathrm{tot}`` by the rule of [`ClimaAtmos.rescale_water_tags!`](@ref).
    The grid-mean constraint of 1-moment microphysics clips and rescales the
    condensates every time the state is constrained, so this runs every step.

  - **The repair** runs on each compartment's parts, among themselves.

  - **The vapour nonnegativity tendency**, when configured, lifts negative
    rain and snow from vapour. Their parts take the non-precipitating
    composition by the net-flow rule.

**The audit.** The microphysics also writes, per tag, the net-flow rule's
change of its rain and snow parts less the change the gross flows gave, into
the state records `q_rtag_aud_<name>` and `q_stag_aud_<name>` (the note's
section 12). Both rules keep each tag's total, so the non-precipitating
part's difference is minus their sum. Where rain forms and evaporates in one
step, the net-flow rule gives the evaporated water the rain's composition only
for the net, and the audit shows the difference. The records are cumulative
and carried through restarts.

**Precipitation.** `pr_tag_<name>` is the tag's share of `pr`: the flux of its
rain and snow parts and of its share of the cloud at the bottom face, from the
same level-1 values, terminal velocities and extrapolated surface density as
`pr`. The partition's `pr_tag` sums to `pr` wherever its rain and snow parts sum
to ``\rho q_\mathrm{rai}`` and ``\rho q_\mathrm{sno}`` at the lowest level.
That tests the closure at one level only.

**Closure.** `q_tag_res` and the closure check sum all three parts of the
partition. Each compartment has its own residual: `q_ntag_res`, `q_rtag_res`
and `q_stag_res`. With first-order tracer upwinding the rain and snow parts'
transport is linear, and on the integration test's column each compartment
closes to rounding under `increment`. The default `vanleer_limiter` is
nonlinear per field, so the parts drift from their species as the tags drift
from ``\rho q_\mathrm{tot}`` today, and the repair only removes negative
parts.

**Negative water.** Known issue 7's option C applies per compartment. The
numerics can take a compartment below zero, and no set of non-negative parts
can partition a negative amount. So the non-precipitating parts partition the
non-negative part of ``\rho q_\mathrm{tot} - \rho q_\mathrm{rai} - \rho q_\mathrm{sno}``,
the rain parts that of ``\rho q_\mathrm{rai}`` and the snow parts that of
``\rho q_\mathrm{sno}``. The initial state, the rebuild from a file and the
corrections of the limiters and constraints aim at these targets. Where a
correction takes rain or snow across zero at fixed ``\rho q_\mathrm{tot}``,
the non-precipitating water changes by more than the rain or snow parts can
give or take. The non-precipitating parts then also take the change of that
compartment's negative part, by their composition, into the rescale's ledgers.
So the tags' totals change by it. Like option C without the key, this is a
numerical convention, not a physical pathway. `q_tag_negative` is the sum of
the three compartments' negative parts. So it can be non-zero where
``\rho q_\mathrm{tot}`` is positive, for example where rain is slightly
negative. Without the key it is the negative part of ``\rho q_\mathrm{tot}``
alone, so its values with and without the key do not compare. `q_tag_res`,
`q_tag_negative` and the partition's parts add up to ``q_\mathrm{tot}``, to
rounding. `q_tag_res` and the closure check compare the parts with the sum of
the three targets, and `q_ntag_res`, `q_rtag_res` and `q_stag_res` compare
each compartment's parts with its own target. Under
`water_tag_transport: increment` the follower takes the increment of the
non-precipitating water's target, and `q_tag_inc_negative` holds what it gives
the tags for that water's negative part. Where no compartment is negative,
nothing changes, bit for bit.

**Cost.** Three fields per tag, two audit records per tag, and the flows,
which cost about as much as the microphysics itself.

## Rain and snow tags API

```@docs
ClimaAtmos.has_water_tag_precipitation
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
ClimaAtmos.water_tag_microphysics_audit
ClimaAtmos.water_tag_precipitation_microphysics_tendency!
ClimaAtmos.snapshot_water_tag_precipitation_tendency!
ClimaAtmos.snapshot_water_tag_precipitation!
ClimaAtmos.follow_water_tag_precipitation!
ClimaAtmos.water_tag_part_follow_shift
ClimaAtmos.water_tag_source_part_follow_shift
ClimaAtmos.water_tag_moves_precip_advection
ClimaAtmos.water_tag_precip_advection!
ClimaAtmos.prep_water_tag_hyperdiffusion!
ClimaAtmos.water_tag_precipitation_flux!
ClimaAtmos.water_tag_precipitation_from_config
ClimaAtmos.check_water_tag_precipitation_supported
ClimaAtmos.rebuild_water_tags_from_state!
ClimaAtmos.water_tag_precipitation_audit_variables
```
