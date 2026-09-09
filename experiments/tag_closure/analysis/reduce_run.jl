#=
Reduce one finished tag-closure run to `operator_residual.csv`.

Run this on Levante against a finished run's `output_dir`, before copying
anything back. It exists because the number phase A turns on is not in the
closure table and the NetCDF never leaves scratch:

  - `gross_relative`, in `water_tag_closure.csv`, is a volume integral of the
    residual with no ledger subtracted.
  - The operator residual is a pointwise maximum of `q_tag_res + Σᵢ q_tag_fix_i`
    over the field, which only the NetCDF diagnostics carry.

Usage:

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/reduce_run.jl <output_dir>

`OUTPUT_DIR` works in place of the argument. The directory is the run's own
output directory, the one `provenance.txt` names, normally
`output/<run>/output_active`.

## What it computes

One row per diagnostic time. The operator residual is the pointwise field

    q_tag_res + Σᵢ q_tag_fix_i

**summed first, then reduced with `max abs`.** The order matters: reducing each
term on its own and adding the scalars is a different and larger number. `i`
runs over the pure region tags only, the same set `q_tag_res` sums, never a tag
carrying a `source`. On `a5_sphere_limiter` that means `q_tag_fix_evap` is read
past even though the run outputs it; including it would add a ledger whose
residual was never in `q_tag_res` to begin with.

`max abs q_tag_res` and the summed ledger go in beside it, so the decomposition
can be checked rather than trusted.

## Reading the two columns against each other

The invariant is an identity, not an inequality: the operator residual is the
residual the run *would* have reported had no correction ever been applied. It
is not reliably smaller than `q_tag_res`, and a check built on that would fire
on almost every run. The partition repair's ledger sums to zero on its
sum-preserving branch and to a positive number on the branch that zeroes a cell
whose negatives outweigh its positives, so the operator residual is usually the
larger of the two. What would be wrong is the two columns moving independently,
or the ledger column being identically zero, which would mean the diagnostic
was never registered.

## Columns

    time                        seconds since the start of the run
    geometry                    `column` or `sphere`, from the run's own config
    remapped                    `true` when the maximum is over a remapped field
    max_abs_operator_residual   max |q_tag_res + Σᵢ q_tag_fix_i|   (kg/kg)
    max_abs_q_tag_res           max |q_tag_res|                    (kg/kg)
    max_abs_ledger_sum          max |Σᵢ q_tag_fix_i|               (kg/kg)
    max_abs_q_tag_fix_<name>    one per pure region tag            (kg/kg)

`remapped` is the honest part. On a sphere the NetCDF writer has already
bilinearly interpolated onto a lat-lon grid, so the maximum is over the remapped
field and not over the model's own columns, and a sphere number is therefore not
the same kind of quantity as a column number. Phase A's ladder is columns, where
this is false and the maximum is over the model's own levels.

**This script has never been executed.** There is no Julia in the container it
was written in. `analysis/selftest.jl` builds synthetic input with values worked
out by hand and asserts the results; run that first.
=#

import NCDatasets
import YAML

const REGION_LEDGER_PREFIX = "q_tag_fix_"

"""
    run_config(output_dir)

The merged configuration snapshot the run wrote beside its output, as a `Dict`.

The snapshot rather than the file in `configs/` because it pins what actually
ran, including every default in force at the time. Errors when it is missing,
which means either the wrong directory or a run that died before writing it.
"""
function run_config(output_dir)
    snapshots = filter(readdir(output_dir)) do name
        endswith(name, ".yml") && !startswith(name, ".")
    end
    isempty(snapshots) && error(
        "No configuration snapshot (*.yml) in $output_dir. Point this at the \
        run's own output directory, the one `provenance.txt` names, normally \
        output/<run>/output_active.",
    )
    length(snapshots) > 1 && @warn "More than one snapshot; using the first" snapshots
    return YAML.load_file(joinpath(output_dir, first(snapshots)))
end

"""
    region_tag_names(config)

Names of the pure region water tags: those with a `region` and no `source`.

This is the set `q_tag_res` sums over, so it is also the set whose ledgers the
operator residual adds back. A tag carrying a `source` is not a member of the
partition, and its ledger cancels a residual that was never in `q_tag_res`.
"""
function region_tag_names(config, key = "water_tracers")
    tags = get(config, key, nothing)
    isnothing(tags) && error(
        "This run configured no `$key`, so there is nothing of that family to \
        reduce. A timing control is one such run.",
    )
    names = [
        String(tag["name"]) for tag in tags if
        haskey(tag, "region") && !haskey(tag, "source")
    ]
    isempty(names) && error(
        "No pure region tag in `$key`. The closure check would not have \
        started either.",
    )
    return names
