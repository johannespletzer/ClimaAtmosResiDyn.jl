# Energy Source Tags

Energy source tags split moist energy by **where the energy present now came
from**. The key `energy_source_tags` switches them on, and
`energy_source_tag_offset` is required with it. Each tag adds one prognostic
field `Y.c.ρe_src_<name>`, which the tracer machinery transports (see
[Tracers](passive_tracers.md)). The tags are Experimental and off by default.

With them on, every model field that exists without them stays bit for bit as in
the same run with them off, under the default solver settings. Only the tags' own
fields and output are added. A Newton solve that stops on a residual norm taken
over the whole state is not covered, because that norm sees the tags. See the
[parity contract](https://github.com/johannespletzer/ClimaAtmosResiDyn.jl/blob/main/docs/clima_atmos_specific.md#fork-parity-with-upstream)
for its limits. The results are attributions defined by the configured rules and
not a unique physical history. They depend on `energy_source_tag_offset`.

Start with [Energy Source Tags: a user guide](energy_source_tags_guide.md) to run
the tags and read their output. This page is the reference behind it. The tags are
the energy counterpart of the [Tagged Water Tracers](tagged_water.md). They differ
from the [Tagged Energy Tracers](tagged_tracers.md) and the
[process records](process_record.md):

| Family                  | Field             | Holds                                                 | `source:` means                            |
|:----------------------- |:----------------- |:----------------------------------------------------- |:------------------------------------------ |
| `energy_source_tags`    | `ρe_src_<name>`   | an amount of energy present now, traced to its origin | the process whose production the tag takes |
| `energy_tracers`        | `ρe_tag_<name>`   | a signed history of what one process did              | the process whose tendency the tag adds up |
| `energy_process_record` | `prc_e_<process>` | what one process did here, never transported          | the process that is recorded               |

## Enabling tags

```yaml
energy_source_tag_offset: 110495.0
energy_source_tags:
  - name: tropics
    region: tropics
  - name: extratropics
    region: extratropics
```

Each entry needs a unique `name` and a `region`, a `source`, or both. The entry
schema and the region types are those of the
[energy tags](tagged_tracers.md#Region-tags), and
[Configuring Tracers](tracer_configuration.md) has the named regions. A tag with a
region and no `source` is a region tag, and a tag with a `source` is a source tag.

`energy_source_tag_offset` is the energy per kilogram of air, in J kg⁻¹, that the tags add
before they split. It is required. The shipped `baroclinic_wave_energy_source_tags.yml` uses
110495.0, and `0` keeps the tags on ``\rho e_\mathrm{tot}`` itself. See
[The energy reference and the offset](@ref).

!!! note "One partition at a time"

    `e_src_res` sums **all** region tags, so configure exactly one partition of
    unity per run, a region and its complement. A warning is emitted at
    initialization when the masks miss 1 by more than 1%.

The other keys of the family are at their default unless set. Each is
Experimental, and the status column says what kind:

| key                                                       | switches on                                       | default  | status                     |
|:--------------------------------------------------------- |:------------------------------------------------- |:-------- |:-------------------------- |
| `energy_source_tag_repair`                                | puts negative tags back (`false` switches it off) | `true`   | Experimental               |
| `energy_source_tag_transport`                             | `enthalpy` or `enthalpy_increment`                | `tracer` | comparison mode, prototype |
| `energy_source_tag_updraft_copy`                          | a copy of each tag in the updraft under EDMF      | `false`  | comparison mode            |
| `energy_source_tag_ledger_per_tag`                        | each tag's own state ledgers                      | `false`  | Experimental               |
| `energy_source_tag_increment_allow_explicit_microphysics` | `enthalpy_increment` with refused microphysics    | `false`  | development override       |

## Attribution

A process's tendency ``\Delta`` of the total the tags split is divided into
production ``\Delta^{+}`` and loss ``\Delta^{-}``. The two are attributed by
**different rules**, as for the water tags:

```math
\Delta\!\left(\rho e_{\mathrm{src},k}\right)
= M_k \, \Delta^{+} - \varphi_k \, \Delta^{-},
\qquad
\varphi_k = \frac{\rho e_{\mathrm{src},k}}{E}.
```

``E`` is the total the tags split, ``\rho e_\mathrm{tot}`` plus the offset term.
The share ``\varphi_k`` is the tag's amount over ``E``, limited to the range 0 to
1 and zero where ``E`` is not positive.

  - **Production is mask-weighted.** ``M_k`` is the tag's region mask. It is 1 for
    a source tag without a region, and 0 if the tag does not list the process. New
    energy carries the label of where it entered.
  - **Loss comes out of every tag in proportion to what it holds.** Every tag
    loses, whatever processes it lists. This makes ``\rho e_{\mathrm{src},k}`` an
    amount of energy and not a running total.

Over the region tags ``\sum_k M_k = 1`` and ``\sum_k \varphi_k = 1``, so their
changes add up to ``\Delta`` exactly, for each process.

The explicit processes use this rule, and so does the microphysics sink on the
implicit path, which is where rain leaves a 0-moment run with its energy. A pure sink
shrinks every tag by the same fraction. A tendency is not always a loss. Removing water
raises the total wherever that water carries less energy per kilogram than `-c`, as cold
condensate can. Then the tendency is production, and it goes by mask to the region tags
and to any tag that lists `microphysics` or `all`.

### Sedimentation

`precipitation`, the sedimentation of precipitating species, is not attributed with
this rule, although the `ρe_tag_*` family attributes it. What arrives in a cell would
count as new energy. So the tags follow sedimentation as transport. Each face's energy
flux, with `c` times the mass it carries, is shared out by the shares of the cell that
loses the energy. That is the cell above where the water falls with positive energy, and
the cell below where it carries negative energy against the reference plus offset, as ice
can. At the surface the lowest cell's shares are kept. The region tags' shares add up to
one, so their fluxes add up to the parent's and sedimentation adds nothing to `e_src_res`.

It needs a positive offset, because a share is zero wherever the total is not positive and there
the tags would not move. The model warns about that at initialization. The parent's
implicit flux has a cross block from `ρe_tot` to each falling species. With the manual
Jacobian's split solver, the default, each tag's row has one to each sedimenting mass as
well, the face's share times the block of `E`. The split solver solves the tags after the
model's fields, so the model's increments do not change. Without it
(`use_auto_jacobian: true`) there are no cross blocks, and the tags lag the parent's
implicit flux within a step. Under `prognostic_edmfx` the parent's flux has two more
corrections, one for the updraft and one for the environment. The tags take the whole face
flux and share it once, by its direction.

### The sub-grid mass flux under EDMF

Without updraft copies the parent's sub-grid mass flux reaches no tag through the updrafts.
Instead each tag takes its share of the parent's own sub-grid flux of `E`, face by face,
from the cell the flux leaves. That flux is the one of `ρe_tot` summed over the subdomains,
plus `c` times the one of `ρ`, each built with `edmfx_sgsflux_upwinding`. So the region
tags' fluxes add up to the parent's. The flux runs in the implicit tendency and has no
Jacobian block, so within a step the tags lag the parent slightly, and that gap lands in
`e_src_res`.

The flux does not mix the tags' composition the way convection mixes the air. So each tag
also takes an exchange of composition,

```
Xᵢ = Σₖ ρᵏ aᵏ (u³ᵏ - u³) (φᵏᵢ - φ̄ᵢ) Aᵏ,
```

over the updraft and the environment `k`. Here `φᵏᵢ` is the tag's share of the subdomain's
energy, `φ̄ᵢ` its share in the grid mean, and `Aᵏ = e_totᵏ + c` the subdomain's energy per
unit mass. No subdomain may carry more of a tag's energy than the cell holds, and no share
may go negative. The region tags share one blending factor, so the exchange sums to zero over
them at every face and closure is untouched. The updraft's shares come from a steady
entraining plume, marched up each column with the model's own entrainment rate. It is exact
when the updraft adjusts faster than the shares change. The exchange needs region tags
without sources that partition the domain, and the model refuses it at initialization without
them, under every transport, unless the tags have updraft copies. See
[`ClimaAtmos.sgs_exchange_of_energy_source_tags!`](@ref).

### Updraft copies, a comparison mode

`energy_source_tag_updraft_copy: true` gives each tag a copy in the updraft, `e_src_<name>` in
`Y.c.sgsʲs`. It is a passive updraft tracer that starts as its tag's specific value, and the
model moves it as any other updraft tracer. Neither the share-weighted flux nor the exchange
runs. Under `enthalpy_increment` the correction after each solve takes the difference between
the copies' fluxes and the parent's. The model refuses the copies under `enthalpy`, where
nothing would. A restart refuses a change of the switch, since the copies are part of the state.

The model gives the updraft's `mseʲ` four changes that it gives no updraft tracer. The copies
get the same change as the updraft in each (`energy_source_copy_mirrors.jl`): the surface
enthalpy flux into the lowest cell, the relaxation there toward the surface's buoyant air,
radiation under RRTMGP, and the updraft's rain-out under 0-moment microphysics. A tag that
receives the process's label gains its mask times the positive part of the change, and every
copy loses its share of the negative part. The buoyancy term and the pressure work are not
copied, because no tag is labelled with either. What the copies do not cover shows in
`e_src_copy_res`, the updraft's energy `mseʲ + Kʲ - p/ρʲ + c` minus the region tags' copies,
times `ρaʲ/ρ`. The copies' state names are nested in the updraft, so they join the nested
solver, and the model takes longer to build.

## Negative tags, and the repair

The loss rule bounds the *rate* at which a tag is depleted, not the amount removed. The
timestepper integrates the tendency over a finite step, so the energy taken from a tag across
one step is about ``\Delta t \, \varphi_k \, \Delta^{-}``. Nothing ties that to what the tag
holds. Where ``E \le 0`` the share is undefined and no loss is applied. And the tags are exempt
from both tracer limiters and ride unlimited explicit transport. So a tag can go negative, and a
negative value **invalidates the amount-of-energy reading of that tag** for as long as it lasts.

`energy_source_tag_repair`, on by default, puts negative tags back after each state update,
wherever the total the tags split is positive. The region tags keep their sum. A negative one is
set to zero, and the positive ones give up the deficit in proportion to what each holds, as the
water tags' partition repair does. A source tag is clipped at zero, because it has no sum to
keep. Where the total is not positive the tags are left alone, because the share is undefined
there. The repair does not force the region tags onto the total. That would drive `e_src_res` to
zero by construction and hide the transport mismatch it exists to show.

Every change is logged in the fix ledger `e_src_fix_<name>`. The ledger is exact at the default
`update_constrain_state_every: step`. At `stage` or `dss` the repair also runs inside the step,
where the stepper rescales or discards what it changes, so the ledger no longer equals what
reached the state. `energy_source_tag_repair: false` leaves the tags as the rule and their
transport make them, negative values included. That is how to measure what the repair changes.
`e_src_res` does not show negative values, because it sums the region tags only and opposite
errors cancel. With the repair off, inspect each `e_src_<name>`. For the total, use the
initialization warning and the `nonpositive_fraction` column of the closure check.

## Tag closure check

The check is on by default whenever the tags include a region tag. Without a block it
runs daily and adds the residual since spin-up, one hour in, to every row. It warns
above the default tolerance of the transport in use, and whenever the total is not
positive somewhere. A block sets its keys, and `false` switches the check off:

```yaml
energy_source_closure_check:
  period: "1days"
  tolerance: 0.1
  spin_up: "1hours"
```

The check reduces `e_src_res` to a pair of numbers and appends them to
`energy_source_tag_closure.csv`. The keys are those of `energy_closure_check` (see
[Configuring Tracers](tracer_configuration.md)), with these differences:

  - `tolerance` defaults to the check level of the transport in use: 1.0 under
    `tracer`, 0.1 under `enthalpy` and 0.01 under `enthalpy_increment`. They guard
    against a runaway. Set your own for a level that means "this configuration
    changed", and `~` to warn about nothing. See `ENERGY_SOURCE_CLOSURE_TOLERANCES`.
  - `spin_up` is `"1hours"` by default and `~` for none. Each row then also carries
    `residual_at_spin_up`, `residual_since_spin_up` and `relative_since_spin_up`, `NaN`
    before the reference is taken. The residual at spin-up includes the initial
    adjustment and the solver's one Newton iteration, and the rows since spin-up leave
    it out. After a restart the reference is taken again.
  - `void_above` and `abort_above` default to `~`. The residual is normalized by a quantity
    whose zero is a convention, so a check level tuned under one `energy_source_tag_offset`
    means something else under another. Calibrate the levels against a first run.
  - `throughput_tolerance` is a second check level, compared with
    `gross_over_throughput`, whose scale is set by the sources and not by the
    offset. It defaults to `~`. It needs `energy_source_tag_ledger_per_tag: true`
    and a verified partition, and the model refuses it at setup without them.

### The residual report

Every row also carries the offset's headroom. `headroom_min` is the smallest `e_tot + c` in the
domain, in J kg⁻¹, and `headroom_min_z` is its height. `nonpositive_fraction` moves only once a
cell has crossed zero, and the headroom shows the margin before that.

With `energy_source_tag_ledger_per_tag: true` the row also carries `source_partition_valid`,
`source_throughput` and `gross_over_throughput`. The source throughput is the gross energy the
sources have put into the region tags since the start of the run. It counts each unit once only
where the region tags' masks sum to 1, a verified partition. The model checks that once, at setup,
to 100 rounding units of the float type, the level `enthalpy_increment` requires anyway. Under
`tracer` and `enthalpy`, masks that miss 1 by more than 1% only draw a warning at setup, so read
`source_partition_valid`, which is 1 on a verified partition and 0 elsewhere.

With `audit: true` the audit table adds where the residual `R` sits, what the source tags do
against the region tags they overlay, and a forecast. An overlay is a source tag, which is not part
of the partition. The loss rule takes from every tag by its share, so each loss flushes part of the
residual, `-(R/E) Δ⁻` in a cell. On a verified partition the residual's source ledger
`e_src_led_src_res` is that flush, and its per-step gross is `flush_gross`. The settling level, the
level at which flush and production would balance, is an order of magnitude and not a prediction.

| column                                                                               | table          | written with                   | `NaN` where                                                              |
|:------------------------------------------------------------------------------------ |:-------------- |:------------------------------ |:------------------------------------------------------------------------ |
| `source_throughput`                                                                  | closure, audit | ledgers per tag                | no verified partition                                                    |
| `gross_over_throughput`                                                              | closure        | ledgers per tag                | no verified partition, zero source throughput                            |
| `ledger_parent_scale`                                                                | audit          | `audit: true`, ledgers per tag | never, and not the source throughput where `source_partition_valid` is 0 |
| `led_<kind>_<name>_parent_fraction`                                                  | audit          | `audit: true`, ledgers per tag | a zero parent scale                                                      |
| `residual_max_z`, `residual_peak_level`, `residual_peak_fraction`, `residual_peak_z` | audit          | `audit: true`                  | a residual zero everywhere                                               |
| `overlay_negative_mass_fraction`, `overlay_excess`, `overlay_excess_mass_fraction`   | audit          | `audit: true`                  | no source tag                                                            |
| `flush_gross`                                                                        | audit          | `audit: true`, ledgers per tag | no verified partition                                                    |
| `flush_rate`, `production_rate`                                                      | audit          | `audit: true`, ledgers per tag | first row, no verified partition, an empty interval                      |
| `settling_level`, `settling_ratio`, `forecast_defined`                               | audit          | `audit: true`, ledgers per tag | no balance, where `forecast_defined` is 0                                |

The columns follow the spin-up columns in the closure table, and `closure_void` stays last. None
of them is a verdict.

### Checking per process

`e_src_res` checks the region tags against their total. Two more checks test the attribution
process by process. The model does not compute them. They are read from the output of a run that
has the region tags, one tag per region with `source: all` (say `new_tropics`), one tag per process
that runs (say `sfc` on `surface_flux`), and a [process record](process_record.md) for each of
those processes. The `new_*` tags list `precipitation`, which no source tag can follow, so the run
warns about each at startup. Form A sets the new energy split by region against the new energy
split by process, at each point. Form B sets the change in a column's `ρe_tot` against the column
integrals of the records. Form A does not see pressure work, and form B does not see transport.
Only `e_src_res` sees transport. On a sphere, read form A as a domain integral, because the tags'
numerics cancel in it and a missing process does not.

## The energy reference and the offset

Water has a physical zero. Moist total energy has none, because its value depends on the chosen
reference points for thermodynamic and gravitational energy. A shift
``\rho e_\mathrm{tot} \to \rho e_\mathrm{tot} + c\rho`` changes every tag's share and can make
the total non-positive somewhere, where the share is undefined. The model does not keep
``\rho q_\mathrm{tot}`` non-negative by default (`tracer_nonnegativity_method: ~`). The water tags
partition ``\max(\rho q_\mathrm{tot}, 0)`` instead, and `q_tag_negative` holds the parent's
negative water. For energy the reference is the cause. No split into never-negative parts can give
the same shares after an arbitrary shift, so the results are **conditional on the energy
reference**, which has to be fixed and reported. Where the share is undefined the loss half of the
rule does not run, while production stays mask-weighted. The model reports the non-positive
fraction of the domain at initialization.

`energy_source_tag_offset` gives the tags a total the model never uses. With an offset ``c``, in
J kg⁻¹, the tags split

```math
E = \rho e_\mathrm{tot} + c\,\rho
```

instead of ``\rho e_\mathrm{tot}``. The region tags start as their masked shares of ``E``, and each
process's tendency becomes ``\Delta E = \Delta(\rho e_\mathrm{tot}) + c\,\Delta\rho``. So a
process that changes the mass, such as surface evaporation, changes the total by ``c`` times that
change. The closure check, its audit and `e_src_res` all read ``E``.

Only the tags see ``E``, so the simulated atmosphere is the one without the offset. Moving the
thermodynamic reference gives the tags the same total in exact arithmetic, but it reaches the
model's own numerics, and the atmosphere drifts from the first step. An offset large enough to make
``E`` positive everywhere lets the loss rule run everywhere. It does not make the reading less
conventional. The shares depend on ``c``, and a larger offset makes the tags less discriminating,
because the part of a source tag that tells it apart from a plain mask-weighted tag scales as
``1/(e_\mathrm{tot} + c)``. Nor does it keep the tags non-negative.

## Moving the tags as enthalpy, a comparison mode

By default the tags move as passive tracers, while the parent moves enthalpy: `ρe_tot` is carried
with `h_tot = e_tot + p/ρ`. The difference is pressure work, and it is most of what `e_src_res`
grows by under `tracer`. `energy_source_tag_transport` has three values:

| value                | what it does                                                        | requires                                                                                                                | status          |
|:-------------------- |:------------------------------------------------------------------- |:----------------------------------------------------------------------------------------------------------------------- |:--------------- |
| `tracer` (default)   | moves each tag as a passive tracer                                  | nothing                                                                                                                 | default         |
| `enthalpy`           | takes each tag's share of the parent's own explicit flux of `E`     | a positive offset                                                                                                       | comparison mode |
| `enthalpy_increment` | adds the parent's implicit increment of `E` after each Newton solve | a positive offset, a region partition, an algorithm that solves every stage, `energy_q_tot_upwinding` other than `none` | prototype       |

A comparison mode is a setting that moves the tags by the model's own machinery, so their result
can be compared with the default. In `enthalpy`, each tag takes its share of the parent's own flux
of `E = ρe_tot + c·ρ` in three terms. In vertical advection that is `ρ u³` times the face value of
`h_tot + c` under `energy_q_tot_upwinding`, times the tag's share in the cell upwind of the face.
In horizontal advection it is `split_divₕ(ρu, sₖ (h_tot + c))`. In hyperdiffusion it is the
parent's flux of `E`, whose water part carries `h_eff + Φ + c`, times the share. The shares are the
ones sedimentation uses. So the region tags' tendencies add up to the parent's, and transport adds
nothing to `e_src_res` except for one gap in timing. The tags move explicitly, with the fluxes of
the solved stage state, while the parent moves `ρe_tot` and `ρ` vertically in the implicit step.
With one Newton iteration (`max_newton_iters_ode: 1`) the parent's contribution is the increment
linearised about the stage's first guess. The difference lands in `e_src_res` and shrinks with more
Newton iterations. Everything else the tags see stays as under `tracer`. Under `prognostic_edmfx`
the tags take their shares of the sub-grid mass flux in both modes (see
[Attribution](#Attribution)).

A share is zero wherever `E` is not positive, so the model refuses `enthalpy` without a
positive offset. A region tag's share is also zero where every region tag is negative, and
there the tags stop moving while the parent's flux goes on. The repair keeps the region tags
non-negative wherever `E` is positive, so this happens only with `energy_source_tag_repair: false`. The upwind shares are first order, so a region's edge smears more than under van
Leer. That is the price of exact closure. Compare a pair of runs with the setting on and off
to separate what transport adds to `e_src_res` from what the attribution and the processes
the tags do not see add.

### Following the parent's implicit increment, a prototype

`enthalpy_increment` is `enthalpy` with its implicit part rebuilt. A tag that follows an implicit
term by its tendency lags the parent's Newton solve, and for a stiff term, such as the EDMF eddy
diffusion, the gap grows step by step. In this mode the tags take the parent's own increment
instead. At the start of each implicit stage the model keeps `ρe_tot`, `ρ` and the sum over the
region tags. After the Newton solve it forms each cell's mismatch between the parent's increment
of `E` and the region tags'. The part of the mismatch that changes a column's total cannot move
within the column. It stays where it arises, in proportion to the mismatch's absolute value, and in
`e_src_res`. The rest integrates up the column into a face flux that is zero at both boundaries,
and each tag takes that flux times its share in the cell it leaves. The tags then take no explicit
share of the vertical advection.

The mode has four requirements, and the model refuses a configuration that misses one:

  - an `energy_source_tag_offset`.
  - region tags without sources whose masks partition the domain. Without a partition the source
    tags would take the whole implicit transport twice.
  - an algorithm that solves every stage whose implicit tendency it uses, such as the default
    ARS343 or ARS222. SSP333 and the IMKG algorithms have stages without a solve.
  - an `energy_q_tot_upwinding` other than `none`, such as the default `vanleer_limiter`. The
    correction runs in the parent's own post-solve hook, and a new hook would change the model's
    fields.

With microphysics that sediments (`microphysics_model` 1M, 2M or 2MP3) stepped explicitly
(`implicit_microphysics: false`), the mode needs the tags' sedimentation cross blocks. Without them
one Newton iteration leaves the tags short of part of the parent's sedimentation update, and that
part lands in `e_src_res`. So 1M stepped explicitly runs with the manual Jacobian, the default, and
with the dense one (`use_dense_jacobian: true`). The model refuses it under
`use_auto_jacobian: true`, whose Jacobian lacks the blocks. It also refuses 2M and 2MP3 stepped
explicitly, because the closure with their blocks is not established.
`energy_source_tag_increment_allow_explicit_microphysics: true` lets a refused configuration run,
with a warning. It is an override for development runs, and it concerns only the tags' keys.

```yaml
# Runs as it is: 1M stepped explicitly, with the manual Jacobian.
energy_source_tag_offset: 110495.0
energy_source_tag_transport: enthalpy_increment
microphysics_model: 1M
implicit_microphysics: false
```

The correction keeps an increment ledger, as two prognostic fields that the stepper integrates with
the tags. `e_src_inc_left` is what it has left out of the tags. In each column it sums to the part
of the parent's implicit increment that changes the column's total and that the tags' own
tendencies did not take, such as a boundary flux the tags do not follow. That part lands in
`e_src_res`. `e_src_inc_moved` is what it has moved between levels, and it sums to zero in each
column. Both are cumulative since the start of the run and carried through a restart. The audit
table gets their integrals, `increment_left`, `increment_left_net_abs` and
`increment_moved_net_abs`. The last two sum each cell's absolute ledger, which is net over time in
that cell, so they are not a source throughput. The ledger records what the correction intends. A
face whose upwind cell has no share of the region tags moves no tag, so there a cell's change
differs a little from the ledger. The column totals are right.

## Diagnostics

  - `e_src_<name>`: specific tagged energy ``\rho e_{\mathrm{src}} / \rho`` (J kg⁻¹).
  - `e_src_fix_<name>`: the fix ledger, what the repair has moved into (positive) or out of
    (negative) each tag, per unit mass, cumulative since the start of the run and carried through a
    restart. Zero with the repair off, and exact only at the default
    `update_constrain_state_every: step`.
  - `e_src_led_fix_<name>`, `e_src_led_src_<name>` and, under `enthalpy_increment`,
    `e_src_led_inc_<name>`, with `energy_source_tag_ledger_per_tag: true`: each tag's own state
    ledgers. They hold what the repair changed the tag by, what the sources put into it or took out
    of it, and what the correction after each solve moved. The audit table reports, per ledger,
    `_retained` (what the accepted steps retained), `_attempted` (what its writers attempted) and
    `_events`. The per-step gross of `e_src_led_src_<name>`, summed over the region tags and the
    domain, is the source throughput, the scale for every energy percentage. Each
    of these ledgers also has `_gross` and `_colgross` outputs, with the kind
    before the tag name, for example `e_src_led_srcgross_<name>` and
    `e_src_led_fixcolgross_<name>`.
  - `e_src_led_src_res`: what the sources did to the residual. Only with region masks that sum to 1
    is it the loss rule's flush of the residual.
  - `e_src_res`: the closure residual ``(E - \sum_i \rho e_{\mathrm{src},i}) / \rho``, summed over
    the region tags.
  - `e_src_inc_left` and `e_src_inc_moved`, under `enthalpy_increment` only: the increment ledger
    per unit mass (J kg⁻¹).

`e_src_res` is a **monitored residual** and not a machine-precision identity. Under the default
`tracer` transport the tags ride the generic passive-tracer path, while ``\rho e_\mathrm{tot}`` is
transported as enthalpy. The `enthalpy` comparison mode moves them with the parent's own fluxes
instead, and only their numerics remain (see
[Moving the tags as enthalpy, a comparison mode](@ref)). It is **not a ratio**. It is an energy per
unit mass in J kg⁻¹, and it differs from the `relative` and `gross_relative` columns, which are
normalized by ``\int|E|``. And it does **not** cover the source tags.

### Reading a tag's own ledgers

For each tag's own ledgers the audit table gives three ratios of the retained amount and a flag.
`_inventory_fraction` is over the tag's energy now, `∫ρe_src`, and serves a region tag with a
positive inventory. `_burden_fraction` is over the tag's absolute burden, `∫|ρe_src|`. It serves a
source tag and any tag with negative parts, and equals the inventory ratio without negative parts.
`_parent_fraction` is over the parent scale, `source_throughput`. It is not `∫(ρe_tot + c·ρ)`, which
depends on the offset and would make most source tags look small. `_applicable` is 0 where the tag's
burden is zero or below the small-tag bound, 2e-4 of the parent scale, and 1 otherwise. At 0 no
ratio to the tag is read, and the tag is judged by `_parent_fraction`. A source tag starts at zero,
and with the repair off a tag can be negative throughout, so the inventory ratio can be zero or
`NaN`. A tag whose positive and negative parts nearly cancel has a near-zero inventory, so read
`_burden_fraction`. A ratio whose denominator is not positive is `NaN`, so a check reads
`_applicable` first.

## Caveats

  - Tags are **grid-scale only** by default. Under `turbconv: prognostic_edmfx` they take their
    shares of the sub-grid mass flux and of the sedimentation corrections, and exchange composition
    at the mass flux (see [Attribution](#Attribution)). The model runs `prognostic_edmfx` with one
    updraft only, and the tags refuse more at configuration time. Under both EDMF variants the eddy
    diffusion moves the tags as passive tracers while it moves `ρe_tot` in enthalpy form, and the
    model warns.
  - Tags are excluded from both tracer limiters, through `is_tagged_tracer_name`. The repair keeps
    them non-negative instead, unless it is switched off.
  - Latitude regions require spherical geometry. Altitude regions also work in columns and boxes.
  - A restart must keep what the tags in the checkpoint mean. A checkpoint records
    `energy_source_tag_offset`, each tag's region and sources, `energy_source_tag_transport` and
    `energy_source_tag_repair`. A restart that changes one stops with an error that names it and
    both values. A restart whose tag or process-record fields differ from the configured ones is
    refused as well. A checkpoint without these entries is checked by its fields alone, with a
    warning. One written in another version of the format is refused.
  - The state ledgers (`e_src_led_*`, `e_src_inc_left`, `e_src_inc_moved`) continue through a
    restart as fields of the state. The fix ledger `e_src_fix_<name>`, its gross and count, and each
    state ledger's per-step gross, events and attempted total live in the cache, and the checkpoint
    carries them beside the state. A checkpoint with none of these accumulators starts them at zero,
    with a warning, and their totals then cover this segment only. A checkpoint with some but not
    all of them is refused.

## Interpretation limit

Tag closure proves one thing: that the included terms sum to the parent, as a signed discrete
accounting. It does **not** establish that the amounts are non-negative, that the origin reading
is valid, that results are independent of the energy reference, or that the set of tracked
processes is physically complete. Nor does it make the tags counterfactual sensitivities. Tagging
says what contributed to the simulated energy, not what would change if a process were altered.

## Energy source tag API

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
ClimaAtmos.energy_source_audit
ClimaAtmos.energy_source_residual_report
ClimaAtmos.energy_source_forecast
ClimaAtmos.energy_source_headroom
ClimaAtmos.energy_source_closure_columns
ClimaAtmos.accumulate_energy_source_residual_source!
ClimaAtmos.ENERGY_SOURCE_RESIDUAL_LEDGER
ClimaAtmos.energy_source_throughput
ClimaAtmos.energy_source_partition_tolerance
ClimaAtmos.energy_source_partition_deviation
ClimaAtmos.energy_source_partition_verified
ClimaAtmos.check_energy_source_throughput_partition
ClimaAtmos.check_energy_source_throughput_setup
ClimaAtmos.AbstractEnergySourceTransport
ClimaAtmos.TracerEnergySourceTransport
ClimaAtmos.EnthalpyEnergySourceTransport
ClimaAtmos.EnthalpyIncrementEnergySourceTransport
ClimaAtmos.follows_implicit_increment
ClimaAtmos.snapshot_energy_source_increment!
ClimaAtmos.correct_energy_source_increment!
ClimaAtmos.check_energy_source_increment_supported
ClimaAtmos.EnergySourceIncrementCorrection
ClimaAtmos.energy_source_post_implicit
ClimaAtmos.energy_source_increment_ledger_variables
ClimaAtmos.energy_source_increment_ledger_names
ClimaAtmos.is_energy_source_ledger_name
ClimaAtmos.moves_as_enthalpy
ClimaAtmos.enthalpy_vertical_advection_of_energy_source_tags!
ClimaAtmos.enthalpy_horizontal_advection_of_energy_source_tags!
ClimaAtmos.enthalpy_hyperdiffusion_of_energy_source_tags!
ClimaAtmos.write_energy_source_checkpoint_attributes!
ClimaAtmos.check_energy_source_checkpoint
ClimaAtmos.sgs_mass_flux_of_energy_source_tags!
ClimaAtmos.sgs_exchange_of_energy_source_tags!
ClimaAtmos.energy_source_plume!
ClimaAtmos.energy_plume_surface_fraction!
ClimaAtmos.start_plume_at_surface!
ClimaAtmos.has_energy_source_updraft_copies
ClimaAtmos.energy_source_updraft_copy_variables
ClimaAtmos.mirror_on_energy_source_copies!
ClimaAtmos.energy_source_copy_residual!
ClimaAtmos.keep_energy_source_sediment_correction!
ClimaAtmos.sediment_energy_source_tags_with_corrections!
```
