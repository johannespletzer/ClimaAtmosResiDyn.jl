using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

@testset "Check that every available config file has a unique `job_id`" begin
    all_job_ids = String[]
    for (root, _, files) in walkdir(CA.config_path), f in files
        file = joinpath(root, f)
        endswith(file, ".yml") || continue
        job_id = CA.job_id_from_config_file(file)
        @test !(job_id in all_job_ids)
        push!(all_job_ids, job_id)
    end
end

file, io = mktemp()
config_err = ErrorException("File $(CA.normrelpath(file)) is empty or missing.")
@test_throws config_err CA.AtmosConfig(file)

@testset "Check that entries in `default_config.yml` have `help` and `value` keys" begin
    config = CA.load_yaml_file(CA.default_config_file)
    missing_help = String[]
    missing_value = String[]
    for (key, value) in config
        !haskey(value, "help") && push!(missing_help, key)
        !haskey(value, "value") && push!(missing_value, key)
    end
    # Every key in the default config should have a `help` and `value` key
    # If not, these tests will fail, indicating which keys are missing
    @test isempty(missing_help)
    @test isempty(missing_value)
end

# Config files whose keys are already out of step with the schema. They predate
# this test; each sets keys the model no longer reads, so those settings do
# nothing. Renaming them to whatever was meant would change what the job runs,
# so they are recorded here rather than quietly repaired. Do not add to this
# list -- fix the config instead.
const KNOWN_STALE_CONFIGS = Set([
    "rcemipii_box_CRM_1M",          # moist, precip_model, surface_temperature
    "single_column_beres_nogw_test", # implicit_sgs_*
    "bm_default",                    # perf_summary
])

@testset "Check that config files only set keys the schema defines" begin
    schema_keys = keys(CA.load_yaml_file(CA.default_config_file))
    for (root, _, files) in walkdir(CA.config_path), f in files
        file = joinpath(root, f)
        endswith(file, ".yml") || continue
        file == CA.default_config_file && continue
        first(splitext(f)) in KNOWN_STALE_CONFIGS && continue
        config = CA.load_yaml_file(file)
        # `job_id` is set by the `AtmosConfig` constructor, not by the schema.
        unknown = sort(setdiff(keys(config), schema_keys, ["job_id"]))
        # A key outside the schema is silently ignored at run time unless
        # `strict_config` is set, so nothing else catches this.
        @test unknown == String[]
    end
end

@testset "Retired config keys name their replacement" begin
    for (key, replacement) in CA.RETIRED_CONFIG_KEYS
        err = try
            CA.override_default_config(Dict(key => nothing))
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin(key, err.msg)
        @test occursin(replacement, err.msg)
    end

    # All offending keys are reported at once, so a config takes one pass to
    # migrate rather than one run per key.
    err = try
        CA.override_default_config(
            Dict("tagged_tracers" => nothing, "tracer_loss_timescale" => "1days"),
        )
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("tagged_tracers", err.msg)
    @test occursin("tracer_loss_timescale", err.msg)
end

@testset "Config files may carry mapping-valued keys" begin
    # `strip_help_messages` runs on user config files as well as on the schema,
    # so it must unwrap only genuine `(help, value)` schema entries. Without
    # that test a mapping-valued key such as `passive_tracers` fails with
    # `KeyError("value")` before any merging happens.
    mktemp() do file, io
        write(io, "passive_tracers:\n  production_rate: 2.0e-10\n")
        close(io)
        config = CA.strip_help_messages(CA.load_yaml_file(file))
        @test config["passive_tracers"] == Dict("production_rate" => 2.0e-10)
    end

    # A real schema entry is still unwrapped to its value.
    @test CA.strip_help_message(Dict("help" => "h", "value" => 3)) == 3
end
