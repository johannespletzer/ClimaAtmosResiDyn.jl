#=
Where the energy source tags' closure residual comes from, operator by
operator, on a column.

    julia +1.11 --project=.buildkite \
        experiments/tag_closure/analysis/transport_ledger.jl [config] [steps] [spinup]

It builds the run a configuration describes, `configs/c6_column_no_repair.yml`
by default, and steps it, 360 steps by default, an hour on the DYCOMS column.
From step `spinup` on, 60 by default, it evaluates the model's own tendencies at
the state each step starts from, and splits `T_E - T_S`, the rate at which the
residual grows, into four parts:

  - `pressure`: the parent moves `h_tot`, the tags move energy. This is the
    vertical transport of `h_tot` minus that of `e_tot`, both with the parent's
    own upwinding;
  - `residual`: the vertical transport of the residual already there, which
    the parent carries and the tags do not. It also holds any difference
    between the parent's upwinding and the tags';
  - `limiter`: the tags' upwinding applied to their sum, minus it applied to
    each tag on its own. Zero for a scheme that is linear in the field;
  - `other`: everything else in the model's full tendencies. That is the
    brackets' attribution, and any process the tags do not see.

`T_E` is the tendency of the tags' total `E = ρe_tot + c·ρ`, and `T_S` that of
the sum of the pure region tags. The four parts add up to `T_E - T_S` exactly,
by construction. Each is accumulated as a field, times `dt`. At every report
the script compares their sum with how the residual `E - S` actually moved since
the spin-up ended. The difference is what an explicit Euler estimate at each
step's start cannot see: the implicit-explicit split of the step, the Newton
solve, and the stages in between. The spin-up keeps the initial adjustment out
of the comparison, since there the implicit solve moves energy very differently
from any estimate at a step's start.

Nothing crosses the column's top or bottom, so the column integral of any
vertical transport is zero. Every part is therefore reported by its gross
integral, the column integral of its absolute value, in J/m². That is the
quantity in the closure table's `gross_residual`. `other` is also reported
signed, because the brackets' part of it has a direction. For each part, the
`_slope` column is the regression slope of the actual change on that part,
`∫ Δr · part / ∫ part²`. It is near 1 where the part explains the change in
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
import ClimaTimeSteppers as CTS

const CONFIG =
    get(ARGS, 1, "experiments/tag_closure/configs/c6_column_no_repair.yml")
const STEPS = parse(Int, get(ARGS, 2, "360"))
const SPINUP = parse(Int, get(ARGS, 3, "60"))
const REPORT_EVERY = 30
# Kept after the run: `mktempdir` would otherwise delete it, and the table with it.
const OUT = mktempdir(get(ENV, "LEDGER_DIR", tempdir()); cleanup = false)

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

# The model's own tendencies at `Y`, into four zeroed copies of the state: the
# explicit ones, the ones that are limited afterwards, the implicit ones, and
# the correction applied after the Newton solve.
function model_tendencies!(tendencies, Y, p, t)
    (; explicit, limited, implicit, corrected) = tendencies
    CA.set_precomputed_quantities!(Y, p, t)
    for x in (explicit, limited, implicit, corrected)
        x .= zero(eltype(x))
    end
    CA.remaining_tendency!(explicit, limited, Y, p, t)
    CA.implicit_tendency!(implicit, Y, p, t)
    p.atmos.numerics.energy_q_tot_upwinding isa Val{:none} ||
        CA.correct_implicit_advection_tendency!(corrected, Y, p, t)
    return nothing
end

