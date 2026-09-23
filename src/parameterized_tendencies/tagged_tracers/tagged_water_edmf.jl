#####
##### The tagged water tracers under prognostic EDMF
#####
##### Under `turbconv: prognostic_edmfx` the updraft moves water: the SGS mass
##### flux carries `ρq_tot` with the updraft's own water, the updraft rains out
##### and sediments, and it relaxes toward a moister value at the surface. The
##### tags follow it in one of two modes, set by `water_tag_updraft_copy`:
#####
#####   - the default, `false`: the tags stay grid-scale. Each takes its share of
#####     the parent's SGS flux of `ρq_tot` from the cell the flux leaves, and an
#####     exchange at the updraft's mass flux, which sums to zero over the
#####     partition, adds the mixing of provenance an updraft copy would carry.
#####     The updraft's shares come from a steady entraining plume, rescaled at
#####     each level to the updraft's water.
#####   - the audit, `true`: each tag has a copy `q_tag_<name>` in the updraft,
#####     which the model's updraft machinery moves as any updraft tracer. What
#####     that machinery does not do for a tracer, the water does, and is
#####     mirrored here.
#####
##### The energy source tags follow the updraft the same way
##### (`energy_source_tags.jl`, PR #95), and the helpers there that do not
##### depend on the weight are used as they are: the plume's level, the bound
##### and the share differences. The water weight is `q_totᵏ` where the energy
##### tags use `Aᵏ = e_totᵏ + c`. The design is `experiments/tag_closure/G3_PLAN.md`,
##### section 4.1, on the fork's record branch.

# ============================================================================
# Configuration checks that need the built cache
# ============================================================================

"""
    check_water_tag_exchange_partition(cache, atmos)

Refuse the water tags' exchange at the updraft's mass flux without region tags
that partition the domain. The exchange runs under `PrognosticEDMFX` with the
SGS mass flux on and without updraft copies. A tag's share there is its value
over the sum of the region tags without sources. Without such tags that sum is
zero, and the exchange would silently do nothing. Where their masks leave a gap,
the sum is too small, and a tag could take the updraft's whole water flux. A
no-op in every other case, and without water tags. The energy tags' version is
[`check_energy_source_exchange_partition`](@ref).
"""
check_water_tag_exchange_partition(cache, atmos) =
    _check_water_tag_exchange_partition(
        cache,
        atmos.water_tagging_model,
        atmos.turbconv_model,
        atmos,
    )
_check_water_tag_exchange_partition(cache, model, turbconv_model, atmos) =
    nothing
function _check_water_tag_exchange_partition(
    cache,
    model::WaterTaggingModel,
    ::PrognosticEDMFX,
    atmos,
)
    atmos.edmfx_model.sgs_mass_flux || return nothing
    has_water_tag_updraft_copies(model) && return nothing
    names = water_region_tag_state_names(model)
    advice = "Add a region and its complement, for example with `above: false` \
             or `inside: false`, or set `water_tag_updraft_copy: true`, whose \
             copies need no partition."
    isempty(names) && error(
        "The water tags exchange provenance at the updraft's mass flux under \
        `turbconv: prognostic_edmfx`, and a tag's share there is its value \
        over the sum of the region tags without sources. These tags have \
        none, so the exchange would do nothing. $advice",
    )
    mask_sum = reduce(
        (a, b) -> a .+ b,
        map(name -> parent(getproperty(cache.ᶜwater_masks, name)), names),
    )
    deviation = maximum(abs.(mask_sum .- 1))
    deviation > 0.01 && error(
        "The water tags exchange provenance at the updraft's mass flux under \
        `turbconv: prognostic_edmfx`, and a tag's share there is its value \
        over the sum of the region tags without sources. Their masks sum to 1 \
        only to within $deviation. Where they leave a gap, that sum is too \
        small, and a tag could take the updraft's whole water flux. $advice",
    )
    return nothing
end

# ============================================================================
# Scratch
# ============================================================================

