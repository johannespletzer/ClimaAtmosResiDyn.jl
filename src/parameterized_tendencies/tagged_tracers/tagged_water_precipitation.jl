#####
##### The rain and snow parts of the water tags
#####
##### Under `water_tag_precipitation: true` each water tag has three parts
##### (design/RAIN_SNOW_TAGS.md on the record branch, WP4b). `ρq_tag_<name>`,
##### called `N` here, holds the water that is neither rain nor snow: vapour,
##### cloud liquid and cloud ice. `ρq_rtag_<name>`, `R`, holds rain, and
##### `ρq_stag_<name>`, `S`, holds snow. Each part is a share of one compartment
##### of the parent: `N` of `ρq_tot - ρq_rai - ρq_sno`, `R` of `ρq_rai` and `S` of
##### `ρq_sno`. The tag's total water is the sum of its parts. It is derived for
##### output.
#####
##### This is stage 1 of the note (its section 13): a 1-moment column without
##### EDMF. The key is refused under EDMF and with updraft copies.
#####
##### What moves the parts:
#####
#####   - rain and snow sediment linearly in their part, by the parent species'
#####     own operator and Jacobian block (`sediment_water_tags!`);
#####   - `N` sediments its cloud by its share, as the tags do without the key;
#####   - the microphysics moves water between the parts by its gross flows
#####     (`water_tag_microphysics_change`), with an audit against the net-flow
#####     rule;
#####   - the limiters and constraints move each compartment's change between
#####     its part and `N` (`rescale_water_tags!`);
#####   - rain and snow take no vertical diffusion, hyperdiffusion or sponge,
#####     and `N` takes those of the diffusing water `q_tot_eff`.

# ============================================================================
# The three parts
# ============================================================================

"""
    WaterTagPart

One of the three parts of a water tag under `water_tag_precipitation: true`:
[`NonPrecipitatingPart`](@ref), `RainPart` or `SnowPart`. Each names a field of
the tag and the compartment of the parent it is a share of.
"""
abstract type WaterTagPart end

"""
    NonPrecipitatingPart()
    RainPart()
    SnowPart()

The parts of a water tag. `NonPrecipitatingPart` is `ρq_tag_<name>`, a share of
`ρq_tot - ρq_rai - ρq_sno`. `RainPart` is `ρq_rtag_<name>`, a share of
`ρq_rai`. `SnowPart` is `ρq_stag_<name>`, a share of `ρq_sno`.
"""
struct NonPrecipitatingPart <: WaterTagPart end
struct RainPart <: WaterTagPart end
struct SnowPart <: WaterTagPart end

Base.broadcastable(part::WaterTagPart) = tuple(part)

# The rain and snow parts' field in a state or tendency, by the tag's type
# parameter, as `tag_field` finds `ρq_tag_<name>`.
@generated rain_tag_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:ρq_rtag_, name)))
@generated snow_tag_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:ρq_stag_, name)))

# The parts as `MatrixFields.FieldName`s relative to `Y.c`, for the Jacobian.
@generated function rain_tag_field_name(::WaterTag{name}) where {name}
    field_name = Symbol(:ρq_rtag_, name)
    return :(MatrixFields.FieldName($(QuoteNode(field_name))))
end
@generated function snow_tag_field_name(::WaterTag{name}) where {name}
    field_name = Symbol(:ρq_stag_, name)
    return :(MatrixFields.FieldName($(QuoteNode(field_name))))
end

# The audit's state records of a tag (`water_tag_microphysics_audit`).
@generated rain_audit_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:q_rtag_aud_, name)))
@generated snow_audit_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:q_stag_aud_, name)))

