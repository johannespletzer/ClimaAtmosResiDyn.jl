#=
Where the step's time and allocation go, one process per point (G3 WP9, the
P2/P3 profile of design/WP9_COST.md section 8). It decides nothing.

    FAMILY=water|energy|both MODE=default NTAGS=<n> [PRECIP=1] OUTDIR=<dir> \
    MODEL_COMMIT=<sha> \
        julia +1.11 --project=<run tree>/.buildkite \
        experiments/tag_closure/analysis/wp9_profile_driver.jl <base config.yml>

The tags, the base config check and the label come from wp9_cost_driver.jl,
read without its last lines (the call to its `main`), so both drivers build the
same model for the same point.

In one process, after the build, the first step and the cost driver's warm-up:

  1. one block of STEPS steps, timed with its allocation, as in the cost
     driver, and a second block that counts the allocations;
  2. a time profile (`Profile`, 1 ms sampling) over at least STEPS steps and
     at least PROFILE_SECONDS of wall time;
  3. an allocation profile (`Profile.Allocs`) over ALLOC_STEPS steps, at a
     sample rate set so that about 2e5 allocations are recorded.

Each sample is put in a phase: the outermost frame of the stack that names one
of the stepper's hooks (`PHASES`), or `callbacks` for a frame in
`src/callbacks/`, or `other` (the time stepper and solver themselves). It is
also put on a frame: the innermost frame in the model's `src/`. And it is
marked `tag code` when any frame on its stack is in
`src/parameterized_tendencies/tagged_tracers/`.

Since design section 12 (2026-10-02) each sample and allocation is also put
on a call: its phase and the first frame in `src/` inside the hook, so the
tendency or cache function the hook called. And on a tag entry: the outermost
frame in `tagged_tracers/`, or none. These two tables are written in full,
so the excess of one point over others can be read key by key.
=#

import Profile

const COST_DRIVER = joinpath(@__DIR__, "wp9_cost_driver.jl")
let src = read(COST_DRIVER, String)
    cut = findfirst("isempty(ARGS) && error(\"Usage: wp9_cost_driver.jl", src)
    isnothing(cut) && error("The cost driver's entry point moved. Update the cut.")
    include_string(Main, src[1:(first(cut) - 1)], COST_DRIVER)
end

const PROFILE_SECONDS = parse(Float64, get(ENV, "WP9_PROFILE_SECONDS", "5"))
const ALLOC_STEPS = parse(Int, get(ENV, "WP9_ALLOC_STEPS", "10"))
const ALLOC_SAMPLES = 2.0e5

# Hook functions by name, outermost first wins. The parent budget is off in
# these configs, so the hooks are the plain functions (src/simulation/integrator.jl).
const PHASES = Dict(
    "update_jacobian!" => "jacobian",
    "implicit_tendency!" => "implicit tendency",
    "remaining_tendency!" => "explicit tendency",
    "fully_explicit_tendency!" => "explicit tendency",
    "set_implicit_precomputed_quantities!" => "cache_imp!",
    "set_precomputed_quantities!" => "cache!",
    "limiters_func!" => "lim!",
    "dss!" => "dss!",
    "constrain_state!" => "constrain_state!",
    "initialize_implicit_stage_problem!" => "initialize_imp!",
    "ldiv!" => "linear solve",
)

# The functions P2 and P3 name (G4_TODO, OT-P2P3). A sample or an allocation
# counts for one when the function is anywhere on its stack. P3's string is
# allocated in `is_energy_source_tag_name` (energy_source_tags.jl).
const WATCH = ("_energy_source_share_norm!", "is_energy_source_tag_name")
on_stack(frames, name) = any(f -> String(f.func) == name, frames)

struct Classifier
    srcdir::String
end
in_src(c, f) = occursin(c.srcdir, String(f.file))
function phase(c, frames)
    # `frames` is innermost first, so read it from the end.
    for f in Iterators.reverse(frames)
        in_src(c, f) && occursin("/callbacks/", String(f.file)) && return "callbacks"
        name = String(f.func)
        haskey(PHASES, name) && return PHASES[name]
    end
    return "other"
end
function frame_key(c, frames)
    for f in frames
        in_src(c, f) && return "$(relpath(String(f.file), c.srcdir)):$(f.line) $(f.func)"
    end
    return "(outside src)"
end
# The call: the phase's hook and the first frame in `src/` inside it, which
# is the function the hook called (section 12). `frames` is innermost first.
function call_key(c, frames)
    for i in reverse(eachindex(frames))
        name = String(frames[i].func)
        in_src(c, frames[i]) && occursin("/callbacks/", String(frames[i].file)) &&
            return "callbacks"
        haskey(PHASES, name) || continue
        for j in (i - 1):-1:1
            f = frames[j]
            in_src(c, f) && String(f.func) != name &&
                return "$(PHASES[name]) > $(f.func) ($(basename(String(f.file))))"
        end
        return "$(PHASES[name]) > (no src frame)"
    end
    return "other"
