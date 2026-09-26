#####
##### The energy source tags' updraft copies: the mirrors of `mseʲ`
#####
##### Under `energy_source_tag_updraft_copy: true` each tag has a copy
##### `e_src_<name>`, a specific value, in every updraft. `sgs_tracer_names`
##### finds it, so the model's updraft machinery moves it as any updraft tracer:
##### advection, entrainment, the SGS mass flux of the grid-mean tag, the
##### diffusion mirror, hyperdiffusion, the sponge and the filter. Four things
##### the model does to the updraft's `mseʲ` it does not do to a tracer, and each
##### changes the updraft's energy `Aʲ = mseʲ + Kʲ - p/ρʲ + c`. They are mirrored
##### here, so that the partition's copies change with `Aʲ` (G4.1 and G4.11 of
##### the tag-closure experiments):
#####
#####   1. the surface enthalpy flux into the updraft's lowest cell,
#####      `energy_source_copies_surface_flux_tendency!`;
#####   2. the relaxation toward the buoyant surface value there,
#####      `energy_source_copies_boundary_condition_tendency!`;
#####   3. radiation, under RRTMGP, `energy_source_copies_radiation_tendency!`;
#####   4. the updraft's 0M rain-out, `energy_source_copies_microphysics_tendency!`.
#####
##### Two writers of `mseʲ` get no mirror. The buoyancy term of
##### `edmfx_sgs_vertical_advection_tendency!` is energy the updraft trades:
##### its velocity equation takes the part `1 - α_b` of it from `Kʲ`, and the
##### rest is work done through the non-hydrostatic pressure. No tag is
##### labelled with either, so neither is a source to share out, and what it
##### leaves in `Aʲ` shows in `e_src_copy_res`. And the pressure work is a no-op
##### in the model (`pressure_work_tendency!`).
#####
##### Each mirror reads the state and writes only the copies' tendencies, so the
##### model's fields do not change.

"""
    energy_source_copy_share(χ, S)

A copy's share of a loss of the updraft's energy: its value over `S`, the sum
of the partition's copies' positive parts, clamped to `[0, 1]`. Zero where `S`
is not positive. Over the partition the shares of non-negative copies add up to
one, so the partition loses exactly what `mseʲ` loses.
"""
@inline energy_source_copy_share(χ, S) =
    S > zero(S) ? min(max(χ / S, zero(χ)), one(χ)) : zero(χ)

"""
    energy_source_copy_sum!(ᶜS, ᶜsgsʲ, tags)

Write into `ᶜS` the sum of the positive parts of the partition's copies in one
updraft, `Σᵢ∈P max(χᵢʲ, 0)`, the denominator of `energy_source_copy_share`.
"""
function energy_source_copy_sum!(ᶜS, ᶜsgsʲ, tags)
    @. ᶜS = 0
    _accumulate_energy_source_copy_sum!(ᶜS, ᶜsgsʲ, tags)
    return ᶜS
end
_accumulate_energy_source_copy_sum!(ᶜS, ᶜsgsʲ, ::Tuple{}) = nothing
function _accumulate_energy_source_copy_sum!(ᶜS, ᶜsgsʲ, tags::Tuple)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜχ = updraft_copy_field(ᶜsgsʲ, tag)
        @. ᶜS += max(ᶜχ, 0)
    end
    return _accumulate_energy_source_copy_sum!(ᶜS, ᶜsgsʲ, Base.tail(tags))
end

# The weight of a gain for a tag that receives the process, as
# `_accumulate_energy_source_tag!` gives it: one without a region, the region's
# mask with one.
_energy_source_copy_gain_weight(ᶜmasks, ::EnergySourceTag{name, Nothing}) where {name} =
    true
_energy_source_copy_gain_weight(ᶜmasks, tag::EnergySourceTag) =
    tag_field(ᶜmasks, tag)

"""
    mirror_on_energy_source_copies!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmasks, ᶜΔʲ, ᶜS, source, tags)

Give the updraft's specific increment of `mseʲ` from one process, `Δʲ`, to the
copies of that updraft, by the grid mean's bracket rule
(`attribute_energy_source_tags!`). A tag that receives the label `source` gains
its mask times `max(Δʲ, 0)`; a pure region tag receives every label. Every copy
loses its share of `min(Δʲ, 0)`, `energy_source_copy_share(χᵢʲ, S)` with `ᶜS`
from `energy_source_copy_sum!`. Where the region tags' masks partition the
domain and the copies are not negative, the partition's copies change by
exactly `Δʲ`. The offset does not enter: an increment of a specific energy
carries none.
"""
mirror_on_energy_source_copies!(ᶜsgsʲₜ, ᶜsgsʲ, ᶜmasks, ᶜΔʲ, ᶜS, source, ::Tuple{}) =
    nothing
