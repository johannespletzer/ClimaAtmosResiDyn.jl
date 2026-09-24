#####
##### The restart guard of the energy source tags
#####
##### A restart may not change what the tags in a checkpoint mean. That is
##### decided by the offset, the tags and their definitions, the transport and
##### the repair. The checkpoint records them, and a restart that changes one
##### stops with an error that names it. The fields of the energy source tags and
##### of the process records must also match. That needs no record at all.

import ClimaCore: InputOutput

"""
    ENERGY_SOURCE_CHECKPOINT_VERSION

The version of the energy source tags' checkpoint attributes. A checkpoint
without it predates the restart guard. A checkpoint with another version is
refused, because its attributes may mean something else.
"""
const ENERGY_SOURCE_CHECKPOINT_VERSION = 1

# The checkpoint attributes, each named after the configuration key it records.
# Each tag's definition has attributes of its own, under `TAG_KEY_PREFIX` and
# the tag's name, because one attribute holding every tag could pass HDF5's
# limit of about 64 KB for an attribute.
const ENERGY_SOURCE_CHECKPOINT_KEYS = (;
    version = "energy_source_tag_checkpoint",
    offset = "energy_source_tag_offset",
    tags = "energy_source_tags",
    transport = "energy_source_tag_transport",
    repair = "energy_source_tag_repair",
)
const ENERGY_SOURCE_TAG_KEY_PREFIX = "energy_source_tag."

# A tag's definition is split into parts of at most this many bytes. The first
# attribute holds the number of parts, and each part is an attribute of its own,
# so that no attribute passes the limit, however many vertices a polygon has.
const ENERGY_SOURCE_TAG_PART_BYTES = 32_000

energy_source_tag_key(name) = string(ENERGY_SOURCE_TAG_KEY_PREFIX, name)
energy_source_tag_part_key(name, part) =
    string(ENERGY_SOURCE_TAG_KEY_PREFIX, name, ".", part)

# The offset as a number and as text. No offset is an offset of zero: the
# configuration turns `energy_source_tag_offset: 0` into `nothing`. The text is
# in the offset's own float type, so `Float32` prints as it was configured.
energy_source_offset_value(::Nothing) = 0.0
energy_source_offset_value(offset) = offset
energy_source_offset_text(offset) = string(energy_source_offset_value(offset))
energy_source_transport_text(::TracerEnergySourceTransport) = "tracer"
energy_source_transport_text(::EnthalpyEnergySourceTransport) = "enthalpy"
energy_source_transport_text(
    ::EnthalpyIncrementEnergySourceTransport,
) = "enthalpy_increment"

# A tag's definition: its region and its sources, separated by a tab, because a
# region's text holds spaces. A tag matches a source by membership, so the
# sources are sorted, and their order in the configuration does not count.
energy_source_tag_sources_text(tag) =
    isempty(tag.sources) ? "none" : join(sort!(collect(string.(tag.sources))), ",")
energy_source_tag_definition(tag) =
    string(tag_region_text(tag.region), "\t", energy_source_tag_sources_text(tag))

# Split a text into parts of at most `bytes` bytes. The parts are joined back
# as they were, so a split inside a character does no harm.
function energy_source_text_parts(text, bytes = ENERGY_SOURCE_TAG_PART_BYTES)
    units = codeunits(text)
    return [
        String(units[first:min(first + bytes - 1, end)]) for
        first in 1:bytes:max(length(units), 1)
    ]
end

"""
    write_energy_source_checkpoint_attributes!(file, model)

Write the settings that decide what the energy source tags in a checkpoint
mean as attributes of `file`:

  - a version, an integer;
  - the offset, the transport and the repair, each as text;
  - the tags' names, in state order;
  - each tag's definition, its region and its sources. It is split into parts
    of at most 32,000 bytes, so that no attribute passes HDF5's limit.

A restart compares the text, so its error can quote both values. A no-op
without energy source tags. Called by `save_state_to_disk_func`.
"""
write_energy_source_checkpoint_attributes!(file, ::Nothing) = nothing
function write_energy_source_checkpoint_attributes!(
    file,
    model::EnergySourceTaggingModel,
)
    K = ENERGY_SOURCE_CHECKPOINT_KEYS
    put(key, value) = InputOutput.HDF5.write_attribute(file, key, value)
    put(K.version, ENERGY_SOURCE_CHECKPOINT_VERSION)
    put(K.offset, energy_source_offset_text(model.offset))
    put(K.transport, energy_source_transport_text(model.transport))
    put(K.repair, string(model.repair))
    put(K.tags, join(map(tag -> string(tag_name(tag)), model.tags), ","))
    for tag in model.tags
        name = tag_name(tag)
        parts = energy_source_text_parts(energy_source_tag_definition(tag))
        put(energy_source_tag_key(name), length(parts))
        for (part, text) in enumerate(parts)
            put(energy_source_tag_part_key(name, part), text)
        end
    end
    return nothing
