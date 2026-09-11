#=
Where D1's closure residual sits, level by level.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/d1_residual_profile.jl <output_dir>

`<output_dir>` is D1's own output directory, with its NetCDF diagnostics. D1 is
a column, so each field is levels by samples.

It prints, at the first minute and at the last sample:
  - the residual `ρ e_src_res Δz` summed over the column, signed and gross, to
    check against the closure table;
  - how the gross splits over height bands: near the ground, below the region
    boundary, at the boundary, in the ice layers above it, and at the top;
  - the level where the residual is largest, and the temperature there.

It prints how the change between those two samples splits over the same bands.
It also prints the column integral of the `lower` tag above 5.6 km, where its
mask is below 0.3%. Only an upward flux can raise it. Sedimentation's upward
branch is one such flux, and vertical diffusion is another.
=#

import NCDatasets

# The one NetCDF file in `dir` that holds `short_name`.
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

# The values of `short_name` with time as the last dimension, and the file's
# raw time axis and `z`.
read_field(dir, short_name) =
    NCDatasets.NCDataset(diagnostic_file(dir, short_name), "r") do ds
        variable = ds[short_name]
        names = collect(NCDatasets.dimnames(variable))
        order = [findall(!=("time"), names); findfirst(==("time"), names)]
        values = permutedims(Array(variable.var), order)
        (; values, time = Array(ds["time"].var), z = Array(ds["z"].var))
    end

const BANDS = (
    ("below 1 km", 0.0, 1000.0),
    ("1 to 4.5 km", 1000.0, 4500.0),
    ("4.5 to 5.5 km, the boundary", 4500.0, 5500.0),
    ("5.5 to 9.5 km, the ice", 5500.0, 9500.0),
    ("above 9.5 km", 9500.0, Inf),
)

function print_bands(column, z)
    gross = sum(abs, column)
    for (name, lower_edge, upper_edge) in BANDS
        in_band = (z .>= lower_edge) .& (z .< upper_edge)
        share = sum(abs, column[in_band]) / gross
        println("  ", rpad(name, 30), round(share; digits = 3))
    end
    return nothing
end

function main(dir)
    residual = read_field(dir, "e_src_res")
    rhoa = read_field(dir, "rhoa").values
    ta = read_field(dir, "ta").values
    lower = read_field(dir, "e_src_lower").values
    z = residual.z
    t = residual.time .- residual.time[1]
    Δz = z[2] - z[1]
    all(d -> isapprox(d, Δz; rtol = 1e-10), diff(z)) ||
        error("The column in $dir is stretched; the Δz quadrature does not hold.")
    layer = rhoa .* residual.values .* Δz
    first_minute = findfirst(>=(60), t)

    for (label, k) in (("first minute", first_minute), ("last sample", length(t)))
        column = layer[:, k]
        println(
            "$label, t = $(t[k]) s: signed $(sum(column)) J/m², gross $(sum(abs, column)) J/m²",
        )
        print_bands(column, z)
        m = argmax(abs.(column))
        println("  largest at z = $(z[m]) m: $(column[m]) J/m², T = $(ta[m, k]) K")
    end

    growth = layer[:, end] .- layer[:, first_minute]
    println(
        "change from the first minute to the last sample: signed $(sum(growth)) J/m², gross $(sum(abs, growth)) J/m²",
    )
    print_bands(growth, z)

    above = z .> 5600
    lower_above = vec(sum(rhoa[above, :] .* lower[above, :]; dims = 1)) .* Δz
    println(
        "`lower` above 5.6 km, column integral: $(lower_above[1]) J/m² at the start, $(lower_above[first_minute]) after the first minute, $(lower_above[end]) at the last sample",
    )
    ice = (z .>= 5000) .& (z .<= 9000)
    println(
        "temperature from 5 to 9 km: $(minimum(ta[ice, 1])) to $(maximum(ta[ice, 1])) K at the start",
    )
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Usage: d1_residual_profile.jl <output_dir>")
    main(only(ARGS))
end
