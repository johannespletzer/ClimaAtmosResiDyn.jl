# Why WP4c's `vdiff` correction raises the gate's part 2a (FINDINGS W45, W46).
#
#   CONFIG=<configs/wp4c_corr_d4w_default.yml> OUTDIR=<dir> \
#       [T_START=6600] [T_END=10800] [EVERY=1] [SETS=gate,sync] \
#       julia --project=<env at the validation's run tree> wp4c_diag_probe.jl
#
# The reference is CONFIG as it is: D4-W under the follower with
# `water_tag_leak_correction: true`, as in V1. At the sampled steps (from
# T_START to T_END, every EVERY-th) it copies the reference's state `Yₖ` into
# three trials under the follower and steps each once:
#   A  CONFIG as it is: `vdiff` on, the correction on (V1's "on" trial);
#   B  the correction off (the key false): W40's "on" trial, from V1's state;
#   C  `vdiff` off (`edmfx_sgs_diffusive_flux: false`), which also turns the
#      correction off: the "off" trial of both W40 and V1.
# So from one state, X = Δmoved(A) − Δmoved(C) is V1's part 2a per step, and
# X + L = Δmoved(B) − Δmoved(C) is W40's. L = Δmoved(B) − Δmoved(A) is what
# the correction takes out of the follower's moved part.
#
# SETS picks how the trials are run (the reference is unchanged), as tokens
# joined by `_`:
#   gate     the trials step at every step from the start, as the gate's probe
#            runs them, and each takes the reference's state only;
#   sync     the trials step only at the sampled steps, and each first takes
#            the reference's cloud fraction as it stood before the reference's
#            previous step. The model computes the cloud fraction by a Picard
#            iteration that starts from the cache's previous value
#            (`set_covariance_cache_and_cloud_fraction!`), so a trial that
#            takes only `Yₖ` recomputes it from its own history. With the sync
#            its precomputed quantities are the reference's bit for bit, which
#            the probe checks for A (`A_precomputed_max_absdiff`);
#   lin<k>   `approximate_linear_solve_iters: k` for the trials;
#   newton<n> `max_newton_iters_ode: n` for the trials.
# E.g. `gate`, `sync`, `sync_lin8`, `sync_newton3_lin8`. The sets share their
# types, so they compile once.
#
# Each implicit stage is recorded in the follower's post-solve hook, which this
# script redefines to call the model's own correction and then read, without
# writing anything the model uses: the mismatch `m` the follower acted on, the
# moved part, the parent's post-solve correction, and the Newton cache (the
# residual `f = dtγ T(Û)` at the first guess, `Δx` and the Jacobian `j`). With
# one Newton iteration the stage's increment is `−j \ f`, so the "vdiff on
# minus off" mismatch of a stage splits exactly, by the solve's linearity:
#   X_s = [−j_A \ (f_A − f_C)]_m + ([−j_A \ f_C]_m − [−j_C \ f_C]_m)
#         + post_A − post_C + (first-guess changes),
# with `[x]_m = x.ρq_tot − Σ_partition x.tag`. The first term is split by the
# right-hand side's rows: `ρq_tot`'s own (`q`), the tags' (`T`), and every
# other variable (`o`: ρ, ρe_tot, the rain and snow, tke, uₕ, the updraft).
# Against the unfiltered tendency `[f_A − f_C]_m` ("tend") that gives
#   filt_q  the parent's solve of its own `vdiff` tendency, less the tendency;
#   filt_T  the same for the partition, with its sign in `m`;
#   lin_o   the parent's `ρq_tot` answering `vdiff`'s tendencies of the other
#           variables through the coupled solve;
#   jac     the change of the Jacobian itself between A and C;
#   post    the parent's upwinding correction after the solve.
# At the first implicit stage A and C start from the same first guess, so
# `f_A − f_C` is `vdiff`'s tendency alone. At the second the first guesses
# differ by the first stage's increment, so `f_A − f_C` also holds every other
# process's change of tendency from that ("stage timing").
#
# Outputs, in kg m⁻² unless stated:
#   OUTDIR/<run>_<set>_diag_steps.csv  one row per sampled step: the gross and
#       net of X, X + L, L, the closed-form leak and the residual leak at `Yₖ`,
#       and per stage the gross of each part of X and of L;
#   OUTDIR/<run>_<set>_diag_cells.csv  per sampled step and level, the
#       step-level X, L and the stage parts, for the reader
#       (`wp4c_diag_read.py`).
import ClimaAtmos as CA
import YAML
import LinearAlgebra

