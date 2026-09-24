#####
##### Energy source tags
#####
##### Each tag adds one grid-scale prognostic field `Y.c.ρe_src_<name>` holding
##### part of the total moist energy `ρe_tot`. The `energy_source_tags` config
##### key switches them on. Types live in `types.jl` and config parsing in
##### `config/tracer_config.jl`. The physics is written up in
##### `docs/src/energy_source_tags.md`.
#####
##### This is the energy counterpart of the water tags in `tagged_water.jl`, and
##### it is a different quantity from `ρe_tag_*` in `tagged_tracers.jl`. A source
##### tag holds energy that is present now, traced back to where it came from,
##### which holds only where the partitioned total is positive and the tag is
##### non-negative. That total is `ρe_tot`, or `ρe_tot + c·ρ` under an offset.
##### An `ρe_tag_*` tag configured with `source` is a signed process tag: it
##### holds the signed increment one process applied. That is not the same as
##### the process-change record, which is the separate `prc_*` family in
##### `process_record.jl`. Both are useful; they answer different questions.
#####
##### This file carries the state, the masks, the transport hook-up and the
##### attribution rule. Production is shared out by region mask and loss is
##### taken from each tag in proportion to what it already holds, which is what
##### makes a tag an amount of energy present rather than a running total. A
##### partition of region tags closes under pure dynamics, and the rule is
##### built to keep that true once sources and sinks are attributed.
#####
##### `energy_source_tag_offset` gives the tags a total the model never uses,
##### `ρe_tot + c·ρ`, which can be positive where `ρe_tot` is not. Every place
##### below that reads the parent goes through `energy_source_parent` or one of
##### its field forms, so without an offset the arithmetic is exactly as before.
#####
##### Tag names are ρ-weighted, so `gs_tracer_names(Y)` picks them up and the
##### usual tracer machinery supplies advection, hyperdiffusion, sponges,
##### vertical eddy diffusion and the implicit-Jacobian blocks. Leave transport
##### to that machinery. Attributing it here would count it twice.
#####
##### Masks are static in space. Evaluate them once when building the cache,
##### outside any per-timestep broadcast.

# ============================================================================
# Names and state
# ============================================================================

