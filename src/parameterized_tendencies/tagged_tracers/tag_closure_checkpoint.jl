#####
##### The closure checks' void flags through a restart
#####
##### Past `void_above`, a closure check marks this row and every later row of
##### its tables with `closure_void = 1`. The flag of each tag family lives in
##### the cache, in `p.tagging.closure_void`, and the checkpoint records it. A
##### restarted run reads it back before its first check. So a run split into
##### segments marks its rows as one run would.

import ClimaCore: InputOutput

"""
    tag_closure_void_flags(atmos)

The closure checks' void flags, stored in `p.tagging.closure_void`: one
`Ref{Bool}` for each tag family the model has, named `water`, `energy` and
`energy_source`. A flag says whether the family's closure check has passed its
`void_above` level, in this run or before the checkpoint the run restarted
from. It starts as `false`.

[`tag_closure_callback!`](@ref) reads and sets the flag.
[`write_tag_closure_void_attributes!`](@ref) writes it to a checkpoint, and
[`restore_tag_closure_void!`](@ref) reads it back.
"""
tag_closure_void_flags(atmos) = (;
    (isnothing(atmos.water_tagging_model) ? (;) : (; water = Ref(false)))...,
    (isnothing(atmos.tagging_model) ? (;) : (; energy = Ref(false)))...,
    (
        isnothing(atmos.energy_source_tagging_model) ? (;) :
        (; energy_source = Ref(false))
    )...,
)

# The checkpoint attribute of one family's flag, named like its closure table.
tag_closure_void_key(family) = "$(family)_tag_closure_void"

# The flag of one family, for its closure check. The check exists only when the
# family has tags, so the flag does too.
tag_closure_voided(p, family::Symbol) =
    getproperty(p.tagging.closure_void, family)

"""
    write_tag_closure_void_attributes!(file, tagging)

Write each tag family's void flag as an attribute of `file`, `1` or `0`, named
`<family>_tag_closure_void`. `tagging` is `p.tagging`. A no-op without tags.
Called by `save_state_to_disk_func`.
"""
write_tag_closure_void_attributes!(file, ::Nothing) = nothing
function write_tag_closure_void_attributes!(file, tagging)
    for (family, voided) in pairs(tagging.closure_void)
        InputOutput.HDF5.write_attribute(
            file,
            tag_closure_void_key(family),
            Int(voided[]),
        )
    end
    return nothing
end

"""
    restore_tag_closure_void!(tagging, restart_file, context)

Set each tag family's void flag in `tagging`, which is `p.tagging`, from the
checkpoint `restart_file`. `AtmosSimulation` calls it after the cache is built
and before the integrator, whose start runs the first closure check. A flag
restored as `true` stays `true` whatever `void_above` the restarted run sets,
and this warns once, naming the families.

A checkpoint written before the flags were recorded has no attribute for a
family. That family's flag stays `false`, and this warns once, naming the
families. If such a family's check had passed its level before the checkpoint,
its rows after the restart are marked again only once it passes the level
again.
"""
restore_tag_closure_void!(::Nothing, restart_file, context) = nothing
function restore_tag_closure_void!(tagging, restart_file, context)
    unrecorded = String[]
    reader = InputOutput.HDF5Reader(restart_file, context)
    try
        recorded = keys(InputOutput.HDF5.attrs(reader.file))
        for (family, voided) in pairs(tagging.closure_void)
            key = tag_closure_void_key(family)
            if key in recorded
                value = InputOutput.HDF5.read_attribute(reader.file, key)
                voided[] = !iszero(value)
            else
                voided[] = false
                push!(unrecorded, string(family))
            end
        end
    finally
        Base.close(reader)
    end
    restored = [string(f) for (f, voided) in pairs(tagging.closure_void) if voided[]]
    isempty(restored) || @warn(
        "The closure checks of the $(join(restored, ", ")) tags passed their \
        `void_above` level before the checkpoint $restart_file. Each of them \
        marks every row of this run `closure_void`, unless this run sets its \
        `void_above` to `~`."
    )
    isempty(unrecorded) || @warn(
        "The restart file $restart_file was written before the closure checks \
        recorded their void flags in a checkpoint. The closure checks of the \
        $(join(unrecorded, ", ")) tags start as not void. If a check passed \
        its `void_above` level before the checkpoint, its rows are marked \
        `closure_void` again only once it passes the level again."
    )
    return nothing
end
