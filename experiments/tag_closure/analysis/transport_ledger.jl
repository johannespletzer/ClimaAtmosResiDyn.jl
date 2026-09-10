#=
Where the energy source tags' closure residual comes from, operator by
operator, on a column or a sphere.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/transport_ledger.jl [config] [steps] [spinup]

It builds the run a configuration describes, `configs/c6_column_no_repair.yml`
by default, and steps it, 360 steps by default. From step `spinup` on, 60 by
default, it evaluates the model's own tendencies at the state each step starts
from, and splits `T_E - T_S`, the rate at which the residual grows, into parts:

  - `pressure_v`: the parent moves `h_tot` vertically, the tags move energy.
    This is the vertical transport of `h_tot` minus that of `e_tot`, both with
    the parent's own upwinding;
  - `residual_v`: the vertical transport of the residual already there, which
    the parent carries and the tags do not. It also holds any difference
    between the parent's upwinding and the tags';
  - `limiter`: the tags' vertical upwinding applied to their sum, minus it
    applied to each tag on its own. Zero for a scheme that is linear;
  - `pressure_h` and `residual_h`: the same two splits for horizontal
    transport. `split_divₕ` is linear in the transported field, so there is no
    horizontal limiter part;
  - `hyperdiffusion`: the parent's hyperdiffusion of `E` minus the tags';
  - `other`: everything else in the model's full tendencies. That is the
    brackets' attribution, and any process the tags do not see.

A column has no horizontal transport and no hyperdiffusion, so there those
parts are zero.

`T_E` is the tendency of the tags' total `E = ρe_tot + c·ρ`, and `T_S` that of
the sum of the pure region tags. The parts add up to `T_E - T_S` exactly, by
construction. Each is accumulated as a field, times `dt`. On a sphere each rate
is passed through the weighted DSS first, as the stepper does to the state, so
that it can be compared with the state point by point. At every report the
script compares the sum of the parts with how the residual `E - S` actually
moved since the spin-up ended. The difference is what an explicit Euler
estimate at each step's start cannot see: the implicit-explicit split of the
step, the Newton solve, and the stages in between. The spin-up keeps the
initial adjustment out of the comparison.

Nothing crosses the domain's top or bottom, and a sphere has no sides, so the
domain integral of any transport is zero. Every part is therefore reported by
its gross integral, the domain integral of its absolute value, in J (per m² of
a column). That is the quantity in the closure table's `gross_residual`.
`other` is also reported signed, because the brackets' part of it has a
direction. The `_slope` columns are regression slopes of the actual change on a
part, `∫ Δr · part / ∫ part²`, near 1 where the part explains the change in
shape as well as in size.

The rates are computed on a second simulation of the same configuration, the
calculator, which is given the run's state before each evaluation and is
stepped alongside it so that its callbacks keep its caches current. The run
itself is only stepped and read, so measuring cannot change it. A first
version computed the rates on the run's own cache, and that run ended in a
different state from an identical one stepped plainly.

The repair is switched off whatever the configuration says, so that the tags
move as the rule and their transport make them.
=#

import ClimaComms as CC
CC.@import_required_backends
import ClimaAtmos as CA
import ClimaCore: Spaces
import ClimaTimeSteppers as CTS

const CONFIG =
    get(ARGS, 1, "experiments/tag_closure/configs/c6_column_no_repair.yml")
const STEPS = parse(Int, get(ARGS, 2, "360"))
const SPINUP = parse(Int, get(ARGS, 3, "60"))
const REPORT_EVERY = parse(Int, get(ENV, "LEDGER_REPORT_EVERY", "30"))
# Kept after the run: `mktempdir` would otherwise delete it, and the table with it.
const OUT = mktempdir(get(ENV, "LEDGER_DIR", tempdir()); cleanup = false)
const split_divₕ = CA.split_divₕ
const PARTS = (
    :pressure_v,
    :residual_v,
    :limiter,
    :pressure_h,
    :residual_h,
    :hyperdiffusion,
    :other,
)

function simulation(name)
    config = CA.load_yaml_file(CONFIG)
    merge!(
        config,
        Dict{String, Any}(
            "job_id" => name,
            "output_dir" => joinpath(OUT, name),
            "energy_source_tag_repair" => false,
            "output_default_diagnostics" => false,
            "diagnostics" => [],
        ),
    )
    return CA.get_simulation(CA.AtmosConfig(config))
end

zero!(x) = (x .= zero(eltype(x)); x)

