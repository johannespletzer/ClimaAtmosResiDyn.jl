#####
##### The applied-update event
#####
##### An open and a close call around every process that writes a parent field.
##### What the event feeds depends on what is configured. The tagging families
##### and the process records take the process's tendency for the labels they
##### know. The parent budget takes the change of `ρ`, `ρq_tot` and `ρe_tot`
##### for the events its coverage registry names. The tendency code opens and
##### closes one event per process and never asks who is listening.

"""
    open_parent_budget_event!(parent_budget, Yₜ, event::Symbol)
    close_parent_budget_event!(parent_budget, Yₜ, Y, p, event::Symbol)

Open and close the parent-budget half of an applied-update event. With the parent budget
off, `parent_budget` is `nothing` and both are no-ops that compile away. With it on, the
adapter's methods read the parent fields of `Yₜ` before and after the process
while the adapter is metering a tendency evaluation, and do nothing otherwise.
The close half also sees the state and the cache, which is where a transfer
event's legs are read from their own flux fields. These generic methods are
defined here, before the tendency code, and the adapter adds the methods for
its own type.

The implicit path calls these directly rather than through
`open_applied_update!`. On that path each tag family sees only some of the
processes, and widening that would change tagged results. So the tag calls stay
beside the parent-budget calls and are not folded into one event.
"""
open_parent_budget_event!(::Nothing, Yₜ, event::Symbol) = nothing
close_parent_budget_event!(::Nothing, Yₜ, Y, p, event::Symbol) = nothing

"""
    open_applied_update!(Yₜ, p, event::Symbol)
    close_applied_update!(Yₜ, Y, p, event::Symbol)

Open and close the applied-update event `event` around one process of the
explicit tendency: everything the process adds to `Yₜ` between the two calls
is that event's applied update.

Three consumers read the event. The tagging families and the process
records take it for the labels in `KNOWN_TAG_SOURCES`, through
[`snapshot_tags!`](@ref) and `attribute_tags!`. A label outside that list
leaves them untouched, so an event around a transport or diffusion term for the
parent budget changes no tagged result. The parent budget takes every label the
coverage registry names, through [`open_parent_budget_event!`](@ref), and is a no-op
when it is off.

The parent budget reads `Yₜ` before the tag half writes into it, so the tags' own
tendencies never enter a parent integral. Events do not nest, and a label may
open once per evaluation. The parent budget refuses both when it is metering.
"""
function open_applied_update!(Yₜ, p, event::Symbol)
    open_parent_budget_event!(p.parent_budget, Yₜ, event)
    event in KNOWN_TAG_SOURCES && snapshot_tags!(p, Yₜ, event)
    return nothing
end

function close_applied_update!(Yₜ, Y, p, event::Symbol)
    close_parent_budget_event!(p.parent_budget, Yₜ, Y, p, event)
    event in KNOWN_TAG_SOURCES && attribute_tags!(Yₜ, Y, p, event)
    return nothing
end
