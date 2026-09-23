# Energy Source Tags: a user guide

This page is for running the energy source tags and reading what they give you.
[Energy Source Tags](energy_source_tags.md) is the reference: it says what each
rule is and why. Start here, go there when a number surprises you.

The tags answer one question: **of the moist energy in this cell now, how much
came from each place or process?** They split the total into named parts that
add up to it, and they follow it as the model moves it.

They do not change the simulation: every model field is bit for bit what it
would be without them, under the solver settings the tags support. A Newton
solve that stops on a residual norm taken over the whole state is the
exception, since the tags are part of that state; use a fixed iteration count
or a direct solve, which the increment transport requires anyway.

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
# The energy reference the tags partition. Required.
energy_source_tag_offset: 110495.0
# How the tags move. Use this one under EDMF.
energy_source_tag_transport: "enthalpy_increment"
# Watch the closure once a day, and write the audit table.
energy_source_closure_check:
  period: "1days"
  audit: true
```

The region tags without sources are the **partition**: their masks must sum to
one everywhere, so configure exactly one region and its complement. The tags
with a `source` are separate fractions of the same total, and they may overlap
the partition freely. The entry schema and the named regions are in
[Configuring Tracers](tracer_configuration.md).

## What you get

| Where                           | What                                                                                       |
|:------------------------------- |:------------------------------------------------------------------------------------------ |
| `e_src_<name>`                  | the tag's energy per unit mass, J kg⁻¹                                                     |
| `e_src_res`                     | the partition's closure residual, J kg⁻¹                                                   |
| `e_src_fix_<name>`              | what the repair moved into or out of the tag, cumulative in the run segment                |
| `energy_source_tag_closure.csv` | one row per check: the residual, gross and relative                                        |
| `energy_source_tag_audit.csv`   | with `audit: true`: untagged, overclaimed, the repair's total, and the correction's ledger |

Add the tags to a `diagnostics` block the same way as any other short name.

## The choices, and what to set them to

| Key                              | Default        | Set it to                                                                                                                                                |
|:-------------------------------- |:-------------- |:-------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `energy_source_tag_offset`       | none, required | 110495.0 unless you have a reason. It makes the partitioned total positive, which the donor rule needs. It is a convention, and the tags depend on it    |
| `energy_source_tag_transport`    | `tracer`       | `enthalpy_increment` under EDMF or implicit diffusion. `tracer` only when you want the tags to ride the plain tracer path                                |
| `energy_source_tag_repair`       | `true`         | leave on, unless you want to see what the attribution rule alone produces                                                                                |
| `energy_source_tag_updraft_copy` | `false`        | leave off. `true` is the audit: a copy of each tag in the updraft, moved by the model's own tracer machinery. A cold build takes about six times as long |

Under `prognostic_edmfx` the tags need `updraft_number: 1`, and the model
refuses more.

## Reading the result

The check warns above a default level that follows the transport, 1.0 under
`tracer`, 0.1 under `enthalpy` and 0.01 under `enthalpy_increment`. They sit
7.1, 1.7 and 50 times above the largest value each transport reached in the
runs they were calibrated from, so they are guards against a runaway, not a
judgement on a run, and the margin differs by transport. Set `tolerance` in
the block once you know where your own configuration settles.

**Start with the closure table.** `gross_relative` is the partition's residual
over the total it partitions, which the offset enters, and it covers the
partition only, not the source tags. Under `enthalpy_increment` it runs from
about 1e-6 after an hour on a column to 2e-4 after ten days on a sphere in
Float32; under `tracer` and `enthalpy` it is 1e-3 to 1e-1, since those
transports do not follow the parent's own fluxes.
What matters is less its size than its trend: it should slow, and the rows
since the spin-up should not grow faster than the first ones.

**Then the audit table.** `untagged` and `overclaimed` split the residual by
sign. `repair_moved` is the size of the repair's *net* accumulated correction
per tag: it adds each change with its sign and takes the absolute value at the
end. A large value means the repair is holding a tag's profile up. A small one
does not mean the repair was idle, since corrections in opposite directions
cancel in it. Under `enthalpy_increment`, `increment_left` is the
part of the parent's implicit increment that the correction could not move
inside a column. It usually explains most of the residual.

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
 5. You know your `c`, and you quote it with the result. Doubling it moved a
    column's source tags by 4 to 6% in a day.
 6. If the run has convection, you know which mixing convention you used: the
    default exchange, or the audit's updraft copies. On a column they agree to
    better than 1% after a day.

## Caveats

  - **The residual is monitored, not enforced.** Nothing drives `e_src_res` to
    zero. That is deliberate: it is the leakage monitor, and a correction that
    zeroed it would hide what it measures.
  - **Some energy changes reach no bracket.** The `c·Δρ` that comes with mass
    changes in processes the tags do not bracket, and, under the `tracer`
    transport, the pressure work the parent carries in enthalpy form, land in
    the residual rather than in a tag.
  - **Sub-grid convection is a convention.** By default the tags have no
    updraft copy. They take their share of the parent's sub-grid flux and
    exchange provenance at the mass flux, from a steady plume.
    `energy_source_tag_updraft_copy: true` is the audit that measures how good
    that is. The copies are a comparator, not ground truth: they take the
    environment's composition for the surface's buoyant air, the model filters
    them, and their flux needs the same post-solve correction. The plume adds
    the assumption that the updraft adjusts faster than the shares change. The sedimentation corrections take the grid mean's shares either
    way.
  - **`e_src_fix_<name>` restarts at zero.** It is cumulative within a run
    segment, not across restarts. Stitch the segments yourself if you want the
    whole history.
  - **The offset `c` is a choice with consequences.** It sets how long the
    initial-energy tags are remembered, and it is the reference that makes the
    shares meaningful. Keep one `c` across every run you compare. Before a run
    whose surface air can fall below about 228 K, choose it from a temperature
    floor instead, or the shares go to zero where the total does.
  - **Falling ice can pass provenance upward.** With the offset used here, ice
    carries negative `E`, so the cell below is the donor. A different `c` can
    flip that direction. It is the reference speaking, not the physics.
  - **Untested ground.** Topography with the tags, more than one updraft
    (refused), 2-moment microphysics, and the GPU. A run that takes its initial
    state from a file now builds the tags from what the file wrote, but no such
    run has been made with tags on.
  - **Provenance of energy is not provenance of air.** Ask the tags where the
    energy came from. For where the air came from, carry a passive tracer.

## Where to look next

  - [Energy Source Tags](energy_source_tags.md) for the rules, the audit, the
    increment prototype and the API.
  - [Process-Change Records](process_record.md) for what a process did, as
    opposed to where what is here came from.
  - [Configuring Tracers](tracer_configuration.md) for the entry schema, the
    named regions and the other tag families.
