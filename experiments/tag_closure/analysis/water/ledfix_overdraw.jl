#=
W63: the follower's outflow beyond a tag's content at site 23
(design/NEGATIVE_PARENT_WATER.md, section 11.13, pre-registered before it runs).

    LEDFIX_ARM=rev|switch \
    CONFIG=experiments/tag_closure/configs/lf_od_<arm>_s23.yml \
    DRIVER=experiments/tag_closure/analysis/water/ledfix_overdraw.jl \
        experiments/tag_closure/runscripts/submit_g3.sh ...

Optional, as `ledfix_trace.jl`: `LEDFIX_WINDOWS` (default
`11.25-11.75,15.75-16.0,55.75-56.25`), `LEDFIX_UNIT` (`days`, the default, or
`seconds`, for a short check) and `LEDFIX_LEVELS` (1-based, default 1 to 22,
15 m to 1911 m, every level below 2 km).

`ledfix_trace.jl`'s run (the switch and the step trace), with two things
added:

  - **The step index.** Each step trace row carries the run's step count, so
    that the stage rows join it.
  - **The stage trace.** In the windows, the follower's post-solve hook
    (`WaterTagIncrementCorrection`) is redefined to call the same two
    functions in the same order, and then to read what the follower did. It
    reads only. For each stage and traced level it writes the stage value of
    `pbl` and `free` before the follower, their shares, and the follower's
    four parts for each tag: the outflow through the cell's faces, the
    inflow, the negative part's give and the crossing's part, each times
    `dtγ`. It also writes the follower's ledger increment itself, times
    `dtγ`, so the score can check that the four parts add up to it. Rows go
    to `<job_id>_stages.csv`.

After the last window the run continues with `solve_atmos!` to `t_end`.
Nothing here is deleted.
=#
include(joinpath(@__DIR__, "..", "..", "run_tag_closure.jl"))

const ARM = get(ENV, "LEDFIX_ARM", "")
ARM in ("rev", "switch") || error("LEDFIX_ARM must be rev or switch, not \"$ARM\"")
const UNIT = get(ENV, "LEDFIX_UNIT", "days") == "seconds" ? 1.0 : 86400.0
const WINDOWS =
    map(split(get(ENV, "LEDFIX_WINDOWS", "11.25-11.75,15.75-16.0,55.75-56.25"), ",")) do w
        a, b = parse.(Float64, split(w, "-"))
        (a * UNIT, b * UNIT)
    end
const LEVELS = parse.(Int, split(get(ENV, "LEDFIX_LEVELS", join(1:22, ",")), ","))
seconds(x) = Float64(CA.time_to_seconds(x))
in_window(t) = any(((a, b),) -> a - 1e-6 <= t < b - 1e-6, WINDOWS)

# The switch, as in `ledfix_trace.jl`: the rule before the revision.
if ARM == "switch"
    @eval CA.water_tag_gain(::CA.TargetGain, Δ, ρq_tot) = max(Δ, 0)
    @eval CA.water_tag_withheld_gain(::CA.TargetGain, Δ, ρq_tot) = zero(Δ)
    @eval CA.water_tag_split_change(::CA.TargetGain, x, ρq_tot) = x
end

# The step trace's fields, as in `ledfix_trace.jl`.
const FIELDS = (
    :ρq_tot,
    :ρq_tag_pbl,
    :ρq_tag_free,
    :q_tag_led_fix_pbl,
    :q_tag_led_fix_free,
    :q_tag_led_inc_pbl,
    :q_tag_led_inc_free,
    :q_tag_exp_negative,
    :q_tag_inc_negative,
)
const TRACED_TAGS = (:free, :pbl)

# The stage recorder's state. It is switched on only in the windows.
const RECORD_ON = Ref(false)
const STEP = Ref(0)
const STAGE = Ref(0)
const STAGE_IO = Ref{IO}(devnull)
const GEOMETRY = Ref{Any}(nothing)
const SHARE_BUFFER = Ref{Any}(nothing)
const PARENT_BUFFER = Ref{Any}(nothing)

