#=
Shared readers for the phase analysis scripts.

`include`d by `phase_a.jl`, `phase_b.jl` and `phase_c.jl`, which differ in their
figures rather than in how they read a run. Not a module: these are three
scripts, and a module would buy namespacing that nothing here needs while
costing a qualified name on every call.

**Never executed.** There is no Julia in the container this was written in. The
first run of it is `analysis/selftest.jl`.
=#

import CairoMakie
import Dates
import DelimitedFiles
import Statistics
import YAML

"""
    setting(config, key, default)

A configuration value, treating a key that is present but null as absent.

`get` cannot do this on its own. The merged snapshot a run writes carries
**every** key of `default_config.yml` -- 175 of them -- with the unset ones
written as `~`, so `get(config, "energy_process_record", [])` finds the key,
returns `nothing`, and never reaches the default. `isempty(nothing)` is then
`iterate(::Nothing)`, which is what the first real run died of. The synthetic
snapshots in the self-test carried only the keys they set, which is why nothing
caught it.
"""
function setting(config, key, default)
    value = get(config, key, nothing)
    return isnothing(value) ? default : value
end

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

Refuses a run whose provenance does not name the commit, whether because the
file is absent or because it records `commit: unknown`. A residual without the
commit that produced it cannot be placed against the rest of the series, and an
`unknown` is that same defect wearing a hat.

The three families are read the same way. `closure` is whichever
`<family>_tag_closure.csv` the run wrote, `family` says which, and `reduced`
holds whatever `analysis/reduce_run.jl` produced for it. `audit` is the
`<family>_tag_audit.csv` of the same family when the run set `audit: true` on
its closure block, and `nothing` otherwise, which is the ordinary case.
"""
function load_run(run_dir)
    name = basename(run_dir)

    # A directory holding no files at all is not a run and is not a fault
    # either. It is what is left when a reading has been archived into a
    # subdirectory of its own, which is how an earlier reading of a
    # configuration is kept when the same configuration is run again against a
    # changed model. Skipping it silently is the point: warning here would fire
    # on every analysis until the new run lands, and would tell the reader to
    # ask for a file that is deliberately not there. A real run always hands
    # back at least `provenance.txt`, including a timing control, which has no
    # closure table.
    any(isfile, readdir(run_dir; join = true)) || return nothing

    provenance_path = joinpath(run_dir, "provenance.txt")
    if !isfile(provenance_path)
        @warn "Skipping $name: no provenance.txt. A residual without the \
               commit that produced it cannot be placed against the rest of \
               the series. Ask for the file."
        return nothing
    end
    provenance = read(provenance_path, String)

    # The rule is about the commit, not about the file. A provenance that
    # records `commit: unknown` fails it exactly as a missing one does: the
    # residual cannot be placed against the rest of the series either way. The
    # first real run produced one of these, because `module purge` had taken
    # git off the compute node's PATH, so this is a state that happens rather
    # than a hypothetical.
    commit = ""
    for line in split(provenance, '\n')
        startswith(line, "commit:") || continue
        commit = strip(line[(length("commit:") + 1):end])
        break
    end
    if isempty(commit) || commit == "unknown"
        recorded = isempty(commit) ? "no commit line at all" : "`commit: $commit`"
        @warn "Skipping $name: its provenance.txt has $recorded. A residual \
               without the commit that produced it cannot be placed against \
               the rest of the series. The run itself may be perfectly good: \
               repair the file rather than discarding the run, and see the \
               README under `Repairing a provenance`."
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
    audit = nothing
    for candidate in ("water", "energy_source", "energy")
        path = joinpath(run_dir, candidate * "_tag_closure.csv")
        if isfile(path)
            family = candidate
            closure = read_table(path)[2]
            # The audit table belongs beside `closure` and not in `reduced`,
            # because the model writes it and `analysis/reduce_run.jl` does not.
            # Most runs do not have one; `audit: true` is off by default and is
            # set on the two runs that have a question it answers.
            audit_path = joinpath(run_dir, candidate * "_tag_audit.csv")
            isfile(audit_path) && (audit = read_table(audit_path)[2])
            break
        end
    end

    # Every table `analysis/reduce_run.jl` can write. A table the reducer
    # produces and this list omits is invisible to every phase script: the file
    # is there, `run.reduced` has no key for it, and whatever reads it silently
    # draws nothing. Keep the two in step. `<family>_tag_audit.csv` is
    # deliberately not here: the reducer does not write it, and it is read above
    # beside the closure table it refines.
    reduced = Dict{String, Any}()
    for table in (
        "operator_residual",
        "energy_tag_residual",
        "source_tag_extrema",
        "process_record_extrema",
    )
        path = joinpath(run_dir, table * ".csv")
        isfile(path) && (reduced[table] = read_table(path)[2])
    end

    return (;
        name,
        config,
        family,
        closure,
        audit,
        reduced,
        dt = seconds(setting(config, "dt", "600secs")),
        upwinding = String(setting(config, "tracer_upwinding", "vanleer_limiter")),
        float_type = String(setting(config, "FLOAT_TYPE", "Float32")),
        microphysics = String(setting(config, "microphysics_model", "dry")),
        geometry = String(setting(config, "config", "sphere")),
        provenance,
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
column is absent. `table` is `"closure"` for the run's closure table and
`"audit"` for its audit table, neither of which the reducer writes.
"""
function column(run, table, name)
    source =
        table == "closure" ? run.closure :
        table == "audit" ? run.audit : get(run.reduced, table, nothing)
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
    log_limits(values; least_decades = 1.0)

