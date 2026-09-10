#=
Where is `ρe_tot` negative, and by how much?

Run this on Levante against a C0 run's `output_dir`:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/where_negative.jl <output_dir>

`OUTPUT_DIR` works in place of the argument.

## Why this exists

C0 measured `nonpositive_fraction` — 1.0 on the column, 0.4328 on the sphere —
and that is a single number per time. Every magnitude argument in
`C1_reference_shift.md` depends on something the number cannot say: **where**
the field is negative and **how far**. A thin cold layer needs a small shift and
a few percent of suppression. The bulk of the troposphere needs a large one and
the suppression argument bites hard. Nobody has looked.

The committed tables carry per-tag minima and maxima only, so this needs the
NetCDF, which stays on Levante scratch. Hence a script the owner runs there.

## How the field is recovered

**At t = 0 the pure region tags sum to `ρe_tot` exactly** — that is the machine
precision partition every C0 run asserts, `gross_relative` of 2.55e-17 and
2.10e-17. The per-tag diagnostics are `e_src_<name> = ρe_src/ρ`, so summing the
region tags gives specific `e_tot` directly, with no diagnostic anyone had to
configure in advance.

**Only the first sample is used**, and the script says so. After t = 0 that
identity is exactly what stops holding — it is the residual — so a later sample
would give `e_tot` plus an unknown error.

## What it reports

One row per level, into `where_negative.csv`:

    level, z, fraction_negative, minimum, maximum, mean

and, printed:

  - the smallest constant that would make the whole field positive, which is the
    `c` the reference-shift argument turns on;
  - the levels that contain any negative value, and whether they are contiguous;
  - the height at which the field changes sign;
  - the fraction of the whole field that is negative, as a check against the
    closure table's own `nonpositive_fraction`.

Height rather than pressure: pressure is not among the diagnostics these runs
configure, and adding it would mean rerunning. `z` comes free with the field.

**On a sphere every horizontal reduction here is over the bilinearly remapped
lat-lon grid**, not the model's own columns, exactly as `reduce_run.jl` warns.
The vertical structure is unaffected by that, which is what this script is for.

**Never executed.** There is no Julia in the container this was written in.
`analysis/selftest.jl` drives it on synthetic input with hand-derived answers.
=#

import NCDatasets

# The readers, rather than a second copy of them. `reduce_run.jl` runs nothing
# on load: its entry point is behind a `PROGRAM_FILE` guard that does not fire
# when it is included. The `main` defined at the bottom of this file is defined
# after that include and so is the one this script runs.
include(joinpath(@__DIR__, "reduce_run.jl"))

"""
    read_levels(output_dir, short_name)

The first time sample of `short_name` as `(z, data)`, with `data` of shape
`(level, point)`.

`read_field` in the reducer flattens every spatial dimension, because a maximum
does not care about layout. This one keeps the vertical axis, which is the whole
subject here, and flattens only the horizontal.
"""
function read_levels(output_dir, short_name)
    located = find_variable(output_dir, short_name)
    isnothing(located) && error(
        "Diagnostic `$short_name` is in none of the NetCDF files in \
        $output_dir.",
    )
    path, varname = located
    return NCDatasets.NCDataset(path, "r") do ds
        var = ds[varname]
        dims = collect(NCDatasets.dimnames(var))
        time_axis = findfirst(==("time"), dims)
        z_axis = findfirst(name -> startswith(name, "z"), dims)
        isnothing(time_axis) && error("`$varname` has no time dimension: $dims")
        isnothing(z_axis) && error("`$varname` has no vertical dimension: $dims")

        raw = var[ntuple(_ -> Colon(), ndims(var))...]
        others = setdiff(1:ndims(raw), [time_axis, z_axis])
        moved = permutedims(raw, [time_axis; z_axis; others])
        # The first sample only: it is the one where the tags sum to the parent.
        first_sample = selectdim(moved, 1, 1)
        levels = size(first_sample, 1)
        flat = reshape(collect(first_sample), levels, :)
        z = map(Float64, ds[dims[z_axis]][:])
        return (z, map(v -> ismissing(v) ? NaN : Float64(v), flat))
    end
end

"""
    level_stats(row)

`(fraction_negative, minimum, maximum, mean)` over one level, ignoring `NaN`.

A remapped sphere carries `NaN` outside the domain, and counting those as
negative would invent a barrier where there is none.
"""
function level_stats(row)
    finite = [v for v in row if isfinite(v)]
    isempty(finite) && return (NaN, NaN, NaN, NaN)
    negative = count(<(0), finite)
    return (
        negative / length(finite),
        minimum(finite),
        maximum(finite),
        sum(finite) / length(finite),
    )
end

"""
    contiguous(levels)

Whether a sorted vector of level indices has no gaps. A contiguous negative
region is a layer, which a modest shift lifts; a broken one is harder to
describe and harder to argue about.
"""
contiguous(levels) =
    length(levels) < 2 || all(diff(sort(levels)) .== 1)

