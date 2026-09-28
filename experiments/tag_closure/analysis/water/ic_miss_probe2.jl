#=
Option C's miss at site 23, the extended probe on `main`
(design/NEGATIVE_PARENT_WATER.md, section 9.7, pre-registered before it runs).

    CONFIG=experiments/tag_closure/configs/ic_miss_probe2_s23.yml \
    DRIVER=experiments/tag_closure/analysis/water/ic_miss_probe2.jl \
        experiments/tag_closure/runscripts/submit_g3.sh ...

Optional: `IC_PROBE_WINDOWS` (default `30.3-31.0,52.4-53.3`) and
`IC_PROBE_UNIT` (`days`, the default, or `seconds`, for a short check).

Everything `ic_miss_probe.jl` does, unchanged, on `main`'s code, where #118
checks the parent's negative water at every accepted step. It adds:

  - per step, the parent's negative water at the step's end,
    `∫max(-ρq_tot, 0)` and its ratio to `∫ρq_tot`, and #118's latch;
  - leave-one-out probes: the forcing without one of its terms, for each
    term, in the same bracket;
  - candidate 5's mechanism, cell by cell: the change of the excess in the
    cells whose parent is at or below zero before and after the step while
    the region tags gain water, split by the sign of the parent's change, for
    the reference's step and for the forcing's probe;
  - per level, summed over each 6-hour interval inside the windows: the
    reference's change of the excess (all, in N, in the mechanism's cells),
    the forcing's, each term's and each leave-one-out probe's.

Two CSVs in the reference's output directory: `<job_id>_steps.csv`, one row
per step, and `<job_id>_levels.csv`, one row per interval and level. Nothing
here is deleted.
=#
include(joinpath(@__DIR__, "..", "..", "run_tag_closure.jl"))
import YAML

seconds(x) = Float64(CA.time_to_seconds(x))

const UNIT = get(ENV, "IC_PROBE_UNIT", "days") == "seconds" ? 1.0 : 86400.0
const WINDOWS = map(split(get(ENV, "IC_PROBE_WINDOWS", "30.3-31.0,52.4-53.3"), ",")) do w
    a, b = parse.(Float64, split(w, "-"))
    (a * UNIT, b * UNIT)
end
in_window(t) = any(((a, b),) -> a - 1e-6 <= t < b - 1e-6, WINDOWS)
# The 6-hour intervals of the model's output, by the step's start.
const INTERVAL = 6 * 3600.0
interval_of(t) = floor(Int, (t + 1e-6) / INTERVAL)

# The trials: a label and the configuration keys it changes.
const TRIALS = (
    ("on", Dict{String, Any}()),
    ("tracer", Dict{String, Any}("water_tag_transport" => "tracer")),
    ("off_sgs_mass_flux", Dict{String, Any}("edmfx_sgs_mass_flux" => false)),
    ("off_sgs_diffusive_flux", Dict{String, Any}("edmfx_sgs_diffusive_flux" => false)),
)

# The ledgers read in the cells with an excess, as W42 read them per 6 hours.
const LEDGERS = (
    :q_tag_inc_negative,
    :q_tag_inc_moved,
    :q_tag_inc_left,
    :q_tag_led_repair,
    :q_tag_led_rescale,
    :q_tag_led_empty,
    :q_tag_led_fix_pbl,
    :q_tag_led_fix_free,
    :q_tag_led_inc_pbl,
    :q_tag_led_inc_free,
)

function trial_config(path, label, changes, trials_dir)
    dict = Dict{String, Any}(YAML.load_file(path))
    dict["diagnostics"] = []
    dict["output_default_diagnostics"] = false
    delete!(dict, "water_closure_check")
    delete!(dict, "energy_source_closure_check")
    dict["toml"] = [joinpath(pkgdir(CA), p) for p in dict["toml"]]
    out = joinpath(trials_dir, label)
    mkpath(out)
    dict["output_dir"] = out
    merge!(dict, changes)
    return CA.AtmosConfig(dict; job_id = "$(dict["job_id"])_$label")
end

# Copy the fields two states share. The tracer trial has no follower ledgers,
# so its state is a subset of the reference's.
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

has_scm_forcing(p) = p.atmos.external_forcing isa CA.ExternalDrivenTVForcing

