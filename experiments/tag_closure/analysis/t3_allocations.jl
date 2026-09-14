# Exploration for T3: which tag calls allocate on a DYCOMS column with tags,
# an offset, the repair, sedimentation under 1M and process records.
#
# Run from the root of a worktree at the commit under test, on a login node:
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/t3_allocations.jl
# T3_TAGS=false runs the same column without tags, records or offset. FINDINGS T10.

using Test
import ClimaAtmos as CA
import ClimaComms
ClimaComms.@import_required_backends

with_tags = get(ENV, "T3_TAGS", "true") == "true"

tags = [
    Dict{String, Any}(
        "name" => "strat",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
        ),
    ),
    Dict{String, Any}(
        "name" => "tropo",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => 100.0,
            "above" => false,
        ),
    ),
    Dict{String, Any}("name" => "rad", "source" => "radiation"),
    Dict{String, Any}("name" => "prec", "source" => "microphysics"),
]
test_dict = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "1M",
    "fixed_terminal_velocity_liquid" => false,
    "dt" => "10secs",
    "t_end" => "20secs",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(),
)
if with_tags
    test_dict["energy_source_tags"] = tags
    test_dict["energy_source_tag_offset"] = 50000.0
    test_dict["energy_process_record"] = ["radiation", "precipitation", "surface_flux"]
end

t0 = time()
simulation = CA.get_simulation(CA.AtmosConfig(test_dict; job_id = "t3_explore"))
println("get_simulation ", round(time() - t0; digits = 1), " s")
Y = simulation.integrator.u
p = simulation.integrator.p
t = simulation.integrator.t
FT = eltype(Y)

function measure(label, f::F, args...) where {F}
    t0 = time()
    f(args...)
    compile = time() - t0
    a1 = @allocated f(args...)
    a2 = @allocated f(args...)
    println(
        rpad(label, 40),
        " allocs ",
        a1,
        " / ",
        a2,
        "   first call ",
        round(compile; digits = 1),
        " s",
    )
    flush(stdout)
end

bracket_pair!(Yₜ, Y, p, source) =
    (CA.open_applied_update!(Yₜ, p, source); CA.close_applied_update!(Yₜ, Y, p, source))
snapshot_attribute!(Yₜ, Y, p, source) =
    (CA.snapshot_tags!(p, Yₜ, source); CA.attribute_tags!(Yₜ, Y, p, source))

Yₜ = zero(Y)
Yₜ_lim = zero(Y)
Y_work = copy(Y)

if with_tags
    measure("open/close radiation", bracket_pair!, Yₜ, Y, p, :radiation)
    measure("open/close surface_flux", bracket_pair!, Yₜ, Y, p, :surface_flux)
    measure("snapshot/attribute microphysics", snapshot_attribute!, Yₜ, Y, p, :microphysics)
    measure("energy_source_share_norm!", CA.energy_source_share_norm!, p, Y)
    measure("repair_energy_source_tags!", CA.repair_energy_source_tags!, Y_work, p)
    region_names = (:ρe_src_strat, :ρe_src_tropo)
    out = zero(Y.c.ρ)
    measure(
        "compute_e_src_res!",
        CA.Diagnostics.compute_e_src_res!,
        out,
        Y,
        p,
        t,
        region_names,
        FT(50000),
    )
    measure(
        "compute_e_src_fix!",
        CA.Diagnostics.compute_e_src_fix!,
        out,
        Y,
        p,
        t,
        :ρe_src_rad,
    )
    measure(
        "compute_process_record!",
        CA.Diagnostics.compute_process_record!,
        out,
        Y,
        p,
        t,
        :prc_e_radiation,
    )
end
measure(
    "vertical_advection_of_water_tendency!",
    CA.vertical_advection_of_water_tendency!,
    Yₜ,
    Y,
    p,
    t,
)
measure("constrain_state!", CA.constrain_state!, Y_work, p, t)
measure("set_precomputed_quantities!", CA.set_precomputed_quantities!, Y_work, p, t)
measure("implicit_tendency!", CA.implicit_tendency!, Yₜ, Y, p, t)
measure("remaining_tendency!", CA.remaining_tendency!, Yₜ, Yₜ_lim, Y, p, t)
println("names in Y.c: ", propertynames(Y.c))
