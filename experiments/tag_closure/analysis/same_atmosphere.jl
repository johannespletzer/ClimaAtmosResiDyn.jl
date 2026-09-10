#=
Whether two runs carry the same atmosphere, to the last bit.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/same_atmosphere.jl <run A> <run B> [short_name]

Each run argument is a run's output directory, the one that holds its NetCDF
diagnostics. The script compares one model-state diagnostic, `ta` by default,
at every sampled time and every point. It exits non-zero unless the two are
identical, NaNs included.

It was written for the two C4 runs, which differ only in
`energy_source_tag_offset`. The model never sees that offset, so their
atmospheres must match exactly, and `ta` depends on everything else in the
state. Identical values are the evidence that the offset reaches the tags and
nothing else.
=#

import NCDatasets

"""
    diagnostic_file(dir, short_name)

The one NetCDF file in `dir` that holds `short_name`, such as `ta_1h_inst.nc`.
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
    read_diagnostic(path, short_name)

The raw time axis and values of `short_name` in the file at `path`, without any
scale, offset or fill-value handling, so that the comparison is of the bits the
run wrote.
"""
read_diagnostic(path, short_name) =
    NCDatasets.NCDataset(path, "r") do ds
        (Array(ds["time"].var), Array(ds[short_name].var))
    end

"""
    same_atmosphere(dir_a, dir_b, short_name = "ta")

Compare `short_name` between two runs and report. Returns whether every value
at every time is identical.
"""
function same_atmosphere(dir_a, dir_b, short_name = "ta")
    time_a, values_a = read_diagnostic(diagnostic_file(dir_a, short_name), short_name)
    time_b, values_b = read_diagnostic(diagnostic_file(dir_b, short_name), short_name)
    time_a == time_b ||
        error("The two runs sampled `$short_name` at different times.")
    size(values_a) == size(values_b) ||
        error(
            "`$short_name` has shape $(size(values_a)) in one run and $(size(values_b)) in the other.",
        )
    identical = isequal(values_a, values_b)
    largest = maximum(abs, values_a .- values_b)
    println("$short_name over $(length(time_a)) samples of $(size(values_a)):")
    println("  ", identical ? "identical, every value" : "DIFFERENT")
    println("  largest absolute difference: $largest")
    return identical
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 3) || error(
        "Usage: same_atmosphere.jl <run A output dir> <run B output dir> [short_name]",
    )
    same_atmosphere(ARGS...) || exit(1)
end
