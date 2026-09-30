#=
The cost of the tags, one process per point (G3 WP9, V-W10).

It measures, for one family, one mode and one tag count, what the tags cost in
build time, wall time per step, allocation per step and memory. It decides
nothing. The budget is the owner's, and design/WP9_COST.md says how the numbers
are read. It adds no model code: the tags come from the environment and the
model is built by `CA.get_simulation`, as for any run.

    FAMILY=water|energy MODE=default|copies NTAGS=<n> [PRECIP=1] \
    [VARIANT=none|ledgers|records|tracer|increment] [OUTDIR=<dir>] \
        julia +1.11 --project=<run tree>/.buildkite \
        experiments/tag_closure/analysis/wp9_cost_driver.jl <base config.yml>

NTAGS=0 is the untagged baseline of the same base config. Every other setting
that a tag needs comes from the tag builders below, so the base config carries
no tag key. The driver refuses a base config that does.

What it times, in this order, all in one process:

  1. loading ClimaAtmos;
  2. `AtmosConfig` and `get_simulation`, with the compile time inside it kept
     apart (`Base.@timed`'s `compile_time` and `recompile_time`);
  3. the first step, which compiles the stepper;
  4. WARMUP more steps, not timed;
  5. REPEATS blocks of STEPS steps, each timed with its allocation and GC time.

Every arm takes the same steps, so block `k` of one arm covers the same model
time as block `k` of every other arm of its base config. The timer reads the
wall clock, and the process is single-threaded on one rank.

`Sys.maxrss()` is read after each phase. It is the process's peak so far, so
the last value is the peak of the run. Slurm's own MaxRSS is the cross-check.

A build or a step that fails stops the run with an error, and the runscript
records the exit status. Nothing is skipped or filled in.
=#

using Printf
import Dates
const T_PROCESS_START = time()

import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaTimeSteppers as CTS
import YAML

# The registered values. The environment overrides them for smoke tests only,
# and the CSV records what was used.
const WARMUP = parse(Int, get(ENV, "WP9_WARMUP", "10"))
const STEPS = parse(Int, get(ENV, "WP9_STEPS", "20"))
const REPEATS = parse(Int, get(ENV, "WP9_REPEATS", "5"))

function env(name, default = nothing)
    value = get(ENV, name, "")
    if isempty(value)
        isnothing(default) && error("Set the environment variable $name.")
        return default
    end
    return value
end

# Keys the driver sets itself. A base config that has one would be measured
# with something the arm's name does not say.
const TAG_KEYS = (
    "water_tracers",
    "water_tag_updraft_copy",
    "water_tag_transport",
    "water_tag_precipitation",
    "water_tag_ledger_per_tag",
    "water_closure_check",
    "energy_source_tags",
    "energy_source_tag_offset",
    "energy_source_tag_repair",
    "energy_source_tag_transport",
    "energy_source_tag_updraft_copy",
    "energy_source_tag_ledger_per_tag",
    "energy_process_record",
    "water_process_record",
)

# The water tags. The first two are the region tags that partition the column,
# and the rest are source tags on the surface flux, as WP4a's scaling script
# has them. The region differs by column, and comes from the base config's name.
function water_tags(ntags, base_name)
    regions = if occursin("trmm0m", base_name)
        (("pbl", 1000.0, 200.0), ("free", 1000.0, 200.0))
    elseif occursin("1m_column", base_name)
        (("lower", 3000.0, 300.0), ("upper", 3000.0, 300.0))
    else
        error("No water tag regions for the base config $base_name.")
    end
    ntags >= 2 || error("Water tags need at least the two region tags, not $ntags.")
    region(name, z, width, above) = Dict{String, Any}(
        "name" => name,
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => z,
            "width" => width,
            ("above" => above,)...,
        ),
    )
    tags = Any[
        region(regions[1][1], regions[1][2], regions[1][3], false),
        region(regions[2][1], regions[2][2], regions[2][3], true),
    ]
    for k in 1:(ntags - 2)
        push!(tags, Dict{String, Any}("name" => "src$k", "source" => "surface_flux"))
    end
    return tags
end

