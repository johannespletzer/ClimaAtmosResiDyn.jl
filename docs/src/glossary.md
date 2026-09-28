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
    [parent-budget vocabulary](parent_budget/vocabulary.md) page.
  - **Tag ledger**: a running total that a tag correction keeps of what it
    moved. The word is used on the tag side only. It comes in three kinds. A
    *repair ledger* is `q_tag_fix_*` or `e_src_fix_*`, held in the cache as
    `ᶜwater_fix` or `ᶜenergy_source_fix`. An *increment ledger* is
    `e_src_inc_left`, `e_src_inc_moved` or `q_tag_inc_*`. A *mechanism
    ledger* is `q_tag_led_*` or `e_src_led_*`. `q_tag_inc_*`, `q_tag_led_*`
    and `e_src_led_*` are not defined in this version of the code. See
    [Tagged Water Tracers](tagged_water.md) and
    [Energy Source Tags](energy_source_tags.md).
  - **Process record**: one process's signed history of the parent tendency,
    kept as `prc_e_<process>` or `prc_q_<process>` and written out as
    `e_prc_*` and `q_prc_*`. See [Process-Change Records](process_record.md).

For the mapping between the symbols used in the equations pages and the
names used in the code (the `ᶜ`/`ᶠ` prefixes, subdomain superscripts, and
prognostic-variable names), see [Notation and Symbols](notation.md).
