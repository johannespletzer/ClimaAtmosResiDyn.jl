#####
##### The restart guard of the water tags
#####
##### A restart may not change what the water tags in a checkpoint mean. The
##### tag fields and their updraft copies must match the configuration, which
##### needs no attribute. Each tag's region and sources are recorded in the
##### checkpoint, as the energy source tags record theirs. A restart that
##### changes one stops with an error that names it. The same holds for
##### `water_tag_precipitation`, under which `ρq_tag_<name>` holds only the
##### water that is neither rain nor snow.

"""
    WATER_TAG_CHECKPOINT_VERSION

The version of the water tags' checkpoint attributes. A checkpoint without the
version attribute restarts with a warning that the tags' regions and sources
cannot be checked. Version 1 reads as written without
`water_tag_precipitation`. Version 2 adds that key. Any other version is
refused.

The tags' own ledgers and the accumulators that a checkpoint carries need no
version of their own. The guard and `restore_tag_ledger_checkpoint!` check them
by whether the file holds them. So does the guard for the ledger of the withheld
gain, `q_tag_exp_negative`. No recorded attribute changes meaning, so the
version stays 2.
"""
const WATER_TAG_CHECKPOINT_VERSION = 2

const WATER_TAG_CHECKPOINT_KEYS = (;
    version = "water_tag_checkpoint",
    tags = "water_tracers",
    precipitation = "water_tag_precipitation",
)

# The versions this guard reads. Version 1 has no `water_tag_precipitation`.
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
version, the tags' names in state order and `water_tag_precipitation` as an
integer, one for `true`. A definition is split into parts of at most 32,000
bytes, as the energy source tags' are. A no-op without water tags. Called by
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

# A checkpoint whose increment ledger lacks `q_tag_inc_negative` holds tags that
# partition `ρq_tot` rather than `max(ρq_tot, 0)`. The field check that follows
# would only report differing ledger fields, so this names the cause.
check_restart_before_option_c(restart_file, Y, ::Nothing) = nothing
function check_restart_before_option_c(restart_file, Y, water_model)
    :q_tag_inc_negative in water_tag_increment_ledger_names(water_model) ||
        return nothing
    found = filter(is_water_tag_ledger_name, propertynames(Y.c))
    (isempty(found) || :q_tag_inc_negative in found) && return nothing
    error(
        "The restart file $restart_file holds the water tags' increment \
        ledger without `q_tag_inc_negative`. An older version wrote it, and its \
        tags partition `ρq_tot` itself. The tags of this version partition the \
        parent's non-negative water, `max(ρq_tot, 0)`, and the correction after \
        each solve records the parent's negative part in `q_tag_inc_negative`. \
        Restart from a checkpoint written by this version, or start a new run.",
    )
end

