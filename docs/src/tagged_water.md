# Tagged Water Tracers

Tagged water tracers split total water ``\rho q_\mathrm{tot}`` by where the
water entered. Each tag is a transported field `Y.c.ρq_tag_<name>`. New water
takes the label of where it enters. Losses come out of every tag in proportion
to what it holds. The key is `water_tracers`, and it is off by default. With it
on, every model field that exists without it stays bit for bit as in the same
run with it off, under the default solver settings. Only the tags' own fields
and output are added. The [parity
contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
states the limits.

The tag results are attributions defined by the configured rules. They are not
a unique physical history. Read [Attribution](#Attribution) before using the
output. The water tags share the region masks, the configuration schema and the
restart handling of the [Tagged Energy Tracers](tagged_tracers.md). See
[Configuring Tracers](tracer_configuration.md) for the full schema.

!!! warning "Total water is not water vapor"

    The `hus` diagnostic in this repository is named "Specific Humidity" but
    computes ``\rho q_\mathrm{tot}/\rho``, the mass of **all** water phases.
    `husv` is the vapor-only counterpart. The tagged names do not inherit that
    ambiguity. `q_tag_<name>` is total water and `qv_tag_<name>` is vapor. In
    the CliMA formulation ``q_t = q_v + q_l + q_i``, with ``q_l`` and ``q_i``
    including precipitation.

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

Each entry needs a unique `name` and a `region`, a `source`, or both.
`water_tracers: ~`, the default, adds no state fields, cache entries or runtime
cost. [Tag entries](tracer_configuration.md#Tag-entries) lists the region types
and the named regions. The `water_closure_check` block reduces `q_tag_res` to a
few numbers and warns while the run goes.

A region tag starts as ``\max(\rho q_\mathrm{tot}, 0)\, M(x)``, with ``M`` its
region mask. A tag with a `source` starts at zero. `q_tag_res` sums all region
tags, so configure exactly one partition of unity per run, such as a region and
its complement. The model warns at initialization when the region masks do not
sum to 1.

## Attribution

For each attributed process, its tendency ``\Delta`` of ``\rho q_\mathrm{tot}``
is split into a gain ``\Delta^{+} = \max(\Delta, 0)`` and a loss
``\Delta^{-} = \max(-\Delta, 0)``. The two halves follow different rules:

```math
\Delta\!\left(\rho q_{\mathrm{tag},k}\right)
= M_k \, \Delta^{+} - \varphi_k \, \Delta^{-},
\qquad
\varphi_k = \frac{\rho q_{\mathrm{tag},k}}{\rho q_\mathrm{tot}}.
```

  - **A gain goes by mask.** ``M_k`` is the tag's region mask. It is 1 for a tag
    without a region and 0 for a tag that does not list this process. New water
    carries the label of where it entered.
  - **A loss goes in proportion to what each tag holds.** ``\varphi_k`` is the
    tag's share: its water over the parent's in the cell, limited to 0 to 1 and
    zero where the parent is not positive. Every tag loses, source tags
    included, whatever processes they list. So ``\rho q_{\mathrm{tag},k}`` is a
    water mass and not a running source integral.

The energy tags differ here. They attribute the whole tendency by mask. A loss
by mask would remove water a tag does not own and could drive tags negative. The
rule is the tendency form of the relative scaling in the MESSy `H2OEMIS`
submodel.

**Closure.** With ``\sum_k M_k = 1`` and
``\sum_k \rho q_{\mathrm{tag},k} = \rho q_\mathrm{tot}``, the shares sum to 1
and ``\sum_k \Delta_k = \Delta`` exactly, for each process. If the tags are a
strict subset, such as one "Atlantic evaporation" tag, the untagged remainder
absorbs the rest. That is correct, but it is not a partition.

**Positivity.** A tag update is
``\rho q_{\mathrm{tag},k}\,(1 - \Delta^{-}\Delta t / \rho q_\mathrm{tot})``. A tag
stays non-negative while ``\Delta^{-}\Delta t`` does not exceed
``\rho q_\mathrm{tot}``, as the parent itself needs under the 0-moment sink.
Nothing enforces that.

### Where the parent is negative

`ρq_tot` is not kept non-negative by default (`tracer_nonnegativity_method: ~`), and transport can drive a cell negative. No set of non-negative tags can
partition a negative amount. So the water tags partition
``\max(\rho q_\mathrm{tot}, 0)``. Where `ρq_tot` is negative they partition
zero, and `q_tag_negative` holds the parent's negative water. The two add up to
`ρq_tot`. Where the parent is never negative, nothing changes, bit for bit.

Each part of the machinery follows this rule.

  - A process gives the tags the gain of the target, ``\max(\rho q_\mathrm{tot}, 0)``. Where the parent is negative, a gain fills the negative part and no tag
    takes it, except a source tag's environment part of the split rain-out
    with copies (see below). The ledger `q_tag_exp_negative` records what is withheld.
  - The limiters' change of `ρq_tot` and the copies' repair take a partition
    whose parent they leave negative to zero, not below.
  - The closure check compares the partition with the non-negative part.
  - Under increment transport, where a solve takes a cell below zero, the cell's
    tags move out by the partition's own composition. The water the parent
    creates elsewhere by overdrawing that cell goes to the tags where the
    mismatch has its sign, by their composition there. The ledger
    `q_tag_inc_negative` records it.

This allocation is a numerical closure convention, not a physical path of water.
It can move origin between cells that no water moved between. The closure can
pass while the parent is negative, so the closure check also reads the raw
`ρq_tot`. See [The parent's negative water](@ref) for
`negative_water_relative` and the flag `negative_water_void`.

### Taggable processes

| Group     | `source` label          | Process                                                                |
|:--------- |:----------------------- |:---------------------------------------------------------------------- |
| `surface` | `surface_flux`          | Turbulent surface moisture flux (evaporation, or dew when negative)    |
| *(none)*  | `microphysics`          | The 0-moment total-water sink                                          |
| `forcing` | `large_scale_advection` | Prescribed large-scale advective moistening or drying                  |
| `forcing` | `subsidence`            | Prescribed large-scale subsidence                                      |
| `forcing` | `external_forcing`      | Externally prescribed (such as GCM-driven) forcing and `q_tot` nudging |

The group `all` expands to every process in the table. `microphysics` belongs to
no named group. So `source: surface` follows evaporation but not the 0-moment
sink. To follow both without the forcings, write
`source: [surface_flux, microphysics]`. The set is smaller than the energy
tags'. `radiation` and `held_suarez` do not move water.

Splitting a tendency by sign is exact where gain and loss exclude each other at
a point. That holds for the surface flux, which is evaporation or dew, and for
the 0-moment tendency, which is a sink. For the prescribed forcings it is an
assumption.

### What is not attributed

  - **Transport.** Advection, hyperdiffusion, sponges, interior vertical
    diffusion and LES SGS diffusion act on each tag in its own right.
    Attributing the `ρq_tot` version on top would count transport twice.

  - **Phase changes.** Condensation, evaporation, freezing and melting conserve
    ``q_t``, so a total-water tag does not see them. A vapor-only tracer would
    lose its origin at every phase change.

  - **Sedimentation.** With 0-moment microphysics nothing sediments. With
    1-moment, each tag's flux is built like the parent's and scaled by its
    share. See [Sedimentation with 1-moment microphysics](@ref).

  - **Numerical corrections.** `rescale_water_tags!` follows them. The tags are
    excluded from both tracer limiters. Limiting each tag on its own would not
    reproduce the parent's change and would break
    ``\sum_i \rho q_{\mathrm{tag},i} = \rho q_\mathrm{tot}``. Instead the
    limiters' change of the parent,
    ``\Delta = \rho q_\mathrm{tot}^{\,\mathrm{after}} - \rho q_\mathrm{tot}^{\,\mathrm{before}}``,
    is handed out in proportion to what each tag holds,
    ``\rho q_{\mathrm{tag},k} \leftarrow \rho q_{\mathrm{tag},k} + \Delta\,s_k``.
    The share ``s_k`` is renormalized over the partition, so the partition
    absorbs ``\Delta`` in full. The signed water moved is the fix ledger
    `q_tag_fix_<name>`.

    The correction adds ``\Delta`` and does not scale the tags. Scaling
    multiplies the closure error by the factor it applies to the tags, so a cell
    that a limiter lifts at every stage compounds the error. Adding ``\Delta``
    leaves the error where it was. The loss is floored at what the tags hold, so
    a non-negative tag stays non-negative. Where the floor binds, the tags empty
    and the water they could not account for shows in `q_tag_res`. A tag that is
    already negative is not lifted, because its share is zero.
    `repair_water_tag_partition!` handles those tags.

### Sedimentation with 1-moment microphysics

With `microphysics_model: "1M"` the condensate species are prognostic and fall.
Sedimentation moves ``\rho q_\mathrm{tot}`` between levels. Attributing its net
tendency in a cell would label the arriving water with the receiving cell's mask.
It would also drain the departing water by the total-water composition, when the
falling condensate's composition is what leaves.

So `sediment_water_tags!` builds each tag's flux like the parent's. It runs once
per sedimenting species inside `vertical_advection_of_water_tendency!`. It takes
the same specific content, terminal velocity, face density and donor-cell
(`ᶠtop_bias`) reconstruction as the parent, and scales the flux by the tag's
share. The tagged fluxes then sum to the parent flux level by level, and the
surface precipitation is tagged.

  - **Region tags** use the renormalized share
    ``\hat\varphi_k = \varphi_k / \sum_j \varphi_j``. Unlimited transport lets a
    tag drift out of the partition, and the clamped shares then no longer sum to
     1. Dividing by their sum restores exact closure and keeps
        ``\hat\varphi_k`` in ``[0, 1]``.
  - **Source tags** are not part of the partition. Their share is the
    unnormalized ``\varphi_k``.

Where no tagged water is present the share is zero. If ``\rho q_\mathrm{tot}`` is
nonzero there, closure cannot hold, and the difference shows in `q_tag_res`.

The tags enter the implicit Jacobian. `update_sedimentation_jacobian!` fills
their diagonal blocks with the analytic derivative of the share. For a region
tag it carries a ``(1 - \hat\varphi_k)`` factor, because a tag that holds all the
local water cannot raise its share. Each tag also gets a cross block to each
falling species, the parent's block times the tag's share. The manual
Jacobian's split solver carries the cross blocks, and the dense autodiff
Jacobian (`use_dense_jacobian: true`) is exact. The sparse autodiff Jacobian
(`use_auto_jacobian: true`) lacks them. See [Manual
differentiation](implicit_solver.md#Manual-differentiation).

The sedimenting condensate is taken to carry the cell's total-water tag
composition, since the tags hold no phase information. `qv_tag` rests on the same
assumption of well-mixed phases.

## Under prognostic EDMF

With `turbconv: prognostic_edmfx` and one updraft, the tags follow the updraft's
water. The model's sub-grid mass flux moves ``\rho q_\mathrm{tot}`` between the
updraft, the environment and the grid mean. `water_tag_updraft_copy` picks how
the tags follow it.

**The default mode** (`false`). The tags have no updraft state. At each face,
each tag takes its share of the parent's sub-grid flux of water, from the donor
cell. The shares of the partition are renormalized to sum to 1. That share is the
grid mean's composition, not the updraft's. So an exchange of composition at the
updraft's mass flux adds the difference. The exchange sums to zero over the
partition. It is bounded so that no tag moves more water than a subdomain holds,
and the audit reports where the bound binds.

The updraft's composition comes from a steady entraining plume. The plume starts
at the lowest level with the grid mean's composition and the updraft's surface
water, by region and source. It mixes in the grid mean's composition at the
entrainment rate. At each level it is rescaled to the updraft's water
``q_\mathrm{tot}^j``. The exchange needs region tags whose masks sum to 1 within
0.01. A run without them is refused.

**The copies** (`true`) are a comparison mode. Each tag gets a copy in the
updraft, `q_tag_<name>`: the tag's water per unit mass of updraft air. The model
moves it as any other updraft tracer. The grid-scale tags take their sub-grid
flux from the copies, and the default mode's flux and exchange do not run. The
copies get the same change as the updraft's water in five places where a tracer
gets none.

  - The 0-moment rain-out. Each copy loses its share of the water rained out.
  - The 1-moment sedimentation. Each copy's rain and snow fall with its share.
    The environment's falling water enters with the environment's composition.
  - The relaxation at the surface. Each copy relaxes toward the buoyant surface
    water times the grid mean's share.
  - The surface flux. `surface_flux_tendency!` also adds the surface moisture
    flux to ``q_\mathrm{tot}^j``. Each copy takes that water by the grid-scale
    tags' rule for the label `surface_flux`.
  - The repair after the filter, with or without the filter. The residual
    ``q_\mathrm{tot}^j - \sum_i \chi_i^j`` is added to the partition's copies by
    their shares, floored at what each holds. Where their sum is not positive
    they are zeroed. The correction goes to `q_tag_upfix_<name>`, and the
    residual the repair found to `q_tag_copy_res`.

`q_tag_copy_res` and `q_tag_upfix` bound everything that parts the copies from
``q_\mathrm{tot}^j``, not the filter alone. That includes the grid partition's
own residual, the Newton iterations, the leaks and the rain-out's clamp. The
ledger is signed and cumulative, so repairs of opposite sign cancel in it. The
copies start, and are rebuilt from a file, as ``q_\mathrm{tot}^j`` times the grid
mean's share. They cost one updraft tracer per tag.

**The 0-moment rain-out.** Under 0-moment microphysics, EDMF computes the
rain-out per subdomain, ``\Delta^j = \rho a^j \, \partial_t q_\mathrm{tot}^j`` in
the updraft and ``\Delta^0 = \rho a^0 \, \partial_t q_\mathrm{tot}^0`` in the
environment. The model adds their sum to ``\rho q_\mathrm{tot}``. The grid-scale
tags take each part by that subdomain's composition, and not by the grid mean's
(`splits_rainout`, `add_split_rainout!`).

  - With the copies, the updraft's share is the copy's,
    ``\chi_i^j / q_\mathrm{tot}^j``. The environment's is what the grid tags and
    the copies leave for it.
  - In the default mode the model holds no subdomain composition. The split
    rebuilds one from the grid mean's shares plus the exchange's difference, from
    the steady plume. It is a modeled estimate, not a prognosed value.
  - The partition's shares are scaled by the partition's sum of grid shares, so a
    drifted partition keeps losing in proportion to what it holds. Where a
    subdomain's share is not defined, the grid mean's applies.
  - The split applies to both signs, since a subdomain's area can go negative in
    the Newton iterates. There the subdomain's rain-out is a gain, and the split
    attributes it. So the split and `pr_tag` are signed attributions that close
    with the sink. They are not a measure of physical rain-out alone. With the
    copies, a source tag's environment part is not withheld where the parent
    is negative.
  - Without the SGS mass flux there is no exchange, and the grid mean's share
    applies to all the rain-out, as without EDMF.

**Refusals.** Both modes refuse more than one updraft. The copies are refused
without prognostic EDMF, and when `edmfx_mse_q_tot_upwinding` differs from
`edmfx_tracer_upwinding`, because the copies' fluxes then do not sum to the
parent's. `amd_les: true` is refused. AMD diffuses each tracer with a diffusivity
from that tracer's own gradient, so the tags' diffusion does not add up to the
parent's.

## Increment transport

`water_tag_transport: increment` makes the tags take the parent's implicit
increment of ``\rho q_\mathrm{tot}`` after each solve. The other value, `tracer`,
moves them as tracers. The default, `~`, picks `increment` in the default mode
under `turbconv: prognostic_edmfx` where the configuration supports it, and
`tracer` elsewhere and with copies. Supported means an ARS algorithm, an
`energy_q_tot_upwinding` other than `none`, a region tag without a source, and
microphysics other than 1M stepped explicitly. With 1M stepped explicitly,
`increment` is opt-in.

The reason is a lag. ``\rho q_\mathrm{tot}`` is advected vertically in the
implicit step, and its sub-grid flux and diffusion have Jacobian blocks that the
tags' terms lack. With one Newton iteration the tags then lag the parent's solve,
and the lag shows in `q_tag_res`.

Under the key the tags skip their explicit vertical advection. After each Newton
solve, `correct_water_tag_increment!` takes the difference `m` between the
parent's increment and the partition's in each cell.

  - The part of `m` that sums to zero in the column is moved as a vertical flux.
    Each tag takes it by its share in the cell the flux leaves. The ledger
    `q_tag_inc_moved` records it.
  - The part that changes the column's total, ``\int m``, is left out of the tags
    and stays in `q_tag_res`. The ledger `q_tag_inc_left` records it.
  - The part that the parent's negative water creates goes to the tags by the rule
    in [Where the parent is negative](@ref). The ledger `q_tag_inc_negative`
    records it.

The energy source tags' `enthalpy_increment` does the same for their total, and
one hook runs both. The correction cannot do four things.

  - Change a column's total. A lag in the surface outflow of sedimentation stays
    in the net residual.
  - Say where the part left out arose. It is spread over the cells whose `m` has
    the column total's sign, in proportion to `m`. The parent's vertical advection
    dominates `m`. No cell leaves out or moves more than its own `m`.
  - Move water a partition does not hold. A residual pinned in a cell stays there.
    A draining cell's partition can go negative, which the partition repair then
    moves.
  - Follow explicit processes, the copies, or a donor cell with an empty
    partition.

The model refuses `increment` where it needs one of three things and lacks it.

  - Region tags that partition the domain, their masks summing to 1 within 100
    rounding units.
  - An algorithm that solves every implicit stage it uses, such as ARS222 or
    ARS343.
  - The parent's own post-solve correction, which exists unless
    `energy_q_tot_upwinding` is `none`.

With 1M stepped explicitly, each grid-scale tag's Jacobian row carries the
parent's sedimentation cross block to each falling species, times the tag's
share. Without these blocks the lag changes the column's total, which the
correction cannot move. So `use_auto_jacobian: true` is refused there, unless
`use_dense_jacobian: true`, whose autodiff is exact. The
updraft copies' rows have no cross blocks. The split Jacobian solver solves the
tags after the other fields, by back-substitution, so the model's fields do not
change.

A restart that changes `water_tag_transport` is refused. A checkpoint written
with `tracer` under EDMF restarts only if `water_tag_transport: tracer` is set, also
where the default would pick `increment`.

## Rain and snow parts

With `water_tag_precipitation: true`, which is Experimental, each tag has three
parts: the water that is neither rain nor snow, the rain and the snow. The page
[Rain and Snow Tags](tagged_water_precipitation.md) describes it.

## Diagnostics and closure

| Diagnostic                                                                                                         | What it holds                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|:------------------------------------------------------------------------------------------------------------------ |:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `q_tag_<name>`                                                                                                     | Tagged total water ``\rho q_\mathrm{tag}/\rho``. Under `water_tag_precipitation: true`, the sum of the tag's three parts                                                                                                                                                                                                                                                                                                                                                   |
| `qv_tag_<name>`                                                                                                    | Tagged vapor, ``q_\mathrm{tag}\, q_v / q_t``. The `comments` field states the well-mixed-phases assumption                                                                                                                                                                                                                                                                                                                                                                 |
| `q_tag_res`                                                                                                        | Closure residual ``(\max(\rho q_\mathrm{tot}, 0) - \sum_i \rho q_{\mathrm{tag},i})/\rho``, summed over the region tags                                                                                                                                                                                                                                                                                                                                                     |
| `q_tag_negative`                                                                                                   | The parent's negative water, ``\min(\rho q_\mathrm{tot}, 0)/\rho``. With `q_tag_res` and the region tags it adds up to ``q_\mathrm{tot}``. Under `water_tag_precipitation: true` it is taken per compartment                                                                                                                                                                                                                                                               |
| `q_tag_negative_integral`, `q_tag_negative_events`                                                                 | Per cell since the start of the run, carried through a restart: the sum over accepted steps of ``\max(-\rho q_\mathrm{tot}, 0)\,\Delta t`` in kg s m⁻³, and the number of steps with ``\rho q_\mathrm{tot} < 0``. In no default output                                                                                                                                                                                                                                     |
| `q_tag_fix_<name>`                                                                                                 | The fix ledger: water moved into or out of the tag by the limiters, the constraints and the partition repair. Cumulative since the start of the run and carried through a restart, so an interval's change is a difference of two outputs. A time average is not meaningful                                                                                                                                                                                                |
| `q_tag_upfix_<name>`, `q_tag_copy_res`                                                                             | With copies, the copies' repair, cumulative like `q_tag_fix`, and the residual it found                                                                                                                                                                                                                                                                                                                                                                                    |
| `q_tag_leak_<path>`                                                                                                | The leak of a path: `vdiff`, `hdiff`, `hyperdiff`, `sponge`, `diffusion_up` or `hyperdiff_up`. See below                                                                                                                                                                                                                                                                                                                                                                   |
| `pr_tag_<name>`, `prra_tag_<name>`, `prsn_tag_<name>`                                                              | Under 0-moment: the tag's part of `pr`, `prra` and `prsn`, the column integral of its part of the rain-out. Upward-positive as `pr` is, split into rain and snow by the grid mean's temperature, and computed from the state at output time. All tags are computed together once per output time. Under 1-moment with `water_tag_precipitation: true`, only `pr_tag_<name>` exists                                                                                         |
| `pr_tag_res`                                                                                                       | Under 0-moment with a region tag: `pr` less the region tags' `pr_tag`, the rain-out no region tag takes. It shows the partition's residual and the copies' at the surface                                                                                                                                                                                                                                                                                                  |
| `q_tag_fixgross_<name>`, `q_tag_fixcount_<name>`, with copies `q_tag_upfixgross_<name>`, `q_tag_upfixcount_<name>` | Beside each fix ledger: the sum of the absolute values of its changes, and the number of cell-events above rounding. A change of `+x` then `-x` reads zero in the ledger and twice the absolute value of `x` in the gross. They count every call, including those in a step the stepper discards, so they record what was attempted. Float64, carried through a restart                                                                                                    |
| `q_tag_led_<mechanism>`                                                                                            | What each correction moved, as the accepted steps retained it. State fields, weighted by the stepper as the tags are, carried through restarts. See below                                                                                                                                                                                                                                                                                                                  |
| `<ledger>_gross`, `<ledger>_colgross`                                                                              | For each `q_tag_led_*` and for `q_tag_inc_left` and `q_tag_inc_moved`: the sum over the steps of the ledger's absolute change per cell, and of the absolute change of its column integral. Float64, carried through a restart. A default callback keeps them, so they read zero without the default callbacks                                                                                                                                                              |
| `q_tag_led_fix_<name>`, `q_tag_led_inc_<name>`                                                                     | With `water_tag_ledger_per_tag: true`: each tag's own ledgers, what the limiters' change and the partition repair changed the tag by, and what increment transport moved into or out of it. Each has `_gross` and `_colgross`, spelled `q_tag_led_fixgross_<name>` and `q_tag_led_fixcolgross_<name>` (and `inc` alike). Under `water_tag_leak_correction: true`, each tag also has `q_tag_led_leak_<name>`, and with copies `q_tag_led_upleak_<name>`, times ``\rho a^j`` |

| Mechanism              | What `q_tag_led_<mechanism>` holds                                                                                                                                                                                                                                    |
|:---------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rescale`, `empty`     | The limiters' and constraints' change where the parent held water, and the removal where it did not                                                                                                                                                                   |
| `repair`, `repairnet`  | The partition repair's transfer between the tags, and the water it adds where it zeroes every tag                                                                                                                                                                     |
| `uprepair`, `upfilter` | With copies: the copies' repair, and the updraft filter's change of the copies                                                                                                                                                                                        |
| `leaknet`, `upleaknet` | Under `water_tag_leak_correction: true`: what the correction gave the partition's tags, net over them, and with copies what it gave their copies, times ``\rho a^j``. A tendency writes them, so they are exact per step at every cadence and have no attempted total |

All are signed except `repair`.

The audit table (`audit: true`, see [The audit table](@ref)) has these columns for
each state ledger `L`, named without its `q_tag_` prefix.

| Column                                                                                   | What it holds                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|:---------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `<L>_retained`                                                                           | The per-step gross integrated over the domain since the start of the run: what the accepted steps kept                                                                                                                                                                                                                                                                                                                                                                         |
| `<L>_attempted`                                                                          | What the writers added, in absolute value, over every call, including calls on stage values that the stepper discards. For a tag's `led_fix` ledger it is the gross of its fix ledger, `q_tag_fixgross_<name>`. Under `water_tag_precipitation: true` it also counts moves between a tag's own parts, which leave the tag's ledger unchanged                                                                                                                                   |
| `<L>_events`                                                                             | The cell-steps whose change of `L` exceeded rounding                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `<L>_retained_relative`, `<L>_attempted_relative`                                        | The first two over the audit's scale                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `<L>_inventory_fraction`, `<L>_burden_fraction`, `<L>_parent_fraction`, `<L>_applicable` | For a tag's own ledger: `<L>_retained` over the tag's water now, over its absolute burden ``\int \lvert \rho q_\mathrm{tag} \rvert``, and over ``\int \rho q_\mathrm{tot}``, and whether a ratio to the tag applies. Under `water_tag_precipitation: true` the tag's water is the sum of its three parts. Under increment transport most of `led_inc` is the parent's vertical advection, so its ratio bounds the correction's intervention from above and does not isolate it |
| `ledger_parent_scale`, `ledger_cadence_step`                                             | With the ledgers per tag                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

**Which ratio to read.** Read a ratio to the tag only where `<L>_applicable` is

 1. That flag is 0 where the tag's burden is below 2e-4 of
    ``\int \rho q_\mathrm{tot}`` (`TAG_LEDGER_SMALL_TAG_BOUND`) or zero. Then
    `_parent_fraction` judges the tag. A ratio whose denominator is not positive is
    `NaN`, and `_applicable` is `NaN` only if the tag or its ledger is not finite.

  - A region tag is read by `_inventory_fraction`, whose precondition is a positive
    inventory.
  - A source tag, such as `evap`, and any tag with negative parts are read by
    `_burden_fraction`. A tag's negative parts can cancel its positive parts, so
    its inventory nears zero and the inventory ratio grows without bound, whatever
    the correction did. The burden does not cancel. For a tag without negative
    parts the two ratios are the same number.

At the default `update_constrain_state_every: step`, the corrections fire once per
step on the accepted state. Then `<L>_attempted` less `<L>_retained` is the work
the steps discarded, for the ledgers per mechanism. At `stage` or `dss` the
stepper weights each stage's firing by its tableau weight, which is negative once
under ARS343. A ledger can then fall within a step, and its per-step change is
neither what the step moved nor a bound on it. In Float32 the state ledgers lose
any change below one rounding unit of their value, about 6e-8 of it, and the
Float64 grosses cannot recover that. A cell-event is a change above 1e-12 of the
cell's total, or 16 rounding units of the float type if larger.

Two mechanisms write to the fix ledger. `repair_water_tag_partition!` runs every
step and contributes wherever transport drove a region tag negative. So
`q_tag_fix_<name>` is generally nonzero even under stock settings, and it measures
how much the tags drift. `rescale_water_tags!` contributes only when something
corrects ``\rho q_\mathrm{tot}``: `apply_sem_quasimonotone_limiter: true`,
`tracer_nonnegativity_method: vertical_water_borrowing`, an elementwise
nonnegativity constraint, or a `PrescribedFlow` setup.

### Sources of `q_tag_res`

`q_tag_res` is a monitored residual, not a machine-precision identity.

  - **The vertical advection split.** Under `water_tag_transport: tracer`,
    ``\rho q_\mathrm{tot}`` is advected implicitly with a post-Newton upwind
    correction, while the tags ride the explicit passive-tracer path. Under
    `increment` the part of the mismatch that changes a column's total stays in
    `q_tag_res` and in `q_tag_inc_left`. Subtract `q_tag_fix_*` to separate the
    operators' disagreement from numerical corrections.

  - **Leaks.** Some paths move the tags as passive tracers on their whole value,
    and ``\rho q_\mathrm{tot}`` only by the water that diffuses,
    ``q_\mathrm{tot} - q_\mathrm{rai} - q_\mathrm{sno}``. They are the vertical
    diffusion, the horizontal EDMF diffusive flux, the hyperdiffusion, the viscous
    sponge, and with copies the updrafts' diffusion and hyperdiffusion. The
    hyperdiffusion also takes ``\rho q_\mathrm{tot}`` as a perturbation from a
    reference profile ``q_\mathrm{tot,r}(p)``, and the tags not. So it drifts the
    partition under 0-moment too, wherever the profile varies along a model level.
    Where ``\rho q_\mathrm{tot}`` is negative, every path moves the parent by the
    negative part and the tags not.

    `q_tag_leak_<path>` is each path's rate, in closed form from the state
    (`water_tag_leak!`): its tendency of the tags' sum minus its tendency of
    ``\rho q_\mathrm{tot}``, over ``\rho``, at a partition closed to
    ``\max(\rho q_\mathrm{tot}, 0)``. Where the parent is negative the leak
    includes the path's transport of the negative part. So it is the path's source
    of `q_tag_res + q_tag_negative`, with the opposite sign. It leaves out the
    path's transport of any other residual. `water_tag_leak_correction: true`
    corrects two of the paths. See [The EDMF diffusion leak correction](@ref).

  - **Tendencies without a tagged counterpart.** A tendency that writes
    ``\rho q_\mathrm{tot}`` by name, outside an attributed process, lands in
    `q_tag_res`. The `PrescribedFlow` surface water inflow is the known case.

A sharper process closure check splits a source tag across a partition. With
`evap`, `evap_tropics` and `evap_extratropics`, linearity implies
``q_\mathrm{tag,evap\_tropics} + q_\mathrm{tag,evap\_extratropics} = q_\mathrm{tag,evap}``
to near machine precision at all times. A violation indicates a bug and not an
expected leak. `config/model_configs/baroclinic_wave_tagged_water.yml` and the
integration test use this identity.

### The EDMF diffusion leak correction

`water_tag_leak_correction: true` is Experimental and off by default. It corrects
the leak of the EDMF vertical diffusive flux and of the updrafts' diffusion of the
copies. Each tag takes back the diffusion of its own share of the rain and snow,
``\nabla\cdot(\rho K_h \nabla(\psi_i\, q_\mathrm{p}))`` with
``q_\mathrm{p} = q_\mathrm{rai} + q_\mathrm{sno}``. Here ``\psi_i`` is the share
that sedimentation takes the tag's rain and snow by. The partition's shares sum to
1 wherever it holds water, so its diffusion is then the parent's. With copies,
each copy takes its tag's correction per unit mass, as it takes its tag's
diffusion. No other path is corrected, and the key is refused with `vert_diff`,
whose diffusion leaks the same way. See `correct_water_tag_diffusion_leak!`. Its
validation did not meet its own criteria, so it is not a default. Its limits are
these.

  - **Each tag's share of the rain and snow is an assumption.** The tags hold no
    phase, so the correction takes the rain and snow to have the cell's
    total-water composition, as sedimentation does. This closes the partition's
    diffusion. It does not show that the tags it charges are the ones whose water
    leaked.
  - **Where the partition holds no water, or the parent's water is not positive,
    the leak is left.** The shares are zero there, and so is the correction. That
    part stays in `q_tag_res`, or under increment transport in `q_tag_inc_moved`.
  - **It has no Jacobian block.** The correction is written in the implicit
    tendency after the tracer loop of `edmfx_sgs_diffusive_flux_tendency!`. The
    Newton solve does not see it, and each iteration evaluates it again at that
    iteration's state. With one iteration it is taken at the stage's first guess.

## Accepted applications

`water_tag_applications: true` writes every accepted application of the water
tags' corrections. It is off by default and only reads the model. The model's
fields are those of the same run without it, bit for bit. The tests show this
after each of six steps for one configuration, in Float64 and in Float32: the
1-moment column with rain and snow parts, two region tags and a source tag,
increment transport and per-tag ledgers.

A channel is a mechanism, a tag and a compartment. The compartment is `total`
without rain and snow parts, and `nonprecipitating`, `rain` or `snow` with them.
The roster holds these mechanisms:

| Mechanism  | Writer                                                 | Quantity, units                | Event scale                   |
|:---------- |:------------------------------------------------------ |:------------------------------ |:----------------------------- |
| `rescale`  | the rescale where the parent held water                | `water_increment`, kg m^-3     | `ρq_tot` before               |
| `empty`    | the rescale where the parent held none                 | `water_increment`, kg m^-3     | `ρq_tot` before               |
| `repair`   | the partition repair, per part                         | `water_increment`, kg m^-3     | the partition's positive part |
| `close`    | the closing step of rain and snow                      | `water_increment`, kg m^-3     | `ρq_tot`                      |
| `follow`   | the follow of rain and snow, both legs of each move    | `water_increment`, kg m^-3     | `ρq_tot`                      |
| `inc`      | the follower's flux under increment transport          | `water_tendency`, kg m^-3 s^-1 | `ρq_tot`                      |
| `negative` | the follower's negative water and its crossing by mask | `water_tendency`, kg m^-3 s^-1 | `ρq_tot`                      |

`close` and `follow` exist with `water_tag_precipitation: true`, and `inc` and
`negative` with `water_tag_transport: increment`. `repair` and `close` exist
for region tags alone, every other mechanism for every tag. These are every
correction writer of the default mode, the leak correction excepted. The leak
correction is not metered yet, as the copies are not, so the producer refuses
`water_tag_leak_correction: true`.

Each call of a writer is one application of each channel it changes. The meter
records the change before the writer applies it, so `+x` and then `-x` in one
step are two applications, and a move between a tag's parts is two legs. The
counted stepper hooks, `lim!`, `constrain_state!` and the post-solve
correction, give each application its role. A map of the accepted state at the
end of the step has weight 1 (`final_map`). A map after a Newton solve has
`b_imp/γ` (`post_newton`). The follower's tendency has `dt b_imp` in seconds
(`implicit`). A change to a stage value that the accepted state does not take
additively is a stage observation. It is counted, not recorded. A writer call
outside the counted hooks has no role in the step. The step's finalization then
stops the run with an error that gives the count and the last such call. The
stepper never rejects a step, so each step has one trial, accepted.

The run writes two files into its output directory:

  - `water_tag_application_receipt.jsonl`. The first line is the header: the
    schema, the integrator pin (`unconstrained_imex_ark`, the
    `ClimaTimeSteppers` version, `b_exp`, `b_imp` and the implicit diagonal),
    and the model identity. The roster is the list of channel ids under
    `water_tag_application_roster`. Each channel's description is under
    `water_tag_application_channels`, and the mechanisms the producer does not
    meter, with their reasons, are under `water_tag_application_unsupported`.
    The identity is `model_commit`, `model_dirty` and `model_diff_sha256`, the
    sha256 of `git diff HEAD --binary` of the source tree, as the evidence
    manifest computes it. It is the hash of the empty string for a clean tree,
    and `unknown` off a git checkout or without `sha256sum`. A converter must
    not overwrite it. Each further line is one accepted step with its
    applications, their roles, weights and stages. A channel with no applied application in a step gets
    an explicit zero. An application that is zero in every cell, with no
    counter set, is left out and counted.
  - `water_tag_applications.nc`. Per record and native cell: `record_values`,
    `record_event_scale` and `record_flags`, the counter code
    `fallback + 2 bound + 4 clamp + 8 zero_normalization`. Per channel and
    accepted step edge: `ledger`, the channel's cumulative ledger, the running
    sum of its applied records times their weights, in Float64. Also the cells'
    `weights` (m for a column, m^3 otherwise) and `geometry`.

Each run segment, a first run or a restart, writes both files afresh. A
segment started in a directory that already holds them replaces both, so the
two files always hold the same steps. With the default
`output_dir_style: ActiveLink` each run has a directory of its own.

The checkpoint carries the ledgers. A restart from a checkpoint without them
starts them at zero with a warning, and the header says so. A checkpoint with
only part of them is refused.

The producer supports the default mode only. It refuses
`water_tag_updraft_copy: true` and `water_tag_leak_correction: true`, runs on
one process on a CPU, and needs an unconstrained IMEX-ARK stepper. It has not
been tried on a GPU, so a GPU device is refused. The energy source
tags are not metered. The cumulative ledger checks the receipt's
bookkeeping. The model's own ledgers `q_tag_led_fix_<name>` and
`q_tag_led_inc_<name>` check its completeness. The output grows with the
records times the cells, so it suits a column.

## Scope

Water tagging supports `microphysics_model: "0M"` and `"1M"`.
`check_water_tagging_supported` errors otherwise. It is refused under
`turbconv: prognostic_edmfx` with more than one updraft and under `amd_les: true`.
It warns when the run has a prescribed flow. `water_process_record` is not refused
under any of them, since its records are not transported.

  - **0-moment.** Every writer of ``\rho q_\mathrm{tot}`` is a local source or
    sink, so the attribution alone is exact and nothing sediments.
  - **1-moment.** Phase changes conserve ``\rho q_\mathrm{tot}`` and are invisible
    to the tags. Sedimentation is the only microphysical writer of
    ``\rho q_\mathrm{tot}``, because `microphysics_tendency!` moves mass between
    species only. So the `microphysics` label does nothing there, and the
    `precipitation` label of the energy tags has no water counterpart. See
    [Sedimentation with 1-moment microphysics](@ref). With
    `water_tag_precipitation: true`, rain and snow carry their own parts, and the
    phase changes move water between a tag's parts.
  - **Dry.** There is no ``\rho q_\mathrm{tot}`` in the state to partition.
  - **2-moment and P3** are unsupported. They carry prognostic number
    concentrations, whose origin is a separate question from the mass origin these
    tags partition. Tagging only the mass flux would leave the number field
    untagged and the two inconsistent.

## Caveats

  - Under `PrognosticEDMFX` the default mode's updraft composition is a modeled
    steady entraining plume, not a prognostic field. The copies audit it.
  - Tag names are restricted. See [Tag entries](@ref) in the tracer configuration
    page.
  - With a `PrescribedFlow` setup (such as `ShipwayHill2012`), the surface water
    inflow imposed as a vertical-transport boundary condition adds to
    ``\rho q_\mathrm{tot}`` outside every attributed process, and has no tagged
    counterpart. That water enters the domain untagged, and `q_tag_res` drifts
    monotonically. The model accepts the combination with a warning at build time.
    `prescribe_flow!` rescales the tags after its clip, so the tags stay
    consistent with each other. They are collectively short of
    ``\rho q_\mathrm{tot}`` by the injected amount.
  - The `ρe_tag_*` family's `microphysics` label fires only when microphysics is
    stepped explicitly. The water tags attribute the implicit path too, because
    `implicit_microphysics` defaults to `true` and the 0-moment water sink lives
    there. So do the energy source tags and the process records.
  - A restart must use the same tag configuration, because the masks are rebuilt
    from it. A checkpoint records each tag's region and sources, and the restart
    guard (`check_water_tag_checkpoint`) refuses a restart that changes one, or
    that adds or drops the copies, before the run starts. The fix ledgers
    `q_tag_fix` and `q_tag_upfix`, and the grosses, counts and attempted totals,
    live in the cache, and the checkpoint carries them beside the state. A
    checkpoint with none of them starts them at zero, with a warning, and the
    audit then covers this segment only. A checkpoint with some but not all of
    them is refused. So is a checkpoint without the ledgers `q_tag_led_*` or
    `q_tag_exp_negative`. A checkpoint under increment transport whose ledger
    lacks `q_tag_inc_negative` is refused, because its tags partition `ρq_tot`
    and not `max(ρq_tot, 0)`. A checkpoint without the version attribute
    restarts with a warning that the tags' regions and sources cannot be
    checked.

## Interpretation limit

Exact closure shows internally consistent accounting. It does not turn the tags
into counterfactual sensitivities. The loss rule in proportion to what each tag
holds, the well-mixed-phases assumption behind `qv_tag`, the sedimentation flux,
the leak correction and the limiter policy are modeling choices. Conclusions are
conditional on them.

See `config/model_configs/baroclinic_wave_tagged_water.yml` for a complete
example, and `test/tagged_water_integration.jl` for the closure assertions. The
docstrings are on the page [Tagged Water API](tagged_water_api.md).
