#####
##### The 0M rain-out split by EDMF subdomain (WP4a)
#####
##### Under 0M the only sink of total water is the rain-out, which prognostic
##### EDMF computes per subdomain: `Δʲ = ρaʲ dq_tot_dtʲ` in the updraft and
##### `Δ⁰ = ρa⁰ dq_tot_dt⁰` in the environment (`microphysics/tendency.jl`). The
##### `:microphysics` bracket sees only their sum. Here each subdomain's part
##### goes to the tags by that subdomain's composition, `Σₖ Δᵏ φᵏᵢ`, for both
##### signs, instead of by the grid mean's. The design, its review and the
##### reasons for each guard are in design/ZERO_M_SPLIT.md on the record branch.

"""
    splits_rainout(p, source)

Whether the bracket's increment for `source` is split by subdomain: the
`:microphysics` label under 0M microphysics and prognostic EDMF, in copies mode
or in the default mode with the SGS mass flux on. Elsewhere, and in the default
mode without the SGS mass flux, the grid mean's share applies as before.
"""
splits_rainout(p, source) =
    source === :microphysics &&
    _splits_rainout(
        p.atmos.microphysics_model,
        p.atmos.turbconv_model,
        p.atmos.water_tagging_model,
        p.atmos,
    )
_splits_rainout(microphysics_model, turbconv_model, model, atmos) = false
_splits_rainout(
    ::EquilibriumMicrophysics0M,
    ::PrognosticEDMFX,
    model::WaterTaggingModel,
    atmos,
) = has_water_tag_updraft_copies(model) || atmos.edmfx_model.sgs_mass_flux

# The rain-out of each subdomain, as the model adds it to `ρq_tot`
# (`microphysics_tendency!` for 0M and PrognosticEDMFX): one updraft.
_rainout_updraft(Y, p) = @. lazy(
    Y.c.sgsʲs.:(1).ρa * p.precomputed.ᶜmp_tendencyʲs.:(1).dq_tot_dt,
)
_rainout_environment(Y, p) = @. lazy(
    p.precomputed.ᶜmp_tendency⁰.dq_tot_dt *
    ρa⁰(Y.c.ρ, Y.c.sgsʲs, p.atmos.turbconv_model),
)

"""
    SplitShare{partition, i}()

Tag `i`'s share of one subdomain's rain-out in the default mode, as a callable
type, so that the partition's flags and the index are constants of the kernel.
It is the tag's partition-normalized share in the grid mean plus the
subdomain's difference from `ShareDifferences`, times `S`, the partition's sum
of clamped grid shares, so that a drifted partition keeps losing in proportion
to what it holds, as before. A source tag's is clamped to [0, 1], since its
environment difference is not bounded by the exchange. Where the partition
holds nothing, or a value is not finite, it is `fallback`, the grid mean's
share.
"""
struct SplitShare{partition, i} end
SplitShare(::Val{partition}, ::Val{i}) where {partition, i} =
    SplitShare{partition, i}()
@inline function (::SplitShare{partition, i})(
    ε̄,
    Δφ,
    S,
    fallback,
) where {partition, i}
    total = _partition_total(ε̄, partition)
    total > zero(total) || return fallback
    φ = S * (_subdomain_share(ε̄, total, i) + Δφ[i])
    isfinite(φ) || return fallback
    return partition[i] ? φ : clamp(φ, zero(φ), one(φ))
end

