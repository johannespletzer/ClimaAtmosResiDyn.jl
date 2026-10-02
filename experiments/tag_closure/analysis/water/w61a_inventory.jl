#=
W61 addendum (design/W61_ADDENDUM.md on claude/rec-wp4b): the per-tag
inventory change from the hyperdiffusion's reference term, and a face-
allocation arm. W61's sphere: the moist baroclinic wave, h_elem 6, 10 levels,
1M, dt 400 s, ARS343, 3 days, region tags tropics and extratropics with
`water_tag_precipitation: true`.

    julia --project=<env> w61a_inventory.jl <label> <out_dir>

Every step, on the step's end state, it evaluates each tag's reference term
in both forms, with the model's operators and DSS:

  - passive (the PR): R = φ ν₄ ∇⋅(ρ ∇ L_r),   L_r = DSS ∇² q_tot_r
  - face (the arm):   R = ν₄ ∇⋅(φ ρ ∇ L_r)

and adds `dt ∫R dV` and `dt ∫|R| dV` to running totals, and `dt` times each
tag's surface precipitation (`water_tag_precipitation_flux!`) to its export.
One evaluation per step, at the step's end: a rectangle rule, for the size,
not the exact budget. Every 6 hours it writes the totals, each tag's
inventory (its three parts), the variance rate `∫ χ T dV` of the passive,
face and cross forms on the state, and the run's ledgers.
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
    "config" => "sphere", "h_elem" => 6, "nh_poly" => 3, "z_elem" => 10,
    "z_max" => 30000.0, "dz_bottom" => 500.0, "dt" => "400secs",
    "ode_algo" => "ARS343", "rayleigh_sponge" => false, "viscous_sponge" => false,
    "initial_condition" => "MoistBaroclinicWave", "cloud_model" => "grid_scale",
    "microphysics_model" => "1M", "hyperdiff" => "Hyperdiffusion",
    "t_end" => "$(days)days", "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false, "log_progress" => false,
    "output_dir" => joinpath(out, "run"),
    "water_tracers" => [
        Dict{String, Any}("name" => "tropics", "region" => "tropics"),
        Dict{String, Any}("name" => "extratropics", "region" => "extratropics"),
    ],
    "water_tag_precipitation" => true,
)
sim = CA.get_simulation(CA.AtmosConfig(config; job_id = "w61a_$label"))
integ = sim.integrator
p = integ.p
tags = p.atmos.water_tagging_model.tags
names = map(CA.tag_name, tags)
thermo_params = CA.Parameters.thermodynamics_params(p.params)
dss!(x) = Spaces.weighted_dss!(x)
const wdivₕ = CA.wdivₕ
const gradₕ = CA.gradₕ
dt = float(integ.dt)
sfc = similar(p.precomputed.surface_rain_flux)
acc = Dict(
    (n, k) => 0.0 for n in names for
    k in (:pass, :pass_abs, :face, :face_abs, :export)
)

inventory(Y, n) =
    sum(getproperty(Y.c, Symbol(:ρq_tag_, n))) +
    sum(getproperty(Y.c, Symbol(:ρq_rtag_, n))) +
    sum(getproperty(Y.c, Symbol(:ρq_stag_, n)))

function reference_terms(Y, p)
    (; ν₄_scalar) = CA.ν₄(p.atmos.hyperdiff, Y)
    ρ = Y.c.ρ
    ᶜq_r = @. CA.q_tot_r(thermo_params, p.precomputed.ᶜp)
    L_r = @. wdivₕ(gradₕ(ᶜq_r))
    dss!(L_r)
    H_r = @. ν₄_scalar * wdivₕ(ρ * gradₕ(L_r))
    CA.water_tag_share_norm!(p, Y)
    terms = map(tags) do tag
        φ = similar(ρ)
        φ .= CA.water_tag_part_share(Y.c, p.scratch, tag, CA.NonPrecipitatingPart())
        R_pass = @. φ * H_r
        R_face = @. ν₄_scalar * wdivₕ(φ * ρ * gradₕ(L_r))
        dss!(R_pass)
        dss!(R_face)
        (; φ, R_pass, R_face)
    end
    return (; ν₄_scalar, ᶜq_r, L_r, terms)
