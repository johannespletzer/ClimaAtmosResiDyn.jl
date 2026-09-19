# The increment correction on a deep-atmosphere sphere: after a set increment,
# does each cell's partition change by the part the ledger says was moved? The
# faces grow with height there, so the flux must be scaled by the face areas.
# The smallest sphere of the test suite, 0M, for one step.
using Test
import ClimaAtmos as CA

region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 15000.0,
    "width" => 2000.0,
    "above" => above,
)
simulation = CA.get_simulation(
    CA.AtmosConfig(
        Dict{String, Any}(
            "config" => "sphere",
            "h_elem" => 2,
            "z_elem" => 4,
            "z_max" => 30000.0,
            "z_stretch" => false,
            "dt" => "400secs",
            "t_end" => "400secs",
            "initial_condition" => "MoistBaroclinicWave",
            "microphysics_model" => "0M",
            "FLOAT_TYPE" => "Float64",
            "output_default_diagnostics" => false,
            "output_dir" => mktempdir(pwd()),
            "energy_source_tag_offset" => 110495.0,
            "energy_source_tag_transport" => "enthalpy_increment",
            "energy_source_tags" => [
                Dict{String, Any}("name" => "strat", "region" => region(true)),
                Dict{String, Any}("name" => "tropo", "region" => region(false)),
            ],
        );
        job_id = "sphere_increment_deep",
    ),
)
@test CA.solve_atmos!(simulation).ret_code == :success
Y = simulation.integrator.u
p = simulation.integrator.p
FT = eltype(Y)
@info "Deep atmosphere" p.atmos.numerics extrema(parent(p.tagging.ᶠe_src_area_ratio))
@test minimum(parent(p.tagging.ᶠe_src_area_ratio)) < 1 - 1e-4

ᶜz = CA.Fields.coordinate_field(Y.c).z
dtγ = FT(100)
Y₀ = copy(Y)
CA.snapshot_energy_source_increment!(Y₀, p, dtγ)
U = copy(Y₀)
@. U.c.ρe_tot += FT(0.01) * (sin(2 * FT(π) * ᶜz / 30000) + FT(0.2)) * Y₀.c.ρ
dY = similar(Y)
dY .= zero(FT)
CA.correct_energy_source_increment!(dY, U, p)
partition(Y) = Y.c.ρe_src_strat .+ Y.c.ρe_src_tropo
U_new = copy(U)
@. U_new += dtγ * dY
ᶜchange = partition(U_new) .- partition(Y₀)
ᶜmoved = dtγ .* dY.c.e_src_inc_moved
error = maximum(abs, parent(ᶜchange) .- parent(ᶜmoved))
scale = maximum(abs, parent(ᶜmoved))
@info "Partition change against the ledger's move" error scale error / scale
@test scale > 0
@test error < 1e-10 * scale + 1000 * eps(FT) * maximum(abs, parent(partition(Y₀)))
