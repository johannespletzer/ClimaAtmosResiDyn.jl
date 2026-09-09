#####
##### Parent-budget ledger: the κ calibration table
#####
##### The tolerance's arithmetic term carries a factor κ that covers reduction
##### order and rank dependence. The contract says it is calibrated and never
##### chosen. A named configuration is run for a fixed number of accepted
##### steps with every term of the parent identity measured. The largest ratio
##### of the residual to the arithmetic term evaluated with κ = 1 is recorded.
##### κ is four times that ratio, rounded up to a power of two. The table has
##### one row per backend, state float type and rank count. Each row is
##### committed with the configuration, the commit and the date. A run whose
##### row is missing has no tolerance and every numeric verdict is blocked.

"""
    CALIBRATION_TABLE_PATH

The committed calibration table, `kappa_calibration.yaml` beside this file.
"""
const CALIBRATION_TABLE_PATH = joinpath(@__DIR__, "kappa_calibration.yaml")

"""
    CALIBRATION_STEPS

The accepted steps the protocol runs the named configuration for.
"""
const CALIBRATION_STEPS = 50

"""
    CalibrationRow

One row of the table: the backend, the state float type and the rank count it
applies to, the κ it fixes, and the provenance the protocol requires.
"""
struct CalibrationRow
    backend::String
    float_type::String
    ranks::Int
    kappa::Float64
    configuration::String
    steps::Int
    worst_ratio::Float64
    commit::String
    date::String
end

"""
    read_calibration_table(path = CALIBRATION_TABLE_PATH) -> Vector{CalibrationRow}

Read the committed rows. A malformed row is an error, never a default.
"""
function read_calibration_table(path = CALIBRATION_TABLE_PATH)
    table = YAML.load_file(path)
    table["version"] == 1 || error(
        "The κ calibration table at $path has version $(table["version"]); " *
        "this code reads version 1.",
    )
    rows = CalibrationRow[]
    for entry in table["rows"]
        # The loader types a date and a bare hash for us; the row keeps strings.
        row = CalibrationRow(
            string(entry["backend"]),
            string(entry["float_type"]),
            Int(entry["ranks"]),
            Float64(entry["kappa"]),
            string(entry["configuration"]),
            Int(entry["steps"]),
            Float64(entry["worst_ratio"]),
            string(entry["commit"]),
            string(entry["date"]),
        )
        row.kappa > 0 && isinteger(log2(row.kappa)) || error(
            "The κ calibration row for $(row.backend), $(row.float_type), " *
            "$(row.ranks) rank(s) has κ = $(row.kappa), which is not a power of two.",
        )
        row.kappa >= 4 * row.worst_ratio || error(
            "The κ calibration row for $(row.backend), $(row.float_type), " *
            "$(row.ranks) rank(s) has κ = $(row.kappa) below four times its " *
            "worst ratio $(row.worst_ratio).",
        )
        push!(rows, row)
    end
    return rows
end

"""
    backend_name(context) -> String

Return the name the table keys a backend by. It is the device type of the
communications context.
"""
backend_name(context) = String(nameof(typeof(ClimaComms.device(context))))

"""
    calibration_row(rows, backend, float_type, ranks) -> Union{Nothing, CalibrationRow}

Return the row for one backend, float type and rank count, or `nothing`.
"""
function calibration_row(
    rows,
    backend::AbstractString,
    float_type::AbstractString,
    ranks::Int,
)
    for row in rows
        row.backend == backend && row.float_type == float_type && row.ranks == ranks &&
            return row
    end
    return nothing
end

"""
    calibrated_tolerances(context, float_type; rows = read_calibration_table())
        -> Union{Nothing, Dict{Symbol, BudgetTolerance}}

Return the tolerances the committed table gives a run on `context` with state
float type `float_type`. Every quantity gets no floor, no relative term, and
the row's κ. Return `nothing` when the table has no row for the run, which
leaves every numeric verdict blocked.
"""
function calibrated_tolerances(context, float_type; rows = read_calibration_table())
    row = calibration_row(
        rows,
        backend_name(context),
        String(nameof(float_type)),
        ClimaComms.nprocs(context),
    )
    isnothing(row) && return nothing
    FT = BUDGET_ACCOUNTING_TYPE
    tolerance = BudgetTolerance(;
        absolute = zero(FT),
        relative = zero(FT),
        scale = one(FT),
        kappa = FT(row.kappa),
    )
    return Dict(quantity => tolerance for quantity in BUDGET_QUANTITIES)
end

"""
    protocol_tolerances() -> Dict{Symbol, BudgetTolerance}

Return the tolerances the calibration protocol runs with. They hold the
arithmetic term alone, at κ = 1, so that a reconciliation's tolerance is the
term the residual is compared with.
"""
protocol_tolerances() = Dict(
    quantity => BudgetTolerance(;
        absolute = 0.0,
        relative = 0.0,
        scale = 1.0,
        kappa = 1.0,
    ) for quantity in BUDGET_QUANTITIES
)

"""
    calibration_configuration() -> Dict{String, Any}

Return the named configuration the protocol runs. It is a moist DYCOMS_RF02
column with zero-moment microphysics, idealized radiation and a slab ocean, in
summary mode, at `Float64`, with every reservoir the ledger knows. The caller
builds an `AtmosConfig` from it and adds the output directory.
"""
calibration_configuration() = Dict{String, Any}(
    "initial_condition" => "DYCOMS_RF02",
    "z_max" => 1500.0,
    "z_elem" => 30,
    "z_stretch" => false,
    "rad" => "DYCOMS",
    "microphysics_model" => "0M",
    "prognostic_surface" => "SlabOceanSST",
    "config" => "column",
    "FLOAT_TYPE" => "Float64",
    "dt" => "10secs",
    "t_end" => "600secs",
    "output_default_diagnostics" => false,
    "parent_budget_mode" => "summary",
)

const CALIBRATION_CONFIGURATION_NAME = "parent_budget_calibration_column"

"""
    worst_parent_ratio(commit) -> Float64

Return the largest ratio of the parent residual to its tolerance over the
applicable rows of one commit. Under `protocol_tolerances` the tolerance is
the arithmetic term at κ = 1, and this is the number the protocol records.
"""
function worst_parent_ratio(commit::BudgetCommit)
    worst = 0.0
    for r in commit.parent
        r.applicable || continue
        isnothing(r.tolerance) && error("The calibration run has no tolerance.")
        isempty(r.blocked_by) || error(
            "The calibration run is blocked by $(r.blocked_by); every term of " *
            "the parent identity has to be measured.",
        )
        worst = max(worst, abs(r.residual) / r.tolerance)
    end
    return worst
end

"""
    kappa_from_ratio(worst_ratio) -> Float64

Return four times the worst ratio, rounded up to a power of two, and at least one.
"""
kappa_from_ratio(worst_ratio) = max(1.0, 2.0^ceil(log2(4 * worst_ratio)))
