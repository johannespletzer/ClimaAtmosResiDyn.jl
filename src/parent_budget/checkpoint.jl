#####
##### Parent-budget ledger: the restart transition and the callback rules
#####
##### A restart restores a state that no transaction produced. The checkpoint
##### carries the closing endpoints of the last step the ledger committed, and
##### the first transaction after the restart measures the restored state and
##### compares it against them exactly before it opens. A difference is a
##### change nobody accounted for. A custom callback runs between two
##### transactions on the accepted state; it is accepted only when it declares
##### itself read-only, and audit mode holds it to the declaration.

"""
    CheckpointEndpoints

The parent-budget endpoints a checkpoint carries: the step the ledger had
committed when the state was written, and one amount and status per declared
reservoir and quantity, as `(reservoir, quantity) => (amount, status)`.
"""
struct CheckpointEndpoints
    step::Int
    components::Dict{Tuple{Symbol, Symbol}, Tuple{BUDGET_ACCOUNTING_TYPE, Symbol}}
end

const CHECKPOINT_STEP_KEY = "parent_budget_step"
const CHECKPOINT_RESERVOIRS_KEY = "parent_budget_reservoirs"

checkpoint_amount_key(
    reservoir::Symbol,
    quantity::Symbol,
) = "parent_budget_endpoint_$(reservoir)_$(quantity)"
checkpoint_status_key(reservoir::Symbol, quantity::Symbol) =
    checkpoint_amount_key(reservoir, quantity) * "_status"

"""
    write_checkpoint_attributes!(file, ledger)

Write the ledger's current endpoint into the checkpoint's attributes. The
current endpoint is the one the open transaction opened on: after a commit it
is the closing endpoint of the committed step, and before the first commit it
is the opening endpoint of the run, and either is the state being written,
because the checkpoint callback runs after the ledger's. Nothing is written
for a run without a ledger, and a checkpoint written that way restarts a
ledger as unverified rather than refusing to.
"""
write_checkpoint_attributes!(file, ::Nothing) = nothing
function write_checkpoint_attributes!(file, adapter)
    endpoints = adapter.ledger.opening
    isnothing(endpoints) && error(
        "The parent-budget ledger has no endpoint to checkpoint: the checkpoint " *
        "callback ran before the ledger initialised.",
    )
    InputOutput.HDF5.write_attribute(file, CHECKPOINT_STEP_KEY, endpoints.step)
    names = [String(reservoir_name(e.reservoir)) for e in endpoints.reservoirs]
    InputOutput.HDF5.write_attribute(file, CHECKPOINT_RESERVOIRS_KEY, join(names, ","))
    for endpoint in endpoints.reservoirs
        reservoir = reservoir_name(endpoint.reservoir)
        for quantity in BUDGET_QUANTITIES
            c = budget_component(endpoint, quantity)
            InputOutput.HDF5.write_attribute(
                file,
                checkpoint_amount_key(reservoir, quantity),
                c.amount,
            )
            InputOutput.HDF5.write_attribute(
                file,
                checkpoint_status_key(reservoir, quantity),
                String(status_name(component_status(c))),
            )
        end
    end
    return nothing
end

"""
    read_checkpoint_endpoints(restart_file, context) -> Union{Nothing, CheckpointEndpoints}

The endpoints a checkpoint carries, or `nothing` when it was written without
a ledger.
"""
function read_checkpoint_endpoints(restart_file, context)
    reader = InputOutput.HDF5Reader(restart_file, context)
    try
        attributes = InputOutput.HDF5.attrs(reader.file)
        CHECKPOINT_STEP_KEY in keys(attributes) || return nothing
        step = Int(InputOutput.HDF5.read_attribute(reader.file, CHECKPOINT_STEP_KEY))
        names = split(
            InputOutput.HDF5.read_attribute(reader.file, CHECKPOINT_RESERVOIRS_KEY),
            ",",
        )
        components = Dict{Tuple{Symbol, Symbol}, Tuple{BUDGET_ACCOUNTING_TYPE, Symbol}}()
        for name in names, quantity in BUDGET_QUANTITIES
            reservoir = Symbol(name)
            amount = InputOutput.HDF5.read_attribute(
                reader.file,
                checkpoint_amount_key(reservoir, quantity),
            )
            status = InputOutput.HDF5.read_attribute(
                reader.file,
                checkpoint_status_key(reservoir, quantity),
            )
            components[(reservoir, quantity)] =
                (BUDGET_ACCOUNTING_TYPE(amount), Symbol(status))
        end
        return CheckpointEndpoints(step, components)
    finally
        Base.close(reader)
    end
