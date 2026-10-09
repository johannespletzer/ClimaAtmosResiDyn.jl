#####
##### The water tags' accepted applications: an opt-in producer
#####

import NCDatasets
import LinearAlgebra: diag

"""
    WATER_TAG_APPLICATION_ROSTER_KEY

The receipt key under which the producer writes the roster of the channels it
instruments, and the ones it marks unsupported.
"""
const WATER_TAG_APPLICATION_ROSTER_KEY = "water_tag_application_roster"

# The output files, in the run's output directory.
const WATER_TAG_APPLICATION_RECEIPT = "water_tag_application_receipt.jsonl"
const WATER_TAG_APPLICATION_ARRAYS = "water_tag_applications.nc"

# The hooks the producer counts. Their firings within a step are mapped to the
# stepper's roles by the parent budget's hook template.
const WATER_TAG_APPLICATION_HOOKS = (:lim!, :constrain_state!, :T_post_imp!)

"""
    WaterApplicationChannel

One channel of the producer: a mechanism, a tag and a compartment. `quantity`
is `water_increment` for a map of the state and `water_tendency` for a writer
of the implicit tendency.
"""
struct WaterApplicationChannel
    id::String
    mechanism::Symbol
    tag::Symbol
    compartment::Symbol
    quantity::String
    units::String
    event_scale::String
end

"""
    WaterApplicationMeter

The producer's state. Each call of a metered writer takes the next slot of its
channel and writes the change it applies there, before the writer applies it.
So two opposite changes inside one step stay two applications. A slot also
holds the writer's event scale and its flags, `fallback + 2 bound + 4 clamp + 8 zero_normalization`, per cell. After each accepted step,
[`finalize_water_tag_applications!`](@ref) gives each slot its role and weight,
adds it to the channel's cumulative ledger, writes it out and frees the slots.

The meter writes only its own fields. The slots and the ledgers are allocated
once, and a slot is added only when a step needs more than any step before.
"""
mutable struct WaterApplicationMeter{F, L}
    channels::Vector{WaterApplicationChannel}
    index::Dict{NTuple{3, Symbol}, Int}
    values::Vector{Vector{F}}
    scales::Vector{Vector{F}}
    flags::Vector{Vector{F}}
    slot_firing::Vector{Vector{Int}}
    used::Vector{Int}
    ledgers::Vector{L}
    scratch::NTuple{3, F}
    firings::Vector{Tuple{Symbol, Int}}
    counts::Dict{Symbol, Int}
    active::Int
    unattributed::Int
    stepping::Bool
    precipitation::Bool
    unsupported::Vector{Tuple{String, String}}
    cadence::Symbol
    output_dir::String
    t_last::Float64
    ledger_start::String
    started::Bool
    template::Any
    pin::Any
end

_water_application_compartment(meter, ::NonPrecipitatingPart) =
    meter.precipitation ? :nonprecipitating : :total
_water_application_compartment(meter, ::RainPart) = :rain
_water_application_compartment(meter, ::SnowPart) = :snow

"""
    water_tag_application_channels(model)

The producer's roster for `model`: its channels, and the mechanisms that change
a water tag in this configuration but that it does not meter, with the reason.
"""
function water_tag_application_channels(model)
    precip = has_water_tag_precipitation(model)
    N = precip ? :nonprecipitating : :total
    channels = WaterApplicationChannel[]
    add!(mechanism, tag, compartment, quantity, scale) = push!(
        channels,
        WaterApplicationChannel(
            "$mechanism.$tag.$compartment",
            mechanism,
            tag,
            compartment,
            quantity,
            quantity == "water_increment" ? "kg m^-3" : "kg m^-3 s^-1",
            scale,
        ),
    )
    for tag in model.tags
        name = _tag_type_name(typeof(tag))
        partition = _is_partition_tag(tag)
        add!(:rescale, name, N, "water_increment", "rho_q_tot_before")
        add!(:empty, name, N, "water_increment", "rho_q_tot_before")
        if partition
            for c in (precip ? (N, :rain, :snow) : (N,))
                add!(:repair, name, c, "water_increment", "partition_positive_part")
            end
        end
        if precip
            partition && add!(:close, name, :rain, "water_increment", "rho_q_tot")
            partition && add!(:close, name, :snow, "water_increment", "rho_q_tot")
            for c in (N, :rain, :snow)
                add!(:follow, name, c, "water_increment", "rho_q_tot")
            end
        end
        if follows_water_increment(model) && partition
            add!(:inc, name, N, "water_tendency", "rho_q_tot")
            add!(:negative, name, N, "water_tendency", "rho_q_tot")
        end
    end
    unsupported = Tuple{String, String}[]
    has_water_tag_leak_correction(model) && push!(
        unsupported,
        (
            "leak",
            "The leak correction writes the explicit or implicit tendency inside \
            the EDMF diffusion. The producer does not see which evaluation the \
            stepper keeps.",
        ),
    )
    return channels, unsupported