end

"""
    check_energy_source_checkpoint(restart_file, model, Y, context)

Refuse a restart that would change what the energy source tags or the process
records in `restart_file` mean. It checks, in this order, and stops at the
first mismatch:

 1. The energy source tag fields in `Y`, then the fields of the increment
    correction's ledger, then the tags' updraft copies, then the energy and
    water process record fields, against what `model` configures. This needs no attribute, so it covers
    every checkpoint.
 2. The version attribute. A checkpoint without it predates this guard. Then
    it warns that the offset, the tags' definitions, the transport and the
    repair cannot be checked, and lets the restart go on. A checkpoint with
    another version is refused.
 3. The offset, then each tag's region and sources, then the transport, then
    the repair.

Each error names the setting, the file, both values and what to do. `Y` is the
state read from `restart_file`. Called by `handle_restart`, before the cache is
built, so a refused restart fails in seconds.
"""
function check_energy_source_checkpoint(restart_file, model, Y, context)
    source_model = model.energy_source_tagging_model
    check_restart_fields(
        restart_file,
        Y,
        is_energy_source_tag_name,
        isnothing(source_model) ? () :
        energy_source_tag_state_names(source_model),
        "energy source tags",
        "energy_source_tags",
        "ρe_src_",
    )
    check_restart_fields(
        restart_file,
        Y,
        is_energy_source_ledger_name,
        isnothing(source_model) ? () :
        energy_source_increment_ledger_names(source_model),
        "fields of the energy source tags' increment ledger",
        "energy_source_tag_transport",
        "",
    )
    # The tags' updraft copies live in each updraft, so the first stands for
    # all of them. A file with no updrafts at all holds none, and a run that
    # configures them is refused rather than passed over.
    check_restart_fields(
        restart_file,
        (; c = hasproperty(Y.c, :sgsʲs) ? Y.c.sgsʲs.:(1) : (;)),
        name -> startswith(string(name), "e_src_"),
        isnothing(source_model) ? () :
        energy_source_updraft_copy_names(source_model),
        "updraft copies of the energy source tags",
        "energy_source_tag_updraft_copy",
        "e_src_",
    )
    check_restart_fields(
        restart_file,
        Y,
        name -> startswith(string(name), "prc_e_"),
        isnothing(model.energy_process_record) ? () :
        energy_process_record_state_names(model.energy_process_record),
        "energy process records",
        "energy_process_record",
        "prc_e_",
    )
    check_restart_fields(
        restart_file,
        Y,
        name -> startswith(string(name), "prc_q_"),
        isnothing(model.water_process_record) ? () :
        water_process_record_state_names(model.water_process_record),
        "water process records",
        "water_process_record",
        "prc_q_",
    )
    # The ledger per mechanism (WP6), present whenever the tags are.
    check_tag_mechanism_ledgers(
        restart_file,
        Y,
        energy_source_mechanism_names(source_model),
        "energy source",
        "e_src_",
        "energy_source_tags",
    )
    # The fields match, so a file without tags goes with a model without them.
    isnothing(source_model) && return nothing

    K = ENERGY_SOURCE_CHECKPOINT_KEYS
    reader = InputOutput.HDF5Reader(restart_file, context)
    recorded = try
        read_energy_source_checkpoint(reader.file, source_model.tags)
    finally
        Base.close(reader)
    end
    if isnothing(recorded)
        @warn "The restart file $restart_file was written before the energy \
               source tags recorded their settings in a checkpoint. The tag \
               fields match. But the offset, the tags' regions and sources, \
               the transport and the repair cannot be checked. Make sure they \
               are the ones the file was written with."
        return nothing
    end
    if recorded.version != ENERGY_SOURCE_CHECKPOINT_VERSION
        error(
            "The restart file $restart_file records the energy source tags' \
            settings in version $(recorded.version) of the checkpoint format, \
            and this run reads version $ENERGY_SOURCE_CHECKPOINT_VERSION. \
            Restart with the version of ClimaAtmos that wrote the file, or \
            start a new run.",
        )
    end

    check_restart_offset(restart_file, recorded.offset, source_model.offset)
    check_restart_tags(restart_file, recorded.tags, source_model.tags)
    check_restart_setting(
        restart_file,
        K.transport,
        recorded.transport,
        energy_source_transport_text(source_model.transport),
        "The closure residual in the file was made by the other transport.",
    )
    check_restart_setting(
        restart_file,
        K.repair,
        recorded.repair,
        string(source_model.repair),
        source_model.repair ?
        "The tags in the file were not kept non-negative by the repair, and \
        would be from here on." :
        "The tags in the file were kept non-negative by the repair, and would \
        not be from here on.",
    )
    return nothing
