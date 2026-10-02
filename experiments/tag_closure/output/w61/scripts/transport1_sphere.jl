#=
transport-1 of the WP4b stage-1 review, measured on a sphere (WP4b fix PR,
claude/wp4b-fix). The moist baroclinic wave at h_elem 6, 10 levels, 1M, with
two region tags (tropics, extratropics) and `water_tag_precipitation: true`.

    julia --project=<env> transport1_sphere.jl <label> <out_dir>

Every 6 hours, on the run's own state, it evaluates both forms of the tags'
hyperdiffusion by hand, with the model's operators and DSS:

  - cross   (main d3c5e42f): -ν ∇⋅(ρ∇ DSS ∇²(N_i/ρ - φ_i q_tot_r))
  - passive (the fix):       -ν ∇⋅(ρ∇ DSS ∇²(N_i/ρ)) + φ_i ν ∇⋅(ρ∇ DSS ∇² q_tot_r)

and the model's own tag tendency, which must equal one of them. It writes per
tag: the variance tendency ∫ χ_i T dV of each form (negative is diffusive), the
relative L1 difference of the forms, the water each form would take below zero
in one step, and the volume fraction where q_tot_eff < q_tot_r. It also writes
the run's own cumulative ledgers (repair, rescale, empty) as domain integrals,
and the partition's L1 residual of N. The model's fields do not depend on the
tags, so two runs that differ only by the form share one atmosphere.
=#
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaCore: Fields, Spaces
import ClimaTimeSteppers as CTS

label, out = ARGS[1], ARGS[2]
days = parse(Float64, get(ENV, "DAYS", "3"))
mkpath(out)
config = Dict{String, Any}(
    "config" => "sphere",
    "h_elem" => 6,
    "nh_poly" => 3,
    "z_elem" => 10,
    "z_max" => 30000.0,
    "dz_bottom" => 500.0,
    "dt" => get(ENV, "DT", "400secs"),
    "ode_algo" => "ARS343",
    "rayleigh_sponge" => false,
    "viscous_sponge" => false,
    "initial_condition" => "MoistBaroclinicWave",
    "cloud_model" => "grid_scale",
    "microphysics_model" => "1M",
    "hyperdiff" => "Hyperdiffusion",
    "t_end" => "$(days)days",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "log_progress" => false,
    "output_dir" => joinpath(out, "run"),
    "water_tracers" => [
        Dict{String, Any}("name" => "tropics", "region" => "tropics"),
        Dict{String, Any}("name" => "extratropics", "region" => "extratropics"),
    ],
    "water_tag_precipitation" => true,
)
sim = CA.get_simulation(CA.AtmosConfig(config; job_id = "transport1_$label"))
integ = sim.integrator
p = integ.p
model = p.atmos.water_tagging_model
tags = model.tags
thermo_params = CA.Parameters.thermodynamics_params(p.params)
dss!(x) = Spaces.weighted_dss!(x)
const wdivₕ = CA.wdivₕ
const gradₕ = CA.gradₕ

