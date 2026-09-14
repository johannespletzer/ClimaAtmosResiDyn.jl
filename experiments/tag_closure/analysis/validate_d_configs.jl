#=
Validate the D configs, `configs/d*.yml`, with the model's own parsing.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/validate_d_configs.jl

For each D config:
  - the checks of `validate_configs.py` that apply, repeated here so that this
    script also runs where no Python has PyYAML. `validate_configs.py` carries
    the D runs in its `AUDIT_REQUIRED`, `STATE_CHECK` and `DENSITY_CHECK` sets;
  - then the model's own parsing: `AtmosConfig`, `AtmosTagging`, the closure
    checks, and `get_atmos`, which runs `check_case_consistency`. None of these
    builds a state or compiles a solve.

D2 and D3 parse. The model refuses 2M and 2MP3 only when it builds the cache
(`src/cache/precomputed_quantities.jl:160-167`), which this does not reach.
=#
import ClimaAtmos as CA

dir = joinpath(@__DIR__, "..", "configs")
is_d_config(path) = endswith(path, ".yml") && occursin(r"^d\d_", basename(path))
# Runs that deliberately carry no tags, as in `validate_configs.py`'s `CONTROLS`.
# A control configures no tag family and lists no diagnostics.
const CONTROLS = Set(["d4_column_edmf_notags"])
# EDMF runs with tags. Since C1a (#70) the model refuses `prognostic_edmfx` with
# energy source tags, so these parse only on code from before it, or once C1b
# shares the sub-grid fluxes. Here the refusal is the expected outcome, and a
# config in this set that parses is flagged, so that the set gets updated.
const REFUSED_BY_C1A =
    Set(["d4_column_edmf", "d4_column_edmf_enthalpy", "d5_column_edmf_ice"])
const C1A_REFUSAL = "cannot be used with `turbconv: prognostic_edmfx`"
defaults = CA.default_config_dict()

function duplicate_keys(path)
    seen, repeated = Set{String}(), String[]
    for line in eachline(path)
        (isempty(line) || !isletter(line[1])) && continue
        occursin(":", line) || continue
        key = split(line, ":")[1]
        key in seen && push!(repeated, key)
        push!(seen, key)
    end
    return repeated
end

schema_value(key) =
    defaults[key] isa AbstractDict && haskey(defaults[key], "value") ?
    defaults[key]["value"] : defaults[key]

is_region_tag(tag) =
    haskey(tag, "region") && (
        !haskey(tag, "source") || all(
            ==("none"),
            string.(tag["source"] isa AbstractVector ? tag["source"] : [tag["source"]]),
        )
    )

function shorts(config)
    out = Set{String}()
    for entry in get(config, "diagnostics", [])
        names = entry["short_name"]
        union!(out, names isa AbstractVector ? string.(names) : [string(names)])
    end
    return out
end

