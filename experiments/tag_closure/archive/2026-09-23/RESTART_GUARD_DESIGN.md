# A restart guard for the energy source tags: design for C2

A design note, written on 2026-09-14 against `main` at `3b4b6056` and #72 at
`f3f48e97`. No model code is written. The owner approved C2 as a draft PR after
#72 merges, with T1: "Write the offset, the tag set, the transport and the
repair setting into the checkpoint, and fail with a named key on a mismatch."
This note fixes the keys, where they are written and read, and the error texts.
Line numbers are at those commits.

## What a restart does today

  - **The checkpoint.** `save_state_to_disk_func` (`callbacks.jl:290-316`)
    writes the state under `"Y"` and two attributes: `"time"`, and
    `"atmos_model_hash"`, which is `hash(p.atmos)`. The parent-budget ledger
    adds its own attributes (`callbacks.jl:311`,
    `parent_budget/checkpoint.jl:48-74`).
  - **The restart.** `handle_restart` (`restart.jl:58-84`) calls
    `get_state_restart` (`restart.jl:22-42`). That reads `Y` and the time, and
    compares the hash (`restart.jl:34-39`). A different hash gives one warning,
    "Restart file ... was constructed with a different AtmosModel", and the run
    goes on. `AtmosSimulation` calls it before the cache is built
    (`AtmosSimulations.jl:393-397`), so a check there fails in seconds, before
    any compile of the solve.
  - **The hash is a real signal, but only a warning.** Measured on the login
    node, in two separate processes at `3b4b6056`: the hash of the same config
    is the same in both. It changes when the offset goes from 50,000 to
    60,000 J/kg, when the regions' width goes from 100 to 200 m, and when the
    repair is switched off. It says nothing about which setting changed.
    *`analysis/c2_model_hash.jl`; the numbers are in this note only.*

What each change does to a restarted run, read from the code and not run:

| change across the restart | the state | what goes wrong |
|:-- |:-- |:-- |
| the offset `c` | loads | the tags partition `ρe_tot + c_old·ρ`. The model now reads them as a partition of `ρe_tot + c_new·ρ`, so `e_src_res` jumps by `(c_new − c_old)` J/kg everywhere, and every donor share is off by the same. Nothing refuses it. |
| a tag added, removed or renamed | its fields differ from what the model expects | not run. A missing field should fail on first access, somewhere in the cache or the first tendency. A field the model does not know is a tagged tracer by its prefix, so it would likely be transported and never attributed. T1 measures both. |
| a region or a source changed, same name | loads | the tag holds energy its old definition gave it and gains by the new one. The partition still adds up, so no residual shows it. |
| the transport | loads | the residual carried over was made by the other transport. An audit pair would compare a mixed run. |
| the repair | loads | the tags carried over were kept non-negative, or not, by the other setting. `e_src_fix` restarts at zero either way. |

## The design

### Keys

Four attributes on the checkpoint file, written only when the energy source tags
are on. Each is a string, so a restart compares strings, and the error can
quote both values as the config spells them.

| attribute | written as | example |
|:-- |:-- |:-- |
| `energy_source_tag_offset` | the offset as the config gives it, `repr(Float64(c))`, or `none` | `110495.0` |
| `energy_source_tags` | one line per tag, in state order: its name, its region, its sources | `strat tanh_altitude(z_center = 750.0, width = 100.0, above = true) none` |
| `energy_source_tag_transport` | `tracer` or `enthalpy` | `tracer` |
| `energy_source_tag_repair` | `true` or `false` | `true` |

  - **The offset** compares as `FT(parse(Float64, file)) == model.offset`, so a
    `Float32` run compares in its own type. `110495` is exact in `Float32`.
  - **The tag set** needs a region written in the config's own words. A new
    function, `tag_region_spec(region)`, gives one method per region type
    (`types.jl:2176-2256`): the `type` name and its fields in order. It is the
    inverse of `tag_region_from_config` (`tracer_config.jl:232`), and a test
    checks the round trip for each type. `repr` of the struct would work too,
    but it prints module-qualified type names, so a rename would refuse every
    old checkpoint.
  - **A version key,** `energy_source_tag_checkpoint = 1`, so a later change to
    the format can be told apart from a changed setting.

### Where they are written

A function beside the ledger's, called from `save_state_to_disk_func` after
`write_checkpoint_attributes!` (`callbacks.jl:311`):

    write_energy_source_checkpoint_attributes!(file, p.atmos.energy_source_tagging_model)

It is a no-op for `nothing`. Attributes are written as `"time"` is, through
`InputOutput.HDF5.write_attribute`. No run of the series has written a
checkpoint on more than one process, so that path stays untested by C2 and V5.

### Where they are read

`handle_restart` has the model and the file (`restart.jl:58-84`). After
`get_state_restart`:

    check_energy_source_checkpoint(restart_file, model.energy_source_tagging_model, Y, context)

