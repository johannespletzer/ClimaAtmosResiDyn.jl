# Energy Source Tags: a user guide

This page is for running the energy source tags and reading what they give you.
The `energy_source_tags` key switches them on. It is off by default, and it
needs `energy_source_tag_offset`. [Energy Source Tags](energy_source_tags.md) is
the reference: it says what each rule is and why. Start here, go there when a
number surprises you.

The tags answer one question: **of the moist energy in this cell now, how much
came from each place or process?** They split the total into named parts that
add up to it, and they follow it as the model moves it.

With the tags on, every model field that exists without them stays bit for bit
as in the same run with them off, under the default solver settings. Only the
tags' own fields and output are added. A Newton solve that stops on a residual
norm taken over the whole state is the exception, since the tags are part of
that state. Use a fixed iteration count or a direct solve, which the increment
transport requires anyway. See the
[parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
for its limits. The tags are attributions defined by the configured rules, not a
unique physical history, and they depend on `energy_source_tag_offset`.

## A first configuration

```yaml
# What to tag: a region and its complement, plus the processes you care about.
energy_source_tags:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
  - name: sfc
    source: surface_flux
  - name: rad
    source: radiation
# The offset c the tags add before they split. Required.
energy_source_tag_offset: 110495.0
# How the tags move. `tracer` is the default. `enthalpy_increment` is a
# prototype and follows the parent's implicit diffusion under EDMF.
energy_source_tag_transport: "enthalpy_increment"
# Watch the closure once a day, and write the audit table.
energy_source_closure_check:
  period: "1days"
  audit: true
```

The region tags, those without sources, are the **partition**. Their masks must
sum to one everywhere, so configure exactly one region and its complement. The
source tags, those with a `source`, are separate fractions of the same total.
They may overlap the region tags freely. The entry schema and the named regions are in
[Configuring Tracers](tracer_configuration.md).

## What you get

| Where                                            | What                                                                                                                                                                                                                                        |
|:------------------------------------------------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `e_src_<name>`                                   | the tag's energy per unit mass, J kg⁻¹                                                                                                                                                                                                      |
| `e_src_res`                                      | the partition's closure residual, J kg⁻¹                                                                                                                                                                                                    |
| `e_src_fix_<name>`                               | the fix ledger, what the repair moved into or out of the tag, cumulative since the run started                                                                                                                                              |
| `e_src_fixgross_<name>`, `e_src_fixcount_<name>` | beside it, the sum of the absolute changes and the number of changed cells, of every call, in Float64                                                                                                                                       |
| `e_src_led_repair`, `e_src_led_repairnet`        | the energy the repair moved between the partition's tags, and the energy it added where it zeroed every tag, as the steps retained them: state fields, through restarts; exact per step at the default `update_constrain_state_every: step` |
| `<ledger>_gross`, `<ledger>_colgross`            | for the ledgers above, `e_src_inc_left` and `e_src_inc_moved`: the sum over the steps of the change per cell and per column, in Float64, carried through a restart                                                                          |
| `energy_source_tag_closure.csv`                  | one row per check: the residual, gross and relative                                                                                                                                                                                         |
| `energy_source_tag_audit.csv`                    | with `audit: true`: untagged, overclaimed, the repair's total, and the correction's increment ledger                                                                                                                                        |

Add the tags to a `diagnostics` block the same way as any other short name.

## The choices, and what to set them to

| Key                                                       | Default        | Set it to                                                                                                                                                                                                                                                               |
|:--------------------------------------------------------- |:-------------- |:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `energy_source_tag_offset`                                | none, required | 110495.0 unless you have a reason. It makes the partitioned total positive, which the loss rule needs. It is a convention, and the tags depend on it                                                                                                                    |
| `energy_source_tag_transport`                             | `tracer`       | `tracer` for the plain tracer path. `enthalpy_increment`, a prototype, also follows the parent's implicit diffusion, which EDMF has. `enthalpy` is a comparison mode                                                                                                    |
| `energy_source_tag_repair`                                | `true`         | leave on, unless you want to see what the attribution rule alone produces                                                                                                                                                                                               |
| `energy_source_tag_updraft_copy`                          | `false`        | leave off. `true` is a comparison mode: a copy of each tag in the updraft, moved by the model's own tracer machinery                                                                                                                                                    |
| `energy_source_tag_increment_allow_explicit_microphysics` | `false`        | leave off. With `enthalpy_increment` the model refuses 2M or P3 stepped explicitly, where no run has shown that the tags close, and 1M stepped explicitly under `use_auto_jacobian: true`, which lacks the tags' cross blocks. `true` runs them anyway, for development |

Under `prognostic_edmfx` the tags need `updraft_number: 1`, and the model
refuses more.

## Reading the result

The check warns above a default level that follows the transport: 1.0 under
`tracer`, 0.1 under `enthalpy` and 0.01 under `enthalpy_increment`. By default
it never stops the run and never marks rows void. `abort_above` and `void_above`
in the block change that. The check runs daily and measures the residual since
spin-up, taken one hour in. The defaults are check levels that guard
against a runaway. They are not a judgement on a run. Set `tolerance` in the block once
you know where your own configuration settles.

**Start with the closure table.** `gross_relative` is the partition's residual
over the total it partitions, which the offset enters, and it covers the
partition only, not the source tags. It is smallest under
`enthalpy_increment`. Under `tracer` and `enthalpy` it is larger, since those
transports do not follow the parent's own implicit fluxes. What matters is less
its size than its trend. It should slow, and the rows since spin-up should not
grow faster than the first ones.

**Then the audit table.** `untagged` (parent the tags do not account for) and
`overclaimed` (tags' amount the parent does not have) split the residual by
sign. `repair_moved` is the size of the repair's *net* accumulated correction
per tag: it adds each change with its sign and takes the absolute value at the
end. A large value means the repair is holding a tag's profile up. A small one
does not mean the repair was idle, since corrections in opposite directions
cancel in it. Under `enthalpy_increment`, `increment_left` is the part of the
parent's implicit increment that the correction could not move inside a column.
It usually explains most of the residual.

**Then the tags themselves.** They are shares of energy, not of mass. A cell
whose air came half from the boundary layer does not hold half its energy from
there, because the two air masses carry different energy per kilogram.

## Is the answer trustworthy? A checklist

 1. `nonpositive_fraction` in the closure table is zero. Where the partitioned
    total is not positive, the shares mean nothing, and the offset is what fixes
    it.
 2. `gross_relative` is small for your purpose and slowing.
 3. `repair_moved` is small against the tags you are reading. It is a net
    figure, so treat it as a lower bound on how much the repair did.
 4. Under `enthalpy_increment`, `increment_left` accounts for most of the
    residual. What it does not account for is what no share follows yet.
 5. You know your `c`, and you quote it with the result. The tags change with
    it.
 6. If the run has convection, you know which mixing convention you used: the
    default exchange, or the comparison mode's updraft copies.

## Caveats

  - **The residual is monitored, not enforced.** Nothing drives `e_src_res` to
    zero. That is deliberate: it is the leakage monitor, and a correction that
    zeroed it would hide what it measures.
  - **Some energy changes reach no tag.** The `c·Δρ` that comes with mass
    changes in processes the tags do not attribute, and, under the `tracer`
    transport, the pressure work the parent carries in enthalpy form, land in
    the residual rather than in a tag.
  - **Sub-grid convection is a convention.** By default the tags have no
    updraft copy. They take their share of the parent's sub-grid flux and
    exchange composition at the mass flux, from a steady plume.
    `energy_source_tag_updraft_copy: true` is a comparison mode that measures how
    good that is. The copies are a comparator, not ground truth: they take the
    environment's composition for the surface's buoyant air, the model filters
    them, and their flux needs the same post-solve correction. The plume adds
    the assumption that the updraft adjusts faster than the shares change. The
    sedimentation corrections take the grid mean's shares either way.
  - **`e_src_fix_<name>` is carried through a restart.** The checkpoint holds
    it beside the state. A checkpoint without it starts it at zero, with a
    warning, and its totals then cover the new segment only.
  - **The offset `c` is a choice with consequences.** It sets how long the
    initial-energy tags are remembered, and it is the reference that makes the
    shares meaningful. Keep one `c` across every run you compare. Before a run
    whose surface air can fall below about 228 K, choose it from a temperature
    floor instead, or the shares go to zero where the total does.
  - **Falling ice can pass its origin upward.** With the offset used here, ice
    carries negative `E`, so the cell below gives up the energy and its shares
    apply. A different `c` can
    flip that direction. It is the reference speaking, not the physics.
  - **Untested ground.** Topography with the tags, 2-moment microphysics, and
    the GPU. More than one updraft is refused. A run that takes its initial
    state from a file builds the tags from what the file wrote. No such run has
    been made with tags on.
  - **The origin of the energy is not the origin of the air.** Ask the tags where
    the energy came from. For where the air came from, carry a passive tracer.

## Where to look next

  - [Energy Source Tags](energy_source_tags.md) for the rules, the comparison
    mode, the increment prototype and the API.
  - [Process-Change Records](process_record.md) for what a process did, as
    opposed to where what is here came from.
  - [Configuring Tracers](tracer_configuration.md) for the entry schema, the
    named regions and the other tag families.
