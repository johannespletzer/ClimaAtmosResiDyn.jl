# Tagged Energy Tracers

Tagged tracers decompose the total energy field ``\rho e_\mathrm{tot}`` into
labeled prognostic components, either by **region** (via smooth spatial
masks) or by **process** (e.g. radiation). Each tag is an ordinary
grid-scale tracer `Y.c.ρe_tag_<name>`, transported by the automatic tracer
machinery (see [Tracers](passive_tracers.md)), so the sum of a set of region
tags can be checked against ``\rho e_\mathrm{tot}``.

!!! warning "Energy, not heat and not temperature"

    The tagged variable is density-weighted moist total energy
    ``\rho e_\mathrm{tot}``. It is not temperature, and it is not heat. Two
    named methods in the literature tag neither: Grewe's *temperature tagging*
    tags temperature, and Fajber and Kushner's *heat tagging* tags potential
    temperature. This page cites the latter for its proportional-removal rule,
    which the [water tags](tagged_water.md) borrow, not for the tagged
    variable. Do not describe this family as heat tagging.

## What a tag means

A tag configured with `region` and a tag configured with `source` are different
kinds of quantity, and the difference matters more than the shared word "tag".

  - A **region tag** is a transported partition of ``\rho e_\mathrm{tot}``. It
    starts as the region's share of the energy present and receives every
    attributed process, weighted by its mask.
  - A **process tag** — one configured with `source` — is a **process-change
    record**. It starts at zero and accumulates the signed increment that one
    labeled process adds to ``\rho e_\mathrm{tot}``. Heating adds, cooling
    subtracts, and the accumulated value can be negative.

A process tag is therefore a history of what a process did, not a share of the
energy that is here now. Reading `e_tag_rad = -3.0e4` as "radiation supplied a
negative amount of the local energy" is a misreading: it says radiation has
removed that much more energy than it added since the tag started.

The `source` key is kept for symmetry with `water_tracers`, where the same key
selects the same processes. The two families differ in the *rule*, not the key.
The water tags share out production by mask and take loss from each tag in
proportion to what it holds, which yields an amount of water actually present
and never below zero. The energy tags apply the whole signed increment by mask.
Both are useful; they answer different questions.

## Enabling tags

Tags are configured with a single YAML block; no Julia code is required:

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
default (`energy_tracers: ~`) disables the feature entirely: no extra state
fields, cache entries, or runtime cost.

See [Configuring Tracers](tracer_configuration.md) for the full schema, the
named regions that shorten common cases, the other two tracer families, and the
`energy_closure_check` block, which reduces `e_tag_res` to a pair of numbers on a
period of its own and warns while the run goes.

!!! note "One partition at a time"

    The closure diagnostic `e_tag_res` sums **all** pure region tags, so
    configure exactly one partition of unity per run (a region and its
    complement, as above) rather than several overlapping decompositions. A
    warning is emitted at initialization when the pure region masks do not
    sum to 1.

## Region tags

A region tag is initialized to ``\rho e_\mathrm{tot} \, M(x)``, where the
mask ``M \in [0, 1]`` uses smooth `tanh` transitions (step functions would
cause Gibbs ringing in the spectral-element discretization). Supported
region types:

  - `everywhere`: ``M = 1`` in the whole domain.
  - `tanh_altitude`: ``M = (1 + \tanh((z - z_\mathrm{center}) / w)) / 2``;
    `above: false` gives the exact complement (1 below, 0 above).
  - `tanh_latitude`: a smooth band ``|\mathrm{lat}| \lesssim \mathrm{lat\_bound}``; `inside: false` gives the exact complement.
    Requires spherical geometry.
  - `tanh_box`: a smooth longitude–latitude box (`lon_min`, `lon_max`,
    `lat_min`, `lat_max`, `width`). Requires spherical geometry.
  - `tanh_polygon`: a smooth arbitrary polygon given by `vertices` (a list of
    `[lon, lat]` pairs) and `width`. Requires spherical geometry.

Every region type accepts `inside: false` (`above: false` for
`tanh_altitude`) to select the exact complement, and a region plus its
complement sum to exactly 1 — so the corresponding pair of tags partitions
``\rho e_\mathrm{tot}`` at initialization to machine precision.