It checks, in this order, and stops at the first mismatch:

 1. **The fields in `Y`.** The `ρe_src_*` names in `Y.c` against
    `energy_source_tag_state_names(model)` (`energy_source_tags.jl:127`). This
    needs no attribute, so it also covers checkpoints written before C2.
 2. **The version key.** Missing: the checkpoint predates C2. Then warn once
    that the offset, the regions, the transport and the repair cannot be
    checked, and go on, as the ledger does with a checkpoint that carries no
    endpoints (`parent_budget/checkpoint.jl:76-81`).
 3. **The offset,** then **each tag's line,** then **the transport,** then
    **the repair.**

A checkpoint with tags restarted into a model without them, and the reverse,
are caught by step 1.

### Error texts

Each names the key, the file, both values, what goes wrong, and what to do.

  - **Offset.** "The restart file `<file>` was written with
    `energy_source_tag_offset: 50000.0`, and this run sets `110495.0`. The tags
    in the file partition `ρe_tot + 50000.0·ρ`. Under the new offset they no
    longer add up to the total they partition, and `e_src_res` would jump by the
    difference, 60495.0 J/kg. Restart with the same offset, or start a new run
    from the initial condition."
  - **Tag set, fields.** "The restart file `<file>` holds the energy source tags
    `strat, tropo, rad`, and this run configures `strat, tropo, sfc`. Missing
    from the file: `sfc`. Not configured: `rad`. Restart with the same
    `energy_source_tags`, or start a new run."
  - **Tag set, definition.** "The energy source tag `strat` in the restart file
    `<file>` was defined as `tanh_altitude(z_center = 750.0, width = 100.0,
    above = true)`, with sources `none`. This run defines it as
    `tanh_altitude(z_center = 750.0, width = 200.0, above = true)`, with sources
    `none`. The tag holds energy by its old definition, so under a new one its
    provenance would mix the two. Keep the definition, or start a new run."
  - **Transport.** "The restart file `<file>` was written under
    `energy_source_tag_transport: tracer`, and this run sets `enthalpy`. The
    closure residual in the file was made by the other transport. Keep the
    transport, or start a new run."
  - **Repair.** "The restart file `<file>` was written with
    `energy_source_tag_repair: true`, and this run sets `false`. The tags in the
    file were kept non-negative by the repair, and would not be from here on.
    Keep the setting, or start a new run."

## T1, the tests

  - **Integration,** in item 7 of `energy_source_tags_integration.jl`, which
    already writes `day0.20.hdf5` with an offset and reuses its compile:
      - a restart with the same config gives the same state, bit for bit, as
        item 5 does without an offset;
      - a restart with `energy_source_tag_offset: 60000.0` throws, and the
        message names `energy_source_tag_offset`. It fails in `handle_restart`,
        before the cache, so it costs no compile.
      - a restart with a changed region width throws, naming the tag.
  - **Unit,** on a small HDF5 file with no simulation: the writer and the
    checker for each key; a missing version key warns and passes; the region
    spec's round trip through `tag_region_from_config` for every region type.
  - **The C3 check** that T1 listed is already in #72: item 10 compares the
    audit's hyperdiffusion against the whole change in `E`. Nothing to add
    unless the owner meant something else.

## V5, after C2

Two segments against one run, with the offset and the repair, on C5's column:
the state bit for bit at the end, the records carried through, and the closure
table's rows the same. V5 is approved for up to 2 jobs.

## Questions for the owner

 1. **The process records.** `energy_process_record` is not in the approved
    list. A changed record set fails the same way a changed tag set does, by
    step 1's kind of field check. Add `prc_e_*` and `prc_q_*` to that check?
    It needs no attribute.
 2. **#77's spin-up reference.** Under #77 the closure check takes its reference
    residual 1 h after the run starts, and on a restart 1 h after the restart
    (`get_callbacks.jl:923-933` in #77, `call_every_dt` with
    `skip_first = true`). So `residual_since_spin_up` starts over in each
    segment. That is already the third of #77's choices under decision 2 of
    `OPERATIONAL_TODO.md`. The alternative is a fifth key: carry the reference
    in the checkpoint, so the column continues across a restart. Either way it
    decides what V5 compares in the closure tables.
 3. **An override.** Should a user be able to switch a setting on purpose, for
    example spin up under `tracer` and restart into the audit? That would be a
    new config key, and a default. The approved design has none; this note keeps
    it that way.
 4. **Tags from a restart without them.** A spun-up atmosphere cannot take tags
    today: step 1 refuses it, and so, probably, does the state. Starting tags
    from a tagless checkpoint, each region tag set to its mask times `E`, would
    be new model code. Out of C2's scope; worth an N item?

## Size

About 120 lines of model code (the writer, the checker, `tag_region_spec`) and
100 of tests. S to M, as the to-do list says.