"""
    check_water_tag_checkpoint(restart_file, model, Y, context)

Refuse a restart that would change what the water tags in `restart_file` mean.
It checks, in this order, and stops at the first mismatch:

 1. The water tag fields in `Y`, the rain and snow parts, the increment's
    ledger, the ledgers of the withheld gain, the tags' copies in the first
    updraft, then the ledgers per mechanism, the leak correction's and each
    tag's own, then the microphysics audit's fields, against what `model`
    configures. A checkpoint without the ledgers per mechanism or the ledger of
    the withheld gain is refused here. A changed
    `water_tag_precipitation`, `water_tag_transport`,
    `water_tag_updraft_copy`, `water_tag_ledger_per_tag` or
    `water_tag_leak_correction` fails here,
    because the parts, the ledgers or the copies are in the file or are not.
    This needs no attribute, so it covers every checkpoint. A checkpoint
    under `increment` whose ledger lacks `q_tag_inc_negative` is refused, and
    the error names the cause.
 2. The version attribute. A checkpoint without it restarts with a warning
    that the tags' regions and sources cannot be checked. A checkpoint with a
    version this guard does not read is refused.
 3. The recorded `water_tag_precipitation`, which version 1 records as
    `false`.
 4. Each tag's region and sources.

`Y` is the state read from `restart_file`. Called by `handle_restart`, before
the cache is built, so a refused restart fails in seconds.

What continues through a restart:

  - The state ledgers: the ledgers per mechanism, the increment ledger, the leak correction's ledgers and each tag's own ledgers. They are
    fields of the state, so they continue from the checkpoint. A checkpoint
    without the configured ones is refused, in step 1. Under
    `water_tag_precipitation: true` the microphysics audit's fields are state
    fields too, and continue the same way.
  - The cache accumulators: the fix ledgers `q_tag_fix_<name>` and
    `q_tag_upfix_<name>`, their grosses and counts, and each state
    ledger's per-step gross, column gross, events and attempted total. The
    checkpoint carries them beside the state, and
    `restore_tag_ledger_checkpoint!` reads them back after the cache is built,
    so they continue too. A checkpoint with none of them starts them at zero,
    with a warning, and their totals then cover the new segment only. One with
    some but not all of them is refused.
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
    # A checkpoint whose increment ledger lacks `q_tag_inc_negative` gets its
    # own error. Without it, the check below would suggest a changed transport.
    check_restart_before_option_c(restart_file, Y, water_model)
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
    # The ledgers of the withheld gain. A checkpoint without them was written
    # under the rule before, and is refused.
    check_water_tag_exp_ledgers(
        restart_file,
        Y,
        water_tag_exp_ledger_names(water_model),
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
    # The ledgers per mechanism. After the copies, so that a changed
    # `water_tag_updraft_copy` is named by their check first.
    check_tag_mechanism_ledgers(
        restart_file,
        Y,
        water_tag_mechanism_names(water_model),
        "water",
        "q_tag_",
        "water_tag_updraft_copy",
    )
    # The leak correction's ledgers are in the file or are not, so a changed
    # `water_tag_leak_correction` fails here.
    check_restart_fields(
        restart_file,
        Y,
        is_water_tag_leak_mechanism_name,
        water_tag_leak_mechanism_names(water_model),
        "water tags' leak correction ledgers",
        "water_tag_leak_correction",
        "q_tag_led_",
    )
    # Each tag's own ledgers are in the file or are not, so a changed
    # `water_tag_ledger_per_tag` fails here. Those of the leak correction
    # depend on `water_tag_leak_correction` too.
    check_restart_fields(
        restart_file,
        Y,
        name ->
            is_tag_per_tag_ledger_name(name) &&
            startswith(string(name), "q_tag_"),
        water_tag_per_tag_ledger_names(water_model),
        "water tags' own ledgers",
        "water_tag_ledger_per_tag` and `water_tag_leak_correction",
        "q_tag_led_",
    )
    # The microphysics audit's fields come with the rain and snow parts.
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
            its old definition, so under a new one its origin would mix \
            the two. Keep the definition, or start a new run.",
        )
    end
    return nothing
end

# A checkpoint without the ledger of the withheld gain is refused with its own
# message. Its tags took a gain where the parent was below zero, and the ledger
# would start at zero partway through the run. The generic message would ask for
# the same `water_tracers`. Otherwise the ledgers are in the file or are not, as
# for the other ledgers.
function check_water_tag_exp_ledgers(restart_file, Y, expected)
    if !isempty(expected) &&
       !any(is_water_tag_exp_ledger_name, propertynames(Y.c))
        error(
            "The restart file $restart_file was written before the water tags \
            kept the ledger of the withheld gain ($(join(expected, ", "))). \
            Its tags took a process's gain where the parent was below zero, \
            and the ledger would start at zero partway through the run. Start \
            a new run.",
        )
    end
    return check_restart_fields(
        restart_file,
        Y,
        is_water_tag_exp_ledger_name,
        expected,
        "water tags' ledgers of the withheld gain",
        "water_tag_precipitation",
        "",
    )
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
    # Version 1 has no `water_tag_precipitation`, so it reads as `false`.
    precipitation =
        WATER_TAG_CHECKPOINT_KEYS.precipitation in keys(attributes) &&
        get_attribute(WATER_TAG_CHECKPOINT_KEYS.precipitation) == 1
    return (;
        version = get_attribute(WATER_TAG_CHECKPOINT_KEYS.version),
        tags = definitions,
        precipitation,
    )
end
