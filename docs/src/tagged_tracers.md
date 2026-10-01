# Tagged Energy Tracers

`energy_tracers` splits the total energy ``\rho e_\mathrm{tot}`` into named,
transported fields `ρe_tag_<name>`. A tag either holds a region's share of the
energy or accumulates what one process added. The key is off by default. With
it on, every model field that exists without the tags stays bit for bit as in
the same run without them, under the default solver settings. See the
[parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream) for its limits.

!!! warning "Energy, not heat and not temperature"

    The tagged variable is density-weighted moist total energy
    ``\rho e_\mathrm{tot}``. It is not temperature, and it is not heat. The
    methods usually meant by "temperature tagging" and "heat tagging" in the
    literature tag temperature and potential temperature respectively, so
    neither name describes what this family does. Do not call it heat tagging.

## What a tag means

A tag configured with `region` and a tag configured with `source` are different
kinds of quantity.

  - A **region tag** is a transported partition of ``\rho e_\mathrm{tot}``. It
    starts as the region's share of the energy present and receives every
    attributed process, weighted by its mask. The sum of a set of region tags
    can be checked against ``\rho e_\mathrm{tot}``.
  - A **signed process tag** is a tag configured with `source`. It starts at
    zero and accumulates the signed tendency that one labeled process adds to
    ``\rho e_\mathrm{tot}``. Heating adds and cooling subtracts, so the value
    can be negative.

A signed process tag is a history of what a process did, not a share of the
energy that is here now. Reading `e_tag_rad = -3.0e4` as "radiation supplied a
negative amount of the local energy" is a misreading. It says radiation has
removed that much more energy than it added since the tag started.

A signed process tag is also not a process-change record. A tag is transported
by the flow. A record is never transported and has one field per process, not
per tag.
See [Process-Change Records](process_record.md).

The `source` key is spelled the same in `water_tracers`, but the rule differs.
The water tags share out production by mask and take loss from each tag in
proportion to what it holds. The energy tags apply the whole signed tendency
by mask.

## Enabling tags

Tags are configured with one YAML block. No Julia code is needed.

```yaml
energy_tracers:
  - name: stratosphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0}
  - name: troposphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0, above: false}
  - name: rad
    source: radiation
  - name: rad_stratosphere
    region: {type: tanh_altitude, z_center: 12000.0, width: 1000.0}
    source: radiation
```

Each entry needs a unique `name` and a `region`, a `source`, or both. The
default `energy_tracers: ~` adds no state fields, no cache entries and no
runtime cost. Each tag is an ordinary grid-scale tracer `Y.c.ρe_tag_<name>`,
transported by the automatic tracer machinery (see [Tracers](passive_tracers.md)).
[Configuring Tracers](tracer_configuration.md) has the full entry schema and
the `energy_closure_check` block, which warns while the run goes.

## Region tags

A region tag starts as ``\rho e_\mathrm{tot} \, M(x)``, where the mask
``M \in [0, 1]`` uses smooth `tanh` transitions. A region and its complement
sum to exactly 1, so the pair partitions ``\rho e_\mathrm{tot}`` at
initialization to machine precision. The region types and the named regions are
in [Configuring Tracers](tracer_configuration.md).

