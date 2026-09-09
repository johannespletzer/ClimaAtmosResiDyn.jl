#=
Driver for one tag-closure experiment: one configuration path in, one run out.

Reads the YAML named by `CONFIG`, builds the configuration, runs the solve, and
prints the closure summary. It adds no model code and configures nothing: every
switch belongs in the configuration file, so that the merged snapshot the run
writes beside its output is a complete record of what ran.

The experiments this serves are planned in
`docs/src/tag_closure_experiments.md`, and the run order and the register are in
`experiments/tag_closure/README.md`.

Usage, from the repository root:

    CONFIG=experiments/tag_closure/configs/a1_dt10.yml \
        sbatch experiments/tag_closure/runscripts/phase_a.sh

`sbatch` exports the submitting environment, so the runscript reads `CONFIG` and
hands it on. The same variable works for a run by hand on a login node, and a
positional argument does as well, which is the shorter form when there is no
batch script in the way:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/run_tag_closure.jl configs/a1_dt10.yml

**A crashed solve returns `:simulation_crashed` rather than throwing**, so a
driver that ignored the return code would let the batch job exit zero over a
dead run. This one checks it and exits non-zero, which is what makes the job's
own exit status worth reading.
=#

import ClimaComms as CC
CC.@import_required_backends

import ClimaAtmos as CA

"""
    config_path()

The configuration file to run, from `CONFIG` or from the first positional
argument, whichever is set. Errors with an actionable message when neither is,
or when the file named is not there.

`CONFIG` wins over the argument, so a batch script can set it without having to
know how the driver was invoked.
"""
function config_path()
    from_env = get(ENV, "CONFIG", "")
    path = !isempty(from_env) ? from_env : (isempty(ARGS) ? "" : first(ARGS))
    isempty(path) && error(
        "No configuration given. Set the `CONFIG` environment variable to a \
        YAML file under experiments/tag_closure/configs/, or pass the path as \
        the first argument.",
    )
    isfile(path) || error(
        "Configuration file not found: $path. Paths are resolved from the \
        working directory, which for a batch job is the directory `sbatch` was \
        invoked from.",
    )
    return abspath(path)
end

"""
    print_closure_summary(output_dir)

Print the first and the last row of every closure table the run wrote.

The tables are the point of these runs, so a glance at the job's own output
should say whether the residual moved and by how much, without opening a file
on a machine the reader may not be logged into. The full tables are handed back
and analysed later; this is the "did it do anything" reading.

A family that was not configured wrote no table, which is not an error here.
"""
function print_closure_summary(output_dir)
    found = false
    for family in ("water", "energy", "energy_source")
        path = CA.tag_closure_path(output_dir, family)
        isfile(path) || continue
        found = true
        rows = readlines(path)
        # A table with a header and no data row is a run that died before the
        # check first fired. Say so rather than printing the header alone.
        if length(rows) < 2
            @info "$family tag closure: no rows, the check never fired" path
            continue
        end
        @info """
              $family tag closure ($(length(rows) - 1) rows)
                columns: $(rows[1])
                first:   $(rows[2])
                last:    $(rows[end])
              """ path
    end
    found || @info "No closure table was written. Expected when the run \
                    configures no closure check, and a symptom otherwise."
    return nothing
end

function main()
    path = config_path()
    config = CA.AtmosConfig(path)
    simulation = CA.get_simulation(config)
    result = CA.solve_atmos!(simulation)

    if CC.iamroot(CC.context(simulation))
        @info "Tag-closure run finished" simulation.job_id result.ret_code
        @info "Where it went" config = path simulation.output_dir
        print_closure_summary(simulation.output_dir)
    end

    # The whole reason the hand-back asks the owner to check what the driver
    # reported. `solve_atmos!` returns `:simulation_crashed` instead of
    # throwing, so without this the job exits zero over a dead run and the
    # failure is visible only to someone who reads the log.
    if result.ret_code != :success
        @error "The solve did not succeed. Hand the run back anyway: its \
                log, its provenance and whatever tables it managed to write \
                are the measurement, and where it stopped is itself a \
                result." result.ret_code
        exit(1)
    end
    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
