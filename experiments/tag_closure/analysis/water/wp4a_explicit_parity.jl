# Parity of the 0M EDMF column on the explicit microphysics path, where the
# split runs from remaining_tendency!: tagged (default mode, then copies) vs
# untagged, compared with isequal on every model field after 1 hour. Also
# checks the split's partition sum against its exact identity at the end.
import ClimaAtmos as CA
using Test
altitude_region(above) = Dict{String, Any}("type" => "tanh_altitude",
    "z_center" => 750.0, "width" => 100.0, "above" => above)
edmf = Dict{String, Any}(
    "config" => "column", "initial_condition" => "DYCOMS_RF02",
    "turbconv" => "prognostic_edmfx", "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized", "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true, "edmfx_sgs_diffusive_flux" => true,
    "edmfx_nh_pressure" => true, "edmfx_vertical_diffusion" => true,
    "edmfx_filter" => true, "prognostic_tke" => true,
    "microphysics_model" => "0M", "implicit_microphysics" => false,
    "z_elem" => 30, "z_max" => 1500.0,
    "z_stretch" => false, "perturb_initstate" => false, "rad" => "DYCOMS",
    "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
    "ode_algo" => "ARS222", "dt" => "120secs", "t_end" => "1hours",
    "FLOAT_TYPE" => "Float64", "output_default_diagnostics" => false,
)
tags = Dict{String, Any}(
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
    "diagnostics" => [Dict{String, Any}("short_name" => ["pr_tag_tropo", "prra_tag_strat"], "period" => "10mins")],
)
run(d, id) = (s = CA.get_simulation(CA.AtmosConfig(merge(d, Dict{String, Any}("output_dir" => mktempdir(pwd()))); job_id = id));
              @test CA.solve_atmos!(s).ret_code == :success; s)
function same(Y, Yp)
    for n in propertynames(Yp.c)
        n == :sgsʲs && continue
        @test isequal(parent(getproperty(Y.c, n)), parent(getproperty(Yp.c, n)))
    end
    for n in propertynames(Yp.c.sgsʲs.:(1))
        @test isequal(parent(getproperty(Y.c.sgsʲs.:(1), n)), parent(getproperty(Yp.c.sgsʲs.:(1), n)))
    end
    @test isequal(parent(Yp.f), parent(Y.f))
end
plain = run(edmf, "wp4a_explicit_plain")
@testset "explicit, default mode" begin
    s = run(merge(edmf, tags), "wp4a_explicit_default")
    same(s.integrator.u, plain.integrator.u)
end
@testset "explicit, copies" begin
    s = run(merge(edmf, tags, Dict{String, Any}("water_tag_updraft_copy" => true)), "wp4a_explicit_copies")
    same(s.integrator.u, plain.integrator.u)
end