function sample(integ)
    Y = integ.u
    p = integ.p
    t = integ.t
    CA.set_precomputed_quantities!(Y, p, t)
    (; ν₄_scalar) = CA.ν₄(p.atmos.hyperdiff, Y)
    ᶜp = p.precomputed.ᶜp
    ρ = Y.c.ρ
    ᶜq_r = @. CA.q_tot_r(thermo_params, ᶜp)
    ᶜN = @. Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno
    ᶜq = @. ᶜN / ρ
    ᶜone = Fields.ones(axes(ρ))
    volume = sum(ᶜone)
    below = sum(@. ifelse(ᶜq < ᶜq_r, 1.0, 0.0)) / volume
    # The model's own tendencies of the tags.
    Yₜ = zero(Y)
    Yₜ_lim = zero(Y)
    CA.hyperdiffusion_tendency!(Yₜ, Yₜ_lim, Y, p, t)
    Yₜ .+= Yₜ_lim
    CA.dss!(Yₜ, p, t)
    CA.water_tag_share_norm!(p, Y)
    L_r = @. wdivₕ(gradₕ(ᶜq_r))
    dss!(L_r)
    H_r = @. ν₄_scalar * wdivₕ(ρ * gradₕ(L_r))
    rows = String[]
    for (k, tag) in enumerate(tags)
        name = CA.tag_name(tag)
        ᶜρq = getproperty(Y.c, Symbol(:ρq_tag_, name))
        φ = similar(ρ)
        φ .= CA.water_tag_part_share(Y.c, p.scratch, tag, CA.NonPrecipitatingPart())
        χ = @. ᶜρq / ρ
        L_i = @. wdivₕ(gradₕ(χ))
        dss!(L_i)
        L_x = @. wdivₕ(gradₕ(χ - φ * ᶜq_r))
        dss!(L_x)
        T_pas = @. -ν₄_scalar * wdivₕ(ρ * gradₕ(L_i)) + φ * H_r
        T_cross = @. -ν₄_scalar * wdivₕ(ρ * gradₕ(L_x))
        dss!(T_pas)
        dss!(T_cross)
        T_model = getproperty(Yₜ.c, Symbol(:ρq_tag_, name))
        scale = sum(abs.(T_pas))
        model_vs_cross = sum(abs.(T_model .- T_cross)) / scale
        model_vs_passive = sum(abs.(T_model .- T_pas)) / scale
        var_cross = sum(χ .* T_cross)
        var_pas = sum(χ .* T_pas)
        diff_rel = sum(abs.(T_cross .- T_pas)) / scale
        dt = float(integ.dt)
        neg_cross = sum(@. max(-(ᶜρq + dt * T_cross), 0))
        neg_pas = sum(@. max(-(ᶜρq + dt * T_pas), 0))
        held = sum(@. max(ᶜρq, 0))
        push!(
            rows,
            join(
                string.((
                    float(t), name, below, var_cross, var_pas, diff_rel,
                    neg_cross, neg_pas, held, model_vs_cross, model_vs_passive,
                )),
                ",",
            ),
        )
    end
    # The run's own ledgers and the partition's residual of `N`.
    parts = zero(ρ)
    for tag in tags
        parts .+= getproperty(Y.c, Symbol(:ρq_tag_, CA.tag_name(tag)))
    end
    resN = sum(@. abs(max(ᶜN, 0) - parts))
    minN = minimum(
        minimum(parent(getproperty(Y.c, Symbol(:ρq_tag_, CA.tag_name(tag))))) for
        tag in tags
    )
    ledgers = map(
        name -> sum(getproperty(Y.c, name)),
        (:q_tag_led_repair, :q_tag_led_repairnet, :q_tag_led_rescale, :q_tag_led_empty),
    )
    led = join(string.((float(t), ledgers..., resN, sum(@. max(ᶜN, 0)), minN)), ",")
    return rows, led
end

open(joinpath(out, "forms.csv"), "w") do io
    println(io, "t,tag,frac_below_qr,var_cross,var_passive,l1_diff_rel,neg_cross,neg_passive,held,model_vs_cross,model_vs_passive")
end
open(joinpath(out, "ledgers.csv"), "w") do io
    println(io, "t,led_repair,led_repairnet,led_rescale,led_empty,l1_res_N,N_pos,min_N_part")
end
function record(integ)
    rows, led = sample(integ)
    open(io -> foreach(r -> println(io, r), rows), joinpath(out, "forms.csv"), "a")
    open(io -> println(io, led), joinpath(out, "ledgers.csv"), "a")
    @info "sampled" t = float(integ.t) led
    flush(stderr)
end
record(integ)
dt = float(integ.dt)
every = round(Int, 6 * 3600 / dt)
nsteps = round(Int, days * 86400 / dt)
t0 = time()
for k in 1:nsteps
    CTS.step!(integ)
    if k % every == 0
        record(integ)
        @info "progress" k nsteps wall = round(time() - t0)
    end
end
@info "done" label wall = round(time() - t0)
