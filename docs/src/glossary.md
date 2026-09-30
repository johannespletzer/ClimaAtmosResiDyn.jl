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
    moved. It comes in three kinds: a *repair* ledger (`q_tag_fix_*`,
    `e_src_fix_*`), an *increment* ledger (`q_tag_inc_*`, `e_src_inc_*`) and a
    *mechanism* ledger (`q_tag_led_<mechanism>`, `e_src_led_<mechanism>`). See
    [Tagged Water Tracers](tagged_water.md) and
    [Energy Source Tags](energy_source_tags.md).
  - **Process record**: one process's signed history of the parent tendency,
    kept as `prc_e_<process>` or `prc_q_<process>` and written out as
    `e_prc_*` and `q_prc_*`. One field per process, never transported. See
    [Process-Change Records](process_record.md).

Tags split a variable, such as total water or moist total energy, into named
parts. The keys are in [Configuring Tracers](tracer_configuration.md).

  - **Region tag**: a tag with a region and no source. A transported part of
    the parent. The region tags together form one partition of it.
  - **Source tag**: a tag with a `source` in `water_tracers` or
    `energy_source_tags`. The amount of the parent present now that came from
    that process.
  - **Signed process tag**: a tag with a `source` in `energy_tracers`. The
    signed running total of what that process added, which goes negative under
    net cooling.
  - **Residual**: the parent, for water `max(ρq_tot, 0)`, minus the sum of the
    region tags. Closure is the statement that it is small.
  - **Offset**: `energy_source_tag_offset`, an energy per kilogram that the
    energy source tags add to `ρe_tot` before they split it. The model never
    sees it.
  - **Not used**: *heat tagging* names a method that tags potential
    temperature, and a *source fingerprint* is an analysis product that the
    model does not write out.

For the mapping between the symbols used in the equations pages and the
names used in the code (the `ᶜ`/`ᶠ` prefixes, subdomain superscripts, and
prognostic-variable names), see [Notation and Symbols](notation.md).
