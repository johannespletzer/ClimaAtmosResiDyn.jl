#=
Where the compile time of building a simulation goes, method by method (P4).

    julia +1.11 --project=<worktree>/.buildkite \
        experiments/tag_closure/analysis/p4_inference_profile.jl <config.yml> <out_dir>

E44c found that the EDMF column's build grows with the tags almost entirely
inside `get_simulation`, and mostly before the constructor's first timer. The
timers cannot say which methods grow. This script measures type inference
directly, with the timer that Julia's compiler carries for SnoopCompile,
`Core.Compiler.Timings`, so it needs no package.

It calls `get_simulation` once, under the timer, and writes into `out_dir`:
  - `summary.txt`: the wall time, the compile time Julia counts, the time in
    inference, and the time outside it, which holds code generation;
  - `methods.csv`: for every method, how often it was inferred, how many
    distinct specializations that was, and the time spent inferring it, not
    counting its callees;
  - `files.csv`: the same time summed by source file;
  - `roots.csv`: each call inference started from, with the time of its whole
    tree. These are the points where the build hands inference a new call.

Runs at 0, 2 and 8 tags are then compared with `p4_profile_compare.jl`.

A method's exclusive time counts each inference of it. A method inferred once
per remaining tuple of tags shows up as many specializations of one method.
=#

const T_START = time()

using Printf
import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA

const Timings = Core.Compiler.Timings

config_path, out_dir = ARGS[1], ARGS[2]
name = splitext(basename(config_path))[1]
mkpath(out_dir)

function report(label, value)
    @printf("[profile] %-40s %s   (since start %7.1f s)\n", label, value, time() - T_START)
    flush(stdout)
end

config = CA.AtmosConfig(config_path; job_id = "profile_$name")
report("AtmosConfig", "done")

Base.cumulative_compile_timing(true)
compile_start = Base.cumulative_compile_time_ns()[1]
Timings.reset_timings()
Core.Compiler.__set_measure_typeinf(true)
wall_start = time()
try
    # The call goes through `invokelatest`, so that what it compiles is
    # compiled inside the timer and not when this script is.
    Base.invokelatest(CA.get_simulation, config)
finally
    Core.Compiler.__set_measure_typeinf(false)
    Timings.close_current_timer()
end
wall = time() - wall_start
compile = (Base.cumulative_compile_time_ns()[1] - compile_start) / 1e9
Base.cumulative_compile_timing(false)
report("get_simulation", @sprintf("%.1f s", wall))

root = Timings._timings[1]

method_key(mi) =
    mi.def isa Method ?
    string(mi.def.module, ".", mi.def.name, " ", mi.def.file, ":", mi.def.line) :
    string(mi.def)
source_file(mi) = mi.def isa Method ? string(mi.def.file) : "(toplevel)"
short(x, n) = (s = replace(string(x), '\n' => ' ', ',' => ';'); first(s, n))

# Walk the tree without recursion, since inference can nest deeply. Each node's
# `time` is its exclusive time in nanoseconds. The root's is the time outside
# inference.
exclusive = Dict{String, Float64}()
inferences = Dict{String, Int}()
specializations = Dict{String, Set{UInt}}()
by_file = Dict{String, Float64}()
inference_total = 0.0
nodes = 0
stack = copy(root.children)
while !isempty(stack)
    node = pop!(stack)
    global nodes += 1
    mi = node.mi_info.mi
    key = method_key(mi)
    seconds = node.time / 1e9
    global inference_total += seconds
    exclusive[key] = get(exclusive, key, 0.0) + seconds
    inferences[key] = get(inferences, key, 0) + 1
    push!(get!(specializations, key, Set{UInt}()), objectid(mi))
    file = source_file(mi)
    by_file[file] = get(by_file, file, 0.0) + seconds
    append!(stack, node.children)
end

inclusive(node) = begin
    total = 0.0
    stack = [node]
    while !isempty(stack)
        n = pop!(stack)
        total += n.time / 1e9
        append!(stack, n.children)
    end
    total
end
roots = [
    (inclusive(c), method_key(c.mi_info.mi), short(c.mi_info.mi.specTypes, 400)) for
    c in root.children
]
sort!(roots; by = first, rev = true)

open(joinpath(out_dir, "summary.txt"), "w") do io
    println(io, "config: ", config_path)
    println(io, "julia: ", VERSION)
    @printf(io, "get_simulation wall time, s: %.1f\n", wall)
    @printf(io, "compile time Julia counts, s: %.1f\n", compile)
    @printf(io, "time in inference, s: %.1f\n", inference_total)
    @printf(io, "time outside inference while timing, s: %.1f\n", root.time / 1e9)
    println(io, "inference frames: ", nodes)
    println(io, "methods inferred: ", length(exclusive))
    println(io, "specializations inferred: ", sum(length, values(specializations)))
    println(io, "inference roots: ", length(root.children))
end

open(joinpath(out_dir, "methods.csv"), "w") do io
    println(io, "exclusive_s,inferences,specializations,method")
    for key in sort(collect(keys(exclusive)); by = k -> exclusive[k], rev = true)
        @printf(io, "%.6f,%d,%d,%s\n", exclusive[key], inferences[key],
            length(specializations[key]), replace(key, ',' => ';'))
    end
end

open(joinpath(out_dir, "files.csv"), "w") do io
    println(io, "exclusive_s,file")
    for file in sort(collect(keys(by_file)); by = f -> by_file[f], rev = true)
        @printf(io, "%.6f,%s\n", by_file[file], replace(file, ',' => ';'))
    end
end

open(joinpath(out_dir, "roots.csv"), "w") do io
    println(io, "inclusive_s,method,signature")
    for (seconds, key, signature) in roots
        @printf(io, "%.6f,%s,%s\n", seconds, replace(key, ',' => ';'), signature)
    end
end

print(read(joinpath(out_dir, "summary.txt"), String))
println("\nthe 25 methods with the most exclusive inference time:")
for line in readlines(joinpath(out_dir, "methods.csv"))[2:min(end, 26)]
    println("  ", first(line, 220))
end
println("\nthe 15 files with the most:")
for line in readlines(joinpath(out_dir, "files.csv"))[2:min(end, 16)]
    println("  ", line)
end
println("\nthe 10 largest inference roots:")
for line in readlines(joinpath(out_dir, "roots.csv"))[2:min(end, 11)]
    println("  ", first(line, 260))
end
report("done", "")