end

"""
    build_water_tag_application_meter(on, model, Y, context; cadence, output_dir, t_start)

The producer's meter for `water_tag_applications: true`, or `nothing`. Refused
without water tags, with the tags' updraft copies, and on more than one process.
"""
build_water_tag_application_meter(on::Bool, model, Y, context; kwargs...) =
    on ? _build_water_tag_application_meter(model, Y, context; kwargs...) :
    nothing
function _build_water_tag_application_meter(
    model,
    Y,
    context;
    cadence,
    output_dir,
    t_start,
)
    tags = model.water_tagging_model
    isnothing(tags) && error(
        "`water_tag_applications: true` needs `water_tracers`. It meters the \
        corrections of the water tags, and there are none.",
    )
    has_water_tag_updraft_copies(tags) && error(
        "`water_tag_applications: true` does not support \
        `water_tag_updraft_copy: true`. The copies' repair and filter are not \
        metered, so the roster would be incomplete.",
    )
    ClimaComms.nprocs(context) == 1 || error(
        "`water_tag_applications: true` runs on one process only. Its native \
        arrays are written from the root's cells.",
    )
    channels, unsupported = water_tag_application_channels(tags)
    ᶜρ = Y.c.ρ
    F = typeof(similar(ᶜρ))
    n = length(channels)
    ledgers = [_tag_zeros(ᶜρ) for _ in 1:n]
    scratch = (similar(ᶜρ), similar(ᶜρ), similar(ᶜρ))
    index = Dict(
        (c.mechanism, c.tag, c.compartment) => i for (i, c) in enumerate(channels)
    )
    return WaterApplicationMeter{F, eltype(ledgers)}(
        channels,
        index,
        [F[] for _ in 1:n],
        [F[] for _ in 1:n],
        [F[] for _ in 1:n],
        [Int[] for _ in 1:n],
        zeros(Int, n),
        ledgers,
        scratch,
        Tuple{Symbol, Int}[],
        Dict(hook => 0 for hook in WATER_TAG_APPLICATION_HOOKS),
        0,
        0,
        false,
        has_water_tag_precipitation(tags),
        unsupported,
        Symbol(cadence),
        output_dir,
        Float64(float(t_start)),
        "zero",
        false,
        nothing,
        nothing,
    )
end

# A Float64 center field of zeros, as the tags' other accumulators are.
function _tag_zeros(ᶜρ)
    ᶜfield = Fields.Field(Float64, axes(ᶜρ))
    parent(ᶜfield) .= 0
    return ᶜfield
end

"""
    water_meter(p)

The producer's meter, or `nothing` when `water_tag_applications` is off. It is
a property of the cache's type, so the off path folds away at compile time.
"""
@inline water_meter(p) = _water_meter(p.tagging)
@inline _water_meter(::Nothing) = nothing
@inline _water_meter(tagging) =
    hasfield(typeof(tagging), :water_applications) ?
    tagging.water_applications : nothing

# The meter travels in the tags' ledger object of a correction. Without the
# producer the ledger keeps its type, so the corrections compile as before.
@inline with_water_meter(ledger, ::Nothing) = ledger
@inline with_water_meter(ledger, meter) = merge(ledger, (; meter))
@inline ledger_water_meter(ledger) =
    hasfield(typeof(ledger), :meter) ? ledger.meter : nothing