Y-axis limits for a logarithmic panel, never narrower than `least_decades`.

A near-constant series autoscales into false structure. The first real `dt`
ladder spanned 10^-5.58 to 10^-5.54 -- four hundredths of a decade -- and
autoscaling magnified seven percent of scatter into a dramatic V with a sharp
minimum, which is the opposite of the finding. Scatter reads as scatter only
when the axis has room to show that it is small.

Returns `nothing` when nothing can be drawn.
"""
function log_limits(values; least_decades = 1.0)
    usable = [v for v in values if isfinite(v) && v > 0]
    isempty(usable) && return nothing
    low = log10(minimum(usable))
    high = log10(maximum(usable))
    centre = (low + high) / 2
    half = max((high - low) / 2 * 1.15, least_decades / 2)
    return (10.0^(centre - half), 10.0^(centre + half))
end

"""
    apply_log_limits!(axis, values; least_decades = 1.0)

Set `axis`'s y-limits with [`log_limits`](@ref). A no-op when there is nothing
to draw, which leaves Makie's own autoscale in place rather than erroring.
"""
function apply_log_limits!(axis, values; least_decades = 1.0)
    limits = log_limits(values; least_decades)
    isnothing(limits) || CairoMakie.ylims!(axis, limits...)
    return nothing
end

"""
    include_zero!(axis, values)

Widen a linear y-axis so that zero is inside it.

Every linear panel in this series asks a question about sign -- is a tag
negative, has a record gone negative -- and a series that stays well away from
zero would otherwise autoscale zero off the panel, taking the reference line
with it and leaving no scale for the reader to judge against.
"""
function include_zero!(axis, values)
    usable = [v for v in values if isfinite(v)]
    isempty(usable) && return nothing
    low = min(0.0, minimum(usable))
    high = max(0.0, maximum(usable))
    pad = (high - low) * 0.05
    pad == 0 && (pad = 1.0)
    CairoMakie.ylims!(axis, low - pad, high + pad)
    return nothing
end

"""
    tick_values(values)

`(positions, labels)` for ticking an axis at the actual values it holds, with a
trailing `.0` dropped.

Three `dt` values on a log axis get decade ticks by default, so the reader is
shown `10^0.4` where they want to know which point is `dt` 5 s.
"""
function tick_values(values)
    positions = sort(unique(values))
    labels = map(positions) do value
        text = string(value)
        endswith(text, ".0") ? text[1:(end - 2)] : text
    end
    return (positions, labels)
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