end

"""
    all_tag_names(config, key)

Every tag of a family, region and source alike.

Phase C needs the source-labelled ones too. `e_src_res` is the parent minus the
sum of the *pure region* tags, so a source tag going negative never enters it
and has to be watched directly.
"""
all_tag_names(config, key) =
    [String(tag["name"]) for tag in get(config, key, [])]

"""
    geometry_of(config)

`(geometry, remapped)`. A column is finite-difference in the vertical with no
horizontal remapping, so its maxima are over the model's own levels. Anything
else is written through a bilinear remap onto lat-lon, and a maximum there is
over the remapped field.
"""
function geometry_of(config)
    geometry = String(get(config, "config", "sphere"))
    return (geometry, geometry != "column")
end

"""
    find_variable(output_dir, short_name)

Locate `short_name` among the run's NetCDF files, as `(path, variable_name)`.

Every `.nc` file in the directory is opened and searched, rather than the file
name being predicted. ClimaDiagnostics decorates an output name with its period
and reduction, and this way the script does not have to know that scheme or
track a change to it. A variable matches when it is the short name exactly or
the short name followed by an underscore.
"""
function find_variable(output_dir, short_name)
    for name in sort(filter(f -> endswith(f, ".nc"), readdir(output_dir)))
        path = joinpath(output_dir, name)
        match = NCDatasets.NCDataset(path, "r") do ds
            candidates = filter(collect(keys(ds))) do key
                key == short_name || startswith(key, short_name * "_")
            end
            isempty(candidates) ? nothing : first(sort(candidates))
        end
        isnothing(match) || return (path, match)
    end
    return nothing
end

"""
    read_field(output_dir, short_name)

Read one diagnostic as `(times, data)`, with time the first axis of `data`.

`data` is flattened to `(time, points)`, because every reduction here is over
the whole field and the spatial layout does not matter to a maximum.
"""
function read_field(output_dir, short_name)
    located = find_variable(output_dir, short_name)
    isnothing(located) && error(
        "Diagnostic `$short_name` is in none of the NetCDF files in \
        $output_dir. Every configuration in this series lists it explicitly \
        under `diagnostics:`; a run whose config did not is not reducible.",
    )
    path, varname = located
    return NCDatasets.NCDataset(path, "r") do ds
        var = ds[varname]
        dims = NCDatasets.dimnames(var)
        time_axis = findfirst(==("time"), dims)
        isnothing(time_axis) && error(
            "`$varname` in $path has no time dimension; dims are $dims.",
        )
        times = map(Float64, ds["time"][:])
        raw = var[:]
        # Move time to the front, then collapse everything else. `missing`
        # becomes `NaN` so a masked point cannot silently win a maximum.
        moved = permutedims(raw, [time_axis; setdiff(1:ndims(raw), time_axis)])
        flat = reshape(moved, length(times), :)
        return (times, map(v -> ismissing(v) ? NaN : Float64(v), flat))
    end
end

"""
    max_abs(row)

`maximum(abs, row)`, with `NaN` treated as absent rather than as the winner.

A remapped sphere field carries `NaN` outside the domain, and `maximum` would
otherwise return `NaN` for every time and hide the measurement.
"""
function max_abs(row)
    best = 0.0
    seen = false
    for value in row
        isfinite(value) || continue
        seen = true
        best = max(best, abs(value))
    end
    return seen ? best : NaN
end

