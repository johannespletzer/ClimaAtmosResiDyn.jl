# T3 for #76: does the split Jacobian solver allocate in the Newton loop? The
# DYCOMS 0M column of energy_source_tags_integration.jl item 6, with its three
# tags, against the unsplit solver on the same state.
#
# Run from the root of a worktree at the commit under test, on a login node:
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/t3_split_solver_allocations.jl
# Needs #76 (SplitJacobianSolver). FINDINGS T10.

import ClimaAtmos as CA
import ClimaComms
ClimaComms.@import_required_backends
import LinearAlgebra

tags = [
    Dict{String, Any}(
        "name" => "strat",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
        ),
    ),
    Dict{String, Any}(
        "name" => "tropo",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
            "above" => false,
        ),
    ),
    Dict{String, Any}("name" => "rad", "source" => "radiation"),
]
test_dict = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "0M",
    "dt" => "10secs",
    "t_end" => "20secs",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(),
    "energy_source_tags" => tags,
)
simulation = CA.get_simulation(CA.AtmosConfig(test_dict; job_id = "t3_split_solver_allocs"))
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
FT = eltype(Y)

function allocations(f::F, args...) where {F}
    f(args...)
    a1 = @allocated f(args...)
    a2 = @allocated f(args...)
    return (a1, a2)
end

jacobian_alg = CA.ManualSparseJacobian()
split_cache = CA.jacobian_cache(jacobian_alg, Y, p.atmos)
unsplit_cache = CA.jacobian_cache(jacobian_alg, Y, p.atmos; split_uncoupled_fields = false)
println("split solver type: ", nameof(typeof(split_cache.solver)))
dtγ = FT(5)
ΔY = zero(Y)
for (label, cache) in (("split", split_cache), ("unsplit", unsplit_cache))
    println(
        label,
        " update_jacobian! allocs ",
        allocations(CA.update_jacobian!, jacobian_alg, cache, Y, p, dtγ, t),
    )
    println(
        label,
        " invert_jacobian! allocs ",
        allocations(CA.invert_jacobian!, jacobian_alg, cache, ΔY, Y),
    )
    println(label, " ldiv! allocs ", allocations(LinearAlgebra.ldiv!, ΔY, cache.solver, Y))
    flush(stdout)
end
