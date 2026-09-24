# Tagged Water Tracers

Tagged water tracers decompose total water ``\rho q_\mathrm{tot}`` into labeled
prognostic components, so that the water at a point can be attributed to where
or how it entered the atmosphere. Each tag is an ordinary grid-scale tracer
`Y.c.ρq_tag_<name>`, transported by the automatic tracer machinery (see
[Tracers](passive_tracers.md)).

They are the water counterpart of the [Tagged Energy
Tracers](tagged_tracers.md) and share their region masks, configuration schema
and restart handling. Two things differ, and both matter — read
[Attribution](#Attribution) before using the output.

!!! warning "Total water is not water vapor"

    The `hus` diagnostic in this repository is named "Specific Humidity" but
    computes ``\rho q_\mathrm{tot}/\rho``, i.e. the mass of **all** water
    phases; `husv` is the vapor-only counterpart. The tagged names do not
    inherit that ambiguity: `q_tag_<name>` is total water and `qv_tag_<name>` is
    vapor. In the CliMA formulation ``q_t = q_v + q_l + q_i``, with ``q_l`` and
    ``q_i`` including precipitation.

## Enabling tags

```yaml
microphysics_model: "0M"
water_tracers:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
  - name: evap
    source: surface_flux
  - name: evap_tropics
    region: tropics
    source: surface_flux
```

Each entry needs a unique `name` and a `region`, a `source`, or both. The
default (`water_tracers: ~`) disables the feature entirely: no extra state
fields, cache entries, or runtime cost. The region types and their `inside: false` / `above: false` complements are exactly those documented for the
[energy tags](tagged_tracers.md#Region-tags): `everywhere`, `tanh_altitude`,
`tanh_latitude`, `tanh_box`, `tanh_polygon`.

See [Configuring Tracers](tracer_configuration.md) for the full schema, the
named regions (`tropics`, `extratropics`, `everywhere`) used above, and the
`water_closure_check` block, which reduces `q_tag_res` to a pair of numbers on a
period of its own and warns while the run goes.

A region tag is initialized to ``\rho q_\mathrm{tot} \, M(x)``; a tag with a
`source` starts at zero.

!!! note "One partition at a time"

    The closure diagnostic `q_tag_res` sums **all** pure region tags, so
    configure exactly one partition of unity per run (a region and its
    complement). A warning is emitted at initialization when the pure region
    masks do not sum to 1.

## Attribution

For each attributed process, the increment ``\Delta`` that it adds to
``\rho q_\mathrm{tot}`` is split into gross production and gross loss,
``\Delta^{+} = \max(\Delta, 0)`` and ``\Delta^{-} = \max(-\Delta, 0)``, and the
two halves are attributed by **different rules**:

```math
\Delta\!\left(\rho q_{\mathrm{tag},k}\right)
= M_k \, \Delta^{+} - \varphi_k \, \Delta^{-},
\qquad
\varphi_k = \frac{\rho q_{\mathrm{tag},k}}{\rho q_\mathrm{tot}}.
```

  - **Production is mask-weighted.** ``M_k`` is the tag's region mask (1 for a
    region-less source tag, 0 if the tag does not list this process). New water
    carries the label of where it entered.
  - **Loss is donor-proportional.** Water leaves in proportion to what is
    actually present, and **every** tag is depleted — including source tags,
    whatever processes they list. This is what makes ``\rho q_{\mathrm{tag},k}``
    an actual water mass rather than a running source integral.

This is the one place where the water tags deliberately depart from the energy
tags, which attribute the whole increment by mask. A mask-weighted *loss* would
remove water a tag does not own and can drive tags negative. The rule here is
the tendency form of the relative scaling ``\chi \mathrel{*}= (1 + \dot q\, \Delta t / q)`` used by the MESSy `H2OEMIS` submodel.

Two consequences worth stating:

  - **Closure.** With ``\sum_k M_k = 1`` and ``\sum_k \rho q_{\mathrm{tag},k} = \rho q_\mathrm{tot}`` we have ``\sum_k \varphi_k = 1``, so
    ``\sum_k \Delta_k = \Delta^{+} - \Delta^{-} = \Delta`` exactly, per process.
    If the configured tags are a strict subset (say a single "Atlantic
    evaporation" tag), then ``\sum_k \varphi_k < 1`` and the untagged remainder
    absorbs the rest — also correct, just not a partition.
  - **Positivity.** A tag update is
    ``\rho q_{\mathrm{tag},k}\,(1 - \Delta^{-}\Delta t / \rho q_\mathrm{tot})``,
    so a tag stays non-negative for as long as the step is short enough that
    ``\Delta^{-}\Delta t`` does not exceed ``\rho q_\mathrm{tot}`` — the same
    restriction that keeps ``\rho q_\mathrm{tot}`` itself non-negative under the
    0-moment sink. But nothing in the model enforces that restriction.
    `tracer_nonnegativity_method` is off unless configured, transport can drive a
    cell negative on its own, and a run on a sphere routinely has
    ``\rho q_\mathrm{tot} \le 0`` over part of its volume. Where it does, the
    share is undefined and the tags of that cell say nothing; the
    `nonpositive_fraction` column of the closure table is what reports how much
    of the domain is in that state.

### Taggable processes

| Group     | `source` label          | Process                                                             |
|:--------- |:----------------------- |:------------------------------------------------------------------- |
| `surface` | `surface_flux`          | Turbulent surface moisture flux (evaporation, or dew when negative) |
| *(none)*  | `microphysics`          | The 0-moment total-water sink                                       |
| `forcing` | `large_scale_advection` | Prescribed large-scale advective moistening or drying               |
| `forcing` | `subsidence`            | Prescribed large-scale subsidence                                   |
| `forcing` | `external_forcing`      | Externally prescribed (e.g. GCM-driven) forcing and `q_tot` nudging |

The group `all` expands to every process in the table. Note that `microphysics`
belongs to **no named group**: `source: surface` selects `surface_flux` only, so
a tag written that way follows evaporation but not the 0-moment sink. `all` is
the only group that includes `microphysics`; to follow both without the
forcings, list them explicitly as `source: [surface_flux, microphysics]`.

This is a *different, smaller* set than the energy tags': `radiation` and
`held_suarez` do not move water.

Splitting a net increment by sign is exact only where production and loss are
mutually exclusive at a point, which holds for the two that matter most — the
surface flux is evaporation or dew, and the 0-moment tendency is a sink by
construction. For the prescribed forcings it is an assumption.

### What is *not* taggable, and why

  - **Transport**: advection, hyperdiffusion, sponges, interior vertical
    diffusion and LES SGS diffusion all act on each tag in its own right, so
    attributing the ``\rho q_\mathrm{tot}`` version on top would count transport
    twice. This is the central correctness constraint of the design.

  - **Phase changes**: condensation, evaporation, freezing and melting conserve
    ``q_t``, so they are invisible to a total-water tag by construction. This is
    why no per-transfer ledger is needed — and why a vapor-only passive tracer
    would be the wrong design, since it would lose provenance at every phase
    change.

  - **Precipitation sedimentation**: with 0-moment microphysics there are no
    prognostic condensate species to sediment, so the term does not exist. With
    1-moment it is a flux divergence between levels rather than a local source,
    so it is not attributed but *mirrored* — see
    [Sedimentation with 1-moment microphysics](@ref).

  - **Numerical corrections** are handled separately, by
    `rescale_water_tags!`: the tags are excluded from both tracer limiters,
    because limiting each independently has no reason to reproduce the parent's
    adjustment and would break ``\sum_i \rho q_{\mathrm{tag},i} = \rho q_\mathrm{tot}``. Instead the parent's increment
    ``\Delta = \rho q_\mathrm{tot}^{\,\mathrm{after}} - \rho q_\mathrm{tot}^{\,\mathrm{before}}``
    is handed to the tags under the donor rule,
    ``\rho q_{\mathrm{tag},k} \leftarrow \rho q_{\mathrm{tag},k} + \Delta\,s_k``,
    where ``s_k`` is the tag's share of what the partition holds. The share is
    renormalized over the partition, as the sedimentation mirror's is, so the
    shares sum to one and the partition absorbs ``\Delta`` in full. The signed
    water moved is recorded in `q_tag_fix_<name>`.

    Adding the increment rather than scaling the tags is deliberate, and the two
    agree wherever the tags already sum to the parent. Where they do not, scaling
    multiplies the closure error by the same factor it applies to the tags, so a
    cell that a limiter lifts every stage compounds that error while
    ``\rho q_\mathrm{tot}`` stays bounded — which is how the tags of a sphere run
    reached ``10^{130}`` against a parent of ``1.6\times10^{16}``
    ([issue #64](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/issues/64)).
    The additive form leaves the error where it was. The loss is floored at what
    the tags hold, so a non-negative tag stays non-negative and where that floor
    binds the tags empty and the water they could not account for surfaces in
    `q_tag_res`. A tag that is already negative is not lifted by this
    correction, because its share is zero; `repair_water_tag_partition!` is what
    handles those.

### Sedimentation with 1-moment microphysics

With `microphysics_model: "1M"` the condensate species are prognostic and fall,
so sedimentation moves ``\rho q_\mathrm{tot}`` between levels. This is the one
water process that is neither attributed nor ignored, because it is a flux
divergence rather than a local source: its net increment in a cell mixes water
arriving from above with water leaving below, and attributing that increment
would label the arriving water with the receiving cell's mask and drain the
departing water in proportion to the total-water composition when the falling
condensate's composition is what actually leaves.

Instead the flux itself is *mirrored*. `sediment_water_tags!` is called once per
sedimenting species from inside the species loop of
`vertical_advection_of_water_tendency!`, and builds each tag's flux from the very
same specific content ``q``, terminal velocity ``w`` and face density ``\rho_f``
as the parent — the same donor-cell (`ᶠtop_bias`) reconstruction — scaled by
the tag's share of the local water. Because only the share differs, the tagged
fluxes sum to the parent flux exactly, level by level, and surface precipitation
is tagged.

The share differs between the two kinds of tag:

  - **Partition tags** (a region, no sources) use the *renormalized* clamped
    donor share ``\hat\varphi_k = \varphi_k / \sum_j \varphi_j``, with
    ``\varphi_k = \mathrm{clamp}(\rho q_{\mathrm{tag},k} / \rho q_\mathrm{tot}, 0, 1)``. The renormalization is what preserves exact closure: unlimited
    transport lets a tag drift slightly out of the partition — a few percent of
    ``\max(\rho q_\mathrm{tot})`` below zero on a sphere — after which the
    clamped shares no longer sum to one and ``\sum_k \mathrm{vtt}_k = \mathrm{vtt}`` fails by the size of that drift. Dividing by the sum restores
    it, and since each clamped share is one of the non-negative terms of the
    denominator, ``\hat\varphi_k \in [0, 1]`` however small the denominator gets.
  - **Source tags** are not members of the partition — they start at zero and
    accumulate one process — so no closure constraint applies and their share is
    the unnormalized ``\varphi_k``. Their water is real water that falls out like
    any other, under the same donor rule the loss half of the attribution uses.

Where no tagged water is present the share is zero rather than undefined; if
``\rho q_\mathrm{tot}`` is nonzero there, closure genuinely cannot hold and the
discrepancy surfaces in `q_tag_res` as it should.

Sedimentation is stepped implicitly, so the tags also enter the Jacobian:
`update_sedimentation_jacobian!` allocates and fills their diagonal blocks using
the analytic derivative of the share. For a partition tag that derivative carries
a ``(1 - \hat\varphi_k)`` factor, because a tag that already owns all the local
water cannot increase its share.

!!! note "Phases are well mixed within a cell"

    The mirror assumes the sedimenting condensate carries the cell's *total*-water
    tag composition, since the tags partition ``q_t`` and hold no phase
    information of their own. This is the same assumption `qv_tag` rests on.

Under 1-moment this is the only microphysical writer of ``\rho q_\mathrm{tot}``
— `microphysics_tendency!` moves mass between species only — so the
`microphysics` attribution bracket is a no-op there, and the `precipitation`
label that the energy tags carry has no water counterpart.

## Under prognostic EDMF

With `turbconv: prognostic_edmfx` and one updraft, the tags follow the
updraft's water. The model's sub-grid mass flux moves ``\rho q_\mathrm{tot}``
between the updraft, the environment and the grid mean. The switch
`water_tag_updraft_copy` picks how the tags follow it.

**The default mode** (`water_tag_updraft_copy: false`). The tags have no
updraft state. At each face, each tag takes its share of the parent's sub-grid
flux of water, from the donor cell. The partition's shares are renormalized to
sum to one, so the partition's fluxes sum to the parent's. That share is the
grid mean's composition, not the updraft's. So an exchange of provenance at
the updraft's mass flux adds the difference between the two. The updraft's
composition comes from a steady entraining plume. The plume starts from the
grid mean's composition at the lowest level. It mixes in the grid mean's
composition at the entrainment rate, and at each level it is rescaled to the
updraft's water ``q_\mathrm{tot}^j``. The exchange sums to zero over the
partition. It is bounded, so that no tag moves more water than a subdomain
holds, and the audit reports where the bound binds. The exchange needs region
tags that partition the domain, and a run without them is refused.

**The copies** (`water_tag_updraft_copy: true`). Each tag gets a copy in the
updraft, `q_tag_<name>`: the tag's water per unit mass of updraft air. The model
moves it as any other updraft tracer, by advection, entrainment and
detrainment, the sub-grid flux, the filter, diffusion and hyperdiffusion. The
grid-scale tags then take their sub-grid flux from the copies, and the default
mode's flux and exchange do not run. Five mirrors give the copies what the
updraft's water gets and a tracer does not:

  - the 0-moment rain-out. Each copy loses its share of the water rained out;
  - the 1-moment sedimentation. Each copy's rain and snow fall with its share,
    and the environment's falling water enters with the environment's
    composition;
  - the relaxation at the surface. Each copy relaxes toward the buoyant surface
    water times the grid mean's share;
  - the surface flux. `surface_flux_tendency!` also adds the surface moisture
    flux to ``q_\mathrm{tot}^j``. Each copy takes that water by the grid-scale
    tags' rule for the label `surface_flux`: new water by region and source,
    dew by the copy's share;
  - the repair after the filter, which runs with or without the filter. The
    residual ``q_\mathrm{tot}^j - \sum_i \chi_i^j`` is added to the
    partition's copies by their shares, floored at what each holds, and where
    their sum is not positive they are zeroed. The correction goes to
    `q_tag_upfix_<name>`, and the residual the repair found to
    `q_tag_copy_res`.

`q_tag_copy_res` and `q_tag_upfix` bound the sum of everything that parts the
copies from ``q_\mathrm{tot}^j``, not the filter alone. That sum includes the
grid partition's own residual, which reaches the copies through the terms that
read the grid tags, such as the entrainment of the environment's values and the
Rayleigh sponge. It includes the Newton iterations, since ``q_\mathrm{tot}^j``
couples to the updraft's condensates in the Jacobian and the copies have only a
diagonal. And it includes the leaks and the rain-out's clamp. The ledger is
signed and cumulative, so repairs of opposite sign cancel in it, and its size
can understate the water the repair moved.

The copies start, and are rebuilt from a file, as ``q_\mathrm{tot}^j`` times
the grid mean's share. They cost one updraft tracer per tag, and they are the
audit of the default mode's plume.

**The 0-moment rain-out.** Under 0-moment microphysics, EDMF computes the
rain-out per subdomain: ``\Delta^j = \rho a^j \, \partial_t q_\mathrm{tot}^j``
in the updraft and ``\Delta^0 = \rho a^0 \, \partial_t q_\mathrm{tot}^0`` in the
environment. The model adds their sum to ``\rho q_\mathrm{tot}``. The
grid-scale tags take each part by that subdomain's composition,
``\sum_k \Delta^k \varphi_i^k``, not by the grid mean's
(`splits_rainout`, `add_split_rainout!`). With the copies, the updraft's share
is the copy's, ``\chi_i^j / q_\mathrm{tot}^j``, and the environment's is what
the grid tags and the copies leave for it. In the default mode, the shares are
the grid mean's plus the exchange's difference for that subdomain. The
partition's shares, both of them in the default mode and the environment's
with the copies, are scaled by the partition's sum of grid shares. So a
drifted partition keeps losing in proportion to what it holds.
Where a subdomain's share is not defined, the grid mean's applies. The split
applies to both signs, since a subdomain's area can go negative in the Newton
iterates. In the default mode without the SGS mass flux there is no
exchange, and the grid mean's share applies to all the rain-out, as it does
without EDMF. The model's fields do not change.

**Refusals.** Both modes refuse more than one updraft. The copies are refused
without prognostic EDMF, and when `edmfx_mse_q_tot_upwinding` differs from
`edmfx_tracer_upwinding`, because the copies' fluxes then do not sum to the
parent's. AMD LES stays refused; see `docs/known_issues.md`, issue 3.

**Restart.** A checkpoint records each tag's region and sources. A restart that
changes one, or that adds or drops the copies, is refused before the run
starts (`check_water_tag_checkpoint`).

## Following the parent's implicit increment

`water_tag_transport: increment` (default `tracer`) makes the tags follow the
parent's own implicit increment. ``\rho q_\mathrm{tot}`` is advected
vertically in the implicit step, and its sub-grid flux, diffusion and
sedimentation have Jacobian blocks the tags' terms lack. So with one Newton
iteration the tags lag the parent's solve. On a day of the DYCOMS RF02 EDMF
column that lag was most of a 0.7% closure residual.

Under the key the tags skip their explicit vertical advection. After each
Newton solve, `correct_water_tag_increment!` takes the difference `m` between
the parent's increment and the partition's in each cell. The part that sums to
zero in the column is moved as a vertical flux, and each tag takes it by its
share in the cell the flux leaves. The part that changes the column's total,
`∫m`, is left out of the tags and stays in `q_tag_res`. The ledger
`q_tag_inc_left` and `q_tag_inc_moved` records both parts, and the audit
integrates them. The energy source tags' `enthalpy_increment` does the same
for their total, and one hook runs both.

What the follower cannot do:

  - change a column's total, so a lag in the surface outflow of sedimentation
    stays in the net residual;
  - say where the part left out arose: it is spread in proportion to `|m|`,
    which the parent's vertical advection dominates;
  - move water a partition does not hold: a residual pinned in a cell stays
    there, and a draining cell's partition can go negative, which the
    partition repair then moves;
  - follow explicit processes, the copies, or a donor cell with an empty
    partition.

It needs region tags that partition the domain, an algorithm that solves every
implicit stage it uses (ARS222, ARS343), and the parent's own post-solve
correction (`energy_q_tot_upwinding` other than `none`). A restart that changes
`water_tag_transport` is refused.

## Diagnostics and closure

  - `q_tag_<name>`: tagged **total** water ``\rho q_\mathrm{tag}/\rho``;
  - `qv_tag_<name>`: tagged **vapor**, ``q_\mathrm{tag} \, q_v / q_t``;
  - `q_tag_res`: the closure residual ``(\rho q_\mathrm{tot} - \sum_i \rho q_{\mathrm{tag},i})/\rho``, summed over the pure region tags;
  - `q_tag_fix_<name>`: water moved into or out of the tag by the limiters and
    state constraints, cumulative since the start of the simulation segment (and
    reset on restart), so a budget over an interval is the difference of two
    outputs, and a time *average* of it is not meaningful;
  - `q_tag_upfix_<name>` and `q_tag_copy_res`: with updraft copies, the copies'
    repair, cumulative as `q_tag_fix` is, and the residual it found;
  - `q_tag_leak_<path>`: the rate at which one path drifts the partition's sum
    from ``\rho q_\mathrm{tot}``, computed from the state; see below;
  - `pr_tag_<name>`, `prra_tag_<name>` and `prsn_tag_<name>`, under 0-moment
    microphysics only: the tag's part of `pr`, `prra` and `prsn`, the column
    integral of its part of the rain-out (`water_tag_precipitation!`). It is
    upward-positive as `pr` is, so negative, and split into rain and snow by
    the grid mean's temperature as `pr` is. Over a partition the tags' sum is
    `pr`, up to the partition's residual. It is computed from the state at
    output time, so it is the rate at the step's end, not the one the step
    applied. Under 1-moment it waits on rain and snow tags.

!!! note "What `q_tag_fix` includes"

    Two mechanisms write to the ledger. `repair_water_tag_partition!` runs every
    step and contributes wherever transport drove a partition tag negative, so
    `q_tag_fix_<name>` is generally nonzero even under stock settings — it is a
    useful direct measure of how much the tags are drifting.
    `rescale_water_tags!` contributes only when something actually corrects
    ``\rho q_\mathrm{tot}``: `apply_sem_quasimonotone_limiter: true`,
    `tracer_nonnegativity_method: vertical_water_borrowing`, an elementwise
    tracer nonnegativity constraint, or a `PrescribedFlow` setup. With none of
    those configured, everything in this field is partition repair.

!!! note "The vapor split is an assumption"

    `qv_tag` assumes the water phases are well mixed within a grid cell: the
    tags partition total water and carry no phase information of their own, and
    with 0-moment microphysics ``q_l`` and ``q_i`` are the saturation-adjustment
    diagnosis of the grid mean. This is stated in the diagnostic's `comments`
    field as well, so it travels with the output.

`q_tag_res` is a **monitored residual**, not a machine-precision identity.
One contributor is the vertical advection split: ``\rho q_\mathrm{tot}`` is
advected implicitly with a post-Newton upwind correction, while the tags ride
the explicit passive-tracer path. Subtract `q_tag_fix_*` to separate that
operator disagreement from numerical corrections.

Another is the paths that move the tags as passive tracers, on their whole
value, and ``\rho q_\mathrm{tot}`` only by the water that diffuses,
``q_\mathrm{tot} - q_\mathrm{rai} - q_\mathrm{sno}``. They are the vertical
diffusion, the horizontal EDMF diffusive flux, the hyperdiffusion, the viscous
sponge, and, with updraft copies, the updrafts' diffusion and hyperdiffusion.
Under 1-moment microphysics the rain and snow make the difference. The
hyperdiffusion also takes ``\rho q_\mathrm{tot}`` as a perturbation from a
reference profile ``q_\mathrm{tot,r}(p)`` and the tags not, so it drifts the
partition under 0-moment too, wherever that profile varies along a model level.
`q_tag_leak_<path>` is each path's source, in closed form from the state
(`water_tag_leak!`): the rate at which the path would drift an exactly closed
partition. It does not read the tags, so it leaves out the path's transport of
a residual already there. No path corrects it yet.

It is not the *only* contributor, though. Any tendency that writes
``\rho q_\mathrm{tot}`` by name without an attribution bracket and without a
tagged counterpart also lands here — see the Caveats below for the known
case, the `PrescribedFlow` surface water inflow. If `q_tag_res` grows faster
than expected, check that and the leaks before concluding the advection split
is responsible.

A sharper *process closure* check is available by splitting a source tag across
a partition: with `evap`, `evap_tropics` and `evap_extratropics`, linearity of
production, loss, transport and the limiter rescale implies
``q_\mathrm{tag,evap\_tropics} + q_\mathrm{tag,evap\_extratropics} = q_\mathrm{tag,evap}`` to near machine precision at all times — any violation
indicates a bug rather than expected leakage.
`config/model_configs/baroclinic_wave_tagged_water.yml` and the integration test use
this identity.

## Scope

Water tagging supports `microphysics_model: "0M"` and `"1M"`, and
`check_water_tagging_supported` errors otherwise. It is refused under
`turbconv: prognostic_edmfx` with more than one updraft and under
`amd_les: true`, and warns when the run has a prescribed flow; see
`check_water_tracers_transport_supported`,
`warn_water_tags_under_prescribed_flow` and the Caveats below. `water_process_record` is not refused under any of them, since
its records are not transported.

  - **0-moment**: every writer of ``\rho q_\mathrm{tot}`` is a local source or
    sink, so bracketed attribution alone is exact and nothing sediments.
  - **1-moment**: phase changes are *not* an obstacle — those conserve
    ``\rho q_\mathrm{tot}`` and are invisible to the tags. Sedimentation is,
    and it is handled by mirroring the flux per tag rather than attributing it;
    see [Sedimentation with 1-moment microphysics](@ref).
  - **Dry**: there is no ``\rho q_\mathrm{tot}`` in the state to partition.
  - **2-moment and P3** remain unsupported: they additionally carry prognostic
    number concentrations, whose provenance is a separate question from the mass
    provenance these tags partition, and mirroring only the mass flux would leave
    the number field untagged and the two inconsistent.

## Caveats

  - Under `PrognosticEDMFX` the default mode's updraft composition is a model,
    a steady entraining plume, not a prognostic field. The copies audit it.
    Which of the two a study should use is not settled yet.
  - Tag names are restricted; see [Tag entries](@ref) in the tracer
    configuration page.
  - With a **`PrescribedFlow`** setup (e.g. `ShipwayHill2012`), the surface
    water inflow imposed as a vertical-transport boundary condition adds to
    ``\rho q_\mathrm{tot}`` outside every attribution bracket and has no tagged
    counterpart. That water enters the domain untagged and `q_tag_res` drifts
    monotonically. The combination is accepted, with a warning when the model
    is built, and `prescribe_flow!` does rescale the tags after its
    clip — so the tags stay consistent with each other, they are just
    collectively short of ``\rho q_\mathrm{tot}`` by the injected amount.
  - The `ρe_tag_*` family's `microphysics` label still fires only when
    microphysics is stepped explicitly. The water tags are bracketed on the
    implicit path too, because `implicit_microphysics` defaults to `true` and
    that is where the 0-moment water sink lives, and so are the energy source
    tags and the process records.
  - Tagged state is carried through restarts like any other prognostic field.
    The masks are rebuilt from the configuration, so the `water_tracers` block
    must match the one used to write the checkpoint, and the restart guard
    refuses one that does not. The `q_tag_fix` and `q_tag_upfix` ledgers are
    cache-resident and restart at zero.

## Interpretation limit

Exact closure establishes internally consistent contribution accounting; it does
not turn the tags into counterfactual sensitivities. The donor-fraction loss
rule, the well-mixed-phases assumption behind `qv_tag`, and the limiter rescale
policy are modeling choices, and conclusions are conditional on them.

See `config/model_configs/baroclinic_wave_tagged_water.yml` for a complete example,
and `test/tagged_water_integration.jl` for the closure assertions.

## Tagged water API

Rendered here so that the `@ref` links in these docstrings resolve; Documenter
resolves `@ref` only against docstrings a `@docs` block splices into a page.

```@docs
ClimaAtmos.WaterTaggingModel
ClimaAtmos.WaterTag
ClimaAtmos.KNOWN_WATER_TAG_SOURCES
ClimaAtmos.WATER_TAG_SOURCE_GROUPS
ClimaAtmos.water_tag_fraction
ClimaAtmos.water_tag_share_norm!
ClimaAtmos.water_tag_sediment_share
ClimaAtmos.sediment_water_tags!
ClimaAtmos.snapshot_tagged_ρq_tot!
ClimaAtmos.attribute_tagged_ρq_tot!
ClimaAtmos.rescale_water_tags!
ClimaAtmos.water_tag_rescale_shift
ClimaAtmos.water_tag_source_rescale_shift
ClimaAtmos.repair_water_tag_partition!
ClimaAtmos.check_water_tag_exchange_partition
ClimaAtmos.water_tag_edmf_scratch
ClimaAtmos.sgs_mass_flux_of_water_tags!
ClimaAtmos.sgs_exchange_of_water_tags!
ClimaAtmos.water_exchange_inputs!
ClimaAtmos.water_tag_plume!
ClimaAtmos.start_water_tag_copies_from_plume!
ClimaAtmos.water_tag_updraft_copy_names
ClimaAtmos.with_water_tag_updraft_copies
ClimaAtmos.rebuild_water_tag_updraft_copies!
ClimaAtmos.water_tag_copies_microphysics_tendency!
ClimaAtmos.sediment_water_tag_copies!
ClimaAtmos.water_tag_copies_boundary_condition_tendency!
ClimaAtmos.water_tag_copies_surface_flux_tendency!
ClimaAtmos.repair_water_tag_copies!
ClimaAtmos.water_tag_copy_sgs_names
ClimaAtmos.water_tag_edmf_audit
ClimaAtmos.WATER_TAG_LEAK_PATHS
ClimaAtmos.water_tag_leak!
ClimaAtmos.splits_rainout
ClimaAtmos.add_split_rainout!
ClimaAtmos.add_rainout_increments!
ClimaAtmos.water_tag_precipitation!
ClimaAtmos.IncrementWaterTagTransport
ClimaAtmos.TracerWaterTagTransport
ClimaAtmos.follows_water_increment
ClimaAtmos.snapshot_water_tag_increment!
ClimaAtmos.correct_water_tag_increment!
ClimaAtmos.WaterTagIncrementCorrection
ClimaAtmos.tag_post_implicit
ClimaAtmos.water_tag_post_implicit
ClimaAtmos.check_water_tag_increment_supported
ClimaAtmos.water_tag_increment_ledger_variables
ClimaAtmos.water_tag_extra_audit
ClimaAtmos.WATER_TAG_CHECKPOINT_VERSION
ClimaAtmos.write_water_tag_checkpoint_attributes!
ClimaAtmos.check_water_tag_checkpoint
```
