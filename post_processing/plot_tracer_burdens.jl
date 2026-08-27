#=
plot_tracer_burdens.jl

Plot the global burden of every stratospheric passive tracer against time, all
in one panel, from the `stratospheric_tracer_budget.csv` written by a
`passive_tracers` run.

Usage:

    julia --project=.buildkite post_processing/plot_tracer_burdens.jl \
        output/passive_stratospheric_tracers/output_active

    # or, from a session
    include("post_processing/plot_tracer_burdens.jl")
    plot_tracer_burdens("output/.../output_active"; dpi = 300)

The burden curve tells you whether a run is long enough. A tracer still
filling rises linearly; one in equilibrium has levelled off. That is the same
statement as `lifetime` (`burden / source`) tracking the elapsed time, but much
quicker to read across many tracers at once.

## Why the colours and dashes mean what they do

A run carries `n_latitude_bands * n_height_bands` tracers, 48 by default, and no
palette has 48 distinguishable hues. So the two region indices map to two
channels instead of cycling colours:

  - **Colour: height band**, on a single-hue ramp from light (just above the
    tropopause) to dark (the model top). Height above the tropopause is an
    ordered magnitude, so a sequential ramp is the honest encoding here.
  - **Dash pattern: latitude band**, south to north.

The legend then has `n_latitude_bands + n_height_bands` entries instead of their
product, 14 rather than 48. Each of the two gradients a reader cares about, with
height and with latitude, stays readable on its own.
=#

include(joinpath(@__DIR__, "tracer_lifetimes.jl"))

import CairoMakie

# Sequential blue ramp, light to dark. The ramp starts at step 250, not at the
# near-white end reserved for continuous fields: on a light surface a discrete
# ordered mark has to stay clear of the background.
const BURDEN_HEIGHT_RAMP = [
    "#86b6ef",  # 250
    "#6da7ec",  # 300
    "#5598e7",  # 350
    "#3987e5",  # 400
    "#2a78d6",  # 450
    "#256abf",  # 500
    "#1c5cab",  # 550
    "#184f95",  # 600
    "#104281",  # 650
    "#0d366b",  # 700
]

const BURDEN_LATITUDE_DASHES =
    [:solid, :dash, :dot, :dashdot, :dashdotdot, [0.5, 1.5, 3.0, 1.5]]

const BURDEN_SURFACE = "#fcfcfb"
const BURDEN_INK = "#0b0b0b"
const BURDEN_INK_MUTED = "#52514e"

"""
    band_indices(name) -> (latitude_index, height_index)

Recover the source-region indices from a tracer name such as
`ρq_gas_y02z05`, so that the plot can encode them on separate channels.
"""
function band_indices(name::AbstractString)
    m = match(r"y(\d+)z(\d+)$", name)
    isnothing(m) && error("Cannot read band indices from tracer name `$name`")
    return (parse(Int, m.captures[1]), parse(Int, m.captures[2]))
end

# Interpolate the ramp instead of indexing its ten tabulated steps, so adjacent
# bands stay distinct at any band count. `n_height_bands` can reach 12, where
# nearest-step picking would give two pairs of bands the same colour.
const BURDEN_HEIGHT_GRADIENT =
    CairoMakie.cgrad(CairoMakie.to_color.(BURDEN_HEIGHT_RAMP))

"""
    ramp_color(index, n)

`index`-th of `n` colours spread over the full sequential height ramp, so that
the lowest band is the lightest step and the topmost the darkest however many
bands there are.
"""
function ramp_color(index, n)
    n <= 1 && return BURDEN_HEIGHT_GRADIENT[1.0]
    return BURDEN_HEIGHT_GRADIENT[(index - 1) / (n - 1)]
end