function mirror_on_energy_source_copies!(
    ᶜsgsʲₜ,
    ᶜsgsʲ,
    ᶜmasks,
    ᶜΔʲ,
    ᶜS,
    source,
    tags::Tuple,
)
    tag = first(tags)
    ᶜχ = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜχₜ = updraft_copy_field(ᶜsgsʲₜ, tag)
    if tag_receives_source(tag, source)
        ᶜgain = _energy_source_copy_gain_weight(ᶜmasks, tag)
        @. ᶜχₜ +=
            ᶜgain * max(ᶜΔʲ, 0) + min(ᶜΔʲ, 0) * energy_source_copy_share(ᶜχ, ᶜS)
    else
        @. ᶜχₜ += min(ᶜΔʲ, 0) * energy_source_copy_share(ᶜχ, ᶜS)
    end
    return mirror_on_energy_source_copies!(
        ᶜsgsʲₜ,
        ᶜsgsʲ,
        ᶜmasks,
        ᶜΔʲ,
        ᶜS,
        source,
        Base.tail(tags),
    )
end

# The model with copies, or `nothing`, so that each mirror is a no-op without.
_energy_source_copies_model(p) =
    has_energy_source_updraft_copies(p.atmos.energy_source_tagging_model) ?
    p.atmos.energy_source_tagging_model : nothing

# One updraft's mirror of an increment `ᶜΔʲ` under the label `source`.
function _mirror_on_updraft!(Yₜ, Y, p, model, j, ᶜΔʲ, source)
    ᶜS = p.tagging.ᶜenergy_source_copy_sum
    energy_source_copy_sum!(ᶜS, Y.c.sgsʲs.:($j), model.tags)
    mirror_on_energy_source_copies!(
        Yₜ.c.sgsʲs.:($j),
        Y.c.sgsʲs.:($j),
        p.tagging.ᶜenergy_source_masks,
        ᶜΔʲ,
        ᶜS,
        source,
        model.tags,
    )
    return nothing
end

# ---------------------------------------------------------------------------
# 1. The surface enthalpy flux into the updraft
# ---------------------------------------------------------------------------

"""
    energy_source_copies_surface_flux_tendency!(Yₜ, Y, p, turbconv_model)

Mirror the updraft's share of the surface enthalpy flux on the copies.
`surface_flux_tendency!` adds the grid mean's boundary tendency of `h_tot`,
over the updraft's density, to `mseʲ` in the lowest cell, and gives no updraft
tracer anything. The copies take that increment by the grid mean's rule for the
label `surface_flux` (`mirror_on_energy_source_copies!`). The model's own term
assumes one updraft, and so does this one. A no-op without copies.
"""
energy_source_copies_surface_flux_tendency!(Yₜ, Y, p, turbconv_model) = nothing
function energy_source_copies_surface_flux_tendency!(
    Yₜ,
    Y,
    p,
    ::PrognosticEDMFX,
)
    model = _energy_source_copies_model(p)
    isnothing(model) && return nothing
    p.atmos.disable_surface_flux_tendency && return nothing
    # The model's own increment of `mseʲ`, from the same flux and operator.
    (; ᶜh_tot, sfc_conditions, ᶜρʲs) = p.precomputed
    btt = boundary_tendency_scalar(ᶜh_tot, sfc_conditions.ρ_flux_h_tot)
    ᶜΔʲ = @. lazy(-specific(btt, ᶜρʲs.:(1)))
    _mirror_on_updraft!(Yₜ, Y, p, model, 1, ᶜΔʲ, :surface_flux)
    return nothing
end

# ---------------------------------------------------------------------------
# 2. The relaxation at the surface
# ---------------------------------------------------------------------------

"""
    energy_source_copies_boundary_condition_tendency!(Yₜ, Y, p, turbconv_model)

Mirror the updraft's relaxation at the lowest level on the copies. The model
relaxes `mseʲ` toward the buoyant surface value `mse_b = mse̅ + C√σ²` at the
rate `mass_flux_source / max(ρa, ρʲ a_min)` (`edmfx_boundary_condition_tendency!`),
with `mse̅ = h_tot - K` the grid mean's; a tracer gets nothing. Each copy relaxes
at the same rate toward its tag's grid-mean value plus its grid-mean share of
the buoyant excess, `ρe_srcᵢ / ρ + φ̄ᵢ (mse_b - mse̅)`. `φ̄ᵢ` is the share the
sedimentation takes, the partition's renormalized, a source tag's its own. So
the partition's targets add up to `(ρe_tot + c ρ)/ρ + (mse_b - mse̅)`, and no
copy takes the excess as its own: the surface-flux tag gets only its share, as
the water copies' relaxation decides (`water_tag_copies_boundary_condition_tendency!`).
The copies' Jacobian diagonals take the rate. A no-op without copies.
"""
energy_source_copies_boundary_condition_tendency!(Yₜ, Y, p, turbconv_model) =
    nothing