# The model's own tendencies at `Y`, into zeroed copies of the state: the
# explicit ones, the ones that are limited afterwards, the implicit ones, the
# correction applied after the Newton solve, and hyperdiffusion on its own.
function model_tendencies!(tendencies, Y, p, t)
    (; explicit, limited, implicit, corrected, hyper, hyper_limited) =
        tendencies
    CA.set_precomputed_quantities!(Y, p, t)
    foreach(zero!, values(tendencies))
    CA.remaining_tendency!(explicit, limited, Y, p, t)
    CA.implicit_tendency!(implicit, Y, p, t)
    p.atmos.numerics.energy_q_tot_upwinding isa Val{:none} ||
        CA.correct_implicit_advection_tendency!(corrected, Y, p, t)
    CA.hyperdiffusion_tendency!(hyper, hyper_limited, Y, p, t)
    return nothing
end

# The tendency of `E` and of the partition's sum in the given state tendencies.
function e_and_s!(te, ts, tendencies, names, c)
    zero!(te)
    zero!(ts)
    for x in tendencies
        @. te += x.c.ρe_tot + c * x.c.ρ
        for name in names
            tendency = getproperty(x.c, name)
            @. ts += tendency
        end
    end
    return nothing
end

# The parts of `T_E - T_S` at `Y`, into `rates`. `vertical_transport` returns a
# lazy broadcast, so it is called outside `@.` and the result added, as the
# model's own tendencies do.
function rates!(rates, tendencies, Y, p, t, names, c, horizontal)
    model_tendencies!(tendencies, Y, p, t)
    (; explicit, limited, implicit, corrected, hyper, hyper_limited) =
        tendencies
    (; e, chi, sum_chi, total_e, total_s, hyper_e, hyper_s) = rates
    ᶜρ = Y.c.ρ
    ᶠu³ = p.precomputed.ᶠu³
    ᶜu = p.precomputed.ᶜu
    ᶜh = p.precomputed.ᶜh_tot
    dt = p.dt
    energy_up = p.atmos.numerics.energy_q_tot_upwinding
    tracer_up = p.atmos.numerics.tracer_upwinding

    @. e = Y.c.ρe_tot / ᶜρ
    zero!(sum_chi)
    for name in names
        ᶜρe_src = getproperty(Y.c, name)
        @. sum_chi += ᶜρe_src / ᶜρ
    end

    # Vertically, the parent moves `h_tot` with its own upwinding and the
    # offset's `c·ρ` with the mass, which moves centrally.
    mass = CA.vertical_transport(ᶜρ, ᶠu³, rates.one, dt, Val(:none))
    of_h = CA.vertical_transport(ᶜρ, ᶠu³, ᶜh, dt, energy_up)
    of_e = CA.vertical_transport(ᶜρ, ᶠu³, e, dt, energy_up)
    of_sum = CA.vertical_transport(ᶜρ, ᶠu³, sum_chi, dt, tracer_up)
    @. rates.parent_v = of_h + c * mass
    @. rates.parent_e_v = of_e + c * mass
    @. rates.tags_of_sum_v = of_sum
    zero!(rates.tags_v)
    for name in names
        ᶜρe_src = getproperty(Y.c, name)
        @. chi = ᶜρe_src / ᶜρ
        of_tag = CA.vertical_transport(ᶜρ, ᶠu³, chi, dt, tracer_up)
        @. rates.tags_v += of_tag
    end
    @. rates.pressure_v = rates.parent_v - rates.parent_e_v
    @. rates.residual_v = rates.parent_e_v - rates.tags_of_sum_v
    @. rates.limiter = rates.tags_of_sum_v - rates.tags_v

    # Horizontally, the parent moves `h_tot` and `c` with the mass flux, and
    # each tag its own specific value. `split_divₕ` is linear in that value, so
    # the tags' sum moves as their sum.
    if horizontal
        @. rates.parent_h =
            -split_divₕ(ᶜρ * ᶜu, ᶜh) - c * split_divₕ(ᶜρ * ᶜu, 1)
        @. rates.pressure_h =
            split_divₕ(ᶜρ * ᶜu, e) - split_divₕ(ᶜρ * ᶜu, ᶜh)
        @. rates.residual_h =
            -split_divₕ(ᶜρ * ᶜu, e) - c * split_divₕ(ᶜρ * ᶜu, 1) +
            split_divₕ(ᶜρ * ᶜu, sum_chi)
        @. rates.tags_h = -split_divₕ(ᶜρ * ᶜu, sum_chi)
    else
        foreach(
            zero!,
            (rates.parent_h, rates.pressure_h, rates.residual_h, rates.tags_h),
        )
    end

    # Hyperdiffusion, and the full tendencies.
    e_and_s!(hyper_e, hyper_s, (hyper, hyper_limited), names, c)
    @. rates.hyperdiffusion = hyper_e - hyper_s
    e_and_s!(total_e, total_s, (explicit, limited, implicit, corrected), names, c)
    @. rates.other =
        (total_e - total_s) - (rates.parent_v - rates.tags_v) -
        (rates.parent_h - rates.tags_h) - rates.hyperdiffusion
    return nothing