# Build a single-entry NamedTuple `(; ρe_src_<name> = value)`. As for the other
# two families, the field name is computed at compile time from the tag's type
# parameter, so this is type-stable and GPU-compatible.
@generated function tag_entry(::EnergySourceTag{name}, value) where {name}
    field_name = Symbol(:ρe_src_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end

# Compile-time lookup of the entry `ρe_src_<name>` in a state or tendency
# `Field` (e.g. `Yₜ.c`) or in the mask cache `NamedTuple`.
@generated tag_field(obj, ::EnergySourceTag{name}) where {name} =
    :(obj.$(Symbol(:ρe_src_, name)))

# The same for a tag's updraft copy, `e_src_<name>` in `Y.c.sgsʲs.:(j)`. Like
# every updraft tracer, it holds the specific value.
@generated function updraft_copy_entry(::EnergySourceTag{name}, value) where {name}
    field_name = Symbol(:e_src_, name)
    return :(NamedTuple{($(QuoteNode(field_name)),)}((value,)))
end
@generated updraft_copy_field(obj, ::EnergySourceTag{name}) where {name} =
    :(obj.$(Symbol(:e_src_, name)))

"""
    energy_source_updraft_copy_variables(gs, model)

The energy source tags' copies for one updraft at a single grid point, `(; e_src_<name₁> = ..., ...)`, under `energy_source_tag_updraft_copy: true`, and
`(;)` otherwise. `gs` holds the grid-scale center variables of that point. Each
copy starts as its tag's specific value, `ρe_src_<name> / ρ`, so the updrafts
begin with the grid mean's composition, as they begin with its other tracers.
"""
energy_source_updraft_copy_variables(gs, model) =
    _energy_source_updraft_copy_variables(
        Val(has_energy_source_updraft_copies(model)),
        gs,
        model,
    )
_energy_source_updraft_copy_variables(::Val{false}, gs, model) = (;)
_energy_source_updraft_copy_variables(::Val{true}, gs, model) =
    _energy_source_copy_entries(gs, model.tags)
_energy_source_copy_entries(gs, ::Tuple{}) = (;)
_energy_source_copy_entries(gs, tags::Tuple) = merge(
    updraft_copy_entry(first(tags), tag_field(gs, first(tags)) / gs.ρ),
    _energy_source_copy_entries(gs, Base.tail(tags)),
)

"""
    energy_source_updraft_copy_names(model)

`Tuple` of the `Symbol`s (`:e_src_<name>`) of the tags' updraft copies, empty
without them.
"""
energy_source_updraft_copy_names(model) =
    has_energy_source_updraft_copies(model) ?
    Tuple(Symbol(:e_src_, tag_name(tag)) for tag in model.tags) : ()

# Region-less tags carry no mask, exactly as for the other two families.
_tag_mask_entry(ᶜcoord, ::EnergySourceTag{name, Nothing}) where {name} = (;)
_tag_mask_entry(ᶜcoord, tag::EnergySourceTag) =
    tag_entry(tag, region_mask.(Ref(tag.region), ᶜcoord))

"""
    energy_source_tagging_variables(ρe_parent, local_geometry, model)

NamedTuple of tagged prognostic fields `(; ρe_src_<name₁> = ..., ...)` for a
single grid point, to be splatted into the center prognostic state alongside the
other grid-scale variables. Returns `(;)` when energy source tagging is disabled
(`model === nothing`).

`ρe_parent` is the total the tags partition, from `energy_source_parent`:
`ρe_tot`, or `ρe_tot + c·ρ` with an offset. Initial values come from
`tag_initial_value`, so a pure region tag starts as its masked share of that
total and a tag carrying a source starts at zero.
"""
energy_source_tagging_variables(ρe_parent, local_geometry, ::Nothing) = (;)
energy_source_tagging_variables(
    ρe_parent,
    local_geometry,
    model::EnergySourceTaggingModel,
) = _energy_source_variables(ρe_parent, local_geometry.coordinates, model.tags)

_energy_source_variables(ρe_parent, coord, ::Tuple{}) = (;)
_energy_source_variables(ρe_parent, coord, tags::Tuple) = merge(
    tag_entry(first(tags), tag_initial_value(first(tags), ρe_parent, coord)),
    _energy_source_variables(ρe_parent, coord, Base.tail(tags)),
)

"""
    energy_source_parent(ρe_tot, ρ, model)

The total the energy source tags partition at one point: `ρe_tot` itself, or
`ρe_tot + c·ρ` when `model` carries an offset `c` in J/kg.

The model never uses this total. Only the tags see it, so an offset changes what
they split and leaves the simulated atmosphere exactly as it was. That is the
reason for it. `ρe_tot` has no physical zero, and under the default energy
reference it is negative over much of a typical domain, where the donor share
`ρe_src_k / ρe_tot` is undefined. A large enough `c` makes the total positive
everywhere without moving the thermodynamic reference, which would reach the
model's own numerics. See `docs/src/energy_source_tags.md`.

`c·ρ` is energy carried by mass, so a process that changes `ρ` changes the total
by `c` times that change. The attribution bracket counts it for the processes it
covers, which are the labels in `KNOWN_TAG_SOURCES`. A process that writes
`Yₜ.c.ρ` under any other label, or under none, moves the offset total without
reaching a tag, and that difference lands in `e_src_res`. Vertical diffusion,
the viscous sponge, the LES SGS closures and hyperdiffusion are all in that
group, so the residual carries a `c`-proportional term wherever they are active
that it did not carry without an offset. A constant per unit mass does pass
unchanged through transport that is consistent with the mass flux, and through
limiters built on differences.
"""
@inline energy_source_parent(ρe_tot, ρ, ::Nothing) = ρe_tot
@inline energy_source_parent(ρe_tot, ρ, model::EnergySourceTaggingModel) =
    _offset_parent(ρe_tot, ρ, model.offset)

# The same total from the offset alone, so that it can be broadcast. `nothing`
# broadcasts as a scalar.
@inline _offset_parent(ρe_tot, ρ, ::Nothing) = ρe_tot
@inline _offset_parent(ρe_tot, ρ, offset) = ρe_tot + offset * ρ

"""
    energy_source_tag_state_names(model::EnergySourceTaggingModel)

`Tuple` of the state-field `Symbol`s (`:ρe_src_<name>`) of every tag.
"""
energy_source_tag_state_names(model::EnergySourceTaggingModel) =
    Tuple(Symbol(:ρe_src_, tag_name(tag)) for tag in model.tags)

"""
    energy_source_region_tag_state_names(model::EnergySourceTaggingModel)

`Tuple` of the state-field `Symbol`s of the pure region tags: those with a
region and no sources. These are the tags whose sum is expected to track
`ρe_tot`, so they are what the closure residual is summed over.
"""
energy_source_region_tag_state_names(model::EnergySourceTaggingModel) = Tuple(
    Symbol(:ρe_src_, tag_name(tag)) for
    tag in model.tags if !isnothing(tag.region) && isempty(tag.sources)
)

"""
    is_energy_source_tag_name(name)

Whether `name` (a `Symbol` like `:ρe_src_tropics`, or a
`MatrixFields.FieldName`) refers to an energy source tag.
"""
is_energy_source_tag_name(name::Symbol) = startswith(string(name), "ρe_src_")
is_energy_source_tag_name(name::MatrixFields.FieldName) =
    is_energy_source_tag_name(MatrixFields.extract_first(name))

# The names of the increment correction's ledger, in the state's order.
const ENERGY_SOURCE_LEDGER_NAMES = (:e_src_inc_left, :e_src_inc_moved)

"""
    energy_source_increment_ledger_variables(ρe_parent, model)

The ledger of [`correct_energy_source_increment!`](@ref), for a single grid
point, as zeros of the type of `ρe_parent`. Only under
`energy_source_tag_transport: enthalpy_increment`, and `(;)` otherwise:

  - `e_src_inc_left`: the energy the correction has left out of the tags, in
    J/m³, since the start of the run. In each column it sums to the part of the
    parent's implicit increment of `E` that changes the column's total and that
    the tags' own implicit tendencies did not take. That part lands in
    `e_src_res`.
  - `e_src_inc_moved`: the energy the correction has moved between levels, in
    J/m³, since the start of the run. It is the part of the mismatch that sums
    to zero in each column. That is mostly vertical transport the tags' own
    implicit tendencies did not take, and also the column-neutral part of
    their lag behind the parent's other implicit terms.

Both are prognostic, so the stepper weights each stage's entry as it weights
the tags. They record what the correction intends. A face whose donor cell has
no share of the partition moves no tag, so there a cell's actual change
differs, and the difference lands in `e_src_res` but in neither field. The
column totals are right.

Like the process records, their names carry no `ρ` prefix. So `gs_tracer_names`
and `is_tracer_var` skip them, and no transport or limiter reaches them. They
are carried through a restart.
"""
energy_source_increment_ledger_variables(ρe_parent, ::Nothing) = (;)
energy_source_increment_ledger_variables(
    ρe_parent,
    model::EnergySourceTaggingModel,
) =
    follows_implicit_increment(model) ?
    NamedTuple{ENERGY_SOURCE_LEDGER_NAMES}((zero(ρe_parent), zero(ρe_parent))) :
    (;)

"""
    energy_source_increment_ledger_names(model)

`Tuple` of the state-field `Symbol`s of the increment correction's ledger:
`(:e_src_inc_left, :e_src_inc_moved)` under `enthalpy_increment`, and `()`
otherwise. See [`energy_source_increment_ledger_variables`](@ref).
"""
energy_source_increment_ledger_names(model) =
    follows_implicit_increment(model) ? ENERGY_SOURCE_LEDGER_NAMES : ()

"""
    is_energy_source_ledger_name(name)

Whether `name`, a `Symbol`, is a field of the increment correction's ledger.
"""
is_energy_source_ledger_name(name::Symbol) =
    name in ENERGY_SOURCE_LEDGER_NAMES

# ============================================================================
# Cache
# ============================================================================

"""
    _energy_source_tagging_cache(Y, model)

Cache entries used by the energy source tags, merged into `p.tagging`; `nothing`
when they are disabled. Contains:

  - `ᶜenergy_source_masks`: one static center `Field` per region tag holding
    the smooth spatial mask of that tag's region, keyed like the state
    (`ρe_src_<name>`). Masks are evaluated once here and never inside a
    per-timestep broadcast.
  - `ᶜenergy_source_fix`: one center `Field` per tag, accumulating the energy
    that `repair_energy_source_tags!` has moved into or out of it. It is
    reported as `e_src_fix_<name>`. It lives in the cache, so it restarts at
    zero, as the water tags' ledger does.
  - `ᶜenergy_source_pos` and `ᶜenergy_source_neg`: the positive and negative
    parts of the partition's sum, which the repair fills itself.
  - `ᶠenergy_source_interior`: one on every face but the bottom one, where it
    is zero. `sediment_energy_source_tags!` uses it to keep the lowest cell as
    the donor at the surface, where there is no cell below.
  - Under `energy_source_tag_transport: enthalpy_increment` only, the fields of
    `snapshot_energy_source_increment!` and `correct_energy_source_increment!`:
    the snapshots of `ρe_tot`, `ρ` and the partition's sum at the start of an
    implicit stage, the stage weight `dtγ`, the correction's work fields, and
    each face's area relative to the bottom face's.
"""
_energy_source_tagging_cache(Y, ::Nothing) = nothing
function _energy_source_tagging_cache(Y, model::EnergySourceTaggingModel)
    ᶜenergy_source_masks = _tag_masks(Fields.coordinate_field(Y.c), model.tags)
    _check_region_partition(
        ᶜenergy_source_masks,
        energy_source_region_tag_state_names(model),
        "e_src_res",
        "ρe_src",
    )
    _check_increment_partition(
        ᶜenergy_source_masks,
        energy_source_region_tag_state_names(model),
        model,
    )
    _check_parent_positivity(Y, model)
    _check_sedimentation_offset(Y, model)
    # The ledger exists whether or not the repair is on, so that
    # `e_src_fix_<name>` reads zero rather than failing when it is off.
    ᶜenergy_source_fix = _energy_source_fix_fields(Y.c.ρ, model.tags)
    ᶜenergy_source_pos = zero.(Y.c.ρ)
    ᶜenergy_source_neg = zero.(Y.c.ρ)
    ᶠenergy_source_interior = one.(Fields.coordinate_field(Y.f).z)
    Fields.level(ᶠenergy_source_interior, half) .=
        zero(eltype(ᶠenergy_source_interior))
    return (;
        ᶜenergy_source_masks,
        ᶜenergy_source_fix,
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
        ᶠenergy_source_interior,
        _energy_source_increment_cache(Y, model)...,
    )
end

# The increment correction gives the partition the parent's increment of `E`,
# less what the partition's own tendencies moved. So under
# `enthalpy_increment` the region tags must partition all of `E`, where the
# other transports only warn (`_check_region_partition`). That there is a
# region tag at all is checked when the model is built.
function _check_increment_partition(ᶜmasks, names, model)
    follows_implicit_increment(model) || return nothing
    isempty(names) && return nothing
    mask_sum = reduce(
        (a, b) -> a .+ b,
        map(name -> parent(getproperty(ᶜmasks, name)), names),
    )
    deviation = maximum(abs.(mask_sum .- 1))
    deviation > 0.01 && error(
        "`energy_source_tag_transport: enthalpy_increment` needs region tags \
        that partition the domain, and the masks of these sum to 1 only to \
        within $deviation. The correction gives the region tags the parent's \
        increment of the total they partition, so where their masks leave a \
        gap or overlap, the tags would take too much or too little. Use \
        regions that sum to 1, such as a region and its complement via \
        `inside: false` or `above: false`.",
    )
    return nothing
end

"""
    check_energy_source_exchange_partition(cache, atmos)

Refuse the exchange of provenance at the sub-grid mass flux without region tags
that partition the domain. The exchange (`sgs_exchange_of_energy_source_tags!`)
runs under `PrognosticEDMFX` with the SGS mass flux on and without updraft
copies. A tag's share there is its value over the sum of the region tags without
sources. Without such tags that sum is zero, and the exchange would silently do
nothing. Where their masks leave a gap, the sum is too small, and a tag could
take the updraft's whole energy flux. A no-op in every other case, and without
energy source tags.
"""
check_energy_source_exchange_partition(cache, atmos) =
    _check_exchange_partition(
        cache,
        atmos.energy_source_tagging_model,
        atmos.turbconv_model,
        atmos,
    )
_check_exchange_partition(cache, model, turbconv_model, atmos) = nothing
function _check_exchange_partition(
    cache,
    model::EnergySourceTaggingModel,
    ::PrognosticEDMFX,
    atmos,
)
    atmos.edmfx_model.sgs_mass_flux || return nothing
    has_energy_source_updraft_copies(model) && return nothing
    names = energy_source_region_tag_state_names(model)
    advice = "Add a region and its complement, for example with `above: false` \
             or `inside: false`, or set `energy_source_tag_updraft_copy: true`, \
             whose copies need no partition."
    isempty(names) && error(
        "The energy source tags exchange provenance at the updraft's mass \
        flux under `turbconv: prognostic_edmfx`, and a tag's share there is \
        its value over the sum of the region tags without sources. These \
        tags have none, so the exchange would do nothing. $advice",
    )
    mask_sum = reduce(
        (a, b) -> a .+ b,
        map(name -> parent(getproperty(cache.ᶜenergy_source_masks, name)), names),
    )
    deviation = maximum(abs.(mask_sum .- 1))
    deviation > 0.01 && error(
        "The energy source tags exchange provenance at the updraft's mass \
        flux under `turbconv: prognostic_edmfx`, and a tag's share there is \
        its value over the sum of the region tags without sources. Their \
        masks sum to 1 only to within $deviation. Where they leave a gap, \
        that sum is too small, and a tag could take the updraft's whole \
        energy flux. $advice",
    )
    return nothing
end

# Sedimentation moves each tag by its share of the total the tags partition,
# and a share is zero wherever that total is not positive. Without an offset,
# under the default energy reference, that is much of a moist troposphere, and
# there the tags would not follow the falling water at all.
function _check_sedimentation_offset(Y, model)
    isempty(sedimenting_mass_names(Y)) && return nothing
    isnothing(model.offset) || return nothing
    @warn "`energy_source_tags` run with sedimenting condensate but no " *
          "`energy_source_tag_offset`. Sedimentation moves each tag by its " *
          "share of the total the tags partition, and that share is zero " *
          "wherever the total is not positive, which under the default " *
          "energy reference is much of the troposphere. There the tags do " *
          "not follow the falling water, and the difference lands in " *
          "`e_src_res`."
    return nothing
end

_energy_source_fix_fields(ᶜρ, ::Tuple{}) = (;)
_energy_source_fix_fields(ᶜρ, tags::Tuple) = merge(
    tag_entry(first(tags), zero.(ᶜρ)),
    _energy_source_fix_fields(ᶜρ, Base.tail(tags)),
)

"""
    energy_source_scratch(Y, model, atmos)

Scratch fields of the energy source tags, merged into `p.scratch`: the
bracket's snapshot of `Yₜ.c.ρe_tot`, the partition-share denominator that
sedimentation divides by, the two face fluxes of `E` that the tags share under
`PrognosticEDMFX`, and with an offset also a snapshot of `Yₜ.c.ρ` and a field
the closure check fills with the offset total. Where the exchange at the mass
flux runs, three more hold one value per tag in each cell: the grid mean's tag
values, the updraft's from the plume, and the environment's share differences
(`sgs_exchange_of_energy_source_tags!`). Three scalars hold the environment's
density and the two ratios the exchange's bound needs. They live in `p.scratch`
because the implicit tendency, where sedimentation runs, may be evaluated with
`ForwardDiff.Dual` numbers, and `p.scratch` is converted for that.
"""
energy_source_scratch(Y, model::EnergySourceTaggingModel, atmos) = merge(
    energy_source_cell_scratch(Y.c.ρ, model.offset),
    _energy_source_exchange_scratch(Y, model, atmos.turbconv_model, atmos),
    (;
        ᶠe_src_sgs_flux = Fields.Field(CT3{eltype(Y.c.ρ)}, axes(Y.f)),
        ᶠe_src_sediment_flux = Fields.Field(
            Geometry.WVector{eltype(Y.c.ρ)},
            axes(Y.f),
        ),
    ),
)

# Three tuples of tag values per cell and three scalars, for the exchange at the
# mass flux. Nothing without it: no prognostic EDMF, no sub-grid mass flux, or
# updraft copies, whose own tracer flux moves the tags instead.
_energy_source_exchange_scratch(Y, model, turbconv_model, atmos) = (;)
function _energy_source_exchange_scratch(
    Y,
    model,
    ::PrognosticEDMFX,
    atmos,
)
    (
        atmos.edmfx_model.sgs_mass_flux &&
        !has_energy_source_updraft_copies(model)
    ) || return (;)
    tag_values() =
        Fields.Field(NTuple{length(model.tags), eltype(Y.c.ρ)}, axes(Y.c))
    return (;
        ᶜe_src_mean = tag_values(),
        ᶜe_src_plume = tag_values(),
        ᶜe_src_environment = tag_values(),
        ᶜe_src_environment_density = similar(Y.c.ρ),
        ᶜe_src_room = similar(Y.c.ρ),
        ᶜe_src_energy_ratio = similar(Y.c.ρ),
    )
end
# The cell-center scratch alone: the bracket's snapshots, the share
# denominator and the offset total. It needs no face space.
energy_source_cell_scratch(ᶜρ, ::Nothing) =
    (; ᶜe_src_snapshot = similar(ᶜρ), ᶜe_src_share_norm = similar(ᶜρ))
energy_source_cell_scratch(ᶜρ, offset) = (;
    ᶜe_src_snapshot = similar(ᶜρ),
    ᶜe_src_share_norm = similar(ᶜρ),
    ᶜe_src_ρ_snapshot = similar(ᶜρ),
    ᶜe_src_parent = similar(ᶜρ),
)

"""
    energy_source_closure_total(model)

What the energy source closure check compares its region tags against, in the
form `closure_parent` takes: `:ρe_tot`, or with an offset a function that fills
a scratch field with the offset total and returns it.
"""
energy_source_closure_total(::Nothing) = :ρe_tot
energy_source_closure_total(model::EnergySourceTaggingModel) =
    _energy_source_closure_total(model.offset)
_energy_source_closure_total(::Nothing) = :ρe_tot
_energy_source_closure_total(offset) =
    (Y, p) -> _fill_energy_source_parent!(p.scratch.ᶜe_src_parent, Y, offset)
function _fill_energy_source_parent!(ᶜparent, Y, offset)
    @. ᶜparent = Y.c.ρe_tot + offset * Y.c.ρ
    return ᶜparent
end

"""
    energy_source_audit(Y, p, model, scale)

The energy source family's own columns of the audit table, beside those
[`tag_audit`](@ref) writes for every family:

  - `source_negative`, `source_negative_relative`: the integral of the negative
    parts of the tags that carry a source, in J, and over `scale`. The closure
    residual does not see those tags at all, so this is where a source tag going
    negative shows;
  - `source_minimum`: the smallest value of any tag that carries a source, per
    unit mass, in J/kg, over the whole domain, or `NaN` when there is none;
  - `repair_moved`, `repair_moved_relative`: the integral over all tags of the
    absolute value of what the repair has moved since the start of the run
    segment, in J, and over `scale`. Zero with the repair off. At
    `update_constrain_state_every: stage` or `dss` the ledger also counts the
    in-step repairs the stepper discards; see `repair_energy_source_tags!`.
  - under `energy_source_tag_transport: enthalpy_increment` only, the integrals
    of the increment correction's ledger since the start of the run, in J:
    `increment_left`, what it left out of the tags, which is signed and lands
    in the closure residual; `increment_left_gross`, the same with each cell's
    absolute value; and `increment_moved_gross`, the absolute value of what it
    moved between levels. Each also over `scale`. See
    [`energy_source_increment_ledger_variables`](@ref).

Every reduction is collective, so every process must call it.
"""
function energy_source_audit(Y, p, model::EnergySourceTaggingModel, scale)
    ᶜtmp = p.scratch.ᶜtemp_scalar
    FT = eltype(ᶜtmp)
    source_names = Tuple(
        Symbol(:ρe_src_, tag_name(tag)) for
        tag in model.tags if !isempty(tag.sources)
    )

    @. ᶜtmp = zero(ᶜtmp)
    for name in source_names
        ᶜtag = getproperty(Y.c, name)
        @. ᶜtmp += min(ᶜtag, zero(ᶜtag))
    end
    source_negative = -sum(ᶜtmp)

    source_minimum = if isempty(source_names)
        FT(NaN)
    else
        @. ᶜtmp = typemax(FT)
        for name in source_names
            ᶜtag = getproperty(Y.c, name)
            @. ᶜtmp = min(ᶜtmp, ᶜtag / Y.c.ρ)
        end
        buffer = [minimum(parent(ᶜtmp))]
        ClimaComms.allreduce!(ClimaComms.context(Y.c), buffer, min)
        buffer[1]
    end

    (; ᶜenergy_source_fix) = p.tagging
    @. ᶜtmp = zero(ᶜtmp)
    for name in energy_source_tag_state_names(model)
        ᶜfix = getproperty(ᶜenergy_source_fix, name)
        @. ᶜtmp += abs(ᶜfix)
    end
    repair_moved = sum(ᶜtmp)

    per_scale(x) = iszero(scale) ? zero(x) : x / scale
    return (;
        source_negative,
        source_negative_relative = per_scale(source_negative),
        source_minimum,
        repair_moved,
        repair_moved_relative = per_scale(repair_moved),
        _energy_source_ledger_audit(Y, ᶜtmp, model, per_scale)...,
    )
end

_energy_source_ledger_audit(Y, ᶜtmp, model, per_scale) =
    follows_implicit_increment(model) ?
    _energy_source_ledger_columns(Y, ᶜtmp, per_scale) : (;)
function _energy_source_ledger_columns(Y, ᶜtmp, per_scale)
    increment_left = sum(Y.c.e_src_inc_left)
    @. ᶜtmp = abs(Y.c.e_src_inc_left)
    increment_left_gross = sum(ᶜtmp)
    @. ᶜtmp = abs(Y.c.e_src_inc_moved)
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

# The donor share `φ_k = ρe_src_k / ρe_tot` needs a positive parent to mean
# anything. Moist total energy has no physical zero, so a shifted thermodynamic
# or gravitational reference can put part of the domain at or below it, and
# there the shares are undefined and `energy_source_fraction` returns zero
# instead.
#
# This runs unconditionally at initialization, because nothing else will say so.
# The closure check reports `nonpositive_fraction` every time it fires, but it
# is optional: a run with source tags and no `energy_source_closure_check` would
# otherwise get no warning at all. A bad reference is bad from t = 0, so
# checking the initial state catches the case that matters without costing a
# reduction every step.
#
# `sum` is used rather than `minimum` because `sum` is the reduction documented
# to reduce across processes.
#
# With an offset the check is made on the offset total, since that is what the
# shares divide by.
function _check_parent_positivity(Y, model)
    ᶜρe_tot = Y.c.ρe_tot
    offset = model.offset
    ᶜflag = similar(ᶜρe_tot)
    @. ᶜflag = ifelse(
        _offset_parent(ᶜρe_tot, Y.c.ρ, offset) <= zero(ᶜρe_tot),
        one(ᶜρe_tot),
        zero(ᶜρe_tot),
    )
    nonpositive_volume = sum(ᶜflag)
    iszero(nonpositive_volume) && return nothing
    @. ᶜflag = one(ᶜρe_tot)
    volume = sum(ᶜflag)
    fraction = iszero(volume) ? nonpositive_volume : nonpositive_volume / volume
    parent =
        isnothing(offset) ? "`ρe_tot`" :
        "`ρe_tot + $(offset)·ρ`, the total the energy source tags partition,"
    @warn(
        "$parent is non-positive over $(fraction * 100)% of the domain " *
        "volume at initialization. The energy source tags divide by it to get " *
        "each tag's donor share, so the shares are undefined there and " *
        "`energy_source_fraction` returns zero rather than a meaningful " *
        "number. Moist total energy has no physical zero, so this usually " *
        "means the chosen thermodynamic or gravitational reference puts part " *
        "of the domain below it. Tag values elsewhere are still computed, but " *
        "they are conditional on that reference. A large enough " *
        "`energy_source_tag_offset` gives the tags a positive total without " *
        "moving the model's reference. Enable `energy_source_closure_check` " *
        "to keep watching it during the run.",
    )
    return nothing
end

# ============================================================================
# Attribution
# ============================================================================

"""
    energy_source_fraction(ρe_src, ρe_tot)

The donor share `φ = ρe_src / ρe_tot` of a tag in the local moist energy,
clamped to `[0, 1]` and defined to be zero where `ρe_tot` is not positive.

This is the energy counterpart of `water_tag_fraction`, and the two share the
same weakness for different reasons. Total water has a physical zero, so a cell
with `ρq_tot ≤ 0` is a numerical artifact, though not a rare one: nothing in the
model enforces the bound and a sphere run routinely has it over part of its
volume. Moist total energy has no physical zero at all, because it depends on
the chosen thermodynamic and gravitational reference, and a shift of that
reference can put a whole region below zero at once. The
fallback below keeps the arithmetic finite in either case, but it does not make
the answer meaningful. A configuration whose `ρe_tot` goes non-positive anywhere
is one whose source shares cannot be interpreted there, and the run reports that
through `e_src_res` and through the `nonpositive_fraction` column of its closure
table rather than silently.

With `energy_source_tag_offset` the second argument is the offset total
`ρe_tot + c·ρ` rather than `ρe_tot`; see `energy_source_parent`.
"""
@inline energy_source_fraction(ρe_src, ρe_tot) =
    ρe_tot > zero(ρe_tot) ?
    min(max(ρe_src / ρe_tot, zero(ρe_tot)), one(ρe_tot)) : zero(ρe_tot)

"""
    snapshot_energy_source_tags!(p, Yₜ)

Record the current `Yₜ.c.ρe_tot` in `p.scratch`, opening an attribution bracket
for the energy source tags, and with an offset `Yₜ.c.ρ` as well. A no-op when
they are disabled.

Paired with [`attribute_energy_source_tags!`](@ref). This uses its own buffers
rather than the ones the `ρe_tag_*` family uses, so that the two can be
configured independently.
"""
snapshot_energy_source_tags!(p, Yₜ) = _snapshot_energy_source_tags!(
    p,
    Yₜ,
    p.atmos.energy_source_tagging_model,
)
_snapshot_energy_source_tags!(p, Yₜ, ::Nothing) = nothing
function _snapshot_energy_source_tags!(p, Yₜ, model::EnergySourceTaggingModel)
    p.scratch.ᶜe_src_snapshot .= Yₜ.c.ρe_tot
    _snapshot_mass!(p, Yₜ, model.offset)
    return nothing
end
_snapshot_mass!(p, Yₜ, ::Nothing) = nothing
function _snapshot_mass!(p, Yₜ, offset)
    p.scratch.ᶜe_src_ρ_snapshot .= Yₜ.c.ρ
    return nothing
end

"""
    attribute_energy_source_tags!(Yₜ, Y, p, source::Symbol)

Close a bracket opened by [`snapshot_energy_source_tags!`](@ref): compute the
increment `Δ = Yₜ.c.ρe_tot - snapshot` produced by the bracketed process
(labeled `source`) and add `M_k·Δ⁺ - φ_k·Δ⁻` to each tag's tendency, where `M_k`
is the tag's mask and `φ_k` its donor share of the local moist energy.

With an offset `c` the increment is that of the offset total instead,
`Δ + c·(Yₜ.c.ρ - ρ snapshot)`, and `φ_k` is the share of `ρe_tot + c·ρ`. A
process that moves mass then moves the offset energy that mass carries, so the
region tags still account for the whole increment.

Production reaches a tag only when it lists `source`; pure region tags list none
and so receive every process. Loss reaches **every** tag, whatever it lists,
because energy leaves in proportion to what is actually present. That asymmetry
is what makes a tag an amount rather than a running total. It is the same rule
the water tags use, and the opposite of the `ρe_tag_*` family, which applies the
whole signed increment by mask.

This step does not keep a tag non-negative. What it produces is a tendency: the
loss term sets the *rate* a tag is depleted at, in proportion to what it holds,
but the timestepper integrates that over a finite step and the amount removed is
roughly `dt * φ_k * Δ⁻`. Nothing here bounds that by the holding. Where the
total is not positive the share is undefined and
[`energy_source_fraction`](@ref) returns zero, so no loss is attributed there at
all. The tags are also exempt from both tracer limiters and ride the unlimited
explicit transport path. What puts a negative tag back, where the total is
positive, is `repair_energy_source_tags!`, after each state update, unless
`energy_source_tag_repair` is off. See the contract on
[`EnergySourceTag`](@ref).

`Y` is needed in addition to `Yₜ` because the donor share is a property of the
current state. A no-op when energy source tagging is disabled.
"""
attribute_energy_source_tags!(Yₜ, Y, p, source::Symbol) =
    _attribute_energy_source_tags!(
        Yₜ,
        Y,
        p,
        source,
        p.atmos.energy_source_tagging_model,
    )
_attribute_energy_source_tags!(Yₜ, Y, p, source, ::Nothing) = nothing
function _attribute_energy_source_tags!(
    Yₜ,
    Y,
    p,
    source,
    model::EnergySourceTaggingModel,
)
    (; ᶜenergy_source_masks) = p.tagging
    ᶜΔ = _energy_source_increment(Yₜ, p.scratch, model.offset)
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    _accumulate_energy_source_tags!(
        Yₜ.c,
        Y.c,
        ᶜenergy_source_masks,
        ᶜΔ,
        source,
        model.tags,
        ᶜparent,
    )
    return nothing
end

# The bracketed process's increment to the total the tags partition. With an
# offset `c`, a process that changes the mass changes the total by `c` times
# that change. The two differences are taken separately, so the large
# tendencies accumulated before the bracket cancel within each field rather than
# across them.
function _energy_source_increment(Yₜ, scratch, ::Nothing)
    ᶜsnapshot = scratch.ᶜe_src_snapshot
    return @. lazy(Yₜ.c.ρe_tot - ᶜsnapshot)
end
function _energy_source_increment(Yₜ, scratch, offset)
    ᶜsnapshot = scratch.ᶜe_src_snapshot
    ᶜρ_snapshot = scratch.ᶜe_src_ρ_snapshot
    return @. lazy((Yₜ.c.ρe_tot - ᶜsnapshot) + offset * (Yₜ.c.ρ - ᶜρ_snapshot))
end

# The total the donor share divides by, as a field: `Y.c.ρe_tot` itself without
# an offset, so that path is unchanged, and a lazy sum with one.
# The energy source tags partition `ρe_tot + c·ρ`, so they are rebuilt from
# that total, and their updraft copies from the tags themselves. See
# `rebuild_tags_from_state!`.
function _rebuild_energy_source_tags!(
    Y,
    ᶜcoord,
    model::EnergySourceTaggingModel,
    turbconv_model,
)
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    _rebuild_tag_fields!(Y.c, ᶜcoord, ᶜparent, model.tags)
    (has_energy_source_updraft_copies(model) && hasproperty(Y.c, :sgsʲs)) ||
        return nothing
    for j in 1:n_mass_flux_subdomains(turbconv_model)
        _rebuild_updraft_copies!(Y.c.sgsʲs.:($j), Y.c, model.tags)
    end
    return nothing
end

_rebuild_updraft_copies!(ᶜsgsʲ, ᶜY, ::Tuple{}) = nothing
function _rebuild_updraft_copies!(ᶜsgsʲ, ᶜY, tags::Tuple)
    tag = first(tags)
    ᶜcopy = updraft_copy_field(ᶜsgsʲ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    @. ᶜcopy = ᶜρe_src / ᶜY.ρ
    return _rebuild_updraft_copies!(ᶜsgsʲ, ᶜY, Base.tail(tags))
end

_energy_source_parent_field(Y, ::Nothing) = Y.c.ρe_tot
_energy_source_parent_field(Y, offset) = @. lazy(Y.c.ρe_tot + offset * Y.c.ρ)

# The split `Δ = Δ⁺ - Δ⁻` appears below as `max(Δ, 0)` and `min(Δ, 0)`, written
# the same way as in `tagged_water.jl` and for the same two reasons: it keeps the
# update in one broadcast, and a `-` directly before a modifier letter such as
# `ᶜ` parses as the suffixed operator `-ᶜ`, which Julia leaves undefined.
#
# `ᶜparent` is the total the donor share divides by. Called without it, it is
# `ᶜY.ρe_tot`, which is what a model without an offset uses.
_accumulate_energy_source_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, tags::Tuple) =
    _accumulate_energy_source_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        tags,
        ᶜY.ρe_tot,
    )