"""
    plot_tracer_burdens(path; output = nothing, dpi = 300, size_inches = (10, 6))

Plot every tracer's burden against time in one panel and save it as a PNG.

`path` is the budget CSV or the output directory holding it. The figure is
written next to the table as `tracer_burdens.png` unless `output` says
otherwise. `size_inches` is the physical figure size, and `dpi` its resolution,
so the file comes out `size_inches .* dpi` pixels.

Returns the path written.
"""
function plot_tracer_burdens(
    path;
    output = nothing,
    dpi = 300,
    size_inches = (10, 6),
)
    (; series, order) = read_tracer_budget(path)

    indices = [band_indices(name) for name in order]
    n_latitude = maximum(first, indices)
    n_height = maximum(last, indices)

    # Time in whatever unit keeps the axis readable for the run at hand.
    span = maximum(maximum(series[name].time) for name in order)
    time_scale, time_label =
        span > 2 * SECONDS_PER_YEAR ? (SECONDS_PER_YEAR, "Time (years)") :
        (86400.0, "Time (days)")

    # Makie sizes figures in points (72 per inch), and `px_per_unit` scales
    # those to pixels, so this pair is exactly `size_inches * dpi` pixels.
    figure = CairoMakie.Figure(
        size = (72 * size_inches[1], 72 * size_inches[2]),
        backgroundcolor = BURDEN_SURFACE,
    )
    axis = CairoMakie.Axis(
        figure[1, 1];
        xlabel = time_label,
        ylabel = "Global burden (kg)",
        title = "Stratospheric passive tracer burdens",
        titlealign = :left,
        backgroundcolor = BURDEN_SURFACE,
        xlabelcolor = BURDEN_INK_MUTED,
        ylabelcolor = BURDEN_INK_MUTED,
        xticklabelcolor = BURDEN_INK_MUTED,
        yticklabelcolor = BURDEN_INK_MUTED,
        titlecolor = BURDEN_INK,
        # Recessive grid: present enough to read a value off, never competing
        # with the data.
        xgridcolor = (BURDEN_INK_MUTED, 0.12),
        ygridcolor = (BURDEN_INK_MUTED, 0.12),
        topspinevisible = false,
        rightspinevisible = false,
        leftspinecolor = (BURDEN_INK_MUTED, 0.4),
        bottomspinecolor = (BURDEN_INK_MUTED, 0.4),
    )

    for (name, (latitude_index, height_index)) in zip(order, indices)
        s = series[name]
        CairoMakie.lines!(
            axis,
            s.time ./ time_scale,
            s.burden;
            color = ramp_color(height_index, n_height),
            linestyle = BURDEN_LATITUDE_DASHES[mod1(
                latitude_index,
                length(BURDEN_LATITUDE_DASHES),
            )],
            linewidth = 2,
        )
    end

    # One legend entry per band, not per tracer. Heights are labelled by the
    # region they cover and latitudes by the band edges. Both come from the
    # table, so they match the configuration that produced it.
    height_labels = String[]
    height_elements = CairoMakie.LineElement[]
    for k in 1:n_height
        name = order[findfirst(ix -> last(ix) == k, indices)]
        s = series[name]
        push!(
            height_labels,
            "$(round(Int, s.height_lower / 1000))–\
             $(round(Int, s.height_upper / 1000)) km",
        )
        push!(
            height_elements,
            CairoMakie.LineElement(
                color = ramp_color(k, n_height),
                linewidth = 3,
            ),
        )
    end

    latitude_labels = String[]
    latitude_elements = CairoMakie.LineElement[]
    for i in 1:n_latitude
        name = order[findfirst(ix -> first(ix) == i, indices)]
        s = series[name]
        push!(
            latitude_labels,
            "$(round(Int, s.latitude_lower))–$(round(Int, s.latitude_upper))°",
        )
        push!(
            latitude_elements,
            CairoMakie.LineElement(
                color = BURDEN_INK_MUTED,
                linestyle = BURDEN_LATITUDE_DASHES[mod1(
                    i,
                    length(BURDEN_LATITUDE_DASHES),
                )],
                linewidth = 3,
            ),
        )
    end

    CairoMakie.Legend(
        figure[1, 2],
        [height_elements, latitude_elements],
        [height_labels, latitude_labels],
        ["Above tropopause", "Latitude"];
        framevisible = false,
        labelcolor = BURDEN_INK_MUTED,
        titlecolor = BURDEN_INK,
        titlefont = :bold,
        patchsize = (28.0f0, 12.0f0),
    )

    output_path =
        isnothing(output) ?
        joinpath(isdir(path) ? path : dirname(path), "tracer_burdens.png") :
        output
    CairoMakie.save(output_path, figure; px_per_unit = dpi / 72)
    @info "Wrote tracer burden plot" output_path dpi size_pixels =
        round.(Int, size_inches .* dpi)
    return output_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error(
        "Usage: julia post_processing/plot_tracer_burdens.jl <output_dir_or_csv>",
    )
    plot_tracer_burdens(ARGS[1])
end