### Geographic regions

`tanh_box` and `tanh_polygon` both take their `width` in degrees of
great-circle arc; the mask equals ``1/2`` on the boundary and approaches 1
inside and 0 outside over roughly that width. Longitudes are handled modulo
360°, so a box or polygon may cross the antimeridian (a polygon is evaluated
in the longitude frame of its first vertex, so it must span less than 180°
of longitude).

```yaml
  - name: tropical_atlantic
    region: {type: tanh_box, lon_min: -60.0, lon_max: -10.0,
             lat_min: -10.0, lat_max: 10.0, width: 2.0}
```

Published reference regions — the IPCC AR6 / ATLAS domains, SREX, PRUDENCE,
and anything else distributed with
[`regionmask`](https://regionmask.readthedocs.io/) — are polygons, so they
map directly onto `tanh_polygon`. Export the vertices once and paste them
into the config:

```python
import regionmask, yaml

region = regionmask.defined_regions.ar6.land["W.Africa"]
vertices = [[round(x, 3), round(y, 3)] for x, y in region.polygon.exterior.coords]
print(yaml.dump({"vertices": vertices}))
```

!!! warning "Smoothing is required, not cosmetic"

    `regionmask` rasterizes regions with a point-in-polygon test, giving a
    sharp 0/1 mask. A discontinuous mask must **not** be used here: in the
    spectral-element discretization it produces Gibbs oscillations that
    contaminate the tagged fields from the first step. The `width` parameter
    is what makes a reference-region polygon usable — choose it comparable
    to (or larger than) the horizontal grid spacing.

## Process tags

A process tag starts at zero and accumulates the tendency that a labeled
process adds to ``\rho e_\mathrm{tot}``. It is configured with the `source`
key, and it holds a process-change record rather than a share of the energy
present. See [What a tag means](#What-a-tag-means).

### Taggable processes

| Group       | `source` label          | Process                                                                          |
|:----------- |:----------------------- |:-------------------------------------------------------------------------------- |
| `radiative` | `radiation`             | All radiation modes (RRTMGP, gray, DYCOMS, TRMM\_LBA, ISDAC)                     |
| `turbulent` | `surface_flux`          | Turbulent surface energy flux                                                    |
| `moist`     | `microphysics`          | Microphysics energy sources, when stepped explicitly (0-moment only — see below) |
| `moist`     | `precipitation`         | Energy carried out of a level by sedimenting precipitation                       |
| `forcing`   | `held_suarez`           | Held–Suarez relaxation forcing                                                   |
| `forcing`   | `large_scale_advection` | Prescribed large-scale advective forcing                                         |
| `forcing`   | `subsidence`            | Prescribed large-scale subsidence                                                |
| `forcing`   | `external_forcing`      | Externally prescribed (e.g. GCM-driven) forcing                                  |

!!! note "Which moist label carries the signal"

    With 0-moment microphysics the moist energy sink appears in
    `microphysics`. The 1-moment and 2-moment schemes instead change only
    the water species, and the energy leaves with the falling precipitation,
    so the signal appears in `precipitation`. Tagging the `moist` group
    covers both cases.

A group name may be used wherever a process label is expected, and `source`
also accepts a list, so these are equivalent:

```yaml
  - name: forced
    source: forcing
  - name: forced
    source: [held_suarez, large_scale_advection, subsidence, external_forcing]
```

The group `all` expands to every process in the table.

### What is *not* taggable, and why

A process can be attributed only if the tags do **not** already receive it
through the automatic tracer machinery. Excluded, therefore:

  - **Transport**: advection, hyperdiffusion, sponges, interior vertical
    diffusion, and LES SGS diffusion all act on each tag in its own right.
    Attributing the ``\rho e_\mathrm{tot}`` version on top of that would
    count transport twice — this is the central correctness constraint of
    the design.
  - **Implicit tendencies**: implicit vertical transport and implicit
    diffusion. Precipitation sedimentation is the exception — it also runs
    on the implicit path but *is* attributed (as `precipitation`), because
    it is a real energy sink the tags never receive. Bracketing it is safe
    because the implicit tendency is rebuilt from zero on every evaluation,
    and its attributed increment does not depend on the tags, so the
    identity Jacobian block that tags fall back to is exactly right.
  - **EDMFX SGS mass fluxes**: tags have no updraft counterpart.

These land in the closure residual described below, which is why that
residual is a monitored quantity rather than zero.

### Regions and processes combined

Pure region tags receive **every** attributed process, weighted by their
mask, so a partition-of-unity set of region tags keeps tracking
``\rho e_\mathrm{tot}``. A tag with both `region` and `source` also starts
at zero and accumulates only its own processes, restricted to its region — the
`region` restricts *where* the process is counted; it does not add the
region's energy content to the tag.

## Diagnostics and closure

With tagging enabled, per-tag diagnostics are registered automatically:

  - `e_tag_<name>`: specific tagged energy ``\rho e_{\mathrm{tag}} / \rho``
    (J kg⁻¹);
  - `e_tag_res`: the closure residual ``(\rho e_\mathrm{tot} - \sum_i \rho e_{\mathrm{tag},i}) / \rho``, summed over the pure region tags.

`e_tag_res` is a **monitored residual**, not a machine-precision identity:
``\rho e_\mathrm{tot}`` is transported as enthalpy (including pressure work)
and has its own diffusion treatment, while tags are passive scalars. In a
10-day dry baroclinic wave validation the residual stayed below one percent
of the pointwise energy scale. If the configured region masks do not sum to
1 (overlapping or incomplete regions), a warning is emitted at
initialization and `e_tag_res` is dominated by the overlap instead of by
attribution leakage.

A sharper *process closure* check is available by splitting a process tag
across a partition: with `rad`, `rad_stratosphere`, and `rad_troposphere`
tags, transport linearity implies ``e_{\mathrm{tag,rad\_strat}} + e_{\mathrm{tag,rad\_tropo}} = e_{\mathrm{tag,rad}}`` to near machine
precision at all times — any violation indicates a bug rather than expected
leakage. `config/model_configs/baroclinic_wave_tagged_tracers.yml` and the
integration test use this identity with the Held–Suarez source.

## Caveats

  - Tags are **grid-scale only**: they have no sub-grid (updraft)
    counterpart. With `PrognosticEDMFX`, the surface-flux and SGS-flux loops
    skip tags rather than looking for a missing updraft field, so EDMFX
    configurations run, but tagged energy is not decomposed across
    subdomains.
  - Tags are excluded from both tracer limiters: from the
    vertical-water-borrowing limiter because tagged energies can be
    legitimately negative (accumulated cooling), and from the SEM
    quasimonotone limiter so that tags receive the same treatment as
    ``\rho e_\mathrm{tot}``, which is not limited either.
  - Latitude regions require spherical geometry; altitude regions also work
    in columns and boxes.
  - Tagged state is carried through restarts like any other prognostic
    field; the masks are rebuilt from the configuration, so the
    `energy_tracers` block must match the one used to write the checkpoint.

## Interpretation limit

Exact closure establishes internally consistent contribution accounting. It does
not turn the tags into counterfactual sensitivities. Tagging says what
contributed to the simulated energy; it does not say what would change if a
process were altered. That is a question for perturbation or ensemble
experiments.

The mask weighting, the choice of which processes are attributed, and the
grouping of gains and losses within one bracket are modeling choices.
Conclusions are conditional on them.

### Tag values depend on the energy reference

Moist total energy has no physical zero. Its value depends on the chosen
reference points for thermodynamic and gravitational energy, so a shift
``\rho e_\mathrm{tot} \to \rho e_\mathrm{tot} + c\rho`` changes what a region
tag holds and changes every residual normalized by
``\max|\rho e_\mathrm{tot}|``. The integration test's tolerance is normalized
that way, so it is not comparable across configurations that use different
references.

Process tags are unaffected, because they accumulate increments rather than
shares. This is one reason to read the two kinds of tag separately.

Water has a physical zero and does not have this problem, which is why
`q_tag_res` and `e_tag_res` are not directly comparable numbers.

See `config/model_configs/baroclinic_wave_tagged_tracers.yml` for a complete
example, and `test/tagged_tracers_integration.jl` for the closure assertions.

## API

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