"""
    reduce_run(output_dir)

Compute the operator residual table. Returns `(header, rows, metadata)`.
"""
function reduce_run(output_dir)
    config = run_config(output_dir)
    regions = region_tag_names(config, "water_tracers")
    geometry, remapped = geometry_of(config)

    times, residual = read_field(output_dir, "q_tag_res")
    ledgers = map(regions) do name
        ledger_times, ledger = read_field(output_dir, REGION_LEDGER_PREFIX * name)
        ledger_times == times || error(
            "`$(REGION_LEDGER_PREFIX * name)` is sampled at different times \
            than `q_tag_res`. The operator residual is a pointwise sum, so the \
            two have to be written on the same schedule. Give them one \
            `diagnostics:` entry, or the same `period`.",
        )
        size(ledger) == size(residual) || error(
            "`$(REGION_LEDGER_PREFIX * name)` has shape $(size(ledger)) against \
            `q_tag_res`'s $(size(residual)).",
        )
        return ledger
    end

    header = [
        "time",
        "geometry",
        "remapped",
        "max_abs_operator_residual",
        "max_abs_q_tag_res",
        "max_abs_ledger_sum",
        ["max_abs_" * REGION_LEDGER_PREFIX * name for name in regions]...,
    ]

    rows = map(eachindex(times)) do index
        residual_row = view(residual, index, :)
        ledger_rows = [view(ledger, index, :) for ledger in ledgers]
        # Sum the fields pointwise first, then reduce. Reducing each term on
        # its own and adding the scalars is a different, larger number.
        ledger_sum = reduce(+, ledger_rows)
        operator = residual_row .+ ledger_sum
        return Any[
            times[index],
            geometry,
            remapped,
            max_abs(operator),
            max_abs(residual_row),
            max_abs(ledger_sum),
            [max_abs(row) for row in ledger_rows]...,
        ]
    end

    metadata = (; geometry, remapped, regions, job_id = get(config, "job_id", "unknown"))
    return (header, rows, metadata)
end

"""
    write_operator_residual(output_dir, header, rows, metadata)

Write `operator_residual.csv` into the run directory.

The comment block above the header records what the numbers are of, because the
file is copied out of the run directory and read months later beside others.
`readdlm(path, ','; comments = true)` skips it.
"""
function write_operator_residual(output_dir, header, rows, metadata)
    path = joinpath(output_dir, "operator_residual.csv")
    open(path, "w") do io
        println(io, "# operator_residual.csv, from analysis/reduce_run.jl")
        println(io, "# run: $(metadata.job_id)")
        println(io, "# generated: $(round(Int, time())) (unix)")
        println(io, "# geometry: $(metadata.geometry)")
        println(io, "# region tags summed: $(join(metadata.regions, ", "))")
        if metadata.remapped
            println(
                io,
                "# NOTE: this is a sphere. The NetCDF writer bilinearly remaps \
                to lat-lon, so",
            )
            println(
                io,
                "# every maximum here is over the remapped field, not over the \
                model's own columns.",
            )
        else
            println(
                io,
                "# Column geometry: no horizontal remapping, so the maxima \
                are over the model's own levels.",
            )
        end
        println(
            io,
            "# operator residual = max |q_tag_res + sum of the region \
            ledgers|, summed then reduced.",
        )
        println(io, join(header, ","))
        for row in rows
            println(io, join(row, ","))
        end
    end
    return path
end

"""
    min_over(row)

`minimum(row)` with `NaN` treated as absent. The minimum of a source tag over
time is the number phase C watches: a negative value invalidates the
amount-of-energy reading of that tag for as long as it lasts, and `e_src_res`
will not show it.
"""
function min_over(row)
    best = Inf
    for value in row
        isfinite(value) || continue
        best = min(best, value)
    end
    return isfinite(best) ? best : NaN
end

"""
    max_over(row)

`maximum(row)`, with `NaN` treated as absent.
"""
function max_over(row)
    best = -Inf
    for value in row
        isfinite(value) || continue
        best = max(best, value)
    end
    return isfinite(best) ? best : NaN
end

"""
    reduce_energy_tags(output_dir)

`e_tag_res` reduced to `max abs` per time, for a run carrying `energy_tracers`.

There is no ledger for this family. Nothing corrects the energy tags, so no
`q_tag_fix` analogue exists and there is no operator-residual subtraction to
make. This table is the residual field's own magnitude, which the closure
table's volume integral does not give.
"""
function reduce_energy_tags(output_dir)
    config = run_config(output_dir)
    region_tag_names(config, "energy_tracers")
    geometry, remapped = geometry_of(config)
    times, residual = read_field(output_dir, "e_tag_res")
    header = ["time", "geometry", "remapped", "max_abs_e_tag_res"]
    rows = [
        Any[times[i], geometry, remapped, max_abs(view(residual, i, :))] for
        i in eachindex(times)
    ]
    return (header, rows, (; geometry, remapped, job_id = get(config, "job_id", "unknown")))
end

