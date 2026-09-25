# Parses each experiment config, builds its model, and checks the keys the
# design relies on and that every requested diagnostic is registered. Run from
# the worktree root, since the D4 config names a toml path relative to it.
import ClimaAtmos as CA
import ClimaAtmos.Diagnostics as CAD
dir = ARGS[1]
for file in sort(readdir(dir; join = true))
    endswith(file, ".yml") || continue
    config = CA.AtmosConfig(file; job_id = splitext(basename(file))[1])
    params = CA.ClimaAtmosParameters(config)
    setup = CA.get_setup_type(
        config.parsed_args,
        CA.Parameters.thermodynamics_params(params),
    )
    grid = CA.get_grid(config.parsed_args, params, config.comms_ctx)
    model = CA.get_atmos(config, params, grid; setup_type = setup)
    esm = model.energy_source_tagging_model
    CAD.register_energy_source_tagging_diagnostics!(model)
    CAD.register_tag_ledger_diagnostics!(model)
    CAD.register_process_record_diagnostics!(model)
    names = reduce(vcat, [d["short_name"] for d in config.parsed_args["diagnostics"]])
    absent = filter(n -> !haskey(CAD.ALL_DIAGNOSTICS, n), names)
    println(
        basename(file),
        ": repair = ", esm.repair,
        ", increment = ", esm.transport isa CA.EnthalpyIncrementEnergySourceTransport,
        ", ledger per tag = ", CA.has_energy_source_ledger_per_tag(esm),
        ", ledgers = ", CA.energy_source_per_tag_ledger_names(esm),
        ", records = ", !isnothing(model.energy_process_record),
        ", absent diagnostics = ", absent,
    )
end
