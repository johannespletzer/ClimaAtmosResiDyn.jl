#=
Phase A analysis: the water runs.

Reads every run directory under `experiments/tag_closure/output/`, writes
`output/summary_a.csv` and one PNG per question into `plots/`.

Usage, from the repository root:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/phase_a.jl

`TAG_CLOSURE_DIR` overrides the directory it works in, which is what
`analysis/selftest.jl` uses to point it at a scratch copy.

## What it reads

Per run, from `output/<run>/`:

  - `water_tag_closure.csv`, verbatim from the run. `gross_relative` is the
    number the memo reasons about.
  - `operator_residual.csv`, from `analysis/reduce_run.jl`. Its
    `max_abs_operator_residual` is the number phase A turns on.
  - `<run>.yml`, the merged snapshot, for `dt` and the upwinding keys. The
    snapshot rather than the file in `configs/`, because it pins what ran.

A run with no `provenance.txt` is refused rather than analysed: a residual
without the commit that produced it cannot be placed against the rest of the
series.

## The figures

  - `a_gross_relative_vs_time.png` — `gross_relative` against time, one line per
    run, both ladders.
  - `a_operator_residual_vs_dt.png` — the end-of-run operator residual against
    `dt` on log axes, van Leer against `none` and `first_order` in one panel,
    with each ladder's fitted slope in the legend. **The gap between the curves
    is the limiter's share, and it is what the decision rule reads.**
  - `a_variants_vs_time.png` — A3 and A4 against time, with the `Float64` A1 run
    at `dt` 10 s as the reference line.

Residual axes are logarithmic, units are on the axes, and every caption names
the commit and the date.

**This script has never been executed.** There is no Julia in the container it
was written in. Run `analysis/selftest.jl` first; it drives this on synthetic
tables whose answers were worked out by hand.
=#

import CairoMakie
import Dates
import DelimitedFiles
import Statistics
import YAML

const PHASE = "a"

"""
    read_table(path)

Read a CSV written by this series into `(header, columns)`, where `columns` maps
a name to a `Vector`. Comment lines beginning with `#` are skipped, which is how
`operator_residual.csv` carries its provenance block.

`DelimitedFiles` rather than `CSV.jl`, which `.buildkite` does not carry.
"""
function read_table(path)
    raw, header = DelimitedFiles.readdlm(
        path, ','; header = true, comments = true, comment_char = '#',
    )
    names = String.(vec(header))
    columns = Dict{String, Any}(
        name => raw[:, index] for (index, name) in enumerate(names)
    )
    return (names, columns)
end

function numeric(column)
    return Float64[
        x isa Number ? Float64(x) : parse(Float64, strip(String(x))) for
        x in column
    ]
end

"""
    seconds(duration)

A ClimaAtmos duration string such as `"2.5secs"` or `"1hours"` in seconds.

A local copy rather than `ClimaAtmos.time_to_seconds`, so the analysis does not
load the model to read three numbers off a ladder.
"""
function seconds(duration)
    duration isa Number && return Float64(duration)
    text = strip(String(duration))
    matched = match(r"^([0-9]+(?:\.[0-9]+)?)(s|secs|m|mins|h|hours|d|days|weeks)$", text)
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
directory is not a finished run.

Refuses a run with no `provenance.txt` rather than quietly analysing it.
"""
function load_run(run_dir)
    name = basename(run_dir)
    isfile(joinpath(run_dir, "provenance.txt")) || begin
        @warn "Skipping $name: no provenance.txt. A residual without the \
               commit that produced it cannot be placed against the rest of \
               the series. Ask for the file."
        return nothing
    end

    snapshot_path = joinpath(run_dir, name * ".yml")
    isfile(snapshot_path) || begin
        @warn "Skipping $name: no $name.yml configuration snapshot."
        return nothing
    end
    config = YAML.load_file(snapshot_path)

    closure_path = joinpath(run_dir, "water_tag_closure.csv")
    closure = isfile(closure_path) ? read_table(closure_path)[2] : nothing

    operator_path = joinpath(run_dir, "operator_residual.csv")
    operator = isfile(operator_path) ? read_table(operator_path)[2] : nothing

    upwinding = String(get(config, "tracer_upwinding", "vanleer_limiter"))
    return (;
        name,
        dt = seconds(get(config, "dt", "600secs")),
        upwinding,
        float_type = String(get(config, "FLOAT_TYPE", "Float32")),
        microphysics = String(get(config, "microphysics_model", "dry")),
        geometry = String(get(config, "config", "sphere")),
        closure,
        operator,
        provenance = read(joinpath(run_dir, "provenance.txt"), String),
    )
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

final(column) = isnothing(column) || isempty(column) ? NaN : numeric(column)[end]

"""
    fit_slope(x, y)

