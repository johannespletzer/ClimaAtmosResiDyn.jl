# Whether the horizontal advection of tracers moves the process records on a
# sphere. The smallest sphere of `energy_source_tags_integration.jl`, item 10,
# without tags and with two energy records, for one step. The records then hold
# a horizontally varying field, and the horizontal tracer advection alone is
# evaluated into a zeroed tendency.
using Test
import ClimaAtmos as CA

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
            "energy_process_record" => ["microphysics", "precipitation"],
        );
        job_id = "sphere_record_advection",
    ),
)
@test CA.solve_atmos!(simulation).ret_code == :success
Y = copy(simulation.integrator.u)
p = simulation.integrator.p
t = simulation.integrator.t
# A record that varies horizontally, as a real one does.
Y.c.prc_e_microphysics .= Y.c.ρe_tot
Yₜ = zero(Y)
CA.horizontal_tracer_advection_tendency!(Yₜ, Y, p, t)
moved = maximum(abs, parent(Yₜ.c.prc_e_microphysics))
@info "Horizontal advection of a record" CA.is_tracer_var(:prc_e_microphysics) moved maximum(
    abs,
    parent(Yₜ.c.ρq_tot),
)
@test maximum(abs, parent(Yₜ.c.ρq_tot)) > 0
@test moved == 0
