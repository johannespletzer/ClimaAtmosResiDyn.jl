# Tagged prognostic energy tracers (masks, state builders, config parsing)
include("tagged_tracers.jl")
# The grosses and counts of the tags' cache ledgers, and their state ledgers
# per mechanism with the gross per step.
include("tag_throughput.jl")
# Tagged prognostic water tracers (reuses the regions and masks defined above)
include("tagged_water.jl")
# The rain and snow parts of the water tags (`water_tag_precipitation`).
include("tagged_water_precipitation.jl")
# Energy source tags (ρe_src_*, the energy counterpart of the water tags)
include("energy_source_tags.jl")
# The residual report of the energy source tags' closure check.
include("energy_source_report.jl")
# After the energy source tags, whose weight-free exchange helpers it uses.
include("tagged_water_edmf.jl")
# The terms the energy copies get as `mseʲ` does and an updraft tracer does not.
include("energy_source_copy_mirrors.jl")
# It calls the diffusion and hyperdiffusion helpers, which load later.
include("tagged_water_leaks.jl")
# The 0M rain-out split by subdomain, after the exchange's helpers it reuses.
include("tagged_water_rainout.jl")
# Increment transport of the water tags, after the default mode's flux helper it
# reuses.
include("tagged_water_increment.jl")
# The water tags' accepted applications, an opt-in producer
# (`water_tag_applications`). After the writers it meters, for their part types.
include("water_tag_applications.jl")
# Process-change records (the signed change of each process, prognostic but not transported)
include("process_record.jl")
include("energy_source_checkpoint.jl")
include("water_tag_checkpoint.jl")
# The closure checks' void flags, carried through a checkpoint.
include("tag_closure_checkpoint.jl")