_accumulate_energy_source_tags!(ᶜYₜ, ᶜY, ᶜmasks, ᶜΔ, source, ::Tuple{}, ᶜparent) =
    nothing
function _accumulate_energy_source_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tags::Tuple,
    ᶜparent,
)
    _accumulate_energy_source_tag!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        first(tags),
        ᶜparent,
    )
    return _accumulate_energy_source_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜmasks,
        ᶜΔ,
        source,
        Base.tail(tags),
        ᶜparent,
    )
end

# Region-less tag: production weight is 1 wherever the tag receives this source.
function _accumulate_energy_source_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::EnergySourceTag{name, Nothing},
    ᶜparent,
) where {name}
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            max(ᶜΔ, 0) + min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    end
    return nothing
end

# Tag with a region: production is masked. Loss stays donor-proportional, so
# energy leaves from wherever the tag is holding it.
function _accumulate_energy_source_tag!(
    ᶜYₜ,
    ᶜY,
    ᶜmasks,
    ᶜΔ,
    source,
    tag::EnergySourceTag,
    ᶜparent,
)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜmask = tag_field(ᶜmasks, tag)
    if tag_receives_source(tag, source)
        @. ᶜρe_srcₜ +=
            ᶜmask * max(ᶜΔ, 0) +
            min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    else
        @. ᶜρe_srcₜ += min(ᶜΔ, 0) * energy_source_fraction(ᶜρe_src, ᶜparent)
    end
    return nothing
end

# ============================================================================
# Repair
# ============================================================================

# A pure region tag has a region and no sources. Those tags partition the total,
# and the repair keeps their sum. Both properties are type parameters, so this
# resolves at compile time, as `_is_partition_tag` does for the water tags.
_is_energy_partition_tag(
    ::EnergySourceTag{name, R, Tuple{}},
) where {name, R <: AbstractTagRegion} = true
_is_energy_partition_tag(::EnergySourceTag) = false

"""
    energy_source_partition_repair(ρe_src, pos, neg, parent)

The value `repair_energy_source_tags!` gives a partition tag. `pos` and `neg` are
the positive and negative parts of the partition's sum in the same cell, and
`parent` is the total the tags partition there.

Where `parent` is positive, a negative tag is set to zero and the positive tags
are scaled by the common factor `max(pos + neg, 0) / pos`, the factor of the
water tags' repair, `water_tag_repair_factor`. The sum `pos + neg` is kept
exactly and every tag ends non-negative. Where the negatives outweigh the
positives, no non-negative partition has that sum, so every tag is zeroed, as
the water repair does.

Where `parent` is not positive the tag is left as it is. The donor share is
undefined there, and a region tag carries the parent's sign by design, so a
negative value is not an error to repair. Under the default energy reference
that is much of the troposphere. With a large enough `energy_source_tag_offset`
it is nowhere.
"""
@inline energy_source_partition_repair(ρe_src, pos, neg, parent) =
    parent > zero(parent) ?
    max(ρe_src, zero(ρe_src)) * water_tag_repair_factor(pos, neg) : ρe_src

"""
    energy_source_overlay_repair(ρe_src, parent)

The value `repair_energy_source_tags!` gives a tag that carries a source. Such a
tag is not a member of the partition. It marks the part of the total that came
in through its processes. Where `parent` is positive a negative value is set to
zero; elsewhere the tag is left alone, for the reason
`energy_source_partition_repair` gives.

There is no sum to keep, so the energy the clip adds comes from nowhere within
the tags. The ledger records it.
"""
@inline energy_source_overlay_repair(ρe_src, parent) =
    parent > zero(parent) ? max(ρe_src, zero(ρe_src)) : ρe_src

