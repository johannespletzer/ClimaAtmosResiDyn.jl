#=
Compare inference profiles of the same build at different numbers of tags (P4).

    julia +1.11 --startup-file=no experiments/tag_closure/analysis/p4_profile_compare.jl \
        <label>=<out_dir> <label>=<out_dir> ...

Each `out_dir` holds what `p4_inference_profile.jl` wrote. Give them in order of
growing size, for example `0=... 2=... 8=...`. The script prints:
  - each run's totals from `summary.txt`;
  - the methods whose exclusive inference time grows most from the first run to
    the last, with their times and specialization counts in every run;
  - the same by source file;
  - the share of the growth that the listed methods and files make.

It reads only the tables, so it runs anywhere.
=#

using Printf

const TOP = 40

runs = map(ARGS) do arg
    label, dir = split(arg, "="; limit = 2)
    (String(label), String(dir))
end
length(runs) >= 2 || error("give at least two label=dir pairs")

function read_methods(dir)
    table = Dict{String, Tuple{Float64, Int, Int}}()
    for line in readlines(joinpath(dir, "methods.csv"))[2:end]
        seconds, inferences, specializations, key = split(line, ","; limit = 4)
        table[key] =
            (parse(Float64, seconds), parse(Int, inferences), parse(Int, specializations))
    end
    return table
end

function read_files(dir)
    table = Dict{String, Float64}()
    for line in readlines(joinpath(dir, "files.csv"))[2:end]
        seconds, file = split(line, ","; limit = 2)
        table[file] = parse(Float64, seconds)
    end
    return table
end

println("totals")
for (label, dir) in runs
    println("  ", label, ":")
    for line in readlines(joinpath(dir, "summary.txt"))
        startswith(line, "config") || println("    ", line)
    end
end

methods = [read_methods(dir) for (_, dir) in runs]
files = [read_files(dir) for (_, dir) in runs]
labels = first.(runs)

seconds_of(table, key) = haskey(table, key) ? table[key][1] : 0.0
specializations_of(table, key) = haskey(table, key) ? table[key][3] : 0

all_methods = union(keys.(methods)...)
growth(key) = seconds_of(methods[end], key) - seconds_of(methods[1], key)
total_growth = sum(growth, all_methods)
ranked = sort(collect(all_methods); by = growth, rev = true)

@printf(
    "\ninference time grows by %.1f s from %s to %s\n",
    total_growth,
    labels[1],
    labels[end]
)
println("\nthe $TOP methods that grow most; seconds and specializations per run:")
println("  growth   ", join([rpad(l, 16) for l in labels]), "method")
for key in ranked[1:min(TOP, end)]
    cells = join([
        rpad(@sprintf("%.1f (%d)", seconds_of(t, key), specializations_of(t, key)), 16)
        for t in methods
    ])
    @printf("  %7.1f  %s%s\n", growth(key), cells, first(key, 150))
end
@printf("  the %d listed make %.0f%% of the growth\n", min(TOP, length(ranked)),
    100 * sum(growth, ranked[1:min(TOP, end)]) / total_growth)

all_files = union(keys.(files)...)
file_growth(f) = get(files[end], f, 0.0) - get(files[1], f, 0.0)
ranked_files = sort(collect(all_files); by = file_growth, rev = true)
println("\nthe 20 files that grow most; seconds per run:")
for f in ranked_files[1:min(20, end)]
    cells = join([rpad(@sprintf("%.1f", get(t, f, 0.0)), 10) for t in files])
    @printf("  %7.1f  %s%s\n", file_growth(f), cells, f)
end