CONFIG = ENV["CONFIG"]
OUTDIR = get(ENV, "OUTDIR", pwd())
mkpath(OUTDIR)
RUN = splitext(basename(CONFIG))[1]
T_START = parse(Float64, get(ENV, "T_START", "6600"))
T_END = parse(Float64, get(ENV, "T_END", "10800"))
EVERY = parse(Int, get(ENV, "EVERY", "1"))
SETS = split(get(ENV, "SETS", "gate,sync"), ",")
seconds(x) = CA.time_to_seconds(x)
@info "ClimaAtmos" path = pathof(CA)

function set_settings(set)
    tokens = split(set, "_")
    all(t -> t in ("gate", "sync") || occursin(r"^(lin|newton)\d+$", t), tokens) ||
        error("SETS entries are tokens gate, sync, lin<k>, newton<n> joined by _, got $set")
    ("gate" in tokens) == ("sync" in tokens) && error("a set is either gate or sync: $set")
    pick(prefix) = (i = findfirst(t -> startswith(t, prefix), tokens);
        isnothing(i) ? nothing : parse(Int, tokens[i][(length(prefix) + 1):end]))
    return (; sync = "sync" in tokens, linear = pick("lin"), newton = pick("newton"))
end

function config(; tag, corr = nothing, off = false, t_end, solver = (;))
    dict = Dict{String, Any}(YAML.load_file(CONFIG))
    dict["diagnostics"] = []
    delete!(dict, "water_closure_check")
    dict["output_default_diagnostics"] = false
    dict["output_dir"] = mktempdir(pwd())
    dict["toml"] = [joinpath(pkgdir(CA), path) for path in dict["toml"]]
    isnothing(corr) || (dict["water_tag_leak_correction"] = corr)
    off && (dict["edmfx_sgs_diffusive_flux"] = false)
    dict["t_end"] = "$(t_end)secs"
    isnothing(get(solver, :linear, nothing)) ||
        (dict["approximate_linear_solve_iters"] = solver.linear)
    isnothing(get(solver, :newton, nothing)) || (dict["max_newton_iters_ode"] = solver.newton)
    return CA.AtmosConfig(dict; job_id = "$(RUN)_diag_$tag")
end

# As `wp4c_gate_probe.jl`.
const TROPO_REGION = Dict(
    "type" => "tanh_altitude",
    "z_center" => 750.0,
    "width" => 100.0,
    "above" => false,
)
function start_as_driver!(integrator)
    Y, p = integrator.u, integrator.p
    if hasproperty(Y.c, :ρq_gas_A)
        FT = CA.Spaces.undertype(axes(Y.c))
        region = CA.tag_region_from_config(TROPO_REGION, FT)
        ᶜmask = CA.region_mask.(Ref(region), CA.Fields.coordinate_field(Y.c))
        @. Y.c.ρq_gas_A = Y.c.ρ * ᶜmask
        Y.c.sgsʲs.:(1).q_gas_A .= ᶜmask
    end
    CA.set_precomputed_quantities!(Y, p, integrator.t)
    return nothing
end
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
function take_state!(integrator, Y, t; cloud_fraction = nothing)
    copy_common!(integrator.u, Y)
    isnothing(cloud_fraction) ||
        (integrator.p.precomputed.ᶜcloud_fraction .= cloud_fraction)
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

# The recorder. The hook below runs for every follower integrator; it records
# only while `active`, for the integrator in `integrator`.
mutable struct Recorder
    active::Bool
    set::String
    label::Symbol
    stage::Int
    integrator::Any
    data::Dict{Tuple{String, Symbol, Int}, Any}
end
const REC = Recorder(false, "", :none, 0, nothing, Dict())

