#=
tracer_residence_times.jl

Turn the `stratospheric_tracer_budget.csv` table written by a `passive_tracers`
run into tracer residence times, and say how close each tracer is to
equilibrium.

Usage:

    julia --project=.buildkite post_processing/tracer_residence_times.jl \
        output/passive_stratospheric_tracers/output_active

    # or, from a session
    include("post_processing/tracer_residence_times.jl")
    summary = tracer_residence_time_summary("output/.../output_active")

The residence time of a tracer whose source and sink balance is

    τ = burden / source

Away from that balance, the same ratio measured against the sink,
`burden / loss`, brackets it from the other side. The two are reported side by
side as `tau_src` and `tau_los`:

  - While the tracer is still filling, `burden ≈ source * t`, so `tau_src` is
    the elapsed time. It rises towards τ from below, so a short run reports its
    own length as the residence time. That is arithmetic rather than a result.
  - The sink lags the source, so `tau_los` starts enormous and falls towards τ
    from above.

They meet at equilibrium. Watching the gap close is the cheapest way to judge
how much longer a run needs, well before either number can be trusted on its
own.

Equilibrium itself is called on two measures, the source-loss imbalance and the
drift of the burden. Both are reported, because a tracer can pass one and fail
the other. An imbalance near zero at a single output time says little while the
burden is still climbing.

This script needs only the budget table, which is written every
`dt_tracer_budget` as the run proceeds. So it can settle whether a run needs
extending before anyone spends time on the 3-D output.
=#

import Printf: @printf, @sprintf

const SECONDS_PER_YEAR = 365.25 * 86400

"""
    TracerBudgetSeries

Time series of one tracer's budget, with the source region it belongs to.
"""
struct TracerBudgetSeries
    name::String
    latitude_lower::Float64
    latitude_upper::Float64
    height_lower::Float64
    height_upper::Float64
    time::Vector{Float64}
    burden::Vector{Float64}
    source::Vector{Float64}
    loss::Vector{Float64}
end

"""
    read_tracer_budget(path)

Read a tracer-budget table into one [`TracerBudgetSeries`](@ref) per tracer,
keyed by tracer name. `path` may be the CSV file itself or the output
directory containing it.

Rows are appended in time order as the run proceeds, and a restart may repeat
the time it restarted from; repeated times are collapsed, keeping the last row
for each, so that the series is strictly increasing in time.
"""
function read_tracer_budget(path)
    file = isdir(path) ? joinpath(path, "stratospheric_tracer_budget.csv") : path
    isfile(file) || error("No tracer budget table at $file")

    lines = readlines(file)
    length(lines) > 1 || error("Tracer budget table $file has no data rows")

    header = split(lines[1], ',')
    column = Dict(name => i for (i, name) in enumerate(header))
    for required in
        ("time", "tracer", "burden", "source", "loss", "latitude_lower",
        "latitude_upper", "height_lower", "height_upper")
        haskey(column, required) ||
            error("Tracer budget table $file has no `$required` column")
    end

    # Accumulate into per-tracer, per-time entries so that duplicated times
    # from a restart resolve to the last row read for that time.
    records = Dict{String, Dict{Float64, NTuple{3, Float64}}}()
    regions = Dict{String, NTuple{4, Float64}}()
    order = String[]

    for line in Iterators.drop(lines, 1)
        isempty(strip(line)) && continue
        fields = split(line, ',')
        name = String(fields[column["tracer"]])
        if !haskey(records, name)
            records[name] = Dict{Float64, NTuple{3, Float64}}()
            regions[name] = (
                parse(Float64, fields[column["latitude_lower"]]),
                parse(Float64, fields[column["latitude_upper"]]),
                parse(Float64, fields[column["height_lower"]]),
                parse(Float64, fields[column["height_upper"]]),
            )
            push!(order, name)
        end
        records[name][parse(Float64, fields[column["time"]])] = (
            parse(Float64, fields[column["burden"]]),
            parse(Float64, fields[column["source"]]),
            parse(Float64, fields[column["loss"]]),
        )
    end

    series = Dict{String, TracerBudgetSeries}()
    for name in order
        times = sort!(collect(keys(records[name])))
        values = [records[name][t] for t in times]
        series[name] = TracerBudgetSeries(
            name,
            regions[name]...,
            times,
            [v[1] for v in values],
            [v[2] for v in values],
            [v[3] for v in values],
        )
    end
    return (; series, order)
end