# A state, a time and the reference's radiation flux into an integrator, with
# its cache refreshed as the stepper does not at a step's first stage, and its
# forcing terms at that time, as the reference's every-step callback has them.
function take_state!(integrator, Y, t, ᶠradiation_flux)
    copy_common!(integrator.u, Y)
    integrator.t = t
    p = integrator.p
    has_scm_forcing(p) && CA.external_driven_single_column!(integrator)
    parent(p.radiation.ᶠradiation_flux) .= parent(ᶠradiation_flux)
    CA.set_precomputed_quantities!(integrator.u, p, integrator.t)
    steps = CA._tag_ledger_steps(p.tagging)
    if !isnothing(steps)
        for (name, ledger) in pairs(steps.ledgers)
            ledger.ᶜprev .= getproperty(integrator.u.c, name)
        end
    end
    return nothing
end

# The excess per cell, `max(Σ region tags − max(ρq_tot, 0), 0)`.
function excess!(ᶜe, Y, names)
    @. ᶜe = -max(Y.c.ρq_tot, 0)
    for name in names
        ᶜe .+= getproperty(Y.c, name)
    end
    @. ᶜe = max(ᶜe, 0)
    return ᶜe
end

# The sum of the region tags per cell.
function region_sum!(ᶜr, Y, names)
    ᶜr .= 0
    for name in names
        ᶜr .+= getproperty(Y.c, name)
    end
    return ᶜr
end

# The change of the excess from `Y₀` to `Y₁`: total, in N (parent at or below
# zero in `Y₀`), in P (the rest), and in X (the parent changes sign). It leaves
# the change per cell in `s.ᶜd`.
function split_change(Y₀, Y₁, ᶜe₀, names, s)
    excess!(s.ᶜe, Y₁, names)
    @. s.ᶜd = s.ᶜe - ᶜe₀
    total = Float64(sum(s.ᶜd))
    @. s.ᶜm = ifelse(Y₀.c.ρq_tot <= 0, s.ᶜd, 0)
    n = Float64(sum(s.ᶜm))
    @. s.ᶜm = ifelse((Y₀.c.ρq_tot <= 0) != (Y₁.c.ρq_tot <= 0), s.ᶜd, 0)
    x = Float64(sum(s.ᶜm))
    return (total, n, total - n, x)
end

# Candidate 5's mechanism, cell by cell (section 9.7.2): the change of the
# excess, `s.ᶜd` from `split_change`, in the cells whose parent is at or below
# zero in both `Y₀` and `Y₁` while the region tags gain water. Split by the
# parent's change: `up` where the parent rises, `down` where it does not. It
# leaves the mechanism's part per cell in `s.ᶜm5`.
function mechanism_change(Y₀, Y₁, ᶜr₀, names, s)
    region_sum!(s.ᶜr, Y₁, names)
    @. s.ᶜm5 = ifelse(
        (Y₀.c.ρq_tot <= 0) & (Y₁.c.ρq_tot <= 0) & (s.ᶜr > ᶜr₀),
        s.ᶜd,
        0,
    )
    @. s.ᶜm = ifelse(Y₁.c.ρq_tot > Y₀.c.ρq_tot, s.ᶜm5, 0)
    up = Float64(sum(s.ᶜm))
    return (up, Float64(sum(s.ᶜm5)) - up)
end

# One explicit process alone at `Y`, in the tags' bracket, as the model
# applies it, stepped forward by `dt`.
function probe!(f!, event, Y, p, t, dt, s)
    Yₜ = s.Yₜ
    Yₜ .= 0
    CA.open_applied_update!(Yₜ, p, event)
    f!(Yₜ, Y, p, t)
    CA.close_applied_update!(Yₜ, Y, p, event)
    @. s.Y₁ = Y + dt * Yₜ
    return s.Y₁
end

