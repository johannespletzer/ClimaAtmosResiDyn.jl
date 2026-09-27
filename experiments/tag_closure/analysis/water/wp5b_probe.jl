# WP5b's distinguishing experiment (the owner's review of #102, point 3): W23's
# column (DYCOMS RF02, 1M, prognostic EDMF, microphysics stepped explicitly,
# ARS222, one hour) with the tags' sedimentation cross blocks off or on, in the
# default mode or with copies, under the tracer transport or the follower.
#
#   julia --project=<env pointing at the code> wp5b_probe.jl MODE TRANSPORT NEWTON LABEL OUTDIR
#
# MODE is default or copies, TRANSPORT tracer or increment, LABEL off or on (the
# code decides which; the label only names the output). It prints the closure,
# the audit and the smallest tag, and writes the final column of the parent and
# the tags to OUTDIR/<run>.csv, each value as `repr` writes it, so that runs can
# be compared bit for bit and default against copies.
using Test
import ClimaAtmos as CA

mode, transport, newton, label, outroot =
    ARGS[1], ARGS[2], parse(Int, ARGS[3]), ARGS[4], ARGS[5]
run = "wp5b_$(label)_$(mode)_$(transport)_n$(newton)"
outdir = joinpath(outroot, run)
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
    "implicit_microphysics" => false,
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
    "water_tag_transport" => transport,
    "water_closure_check" =>
        Dict{String, Any}("period" => "10mins", "audit" => true),
)
simulation = CA.get_simulation(CA.AtmosConfig(config; job_id = run))
commit = try
    readchomp(`git -C $(pkgdir(CA)) rev-parse --short HEAD`)
catch
    "?"
end
@info "solving" run commit
result = CA.solve_atmos!(simulation)
@info "finished" run result.ret_code
Y = simulation.integrator.u
p = simulation.integrator.p
model = p.atmos.water_tagging_model
closure = CA.tag_closure(Y, p, :ρq_tot, CA.water_region_tag_state_names(model))
audit = CA.water_tag_extra_audit(Y, p, model, closure.scale)
smallest = minimum(
    minimum(parent(getproperty(Y.c, name)) ./ parent(Y.c.ρ)) for
    name in CA.water_region_tag_state_names(model)
)
repair = sum(
    sum(abs, parent(getproperty(p.tagging.ᶜwater_fix, name))) for
    name in CA.water_region_tag_state_names(model)
)
println("RESULT run=$run commit=$commit ret=$(result.ret_code)")
println("RESULT closure net=$(closure.relative) gross=$(closure.gross_relative)")
println("RESULT smallest_partition_tag_kg_per_kg=$smallest")
println("RESULT partition_repair_ledger_abs_sum_over_cells=$repair scale=$(closure.scale)")
println("RESULT audit=$(audit)")

columns = (:ρ, :ρq_tot, :ρe_tot, :ρq_rai, :ρq_sno, CA.water_tag_state_names(model)...)
open(joinpath(outroot, "$run.csv"), "w") do io
    println(io, join(string.(columns), ","))
    values = map(name -> parent(getproperty(Y.c, name))[:], columns)
    for k in eachindex(values[1])
        println(io, join((repr(v[k]) for v in values), ","))
    end
end
