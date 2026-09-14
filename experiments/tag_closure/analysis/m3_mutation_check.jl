# M3: run the new testset of `test/tracer_processes_tests.jl` as written, then
# against mutated copies of `water_advection.jl`. Each mutation must fail it.
#
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/m3_mutation_check.jl \
#       <worktree>/test/tracer_processes_tests.jl
using Test
import ClimaAtmos as CA

# The test file to check, from a worktree with M3 applied.
test_file = abspath(only(ARGS))
test_dir = dirname(test_file)
source_file = joinpath(pkgdir(CA), "src", "prognostic_equations", "water_advection.jl")
original = read(source_file, String)

function run_with_source(label, text)
    root = mktempdir()
    mkpath(joinpath(root, "src", "prognostic_equations"))
    write(joinpath(root, "src", "prognostic_equations", "water_advection.jl"), text)
    # Only the new block, with the imports it needs. The rest of the file needs
    # test-only packages that the .buildkite project does not have.
    full_text = read(test_file, String)
    first_line = findfirst("# `vertical_advection_of_water_tendency!` does not use", full_text)
    last_line = findfirst("@testset \"Name lifting\"", full_text)
    block = full_text[first(first_line):(first(last_line) - 1)]
    test_text = "using Test\nimport ClimaAtmos as CA\nimport ClimaCore.MatrixFields: @name\n" *
                replace(block, "pkgdir(CA)" => repr(root))
    mod = Module(Symbol(label))
    ts = @testset ReportingTestSet "$label" begin
        Base.include_string(mod, test_text, test_file)
    end
end

# A test set that records results without throwing, so a mutation's failures
# can be counted.
struct ReportingTestSet <: Test.AbstractTestSet
    description::String
    results::Vector{Any}
end
ReportingTestSet(desc; kwargs...) = ReportingTestSet(desc, [])
Test.record(ts::ReportingTestSet, t) = (push!(ts.results, t); t)
function Test.finish(ts::ReportingTestSet)
    Test.get_testset_depth() > 0 && Test.record(Test.get_testset(), ts)
    return ts
end

count_fails(ts) = sum(r -> r isa ReportingTestSet ? count_fails(r) : (r isa Test.Fail || r isa Test.Error) ? 1 : 0, ts.results; init = 0)
function show_failures(ts, path = ts.description)
    for r in ts.results
        if r isa ReportingTestSet
            show_failures(r, path * " / " * r.description)
        elseif r isa Test.Fail || r isa Test.Error
            println("    in ", path, ": ", first(sprint(show, r), 600))
        end
    end
end
count_all(ts) =sum(r -> r isa ReportingTestSet ? count_all(r) : 1, ts.results; init = 0)

mutations = [
    ("unchanged", original),
    ("species_dropped", replace(original, "        (@name(ρq_sno), @name(ᶜwₛ)),\n" => "")),
    ("species_added", replace(original, "        (@name(ρq_sno), @name(ᶜwₛ)),\n" => "        (@name(ρq_sno), @name(ᶜwₛ)),\n        (@name(ρq_rim), @name(ᶜwᵢ)),\n")),
    ("wrong_velocity", replace(original, "(@name(ρq_rai), @name(ᶜwᵣ))" => "(@name(ρq_rai), @name(ᶜwₗ))")),
    ("sgs_species_dropped", replace(original, "            (@name(q_sno), @name(ᶜwₛʲs.:(1)), @name(ᶜwₛ)),\n" => "")),
]
for (label, text) in mutations
    label != "unchanged" && text == original && error("mutation $label did not apply")
    ts = run_with_source(label, text)
    println(rpad(label, 22), " failures ", count_fails(ts), " of ", count_all(ts))
    show_failures(ts)
end