# The forcing's terms with index in `keep`, composed as
# `external_forcing_tendency!` composes them all: the terms' `(dT, dq)`
# accumulated and converted once, then each term's direct part.
function forcing_terms!(keep)
    return function (Yₜ, Y, p, t)
        (; forcing_terms, term_caches) = p.external_forcing
        ᶜdTdt = p.scratch.ᶜtemp_scalar
        ᶜdqtdt = p.scratch.ᶜtemp_scalar_2
        ᶜdTdt .= 0
        ᶜdqtdt .= 0
        for (i, (term, cache)) in enumerate(zip(forcing_terms, term_caches))
            i in keep && CA.accumulate_Tq_tendency!(ᶜdTdt, ᶜdqtdt, term, cache, Y, p)
        end
        CA.apply_Tq_forcing!(Yₜ, Y, p, ᶜdTdt, ᶜdqtdt)
        for (i, (term, cache)) in enumerate(zip(forcing_terms, term_caches))
            i in keep && CA.apply_direct_forcing!(Yₜ, Y, p, term, cache)
        end
        return nothing
    end
end

function large_scale_advection!(Yₜ, Y, p, t)
    thermo_params = CA.CAP.thermodynamics_params(p.params)
    (; ᶜp, ᶜT, ᶜq_tot_nonneg, ᶜq_liq, ᶜq_ice) = p.precomputed
    args = (Y.c.ρ, thermo_params, ᶜT, ᶜp, ᶜq_tot_nonneg, ᶜq_liq, ᶜq_ice, t, p.atmos.ls_adv)
    @. Yₜ.c.ρe_tot += CA.large_scale_advection_tendency_ρe_tot(args...)
    @. Yₜ.c.ρq_tot += CA.large_scale_advection_tendency_ρq_tot(args...)
    return nothing
end

# The forcing's term labels, as `ic_miss_probe.jl` labels them.
function term_labels(p)
    labels = String[]
    used = Set{String}()
    for term in p.external_forcing.forcing_terms
        label = "forcing_" * lowercase(string(nameof(typeof(term))))
        hasproperty(term, :variables) &&
            (label *= "_" * join(string.(term.variables), "_"))
        label in used && (label *= "_$(length(used))")
        push!(used, label)
        push!(labels, label)
    end
    return labels
end

# The explicit probes the model has, as (label, event, f!): those of
# `ic_miss_probe.jl`, then the leave-one-out probes, `forcing_without_<term>`.
function explicit_probes(p)
    probes = Any[]
    if !isnothing(p.atmos.external_forcing)
        push!(
            probes,
            (
                "forcing",
                :external_forcing,
                (Yₜ, Y, p, t) ->
                    CA.external_forcing_tendency!(Yₜ, Y, p, t, p.atmos.external_forcing),
            ),
        )
        if has_scm_forcing(p)
            labels = term_labels(p)
            n = length(labels)
            for (i, label) in enumerate(labels)
                push!(probes, (label, :external_forcing, forcing_terms!((i,))))
            end
            for (i, label) in enumerate(labels)
                push!(
                    probes,
                    (
                        replace(label, "forcing_" => "forcing_without_"),
                        :external_forcing,
                        forcing_terms!(Tuple(filter(!=(i), 1:n))),
                    ),
                )
            end
        end
    end
    push!(
        probes,
        (
            "surface_flux",
            :surface_flux,
            (Yₜ, Y, p, t) -> CA.surface_flux_tendency!(Yₜ, Y, p, t),
        ),
    )
    isnothing(p.atmos.subsidence) || push!(
        probes,
        (
            "subsidence",
            :subsidence,
            (Yₜ, Y, p, t) -> CA.subsidence_tendency!(Yₜ, Y, p, t, p.atmos.subsidence),
        ),
    )
    isnothing(p.atmos.ls_adv) ||
        push!(
            probes,
            ("large_scale_advection", :large_scale_advection, large_scale_advection!),
        )
    return probes
end

# The probes whose change is also kept per level.
per_level(label) = startswith(label, "forcing")

function write_csv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            println(io, join(repr.(row), ","))
        end
    end
end

function write_levels(path, quantities, levels, z)
    open(path, "w") do io
        println(io, join(["interval_start_days", "level", "z_m", quantities...], ","))
        for i in sort(collect(keys(levels)))
            acc = levels[i]
            for k in eachindex(z)
                row = [i * INTERVAL / 86400.0, Float64(k), z[k]]
                append!(row, [acc[q][k] for q in quantities])
                println(io, join(repr.(row), ","))
            end
        end
    end
end

