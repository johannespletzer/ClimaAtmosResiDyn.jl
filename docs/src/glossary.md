# Glossary

Short definitions of the symbols and terms that recur across the ClimaAtmos
source code and documentation. Each entry links to the page that covers it in
depth.

## State and cache

ClimaAtmos integrates a prognostic state vector forward in time. A few
single-letter names appear throughout the code:

| Symbol | Meaning                                                                                                                                                                                                                              |
|:------ |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Y`    | The **prognostic state vector**: the quantities integrated in time. `Y.c` holds cell-center variables (e.g. density `ρ`, total energy `ρe_tot`, horizontal velocity `uₕ`); `Y.f` holds face variables (e.g. vertical velocity `u₃`). |
| `Yₜ`   | The **tendency vector**, i.e. the time derivative `∂Y/∂t`. `Yₜ.sfc` holds surface tendencies.                                                                                                                                        |
| `p`    | The **cache**: parameters, precomputed fields (radiation fluxes, surface conditions, precipitation fluxes), model configuration, and slab/surface model properties.                                                                  |
| `t`    | The **current simulation time**, in seconds from `start_date`.                                                                                                                                                                       |

These are accessed through the integrator after a run, e.g.
`Y = simulation.integrator.u` (see [Your First Simulation](@ref)).

## Common terms

  - **Setup**: the initial conditions, boundary conditions, and optional forcing
    that define a simulation *case* (BOMEX, DYCOMS, RICO, Held–Suarez, …). See [Setups](@ref).
  - **Preset**: a NamedTuple of `AtmosModel` keyword arguments (such as
    `microphysics_model`, `turbconv_model`, `insolation`) that describes the
    physics of a common configuration, passed to the `defaults` slot of
    `AtmosModel`. See [`Presets`](api.md#Presets). A preset chooses the
    parameterizations, while a setup chooses the case, so the two are combined
    to specify a simulation.
  - **AtmosConfig**: the structure that parses YAML configuration files and
    builds the simulation setup.
  - **Integrator**: the time-stepping object that advances `Y`; its `.u` field is
    the current state vector.
  - **IMEX time stepping**: the implicit–explicit scheme used by default; the
    implicit part is handled by the [Implicit Solver](@ref).
  - **ITime**: the integer time type used for reproducible, exactly representable
    simulation times. See [Integer Time (ITime)](@ref).
  - **PROPHET**: the Prognostic Representation Of Physics for Eddy Transport,
    the turbulence/convection scheme of ClimaAtmos: an extended, prognostic
    eddy-diffusivity mass-flux (EDMF) scheme, still called EDMFX in the code.
    See the [PROPHET equations](@ref "PROPHET: Overview and Equations").
  - **Diagnostics**: derived output variables, as opposed to the prognostic state
    `Y`. See [Computing and saving diagnostics](@ref) and the catalog of
    [available diagnostic variables](@ref "Available diagnostic variables").

Three families of bookkeeping words: budget is the parent's, ledger is a tag's,
record is a process's.

  - **Parent budget**: the internal accounting that checks whether air
    mass, total water and total energy changed by exactly what the accepted
    time step applied. Its terms, from *reservoir* to *reported*, are explained
    in plain language on the
    [parent-budget vocabulary](parent_budget/vocabulary.md) page. In the code
    its per-step store is `BudgetJournal`, and the tendency code reaches it
    through `open_parent_budget_event!` and `close_parent_budget_event!`.
  - **Tag ledger**: a running total that a tag correction keeps of what it
    moved. It comes in three kinds: a *fix* ledger (`q_tag_fix_*`,
    `e_src_fix_*`), an *increment* ledger (`q_tag_inc_*`, `e_src_inc_*`) and a
    *mechanism* ledger (`q_tag_led_<mechanism>`, `e_src_led_<mechanism>`). See
    [Tagged Water Tracers](tagged_water.md) and
    [Energy Source Tags](energy_source_tags.md).
  - **Process record**: one process's signed history of the parent tendency,
    kept as `prc_e_<process>` or `prc_q_<process>` and written out as
    `e_prc_*` and `q_prc_*`. One field per process, never transported. See
    [Process-Change Records](process_record.md).

Tags split a variable, such as total water or moist total energy, into named
tags. The keys are in [Configuring Tracers](tracer_configuration.md). The terms
below are those of the tag families.

  - **Applied-update event**: the part of the tendency code that one process
    adds to the tendencies. The difference of the tendency before and after it
    is the process's tendency. The explicit path marks it with
    `open_applied_update!` and `close_applied_update!`. The implicit path uses
    separate parent-budget and attribution calls. Each tag family and the
    process records take only the processes they support. Older text and some
    identifiers call the event a bracket.
  - **Audit**: the audit table (`audit: true`, `<family>_tag_audit.csv`), the
    parent budget's `audit` mode, and the rain and snow tags' `aud` fields.
  - **Check level**: `tolerance`, `throughput_tolerance`, `void_above` or
    `abort_above`. The first two warn on every row above them. `void_above` warns once and
    sets the void flag. `abort_above` ends the run. It is not a model level.
  - **Comparison mode**: a setting that moves the tags by the model's own
    machinery, so that their result can be compared with the default:
    `energy_source_tag_transport: enthalpy`, `energy_source_tag_updraft_copy`
    and `water_tag_updraft_copy`.
  - **Compartment**: under `water_tag_precipitation: true`, one of the parent's
    three water pools: the water that is neither rain nor snow, rain, and snow.
  - **Exchange**: the term that gives each tag the updraft's composition instead
    of the grid mean's. It sums to zero over the region tags.
  - **Fix ledger**: what the tag corrections moved into or out of each tag,
    cumulative: `q_tag_fix_<name>`, `q_tag_upfix_<name>` and `e_src_fix_<name>`.
    For water it holds the limiters' and constraints' change and the partition
    repair, and `q_tag_upfix` holds the copies' repair. For energy source tags
    it holds what `energy_source_tag_repair` changed: the region tags' partition
    repair and the source tags' clip at zero. The model's fields are not
    changed.
  - **Gross**: absolute values summed, or positive and negative parts kept
    apart, so that opposite changes do not cancel. The `_gross` outputs sum over
    time. `gross_residual` sums over the domain.
  - **Headroom**: `headroom_min`, the smallest `e_tot + c` in the domain, and
    `headroom_min_z`, its height. It is the margin before the split total
    reaches zero.
  - **Increment transport**: with `water_tag_transport: increment` or
    `energy_source_tag_transport: enthalpy_increment`, the tags take the
    parent's change from each implicit solve. A correction after each solve moves
    the difference. The `inc` ledgers hold what it left out and what it moved, and for water
    what the parent's negative water changed (`q_tag_inc_negative`).
  - **Leak**: the rate at which one transport path moves the region tags' sum
    away from the parent (`q_tag_leak_<path>`). The model's fields are not
    changed.
  - **Net-flow rule**: on the rain and snow tags, a compartment that loses gives
    its own composition, and one that gains takes the losers' compositions
    weighted by their losses. It is the fallback where the gross flows are
    absent, and the comparison behind the `aud` fields.
  - **Offset**: `energy_source_tag_offset`, an energy per kilogram that the
    energy source tags add to `ρe_tot` before they split it. The model never
    sees it.
  - **Overlay**: the source tags lie over the region tags. They are not summed
    in the residual and are not part of the partition.
  - **Parent**: the model's own prognostic total that a family of tags splits.
    It is `ρq_tot` for water tags, `ρe_tot` for `energy_tracers`, and
    `ρe_tot + c·ρ` for energy source tags. Under `water_tag_precipitation: true`
    each compartment has its own parent. It is not related to the parent
    budget.
  - **Region tag**: a tag with a `region` and no `source`, a transported part of
    the parent. The region tags together are the partition. They partition the
    parent only where their masks sum to 1. A tag with a region and a source
    is a source tag, and its region only masks its production.
  - **Residual**: the parent, for water `max(ρq_tot, 0)`, minus the sum of the
    region tags. Tag closure is the statement that it is small.
  - **Share**: a tag's amount over the parent's amount in the cell, limited to
    the range 0 to 1 and zero where the parent is not positive. Losses,
    sedimentation and the sub-grid flux are handed to the tags in proportion to
    it. So is the limiters' change of the parent, for water.
  - **Signed process tag**: a tag with a `source` in `energy_tracers`. A
    transported field that holds the signed running total of what that process
    added, so it goes negative under net cooling. It is not a process-change
    record, which is never transported.
  - **Source tag**: a tag with a `source` in `water_tracers` or
    `energy_source_tags`. The amount of the parent present now that came from
    that process.
  - **Source throughput**: the gross energy that the sources put into the region
    tags, summed over steps and the domain since the start of the run, in J. It
    is the column `source_throughput` and the scale of `throughput_tolerance`.
  - **Tag closure**: whether a family's tags still add up to their parent. The
    residual (`q_tag_res`, `e_tag_res`, `e_src_res`) and the closure check
    measure it. It is not a turbulence closure.
  - **Untagged, overclaimed, orphaned**: audit columns. They are the parent
    that the tags do not account for, the tags' amount that the parent does not
    have, and the mass in cells where every region tag is empty.
  - **Void**: `closure_void` is 1 from the first check row whose
    `gross_relative` passes `void_above`. It stays 1, also after a restart, and
    the run continues. 0 does not mean that the parent is valid.
    `negative_water_void` is a second flag of the same kind.
  - **Not used**: *heat tagging* names a method that tags potential
    temperature, and a *source fingerprint* is an analysis product that the
    model does not write out.

For the mapping between the symbols used in the equations pages and the
names used in the code (the `ᶜ`/`ᶠ` prefixes, subdomain superscripts, and
prognostic-variable names), see [Notation and Symbols](notation.md).
