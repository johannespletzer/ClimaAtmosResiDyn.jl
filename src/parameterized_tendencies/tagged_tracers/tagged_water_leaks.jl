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
"""
function water_tag_leak!(ᶜleak, Y, p, path::Val)
    @. ᶜleak = 0
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

#####
##### The correction of the EDMF vertical diffusion's leak (WP4c)
#####
##### WP4c's gate retained two corrections (FINDINGS W40 on the record branch):
##### the grid mean's `vdiff` and the updrafts' `diffusion_up`. Each gives the
##### tags back the diffusion of the rain and snow, which the parent does not
##### diffuse. Each tag takes back the diffusion of its own share of the rain
##### and snow, the share the sedimentation takes it by, so the leak is charged
##### to the tags whose water leaked. Without the correction the follower
##### absorbs the leak and spreads it by the shares of the cells its flux
##### leaves. design/WP4C_CORRECTIONS.md on the record branch.

"""
    correct_water_tag_diffusion_leak!(Yₜ, Y, p, ᶠρK_h, apply_sgs_updraft)

Under `water_tag_leak_correction: true`, add to each water tag's tendency
`∇·(ρK_h ∇(ψᵢ q_p))`, the EDMF vertical diffusion of its share `ψᵢ` of the rain
and snow `q_p = q_tot - q_tot_eff`. The tags diffuse their whole value at
`K_h + K_e`, and the parent diffuses `q_tot_eff` at `K_h` and `q_tot` at `K_e`.
So without the correction the partition gains `-∇·(ρK_h ∇q_p)` that the parent
does not, the leak `q_tag_leak_vdiff`.

`ψᵢ` is the share the sedimentation mirror takes a tag's rain and snow by: a
partition tag's clamped share renormalized over the partition, a source tag's
own clamped share. The partition's shares sum to one wherever it holds water, so
the partition's corrections sum to `∇·(ρK_h ∇q_p)`, the leak with the opposite
sign, and its diffusion is the parent's. Where the partition holds no water the
shares are zero and the leak there is not corrected. It lands in `q_tag_res`, or
under the follower in `q_tag_inc_moved`, as before. A source tag's correction
takes back its own share, so its diffusion moves only the water that the parent
diffuses too.

With `apply_sgs_updraft`, the updrafts' mirror of the diffusion is on, and with
updraft copies each copy takes its tag's correction per unit mass, `/ρ`, as it
takes its tag's diffusion. So the copies' sum mirrors `q_totʲ`'s diffusion too,
and their repair no longer takes out the `diffusion_up` leak.

`ᶠρK_h` is the face field `ρK_h` the parent's water diffusion uses. Called from
`edmfx_sgs_diffusive_flux_tendency!` after its tracer loop, so it is implicit
where the diffusion is. It has no Jacobian block, so with one Newton iteration
it is taken at the stage's first guess, and under `water_tag_transport: increment` the follower moves what differs.

Each correction is added to its ledgers: `q_tag_led_leaknet`, the partition's
correction, and with copies `q_tag_led_upleaknet`, the copies' times `ρaʲ`; and
under `water_tag_ledger_per_tag: true` each tag's `q_tag_led_leak_<name>` and
`q_tag_led_upleak_<name>`. They are state fields, so the stepper weights them as
it weights the tags. Only the tags and their ledgers change. A no-op without the
key.
"""
correct_water_tag_diffusion_leak!(Yₜ, Y, p, ᶠρK_h, apply_sgs_updraft) =
    _correct_water_tag_diffusion_leak!(
        Yₜ,
        Y,
        p,
        ᶠρK_h,
        apply_sgs_updraft,
        p.atmos.water_tagging_model,
    )
_correct_water_tag_diffusion_leak!(Yₜ, Y, p, ᶠρK_h, apply_sgs_updraft, ::Nothing) =
    nothing
function _correct_water_tag_diffusion_leak!(
    Yₜ,
    Y,
    p,
    ᶠρK_h,
    apply_sgs_updraft,
    model::WaterTaggingModel,
)
    has_water_tag_leak_correction(model) || return nothing
    apply_water_tag_leak_correction!(
        Yₜ,
        Y,
        p,
        ᶠρK_h,
        p.scratch.ᶜtagging_q_leak_correction,
        water_tag_leak_ledgers(Yₜ, model),
        apply_sgs_updraft && _has_water_tag_copies(p, p.atmos.turbconv_model),
    )
    return nothing
end

"""
    water_tag_leak_ledgers(Yₜ, model)