Least-squares slope of `log10(y)` against `log10(x)`.

The slope is what the decision rule reads: a ladder that falls with `dt` is a
time-discretization error that implicit tags would remove, and one that does not
is limiter nonlinearity that they would not touch. `NaN` with fewer than two
usable points, which is what a partly-submitted ladder gives.
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

ladder_label(upwinding) =
    upwinding == "vanleer_limiter" ? "A1, van Leer (default)" :
    upwinding == "none" ? "A2, none" :
    upwinding == "first_order" ? "A2, first_order" : "A2, $upwinding"

"""
    caption(runs)

The commit and the date, for the caption every plot carries.
"""
function caption(runs)
    commits = unique(provenance_field(run, "commit") for run in runs)
    commit = length(commits) == 1 ? first(commits) : "mixed: " * join(commits, ", ")
    short = length(commit) > 12 && !startswith(commit, "mixed") ? commit[1:12] : commit
    dates = unique(first(split(provenance_field(run, "finished"), 'T')) for run in runs)
    today = Dates.format(Dates.today(), "yyyy-mm-dd")
    return "commit $short, run $(join(dates, "/")), plotted $today"
end

"""
    plot_gross_relative(runs, plots_dir, note)

`gross_relative` against time, one line per run, both ladders together.
"""
function plot_gross_relative(runs, plots_dir, note)
    with_closure = filter(run -> !isnothing(run.closure), runs)
    isempty(with_closure) && return nothing
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase A: closure drift, both ladders",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "gross_relative (dimensionless)",
        yscale = log10,
    )
    for run in sort(with_closure; by = r -> (r.upwinding, r.dt))
        times = numeric(run.closure["time"])
        values = numeric(run.closure["gross_relative"])
        keep = findall(v -> isfinite(v) && v > 0, values)
        isempty(keep) && continue
        CairoMakie.lines!(
            axis, times[keep], values[keep];
            label = "$(run.name) (dt $(run.dt) s)",
        )
    end
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "a_gross_relative_vs_time.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    plot_operator_residual(runs, plots_dir, note)

The end-of-run operator residual against `dt`, log axes, one series per ladder,
each ladder's fitted slope in the legend.

This is the figure the decision rule reads. If A2's ladder falls with `dt` and
A1's is much flatter, the time-discretization part is real but the limiter sets
a floor that implicit tags cannot remove, and the distance between the curves is
all that closing the split would buy. If both fall together, the split is
time-discretization error. If neither falls, it is structural.
"""
function plot_operator_residual(runs, plots_dir, note)
    ladder_runs = filter(runs) do run
        !isnothing(run.operator) && run.geometry == "column" &&
            run.float_type == "Float64" && run.microphysics == "0M"
    end
    isempty(ladder_runs) && return nothing
    figure = CairoMakie.Figure(size = (860, 600))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase A: end-of-run operator residual against dt",
        subtitle = note,
        xlabel = "dt (s)",
        ylabel = "max |q_tag_res + Σᵢ q_tag_fix_i|  (kg kg⁻¹)",
        xscale = log10,
        yscale = log10,
    )
    for upwinding in ("vanleer_limiter", "none", "first_order")
        ladder = sort(
            filter(run -> run.upwinding == upwinding, ladder_runs); by = r -> r.dt,
        )
        length(ladder) < 1 && continue
        dts = [run.dt for run in ladder]
        values = [final(run.operator["max_abs_operator_residual"]) for run in ladder]
        keep = findall(v -> isfinite(v) && v > 0, values)
        isempty(keep) && continue
        slope = fit_slope(dts[keep], values[keep])
        label = ladder_label(upwinding) *
                (isnan(slope) ? " (slope: needs 2 points)" :
                 " (slope $(round(slope; digits = 2)))")
        CairoMakie.scatterlines!(axis, dts[keep], values[keep]; label)
    end
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "a_operator_residual_vs_dt.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    plot_variants(runs, plots_dir, note)

A3 and A4 against time, with the `Float64` A1 run at `dt` 10 s as the reference
line in the panel.
"""
function plot_variants(runs, plots_dir, note)
    reference = findfirst(run -> run.name == "a1_dt10", runs)
    variants = filter(run -> run.name in ("a3_1m", "a4_float32"), runs)
    isempty(variants) && return nothing
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase A: 1M and Float32 against the a1_dt10 reference",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "gross_relative (dimensionless)",
        yscale = log10,
    )
    for run in vcat(isnothing(reference) ? [] : [runs[reference]], variants)
        isnothing(run.closure) && continue
        times = numeric(run.closure["time"])
        values = numeric(run.closure["gross_relative"])
        keep = findall(v -> isfinite(v) && v > 0, values)
        isempty(keep) && continue
        is_reference = run.name == "a1_dt10"
        CairoMakie.lines!(
            axis, times[keep], values[keep];
            label = is_reference ? "$(run.name) (reference)" : run.name,
            linestyle = is_reference ? :dash : :solid,
            linewidth = is_reference ? 3 : 2,
        )
    end
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "a_variants_vs_time.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    write_summary(runs, output_dir)