function check(path)
    name = splitext(basename(path))[1]
    config = CA.load_yaml_file(path)
    problems = String[]
    for key in duplicate_keys(path)
        push!(problems, "key $key bound twice")
    end
    for (key, value) in config
        key == "job_id" && continue
        haskey(defaults, key) || (push!(problems, "UNKNOWN KEY $key"); continue)
        default = schema_value(key)
        (isnothing(default) || key in ("hyperdiff", "diagnostics")) && continue
        same_boolness = (default isa Bool) == (value isa Bool)
        numeric_ok = default isa AbstractFloat && value isa Real
        if !same_boolness || (
            !(default isa Bool) && !(value isa typeof(default)) && !numeric_ok &&
            !(default isa AbstractVector && value isa AbstractVector)
        )
            push!(problems, "TYPE $key: default $(repr(default)) vs $(repr(value))")
        end
    end
    get(config, "job_id", nothing) == name || push!(problems, "job_id != file name")
    get(config, "FLOAT_TYPE", nothing) == "Float64" || push!(problems, "FLOAT_TYPE")
    get(config, "output_default_diagnostics", true) === false ||
        push!(problems, "output_default_diagnostics is not false")
    for key in ("apply_sem_quasimonotone_limiter", "tracer_nonnegativity_method")
        haskey(config, key) && push!(problems, "configures $key")
    end
    if get(config, "implicit_diffusion", false) === true &&
       isnothing(get(config, "vert_diff", nothing)) &&
       isnothing(get(config, "turbconv", nothing))
        push!(problems, "implicit_diffusion without vert_diff or turbconv")
    end
    tags = get(config, "energy_source_tags", nothing)
    block = get(config, "energy_source_closure_check", nothing)
    listed = shorts(config)
    if name in CONTROLS
        (isnothing(tags) && isnothing(block)) ||
            push!(problems, "a control must configure no tag family")
        isempty(listed) || push!(problems, "a control should list no diagnostics")
        return name, problems
    end
    (isnothing(tags) || isnothing(block)) && push!(problems, "tags and check together")
    if !isnothing(tags) && !isnothing(block)
        any(is_region_tag, tags) || push!(problems, "no pure region tag")
        haskey(block, "tolerance") && push!(problems, "tolerance set")
        haskey(block, "period") || push!(problems, "no period")
        get(block, "audit", false) === true || push!(problems, "audit is not true")
        "e_src_res" in listed || push!(problems, "e_src_res not listed")
        covered = Set(["e_src_res", "rhoa", "ta"])
        for tag in tags, prefix in ("e_src_", "e_src_fix_")
            push!(covered, prefix * string(tag["name"]))
        end
        for label in get(config, "energy_process_record", [])
            push!(covered, "e_prc_" * string(label))
        end
        stray = setdiff(listed, covered)
        isempty(stray) || push!(problems, "stray diagnostics $(collect(stray))")
        missing_fix = setdiff(
            Set("e_src_fix_" * string(t["name"]) for t in tags), listed,
        )
        isempty(missing_fix) ||
            push!(problems, "ledgers not listed $(collect(missing_fix))")
    end
    for entry in get(config, "diagnostics", [])
        haskey(entry, "reduction_time") && push!(problems, "reduction_time set")
        haskey(entry, "period") || push!(problems, "an entry has no period")
    end
    return name, problems
end

failed = 0
for path in sort(filter(is_d_config, readdir(dir; join = true)))
    name, problems = check(path)
    try
        config = CA.AtmosConfig(path; job_id = name)
        tagging = CA.AtmosTagging(config)
        CA.closure_checks_from_config(config)
        params = CA.ClimaAtmosParameters(config)
        setup = CA.get_setup_type(
            config.parsed_args,
            CA.Parameters.thermodynamics_params(params),
        )
        atmos = CA.get_atmos(config, params; setup_type = setup)
        model = tagging.energy_source_tagging_model
        if isnothing(model)
            println("     $name: no tags (control), ",
                "$(nameof(typeof(atmos.microphysics_model))), ",
                "$(nameof(typeof(atmos.turbconv_model)))")
        else
            println("     $name: $(length(model.tags)) tags, offset $(model.offset), ",
                "repair $(model.repair), $(nameof(typeof(model.transport))), ",
                "$(nameof(typeof(atmos.microphysics_model))), ",
                "$(nameof(typeof(atmos.turbconv_model)))")
        end
        name in REFUSED_BY_C1A &&
            push!(
                problems,
                "parsed, but the C1a refusal was expected; update REFUSED_BY_C1A",
            )
    catch err
        message = sprint(showerror, err)
        if name in REFUSED_BY_C1A && occursin(C1A_REFUSAL, message)
            println("     $name: refused, as C1a intends until C1b")
        else
            push!(problems, "model parsing failed: " * first(message, 400))
        end
    end
    if isempty(problems)
        println("ok   $name")
    else
        global failed += 1
        println("FAIL $name: ", join(problems, "; "))
    end
    flush(stdout)
end
println("\n$failed configs with problems")