function main_probe()
    path = config_path()
    reference_simulation = CA.get_simulation(CA.AtmosConfig(path))
    reference = reference_simulation.integrator
    job_id = reference_simulation.job_id
    outdir = reference_simulation.output_dir
    model = reference.p.atmos.water_tagging_model
    names = CA.water_region_tag_state_names(model)
    @info "The probe's reference" job_id outdir names WINDOWS
    dt = seconds(reference.dt)
    latch = CA.negative_water_voided(reference.p, :water)

    trials_dir = joinpath(outdir, "trials")
    trials = map(TRIALS) do (label, changes)
        @info "building the trial" label
        label =>
            CA.get_simulation(trial_config(path, label, changes, trials_dir)).integrator
    end
    on = last(first(trials))
    probes = explicit_probes(on.p)
    @info "explicit probes" map(first, probes)
    ledgers = filter(l -> hasproperty(reference.u.c, l), LEDGERS)

    # The per-level weights of `sum`, checked against it once.
    space = axes(reference.u.c)
    weights = vec(Array(parent(CA.ClimaCore.Spaces.weighted_jacobian(space))))
    z = vec(Array(parent(CA.ClimaCore.Fields.coordinate_field(space).z)))
    check = copy(reference.u.c.ρq_tot)
    total = Float64(sum(check))
    by_level = sum(weights .* vec(Array(parent(check))))
    @assert abs(by_level - total) <= 1e-10 * max(abs(total), eps()) (by_level, total)
    level_values(ᶜf) = weights .* vec(Array(parent(ᶜf)))

    header = ["t_seconds", "water", "excess", "ref_total", "ref_N", "ref_P", "ref_X"]
    append!(header, ["ledger_$(l)_in_excess" for l in ledgers])
    append!(header, ["on_gap_q_tot", "on_gap_tags"])
    for (label, _) in trials
        append!(header, ["$(label)_$(c)" for c in ("total", "N", "P", "X")])
    end
    for (label, _, _) in probes
        append!(header, ["probe_$(label)_$(c)" for c in ("total", "N", "P", "X")])
    end
    append!(header, ["probe_explicit_$(c)" for c in ("total", "N", "P", "X")])
    # Section 9.7's additions, after the first probe's columns.
    append!(header, ["negative_water", "negative_water_relative", "latch"])
    append!(
        header,
        ["ref_M5_up", "ref_M5_down", "probe_forcing_M5_up", "probe_forcing_M5_down"],
    )

    level_quantities = ["ref", "ref_N", "ref_M5"]
    for (label, _, _) in probes
        per_level(label) && push!(level_quantities, label)
    end
    push!(level_quantities, "forcing_M5")
    levels = Dict{Int, Dict{String, Vector{Float64}}}()

    Y₀ = similar(reference.u)
    s = (;
        ᶜe = similar(reference.u.c.ρ),
        ᶜd = similar(reference.u.c.ρ),
        ᶜm = similar(reference.u.c.ρ),
        ᶜm5 = similar(reference.u.c.ρ),
        ᶜr = similar(reference.u.c.ρ),
        Yₜ = similar(on.u),
        Y₁ = similar(on.u),
    )
    Yₜ_lim = similar(on.u)
    ᶜe₀ = similar(reference.u.c.ρ)
    ᶜr₀ = similar(reference.u.c.ρ)
    ᶜw = similar(reference.u.c.ρ)
    ᶠflux = similar(reference.p.radiation.ᶠradiation_flux)
    rows = Vector{Vector{Float64}}()
    csv = joinpath(outdir, "$(job_id)_steps.csv")
    levels_csv = joinpath(outdir, "$(job_id)_levels.csv")
    t_last = maximum(last, WINDOWS)
    wrote = 0
    while seconds(reference.t) < t_last - 1e-6
        tₖ = reference.t
        if !in_window(seconds(tₖ))
            CA.CTS.step!(reference)
            continue
        end
        acc = get!(levels, interval_of(seconds(tₖ))) do
            Dict(q => zeros(length(z)) for q in level_quantities)
        end
        Y₀ .= reference.u
        ᶠflux .= reference.p.radiation.ᶠradiation_flux
        excess!(ᶜe₀, Y₀, names)
        region_sum!(ᶜr₀, Y₀, names)
        CA.CTS.step!(reference)
        Y_ref = reference.u
        @. ᶜw = max(Y₀.c.ρq_tot, 0)
        row = [seconds(reference.t), Float64(sum(ᶜw)), Float64(sum(ᶜe₀))]
        append!(row, split_change(Y₀, Y_ref, ᶜe₀, names, s))
        acc["ref"] .+= level_values(s.ᶜd)
        @. s.ᶜm = ifelse(Y₀.c.ρq_tot <= 0, s.ᶜd, 0)
        acc["ref_N"] .+= level_values(s.ᶜm)
        ref_m5 = mechanism_change(Y₀, Y_ref, ᶜr₀, names, s)
        acc["ref_M5"] .+= level_values(s.ᶜm5)
        # The parent's negative water at the step's end, and #118's latch.
        @. ᶜw = max(-Y_ref.c.ρq_tot, 0)
        negative = Float64(sum(ᶜw))
        parent_water = Float64(sum(Y_ref.c.ρq_tot))
        negative_row = (
            negative,
            CA.negative_water_relative(negative, parent_water),
            Float64(latch[]),
        )
        # Each ledger's change in the cells that hold an excess at the end.
        excess!(s.ᶜe, Y_ref, names)
        for l in ledgers
            @. s.ᶜm =
                ifelse(s.ᶜe > 0, abs(getproperty(Y_ref.c, l) - getproperty(Y₀.c, l)), 0)
            push!(row, Float64(sum(s.ᶜm)))
        end
        gaps = nothing
        changes = Float64[]
        for (label, trial) in trials
            take_state!(trial, Y₀, tₖ, ᶠflux)
            CA.CTS.step!(trial)
            @assert trial.t == reference.t
            if label == "on"
                q_gap =
                    maximum(abs, parent(trial.u.c.ρq_tot) .- parent(Y_ref.c.ρq_tot)) /
                    maximum(abs, parent(Y_ref.c.ρq_tot))
                tag_gap =
                    maximum(
                        n -> maximum(
                            abs,
                            parent(getproperty(trial.u.c, n)) .-
                            parent(getproperty(Y_ref.c, n)),
                        ),
                        names,
                    ) / maximum(abs, parent(Y_ref.c.ρq_tot))
                gaps = (q_gap, tag_gap)
            end
            append!(changes, split_change(Y₀, trial.u, ᶜe₀, names, s))
        end
        append!(row, gaps)
        append!(row, changes)
        # The explicit probes, on the `on` trial's cache refreshed at `Yₖ`.
        take_state!(on, Y₀, tₖ, ᶠflux)
        forcing_m5 = (NaN, NaN)
        for (label, event, f!) in probes
            Y₁ = probe!(f!, event, on.u, on.p, on.t, dt, s)
            append!(row, split_change(Y₀, Y₁, ᶜe₀, names, s))
            per_level(label) && (acc[label] .+= level_values(s.ᶜd))
            if label == "forcing"
                forcing_m5 = mechanism_change(Y₀, Y₁, ᶜr₀, names, s)
                acc["forcing_M5"] .+= level_values(s.ᶜm5)
            end
        end
        CA.remaining_tendency!(s.Yₜ, Yₜ_lim, on.u, on.p, on.t)
        @. s.Y₁ = on.u + dt * (s.Yₜ + Yₜ_lim)
        append!(row, split_change(Y₀, s.Y₁, ᶜe₀, names, s))
        append!(row, negative_row)
        append!(row, ref_m5)
        append!(row, forcing_m5)
        push!(rows, row)
        # Write as the windows go, so that a stopped job keeps what it did.
        if length(rows) - wrote >= 500
            write_csv(csv, header, rows)
            write_levels(levels_csv, level_quantities, levels, z)
            wrote = length(rows)
        end
    end
    write_csv(csv, header, rows)
    write_levels(levels_csv, level_quantities, levels, z)
    writers = reference_simulation.output_writers
    isnothing(writers) || foreach(close, writers)
    @info "The probe finished" csv levels_csv steps = length(rows)
    println("RESULT run=$job_id steps=$(length(rows)) csv=$csv levels=$levels_csv")
    return nothing
end

main_probe()