"""
    repair_energy_source_tags!(Y, p)

Keep the energy source tags non-negative where their total is positive.

The tags go negative for the reasons given in `docs/src/energy_source_tags.md`:
the finite step of the donor loss, and unlimited explicit transport with no
limiter. A negative tag voids its reading as an amount of energy from
somewhere. Through the clamp in `energy_source_fraction` it also distorts what
the other tags lose. This puts the tags back in range after each state update:

  - the partition tags keep their sum, through `energy_source_partition_repair`;
  - a tag that carries a source is clipped at zero, through
    `energy_source_overlay_repair`.

Both act only where the total the tags partition is positive, which is
everywhere with a large enough `energy_source_tag_offset`.

It does **not** force the region tags to add up to the total. That would drive
`e_src_res` to zero by construction and hide the transport mismatch the residual
exists to show. It removes only the negativity, as the water tags' partition
repair does.

Every change is added to `p.tagging.ᶜenergy_source_fix` and reported as
`e_src_fix_<name>`, so what the repair did stays distinguishable from what the
rule and the transport did. For the partition tags these changes sum to zero in
each cell, except where the negatives outweighed the positives and every tag was
zeroed. The ledger equals what the repair changed in the accepted state only at
the default `update_constrain_state_every: step`. At `stage` or `dss` the repair
also runs inside the step, where the stepper rescales or discards what it
changes, as it does for the water tags' `q_tag_fix`. The tags end each step
repaired either way.

On by default. `energy_source_tag_repair: false` switches it off, and leaves the
tags exactly as the rule and their transport make them, negative values
included. Called from `constrain_state!` after the water tags' repair. A no-op
when energy source tagging is disabled.
"""
repair_energy_source_tags!(Y, p) =
    _repair_energy_source_tags!(Y, p, p.atmos.energy_source_tagging_model)
_repair_energy_source_tags!(Y, p, ::Nothing) = nothing
function _repair_energy_source_tags!(Y, p, model::EnergySourceTaggingModel)
    model.repair || return nothing
    (; ᶜenergy_source_fix, ᶜenergy_source_pos, ᶜenergy_source_neg) = p.tagging
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    ᶜenergy_source_pos .= zero(eltype(ᶜenergy_source_pos))
    ᶜenergy_source_neg .= zero(eltype(ᶜenergy_source_neg))
    _accumulate_energy_source_partition!(
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
        Y.c,
        model.tags,
    )
    _apply_energy_source_repair!(
        Y.c,
        ᶜenergy_source_fix,
        ᶜenergy_source_pos,
        ᶜenergy_source_neg,
        ᶜparent,
        model.tags,
    )
    return nothing
end

# The partition's sum split into its positive and negative parts, over the pure
# region tags only. The tags that carry a source are outside the partition.
_accumulate_energy_source_partition!(ᶜpos, ᶜneg, ᶜY, ::Tuple{}) = nothing
function _accumulate_energy_source_partition!(ᶜpos, ᶜneg, ᶜY, tags::Tuple)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜρe_src = tag_field(ᶜY, tag)
        @. ᶜpos += max(ᶜρe_src, 0)
        @. ᶜneg += min(ᶜρe_src, 0)
    end
    return _accumulate_energy_source_partition!(
        ᶜpos,
        ᶜneg,
        ᶜY,
        Base.tail(tags),
    )
end

# `ᶜpos` and `ᶜneg` come from the state before the repair and are only read
# here, so each tag can be rewritten in place and a later tag's factor still
# holds. The ledger is written first, so it records the correction itself.
_apply_energy_source_repair!(ᶜY, ᶜfix, ᶜpos, ᶜneg, ᶜparent, ::Tuple{}) =
    nothing
function _apply_energy_source_repair!(
    ᶜY,
    ᶜfix,
    ᶜpos,
    ᶜneg,
    ᶜparent,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜtag_fix = tag_field(ᶜfix, tag)
    if _is_energy_partition_tag(tag)
        @. ᶜtag_fix +=
            energy_source_partition_repair(ᶜρe_src, ᶜpos, ᶜneg, ᶜparent) -
            ᶜρe_src
        @. ᶜρe_src =
            energy_source_partition_repair(ᶜρe_src, ᶜpos, ᶜneg, ᶜparent)
    else
        @. ᶜtag_fix += energy_source_overlay_repair(ᶜρe_src, ᶜparent) - ᶜρe_src
        @. ᶜρe_src = energy_source_overlay_repair(ᶜρe_src, ᶜparent)
    end
    return _apply_energy_source_repair!(
        ᶜY,
        ᶜfix,
        ᶜpos,
        ᶜneg,
        ᶜparent,
        Base.tail(tags),
    )
end

# ============================================================================
# Sedimentation
# ============================================================================

# A center value taken from the cell below each face. There is no cell below
# the bottom face, so it gives zero there, and `ᶠenergy_source_interior`
# removes the term it enters at that face anyway.
const ᶠbottom_bias_zero =
    Operators.BottomBiasedC2F(bottom = Operators.SetValue(0))

"""
    energy_source_sediment_share(ρe_src, parent, norm)
    energy_source_source_sediment_share(ρe_src, parent)

The fraction of the energy that sedimentation carries out of a cell which a tag
gives up. A partition tag's clamped share of the total is divided by `norm`,
the sum of those shares over the partition. So the shares add up to one wherever
there is tagged energy, and the partition's fluxes add up to the parent's
exactly. A tag that carries a source keeps its own clamped share, as the water
tags' source tags do.
"""
@inline energy_source_sediment_share(ρe_src, parent, norm) =
    norm > zero(norm) ? energy_source_fraction(ρe_src, parent) / norm :
    zero(norm)
@inline energy_source_source_sediment_share(ρe_src, parent) =
    energy_source_fraction(ρe_src, parent)

"""
    energy_source_share_norm!(p, Y)

Fill `p.scratch.ᶜe_src_share_norm` with the sum of the partition tags' clamped
shares of the total they partition, the denominator that
`energy_source_sediment_share` divides by. It is a property of the current
state, so each caller recomputes it: `vertical_advection_of_water_tendency!`
once per call, and each term of the enthalpy-form transport once per
evaluation. A no-op when energy source tagging is disabled.
"""
energy_source_share_norm!(p, Y) =
    _energy_source_share_norm!(p, Y, p.atmos.energy_source_tagging_model)
_energy_source_share_norm!(p, Y, ::Nothing) = nothing
function _energy_source_share_norm!(p, Y, model::EnergySourceTaggingModel)
    ᶜnorm = p.scratch.ᶜe_src_share_norm
    ᶜparent = _energy_source_parent_field(Y, model.offset)
    ᶜnorm .= zero(eltype(ᶜnorm))
    _accumulate_energy_source_share_norm!(ᶜnorm, Y.c, ᶜparent, model.tags)
    return nothing
end

_accumulate_energy_source_share_norm!(ᶜnorm, ᶜY, ᶜparent, ::Tuple{}) =
    nothing
function _accumulate_energy_source_share_norm!(
    ᶜnorm,
    ᶜY,
    ᶜparent,
    tags::Tuple,
)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜρe_src = tag_field(ᶜY, tag)
        @. ᶜnorm += energy_source_fraction(ᶜρe_src, ᶜparent)
    end
    return _accumulate_energy_source_share_norm!(
        ᶜnorm,
        ᶜY,
        ᶜparent,
        Base.tail(tags),
    )
end

"""
    sediment_energy_source_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶜenergy_flux, ᶠρ)

Move the energy source tags with one sedimenting species. `ᶜq` is that species'
specific content, `ᶜw` its terminal velocity, `ᶠρ` the face density, and
`ᶜenergy_flux` the per-cell value of the species' energy flux,
`-w q (e_int + Φ + K)`. They are the quantities
`vertical_advection_of_water_tendency!` builds the parent's flux from.

The tags partition `E = ρe_tot + c·ρ`, and sedimentation moves `c` with the mass
it moves, so the flux the tags share is `-w q (e_int + Φ + K + c)`. Each face's
flux is shared out by the shares of the cell that loses the energy:

  - where the energy falls with the water, the cell above loses it, and the
    face takes the shares of the cell above, as the parent's flux takes its
    value;
  - where the water carries negative energy against the reference plus offset,
    as ice can, the energy flux points up while the water falls. Then the cell
    below loses the energy, and the face takes its shares;
  - at the bottom face there is no cell below, so the lowest cell's shares are
    kept, and energy that enters there brings no new provenance.

The partition's shares add up to one, so its fluxes add up to the parent's at
every face, and sedimentation adds nothing to `e_src_res`. A no-op when energy
source tagging is disabled, and under 0-moment microphysics, where nothing
sediments.

The tags have no Jacobian block for this. A tag's own Courant number is the
species' times the species' share of the total, which is small, so the step is
not stiff for the tags. The parent's energy flux does enter the Newton solve,
through the condensate's own blocks, so within a step the tags lag it slightly.
That gap is bounded and lands in `e_src_res`.
"""
sediment_energy_source_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶜenergy_flux, ᶠρ) =
    _sediment_energy_source_tags!(
        Yₜ,
        Y,
        p,
        ᶜq,
        ᶜw,
        ᶜenergy_flux,
        ᶠρ,
        p.atmos.energy_source_tagging_model,
    )
_sediment_energy_source_tags!(Yₜ, Y, p, ᶜq, ᶜw, ᶜenergy_flux, ᶠρ, ::Nothing) =
    nothing
function _sediment_energy_source_tags!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶜenergy_flux,
    ᶠρ,
    model::EnergySourceTaggingModel,
)
    # The offset per unit of falling mass. `false` is a strong zero, so without
    # an offset the flux is exactly the parent's.
    c = _mass_energy(model.offset)
    ᶜflux = @. lazy(ᶜenergy_flux - c * ᶜw * ᶜq)
    _sediment_energy_source_tag_fluxes!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, model.offset),
        p.scratch.ᶜe_src_share_norm,
        p.tagging.ᶠenergy_source_interior,
        ᶜflux,
        ᶠρ,
        model.tags,
    )
    return nothing
end
_mass_energy(::Nothing) = false
_mass_energy(offset) = offset

_sediment_energy_source_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠinterior,
    ᶜflux,
    ᶠρ,
    ::Tuple{},
) = nothing
function _sediment_energy_source_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠinterior,
    ᶜflux,
    ᶠρ,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜρe_src = tag_field(ᶜY, tag)
    ᶜshare = _energy_source_share_field(ᶜρe_src, ᶜparent, ᶜnorm, tag)
    # The whole flux with the shares of the cell above, plus, on interior faces
    # where the energy moves up, the difference that swaps in the shares of the
    # cell below.
    @. ᶜρe_srcₜ -= ᶜprecipdivᵥ(
        ᶠρ * (
            ᶠtop_bias(Geometry.WVector(ᶜflux * ᶜshare)) +
            ᶠinterior *
            ᶠtop_bias(Geometry.WVector(max(ᶜflux, 0))) *
            (ᶠbottom_bias_zero(ᶜshare) - ᶠtop_bias(ᶜshare))
        ),
    )
    return _sediment_energy_source_tag_fluxes!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶠinterior,
        ᶜflux,
        ᶠρ,
        Base.tail(tags),
    )
end

"""
    keep_energy_source_sediment_correction!(p, ᶠcorrection)

Keep the updraft's correction for
`sediment_energy_source_tags_with_corrections!`, which moves the energy source
tags with one sedimenting species under `PrognosticEDMFX`. There the parent's
energy flux has two corrections besides the grid mean's, one for the updraft
and one for the environment. Each moves the subdomain's specific energy minus
the grid mean's with the subdomain's own mass flux. The subdomain mass fluxes
sum to the grid mean's, so the corrections move no mass and carry no `c` part.

The tags take the species' whole face flux of `E`, the grid mean's flux as
`sediment_energy_source_tags!` builds it plus both corrections. They share it
once, by its direction, as that function shares the grid mean's flux alone.
Shared apart, a correction that points against the grid mean's flux would take
its shares from the other cell. A tag could then lose energy from a cell that
gains it.

`vertical_advection_of_water_tendency!` computes the updraft's correction and
then the environment's in the same scratch field. So the updraft's face flux is
kept first, with `keep_energy_source_sediment_correction!`, and the
environment's face flux is `ᶠcorrection`. Both are no-ops when energy source
tagging is disabled.
"""
keep_energy_source_sediment_correction!(p, ᶠcorrection) =
    _keep_energy_source_sediment_correction!(
        p,
        ᶠcorrection,
        p.atmos.energy_source_tagging_model,
    )
_keep_energy_source_sediment_correction!(p, ᶠcorrection, ::Nothing) = nothing
function _keep_energy_source_sediment_correction!(
    p,
    ᶠcorrection,
    ::EnergySourceTaggingModel,
)
    ᶠflux = p.scratch.ᶠe_src_sediment_flux
    @. ᶠflux = ᶠcorrection
    return nothing
end

"""
    sediment_energy_source_tags_with_corrections!(Yₜ, Y, p, ᶜq, ᶜw, ᶜenergy_flux, ᶠρ, ᶠcorrection)

Move the energy source tags with one sedimenting species under
`PrognosticEDMFX`. Each tag takes its share of the species' whole face flux of
`E`: the grid mean's, the updraft's correction kept by
`keep_energy_source_sediment_correction!`, and the environment's correction
`ᶠcorrection`. The flux is shared once, by its direction. See
`keep_energy_source_sediment_correction!` for why. A no-op when energy source
tagging is disabled.
"""
sediment_energy_source_tags_with_corrections!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶜenergy_flux,
    ᶠρ,
    ᶠcorrection,
) = _sediment_energy_source_tags_with_corrections!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶜenergy_flux,
    ᶠρ,
    ᶠcorrection,
    p.atmos.energy_source_tagging_model,
)
_sediment_energy_source_tags_with_corrections!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶜenergy_flux,
    ᶠρ,
    ᶠcorrection,
    ::Nothing,
) = nothing
function _sediment_energy_source_tags_with_corrections!(
    Yₜ,
    Y,
    p,
    ᶜq,
    ᶜw,
    ᶜenergy_flux,
    ᶠρ,
    ᶠcorrection,
    model::EnergySourceTaggingModel,
)
    c = _mass_energy(model.offset)
    # The updraft's correction is already in `ᶠflux`.
    ᶠflux = p.scratch.ᶠe_src_sediment_flux
    @. ᶠflux +=
        ᶠρ * ᶠtop_bias(Geometry.WVector(ᶜenergy_flux - c * ᶜw * ᶜq)) +
        ᶠcorrection
    _sediment_energy_source_tag_face_fluxes!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, model.offset),
        p.scratch.ᶜe_src_share_norm,
        p.tagging.ᶠenergy_source_interior,
        ᶠflux,
        model.tags,
    )
    return nothing
