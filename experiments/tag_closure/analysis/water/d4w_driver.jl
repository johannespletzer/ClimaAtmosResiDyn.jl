#=
The D4-W driver: `run_tag_closure.jl` with one step added, as V3's driver does.
Before the solve, the passive tracer `q_gas_A` of `chemistry_model: passive` and
its copy in the updraft are set to the mask of the region `tropo`: below 750 m,
with a 100 m tanh edge. So at the start the tracer is the fraction of the air
that began below the inversion.

The mask is built from the region itself, not from a tag's cache. So the same
driver sets the tracer in the tagged runs and in their untagged twins, and the
twins stay comparable. The tracer feeds back into nothing.

    DRIVER=experiments/tag_closure/analysis/water/d4w_driver.jl \
    CONFIG=experiments/tag_closure/configs/w1_d4w_grid_tags.yml \
        sbatch experiments/tag_closure/runscripts/phase_c.sh

The NetCDF output at t = 0 is written while the simulation is built, before the
tracer is set, so its first `q_gas_A` sample is zero.

A run without the passive tracer, such as V-W3's TRMM pair, skips that step.

**With `water_tag_updraft_copy: true`,** the driver then starts the copies from
the default mode's plume (`CA.start_water_tag_copies_from_plume!`), not from
the grid mean's composition the model starts them with (G3_PLAN 4.1). So a
default run and its copies twin start from one updraft composition, and the
first hour measures the dynamics, not a spin-up. The copies' output at t = 0 is
from before this step too.
=#
include(joinpath(@__DIR__, "..", "..", "run_tag_closure.jl"))

# The region of D4-W's `tropo` tags. It must match their config entry.
const TROPO_REGION =
    Dict("type" => "tanh_altitude", "z_center" => 750.0, "width" => 100.0, "above" => false)

function set_passive_tracer_to_region!(simulation, region_config)
    Y = simulation.integrator.u
    p = simulation.integrator.p
    FT = CA.Spaces.undertype(axes(Y.c))
    region = CA.tag_region_from_config(region_config, FT)
    ᶜmask = CA.region_mask.(Ref(region), CA.Fields.coordinate_field(Y.c))
    @. Y.c.ρq_gas_A = Y.c.ρ * ᶜmask
    ᶜq_updraft = Y.c.sgsʲs.:(1).q_gas_A
    ᶜq_updraft .= ᶜmask
    CA.set_precomputed_quantities!(Y, p, simulation.integrator.t)
    return nothing
end

function main_d4w()
    path = config_path()
    config = CA.AtmosConfig(path)
    simulation = CA.get_simulation(config)
    Y = simulation.integrator.u
    hasproperty(Y.c, :ρq_gas_A) &&
        set_passive_tracer_to_region!(simulation, TROPO_REGION)
    if CA.has_water_tag_updraft_copies(simulation.integrator.p.atmos.water_tagging_model)
        CA.start_water_tag_copies_from_plume!(Y, simulation.integrator.p)
        @info "The water tags' updraft copies start from the default mode's plume"
    end
    result = CA.solve_atmos!(simulation)
    if CC.iamroot(CC.context(simulation))
        @info "D4-W finished" simulation.job_id result.ret_code
        print_closure_summary(simulation.output_dir)
    end
    result.ret_code == :success || exit(1)
    return simulation
end

main_d4w()
