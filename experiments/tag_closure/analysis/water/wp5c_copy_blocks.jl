# WP5b-C: the copies' sedimentation cross blocks, on the model's own state.
#
#   julia --project=<env at WP5b-C's code> wp5c_copy_blocks.jl
#
# The copies column of `test/tagged_water_edmf_copies_integration.jl` (DYCOMS
# RF02, prognostic EDMF, 1M stepped explicitly, copies on), run for an hour with
# one Newton iteration. At its final state it builds the Jacobian twice, split
# (the default) and unsplit (`split_uncoupled_fields = false`, as
# `AutoSparseJacobian` uses), and prints:
#   1. per sedimenting updraft species, the partition copies' blocks summed,
#      against the updraft water's block `(q_totʲ, species)`: the largest
#      difference over the block's largest value;
#   2. whether the unsplit form builds with the copies' blocks;
#   3. for a right-hand side of `dtγ` times the implicit tendency, each form's
#      increment of the model's fields, compared bit for bit, and each form's
#      partition copies' increments summed against `q_totʲ`'s, over its largest
#      value.
import ClimaAtmos as CA
import ClimaAtmos: MatrixFields

altitude_region(above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => above,
)
dict = Dict{String, Any}(
    "config" => "column", "initial_condition" => "DYCOMS_RF02",
    "turbconv" => "prognostic_edmfx", "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized", "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true, "edmfx_sgs_diffusive_flux" => true,
    "edmfx_nh_pressure" => true, "edmfx_vertical_diffusion" => true,
    "edmfx_filter" => true, "prognostic_tke" => true,
    "microphysics_model" => "1M", "implicit_microphysics" => false,
    "fixed_terminal_velocity_liquid" => false, "z_elem" => 30,
    "z_max" => 1500.0, "z_stretch" => false, "perturb_initstate" => false,
    "rad" => "DYCOMS",
    "toml" => [joinpath(pkgdir(CA), "toml", "prognostic_edmfx_1M.toml")],
    "ode_algo" => "ARS222", "max_newton_iters_ode" => 1, "dt" => "120secs",
    "t_end" => get(ENV, "T_END", "1hours"), "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false, "output_dir" => mktempdir(pwd()),
    "water_tracers" => [
        Dict{String, Any}("name" => "tropo", "region" => altitude_region(false)),
        Dict{String, Any}("name" => "strat", "region" => altitude_region(true)),
        Dict{String, Any}("name" => "evap", "source" => "surface_flux"),
    ],
    "water_tag_updraft_copy" => true,
)
simulation = CA.get_simulation(CA.AtmosConfig(dict; job_id = "wp5c_copy_blocks"))
@assert CA.solve_atmos!(simulation).ret_code == :success
(; u, p, t) = simulation.integrator
Y = u
atmos = p.atmos
FT = eltype(Y)
dtγ = FT(60)

sgs(name) = CA.sgs_state_name(name)
partition_copies = (:q_tag_tropo, :q_tag_strat)
alg = CA.ManualSparseJacobian(; approximate_solve_iters = 2)

split_cache = CA.jacobian_cache(alg, Y, atmos)
CA.update_jacobian!(alg, split_cache, Y, p, dtγ, t)
for species in CA.sedimenting_sgs_mass_names(Y)
    block = split_cache.matrix[sgs(MatrixFields.FieldName(:q_tot)), sgs(species)]
    ᶜsum = copy(block)
    parent(ᶜsum) .= 0
    for copy_name in partition_copies
        ᶜcopy_block =
            split_cache.matrix[sgs(MatrixFields.FieldName(copy_name)), sgs(species)]
        @. ᶜsum = ᶜsum + ᶜcopy_block
    end
    scale = maximum(abs, parent(block))
    difference = maximum(abs, parent(ᶜsum) .- parent(block))
    println(
        "RESULT block_sum species=$species scale=$scale relative_difference=$(difference / scale)",
    )
end

unsplit_cache = try
    cache = CA.jacobian_cache(alg, Y, atmos; split_uncoupled_fields = false)
    CA.update_jacobian!(alg, cache, Y, p, dtγ, t)
    println("RESULT unsplit built: $(typeof(cache.solver).name.name)")
    cache
catch err
    println("RESULT unsplit ERROR: ", first(sprint(showerror, err), 600))
    nothing
end

R = zero(Y)
CA.implicit_tendency!(R, Y, p, t)
R .*= dtγ
function solve(cache)
    ΔY = zero(Y)
    CA.invert_jacobian!(alg, cache, ΔY, R)
    return ΔY
end
ΔY_split = solve(split_cache)
function copies_closure(ΔY)
    ᶜΔq_totʲ = ΔY.c.sgsʲs.:(1).q_tot
    ᶜsum = sum(name -> getproperty(ΔY.c.sgsʲs.:(1), name), partition_copies)
    return maximum(abs, parent(ᶜsum) .- parent(ᶜΔq_totʲ)) /
           maximum(abs, parent(ᶜΔq_totʲ))
end
println("RESULT split copies_closure=$(copies_closure(ΔY_split))")
if !isnothing(unsplit_cache)
    ΔY_unsplit = solve(unsplit_cache)
    println("RESULT unsplit copies_closure=$(copies_closure(ΔY_unsplit))")
    is_tag(name) = startswith(string(name), "ρq_tag") || startswith(string(name), "q_tag")
    differing = String[]
    for name in propertynames(Y.c)
        name == :sgsʲs && continue
        is_tag(name) && continue
        parent(getproperty(ΔY_split.c, name)) == parent(getproperty(ΔY_unsplit.c, name)) ||
            push!(differing, "c.$name")
    end
    for name in propertynames(Y.c.sgsʲs.:(1))
        is_tag(name) && continue
        parent(getproperty(ΔY_split.c.sgsʲs.:(1), name)) ==
        parent(getproperty(ΔY_unsplit.c.sgsʲs.:(1), name)) ||
            push!(differing, "c.sgsʲ.$name")
    end
    parent(ΔY_split.f) == parent(ΔY_unsplit.f) || push!(differing, "f")
    println(
        "RESULT model increments split against unsplit: ",
        isempty(differing) ? "bit for bit" : "differ in " * join(differing, ", "),
    )
end
