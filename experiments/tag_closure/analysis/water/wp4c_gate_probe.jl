# WP4c's entry gate (design/WP4C_GATE.md): the operator decomposition, on one
# parent state per step.
#
#   CONFIG=<configs/wp4c_gate_*.yml> OUTDIR=<dir> [OPERATORS=vdiff,sgs_mass_flux] \
#       [T_END=1days] [REFERENCE_OUTPUT=1] \
#       julia --project=<env at the gate's run tree> wp4c_gate_probe.jl
#
# With `REFERENCE_OUTPUT=1` (WP4c's validation, design/WP4C_CORRECTIONS.md) the
# reference keeps CONFIG's diagnostics and closure check and writes them to
# `OUTDIR/<run>_reference/`. The trials never write output. The default, `0`,
# is the gate's behaviour.
#
# The reference is CONFIG as it is: D4-W's water tags under the follower, with
# each tag's ledgers on. At every step it copies the reference's state `Yₖ` and
# time into trials, refreshes their cache (the pattern of
# `w5v_same_atmosphere.jl`), and steps each trial once. The trials are
#   (on, follower), (on, tracer), and for each operator o:
#   (o off, follower), (o off, tracer).
# "o off" switches the operator off for the parent and the tags alike, by its
# configuration key (`OPERATOR_KEYS`). So for each operator and step, from the
# same `Yₖ`, it writes:
#   source     dt ∫ρ leak_o(Yₖ) dV, from `water_tag_leak!` (the closed form),
#              net and gross, for the leak paths; NaN for an operator without
#              one (`sgs_mass_flux`, a reference operator that shows how much
#              of the follower's work is the mass flux's, E59); for `vdiff`,
#              also each tag's excess, the part of
#              the leak the candidate correction would take from that tag,
#              dt ∫ ∇·(ρK_h ∇(ψᵢ q_p)) dV;
#   growth     R(on, tracer) − R(o off, tracer) at the step's end, with R the
#              partition's sum minus `ρq_tot`: the residual's actual growth
#              that the operator causes when nothing follows the parent;
#   follower   each state ledger's change over the step, on minus o off, under
#              the follower (`q_tag_inc_moved`, `q_tag_inc_left`, each tag's
#              `q_tag_led_inc_<tag>` and the rest): the follower's correction
#              of the operator's transfer;
#   remainder  R(on, follower) − R(o off, follower): what is left after it.
# Net values are ∫ over the column, gross values ∫ of the absolute value per
# cell. Everything is in kg (per m² of the column). The CSV has one row per
# step. For the provenance part of the retention rule it also accumulates, per
# cell and tag, D = Σₖ (−excess − follower's per-tag correction) for `vdiff`,
# the change of the tag if the correction replaced the follower's share, and
# writes it with the reference's final profiles.
#
# Every difference "on minus o off" changes more than the operator's leak: the
# operator's transport of the parent and of any residual already there, and
# its coupling in the Newton solve, go with it. So the columns bound the
# operator's part; they do not isolate the leak (the design note, section 3).
import ClimaAtmos as CA
import YAML

CONFIG = ENV["CONFIG"]
OUTDIR = get(ENV, "OUTDIR", pwd())
mkpath(OUTDIR)
RUN = splitext(basename(CONFIG))[1]
OPERATORS = Symbol.(split(get(ENV, "OPERATORS", "vdiff,sgs_mass_flux"), ","))
REFERENCE_OUTPUT = get(ENV, "REFERENCE_OUTPUT", "0") == "1"
# The configuration key that switches each operator off, parent and tags alike.
OPERATOR_KEYS = Dict(
    :vdiff => "edmfx_sgs_diffusive_flux",
    :diffusion_up => "edmfx_vertical_diffusion",
    :sgs_mass_flux => "edmfx_sgs_mass_flux",
)
all(in(keys(OPERATOR_KEYS)), OPERATORS) ||
    error("OPERATORS must be among $(collect(keys(OPERATOR_KEYS))), got $OPERATORS")
TROPO_REGION = Dict(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => false,
)
seconds(x) = CA.time_to_seconds(x)

function config(; tag, transport = nothing, off = nothing, t_end = nothing, output = false)
    dict = Dict{String, Any}(YAML.load_file(CONFIG))
    if output
        dict["output_dir"] = joinpath(OUTDIR, "$(RUN)_reference")
    else
        dict["diagnostics"] = []
        delete!(dict, "water_closure_check")
        dict["output_default_diagnostics"] = false
        dict["output_dir"] = mktempdir(pwd())
    end
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    isnothing(transport) || (dict["water_tag_transport"] = transport)
    isnothing(off) || (dict[OPERATOR_KEYS[off]] = false)
    isnothing(t_end) || (dict["t_end"] = "$(t_end)secs")
    return CA.AtmosConfig(dict; job_id = "$(RUN)_gate_$tag")
end

# As `d4w_driver.jl`: the passive tracer to the `tropo` mask, and the copies
# from the default mode's plume (`w25_probes.jl`).
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