# Single-entry NamedTuples, as `tag_entry` builds `ρq_tag_<name>`.
@generated function rain_tag_entry(::WaterTag{name}, value) where {name}
    field_name = Symbol(:ρq_rtag_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end
@generated function snow_tag_entry(::WaterTag{name}, value) where {name}
    field_name = Symbol(:ρq_stag_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

"""
    water_tag_part_field(obj, tag, part)

The field of `tag`'s `part` in `obj`, a state, a tendency or a keyed cache.
"""
water_tag_part_field(obj, tag, ::NonPrecipitatingPart) = tag_field(obj, tag)
water_tag_part_field(obj, tag, ::RainPart) = rain_tag_field(obj, tag)
water_tag_part_field(obj, tag, ::SnowPart) = snow_tag_field(obj, tag)

"""
    water_tag_part_parent(ᶜY, part)

The compartment of the parent that `part` is a share of: `ρq_tot - ρq_rai -
ρq_sno`, lazily, for the non-precipitating part, and `ρq_rai` or `ρq_sno` for
rain and snow.
"""
water_tag_part_parent(ᶜY, ::NonPrecipitatingPart) =
    @. lazy(ᶜY.ρq_tot - ᶜY.ρq_rai - ᶜY.ρq_sno)
water_tag_part_parent(ᶜY, ::RainPart) = ᶜY.ρq_rai
water_tag_part_parent(ᶜY, ::SnowPart) = ᶜY.ρq_sno

"""
    water_tag_parent(ᶜY, model)

What the tags' `ρq_tag_<name>` fields partition: `ρq_tot`, and under
`water_tag_precipitation: true` the water that is neither rain nor snow,
`ρq_tot - ρq_rai - ρq_sno`. Every share of a `ρq_tag_<name>` field divides by
it. The branch folds away at compile time.
"""
water_tag_parent(ᶜY, model) =
    has_water_tag_precipitation(model) ?
    water_tag_part_parent(ᶜY, NonPrecipitatingPart()) : ᶜY.ρq_tot

# The scratch field that holds the share denominator of each part.
water_tag_part_norm(scratch, ::NonPrecipitatingPart) =
    scratch.ᶜtagging_q_share_norm
water_tag_part_norm(scratch, ::RainPart) = scratch.ᶜtagging_q_share_norm_rai
water_tag_part_norm(scratch, ::SnowPart) = scratch.ᶜtagging_q_share_norm_sno

"""
    is_water_precip_part_name(name)

Whether `name` (a `Symbol` like `:ρq_rtag_upper`, or a
`MatrixFields.FieldName`) is the rain or snow part of a water tag,
`ρq_rtag_<name>` or `ρq_stag_<name>`. [`is_water_tag_name`](@ref) does not
see these parts, and [`is_tagged_tracer_name`](@ref) does.
"""
is_water_precip_part_name(name::Symbol) =
    startswith(string(name), "ρq_rtag_") || startswith(string(name), "ρq_stag_")
is_water_precip_part_name(name::MatrixFields.FieldName) =
    is_water_precip_part_name(MatrixFields.extract_first(name))

# The same test at compile time, for the tracer loops, whose names are
# `FieldName`s.
@generated function _is_water_precip_part_field(
    ::MatrixFields.FieldName{chain},
) where {chain}
    name = string(first(chain))
    return startswith(name, "ρq_rtag_") || startswith(name, "ρq_stag_")
end

"""
    is_water_tag_audit_name(name)

Whether `name`, a `Symbol`, is a state record of the microphysics audit,
`q_rtag_aud_<name>` or `q_stag_aud_<name>`.
"""
is_water_tag_audit_name(name::Symbol) =
    startswith(string(name), "q_rtag_aud_") ||
    startswith(string(name), "q_stag_aud_")

"""
    water_tag_precip_part_state_names(model)

`Tuple` of the state-field `Symbol`s of the rain parts and then the snow parts
of every water tag, and `()` without the key.
"""
water_tag_precip_part_state_names(::Nothing) = ()
water_tag_precip_part_state_names(model::WaterTaggingModel) =
    has_water_tag_precipitation(model) ?
    (
        Tuple(Symbol(:ρq_rtag_, tag_name(tag)) for tag in model.tags)...,
        Tuple(Symbol(:ρq_stag_, tag_name(tag)) for tag in model.tags)...,
    ) : ()

"""
    water_tag_audit_state_names(model)

`Tuple` of the state-field `Symbol`s of the microphysics audit, the rain
records and then the snow records, and `()` without the key.
"""
water_tag_audit_state_names(::Nothing) = ()
water_tag_audit_state_names(model::WaterTaggingModel) =
    has_water_tag_precipitation(model) ?
    (
        Tuple(Symbol(:q_rtag_aud_, tag_name(tag)) for tag in model.tags)...,
        Tuple(Symbol(:q_stag_aud_, tag_name(tag)) for tag in model.tags)...,
    ) : ()

# The partition's parts: the region tags without sources.
_water_region_part_names(model, prefix) = Tuple(
    Symbol(prefix, tag_name(tag)) for
    tag in model.tags if !isnothing(tag.region) && isempty(tag.sources)
)

"""
    water_partition_state_names(model)

`Tuple` of the state-field `Symbol`s that together partition `ρq_tot`: the
region tags without sources, and under `water_tag_precipitation: true` their
rain and snow parts too. The closure check and `q_tag_res` sum over them.
"""
water_partition_state_names(model::WaterTaggingModel) = (
    water_region_tag_state_names(model)...,
    (
        has_water_tag_precipitation(model) ?
        (
            _water_region_part_names(model, :ρq_rtag_)...,
            _water_region_part_names(model, :ρq_stag_)...,
        ) : ()
    )...,
)

# ============================================================================
# State, cache and scratch
# ============================================================================

"""
    water_tagging_variables(ρq_tot, ρq_rai, ρq_sno, local_geometry, model)

The water tags' state for a single grid point. Without the key it is
`water_tagging_variables(ρq_tot, local_geometry, model)`. With it, each tag's
non-precipitating part starts from `ρq_tot - ρq_rai - ρq_sno` and its rain and
snow parts from `ρq_rai` and `ρq_sno`, each times the tag's mask. A tag with a
`source` starts at zero in every part. The non-precipitating parts come first,
then the rain parts, then the snow parts.
"""
water_tagging_variables(ρq_tot, ρq_rai, ρq_sno, local_geometry, ::Nothing) = (;)
water_tagging_variables(
    ρq_tot,
    ρq_rai,
    ρq_sno,
    local_geometry,
    model::WaterTaggingModel,
) =
    has_water_tag_precipitation(model) ?
    (;
        _tag_variables(
            ρq_tot - ρq_rai - ρq_sno,
            local_geometry.coordinates,
            model.tags,
        )...,
        _part_variables(
            rain_tag_entry,
            ρq_rai,
            local_geometry.coordinates,
            model.tags,
        )...,
        _part_variables(
            snow_tag_entry,
            ρq_sno,
            local_geometry.coordinates,
            model.tags,
        )...,
    ) : water_tagging_variables(ρq_tot, local_geometry, model)

_part_variables(entry, ρq, coord, ::Tuple{}) = (;)
_part_variables(entry, ρq, coord, tags::Tuple) = merge(
    entry(first(tags), tag_initial_value(first(tags), ρq, coord)),
    _part_variables(entry, ρq, coord, Base.tail(tags)),
)

"""
    water_tag_precipitation_audit_variables(value, model)

The microphysics audit's state records for a single grid point, as zeros of the
type of `value`: `q_rtag_aud_<name>` and `q_stag_aud_<name>` for each tag,
under `water_tag_precipitation: true` only. See
[`water_tag_microphysics_audit`](@ref).
"""
water_tag_precipitation_audit_variables(value, ::Nothing) = (;)
water_tag_precipitation_audit_variables(value, model::WaterTaggingModel) =
    has_water_tag_precipitation(model) ?
    _mechanism_zeros(value, _audit_names(model.tags)) : (;)
# The names come from the tags' type parameters, so the state's type can be
# inferred where it is built point by point.
@generated function _audit_names(::T) where {T <: Tuple}
    rain = Symbol[]
    snow = Symbol[]
    for tag in T.parameters
        push!(rain, Symbol(:q_rtag_aud_, tag.parameters[1]))
        push!(snow, Symbol(:q_stag_aud_, tag.parameters[1]))
    end
    names = (rain..., snow...)
    return :(Val($names))
end

"""
    rebuild_water_tags_from_state!(ᶜY, ᶜcoord, model)

Set the water tags from the state `ᶜY` holds, by the rule that built them. Under
`water_tag_precipitation: true` each part takes its masked share of its
compartment. Called by `rebuild_tags_from_state!`.
"""
rebuild_water_tags_from_state!(ᶜY, ᶜcoord, ::Nothing) = nothing
function rebuild_water_tags_from_state!(ᶜY, ᶜcoord, model::WaterTaggingModel)
    _rebuild_tag_fields!(
        ᶜY,
        ᶜcoord,
        water_tag_parent(ᶜY, model),
        model.tags,
    )
    has_water_tag_precipitation(model) || return nothing
    _rebuild_part_fields!(ᶜY, ᶜcoord, ᶜY.ρq_rai, model.tags, RainPart())
    _rebuild_part_fields!(ᶜY, ᶜcoord, ᶜY.ρq_sno, model.tags, SnowPart())
    return nothing
end
_rebuild_part_fields!(ᶜY, ᶜcoord, ᶜparent, ::Tuple{}, part) = nothing
function _rebuild_part_fields!(ᶜY, ᶜcoord, ᶜparent, tags::Tuple, part)
    tag = first(tags)
    ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
    ᶜρq_part .= tag_initial_value.(Ref(tag), ᶜparent, ᶜcoord)
    return _rebuild_part_fields!(ᶜY, ᶜcoord, ᶜparent, Base.tail(tags), part)
end

"""
    WATER_TAG_FLOW_NAMES

The six flows of water between the three compartments of the parent, as
[`water_tag_1m_flows`](@ref) returns them: `NR`, from the non-precipitating
water into rain, `NS` into snow, `RN` from rain into the non-precipitating
water, `RS` from rain into snow, `SR` from snow into rain and `SN` from snow
into the non-precipitating water. Each is a rate per unit mass of air.
"""
const WATER_TAG_FLOW_NAMES = (:NR, :NS, :RN, :RS, :SR, :SN)

# The cache under the key: the microphysics' flows, the snapshots of rain and
# snow that the corrections follow, and three sums and shifts they use.
function _water_tag_precipitation_cache(Y, model)
    has_water_tag_precipitation(model) || return (;)
    FT = eltype(Y.c.ρ)
    ᶜflows = Fields.Field(
        NamedTuple{WATER_TAG_FLOW_NAMES, NTuple{6, FT}},
        axes(Y.c),
    )
    fill!(parent(ᶜflows), 0)
    return (;
        ᶜwater_mp_flows = ᶜflows,
        ᶜwater_rai_before = copy(Y.c.ρq_rai),
        ᶜwater_sno_before = copy(Y.c.ρq_sno),
        ᶜwater_pos_2 = zero.(Y.c.ρ),
        ᶜwater_shift = zero.(Y.c.ρ),
    )
end

# The scratch under the key: the rain and snow parts' share denominators, and
# the snapshots of the bracket around the vapour nonnegativity tendency. They
# live in `p.scratch` because the microphysics may be evaluated with dual
# numbers, as the tags' own share denominator does.
_water_tag_precipitation_scratch(Y, ::Nothing) = (;)
_water_tag_precipitation_scratch(Y, model) =
    has_water_tag_precipitation(model) ?
    (;
        ᶜtagging_q_share_norm_rai = similar(Y.c.ρ),
        ᶜtagging_q_share_norm_sno = similar(Y.c.ρ),
        ᶜtagging_q_rai_snapshot = similar(Y.c.ρ),
        ᶜtagging_q_sno_snapshot = similar(Y.c.ρ),
    ) : (;)

# ============================================================================
# Shares
# ============================================================================

"""
    water_tag_part_share(ᶜY, scratch, tag, part)

Lazy field of `tag`'s share of the compartment `part` is a share of: for a
partition tag, its clamped share renormalized over the partition
([`water_tag_sediment_share`](@ref)), and for a source tag its own clamped share
([`water_tag_source_sediment_share`](@ref)). The partition's shares of a
compartment then sum to one wherever the partition holds some of it. Needs
[`water_tag_share_norm!`](@ref) for the current state.
"""
function water_tag_part_share(ᶜY, scratch, tag, part)
    ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
    ᶜparent = water_tag_part_parent(ᶜY, part)
    if _is_partition_tag(tag)
        ᶜnorm = water_tag_part_norm(scratch, part)
        return @. lazy(water_tag_sediment_share(ᶜρq_part, ᶜparent, ᶜnorm))
    else
        return @. lazy(water_tag_source_sediment_share(ᶜρq_part, ᶜparent))
    end
end

# The share denominators of the rain and snow parts, beside the one
# `water_tag_share_norm!` fills for `ρq_tag_<name>`.
_water_tag_precipitation_share_norms!(p, Y, model) =
    has_water_tag_precipitation(model) ?
    _fill_precipitation_share_norms!(p.scratch, Y.c, model.tags) : nothing
function _fill_precipitation_share_norms!(scratch, ᶜY, tags)
    for part in (RainPart(), SnowPart())
        ᶜnorm = water_tag_part_norm(scratch, part)
        ᶜnorm .= zero(eltype(ᶜnorm))
        _accumulate_part_share_norm!(ᶜnorm, ᶜY, tags, part)
    end
    return nothing
end

_accumulate_part_share_norm!(ᶜnorm, ᶜY, ::Tuple{}, part) = nothing
function _accumulate_part_share_norm!(ᶜnorm, ᶜY, tags::Tuple, part)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
        ᶜparent = water_tag_part_parent(ᶜY, part)
        @. ᶜnorm += water_tag_fraction(ᶜρq_part, ᶜparent)
    end
    return _accumulate_part_share_norm!(ᶜnorm, ᶜY, Base.tail(tags), part)
end

# ============================================================================
# Sedimentation
# ============================================================================

"""
    water_tag_sedimenting_mass_names(Y, model)

The sedimenting species whose flux the tags' `ρq_tag_<name>` fields share, as
`@name`s relative to `Y.c`: every sedimenting mass without the key, and only
cloud liquid and cloud ice with it. Rain and snow then fall in their own parts.
"""
water_tag_sedimenting_mass_names(Y, model) =
    has_water_tag_precipitation(model) ?
    unrolled_filter(
        name -> name == @name(ρq_lcl) || name == @name(ρq_icl),
        sedimenting_mass_names(Y),
    ) : sedimenting_mass_names(Y)

"""
    water_precip_part_names(Y)

`Tuple` of the `@name`s, relative to `Y.c`, of the rain and snow parts of the
water tags in `Y`. Empty without the key.
"""
water_precip_part_names(Y) =
    unrolled_filter(is_water_precip_part_name, gs_tracer_names(Y))

# One species' flux for the three parts. Rain and snow fall in their own part,
# linearly: each part is moved by the parent species' own operator, as if it
# were that species. Their sum is the species' flux wherever the parts sum to
# the species. Cloud liquid and ice fall in the non-precipitating part, by its
# share, as without the key.
function _sediment_water_tag_parts!(Yₜ, Y, p, ᶜq, ᶜw, ᶠρ, ρq_name, model)
    if ρq_name == @name(ρq_rai)
        _sediment_precip_parts!(Yₜ.c, Y.c, ᶜw, ᶠρ, model.tags, RainPart())
    elseif ρq_name == @name(ρq_sno)
        _sediment_precip_parts!(Yₜ.c, Y.c, ᶜw, ᶠρ, model.tags, SnowPart())
    else
        _sediment_water_tags!(
            Yₜ.c,
            Y.c,
            p.scratch.ᶜtagging_q_share_norm,
            ᶜq,
            ᶜw,
            ᶠρ,
            model.tags,
            water_tag_parent(Y.c, model),
        )
    end
    return nothing
end

_sediment_precip_parts!(ᶜYₜ, ᶜY, ᶜw, ᶠρ, ::Tuple{}, part) = nothing
function _sediment_precip_parts!(ᶜYₜ, ᶜY, ᶜw, ᶠρ, tags::Tuple, part)
    tag = first(tags)
    ᶜρq_partₜ = water_tag_part_field(ᶜYₜ, tag, part)
    ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
    # `-(ᶜw)` is parenthesized for the reason `sediment_water_tags!` gives.
    @. ᶜρq_partₜ +=
        -1 * ᶜprecipdivᵥ(
            ᶠρ * ᶠtop_bias(
                Geometry.WVector(-(ᶜw)) * specific(ᶜρq_part, ᶜY.ρ),
            ),
        )
    return _sediment_precip_parts!(ᶜYₜ, ᶜY, ᶜw, ᶠρ, Base.tail(tags), part)
end

"""
    update_water_precip_part_sedimentation_jacobian!(matrix, Y, p)

Set the Jacobian block of each rain and snow part to the block of its parent
species, `ρq_rai` or `ρq_sno`, value for value. Each part falls by the
species' own linear operator, so its block is the species' block. The parts
take nothing else implicitly that has a block, and no other row names them, so
the split solver solves each apart. Called at the end of the sedimentation
update, after the species' blocks are set. A no-op without the key.
"""
function update_water_precip_part_sedimentation_jacobian!(matrix, Y, p)
    has_water_tag_precipitation(p.atmos.water_tagging_model) || return nothing
    ∂ᶜρq_rai_err_∂ᶜρq_rai = matrix[@name(c.ρq_rai), @name(c.ρq_rai)]
    ∂ᶜρq_sno_err_∂ᶜρq_sno = matrix[@name(c.ρq_sno), @name(c.ρq_sno)]
    MatrixFields.unrolled_foreach(p.atmos.water_tagging_model.tags) do tag
        ∂ᶜrain_err_∂ᶜrain = matrix[
            center_state_name(rain_tag_field_name(tag)),
            center_state_name(rain_tag_field_name(tag)),
        ]
        @. ∂ᶜrain_err_∂ᶜrain = ∂ᶜρq_rai_err_∂ᶜρq_rai
        ∂ᶜsnow_err_∂ᶜsnow = matrix[
            center_state_name(snow_tag_field_name(tag)),
            center_state_name(snow_tag_field_name(tag)),
        ]
        @. ∂ᶜsnow_err_∂ᶜsnow = ∂ᶜρq_sno_err_∂ᶜρq_sno
    end
    return nothing
end

# ============================================================================
# Microphysics: the gross flows
# ============================================================================

"""
    WaterTagFlows1M()

A scheme tag for `BMT.bulk_microphysics_tendencies`. With it the 1-moment
linearized average returns the six flows between the three compartments
([`WATER_TAG_FLOW_NAMES`](@ref)) instead of the four net tendencies. It lets the
model's own quadrature evaluator (`Microphysics1MEvaluator`) average the flows
over the same points and weights as the tendencies. See
[`water_tag_1m_flows`](@ref).
"""
struct WaterTagFlows1M end
Base.broadcastable(x::WaterTagFlows1M) = tuple(x)

function BMT.bulk_microphysics_tendencies(
    ::BMT.LinearizedAverage,
    ::WaterTagFlows1M,
    mp,
    tps,
    ρ,
    T,
    q_tot,
    q_lcl,
    q_icl,
    q_rai,
    q_sno,
    Δt,
    nsub = 1,
)
    flows = water_tag_1m_flows(
        mp,
        tps,
        ρ,
        T,
        q_tot,
        q_lcl,
        q_icl,
        q_rai,
        q_sno,
        Δt,
        nsub,
    )
    return NamedTuple{WATER_TAG_FLOW_NAMES}(
        map(name -> getproperty(flows, name), WATER_TAG_FLOW_NAMES),
    )
end

"""
    water_tag_1m_flows(mp, tps, ρ, T, q_tot, q_lcl, q_icl, q_rai, q_sno, Δt, nsub)

The 1-moment microphysics over `Δt`, decomposed into the flows of water between
the non-precipitating water `N` (vapour, cloud liquid, cloud ice), rain `R` and
snow `S`. Returns the six flows of [`WATER_TAG_FLOW_NAMES`](@ref), each averaged
over `Δt`, and the net tendencies of rain and snow, `dq_rai_dt` and
`dq_sno_dt`.

It repeats `BMT.bulk_microphysics_tendencies(BMT.LinearizedAverage(), ...)` of
CloudMicrophysics 0.40, substep for substep, with the same arithmetic. Each
substep solves the linearized system `(q* - q)/Δt = M q* + e`. A sink is linear
in its donor, `D q_donor*`, so each process's transfer over the substep is its
coefficient times the solved donor. The transfers that cross between
compartments are summed into the six flows. Transfers inside `N`, such as
condensation or ice melt, do not move a tag's water between its parts, so they
are left out. The flows' net is the tendency's net, to rounding. A test holds
the two nets to that.

This is the per-process decomposition that the design note's section 9 calls
the gross flows. Each flow is later attributed with its donor's composition
([`water_tag_microphysics_change`](@ref)).
"""
@inline function water_tag_1m_flows(
    mp,
    tps,
    ρ,
    T,
    q_tot,
    q_lcl,
    q_icl,
    q_rai,
    q_sno,
    Δt,
    nsub,
)
    FT = typeof(q_tot)
    q_rai_0 = q_rai
    q_sno_0 = q_sno
    Δt_sub = Δt / FT(nsub)
    Lv_over_cp =
        BMT.TDI.TD.Parameters.LH_v0(tps) / BMT.TDI.TD.Parameters.cp_d(tps)
    Ls_over_cp =
        BMT.TDI.TD.Parameters.LH_s0(tps) / BMT.TDI.TD.Parameters.cp_d(tps)
    NR = NS = RN = RS = SR = SN = zero(FT)
    for _ in 1:nsub
        (; rates, flows) = _water_tag_1m_substep(
            mp,
            tps,
            ρ,
            T,
            q_tot,
            q_lcl,
            q_icl,
            q_rai,
            q_sno,
            Δt_sub,
        )
        # The state update of `BMT.bulk_microphysics_tendencies`.
        q_lcl += rates.dq_lcl_dt * Δt_sub
        q_icl += rates.dq_icl_dt * Δt_sub
        q_rai += rates.dq_rai_dt * Δt_sub
        q_sno += rates.dq_sno_dt * Δt_sub
        T +=
            (
                Lv_over_cp * (rates.dq_lcl_dt + rates.dq_rai_dt) +
                Ls_over_cp * (rates.dq_icl_dt + rates.dq_sno_dt)
            ) * Δt_sub
        NR += flows.NR * Δt_sub
        NS += flows.NS * Δt_sub
        RN += flows.RN * Δt_sub
        RS += flows.RS * Δt_sub
        SR += flows.SR * Δt_sub
        SN += flows.SN * Δt_sub
    end
    return (;
        NR = NR / Δt,
        NS = NS / Δt,
        RN = RN / Δt,
        RS = RS / Δt,
        SR = SR / Δt,
        SN = SN / Δt,
        dq_rai_dt = (q_rai - q_rai_0) / Δt,
        dq_sno_dt = (q_sno - q_sno_0) / Δt,
    )
end

# One substep of `BMT._linearized_implicit_step`, CloudMicrophysics 0.40, line
# for line, and the flows it implies. The rain row of the solved system is
# `(q_rai* - q_rai)/Δt = M31 q_lcl* + M33 q_rai* + M34 q_sno*`, and the snow row
# `M41 q_lcl* + M42 q_icl* + M43 q_rai* + M44 q_sno* + α e4`. `M31` holds the
# transfers from cloud liquid into rain, `M41` and `M42` those from cloud
# liquid and ice into snow, `α e4` vapour deposition on snow, `M43` rain's
# transfers into snow and `M34` snow's into rain. What rain loses beyond
# `M43` is evaporation, `-(M33 + M43)`, and what snow loses beyond `M34` is
# sublimation, `-(M44 + M34)`.
@inline function _water_tag_1m_substep(
    mp,
    tps,
    ρ,
    T,
    q_tot,
    q_lcl,
    q_icl,
    q_rai,
    q_sno,
    Δt,
)
    FT = typeof(q_tot)
    src = BMT._microphysics_source_terms(
        BMT.Microphysics1Moment(),
        mp,
        tps,
        ρ,
        T,
        q_tot,
        q_lcl,
        q_icl,
        q_rai,
        q_sno,
    )
    q_min = BMT.TDI.TD.Parameters.q_min(tps)
    lin = BMT._linearize(src, q_lcl, q_icl, q_rai, q_sno, q_min, Δt)

    invΔt = one(FT) / Δt

    q_sat_min = min(
        BMT.TDI.saturation_vapor_specific_content_over_liquid(tps, T, ρ),
        BMT.TDI.saturation_vapor_specific_content_over_ice(tps, T, ρ),
    )
    q_v = q_tot - q_lcl - q_icl - q_rai - q_sno
    α = min(
        one(FT),
        max(zero(FT), q_v - q_sat_min) * invΔt /
        max(lin.e1 + lin.e2 + lin.e4, eps(FT)),
    )

    a11 = invΔt - lin.M11
    a12 = -lin.M12
    a21 = -lin.M21
    a22 = invΔt - lin.M22
    a31 = -lin.M31
    a33 = invΔt - lin.M33
    a34 = -lin.M34
    a41 = -lin.M41
    a42 = -lin.M42
    a43 = -lin.M43
    a44 = invΔt - lin.M44

    b1 = α * lin.e1 + invΔt * q_lcl
    b2 = α * lin.e2 + invΔt * q_icl
    b3 = invΔt * q_rai
    b4 = α * lin.e4 + invΔt * q_sno

    det12 = muladd(-a12, a21, a11 * a22)
    q_lcl_new = (b1 * a22 - a12 * b2) / det12
    q_icl_new = (a11 * b2 - a21 * b1) / det12

    r3 = muladd(-a31, q_lcl_new, b3)
    r4 = muladd(-a41, q_lcl_new, muladd(-a42, q_icl_new, b4))

    det = muladd(-a34, a43, a33 * a44)
    q_rai_new = (r3 * a44 - a34 * r4) / det
    q_sno_new = (a33 * r4 - r3 * a43) / det

    rates = (;
        dq_lcl_dt = (q_lcl_new - q_lcl) * invΔt,
        dq_icl_dt = (q_icl_new - q_icl) * invΔt,
        dq_rai_dt = (q_rai_new - q_rai) * invΔt,
        dq_sno_dt = (q_sno_new - q_sno) * invΔt,
    )
    flows = (;
        NR = lin.M31 * q_lcl_new,
        NS = lin.M41 * q_lcl_new + lin.M42 * q_icl_new + α * lin.e4,
        RN = -(lin.M33 + lin.M43) * q_rai_new,
        RS = lin.M43 * q_rai_new,
        SR = lin.M34 * q_sno_new,
        SN = -(lin.M44 + lin.M34) * q_sno_new,
    )
    return (; rates, flows)
end

"""
    water_tag_1m_flows_grid_mean(ρ, q_tot_nonneg, q_lcl, q_icl, q_rai, q_sno, T, cmp, thp, dt, nsubs)

The flows of [`water_tag_1m_flows`](@ref) at the grid mean, with the arguments
of `microphysics_tendencies_1m`'s grid-mean form, which the model calls without
SGS quadrature.
"""
@inline water_tag_1m_flows_grid_mean(
    ρ,
    q_tot_nonneg,
    q_lcl,
    q_icl,
    q_rai,
    q_sno,
    T,
    cmp,
    thp,
    dt,
    nsubs,
) = BMT.bulk_microphysics_tendencies(
    BMT.LinearizedAverage(),
    WaterTagFlows1M(),
    cmp,
    thp,
    ρ,
    T,
    q_tot_nonneg,
    q_lcl,
    q_icl,
    q_rai,
    q_sno,
    dt,
    nsubs,
)

"""
    set_water_tag_microphysics_flows!(Y, p)

Fill `p.tagging.ᶜwater_mp_flows` with the flows between the compartments
([`water_tag_1m_flows`](@ref)) from the state and inputs the model's 1-moment
microphysics uses. Called right after `set_microphysics_tendency_cache!`, so the
flows are frozen with the model's tendencies. With SGS quadrature the flows are
averaged by the model's own evaluator, over the same points and weights. A
no-op without the key, and while the cache is built, before `p.tagging` exists.
The flows start at zero, so a tendency read before they are set moves the
parts by the net-flow rule alone.

It costs about as much as the microphysics itself (the design note, section
9).
"""
set_water_tag_microphysics_flows!(Y, p) = _set_water_tag_microphysics_flows!(
    Y,
    p,
    p.atmos.water_tagging_model,
    p.atmos.microphysics_model,
)
_set_water_tag_microphysics_flows!(Y, p, model, microphysics_model) = nothing
function _set_water_tag_microphysics_flows!(
    Y,
    p,
    model::WaterTaggingModel,
    mp1m::NonEquilibriumMicrophysics1M,
)
    has_water_tag_precipitation(model) || return nothing
    hasproperty(p, :tagging) || return nothing
    (; dt) = p
    (; ᶜT, ᶜq_tot_nonneg) = p.precomputed
    ᶜflows = p.tagging.ᶜwater_mp_flows
    thp = CAP.thermodynamics_params(p.params)
    cmp = CAP.microphysics_1m_params(p.params)
    # As `set_microphysics_tendency_cache!` for 1-moment microphysics.
    ᶜq_lcl = @. lazy(specific(Y.c.ρq_lcl, Y.c.ρ))
    ᶜq_icl = @. lazy(specific(Y.c.ρq_icl, Y.c.ρ))
    ᶜq_rai = @. lazy(specific(Y.c.ρq_rai, Y.c.ρ))
    ᶜq_sno = @. lazy(specific(Y.c.ρq_sno, Y.c.ρ))
    sgs_quad = p.atmos.sgs_quadrature
    if not_quadrature(sgs_quad)
        @. ᶜflows = water_tag_1m_flows_grid_mean(
            Y.c.ρ, ᶜq_tot_nonneg, ᶜq_lcl, ᶜq_icl, ᶜq_rai, ᶜq_sno,
            ᶜT, cmp, thp, dt, mp1m.n_substeps,
        )
    else
        (; ᶜT′T′, ᶜq′q′, ᶜsgs_moments) = p.precomputed
        corr_Tq = correlation_Tq(p.params)
        α = sgs_variance_fidelity(CAP.cloud_fraction_steepness_scale(p.params))
        @. ᶜflows = microphysics_tendencies_1m(
            WaterTagFlows1M(), sgs_quad, cmp, thp, Y.c.ρ, ᶜT,
            ᶜq_tot_nonneg, ᶜq_lcl, ᶜq_icl, ᶜq_rai, ᶜq_sno,
            ᶜT′T′, ᶜq′q′, corr_Tq, ᶜsgs_moments.λ_lagrange, α,
            dt, mp1m.n_substeps_quad,
        )
    end
    return nothing
end

"""
    water_tag_gross_flow_change(F, ψN, ψR, ψS)

The change of one tag's three parts, per unit mass and time, when each of the
six flows `F` ([`WATER_TAG_FLOW_NAMES`](@ref)) carries its donor compartment's
composition: `ψN`, `ψR` and `ψS` are the tag's shares of the water that leaves
the non-precipitating water, rain and snow ([`water_tag_pool_shares`](@ref)).
Returns `(ΔN, ΔR, ΔS)`, which sum to zero.
"""
@inline water_tag_gross_flow_change(F, ψN, ψR, ψS) = (
    F.RN * ψR + F.SN * ψS - (F.NR + F.NS) * ψN,
    F.NR * ψN + F.SR * ψS - (F.RN + F.RS) * ψR,
    F.NS * ψN + F.RS * ψR - (F.SN + F.SR) * ψS,
)

"""
    water_tag_pool_shares(F, qN, qR, qS, Δt, φN, φR, φS)

A tag's shares of the water that leaves each compartment over the step `Δt`:
the compartment's water at the start, `qN`, `qR` or `qS` (per unit mass, with
the tag's shares `φN`, `φR`, `φS`), mixed with what the flows `F` bring into it
during the step, each with its own donor's share. So each share solves

    ψR (qR + Δt (F.NR + F.SR)) = qR φR + Δt (F.NR ψN + F.SR ψS),

and alike for `ψN` and `ψS`, a 3×3 linear system solved by Cramer's rule.
Returns `(ψN, ψR, ψS)`.

Why the pool and not the start alone: the model's linearized step lets water
pass through a compartment within the step, such as rain that forms and
evaporates again, or snow that forms and melts. At the start such a compartment
may hold none of it, or none at all, and then its outflow would carry no
composition, and the partition's parts would drift from their compartments.
Over the pool the partition's shares of each compartment sum to one wherever
the pool holds water, as the start's do. Where a compartment holds much more
than passes through it, `ψ` is its start share `φ`.

Where the system is singular, which needs every pool empty, it returns the
start shares.
"""
@inline function water_tag_pool_shares(F, qN, qR, qS, Δt, φN, φR, φS)
    a11 = qN + Δt * (F.RN + F.SN)
    a12 = -Δt * F.RN
    a13 = -Δt * F.SN
    a21 = -Δt * F.NR
    a22 = qR + Δt * (F.NR + F.SR)
    a23 = -Δt * F.SR
    a31 = -Δt * F.NS
    a32 = -Δt * F.RS
    a33 = qS + Δt * (F.NS + F.RS)
    b1 = qN * φN
    b2 = qR * φR
    b3 = qS * φS
    m1 = a22 * a33 - a23 * a32
    m2 = a21 * a33 - a23 * a31
    m3 = a21 * a32 - a22 * a31
    det = a11 * m1 - a12 * m2 + a13 * m3
    det > zero(det) || return (φN, φR, φS)
    ψN = (b1 * m1 - a12 * (b2 * a33 - a23 * b3) + a13 * (b2 * a32 - a22 * b3)) / det
    ψR =
        (a11 * (b2 * a33 - a23 * b3) - b1 * m2 + a13 * (a21 * b3 - b2 * a31)) /
        det
    ψS =
        (a11 * (a22 * b3 - b2 * a32) - a12 * (a21 * b3 - b2 * a31) + b1 * m3) /
        det
    return (ψN, ψR, ψS)
end

"""
    water_tag_net_flow_change(ΔN, ΔR, ΔS, φN, φR, φS)

The net-flow rule of the design note's section 9 for one tag. The parent's
compartments change by `ΔN`, `ΔR` and `ΔS`, which sum to zero. A compartment
that loses gives its own composition, and one that gains takes the losers'
compositions weighted by their losses. Returns the tag's `(ΔN, ΔR, ΔS)`, which
sum to zero.

The guards: a losing compartment the tags hold none of (a zero share) gives
the tag nothing, so its water stays untagged. Without any loss nothing moves. A
source tag's shares are not normalized, as elsewhere.
"""
@inline function water_tag_net_flow_change(ΔN, ΔR, ΔS, φN, φR, φS)
    lossN = max(-ΔN, zero(ΔN))
    lossR = max(-ΔR, zero(ΔR))
    lossS = max(-ΔS, zero(ΔS))
    loss = lossN + lossR + lossS
    mix =
        loss > zero(loss) ? (lossN * φN + lossR * φR + lossS * φS) / loss :
        zero(loss)
    return (
        min(ΔN, zero(ΔN)) * φN + max(ΔN, zero(ΔN)) * mix,
        min(ΔR, zero(ΔR)) * φR + max(ΔR, zero(ΔR)) * mix,
        min(ΔS, zero(ΔS)) * φS + max(ΔS, zero(ΔS)) * mix,
    )
end

"""
    water_tag_microphysics_change(F, dq_rai_dt, dq_sno_dt, qN, qR, qS, Δt, φN, φR, φS)

The change of one tag's parts by the microphysics, per unit mass and time: the
gross flows `F` over the step `Δt`, each with its donor's composition over the
step ([`water_tag_pool_shares`](@ref), [`water_tag_gross_flow_change`](@ref)),
plus the net-flow rule ([`water_tag_net_flow_change`](@ref)) on what the
flows' net misses of the model's own tendencies, `dq_rai_dt` and `dq_sno_dt`.
That remainder is rounding where the flows are available, so the gross flows
set the attribution. Where they are not, `F` is zero, and the net-flow rule is
the fallback. `qN`, `qR` and `qS` are the compartments' water per unit mass,
and `φN`, `φR`, `φS` the tag's shares of them. Returns `(ΔN, ΔR, ΔS)`.
"""
@inline function water_tag_microphysics_change(
    F,
    dq_rai_dt,
    dq_sno_dt,
    qN,
    qR,
    qS,
    Δt,
    φN,
    φR,
    φS,
)
    (ψN, ψR, ψS) = water_tag_pool_shares(F, qN, qR, qS, Δt, φN, φR, φS)
    (gN, gR, gS) = water_tag_gross_flow_change(F, ψN, ψR, ψS)
    δR = dq_rai_dt - ((F.NR + F.SR) - (F.RN + F.RS))
    δS = dq_sno_dt - ((F.NS + F.RS) - (F.SN + F.SR))
    (nN, nR, nS) = water_tag_net_flow_change(-(δR + δS), δR, δS, φN, φR, φS)
    return (gN + nN, gR + nR, gS + nS)
end

"""
    water_tag_microphysics_audit(F, dq_rai_dt, dq_sno_dt, qN, qR, qS, Δt, φN, φR, φS)

The audit of the design note's section 12, for one tag: the net-flow rule's
change of the tag's rain and snow parts, minus the change the model applies
([`water_tag_microphysics_change`](@ref)). Returns `(ΔR, ΔS)`. Both rules keep
each tag's total, so the non-precipitating part's difference is minus their
sum.
"""
@inline function water_tag_microphysics_audit(
    F,
    dq_rai_dt,
    dq_sno_dt,
    qN,
    qR,
    qS,
    Δt,
    φN,
    φR,
    φS,
)
    (_, aR, aS) = water_tag_net_flow_change(
        -(dq_rai_dt + dq_sno_dt),
        dq_rai_dt,
        dq_sno_dt,
        φN,
        φR,
        φS,
    )
    (_, cR, cS) = water_tag_microphysics_change(
        F,
        dq_rai_dt,
        dq_sno_dt,
        qN,
        qR,
        qS,
        Δt,
        φN,
        φR,
        φS,
    )
    return (aR - cR, aS - cS)
end

# One output of the two kernels above each, for a broadcast.
@inline _mp_change_n(args...) = water_tag_microphysics_change(args...)[1]
@inline _mp_change_r(args...) = water_tag_microphysics_change(args...)[2]
@inline _mp_change_s(args...) = water_tag_microphysics_change(args...)[3]
@inline _mp_audit_r(args...) = water_tag_microphysics_audit(args...)[1]
@inline _mp_audit_s(args...) = water_tag_microphysics_audit(args...)[2]

"""
    water_tag_precipitation_microphysics_tendency!(Yₜ, Y, p)

Move each tag's water between its three parts as the 1-moment microphysics
moves the parent's between its compartments: by the gross flows, each with its
donor's composition over the step ([`water_tag_microphysics_change`](@ref)). The flows are
frozen in `p.tagging.ᶜwater_mp_flows` with the model's own tendencies, and the
shares are taken from `Y`. It also adds the audit's difference to the state
records `q_rtag_aud_<name>` and `q_stag_aud_<name>`
([`water_tag_microphysics_audit`](@ref)).

Called beside `microphysics_tendency!`, on the implicit path or the explicit
one, whichever the model uses. The microphysics keeps `ρq_tot`, so the
bracket around it moves nothing. A no-op without the key.
"""
water_tag_precipitation_microphysics_tendency!(Yₜ, Y, p) =
    _water_tag_precipitation_microphysics_tendency!(
        Yₜ,
        Y,
        p,
        p.atmos.water_tagging_model,
    )
_water_tag_precipitation_microphysics_tendency!(Yₜ, Y, p, ::Nothing) = nothing
function _water_tag_precipitation_microphysics_tendency!(
    Yₜ,
    Y,
    p,
    model::WaterTaggingModel,
)
    has_water_tag_precipitation(model) || return nothing
    water_tag_share_norm!(p, Y)
    # The compartments' water per unit mass, not below zero, as the
    # microphysics takes it. The flows are averages over the model's step.
    ᶜqN = @. lazy(
        max(specific(Y.c.ρq_tot - Y.c.ρq_rai - Y.c.ρq_sno, Y.c.ρ), 0),
    )
    ᶜqR = @. lazy(max(specific(Y.c.ρq_rai, Y.c.ρ), 0))
    ᶜqS = @. lazy(max(specific(Y.c.ρq_sno, Y.c.ρ), 0))
    ᶜpools = (; N = ᶜqN, R = ᶜqR, S = ᶜqS)
    _microphysics_of_water_tag_parts!(
        Yₜ.c,
        Y.c,
        p.scratch,
        p.tagging.ᶜwater_mp_flows,
        p.precomputed.ᶜmp_tendency,
        ᶜpools,
        eltype(Y.c.ρ)(float(p.dt)),
        model.tags,
    )
    return nothing
end

_microphysics_of_water_tag_parts!(
    ᶜYₜ,
    ᶜY,
    scratch,
    ᶜF,
    ᶜmp,
    ᶜpools,
    Δt,
    ::Tuple{},
) = nothing
function _microphysics_of_water_tag_parts!(
    ᶜYₜ,
    ᶜY,
    scratch,
    ᶜF,
    ᶜmp,
    ᶜpools,
    Δt,
    tags::Tuple,
)
    tag = first(tags)
    ᶜφN = water_tag_part_share(ᶜY, scratch, tag, NonPrecipitatingPart())
    ᶜφR = water_tag_part_share(ᶜY, scratch, tag, RainPart())
    ᶜφS = water_tag_part_share(ᶜY, scratch, tag, SnowPart())
    ᶜdq_rai_dt = ᶜmp.dq_rai_dt
    ᶜdq_sno_dt = ᶜmp.dq_sno_dt
    (ᶜqN, ᶜqR, ᶜqS) = (ᶜpools.N, ᶜpools.R, ᶜpools.S)
    ᶜNₜ = tag_field(ᶜYₜ, tag)
    ᶜRₜ = rain_tag_field(ᶜYₜ, tag)
    ᶜSₜ = snow_tag_field(ᶜYₜ, tag)
    @. ᶜNₜ +=
        ᶜY.ρ * _mp_change_n(
            ᶜF, ᶜdq_rai_dt, ᶜdq_sno_dt, ᶜqN, ᶜqR, ᶜqS, Δt, ᶜφN, ᶜφR, ᶜφS,
        )
    @. ᶜRₜ +=
        ᶜY.ρ * _mp_change_r(
            ᶜF, ᶜdq_rai_dt, ᶜdq_sno_dt, ᶜqN, ᶜqR, ᶜqS, Δt, ᶜφN, ᶜφR, ᶜφS,
        )
    @. ᶜSₜ +=
        ᶜY.ρ * _mp_change_s(
            ᶜF, ᶜdq_rai_dt, ᶜdq_sno_dt, ᶜqN, ᶜqR, ᶜqS, Δt, ᶜφN, ᶜφR, ᶜφS,
        )
    ᶜrain_auditₜ = rain_audit_field(ᶜYₜ, tag)
    ᶜsnow_auditₜ = snow_audit_field(ᶜYₜ, tag)
    @. ᶜrain_auditₜ +=
        ᶜY.ρ * _mp_audit_r(
            ᶜF, ᶜdq_rai_dt, ᶜdq_sno_dt, ᶜqN, ᶜqR, ᶜqS, Δt, ᶜφN, ᶜφR, ᶜφS,
        )
    @. ᶜsnow_auditₜ +=
        ᶜY.ρ * _mp_audit_s(
            ᶜF, ᶜdq_rai_dt, ᶜdq_sno_dt, ᶜqN, ᶜqR, ᶜqS, Δt, ᶜφN, ᶜφR, ᶜφS,
        )
    return _microphysics_of_water_tag_parts!(
        ᶜYₜ,
        ᶜY,
        scratch,
        ᶜF,
        ᶜmp,
        ᶜpools,
        Δt,
        Base.tail(tags),
    )
end

# ============================================================================
# The vapour nonnegativity tendency
# ============================================================================

"""
    snapshot_water_tag_precipitation_tendency!(p, Yₜ)
    attribute_water_tag_precipitation_tendency!(Yₜ, Y, p)

A bracket around `tracer_nonnegativity_vapor_tendency!`, which lifts negative
condensate at the expense of vapour and keeps `ρq_tot`. The rain and snow it
adds or removes move between each tag's rain or snow part and its
non-precipitating part by the net-flow rule
([`water_tag_net_flow_change`](@ref)): what a compartment gains takes the
non-precipitating composition. A no-op without the key.
"""
snapshot_water_tag_precipitation_tendency!(p, Yₜ) =
    has_water_tag_precipitation(p.atmos.water_tagging_model) ?
    _snapshot_precipitation_tendency!(p.scratch, Yₜ) : nothing
function _snapshot_precipitation_tendency!(scratch, Yₜ)
    scratch.ᶜtagging_q_rai_snapshot .= Yₜ.c.ρq_rai
    scratch.ᶜtagging_q_sno_snapshot .= Yₜ.c.ρq_sno
    return nothing
end

function attribute_water_tag_precipitation_tendency!(Yₜ, Y, p)
    model = p.atmos.water_tagging_model
    has_water_tag_precipitation(model) || return nothing
    water_tag_share_norm!(p, Y)
    ᶜΔR = @. lazy(Yₜ.c.ρq_rai - p.scratch.ᶜtagging_q_rai_snapshot)
    ᶜΔS = @. lazy(Yₜ.c.ρq_sno - p.scratch.ᶜtagging_q_sno_snapshot)
    _net_flow_of_water_tag_parts!(Yₜ.c, Y.c, p.scratch, ᶜΔR, ᶜΔS, model.tags)
    return nothing
end

@inline _net_change_n(ΔR, ΔS, φN, φR, φS) =
    water_tag_net_flow_change(-(ΔR + ΔS), ΔR, ΔS, φN, φR, φS)[1]
@inline _net_change_r(ΔR, ΔS, φN, φR, φS) =
    water_tag_net_flow_change(-(ΔR + ΔS), ΔR, ΔS, φN, φR, φS)[2]
@inline _net_change_s(ΔR, ΔS, φN, φR, φS) =
    water_tag_net_flow_change(-(ΔR + ΔS), ΔR, ΔS, φN, φR, φS)[3]

_net_flow_of_water_tag_parts!(ᶜYₜ, ᶜY, scratch, ᶜΔR, ᶜΔS, ::Tuple{}) = nothing
function _net_flow_of_water_tag_parts!(ᶜYₜ, ᶜY, scratch, ᶜΔR, ᶜΔS, tags::Tuple)
    tag = first(tags)
    ᶜφN = water_tag_part_share(ᶜY, scratch, tag, NonPrecipitatingPart())
    ᶜφR = water_tag_part_share(ᶜY, scratch, tag, RainPart())
    ᶜφS = water_tag_part_share(ᶜY, scratch, tag, SnowPart())
    ᶜNₜ = tag_field(ᶜYₜ, tag)
    ᶜRₜ = rain_tag_field(ᶜYₜ, tag)
    ᶜSₜ = snow_tag_field(ᶜYₜ, tag)
    @. ᶜNₜ += _net_change_n(ᶜΔR, ᶜΔS, ᶜφN, ᶜφR, ᶜφS)
    @. ᶜRₜ += _net_change_r(ᶜΔR, ᶜΔS, ᶜφN, ᶜφR, ᶜφS)
    @. ᶜSₜ += _net_change_s(ᶜΔR, ᶜΔS, ᶜφN, ᶜφR, ᶜφS)
    return _net_flow_of_water_tag_parts!(
        ᶜYₜ,
        ᶜY,
        scratch,
        ᶜΔR,
        ᶜΔS,
        Base.tail(tags),
    )
end

# ============================================================================
# Limiters and constraints
# ============================================================================

"""
    snapshot_water_tag_precipitation!(Y, p)

Keep `ρq_rai` and `ρq_sno` before the limiters or the state constraints change
them, in fields the tags own (`p.tagging.ᶜwater_rai_before` and
`ᶜwater_sno_before`). [`rescale_water_tags!`](@ref) and
[`follow_water_tag_precipitation!`](@ref) move the changes since then. Called
first thing in `limiters_func!` and `constrain_state!`. A no-op without the
key.
"""
snapshot_water_tag_precipitation!(Y, p) =
    has_water_tag_precipitation(p.atmos.water_tagging_model) ?
    _snapshot_water_tag_precipitation!(Y, p.tagging) : nothing
function _snapshot_water_tag_precipitation!(Y, tagging)
    tagging.ᶜwater_rai_before .= Y.c.ρq_rai
    tagging.ᶜwater_sno_before .= Y.c.ρq_sno
    return nothing
end

"""
    follow_water_tag_precipitation!(Y, p)

Move the change of `ρq_rai` and `ρq_sno` since the last snapshot between each
tag's rain or snow part and its non-precipitating part, at fixed `ρq_tot`, as
[`rescale_water_tags!`](@ref) does. Some corrections change rain and snow
without a change of `ρq_tot`, and so without a call of `rescale_water_tags!`:
the clip and rescale of the condensates in
`enforce_grid_mean_microphysics_constraints!`, the vapour constraint, and a
limiter that leaves `ρq_tot` out. Called last in `limiters_func!`, and in
`constrain_state!` before the partition repair. A no-op without the key.
"""
follow_water_tag_precipitation!(Y, p) =
    has_water_tag_precipitation(p.atmos.water_tagging_model) ?
    _rescale_water_tag_parts!(
        Y,
        p,
        Y.c.ρq_tot,
        p.atmos.water_tagging_model,
        Val(false),
    ) : nothing

"""
    water_tag_part_follow_shift(ρq_part, ρq_nonprecip, after, before, pos_part, pos_nonprecip)

The water that a correction moves into the rain or snow part of a *partition*
tag, and out of its non-precipitating part, when it changes the compartment
from `before` to `after` at fixed `ρq_tot`. `pos_part` and `pos_nonprecip` are
the sums of the partition's non-negative parts of each kind in the cell. The
design note's section 8:

  - a compartment that decreases gives its own composition back to the
    non-precipitating parts, `Δ ρq_part⁺ / pos_part`, with `Δ` floored at
    `-pos_part`, so no part goes below zero;
  - a compartment that increases takes the non-precipitating composition,
    `Δ ρq_nonprecip⁺ / pos_nonprecip`, with `Δ` capped at `pos_nonprecip`;
  - where the compartment is clipped to zero, or is not positive, the part is
    emptied into the non-precipitating part.

What the floors leave out surfaces in the compartment's residual.
"""
@inline function water_tag_part_follow_shift(
    ρq_part,
    ρq_nonprecip,
    after,
    before,
    pos_part,
    pos_nonprecip,
)
    after > zero(after) || return -ρq_part
    Δ = after - before
    if Δ < zero(Δ)
        pos_part > zero(pos_part) || return zero(ρq_part)
        return max(Δ, -pos_part) * max(ρq_part, zero(ρq_part)) / pos_part
    else
        pos_nonprecip > zero(pos_nonprecip) || return zero(ρq_part)
        return min(Δ, pos_nonprecip) * max(ρq_nonprecip, zero(ρq_nonprecip)) /
               pos_nonprecip
    end
end

"""
    water_tag_source_part_follow_shift(ρq_part, ρq_nonprecip, after, before, nonprecip_before)

The same for a *source* tag, with its own clamped shares of each compartment,
unnormalized, as `water_tag_source_rescale_shift` takes them.
`nonprecip_before` is the non-precipitating compartment before the change.
"""
@inline function water_tag_source_part_follow_shift(
    ρq_part,
    ρq_nonprecip,
    after,
    before,
    nonprecip_before,
)
    after > zero(after) || return -ρq_part
    Δ = after - before
    Δ < zero(Δ) && return Δ * water_tag_fraction(ρq_part, before)
    return min(Δ, max(nonprecip_before, zero(nonprecip_before))) *
           water_tag_fraction(ρq_nonprecip, nonprecip_before)
end

# The corrections under the key. Rain, then snow: each compartment's change
# since the snapshot moves between the part and the non-precipitating part.
# Then, when the caller passes a change of `ρq_tot`, the non-precipitating
# parts take it by the rule the tags follow without the key, on their own
# compartment. Last, the snapshots move on, so a later call moves only what
# changed since.
function _rescale_water_tag_parts!(Y, p, ᶜρq_tot_before, model, ::Val{total}) where {total}
    (; ᶜwater_fix, ᶜwater_fix_gross, ᶜwater_fix_count) = p.tagging
    (; ᶜwater_pos, ᶜwater_pos_2, ᶜwater_shift) = p.tagging
    (; ᶜwater_rai_before, ᶜwater_sno_before) = p.tagging
    ledger = tag_ledger(ᶜwater_fix, ᶜwater_fix_gross, ᶜwater_fix_count)
    ᶜY = Y.c
    # The non-precipitating compartment before each step, for the source
    # tags' shares.
    ᶜnonprecip_before_rain =
        @. lazy(ᶜρq_tot_before - ᶜwater_rai_before - ᶜwater_sno_before)
    _follow_water_tag_part!(
        ᶜY,
        ledger,
        (ᶜwater_pos, ᶜwater_pos_2, ᶜwater_shift),
        ᶜwater_rai_before,
        ᶜnonprecip_before_rain,
        model.tags,
        RainPart(),
    )
    ᶜnonprecip_before_snow =
        @. lazy(ᶜρq_tot_before - ᶜY.ρq_rai - ᶜwater_sno_before)
    _follow_water_tag_part!(
        ᶜY,
        ledger,
        (ᶜwater_pos, ᶜwater_pos_2, ᶜwater_shift),
        ᶜwater_sno_before,
        ᶜnonprecip_before_snow,
        model.tags,
        SnowPart(),
    )
    if total
        ᶜwater_pos .= zero(eltype(ᶜwater_pos))
        _accumulate_partition_pos!(ᶜwater_pos, ᶜY, model.tags)
        _apply_water_tag_rescale!(
            ᶜY,
            ledger,
            ᶜwater_pos,
            (@. lazy(ᶜρq_tot_before - ᶜY.ρq_rai - ᶜY.ρq_sno)),
            model.tags,
            water_tag_part_parent(ᶜY, NonPrecipitatingPart()),
        )
    end
    ᶜwater_rai_before .= ᶜY.ρq_rai
    ᶜwater_sno_before .= ᶜY.ρq_sno
    return nothing
end

function _follow_water_tag_part!(
    ᶜY,
    ledger,
    (ᶜpos_part, ᶜpos_nonprecip, ᶜshift),
    ᶜbefore,
    ᶜnonprecip_before,
    tags,
    part,
)
    ᶜpos_part .= zero(eltype(ᶜpos_part))
    _accumulate_part_pos!(ᶜpos_part, ᶜY, tags, part)
    ᶜpos_nonprecip .= zero(eltype(ᶜpos_nonprecip))
    _accumulate_partition_pos!(ᶜpos_nonprecip, ᶜY, tags)
    _apply_part_follow!(
        ᶜY,
        ledger,
        ᶜpos_part,
        ᶜpos_nonprecip,
        ᶜshift,
        water_tag_part_parent(ᶜY, part),
        ᶜbefore,
        ᶜnonprecip_before,
        tags,
        part,
    )
    return nothing
end

_accumulate_part_pos!(ᶜpos, ᶜY, ::Tuple{}, part) = nothing
function _accumulate_part_pos!(ᶜpos, ᶜY, tags::Tuple, part)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
        @. ᶜpos += max(ᶜρq_part, 0)
    end
    return _accumulate_part_pos!(ᶜpos, ᶜY, Base.tail(tags), part)
end

_accumulate_part_neg!(ᶜneg, ᶜY, ::Tuple{}, part) = nothing
function _accumulate_part_neg!(ᶜneg, ᶜY, tags::Tuple, part)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
        @. ᶜneg += min(ᶜρq_part, 0)
    end
    return _accumulate_part_neg!(ᶜneg, ᶜY, Base.tail(tags), part)
end

# Each tag's shift is computed once into `ᶜshift` and then applied, because it
# reads both parts it changes. The sums come from before the step and are only
# read, so each tag's shift sees its own fields before the step.
_apply_part_follow!(
    ᶜY,
    ledger,
    ᶜpos_part,
    ᶜpos_nonprecip,
    ᶜshift,
    ᶜafter,
    ᶜbefore,
    ᶜnonprecip_before,
    ::Tuple{},
    part,
) = nothing
function _apply_part_follow!(
    ᶜY,
    ledger,
    ᶜpos_part,
    ᶜpos_nonprecip,
    ᶜshift,
    ᶜafter,
    ᶜbefore,
    ᶜnonprecip_before,
    tags::Tuple,
    part,
)
    tag = first(tags)
    ᶜρq_part = water_tag_part_field(ᶜY, tag, part)
    ᶜρq_nonprecip = tag_field(ᶜY, tag)
    (_, ᶜgross, ᶜcount) = tag_ledger_fields(ledger, tag)
    if _is_partition_tag(tag)
        @. ᶜshift = water_tag_part_follow_shift(
            ᶜρq_part,
            ᶜρq_nonprecip,
            ᶜafter,
            ᶜbefore,
            ᶜpos_part,
            ᶜpos_nonprecip,
        )
    else
        @. ᶜshift = water_tag_source_part_follow_shift(
            ᶜρq_part,
            ᶜρq_nonprecip,
            ᶜafter,
            ᶜbefore,
            ᶜnonprecip_before,
        )
    end
    # The shift moves water within the tag, so the tag's signed ledger does
    # not change. The gross twin counts it out of one part and into the
    # other, as a transfer between tags counts.
    @. ᶜgross += 2 * abs(ᶜshift)
    @. ᶜcount += tag_event(ᶜshift, ᶜY.ρq_tot)
    @. ᶜρq_part += ᶜshift
    @. ᶜρq_nonprecip -= ᶜshift
    return _apply_part_follow!(
        ᶜY,
        ledger,
        ᶜpos_part,
        ᶜpos_nonprecip,
        ᶜshift,
        ᶜafter,
        ᶜbefore,
        ᶜnonprecip_before,
        Base.tail(tags),
        part,
    )
end

# The partition repair of the rain and snow parts, each among themselves, as
# `repair_water_tag_partition!` repairs the non-precipitating parts.
function _repair_water_tag_precip_parts!(Y, p, ledger, model)
    has_water_tag_precipitation(model) || return nothing
    (; ᶜwater_pos, ᶜwater_neg) = p.tagging
    for part in (RainPart(), SnowPart())
        ᶜwater_pos .= zero(eltype(ᶜwater_pos))
        ᶜwater_neg .= zero(eltype(ᶜwater_neg))
        _accumulate_part_pos!(ᶜwater_pos, Y.c, model.tags, part)
        _accumulate_part_neg!(ᶜwater_neg, Y.c, model.tags, part)
        _apply_partition_repair!(
            Y.c,
            ledger,
            ᶜwater_pos,
            ᶜwater_neg,
            model.tags,
            part,
        )
        @. Y.c.q_tag_led_repair -= max(-(ᶜwater_pos + ᶜwater_neg), 0) / 2
        @. Y.c.q_tag_led_repairnet += max(-(ᶜwater_pos + ᶜwater_neg), 0)
    end
    return nothing
end

# ============================================================================
# Advection under the increment follower
# ============================================================================

"""
    water_tag_moves_precip_advection(p, name)

Whether `name` is a rain or snow part whose explicit vertical advection the
tag's non-precipitating part gives back, under `water_tag_precipitation: true`
and `water_tag_transport: increment`. The non-precipitating parts follow the
parent's implicit increment of its non-precipitating water, and `ρq_tot` is
advected implicitly with its rain and snow. So each takes minus its own rain's
and snow's explicit advection (the design note, section 6).
"""
water_tag_moves_precip_advection(p, name) =
    has_water_tag_precipitation(p.atmos.water_tagging_model) &&
    follows_water_increment(p.atmos.water_tagging_model) &&
    _is_water_precip_part_field(name)

# The non-precipitating part of the tag whose rain or snow part is `name`.
@generated function _nonprecip_part_name(
    ::MatrixFields.FieldName{chain},
) where {chain}
    name = string(first(chain))
    suffix = name[(ncodeunits("ρq_rtag_") + 1):end]
    return :(MatrixFields.FieldName($(QuoteNode(Symbol(:ρq_tag_, suffix)))))
end

"""
    water_tag_precip_advection!(Yₜ, p, name, vtt)

Take the explicit vertical advection `vtt` of the rain or snow part `name` out
of the tag's non-precipitating part, where
[`water_tag_moves_precip_advection`](@ref) says so. Called from the tracer
loop of the explicit vertical advection, after the part took `vtt`.
"""
function water_tag_precip_advection!(Yₜ, p, name, vtt)
    water_tag_moves_precip_advection(p, name) || return nothing
    ᶜρq_nonprecipₜ = MatrixFields.get_field(Yₜ.c, _nonprecip_part_name(name))
    @. ᶜρq_nonprecipₜ -= vtt
    return nothing
end

# ============================================================================
# Hyperdiffusion
# ============================================================================

# The Laplacian's field of a tag's non-precipitating part, keyed by its
# specific name, as `allocate_ᶜspecific_gs_tracers` keys them.
@generated _laplacian_tag_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:q_tag_, name)))

