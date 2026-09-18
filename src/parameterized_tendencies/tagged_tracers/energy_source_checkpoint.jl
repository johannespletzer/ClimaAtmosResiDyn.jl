#####
##### The restart guard of the energy source tags
#####
##### A restart may change nothing that decides what the tags in the checkpoint
##### mean: the offset, the tags and their definitions, the transport and the
##### repair. The checkpoint records them, and a restart that changes one stops
##### with an error that names it. The fields of the energy source tags and of
##### the process records must also match, which needs no record at all.

import ClimaCore: InputOutput

"""
    ENERGY_SOURCE_CHECKPOINT_VERSION

The version of the energy source tags' checkpoint attributes. A checkpoint
without it predates the restart guard.
"""
const ENERGY_SOURCE_CHECKPOINT_VERSION = 1

# The checkpoint attributes, each named after the configuration key it records.
const ENERGY_SOURCE_CHECKPOINT_KEYS = (;
    version = "energy_source_tag_checkpoint",
    offset = "energy_source_tag_offset",
    tags = "energy_source_tags",
    transport = "energy_source_tag_transport",
    repair = "energy_source_tag_repair",
)

energy_source_offset_text(::Nothing) = "none"
energy_source_offset_text(offset) = repr(Float64(offset))
energy_source_transport_text(::TracerEnergySourceTransport) = "tracer"
energy_source_transport_text(::EnthalpyEnergySourceTransport) = "enthalpy"

# One tag as it is written into a checkpoint: its name, its region and its
# sources, separated by tabs, because a region's text holds spaces.
energy_source_tag_sources_text(tag) =
    isempty(tag.sources) ? "none" : join(tag.sources, ",")
energy_source_tag_line(tag) = join(
    (
        string(tag_name(tag)),
        tag_region_text(tag.region),
        energy_source_tag_sources_text(tag),
    ),
    "\t",
)

"""
    write_energy_source_checkpoint_attributes!(file, model)

Write the settings that decide what the energy source tags in a checkpoint
mean as attributes of `file`: the offset, one line per tag with its name,
region and sources, the transport, the repair, and a version. Each is a string,
so a restart compares strings and can quote both values. A no-op without
energy source tags. Called by `save_state_to_disk_func`.
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
    put(K.tags, join(map(energy_source_tag_line, model.tags), "\n"))
    put(K.transport, energy_source_transport_text(model.transport))
    put(K.repair, string(model.repair))
    return nothing
end

"""
    check_energy_source_checkpoint(restart_file, model, Y, context)

Refuse a restart that would change what the energy source tags or the process
records in `restart_file` mean. It checks, in this order, and stops at the
first mismatch:

 1. the energy source tag fields in `Y`, then the energy and water process
    record fields, against what `model` configures. This needs no attribute,
    so it covers every checkpoint;
 2. the version attribute. A checkpoint without it predates this guard. It
    warns that the offset, the tags' definitions, the transport and the repair
    cannot be checked, and lets the restart go on;
 3. the offset, then each tag's region and sources, then the transport, then
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
    # The fields match, so a file without tags goes with a model without them.
    isnothing(source_model) && return nothing

    K = ENERGY_SOURCE_CHECKPOINT_KEYS
    reader = InputOutput.HDF5Reader(restart_file, context)
    recorded = try
        attributes = InputOutput.HDF5.attrs(reader.file)
        if !(K.version in keys(attributes))
            nothing
        else
            Dict(
                name => InputOutput.HDF5.read_attribute(reader.file, key) for
                (name, key) in pairs(K)
            )
        end
    finally
        Base.close(reader)
    end
    if isnothing(recorded)
        @warn "The restart file $restart_file was written before the energy \
               source tags recorded their settings in a checkpoint. The tag \
               fields match, but the offset, the tags' regions and sources, the \
               transport and the repair cannot be checked. Make sure they are \
               the ones the file was written with." maxlog = 1
        return nothing
    end

    check_restart_offset(restart_file, recorded[:offset], source_model.offset)
    check_restart_tags(restart_file, recorded[:tags], source_model.tags)
    check_restart_setting(
        restart_file,
        K.transport,
        recorded[:transport],
        energy_source_transport_text(source_model.transport),
        "The closure residual in the file was made by the other transport.",
    )
    check_restart_setting(
        restart_file,
        K.repair,
        recorded[:repair],
        string(source_model.repair),
        source_model.repair ?
        "The tags in the file were not kept non-negative by the repair, and \
        would be from here on." :
        "The tags in the file were kept non-negative by the repair, and would \
        not be from here on.",
    )
    return nothing
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
        "They are the same, in a different order." :
        "Missing from the file: $(listed(missing_from_file)). Not \
        configured: $(listed(not_configured))."
    error(
        "The restart file $restart_file holds the $family \
        $(listed(in_file)), and this run configures $(listed(configured)). \
        $difference Restart with the same `$config_key`, or start a new run.",
    )
end

function check_restart_offset(restart_file, recorded, offset)
    configured = energy_source_offset_text(offset)
    same =
        recorded == configured || (
            !isnothing(offset) &&
            recorded != "none" &&
            typeof(offset)(parse(Float64, recorded)) == offset
        )
    same && return nothing
    old = recorded == "none" ? 0.0 : parse(Float64, recorded)
    new = isnothing(offset) ? 0.0 : Float64(offset)
    error(
        "The restart file $restart_file was written with \
        `energy_source_tag_offset: $recorded`, and this run sets \
        $configured. The tags in the file partition `ρe_tot + $old·ρ`. Under \
        the new offset they no longer add up to the total they partition, \
        and `e_src_res` would jump by the difference, $(new - old) J/kg. \
        Restart with the same offset, or start a new run from the initial \
        condition.",
    )
end

function check_restart_tags(restart_file, recorded, tags)
    lines = split(recorded, "\n")
    by_name = Dict(first(split(line, "\t")) => line for line in lines)
    for tag in tags
        name = string(tag_name(tag))
        line = energy_source_tag_line(tag)
        old = get(by_name, name, nothing)
        (isnothing(old) || old == line) && continue
        _, old_region, old_sources = split(old, "\t")
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