end

"""
    RestartTransition

What the ledger found when it opened on a restored state: `:verified` when
the checkpoint carried endpoints and the restored state reproduced every one
of them exactly, `:unverified` when the checkpoint carried none. A restored
state that differs from its checkpoint is refused at initialisation instead
of becoming a record. `checkpoint_step` is the step the ledger had committed
when the checkpoint was written; the record after the restart is a new
segment, starting from the restored endpoint.
"""
struct RestartTransition
    status::Symbol
    checkpoint_step::Int
end

"""
    check_restart_transition(schema, measured, checkpoint) -> RestartTransition

Compare the restored state's endpoints with the checkpoint's, exactly. The
amounts are the same integrals of the same state in the same arithmetic, so
they are equal or something changed the state between the checkpoint and the
first transaction, and that change belongs to no step.
"""
function check_restart_transition(
    schema::BudgetSchema,
    measured::BudgetEndpoints,
    checkpoint::Union{Nothing, CheckpointEndpoints},
)
    isnothing(checkpoint) && return RestartTransition(:unverified, 0)
    expected = Set(keys(checkpoint.components))
    for endpoint in measured.reservoirs
        reservoir = reservoir_name(endpoint.reservoir)
        for quantity in BUDGET_QUANTITIES
            haskey(checkpoint.components, (reservoir, quantity)) || error(
                "The checkpoint carries no parent-budget endpoint for $quantity " *
                "in $reservoir, which this run declares. The restored state " *
                "cannot be checked against a checkpoint of another configuration.",
            )
            delete!(expected, (reservoir, quantity))
            amount, status = checkpoint.components[(reservoir, quantity)]
            c = budget_component(endpoint, quantity)
            status_name(component_status(c)) === status || error(
                "The checkpoint closed $quantity in $reservoir as $status, and " *
                "the restored state opens it as " *
                "$(status_name(component_status(c))). What a reservoir owns may " *
                "not change across a restart without being represented as a " *
                "transition.",
            )
            is_contributing(c) || continue
            c.amount == amount || error(
                "The restored state differs from its checkpoint: $quantity in " *
                "$reservoir was $amount when the checkpoint was written and is " *
                "$(c.amount) after the restart, a change of $(c.amount - amount) " *
                "that no transaction accounts for.",
            )
        end
    end
    isempty(expected) || error(
        "The checkpoint carries parent-budget endpoints for " *
        "$(join(string.(first.(collect(expected))), ", ")), which this run does " *
        "not declare. The restored state cannot be checked against a checkpoint " *
        "of another configuration.",
    )
    return RestartTransition(:verified, checkpoint.step)
end

# ============================================================================
# Custom callbacks
# ============================================================================

"""
    ReadOnlyCallback(callback)

A user callback declared not to write the state. With the ledger on, a custom
callback is accepted only inside this declaration, because a callback that
writes `Y` between two transactions is a change nothing accounts for. In
`AuditMode` the declaration is held to: the parent integrals of the state are
read before and after every firing, locally, and a firing that changed them
is an error.
"""
struct ReadOnlyCallback{C}
    callback::C
    function ReadOnlyCallback(callback::C) where {C}
        callback isa CTS.DiscreteCallback || error(
            "ReadOnlyCallback wraps a ClimaTimeSteppers.DiscreteCallback, got " *
            "$(typeof(callback)).",
        )
        return new{C}(callback)
    end
end