"""
    tracer_residence_time(series; window_fraction = 0.25)

Residence time and equilibrium measures of one tracer, averaged over the last
`window_fraction` of its time series.

Returns a NamedTuple with

  - `residence_time`: `burden / source`, in s, and `residence_time_years`.
  - `imbalance`: `(source - loss) / source`, the fraction of the source that
    is not being removed. Zero in equilibrium.
  - `burden_drift`: `(dburden/dt) / source` over the window — the same
    quantity measured from the burden instead of from the sink, and the more
    demanding of the two, since it integrates the imbalance rather than
    sampling it. Zero in equilibrium.
  - `window_start`, `window_end`: the times averaged over, in s.
"""
function tracer_residence_time(series::TracerBudgetSeries; window_fraction = 0.25)
    0 < window_fraction <= 1 ||
        error("window_fraction must be in (0, 1], got $window_fraction")
    n = length(series.time)
    first_index = max(1, n - max(1, ceil(Int, window_fraction * n)) + 1)
    window = first_index:n

    burden = sum(@view series.burden[window]) / length(window)
    source = sum(@view series.source[window]) / length(window)
    loss = sum(@view series.loss[window]) / length(window)

    residence_time = source > 0 ? burden / source : NaN
    residence_time_from_loss = loss > 0 ? burden / loss : NaN
    imbalance = source > 0 ? (source - loss) / source : NaN

    Δt = series.time[n] - series.time[first_index]
    Δburden = series.burden[n] - series.burden[first_index]
    burden_drift = (Δt > 0 && source > 0) ? (Δburden / Δt) / source : NaN

    return (;
        name = series.name,
        latitude_lower = series.latitude_lower,
        latitude_upper = series.latitude_upper,
        height_lower = series.height_lower,
        height_upper = series.height_upper,
        burden,
        source,
        loss,
        residence_time,
        residence_time_years = residence_time / SECONDS_PER_YEAR,
        residence_time_from_loss,
        residence_time_from_loss_years = residence_time_from_loss / SECONDS_PER_YEAR,
        imbalance,
        burden_drift,
        window_start = series.time[first_index],
        window_end = series.time[n],
    )
end

"""
    tracer_residence_time_summary(path; window_fraction = 0.25, tolerance = 0.05)

Residence times of every tracer in the budget table at `path`, printed as a
table and returned as a vector of NamedTuples.

A tracer is marked as equilibrated when both its imbalance and its burden
drift are within `tolerance` of zero. Tracers that are not yet there need a
longer run, not a different analysis: their burdens are still filling up, so
their residence times are underestimates.
"""
function tracer_residence_time_summary(path; window_fraction = 0.25, tolerance = 0.05)
    (; series, order) = read_tracer_budget(path)
    results = [tracer_residence_time(series[name]; window_fraction) for name in order]

    @printf(
        "%-14s %8s %8s %9s %9s %12s %11s %11s %8s %7s\n",
        "tracer", "lat_lo", "lat_hi", "h_lo[km]", "h_hi[km]",
        "burden[kg]", "tau_src[yr]", "tau_los[yr]", "imbal", "drift",
    )
    is_equilibrated(r) =
        isfinite(r.imbalance) &&
        isfinite(r.burden_drift) &&
        abs(r.imbalance) <= tolerance &&
        abs(r.burden_drift) <= tolerance

    for r in results
        height_upper = @sprintf("%.1f", r.height_upper / 1000)
        marker = is_equilibrated(r) ? "" : "  (not equilibrated)"
        @printf(
            "%-14s %8.1f %8.1f %9.1f %9s %12.4e %11.3f %11.3f %8.3f %7.3f %s\n",
            r.name, r.latitude_lower, r.latitude_upper,
            r.height_lower / 1000, height_upper,
            r.burden, r.residence_time_years, r.residence_time_from_loss_years,
            r.imbalance, r.burden_drift, marker,
        )
    end

    unequilibrated = count(!is_equilibrated, results)
    if unequilibrated > 0
        @info "$unequilibrated of $(length(results)) tracers are not yet in \
               equilibrium to within $tolerance; their residence times are lower \
               bounds. Extend the run and rerun this script."
    else
        @info "All $(length(results)) tracers are in equilibrium to within \
               $tolerance."
    end
    return results
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error(
        "Usage: julia post_processing/tracer_residence_times.jl <output_dir_or_csv>",
    )
    tracer_residence_time_summary(ARGS[1])
end
