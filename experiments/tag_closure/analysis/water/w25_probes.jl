# W25's isolation (design/W25_ISOLATION.md): three probes on D4-W, each on one
# parent state, so that the tags' numerics are measured apart from a change of
# the atmosphere.
#
#   PROBE=fixed_parent|refinement|first_step CONFIG=<configs/*.yml> OUTDIR=<dir> \
#       julia --project=<the W25 run tree's .buildkite> w25_probes.jl
#
# fixed_parent  The reference is CONFIG with NREF (10) Newton iterations. At
#               every step it copies the reference's state into trials with
#               TRIALS (1,2) iterations, refreshes their cache, steps all, and
#               writes per step, for the parent `ρq_tot` and each tag, the
#               error `Σ|ρq_trial − ρq_ref|` and the increment `Σ|ρq_ref − ρq(Yₖ)|`,
#               and for each state ledger its change over the step in each run.
#               To T_END (6 h). As `w5v_same_atmosphere.jl`, whose cache
#               refresh it reuses.
# refinement    Runs CONFIG to T0 (6 h), keeps the state, and from it runs each
#               VARIANT `dt:newton` (120:1,120:2,120:10,60:1,30:1) for INTERVAL
#               (1 h). Writes, per variant, each state ledger's per-step gross
#               over the interval, per hour, over the column's water, and the
#               parent's change against the first variant at the interval's end.
# first_step    From t = 0 to T_END (1 h), three variants: `baseline` (CONFIG as
#               it is), `converged_first` (the first step with NREF iterations),
#               and `tags_after_first` (the tags rebuilt from the state after
#               the first step). Writes each tag's profile at T_END per variant,
#               for `w25_compare.py` to take the default-against-copies L1.
#
# Every run starts as the D4-W driver starts it: the passive tracer set to the
# `tropo` mask where the configuration has it, and copies from the plume.
# RESULT lines summarize; the CSVs hold everything the design scores.
import ClimaAtmos as CA
import YAML

PROBE = get(ENV, "PROBE", "fixed_parent")
CONFIG = ENV["CONFIG"]
OUTDIR = get(ENV, "OUTDIR", pwd())
mkpath(OUTDIR)
RUN = splitext(basename(CONFIG))[1]
TROPO_REGION = Dict(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => false,
)
seconds(x) = CA.time_to_seconds(x)

function config(; newton = nothing, dt = nothing, t_start = nothing, t_end = nothing, tag)
    dict = Dict{String, Any}(YAML.load_file(CONFIG))
    dict["diagnostics"] = []
    delete!(dict, "water_closure_check")
    dict["output_default_diagnostics"] = false
    dict["output_dir"] = mktempdir(pwd())
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    isnothing(newton) || (dict["max_newton_iters_ode"] = newton)
    isnothing(dt) || (dict["dt"] = "$(dt)secs")
    isnothing(t_start) || (dict["t_start"] = "$(t_start)secs")
    isnothing(t_end) || (dict["t_end"] = "$(t_end)secs")
    return CA.AtmosConfig(dict; job_id = "$(RUN)_$(PROBE)_$tag")
end

# As `d4w_driver.jl`: the passive tracer to the `tropo` mask, and the copies
# from the default mode's plume.
function start_as_driver!(integrator)
    Y, p = integrator.u, integrator.p
    if hasproperty(Y.c, :ρq_gas_A)
        FT = CA.Spaces.undertype(axes(Y.c))
        region = CA.tag_region_from_config(TROPO_REGION, FT)
        ᶜmask = CA.region_mask.(Ref(region), CA.Fields.coordinate_field(Y.c))
        @. Y.c.ρq_gas_A = Y.c.ρ * ᶜmask
        Y.c.sgsʲs.:(1).q_gas_A .= ᶜmask
    end
    CA.has_water_tag_updraft_copies(p.atmos.water_tagging_model) &&
        CA.start_water_tag_copies_from_plume!(Y, p)
    CA.set_precomputed_quantities!(Y, p, integrator.t)
    return nothing
end