function energy_source_copies_boundary_condition_tendency!(
    Yₜ,
    Y,
    p,
    turbconv_model::PrognosticEDMFX,
)
    model = _energy_source_copies_model(p)
    isnothing(model) && return nothing
    (; params) = p
    (; ᶜρʲs, sfc_mass_flux_sourceʲs, sfc_mse_buoyantʲs, ᶜh_tot, ᶜK) =
        p.precomputed
    FT = eltype(params)
    a_min = CAP.min_area(CAP.turbconv_params(params))
    energy_source_share_norm!(p, Y)
    ᶜnorm = p.scratch.ᶜe_src_share_norm
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    # Each tag's share is written here before its level is read.
    ᶜshare = p.tagging.ᶜenergy_source_copy_sum
    level_values(field) = Fields.field_values(Fields.level(field, 1))
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        values = (;
            ρʲ = level_values(ᶜρʲs.:($j)),
            ρa = level_values(Y.c.sgsʲs.:($j).ρa),
            source = level_values(sfc_mass_flux_sourceʲs.:($j)),
            mse_b = level_values(sfc_mse_buoyantʲs.:($j)),
            h_tot = level_values(ᶜh_tot),
            K = level_values(ᶜK),
            ρ = level_values(Y.c.ρ),
            a_min = FT(a_min),
        )
        _relax_energy_source_copies!(
            Yₜ.c.sgsʲs.:($j),
            Y.c.sgsʲs.:($j),
            Y.c,
            ᶜparent,
            ᶜnorm,
            ᶜshare,
            values,
            level_values,
            model.tags,
        )
    end
    return nothing
end
_relax_energy_source_copies!(
    ᶜsgsʲₜ,
    ᶜsgsʲ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶜshare,
    values,
    level_values,
    ::Tuple{},
) = nothing
function _relax_energy_source_copies!(
    ᶜsgsʲₜ,
    ᶜsgsʲ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶜshare,
    values,
    level_values,
    tags::Tuple,
)
    tag = first(tags)
    (; ρʲ, ρa, source, mse_b, h_tot, K, ρ, a_min) = values
    χ = level_values(updraft_copy_field(ᶜsgsʲ, tag))
    χₜ = level_values(updraft_copy_field(ᶜsgsʲₜ, tag))
    ρe_src = level_values(tag_field(ᶜY, tag))
    ᶜtag_share = _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    @. ᶜshare = ᶜtag_share
    share = level_values(ᶜshare)
    @. χₜ +=
        source * (ρe_src / ρ + share * (mse_b - (h_tot - K)) - χ) /
        max(ρa, ρʲ * a_min)
    return _relax_energy_source_copies!(
        ᶜsgsʲₜ,
        ᶜsgsʲ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶜshare,
        values,
        level_values,
        Base.tail(tags),
    )
end

# ---------------------------------------------------------------------------
# 3. Radiation
# ---------------------------------------------------------------------------

"""
    energy_source_copies_radiation_tendency!(Yₜ, Y, p, radiation_mode)

Mirror the radiation that `radiation_tendency!` gives each updraft's `mseʲ`
under RRTMGP, the grid mean's heating over the updraft's density, on the
copies, by the grid mean's rule for the label `radiation`. The model gives
`mseʲ` no radiation under the other modes, and neither does this. A no-op
without copies.
"""
function energy_source_copies_radiation_tendency!(Yₜ, Y, p, radiation_mode)
    radiation_mode isa RRTMGPI.AbstractRRTMGPMode || return nothing
    turbconv_model = p.atmos.turbconv_model
    turbconv_model isa PrognosticEDMFX || return nothing
    model = _energy_source_copies_model(p)
    isnothing(model) && return nothing
    (; ᶠradiation_flux) = p.radiation
    (; ᶜρʲs) = p.precomputed
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        ᶜΔʲ = @. lazy(-(ᶜdivᵥ(ᶠradiation_flux)) / ᶜρʲs.:($$j))
        _mirror_on_updraft!(Yₜ, Y, p, model, j, ᶜΔʲ, :radiation)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# 4. The updraft's 0M rain-out
# ---------------------------------------------------------------------------