# The next slot of a channel, for one call of a writer. Outside a counted hook
# the call is not part of an accepted step's application inventory. It writes
# into a scratch slot and is counted, and the receipt reports the count.
function next_water_slot!(meter::WaterApplicationMeter, mechanism, tag, part)
    if meter.active == 0
        meter.unattributed += 1
        return meter.scratch
    end
    key = (
        mechanism,
        _tag_type_name(typeof(tag)),
        _water_application_compartment(meter, part),
    )
    c = meter.index[key]
    k = (meter.used[c] += 1)
    if k > length(meter.values[c])
        ᶜρ = first(meter.scratch)
        push!(meter.values[c], similar(ᶜρ))
        push!(meter.scales[c], similar(ᶜρ))
        push!(meter.flags[c], similar(ᶜρ))
        push!(meter.slot_firing[c], 0)
    end
    meter.slot_firing[c][k] = meter.active
    return (meter.values[c][k], meter.scales[c][k], meter.flags[c][k])
end

"""
    meter_water_leg!(meter, mechanism, tag, part, change, scale, flags)

Record one application of a writer to one tag compartment: `change` is what the
writer adds to it, `scale` its event scale and `flags` its counter code. Called
before the writer applies `change`, so it reads the same values. A no-op for
`nothing`.
"""
@inline meter_water_leg!(::Nothing, mechanism, tag, part, change, scale, flags) =
    nothing
function meter_water_leg!(
    meter::WaterApplicationMeter,
    mechanism,
    tag,
    part,
    change,
    scale,
    flags,
)
    (ᶜvalue, ᶜscale, ᶜflags) = next_water_slot!(meter, mechanism, tag, part)
    @. ᶜvalue = change
    @. ᶜscale = scale
    @. ᶜflags = flags
    return nothing
end

"""
    WaterApplicationView{mechanism}(meter, scale)

A target for the follower's writers of the implicit tendency. `tag_field` hands
each tag the next zeroed slot of its channel, so the same writer that adds a
tag's tendency to `dY` writes it here alone. `nothing` for no meter.
"""
struct WaterApplicationView{mechanism, M, S}
    meter::M
    scale::S
end
WaterApplicationView{mechanism}(meter, scale) where {mechanism} =
    WaterApplicationView{mechanism, typeof(meter), typeof(scale)}(meter, scale)
water_application_view(::Nothing, mechanism, scale) = nothing
water_application_view(meter, mechanism, scale) =
    WaterApplicationView{mechanism}(meter, scale)
function tag_field(
    view::WaterApplicationView{mechanism},
    tag::WaterTag,
) where {mechanism}
    (ᶜvalue, ᶜscale, ᶜflags) =
        next_water_slot!(view.meter, mechanism, tag, NonPrecipitatingPart())
    parent(ᶜvalue) .= 0
    parent(ᶜflags) .= 0
    @. ᶜscale = view.scale
    return ᶜvalue
end

# The counter code of one application in one cell.
@inline water_application_flags(fallback, bound, clamp, zero_normalization, x) =
    ifelse(fallback, one(x), zero(x)) + ifelse(bound, 2 * one(x), zero(x)) +
    ifelse(clamp, 4 * one(x), zero(x)) +
    ifelse(zero_normalization, 8 * one(x), zero(x))

# The rescale of a partition tag: the floor at `-pos` binds, a negative tag
# gets no share, or there is no positive water to share by.
@inline function water_tag_rescale_flags(ρq_tag, ρq_tot_after, ρq_tot_before, pos)
    ρq_tot_before > zero(ρq_tot_before) || return zero(ρq_tag)
    Δ = water_tag_partition_target(ρq_tot_after) - ρq_tot_before
    return water_application_flags(
        false,
        pos > zero(pos) && Δ < -pos,
        ρq_tag < zero(ρq_tag),
        !(pos > zero(pos)),
        ρq_tag,
    )
end
# The rescale of a source tag: a negative parent after the correction, or a
# negative tag, is clamped to zero.
@inline function water_tag_source_rescale_flags(ρq_tag, ρq_tot_after, ρq_tot_before)
    ρq_tot_before > zero(ρq_tot_before) || return zero(ρq_tag)
    return water_application_flags(
        false,
        false,
        ρq_tot_after < zero(ρq_tot_after) || ρq_tag < zero(ρq_tag),
        false,
        ρq_tag,
    )