end

_sediment_energy_source_tag_face_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠinterior,
    ᶠflux,
    ::Tuple{},
) = nothing
function _sediment_energy_source_tag_face_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠinterior,
    ᶠflux,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜshare =
        _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    # The shares of the cell above, or, on interior faces where the energy
    # moves up, of the cell below.
    @. ᶜρe_srcₜ -= ᶜprecipdivᵥ(
        ᶠflux * ifelse(
            _is_upward(ᶠflux) & (ᶠinterior > 0),
            ᶠbottom_bias_zero(ᶜshare),
            ᶠtop_bias(ᶜshare),
        ),
    )
    return _sediment_energy_source_tag_face_fluxes!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶠinterior,
        ᶠflux,
        Base.tail(tags),
    )
end

# The partition and source forms of the share, selected on the tag's type, so
# the branch folds away at compile time. Sedimentation and the enthalpy-form
# transport below both share out a flux with it.
_energy_source_share_field(ᶜρe_src, ᶜparent, ᶜnorm, tag) =
    _is_energy_partition_tag(tag) ?
    (@. lazy(energy_source_sediment_share(ᶜρe_src, ᶜparent, ᶜnorm))) :
    (@. lazy(energy_source_source_sediment_share(ᶜρe_src, ᶜparent)))

# ============================================================================
# Enthalpy-form transport, an audit
# ============================================================================

"""
    moves_as_enthalpy(model)

Whether the energy source tags of `model` move by their shares of the parent's
own flux, which `energy_source_tag_transport: enthalpy` and `enthalpy_increment`
select. `false` when
energy source tagging is off, and under the default `tracer` transport. The
answer is a property of the model's type, so it folds away at compile time.
"""
moves_as_enthalpy(::Nothing) = false
moves_as_enthalpy(model::EnergySourceTaggingModel) =
    model.transport isa
    Union{EnthalpyEnergySourceTransport, EnthalpyIncrementEnergySourceTransport}

"""
    energy_source_tag_moves_as_enthalpy(p, name)

Whether `name` is an energy source tag that the enthalpy-form transport moves.
The generic tracer loops skip those tags in advection and hyperdiffusion, and
the kernels below move them instead.
"""
energy_source_tag_moves_as_enthalpy(p, name) =
    moves_as_enthalpy(p.atmos.energy_source_tagging_model) &&
    is_energy_source_tag_name(name)

# A center value taken from the cell above each face, and zero at the top face,
# where there is no cell above. The counterpart of `ᶠbottom_bias_zero`.
const ᶠtop_bias_zero = Operators.TopBiasedC2F(top = Operators.SetValue(0))

# The face below each cell. The lowest cell's is the surface face, so this
# needs no boundary value.
const ᶜbottom_bias = Operators.BottomBiasedF2C()

# Whether the flow through a face points up. `u³` is contravariant, and its one
# component has the sign of the vertical velocity. A `WVector` flux, as in
# sedimentation, is read the same way.
@inline _is_upward(u³) = u³.components.data.:1 > 0

# The face flux per unit density, `u³` times the face value of `ᶜχ`, as
# `vertical_transport` builds it for each upwinding scheme.
_face_value_flux(ᶠu³, ᶜχ, dt, ::Val{:none}) = @. lazy(ᶠu³ * ᶠinterp(ᶜχ))
_face_value_flux(ᶠu³, ᶜχ, dt, ::Val{:first_order}) =
    @. lazy(ᶠupwind1(ᶠu³, ᶜχ))
_face_value_flux(ᶠu³, ᶜχ, dt, ::Val{:vanleer_limiter}) =
    @. lazy(ᶠlin_vanleer(ᶠu³, ᶜχ, dt))
_face_value_flux(ᶠu³, ᶜχ, dt, ::Val{:third_order}) =
    @. lazy(ᶠupwind3(ᶠu³, ᶜχ))

"""
    enthalpy_vertical_advection_of_energy_source_tags!(Yₜ, Y, p)

Under `energy_source_tag_transport: enthalpy`, move the energy source tags
vertically by their shares of the parent's own flux.

The parent moves `h_tot` with `energy_q_tot_upwinding`, and the offset's `c·ρ`
moves with the mass. A constant passes through each of those reconstructions
unchanged, so the parent's flux of `E = ρe_tot + c·ρ` through a face is `ρ u³`
times the face value of `h_tot + c`. Each tag takes that flux times its share in
the cell upwind of the face. The shares add up to one, so the partition's fluxes
add up to the parent's at every face. The upwind shares are first order, so a
region's edge smears more than under van Leer. For an audit that is acceptable,
because what it checks is closure.

The tags move explicitly, with the fluxes of the solved stage state. The parent
moves `ρe_tot` vertically in the implicit step. With one Newton iteration
(`max_newton_iters_ode: 1`), its contribution is the increment linearised about
the stage's first guess, not its flux at the solved state, and its upwind
correction comes after the solve. The two differ by that linearisation, and the
difference lands in `e_src_res`. A no-op under the default `tracer` transport,
where the generic tracer loop moves the tags. A no-op too under
`enthalpy_increment`: there the tags take the parent's implicit increment,
which carries its vertical advection (see `correct_energy_source_increment!`).
"""
enthalpy_vertical_advection_of_energy_source_tags!(Yₜ, Y, p) =
    moves_as_enthalpy(p.atmos.energy_source_tagging_model) &&
    !follows_implicit_increment(p.atmos.energy_source_tagging_model) ?
    _enthalpy_vertical_advection!(
        Yₜ,
        Y,
        p,
        p.atmos.energy_source_tagging_model,
    ) : nothing
function _enthalpy_vertical_advection!(Yₜ, Y, p, model)
    energy_source_share_norm!(p, Y)
    (; ᶠu³, ᶜh_tot) = p.precomputed
    c = model.offset
    ᶜJ = Fields.local_geometry_field(Y.c).J
    ᶠJ = Fields.local_geometry_field(Y.f).J
    ᶠρ = @. lazy(ᶠinterp(Y.c.ρ * ᶜJ) / ᶠJ)
    ᶜH = @. lazy(ᶜh_tot + c)
    ᶠflux = _face_value_flux(
        ᶠu³,
        ᶜH,
        p.dt,
        p.atmos.numerics.energy_q_tot_upwinding,
    )
    _enthalpy_vertical_tag_fluxes!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, c),
        p.scratch.ᶜe_src_share_norm,
        ᶠρ,
        ᶠu³,
        ᶠflux,
        model.tags,
    )
    return nothing
end

_enthalpy_vertical_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠρ,
    ᶠu³,
    ᶠflux,
    ::Tuple{},
) = nothing
function _enthalpy_vertical_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠρ,
    ᶠu³,
    ᶠflux,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜshare =
        _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    @. ᶜρe_srcₜ -= ᶜadvdivᵥ(
        ᶠρ *
        ᶠflux *
        ifelse(
            _is_upward(ᶠu³),
            ᶠbottom_bias_zero(ᶜshare),
            ᶠtop_bias_zero(ᶜshare),
        ),
    )
    return _enthalpy_vertical_tag_fluxes!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶠρ,
        ᶠu³,
        ᶠflux,
        Base.tail(tags),
    )
end

# ============================================================================
# The sub-grid mass flux under PrognosticEDMFX
# ============================================================================

"""
    sgs_mass_flux_of_energy_source_tags!(Yₜ, Y, p, turbconv_model)

Under `PrognosticEDMFX` with its SGS mass flux on, move the energy source tags
by their shares of the parent's own sub-grid mass flux of `E = ρe_tot + c·ρ`.

The tags have no copy in the updrafts, so the SGS tracer loop of
`edmfx_sgs_mass_flux_tendency!` never reaches them. For each subdomain `k`, the
parent moves `ρe_tot` with the difference-form flux `ρᵏ aᵏ (u³ᵏ - u³)(χᵏ - h_tot)`, where `χᵏ` is the subdomain's moist static energy plus its kinetic
energy, and, when the air is moist, `ρ` with the same flux of `q_totᵏ - q_tot`.
The flux of `E` is the first plus `c` times the second. It is rebuilt here face
by face, each part with the parent's own reconstruction, and summed over the
subdomains. The two parts are reconstructed apart, because the van Leer option
is not linear.

Each tag takes that face flux times its share in the cell the flux leaves: the
cell below where it points up, the cell above where it points down. The
partition's shares add up to one, so its fluxes add up to the parent's at every
face. The divergence has the parent's zero-flux boundaries.

It runs in the implicit tendency, right after the parent's flux, so the tags
follow the parent at the Newton iterate. The tags have no Jacobian block for it:
the flux moves the energy anomaly, not the air, which against the tags' total
is a Courant number of order 1e-2 on the columns this was designed on. That
keeps every tag uncoupled in the split solver. It runs under both transports,
because there is no tracer form of this flux for a field without an updraft
copy.

A tag's composition in an updraft is taken as that of the cell it leaves. So
the flux moves the energy convection carries, but it does not mix provenance
the way it mixes the air. `sgs_exchange_of_energy_source_tags!` adds that
mixing, as an exchange that sums to zero over the tags.

Under `energy_source_tag_updraft_copy: true` neither runs. The tags then have
copies in the updraft, and the model's SGS tracer flux moves them, as it moves
any tracer with an updraft copy (`edmfx_sgs_mass_flux_tendency!`). A no-op
without energy source tags, without `PrognosticEDMFX`, and with the SGS mass
flux off.
"""
sgs_mass_flux_of_energy_source_tags!(Yₜ, Y, p, turbconv_model) = nothing
sgs_mass_flux_of_energy_source_tags!(
    Yₜ,
    Y,
    p,
    turbconv_model::PrognosticEDMFX,
) =
    p.atmos.edmfx_model.sgs_mass_flux ?
    _sgs_mass_flux_of_energy_source_tags!(
        Yₜ,
        Y,
        p,
        turbconv_model,
        p.atmos.energy_source_tagging_model,
    ) : nothing
_sgs_mass_flux_of_energy_source_tags!(Yₜ, Y, p, turbconv_model, ::Nothing) =
    nothing
function _sgs_mass_flux_of_energy_source_tags!(
    Yₜ,
    Y,
    p,
    turbconv_model,
    model::EnergySourceTaggingModel,
)
    # The copies' own SGS tracer flux moves the tags.
    has_energy_source_updraft_copies(model) && return nothing
    energy_source_share_norm!(p, Y)
    n = n_mass_flux_subdomains(turbconv_model)
    (; edmfx_sgsflux_upwinding) = p.atmos.numerics
    (; ᶠu³, ᶜh_tot, ᶠu³ʲs, ᶜKʲs, ᶜρʲs) = p.precomputed
    (; ᶜp, ᶠu³⁰, ᶜK⁰, ᶜT⁰, ᶜq_tot_nonneg⁰, ᶜq_liq⁰, ᶜq_ice⁰) = p.precomputed
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
    # `false` is a strong zero, so without an offset the flux is `ρe_tot`'s.
    c = _mass_energy(model.offset)
    moist = !(p.atmos.microphysics_model isa DryModel)

    # The environment's part first, so that it sets `ᶠflux` and the updrafts
    # add to it. Zeroing a vector field would need a `Ref`, which allocates.
    # The velocity differences stay lazy. The parent keeps them in the shared
    # `ᶠtemp_CT3`, and a diagnostic writes no scratch field the model reads.
    ᶠflux = p.scratch.ᶠe_src_sgs_flux
    ᶠu³_diff⁰ = @. lazy(ᶠu³⁰ - ᶠu³)
    ᶜa⁰ = @. lazy(draft_area(ᶜρa⁰, ᶜρ⁰))
    ᶠρ⁰ = @. lazy(ᶠinterp(ᶜρ⁰ * ᶜJ) / ᶠJ)
    ᶜmse⁰ = ᶜspecific_env_mse(Y, p)
    ᶜenergy⁰ = @. lazy((ᶜmse⁰ + ᶜK⁰ - ᶜh_tot) * ᶜa⁰)
    ᶠenergy_flux⁰ =
        _face_value_flux(ᶠu³_diff⁰, ᶜenergy⁰, dt, edmfx_sgsflux_upwinding)
    @. ᶠflux = ᶠρ⁰ * ᶠenergy_flux⁰
    if moist
        ᶜq_tot⁰ = ᶜspecific_env_value(@name(q_tot), Y, p)
        ᶜwater⁰ = @. lazy((ᶜq_tot⁰ - specific(Y.c.ρq_tot, Y.c.ρ)) * ᶜa⁰)
        ᶠwater_flux⁰ =
            _face_value_flux(ᶠu³_diff⁰, ᶜwater⁰, dt, edmfx_sgsflux_upwinding)
        @. ᶠflux += c * ᶠρ⁰ * ᶠwater_flux⁰
    end
    for j in 1:n
        ᶠu³_diffʲ = @. lazy(ᶠu³ʲs.:($$j) - ᶠu³)
        ᶜaʲ = @. lazy(draft_area(Y.c.sgsʲs.:($$j).ρa, ᶜρʲs.:($$j)))
        ᶠρʲ = @. lazy(ᶠinterp(ᶜρʲs.:($$j) * ᶜJ) / ᶠJ)
        ᶜenergy = @. lazy(
            (Y.c.sgsʲs.:($$j).mse + ᶜKʲs.:($$j) - ᶜh_tot) * ᶜaʲ,
        )
        ᶠenergy_flux = _face_value_flux(
            ᶠu³_diffʲ,
            ᶜenergy,
            dt,
            edmfx_sgsflux_upwinding,
        )
        @. ᶠflux += ᶠρʲ * ᶠenergy_flux
        if moist
            ᶜwater = @. lazy(
                (Y.c.sgsʲs.:($$j).q_tot - specific(Y.c.ρq_tot, Y.c.ρ)) * ᶜaʲ,
            )
            ᶠwater_flux = _face_value_flux(
                ᶠu³_diffʲ,
                ᶜwater,
                dt,
                edmfx_sgsflux_upwinding,
            )
            @. ᶠflux += c * ᶠρʲ * ᶠwater_flux
        end
    end

    _sgs_energy_source_tag_fluxes!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, model.offset),
        p.scratch.ᶜe_src_share_norm,
        ᶠflux,
        model.tags,
    )
    sgs_exchange_of_energy_source_tags!(Yₜ, Y, p, turbconv_model, model)
    return nothing