"""
    energy_source_copies_microphysics_tendency!(Yₜ, Y, p, microphysics_model, turbconv_model)

Mirror what the 0M updraft microphysics gives `mseʲ`, `dq_totʲ (e_hlpr - e_int(Tʲ))`, the energy the rain takes out with it relative to the updraft's,
on the copies, by the grid mean's rule for the label `microphysics`. Call it
right after `microphysics_tendency!`, on the implicit or the explicit path,
wherever that runs, as `water_tag_copies_microphysics_tendency!`. It has no
Jacobian entry, as the rain-out of `mseʲ` has none. A no-op without copies and
other than under 0M with prognostic EDMF, where the updraft's microphysics
never changes `mseʲ`.
"""
energy_source_copies_microphysics_tendency!(
    Yₜ,
    Y,
    p,
    microphysics_model,
    turbconv_model,
) = nothing
function energy_source_copies_microphysics_tendency!(
    Yₜ,
    Y,
    p,
    ::EquilibriumMicrophysics0M,
    turbconv_model::PrognosticEDMFX,
)
    model = _energy_source_copies_model(p)
    isnothing(model) && return nothing
    (; ᶜmp_tendencyʲs, ᶜTʲs) = p.precomputed
    thp = CAP.thermodynamics_params(p.params)
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        ᶜΔʲ = @. lazy(
            ᶜmp_tendencyʲs.:($$j).dq_tot_dt * (
                ᶜmp_tendencyʲs.:($$j).e_tot_hlpr -
                TD.internal_energy(thp, ᶜTʲs.:($$j))
            ),
        )
        _mirror_on_updraft!(Yₜ, Y, p, model, j, ᶜΔʲ, :microphysics)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# The copies in the Jacobian, and their residual
# ---------------------------------------------------------------------------

@generated energy_source_copy_field_name(::EnergySourceTag{name}) where {name} =
    :(MatrixFields.FieldName($(QuoteNode(Symbol(:e_src_, name)))))

"""
    energy_source_copy_sgs_names(model)

`Tuple` of the `@name`s (relative to `Y.c.sgsʲs.:(1)`) of the energy source
tags' updraft copies, empty without them. The copies are passive updraft
tracers, so the generic Jacobian blocks of advection, diffusion and entrainment
cover them. The surface relaxation adds to their diagonals. The names come from
the model's type, so building the tuple allocates nothing.
"""
energy_source_copy_sgs_names(::Nothing) = ()
energy_source_copy_sgs_names(model::EnergySourceTaggingModel) =
    _energy_source_copy_sgs_names(
        Val(has_energy_source_updraft_copies(model)),
        model.tags,
    )
_energy_source_copy_sgs_names(::Val{false}, tags) = ()
_energy_source_copy_sgs_names(::Val{true}, tags) =
    unrolled_map(energy_source_copy_field_name, tags)

"""
    energy_source_copy_residual!(ᶜout, Y, p)

Write into `ᶜout` the first updraft's energy minus the partition's copies,
`ρaʲ (Aʲ - Σᵢ∈P χᵢʲ) / ρ`, with `Aʲ = mseʲ + Kʲ - p/ρʲ + c`, per unit mass of
grid-mean air. The mirrors keep the partition's copies changing with `Aʲ` where
`mseʲ` changes and a tracer would not. What they do not cover shows here: the
two advection schemes, the diffusion and hyperdiffusion mirrors, whose
operators differ for the tags and for `mseʲ`, the filter's clamp, and the
exchange between `mseʲ` and `Kʲ`. The copies start from the grid mean's values,
so it starts at the updraft's departure from the grid mean.
"""
function energy_source_copy_residual!(ᶜout, Y, p)
    model = p.atmos.energy_source_tagging_model
    c = _mass_energy(model.offset)
    (; ᶜKʲs, ᶜρʲs, ᶜp) = p.precomputed
    ᶜsgsʲ = Y.c.sgsʲs.:(1)
    ᶜS = p.tagging.ᶜenergy_source_copy_sum
    @. ᶜS = 0
    _accumulate_energy_source_copy_values!(ᶜS, ᶜsgsʲ, model.tags)
    @. ᶜout =
        ᶜsgsʲ.ρa * (ᶜsgsʲ.mse + ᶜKʲs.:(1) - ᶜp / ᶜρʲs.:(1) + c - ᶜS) / Y.c.ρ
    return ᶜout
end
# The partition's copies, summed as they are (the residual's sum, not the
# shares' denominator).
_accumulate_energy_source_copy_values!(ᶜS, ᶜsgsʲ, ::Tuple{}) = nothing
function _accumulate_energy_source_copy_values!(ᶜS, ᶜsgsʲ, tags::Tuple)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜχ = updraft_copy_field(ᶜsgsʲ, tag)
        @. ᶜS += ᶜχ
    end
    return _accumulate_energy_source_copy_values!(ᶜS, ᶜsgsʲ, Base.tail(tags))
end