"""
    prep_water_tag_hyperdiffusion!(ᶜ∇²specific_tracers, Y, p)

Under `water_tag_precipitation: true`, set the Laplacian that each tag's
non-precipitating part is hyperdiffused on to `∇²(N/ρ - φ q_tot_r)`, with `φ`
the tag's share of its compartment ([`water_tag_part_share`](@ref)) and
`q_tot_r` the reference profile the parent's water is hyperdiffused against.
The parent hyperdiffuses `q_tot_eff - q_tot_r`, and the partition's shares sum
to one, so the partition's non-precipitating parts then move as the parent's
diffusing water (the design note, section 3). Called after the tracer
Laplacians are computed, before their DSS. A no-op without the key.
"""
function prep_water_tag_hyperdiffusion!(ᶜ∇²specific_tracers, Y, p)
    model = p.atmos.water_tagging_model
    has_water_tag_precipitation(model) || return nothing
    water_tag_share_norm!(p, Y)
    thermo_params = CAP.thermodynamics_params(p.params)
    (; ᶜp) = p.precomputed
    MatrixFields.unrolled_foreach(model.tags) do tag
        ᶜ∇²χ = _laplacian_tag_field(ᶜ∇²specific_tracers, tag)
        ᶜρq_tag = tag_field(Y.c, tag)
        ᶜshare = water_tag_part_share(
            Y.c,
            p.scratch,
            tag,
            NonPrecipitatingPart(),
        )
        @. ᶜ∇²χ = wdivₕ(
            gradₕ(
                specific(ᶜρq_tag, Y.c.ρ) - ᶜshare * q_tot_r(thermo_params, ᶜp),
            ),
        )
    end
    return nothing