"""
    add_split_rainout!(ᶜdest, Y, p, model)

Add to `ᶜdest.ρq_tag_<name>`, for every water tag, its part of the 0M rain-out
split by subdomain: `Δʲ φʲᵢ + Δ⁰ φ⁰ᵢ`. `ᶜdest` is `Yₜ.c` in the bracket, or a
field of zeros per tag for `pr_tag`. Call only where [`splits_rainout`](@ref)
holds.

  - **Default mode.** The shares come from the exchange's plume and bound,
    computed here into the exchange's scratch, which the exchange later
    recomputes and overwrites: `SplitShare`. Where the exchange does not run
    (no updraft, no room, a non-rising cell), the differences are zero and the
    shares are the grid mean's.
  - **Copies.** The updraft's share is the copy's clamped share of `q_totʲ`,
    the one the copies' own rain-out takes (`_copies_rain_out!`), so one rule
    serves the copies and the grid tags. The environment's is the model's
    regularized environment value of the copy over `q_tot⁰`, renormalized
    over the partition and times `S`, as the copies' sedimentation mirror
    renormalizes; a source tag takes its own clamped share. Where the
    environment's partition holds nothing, the grid mean's share.

The partition's increment sums to `S·(Δʲ + Δ⁰)` in the default mode, and in
copies mode to `Δʲ·Σᵢ φʲᵢ + S·Δ⁰`, which is the same where the copies' partition
holds the updraft's water.
"""
function add_split_rainout!(ᶜdest, Y, p, model)
    water_tag_share_norm!(p, Y)
    ᶜS = p.scratch.ᶜtagging_q_share_norm
    ᶜΔʲ = _rainout_updraft(Y, p)
    ᶜΔ⁰ = _rainout_environment(Y, p)
    if has_water_tag_updraft_copies(model)
        _add_split_rainout_copies!(ᶜdest, Y, p, ᶜΔʲ, ᶜΔ⁰, ᶜS, model)
    else
        turbconv_model = p.atmos.turbconv_model
        inputs = water_exchange_inputs!(Y, p, turbconv_model, model)
        (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags) = inputs
        # As in `sgs_exchange_of_water_tags!`: the environment's differences
        # first, since the updraft's overwrite the plume in place.
        environment_differences = ShareDifferences(flags, true)
        updraft_differences = ShareDifferences(flags, false)
        ᶜΔφ⁰ = p.scratch.ᶜq_tag_environment
        @. ᶜΔφ⁰ = environment_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
        ᶜΔφʲ = ᶜεʲ
        @. ᶜΔφʲ = updraft_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
        _add_split_rainout_default!(
            ᶜdest,
            Y.c,
            ᶜΔʲ,
            ᶜΔ⁰,
            ᶜΔφʲ,
            ᶜΔφ⁰,
            ᶜε̄,
            ᶜS,
            flags,
            model.tags,
            Val(1),
        )
    end
    return nothing
end

_add_split_rainout_default!(
    ᶜdest,
    ᶜY,
    ᶜΔʲ,
    ᶜΔ⁰,
    ᶜΔφʲ,
    ᶜΔφ⁰,
    ᶜε̄,
    ᶜS,
    flags,
    ::Tuple{},
    ::Val,
) =
    nothing
function _add_split_rainout_default!(
    ᶜdest,
    ᶜY,
    ᶜΔʲ,
    ᶜΔ⁰,
    ᶜΔφʲ,
    ᶜΔφ⁰,
    ᶜε̄,
    ᶜS,
    flags,
    tags::Tuple,
    ::Val{i},
) where {i}
    tag = first(tags)
    ᶜρq_tagₜ = tag_field(ᶜdest, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    share = SplitShare(flags, Val(i))
    @. ᶜρq_tagₜ +=
        ᶜΔʲ * share(ᶜε̄, ᶜΔφʲ, ᶜS, water_tag_fraction(ᶜρq_tag, ᶜY.ρq_tot)) +
        ᶜΔ⁰ * share(ᶜε̄, ᶜΔφ⁰, ᶜS, water_tag_fraction(ᶜρq_tag, ᶜY.ρq_tot))
    return _add_split_rainout_default!(
        ᶜdest,
        ᶜY,
        ᶜΔʲ,
        ᶜΔ⁰,
        ᶜΔφʲ,
        ᶜΔφ⁰,
        ᶜε̄,
        ᶜS,
        flags,
        Base.tail(tags),
        Val(i + 1),
    )
end

function _add_split_rainout_copies!(ᶜdest, Y, p, ᶜΔʲ, ᶜΔ⁰, ᶜS, model)
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    (ᶜnormʲ, ᶜnorm⁰) =
        (p.scratch.ᶜq_tag_copy_normʲ, p.scratch.ᶜq_tag_copy_norm⁰)
    @. ᶜnormʲ = 0
    @. ᶜnorm⁰ = 0
    _accumulate_copy_norms!(ᶜnormʲ, ᶜnorm⁰, ᶜsgsʲ, Y, p, model.tags)
    ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
    _add_split_rainout_copies_each!(
        ᶜdest,
        Y,
        p,
        ᶜsgsʲ,
        (; ᶜΔʲ, ᶜΔ⁰, ᶜS, ᶜnorm⁰, ᶜq_tot⁰),
        model.tags,
    )
    return nothing
end
_add_split_rainout_copies_each!(ᶜdest, Y, p, ᶜsgsʲ, args, ::Tuple{}) = nothing
function _add_split_rainout_copies_each!(ᶜdest, Y, p, ᶜsgsʲ, args, tags::Tuple)
    tag = first(tags)
    (; ᶜΔʲ, ᶜΔ⁰, ᶜS, ᶜnorm⁰, ᶜq_tot⁰) = args
    ᶜρq_tagₜ = tag_field(ᶜdest, tag)
    ᶜρq_tag = tag_field(Y.c, tag)
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜχ⁰ = ᶜspecific_env_value(water_tag_copy_field_name(tag), Y, p)
    ᶜφ̄ = @. lazy(water_tag_fraction(ᶜρq_tag, Y.c.ρq_tot))
    ᶜφʲ = @. lazy(water_tag_fraction(ᶜχʲ, ᶜsgsʲ.q_tot))
    ᶜφ⁰ =
        _is_partition_tag(tag) ?
        (@. lazy(
            ifelse(
                ᶜnorm⁰ > 0,
                ᶜS * water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰) / ᶜnorm⁰,
                ᶜφ̄,
            ),
        )) : (@. lazy(water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰)))
    @. ᶜρq_tagₜ += ᶜΔʲ * ᶜφʲ + ᶜΔ⁰ * ᶜφ⁰
    return _add_split_rainout_copies_each!(
        ᶜdest,
        Y,
        p,
        ᶜsgsʲ,
        args,
        Base.tail(tags),
    )
