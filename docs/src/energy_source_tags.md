# Energy Source Tags

Energy source tags split moist total energy ``\rho e_\mathrm{tot}`` by **where the
energy present now came from**. Each tag adds one grid-scale prognostic field
`Y.c.ρe_src_<name>`, transported by the automatic tracer machinery (see
[Tracers](passive_tracers.md)).

They are the energy counterpart of the [Tagged Water Tracers](tagged_water.md),
and a different quantity from the [Tagged Energy Tracers](tagged_tracers.md):

| Family               | Field           | Holds                                                 |
|:-------------------- |:--------------- |:----------------------------------------------------- |
| `energy_source_tags` | `ρe_src_<name>` | an amount of energy present now, traced to its origin |
| `energy_tracers`     | `ρe_tag_<name>` | a signed record of what one process did               |

Both accept the same `source` labels. The rule applied to them differs, and that
is the whole distinction.

## Enabling tags

```yaml
energy_source_tags:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
```

Each entry needs a unique `name` and a `region`, a `source`, or both — the entry
schema and the region types are exactly those of the
[energy tags](tagged_tracers.md#Region-tags). Off by default, at no runtime cost.

See [Configuring Tracers](tracer_configuration.md) for the full schema and the
named regions.

!!! note "One partition at a time"

    `e_src_res` sums **all** pure region tags, so configure exactly one
    partition of unity per run — a region and its complement. A warning is
    emitted at initialization when the masks do not sum to 1.

## Attribution

A bracketed increment ``\Delta`` to ``\rho e_\mathrm{tot}`` is split into gross
production and gross loss and attributed by **different rules**, exactly as the
water tags do:

```math
\Delta\!\left(\rho e_{\mathrm{src},k}\right)
= M_k \, \Delta^{+} - \varphi_k \, \Delta^{-},
\qquad
\varphi_k = \frac{\rho e_{\mathrm{src},k}}{\rho e_\mathrm{tot}}.
```

  - **Production is mask-weighted.** ``M_k`` is the tag's region mask (1 for a
    region-less source tag, 0 if the tag does not list this process). New energy
    carries the label of where it entered.
  - **Loss is donor-proportional.** Energy leaves in proportion to what is
    actually present, and **every** tag is depleted, whatever processes it
    lists. This is what makes ``\rho e_{\mathrm{src},k}`` an amount of energy
    rather than a running total, and what keeps a tag from absorbing a loss it
    does not own.

With ``\sum_k M_k = 1`` and ``\sum_k \rho e_{\mathrm{src},k} = \rho e_\mathrm{tot}``
we have ``\sum_k \varphi_k = 1``, so ``\sum_k \Delta_k = \Delta^{+} - \Delta^{-} = \Delta``
exactly, per process.

Only the explicit path is bracketed for these tags, as for the process records,
so `precipitation` — which is attributed on the implicit path for the
`ρe_tag_*` family — does not reach a source tag. That is a named limitation, not
an oversight, and it shows up in `e_src_res`.

## Tags are not guaranteed non-negative

The donor-proportional loss bounds the *rate* at which a tag is depleted, not
the amount removed. Attribution produces a tendency, and the timestepper
integrates it over a finite step, so the energy taken from a tag across one
step is about ``\Delta t \, \varphi_k \, \Delta^{-}``. Nothing ties that to
what the tag holds. Parent tendencies that cancel — say ``+200`` against
``-200`` — leave ``\rho e_\mathrm{tot}`` unchanged while a tag receiving only
the loss half crosses zero inside the step. Clamping ``\varphi_k`` to
``[0, 1]`` does not prevent it, because the clamp acts on the share and the
step length sets the amount.

Two further routes take a tag negative. Where ``\rho e_\mathrm{tot} \le 0``
the share is undefined and `energy_source_fraction` returns zero, so no
donor-proportional loss is applied there at all; how much of a domain that
covers depends on the energy reference. And the tags are exempt from both
tracer limiters and ride unlimited explicit transport with no partition repair.

So `ρe_src_<name>` is a monitored quantity, not a bounded one. A negative value
is information about the configuration — the timestep, the energy reference, or
the transport — rather than a failure of the attribution rule. Watch it through
`e_src_res` and the closure check, which reports the fraction of the domain
where the parent is non-positive.

## Closure checking

```yaml
energy_source_closure_check:
  period: "1days"
  tolerance: 1.0e-6
```

Reduces `e_src_res` to a pair of numbers on its own cadence and appends them to
`energy_source_tag_closure.csv`, warning when the run drifts past the tolerance.
The keys and behaviour are those of `energy_closure_check`; see
[Configuring Tracers](tracer_configuration.md).