# Copy a state and time into an integrator, refresh its cache (the stepper does
# not at a step's first stage), and restart its per-step ledger gross from the
# copied ledgers, so that the jump to the copied state is not counted.
function take_state!(integrator, Y, t)
    integrator.u .= Y
    integrator.t = t
    CA.set_precomputed_quantities!(integrator.u, integrator.p, integrator.t)
    steps = CA._tag_ledger_steps(integrator.p.tagging)
    if !isnothing(steps)
        for (name, ledger) in pairs(steps.ledgers)
            ledger.ᶜprev .= getproperty(integrator.u.c, name)
        end
    end
    return nothing
end

l1(a, b) = sum(abs, parent(a) .- parent(b))
tag_names(integrator) =
    CA.water_tag_state_names(integrator.p.atmos.water_tagging_model)
ledger_names(integrator) = CA.tag_state_ledger_names(integrator.p.atmos)
gross_total(integrator, name) = Float64(
    sum(getproperty(CA._tag_ledger_steps(integrator.p.tagging).ledgers, name).ᶜgross),
)
function write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(repr.(row), ","))
        end
    end
end

function fixed_parent()
    nref = parse(Int, get(ENV, "NREF", "10"))
    trials_n = parse.(Int, split(get(ENV, "TRIALS", "1,2"), ","))
    t_end = seconds(get(ENV, "T_END", "6hours"))
    reference = CA.get_simulation(config(; newton = nref, tag = "n$nref")).integrator
    start_as_driver!(reference)
    trials = [
        (n, CA.get_simulation(config(; newton = n, tag = "n$n")).integrator) for
        n in trials_n
    ]
    variables = (:ρq_tot, tag_names(reference)...)
    ledgers = ledger_names(reference)
    header = ["t_seconds"]
    append!(header, ["increment_$(v)" for v in variables])
    append!(header, ["ledger_n$(nref)_$(l)" for l in ledgers])
    for (n, _) in trials
        append!(header, ["error_n$(n)_$(v)" for v in variables])
        append!(header, ["ledger_n$(n)_$(l)" for l in ledgers])
    end
    rows = Vector{Vector{Float64}}()
    while seconds(reference.t) < t_end - 1e-6
        Yₖ = copy(reference.u)
        tₖ = reference.t
        CA.CTS.step!(reference)
        row = [seconds(reference.t)]
        append!(row, [l1(getproperty(reference.u.c, v), getproperty(Yₖ.c, v)) for v in variables])
        append!(row, [l1(getproperty(reference.u.c, l), getproperty(Yₖ.c, l)) for l in ledgers])
        for (_, trial) in trials
            take_state!(trial, Yₖ, tₖ)
            CA.CTS.step!(trial)
            @assert trial.t == reference.t
            append!(row, [l1(getproperty(trial.u.c, v), getproperty(reference.u.c, v)) for v in variables])
            append!(row, [l1(getproperty(trial.u.c, l), getproperty(Yₖ.c, l)) for l in ledgers])
        end
        push!(rows, row)
    end
    write_csv(joinpath(OUTDIR, "$(RUN)_fixed_parent.csv"), header, rows)
    column(name) = findfirst(==(name), header)
    for (label, keep) in (("all", r -> true), ("first_hour", r -> r[1] <= 3600 + 1e-6))
        kept = filter(keep, rows)
        for (n, _) in trials, v in variables
            error = sum(r[column("error_n$(n)_$(v)")] for r in kept)
            increment = sum(r[column("increment_$(v)")] for r in kept)
            println("RESULT run=$RUN probe=fixed_parent window=$label newton=$n variable=$v E=$(error / increment)")
        end
    end
    println("RESULT run=$RUN probe=fixed_parent steps=$(length(rows))")
end