"""
    water_tag_edmf_scratch(Y, model, atmos)

Scratch fields of the water tags' default mode under prognostic EDMF, merged
into `p.scratch`: the face flux of `ρq_tot` the tags share, three tuples of tag
values per cell (the grid mean's, the updraft's from the plume, and the
environment's share differences), and three scalars (the environment's density,
and the room and the water ratio of the exchange's bound). Nothing without it:
no prognostic EDMF, no SGS mass flux, or updraft copies, whose own tracer flux
moves the tags instead. They live in `p.scratch` because the implicit tendency
may be evaluated with `ForwardDiff.Dual` numbers, and `p.scratch` is converted
for that.
"""
water_tag_edmf_scratch(Y, model, atmos) =
    _water_tag_edmf_scratch(Y, model, atmos.turbconv_model, atmos)
_water_tag_edmf_scratch(Y, model, turbconv_model, atmos) = (;)
function _water_tag_edmf_scratch(Y, model, ::PrognosticEDMFX, atmos)
    (
        atmos.edmfx_model.sgs_mass_flux &&
        !has_water_tag_updraft_copies(model)
    ) || return (;)
    FT = eltype(Y.c.ρ)
    tag_values() = Fields.Field(NTuple{length(model.tags), FT}, axes(Y.c))
    return (;
        ᶠq_tag_sgs_flux = Fields.Field(CT3{FT}, axes(Y.f)),
        ᶜq_tag_mean = tag_values(),
        ᶜq_tag_plume = tag_values(),
        ᶜq_tag_environment = tag_values(),
        ᶜq_tag_environment_density = similar(Y.c.ρ),
        ᶜq_tag_room = similar(Y.c.ρ),
        ᶜq_tag_water_ratio = similar(Y.c.ρ),
    )
end

# ============================================================================
# The default mode: the donor share and the exchange
# ============================================================================

"""
    sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model)

Under `PrognosticEDMFX` with its SGS mass flux on, move the water tags by their
shares of the parent's own SGS mass flux of `ρq_tot`, and exchange provenance
between them at the updraft's mass flux.

For each subdomain `k`, the updraft and the environment, the parent moves
`ρq_tot` with the difference-form flux `ρᵏ aᵏ (u³ᵏ - u³)(q_totᵏ - q_tot)`
(`edmfx_sgs_mass_flux_tendency!`). The flux is rebuilt here face by face, each
subdomain's part with the parent's own reconstruction, and summed. Each tag
takes that face flux times its share in the cell the flux leaves: the cell below
where it points up, the cell above where it points down. The partition's shares
add up to one, so its fluxes add up to the parent's at every face, and closure
holds. Then [`sgs_exchange_of_water_tags!`](@ref) adds the mixing of
provenance.

It runs in the implicit tendency, right after the parent's flux, with no
Jacobian block, as the energy source tags' flux has none. A tag that lags the
parent's Newton solve is followed by WP5's increment follower where that
matters (G3_PLAN 4.3). Under `water_tag_updraft_copy: true` it does nothing:
the model's SGS tracer flux moves the copies' grid-mean tags. A no-op without
water tags, without `PrognosticEDMFX`, and with the SGS mass flux off.
"""
sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model) = nothing
sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model::PrognosticEDMFX) =
    p.atmos.edmfx_model.sgs_mass_flux ?
    _sgs_mass_flux_of_water_tags!(
        Yₜ,
        Y,
        p,
        turbconv_model,
        p.atmos.water_tagging_model,
    ) : nothing
