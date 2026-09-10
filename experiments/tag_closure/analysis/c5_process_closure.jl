#=
C5's per-process reading of the energy source tags, from one run's output.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/c5_process_closure.jl <output_dir>

`<output_dir>` is the run's own output directory, the one that holds its NetCDF
diagnostics, its configuration and `energy_source_tag_closure.csv`. The script
expects the C5 tag layout:

  - pure region tags;
  - one `new_<region>` tag per region, which follows every process
    (`source: all`) inside that region and starts at zero;
  - one tag per process.

It writes `process_closure.csv` into that directory, one row per sample, and on
a column also `cloud_top.csv`, one row per level at the last sample. It prints
a summary.

The columns of `process_closure.csv`:

  - `form_a_max` and `form_a_relative`: the new energy split by region against
    the same energy split by process, `Σ new_<region> - Σ <process>`. The first
    is the largest absolute pointwise difference in J/kg, the second that over
    the largest `Σ new_<region>` at the same sample, zero where both are zero.
    The two sides are separate tags that obey the same rule, so the difference
    is rounding as long as that rule is linear in the tags: no tag clamped, no
    repair, no limiter acting on each tag on its own, and a tag for every
    process that fires. Interpolation to a lat-lon grid is linear, so the
    identity survives it.
  - `initial_min_<region>`: the smallest value of `<region> - new_<region>`, the
    energy that was in the region at the start, in J/kg. Where it is negative,
    the tags that carry a source claim more than the region tag holds.
  - On a column, `initial_<region>`: the column integral of that energy, in
    J/m². It gains nothing, so it may only fall.
  - On a column, `energy_change`, `records` and `form_b`: the change in the
    column integral of `ρe_tot` since the first sample, the sum of the column
    integrals of the energy process records, and the first minus the second,
    all in J/m². The difference is what no record sees.

A column integral is the sum of `rhoa × value × Δz` over the levels, which is
the model's own quadrature on an unstretched column. The script refuses a
stretched column, and checks the sum against the closure table's native
integral of the tags' total at the first sample.
=#

import NCDatasets

"""
    diagnostic_file(dir, short_name)

The one NetCDF file in `dir` that holds `short_name`, such as
`e_src_rad_1h_inst.nc`.
"""
function diagnostic_file(dir, short_name)
    matches = filter(
        name -> startswith(name, short_name * "_") && endswith(name, ".nc"),
        readdir(dir),
    )
    length(matches) == 1 || error(
        "Expected one `$(short_name)_*.nc` in $dir, found $(length(matches)).",
    )
    return joinpath(dir, only(matches))
end

"""
    read_field(dir, short_name)

The values of `short_name` with time as the last dimension, whatever order the
writer used, and the file's raw time axis and `z`.
"""
read_field(dir, short_name) =
    NCDatasets.NCDataset(diagnostic_file(dir, short_name), "r") do ds
        variable = ds[short_name]
        names = collect(NCDatasets.dimnames(variable))
        order = [findall(!=("time"), names); findfirst(==("time"), names)]
        values = permutedims(Array(variable.var), order)
        (; values, time = Array(ds["time"].var), z = Array(ds["z"].var))
    end

# Names from files `<prefix><name>_<period>_inst.nc`.
function names_with_prefix(dir, prefix)
    names = String[]
    for file in readdir(dir)
        m = match(Regex("^$(prefix)(.+?)_[0-9]+[a-z]+_inst\\.nc\$"), file)
        isnothing(m) || push!(names, m.captures[1])
    end
    return names
end

# The tags a run wrote. The residual and any repair ledger are not tags.
tag_names(dir) = filter(
    name -> name != "res" && !startswith(name, "fix_"),
    names_with_prefix(dir, "e_src_"),
)
record_names(dir) = names_with_prefix(dir, "e_prc_")

# The offset from the run's own configuration, 0 without one.
function offset(dir)
    for config in filter(endswith(".yml"), readdir(dir))
        for line in eachline(joinpath(dir, config))
            m = match(r"^energy_source_tag_offset:\s*([-+0-9.eE]+)\s*$", line)
            isnothing(m) || return parse(Float64, m.captures[1])
        end
    end
    return 0.0
