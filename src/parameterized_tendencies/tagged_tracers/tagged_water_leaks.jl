#####
##### The water tags' leaks, in closed form
#####
##### Six paths move the water tags as passive tracers, on their whole value.
##### They move the parent only by the water that diffuses,
##### `q_tot_eff = q_tot - q_rai - q_sno` (`ᶜdiffusing_water`). The
##### hyperdiffusion also takes the parent as a perturbation from the reference
##### profile `q_tot_r(p)`, and the tags not. So on each path the tags' sum
##### drifts from the parent at a rate that the state alone decides (G3_PLAN
##### 4.2). These functions compute that rate, to size each path before any
##### correction is written. They only read the state and write scratch, so a
##### run's fields do not change.

"""
    WATER_TAG_LEAK_PATHS

The paths [`water_tag_leak!`](@ref) computes a leak for:

  - `vdiff`: the grid mean's vertical diffusion. That is the EDMF diffusive
    flux, at `K_h`, and the boundary-layer diffusion;
  - `hdiff`: the grid mean's horizontal EDMF diffusive flux, on the sphere;
  - `hyperdiff`: the grid mean's hyperdiffusion;
  - `sponge`: the viscous sponge;
  - `diffusion_up`: the updrafts' mirror of the EDMF diffusive fluxes,
    vertical and horizontal, on the water tags' updraft copies;
  - `hyperdiff_up`: the updrafts' hyperdiffusion, on the copies.
"""
const WATER_TAG_LEAK_PATHS =
    (:vdiff, :hdiff, :hyperdiff, :sponge, :diffusion_up, :hyperdiff_up)

"""
    water_tag_leak!(ᶜleak, Y, p, ::Val{path})

Write into `ᶜleak` the rate at which `path` would move the sum of a partition
of water tags away from the parent if the partition were exactly closed, per
unit mass of grid-mean air, in kg kg⁻¹ s⁻¹. It is the path's tendency of
`Σᵢ ρq_tagᵢ` minus its tendency of `ρq_tot`, over `ρ`, evaluated at
`Σᵢ ρq_tagᵢ = ρq_tot`. So it is the source the path adds to the closure
residual. It does not read the tags: the path's transport of a residual already
there, `L(Σᵢ q_tagᵢ - q_tot)` for the path's operator `L`, is not in it. A
positive value means the tags gain water the parent does not.

For the updrafts' paths, the tendency is the copies' `Σᵢ χᵢʲ` minus `q_totʲ`,
evaluated at `Σᵢ χᵢʲ = q_totʲ`, times `ρaʲ / ρ`, summed over the updrafts. That is the water the copies gain
that the updraft does not, per unit mass of grid-mean air. The copies' repair
takes it out again, into `q_tag_upfix_<name>`.

Zero where the path is off, or on a column for the horizontal paths. On the
sphere the result is DSSed, as a tendency diagnostic is. See
[`WATER_TAG_LEAK_PATHS`](@ref) for the paths.

Zero under `water_tag_precipitation: true`. There the tags' `ρq_tag_<name>`
fields hold the diffusing water and move as it does, and the hyperdiffusion
takes each tag's share of the reference profile, so no path leaks
(`prep_water_tag_hyperdiffusion!`). The copies are refused with the key.
"""
function water_tag_leak!(ᶜleak, Y, p, path::Val)
    @. ᶜleak = 0
    has_water_tag_precipitation(p.atmos.water_tagging_model) ||
        _water_tag_leak!(ᶜleak, Y, p, path)
    do_dss(axes(Y.c)) && Spaces.weighted_dss!(ᶜleak)
    return ᶜleak
end

# The water the parent does not move on these paths, as the tags' sum minus
# the diffusing water. Zero without rain and snow.
function _leaking_water(Y, p)
    ᶜq_tot_eff = ᶜdiffusing_water(Y, p)
    return @. lazy(specific(Y.c.ρq_tot, Y.c.ρ) - ᶜq_tot_eff)
end

# The updraft's counterpart, `q_raiʲ + q_snoʲ`, or zero without them.
_leaking_updraft_water(ᶜsgsʲ, microphysics_model) =
    microphysics_model isa
    Union{NonEquilibriumMicrophysics1M, NonEquilibriumMicrophysics2M} ?
    (@. lazy(ᶜsgsʲ.q_rai + ᶜsgsʲ.q_sno)) : (@. lazy(0 * ᶜsgsʲ.q_tot))