# `[x]_m`: the parent's `ρq_tot` less the partition's sum, per cell.
function mpart(x, partition)
    ᶜm = copy(x.c.ρq_tot)
    for name in partition
        ᶜm .-= getproperty(x.c, name)
    end
    return ᶜm
end
# `a − b` on `a`'s layout, from the fields the two share.
function common_difference(a, b)
    d = similar(a)
    d .= 0
    copy_common!(d, b)
    @. d = a - d
    return d
end
function solve_m(j, b, partition)
    x = similar(b)
    x .= 0
    LinearAlgebra.ldiv!(x, j, copy(b))
    ᶜm = mpart(x, partition)
    ᶜm .*= -1  # the increment is −j \ b
    return ᶜm
end
function split_rhs(b, tags)
    bq = similar(b)
    bq .= 0
    bq.c.ρq_tot .= b.c.ρq_tot
    bT = similar(b)
    bT .= 0
    for name in tags
        getproperty(bT.c, name) .= getproperty(b.c, name)
    end
    bo = similar(b)
    @. bo = b - bq - bT
    return bq, bT, bo
end

function record_stage!(dY, U, p)
    REC.stage += 1
    s = REC.stage
    integrator = REC.integrator
    cache = integrator.cache
    nc = cache.newtons_method_cache
    model = p.atmos.water_tagging_model
    partition = CA.water_region_tag_state_names(model)
    tags = CA.water_tag_state_names(model)
    dtγ = p.tagging.q_tag_dtγ[]
    m = copy(p.tagging.ᶜq_tag_mismatch)
    moved = copy(dY.c.q_tag_inc_moved)
    @. moved *= dtγ
    post = copy(dY.c.ρq_tot)
    @. post *= dtγ
    inc = mpart(nc.Δx, partition)
    @. inc = -inc
    # The Newton iteration started from `U + Δx` (one iteration); the stage
    # started from `cache.temp`. Their difference is what the stage's
    # initializer and constraints changed before the solve.
    first_guess = similar(U)
    @. first_guess = U + nc.Δx - cache.temp
    constr = mpart(first_guess, partition)
    entry = Dict{Symbol, Any}(
        :m => m,
        :moved => moved,
        :post => post,
        :inc => inc,
        :constr => constr,
        :f => copy(nc.f),
        :dtγ => dtγ,
    )
    if REC.label in (:A, :B) && haskey(REC.data, (REC.set, :C, s))
        C = REC.data[(REC.set, :C, s)]
        j = nc.j
        # The re-solve reproduces the stage's own increment.
        entry[:resolve_error] =
            maximum(abs.(parent(solve_m(j, nc.f, partition) .- inc)))
        b = common_difference(nc.f, C[:f])
        fC = similar(nc.f)
        fC .= 0
        copy_common!(fC, C[:f])
        tend = mpart(b, partition)
        bq, bT, bo = split_rhs(b, tags)
        lin_q = solve_m(j, bq, partition)
        lin_T = solve_m(j, bT, partition)
        lin_o = solve_m(j, bo, partition)
        lin_total = solve_m(j, b, partition)
        entry[:linearity_error] =
            maximum(abs.(parent(lin_q .+ lin_T .+ lin_o .- lin_total)))
        filt_q = lin_q .- bq.c.ρq_tot
        filt_T = lin_T .- mpart(bT, partition)
        jac = solve_m(j, fC, partition) .- C[:inc]
        entry[:tend] = tend
        entry[:filt_q] = filt_q
        entry[:filt_T] = filt_T
        entry[:lin_o] = lin_o
        entry[:jac] = jac
        entry[:post_diff] = post .- C[:post]
        entry[:constr_diff] = constr .- C[:constr]
        entry[:X_m] = m .- C[:m]
        # A sub-part of the above: the parent's leak term and the partition's
        # correction, at the first guess, each through its own solve. The
        # correction has no Jacobian block and the parent's `ρq_tot` row holds
        # more blocks than the tags' rows, so the two need not cancel after the
        # solve even where they cancel before it.
        if REC.label == :A
            Û = cache.temp
            ᶠρK_h = CA.Fields.Field(eltype(Û.c.ρ), axes(Û.f))
            @. ᶠρK_h = CA.ᶠinterp(Û.c.ρ) * p.precomputed.ᶠK_h
            b_leak = similar(nc.f)
            b_leak .= 0
            b_leak.c.ρq_tot .= CA.ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, CA._leaking_water(Û, p))
            correction = similar(nc.f)
            correction .= 0
            CA.apply_water_tag_leak_correction!(
                correction,
                Û,
                p,
                ᶠρK_h,
                p.scratch.ᶜtagging_q_leak_correction,
                nothing,
                false,
            )
            for name in tags
                getproperty(b_leak.c, name) .= getproperty(correction.c, name)
            end
            b_leak .*= dtγ
            entry[:leak_tend] = mpart(b_leak, partition)
            entry[:leak_solve] = solve_m(j, b_leak, partition) .- entry[:leak_tend]
            # The parent's leak term alone through the parent's solve, and the
            # partition's correction alone through the tags' solve.
            b_parent = similar(b_leak)
            b_parent .= 0
            b_parent.c.ρq_tot .= b_leak.c.ρq_tot
            entry[:leak_parent] = solve_m(j, b_parent, partition)
            entry[:leak_partition] = solve_m(j, b_leak .- b_parent, partition)
        end
    end
    REC.data[(REC.set, REC.label, s)] = entry
    return nothing