# The four parts of `T_E - T_S` at `Y`, into `rates`. `vertical_transport`
# returns a lazy broadcast, so it is called outside `@.` and the result added,
# as the model's own tendencies do.
function rates!(rates, tendencies, Y, p, t, names, c)
    model_tendencies!(tendencies, Y, p, t)
    (; explicit, limited, implicit, corrected) = tendencies
    (; e, chi, sum_chi, total_e, total_s) = rates
    ᶜρ = Y.c.ρ
    ᶠu³ = p.precomputed.ᶠu³
    ᶜh = p.precomputed.ᶜh_tot
    dt = p.dt
    energy_up = p.atmos.numerics.energy_q_tot_upwinding
    tracer_up = p.atmos.numerics.tracer_upwinding

    # The parent's vertical transport: `h_tot` with its own upwinding, and the
    # offset's `c·ρ` with the mass, which moves centrally.
    mass = CA.vertical_transport(ᶜρ, ᶠu³, rates.one, dt, Val(:none))
    of_h = CA.vertical_transport(ᶜρ, ᶠu³, ᶜh, dt, energy_up)
    @. rates.parent = of_h + c * mass
    @. e = Y.c.ρe_tot / ᶜρ
    of_e = CA.vertical_transport(ᶜρ, ᶠu³, e, dt, energy_up)
    @. rates.parent_e = of_e + c * mass

    # The tags' vertical transport, each on its own and of their sum.
    sum_chi .= zero(eltype(sum_chi))
    rates.tags .= zero(eltype(rates.tags))
    for name in names
        ᶜρe_src = getproperty(Y.c, name)
        @. chi = ᶜρe_src / ᶜρ
        @. sum_chi += chi
        of_tag = CA.vertical_transport(ᶜρ, ᶠu³, chi, dt, tracer_up)
        @. rates.tags += of_tag
    end
    of_sum = CA.vertical_transport(ᶜρ, ᶠu³, sum_chi, dt, tracer_up)
    @. rates.tags_of_sum = of_sum

    # The full tendencies of `E` and of the partition's sum.
    @. total_e =
        explicit.c.ρe_tot +
        limited.c.ρe_tot +
        implicit.c.ρe_tot +
        corrected.c.ρe_tot +
        c * (explicit.c.ρ + limited.c.ρ + implicit.c.ρ + corrected.c.ρ)
    total_s .= zero(eltype(total_s))
    for x in (explicit, limited, implicit, corrected), name in names
        tendency = getproperty(x.c, name)
        @. total_s += tendency
    end

    @. rates.pressure = rates.parent - rates.parent_e
    @. rates.residual = rates.parent_e - rates.tags_of_sum
    @. rates.limiter = rates.tags_of_sum - rates.tags
    @. rates.other = (total_e - total_s) - (rates.parent - rates.tags)
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
# The regression slope of `y` on `x` over the column.
slope(y, x) = (s = sum(x .* x); iszero(s) ? zero(s) : sum(y .* x) / s)

function main()
    run = simulation("transport_ledger")
    calculator = simulation("transport_ledger_calculator")
    integrator = run.integrator
    Y = integrator.u
    Yc, pc = calculator.integrator.u, calculator.integrator.p
    CA.do_dss(axes(Y.c)) && error(
        "transport_ledger.jl splits vertical transport only; run it on a column.",
    )
    model = pc.atmos.energy_source_tagging_model
    names = CA.energy_source_region_tag_state_names(model)
    c = something(model.offset, 0.0)

    field() = zero.(Y.c.ρ)
    parts = (:pressure, :residual, :limiter, :other)
    rates = (;
        one = one.(Y.c.ρ),
        e = field(),
        chi = field(),
        parent = field(),
        parent_e = field(),
        tags = field(),
        tags_of_sum = field(),
        sum_chi = field(),
        total_e = field(),
        total_s = field(),
        (part => field() for part in parts)...,
    )
    tendencies = (;
        explicit = similar(Y),
        limited = similar(Y),
        implicit = similar(Y),
        corrected = similar(Y),
    )
    accumulated = NamedTuple{parts}(Tuple(field() for _ in parts))
    r₀ = field()
    r = field()
    Δr = field()
    predicted = field()

    header = [
        "time",
        "moved",
        "moved_signed",
        "pressure",
        "residual",
        "limiter",
        "other",
        "other_signed",
        "sum_of_parts",
        "unexplained",
        "pressure_slope",
        "limiter_slope",
        "sum_slope",
    ]
    rows = Vector{Vector{Float64}}()
    println(
        "config: $CONFIG; $STEPS steps, ledger from step $SPINUP; offset $c J/kg; tags $(join(names, ", "))",
    )
    println("gross column integrals in J/m², since the spin-up ended:")
    println("  ", join(header, "  "))
    for step in 1:STEPS
        if step > SPINUP
            Yc .= Y
            rates!(rates, tendencies, Yc, pc, integrator.t, names, c)
            dt = float(pc.dt)
            for part in parts
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
        @. predicted =
            accumulated.pressure +
            accumulated.residual +
            accumulated.limiter +
            accumulated.other
        row = [
            float(integrator.t),
            gross(Δr),
            sum(Δr),
            gross(accumulated.pressure),
            gross(accumulated.residual),
            gross(accumulated.limiter),
            gross(accumulated.other),
            sum(accumulated.other),
            gross(predicted),
            gross(Δr .- predicted),
            slope(Δr, accumulated.pressure),
            slope(Δr, accumulated.limiter),
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
            "# gross column integrals in J/m² since the spin-up, `_signed` ones signed, `_slope` regression slopes",
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