end

"""
    add_rainout_increments!(ᶜdest, Y, p, model)

Add to `ᶜdest.ρq_tag_<name>` each tag's part of the 0M rain-out, by the rule
the `:microphysics` bracket applies: split by subdomain where
[`splits_rainout`](@ref) holds, and otherwise the grid rule on the cached sink
`ᶜρ_dq_tot_dt`, production by mask and loss by share. Reads only the state and
the cache, so the diagnostics can call it at output time.
"""
add_rainout_increments!(ᶜdest, Y, p, model) =
    splits_rainout(p, :microphysics) ?
    add_split_rainout!(ᶜdest, Y, p, model) :
    _accumulate_water_tags!(
        ᶜdest,
        Y.c,
        p.tagging.ᶜwater_masks,
        p.precomputed.ᶜρ_dq_tot_dt,
        :microphysics,
        model.tags,
    )

"""
    water_tag_precipitation!(out, Y, p, tag, phase)

The column integral of `tag`'s part of the 0M rain-out into `out`, a level
field, as `pr` integrates `ᶜρ_dq_tot_dt` (`set_precipitation_surface_fluxes!`):
upward-positive, so negative, and split into rain and snow by the grid mean's
temperature for `phase` `Val(:rain)` and `Val(:snow)`; `Val(:all)` is both. Over
a closed partition the tags' sum is `pr`. It reads the state at output time, so
it is the rate at the step's end, not the one applied during it. It allocates
one field per tag.
"""
function water_tag_precipitation!(out, Y, p, tag, phase)
    model = p.atmos.water_tagging_model
    ᶜincrements = _water_fix_fields(Y.c.ρ, model.tags)
    add_rainout_increments!(ᶜincrements, Y, p, model)
    ᶜincrement = tag_field(ᶜincrements, tag)
    T_freeze = TD.Parameters.T_freeze(CAP.thermodynamics_params(p.params))
    Operators.column_integral_definite!(
        out,
        _precipitation_phase(ᶜincrement, p.precomputed.ᶜT, T_freeze, phase),
    )
    return out
end
_precipitation_phase(ᶜx, ᶜT, T_freeze, ::Val{:all}) = ᶜx
_precipitation_phase(ᶜx, ᶜT, T_freeze, ::Val{:rain}) =
    @. lazy(ifelse(ᶜT >= T_freeze, ᶜx, zero(ᶜx)))
_precipitation_phase(ᶜx, ᶜT, T_freeze, ::Val{:snow}) =
    @. lazy(ifelse(ᶜT < T_freeze, ᶜx, zero(ᶜx)))
