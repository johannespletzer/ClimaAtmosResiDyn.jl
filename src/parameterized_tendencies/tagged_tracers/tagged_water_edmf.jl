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
`check_energy_source_exchange_partition`.
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
    masks = map(name -> getproperty(cache.ᶜwater_masks, name), names)
    mask_sum = reduce((a, b) -> a .+ b, map(parent, masks))
    # The largest deviation over every process, so that all of them refuse
    # together, rather than some while the others go on and wait for them.
    deviation = _collective_maximum(maximum(abs.(mask_sum .- 1)), first(masks))
    deviation > 0.01 && error(
        "The water tags exchange provenance at the updraft's mass flux under \
        `turbconv: prognostic_edmfx`, and a tag's share there is its value \
        over the sum of the region tags without sources. Their masks sum to 1 \
        only to within $deviation. Where they leave a gap, that sum is too \
        small, and a tag could take the updraft's whole water flux. $advice",
    )
    return nothing
end

# The maximum of a local value over the processes that hold `field`. Arrays
# that are not fields, as in the unit tests, are one process's.
_collective_maximum(value, field::Fields.Field) =
    ClimaComms.allreduce(ClimaComms.context(field), value, max)
_collective_maximum(value, field) = value

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
    # With copies: the partition's summed shares in the updraft and the
    # environment, which the copies' sedimentation renormalizes by.
    has_water_tag_updraft_copies(model) && return (;
        ᶜq_tag_copy_normʲ = similar(Y.c.ρ),
        ᶜq_tag_copy_norm⁰ = similar(Y.c.ρ),
    )
    atmos.edmfx_model.sgs_mass_flux || return (;)
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
# share. `_is_partition_tag` resolves on the tag's type. The tag's field is
# looked up outside the broadcast, which cannot take the tag itself.
function _water_tag_share_field(ᶜY, ᶜnorm, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    return _is_partition_tag(tag) ?
           (@. lazy(water_tag_sediment_share(ᶜρq_tag, ᶜY.ρq_tot, ᶜnorm))) :
           (@. lazy(water_tag_source_sediment_share(ᶜρq_tag, ᶜY.ρq_tot)))
end

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
`check_water_tracers_transport_supported` and
[`check_water_tag_exchange_partition`](@ref) enforce.
"""
function sgs_exchange_of_water_tags!(Yₜ, Y, p, turbconv_model, model)
    inputs = water_exchange_inputs!(Y, p, turbconv_model, model)
    (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags, upwinding, dt) = inputs
    updraft_differences = ShareDifferences(flags, false)
    environment_differences = ShareDifferences(flags, true)
    ᶜΔφ⁰ = p.scratch.ᶜq_tag_environment
    @. ᶜΔφ⁰ = environment_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
    ᶜΔφʲ = ᶜεʲ
    @. ᶜΔφʲ = updraft_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)

    (; ᶜq_totʲ, ᶜq_tot⁰, ᶜaʲ, ᶜa⁰, ᶠρʲ, ᶠρ⁰, ᶠu³_diffʲ, ᶠu³_diff⁰) = inputs
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

"""
    water_exchange_inputs!(Y, p, turbconv_model, model)

Fill the scratch the water tags' exchange reads, for the current state, and
return it with the lazy fields the exchange needs: the grid mean's specific tag
values `ᶜε̄`, the updraft's from the rescaled plume `ᶜεʲ`, and the bound's room
and water ratio. [`sgs_exchange_of_water_tags!`](@ref) applies the exchange from
these; the audit ([`water_tag_edmf_audit`](@ref)) recomputes them to report
where the bound binds.
"""
function water_exchange_inputs!(Y, p, turbconv_model, model)
    (; edmfx_sgsflux_upwinding) = p.atmos.numerics
    (; ᶠu³, ᶠu³ʲs, ᶜρʲs) = p.precomputed
    (; ᶜp, ᶠu³⁰, ᶜT⁰, ᶜq_tot_nonneg⁰, ᶜq_liq⁰, ᶜq_ice⁰) = p.precomputed
    (; dt) = p
    thermo_params = CAP.thermodynamics_params(p.params)
    upwinding = _exchange_upwinding(edmfx_sgsflux_upwinding)
    ᶜJ = Fields.local_geometry_field(Y.c).J
    ᶠJ = Fields.local_geometry_field(Y.f).J
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
    flags = _water_partition_flags(model.tags)
    ᶜε̄ = p.scratch.ᶜq_tag_mean
    ᶜεʲ = p.scratch.ᶜq_tag_plume
    water_tag_plume!(ᶜεʲ, ᶜε̄, Y, p, turbconv_model, model)

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
    return (;
        ᶜεʲ,
        ᶜε̄,
        ᶜroom,
        ᶜwater_ratio,
        flags,
        upwinding,
        dt,
        ᶜq_totʲ,
        ᶜq_tot⁰,
        ᶜaʲ,
        ᶜa⁰,
        ᶠρʲ,
        ᶠρ⁰,
        ᶠu³_diffʲ,
        ᶠu³_diff⁰,
    )
end

"""
    water_tag_plume!(ᶜεʲ, ᶜε̄, Y, p, turbconv_model, model)

Write the default mode's plume into `ᶜεʲ`: the updraft's specific tag values
from a steady entraining plume, rescaled at each level so that the partition
holds `q_totʲ` (`WaterPlumeStep`). `ᶜε̄` gets the grid mean's specific tag
values, negative ones as zero, which the plume mixes in. Both hold one tuple of
the tags' values per cell. It reads only the state and the precomputed
quantities, so [`start_water_tag_copies_from_plume!`](@ref) can call it with
fields of its own.
"""
function water_tag_plume!(ᶜεʲ, ᶜε̄, Y, p, turbconv_model, model)
    (; ᶠu³ʲs, ᶜuʲs) = p.precomputed
    (;
        ᶜturb_entrʲs,
        ᶜentr_vel_scaleʲs,
        ᶜentr_nonvel_rateʲs,
        ᶜarea_bounding_entr_detrʲs,
    ) = p.precomputed
    FT = eltype(Y.c.ρ)
    ᶜlg = Fields.local_geometry_field(Y.c)
    ᶜΔz = Fields.Δz_field(Y.c)
    ᶜρaʲ = Y.c.sgsʲs.:(1).ρa
    ᶜq_totʲ = Y.c.sgsʲs.:(1).q_tot
    ᶜρa⁰ = @. lazy(ρa⁰(Y.c.ρ, Y.c.sgsʲs, turbconv_model))
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
    # The grid mean's specific tag values, negative ones as zero, one tuple per
    # cell, so each tag's kernel below reads a few tuple fields.
    # `unrolled_map`: `map` over 32 tags or more returns a tuple whose type is
    # not inferred, and every kernel it feeds then dispatches at run time.
    tag_fields = unrolled_map(tag -> tag_field(Y.c, tag), model.tags)
    Base.Broadcast.materialize!(
        ᶜε̄,
        Base.Broadcast.broadcasted(_nonnegative_specific, Y.c.ρ, tag_fields...),
    )

    # The updraft's specific tag values, from the plume, rescaled at each level
    # to the updraft's water.
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
    return nothing
end

"""
    start_water_tag_copies_from_plume!(Y, p)

Set each updraft copy to the default mode's plume ([`water_tag_plume!`](@ref)),
not to `q_totʲ φ̄ᵢ`, the grid mean's composition, which the model starts them
with. The comparison runs of G3_PLAN 6 call it once, after the simulation is
built, so that a default run and its copies twin start from one updraft
composition, and the first hour measures the dynamics, not a spin-up. The model
never calls it. It allocates two fields. Where the updraft holds no water, or
the partition nothing, the plume is left as mixed, and the copies' repair
closes the partition at the first step. Errors without copies.
"""
function start_water_tag_copies_from_plume!(Y, p)
    model = p.atmos.water_tagging_model
    turbconv_model = p.atmos.turbconv_model
    has_water_tag_updraft_copies(model) || error(
        "`start_water_tag_copies_from_plume!` needs the water tags' updraft \
        copies, `water_tag_updraft_copy: true`.",
    )
    FT = eltype(Y.c.ρ)
    tag_values() = Fields.Field(NTuple{length(model.tags), FT}, axes(Y.c))
    ᶜεʲ = tag_values()
    ᶜε̄ = tag_values()
    water_tag_plume!(ᶜεʲ, ᶜε̄, Y, p, turbconv_model, model)
    _copies_from_plume!(Y.c.sgsʲs.:(1), ᶜεʲ, model.tags, 1)
    return nothing
end
_copies_from_plume!(ᶜsgsʲ, ᶜεʲ, ::Tuple{}, i) = nothing
function _copies_from_plume!(ᶜsgsʲ, ᶜεʲ, tags::Tuple, i)
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, first(tags))
    @. ᶜχʲ = getindex(ᶜεʲ, i)
    return _copies_from_plume!(ᶜsgsʲ, ᶜεʲ, Base.tail(tags), i + 1)
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
    # Each value's share first, then the water: `q_totʲ / total` can overflow
    # where the partition holds a denormal amount, and a share cannot.
    # `map`, not `ntuple` over the index: inside the column march the tuple is
    # ClimaCore's `AutoBroadcaster`, whose `map` unrolls, while `ntuple` builds
    # a plain tuple that the march converts back, allocating in every cell
    # (`analysis/water/wp9_variants.jl`).
    return map(ε -> (ε / total) * q_totʲ, mixed)
end

# ============================================================================
# The audit mode: updraft copies
# ============================================================================

##### Under `water_tag_updraft_copy: true` each tag has a copy `q_tag_<name>`, a
##### specific value, in every updraft. `sgs_tracer_names` finds it, so the
##### model's updraft machinery moves it as any updraft tracer: advection,
##### entrainment and detrainment, the SGS mass flux of the grid-mean tag, the
##### diffusion mirror, hyperdiffusion and the filter. Five things the model
##### does to the updraft's water it does not do to a tracer, and they are
##### mirrored here, so that the copies keep summing to `q_totʲ`:
#####
#####   1. the updraft's 0M rain-out, `water_tag_copies_microphysics_tendency!`;
#####   2. the updraft's 1M sedimentation, `sediment_water_tag_copies!`;
#####   3. the relaxation at the surface, `water_tag_copies_boundary_condition_tendency!`;
#####   4. the surface moisture flux into the updraft,
#####      `water_tag_copies_surface_flux_tendency!`. G3_PLAN 4.1 lists four
#####      mirrors; the CI group `tagging_water_edmf_0m` found this one;
#####   5. the filter's clamps, which the copies' repair after it undoes for the
#####      partition's sum, `repair_water_tag_copies!`.

# The copy's entry `(; q_tag_<name> = value)` and its field, from the tag's
# type, so that the name is a compile-time constant.
@generated function updraft_copy_entry(::WaterTag{name}, value) where {name}
    field_name = Symbol(:q_tag_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end
@generated updraft_copy_field(obj, ::WaterTag{name}) where {name} =
    :(obj.$(Symbol(:q_tag_, name)))

"""
    water_tag_updraft_copy_names(model)

`Tuple` of the `Symbol`s (`:q_tag_<name>`) of the water tags' updraft copies,
empty without them.
"""
water_tag_updraft_copy_names(model) =
    has_water_tag_updraft_copies(model) ?
    Tuple(Symbol(:q_tag_, tag_name(tag)) for tag in model.tags) : ()

# Whether an updraft tracer's name is a water tag's copy.
is_water_tag_copy_name(name::Symbol) = startswith(string(name), "q_tag_")
is_water_tag_copy_name(name::MatrixFields.FieldName) =
    is_water_tag_copy_name(MatrixFields.extract_first(name))

"""
    with_water_tag_updraft_copies(sgs, gs, model)

Add the water tags' copies to every updraft's state at a single grid point,
under `water_tag_updraft_copy: true`; return `sgs` unchanged otherwise. Each
copy starts as `q_totʲ φ̄ᵢ`: the updraft's own water, split by the grid mean's
shares, so that the partition's copies sum to `q_totʲ` from the start. The
energy source tags' copies start from the grid mean's specific values instead;
for water that would give the copies the grid mean's water where the updraft
holds more.
"""
with_water_tag_updraft_copies(sgs, gs, model) = _with_water_tag_updraft_copies(
    Val(has_water_tag_updraft_copies(model)),
    sgs,
    gs,
    model,
)
_with_water_tag_updraft_copies(::Val{false}, sgs, gs, model) = sgs
_with_water_tag_updraft_copies(::Val{true}, sgs, gs, model) =
    haskey(sgs, :sgsʲs) ?
    (;
        sgs...,
        sgsʲs = map(
            sgsʲ -> (;
                sgsʲ...,
                _water_tag_copy_entries(gs, sgsʲ.q_tot, model.tags)...,
            ),
            sgs.sgsʲs,
        ),
    ) : sgs
_water_tag_copy_entries(gs, q_totʲ, ::Tuple{}) = (;)
_water_tag_copy_entries(gs, q_totʲ, tags::Tuple) = merge(
    updraft_copy_entry(
        first(tags),
        q_totʲ * water_tag_fraction(tag_field(gs, first(tags)), gs.ρq_tot),
    ),
    _water_tag_copy_entries(gs, q_totʲ, Base.tail(tags)),
)

"""
    rebuild_water_tag_updraft_copies!(Y, model, turbconv_model)

Set every copy to `q_totʲ φ̄ᵢ` from the current state, after the grid-scale tags
are rebuilt: for a fresh run and a file-based start, where the state is written
after the tags were first built. Not on a restart, which reads the copies from
the checkpoint. A no-op without copies.
"""
rebuild_water_tag_updraft_copies!(Y, model, turbconv_model) = nothing
function rebuild_water_tag_updraft_copies!(
    Y,
    model::WaterTaggingModel,
    turbconv_model::PrognosticEDMFX,
)
    has_water_tag_updraft_copies(model) || return nothing
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        _rebuild_water_tag_copies!(Y.c.sgsʲs.:($j), Y.c, model.tags)
    end
    return nothing
end
_rebuild_water_tag_copies!(ᶜsgsʲ, ᶜY, ::Tuple{}) = nothing
function _rebuild_water_tag_copies!(ᶜsgsʲ, ᶜY, tags::Tuple)
    tag = first(tags)
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜρq_tag = tag_field(ᶜY, tag)
    @. ᶜχʲ = ᶜsgsʲ.q_tot * water_tag_fraction(ᶜρq_tag, ᶜY.ρq_tot)
    return _rebuild_water_tag_copies!(ᶜsgsʲ, ᶜY, Base.tail(tags))
end

# ---------------------------------------------------------------------------
# 1. The updraft's 0M rain-out
# ---------------------------------------------------------------------------

"""
    water_tag_copies_microphysics_tendency!(Yₜ, Y, p, microphysics_model, turbconv_model)

Mirror the updraft's 0M rain-out on the copies. The model removes the rain as
`ρaʲ += ρaʲ dq` and `q_totʲ += dq (1 - q_totʲ)`, with `dq ≤ 0` the updraft's
`dq_tot_dt` (`microphysics_tendency!`). A tracer gets neither. Each copy takes
`χᵢʲ += dq (φʲᵢ - χᵢʲ)` with `φʲᵢ = clamp(χᵢʲ / q_totʲ, 0, 1)`: its share of the
water lost, plus the concentration of what stays by the mass that left. Summed
over a partition whose copies lie in `[0, q_totʲ]` and sum to `q_totʲ`, this is
the parent's term exactly. A drift of the sum keeps its ratio to `q_totʲ`, so
only its absolute size shrinks as the updraft rains out, and the clamp breaks
exactness where a copy lies outside that range. Call it right after
`microphysics_tendency!`, on the implicit or
the explicit path, wherever that runs. A no-op without copies and other than
under 0M with prognostic EDMF, where the updraft's microphysics never changes
`q_totʲ`.

It has no Jacobian entry, deliberately: `q_totʲ`'s rain-out has none, and an
entry for the copies alone would part their Newton updates from `q_totʲ`'s.
See `docs/known_issues.md`, issue 4.
"""
water_tag_copies_microphysics_tendency!(Yₜ, Y, p, microphysics_model, turbconv_model) =
    nothing
function water_tag_copies_microphysics_tendency!(
    Yₜ,
    Y,
    p,
    ::EquilibriumMicrophysics0M,
    turbconv_model::PrognosticEDMFX,
)
    model = p.atmos.water_tagging_model
    has_water_tag_updraft_copies(model) || return nothing
    (; ᶜmp_tendencyʲs) = p.precomputed
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        _copies_rain_out!(
            Yₜ.c.sgsʲs.:($j),
            Y.c.sgsʲs.:($j),
            ᶜmp_tendencyʲs.:($j),
            model.tags,
        )
    end
    return nothing
end
_copies_rain_out!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmp_tendencyʲ, ::Tuple{}) = nothing
function _copies_rain_out!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmp_tendencyʲ, tags::Tuple)
    tag = first(tags)
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜχʲₜ = updraft_copy_field(ᶜsgsʲₜ, tag)
    @. ᶜχʲₜ +=
        ᶜmp_tendencyʲ.dq_tot_dt *
        (water_tag_fraction(ᶜχʲ, ᶜsgsʲ.q_tot) - ᶜχʲ)
    return _copies_rain_out!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmp_tendencyʲ, Base.tail(tags))
end

# ---------------------------------------------------------------------------
# 2. The updraft's 1M sedimentation
# ---------------------------------------------------------------------------

"""
    sediment_water_tag_copies!(Yₜ, Y, p, j, ᶜqʲ, ᶜwʲ, ᶜa, ᶜρ⁰w⁰q⁰, α_lat, ᶜinv_ρ̂, ᶠJ)

Mirror one sedimenting species' updraft sedimentation on the copies of updraft
`j`. The model moves the species `qʲ` and `q_totʲ` by
`ᶜinv_ρ̂ * updraft_sedimentation!(…, qʲ, …, ρ⁰w⁰q⁰, α_lat)`: the flux within the
updraft, and where the updraft narrows with height, the environment's falling
water flowing in (`edmfx_sgs_vertical_advection_tendency!`). The falling updraft
water carries the updraft's composition, and the inflow the environment's. So
each copy takes the same term with `qʲ φʲᵢ` and `ρ⁰w⁰q⁰ φ⁰ᵢ`. The term is
linear in both, and the partition's shares in each subdomain are renormalized to
sum to one, so the copies' terms sum to the parent's. A source tag's copy takes
its own clamped share. Call it inside the species loop, after the species' own
update, since it reuses that update's scratch. A no-op without copies.
"""
sediment_water_tag_copies!(Yₜ, Y, p, j, ᶜqʲ, ᶜwʲ, ᶜa, ᶜρ⁰w⁰q⁰, α_lat, ᶜinv_ρ̂, ᶠJ) =
    _sediment_water_tag_copies!(
        Yₜ,
        Y,
        p,
        j,
        ᶜqʲ,
        ᶜwʲ,
        ᶜa,
        ᶜρ⁰w⁰q⁰,
        α_lat,
        ᶜinv_ρ̂,
        ᶠJ,
        p.atmos.water_tagging_model,
    )
_sediment_water_tag_copies!(Yₜ, Y, p, j, ᶜqʲ, ᶜwʲ, ᶜa, ᶜρ⁰w⁰q⁰, α_lat, ᶜinv_ρ̂, ᶠJ, model) =
    nothing
function _sediment_water_tag_copies!(
    Yₜ,
    Y,
    p,
    j,
    ᶜqʲ,
    ᶜwʲ,
    ᶜa,
    ᶜρ⁰w⁰q⁰,
    α_lat,
    ᶜinv_ρ̂,
    ᶠJ,
    model::WaterTaggingModel,
)
    has_water_tag_updraft_copies(model) || return nothing
    ᶜsgsʲ = Y.c.sgsʲs.:($j)
    ᶜq_totʲ = ᶜsgsʲ.q_tot
    ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
    # The partition's shares in the updraft and the environment, summed, to
    # renormalize by. The copies are specific values, so the updraft's share is
    # the copy over `q_totʲ`, and the environment's its value there over `q_tot⁰`.
    (ᶜnormʲ, ᶜnorm⁰) =
        (p.scratch.ᶜq_tag_copy_normʲ, p.scratch.ᶜq_tag_copy_norm⁰)
    @. ᶜnormʲ = 0
    @. ᶜnorm⁰ = 0
    _accumulate_copy_norms!(ᶜnormʲ, ᶜnorm⁰, ᶜsgsʲ, Y, p, model.tags)
    vtt = p.scratch.ᶜtemp_scalar_4
    _sediment_water_tag_copies_each!(
        Yₜ.c.sgsʲs.:($j),
        Y,
        p,
        ᶜsgsʲ,
        (;
            ᶜρʲ = p.precomputed.ᶜρʲs.:($j),
            ᶜqʲ,
            ᶜwʲ,
            ᶜa,
            ᶜρ⁰w⁰q⁰,
            α_lat,
            ᶜinv_ρ̂,
            ᶠJ,
            ᶜnormʲ,
            ᶜnorm⁰,
            ᶜq_tot⁰,
            vtt,
        ),
        model.tags,
    )
    return nothing
end

@generated water_tag_copy_field_name(::WaterTag{name}) where {name} =
    :(MatrixFields.FieldName($(QuoteNode(Symbol(:q_tag_, name)))))

_accumulate_copy_norms!(ᶜnormʲ, ᶜnorm⁰, ᶜsgsʲ, Y, p, ::Tuple{}) = nothing
function _accumulate_copy_norms!(ᶜnormʲ, ᶜnorm⁰, ᶜsgsʲ, Y, p, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
        ᶜχ⁰ = ᶜspecific_env_value(water_tag_copy_field_name(tag), Y, p)
        ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
        @. ᶜnormʲ += water_tag_fraction(ᶜχʲ, ᶜsgsʲ.q_tot)
        @. ᶜnorm⁰ += water_tag_fraction(ᶜχ⁰, ᶜq_tot⁰)
    end
    return _accumulate_copy_norms!(ᶜnormʲ, ᶜnorm⁰, ᶜsgsʲ, Y, p, Base.tail(tags))
end

# A copy's share of its subdomain's water: renormalized for the partition, its
# own clamped share for a source tag.
_copy_share(χ, q, norm, ::Val{true}) = water_tag_sediment_share(χ, q, norm)
_copy_share(χ, q, norm, ::Val{false}) = water_tag_source_sediment_share(χ, q)

_sediment_water_tag_copies_each!(ᶜsgsʲₜ, Y, p, ᶜsgsʲ, args, ::Tuple{}) = nothing
function _sediment_water_tag_copies_each!(ᶜsgsʲₜ, Y, p, ᶜsgsʲ, args, tags::Tuple)
    (; ᶜρʲ, ᶜqʲ, ᶜwʲ, ᶜa, ᶜρ⁰w⁰q⁰, α_lat, ᶜinv_ρ̂, ᶠJ) = args
    (; ᶜnormʲ, ᶜnorm⁰, ᶜq_tot⁰, vtt) = args
    tag = first(tags)
    partition = Val(_is_partition_tag(tag))
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜχʲₜ = updraft_copy_field(ᶜsgsʲₜ, tag)
    ᶜχ⁰ = ᶜspecific_env_value(water_tag_copy_field_name(tag), Y, p)
    ᶜfalling = @. lazy(ᶜqʲ * _copy_share(ᶜχʲ, ᶜsgsʲ.q_tot, ᶜnormʲ, partition))
    ᶜinflow = @. lazy(ᶜρ⁰w⁰q⁰ * _copy_share(ᶜχ⁰, ᶜq_tot⁰, ᶜnorm⁰, partition))
    updraft_sedimentation!(
        vtt,
        p,
        ᶜρʲ,
        ᶜwʲ,
        ᶜa,
        ᶜfalling,
        ᶠJ,
        ᶜinflow,
        α_lat,
    )
    @. ᶜχʲₜ += ᶜinv_ρ̂ * vtt
    return _sediment_water_tag_copies_each!(
        ᶜsgsʲₜ,
        Y,
        p,
        ᶜsgsʲ,
        args,
        Base.tail(tags),
    )
end

# ---------------------------------------------------------------------------
# 3. The relaxation at the surface
# ---------------------------------------------------------------------------

"""
    water_tag_copies_boundary_condition_tendency!(Yₜ, Y, p, turbconv_model)

Mirror the updraft's relaxation at the lowest level on the copies. The model
relaxes `q_totʲ` toward the buoyant surface value `q_b = q̄ + C√σ²` at the rate
`mass_flux_source / max(ρa, ρ a_min)` (`edmfx_boundary_condition_tendency!`); a
tracer gets nothing. Each copy relaxes at the same rate toward `q_b φ̄ᵢ`, the
grid mean's composition in that cell, the partition's renormalized. So the
partition's copies relax toward `q_b` together, and no copy gets water the cell
does not hold: a surface-evaporation tag gets only its share of the cell's
water, not the excess `C√σ²` as its own. A no-op without copies.
"""
water_tag_copies_boundary_condition_tendency!(Yₜ, Y, p, turbconv_model) = nothing
function water_tag_copies_boundary_condition_tendency!(
    Yₜ,
    Y,
    p,
    turbconv_model::PrognosticEDMFX,
)
    model = p.atmos.water_tagging_model
    has_water_tag_updraft_copies(model) || return nothing
    (; params) = p
    (; ᶜρʲs, sfc_mass_flux_sourceʲs, sfc_q_tot_buoyantʲs) = p.precomputed
    FT = eltype(params)
    a_min = CAP.min_area(CAP.turbconv_params(params))
    water_tag_share_norm!(p, Y)
    ᶜnorm = p.scratch.ᶜtagging_q_share_norm
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        level_values(field) = Fields.field_values(Fields.level(field, 1))
        values = (;
            ρ = level_values(ᶜρʲs.:($j)),
            ρa = level_values(Y.c.sgsʲs.:($j).ρa),
            source = level_values(sfc_mass_flux_sourceʲs.:($j)),
            q_b = level_values(sfc_q_tot_buoyantʲs.:($j)),
            ρq_tot = level_values(Y.c.ρq_tot),
            norm = level_values(ᶜnorm),
            a_min = FT(a_min),
        )
        _relax_water_tag_copies!(
            Yₜ.c.sgsʲs.:($j),
            Y.c.sgsʲs.:($j),
            Y.c,
            values,
            level_values,
            model.tags,
        )
    end
    return nothing
end
_relax_water_tag_copies!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜY, values, level_values, ::Tuple{}) =
    nothing
function _relax_water_tag_copies!(
    ᶜsgsʲₜ,
    ᶜsgsʲ,
    ᶜY,
    values,
    level_values,
    tags::Tuple,
)
    tag = first(tags)
    (; ρ, ρa, source, q_b, ρq_tot, norm, a_min) = values
    χ = level_values(updraft_copy_field(ᶜsgsʲ, tag))
    χₜ = level_values(updraft_copy_field(ᶜsgsʲₜ, tag))
    ρq_tag = level_values(tag_field(ᶜY, tag))
    partition = Val(_is_partition_tag(tag))
    @. χₜ +=
        source * (q_b * _copy_share(ρq_tag, ρq_tot, norm, partition) - χ) /
        max(ρa, ρ * a_min)
    return _relax_water_tag_copies!(
        ᶜsgsʲₜ,
        ᶜsgsʲ,
        ᶜY,
        values,
        level_values,
        Base.tail(tags),
    )
end

# ---------------------------------------------------------------------------
# 3b. The surface flux into the updraft
# ---------------------------------------------------------------------------

"""
    water_tag_copies_surface_flux_tendency!(Yₜ, Y, p, turbconv_model)

Mirror the updraft's share of the surface moisture flux on the copies.
`surface_flux_tendency!` adds the flux to `q_totʲ` in the lowest cell, as the
grid mean's boundary tendency over the updraft's density. It gives every other
updraft tracer a zero flux, the copies included. Each copy takes that
increment `Δʲ` by the grid-scale tags' rule for the label `surface_flux`
(`attribute_tagged_ρq_tot!`). A tag that receives the surface flux gains its
mask times `max(Δʲ, 0)`. Every copy loses its share `φʲᵢ = clamp(χᵢʲ / q_totʲ)`
of `min(Δʲ, 0)`, the dew. The partition's masks sum to one, so its copies take
the whole gain, and their shares the whole loss. The model's own term assumes
one updraft, and so does this one. A no-op without copies.
"""
water_tag_copies_surface_flux_tendency!(Yₜ, Y, p, turbconv_model) = nothing
function water_tag_copies_surface_flux_tendency!(
    Yₜ,
    Y,
    p,
    ::PrognosticEDMFX,
)
    model = p.atmos.water_tagging_model
    has_water_tag_updraft_copies(model) || return nothing
    p.atmos.disable_surface_flux_tendency && return nothing
    # The model's own increment of `q_totʲ`, from the same flux and operator.
    # The flux goes to the operator as it is, so the model's scratch is not
    # written.
    ᶜq_tot = @. lazy(specific(Y.c.ρq_tot, Y.c.ρ))
    btt = boundary_tendency_scalar(
        ᶜq_tot,
        p.precomputed.sfc_conditions.ρ_flux_q_tot,
    )
    ᶜΔʲ = @. lazy(-specific(btt, p.precomputed.ᶜρʲs.:(1)))
    _surface_flux_of_copies!(
        Yₜ.c.sgsʲs.:(1),
        Y.c.sgsʲs.:(1),
        p.tagging.ᶜwater_masks,
        ᶜΔʲ,
        model.tags,
    )
    return nothing
end
_surface_flux_of_copies!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmasks, ᶜΔʲ, ::Tuple{}) = nothing
function _surface_flux_of_copies!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmasks, ᶜΔʲ, tags::Tuple)
    tag = first(tags)
    ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜχʲₜ = updraft_copy_field(ᶜsgsʲₜ, tag)
    receives = tag_receives_source(tag, :surface_flux)
    ᶜgain = _surface_gain_weight(ᶜmasks, tag)
    @. ᶜχʲₜ +=
        receives * ᶜgain * max(ᶜΔʲ, 0) +
        min(ᶜΔʲ, 0) * water_tag_fraction(ᶜχʲ, ᶜsgsʲ.q_tot)
    return _surface_flux_of_copies!(
        ᶜsgsʲₜ,
        ᶜsgsʲ,
        ᶜmasks,
        ᶜΔʲ,
        Base.tail(tags),
    )
end
# The weight of a gain for a tag that receives the surface flux, as
# `_accumulate_water_tag!` gives it: one without a region, the region's mask
# with one. Whether it receives the flux is known only at run time, so it is a
# factor in the broadcast, which keeps the weight's type fixed.
_surface_gain_weight(ᶜmasks, tag::WaterTag{name, Nothing}) where {name} = true
_surface_gain_weight(ᶜmasks, tag::WaterTag) = tag_field(ᶜmasks, tag)

# ---------------------------------------------------------------------------
# 4. The copies' repair after the filter
# ---------------------------------------------------------------------------

"""
    repair_water_tag_copies!(Y, p)

After the updraft filter (`enforce_edmf_updraft_constraints!`), close the
partition's copies onto `q_totʲ` again. The filter clamps each copy and
`q_totʲ` apart, so their sum and `q_totʲ` part. The residual
`r = q_totʲ - Σᵢ∈P χᵢʲ` is handed to the partition's copies by their shares,
floored at what they hold, by [`water_tag_rescale_shift`](@ref), the rule the
grid-scale tags follow after a limiter. The filter's own increment is not
handed on as well: the filter already clamped each copy, and doing both would
count it twice. `r` before the repair is kept in `p.tagging.ᶜwater_copy_residual`
for the diagnostic `q_tag_copy_res`, and the water moved, times `ρaʲ`, in the
ledger `q_tag_upfix_<name>`, cumulative since the segment started. Source tags'
copies are not part of the sum and are left as the filter left them. A no-op
without copies.
"""
repair_water_tag_copies!(Y, p) =
    _repair_water_tag_copies!(
        Y,
        p,
        p.atmos.water_tagging_model,
        p.atmos.turbconv_model,
    )
_repair_water_tag_copies!(Y, p, model, turbconv_model) = nothing
function _repair_water_tag_copies!(
    Y,
    p,
    model::WaterTaggingModel,
    ::PrognosticEDMFX,
)
    has_water_tag_updraft_copies(model) || return nothing
    (; ᶜwater_upfix, ᶜwater_copy_residual, ᶜwater_copy_sum, ᶜwater_copy_pos) =
        p.tagging
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    @. ᶜwater_copy_sum = 0
    @. ᶜwater_copy_pos = 0
    _accumulate_copy_sums!(ᶜwater_copy_sum, ᶜwater_copy_pos, ᶜsgsʲ, model.tags)
    @. ᶜwater_copy_residual = ᶜsgsʲ.q_tot - ᶜwater_copy_sum
    _apply_copy_repair!(
        ᶜsgsʲ,
        ᶜwater_upfix,
        ᶜwater_copy_sum,
        ᶜwater_copy_pos,
        model.tags,
    )
    return nothing
end
_accumulate_copy_sums!(ᶜsum, ᶜpos, ᶜsgsʲ, ::Tuple{}) = nothing
function _accumulate_copy_sums!(ᶜsum, ᶜpos, ᶜsgsʲ, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
        @. ᶜsum += ᶜχʲ
        @. ᶜpos += max(ᶜχʲ, 0)
    end
    return _accumulate_copy_sums!(ᶜsum, ᶜpos, ᶜsgsʲ, Base.tail(tags))
end
# `ᶜsum` and `ᶜpos` come from the pre-repair copies and are only read here, so
# each copy can be rewritten in place.
_apply_copy_repair!(ᶜsgsʲ, ᶜupfix, ᶜsum, ᶜpos, ::Tuple{}) = nothing
function _apply_copy_repair!(ᶜsgsʲ, ᶜupfix, ᶜsum, ᶜpos, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜχʲ = updraft_copy_field(ᶜsgsʲ, tag)
        ᶜfix = tag_field(ᶜupfix, tag)
        # Ledger first, so it records the correction itself.
        @. ᶜfix +=
            ᶜsgsʲ.ρa *
            water_tag_rescale_shift(ᶜχʲ, ᶜsgsʲ.q_tot, ᶜsum, ᶜpos)
        @. ᶜχʲ += water_tag_rescale_shift(ᶜχʲ, ᶜsgsʲ.q_tot, ᶜsum, ᶜpos)
    end
    return _apply_copy_repair!(ᶜsgsʲ, ᶜupfix, ᶜsum, ᶜpos, Base.tail(tags))
end

# ---------------------------------------------------------------------------
# The copies in the Jacobian
# ---------------------------------------------------------------------------

"""
    water_tag_copy_sgs_names(model)

`Tuple` of the `@name`s (relative to `Y.c.sgsʲs.:(1)`) of the water tags'
updraft copies, empty without them. They are passive updraft tracers, so the
generic Jacobian blocks of advection, diffusion and entrainment cover them; the
copies' sedimentation and surface relaxation add to those blocks. The names come
from the model's type, so the tuple's type is fixed and building it allocates
nothing, in every Jacobian update of every run.
"""
water_tag_copy_sgs_names(::Nothing) = ()
water_tag_copy_sgs_names(model::WaterTaggingModel) = _water_tag_copy_sgs_names(
    Val(has_water_tag_updraft_copies(model)),
    model.tags,
)
_water_tag_copy_sgs_names(::Val{false}, tags) = ()
_water_tag_copy_sgs_names(::Val{true}, tags) =
    unrolled_map(water_tag_copy_field_name, tags)

# The derivative of a copy's falling water `qʲ χ / q_totʲ` with respect to the
# copy. The sedimentation Jacobian takes it without the renormalization's and
# the clamp's dependence, as an approximation. It is capped at one, the most a
# species can hold of the updraft's water.
@inline water_tag_copy_fall_share_derivative(qʲ, q_totʲ) =
    q_totʲ > zero(q_totʲ) ? min(qʲ / q_totʲ, one(q_totʲ)) : zero(q_totʲ)

# ============================================================================
# The audit's own columns
# ============================================================================

"""
    water_tag_edmf_audit(Y, p, model, scale)

The water tags' own columns for `water_tag_audit.csv` under prognostic EDMF, or
`nothing` otherwise. Collective, as [`tag_audit`](@ref) is.

In the default mode, where the exchange runs: where its bound binds. The
exchange blends the plume toward the grid mean where a tag would otherwise
carry more water in a subdomain than the cell holds (decision 5 of G3_PLAN).
From the current state, `exchange_volume_fraction` is the fraction of the
volume where the exchange runs at all, `bound_partition` the fraction of that
where the partition's factor is below one, and `bound_<name>` the same for each
source tag's own factor. Where the partition's bound binds, the partition mixes
less than a copy would; where a source tag's binds, that tag does, and an
identity such as `evap_tropo + evap_strat = evap` stops holding exactly.

With updraft copies: `copy_residual`, the integral of `|q_totʲ - Σᵢ χᵢʲ| ρaʲ`
before the last repair, and `copy_repair`, the integral of the repair ledgers'
magnitudes, cumulative, each also relative to `scale`.
"""
water_tag_edmf_audit(Y, p, model, scale) =
    _water_tag_edmf_audit(Y, p, model, p.atmos.turbconv_model, scale)
_water_tag_edmf_audit(Y, p, model, turbconv_model, scale) = nothing
function _water_tag_edmf_audit(
    Y,
    p,
    model::WaterTaggingModel,
    turbconv_model::PrognosticEDMFX,
    scale,
)
    per_scale(x) = iszero(scale) ? zero(x) : x / scale
    ᶜtmp = p.scratch.ᶜtemp_scalar
    if has_water_tag_updraft_copies(model)
        (; ᶜwater_copy_residual, ᶜwater_upfix) = p.tagging
        @. ᶜtmp = abs(ᶜwater_copy_residual) * Y.c.sgsʲs.:(1).ρa
        copy_residual = sum(ᶜtmp)
        @. ᶜtmp = 0
        for tag in model.tags
            _is_partition_tag(tag) || continue
            ᶜfix = tag_field(ᶜwater_upfix, tag)
            @. ᶜtmp += abs(ᶜfix)
        end
        copy_repair = sum(ᶜtmp)
        return (;
            copy_residual,
            copy_residual_relative = per_scale(copy_residual),
            copy_repair,
            copy_repair_relative = per_scale(copy_repair),
        )
    end
    p.atmos.edmfx_model.sgs_mass_flux || return nothing
    inputs = water_exchange_inputs!(Y, p, turbconv_model, model)
    (; ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio, flags) = inputs
    ᶜθ = p.scratch.ᶜq_tag_environment
    blend_factors = WaterBlendFactors(flags)
    @. ᶜθ = blend_factors(ᶜεʲ, ᶜε̄, ᶜroom, ᶜwater_ratio)
    first_index = findfirst(identity, _flag_values(flags))
    @. ᶜtmp = one(ᶜtmp)
    volume = sum(ᶜtmp)
    @. ᶜtmp = ifelse(getindex(ᶜθ, $first_index) >= 0, one(ᶜtmp), zero(ᶜtmp))
    active = sum(ᶜtmp)
    fraction_bound(i) = begin
        @. ᶜtmp = ifelse(
            (getindex(ᶜθ, $i) >= 0) & (getindex(ᶜθ, $i) < 1),
            one(ᶜtmp),
            zero(ᶜtmp),
        )
        iszero(active) ? zero(active) : sum(ᶜtmp) / active
    end
    source_indices =
        Tuple(i for (i, tag) in enumerate(model.tags) if !_is_partition_tag(tag))
    source_names =
        Tuple(Symbol(:bound_, tag_name(model.tags[i])) for i in source_indices)
    return (;
        exchange_volume_fraction = iszero(volume) ? zero(volume) :
                                   active / volume,
        bound_partition = fraction_bound(first_index),
        NamedTuple{source_names}(map(fraction_bound, source_indices))...,
    )
end

_flag_values(::Val{partition}) where {partition} = partition

# The blend factors of the exchange's bound per tag, as `ShareDifferences`
# takes them: the partition's common factor for its tags, and each source tag's
# own. `-1` where the exchange does not run.
struct WaterBlendFactors{partition} end
WaterBlendFactors(::Val{partition}) where {partition} =
    WaterBlendFactors{partition}()
@inline function (::WaterBlendFactors{partition})(
    εʲ,
    ε̄,
    room,
    ratio,
) where {partition}
    FT = typeof(room)
    N = length(partition)
    total = _partition_total(ε̄, partition)
    totalʲ = _partition_total(εʲ, partition)
    no_exchange =
        (room < zero(FT)) |
        (ratio <= zero(FT)) |
        (total <= zero(FT)) |
        (totalʲ <= zero(FT))
    no_exchange && return ntuple(_ -> -one(FT), Val(N))
    θ = _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    return ntuple(
        i ->
            partition[i] ? θ : _blend_factor(ε̄, εʲ, total, totalʲ, room, i),
        Val(N),
    )
end
