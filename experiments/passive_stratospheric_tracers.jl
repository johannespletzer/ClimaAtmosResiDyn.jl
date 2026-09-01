#=
Stratospheric passive tracer residence times.

Runs the configuration in
`config/example_configs/passive_stratospheric_tracers.yml`. That is a moist
aquaplanet with RRTMGP radiation, carrying one inert tracer per source region
above the tropopause, on a grid of latitude bands by height bands. Each tracer
is produced at a constant rate inside its region and removed below the
tropopause. Once its global burden stops drifting, its residence time is

    τ = burden / source

The burden, the source rate and the loss rate of every tracer are appended to
`stratospheric_tracer_budget.csv` in the output directory as the run proceeds.
`post_processing/tracer_residence_times.jl` turns that table into residence
times and reports how close each tracer is to equilibrium.

This script only selects the configuration, so the run picks up the usual
checkpointing, restart and diagnostics handling. The tracer machinery itself
lives in the package. See
`src/parameterized_tendencies/chemistry/stratospheric_passive_tracers.jl` and
`docs/src/passive_tracers.md`.

Usage:

    julia --project=.buildkite experiments/passive_stratospheric_tracers.jl

Resubmitting continues from the newest checkpoint, because the configuration
sets `detect_restart_file`. That is how a multi-year integration is built up out
of jobs that each fit in a queue slot.
=#

import ClimaComms as CC
CC.@import_required_backends

import ClimaAtmos as CA
import YAML

const CONFIG_FILE = normpath(
    @__DIR__,
    "..",
    "config",
    "example_configs",
    "passive_stratospheric_tracers.yml",
)

"""
    passive_tracer_config(; config_file = CONFIG_FILE, overrides...)

`AtmosConfig` for the passive stratospheric tracer experiment.

`overrides` replace individual configuration keys, which is how tests and
short trial runs shorten the integration without editing the YAML file:

```julia
config = passive_tracer_config(; t_end = "1days", dt_save_state_to_disk = "Inf")
```

An override replaces a whole top-level key, so changing one tracer setting means
passing the whole `passive_tracers` block, not just the part that differs:

```julia
config = passive_tracer_config(;
    passive_tracers = Dict(
        "release_grid" => Dict("latitude_bands" => 2, "height_bands" => 2),
        "loss_timescale" => "6hours",
    ),
)
```
"""
function passive_tracer_config(; config_file = CONFIG_FILE, overrides...)
    config_dict = YAML.load_file(config_file)
    for (key, value) in pairs(overrides)
        config_dict[String(key)] = value
    end
    return CA.AtmosConfig(config_dict; config_files = [config_file])
end

"""
    build_simulation(; kwargs...)

Build, but do not run, the passive stratospheric tracer simulation. Keyword
arguments are forwarded to [`passive_tracer_config`](@ref).
"""
build_simulation(; kwargs...) =
    CA.get_simulation(passive_tracer_config(; kwargs...))

"""
    plot_budget(output_dir)

Plot the tracer burdens from the budget table just written.

Wrapped so that a plotting failure cannot discard a completed integration:
this runs at the very end of a run that may have taken days, and the budget
table on disk is the actual result. `post_processing/plot_tracer_burdens.jl`
can always be re-run against that table afterwards.
"""
function plot_budget(output_dir)
    try
        include(
            joinpath(pkgdir(CA), "post_processing", "plot_tracer_burdens.jl"),
        )
        return Base.invokelatest(plot_tracer_burdens, output_dir)
    catch exception
        @warn "Could not plot tracer burdens; the budget table is unaffected \
               and post_processing/plot_tracer_burdens.jl can be run on it \
               directly" exception
        return nothing
    end
end

function main()
    simulation = build_simulation()
    CA.solve_atmos!(simulation)

    @info "Tracer budget table" path =
        CA.tracer_budget_path(simulation.output_dir)
    plot_budget(simulation.output_dir)

    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
