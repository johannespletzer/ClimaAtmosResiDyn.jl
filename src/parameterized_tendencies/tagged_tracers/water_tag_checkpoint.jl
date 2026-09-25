#####
##### The restart guard of the water tags
#####
##### A restart may not change what the water tags in a checkpoint mean. The
##### tag fields and their updraft copies must match the configuration, which
##### needs no record. Each tag's region and sources are recorded in the
##### checkpoint, as the energy source tags record theirs, and a restart that
##### changes one stops with an error that names it. So is
##### `water_tag_precipitation`, under which `ρq_tag_<name>` holds only the
##### water that is neither rain nor snow.

"""
    WATER_TAG_CHECKPOINT_VERSION

The version of the water tags' checkpoint attributes. A checkpoint without it
predates the restart guard. Version 2 adds `water_tag_precipitation`. A
version 1 checkpoint was written before that key, so it reads as written
without it. A checkpoint with any other version is refused.
"""
const WATER_TAG_CHECKPOINT_VERSION = 2

const WATER_TAG_CHECKPOINT_KEYS = (;
    version = "water_tag_checkpoint",
    tags = "water_tracers",
    precipitation = "water_tag_precipitation",
)

# The versions this guard reads. Version 1 predates `water_tag_precipitation`.
const WATER_TAG_CHECKPOINT_READABLE_VERSIONS = (1, 2)
const WATER_TAG_KEY_PREFIX = "water_tag."

water_tag_key(name) = string(WATER_TAG_KEY_PREFIX, name)
water_tag_part_key(name, part) = string(WATER_TAG_KEY_PREFIX, name, ".", part)

# A water tag's definition has the energy source tags' form: its region and its
# sorted sources, separated by a tab.
water_tag_definition(tag) = energy_source_tag_definition(tag)

"""
    write_water_tag_checkpoint_attributes!(file, model)

Write each water tag's region and sources as attributes of `file`, with a
version, the tags' names in state order and `water_tag_precipitation`, as 0 or
1. A definition is split into parts of at most 32,000 bytes, as the energy
source tags' are. A no-op without water tags. Called by
`save_state_to_disk_func`.
"""
write_water_tag_checkpoint_attributes!(file, ::Nothing) = nothing
function write_water_tag_checkpoint_attributes!(file, model::WaterTaggingModel)
    K = WATER_TAG_CHECKPOINT_KEYS
    put(key, value) = InputOutput.HDF5.write_attribute(file, key, value)
    put(K.version, WATER_TAG_CHECKPOINT_VERSION)
    put(K.tags, join(map(tag -> string(tag_name(tag)), model.tags), ","))
    put(K.precipitation, Int(has_water_tag_precipitation(model)))
    for tag in model.tags
        name = tag_name(tag)
        parts = energy_source_text_parts(water_tag_definition(tag))
        put(water_tag_key(name), length(parts))
        for (part, text) in enumerate(parts)
            put(water_tag_part_key(name, part), text)
        end
    end
    return nothing
end