function refinement()
    t0 = seconds(get(ENV, "T0", "6hours"))
    interval = seconds(get(ENV, "INTERVAL", "1hours"))
    variants = map(split(get(ENV, "VARIANTS", "120:1,120:2,120:10,60:1,30:1"), ",")) do v
        dt, n = parse.(Int, split(v, ":"))
        (dt, n)
    end
    lead = CA.get_simulation(config(; tag = "lead")).integrator
    start_as_driver!(lead)
    while seconds(lead.t) < t0 - 1e-6
        CA.CTS.step!(lead)
    end
    Y0 = copy(lead.u)
    header = ["dt", "newton", "steps"]
    rows = Vector{Vector{Float64}}()
    first_hus = nothing
    names = nothing
    for (dt, n) in variants
        run = CA.get_simulation(
            config(; dt, newton = n, t_start = t0, t_end = t0 + interval, tag = "dt$(dt)_n$n"),
        ).integrator
        take_state!(run, Y0, run.t)
        names = ledger_names(run)
        before = [gross_total(run, l) for l in names]
        steps = 0
        while seconds(run.t) < t0 + interval - 1e-6
            CA.CTS.step!(run)
            steps += 1
        end
        water = Float64(sum(run.u.c.ρq_tot))
        per_hour = [(gross_total(run, l) - b) / water / (interval / 3600) for (l, b) in zip(names, before)]
        hus = parent(run.u.c.ρq_tot ./ run.u.c.ρ)
        drift = isnothing(first_hus) ? 0.0 : maximum(abs, hus .- first_hus) / maximum(abs, first_hus)
        isnothing(first_hus) && (first_hus = copy(hus))
        push!(rows, [dt, n, steps, per_hour..., drift])
        for (l, value) in zip(names, per_hour)
            println("RESULT run=$RUN probe=refinement dt=$dt newton=$n ledger=$l per_hour=$value")
        end
        println("RESULT run=$RUN probe=refinement dt=$dt newton=$n parent_hus_change=$drift")
    end
    append!(header, ["$(l)_per_hour" for l in names])
    push!(header, "parent_hus_change_vs_first")
    write_csv(joinpath(OUTDIR, "$(RUN)_refinement.csv"), header, rows)
end

function first_step()
    nref = parse(Int, get(ENV, "NREF", "10"))
    t_end = seconds(get(ENV, "T_END", "1hours"))
    for variant in ("baseline", "converged_first", "tags_after_first")
        run = CA.get_simulation(config(; tag = variant)).integrator
        start_as_driver!(run)
        if variant == "converged_first"
            converged = CA.get_simulation(config(; newton = nref, tag = "first_n$nref")).integrator
            take_state!(converged, run.u, run.t)
            CA.CTS.step!(converged)
            take_state!(run, converged.u, converged.t)
        elseif variant == "tags_after_first"
            CA.CTS.step!(run)
            CA.rebuild_tags_from_state!(run.u, run.p.atmos)
            CA.has_water_tag_updraft_copies(run.p.atmos.water_tagging_model) &&
                CA.start_water_tag_copies_from_plume!(run.u, run.p)
            take_state!(run, copy(run.u), run.t)
        end
        while seconds(run.t) < t_end - 1e-6
            CA.CTS.step!(run)
        end
        tags = tag_names(run)
        z = parent(CA.Fields.coordinate_field(run.u.c).z)
        rho = parent(run.u.c.ρ)
        header = ["z", "rho", "rho_q_tot", string.(tags)...]
        columns = [vec(z), vec(rho), vec(parent(run.u.c.ρq_tot)), (vec(parent(getproperty(run.u.c, t))) for t in tags)...]
        rows = [[c[i] for c in columns] for i in eachindex(columns[1])]
        write_csv(joinpath(OUTDIR, "$(RUN)_first_step_$(variant).csv"), header, rows)
        closure = CA.tag_closure(run.u, run.p, :ρq_tot, CA.water_region_tag_state_names(run.p.atmos.water_tagging_model))
        println("RESULT run=$RUN probe=first_step variant=$variant t=$(seconds(run.t)) gross_relative=$(closure.gross_relative)")
    end
end

PROBE == "fixed_parent" ? fixed_parent() :
PROBE == "refinement" ? refinement() :
PROBE == "first_step" ? first_step() : error("PROBE must be fixed_parent, refinement or first_step, got $PROBE")
