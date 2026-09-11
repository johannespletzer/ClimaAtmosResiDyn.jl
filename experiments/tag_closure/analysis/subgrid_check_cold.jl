#=
Build and run check: a cold precipitating column with energy source tags.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_check_cold.jl 1M
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_check_cold.jl 2M
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_check_cold.jl 2MP3

`PrecipitatingColumn` starts with cloud ice at 6 to 9 km and snow at 5 to 8 km,
where the air is well below freezing. So ice falls from the first step, and its
energy against the reference plus the offset is negative. That is the upward
branch of `sediment_energy_source_tags!`, which only a set flux in the
integration test has reached so far.

The script steps the column for a minute and then checks, on the real state:
  - that the partition's sedimentation tendency adds up to the parent's, `E`;
  - how many cells carry falling water with negative energy, per species;
  - on a step partition inside the ice layer, that the lower tag reaches above
    the step, which only the upward branch can do;
  - whether each species' own sedimentation matches what `ρq_tot` is moved by.

No repository file is touched. Output goes to $SCRATCH/tag_closure/subgrid_checks.
=#
import ClimaAtmos as CA
using Printf

scheme = get(ARGS, 1, "1M")
scratch = joinpath(get(ENV, "SCRATCH", tempdir()), "tag_closure", "subgrid_checks")
mkpath(scratch)
c = 110495.0
z_step = 6500.0

alt(z, above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => z,
    "width" => 200.0,
    "above" => above,
)
tags = [
    Dict{String, Any}("name" => "upper", "region" => alt(5000.0, true)),
    Dict{String, Any}("name" => "lower", "region" => alt(5000.0, false)),
    Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
]

# `config/model_configs/single_column_precipitation_2M_test.yml`, written out,
# with the scheme, the tags, an offset and a short run.
dict = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "PrecipitatingColumn",
    "surface_setup" => "DefaultMoninObukhov",
    "z_elem" => 100,
    "z_max" => 10000.0,
    "z_stretch" => false,
    "dt" => "10secs",
    "t_end" => "60secs",
    "cloud_model" => "grid_scale",
    # The shipped 2M column runs microphysics explicitly: "2M implicit
    # microphysics Jacobian not yet fully implemented".
    "implicit_microphysics" => scheme == "1M",
    "microphysics_model" => scheme,
    "use_sgs_quadrature" => false,
    "vert_diff" => "DecayWithHeightDiffusion",
    "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => joinpath(scratch, "out_cold_$scheme"),
    "energy_source_tags" => tags,
    "energy_source_tag_offset" => c,
)

t0 = time()
sim = CA.get_simulation(CA.AtmosConfig(dict; job_id = "agentD_cold_$scheme"))
@printf("[%s] simulation built after %.0f s\n", scheme, time() - t0)
println("[$scheme] state: ", propertynames(sim.integrator.u.c))
result = CA.solve_atmos!(sim)
println("[$scheme] ret_code = ", result.ret_code)
@printf("[%s] solved after %.0f s\n", scheme, time() - t0)
Y = sim.integrator.u
p = sim.integrator.p
t = sim.integrator.t
FT = eltype(Y)
CA.set_precomputed_quantities!(Y, p, t)

maxabs(f) = maximum(abs, parent(f))
gross(f) = sum(abs.(f))
ᶜz = CA.Fields.coordinate_field(Y.c).z
ᶜE = @. Y.c.ρe_tot + c * Y.c.ρ
@printf("[%s] cells with E <= 0: %d\n", scheme, count(<=(0), parent(ᶜE)))
for name in (:ρe_src_upper, :ρe_src_lower, :ρe_src_sfc)
    @printf("[%s] min %-14s %.4e\n", scheme, name, minimum(parent(getproperty(Y.c, name))))
end
ᶜres = @. ᶜE - Y.c.ρe_src_upper - Y.c.ρe_src_lower
@printf("[%s] closure after %.0f s: gross %.4e, over gross E %.4e\n",
    scheme, t, gross(ᶜres), gross(ᶜE))