_sgs_mass_flux_of_water_tags!(Yₜ, Y, p, turbconv_model, ::Nothing) = nothing
function _sgs_mass_flux_of_water_tags!(
    Yₜ,
    Y,
    p,
    turbconv_model,
    model::WaterTaggingModel,
)
    # The copies' own SGS tracer flux moves the tags.
    has_water_tag_updraft_copies(model) && return nothing
    water_tag_share_norm!(p, Y)
    n = n_mass_flux_subdomains(turbconv_model)
    (; edmfx_sgsflux_upwinding) = p.atmos.numerics
    (; ᶠu³, ᶠu³ʲs, ᶜρʲs) = p.precomputed
    (; ᶜp, ᶠu³⁰, ᶜT⁰, ᶜq_tot_nonneg⁰, ᶜq_liq⁰, ᶜq_ice⁰) = p.precomputed
    (; dt) = p
    thermo_params = CAP.thermodynamics_params(p.params)
    ᶜρ⁰ = @. lazy(
        TD.air_density(
            thermo_params,
            ᶜT⁰,
            ᶜp,
            ᶜq_tot_nonneg⁰,
            ᶜq_liq⁰,
            ᶜq_ice⁰,
        ),
    )
    ᶜρa⁰ = @. lazy(ρa⁰(Y.c.ρ, Y.c.sgsʲs, turbconv_model))
    ᶜJ = Fields.local_geometry_field(Y.c).J
    ᶠJ = Fields.local_geometry_field(Y.f).J
    ᶜq_tot = @. lazy(specific(Y.c.ρq_tot, Y.c.ρ))

    # The environment's part first, so that it sets `ᶠflux` and the updrafts
    # add to it, as the parent's code adds them in the other order; the sum is
    # the same. Zeroing a vector field would need a `Ref`, which allocates.
    ᶠflux = p.scratch.ᶠq_tag_sgs_flux
    ᶠu³_diff⁰ = @. lazy(ᶠu³⁰ - ᶠu³)
    ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
    ᶜwater⁰ = @. lazy((ᶜq_tot⁰ - ᶜq_tot) * draft_area(ᶜρa⁰, ᶜρ⁰))
    ᶠρ⁰ = @. lazy(ᶠinterp(ᶜρ⁰ * ᶜJ) / ᶠJ)
    ᶠwater_flux⁰ =
        _face_value_flux(ᶠu³_diff⁰, ᶜwater⁰, dt, edmfx_sgsflux_upwinding)
    @. ᶠflux = ᶠρ⁰ * ᶠwater_flux⁰
    for j in 1:n
        ᶠu³_diffʲ = @. lazy(ᶠu³ʲs.:($$j) - ᶠu³)
        ᶜwaterʲ = @. lazy(
            (Y.c.sgsʲs.:($$j).q_tot - ᶜq_tot) *
            draft_area(Y.c.sgsʲs.:($$j).ρa, ᶜρʲs.:($$j)),
        )
        ᶠρʲ = @. lazy(ᶠinterp(ᶜρʲs.:($$j) * ᶜJ) / ᶠJ)
        ᶠwater_fluxʲ =
            _face_value_flux(ᶠu³_diffʲ, ᶜwaterʲ, dt, edmfx_sgsflux_upwinding)
        @. ᶠflux += ᶠρʲ * ᶠwater_fluxʲ
    end

    _sgs_water_tag_fluxes!(
        Yₜ.c,
        Y.c,
        p.scratch.ᶜtagging_q_share_norm,
        ᶠflux,
        model.tags,
    )
    sgs_exchange_of_water_tags!(Yₜ, Y, p, turbconv_model, model)
    return nothing
end

# A tag's share of the local water, as the sedimentation mirror takes it: the
# partition's shares renormalized to sum to one, a source tag's its own clamped
# share. `_is_partition_tag` resolves on the tag's type.
_water_tag_share_field(ᶜY, ᶜnorm, tag) =
    _is_partition_tag(tag) ?
    (@. lazy(water_tag_sediment_share(tag_field(ᶜY, tag), ᶜY.ρq_tot, ᶜnorm))) :
    (@. lazy(water_tag_source_sediment_share(tag_field(ᶜY, tag), ᶜY.ρq_tot)))

_sgs_water_tag_fluxes!(ᶜYₜ, ᶜY, ᶜnorm, ᶠflux, ::Tuple{}) = nothing
function _sgs_water_tag_fluxes!(ᶜYₜ, ᶜY, ᶜnorm, ᶠflux, tags::Tuple)
    tag = first(tags)
    ᶜρq_tagₜ = tag_field(ᶜYₜ, tag)
    ᶜshare = _water_tag_share_field(ᶜY, ᶜnorm, tag)
    @. ᶜρq_tagₜ -= ᶜadvdivᵥ(
        ᶠflux * ifelse(
            _is_upward(ᶠflux),
            ᶠbottom_bias_zero(ᶜshare),
            ᶠtop_bias_zero(ᶜshare),
        ),
    )
    return _sgs_water_tag_fluxes!(ᶜYₜ, ᶜY, ᶜnorm, ᶠflux, Base.tail(tags))