end

# The follower's post-solve hook, as `ClimaAtmos` defines it, then the record.
function (correction::CA.WaterTagIncrementCorrection)(dY, U, p, t)
    correction.post(dY, U, p, t)
    CA.correct_water_tag_increment!(dY, U, p)
    REC.active && record_stage!(dY, U, p)
    return nothing
end

# The precomputed quantities that are fields, to compare a trial's cache with
# the reference's.
precomputed_fields(p) = [
    name => getproperty(p.precomputed, name) for
    name in propertynames(p.precomputed) if
    getproperty(p.precomputed, name) isa CA.Fields.Field
]
precomputed_snapshot(p) =
    Dict(name => copy(parent(x)) for (name, x) in precomputed_fields(p))
function precomputed_difference(snapshot, p)
    worst, names = 0.0, Symbol[]
    for (name, x) in precomputed_fields(p)
        a, b = snapshot[name], parent(x)
        all(isequal.(a, b)) && continue
        push!(names, name)
        d = [abs(u - v) for (u, v) in zip(a, b) if isfinite(u) && isfinite(v)]
        worst = max(worst, isempty(d) ? Inf : Float64(maximum(d)))
    end
    return worst, names
end

net(ᶜf) = Float64(sum(ᶜf))
gross(ᶜf) = Float64(sum(abs.(ᶜf)))
column(ᶜf) = Float64.(vec(parent(ᶜf)))

const PARTS = (:tend, :filt_q, :filt_T, :lin_o, :jac, :post_diff, :constr_diff)

