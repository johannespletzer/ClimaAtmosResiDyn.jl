#####
##### The water tags follow the parent's implicit increment
#####
##### Under `water_tag_transport: increment` the tags take the parent's own
##### increment of `ρq_tot` in each implicit stage. The parent advects `ρq_tot`
##### vertically in the implicit step, and its sub-grid mass flux, diffusion and
##### sedimentation have Jacobian blocks there. The tags' own implicit terms have
##### fewer blocks, so with one Newton iteration they lag the parent's solve
##### (FINDINGS W21, G3_PLAN 4.3). After each solve the partition's lag is moved
##### to it as a vertical flux, as `correct_energy_source_increment!` does for
##### the energy source tags. The tags' explicit vertical advection is skipped,
##### because the parent's increment carries it.

# The names of the correction's ledger, in the state's order.
const WATER_TAG_LEDGER_NAMES = (:q_tag_inc_left, :q_tag_inc_moved)

"""
    water_tag_increment_ledger_variables(ρq_tot, model)

The ledger of [`correct_water_tag_increment!`](@ref), for a single grid point,
as zeros of the type of `ρq_tot`. Only under `water_tag_transport: increment`,
and `(;)` otherwise:

  - `q_tag_inc_left`: the water the correction has left out of the tags, in
    kg/m³, since the start of the run. In each column it sums to the part of
    the parent's implicit increment of `ρq_tot` that changes the column's total
    and that the tags' own implicit tendencies did not take. That part lands in
    `q_tag_res`.
  - `q_tag_inc_moved`: the water the correction has moved between levels, in
    kg/m³, since the start of the run. It is the part of the mismatch that sums
    to zero in each column: mostly the parent's vertical advection, which the
    tags no longer take explicitly, and the column-neutral part of their lag
    behind the parent's other implicit terms.

Both are prognostic, so the stepper weights each stage's entry as it weights
the tags. They record what the correction intends. A face whose donor cell holds
no partition water moves no tag, so there a cell's actual change differs, and
the difference lands in `q_tag_res` but in neither field.

Their names carry no `ρ` prefix, so `gs_tracer_names` and `is_tracer_var` skip
them, and no transport or limiter reaches them. They are carried through a
restart. The tag names `inc_left` and `inc_moved` are reserved, so no tag's
diagnostic can take these names.
"""
water_tag_increment_ledger_variables(ρq_tot, ::Nothing) = (;)
water_tag_increment_ledger_variables(ρq_tot, model::WaterTaggingModel) =
    follows_water_increment(model) ?
    NamedTuple{WATER_TAG_LEDGER_NAMES}((zero(ρq_tot), zero(ρq_tot))) : (;)

"""
    water_tag_increment_ledger_names(model)

`Tuple` of the state-field `Symbol`s of the correction's ledger:
`(:q_tag_inc_left, :q_tag_inc_moved)` under `water_tag_transport: increment`,
and `()` otherwise. See [`water_tag_increment_ledger_variables`](@ref).
"""
water_tag_increment_ledger_names(model) =
    follows_water_increment(model) ? WATER_TAG_LEDGER_NAMES : ()

"""
    is_water_tag_ledger_name(name)

Whether `name`, a `Symbol`, is a field of the water tags' increment ledger.
"""
is_water_tag_ledger_name(name::Symbol) = name in WATER_TAG_LEDGER_NAMES

"""
    water_tag_follows_increment(p, name)

Whether `name` is a water tag that follows the parent's implicit increment. The
explicit vertical advection skips those tags, since the parent's increment
carries that transport to them.
"""
water_tag_follows_increment(p, name) =
    follows_water_increment(p.atmos.water_tagging_model) &&
    is_water_tag_name(name)