end

"""
    sgs_exchange_of_water_tags!(Yₜ, Y, p, turbconv_model, model)

Exchange provenance between the water tags at the SGS mass flux, as an updraft
copy of the tags would, without one. Each tag `i` takes

    Xᵢ = Σₖ ρᵏ aᵏ (u³ᵏ - u³) (φᵏᵢ - φ̄ᵢ) q_totᵏ

at each face, over the updraft and the environment `k`. `φᵏᵢ` is the tag's share
of the water in subdomain `k`, `φ̄ᵢ` its share in the grid mean. A share is the
tag's specific value over the sum of the partition's, the region tags without
sources, in each subdomain. Where a subdomain's sum or the grid mean's is not
positive, the tags exchange nothing. `X` is the part of the flux an updraft copy
would add to the donor-share flux of [`sgs_mass_flux_of_water_tags!`](@ref): air
of one composition rises and air of another sinks, each with its whole water.

It is the energy source tags' exchange
([`sgs_exchange_of_energy_source_tags!`](@ref)) with the weight `q_totᵏ` in
place of `Aᵏ`, and the same bound: no subdomain may carry more of a tag's water
than the cell holds, `ρaʲ φʲᵢ q_totʲ ≤ ρ φ̄ᵢ q_tot`, no share may go negative,
the partition's tags share one blend factor and each source tag has its own.
Under van Leer the exchange is reconstructed first-order upwind, which keeps
its sum over the partition zero.

The updraft's shares come from the steady entraining plume of the energy tags,
with one change: after the mixing step at each level, the plume's specific
values are scaled so that the partition's sum is the updraft's own water,
`sgsʲs.q_tot`. The shares stay what the mixing made them, and the next level
mixes the right amounts. The updraft loses water by rain-out and sedimentation,
and a plume without the rescale would weight the water it entrained low down too
heavily. The plume starts in the lowest cell with the grid mean's composition,
and again wherever the updraft is absent or does not rise.

It needs one updraft and region tags that partition the domain, which
[`check_water_tracers_transport_supported`](@ref) and
[`check_water_tag_exchange_partition`](@ref) enforce.
"""
function sgs_exchange_of_water_tags!(Yₜ, Y, p, turbconv_model, model)
    (; edmfx_sgsflux_upwinding) = p.atmos.numerics
    (; ᶠu³, ᶠu³ʲs, ᶜρʲs, ᶜuʲs) = p.precomputed
    (; ᶜp, ᶠu³⁰, ᶜT⁰, ᶜq_tot_nonneg⁰, ᶜq_liq⁰, ᶜq_ice⁰) = p.precomputed
    (;
        ᶜturb_entrʲs,
        ᶜentr_vel_scaleʲs,
        ᶜentr_nonvel_rateʲs,
        ᶜarea_bounding_entr_detrʲs,
    ) = p.precomputed
    (; dt) = p
    FT = eltype(Y.c.ρ)
    thermo_params = CAP.thermodynamics_params(p.params)
    upwinding = _exchange_upwinding(edmfx_sgsflux_upwinding)
    ᶜlg = Fields.local_geometry_field(Y.c)
    ᶜJ = ᶜlg.J
    ᶠJ = Fields.local_geometry_field(Y.f).J
    ᶜΔz = Fields.Δz_field(Y.c)
    ᶜρaʲ = Y.c.sgsʲs.:(1).ρa
    ᶜρʲ = ᶜρʲs.:(1)
    ᶜq_totʲ = Y.c.sgsʲs.:(1).q_tot
    ᶜρa⁰ = @. lazy(ρa⁰(Y.c.ρ, Y.c.sgsʲs, turbconv_model))
    # The environment's density is written once, as in the energy exchange:
    # left lazy, it would bring a thermodynamic call into every broadcast below.
    ᶜρ⁰ = p.scratch.ᶜq_tag_environment_density
    @. ᶜρ⁰ = TD.air_density(
        thermo_params,
        ᶜT⁰,
        ᶜp,
        ᶜq_tot_nonneg⁰,
        ᶜq_liq⁰,
        ᶜq_ice⁰,
    )
    ᶜentrʲ = @. lazy(
        compute_entrainment(
            ᶜentr_vel_scaleʲs.:(1),
            ᶜentr_nonvel_rateʲs.:(1),
            ᶜarea_bounding_entr_detrʲs.:(1),
            get_physical_w(ᶜuʲs.:(1), ᶜlg),
        ) + ᶜturb_entrʲs.:(1),
    )
    # The model advects an updraft tracer with the velocity at the face below
    # each cell, so the plume marches with that one.
    ᶠlg = Fields.local_geometry_field(Y.f)
    ᶜwʲ = @. lazy(ᶜbottom_bias(get_physical_w(ᶠu³ʲs.:(1), ᶠlg)))
    flags = _water_partition_flags(model.tags)
    updraft_differences = ShareDifferences(flags, false)
    environment_differences = ShareDifferences(flags, true)
    # The grid mean's specific tag values, negative ones as zero, one tuple per
    # cell, so each tag's kernel below reads a few tuple fields.
    ᶜε̄ = p.scratch.ᶜq_tag_mean
    tag_fields = map(tag -> tag_field(Y.c, tag), model.tags)
    Base.Broadcast.materialize!(
        ᶜε̄,
        Base.Broadcast.broadcasted(_nonnegative_specific, Y.c.ρ, tag_fields...),
    )

    # The updraft's specific tag values, from the plume, rescaled at each level
    # to the updraft's water.
    ᶜεʲ = p.scratch.ᶜq_tag_plume
    ᶜplume_input = Base.Broadcast.broadcasted(
        _water_plume_level,
        ᶜε̄,
        ᶜq_totʲ,
        Y.c.ρ,
        ᶜρaʲ,
        ᶜρa⁰,
        ᶜentrʲ,
        ᶜwʲ,
        ᶜΔz,
    )
    Operators.column_accumulate!(
        WaterPlumeStep(flags),
        ᶜεʲ,
        ᶜplume_input;
        init = ntuple(_ -> FT(NaN), Val(length(model.tags))),
    )

    # Each subdomain's water per unit mass, its area fraction and face density.
    ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
    ᶜq̄ = @. lazy(specific(Y.c.ρq_tot, Y.c.ρ))
    ᶜaʲ = @. lazy(draft_area(ᶜρaʲ, ᶜρʲ))
    ᶜa⁰ = @. lazy(draft_area(ᶜρa⁰, ᶜρ⁰))
    ᶠρʲ = @. lazy(ᶠinterp(ᶜρʲ * ᶜJ) / ᶠJ)
    ᶠρ⁰ = @. lazy(ᶠinterp(ᶜρ⁰ * ᶜJ) / ᶠJ)
    ᶠu³_diffʲ = @. lazy(ᶠu³ʲs.:(1) - ᶠu³)
    ᶠu³_diff⁰ = @. lazy(ᶠu³⁰ - ᶠu³)
    # Each subdomain's shares less the grid mean's, bounded so that no
    # subdomain carries more of a tag's water than the cell holds. The bound's
    # two ratios are written to scratch first, as in the energy exchange: left
    # lazy they box the kernel's broadcast. `_exchange_room` and
    # `_exchange_energy_ratio` do not depend on the weight; here it is water.
    ᶜroom = p.scratch.ᶜq_tag_room
    @. ᶜroom = _exchange_room(Y.c.ρ, ᶜρaʲ, ᶜρa⁰, ᶜq̄, ᶜq_totʲ, ᶜq_tot⁰)
    ᶜwater_ratio = p.scratch.ᶜq_tag_water_ratio
    @. ᶜwater_ratio = _exchange_energy_ratio(ᶜρaʲ, ᶜρa⁰, ᶜq_totʲ, ᶜq_tot⁰)
    ᶜΔφ⁰ = p.scratch.ᶜq_tag_environment
    @. ᶜΔφ⁰ = environment_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
    ᶜΔφʲ = ᶜεʲ
    @. ᶜΔφʲ = updraft_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)

    subdomains = (;
        ᶜΔφʲ,
        ᶜΔφ⁰,
        ᶜq_totʲ,
        ᶜq_tot⁰,
        ᶜaʲ,
        ᶜa⁰,
        ᶠρʲ,
        ᶠρ⁰,
        ᶠu³_diffʲ,
        ᶠu³_diff⁰,
    )
    _exchange_water_tags!(Yₜ.c, subdomains, dt, upwinding, model.tags, 1)
    return nothing
