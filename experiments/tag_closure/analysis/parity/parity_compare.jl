#=
Compare two checkouts' `parity_run.jl` output bit for bit.

    julia +1.11 --project=<checkout>/.buildkite parity_compare.jl <dir_a> <dir_b>

Every configuration found in either directory must be in both. For each one,
the field names and the time must agree, and every array of the state and of
the three tendencies must be equal under `isequal`, which tells signed zeros
apart and matches NaNs. `parity_run.jl` already refuses a NaN. The provenance of
both sides is printed. The exit status is 0 only when everything agrees.

The saved time is a ClimaUtilities `ITime`, so that package has to be loadable:
run it from a checkout's `.buildkite` environment.
=#
using Serialization
Base.require(
    Base.PkgId(Base.UUID("b3f4f4ca-9299-4f7f-bd9b-81e1242a7513"), "ClimaUtilities"),
)

a_dir, b_dir = ARGS
files = sort(union(
    filter(endswith(".jls"), readdir(a_dir)),
    filter(endswith(".jls"), readdir(b_dir)),
))
isempty(files) && error("No results in $a_dir or $b_dir")
all_equal = true
for file in files
    println("== ", file)
    if !(isfile(joinpath(a_dir, file)) && isfile(joinpath(b_dir, file)))
        println("   MISSING on one side")
        global all_equal = false
        continue
    end
    a = deserialize(joinpath(a_dir, file))
    b = deserialize(joinpath(b_dir, file))
    println("   a: ", a.provenance)
    println("   b: ", b.provenance)
    same = a.names == b.names && a.t == b.t
    println("   field names and time equal: ", same)
    global all_equal &= same
    groups = [
        (:state, a.state, b.state),
        [
            (k, getproperty(a.tendencies, k), getproperty(b.tendencies, k)) for
            k in keys(a.tendencies)
        ]...,
    ]
    for (label, x_group, y_group) in groups
        if keys(x_group) != keys(y_group)
            println("   $label: components differ")
            global all_equal = false
            continue
        end
        for key in keys(x_group)
            x, y = getproperty(x_group, key), getproperty(y_group, key)
            equal = size(x) == size(y) && isequal(x, y)
            global all_equal &= equal
            detail = equal ? "" :
                size(x) != size(y) ? "  sizes $(size(x)) and $(size(y))" :
                "  max abs difference $(maximum(abs, x .- y)), differing entries $(count(!, isequal.(x, y)))"
            println("   ", rpad("$label.$key", 16), equal ? "bit for bit" : "DIFFERENT", detail)
        end
    end
end
println(all_equal ? "ALL BIT FOR BIT" : "DIFFERENCES FOUND")
exit(all_equal ? 0 : 1)