# The fields the correction needs, in `p.tagging`. `dtγ` is the stage's
# implicit weight, which the post-solve hook is not given, so the snapshot
# keeps it. The face area ratio is the energy source tags' own.
_water_tag_increment_cache(Y, model) =
    follows_water_increment(model) ?
    (;
        ᶜq_tag_ρq_tot_snapshot = similar(Y.c.ρ),
        ᶜq_tag_partition_snapshot = similar(Y.c.ρ),
        ᶜq_tag_mismatch = similar(Y.c.ρ),
        ᶜq_tag_abs_mismatch = similar(Y.c.ρ),
        ᶠq_tag_mismatch_integral = Fields.Field(eltype(Y.c.ρ), axes(Y.f)),
        ᶠq_tag_abs_mismatch_integral = Fields.Field(eltype(Y.c.ρ), axes(Y.f)),
        q_tag_mismatch_total = zeros(axes(Fields.level(Y.f, half))),
        q_tag_abs_mismatch_total = zeros(axes(Fields.level(Y.f, half))),
        ᶠq_tag_increment_flux = Fields.Field(CT3{eltype(Y.c.ρ)}, axes(Y.f)),
        ᶠq_tag_area_ratio = _energy_source_face_area_ratio(Y.f),
        q_tag_dtγ = Ref(zero(eltype(Y.c.ρ))),
    ) : (;)

# The correction gives the partition the parent's increment of `ρq_tot`, less
# what the partition's own tendencies moved. So the region tags must partition
# all of the water, where the default transport only warns
# (`_check_region_partition`). That there is a region tag at all is checked
# when the model is built. The largest deviation is taken over every process,
# so that all of them refuse together.
function _check_water_increment_partition(ᶜmasks, names, model)
    follows_water_increment(model) || return nothing
    isempty(names) && return nothing
    masks = map(name -> getproperty(ᶜmasks, name), names)
    mask_sum = reduce((a, b) -> a .+ b, map(parent, masks))
    deviation =
        _collective_maximum(maximum(abs.(mask_sum .- 1)), first(masks))
    deviation > 0.01 && error(
        "`water_tag_transport: increment` needs region tags that partition \
        the domain, and the masks of these sum to 1 only to within \
        $deviation. The correction gives the region tags the parent's \
        increment of `ρq_tot`, so where their masks leave a gap or overlap, \
        the tags would take too much or too little. Use regions that sum to \
        1, such as a region and its complement via `above: false` or \
        `inside: false`.",
    )
    return nothing
end

# The sum of the partition tags of `ᶜY`, plus `dtγ` times that of `ᶜdY`.
function _water_partition_sum!(ᶜsum, ᶜY, ᶜdY, dtγ, tags)
    ᶜsum .= zero(eltype(ᶜsum))
    return _add_water_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, tags)
end
_add_water_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, ::Tuple{}) = ᶜsum
function _add_water_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, tags::Tuple)
    tag = first(tags)
    if _is_partition_tag(tag)
        ᶜtag = tag_field(ᶜY, tag)
        ᶜtag_increment = tag_field(ᶜdY, tag)
        @. ᶜsum += ᶜtag + dtγ * ᶜtag_increment
    end
    return _add_water_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, Base.tail(tags))
end

"""
    snapshot_water_tag_increment!(Y, p, dtγ)

At the start of an implicit stage, keep `ρq_tot`, the sum of the partition
tags and the stage's weight `dtγ`, for [`correct_water_tag_increment!`](@ref).
Called first thing in `initialize_implicit_stage_problem!`, where `Y` is still
the stage value before the solve. A no-op unless the tags follow the parent's
implicit increment.
"""
snapshot_water_tag_increment!(Y, p, dtγ) =
    follows_water_increment(p.atmos.water_tagging_model) ?
    _snapshot_water_tag_increment!(Y, p, dtγ, p.atmos.water_tagging_model) :
    nothing