end

_exchange_water_tags!(ᶜYₜ, subdomains, dt, upwinding, ::Tuple{}, i) = nothing
function _exchange_water_tags!(ᶜYₜ, subdomains, dt, upwinding, tags::Tuple, i)
    (; ᶜΔφʲ, ᶜΔφ⁰, ᶜq_totʲ, ᶜq_tot⁰, ᶜaʲ, ᶜa⁰) = subdomains
    (; ᶠρʲ, ᶠρ⁰, ᶠu³_diffʲ, ᶠu³_diff⁰) = subdomains
    ᶜρq_tagₜ = tag_field(ᶜYₜ, first(tags))
    ᶜvalueʲ = @. lazy(getindex(ᶜΔφʲ, i) * ᶜq_totʲ * ᶜaʲ)
    ᶜvalue⁰ = @. lazy(getindex(ᶜΔφ⁰, i) * ᶜq_tot⁰ * ᶜa⁰)
    ᶠfluxʲ = _face_value_flux(ᶠu³_diffʲ, ᶜvalueʲ, dt, upwinding)
    ᶠflux⁰ = _face_value_flux(ᶠu³_diff⁰, ᶜvalue⁰, dt, upwinding)
    @. ᶜρq_tagₜ -= ᶜadvdivᵥ(ᶠρʲ * ᶠfluxʲ + ᶠρ⁰ * ᶠflux⁰)
    return _exchange_water_tags!(
        ᶜYₜ,
        subdomains,
        dt,
        upwinding,
        Base.tail(tags),
        i + 1,
    )
