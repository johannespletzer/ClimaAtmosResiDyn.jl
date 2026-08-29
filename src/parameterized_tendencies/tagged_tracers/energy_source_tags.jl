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
##### tag holds energy that is present now, traced back to where it came from.
##### An `ρe_tag_*` tag configured with `source` holds a process-change record,
##### the signed increment one process applied. Both are useful; they answer
##### different questions.
#####
##### This file carries state, masks and transport only. The attribution rule
##### that makes a source tag a source tag is not here yet, so for now the tags
##### are initialized to their masked share and then only transported. A
##### partition of region tags therefore closes under pure dynamics, which is
##### the property the first tests check.
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

# Region-less tags carry no mask, exactly as for the other two families.
_tag_mask_entry(ᶜcoord, ::EnergySourceTag{name, Nothing}) where {name} = (;)
_tag_mask_entry(ᶜcoord, tag::EnergySourceTag) =
    tag_entry(tag, region_mask.(Ref(tag.region), ᶜcoord))

"""
    energy_source_tagging_variables(ρe_tot, local_geometry, model)

NamedTuple of tagged prognostic fields `(; ρe_src_<name₁> = ..., ...)` for a
single grid point, to be splatted into the center prognostic state alongside the
other grid-scale variables. Returns `(;)` when energy source tagging is disabled
(`model === nothing`).

Initial values come from `tag_initial_value`, so a pure region tag starts as its
masked share of `ρe_tot` and a tag carrying a source starts at zero.
"""
energy_source_tagging_variables(ρe_tot, local_geometry, ::Nothing) = (;)
energy_source_tagging_variables(
    ρe_tot,
    local_geometry,
    model::EnergySourceTaggingModel,
) = _energy_source_variables(ρe_tot, local_geometry.coordinates, model.tags)

_energy_source_variables(ρe_tot, coord, ::Tuple{}) = (;)
_energy_source_variables(ρe_tot, coord, tags::Tuple) = merge(
    tag_entry(first(tags), tag_initial_value(first(tags), ρe_tot, coord)),
    _energy_source_variables(ρe_tot, coord, Base.tail(tags)),
)

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

# ============================================================================
# Cache
# ============================================================================

"""
    _energy_source_tagging_cache(Y, model)

Cache entries used by the energy source tags, merged into `p.tagging`; `nothing`
when they are disabled. Contains `ᶜenergy_source_masks`, one static center
`Field` per region tag holding the smooth spatial mask of that tag's region,
keyed like the state (`ρe_src_<name>`). Masks are evaluated once here and never
inside a per-timestep broadcast.
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
    return (; ᶜenergy_source_masks)
end