function _snapshot_water_tag_increment!(Y, p, dtγ, model)
    (; ᶜq_tag_ρq_tot_snapshot, ᶜq_tag_partition_snapshot, q_tag_dtγ) =
        p.tagging
    @. ᶜq_tag_ρq_tot_snapshot = Y.c.ρq_tot
    _water_partition_sum!(ᶜq_tag_partition_snapshot, Y.c, Y.c, false, model.tags)
    q_tag_dtγ[] = dtγ
    return nothing
end

"""
    correct_water_tag_increment!(dY, U, p)

After the Newton solve of an implicit stage, make the partition tags take the
parent's increment of `ρq_tot`. `U` is the solved stage value, and `dY` already
holds the parent's own post-solve correction, which the stepper adds as
`dtγ·dY`.

In each cell, the mismatch `m` is the parent's increment of `ρq_tot` since the
snapshot less the partition's. The part of `m` that changes a column's total
cannot be moved within the column. It is left where it arises, in proportion to
`|m|`, and stays in `q_tag_res`. The rest integrates up the column to a face
flux that is zero at both boundaries, whose divergence is that rest. Each tag
takes the flux times its share in the cell the flux leaves, as with the default
mode's sub-grid mass flux (`_sgs_water_tag_fluxes!`), and the flux is added to
`dY` divided by `dtγ`. The partition's shares add up to one, so the partition
then follows the parent's increment, up to the part left in place. A tag that
carries a source takes its own share of the flux.

The part left in place and the part moved are added to the ledger,
`q_tag_inc_left` and `q_tag_inc_moved` (see
[`water_tag_increment_ledger_variables`](@ref)).
"""
function correct_water_tag_increment!(dY, U, p)
    model = p.atmos.water_tagging_model
    (; ᶜq_tag_ρq_tot_snapshot, ᶜq_tag_partition_snapshot, q_tag_dtγ) =
        p.tagging
    (; ᶜq_tag_mismatch, ᶜq_tag_abs_mismatch, ᶠq_tag_increment_flux) = p.tagging
    (; ᶠq_tag_mismatch_integral, ᶠq_tag_abs_mismatch_integral) = p.tagging
    (; q_tag_mismatch_total, q_tag_abs_mismatch_total) = p.tagging
    (; ᶠq_tag_area_ratio) = p.tagging
    FT = eltype(ᶜq_tag_mismatch)
    dtγ = q_tag_dtγ[]
    ᶜm = ᶜq_tag_mismatch
    # The partition after the stage, with the parent's post-solve correction,
    # which moves no tag. That correction zeroes `dY` and writes only `ρe_tot`
    # and `ρq_tot`, so the `dY` terms of the partition are zero; they are kept
    # so the mismatch stays right if it ever writes more.
    _water_partition_sum!(ᶜm, U.c, dY.c, dtγ, model.tags)
    @. ᶜm =
        (U.c.ρq_tot + dtγ * dY.c.ρq_tot - ᶜq_tag_ρq_tot_snapshot) -
        (ᶜm - ᶜq_tag_partition_snapshot)
    @. ᶜq_tag_abs_mismatch = abs(ᶜm)
    Operators.column_integral_indefinite!(ᶠq_tag_mismatch_integral, ᶜm)
    Operators.column_integral_indefinite!(
        ᶠq_tag_abs_mismatch_integral,
        ᶜq_tag_abs_mismatch,
    )
    Operators.column_integral_definite!(q_tag_mismatch_total, ᶜm)
    Operators.column_integral_definite!(
        q_tag_abs_mismatch_total,
        ᶜq_tag_abs_mismatch,
    )
    # Upward positive. It is zero at the bottom face and, having taken out the
    # column's total, at the top face too. The integrals are per unit area of
    # the bottom face, and the divergence weights each face by its own area.
    # Under a deep atmosphere the faces grow with height, so the flux is
    # scaled by the bottom face's area over its own. On a flat grid that is 1.
    @. ᶠq_tag_increment_flux = CT3(
        Geometry.WVector(
            -(
                ᶠq_tag_mismatch_integral -
                ifelse(
                    q_tag_abs_mismatch_total > 0,
                    q_tag_mismatch_total / q_tag_abs_mismatch_total,
                    FT(0),
                ) * ᶠq_tag_abs_mismatch_integral
            ) / dtγ * ᶠq_tag_area_ratio,
        ),
    )
    water_tag_share_norm!(p, U)
    _sgs_water_tag_fluxes!(
        dY.c,
        U.c,
        p.scratch.ᶜtagging_q_share_norm,
        ᶠq_tag_increment_flux,
        model.tags,
    )
    # The ledger. What is left in place stays out of the tags, and the rest is
    # what the flux moved. The stepper adds `dtγ·dY`, as it does for the tags.
    @. ᶜq_tag_abs_mismatch *= ifelse(
        q_tag_abs_mismatch_total > 0,
        q_tag_mismatch_total / q_tag_abs_mismatch_total,
        FT(0),
    )
    @. dY.c.q_tag_inc_left += ᶜq_tag_abs_mismatch / dtγ
    @. dY.c.q_tag_inc_moved += (ᶜm - ᶜq_tag_abs_mismatch) / dtγ
    return nothing
