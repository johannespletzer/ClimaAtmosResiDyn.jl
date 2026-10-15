#####
##### Reading what the tags and the parent budget saved back from a checkpoint
#####
##### The tags and the parent budget each read their own attributes and fields
##### from a restart file. These helpers hold the steps they share.

import ClimaCore: InputOutput

"""
    with_restart_reader(f, restart_file, context)

Open `restart_file` with `InputOutput.HDF5Reader`, return `f(reader)`, and close
the reader on every path.
"""
function with_restart_reader(f, restart_file, context)
    reader = InputOutput.HDF5Reader(restart_file, context)
    try
        return f(reader)
    finally
        Base.close(reader)
    end
end

"""
    restore_void_flags!(flags, key, reader) -> Vector{String}

Set each `voided[]` in `pairs(flags)` from the attribute `key(family)`, or to
`false` without it, and return the families without it.
"""
function restore_void_flags!(flags, key, reader)
    unrecorded = String[]
    recorded = keys(InputOutput.HDF5.attrs(reader.file))
    for (family, voided) in pairs(flags)
        if key(family) in recorded
            value = InputOutput.HDF5.read_attribute(reader.file, key(family))
            voided[] = !iszero(value)
        else
            voided[] = false
            push!(unrecorded, string(family))
        end
    end
    return unrecorded
end

"""
    missing_checkpoint_fields(reader, fields) -> Vector{String}

The names in `fields`, pairs `name => field`, that the file does not carry under
`fields/<name>`.
"""
missing_checkpoint_fields(reader, fields) =
    String[string(name) for (name, _) in fields if !haskey(reader.file, "fields/$name")]

"""
    read_checkpoint_fields!(reader, fields)

Copy each field in `fields`, pairs `name => field`, from the file into the field.
"""
function read_checkpoint_fields!(reader, fields)
    for (name, field) in fields
        restored = InputOutput.read_field(reader, name)
        parent(field) .= parent(restored)
    end
    return nothing
end