# The follower's hook, as the model defines it, with the recorder around the
# water correction. In a step outside the windows it is the model's own.
@eval function (correction::CA.WaterTagIncrementCorrection)(dY, U, p, t)
    correction.post(dY, U, p, t)
    if RECORD_ON[]
        record_stage!(dY, U, p, t)
    else
        CA.correct_water_tag_increment!(dY, U, p)
    end
    return nothing
end

column(x) = vec(Array(parent(x)))

function find_tag(model, name)
    for tag in model.tags
        CA.tag_name(tag) == name && return tag
    end
    error("no water tag $name")
end

# Call the follower, then read its four parts per traced tag. The parts are
# the kernels' own terms, in amounts (times `dtγ`):
#   out:   the cell's share times the whole flux leaving it through its faces;
#   in:    the flux entering it times the donor neighbour's share;
#   give:  the negative part's weight times the share, where `N` is not zero;
#   cross: the mask times the crossing's positive part, where `δL` is not zero.
# The divergence is `(J⁺ F⁺ − J⁻ F⁻) / J`, with zero at the boundary faces.
function record_stage!(dY, U, p, t)
    model = p.atmos.water_tagging_model
    STAGE[] += 1
    ledger(tag) = getproperty(dY.c, Symbol(:q_tag_led_inc_, tag))
    before = map(name -> column(ledger(name)), TRACED_TAGS)
    CA.correct_water_tag_increment!(dY, U, p)
    after = map(name -> column(ledger(name)), TRACED_TAGS)

    dtγ = Float64(p.tagging.q_tag_dtγ[])
    Jc, Jf, z = GEOMETRY[]
    nz = length(Jc)
    F = column(p.tagging.ᶠq_tag_increment_flux)
    length(F) == nz + 1 || error("the flux has $(length(F)) faces, not $(nz + 1)")
    F[1] = 0.0
    F[end] = 0.0
    ᶜnorm = p.scratch.ᶜtagging_q_share_norm
    ᶜpos = p.tagging.ᶜwater_pos
    ᶜparent = CA.water_tag_parent(U.c, model)
    pb = PARENT_BUFFER[]
    @. pb = $(ᶜparent)
    pos = column(ᶜpos)
    parent_w = column(pb)
    N = Float64(column(p.tagging.q_tag_negative_total)[1])
    δL = column(p.tagging.ᶜq_tag_exp_change)
    g = column(p.tagging.ᶜq_tag_crossing)
    # The negative part's entry holds the crossing's part where `δL ≠ 0`.
    give_w = column(p.tagging.ᶜq_tag_negative_weight) .- ifelse.(δL .== 0, 0.0, g)
    outtot = [
        dtγ * (Jf[i + 1] * max(F[i + 1], 0.0) + Jf[i] * max(-F[i], 0.0)) / Jc[i] for
        i in 1:nz
    ]

    parts = map(TRACED_TAGS) do name
        tag = find_tag(model, name)
        sh = SHARE_BUFFER[]
        @. sh = $(CA._water_tag_follower_share_field(U.c, ᶜnorm, ᶜpos, tag, ᶜparent))
        s = column(sh)
        C = column(CA.tag_field(U.c, tag))
        mask = column(CA.tag_field(p.tagging.ᶜwater_masks, tag))
        out = s .* outtot
        inn = [
            dtγ * (
                Jf[i] * max(F[i], 0.0) * (i > 1 ? s[i - 1] : 0.0) +
                Jf[i + 1] * max(-F[i + 1], 0.0) * (i < nz ? s[i + 1] : 0.0)
            ) / Jc[i] for i in 1:nz
        ]
        give = N != 0 ? give_w .* s : zeros(nz)
        cross = ifelse.(δL .== 0, 0.0, mask .* g)
        (; C, s, out, inn, give, cross)
    end
    led = map((a, b) -> dtγ .* (a .- b), after, before)

    io = STAGE_IO[]
    ts = seconds(t)
    for l in LEVELS
        row = Any[STEP[], STAGE[], ts, dtγ, l, z[l], parent_w[l], pos[l], outtot[l]]
        for (k, q) in enumerate(parts)
            push!(row, q.C[l], q.s[l], q.out[l], q.inn[l], q.give[l], q.cross[l], led[k][l])
        end
        println(io, join(row, ","))
    end
    return nothing
end