end

"""
    sgs_exchange_of_energy_source_tags!(Yₜ, Y, p, turbconv_model, model)

Exchange provenance between the energy source tags at the sub-grid mass flux,
as an updraft copy of the tags would, without one. Each tag `i` takes

    Xᵢ = Σₖ ρᵏ aᵏ (u³ᵏ - u³) (φᵏᵢ - φ̄ᵢ) Aᵏ

at each face, over the updraft and the environment `k`. `φᵏᵢ` is the tag's share
of the energy in subdomain `k`, `φ̄ᵢ` its share in the grid mean, and
`Aᵏ = e_totᵏ + c` the subdomain's energy per unit mass. A share is the tag's
specific value over the sum of the partition's, the region tags without
sources, in each subdomain. So a source tag's share is its fraction of the
partition's energy there. Where a subdomain's sum or the grid mean's is not
positive, the tags exchange nothing. Each term is
reconstructed as the parent reconstructs its own SGS flux. `X` is the part of
the flux an updraft copy would add to the donor-share flux of
`sgs_mass_flux_of_energy_source_tags!`: air of one composition rises and air of
another sinks, each with its whole energy.

No subdomain may carry more of a tag's energy than the cell holds,
`ρaʲ φʲᵢ Aʲ ≤ ρ φ̄ᵢ Ā`, and no share may go negative. The plume is blended toward
the grid mean by the largest factor that keeps a tag inside the smaller of those
two bounds. The partition's tags share one factor, so their shares keep summing
to one and their `Xᵢ` add up to zero at every face, and closure is untouched
under every transport. Each source tag has its own factor, since its exchange
stands alone, so a tag the cell holds little of cannot slow the partition's
mixing. The environment's shares follow from the updraft's, reversed and scaled
by the energy each subdomain carries, and are non-negative by construction.
Where the subdomains' energies do not add up to the cell's, the share-weighted
inventory is off by that mismatch. The zero sum also
needs region tags that partition the domain, which
`check_energy_source_exchange_partition` enforces. A
source tag's exchange stands alone, as its other fluxes do. The van
Leer reconstruction is not linear, so under it `X` is reconstructed first-order
upwind, which keeps that sum zero.

The updraft's shares come from a steady entraining plume, marched up each column
with the model's own entrainment rate `ε + ε_turb` and the updraft's velocity
`wʲ` at the face below each cell, as the model advects an updraft tracer. In the specific tag values `εʲ`, which
mix by mass,

    εʲ(k) = (εʲ(k - 1) + a ε̄(k)) / (1 + a),    a = (ε + ε_turb) Δz / wʲ · ρ / ρa⁰,

which is the steady updraft equation `wʲ ∂εʲ/∂z = (ε + ε_turb)(ε⁰ - εʲ)`, taken
implicitly in `z`, with the environment `ε⁰` from the grid mean and the updraft.
The plume starts in the lowest cell with the grid mean's composition, and
starts again wherever the updraft is absent or does not rise. It assumes one
updraft, since the environment is the grid mean less that updraft. It is exact when
the updraft adjusts faster than the shares change. The environment's shares
follow from the grid mean and the updraft. Negative tags count as zero in every
share.

It runs in the implicit tendency, after the donor-share flux, and has no
Jacobian block, as the model's SGS flux of a passive tracer has none. It needs
one updraft, which `check_energy_source_tagging_supported` enforces.
"""
function sgs_exchange_of_energy_source_tags!(Yₜ, Y, p, turbconv_model, model)
    (; edmfx_sgsflux_upwinding) = p.atmos.numerics
    (; ᶠu³, ᶠu³ʲs, ᶜKʲs, ᶜρʲs, ᶜuʲs) = p.precomputed
    (; ᶜp, ᶠu³⁰, ᶜK⁰, ᶜT⁰, ᶜq_tot_nonneg⁰, ᶜq_liq⁰, ᶜq_ice⁰) = p.precomputed
    (;
        ᶜturb_entrʲs,
        ᶜentr_vel_scaleʲs,
        ᶜentr_nonvel_rateʲs,
        ᶜarea_bounding_entr_detrʲs,
    ) = p.precomputed
    (; dt) = p
    FT = eltype(Y.c.ρ)
    thermo_params = CAP.thermodynamics_params(p.params)
    c = _mass_energy(model.offset)
    upwinding = _exchange_upwinding(edmfx_sgsflux_upwinding)
    ᶜlg = Fields.local_geometry_field(Y.c)
    ᶜJ = ᶜlg.J
    ᶠJ = Fields.local_geometry_field(Y.f).J
    ᶜΔz = Fields.Δz_field(Y.c)
    ᶜρaʲ = Y.c.sgsʲs.:(1).ρa
    ᶜρʲ = ᶜρʲs.:(1)
    ᶜρa⁰ = @. lazy(ρa⁰(Y.c.ρ, Y.c.sgsʲs, turbconv_model))
    # The environment's density is written once, as the parent's microphysics
    # does. Most broadcasts below read it. Left lazy, it would add five fields
    # and a thermodynamic call to each of them (see the ratios below).
    ᶜρ⁰ = p.scratch.ᶜe_src_environment_density
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
    flags = _energy_partition_flags(model.tags)
    updraft_differences = ShareDifferences(flags, false)
    environment_differences = ShareDifferences(flags, true)
    # The grid mean's specific tag values, negative ones as zero. They are
    # stored as one tuple per cell, so the tag fields are read once, and each
    # tag's kernel below reads a few tuple fields rather than every tag.
    ᶜε̄ = p.scratch.ᶜe_src_mean
    set_nonnegative_specific!(ᶜε̄, Y.c, model.tags)

    # The updraft's specific tag values, from the plume.
    ᶜεʲ = p.scratch.ᶜe_src_plume
    ᶜplume_input = Base.Broadcast.broadcasted(
        _plume_level,
        ᶜε̄,
        Y.c.ρ,
        ᶜρaʲ,
        ᶜρa⁰,
        ᶜentrʲ,
        ᶜwʲ,
        ᶜΔz,
    )
    Operators.column_accumulate!(
        _plume_step,
        ᶜεʲ,
        ᶜplume_input;
        init = ntuple(_ -> FT(NaN), Val(length(model.tags))),
    )

    # Each subdomain's energy per unit mass, `e_tot + c`, with `e_tot = mse +
    # K - p/ρ`, and its area fraction and face density.
    ᶜmse⁰ = ᶜspecific_env_mse(Y, p)
    ᶜAʲ = @. lazy(Y.c.sgsʲs.:(1).mse + ᶜKʲs.:(1) - ᶜp / ᶜρʲ + c)
    ᶜA⁰ = @. lazy(ᶜmse⁰ + ᶜK⁰ - ᶜp / ᶜρ⁰ + c)
    ᶜaʲ = @. lazy(draft_area(ᶜρaʲ, ᶜρʲ))
    ᶜa⁰ = @. lazy(draft_area(ᶜρa⁰, ᶜρ⁰))
    ᶠρʲ = @. lazy(ᶠinterp(ᶜρʲ * ᶜJ) / ᶠJ)
    ᶠρ⁰ = @. lazy(ᶠinterp(ᶜρ⁰ * ᶜJ) / ᶠJ)
    ᶠu³_diffʲ = @. lazy(ᶠu³ʲs.:(1) - ᶠu³)
    ᶠu³_diff⁰ = @. lazy(ᶠu³⁰ - ᶠu³)
    # Each subdomain's shares less the grid mean's, bounded so that no
    # subdomain carries more of a tag's energy than the cell holds. The
    # environment's differences follow from the updraft's, so both sum to zero
    # over the partition.
    # The bound needs two ratios, which are written to scratch before the
    # kernel reads them. Left lazy, they would bring every field of both
    # subdomains' energies into the kernel's broadcast, and ClimaCore then
    # boxes that broadcast on every call. The values are the same either way.
    # The allocation tests on the EDMF column guard this.
    ᶜĀ = @. lazy(Y.c.ρe_tot / Y.c.ρ + c)
    ᶜroom = p.scratch.ᶜe_src_room
    @. ᶜroom = _exchange_room(Y.c.ρ, ᶜρaʲ, ᶜρa⁰, ᶜĀ, ᶜAʲ, ᶜA⁰)
    ᶜenergy_ratio = p.scratch.ᶜe_src_energy_ratio
    @. ᶜenergy_ratio = _exchange_energy_ratio(ᶜρaʲ, ᶜρa⁰, ᶜAʲ, ᶜA⁰)
    ᶜΔφ⁰ = p.scratch.ᶜe_src_environment
    @. ᶜΔφ⁰ = environment_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜenergy_ratio)
    ᶜΔφʲ = ᶜεʲ
    @. ᶜΔφʲ = updraft_differences(ᶜεʲ, ᶜε̄, ᶜroom, ᶜenergy_ratio)

    subdomains = (;
        ᶜΔφʲ,
        ᶜΔφ⁰,
        ᶜAʲ,
        ᶜA⁰,
        ᶜaʲ,
        ᶜa⁰,
        ᶠρʲ,
        ᶠρ⁰,
        ᶠu³_diffʲ,
        ᶠu³_diff⁰,
    )
    _exchange_energy_source_tags!(Yₜ.c, subdomains, dt, upwinding, model.tags, 1)
    return nothing
end

_exchange_energy_source_tags!(ᶜYₜ, subdomains, dt, upwinding, ::Tuple{}, i) =
    nothing
function _exchange_energy_source_tags!(
    ᶜYₜ,
    subdomains,
    dt,
    upwinding,
    tags::Tuple,
    i,
)
    (; ᶜΔφʲ, ᶜΔφ⁰, ᶜAʲ, ᶜA⁰, ᶜaʲ, ᶜa⁰) = subdomains
    (; ᶠρʲ, ᶠρ⁰, ᶠu³_diffʲ, ᶠu³_diff⁰) = subdomains
    ᶜρe_srcₜ = tag_field(ᶜYₜ, first(tags))
    ᶜvalueʲ = @. lazy(getindex(ᶜΔφʲ, i) * ᶜAʲ * ᶜaʲ)
    ᶜvalue⁰ = @. lazy(getindex(ᶜΔφ⁰, i) * ᶜA⁰ * ᶜa⁰)
    ᶠfluxʲ = _face_value_flux(ᶠu³_diffʲ, ᶜvalueʲ, dt, upwinding)
    ᶠflux⁰ = _face_value_flux(ᶠu³_diff⁰, ᶜvalue⁰, dt, upwinding)
    @. ᶜρe_srcₜ -= ᶜadvdivᵥ(ᶠρʲ * ᶠfluxʲ + ᶠρ⁰ * ᶠflux⁰)
    return _exchange_energy_source_tags!(
        ᶜYₜ,
        subdomains,
        dt,
        upwinding,
        Base.tail(tags),
        i + 1,
    )
end

# Which tags form the partition, as `Val` of a tuple of `Bool`s. It is built from
# the tags' types, so it is a constant: a `Val` of a value computed at run time
# would leave every broadcast that reads it to dynamic dispatch.
@generated _energy_partition_flags(::T) where {T <: Tuple} = :(Val(
    $(Tuple(
        tag <: EnergySourceTag{<:Any, <:AbstractTagRegion, Tuple{}} for
        tag in T.parameters
    )),
))

# A linear reconstruction keeps the exchange's sum over the tags zero at every
# face. The van Leer limiter is not linear, so the exchange uses first-order
# upwinding under it.
_exchange_upwinding(upwinding) = upwinding
_exchange_upwinding(::Val{:vanleer_limiter}) = Val(:first_order)

@inline _nonnegative_specific(ρ, ρχs...) =
    map(ρχ -> max(ρχ, zero(ρχ)) / ρ, ρχs)

"""
    set_nonnegative_specific!(ᶜε̄, ᶜY, tags)

Write every tag's specific value in `ᶜY`, negative ones as zero, into the tuple
field `ᶜε̄` (`_nonnegative_specific`). Up to 31 tags this is one broadcast over
`ρ` and the tag fields. From 32 tags on that broadcast would take more than 32
arguments, which Julia does not specialize: with 32 tags it allocated at every
level (FINDINGS W34 on the record branch). So there each tag's component is
written by its own broadcast. The number of tags is a constant of the type, so
the choice costs nothing at run time.
"""
function set_nonnegative_specific!(ᶜε̄, ᶜY, tags)
    if length(tags) < 32
        tag_fields = unrolled_map(tag -> tag_field(ᶜY, tag), tags)
        Base.Broadcast.materialize!(
            ᶜε̄,
            Base.Broadcast.broadcasted(_nonnegative_specific, ᶜY.ρ, tag_fields...),
        )
    else
        _set_nonnegative_specific!(ᶜε̄, ᶜY, tags, Val(1))
    end
    return nothing
end
_set_nonnegative_specific!(ᶜε̄, ᶜY, ::Tuple{}, ::Val) = nothing
function _set_nonnegative_specific!(ᶜε̄, ᶜY, tags::Tuple, ::Val{i}) where {i}
    ᶜε̄ᵢ = getproperty(ᶜε̄, i)
    ᶜρχ = tag_field(ᶜY, first(tags))
    @. ᶜε̄ᵢ = max(ᶜρχ, zero(ᶜρχ)) / ᶜY.ρ
    return _set_nonnegative_specific!(ᶜε̄, ᶜY, Base.tail(tags), Val(i + 1))
end