_edmf_diffuses(p, ::Union{EDOnlyEDMFX, PrognosticEDMFX}) =
    p.atmos.edmfx_model.sgs_diffusive_flux
_edmf_diffuses(p, turbconv_model) = false
_edmf_diffuses_horizontally(Y, p, ::Union{EDOnlyEDMFX, PrognosticEDMFX}) =
    p.atmos.edmfx_model.sgs_diffusive_flux_horizontal isa Val{true} &&
    !iscolumn(axes(Y.c))
_edmf_diffuses_horizontally(Y, p, turbconv_model) = false

# The EDMF vertical flux diffuses the tags at `K_h + K_e` and the parent at
# `K_h` on `q_tot_eff` plus `K_e` on `q_tot` (`edmfx_sgs_diffusive_flux_tendency!`).
function _add_edmf_vertical_leak!(ᶜleak, Y, p)
    ᶠρK_h = @. lazy(ᶠinterp(Y.c.ρ) * p.precomputed.ᶠK_h)
    ᶜdivergence = ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, _leaking_water(Y, p))
    @. ᶜleak -= ᶜdivergence / Y.c.ρ
    return nothing
end

# The horizontal flux diffuses the tags at `K_h` and the parent at `K_h` on
# `q_tot_eff` (`edmfx_sgs_horizontal_diffusive_flux_tendency!`).
function _add_edmf_horizontal_leak!(ᶜleak, Y, p)
    (; ᶜK_h_h) = p.precomputed
    ᶜq_p = _leaking_water(Y, p)
    @. ᶜleak += wdivₕ(Y.c.ρ * ᶜK_h_h * gradₕ(ᶜq_p)) / Y.c.ρ
    return nothing
end

function _water_tag_leak!(ᶜleak, Y, p, ::Val{:vdiff})
    _edmf_diffuses(p, p.atmos.turbconv_model) &&
        _add_edmf_vertical_leak!(ᶜleak, Y, p)
    _add_boundary_layer_leak!(ᶜleak, Y, p, p.atmos.vertical_diffusion)
    return nothing
end

_add_boundary_layer_leak!(ᶜleak, Y, p, vertical_diffusion) = nothing
# As `vertical_diffusion_boundary_layer_tendency!`: the same harmonic-mean face
# diffusivity for the tags and for `q_tot_eff`.
function _add_boundary_layer_leak!(
    ᶜleak,
    Y,
    p,
    vertical_diffusion::Union{VerticalDiffusion, DecayWithHeightDiffusion},
)
    FT = eltype(Y)
    ᶜK_h = p.scratch.ᶜtemp_scalar
    if vertical_diffusion isa DecayWithHeightDiffusion
        ᶜK_h .= ᶜcompute_eddy_diffusivity_coefficient(Y.c.ρ, vertical_diffusion)
    else
        ᶜK_h .= ᶜcompute_eddy_diffusivity_coefficient(
            Y.c.uₕ,
            p.precomputed.ᶜp,
            vertical_diffusion,
        )
    end
    ᶠρK = @. lazy(ᶠinterp(Y.c.ρ) / ᶠinterp(1 / max(ᶜK_h, eps(FT))))
    ᶜq_p = _leaking_water(Y, p)
    @. ᶜleak -= ᶜdiffdivᵥ(-(ᶠρK * ᶠgradᵥ(ᶜq_p))) / Y.c.ρ
    return nothing
end

function _water_tag_leak!(ᶜleak, Y, p, ::Val{:hdiff})
    _edmf_diffuses_horizontally(Y, p, p.atmos.turbconv_model) &&
        _add_edmf_horizontal_leak!(ᶜleak, Y, p)
    return nothing
end

