#=
V3's driver: `run_tag_closure.jl` with one step added. Before the solve, the
passive tracer `q_gas_A` of `chemistry_model: passive`, and its copy in the
updraft, are set to the mask of the region tag `tropo`. So at the start the
tracer is the fraction of the air that began in that region, as the ratio
`ψ = tropo / (tropo + strat)` of the tags is.

The loss rule and new production leave `ψ` as it is, and subsidence moves
neither. So `ψ` changes only by transport, mixing and the repair, and the
tracer by transport and mixing, with its own updraft copy. `ψ - q_gas_A`
measures how the tags' mixing differs from the air's, the updraft included
(UPDRAFT_GAP.md). The tracer feeds back into nothing, so the model's own fields
should be those of the same run without it.

    DRIVER=experiments/tag_closure/analysis/increment/v3_driver.jl \
    CONFIG=experiments/tag_closure/configs/v3_d4_passive_tracer.yml \
        sbatch experiments/tag_closure/runscripts/phase_c.sh

The NetCDF output at t = 0 is written while the simulation is built, before
the tracer is set, so its first `q_gas_A` sample is zero.
=#
include(joinpath(@__DIR__, "..", "..", "run_tag_closure.jl"))

function set_passive_tracer_to_region!(simulation, tag)
    Y = simulation.integrator.u
    p = simulation.integrator.p
    ᶜmask = getproperty(p.tagging.ᶜenergy_source_masks, Symbol(:ρe_src_, tag))
    @. Y.c.ρq_gas_A = Y.c.ρ * ᶜmask
    ᶜq_updraft = Y.c.sgsʲs.:(1).q_gas_A
    ᶜq_updraft .= ᶜmask
    CA.set_precomputed_quantities!(Y, p, simulation.integrator.t)
    return nothing
end

function main_v3()
    path = config_path()
    config = CA.AtmosConfig(path)
    simulation = CA.get_simulation(config)
    set_passive_tracer_to_region!(simulation, :tropo)
    result = CA.solve_atmos!(simulation)
    if CC.iamroot(CC.context(simulation))
        @info "V3 finished" simulation.job_id result.ret_code
        print_closure_summary(simulation.output_dir)
    end
    result.ret_code == :success || exit(1)
    return simulation
end

main_v3()