"""
    reduce_source_tags(output_dir)

Per time: `max abs e_src_res`, and the minimum and maximum of **every** source
tag, region-labelled and source-labelled alike.

The minima are the point. `e_src_res` is the parent minus the sum of the pure
region tags, so a source-labelled tag going negative never enters it, and a
negative region-tag error can be cancelled by a positive one elsewhere. The
family has no rescale and no partition repair, so nothing stops a tag going
negative and staying there, and a negative tag invalidates the
amount-of-energy reading for as long as it lasts.
"""
function reduce_source_tags(output_dir)
    config = run_config(output_dir)
    region_tag_names(config, "energy_source_tags")
    names = all_tag_names(config, "energy_source_tags")
    geometry, remapped = geometry_of(config)

    times, residual = read_field(output_dir, "e_src_res")
    fields = map(names) do name
        field_times, field = read_field(output_dir, "e_src_" * name)
        field_times == times || error(
            "`e_src_$name` is sampled at different times than `e_src_res`; \
            give them the same `period`.",
        )
        return field
    end

    header = vcat(
        ["time", "geometry", "remapped", "max_abs_e_src_res"],
        ["min_e_src_" * name for name in names],
        ["max_e_src_" * name for name in names],
    )
    rows = map(eachindex(times)) do i
        return vcat(
            Any[times[i], geometry, remapped, max_abs(view(residual, i, :))],
            [min_over(view(field, i, :)) for field in fields],
            [max_over(view(field, i, :)) for field in fields],
        )
    end
    return (header, rows, (; geometry, remapped, job_id = get(config, "job_id", "unknown")))
end

"""
    write_table(output_dir, stem, header, rows, metadata, note)

Write one reduced table with the provenance block above its header.

`stem` rather than `basename`, which would shadow `Base.basename` inside this
function for no gain.
"""
function write_table(output_dir, stem, header, rows, metadata, note)
    path = joinpath(output_dir, stem * ".csv")
    open(path, "w") do io
        println(io, "# $stem.csv, from analysis/reduce_run.jl")
        println(io, "# run: $(metadata.job_id)")
        println(io, "# generated: $(round(Int, time())) (unix)")
        println(io, "# geometry: $(metadata.geometry)")
        if metadata.remapped
            println(
                io,
                "# NOTE: sphere. The NetCDF writer bilinearly remaps to \
                lat-lon, so every",
            )
            println(
                io,
                "# reduction here is over the remapped field, not over the \
                model's own columns.",
            )
        else
            println(
                io,
                "# Column geometry: no horizontal remapping, so the \
                reductions are over the model's own levels.",
            )
        end
        println(io, "# " * note)
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
        "No output directory given. Pass the run's output directory as the \
        first argument, or set OUTPUT_DIR.",
    )
    isdir(output_dir) || error("Not a directory: $output_dir")

    config = run_config(output_dir)
    written = String[]
    remapped = false

    # Whichever families the run configured. A timing control configures none
    # and is not reduced, which is not an error.
    if !isnothing(get(config, "water_tracers", nothing))
        header, rows, metadata = reduce_run(output_dir)
        remapped |= metadata.remapped
        push!(
            written,
            write_operator_residual(output_dir, header, rows, metadata),
        )
        isempty(rows) || @info "operator residual" first = rows[1] last = rows[end]
    end
    if !isnothing(get(config, "energy_tracers", nothing))
        header, rows, metadata = reduce_energy_tags(output_dir)
        remapped |= metadata.remapped
        push!(
            written,
            write_table(
                output_dir, "energy_tag_residual", header, rows, metadata,
                "max |e_tag_res| per time. This family has no ledger, so there \
                is no operator-residual subtraction to make.",
            ),
        )
        isempty(rows) || @info "energy tag residual" first = rows[1] last = rows[end]
    end
    if !isnothing(get(config, "energy_source_tags", nothing))
        header, rows, metadata = reduce_source_tags(output_dir)
        remapped |= metadata.remapped
        push!(
            written,
            write_table(
                output_dir, "source_tag_extrema", header, rows, metadata,
                "max |e_src_res| and the min and max of every tag. e_src_res \
                covers the region tags only, so a source tag going negative \
                shows up in the minima and nowhere else.",
            ),
        )
        isempty(rows) || @info "source tag extrema" first = rows[1] last = rows[end]
    end

    if isempty(written)
        @info "Nothing to reduce: this run configured no tag family. A timing \
               control is one such run."
    else
        @info "Wrote" written
    end
    remapped && @warn "Sphere geometry: every reduction is over the bilinearly \
                       remapped lat-lon field rather than the model's own \
                       columns. Do not set it beside a column number as though \
                       they were the same."
    return written
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