function diag()
    reference = CA.get_simulation(config(; tag = "reference", t_end = T_END)).integrator
    start_as_driver!(reference)
    model = reference.p.atmos.water_tagging_model
    CA.follows_water_increment(model) || error("The reference must follow the increment.")
    CA.has_water_tag_leak_correction(model) ||
        error("CONFIG must have `water_tag_leak_correction: true` (V1's).")
    partition = CA.water_region_tag_state_names(model)
    tags = CA.water_tag_state_names(model)
    dt = Float64(seconds(reference.dt))
    trials = Dict{Tuple{String, Symbol}, Any}()
    for set in SETS
        solver = set_settings(set)
        for (label, kwargs) in ((:C, (; off = true)), (:B, (; corr = false)), (:A, (;)))
            @info "building" set label
            flush(stderr)
            trials[(set, label)] =
                CA.get_simulation(config(; tag = "$(set)_$label", t_end = T_END, solver, kwargs...)).integrator
        end
    end
    tableau = reference.cache.tableau
    implicit_stages = [i for i in 1:length(tableau.b_imp) if !iszero(tableau.a_imp[i, i])]
    weights = [tableau.b_imp[i] / tableau.a_imp[i, i] for i in implicit_stages]
    @info "implicit stages and their weights in the step" implicit_stages weights
    z = column(CA.Fields.coordinate_field(reference.u.c).z)
    J = column(CA.Fields.local_geometry_field(reference.u.c).J)
    ᶜleak = similar(reference.u.c.ρ)
    for set in SETS
        settings = set_settings(set)
        decompose = isnothing(settings.newton) || settings.newton == 1
        rows = Vector{Vector{Float64}}()
        header = String[]
        cells = Vector{Vector{Float64}}()
        cell_header = String[]
        REC.set = set
        # Each set steps its own reference from the start.
        if set != first(SETS)
            reference =
                CA.get_simulation(config(; tag = "reference_$set", t_end = T_END)).integrator
            start_as_driver!(reference)
        end
        step_index = 0
        cf_previous = nothing
        while seconds(reference.t) < T_END - 1e-6
            step_index += 1
            tₖ = reference.t
            sampled = seconds(tₖ) >= T_START - 1e-6 && (step_index % EVERY == 0)
            # The reference's cloud fraction at this step's start, and at the
            # previous step's start, from which this one was iterated.
            cf_now = copy(reference.p.precomputed.ᶜcloud_fraction)
            cf_sync = settings.sync ? cf_previous : nothing
            cf_previous = cf_now
            if !sampled && settings.sync
                CA.CTS.step!(reference)
                continue
            end
            Yₖ = copy(reference.u)
            reference_cache = precomputed_snapshot(reference.p)
            CA.CTS.step!(reference)
            ends = Dict{Symbol, Any}()
            precomputed_gap = NaN
            cf_gap = K_h_gap = NaN
            for label in (:C, :B, :A)
                trial = trials[(set, label)]
                take_state!(trial, Yₖ, tₖ; cloud_fraction = cf_sync)
                if label == :A
                    precomputed_gap, gap_names = precomputed_difference(reference_cache, trial.p)
                    cf_gap = Float64(maximum(abs.(reference_cache[:ᶜcloud_fraction] .-
                        parent(trial.p.precomputed.ᶜcloud_fraction))))
                    K_h_gap = Float64(maximum(abs.(reference_cache[:ᶠK_h] .-
                        parent(trial.p.precomputed.ᶠK_h))))
                    sampled && !isempty(gap_names) && (step_index % 10 == 0 || isempty(rows)) &&
                        @info "A's precomputed differ from the reference's" set t = seconds(tₖ) precomputed_gap gap_names
                end
                REC.label, REC.stage, REC.integrator, REC.active = label, 0, trial, sampled
                CA.CTS.step!(trial)
                REC.active = false
                @assert trial.t == reference.t
                ends[label] = trial.u.c.q_tag_inc_moved .- Yₖ.c.q_tag_inc_moved
            end
            sampled || continue
            # The closed-form leak and the part the correction cannot take
            # (where the partition's shares do not sum to 1), at `Yₖ`.
            A = trials[(set, :A)]
            take_state!(A, Yₖ, tₖ; cloud_fraction = cf_sync)
            CA.water_tag_leak!(ᶜleak, Yₖ, A.p, Val(:vdiff))
            ᶜl = @. dt * Yₖ.c.ρ * ᶜleak
            CA.water_tag_share_norm!(A.p, Yₖ)
            ᶜnorm = A.p.scratch.ᶜtagging_q_share_norm
            ᶜψ = zero(Yₖ.c.ρ)
            for name in partition
                ᶜψ .+= CA.water_tag_sediment_share.(getproperty(Yₖ.c, name), Yₖ.c.ρq_tot, ᶜnorm)
            end
            ᶜl_res = @. ᶜl * (1 - ᶜψ)
            X = ends[:A] .- ends[:C]
            XL = ends[:B] .- ends[:C]
            L = ends[:B] .- ends[:A]
            row = Float64[seconds(reference.t), net(Yₖ.c.ρq_tot)]
            hdr = ["t_seconds", "water"]
            for (name, f) in (("X", X), ("XL", XL), ("L", L), ("leak", ᶜl), ("leak_residual", ᶜl_res))
                push!(row, net(f), gross(f))
                push!(hdr, "$(name)_net", "$(name)_gross")
            end
            # The per-stage parts, weighted as the step weights them.
            cellcols = Dict{String, Vector{Float64}}(
                "X" => column(X), "L" => column(L), "leak" => column(ᶜl),
                "leak_residual" => column(ᶜl_res),
            )
            recon = zero(Yₖ.c.ρ)
            for (k, (i, w)) in enumerate(zip(implicit_stages, weights))
                for label in (:A, :B, :C)
                    e = REC.data[(set, label, k)]
                    ᶜmoved_w = w .* e[:moved]
                    label == :A && (recon .+= ᶜmoved_w)
                    push!(row, gross(ᶜmoved_w), gross(w .* (e[:m] .- e[:moved])))
                    push!(hdr, "s$(i)_$(label)_moved_gross", "s$(i)_$(label)_left_gross")
                end
                for label in (:A, :B)
                    e = REC.data[(set, label, k)]
                    Xs = w .* e[:X_m]
                    push!(row, net(Xs), gross(Xs))
                    push!(hdr, "s$(i)_$(label)_Xm_net", "s$(i)_$(label)_Xm_gross")
                    cellcols["s$(i)_$(label)_Xm"] = column(Xs)
                    if decompose
                        rest = copy(Xs)
                        for part in PARTS
                            ᶜpart = w .* e[part]
                            rest .-= ᶜpart
                            push!(row, net(ᶜpart), gross(ᶜpart))
                            push!(hdr, "s$(i)_$(label)_$(part)_net", "s$(i)_$(label)_$(part)_gross")
                            cellcols["s$(i)_$(label)_$(part)"] = column(ᶜpart)
                        end
                        if label == :A
                            for part in (:leak_tend, :leak_solve, :leak_parent, :leak_partition)
                                ᶜpart = w .* e[part]
                                push!(row, net(ᶜpart), gross(ᶜpart))
                                push!(hdr, "s$(i)_A_$(part)_net", "s$(i)_A_$(part)_gross")
                                cellcols["s$(i)_A_$(part)"] = column(ᶜpart)
                            end
                        end
                        push!(row, gross(rest), e[:resolve_error], e[:linearity_error])
                        push!(hdr, "s$(i)_$(label)_unexplained_gross",
                            "s$(i)_$(label)_resolve_error", "s$(i)_$(label)_linearity_error")
                    end
                end
            end
            # The step's moved change against the weighted stages (A).
            push!(row, maximum(abs.(parent(recon .- ends[:A]))), precomputed_gap, cf_gap, K_h_gap)
            push!(hdr, "A_stage_weight_error", "A_precomputed_max_absdiff",
                "A_cloud_fraction_max_absdiff", "A_K_h_max_absdiff")
            isempty(header) && append!(header, hdr)
            push!(rows, row)
            if isempty(cell_header)
                append!(cell_header, ["t_seconds", "z", "J"], sort(collect(keys(cellcols))))
            end
            for lev in eachindex(z)
                push!(cells, vcat([seconds(reference.t), z[lev], J[lev]],
                    [cellcols[name][lev] for name in cell_header[4:end]]))
            end
            @info "step" set t = seconds(reference.t) X = gross(X) XL = gross(XL) L = gross(L) leak = gross(ᶜl)
            flush(stderr)
        end
        open(joinpath(OUTDIR, "$(RUN)_$(set)_diag_steps.csv"), "w") do io
            println(io, join(header, ","))
            foreach(r -> println(io, join(repr.(r), ",")), rows)
        end
        open(joinpath(OUTDIR, "$(RUN)_$(set)_diag_cells.csv"), "w") do io
            println(io, join(cell_header, ","))
            foreach(r -> println(io, join(repr.(r), ",")), cells)
        end
        W = rows[end][2]
        days = length(rows) * dt / 86400
        col(name) = findfirst(==(name), header)
        for name in ("X", "XL", "L", "leak", "leak_residual")
            g = sum(r[col("$(name)_gross")] for r in rows)
            println("RESULT run=$RUN set=$set $name gross_per_day=$(g / W / days)")
        end
        println("RESULT run=$RUN set=$set steps=$(length(rows)) days=$days water=$W")
    end
end

diag()
