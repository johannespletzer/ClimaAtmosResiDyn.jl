# Tagged Energy Tracers

Tagged tracers decompose the total energy field ``\rho e_\mathrm{tot}`` into
labeled prognostic components, either by **region** (via smooth spatial
masks) or by **source process** (e.g. radiation). Each tag is an ordinary
grid-scale tracer `Y.c.ρe_tag_<name>`, transported by the automatic tracer
machinery (see [Tracers](passive_tracers.md)), so the sum of a set of region
tags can be checked against ``\rho e_\mathrm{tot}``.

## Enabling tags

Tags are configured with a single YAML block; no Julia code is required:

```yaml
tagged_tracers:
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
default (`tagged_tracers: ~`) disables the feature entirely: no extra state
fields, cache entries, or runtime cost.

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
  - `tanh_latitude`: a smooth band ``|\mathrm{lat}| \lesssim
    \mathrm{lat\_bound}``; `inside: false` gives the exact complement.
    Requires spherical geometry.

A region and its complement sum to exactly 1, so the corresponding pair of
tags partitions ``\rho e_\mathrm{tot}`` at initialization to machine
precision.

## Source tags

A source tag starts at zero and accumulates the tendency that a labeled
process adds to ``\rho e_\mathrm{tot}``. Supported `source` labels:

  - `radiation`: all radiation modes
  - `surface_flux`: turbulent surface energy flux
  - `microphysics`: microphysics energy sources (when stepped explicitly)
  - `held_suarez`: Held–Suarez relaxation forcing

Region tags receive **every** attributed source, weighted by their mask, so
a partition-of-unity set of region tags keeps tracking
``\rho e_\mathrm{tot}``. A tag with both `region` and `source` also starts
at zero and accumulates only its own source, restricted to its region — the
`region` restricts *where* the source is counted; it does not add the
region's energy content to the tag.

Only genuine sources/sinks are attributed. Transport-like tendencies
(advection, hyperdiffusion, sponges, interior vertical diffusion) are never
attributed, because each tag already receives its own transport from the
tracer machinery — attributing them would count transport twice. Tendencies
applied by the implicit solver are not attributed either.

## Diagnostics and closure

With tagging enabled, per-tag diagnostics are registered automatically:

  - `e_tag_<name>`: specific tagged energy ``\rho e_{\mathrm{tag}} / \rho``
    (J kg⁻¹);
  - `e_tag_res`: the closure residual ``(\rho e_\mathrm{tot} - \sum_i \rho
    e_{\mathrm{tag},i}) / \rho``, summed over the pure region tags.

`e_tag_res` is a **monitored residual**, not a machine-precision identity:
``\rho e_\mathrm{tot}`` is transported as enthalpy (including pressure work)
and has its own diffusion treatment, while tags are passive scalars. In a
10-day dry baroclinic wave validation the residual stayed below one percent
of the pointwise energy scale. If the configured region masks do not sum to
1 (overlapping or incomplete regions), a warning is emitted at
initialization and `e_tag_res` is dominated by the overlap instead of by
attribution leakage.

A sharper *process closure* check is available by splitting a source tag
across a partition: with `rad`, `rad_stratosphere`, and `rad_troposphere`
tags, transport linearity implies ``e_{\mathrm{tag,rad\_strat}} +
e_{\mathrm{tag,rad\_tropo}} = e_{\mathrm{tag,rad}}`` to near machine
precision at all times — any violation indicates a bug rather than expected
leakage. `config/model_configs/baroclinic_wave_tagged_tracers.yml` and the
integration test use this identity with the Held–Suarez source.

## Caveats

  - Tags are grid-scale only; `PrognosticEDMFX` configurations are not yet
    supported with tagging enabled.
  - Tagged energies can be legitimately negative (accumulated cooling); they
    are excluded from the vertical-water-borrowing nonnegativity limiter.
  - Latitude regions require spherical geometry; altitude regions also work
    in columns and boxes.

See `config/model_configs/baroclinic_wave_tagged_tracers.yml` for a complete
example, and `test/tagged_tracers_integration.jl` for the closure assertions.