# 1. The partition's sedimentation tendency against the parent's, at this state.
Yₜ = zero(Y)
CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
ᶜEₜ = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
ᶜPₜ = @. Yₜ.c.ρe_src_upper + Yₜ.c.ρe_src_lower
@printf(
    "[%s] sedimentation: max|E-tendency| %.4e, max|partition - E| %.4e, ratio %.2e (100 eps = %.2e)\n",
    scheme, maxabs(ᶜEₜ), maxabs(@. ᶜPₜ - ᶜEₜ),
    maxabs(@. ᶜPₜ - ᶜEₜ) / maxabs(ᶜEₜ), 100 * eps(FT))

# 2. Where the falling water carries negative energy, per species. The kinetic
# term is left out; it is below 1 J/kg here, against 1e5.
thp = CA.Parameters.thermodynamics_params(p.params)
(; ᶜT) = p.precomputed
(; ᶜΦ) = p.core
species = (
    (:ρq_lcl, CA.TD.internal_energy_liquid),
    (:ρq_icl, CA.TD.internal_energy_ice),
    (:ρq_rai, CA.TD.internal_energy_liquid),
    (:ρq_sno, CA.TD.internal_energy_ice),
)
for (name, e_int) in species
    hasproperty(Y.c, name) || continue
    ᶜρq = getproperty(Y.c, name)
    ᶜe = @. e_int(thp, ᶜT) + ᶜΦ + c
    wet = parent(ᶜρq) .> 1e-9 .* parent(Y.c.ρ)
    negative = wet .& (parent(ᶜe) .< 0)
    @printf(
        "[%s] %-7s cells with q > 1e-9: %3d, of which E per kg < 0: %3d, min(e_int + Φ + c) there %.3e J/kg\n",
        scheme, name, count(wet), count(negative),
        count(negative) > 0 ? minimum(parent(ᶜe)[negative]) : NaN)
end

# 3. A step partition inside the ice layer. Under the downward branch alone the
# lower tag could never gain above the step.
Y_step = copy(Y)
@. Y_step.c.ρe_src_upper = ifelse(ᶜz > z_step, ᶜE, FT(0))
@. Y_step.c.ρe_src_lower = ᶜE - Y_step.c.ρe_src_upper
Yₜ = zero(Y_step)
CA.vertical_advection_of_water_tendency!(Yₜ, Y_step, p, t)
above = parent(ᶜz) .> z_step
upper = parent(Yₜ.c.ρe_src_upper)
lower = parent(Yₜ.c.ρe_src_lower)
ᶜEₜ = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
@printf(
    "[%s] step at %.0f m: cells above the step where `lower` moves: %d; cells below where `upper` moves: %d; closure %.2e\n",
    scheme, z_step, count(!iszero, lower[above]), count(!iszero, upper[.!above]),
    maximum(abs, upper .+ lower .- parent(ᶜEₜ)) / maxabs(ᶜEₜ))

# 4. Each species' own sedimentation against what ρq_tot is moved by. Species
# advect with the mean flow in the explicit tendency, so in the implicit
# vertical advection their tendency is sedimentation alone.
Yₜ_all = zero(Y)
CA.implicit_vertical_advection_tendency!(Yₜ_all, Y, p, t)
Yₜ_sed = zero(Y)
CA.vertical_advection_of_water_tendency!(Yₜ_sed, Y, p, t)
ᶜspecies = zero.(Y.c.ρ)
for (name, _) in species
    hasproperty(Y.c, name) || continue
    ᶜs = getproperty(Yₜ_all.c, name)
    @. ᶜspecies += ᶜs
    @printf("[%s] %-7s own sedimentation, gross %.4e\n", scheme, name, gross(ᶜs))
end
@printf(
    "[%s] ρq_tot moved by sedimentation, gross %.4e; minus the species' own, gross %.4e\n",
    scheme, gross(Yₜ_sed.c.ρq_tot), gross(@. Yₜ_sed.c.ρq_tot - ᶜspecies))
@printf("[%s] done after %.0f s\n", scheme, time() - t0)