end
# The partition repair: a negative tag is clamped, no positive water to repair
# into, or the negatives outweigh the positives and every tag is zeroed.
@inline water_tag_repair_flags(ρq_tag, pos, neg) = water_application_flags(
    false,
    pos + neg < zero(pos),
    ρq_tag < zero(ρq_tag),
    !(pos > zero(pos)),
    ρq_tag,
)
# The closing step: the parts take the rest by the non-precipitating
# composition, or nothing holds water to take it by.
@inline function water_tag_closing_flags(
    ρq_part,
    target,
    pos,
    neg,
    pos_nonprecip,
)
    rest = target - (pos + neg)
    iszero(rest) && return zero(ρq_part)
    pos > zero(pos) && return water_application_flags(
        false,
        false,
        ρq_part < zero(ρq_part),
        false,
        ρq_part,
    )
    fallback = rest > zero(rest) && pos_nonprecip > zero(pos_nonprecip)
    return water_application_flags(fallback, false, false, !fallback, ρq_part)
end
# The follow of a partition tag's part: the part is emptied where the
# compartment is not positive, the floor or the cap binds, a negative part
# gets no share, or there is nothing to share by.
@inline function water_tag_follow_flags(
    ρq_part,
    ρq_nonprecip,
    after,
    before,
    pos_part,
    pos_nonprecip,
)
    after > zero(after) ||
        return water_application_flags(true, false, false, false, ρq_part)
    Δ = after - water_tag_partition_target(before)
    if Δ < zero(Δ)
        return water_application_flags(
            false,
            pos_part > zero(pos_part) && Δ < -pos_part,
            ρq_part < zero(ρq_part),
            !(pos_part > zero(pos_part)),
            ρq_part,
        )
    end
    return water_application_flags(
        false,
        pos_nonprecip > zero(pos_nonprecip) && Δ > pos_nonprecip,
        ρq_nonprecip < zero(ρq_nonprecip),
        !(pos_nonprecip > zero(pos_nonprecip)),
        ρq_part,
    )
end
# The follow of a source tag's part: emptied where the compartment is not
# positive.
@inline water_tag_source_follow_flags(ρq_part, after) =
    water_application_flags(
        after > zero(after) ? false : true,
        false,
        false,
        false,
        ρq_part,
    )

"""
    WaterApplicationHook

A stepper hook wrapped so the producer knows which firing of the step a writer
call belongs to. It counts the firing and passes on exactly what the stepper
passed. It writes nothing the model reads.
"""
struct WaterApplicationHook{F, M}
    hook::Symbol
    f::F
    meter::M
end
function (h::WaterApplicationHook)(args...)
    meter = h.meter
    # Writer calls before the first firing belong to the initial state.
    meter.stepping || (meter.unattributed = 0; meter.stepping = true)
    ordinal = (meter.counts[h.hook] += 1)
    push!(meter.firings, (h.hook, ordinal))
    meter.active = length(meter.firings)
    h.f(args...)
    meter.active = 0
    return nothing
end
water_application_hook(::Nothing, hook, f) = f
water_application_hook(meter, hook, f) = WaterApplicationHook(hook, f, meter)
water_application_hook(meter, hook, ::Nothing) = nothing
water_application_hook(::Nothing, hook, ::Nothing) = nothing

"""
    water_tag_application_pin(integrator)

The integrator pin of the receipt: the parent budget's `timestepper_pin` and
the implicit diagonal of the stepper's tableau, under the name the reader
expects, `unconstrained_imex_ark`. `tableau` names the tableau.
"""
function water_tag_application_pin(integrator)
    PB = Internals.ParentBudget
    pin = PB.timestepper_pin(integrator)
    tableau = integrator.cache.tableau
    return (;
        algorithm = "unconstrained_imex_ark",
        package = "ClimaTimeSteppers",
        version = string(pin.package_version),
        tableau = string(pin.algorithm),
        b_exp = Float64.(pin.b_exp),
        b_imp = Float64.(pin.b_imp),
        implicit_diagonal = Float64.(diag(tableau.a_imp.coeffs)),
        fsal = pin.fsal,
    )
end

"""
    water_application_role(call)

The role and stage of a hook firing in the receipt, or `nothing` for a stage
observation, a change the accepted state does not take additively.
"""
function water_application_role(call)
    call.role === :final && return (:final_map, 0)
    call.role === :post_newton && return (:post_newton, call.stage)
    call.role === :correction && return (:implicit, call.stage)
    return nothing
end