# Copy the fields two states share. The tracer transport's trials have no
# follower ledgers, so their state is a subset of the reference's; every model
# field and tag is in both. A field only the destination has keeps its value.
function copy_common!(dest, src)
    for name in propertynames(dest.c)
        name == :sgsʲs && continue
        hasproperty(src.c, name) &&
            (parent(getproperty(dest.c, name)) .= parent(getproperty(src.c, name)))
    end
    if hasproperty(dest.c, :sgsʲs)
        ᶜd, ᶜs = dest.c.sgsʲs.:(1), src.c.sgsʲs.:(1)
        for name in propertynames(ᶜd)
            hasproperty(ᶜs, name) &&
                (parent(getproperty(ᶜd, name)) .= parent(getproperty(ᶜs, name)))
        end
    end
    parent(dest.f) .= parent(src.f)
    return dest
end

# Copy a state and time into an integrator, refresh its cache (the stepper does
# not at a step's first stage), and restart its per-step ledger gross from the
# copied ledgers (`w25_probes.jl`).
function take_state!(integrator, Y, t)
    copy_common!(integrator.u, Y)
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

net(ᶜf) = Float64(sum(ᶜf))
gross(ᶜf) = Float64(sum(abs.(ᶜf)))
function write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(repr.(row), ","))
        end
    end
end

# The partition's residual, per cell.
function residual(Y, model)
    ᶜR = copy(Y.c.ρq_tot)
    @. ᶜR = -(Y.c.ρq_tot)
    for name in CA.water_region_tag_state_names(model)
        ᶜR .+= getproperty(Y.c, name)
    end
    return ᶜR
end

# Each tag's excess on the grid mean's vertical diffusion, per cell, in kg m⁻³
# over the step: the K_h diffusion of its share of the water that the parent
# does not diffuse, `ψᵢ q_p`. `ψᵢ` is the composition the sedimentation uses
# (G3_PLAN 4.2). Its sum over the partition is the path's leak, `ρ leak`.
function vdiff_excess(Y, p, dt)
    model = p.atmos.water_tagging_model
    CA.water_tag_share_norm!(p, Y)
    ᶜnorm = p.scratch.ᶜtagging_q_share_norm
    ᶜq_p = CA._leaking_water(Y, p)
    ᶠρK_h = @. CA.ᶠinterp(Y.c.ρ) * p.precomputed.ᶠK_h
    partition = CA.water_region_tag_state_names(model)
    return map(CA.water_tag_state_names(model)) do name
        ᶜρq_tag = getproperty(Y.c, name)
        ᶜshare =
            name in partition ?
            (@. CA.water_tag_sediment_share(ᶜρq_tag, Y.c.ρq_tot, ᶜnorm)) :
            (@. CA.water_tag_source_sediment_share(ᶜρq_tag, Y.c.ρq_tot))
        ᶜpart = @. ᶜshare * ᶜq_p
        ᶜdivergence = CA.ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, ᶜpart)
        ᶜexcess = similar(Y.c.ρ)
        @. ᶜexcess = -dt * ᶜdivergence
        name => ᶜexcess
    end
end