end

# ============================================================================
# Surface precipitation of each tag
# ============================================================================

"""
    water_tag_precipitation_flux!(sfc_flux, Y, p, tag)

Write into `sfc_flux` the tag's share of the model's surface precipitation
`surface_rain_flux + surface_snow_flux`: the flux of its rain and snow parts
and of its share of the cloud liquid and ice, at the bottom face. It is built
as `set_precipitation_surface_fluxes!` builds the model's, from the level-1
values, the terminal velocities and the extrapolated surface density, so the
partition's fluxes sum to the model's wherever its rain and snow parts sum to
`ρq_rai` and `ρq_sno` at level 1 (the design note, section 10). Upward
positive, as the model's. Uses `p.scratch.ᶜtemp_scalar` and the tags' share
denominators.
"""
function water_tag_precipitation_flux!(sfc_flux, Y, p, tag)
    (; ᶜwᵣ, ᶜwₛ, ᶜwₗ, ᶜwᵢ) = p.precomputed
    water_tag_share_norm!(p, Y)
    ᶜJ = Fields.local_geometry_field(Y.c).J
    ᶠJ = Fields.local_geometry_field(Y.f).J
    sfc_J = Fields.level(ᶠJ, Fields.half)
    sfc_space = axes(sfc_J)
    sfc_lev(x) = Fields.Field(Fields.field_values(Fields.level(x, 1)), sfc_space)
    ᶜφN = water_tag_part_share(Y.c, p.scratch, tag, NonPrecipitatingPart())
    ᶜflux = p.scratch.ᶜtemp_scalar
    @. ᶜflux =
        specific(rain_tag_field(Y.c, tag), Y.c.ρ) * (-(ᶜwᵣ)) +
        specific(snow_tag_field(Y.c, tag), Y.c.ρ) * (-(ᶜwₛ)) +
        ᶜφN * (
            specific(Y.c.ρq_lcl, Y.c.ρ) * (-(ᶜwₗ)) +
            specific(Y.c.ρq_icl, Y.c.ρ) * (-(ᶜwᵢ))
        )
    int_J = sfc_lev(ᶜJ)
    int_ρ = sfc_lev(Y.c.ρ)
    @. sfc_flux = int_ρ * int_J / sfc_J * $(sfc_lev(ᶜflux))
    return sfc_flux