# The energy tags. 2 and 4 are the first entries of G4.15's eight, 8 is the
# eight, and 32 adds source tags that repeat the four sources.
function energy_tags(ntags)
    region(name, above; source = nothing) = begin
        entry = Dict{String, Any}(
            "name" => name,
            "region" => Dict{String, Any}(
                "type" => "tanh_altitude",
                "z_center" => 750.0,
                "width" => 100.0,
                "above" => above,
            ),
        )
        isnothing(source) || (entry["source"] = source)
        entry
    end
    source(name, label) = Dict{String, Any}("name" => name, "source" => label)
    eight = Any[
        region("strat", true),
        region("tropo", false),
        source("rad", "radiation"),
        source("sfc", "surface_flux"),
        source("sub", "subsidence"),
        source("mp", "microphysics"),
        region("new_strat", true; source = "all"),
        region("new_tropo", false; source = "all"),
    ]
    ntags in (2, 4, 8) && return eight[1:ntags]
    ntags == 32 || error("Energy tag counts are 2, 4, 8 and 32, not $ntags.")
    labels = ("radiation", "surface_flux", "subsidence", "microphysics")
    extra = [source("src$k", labels[mod1(k, 4)]) for k in 1:(ntags - 8)]
    return vcat(eight, extra)
end

function tagged_config(dict, family, mode, ntags, precip, variant, base_name)
    ntags == 0 && return dict
    if family == "water"
        dict["water_tracers"] = water_tags(ntags, base_name)
        mode == "copies" && (dict["water_tag_updraft_copy"] = true)
        precip && (dict["water_tag_precipitation"] = true)
        variant == "ledgers" && (dict["water_tag_ledger_per_tag"] = true)
        variant in ("tracer", "increment") && (dict["water_tag_transport"] = variant)
    elseif family == "energy"
        precip && error("Rain and snow tags exist for the water family only.")
        dict["energy_source_tags"] = energy_tags(ntags)
        dict["energy_source_tag_offset"] = 110495.0
        dict["energy_source_tag_repair"] = true
        dict["energy_source_tag_transport"] = "enthalpy_increment"
        mode == "copies" && (dict["energy_source_tag_updraft_copy"] = true)
        variant == "ledgers" && (dict["energy_source_tag_ledger_per_tag"] = true)
        variant == "records" && (
            dict["energy_process_record"] =
                ["radiation", "surface_flux", "subsidence", "microphysics", "precipitation"]
        )
        variant in ("tracer", "increment") &&
            error("The transport variants are for the water family.")
    else
        error("FAMILY must be water or energy, not $family.")
    end
    return dict
end

maxrss_gb() = Sys.maxrss() / 1024^3
median(x) = (s = sort(x); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)

