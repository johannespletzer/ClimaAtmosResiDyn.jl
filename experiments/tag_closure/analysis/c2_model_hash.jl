# C2 design: is the AtmosModel hash that restart.jl compares stable across
# processes, and does it change with the offset and the tag set? Run twice in
# separate processes and compare the printed values.
#
# Run from the root of a worktree at the commit under test, on a login node:
#   julia +1.11 --project=.buildkite experiments/tag_closure/analysis/c2_model_hash.jl
# Run it twice and compare. RESTART_GUARD_DESIGN.md.

import ClimaAtmos as CA
import ClimaComms
ClimaComms.@import_required_backends

tags(width) = [
    Dict{String, Any}(
        "name" => "strat",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => width,
        ),
    ),
    Dict{String, Any}(
        "name" => "tropo",
        "region" => Dict{String, Any}(
            "type" => "tanh_altitude",
            "z_center" => 750.0,
            "width" => width,
            "above" => false,
        ),
    ),
]
base = Dict{String, Any}(
    "config" => "column",
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "0M",
    "FLOAT_TYPE" => "Float64",
    "output_default_diagnostics" => false,
    "output_dir" => mktempdir(),
)
function model_hash(extra)
    config = CA.AtmosConfig(merge(base, extra); job_id = "c2_hash_check")
    params = CA.ClimaAtmosParameters(config)
    atmos = CA.get_atmos(config, params)
    return hash(atmos), hash(atmos.energy_source_tagging_model)
end
for (label, extra) in (
    ("no tags", Dict{String, Any}()),
    (
        "tags, offset 50000",
        Dict{String, Any}(
            "energy_source_tags" => tags(100.0),
            "energy_source_tag_offset" => 50000.0,
        ),
    ),
    (
        "tags, offset 50000 again",
        Dict{String, Any}(
            "energy_source_tags" => tags(100.0),
            "energy_source_tag_offset" => 50000.0,
        ),
    ),
    (
        "tags, offset 60000",
        Dict{String, Any}(
            "energy_source_tags" => tags(100.0),
            "energy_source_tag_offset" => 60000.0,
        ),
    ),
    (
        "tags, width 200",
        Dict{String, Any}(
            "energy_source_tags" => tags(200.0),
            "energy_source_tag_offset" => 50000.0,
        ),
    ),
    (
        "tags, repair off",
        Dict{String, Any}(
            "energy_source_tags" => tags(100.0),
            "energy_source_tag_offset" => 50000.0,
            "energy_source_tag_repair" => false,
        ),
    ),
)
    println(rpad(label, 28), " ", model_hash(extra))
end
