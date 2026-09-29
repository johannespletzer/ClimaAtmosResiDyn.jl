#=
C's revision: the parity check's prognostic state (design/NEGATIVE_PARENT_WATER.md,
section 11.8).

    julia --project=<an env with ClimaCore and ClimaComms> cr_parity_state.jl [OUTPUT_ROOT]

OUTPUT_ROOT (default $SCRATCH/tag_closure/output) holds
`cr_parity_{tags,untagged}_{rev,main}/output_0000/day10.0.hdf5`, the state the
runs saved at day 10. For each pair it reads both states and compares every
model field of `Y.c`, `Y.f` and the updraft's `sgsʲs` with `isequal` on the
parent arrays, as docs/clima_atmos_specific.md ("Fork parity with upstream")
asks. A model field is any field whose name is not a tag's, a tag part's or a
tag ledger's. Both states must hold the same model fields. The water tags'
fields, the revision against main, are reported. It exits 1 if a model field
differs or is missing.
=#
import ClimaComms
import ClimaCore: InputOutput, Fields

const ROOT = get(ARGS, 1, joinpath(ENV["SCRATCH"], "tag_closure", "output"))
const DIAGNOSTIC_PREFIXES = (
    "ρq_tag_", "ρq_rtag_", "ρq_stag_", "q_tag_", "q_rtag_", "q_stag_",
    "ρe_src_", "e_src_", "ρe_tag_", "e_tag_", "prc_",
)
is_diagnostic(name) = any(prefix -> startswith(string(name), prefix), DIAGNOSTIC_PREFIXES)

function read_state(job)
    path = joinpath(ROOT, job, "output_0000", "day10.0.hdf5")
    reader = InputOutput.HDF5Reader(path, ClimaComms.SingletonCommsContext())
    Y = InputOutput.read_field(reader, "Y")
    Base.close(reader)
    return Y
end

# Every leaf field of the state, by a readable name: `c.ρ`, `f.u₃`,
# `c.sgsʲs.1.ρa`, and so on.
function leaves(Y)
    out = Dict{String, Any}()
    for group in (:c, :f)
        field = getproperty(Y, group)
        for name in propertynames(field)
            sub = getproperty(field, name)
            if name == :sgsʲs
                for j in 1:length(propertynames(sub))
                    updraft = getproperty(sub, j)
                    for n in propertynames(updraft)
                        out["$group.sgsʲs.$j.$n"] = getproperty(updraft, n)
                    end
                end
            else
                out["$group.$name"] = sub
            end
        end
    end
    return out
end

leaf_name(key) = last(split(key, "."))

function compare(a, b, label; report_tags = false)
    A, B = leaves(read_state(a)), leaves(read_state(b))
    model_a = sort([k for k in keys(A) if !is_diagnostic(leaf_name(k))])
    model_b = sort([k for k in keys(B) if !is_diagnostic(leaf_name(k))])
    differ = String[]
    model_a == model_b ||
        push!(differ, "the model fields differ in name: $(symdiff(model_a, model_b))")
    for k in intersect(model_a, model_b)
        isequal(parent(A[k]), parent(B[k])) || push!(differ, k)
    end
    ok = isempty(differ) && !isempty(model_a)
    println(
        "$label: $(length(model_a)) model fields at day 10: ",
        ok ? "isequal" : "FAIL $(differ)",
    )
    if report_tags
        for k in sort([
            k for k in keys(B) if
            is_diagnostic(leaf_name(k)) && startswith(leaf_name(k), "ρq_tag_")
        ])
            haskey(A, k) || (println("    $k: missing in $a"); continue)
            pa, pb = parent(A[k]), parent(B[k])
            same = isequal(pa, pb)
            scale = max(maximum(abs, pb), floatmin(eltype(pb)))
            println(
                "    $k: ",
                same ? "the same" :
                "differs, largest difference $(maximum(abs, pa .- pb) / scale) of its largest value",
            )
        end
    end
    return ok
end

function main()
    results = [
        compare(
            "cr_parity_tags_rev",
            "cr_parity_tags_main",
            "tags on, the revision against main";
            report_tags = true,
        ),
        compare(
            "cr_parity_untagged_rev",
            "cr_parity_untagged_main",
            "tags off, the revision against main",
        ),
        compare(
            "cr_parity_tags_rev",
            "cr_parity_untagged_rev",
            "the revision, tags on against off",
        ),
        compare(
            "cr_parity_tags_main",
            "cr_parity_untagged_main",
            "main, tags on against off",
        ),
    ]
    println("RESULT ", all(results) ? "every model field isequal" : "FAIL")
    exit(all(results) ? 0 : 1)
end

main()
