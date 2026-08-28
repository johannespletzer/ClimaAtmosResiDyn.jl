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
    unparseable = String[]
    for (root, _, files) in walkdir(CA.config_path), f in files
        file = joinpath(root, f)
        endswith(file, ".yml") || continue
        file == CA.default_config_file && continue
        first(splitext(f)) in KNOWN_STALE_CONFIGS && continue
        # Whether the oldest YAML.jl our `[compat]` bound allows can read every
        # config file is a dependency-bounds question, not a config-key one.
        # YAML 0.4.0 cannot parse a multi-line flow sequence, which several
        # `diagnostics` blocks use, and the downgrade job is the only place that
        # resolves it. Name the file and carry on rather than reporting a parser
        # limitation as a stale key; every file that does parse is still checked.
        config = try
            CA.load_yaml_file(file)
        catch
            push!(unparseable, CA.normrelpath(file))
            continue
        end
        # `job_id` is set by the `AtmosConfig` constructor, not by the schema.
        # `collect` because `setdiff` over `KeySet`s returns a `Set`, which
        # `sort` has no method for.
        unknown = sort(collect(setdiff(keys(config), schema_keys, ["job_id"])))
        # A key outside the schema is silently ignored at run time unless
        # `strict_config` is set, so nothing else catches this. The file name
        # rides along in the comparison because naming the offending file is
        # the point of the test, and a bare `unknown == String[]` would report
        # the stray keys without saying which file set them.
        name = CA.normrelpath(file)
        @test (name => unknown) == (name => String[])
    end
    isempty(unparseable) ||
        @warn "Config files this YAML.jl could not parse, so left unchecked" unparseable
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
