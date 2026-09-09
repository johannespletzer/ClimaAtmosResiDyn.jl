#=
Phase C analysis: the energy source tags.

Reads every phase C run directory under
`experiments/tag_closure/output/`, writes `output/summary_c.csv` and one PNG
per question into `plots/`.

Usage, from the repository root:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/phase_c.jl

`TAG_CLOSURE_DIR` overrides the directory it works in, which is what
`analysis/selftest.jl` uses to point it at a scratch copy.

## The figures

  - `c_nonpositive_fraction.png` — the volume fraction where `ρe_tot ≤ 0`,
    against time. Where that holds the donor share is undefined,
    `energy_source_fraction` returns zero, and the loss half of the attribution
    rule does not run at all while production still reaches the tags normally.
    A run in that regime accumulates production with no matching loss, which is
    not the rule the docs describe.
  - `c_min_tag_value.png` — the minimum of every `e_src_<name>` against time. A
    negative tag invalidates the amount-of-energy reading of that tag for as
    long as it lasts, and `e_src_res` will not tell you: it sums the pure region
    tags only, so a source-labelled tag going negative never enters it.
  - `c_e_src_res.png` — `max |e_src_res|` against time.

## What this phase decides

If a run shows bounded residuals and non-negative tags, the family is viable and
the remaining work is the tolerance model and the implicit brackets. If it does
not, the docs' alternative — water source tracing plus the energy process
record — is the recommendation, and `c3_column_record` is the run that shows
what that alternative reads.

There is no ledger for this family either: the source tags have no rescale and
no partition repair, so no `q_tag_fix` analogue exists and the operator-residual
subtraction of phase A does not apply.

A `c1_*` run does not exist yet and needs a model change and the owner's
approval. When one lands it is picked up here without an edit, and the
before-and-after reading the plan asks for becomes possible.

**This script has never been executed.** There is no Julia in the container it
was written in. Run `analysis/selftest.jl` first; it drives this on synthetic
tables whose answers were worked out by hand.
=#

import CairoMakie
import Dates

include(joinpath(@__DIR__, "tables.jl"))

const PHASE = "c"

"""
    tag_names(run)

The `e_src_<name>` tags this run carried, from its configuration snapshot.
"""
tag_names(run) =
    [String(tag["name"]) for tag in setting(run.config, "energy_source_tags", [])]

"""
    plot_nonpositive(runs, plots_dir, note)

The fraction of the domain where the parent is non-positive, against time.

This is the barrier the phase exists to measure, so it is drawn on a linear axis
from zero to one rather than a logarithmic one: the interesting values are 0 and
1, and a log axis cannot show either.
"""
function plot_nonpositive(runs, plots_dir, note)
    drawable = filter(run -> !isnothing(run.closure), runs)
    isempty(drawable) && return nothing
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase C: fraction of the domain where the parent is non-positive",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "nonpositive_fraction (volume fraction)",
    )
    drew = false
    for run in sort(drawable; by = r -> r.name)
        times = column(run, "closure", "time")
        values = column(run, "closure", "nonpositive_fraction")
        (isnothing(times) || isnothing(values)) && continue
        drew = true
        CairoMakie.lines!(axis, times, values; label = run.name)
    end
    drew || return nothing
    CairoMakie.ylims!(axis, -0.02, 1.02)
    CairoMakie.axislegend(axis; position = :rc, labelsize = 10)
    path = joinpath(plots_dir, "c_nonpositive_fraction.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    plot_min_tag(runs, plots_dir, note)

The minimum of every tag against time, with zero marked.

Linear, not logarithmic: the question is the sign, and a log axis cannot draw a
negative number at all.
"""
function plot_min_tag(runs, plots_dir, note)
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase C: minimum of each source tag (below zero is the barrier)",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "min e_src_<name> (J kg⁻¹)",
    )
    drew = false
    for run in sort(runs; by = r -> r.name)
        times = column(run, "source_tag_extrema", "time")
        isnothing(times) && continue
        for name in tag_names(run)
            values = column(run, "source_tag_extrema", "min_e_src_" * name)
            isnothing(values) && continue
            drew = true
            CairoMakie.lines!(axis, times, values; label = "$(run.name): $name")
        end
    end
    drew || return nothing
    CairoMakie.hlines!(axis, [0.0]; color = :black, linestyle = :dash)
    CairoMakie.axislegend(axis; position = :rb, labelsize = 9)
    path = joinpath(plots_dir, "c_min_tag_value.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    plot_residual(runs, plots_dir, note)

`max |e_src_res|` against time, on a logarithmic axis.
"""
function plot_residual(runs, plots_dir, note)
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase C: source tag closure residual",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "max |e_src_res| (J kg⁻¹)",
        yscale = log10,
    )
    drew = false
    for run in sort(runs; by = r -> r.name)
        times = column(run, "source_tag_extrema", "time")
        values = column(run, "source_tag_extrema", "max_abs_e_src_res")
        (isnothing(times) || isnothing(values)) && continue
        x, y = positive(times, values)
        isempty(y) && continue
        drew = true
        CairoMakie.lines!(axis, x, y; label = run.name)
    end
    drew || return nothing
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "c_e_src_res.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    record_processes(run)