# The tags hyperdiffuse on `∇²q_tag`, the parent on `∇²(q_tot_eff - q_tot_r)`
# (`apply_tracer_hyperdiffusion_tendency!`). The Laplacian is DSSed before the
# outer operator, as in the model.
function _water_tag_leak!(ᶜleak, Y, p, ::Val{:hyperdiff})
    hyperdiff = p.atmos.hyperdiff
    (isnothing(hyperdiff) || iscolumn(axes(Y.c))) && return nothing
    thermo_params = CAP.thermodynamics_params(p.params)
    (; ν₄_scalar) = ν₄(hyperdiff, Y)
    (; ᶜp) = p.precomputed
    ᶜq_p = _leaking_water(Y, p)
    ᶜ∇² = p.scratch.ᶜtemp_scalar
    @. ᶜ∇² = wdivₕ(gradₕ(ᶜq_p + q_tot_r(thermo_params, ᶜp)))
    do_dss(axes(Y.c)) && Spaces.weighted_dss!(ᶜ∇²)
    @. ᶜleak -= ν₄_scalar * wdivₕ(Y.c.ρ * gradₕ(ᶜ∇²)) / Y.c.ρ
    return nothing
end

# The sponge diffuses the tags on their value and the parent on `q_tot_eff`
# (`viscous_sponge_tendency!`).
function _water_tag_leak!(ᶜleak, Y, p, ::Val{:sponge})
    sponge = p.atmos.viscous_sponge
    (isnothing(sponge) || iscolumn(axes(Y.c))) && return nothing
    ᶜtendency = viscous_sponge_tendency_tracer(Y.c.ρ, _leaking_water(Y, p), sponge)
    @. ᶜleak += ᶜtendency / Y.c.ρ
    return nothing
end

# Each copy takes its grid-mean tag's specific diffusive tendency, and `q_totʲ`
# the parent's. So the copies' sum leaks as the grid mean's does, on the EDMF
# paths the updrafts mirror.
function _water_tag_leak!(ᶜleak, Y, p, ::Val{:diffusion_up})
    turbconv_model = p.atmos.turbconv_model
    _has_water_tag_copies(p, turbconv_model) || return nothing
    (; edmfx_model) = p.atmos
    ᶜmirror = p.scratch.ᶜtemp_scalar_2
    @. ᶜmirror = 0
    edmfx_model.vertical_diffusion && _edmf_diffuses(p, turbconv_model) &&
        _add_edmf_vertical_leak!(ᶜmirror, Y, p)
    edmfx_model.horizontal_diffusion isa Val{true} &&
        _edmf_diffuses_horizontally(Y, p, turbconv_model) &&
        _add_edmf_horizontal_leak!(ᶜmirror, Y, p)
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        @. ᶜleak += ᶜmirror * Y.c.sgsʲs.:($$j).ρa / Y.c.ρ
    end
    return nothing
end

# The copies hyperdiffuse on `∇²χᵢʲ`, `q_totʲ` on `∇²(q_tot_effʲ - q_tot_r)`,
# without density weighting.
function _water_tag_leak!(ᶜleak, Y, p, ::Val{:hyperdiff_up})
    turbconv_model = p.atmos.turbconv_model
    hyperdiff = p.atmos.hyperdiff
    _has_water_tag_copies(p, turbconv_model) || return nothing
    (isnothing(hyperdiff) || iscolumn(axes(Y.c))) && return nothing
    thermo_params = CAP.thermodynamics_params(p.params)
    (; ν₄_scalar) = ν₄(hyperdiff, Y)
    (; ᶜp) = p.precomputed
    ᶜ∇² = p.scratch.ᶜtemp_scalar
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        ᶜsgsʲ = Y.c.sgsʲs.:($j)
        ᶜq_pʲ = _leaking_updraft_water(ᶜsgsʲ, p.atmos.microphysics_model)
        @. ᶜ∇² = wdivₕ(gradₕ(ᶜq_pʲ + q_tot_r(thermo_params, ᶜp)))
        do_dss(axes(Y.c)) && Spaces.weighted_dss!(ᶜ∇²)
        @. ᶜleak -= ν₄_scalar * wdivₕ(gradₕ(ᶜ∇²)) * ᶜsgsʲ.ρa / Y.c.ρ
    end
    return nothing
end

_has_water_tag_copies(p, ::PrognosticEDMFX) =
    has_water_tag_updraft_copies(p.atmos.water_tagging_model)
_has_water_tag_copies(p, turbconv_model) = false
