# Why the copies CI group misses closure: the copies test's column, one hour,
# with copies on or off and the microphysics explicit or implicit.
# Usage: julia explicit_probe.jl {copies,default} {explicit,implicit} [newton]
using Test
import ClimaAtmos as CA

mode, path = ARGS[1], ARGS[2]
newton = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 1
suffix = newton == 1 ? "" : "_n$(newton)"
outdir = joinpath(@__DIR__, "output", "probe_$(mode)_$(path)$(suffix)")
mkpath(outdir)

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)
config = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "turbconv" => "prognostic_edmfx",
    "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized",
    "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true,
    "edmfx_sgs_diffusive_flux" => true,
    "edmfx_nh_pressure" => true,
    "edmfx_vertical_diffusion" => true,
    "edmfx_filter" => true,
    "prognostic_tke" => true,
    "microphysics_model" => "1M",
    "implicit_microphysics" => path == "implicit",
    "fixed_terminal_velocity_liquid" => false,
    "z_elem" => 30,
    "z_max" => 1500.0,
    "z_stretch" => false,
    "perturb_initstate" => false,
    "rad" => "DYCOMS",
    "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
    "ode_algo" => "ARS222",
    "max_newton_iters_ode" => newton,
    "dt" => "120secs",
    "t_end" => "1hours",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => outdir,
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
    "water_tag_updraft_copy" => mode == "copies",
    "water_closure_check" => Dict{String, Any}("period" => "10mins", "audit" => true),
    "diagnostics" => [
        Dict{String, Any}(
            "short_name" =>
                mode == "copies" ?
                ["q_tag_leak_vdiff", "q_tag_leak_diffusion_up"] :
                ["q_tag_leak_vdiff"],
            "period" => "10mins",
        ),
    ],
)
simulation = CA.get_simulation(
    CA.AtmosConfig(config; job_id = "probe_$(mode)_$(path)$(suffix)"),
)
commit = try
    readchomp(`git -C $(pkgdir(CA)) rev-parse --short HEAD`)
catch
    "?"
end
@info "solving" mode path newton commit
result = CA.solve_atmos!(simulation)
@info "finished" result.ret_code
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
model = p.atmos.water_tagging_model
closure = CA.tag_closure(Y, p, :ρq_tot, CA.water_region_tag_state_names(model))
@info "closure after an hour" mode path newton closure.relative closure.gross_relative
if CA.has_water_tag_updraft_copies(model)
    audit = CA.water_tag_edmf_audit(Y, p, model, closure.scale)
    @info "copies audit" audit
    # Where the composition check's NaN comes from.
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    ρa = parent(ᶜsgsʲ.ρa)
    @info "updraft area" minimum(ρa) count(iszero, ρa) count(<(1e-10), ρa) length(ρa)
    ᶜleak = similar(Y.c.ρ)
    CA.water_tag_leak!(ᶜleak, Y, p, Val(:diffusion_up))
    ᶜleakʲ = ᶜleak .* Y.c.ρ ./ ᶜsgsʲ.ρa
    @info "leak per updraft mass" count(isnan, parent(ᶜleakʲ)) count(isinf, parent(ᶜleakʲ)) count(
        iszero,
        parent(ᶜleak),
    )
    Yₜ = zero(Y)
    Yₜ_lim = zero(Y)
    CA.remaining_tendency!(Yₜ, Yₜ_lim, Y, p, t)
    Yₜ_implicit = zero(Y)
    CA.implicit_tendency!(Yₜ_implicit, Y, p, t)
    for name in CA.water_tag_updraft_copy_names(model)
        v =
            parent(getproperty(Yₜ.c.sgsʲs.:(1), name)) .+
            parent(getproperty(Yₜ_lim.c.sgsʲs.:(1), name)) .+
            parent(getproperty(Yₜ_implicit.c.sgsʲs.:(1), name))
        @info "copy tendency" name count(isnan, v)
    end
end
