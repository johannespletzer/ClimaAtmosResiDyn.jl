#####
##### The applied-update event
#####
##### One bracket around every process that writes a parent field. What it
##### feeds depends on what is configured: the tagging families and the process
##### records take the increment for the labels they know, and the parent-budget
##### ledger takes the increment of `ρ`, `ρq_tot` and `ρe_tot` for the rows its
##### coverage registry names. The tendency code opens and closes one event per
##### process and never asks who is listening.

"""
    open_ledger_event!(ledger, Yₜ, event::Symbol)
    close_ledger_event!(ledger, Yₜ, event::Symbol)

Open and close the ledger half of an applied-update event. With the ledger off,
`ledger` is `nothing` and both are no-ops that compile away. With it on, the
adapter's methods read the parent fields of `Yₜ` before and after the process
while the adapter is metering a tendency evaluation, and do nothing otherwise.
Defined here, before the tendency code, so that code names one function; the
adapter adds the methods for its own type.

The implicit path calls these directly rather than through
`open_applied_update!`, because the tag brackets on that path are deliberately
partial and widening them would change tagged results.
"""
open_ledger_event!(::Nothing, Yₜ, event::Symbol) = nothing
close_ledger_event!(::Nothing, Yₜ, event::Symbol) = nothing

"""
    open_applied_update!(Yₜ, p, event::Symbol)
    close_applied_update!(Yₜ, Y, p, event::Symbol)

Open and close the applied-update event `event` around one process of the
explicit tendency: everything the process adds to `Yₜ` between the two calls
is that event's applied update.

Three consumers read the bracket. The tagging families and the process
records take it for the labels in `KNOWN_TAG_SOURCES`, through
[`snapshot_tags!`](@ref) and `attribute_tags!`. A label outside that list
leaves them untouched, so bracketing a transport or diffusion term for the
ledger changes no tagged result. The parent-budget ledger takes every label the
coverage registry names, through [`open_ledger_event!`](@ref), and is a no-op
when it is off.

The ledger reads `Yₜ` before the tag half writes into it, so the tags' own
tendencies never enter a parent integral. A bracket may not nest, and a label
may open once per evaluation; the ledger refuses both when it is metering.
"""
function open_applied_update!(Yₜ, p, event::Symbol)
    open_ledger_event!(p.parent_budget, Yₜ, event)
    event in KNOWN_TAG_SOURCES && snapshot_tags!(p, Yₜ, event)
    return nothing
end

function close_applied_update!(Yₜ, Y, p, event::Symbol)
    close_ledger_event!(p.parent_budget, Yₜ, event)
    event in KNOWN_TAG_SOURCES && attribute_tags!(Yₜ, Y, p, event)
    return nothing
end
