#=
Compare two runs that differ in `FLOAT_TYPE`, from their committed tables.

    julia +1.11 --startup-file=no experiments/tag_closure/analysis/float_type_compare.jl \
        output/c7_sphere_mp output/v3_sphere_float32

The first directory is the reference, the second the run in the smaller float
type. It prints three things (E45):
  - for each table, the largest relative difference after t = 0;
  - the closure residual of both runs in units of the second run's rounding step,
    the gap between two neighbouring floats at its total;
  - for each tag extremum, the largest relative difference over the run.

Values below 1 in size are skipped in the relative differences, because a
relative difference of two numbers near zero says nothing.
=#

const TABLES = (
    "energy_source_tag_closure.csv",
    "energy_source_tag_audit.csv",
    "process_closure.csv",
    "source_tag_extrema.csv",
    "process_record_extrema.csv",
)
const SMALL = 1.0

function read_table(path)
    lines = filter(l -> !isempty(l) && !startswith(l, "#"), readlines(path))
    header = split(lines[1], ",")
    rows = [split(line, ",") for line in lines[2:end]]
    return header, rows
end

number(field) = tryparse(Float64, field)

function relative_difference(x, y)
    size = max(abs(x), abs(y))
    return size < SMALL ? 0.0 : abs(x - y) / size
end

reference, other = ARGS[1], ARGS[2]
other_type = occursin("float32", lowercase(other)) ? Float32 : Float64

println("largest relative difference after t = 0, by table")
for table in TABLES
    header, a = read_table(joinpath(reference, table))
    _, b = read_table(joinpath(other, table))
    length(a) == length(b) || println("  $table: $(length(a)) rows against $(length(b))")
    worst = (0.0, "", NaN)
    for (ra, rb) in zip(a, b), (j, name) in enumerate(header)
        x, y = number(ra[j]), number(rb[j])
        (isnothing(x) || isnothing(y) || number(ra[1]) == 0) && continue
        r = relative_difference(x, y)
        r > worst[1] && (worst = (r, name, number(ra[1])))
    end
    println("  ", rpad(table, 30), round(worst[1]; sigdigits = 2),
        " in ", worst[2], " at t = ", worst[3], " s")
end

println("\nclosure residual in rounding steps of the second run's total")
header, a = read_table(joinpath(reference, "energy_source_tag_closure.csv"))
_, b = read_table(joinpath(other, "energy_source_tag_closure.csv"))
total, residual = findfirst(==("total"), header), findfirst(==("residual"), header)
for (ra, rb) in zip(a, b)
    x_total = other_type(number(rb[total]))
    step = Float64(nextfloat(x_total) - x_total)
    x, y = number(ra[residual]) / step, number(rb[residual]) / step
    println("  t = ", rpad(ra[1], 9), " reference ", rpad(round(x; digits = 2), 9),
        " other ", rpad(round(y; digits = 2), 9), " apart ", round(y - x; digits = 2))
end

println("\nlargest relative difference over the run, by tag extremum")
header, a = read_table(joinpath(reference, "source_tag_extrema.csv"))
_, b = read_table(joinpath(other, "source_tag_extrema.csv"))
for (j, name) in enumerate(header)
    (startswith(name, "min_") || startswith(name, "max_")) || continue
    worst = maximum(zip(a, b)) do (ra, rb)
        number(ra[1]) == 0 ? 0.0 : relative_difference(number(ra[j]), number(rb[j]))
    end
    println("  ", rpad(name, 30), round(worst; sigdigits = 2))
end