The tolerance is compared against a residual normalized by a quantity whose zero
is a convention, so a value tuned for one energy reference means something
different under another. Calibrate it against a first run of your own
configuration.

## The energy reference problem

Water has a physical zero: ``\rho q_\mathrm{tot} \ge 0`` is enforced by the
model, which is what makes the donor fraction ``\varphi_k`` well posed. **Moist
total energy has no such zero.** Its value depends on the chosen reference points
for thermodynamic and gravitational energy, so a shift
``\rho e_\mathrm{tot} \to \rho e_\mathrm{tot} + c\rho`` changes every tag's share
and can drive ``\rho e_\mathrm{tot}`` non-positive somewhere, where the donor
fraction is undefined.

No decomposition of an energy variable into never-negative parts can give the
same shares after an arbitrary shift of the zero point. Results from these tags
are therefore **conditional on the energy reference**, and that has to be fixed
and reported rather than assumed away.

This is the open question the tags exist to answer. Whether the shares are
stable and interpretable under a realistic configuration is what decides whether
energy source tracing is used at all, or whether water source tracing is
combined with an energy process record instead.

It is not hypothetical. `test/energy_source_tags_integration.jl` runs a
DYCOMS_RF02 marine boundary layer, and the model reports the fraction of the
domain where ``\rho e_\mathrm{tot} \le 0`` at initialization:

  - on the shipped 1.5 km column, **100%**;
  - on a 30 km column, **43%**.

Depth reduces the fraction, because geopotential lifts ``e_\mathrm{tot}``
positive higher up, but no choice of depth removes it.

**Where the share is undefined the loss half of the rule does not run at all.**
`energy_source_fraction` returns zero, so no tag is depleted, while production
stays mask-weighted and reaches tags normally. A run in that regime accumulates
production without the matching donor-proportional loss, which is not the rule
this page describes.

It also sets the boundary of what is currently tested, which is worth stating
exactly:

  - `test/energy_source_tags_integration.jl` covers configuration and state,
    bracketed **production** wiring, transport, restart, and a bounded closure
    residual. Production is mask-weighted and never divides by the parent, so
    it is exercised even here.
  - `test/energy_source_tags_tests.jl` covers the **loss algebra** against a
    parent that is positive by construction. That is a kernel-level check.
  - **Donor-proportional loss through a real bracketed solve is not validated.**
    No configured run currently puts the donor share on a defined footing, so
    there is nothing for such a test to assert against yet. Closing that gap
    needs either a well-defined positive energy reference or a reference-safe
    reformulation of the share.

That last point is also the strongest argument on the table for the fallback:
water source tracing, whose parent is non-negative by construction, combined
with an energy [process record](process_record.md) for the per-process history.

## Diagnostics

  - `e_src_<name>`: specific tagged energy ``\rho e_{\mathrm{src}} / \rho``
    (J kg⁻¹);
  - `e_src_res`: the closure residual
    ``(\rho e_\mathrm{tot} - \sum_i \rho e_{\mathrm{src},i}) / \rho``, summed
    over the pure region tags.

`e_src_res` is a **monitored residual**, not a machine-precision identity.
``\rho e_\mathrm{tot}`` is transported as enthalpy including pressure work and
has its own diffusion treatment, while the tags ride the generic passive-tracer
path. Because it is normalized by a quantity whose zero is a convention, it is
not comparable across configurations that use different references.

## Caveats

  - Tags are **grid-scale only**, with no sub-grid updraft counterpart.
  - Tags are excluded from both tracer limiters, through
    `is_tagged_tracer_name`.
  - Latitude regions require spherical geometry; altitude regions also work in
    columns and boxes.
  - Tagged state is carried through restarts like any other prognostic field,
    and the masks are rebuilt from the configuration, so the
    `energy_source_tags` block must match the one used to write the checkpoint.

## Interpretation limit

Exact closure establishes internally consistent contribution accounting. It does
not turn the tags into counterfactual sensitivities. Tagging says what
contributed to the simulated energy; it does not say what would change if a
process were altered.

## API

```@docs
ClimaAtmos.EnergySourceTag
ClimaAtmos.EnergySourceTaggingModel
ClimaAtmos.energy_source_tagging_variables
ClimaAtmos.energy_source_tag_state_names
ClimaAtmos.energy_source_region_tag_state_names
ClimaAtmos.is_energy_source_tag_name
ClimaAtmos.energy_source_tracer_tuple
ClimaAtmos.warn_inactive_energy_source_labels
ClimaAtmos.energy_source_fraction
ClimaAtmos.snapshot_energy_source_tags!
ClimaAtmos.attribute_energy_source_tags!
```