# One level of the plume: the grid mean's specific values, the grid mean's
# weight in the step, and whether the plume starts again here, because there is
# no rising updraft. The step `(εʲ + a ε̄) / (1 + a)`, with
# `a = (ε + ε_turb) Δz / wʲ · ρ / ρa⁰`, is written with the weight
# `a / (1 + a)`. That form cannot overflow where `wʲ` is tiny, as `a` can in
# Float32.
@inline function _plume_level(ε̄, ρ, ρaʲ, ρa⁰, entr, wʲ, Δz)
    FT = typeof(ρ)
    rising = (ρaʲ > ϵ_numerics(FT)) & (wʲ > zero(FT)) & (ρa⁰ > zero(FT))
    mixing = max(entr, zero(FT)) * Δz * ρ
    weight =
        rising & (mixing > zero(FT)) ? mixing / (mixing + wʲ * ρa⁰) :
        zero(FT)
    return (ε̄, weight, !rising)
end

# The plume's step from the level below. The `NaN` it starts from marks the
# lowest level, where it takes the grid mean's composition.
@inline function _plume_step(εʲ_below, level)
    (ε̄, weight, restart) = level
    (restart | isnan(first(εʲ_below))) && return ε̄
    return map((εʲ, ε) -> εʲ + weight * (ε - εʲ), εʲ_below, ε̄)
end

# The sum of the partition's values, which `partition`, a tuple of `Bool`s,
# marks. The loop is over a tuple of one type, so it unrolls and allocates
# nothing. These helpers index the tuples rather than `map` over them: inside a
# ClimaCore broadcast a tuple is an `AutoBroadcaster`, whose `map` builds a new
# one and allocates.
@inline function _partition_total(ε, partition)
    total = zero(ε[1])
    for i in 1:length(partition)
        total += partition[i] ? ε[i] : zero(total)
    end
    return total
end

# How far a tag's share in the updraft may exceed its share in the grid mean,
# per unit of that share. Two bounds meet here. The updraft may hold at most the
# cell's own energy of a tag, `ρaʲ φʲᵢ Aʲ ≤ ρ φ̄ᵢ Ā`, which leaves the room
# `ρĀ - ρaʲAʲ`. And the environment may not be left with a negative share, which
# leaves `ρa⁰A⁰`. The two agree when the subdomains' energies add up to the
# cell's, which they do not quite: the environment is diagnosed, and the kinetic
# energy and `p/ρ` differ by subdomain. So the smaller one binds. Negative where
# there is no updraft or no energy, which switches the exchange off there.
@inline function _exchange_room(ρ, ρaʲ, ρa⁰, Ā, Aʲ, A⁰)
    FT = typeof(ρ)
    ((ρaʲ > zero(FT)) & (Aʲ > zero(FT)) & (Ā > zero(FT))) ||
        return -one(FT)
    return min(ρ * Ā - ρaʲ * Aʲ, ρa⁰ * A⁰) / (ρaʲ * Aʲ)
end

# The energy the updraft carries over the environment's, `ρaʲ Aʲ / (ρa⁰ A⁰)`,
# which is how much the environment gives up for what the updraft takes.
@inline function _exchange_energy_ratio(ρaʲ, ρa⁰, Aʲ, A⁰)
    FT = typeof(ρaʲ)
    ((ρa⁰ > zero(FT)) & (A⁰ > zero(FT))) || return zero(FT)
    return ρaʲ * Aʲ / (ρa⁰ * A⁰)
end

# Each tag's share difference between one subdomain and the grid mean, as a
# callable type: a broadcast then carries the partition and the branch in the
# function's type rather than as arguments, which ClimaCore would wrap in a
# `Ref`. `environment` picks the environment's differences over the updraft's.
struct ShareDifferences{partition, environment} end
ShareDifferences(::Val{partition}, environment::Bool) where {partition} =
    ShareDifferences{partition, environment}()

@inline function (::ShareDifferences{partition, environment})(
    εʲ,
    ε̄,
    room,
    energy_ratio,
) where {partition, environment}
    FT = typeof(room)
    N = length(partition)
    total = _partition_total(ε̄, partition)
    totalʲ = _partition_total(εʲ, partition)
    no_exchange =
        (room < zero(FT)) |
        (energy_ratio <= zero(FT)) |
        (total <= zero(FT)) |
        (totalʲ <= zero(FT))
    no_exchange && return ntuple(_ -> zero(FT), Val(N))
    # The partition's tags share one factor, so their shares keep summing to
    # one and their exchange sums to zero at every face. A source tag's
    # exchange stands alone, so each has its own factor, and a scarce one
    # cannot slow the partition's mixing.
    θ = _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    return ntuple(Val(N)) do i
        θᵢ = partition[i] ? θ : _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
        # The environment makes room for what the updraft takes, in proportion
        # to the energy each carries. So its difference is the updraft's,
        # reversed and scaled.
        scale = environment ? -θᵢ * energy_ratio : θᵢ
        scale *
        (_subdomain_share(εʲ, totalʲ, i) - _subdomain_share(ε̄, total, i))
    end
end

# The partition's common factor: the smallest over its tags. A helper, so that
# the factor is bound once. A variable reassigned in a loop and captured by the
# `ntuple` closure is boxed, and the kernel then allocates.
@inline function _partition_blend_factor(ε̄, εʲ, total, totalʲ, room, partition)
    θ = one(room)
    for i in 1:length(partition)
        θ = partition[i] ?
            min(θ, _blend_factor(ε̄, εʲ, total, totalʲ, room, i)) : θ
    end
    return θ
end

# The largest factor in `[0, 1]` by which tag `i`'s share in the updraft may
# move from its share in the grid mean, so that the tag stays inside `room`.
@inline function _blend_factor(ε̄, εʲ, total, totalʲ, room, i)
    mean_share = _subdomain_share(ε̄, total, i)
    difference = _subdomain_share(εʲ, totalʲ, i) - mean_share
    limit = mean_share * room
    FT = typeof(limit)
    return difference > limit ?
           min(one(FT), max(limit, zero(FT)) / difference) : one(FT)
end

# Tag `i`'s share of a subdomain: its value over the partition's sum there,
# capped at one.
@inline _subdomain_share(ε, total, i) = min(ε[i] / total, one(total))

_sgs_energy_source_tag_fluxes!(ᶜYₜ, ᶜY, ᶜparent, ᶜnorm, ᶠflux, ::Tuple{}) =
    nothing
function _sgs_energy_source_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶠflux,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜshare =
        _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    @. ᶜρe_srcₜ -= ᶜadvdivᵥ(
        ᶠflux * ifelse(
            _is_upward(ᶠflux),
            ᶠbottom_bias_zero(ᶜshare),
            ᶠtop_bias_zero(ᶜshare),
        ),
    )
    return _sgs_energy_source_tag_fluxes!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶠflux,
        Base.tail(tags),
    )
end

# ============================================================================
# The implicit channel: following the parent's increment (a prototype)
# ============================================================================

"""
    follows_implicit_increment(model)

Whether the energy source tags of `model` take the parent's own increment in
each implicit stage (`energy_source_tag_transport: enthalpy_increment`). A tag
that follows an implicit term by its tendency lags the parent's Newton solve,
and for a stiff term the gap grows step by step (FINDINGS E59). The parent's
increment has no such gap, whatever the solver does. The answer is a property
of the model's type, so it folds away at compile time.
"""
follows_implicit_increment(::Nothing) = false
follows_implicit_increment(model::EnergySourceTaggingModel) =
    model.transport isa EnthalpyIncrementEnergySourceTransport

# The fields the correction needs. `dtγ` is the stage's implicit weight, which
# the post-solve hook is not given, so the snapshot keeps it.
_energy_source_increment_cache(Y, model) =
    follows_implicit_increment(model) ?
    (;
        ᶜe_src_ρe_tot_snapshot = similar(Y.c.ρ),
        ᶜe_src_ρ_snapshot = similar(Y.c.ρ),
        ᶜe_src_partition_snapshot = similar(Y.c.ρ),
        ᶜe_src_mismatch = similar(Y.c.ρ),
        ᶜe_src_abs_mismatch = similar(Y.c.ρ),
        ᶠe_src_mismatch_integral = Fields.Field(eltype(Y.c.ρ), axes(Y.f)),
        ᶠe_src_abs_mismatch_integral = Fields.Field(eltype(Y.c.ρ), axes(Y.f)),
        e_src_mismatch_total = zeros(axes(Fields.level(Y.f, half))),
        e_src_abs_mismatch_total = zeros(axes(Fields.level(Y.f, half))),
        ᶠe_src_increment_flux = Fields.Field(CT3{eltype(Y.c.ρ)}, axes(Y.f)),
        ᶠe_src_area_ratio = _energy_source_face_area_ratio(Y.f),
        e_src_dtγ = Ref(zero(eltype(Y.c.ρ))),
    ) : (;)

# The area of a column's bottom face over each face's own, `J/Δz` at the bottom
# over `J/Δz` at the face. 1 to rounding under a shallow atmosphere, with or
# without topography; below 1 under a deep atmosphere, whose faces grow with
# height. Static, so kept.
function _energy_source_face_area_ratio(Yf)
    ᶠJ = Fields.local_geometry_field(Yf).J
    ᶠΔz = Fields.Δz_field(Yf)
    ΔA_bot = Fields.level(ᶠJ, half) ./ Fields.level(ᶠΔz, half)
    return @. ΔA_bot * ᶠΔz / ᶠJ
end

# The sum of the partition tags of `ᶜY`, plus `dtγ` times that of `ᶜdY`.
function _energy_source_partition_sum!(ᶜsum, ᶜY, ᶜdY, dtγ, tags)
    ᶜsum .= zero(eltype(ᶜsum))
    return _add_energy_source_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, tags)
end
_add_energy_source_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, ::Tuple{}) = ᶜsum
function _add_energy_source_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, tags::Tuple)
    tag = first(tags)
    if _is_energy_partition_tag(tag)
        ᶜtag = tag_field(ᶜY, tag)
        ᶜtag_increment = tag_field(ᶜdY, tag)
        @. ᶜsum += ᶜtag + dtγ * ᶜtag_increment
    end
    return _add_energy_source_partition!(ᶜsum, ᶜY, ᶜdY, dtγ, Base.tail(tags))
end

"""
    snapshot_energy_source_increment!(Y, p, dtγ)

At the start of an implicit stage, keep `ρe_tot`, `ρ`, the sum of the partition
tags and the stage's weight `dtγ`, for `correct_energy_source_increment!`.
`ρe_tot` and `ρ` are kept apart, and not as `E = ρe_tot + c·ρ`, so that the
parent's increment is not the difference of two totals of the size of `E`. The
partition's increment still is, so in Float32 the correction has a floor of
about one unit in the last place of `E` per cell and stage, as the tags' own
updates do. Called first thing in
`initialize_implicit_stage_problem!`, where `Y` is still the stage value before
the solve. A no-op unless the tags follow the parent's implicit increment.
"""
snapshot_energy_source_increment!(Y, p, dtγ) =
    follows_implicit_increment(p.atmos.energy_source_tagging_model) ?
    _snapshot_energy_source_increment!(
        Y,
        p,
        dtγ,
        p.atmos.energy_source_tagging_model,
    ) : nothing
function _snapshot_energy_source_increment!(Y, p, dtγ, model)
    (; ᶜe_src_ρe_tot_snapshot, ᶜe_src_ρ_snapshot) = p.tagging
    (; ᶜe_src_partition_snapshot, e_src_dtγ) = p.tagging
    @. ᶜe_src_ρe_tot_snapshot = Y.c.ρe_tot
    @. ᶜe_src_ρ_snapshot = Y.c.ρ
    _energy_source_partition_sum!(
        ᶜe_src_partition_snapshot,
        Y.c,
        Y.c,
        false,
        model.tags,
    )
    e_src_dtγ[] = dtγ
    return nothing
end

