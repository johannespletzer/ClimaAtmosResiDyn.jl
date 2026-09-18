#=
V5, restart equivalence: compare `v5_c5_restarted` with `v5_c5_continuous`.

    julia +1.11 --project=<checkout>/.buildkite \
        experiments/tag_closure/analysis/v5_compare.jl \
        $SCRATCH/tag_closure/output/v5_c5_continuous/output_active \
        $SCRATCH/tag_closure/output/v5_c5_restarted/output_active

It checks three things and exits non-zero when one fails:

 1. The states at the end, `day1.0.hdf5` in each directory. Every field in
    `Y.c` and `Y.f` must be identical under `isequal`, the tags and the
    records included. `isequal` tells signed zeros apart and matches NaN with
    NaN, as the parity checks do.
 2. The closure table's rows after the restart. Every column must be the same
    text, except the three spin-up columns. The restarted run takes its
    spin-up reference again an hour after the restart, so those differ by
    design. The tables print each value in full, so the same text is the same
    number.
 3. The audit table's rows after the restart, every column but
    `repair_moved` and `repair_moved_relative`. Those count what the repair
    moved since the start of the run segment, so they start over at the
    restart by design.

The guard's own result is read from the restarted job's log, not here: with
the same settings it must pass without a warning.
=#

import ClimaComms
import ClimaCore: InputOutput, Fields

const SPIN_UP_COLUMNS =
    ("residual_at_spin_up", "residual_since_spin_up", "relative_since_spin_up")
const SEGMENT_COLUMNS = ("repair_moved", "repair_moved_relative")
const RESTART_TIME = 43200.0

function read_state(dir)
    path = joinpath(dir, "day1.0.hdf5")
    isfile(path) || error("No final checkpoint: $path")
    reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
    try
        return InputOutput.read_field(reader, "Y")
    finally
        close(reader)
    end
end

function compare_states(Y_continuous, Y_restarted)
    all_equal = true
    for part in (:c, :f)
        continuous = getproperty(Y_continuous, part)
        restarted = getproperty(Y_restarted, part)
        names_c = propertynames(continuous)
        names_r = propertynames(restarted)
        if names_c != names_r
            println("DIFFERENT FIELDS in Y.$part: $names_c against $names_r")
            all_equal = false
            continue
        end
        for name in names_c
            a = parent(getproperty(continuous, name))
            b = parent(getproperty(restarted, name))
            same = isequal(a, b)
            all_equal &= same
            detail = same ? "" : "  largest difference $(maximum(abs, a .- b))"
            println(rpad("Y.$part.$name", 32), same ? "bit for bit" : "DIFFERS", detail)
        end
    end
    return all_equal
end

# The rows of a table after the restart, keyed by time, as text.
function rows_after_restart(path)
    lines = readlines(path)
    header = split(first(lines), ",")
    time_column = findfirst(==("time"), header)
    rows = Dict{String, Vector{SubString{String}}}()
    for line in lines[2:end]
        fields = split(line, ",")
        parse(Float64, fields[time_column]) > RESTART_TIME || continue
        rows[fields[time_column]] = fields
    end
    return header, rows
end

function compare_table(name, dir_continuous, dir_restarted; skip = ())
    path_c = joinpath(dir_continuous, name)
    path_r = joinpath(dir_restarted, name)
    for path in (path_c, path_r)
        isfile(path) || (println("MISSING $path"); return false)
    end
    header_c, rows_c = rows_after_restart(path_c)
    header_r, rows_r = rows_after_restart(path_r)
    header_c == header_r || (println("$name: DIFFERENT COLUMNS"); return false)
    times = sort!(collect(keys(rows_c)); by = t -> parse(Float64, t))
    if Set(times) != Set(keys(rows_r))
        println("$name: DIFFERENT TIMES after the restart")
        return false
    end
    all_equal = true
    for (i, column) in enumerate(header_c)
        column in skip && continue
        differing = [t for t in times if rows_c[t][i] != rows_r[t][i]]
        same = isempty(differing)
        all_equal &= same
        detail = same ? "" : "  at t = $(join(differing, ", "))"
        println(rpad("$name: $column", 56), same ? "same" : "DIFFERS", detail)
    end
    println("$name: $(length(times)) rows after t = $(RESTART_TIME) s")
    return all_equal
end

function main(dir_continuous, dir_restarted)
    println("continuous: $dir_continuous")
    println("restarted:  $dir_restarted")
    states = compare_states(read_state(dir_continuous), read_state(dir_restarted))
    closure = compare_table(
        "energy_source_tag_closure.csv",
        dir_continuous,
        dir_restarted;
        skip = SPIN_UP_COLUMNS,
    )
    audit = compare_table(
        "energy_source_tag_audit.csv",
        dir_continuous,
        dir_restarted;
        skip = SEGMENT_COLUMNS,
    )
    passed = states && closure && audit
    println(passed ? "V5 PASSED" : "V5 FAILED")
    return passed
end

length(ARGS) == 2 ||
    error("Usage: v5_compare.jl <continuous output dir> <restarted output dir>")
main(ARGS[1], ARGS[2]) || exit(1)