end

# The recorded settings, or `nothing` when the file has no version attribute.
# A tag the file records no definition for maps to `nothing`.
function read_energy_source_checkpoint(file, tags)
    K = ENERGY_SOURCE_CHECKPOINT_KEYS
    attributes = InputOutput.HDF5.attrs(file)
    K.version in keys(attributes) || return nothing
    get_attribute(key) = InputOutput.HDF5.read_attribute(file, key)
    definitions = Dict{String, Union{Nothing, String}}()
    for tag in tags
        name = tag_name(tag)
        key = energy_source_tag_key(name)
        definitions[string(name)] =
            key in keys(attributes) ?
            join(
                get_attribute(energy_source_tag_part_key(name, part)) for
                part in 1:get_attribute(key)
            ) : nothing
    end
    return (;
        version = get_attribute(K.version),
        offset = get_attribute(K.offset),
        transport = get_attribute(K.transport),
        repair = get_attribute(K.repair),
        tags = definitions,
    )
end

# Step 1: the fields of one family in the restart state against the ones the
# model configures, in order. They are named without their prefix.
function check_restart_fields(
    restart_file,
    Y,
    in_family,
    expected,
    family,
    config_key,
    prefix,
)
    found = Tuple(filter(in_family, propertynames(Y.c)))
    found == Tuple(expected) && return nothing
    short(names) = map(name -> chopprefix(string(name), prefix), collect(names))
    in_file, configured = short(found), short(expected)
    listed(names) = isempty(names) ? "none" : join(names, ", ")
    missing_from_file = setdiff(configured, in_file)
    not_configured = setdiff(in_file, configured)
    difference =
        isempty(missing_from_file) && isempty(not_configured) ?
        "They are the same, in a different order, and the order of the \
        fields in the state is part of the configuration." :
        "Missing from the file: $(listed(missing_from_file)). Not \
        configured: $(listed(not_configured))."
    error(
        "The restart file $restart_file holds the $family \
        $(listed(in_file)), and this run configures $(listed(configured)). \
        $difference Restart with the same `$config_key`, or start a new run.",
    )
end

# The offset compares as a number in the configured offset's type, so a
# `Float32` run compares in its own precision, and no offset equals zero.
function check_restart_offset(restart_file, recorded, offset)
    value = energy_source_offset_value(offset)
    old = parse(Float64, recorded)
    convert(typeof(value), old) == value && return nothing
    error(
        "The restart file $restart_file was written with \
        `energy_source_tag_offset: $recorded`, and this run sets \
        $(energy_source_offset_text(offset)). The tags in the file partition \
        `ρe_tot + $recorded·ρ`. Under the new offset they no longer add up to \
        the total they partition, and `e_src_res` would jump by the \
        difference, $(Float64(value) - old) J/kg. Restart with the same \
        offset, or start a new run from the initial condition.",
    )
end

function check_restart_tags(restart_file, recorded, tags)
    for tag in tags
        name = string(tag_name(tag))
        old = recorded[name]
        if isnothing(old)
            error(
                "The restart file $restart_file records no definition for the \
                energy source tag `$name`, although it holds the tag's field. \
                The file does not come from this version of the restart \
                guard. Restart with the version of ClimaAtmos that wrote it, \
                or start a new run.",
            )
        end
        old == energy_source_tag_definition(tag) && continue
        old_region, old_sources = split(old, "\t")
        error(
            "The energy source tag `$name` in the restart file $restart_file \
            was defined as `$old_region`, with sources `$old_sources`. This \
            run defines it as `$(tag_region_text(tag.region))`, with sources \
            `$(energy_source_tag_sources_text(tag))`. The tag holds energy by \
            its old definition, so under a new one its provenance would mix \
            the two. Keep the definition, or start a new run.",
        )
    end
    return nothing
end

function check_restart_setting(restart_file, key, recorded, configured, why)
    recorded == configured && return nothing
    error(
        "The restart file $restart_file was written under `$key: $recorded`, \
        and this run sets $configured. $why Keep the setting, or start a new \
        run.",
    )
end