end

function residual!(r, Y, names, c)
    @. r = Y.c.ρe_tot + c * Y.c.ρ
    for name in names
        ᶜρe_src = getproperty(Y.c, name)
        @. r -= ᶜρe_src
    end
    return r
end

gross(x) = sum(abs.(x))
# The regression slope of `y` on `x` over the domain.
slope(y, x) = (s = sum(x .* x); iszero(s) ? zero(s) : sum(y .* x) / s)

function main()
    run = simulation("transport_ledger")
    calculator = simulation("transport_ledger_calculator")
    integrator = run.integrator
    Y = integrator.u
    Yc, pc = calculator.integrator.u, calculator.integrator.p
    model = pc.atmos.energy_source_tagging_model
    names = CA.energy_source_region_tag_state_names(model)
    c = something(model.offset, 0.0)
    horizontal = CA.do_dss(axes(Y.c))

    field() = zero.(Y.c.ρ)
    work = (
        :e,
        :chi,
        :sum_chi,
        :total_e,
        :total_s,
        :hyper_e,
        :hyper_s,
        :parent_v,
        :parent_e_v,
        :tags_v,
        :tags_of_sum_v,
        :parent_h,
        :tags_h,
    )
    rates = (;
        one = one.(Y.c.ρ),
        (name => field() for name in work)...,
        (part => field() for part in PARTS)...,
    )
    tendencies = (;
        explicit = similar(Y),
        limited = similar(Y),
        implicit = similar(Y),
        corrected = similar(Y),
        hyper = similar(Y),
        hyper_limited = similar(Y),
    )
    buffer = horizontal ? Spaces.create_dss_buffer(field()) : nothing
    accumulated = NamedTuple{PARTS}(Tuple(field() for _ in PARTS))
    r₀ = field()
    r = field()
    Δr = field()
    predicted = field()

    header = [
        "time",
        "moved",
        "moved_signed",
        (string(part) for part in PARTS)...,
        "other_signed",
        "sum_of_parts",
        "unexplained",
        "pressure_v_slope",
        "pressure_h_slope",
        "hyperdiffusion_slope",
        "sum_slope",
    ]
    rows = Vector{Vector{Float64}}()
    println(
        "config: $CONFIG; $STEPS steps, ledger from step $SPINUP; offset $c J/kg; tags $(join(names, ", ")); horizontal parts: $horizontal",
    )
    println("gross integrals since the spin-up ended:")
    println("  ", join(header, "  "))
    for step in 1:STEPS
        if step > SPINUP
            Yc .= Y
            rates!(rates, tendencies, Yc, pc, integrator.t, names, c, horizontal)
            dt = float(pc.dt)
            for part in PARTS
                horizontal && Spaces.weighted_dss!(rates[part] => buffer)
                @. accumulated[part] += dt * rates[part]
            end
        end
        Yc .= Y
        CTS.step!(integrator)
        CTS.step!(calculator.integrator)
        step == SPINUP && residual!(r₀, Y, names, c)
        step > SPINUP || continue
        (step - SPINUP) % REPORT_EVERY == 0 || step == STEPS || continue
        residual!(r, Y, names, c)
        @. Δr = r - r₀
        predicted .= zero(eltype(predicted))
        for part in PARTS
            @. predicted += accumulated[part]
        end
        row = [
            float(integrator.t),
            gross(Δr),
            sum(Δr),
            (gross(accumulated[part]) for part in PARTS)...,
            sum(accumulated.other),
            gross(predicted),
            gross(Δr .- predicted),
            slope(Δr, accumulated.pressure_v),
            slope(Δr, accumulated.pressure_h),
            slope(Δr, accumulated.hyperdiffusion),
            slope(Δr, predicted),
        ]
        push!(rows, row)
        println("  ", join(round.(row; sigdigits = 4), "  "))
    end

    path = joinpath(OUT, "transport_ledger.csv")
    open(path, "w") do io
        println(io, "# transport_ledger.csv, from analysis/transport_ledger.jl")
        println(io, "# config: $CONFIG; ledger from step $SPINUP; offset $c J/kg")
        println(
            io,
            "# gross integrals since the spin-up, `_signed` ones signed, `_slope` regression slopes",
        )
        println(io, join(header, ','))
        foreach(row -> println(io, join(row, ',')), rows)
    end
    println("wrote $path")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