function gate()
    t_end = seconds(get(ENV, "T_END", "1days"))
    build(; kwargs...) = CA.get_simulation(config(; t_end, kwargs...)).integrator
    reference_simulation =
        CA.get_simulation(config(; t_end, tag = "reference", output = REFERENCE_OUTPUT))
    reference = reference_simulation.integrator
    start_as_driver!(reference)
    model = reference.p.atmos.water_tagging_model
    CA.follows_water_increment(model) ||
        error("The gate's reference must follow the increment (`water_tag_transport: increment`).")
    tags = CA.water_tag_state_names(model)
    ledgers = CA.tag_state_ledger_names(reference.p.atmos)
    per_tag_inc = filter(l -> startswith(string(l), "q_tag_led_inc_"), collect(ledgers))
    isempty(per_tag_inc) &&
        error("The gate needs each tag's ledgers (`water_tag_ledger_per_tag: true`).")
    dt = Float64(seconds(reference.dt))

    trials = Dict{Tuple{Any, String}, Any}()
    for off in (nothing, OPERATORS...), transport in ("increment", "tracer")
        label = "$(isnothing(off) ? "on" : "off_$off")_$transport"
        @info "building" label
        trials[(off, transport)] = build(; tag = label, transport, off)
    end

    header = ["t_seconds", "water", "on_growth_net", "on_growth_gross", "on_remainder_net"]
    for l in ledgers
        push!(header, "on_ledger_$(l)_net")
    end
    for o in OPERATORS
        append!(header, ["$(o)_source_net", "$(o)_source_gross"])
        append!(header, ["$(o)_growth_net", "$(o)_growth_gross"])
        append!(header, ["$(o)_remainder_net", "$(o)_remainder_gross"])
        for l in ledgers
            append!(header, ["$(o)_ledger_$(l)_net", "$(o)_ledger_$(l)_gross"])
        end
        if o == :vdiff
            for t in tags
                append!(header, ["$(o)_excess_$(t)_net", "$(o)_excess_$(t)_gross"])
            end
        end
    end
    rows = Vector{Vector{Float64}}()
    # D per tag and cell: the correction's change of the tag against the
    # follower's, accumulated over the run (vdiff only).
    ᶜD = Dict(t => zero(reference.u.c.ρ) for t in tags)
    ᶜleak = similar(reference.u.c.ρ)
    while seconds(reference.t) < t_end - 1e-6
        Yₖ = copy(reference.u)
        tₖ = reference.t
        CA.CTS.step!(reference)
        ends = Dict{Tuple{Any, String}, Any}()
        for (key, trial) in trials
            take_state!(trial, Yₖ, tₖ)
            CA.CTS.step!(trial)
            @assert trial.t == reference.t
            ends[key] = copy(trial.u)
        end
        # The cache of the "on, follower" trial holds `Yₖ`'s next state now;
        # the leak is evaluated on `Yₖ` itself, after a refresh.
        on_trial = trials[(nothing, "increment")]
        take_state!(on_trial, Yₖ, tₖ)
        R₀ = residual(Yₖ, model)
        on_fo, on_tr = ends[(nothing, "increment")], ends[(nothing, "tracer")]
        growth_on = residual(on_tr, model) .- R₀
        row = [
            seconds(reference.t),
            net(Yₖ.c.ρq_tot),
            net(growth_on),
            gross(growth_on),
            net(residual(on_fo, model) .- R₀),
        ]
        for l in ledgers
            push!(row, net(getproperty(on_fo.c, l) .- getproperty(Yₖ.c, l)))
        end
        for o in OPERATORS
            if o in CA.WATER_TAG_LEAK_PATHS
                CA.water_tag_leak!(ᶜleak, Yₖ, on_trial.p, Val(o))
                ᶜsource = @. dt * Yₖ.c.ρ * ᶜleak
                append!(row, [net(ᶜsource), gross(ᶜsource)])
            else
                append!(row, [NaN, NaN])
            end
            off_fo, off_tr = ends[(o, "increment")], ends[(o, "tracer")]
            ᶜgrowth = residual(on_tr, model) .- residual(off_tr, model)
            ᶜremainder = residual(on_fo, model) .- residual(off_fo, model)
            append!(row, [net(ᶜgrowth), gross(ᶜgrowth)])
            append!(row, [net(ᶜremainder), gross(ᶜremainder)])
            ledger_change = Dict{Symbol, Any}()
            for l in ledgers
                ᶜchange = getproperty(on_fo.c, l) .- getproperty(off_fo.c, l)
                ledger_change[l] = ᶜchange
                append!(row, [net(ᶜchange), gross(ᶜchange)])
            end
            if o == :vdiff
                for (t, ᶜexcess) in vdiff_excess(Yₖ, on_trial.p, dt)
                    append!(row, [net(ᶜexcess), gross(ᶜexcess)])
                    inc = Symbol(:q_tag_led_inc_, Symbol(replace(string(t), "ρq_tag_" => "")))
                    ᶜfollower = get(ledger_change, inc, zero(ᶜexcess))
                    ᶜDₜ = ᶜD[t]
                    @. ᶜDₜ += -(ᶜexcess) - ᶜfollower
                end
            end
        end
        push!(rows, row)
    end
    write_csv(joinpath(OUTDIR, "$(RUN)_gate.csv"), header, rows)
    # The reference's writers, as `solve_atmos!` closes them.
    writers = reference_simulation.output_writers
    REFERENCE_OUTPUT && !isnothing(writers) && foreach(close, writers)

    # The provenance part: D against the reference's final profiles.
    Y = reference.u
    z = Float64.(vec(parent(CA.Fields.coordinate_field(Y.c).z)))
    J = Float64.(vec(parent(CA.Fields.local_geometry_field(Y.c).J)))
    profile_header = ["z", "J", "rho", "rho_q_tot"]
    columns = Vector{Float64}[z, J, Float64.(vec(parent(Y.c.ρ))), Float64.(vec(parent(Y.c.ρq_tot)))]
    for t in tags
        push!(profile_header, "$(t)_final", "$(t)_D_vdiff")
        push!(columns, Float64.(vec(parent(getproperty(Y.c, t)))), Float64.(vec(parent(ᶜD[t]))))
    end
    write_csv(
        joinpath(OUTDIR, "$(RUN)_gate_profiles.csv"),
        profile_header,
        [[c[i] for c in columns] for i in eachindex(z)],
    )
    column(name) = findfirst(==(name), header)
    water = rows[end][column("water")]
    days = (rows[end][1] - rows[1][1] + dt) / 86400
    for o in OPERATORS, quantity in ("source", "growth", "remainder")
        n = sum(r[column("$(o)_$(quantity)_net")] for r in rows)
        g = sum(r[column("$(o)_$(quantity)_gross")] for r in rows)
        println("RESULT run=$RUN operator=$o $quantity net_per_day=$(n / water / days) gross_per_day=$(g / water / days)")
    end
    for o in OPERATORS, l in ledgers
        g = sum(r[column("$(o)_ledger_$(l)_gross")] for r in rows)
        println("RESULT run=$RUN operator=$o ledger=$l gross_per_day=$(g / water / days)")
    end
    println("RESULT run=$RUN steps=$(length(rows)) days=$days water=$water")
end

gate()
