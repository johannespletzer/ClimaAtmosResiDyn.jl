#=
Shared readers for the phase analysis scripts.

`include`d by `phase_a.jl`, `phase_b.jl` and `phase_c.jl`, which differ in their
figures rather than in how they read a run. Not a module: these are three
scripts, and a module would buy namespacing that nothing here needs while
costing a qualified name on every call.

**Never executed.** There is no Julia in the container this was written in. The
first run of it is `analysis/selftest.jl`.
=#

import DelimitedFiles
import Statistics
import YAML

"""
    read_table(path)

Read a CSV written by this series into `(names, columns)`, where `columns` maps
a column name to a `Vector`. Lines beginning with `#` are skipped, which is how
`operator_residual.csv` carries its provenance block.

`DelimitedFiles` rather than `CSV.jl`, which `.buildkite` does not carry.
"""
function read_table(path)
    raw, header = DelimitedFiles.readdlm(
        path, ','; header = true, comments = true, comment_char = '#',
    )
    names = String.(vec(header))
    columns =
        Dict{String, Any}(name => raw[:, i] for (i, name) in enumerate(names))
    return (names, columns)
end

"""
    numeric(column)

A table column as `Float64`, whether `readdlm` typed it as numbers or strings.
"""
function numeric(column)
    return Float64[
        x isa Number ? Float64(x) : parse(Float64, strip(String(x))) for
        x in column
    ]
end

"""
    seconds(duration)

A ClimaAtmos duration string such as `"2.5secs"` or `"1hours"` in seconds.

A local copy of `time_to_seconds` rather than the model's, so the analysis does
not load ClimaAtmos to read three numbers off a ladder.
"""
function seconds(duration)
    duration isa Number && return Float64(duration)
    text = strip(String(duration))
    matched =
        match(r"^([0-9]+(?:\.[0-9]+)?)(s|secs|m|mins|h|hours|d|days|weeks)$", text)
    isnothing(matched) && error("Not a duration: $text")
    factors = Dict(
        "s" => 1.0, "secs" => 1.0, "m" => 60.0, "mins" => 60.0,
        "h" => 3600.0, "hours" => 3600.0, "d" => 86400.0, "days" => 86400.0,
        "weeks" => 604800.0,
    )
    return parse(Float64, matched.captures[1]) * factors[matched.captures[2]]
end

"""
    load_run(run_dir)

Everything the figures need from one run directory, or `nothing` when the
directory does not hold a finished run.

Refuses a run with no `provenance.txt` rather than quietly analysing it: a
residual without the commit that produced it cannot be placed against the rest
of the series.

The three families are read the same way. `closure` is whichever
`<family>_tag_closure.csv` the run wrote, `family` says which, and `reduced`
holds whatever `analysis/reduce_run.jl` produced for it.
"""
function load_run(run_dir)
    name = basename(run_dir)
    if !isfile(joinpath(run_dir, "provenance.txt"))
        @warn "Skipping $name: no provenance.txt. A residual without the \
               commit that produced it cannot be placed against the rest of \
               the series. Ask for the file."
        return nothing
    end

    snapshot = joinpath(run_dir, name * ".yml")
    if !isfile(snapshot)
        @warn "Skipping $name: no $name.yml configuration snapshot."
        return nothing
    end
    config = YAML.load_file(snapshot)

    family = nothing
    closure = nothing
    for candidate in ("water", "energy_source", "energy")
        path = joinpath(run_dir, candidate * "_tag_closure.csv")
        if isfile(path)
            family = candidate
            closure = read_table(path)[2]
            break
        end
    end

    reduced = Dict{String, Any}()
    for table in
        ("operator_residual", "energy_tag_residual", "source_tag_extrema")
        path = joinpath(run_dir, table * ".csv")
        isfile(path) && (reduced[table] = read_table(path)[2])
    end

    return (;
        name,
        config,
        family,
        closure,
        reduced,
        dt = seconds(get(config, "dt", "600secs")),
        upwinding = String(get(config, "tracer_upwinding", "vanleer_limiter")),
        float_type = String(get(config, "FLOAT_TYPE", "Float32")),
        microphysics = String(get(config, "microphysics_model", "dry")),
        geometry = String(get(config, "config", "sphere")),
        provenance = read(joinpath(run_dir, "provenance.txt"), String),
    )