"""
    water_application_coefficient(role, stage, pin, start, stop)

The weight of an application in the accepted step `[start, stop]`, in Float64,
as the reader computes it from the pin and the step's edges.
"""
function water_application_coefficient(role, stage, pin, start, stop)
    role === :final_map && return 1.0
    role === :post_newton && return pin.b_imp[stage] / pin.implicit_diagonal[stage]
    role === :implicit && return (stop - start) * pin.b_imp[stage]
    role === :explicit && return (stop - start) * pin.b_exp[stage]
    error("unknown application role $role")
end

# A tiny JSON writer for the receipt: strings, numbers, booleans, `nothing`,
# vectors, tuples, dictionaries and named tuples.
_json(io, x::AbstractString) = print(
    io,
    '"',
    replace(x, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n"),
    '"',
)
_json(io, x::Symbol) = _json(io, string(x))
_json(io, x::Bool) = print(io, x ? "true" : "false")
_json(io, x::Integer) = print(io, x)
function _json(io, x::AbstractFloat)
    isfinite(x) || error("The receipt holds a non-finite number")
    return print(io, repr(Float64(x)))
end
_json(io, ::Nothing) = print(io, "null")
function _json(io, x::Union{AbstractVector, Tuple})
    print(io, '[')
    for (i, v) in enumerate(x)
        i > 1 && print(io, ',')
        _json(io, v)
    end
    return print(io, ']')
end
function _json(io, x::Union{AbstractDict, NamedTuple})
    print(io, '{')
    for (i, (k, v)) in enumerate(pairs(x))
        i > 1 && print(io, ',')
        _json(io, string(k))
        print(io, ':')
        _json(io, v)
    end
    return print(io, '}')
end
water_application_json(x) = sprint(_json, x)

function _git_commit()
    dir = pkgdir(@__MODULE__)
    try
        commit = readchomp(`git -C $dir rev-parse HEAD`)
        dirty = !isempty(readchomp(`git -C $dir status --porcelain`))
        return commit, dirty
    catch
        return "unknown", true
    end
end

# The native cells: the volume weight and the coordinates of each node, in the
# order of the field's storage.
function _water_application_geometry(ᶜρ)
    space = axes(ᶜρ)
    weights = vec(Array(parent(Fields.local_geometry_field(space).WJ)))
    coord = Fields.coordinate_field(space)
    names = propertynames(coord)
    geometry = hcat((vec(Array(parent(getproperty(coord, n)))) for n in names)...)
    units = space isa Spaces.FiniteDifferenceSpace ? "m" : "m^3"
    return Float64.(weights), Float64.(geometry), collect(string.(names)), units
end

# The header of the receipt and the native file, written once per run segment
# at its first accepted step.
function _start_water_tag_applications!(meter, integrator)
    PB = Internals.ParentBudget
    PB.check_algorithm(integrator.alg)
    f = integrator.sol.prob.f
    meter.template = PB.hook_template(
        integrator.cache.tableau,
        meter.cadence,
        !isnothing(f.T_post_imp!),
        !isnothing(f.initialize_imp!),
        CTS.is_fsal(integrator.alg),
    )
    meter.pin = water_tag_application_pin(integrator)
    ᶜρ = integrator.u.c.ρ
    FT = eltype(ᶜρ)
    commit, dirty = _git_commit()
    roster = (;
        channels = [
            (;
                id = c.id,
                mechanism = c.mechanism,
                tag = c.tag,
                compartment = c.compartment,
                quantity = c.quantity,
                units = c.units,
                event_scale = c.event_scale,
                status = "observed",
            ) for c in meter.channels
        ],
        unsupported = [(; mechanism = m, reason = r) for (m, r) in meter.unsupported],
    )
    header = Dict{String, Any}(
        "schema_version" => 1,
        "semantics" => "weighted_final_additive_updates",
        "kind" => "runtime_capture",
        "producer" => "climaatmos.water_tag_applications",
        "model_commit" => commit,
        "model_dirty" => dirty,
        "integrator_pin" => meter.pin,
        "precision" => string(FT),
        "segment_start_seconds" => meter.t_last,
        "ledger_start" => meter.ledger_start,
        "native_arrays" => WATER_TAG_APPLICATION_ARRAYS,
        "roster_key" => WATER_TAG_APPLICATION_ROSTER_KEY,
        WATER_TAG_APPLICATION_ROSTER_KEY => roster,
    )
    open(joinpath(meter.output_dir, WATER_TAG_APPLICATION_RECEIPT), "a") do io
        println(io, water_application_json(header))
    end
    weights, geometry, names, units = _water_application_geometry(ᶜρ)
    path = joinpath(meter.output_dir, WATER_TAG_APPLICATION_ARRAYS)
    NCDatasets.NCDataset(path, "c") do ds
        NCDatasets.defDim(ds, "cell", length(weights))
        NCDatasets.defDim(ds, "coord", length(names))
        NCDatasets.defDim(ds, "channel", length(meter.channels))
        NCDatasets.defDim(ds, "record", Inf)
        NCDatasets.defDim(ds, "edge", Inf)
        ds.attrib["weight_units"] = units
        ds.attrib["precision"] = string(FT)
        ds.attrib["flags"] = "fallback + 2 bound + 4 clamp + 8 zero_normalization"
        NCDatasets.defVar(ds, "weights", weights, ("cell",))
        NCDatasets.defVar(ds, "geometry", geometry, ("cell", "coord"))
        NCDatasets.defVar(ds, "coord_name", names, ("coord",))
        NCDatasets.defVar(ds, "channel_id", [c.id for c in meter.channels], ("channel",))
        NCDatasets.defVar(
            ds,
            "channel_quantity",
            [c.quantity for c in meter.channels],
            ("channel",),
        )
        NCDatasets.defVar(
            ds,
            "channel_units",
            [c.units for c in meter.channels],
            ("channel",),
        )
        NCDatasets.defVar(ds, "record_values", FT, ("cell", "record"))
        NCDatasets.defVar(ds, "record_event_scale", FT, ("cell", "record"))
        NCDatasets.defVar(ds, "record_flags", Int8, ("cell", "record"))
        NCDatasets.defVar(ds, "record_channel", Int32, ("record",))
        NCDatasets.defVar(ds, "record_id", String, ("record",))
        NCDatasets.defVar(ds, "ledger", Float64, ("cell", "channel", "edge"))
        NCDatasets.defVar(ds, "ledger_time", Float64, ("edge",))
        ds["ledger"][:, :, 1] = _ledger_matrix(meter)
        ds["ledger_time"][1] = meter.t_last
    end
    meter.started = true
    return nothing
end

_ledger_matrix(meter) = reduce(
    hcat,
    (_float64_values(L, first(meter.scratch)) for L in meter.ledgers),
)

# The values of a Float64 field in the order of the storage of `ᶜρ`'s field.
# On a Float32 space the storage holds each Float64 in two slots of the
# field dimension, the one dimension whose size differs from `ᶜρ`'s.
function _float64_values(ᶜL, ᶜρ)
    a = Array(parent(ᶜL))
    eltype(a) == Float64 && return vec(a)
    s, r = size(a), size(parent(ᶜρ))
    f = findfirst(i -> s[i] != r[i], 1:ndims(a))
    b = permutedims(a, (f, filter(!=(f), 1:ndims(a))...))
    return vec(reinterpret(Float64, b))
end

"""
    finalize_water_tag_applications!(integrator)

After an accepted step: check the step's hook firings against the template,
give each application its role and weight, add the applied ones to their
channels' cumulative ledgers, and append the step to the receipt and the native
arrays. A channel with no applied record gets an explicit zero. An application
that is zero in every cell, with no counter set, is left out and counted. Then
the slots are freed for the next step. The stepper never rejects a step, so
each step has one trial, accepted.
"""
function finalize_water_tag_applications!(integrator)
    meter = water_meter(integrator.p)
    meter.started || _start_water_tag_applications!(meter, integrator)
    (; template, pin) = meter
    for hook in WATER_TAG_APPLICATION_HOOKS
        expected = length(template.per_hook[hook])
        meter.counts[hook] == expected || error(
            "The water tag producer counted $(meter.counts[hook]) firings of \
            $hook in a step, and the stepper's template has $expected. The \
            roles of its applications would be wrong.",
        )
    end
    start, stop = meter.t_last, Float64(float(integrator.t))
    step_id = "t$(repr(start))"
    trial = "$step_id.trial"
    FT = eltype(integrator.u.c.ρ)
    applications = Any[]
    values, scales, flags = Vector{FT}[], Vector{FT}[], Vector{Int8}[]
    channel_of, ids = Int32[], String[]
    observations, dropped = 0, 0
    function push_record!(c, k, role, stage, v, s, fl)
        channel = meter.channels[c]
        tendency = channel.quantity == "water_tendency"
        tendency == (role in (:implicit, :explicit)) || error(
            "The water tag producer's channel $(channel.id) got a $role \
            application. Its quantity is $(channel.quantity).",
        )
        coefficient = water_application_coefficient(role, stage, pin, start, stop)
        id = "$step_id/$(channel.id)/$k"
        record = Dict{String, Any}(
            "channel" => channel.id,
            "record_id" => id,
            "trial" => trial,
            "application_id" => "a$k",
            "evaluation_id" => "e$k",
            "disposition" => "applied",
            "role" => role,
            "coefficient" => coefficient,
            "coefficient_units" => tendency ? "s" : "1",
        )
        role === :final_map || (record["stage"] = stage)
        push!(applications, record)
        push!(values, v)
        push!(scales, s)
        push!(flags, fl)
        push!(channel_of, c)
        push!(ids, id)
        return coefficient
    end
    for c in eachindex(meter.channels)
        applied = 0
        for k in 1:meter.used[c]
            (hook, ordinal) = meter.firings[meter.slot_firing[c][k]]
            call = template.calls[template.per_hook[hook][ordinal]]
            role = water_application_role(call)
            if isnothing(role)
                observations += 1
                continue
            end
            ᶜvalue = meter.values[c][k]
            v = vec(Array(parent(ᶜvalue)))
            fl = Int8.(vec(Array(parent(meter.flags[c][k]))))
            if all(iszero, v) && all(iszero, fl)
                dropped += 1
                continue
            end
            s = vec(Array(parent(meter.scales[c][k])))
            coefficient = push_record!(c, k, role..., v, s, fl)
            ᶜL = meter.ledgers[c]
            @. ᶜL += coefficient * ᶜvalue
            applied += 1
        end
        if applied == 0
            # An explicit zero: the channel was observed and nothing moved.
            tendency = meter.channels[c].quantity == "water_tendency"
            role = tendency ? (:implicit, first(template.implicit_stages)) : (:final_map, 0)
            n = length(first(meter.scratch))
            push_record!(c, 0, role..., zeros(FT, n), zeros(FT, n), zeros(Int8, n))
        end
    end
    step = Dict{String, Any}(
        "id" => step_id,
        "start_seconds" => start,
        "end_seconds" => stop,
        "accepted_trial" => trial,
        "trials" => [Dict("id" => trial, "decision" => "accepted")],
        "applications" => applications,
        "stage_observations" => observations,
        "dropped_zero_applications" => dropped,
        "unattributed_calls" => meter.unattributed,
    )
    open(joinpath(meter.output_dir, WATER_TAG_APPLICATION_RECEIPT), "a") do io
        println(io, water_application_json(step))
    end
    path = joinpath(meter.output_dir, WATER_TAG_APPLICATION_ARRAYS)
    NCDatasets.NCDataset(path, "a") do ds
        r = ds.dim["record"]
        rows = (r + 1):(r + length(ids))
        ds["record_values"][:, rows] = reduce(hcat, values)
        ds["record_event_scale"][:, rows] = reduce(hcat, scales)
        ds["record_flags"][:, rows] = reduce(hcat, flags)
        ds["record_channel"][rows] = channel_of
        ds["record_id"][rows] = ids
        e = ds.dim["edge"] + 1
        ds["ledger"][:, :, e] = _ledger_matrix(meter)
        ds["ledger_time"][e] = stop
    end
    meter.used .= 0
    empty!(meter.firings)
    for hook in WATER_TAG_APPLICATION_HOOKS
        meter.counts[hook] = 0
    end
    meter.unattributed = 0
    meter.t_last = stop
    return nothing
end

"""
    water_tag_application_callbacks(meter)

The producer's callback after every accepted step, or `()` without it.
"""
water_tag_application_callbacks(::Nothing) = ()
water_tag_application_callbacks(meter) = (
    call_every_n_steps(finalize_water_tag_applications!, 1; skip_first = true),
)

# The meter's cumulative ledgers in a checkpoint, one per channel.
water_application_checkpoint_fields(::Nothing) = Pair{String, Any}[]
water_application_checkpoint_fields(meter) = Pair{String, Any}[
    "tag_ledger.applications.$(c.id)" => L for
    (c, L) in zip(meter.channels, meter.ledgers)
]
is_water_application_checkpoint_field(name) =
    startswith(name, "tag_ledger.applications.")