end
# The tag entry: the outermost frame in `tagged_tracers/` (section 12).
function tag_entry_key(c, frames)
    for f in Iterators.reverse(frames)
        in_src(c, f) && occursin("/tagged_tracers/", String(f.file)) &&
            return "$(f.func) ($(basename(String(f.file))))"
    end
    return "(not tag code)"
end
tag_code(c, frames) =
    any(f -> in_src(c, f) && occursin("/tagged_tracers/", String(f.file)), frames)

add!(d, k, v) = (d[k] = get(d, k, 0.0) + v)

function write_table(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for r in rows
            println(
                io,
                join(
                    (
                        x isa AbstractString ? "\"" * replace(x, "\"" => "'") * "\"" : x
                        for
                        x in r
                    ),
                    ",",
                ),
            )
        end
    end
end
sorted(d) = sort(collect(d); by = x -> -x[2])

function profile_main(base_path)
    family = env("FAMILY")
    mode = env("MODE")
    mode == "default" || error("The profile is of the default mode, not $mode.")
    ntags = parse(Int, env("NTAGS"))
    precip = env("PRECIP", "0") == "1"
    variant = env("VARIANT", "none")
    variant == "none" || error("The profile has no variants, not $variant.")
    outdir = env("OUTDIR")
    model_commit = env("MODEL_COMMIT")
    mkpath(outdir)
    base_name = splitext(basename(base_path))[1]
    dict = Dict{String, Any}(YAML.load_file(base_path))
    for key in TAG_KEYS
        haskey(dict, key) && error("The base config sets $key. The driver sets the tags.")
    end
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    dict["output_dir"] = mktempdir(outdir)
    dict = tagged_config(dict, family, mode, ntags, precip, variant, base_name)
    label = join(
        [family, base_name, ntags == 0 ? "untagged" : mode,
            precip ? "precip" : "noprecip",
            variant, "n$ntags"],
        "_",
    )
    println("[wp9p] run $label, model commit $model_commit, host ", gethostname(),
        " loadavg ", strip(read("/proc/loadavg", String)))
    flush(stdout)

    build = Base.@timed begin
        config = CA.AtmosConfig(dict; job_id = label)
        CA.get_simulation(config)
    end
    integrator = build.value.integrator
    @printf("[wp9p] build %.1f s\n", build.time)
    CTS.step!(integrator)
    for _ in 1:WARMUP
        CTS.step!(integrator)
    end

    GC.gc()
    block = Base.@timed for _ in 1:STEPS
        CTS.step!(integrator)
    end
    step_ms = 1e3 * block.time / STEPS
    bytes_step = block.bytes / STEPS
    GC.gc()
    g0 = Base.gc_num()
    for _ in 1:STEPS
        CTS.step!(integrator)
    end
    allocs_step = Base.gc_alloc_count(Base.GC_Diff(Base.gc_num(), g0)) / STEPS
    @printf(
        "[wp9p] block: %.3f ms/step, %.0f B/step, %.0f allocations/step, compile %.3f s\n",
        step_ms, bytes_step, allocs_step, block.compile_time + block.recompile_time)
    flush(stdout)

    c = Classifier(dirname(pathof(CA)) * "/")

    # Time profile.
    time_steps = max(STEPS, ceil(Int, PROFILE_SECONDS / (step_ms / 1e3)))
    Profile.init(n = 10_000_000, delay = 0.001)
    Profile.clear()
    Profile.@profile for _ in 1:time_steps
        CTS.step!(integrator)
    end
    data = Profile.fetch(include_meta = false)
    lidict = Profile.getdict(data)
    t_phase, t_frame = Dict{String, Float64}(), Dict{String, Float64}()
    t_call, t_entry = Dict{String, Float64}(), Dict{String, Float64}()
    nsamples, ntag = 0, 0
    t_watch = Dict{String, Float64}(w => 0.0 for w in WATCH)
    frames = Base.StackTraces.StackFrame[]
    for ip in data
        if ip == 0
            if !isempty(frames)
                nsamples += 1
                add!(t_phase, phase(c, frames), 1)
                add!(t_frame, frame_key(c, frames), 1)
                add!(t_call, call_key(c, frames), 1)
                add!(t_entry, tag_entry_key(c, frames), 1)
                ntag += tag_code(c, frames)
                for w in WATCH
                    on_stack(frames, w) && add!(t_watch, w, 1)
                end
            end
            empty!(frames)
        else
            append!(frames, lidict[ip])
        end
    end
    nsamples > 0 || error("The time profile has no samples.")
    @printf("[wp9p] time profile: %d steps, %d samples, tag code on %.1f%% of them\n",
        time_steps, nsamples, 100 * ntag / nsamples)

    # Allocation profile.
    rate = min(1.0, ALLOC_SAMPLES / max(1.0, allocs_step * ALLOC_STEPS))
    Profile.Allocs.clear()
    Profile.Allocs.@profile sample_rate = rate for _ in 1:ALLOC_STEPS
        CTS.step!(integrator)
    end
    res = Profile.Allocs.fetch()
    scale = 1 / (rate * ALLOC_STEPS)  # recorded bytes to bytes per step
    a_phase, a_frame, a_type =
        Dict{String, Float64}(), Dict{String, Float64}(), Dict{String, Float64}()
    n_phase, n_frame = Dict{String, Float64}(), Dict{String, Float64}()
    a_tag = 0.0
    a_call, a_entry = Dict{String, Float64}(), Dict{String, Float64}()
    a_watch = Dict{String, Float64}(w => 0.0 for w in WATCH)
    for a in res.allocs
        st = a.stacktrace
        p, k, b = phase(c, st), frame_key(c, st), a.size * scale
        add!(a_phase, p, b)
        add!(n_phase, p, scale)
        add!(a_frame, k, b)
        add!(n_frame, k, scale)
        add!(a_type, string(a.type), b)
        add!(a_call, call_key(c, st), b)
        add!(a_entry, tag_entry_key(c, st), b)
        tag_code(c, st) && (a_tag += b)
        for w in WATCH
            on_stack(st, w) && add!(a_watch, w, b)
        end
    end
    a_total = sum(values(a_phase); init = 0.0)
    @printf(
        "[wp9p] allocation profile: rate %.4g, %d recorded, %.0f B/step estimated (block %.0f), tag code %.1f%%\n",
        rate, length(res.allocs), a_total, bytes_step,
        a_total > 0 ? 100 * a_tag / a_total : 0.0)
    flush(stdout)

    stem = joinpath(outdir, label)
    write_table("$(stem)_summary.csv",
        ["label", "family", "base", "ntags", "precip", "commit", "host", "loadavg1",
            "build_s",
            "step_ms", "bytes_per_step", "allocs_per_step", "time_steps", "samples",
            "tag_code_time_share", "alloc_steps", "alloc_rate", "alloc_recorded",
            "alloc_bytes_per_step_est", "tag_code_alloc_share"],
        [[label, family, base_name, ntags, precip ? 1 : 0, model_commit, gethostname(),
            split(read("/proc/loadavg", String))[1], build.time, step_ms, bytes_step,
            allocs_step,
            time_steps, nsamples, ntag / nsamples, ALLOC_STEPS, rate, length(res.allocs),
            a_total,
            a_total > 0 ? a_tag / a_total : 0.0]])
    # ms per step from the sample share and the timed block's step time.
    write_table("$(stem)_time_phase.csv", ["phase", "samples", "share", "ms_per_step"],
        [[k, v, v / nsamples, step_ms * v / nsamples] for (k, v) in sorted(t_phase)])
    write_table("$(stem)_time_frame.csv", ["frame", "samples", "share", "ms_per_step"],
        [
            [k, v, v / nsamples, step_ms * v / nsamples] for
            (k, v) in sorted(t_frame)[1:min(end, 80)]
        ])
    write_table("$(stem)_alloc_phase.csv", ["phase", "bytes_per_step", "allocs_per_step"],
        [[k, v, n_phase[k]] for (k, v) in sorted(a_phase)])
    write_table("$(stem)_alloc_frame.csv", ["frame", "bytes_per_step", "allocs_per_step"],
        [[k, v, n_frame[k]] for (k, v) in sorted(a_frame)[1:min(end, 80)]])
    write_table("$(stem)_watch.csv",
        ["function", "time_share", "ms_per_step", "bytes_per_step"],
        [
            [w, t_watch[w] / nsamples, step_ms * t_watch[w] / nsamples, a_watch[w]] for
            w in WATCH
        ])
    write_table("$(stem)_alloc_type.csv", ["type", "bytes_per_step"],
        [[k, v] for (k, v) in sorted(a_type)[1:min(end, 40)]])
    # Section 12: the calls and tag entries, in full.
    for (name, t, a) in (("call", t_call, a_call), ("tag_entry", t_entry, a_entry))
        keys_all = union(keys(t), keys(a))
        write_table("$(stem)_$(name).csv",
            ["key", "samples", "share", "ms_per_step", "bytes_per_step"],
            [
                [k, get(t, k, 0.0), get(t, k, 0.0) / nsamples,
                    step_ms * get(t, k, 0.0) / nsamples, get(a, k, 0.0)] for
                k in sort(collect(keys_all); by = k -> -get(t, k, 0.0))
            ])
    end
    println("RESULT $label done")
    return nothing
end

isempty(ARGS) && error("Usage: wp9_profile_driver.jl <base config.yml>")
isfile(ARGS[1]) || error("Base config not found: $(ARGS[1])")
profile_main(abspath(ARGS[1]))
