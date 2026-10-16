#=
Compare the output of two `parity_run.jl` runs, a reference (a) and a
candidate (b), bit for bit.

    julia --project=<env> parity_compare.jl <dir_a> <dir_b> [prefix...]

Every field the reference has must be in the candidate and equal under
`isequal`, in the state and in the three tendencies. `isequal` tells signed
zeros apart, which `==` does not. Fields only the candidate has are the
diagnostic's own, and are listed. A field whose last name component starts
with one of the prefixes, such as `ρq_tag_`, is reported but not judged. Use
the prefixes only when the change is meant to move a diagnostic that both
sides have. Every field a prefix excludes is listed, and a prefix that would
exclude one of the model's own fields (`ρq` matches `ρq_tot`) is refused.

`PARITY_OWN_FIELDS` (set by `parity_job.sh`) says what the fields only the
candidate has must be: `expected` when the two sides ran different
configuration files (b switched a diagnostic on, so b must have fields of its
own; none means the diagnostic never ran), `none` when they ran the same file
(any such field is a fork field on by default), or `any`.

The exit status is 0 only when every judged field agrees and the fields only
in b are as expected.

The saved time is a ClimaUtilities `ITime`, so run this from an environment
that loads ClimaUtilities, such as the one `parity_run.jl` ran in.
=#
using Serialization
Base.require(
    Base.PkgId(Base.UUID("b3f4f4ca-9299-4f7f-bd9b-81e1242a7513"), "ClimaUtilities"),
)

length(ARGS) >= 2 || error("usage: parity_compare.jl <dir_a> <dir_b> [prefix...]")
a_dir, b_dir = ARGS[1], ARGS[2]
prefixes = ARGS[3:end]
own_fields = get(ENV, "PARITY_OWN_FIELDS", "any")
own_fields in ("expected", "none", "any") ||
    error("PARITY_OWN_FIELDS must be expected, none or any")
reported(key) = any(prefix -> startswith(last(split(key, '.')), prefix), prefixes)
# The model's own prognostic and tendency names, which no prefix may exclude.
for prefix in prefixes
    hits = filter(
        n -> startswith(n, prefix),
        ["ρ", "uₕ", "u₃", "ρe_tot", "ρq_tot", "ρq_vap", "ρq_liq", "ρq_ice",
            "ρq_lcl", "ρq_icl", "ρq_rai", "ρq_sno", "ρn_lcl", "ρn_rai", "ρtke", "ρa",
            "mse", "q_tot", "q_lcl",
            "q_icl", "q_rai", "q_sno", "tke", "T_sfc"],
    )
    isempty(hits) ||
        error("prefix $(repr(prefix)) would exclude the model's fields $(join(hits, ", "))")
end
max_abs_difference(x, y) =
    size(x) == size(y) ? maximum(abs, Float64.(x) .- Float64.(y); init = 0.0) :
    "sizes differ"

files_a = filter(endswith(".jls"), readdir(a_dir))
files_b = filter(endswith(".jls"), readdir(b_dir))
isempty(files_a) && error("no results in $a_dir")
all_equal = true
for file in sort(union(files_a, files_b))
    println("== ", file)
    if !(file in files_a && file in files_b)
        println("   MISSING on ", file in files_a ? "b" : "a")
        global all_equal = false
        continue
    end
    a = deserialize(joinpath(a_dir, file))
    b = deserialize(joinpath(b_dir, file))
    println("   a: ", a.provenance)
    println("   b: ", b.provenance)
    if a.t != b.t
        println("   END TIME DIFFERS: ", a.t, " against ", b.t)
        global all_equal = false
    end
    n_judged = 0
    only_b = String[]
    excluded = String[]
    moved = Dict{String, Any}()
    for group in (:state, :implicit, :remaining, :lim)
        A, B = getproperty(a, group), getproperty(b, group)
        for key in sort(collect(keys(A)))
            label = "$group.$key"
            if !haskey(B, key)
                println("   MISSING in b: ", label)
                global all_equal = false
                continue
            end
            x, y = A[key], B[key]
            equal = size(x) == size(y) && isequal(x, y)
            if reported(key)
                push!(excluded, label)
                equal || (moved[label] = max_abs_difference(x, y))
            else
                n_judged += 1
                if !equal
                    signed_zero_only = size(x) == size(y) && x == y
                    println(
                        "   MODEL FIELD DIFFERS: ", label, " max abs ",
                        max_abs_difference(x, y),
                        signed_zero_only ? " (signed zeros only)" : "",
                    )
                    global all_equal = false
                end
            end
        end
        append!(only_b, "$group.$key" for key in sort(collect(setdiff(keys(B), keys(A)))))
    end
    println("   fields judged: ", n_judged)
    println("   fields only in b: ", length(only_b))
    if own_fields == "expected" && isempty(only_b)
        println(
            "   NO FIELDS ONLY IN b: the two sides ran different configurations, so b's diagnostic did not switch on",
        )
        global all_equal = false
    elseif own_fields == "none" && !isempty(only_b)
        println(
            "   FIELDS ONLY IN b WITH THE SAME CONFIGURATION: a fork field that is on by default",
        )
        global all_equal = false
    end
    foreach(label -> println("     ", label), first(only_b, 20))
    length(only_b) > 20 && println("     ...")
    isempty(prefixes) || println(
        "   excluded by a prefix: ",
        length(excluded),
        ", of which moved: ",
        length(moved),
    )
    foreach(
        l -> println(
            "     ",
            l,
            haskey(moved, l) ? "  moved, max abs $(moved[l])" : "  unchanged",
        ),
        excluded,
    )
end
println(all_equal ? "ALL MODEL FIELDS BIT FOR BIT" : "MODEL FIELD DIFFERENCES FOUND")
exit(all_equal ? 0 : 1)