function main_overdraw()
    gain = CA.water_tag_gain(CA.TargetGain(), 1.0, -1.0)
    withheld = CA.water_tag_withheld_gain(CA.TargetGain(), 1.0, -1.0)
    expected = ARM == "switch" ? (1.0, 0.0) : (0.0, 1.0)
    (gain, withheld) == expected ||
        error("the arm $ARM gives gain $gain and withheld $withheld, not $expected")
    @info "The arm" ARM gain withheld

    path = config_path()
    simulation = CA.get_simulation(CA.AtmosConfig(path))
    integrator = simulation.integrator
    job_id = simulation.job_id
    occursin(ARM, job_id) || error("job id $job_id does not name the arm $ARM")
    outdir = simulation.output_dir
    Y = integrator.u
    for f in FIELDS
        hasproperty(Y.c, f) || error("the state has no field $f")
    end
    p = integrator.p
    CA.follows_water_increment(p.atmos.water_tagging_model) ||
        error("the water tags do not follow the increment")

    space = axes(Y.c)
    weights = vec(Array(parent(CA.ClimaCore.Spaces.weighted_jacobian(space))))
    z = vec(Array(parent(CA.ClimaCore.Fields.coordinate_field(space).z)))
    Jc = column(CA.ClimaCore.Fields.local_geometry_field(space).J)
    Jf = column(CA.ClimaCore.Fields.local_geometry_field(axes(Y.f)).J)
    length(Jf) == length(Jc) + 1 || error("not a single column")
    GEOMETRY[] = (Jc, Jf, z)
    SHARE_BUFFER[] = similar(Y.c.ρq_tot)
    PARENT_BUFFER[] = similar(Y.c.ρq_tot)
    all(l -> 1 <= l <= length(z), LEVELS) ||
        error("a traced level is outside 1:$(length(z))")
    @info "The trace" job_id outdir WINDOWS LEVELS z_traced = z[LEVELS]

    header = ["step", "t_seconds", "step_end", "level", "z_m", String.(FIELDS)...]
    csv = joinpath(outdir, "$(job_id)_trace.csv")
    io = open(csv, "w")
    println(io, join(header, ","))
    stage_header = ["step", "stage", "t_stage", "dtgamma", "level", "z_m", "parent", "pos", "outtot"]
    for name in TRACED_TAGS, part in ("C", "s", "out", "in", "give", "cross", "led")
        push!(stage_header, "$(part)_$(name)")
    end
    stage_csv = joinpath(outdir, "$(job_id)_stages.csv")
    sio = open(stage_csv, "w")
    println(sio, join(stage_header, ","))
    STAGE_IO[] = sio

    function write_rows(t, step_end)
        values = map(f -> vec(Array(parent(getproperty(integrator.u.c, f)))), FIELDS)
        println(
            io,
            join(
                [STEP[], t, step_end, 0, 0.0, (sum(weights .* v) for v in values)...],
                ",",
            ),
        )
        for l in LEVELS
            println(io, join([STEP[], t, step_end, l, z[l], (v[l] for v in values)...], ","))
        end
    end

    t_last = maximum(last, WINDOWS)
    steps = 0
    odd_stages = 0
    was_in = false
    while seconds(integrator.t) < t_last - 1e-6
        t = seconds(integrator.t)
        now_in = in_window(t)
        now_in && !was_in && write_rows(t, 0)
        RECORD_ON[] = now_in
        STAGE[] = 0
        STEP[] += 1
        CA.CTS.step!(integrator)
        if now_in
            STAGE[] == 2 || (odd_stages += 1)
            write_rows(seconds(integrator.t), 1)
            steps += 1
            if steps % 500 == 0
                flush(io)
                flush(sio)
            end
        end
        was_in = now_in
    end
    RECORD_ON[] = false
    STAGE_IO[] = devnull
    close(io)
    close(sio)
    @info "The trace finished" csv stage_csv steps odd_stages
    println("TRACE run=$job_id arm=$ARM steps=$steps odd_stages=$odd_stages csv=$csv")

    result = CA.solve_atmos!(simulation)
    @info "Tag-closure run finished" job_id result.ret_code
    print_closure_summary(outdir)
    if result.ret_code != :success
        @error "The solve did not succeed." result.ret_code
        exit(1)
    end
    return nothing
end

main_overdraw()