Published reference regions, such as the IPCC AR6 domains, are polygons and map
onto `tanh_polygon`. Export the vertices once with
[`regionmask`](https://regionmask.readthedocs.io/) and paste them into the
config:

```python
import regionmask, yaml

region = regionmask.defined_regions.ar6.land["W.Africa"]
vertices = [[round(x, 3), round(y, 3)] for x, y in region.polygon.exterior.coords]
print(yaml.dump({"vertices": vertices}))
```

`regionmask` gives a sharp 0/1 mask. Do not use it as a mask. In the
spectral-element discretization a discontinuous mask produces Gibbs
oscillations. Choose the `width` of the `tanh_polygon` comparable to or larger
than the horizontal grid spacing.

## Signed process tags

A tag with a `source` accumulates the tendency that a labeled process adds to
``\rho e_\mathrm{tot}``. The `source` labels and the groups that expand to
several of them are listed in [Configuring Tracers](tracer_configuration.md).
`source` takes one label, a group name or a list, and the group `all` expands to
every label.

A process can be attributed only if the tags do not already receive it through
the tracer machinery. These are not taggable:

  - **Transport.** Advection, hyperdiffusion, sponges, interior vertical
    diffusion and LES SGS diffusion act on each tag itself. Attributing the
    ``\rho e_\mathrm{tot}`` version as well would count transport twice.
  - **Implicit tendencies**, except precipitation sedimentation. It runs on the
    implicit path but is attributed as `precipitation`, because it is a real
    energy sink the tags never receive. Its increment does not depend on the
    tags, so the identity Jacobian block the tags fall back to is exact (see
    [Implicit Solver](implicit_solver.md)).
  - **EDMFX SGS mass fluxes.** Tags have no updraft counterpart.

These terms land in the closure residual, which is why the residual is
monitored and not zero.

A region tag receives every attributed process, weighted by its mask, so a
partition of unity of region tags keeps tracking ``\rho e_\mathrm{tot}``. A tag
with both `region` and `source` starts at zero and accumulates only its own
processes, restricted to its region. The `region` restricts where the process
is counted. It does not add the region's energy to the tag.

## Diagnostics and closure

Each tag registers a diagnostic automatically:

  - `e_tag_<name>`: specific tagged energy ``\rho e_{\mathrm{tag}} / \rho``
    (J kg⁻¹);
  - `e_tag_res`: the closure residual
    ``(\rho e_\mathrm{tot} - \sum_i \rho e_{\mathrm{tag},i}) / \rho``, summed
    over the region tags.

`e_tag_res` is a monitored residual, not a machine-precision identity.
``\rho e_\mathrm{tot}`` is transported as enthalpy, including pressure work, and
has its own diffusion treatment, while the tags are passive scalars. If the
region masks do not sum to 1, the run warns at initialization and `e_tag_res`
is dominated by the overlap instead of by unattributed processes. Configure one
partition of unity per run.

Splitting a signed process tag across a partition gives a sharper check. With
`rad`, `rad_stratosphere` and `rad_troposphere` tags, transport linearity gives
``e_{\mathrm{tag,rad\_strat}} + e_{\mathrm{tag,rad\_tropo}} = e_{\mathrm{tag,rad}}``
to near machine precision at all times. A violation is a bug and not expected
leakage. `config/model_configs/baroclinic_wave_tagged_tracers.yml` uses this
identity with the Held–Suarez source.

## Caveats

  - Tags are grid-scale only. With `PrognosticEDMFX` the surface-flux and
    SGS-flux loops skip tags, so EDMFX configurations run, but the tagged
    energy is not decomposed across subdomains.
  - Tags are excluded from both tracer limiters. The vertical-water-borrowing
    limiter would be wrong because tagged energies can be negative
    (accumulated cooling). The SEM quasimonotone limiter is skipped so that tags
    are treated as ``\rho e_\mathrm{tot}`` is, which is not limited either.
  - Latitude, box and polygon regions need spherical geometry. Altitude regions
    also work in columns and boxes.
  - Tagged state is carried through restarts like any other prognostic field.
    The masks are rebuilt from the configuration, so the `energy_tracers` block
    must match the one that wrote the checkpoint.

## Interpretation limit

Closure shows one thing: the included terms sum to the parent, as a signed
discrete accounting. It does not show that the amounts are non-negative, that
the origin reading is valid, that results are independent of the energy
reference, or that the set of tracked processes is physically complete. The
tags are not counterfactual sensitivities. They say what contributed to the
simulated energy, not what would change if a process were altered. That
question needs perturbation or ensemble experiments. The mask weighting, the
choice of attributed processes and the grouping of gains and losses within one
attributed process are modeling choices, and conclusions depend on them.

### Tag values depend on the energy reference

Moist total energy has no physical zero. A shift
``\rho e_\mathrm{tot} \to \rho e_\mathrm{tot} + c\rho`` changes what a region
tag holds, and changes every residual normalized by
``\max|\rho e_\mathrm{tot}|``. Such residuals are not comparable across
configurations with different references.

A signed process tag for a process that exchanges no mass is unaffected, because it
accumulates tendencies and not shares. One that does exchange mass is affected.
Under a shift `c`, the tendency attributed to `precipitation`, or to the
moisture part of `surface_flux`, moves by `c` times the mass exchanged.

Water has a physical zero and does not have this problem.

See `config/model_configs/baroclinic_wave_tagged_tracers.yml` for a complete
example, and `test/tagged_tracers_integration.jl` for the closure assertions.

## Tagged tracer API

Rendered here so that the `@ref` links in these docstrings resolve; Documenter
resolves `@ref` only against docstrings a `@docs` block splices into a page.

```@docs
ClimaAtmos.TaggingModel
ClimaAtmos.TracerTag
ClimaAtmos.AbstractTagRegion
ClimaAtmos.EntireDomain
ClimaAtmos.TanhAltitudeRegion
ClimaAtmos.TanhLatitudeRegion
ClimaAtmos.TanhBoxRegion
ClimaAtmos.TanhPolygonRegion
ClimaAtmos.KNOWN_TAG_SOURCES
ClimaAtmos.TAG_SOURCE_GROUPS
ClimaAtmos.is_tagged_tracer_name
ClimaAtmos.tagging_scratch
ClimaAtmos.snapshot_tagged_ρe_tot!
ClimaAtmos.attribute_tagged_ρe_tot!
```
