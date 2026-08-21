#=
Merge stratospheric tracer budget tables across restart segments and members.

    julia --project=.buildkite post_processing/merge_tracer_budgets.jl OUT [OUT...]

Each `OUT` is the base output directory of one run -- the directory holding the
numbered `output_XXXX` subdirectories. Both layouts are searched:

    <base>/output_XXXX/stratospheric_tracer_budget.csv               (standalone)
    <base>/output_XXXX/clima_atmos/stratospheric_tracer_budget.csv   (coupled)

A chained run writes one table per segment, because each launch gets a fresh
`output_XXXX`. Segments also overlap: a job that is resubmitted re-runs from its
last checkpoint, so rows after that checkpoint are written twice. Rows are
therefore deduplicated on `(time, box edges)`, keeping the last one seen, which
is the row from the segment that actually carried the run forward.

Members are merged on the box edges rather than on the tracer name. The names
collide across members -- `y01z01` in member A is a different box from `y01z01`
in member B -- while the edges identify a box uniquely.

The merged table is written to `stratospheric_tracer_budget_merged.csv` in the
current directory, or to the path given by `--output`.

This script uses only the standard library, so it runs in any environment that
has ClimaAtmos's dependencies, or none of them.
=#

const BUDGET_FILE = "stratospheric_tracer_budget.csv"
const OUTPUT_NAME = "stratospheric_tracer_budget_merged.csv"

"""
    budget_files(base_dir)

Every budget table under `base_dir`, ordered by segment number, covering both
the standalone and the coupled output layouts.
"""
function budget_files(base_dir)
    isdir(base_dir) || error("not a directory: $base_dir")
    segments = filter(readdir(base_dir)) do entry
        !isnothing(match(r"^output_\d+$", entry)) && isdir(joinpath(base_dir, entry))
    end
    sort!(segments)   # zero-padded, so lexical order is segment order
    files = String[]
    for segment in segments
        for candidate in (
            joinpath(base_dir, segment, BUDGET_FILE),
            joinpath(base_dir, segment, "clima_atmos", BUDGET_FILE),
        )
            isfile(candidate) && push!(files, candidate)
        end
    end
    # A run that wrote straight into the base directory, rather than into
    # numbered segments, still has a table worth picking up.
    root_file = joinpath(base_dir, BUDGET_FILE)
    isfile(root_file) && push!(files, root_file)
    return files
end

"""
    row_key(fields)

Identity of one budget row: the time and the four box edges. Deliberately not
the tracer name, which is only unique within a member.
"""
row_key(fields) = (fields[1], fields[3], fields[4], fields[5], fields[6])

function merge_budgets(base_dirs; output_path = OUTPUT_NAME)
    header = nothing
    rows = Dict{NTuple{5, String}, Vector{String}}()
    order = NTuple{5, String}[]
    n_files = 0
    n_rows = 0

    for base_dir in base_dirs, file in budget_files(base_dir)
        n_files += 1
        lines = readlines(file)
        isempty(lines) && continue
        file_header = first(lines)
        if isnothing(header)
            header = file_header
        elseif file_header != header
            error(
                "budget tables disagree on their columns, so they cannot be \
                merged:\n  $(file)\n    $(file_header)\n  expected\n    $(header)",
            )
        end
        n_columns = length(split(header, ','))
        for line in Iterators.drop(lines, 1)
            isempty(strip(line)) && continue
            # Converted to `String` rather than left as `SubString` so that the
            # dictionary keys have exactly the declared type.
            fields = String.(split(line, ','))
            length(fields) == n_columns || error(
                "malformed row in $(file) (expected $(n_columns) fields, got \
                $(length(fields))):\n  $(line)",
            )
            key = row_key(fields)
            haskey(rows, key) || push!(order, key)
            rows[key] = fields   # last writer wins: the segment that carried on
            n_rows += 1
        end
    end

    isnothing(header) && error(
        "no $(BUDGET_FILE) found under: $(join(base_dirs, ", "))",
    )

    # Sort by time, then by box, so the table reads as a time series per box.
    sort!(order, by = key -> (parse_or_inf(key[1]), key[2], key[3], key[4], key[5]))

    open(output_path, "w") do io
        println(io, header)
        for key in order
            println(io, join(rows[key], ','))
        end
    end

    @info "Merged tracer budgets" files = n_files rows_read = n_rows unique_rows =
        length(order) output = output_path
    return output_path
end

# Times are written by `write_tracer_budget!` as Float64 seconds. Anything that
# does not parse sorts last rather than bringing the merge down.
parse_or_inf(s) = something(tryparse(Float64, s), Inf)

function main(args)
    output_path = OUTPUT_NAME
    base_dirs = String[]
    i = firstindex(args)
    while i <= lastindex(args)
        if args[i] == "--output"
            i < lastindex(args) || error("--output needs a path")
            output_path = args[i + 1]
            i += 2
        else
            push!(base_dirs, args[i])
            i += 1
        end
    end
    isempty(base_dirs) && error(
        "usage: julia post_processing/merge_tracer_budgets.jl [--output PATH] OUT [OUT...]",
    )
    return merge_budgets(base_dirs; output_path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