The fields of the tendency `Yₜ` that [`apply_water_tag_leak_correction!`](@ref)
adds the corrections to: `net`, `q_tag_led_leaknet`; `upnet`,
`q_tag_led_upleaknet` with copies; and `per_tag` and `per_tag_up`, the
[`TagLedgerView`](@ref)s of each tag's own ledgers under
`water_tag_ledger_per_tag: true`. `nothing` for each that the model does not
have, and `nothing` without the correction.
"""
water_tag_leak_ledgers(Yₜ, model) =
    has_water_tag_leak_correction(model) ?
    (;
        net = Yₜ.c.q_tag_led_leaknet,
        upnet = has_water_tag_updraft_copies(model) ? Yₜ.c.q_tag_led_upleaknet :
                nothing,
        per_tag = has_water_tag_ledger_per_tag(model) ? TagLedgerView{:leak}(Yₜ.c) :
                  nothing,
        per_tag_up = has_water_tag_ledger_per_tag(model) &&
                     has_water_tag_updraft_copies(model) ?
                     TagLedgerView{:upleak}(Yₜ.c) : nothing,
    ) : nothing

"""
    apply_water_tag_leak_correction!(Yₜ, Y, p, ᶠρK_h, ᶜcorrection, ledgers,
                                     mirror)

The correction of [`correct_water_tag_diffusion_leak!`](@ref), whatever the
model's key: each tag's correction is written into `ᶜcorrection`, a scratch
center field, and added to the tag's tendency, to `ledgers`
([`water_tag_leak_ledgers`](@ref), or `nothing` for none), and where `mirror` is
`true` to each updraft's copy, per unit mass. The tests call it on a model
without the key.
"""
function apply_water_tag_leak_correction!(
    Yₜ,
    Y,
    p,
    ᶠρK_h,
    ᶜcorrection,
    ledgers,
    mirror,
)
    model = p.atmos.water_tagging_model
    water_tag_share_norm!(p, Y)
    ᶜnorm = p.scratch.ᶜtagging_q_share_norm
    ᶜq_p = _leaking_water(Y, p)
    n = mirror ? n_mass_flux_subdomains(p.atmos.turbconv_model) : 0
    _apply_water_tag_leak_correction!(
        Yₜ,
        Y,
        ᶠρK_h,
        ᶜq_p,
        ᶜnorm,
        ᶜcorrection,
        ledgers,
        n,
        model.tags,
    )
    return nothing
end

_apply_water_tag_leak_correction!(
    Yₜ,
    Y,
    ᶠρK_h,
    ᶜq_p,
    ᶜnorm,
    ᶜcorrection,
    ledgers,
    n,
    ::Tuple{},
) =
    nothing
function _apply_water_tag_leak_correction!(
    Yₜ,
    Y,
    ᶠρK_h,
    ᶜq_p,
    ᶜnorm,
    ᶜcorrection,
    ledgers,
    n,
    tags::Tuple,
)
    tag = first(tags)
    ᶜshare = _water_tag_share_field(Y.c, ᶜnorm, tag)
    ᶜdivergence =
        ᶜdiffusive_flux_divergenceᵥ(ᶠρK_h, (@. lazy(ᶜshare * ᶜq_p)))
    @. ᶜcorrection = ᶜdivergence
    ᶜρq_tagₜ = tag_field(Yₜ.c, tag)
    @. ᶜρq_tagₜ += ᶜcorrection
    _add_leak_ledgers!(ledgers, tag, ᶜcorrection)
    for j in 1:n
        ᶜχʲₜ = updraft_copy_field(Yₜ.c.sgsʲs.:($j), tag)
        @. ᶜχʲₜ += ᶜcorrection / Y.c.ρ
        _add_updraft_leak_ledgers!(
            ledgers,
            tag,
            (@. lazy(ᶜcorrection * Y.c.sgsʲs.:($$j).ρa / Y.c.ρ)),
        )
    end
    return _apply_water_tag_leak_correction!(
        Yₜ,
        Y,
        ᶠρK_h,
        ᶜq_p,
        ᶜnorm,
        ᶜcorrection,
        ledgers,
        n,
        Base.tail(tags),
    )
end

# The partition's correction goes to the mechanism's ledger, and every tag's to
# its own. `_is_partition_tag` resolves on the tag's type.
_add_leak_ledgers!(::Nothing, tag, ᶜchange) = nothing
function _add_leak_ledgers!(ledgers, tag, ᶜchange)
    if _is_partition_tag(tag)
        ᶜnet = ledgers.net
        @. ᶜnet += ᶜchange
    end
    add_to_tag_ledger!(ledgers.per_tag, tag, ᶜchange)
    return nothing
end
_add_updraft_leak_ledgers!(::Nothing, tag, change) = nothing
function _add_updraft_leak_ledgers!(ledgers, tag, change)
    if _is_partition_tag(tag) && !isnothing(ledgers.upnet)
        ᶜupnet = ledgers.upnet
        @. ᶜupnet += change
    end
    add_to_tag_ledger!(ledgers.per_tag_up, tag, change)
    return nothing
end
