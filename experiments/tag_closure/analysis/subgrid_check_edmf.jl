#=
Build check: a PrognosticEDMFX column with energy source tags.

    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_check_edmf.jl novd
    julia +1.11 --project=.buildkite experiments/tag_closure/analysis/subgrid_check_edmf.jl vd

`novd`: the shipped DYCOMS RF02 EDMF column, 1M, with `edmfx_vertical_diffusion`
off. It steps three times, then measures what each SGS term does to the tags'
total `E = ρe_tot + c·ρ` against what it does to the partition.

`vd`: the same with `edmfx_vertical_diffusion` on, as every shipped EDMF config
has it. It builds the simulation and calls the SGS diffusive flux once, which is
where the code asks the updraft for a tag counterpart it does not carry.

No repository file is touched. Output goes to $SCRATCH/tag_closure/subgrid_checks.
=#
import ClimaAtmos as CA
using Printf

mode = get(ARGS, 1, "novd")
scratch = joinpath(get(ENV, "SCRATCH", tempdir()), "tag_closure", "subgrid_checks")
mkpath(scratch)
c = 110495.0

alt(z, above) = Dict{String, Any}(
    "type" => "tanh_altitude",
    "z_center" => z,
    "width" => 100.0,
    "above" => above,
)
tags = [
    Dict{String, Any}("name" => "strat", "region" => alt(750.0, true)),
    Dict{String, Any}("name" => "tropo", "region" => alt(750.0, false)),
    Dict{String, Any}("name" => "sfc", "source" => "surface_flux"),
    Dict{String, Any}("name" => "rad", "source" => "radiation"),
]

# `config/model_configs/prognostic_edmfx_dycoms_rf02_column.yml`, written out,
# with the tags, an offset, a short run and `rad: DYCOMS` added.
dict = Dict{String, Any}(
    "initial_condition" => "DYCOMS_RF02",
    "turbconv" => "prognostic_edmfx",
    "implicit_diffusion" => true,
    "approximate_linear_solve_iters" => 2,
    "edmfx_entr_model" => "Generalized",
    "edmfx_detr_model" => "Generalized",
    "edmfx_sgs_mass_flux" => true,
    "edmfx_sgs_diffusive_flux" => true,
    "edmfx_nh_pressure" => true,
    "edmfx_vertical_diffusion" => mode == "vd",
    "edmfx_filter" => true,
    "prognostic_tke" => true,
    "microphysics_model" => "1M",
    "config" => "column",
    "z_elem" => 30,
    "z_max" => 1500.0,
    "z_stretch" => false,
    "perturb_initstate" => false,
    "dt" => "120secs",
    "t_end" => "360secs",
    "toml" => ["toml/prognostic_edmfx_1M.toml"],
    "ode_algo" => "ARS222",
    "rad" => "DYCOMS",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => joinpath(scratch, "out_edmf_$mode"),
    "energy_source_tags" => tags,
    "energy_source_tag_offset" => c,
)

t0 = time()
sim = CA.get_simulation(CA.AtmosConfig(dict; job_id = "agentD_edmf_$mode"))
@printf("[%s] simulation built after %.0f s\n", mode, time() - t0)
Y = sim.integrator.u
p = sim.integrator.p
t = sim.integrator.t
tc = p.atmos.turbconv_model
println("[$mode] turbconv: ", nameof(typeof(tc)))
println("[$mode] updraft fields: ", propertynames(Y.c.sgsʲs.:(1)))
println("[$mode] tag fields in the updraft: ",
    filter(n -> startswith(string(n), "e_src"), propertynames(Y.c.sgsʲs.:(1))))

if mode == "vd"
    try
        CA.edmfx_sgs_diffusive_flux_tendency!(zero(Y), Y, p, t, tc)
        println("[vd] edmfx_sgs_diffusive_flux_tendency! ran without error")
    catch err
        println("[vd] edmfx_sgs_diffusive_flux_tendency! FAILED:")
        msg = sprint(showerror, err)
        println(first(msg, 1500))
    end
    @printf("[vd] done after %.0f s\n", time() - t0)
    exit()
end

result = CA.solve_atmos!(sim)
println("[novd] ret_code = ", result.ret_code)
@printf("[novd] solved after %.0f s\n", time() - t0)
Y = sim.integrator.u
t = sim.integrator.t
CA.set_precomputed_quantities!(Y, p, t)

E_of(Yₜ) = @. Yₜ.c.ρe_tot + c * Yₜ.c.ρ
part_of(Yₜ) = @. Yₜ.c.ρe_src_strat + Yₜ.c.ρe_src_tropo
gross(f) = sum(abs.(f))

function report(label, Yₜ)
    ᶜE = E_of(Yₜ)
    ᶜP = part_of(Yₜ)
    ᶜD = @. ᶜE - ᶜP
    @printf(
        "[novd] %-34s gross E-tendency %.4e  gross partition %.4e  gross miss %.4e  (miss/E %.3f)  signed E %.3e\n",
        label, gross(ᶜE), gross(ᶜP), gross(ᶜD),
        gross(ᶜD) / max(gross(ᶜE), eps()), sum(ᶜE),
    )
    return nothing
end

Yₜ = zero(Y)
CA.edmfx_sgs_mass_flux_tendency!(Yₜ, Y, p, t, tc)
report("SGS mass flux", Yₜ)
@printf("[novd]   of which c·ρ part: gross %.4e\n", gross(@. c * Yₜ.c.ρ))

Yₜ = zero(Y)
CA.edmfx_sgs_diffusive_flux_tendency!(Yₜ, Y, p, t, tc)
report("SGS diffusive flux (vertical)", Yₜ)

Yₜ = zero(Y)
CA.vertical_advection_of_water_tendency!(Yₜ, Y, p, t)
report("sedimentation, with EDMF corrections", Yₜ)

Yₜ = zero(Y)
CA.explicit_vertical_advection_tendency!(Yₜ, Y, p, t)
@printf("[novd] grid-mean vertical advection of the partition, gross %.4e\n",
    gross(part_of(Yₜ)))

ᶜres = @. Y.c.ρe_tot + c * Y.c.ρ - Y.c.ρe_src_strat - Y.c.ρe_src_tropo
@printf("[novd] closure after %.0f s: gross %.4e J, over gross E %.4e\n",
    t, gross(ᶜres), gross(@. Y.c.ρe_tot + c * Y.c.ρ))
for name in (:ρe_src_strat, :ρe_src_tropo, :ρe_src_sfc, :ρe_src_rad)
    @printf("[novd] min %-14s %.4e\n", name, minimum(parent(getproperty(Y.c, name))))
end
@printf("[novd] done after %.0f s\n", time() - t0)