The processes this run recorded, from its configuration snapshot.
"""
record_processes(run) =
    [String(name) for name in setting(run.config, "energy_process_record", [])]

"""
    plot_two_readings(runs, plots_dir, note)

The source tags and the process record of the same run, in one panel.

This is what C3 exists for, and it is the figure the fallback argument turns on.
The two are different quantities and neither can be read off the other: a source
tag is the amount of energy present now that came from a process, and a record
is the signed total that process has applied since the run started. They are
both J kg⁻¹, so one axis holds them, but where they diverge is the measurement
rather than an error.

Linear, not logarithmic: a record goes negative under net cooling, which a log
axis cannot draw at all.
"""
function plot_two_readings(runs, plots_dir, note)
    both = filter(runs) do run
        haskey(run.reduced, "process_record_extrema") &&
            haskey(run.reduced, "source_tag_extrema")
    end
    isempty(both) && return nothing
    figure = CairoMakie.Figure(size = (900, 600))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase C: two readings of the same process",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "J kg⁻¹",
    )
    drew = false
    for run in sort(both; by = r -> r.name)
        times = column(run, "source_tag_extrema", "time")
        isnothing(times) && continue
        for name in tag_names(run)
            values = column(run, "source_tag_extrema", "max_e_src_" * name)
            isnothing(values) && continue
            drew = true
            CairoMakie.lines!(
                axis, times, values;
                label = "$(run.name): max e_src_$name (amount present)",
            )
        end
        record_times = column(run, "process_record_extrema", "time")
        isnothing(record_times) && continue
        for process in record_processes(run)
            values = column(run, "process_record_extrema", "max_e_prc_" * process)
            isnothing(values) && continue
            drew = true
            CairoMakie.lines!(
                axis, record_times, values;
                linestyle = :dash,
                label = "$(run.name): max e_prc_$process (applied since t=0)",
            )
        end
    end
    drew || return nothing
    CairoMakie.hlines!(axis, [0.0]; color = :black, linestyle = :dot)
    CairoMakie.axislegend(axis; position = :lt, labelsize = 9)
    path = joinpath(plots_dir, "c_two_readings.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    worst_tag(run)

The most negative any tag of this run reached, and which tag it was.
"""
function worst_tag(run)
    worst = NaN
    which = ""
    for name in tag_names(run)
        values = column(run, "source_tag_extrema", "min_e_src_" * name)
        (isnothing(values) || isempty(values)) && continue
        candidate = minimum(values)
        if isnan(worst) || candidate < worst
            worst = candidate
            which = name
        end
    end
    return (worst, which)
end

function main()
    base = get(ENV, "TAG_CLOSURE_DIR", normpath(joinpath(@__DIR__, "..")))
    plots_dir = joinpath(base, "plots")
    mkpath(plots_dir)
    runs = load_phase(base, PHASE)
    isempty(runs) && error(
        "No phase C run under $(joinpath(base, "output")). The owner commits \
        each run's files into output/<run>/ after it finishes.",
    )

    note = caption(runs)
    summary = write_summary(
        runs, joinpath(base, "output"), PHASE,
        [
            "final_gross_relative", "final_nonpositive_fraction",
            "max_nonpositive_fraction", "final_max_abs_e_src_res",
            "most_negative_tag_value", "most_negative_tag",
            "recorded_processes", "final_max_e_prc",
        ],
        function (run)
            fraction = column(run, "closure", "nonpositive_fraction")
            worst, which = worst_tag(run)
            return Any[
                final(column(run, "closure", "gross_relative")),
                final(fraction),
                isnothing(fraction) || isempty(fraction) ? NaN : maximum(fraction),
                final(column(run, "source_tag_extrema", "max_abs_e_src_res")),
                worst,
                which,
                join(record_processes(run), " "),
                isempty(record_processes(run)) ? NaN :
                final(
                    column(
                        run, "process_record_extrema",
                        "max_e_prc_" * first(record_processes(run)),
                    ),
                ),
            ]
        end,
    )
    figures = filter(
        !isnothing,
        [
            plot_nonpositive(runs, plots_dir, note),
            plot_min_tag(runs, plots_dir, note),
            plot_residual(runs, plots_dir, note),
            plot_two_readings(runs, plots_dir, note),
        ],
    )

    # The barrier register, stated rather than left in a plot.
    for run in sort(runs; by = r -> r.name)
        fraction = column(run, "closure", "nonpositive_fraction")
        if !isnothing(fraction) && !isempty(fraction) && maximum(fraction) > 0
            @warn "Parent non-positive somewhere: the donor rule is inert \
                   there and production accumulates with no matching loss." run =
                run.name max_fraction = maximum(fraction)
        end
        worst, which = worst_tag(run)
        if !isnan(worst) && worst < 0
            @warn "A source tag went negative, which invalidates its \
                   amount-of-energy reading. e_src_res does not show this." run =
                run.name tag = which minimum = worst
        end
    end

    @info "Phase C analysis" runs = [run.name for run in runs] summary figures
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