end

# Which water tags form the partition, as `Val` of a tuple of `Bool`s, built
# from the tags' types so that it is a constant, as for the energy tags.
@generated _water_partition_flags(::T) where {T <: Tuple} = :(Val(
    $(Tuple(
        tag <: WaterTag{<:Any, <:AbstractTagRegion, Tuple{}} for
        tag in T.parameters
    )),
))

# One level of the water plume: the energy plume's level, with the updraft's
# own water at that level, which the step rescales to.
@inline function _water_plume_level(ε̄, q_totʲ, ρ, ρaʲ, ρa⁰, entr, wʲ, Δz)
    (ε̄, weight, restart) = _plume_level(ε̄, ρ, ρaʲ, ρa⁰, entr, wʲ, Δz)
    return (ε̄, weight, restart, q_totʲ)
end

# The water plume's step from the level below: mix as the energy plume does,
# then scale every tag's specific value by one factor, so that the partition's
# sum is the updraft's water. The factor keeps the shares, source tags'
# included. Where the partition holds nothing, or the updraft no water, the
# values are left as mixed. A callable type, so that the partition travels in
# the type and the kernel does not box it.
struct WaterPlumeStep{partition} end
WaterPlumeStep(::Val{partition}) where {partition} = WaterPlumeStep{partition}()

@inline function (::WaterPlumeStep{partition})(
    εʲ_below,
    level,
) where {partition}
    (ε̄, weight, restart, q_totʲ) = level
    mixed = _plume_step(εʲ_below, (ε̄, weight, restart))
    total = _partition_total(mixed, partition)
    FT = typeof(total)
    ((total > zero(FT)) & (q_totʲ > zero(FT))) || return mixed
    scale = q_totʲ / total
    return map(ε -> ε * scale, mixed)
end