"""
    sign_change_height(z, fractions)

The height at which the field stops containing negative values, going upward,
or `NaN` when it never does.

Reported as the first level from the top of the negative region rather than by
interpolation: these are level quantities and inventing a sub-level crossing
would be false precision.
"""
function sign_change_height(z, fractions)
    negative_levels = findall(f -> isfinite(f) && f > 0, fractions)
    isempty(negative_levels) && return NaN
    highest = maximum(negative_levels)
    highest == length(z) && return NaN
    return z[highest + 1]
end

"""
    where_negative(output_dir)

Reconstruct specific `e_tot` at t = 0 from the region tags and describe where it
is negative. Returns `(header, rows, summary)`.
"""
function where_negative(output_dir)
    config = run_config(output_dir)
    regions = region_tag_names(config, "energy_source_tags")
    geometry, remapped = geometry_of(config)

    z = nothing
    total = nothing
    for name in regions
        level_z, field = read_levels(output_dir, "e_src_" * name)
        if isnothing(total)
            z, total = level_z, copy(field)
        else
            size(field) == size(total) || error(
                "`e_src_$name` has shape $(size(field)) against the first \
                region tag's $(size(total)).",
            )
            total .+= field
        end
    end
    isnothing(total) && error("No region tags to sum.")

    stats = [level_stats(view(total, level, :)) for level in axes(total, 1)]
    header = ["level", "z", "fraction_negative", "minimum", "maximum", "mean"]
    rows = [
        Any[level, z[level], stats[level][1], stats[level][2], stats[level][3],
            stats[level][4]] for level in eachindex(stats)
    ]

    finite = [v for v in total if isfinite(v)]
    negative_levels = findall(s -> isfinite(s[1]) && s[1] > 0, stats)
    field_minimum = isempty(finite) ? NaN : minimum(finite)
    summary = (;
        job_id = run_name(output_dir),
        geometry,
        remapped,
        regions,
        levels = length(z),
        field_minimum,
        # The smallest constant that makes every point positive. This is the `c`
        # the reference-shift argument turns on, measured rather than inferred
        # from a tag minimum.
        smallest_shift = isfinite(field_minimum) && field_minimum < 0 ?
                         -field_minimum : 0.0,
        fraction_negative = isempty(finite) ? NaN :
                            count(<(0), finite) / length(finite),
        negative_levels,
        contiguous = contiguous(negative_levels),
        sign_change_z = sign_change_height(z, [s[1] for s in stats]),
    )
    return (header, rows, summary)
end

"""
    write_where_negative(output_dir, header, rows, summary)

Write `where_negative.csv` into the run directory, with the provenance block
above the header that the other reduced tables carry.
"""
function write_where_negative(output_dir, header, rows, summary)
    path = joinpath(output_dir, "where_negative.csv")
    open(path, "w") do io
        println(io, "# where_negative.csv, from analysis/where_negative.jl")
        println(io, "# run: $(summary.job_id)")
        println(io, "# geometry: $(summary.geometry)")
        println(io, "# specific e_tot at t = 0, recovered as the sum of the")
        println(io, "# region tags: $(join(summary.regions, " + "))")
        println(
            io,
            "# smallest constant making the field positive: \
            $(summary.smallest_shift) J/kg",
        )
        if summary.remapped
            println(
                io,
                "# NOTE: sphere. Horizontal statistics are over the bilinearly \
                remapped",
            )
            println(
                io,
                "# lat-lon grid, not the model's own columns. The vertical \
                structure is not affected.",
            )
        end
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
    return path
end

function main()
    from_env = get(ENV, "OUTPUT_DIR", "")
    output_dir = !isempty(from_env) ? from_env : (isempty(ARGS) ? "" : first(ARGS))
    isempty(output_dir) && error(
        "No output directory given. Pass a C0 run's output directory as the \
        first argument, or set OUTPUT_DIR.",
    )
    isdir(output_dir) || error("Not a directory: $output_dir")

    header, rows, summary = where_negative(output_dir)
    path = write_where_negative(output_dir, header, rows, summary)

    @info "Specific e_tot at t = 0, from the region tags" summary.job_id summary.geometry
    @info "How negative, and where" levels = summary.levels minimum_J_per_kg =
        summary.field_minimum smallest_shift_J_per_kg = summary.smallest_shift
    @info "Fraction of the field below zero" summary.fraction_negative
    if isempty(summary.negative_levels)
        @info "No level contains a negative value. A reference shift is not \
               needed for this configuration."
    else
        @info "The negative region" levels = summary.negative_levels contiguous =
            summary.contiguous sign_change_z_m = summary.sign_change_z
        summary.contiguous ||
            @warn "The negative levels are not contiguous, so this is not a \
                   single layer and a shift argument phrased as lifting one \
                   does not describe it."
    end
    summary.remapped && @warn "Sphere: horizontal statistics are over the \
                               remapped lat-lon grid. The vertical structure, \
                               which is what this script is for, is unaffected."
    @info "Wrote" path
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