function main(base_path)
    load_seconds = time() - T_PROCESS_START
    family = env("FAMILY")
    mode = env("MODE")
    mode in ("default", "copies") || error("MODE must be default or copies, not $mode.")
    ntags = parse(Int, env("NTAGS"))
    precip = env("PRECIP", "0") == "1"
    variant = env("VARIANT", "none")
    variant in ("none", "ledgers", "records", "tracer", "increment") ||
        error("Unknown VARIANT $variant.")
    outdir = env("OUTDIR")
    # A batch node has no git, so the submitter reads the commit and hands it on.
    model_commit = env("MODEL_COMMIT")
    mkpath(outdir)
    ntags == 0 && (mode == "copies" || variant != "none" || precip) &&
        error("The untagged baseline has no mode, variant or precipitation.")
    base_name = splitext(basename(base_path))[1]

    dict = Dict{String, Any}(YAML.load_file(base_path))
    for key in TAG_KEYS
        haskey(dict, key) && error("The base config sets $key. The driver sets the tags.")
    end
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    dict["output_dir"] = mktempdir(outdir)
    dict = tagged_config(dict, family, mode, ntags, precip, variant, base_name)

    label = join(
        [family, base_name, ntags == 0 ? "untagged" : mode, precip ? "precip" : "noprecip",
         variant, "n$ntags"],
        "_",
    )
    println("[wp9] run $label")
    println("[wp9] model commit ", model_commit)
    println("[wp9] host ", gethostname(), " threads ", Threads.nthreads(),
        " loadavg ", strip(read("/proc/loadavg", String)))
    flush(stdout)

    # Build. The compile time inside it is counted by the runtime, not by us.
    build = Base.@timed begin
        config = CA.AtmosConfig(dict; job_id = label)
        CA.get_simulation(config)
    end
    simulation = build.value
    build_rss = maxrss_gb()
    @printf("[wp9] build %.1f s (compile %.1f s, recompile %.1f s, gc %.1f s, %.2f GB allocated), maxrss %.2f GB\n",
        build.time, build.compile_time, build.recompile_time, build.gctime, build.bytes / 1024^3,
        build_rss)
    flush(stdout)

    integrator = simulation.integrator
    p = integrator.p
    follower = if ntags > 0 && family == "water"
        string(CA.follows_water_increment(p.atmos.water_tagging_model))
    else
        "na"
    end
    println("[wp9] follows_water_increment ", follower)

    first_step = Base.@timed CTS.step!(integrator)
    @printf("[wp9] first step %.1f s (compile %.1f s), maxrss %.2f GB\n", first_step.time,
        first_step.compile_time + first_step.recompile_time, maxrss_gb())
    flush(stdout)
    for _ in 1:WARMUP
        CTS.step!(integrator)
    end
    warm_rss = maxrss_gb()

    blocks = map(1:REPEATS) do k
        GC.gc()
        block = Base.@timed for _ in 1:STEPS
            CTS.step!(integrator)
        end
        @printf("[wp9] block %d: %.3f ms/step, %.0f B/step, gc %.3f s, t = %.0f s\n", k,
            1e3 * block.time / STEPS, block.bytes / STEPS, block.gctime, integrator.t)
        flush(stdout)
        block
    end
    isnothing(findfirst(b -> b.compile_time + b.recompile_time > 0.05 * b.time, blocks)) ||
        @warn "A timed block spent over 5% of its time compiling. Read its number with care."

    step_ms = [1e3 * b.time / STEPS for b in blocks]
    bytes_per_step = [b.bytes / STEPS for b in blocks]
    gc_fraction = [b.gctime / b.time for b in blocks]
    final_rss = maxrss_gb()
    header = [
        "label", "family", "base", "mode", "ntags", "precip", "variant", "follower",
        "commit", "host", "loadavg1", "load_s", "build_s", "build_compile_s",
        "build_gc_s", "build_gb", "first_step_s", "first_step_compile_s", "steps_per_block",
        "repeats", "step_ms_min", "step_ms_median", "step_ms_max", "bytes_per_step_min",
        "bytes_per_step_max", "gc_fraction_max", "block_compile_s_max", "maxrss_build_gb", "maxrss_warm_gb",
        "maxrss_final_gb", "step_ms_blocks", "finished",
    ]
    row = [
        label, family, base_name, ntags == 0 ? "untagged" : mode, ntags, precip ? 1 : 0,
        variant, follower, model_commit, gethostname(),
        split(read("/proc/loadavg", String))[1], load_seconds, build.time,
        build.compile_time + build.recompile_time, build.gctime, build.bytes / 1024^3,
        first_step.time, first_step.compile_time + first_step.recompile_time, STEPS, REPEATS,
        minimum(step_ms), median(step_ms), maximum(step_ms), minimum(bytes_per_step),
        maximum(bytes_per_step), maximum(gc_fraction), maximum(b.compile_time + b.recompile_time for b in blocks), build_rss, warm_rss, final_rss,
        join(round.(step_ms; digits = 4), ";"), Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS"),
    ]
    length(header) == length(row) || error("The header and the row differ in length.")
    open(joinpath(outdir, "$label.csv"), "w") do io
        println(io, join(header, ","))
        println(io, join(row, ","))
    end
    @printf("RESULT %s step_ms_min=%.4f step_ms_median=%.4f build_s=%.1f maxrss_gb=%.2f\n", label,
        minimum(step_ms), median(step_ms), build.time, final_rss)
    return nothing
end

isempty(ARGS) && error("Usage: wp9_cost_driver.jl <base config.yml>")
isfile(ARGS[1]) || error("Base config not found: $(ARGS[1])")
main(abspath(ARGS[1]))