One row per run: what it was, and where its two residuals ended up.
"""
function write_summary(runs, output_dir)
    header = [
        "run", "dt_seconds", "tracer_upwinding", "float_type",
        "microphysics_model", "geometry", "final_gross_relative",
        "final_operator_residual", "final_max_abs_q_tag_res",
        "final_max_abs_ledger_sum", "remapped_maximum", "commit",
    ]
    path = joinpath(output_dir, "summary_$(PHASE).csv")
    open(path, "w") do io
        println(io, join(header, ","))
        for run in sort(runs; by = r -> r.name)
            println(
                io,
                join(
                    Any[
                        run.name,
                        run.dt,
                        run.upwinding,
                        run.float_type,
                        run.microphysics,
                        run.geometry,
                        isnothing(run.closure) ? "" :
                        final(run.closure["gross_relative"]),
                        isnothing(run.operator) ? "" :
                        final(run.operator["max_abs_operator_residual"]),
                        isnothing(run.operator) ? "" :
                        final(run.operator["max_abs_q_tag_res"]),
                        isnothing(run.operator) ? "" :
                        final(run.operator["max_abs_ledger_sum"]),
                        run.geometry != "column",
                        provenance_field(run, "commit"),
                    ],
                    ",",
                ),
            )
        end
    end
    return path
end

function main()
    base = get(
        ENV, "TAG_CLOSURE_DIR",
        normpath(joinpath(@__DIR__, "..")),
    )
    output_dir = joinpath(base, "output")
    plots_dir = joinpath(base, "plots")
    isdir(output_dir) || error("No output directory: $output_dir")
    mkpath(plots_dir)

    candidates = sort(filter(isdir, [joinpath(output_dir, d) for d in readdir(output_dir)]))
    runs = filter(!isnothing, map(load_run, candidates))
    # Phase A only: every run of this phase is named a<n>.
    runs = filter(run -> startswith(run.name, PHASE), runs)
    isempty(runs) && error(
        "No phase A run under $output_dir. The owner commits each run's files \
        into output/<run>/ after it finishes; nothing has landed yet.",
    )

    note = caption(runs)
    summary = write_summary(runs, output_dir)
    figures = filter(
        !isnothing,
        [
            plot_gross_relative(runs, plots_dir, note),
            plot_operator_residual(runs, plots_dir, note),
            plot_variants(runs, plots_dir, note),
        ],
    )

    @info "Phase A analysis" runs = [run.name for run in runs] summary figures
    missing_operator = [run.name for run in runs if isnothing(run.operator)]
    isempty(missing_operator) || @warn "No operator_residual.csv for these \
                                        runs, so they are in the summary but \
                                        not in the dt figure. Run \
                                        analysis/reduce_run.jl on Levante \
                                        before copying a run back." missing_operator
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