"""
    correct_energy_source_increment!(dY, U, p)

After the Newton solve of an implicit stage, make the partition tags take the
parent's increment of `E`. `U` is the solved stage value, and `dY` already holds
the parent's own post-solve correction, which the stepper adds as `dtγ·dY`.

In each cell, the mismatch `m` is the parent's increment of `E` since the
snapshot less the partition's. The part of `m` that changes a column's total
cannot be moved within the column; it is left out of the tags, spread over the
column in proportion to `|m|`, and stays in `e_src_res`. Its column total is
exact, but `|m|` is dominated by the parent's vertical transport, so its
profile does not show where it arose. The rest integrates up the column to a face flux
that is zero at both boundaries, whose divergence is that rest. Each tag takes
the flux times its share in the cell the flux leaves, as with the sub-grid mass
flux, and the flux is added to `dY` divided by `dtγ`. The partition's shares add
up to one, so the partition then follows the parent's increment, up to the part
left in place. A tag that carries a source takes its own share of the flux.

The part left in place and the part moved are added to the ledger,
`e_src_inc_left` and `e_src_inc_moved` (see
[`energy_source_increment_ledger_variables`](@ref)).
"""
function correct_energy_source_increment!(dY, U, p)
    model = p.atmos.energy_source_tagging_model
    (; ᶜe_src_ρe_tot_snapshot, ᶜe_src_ρ_snapshot) = p.tagging
    (; ᶜe_src_partition_snapshot, e_src_dtγ) = p.tagging
    (; ᶜe_src_mismatch, ᶜe_src_abs_mismatch, ᶠe_src_increment_flux) = p.tagging
    (; ᶠe_src_mismatch_integral, ᶠe_src_abs_mismatch_integral) = p.tagging
    (; e_src_mismatch_total, e_src_abs_mismatch_total) = p.tagging
    (; ᶠe_src_area_ratio) = p.tagging
    FT = eltype(ᶜe_src_mismatch)
    dtγ = e_src_dtγ[]
    c = _mass_energy(model.offset)
    ᶜm = ᶜe_src_mismatch
    # The partition after the stage, with the parent's post-solve correction,
    # which moves no tag. That correction zeroes `dY` and writes only `ρe_tot`
    # and `ρq_tot`, so the `dY` terms of the partition and of `ρ` are zero; they
    # are kept so the mismatch stays right if it ever writes more.
    _energy_source_partition_sum!(ᶜm, U.c, dY.c, dtγ, model.tags)
    @. ᶜm =
        (U.c.ρe_tot + dtγ * dY.c.ρe_tot - ᶜe_src_ρe_tot_snapshot) +
        c * (U.c.ρ + dtγ * dY.c.ρ - ᶜe_src_ρ_snapshot) -
        (ᶜm - ᶜe_src_partition_snapshot)
    @. ᶜe_src_abs_mismatch = abs(ᶜm)
    Operators.column_integral_indefinite!(ᶠe_src_mismatch_integral, ᶜm)
    Operators.column_integral_indefinite!(
        ᶠe_src_abs_mismatch_integral,
        ᶜe_src_abs_mismatch,
    )
    Operators.column_integral_definite!(e_src_mismatch_total, ᶜm)
    Operators.column_integral_definite!(
        e_src_abs_mismatch_total,
        ᶜe_src_abs_mismatch,
    )
    # Upward positive. It is zero at the bottom face and, having taken out the
    # column's total, at the top face too. The integrals are per unit area of
    # the bottom face, and the divergence weights each face by its own area.
    # Under a deep atmosphere the faces grow with height, so the flux is
    # scaled by the bottom face's area over its own. On a flat grid that is 1.
    @. ᶠe_src_increment_flux = CT3(
        Geometry.WVector(
            -(
                ᶠe_src_mismatch_integral -
                ifelse(
                    e_src_abs_mismatch_total > 0,
                    e_src_mismatch_total / e_src_abs_mismatch_total,
                    FT(0),
                ) * ᶠe_src_abs_mismatch_integral
            ) / dtγ * ᶠe_src_area_ratio,
        ),
    )
    energy_source_share_norm!(p, U)
    _sgs_energy_source_tag_fluxes!(
        dY.c,
        U.c,
        _energy_source_parent_field(U, model.offset),
        p.scratch.ᶜe_src_share_norm,
        ᶠe_src_increment_flux,
        model.tags,
    )
    # The ledger. What is left in place stays out of the tags, and the rest is
    # what the flux moved. The stepper adds `dtγ·dY`, as it does for the tags.
    @. ᶜe_src_abs_mismatch *= ifelse(
        e_src_abs_mismatch_total > 0,
        e_src_mismatch_total / e_src_abs_mismatch_total,
        FT(0),
    )
    @. dY.c.e_src_inc_left += ᶜe_src_abs_mismatch / dtγ
    @. dY.c.e_src_inc_moved += (ᶜm - ᶜe_src_abs_mismatch) / dtγ
    return nothing
end

"""
    check_energy_source_increment_supported(atmos, ode_algo, T_imp!, T_post_imp!)

Refuse `energy_source_tag_transport: enthalpy_increment` where it cannot follow
the parent, or where following it would change the model. `T_post_imp!` is the
parent's own post-solve correction, or `nothing`.

  - The tags take the parent's increment after each Newton solve. So every
    implicit tendency must go through one. The algorithm must be an IMEX
    algorithm with a Newton method, and the flow must not be prescribed. A
    stage whose implicit diagonal is zero must not use the implicit tendency
    in a later stage or in the step's result. The ARS algorithms, such as the
    default ARS343, meet this. SSP333 and the IMKG algorithms do not, and
    neither do explicit or Rosenbrock algorithms.
  - The parent must have a post-solve correction of its own, which it has
    unless `energy_q_tot_upwinding` is `none`. Whenever there is a post-solve
    hook, the stepper refreshes the implicit cache on the solved state. The
    parent's `constrain_state!` can read that cache before the next refresh:
    at the end of a step of an FSAL tableau such as ARS222, or at every stage
    under `update_constrain_state_every: stage`. So a hook the parent does not
    have would change the model's fields.

Called when the integrator is built. A no-op for every other transport.
"""
check_energy_source_increment_supported(atmos, ode_algo, T_imp!, T_post_imp!) =
    follows_implicit_increment(atmos.energy_source_tagging_model) ?
    _check_energy_source_increment_supported(ode_algo, T_imp!, T_post_imp!) :
    nothing
function _check_energy_source_increment_supported(ode_algo, T_imp!, T_post_imp!)
    !isnothing(T_imp!) && isnothing(T_post_imp!) &&
        error(
            "`energy_source_tag_transport: enthalpy_increment` takes the parent's \
            increment in a post-solve hook. With `energy_q_tot_upwinding: none` \
            the parent has no post-solve correction of its own. A hook would make \
            the stepper refresh the implicit cache after each solve, which the \
            model's constraints read, so the model's fields would change. Use an \
            `energy_q_tot_upwinding` other than `none`, such as the default \
            `vanleer_limiter`, or `energy_source_tag_transport: enthalpy`.",
        )
    reason = implicit_increment_gap(ode_algo, T_imp!)
    isnothing(reason) && return nothing
    error(
        "`energy_source_tag_transport: enthalpy_increment` needs every \
        implicit tendency to go through a Newton solve, after which the tags \
        take the parent's increment. Here $reason, so the tags would miss \
        that part of the parent's vertical transport. Use an algorithm that \
        solves every stage it uses, such as the default ARS343, or \
        `energy_source_tag_transport: enthalpy`.",
    )
end

"""
    implicit_increment_gap(ode_algo, T_imp!)

Why a tag family that takes the parent's increment after each Newton solve
would miss part of the parent's implicit transport under `ode_algo`, as text
for an error message, or `nothing` when it would not. It misses part when the
flow is prescribed (`T_imp!` is `nothing`), when `ode_algo` is not an IMEX
algorithm with a Newton method, and when a stage whose implicit diagonal is
zero uses the implicit tendency in a later stage or in the step's result. The
ARS algorithms, such as ARS222 and ARS343, solve every stage they use. The
energy source tags' and the water tags' increments share it.
"""
function implicit_increment_gap(ode_algo, T_imp!)
    isnothing(T_imp!) &&
        return "the flow is prescribed, so there is no implicit tendency"
    (ode_algo isa CTS.IMEXAlgorithm && !isnothing(ode_algo.newtons_method)) ||
        return "`ode_algo` is not an IMEX algorithm with a Newton method"
    (; a_imp, b_imp) = ode_algo.tableau
    s = length(b_imp)
    unsolved = filter(
        i ->
            iszero(a_imp[i, i]) && (
                !iszero(b_imp[i]) ||
                any(j -> !iszero(a_imp[j, i]), 1:s)
            ),
        1:s,
    )
    isempty(unsolved) && return nothing
    return "$(length(unsolved) == 1 ? "stage" : "stages") \
        $(join(unsolved, ", ")) of `ode_algo` \
        $(length(unsolved) == 1 ? "uses" : "use") the implicit tendency \
        without a solve"
end

"""
    EnergySourceIncrementCorrection(post)

The post-solve hook when the tags follow the parent's implicit increment. It
runs the parent's own post-solve correction `post`, which sets every field of
`dY`, and then `correct_energy_source_increment!`. `post` is never `nothing`:
`check_energy_source_increment_supported` refuses the mode where the parent has
no correction. See `energy_source_post_implicit`.
"""
struct EnergySourceIncrementCorrection{F}
    post::F
end
function (correction::EnergySourceIncrementCorrection)(dY, U, p, t)
    correction.post(dY, U, p, t)
    correct_energy_source_increment!(dY, U, p)
    return nothing
end

"""
    energy_source_post_implicit(post, atmos)

The post-solve hook to give the stepper: `post` itself, or wrapped in
[`EnergySourceIncrementCorrection`](@ref) when the energy source tags follow the
parent's implicit increment.
"""
energy_source_post_implicit(post, atmos) =
    follows_implicit_increment(atmos.energy_source_tagging_model) ?
    EnergySourceIncrementCorrection(post) : post

"""
    enthalpy_horizontal_advection_of_energy_source_tags!(Yₜ, Y, p)

Under `energy_source_tag_transport: enthalpy`, move the energy source tags
horizontally with the parent's own value. The parent moves `h_tot`, and the
offset's `c·ρ` moves with the mass, through `split_divₕ`, which is linear in the
value it moves. So each tag moves with its share times `h_tot + c`, and the
partition's tendencies add up to the parent's. A no-op under the default
`tracer` transport, where the generic tracer loop moves the tags.
"""
enthalpy_horizontal_advection_of_energy_source_tags!(Yₜ, Y, p) =
    moves_as_enthalpy(p.atmos.energy_source_tagging_model) ?
    _enthalpy_horizontal_advection!(
        Yₜ,
        Y,
        p,
        p.atmos.energy_source_tagging_model,
    ) : nothing
function _enthalpy_horizontal_advection!(Yₜ, Y, p, model)
    energy_source_share_norm!(p, Y)
    (; ᶜu, ᶜh_tot) = p.precomputed
    c = model.offset
    ᶜH = @. lazy(ᶜh_tot + c)
    _enthalpy_horizontal_tag_fluxes!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, c),
        p.scratch.ᶜe_src_share_norm,
        ᶜu,
        ᶜH,
        model.tags,
    )
    return nothing
end

_enthalpy_horizontal_tag_fluxes!(ᶜYₜ, ᶜY, ᶜparent, ᶜnorm, ᶜu, ᶜH, ::Tuple{}) =
    nothing
function _enthalpy_horizontal_tag_fluxes!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ᶜu,
    ᶜH,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜshare =
        _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    @. ᶜρe_srcₜ -= split_divₕ(ᶜY.ρ * ᶜu, ᶜshare * ᶜH)
    return _enthalpy_horizontal_tag_fluxes!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ᶜu,
        ᶜH,
        Base.tail(tags),
    )
end

"""
    enthalpy_hyperdiffusion_of_energy_source_tags!(Yₜ, Y, p, ν₄_scalar, ᶜh_eff_plus_Φ)

Under `energy_source_tag_transport: enthalpy`, hyperdiffuse the energy source
tags with their shares of the parent's own hyperdiffusion flux.

The parent's flux of `ρe_tot` is `ρ ∇∇²s_d`, plus `ρ (h_eff + Φ) ∇∇²q_tot_eff`
when moisture is prognostic; see `apply_hyperdiffusion_tendency!`. The water
part moves `ρ` too, since `apply_tracer_hyperdiffusion_tendency!` takes it out
of `ρ` as well as `ρq_tot`. So the flux of `E = ρe_tot + c·ρ` carries
`h_eff + Φ + c` in its water part. Each tag takes that vector times its share
before the divergence, so the partition's tendencies add up to the parent's.
`ᶜh_eff_plus_Φ` is `nothing` in a dry model, where nothing moves `ρ`. A no-op
under the default `tracer` transport, where the tags are hyperdiffused as
tracers.
"""
enthalpy_hyperdiffusion_of_energy_source_tags!(
    Yₜ,
    Y,
    p,
    ν₄_scalar,
    ᶜh_eff_plus_Φ,
) =
    moves_as_enthalpy(p.atmos.energy_source_tagging_model) ?
    _enthalpy_hyperdiffusion!(
        Yₜ,
        Y,
        p,
        p.atmos.energy_source_tagging_model,
        ν₄_scalar,
        ᶜh_eff_plus_Φ,
    ) : nothing
function _enthalpy_hyperdiffusion!(Yₜ, Y, p, model, ν₄_scalar, ᶜh_eff_plus_Φ)
    energy_source_share_norm!(p, Y)
    (; ᶜ∇²s_d, ᶜ∇²q_tot_eff) = p.hyperdiff
    ᶜflux = _enthalpy_hyperdiffusion_flux(
        Y.c.ρ,
        ᶜ∇²s_d,
        ᶜ∇²q_tot_eff,
        ᶜh_eff_plus_Φ,
        model.offset,
    )
    _enthalpy_hyperdiffusion_tags!(
        Yₜ.c,
        Y.c,
        _energy_source_parent_field(Y, model.offset),
        p.scratch.ᶜe_src_share_norm,
        ν₄_scalar,
        ᶜflux,
        model.tags,
    )
    return nothing
end

# The parent's hyperdiffusion flux of `E = ρe_tot + c·ρ`, in a dry and a moist
# model. The water part moves `ρ` too, so it carries the offset `c`.
_enthalpy_hyperdiffusion_flux(ᶜρ, ᶜ∇²s_d, ᶜ∇²q_tot_eff, ::Nothing, c) =
    @. lazy(ᶜρ * gradₕ(ᶜ∇²s_d))
_enthalpy_hyperdiffusion_flux(ᶜρ, ᶜ∇²s_d, ᶜ∇²q_tot_eff, ᶜh_eff_plus_Φ, c) =
    @. lazy(
        ᶜρ * gradₕ(ᶜ∇²s_d) + ᶜρ * (ᶜh_eff_plus_Φ + c) * gradₕ(ᶜ∇²q_tot_eff),
    )

_enthalpy_hyperdiffusion_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ν₄_scalar,
    ᶜflux,
    ::Tuple{},
) = nothing
function _enthalpy_hyperdiffusion_tags!(
    ᶜYₜ,
    ᶜY,
    ᶜparent,
    ᶜnorm,
    ν₄_scalar,
    ᶜflux,
    tags::Tuple,
)
    tag = first(tags)
    ᶜρe_srcₜ = tag_field(ᶜYₜ, tag)
    ᶜshare =
        _energy_source_share_field(tag_field(ᶜY, tag), ᶜparent, ᶜnorm, tag)
    @. ᶜρe_srcₜ -= ν₄_scalar * wdivₕ(ᶜshare * ᶜflux)
    return _enthalpy_hyperdiffusion_tags!(
        ᶜYₜ,
        ᶜY,
        ᶜparent,
        ᶜnorm,
        ν₄_scalar,
        ᶜflux,
        Base.tail(tags),
    )
end
