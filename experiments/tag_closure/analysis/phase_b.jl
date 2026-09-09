#=
Phase B analysis: the energy runs.

Reads every phase B run directory under
`experiments/tag_closure/output/`, writes `output/summary_b.csv` and one PNG
per question into `plots/`.

Usage, from the repository root:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/phase_b.jl

`TAG_CLOSURE_DIR` overrides the directory it works in, which is what
`analysis/selftest.jl` uses to point it at a scratch copy.

## The figures

  - `b_gross_relative_bars.png` — the final `gross_relative` of each variant as
    one bar. The four B1 runs are the split: the difference between the
    baseline and each variant is that operator's share of the residual.
  - `b_gross_relative_vs_time.png` — the four B1 time series in one panel, with
    B2 and B3 alongside where they ran.

## What the decision rule reads

If one operator carries most of `gross_relative` and it is linear in `e_tot`,
mirroring that single operator by share could be reconsidered. Otherwise the
monitored residual stands, and the memo's statement that the energy residual is
the sum of every operator the parent receives as enthalpy is measured rather
than argued.

There is no ledger for the energy family. Nothing corrects the energy tags, so
no `q_tag_fix` analogue exists and the operator-residual subtraction of phase A
does not apply. What is read here is `gross_relative` from the closure table and
`max |e_tag_res|` from `energy_tag_residual.csv`.

**This script has never been executed.** There is no Julia in the container it
was written in. Run `analysis/selftest.jl` first; it drives this on synthetic
tables whose answers were worked out by hand.
=#

import CairoMakie
import Dates

include(joinpath(@__DIR__, "tables.jl"))

const PHASE = "b"

const B1_SPLIT = ("b1_base", "b1a_no_hyperdiff", "b1b_no_vert_diff", "b1c_neither")

variant_label(name) =
    name == "b1_base" ? "B1 baseline (both on)" :
    name == "b1a_no_hyperdiff" ? "B1a (no hyperdiff)" :
    name == "b1b_no_vert_diff" ? "B1b (no vert_diff)" :
    name == "b1c_neither" ? "B1c (neither)" :
    name == "b2_dry_hs" ? "B2 (dry Held-Suarez)" :
    name == "b3_limiter" ? "B3 (SEM limiter)" : name

"""
    plot_bars(runs, plots_dir, note)

The final `gross_relative` of each variant as one bar. The B1 split is the point:
the gap from the baseline to each variant is that operator's share.
"""
function plot_bars(runs, plots_dir, note)
    withvalue = [
        (run.name, final(column(run, "closure", "gross_relative"))) for run in runs
    ]
    withvalue = filter(p -> isfinite(p[2]) && p[2] > 0, withvalue)
    isempty(withvalue) && return nothing
    sort!(withvalue; by = first)
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase B: closure residual at the end of the run",
        subtitle = note,
        xlabel = "run",
        ylabel = "final gross_relative (dimensionless)",
        yscale = log10,
        xticks = (1:length(withvalue), [variant_label(p[1]) for p in withvalue]),
        xticklabelrotation = pi / 6,
    )
    CairoMakie.barplot!(axis, 1:length(withvalue), [p[2] for p in withvalue])
    path = joinpath(plots_dir, "b_gross_relative_bars.png")
    CairoMakie.save(path, figure)
    return path
end

"""
    plot_time_series(runs, plots_dir, note)

The four B1 variants in one panel, with B2 and B3 alongside where they ran.
"""
function plot_time_series(runs, plots_dir, note)
    drawable = filter(run -> !isnothing(run.closure), runs)
    isempty(drawable) && return nothing
    figure = CairoMakie.Figure(size = (900, 560))
    axis = CairoMakie.Axis(
        figure[1, 1];
        title = "Phase B: closure drift over ten days",
        subtitle = note,
        xlabel = "time (s)",
        ylabel = "gross_relative (dimensionless)",
        yscale = log10,
    )
    drew = false
    for run in sort(drawable; by = r -> r.name)
        times = column(run, "closure", "time")
        values = column(run, "closure", "gross_relative")
        (isnothing(times) || isnothing(values)) && continue
        x, y = positive(times, values)
        isempty(y) && continue
        drew = true
        CairoMakie.lines!(
            axis, x, y;
            label = variant_label(run.name),
            linewidth = run.name in B1_SPLIT ? 2 : 1,
            linestyle = run.name in B1_SPLIT ? :solid : :dash,
        )
    end
    drew || return nothing
    CairoMakie.axislegend(axis; position = :rb, labelsize = 10)
    path = joinpath(plots_dir, "b_gross_relative_vs_time.png")
    CairoMakie.save(path, figure)
    return path
end

function main()
    base = get(ENV, "TAG_CLOSURE_DIR", normpath(joinpath(@__DIR__, "..")))
    plots_dir = joinpath(base, "plots")
    mkpath(plots_dir)
    runs = load_phase(base, PHASE)
    isempty(runs) && error(
        "No phase B run under $(joinpath(base, "output")). The owner commits \
        each run's files into output/<run>/ after it finishes.",
    )

    note = caption(runs)
    summary = write_summary(
        runs, joinpath(base, "output"), PHASE,
        ["final_gross_relative", "final_max_abs_e_tag_res", "hyperdiff", "vert_diff"],
        run -> Any[
            final(column(run, "closure", "gross_relative")),
            final(column(run, "energy_tag_residual", "max_abs_e_tag_res")),
            # `setting` rather than `get`: a snapshot writes an unset key as
            # `~`, so `get` returns nothing rather than the default.
            setting(run.config, "hyperdiff", "off"),
            setting(run.config, "vert_diff", "off"),
        ],
    )
    figures = filter(
        !isnothing,
        [plot_bars(runs, plots_dir, note), plot_time_series(runs, plots_dir, note)],
    )

    # The share of each operator, which is what phase B exists to measure.
    baseline = findfirst(run -> run.name == "b1_base", runs)
    if !isnothing(baseline)
        base_value = final(column(runs[baseline], "closure", "gross_relative"))
        for run in runs
            run.name in B1_SPLIT && run.name != "b1_base" || continue
            value = final(column(run, "closure", "gross_relative"))
            isfinite(value) && isfinite(base_value) || continue
            @info "Share removed by switching one operator off" run =
                run.name baseline = base_value variant = value share =
                (base_value - value) / base_value
        end
    end

    @info "Phase B analysis" runs = [run.name for run in runs] summary figures
    return summary
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