end

"""
    water_tag_extra_audit(Y, p, model, scale)

The water family's own columns of `water_tag_audit.csv`: those of
[`water_tag_edmf_audit`](@ref) under prognostic EDMF, and under
`water_tag_transport: increment` the integrals of the increment's ledger since
the start of the run, over the domain as `scale` is: `increment_left`, what it
left out of the tags, which is signed and lands in the closure residual;
`increment_left_gross`, the same with each cell's absolute value; and
`increment_moved_gross`, the absolute value of what it moved between levels.
The two "gross" columns are gross over the cells but net over time in each
cell, as the energy source tags' are: a cell whose ledger went up and down
again counts only what is left. Each also over `scale`.

Always, the gross throughput of the cache ledgers since the segment started
(`tag_throughput.jl`): `fix_gross` and `fix_events`, for the limiters' and the
constraints' corrections of the tags, and with copies `copy_repair_events`,
the copies' repair's count, beside the EDMF audit's `copy_repair`. The gross
is an amount over the domain, a transfer counting once out and once in, and
also over `scale`. Collective, as `tag_audit` is.
"""
function water_tag_extra_audit(Y, p, model, scale)
    per_scale(x) = iszero(scale) ? zero(x) : x / scale
    fix_gross = tag_gross_total(p.tagging.ᶜwater_fix_gross)
    throughput = (;
        fix_gross,
        fix_gross_relative = per_scale(fix_gross),
        fix_events = tag_event_total(p.tagging.ᶜwater_fix_count),
        _water_copy_events(p, model)...,
    )
    edmf = water_tag_edmf_audit(Y, p, model, scale)
    columns = isnothing(edmf) ? throughput : merge(edmf, throughput)
    follows_water_increment(model) || return columns
    return merge(
        columns,
        _water_tag_ledger_columns(Y, p.scratch.ᶜtemp_scalar, scale),
    )
end
_water_copy_events(p, model) =
    has_water_tag_updraft_copies(model) ?
    (; copy_repair_events = tag_event_total(p.tagging.ᶜwater_upfix_count)) :
    (;)
function _water_tag_ledger_columns(Y, ᶜtmp, scale)
    per_scale(x) = iszero(scale) ? zero(x) : x / scale
    increment_left = sum(Y.c.q_tag_inc_left)
    @. ᶜtmp = abs(Y.c.q_tag_inc_left)
    increment_left_gross = sum(ᶜtmp)
    @. ᶜtmp = abs(Y.c.q_tag_inc_moved)
    increment_moved_gross = sum(ᶜtmp)
    return (;
        increment_left,
        increment_left_relative = per_scale(increment_left),
        increment_left_gross,
        increment_left_gross_relative = per_scale(increment_left_gross),
        increment_moved_gross,
        increment_moved_gross_relative = per_scale(increment_moved_gross),
    )