end

# One column of the closure table, by header name.
function closure_column(dir, name)
    lines = filter(
        !startswith("#"),
        readlines(joinpath(dir, "energy_source_tag_closure.csv")),
    )
    header = split(first(lines), ',')
    index = findfirst(==(name), header)
    isnothing(index) && error("No `$name` in the closure table of $dir.")
    return [parse(Float64, split(line, ',')[index]) for line in lines[2:end]]
end

slices(field) = eachslice(field; dims = ndims(field))
ratio(a, b) = iszero(b) ? zero(a) : a / b

function write_csv(path, header, columns)
    open(path, "w") do io
        println(io, join(header, ','))
        for row in zip(columns...)
            println(io, join(row, ','))
        end
    end
    return nothing
end

function main(dir)
    names = tag_names(dir)
    new = filter(startswith("new_"), names)
    isempty(new) && error("No `new_<region>` tags in $dir: not a C5 layout.")
    regions = [chopprefix(name, "new_") for name in new]
    all(in(names), regions) ||
        error("Every `new_<region>` tag needs its region tag in $dir.")
    processes = setdiff(names, [new; regions])
    c = offset(dir)

    fields = Dict(name => read_field(dir, "e_src_" * name) for name in names)
    value(name) = fields[name].values
    time = fields[first(names)].time
    z = fields[first(names)].z
    residual = read_field(dir, "e_src_res").values
    column = ndims(residual) == 2

    new_sum = sum(value("new_" * r) for r in regions)
    process_sum = sum(value(p) for p in processes)
    gap = new_sum .- process_sum
    form_a_max = [maximum(abs, g) for g in slices(gap)]
    new_scale = [maximum(abs, s) for s in slices(new_sum)]
    form_a_relative = ratio.(form_a_max, new_scale)

    initial = Dict(r => value(r) .- value("new_" * r) for r in regions)
    initial_min =
        Dict(r => [minimum(s) for s in slices(initial[r])] for r in regions)

    header = ["time", "form_a_max", "form_a_relative"]
    columns = Any[time, form_a_max, form_a_relative]
    for r in regions
        push!(header, "initial_min_$r")
        push!(columns, initial_min[r])
    end

    println("run: $dir")
    println(
        "offset $c J/kg; regions $(join(regions, ", ")); processes $(join(processes, ", "))",
    )
    println("form A, new energy by region against by process:")
    worst = argmax(form_a_max)
    at = argmax(abs.(selectdim(gap, ndims(gap), worst)))
    where = column ? "z = $(z[at[1]]) m" : "grid index $(Tuple(at))"
    println(
        "  largest pointwise gap $(form_a_max[worst]) J/kg, at t = $(time[worst]) s, $where",
    )
    println(
        "  there: new by region $(selectdim(new_sum, ndims(gap), worst)[at]), by process $(selectdim(process_sum, ndims(gap), worst)[at])",
    )
    println("  largest relative gap $(maximum(form_a_relative))")
    println("  largest gap by hour: ", join(round.(form_a_max; sigdigits = 3), " "))
    # What each process record holds at that point, to tell which process gave
    # the tags energy that no process tag follows.
    for p in record_names(dir)
        record = read_field(dir, "e_prc_" * p).values
        println("  record $p there: $(selectdim(record, ndims(record), worst)[at]) J/kg")
    end
    for r in regions
        println("  initial energy of $r: smallest value $(minimum(initial_min[r])) J/kg")
    end

    # With the repair on, each tag's ledger holds what the repair added to it.
    # Taking the ledgers back out gives form A as the rule and the transport
    # alone would have it, to first order, since a repaired value also fed the
    # shares after it.
    fixes = filter(startswith("fix_"), names_with_prefix(dir, "e_src_"))
    if !isempty(fixes)
        fix(name) = read_field(dir, "e_src_fix_" * name).values
        unrepaired =
            sum(value("new_" * r) .- fix("new_" * r) for r in regions) .-
            sum(value(p) .- fix(p) for p in processes)
        form_a_unrepaired = [maximum(abs, g) for g in slices(unrepaired)]
        push!(header, "form_a_max_unrepaired")
        push!(columns, form_a_unrepaired)
        println(
            "  with the repair's ledgers taken back out: largest gap $(maximum(form_a_unrepaired)) J/kg",
        )
        println("the repair's ledgers over the run, J/kg:")
        for name in names
            ledger = fix(name)
            println("  ", rpad(name, 18), minimum(ledger), "   ", maximum(ledger))
        end
    end
    println("tag minima and maxima over the run, J/kg:")
    for name in names
        println("  ", rpad(name, 18), minimum(value(name)), "   ", maximum(value(name)))
    end

    if column
        rhoa = read_field(dir, "rhoa").values
        Δz = z[2] - z[1]
        all(d -> isapprox(d, Δz; rtol = 1e-10), diff(z)) || error(
            "The column in $dir is stretched; the Δz quadrature does not hold.",
        )
        integral(x) = vec(sum(rhoa .* x; dims = 1)) .* Δz

        total = residual .+ sum(value(r) for r in regions)
        native = closure_column(dir, "total")
        check = abs(integral(total)[1] - native[1]) / abs(native[1])
        println(
            "column quadrature against the closure table at the first sample: relative difference $check",
        )

        energy = integral(total) .- c .* integral(one.(rhoa))
        energy_change = energy .- energy[1]
        records = record_names(dir)
        recorded = sum(
            integral(read_field(dir, "e_prc_" * p).values) for p in records
        )
        form_b = energy_change .- recorded

        for r in regions
            column_initial = integral(initial[r])
            push!(header, "initial_$r")
            push!(columns, column_initial)
            println(
                "initial energy of $r, column integral: $(column_initial[1]) to $(column_initial[end]) J/m², largest rise between samples $(maximum(diff(column_initial)))",
            )
        end
        append!(header, ["energy_change", "records", "form_b"])
        append!(columns, [energy_change, recorded, form_b])
        println(
            "form B, records ($(join(records, ", "))) against the change in ρe_tot, J/m²:",
        )
        for p in records
            println(
                "  record $p at the last sample: $(integral(read_field(dir, "e_prc_" * p).values)[end])",
            )
        end
        println(
            "  at the last sample: change $(energy_change[end]), records $(recorded[end]), difference $(form_b[end])",
        )

        # The last sample, level by level, to read radiation's cooling beside
        # the tag that says how much of the energy came in through radiation.
        radiation = read_field(dir, "e_prc_radiation").values[:, end]
        rad_tag = value("rad")[:, end]
        total_now = total[:, end]
        write_csv(
            joinpath(dir, "cloud_top.csv"),
            ["z", "e_prc_radiation", "e_src_rad", "total", "rad_share"],
            [z, radiation, rad_tag, total_now, rad_tag ./ total_now],
        )
        k = argmin(radiation)
        println(
            "where the radiation record is most negative, z = $(z[k]) m, at the last sample:",
        )
        println(
            "  record $(radiation[k]) J/kg; rad tag $(rad_tag[k]) J/kg; tags' total $(total_now[k]) J/kg; share $(rad_tag[k] / total_now[k])",
        )
        println(
            "  over the column at the last sample: rad tag $(minimum(rad_tag)) to $(maximum(rad_tag)) J/kg, record $(minimum(radiation)) to $(maximum(radiation)) J/kg",
        )
    else
        for p in record_names(dir)
            record = read_field(dir, "e_prc_" * p).values
            println("record $p over the run: $(minimum(record)) to $(maximum(record)) J/kg")
        end
    end

    write_csv(joinpath(dir, "process_closure.csv"), header, columns)
    println("wrote process_closure.csv", column ? " and cloud_top.csv" : "")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    dir = isempty(ARGS) ? get(ENV, "OUTPUT_DIR", "") : only(ARGS)
    isempty(dir) && error("Usage: c5_process_closure.jl <output_dir>")
    main(dir)
end
