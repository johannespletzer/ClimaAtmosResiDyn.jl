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

include(joinpath(@__DIR__, "tables.jl"))

const PHASE = "a"

ladder_label(upwinding) =
    upwinding == "vanleer_limiter" ? "A1, van Leer (default)" :
    upwinding == "none" ? "A2, none" :
    upwinding == "first_order" ? "A2, first_order" : "A2, $upwinding"

"""
    plot_gross_relative(runs, plots_dir, note)

`gross_relative` against time, one line per run, both ladders together.
"""
function plot_gross_relative(runs, plots_dir, note)
    drawable = filter(run -> !isnothing(run.closure), runs)
    isempty(drawable) && return nothing
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase A: closure drift, both ladders",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "gross_relative (dimensionless)",
        yscale = log10,
    )
    drew = false
    for run in sort(drawable; by = r -> (r.upwinding, r.dt))
        times = column(run, "closure", "time")
        values = column(run, "closure", "gross_relative")
        (isnothing(times) || isnothing(values)) && continue
        x, y = positive(times, values)
        isempty(y) && continue
        drew = true
        CairoMakie.lines!(axis, x, y; label = "$(run.name) (dt $(run.dt) s)")
    end
    drew || return nothing
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
time-discretization error and moving the water tags into the implicit solve
becomes worth its Jacobian cost. If neither falls, it is structural.
"""
function plot_operator_residual(runs, plots_dir, note)
    ladder_runs = filter(runs) do run
        haskey(run.reduced, "operator_residual") && run.geometry == "column" &&
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
    drew = false
    for upwinding in ("vanleer_limiter", "none", "first_order")
        ladder = sort(
            filter(run -> run.upwinding == upwinding, ladder_runs); by = r -> r.dt,
        )
        isempty(ladder) && continue
        dts = [run.dt for run in ladder]
        values = [
            final(column(run, "operator_residual", "max_abs_operator_residual"))
            for run in ladder
        ]
        x, y = positive(dts, values)
        isempty(y) && continue
        drew = true
        slope = fit_slope(x, y)
        label =
            ladder_label(upwinding) * (
                isnan(slope) ? " (slope: needs 2 points)" :
                " (slope $(round(slope; digits = 2)))"
            )
        CairoMakie.scatterlines!(axis, x, y; label)
    end
    drew || return nothing
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
    reference = filter(run -> run.name == "a1_dt10", runs)
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
    drew = false
    for run in vcat(reference, variants)
        times = column(run, "closure", "time")
        values = column(run, "closure", "gross_relative")
        (isnothing(times) || isnothing(values)) && continue
        x, y = positive(times, values)
        isempty(y) && continue
        drew = true
        is_reference = run.name == "a1_dt10"
        CairoMakie.lines!(
            axis, x, y;
            label = is_reference ? "$(run.name) (reference)" : run.name,
            linestyle = is_reference ? :dash : :solid,
            linewidth = is_reference ? 3 : 2,
        )
    end
    drew || return nothing
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "a_variants_vs_time.png")
    CairoMakie.save(path, figure)
    return path
end

function main()
    base = get(ENV, "TAG_CLOSURE_DIR", normpath(joinpath(@__DIR__, "..")))
    plots_dir = joinpath(base, "plots")
    mkpath(plots_dir)
    runs = load_phase(base, PHASE)
    isempty(runs) && error(
        "No phase A run under $(joinpath(base, "output")). The owner commits \
        each run's files into output/<run>/ after it finishes.",
    )

    note = caption(runs)
    summary = write_summary(
        runs, joinpath(base, "output"), PHASE,
        [
            "tracer_upwinding", "microphysics_model", "final_gross_relative",
            "final_operator_residual", "final_max_abs_q_tag_res",
            "final_max_abs_ledger_sum",
        ],
        run -> Any[
            run.upwinding,
            run.microphysics,
            final(column(run, "closure", "gross_relative")),
            final(column(run, "operator_residual", "max_abs_operator_residual")),
            final(column(run, "operator_residual", "max_abs_q_tag_res")),
            final(column(run, "operator_residual", "max_abs_ledger_sum")),
        ],
    )
    figures = filter(
        !isnothing,
        [
            plot_gross_relative(runs, plots_dir, note),
            plot_operator_residual(runs, plots_dir, note),
            plot_variants(runs, plots_dir, note),
        ],
    )

    @info "Phase A analysis" runs = [run.name for run in runs] summary figures
    unreduced = [
        run.name for run in runs if
        !haskey(run.reduced, "operator_residual") && !isnothing(run.family)
    ]
    isempty(unreduced) || @warn "No operator_residual.csv for these runs, so \
                                 they are in the summary but not in the dt \
                                 figure. Run analysis/reduce_run.jl on Levante \
                                 before copying a run back." unreduced
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
