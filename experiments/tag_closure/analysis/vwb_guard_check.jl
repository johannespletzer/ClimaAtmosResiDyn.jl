# Decision 12: whether the vertical water borrowing guards of limiters_func!
# match an explicit species list, and what the limiter then does to rho and
# rho e_tot. The argument is the root of a ClimaAtmos checkout.
#
#   julia +1.11 --project=<checkout>/.buildkite experiments/tag_closure/analysis/vwb_guard_check.jl <checkout>
#
# Run on 2026-09-16 against CliMA/ClimaAtmos.jl main at eb010645.
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaCore.MatrixFields: @name
include(joinpath(ARGS[1], "test", "test_helpers.jl"))

config = CA.AtmosConfig(
    Dict(
        "config" => "column",
        "initial_condition" => "DecayingProfile",
        "microphysics_model" => "1M",
        "tracer_nonnegativity_method" => "vertical_water_borrowing",
        "output_default_diagnostics" => false,
        "vertical_water_borrowing_species" => ["ρq_tot"],
    );
    job_id = "vwb_debug",
)
(; Y, p) = generate_test_simulation(config)
FT = eltype(Y)
species = p.numerics.vertical_water_borrowing_species
println("species = ", repr(species), " :: ", typeof(species))
println("guard with @name: ", CA._should_apply_limiter_to_tracer(@name(ρq_tot), species))
println("guard with Symbol: ", CA._should_apply_limiter_to_tracer(:ρq_tot, species))
println("limiter: ", typeof(p.numerics.vertical_water_borrowing_limiter))
ref_Y = deepcopy(Y)
ρq = parent(Y.c.ρq_tot)
n = length(ρq)
ρq[(n - max(1, round(Int, 0.2n)) + 1):n] .= -1e-7
Y_before = copy(Y)
CA.limiters_func!(Y, p, FT(0), ref_Y)
Δρq = parent(Y.c.ρq_tot) .- parent(Y_before.c.ρq_tot)
Δρ = parent(Y.c.ρ) .- parent(Y_before.c.ρ)
Δρe = parent(Y.c.ρe_tot) .- parent(Y_before.c.ρe_tot)
println("max |Δρq_tot| = ", maximum(abs, Δρq), ", max |Δρ| = ", maximum(abs, Δρ), ", max |Δρe_tot| = ", maximum(abs, Δρe))
println("ρ range ", extrema(parent(Y.c.ρ)))
println("isapprox(ρ_after, ρ_before + Δρq) = ", parent(Y.c.ρ) ≈ parent(Y_before.c.ρ) .+ Δρq)
println("isapprox(ρ_after, ρ_before) = ", parent(Y.c.ρ) ≈ parent(Y_before.c.ρ))