end

# ============================================================================
# Configuration
# ============================================================================

"""
    water_tag_precipitation_from_config(value)

Parse `water_tag_precipitation`. `false`, the default, and `~` keep one field
per water tag; `true` splits each tag into its non-precipitating, rain and snow
parts. Anything else is an error, so that a quoted `"true"` cannot read as
off.
"""
function water_tag_precipitation_from_config(value)
    isnothing(value) && return false
    value isa Bool || error(
        "`water_tag_precipitation` must be `true` or `false`, got \
        $(repr(value)).",
    )
    return value
end

"""
    check_water_tag_precipitation_supported(microphysics_model, turbconv)

Refuse `water_tag_precipitation: true` where its parts are not built yet: with
microphysics other than 1-moment, whose rain and snow are the prognostic
`ρq_rai` and `ρq_sno` the parts partition, and under EDMF, which is stage 2 of
the design note. Updraft copies are refused where the model is built.
"""
function check_water_tag_precipitation_supported(microphysics_model, turbconv)
    microphysics_model isa NonEquilibriumMicrophysics1M || error(
        "`water_tag_precipitation: true` needs `microphysics_model: 1M`, got \
        $(nameof(typeof(microphysics_model))). Its rain and snow parts \
        partition the prognostic `ρq_rai` and `ρq_sno` of the 1-moment \
        scheme.",
    )
    turbconv in ("prognostic_edmfx", "edonly_edmfx") && error(
        "`water_tag_precipitation: true` is refused with `turbconv: \
        $turbconv`. The rain and snow parts are built for a column or grid \
        without EDMF so far. Under EDMF the updraft's rain, the sub-grid \
        fluxes and the diffusive fluxes need their own rules, which are not \
        built yet. Drop one of the two keys.",
    )
    return nothing
end