end

"""
    WaterTagIncrementCorrection(post)

The post-solve hook when the water tags follow the parent's implicit increment.
It runs `post`, which sets every field of `dY`, and then
[`correct_water_tag_increment!`](@ref). `post` is the parent's own post-solve
correction, or that wrapped in the energy source tags' correction
(`EnergySourceIncrementCorrection`), so one hook serves both families. It is
never `nothing`: [`check_water_tag_increment_supported`](@ref) refuses the mode
where the parent has no correction.
"""
struct WaterTagIncrementCorrection{F}
    post::F
end
function (correction::WaterTagIncrementCorrection)(dY, U, p, t)
    correction.post(dY, U, p, t)
    correct_water_tag_increment!(dY, U, p)
    return nothing
end

"""
    tag_post_implicit(post, atmos)

The post-solve hook to give the stepper: `post` itself, or wrapped in the
energy source tags' correction and then the water tags', for each family that
follows the parent's implicit increment. The energy correction writes only the
energy tags and its own ledger, and the water correction only the water tags
and its own, so their order does not matter.
"""
tag_post_implicit(post, atmos) =
    water_tag_post_implicit(energy_source_post_implicit(post, atmos), atmos)

"""
    water_tag_post_implicit(post, atmos)

`post` itself, or wrapped in [`WaterTagIncrementCorrection`](@ref) when the
water tags follow the parent's implicit increment.
"""
water_tag_post_implicit(post, atmos) =
    follows_water_increment(atmos.water_tagging_model) ?
    WaterTagIncrementCorrection(post) : post

"""
    check_water_tag_increment_supported(atmos, ode_algo, T_imp!, T_post_imp!)

Refuse `water_tag_transport: increment` where it cannot follow the parent, or
where following it would change the model. The conditions are those of the
energy source tags' increment (`check_energy_source_increment_supported`), and
the same check decides them:

  - every implicit tendency must go through a Newton solve, after which the
    tags take the parent's increment. So the algorithm must be an IMEX
    algorithm with a Newton method, and the flow must not be prescribed. A
    stage whose implicit diagonal is zero must not use the implicit tendency
    in a later stage or in the step's result. The ARS algorithms, such as the
    default ARS343 and ARS222, meet this;
  - the parent must have a post-solve correction of its own, which it has
    unless `energy_q_tot_upwinding` is `none`. A hook the parent does not have
    would make the stepper refresh the implicit cache after each solve, which
    the model's constraints read, and so change the model's fields.

Called when the integrator is built. A no-op for the default transport.
"""
check_water_tag_increment_supported(atmos, ode_algo, T_imp!, T_post_imp!) =
    follows_water_increment(atmos.water_tagging_model) ?
    _check_water_tag_increment_supported(ode_algo, T_imp!, T_post_imp!) :
    nothing
function _check_water_tag_increment_supported(ode_algo, T_imp!, T_post_imp!)
    !isnothing(T_imp!) && isnothing(T_post_imp!) &&
        error(
            "`water_tag_transport: increment` takes the parent's increment in \
            a post-solve hook. With `energy_q_tot_upwinding: none` the parent \
            has no post-solve correction of its own. A hook would make the \
            stepper refresh the implicit cache after each solve, which the \
            model's constraints read, so the model's fields would change. Use \
            an `energy_q_tot_upwinding` other than `none`, such as the default \
            `vanleer_limiter`, or `water_tag_transport: tracer`.",
        )
    reason = implicit_increment_gap(ode_algo, T_imp!)
    isnothing(reason) && return nothing
    error(
        "`water_tag_transport: increment` needs every implicit tendency to go \
        through a Newton solve, after which the tags take the parent's \
        increment. Here $reason, so the tags would miss that part of the \
        parent's implicit transport. Use an algorithm that solves every stage \
        it uses, such as the default ARS343, or `water_tag_transport: tracer`.",
    )
end