end

function variance_rates(Y, p, ref)
    ρ = Y.c.ρ
    (; ν₄_scalar, ᶜq_r, L_r, terms) = ref
    rows = String[]
    for (tag, term) in zip(tags, terms)
        n = CA.tag_name(tag)
        χ = @. getproperty(Y.c, Symbol(:ρq_tag_, n)) / ρ
        L_i = @. wdivₕ(gradₕ(χ))
        dss!(L_i)
        L_x = @. wdivₕ(gradₕ(χ - term.φ * ᶜq_r))
        dss!(L_x)
        base = @. -ν₄_scalar * wdivₕ(ρ * gradₕ(L_i))
        dss!(base)
        T_cross = @. -ν₄_scalar * wdivₕ(ρ * gradₕ(L_x))
        dss!(T_cross)
        T_pass = @. base + term.R_pass
        T_face = @. base + term.R_face
        push!(
            rows,
            join(string.((n, sum(χ .* T_pass), sum(χ .* T_face), sum(χ .* T_cross))), ","),
        )
    end
    return rows
end

open(joinpath(out, "inventory.csv"), "w") do io
    println(io, "t,tag,inventory,ref_pass,ref_pass_abs,ref_face,ref_face_abs,export")
end
open(joinpath(out, "variance.csv"), "w") do io
    println(io, "t,tag,var_pass,var_face,var_cross")
end
open(joinpath(out, "ledgers.csv"), "w") do io
    println(io, "t,led_repair,led_repairnet,led_rescale,led_empty")
end
function record(integ, ref)
    Y = integ.u
    t = float(integ.t)
    open(joinpath(out, "inventory.csv"), "a") do io
        for n in names
            println(
                io,
                join(
                    string.((
                        t,
                        n,
                        inventory(Y, n),
                        acc[(n, :pass)],
                        acc[(n, :pass_abs)],
                        acc[(n, :face)],
                        acc[(n, :face_abs)],
                        acc[(n, :export)],
                    )),
                    ",",
                ),
            )
        end
    end
    open(
        io -> foreach(r -> println(io, "$t,", r), variance_rates(Y, integ.p, ref)),
        joinpath(out, "variance.csv"),
        "a",
    )
    led = map(
        k -> sum(getproperty(Y.c, k)),
        (:q_tag_led_repair, :q_tag_led_repairnet, :q_tag_led_rescale, :q_tag_led_empty),
    )
    open(
        io -> println(io, join(string.((t, led...)), ",")),
        joinpath(out, "ledgers.csv"),
        "a",
    )
    @info "sampled" t
end

CA.set_precomputed_quantities!(integ.u, p, integ.t)
record(integ, reference_terms(integ.u, p))
every = round(Int, 6 * 3600 / dt)
nsteps = round(Int, days * 86400 / dt)
t0 = time()
for k in 1:nsteps
    CTS.step!(integ)
    Y = integ.u
    CA.set_precomputed_quantities!(Y, p, integ.t)
    ref = reference_terms(Y, p)
    for (tag, term) in zip(tags, ref.terms)
        n = CA.tag_name(tag)
        acc[(n, :pass)] += dt * sum(term.R_pass)
        acc[(n, :pass_abs)] += dt * sum(abs.(term.R_pass))
        acc[(n, :face)] += dt * sum(term.R_face)
        acc[(n, :face_abs)] += dt * sum(abs.(term.R_face))
        CA.water_tag_precipitation_flux!(sfc, Y, p, tag)
        acc[(n, :export)] += -dt * sum(sfc)
    end
    k % every == 0 &&
        (record(integ, ref); @info "progress" k nsteps wall = round(time() - t0))
end
@info "done" label wall = round(time() - t0)