end

"""
    load_phase(base, letter)

Every run of one phase under `base/output`, sorted by name.
"""
function load_phase(base, letter)
    output_dir = joinpath(base, "output")
    isdir(output_dir) || error("No output directory: $output_dir")
    dirs = sort(filter(isdir, [joinpath(output_dir, d) for d in readdir(output_dir)]))
    runs = filter(!isnothing, map(load_run, dirs))
    return filter(run -> startswith(run.name, letter), runs)
end

"""
    provenance_field(run, key)

One `key: value` line out of a run's `provenance.txt`, or `"unknown"`.
"""
function provenance_field(run, key)
    for line in split(run.provenance, '\n')
        startswith(line, key * ":") || continue
        return strip(line[(length(key) + 2):end])
    end
    return "unknown"
end

"""
    column(run, table, name)

One column of one reduced table as `Float64`, or `nothing` when the table or the
column is absent. `table` is `"closure"` for the run's closure table.
"""
function column(run, table, name)
    source =
        table == "closure" ? run.closure : get(run.reduced, table, nothing)
    isnothing(source) && return nothing
    haskey(source, name) || return nothing
    return numeric(source[name])
end

"""
    final(values)

The last element, or `NaN` when there is nothing to take.
"""
final(values) = isnothing(values) || isempty(values) ? NaN : values[end]

"""
    positive(x, y)

The pairs of `(x, y)` that a logarithmic axis can draw.
"""
function positive(x, y)
    keep = findall(i -> isfinite(x[i]) && isfinite(y[i]) && y[i] > 0, eachindex(y))
    return (x[keep], y[keep])
end

"""
    fit_slope(x, y)

Least-squares slope of `log10(y)` against `log10(x)`.

The slope is what phase A's decision rule reads: a ladder that falls with `dt`
is a time-discretization error that implicit tags would remove, and one that
does not is limiter nonlinearity that they would not touch. `NaN` with fewer
than two usable points, which is what a partly-submitted ladder gives.
"""
function fit_slope(x, y)
    usable = [
        (log10(xi), log10(yi)) for (xi, yi) in zip(x, y) if
        isfinite(xi) && isfinite(yi) && xi > 0 && yi > 0
    ]
    length(usable) < 2 && return NaN
    lx = first.(usable)
    ly = last.(usable)
    mx = Statistics.mean(lx)
    my = Statistics.mean(ly)
    denominator = sum((v - mx)^2 for v in lx)
    denominator == 0 && return NaN
    return sum((lx[i] - mx) * (ly[i] - my) for i in eachindex(lx)) / denominator
end

"""
    caption(runs)

The commit and the date, for the caption every plot carries.
"""
function caption(runs)
    commits = unique(provenance_field(run, "commit") for run in runs)
    commit =
        length(commits) == 1 ? first(commits) : "mixed: " * join(commits, ", ")
    short =
        length(commit) > 12 && !startswith(commit, "mixed") ? commit[1:12] :
        commit
    dates =
        unique(first(split(provenance_field(run, "finished"), 'T')) for run in runs)
    today = Dates.format(Dates.today(), "yyyy-mm-dd")
    return "commit $short, run $(join(dates, "/")), plotted $today"
end

"""
    write_summary(runs, output_dir, phase, extra_header, extra_row)

One row per run, with the columns every phase shares and whatever `extra_row`
adds. Returns the path written.
"""
function write_summary(runs, output_dir, phase, extra_header, extra_row)
    header = vcat(
        ["run", "family", "geometry", "dt_seconds", "float_type", "remapped_maximum"],
        extra_header,
        ["commit"],
    )
    path = joinpath(output_dir, "summary_$(phase).csv")
    open(path, "w") do io
        println(io, join(header, ","))
        for run in sort(runs; by = r -> r.name)
            row = vcat(
                Any[
                    run.name,
                    isnothing(run.family) ? "none" : run.family,
                    run.geometry,
                    run.dt,
                    run.float_type,
                    run.geometry != "column",
                ],
                extra_row(run),
                Any[provenance_field(run, "commit")],
            )
            println(io, join(row, ","))
        end
    end
    return path
end