"""
    check_water_tag_checkpoint(restart_file, model, Y, context)

Refuse a restart that would change what the water tags in `restart_file` mean.
It checks, in this order, and stops at the first mismatch:

 1. The water tag fields in `Y`, the rain and snow parts, the increment's
    ledger, the tags' copies in the first updraft, then the ledgers per
    mechanism, then the records of the microphysics audit, against what
    `model` configures. A checkpoint written before the ledgers per mechanism
    is refused here. A changed `water_tag_precipitation`,
    `water_tag_transport` or `water_tag_updraft_copy` fails here, because the
    parts, the ledger or the copies are in the file or are not. This needs no
    attribute, so it covers every checkpoint.
 2. The version attribute. A checkpoint without it predates this guard. Then
    it warns that the tags' regions and sources cannot be checked, and lets
    the restart go on. A checkpoint with a version this guard does not read
    is refused.
 3. The recorded `water_tag_precipitation`, which version 1 records as
    `false`.
 4. Each tag's region and sources.

`Y` is the state read from `restart_file`. Called by `handle_restart`, before
the cache is built, so a refused restart fails in seconds. The repair ledgers
start again from zero, as every cumulative tag diagnostic does.
"""
function check_water_tag_checkpoint(restart_file, model, Y, context)
    water_model = model.water_tagging_model
    check_restart_fields(
        restart_file,
        Y,
        name -> startswith(string(name), "ρq_tag_"),
        isnothing(water_model) ? () : water_tag_state_names(water_model),
        "water tags",
        "water_tracers",
        "ρq_tag_",
    )
    # The rain and snow parts are in the file or are not, so a changed
    # `water_tag_precipitation` fails here. Without this check a checkpoint
    # written with the key would restart without it, and its parts would ride
    # along as untagged tracers.
    check_restart_fields(
        restart_file,
        Y,
        is_water_precip_part_name,
        water_tag_precip_part_state_names(water_model),
        "rain and snow parts of the water tags",
        "water_tag_precipitation",
        "ρq_",
    )
    # The increment's ledger is in the file or is not, so a changed
    # `water_tag_transport` fails here, as a changed energy transport does.
    check_restart_fields(
        restart_file,
        Y,
        is_water_tag_ledger_name,
        isnothing(water_model) ? () :
        water_tag_increment_ledger_names(water_model),
        "fields of the water tags' increment ledger",
        "water_tag_transport",
        "",
    )
    # As for the energy source tags' copies, the first updraft stands for all.
    check_restart_fields(
        restart_file,
        (; c = hasproperty(Y.c, :sgsʲs) ? Y.c.sgsʲs.:(1) : (;)),
        is_water_tag_copy_name,
        isnothing(water_model) ? () : water_tag_updraft_copy_names(water_model),
        "updraft copies of the water tags",
        "water_tag_updraft_copy",
        "q_tag_",
    )
    # The ledgers per mechanism (WP6). After the copies, so that a
    # changed `water_tag_updraft_copy` is named by their check first.
    check_tag_mechanism_ledgers(
        restart_file,
        Y,
        water_tag_mechanism_names(water_model),
        "water",
        "q_tag_",
        "water_tag_updraft_copy",
    )
    # The microphysics audit's records come with the rain and snow parts.
    check_restart_fields(
        restart_file,
        Y,
        is_water_tag_audit_name,
        water_tag_audit_state_names(water_model),
        "records of the water tags' microphysics audit",
        "water_tag_precipitation",
        "q_",
    )
    isnothing(water_model) && return nothing

    reader = InputOutput.HDF5Reader(restart_file, context)
    recorded = try
        read_water_tag_checkpoint(reader.file, water_model.tags)
    finally
        Base.close(reader)
    end
    if isnothing(recorded)
        @warn "The restart file $restart_file was written before the water tags \
               recorded their settings in a checkpoint. The tag fields match. \
               But the tags' regions and sources cannot be checked. Make sure \
               they are the ones the file was written with."
        return nothing
    end
    if !(recorded.version in WATER_TAG_CHECKPOINT_READABLE_VERSIONS)
        error(
            "The restart file $restart_file records the water tags' settings \
            in version $(recorded.version) of the checkpoint format, and this \
            run reads version $WATER_TAG_CHECKPOINT_VERSION. Restart with the \
            version of ClimaAtmos that wrote the file, or start a new run.",
        )
    end
    if recorded.precipitation != has_water_tag_precipitation(water_model)
        error(
            "The restart file $restart_file was written with \
            `water_tag_precipitation: $(recorded.precipitation)`, and this run \
            sets `water_tag_precipitation: \
            $(has_water_tag_precipitation(water_model))`. The key decides \
            whether `ρq_tag_<name>` holds all of a tag's water or only the \
            water that is neither rain nor snow. Restart with the same key, or \
            start a new run.",
        )
    end
    for tag in water_model.tags
        name = string(tag_name(tag))
        old = recorded.tags[name]
        if isnothing(old)
            error(
                "The restart file $restart_file records no definition for the \
                water tag `$name`, although it holds the tag's field. The file \
                does not come from this version of the restart guard. Restart \
                with the version of ClimaAtmos that wrote it, or start a new \
                run.",
            )
        end
        old == water_tag_definition(tag) && continue
        old_region, old_sources = split(old, "\t")
        error(
            "The water tag `$name` in the restart file $restart_file was \
            defined as `$old_region`, with sources `$old_sources`. This run \
            defines it as `$(tag_region_text(tag.region))`, with sources \
            `$(energy_source_tag_sources_text(tag))`. The tag holds water by \
            its old definition, so under a new one its provenance would mix \
            the two. Keep the definition, or start a new run.",
        )
    end
    return nothing
end

# The recorded settings, or `nothing` when the file has no version attribute.
# A tag the file records no definition for maps to `nothing`.
function read_water_tag_checkpoint(file, tags)
    attributes = InputOutput.HDF5.attrs(file)
    WATER_TAG_CHECKPOINT_KEYS.version in keys(attributes) || return nothing
    get_attribute(key) = InputOutput.HDF5.read_attribute(file, key)
    definitions = Dict{String, Union{Nothing, String}}()
    for tag in tags
        name = tag_name(tag)
        key = water_tag_key(name)
        definitions[string(name)] =
            key in keys(attributes) ?
            join(
                get_attribute(water_tag_part_key(name, part)) for
                part in 1:get_attribute(key)
            ) : nothing
    end
    # Version 1 predates `water_tag_precipitation`, and so was written
    # without it.
    precipitation =
        WATER_TAG_CHECKPOINT_KEYS.precipitation in keys(attributes) &&
        get_attribute(WATER_TAG_CHECKPOINT_KEYS.precipitation) == 1
    return (;
        version = get_attribute(WATER_TAG_CHECKPOINT_KEYS.version),
        tags = definitions,
        precipitation,
    )
end
