#####
##### Parent-budget ledger: packet layout and the one collective
#####
##### A global integral is a collective. ARS343 has four stages and the coverage
##### registry lists dozens of paths, so a collective per quantity per leg would
##### cost on the order of a hundred per timestep. The contract's answer is one
##### packed collective per accepted step, and this file is what makes that
##### possible: local values go into a fixed-layout buffer, the buffer is reduced
##### once, and everything downstream reads the reduced buffer.
#####
##### Nothing here knows what a reservoir type is or what a leg means. It works
##### in plain group and quantity symbols, so the reduction mechanics stay out of
##### the journal and the transaction logic stays out of MPI.

"""
    ATMOSPHERE_ENDPOINT_GROUP

The packet group holding the atmospheric endpoint slots.

Endpoint groups are plain symbols so that this file needs no reservoir types.
`reservoir_name` returns the same symbols, which is what ties a group
back to its reservoir.
"""
const ATMOSPHERE_ENDPOINT_GROUP = :atmosphere

"""
    SLAB_SURFACE_ENDPOINT_GROUP

The packet group holding the slab surface endpoint slots. See
`ATMOSPHERE_ENDPOINT_GROUP`.
"""
const SLAB_SURFACE_ENDPOINT_GROUP = :slab_surface

"""
    BudgetPacketLayout(slots)

Which `(group, quantity)` pair each index of a packed buffer holds.

The layout is derived from the configuration, not from the order values happen
to be produced in. Every rank builds the same layout from the same
configuration, which is what makes a single elementwise reduction well defined,
and the same run builds the same layout every step, which is what makes a
residual reproducible.

It also bounds memory: a packet is sized from the layout rather than growing
with the number of values recorded.
"""
struct BudgetPacketLayout
    slots::Vector{Tuple{Symbol, Symbol}}
    index::Dict{Tuple{Symbol, Symbol}, Int}
    function BudgetPacketLayout(slots::Vector{Tuple{Symbol, Symbol}})
        index = Dict{Tuple{Symbol, Symbol}, Int}()
        for (i, slot) in enumerate(slots)
            haskey(index, slot) && error(
                "Budget packet layout lists $(slot[1])/$(slot[2]) twice. A " *
                "slot holds one value, so a repeated pair would make two " *
                "different quantities share one index.",
            )
            index[slot] = i
        end
        return new(slots, index)
    end
end

"""
    endpoint_packet_layout(groups)

The endpoint layout for `groups`: every quantity of every group, groups in the
order given and quantities in `BUDGET_QUANTITIES` order.

Inapplicable slots are still laid out. A dry configuration's water slot exists
and is marked inapplicable, so the layout depends on which reservoirs the
configuration has and not on what each of them happens to own. That keeps the
buffer length the same on every rank without anyone having to agree about
moisture separately.
"""
function endpoint_packet_layout(groups)
    slots = Tuple{Symbol, Symbol}[]
    for group in groups, quantity in BUDGET_QUANTITIES
        push!(slots, (group, quantity))
    end
    return BudgetPacketLayout(slots)
end

"""
    packet_length(layout) -> Int

How many values a packet with this layout holds.
"""
packet_length(layout::BudgetPacketLayout) = length(layout.slots)

"""
    packet_index(layout, group, quantity) -> Int

The buffer index of one slot. Errors when the layout has no such slot, rather
than returning a default that would silently read someone else's value.
"""
function packet_index(layout::BudgetPacketLayout, group::Symbol, quantity::Symbol)
    slot = (group, quantity)
    haskey(layout.index, slot) || error(
        "Budget packet layout has no slot for $group/$quantity. The layout " *
        "is built from the configuration, so a missing slot means the caller " *
        "and the configuration disagree about which reservoirs exist.",
    )
    return layout.index[slot]
end

"""
    BudgetPacket(layout)

A fixed-layout buffer of accounting-precision values, with an applicability flag
per slot and a record of whether it has been reduced.

`values` is what the collective reduces. `applicable` is **not** reduced: it is
derived from the configuration, so it is already identical on every rank, and
reducing it would spend a second collective to learn nothing.

The `is_reduced` flag exists so that reading a local value as though it were
global, or reducing the same packet twice, is an error rather than a wrong
number. Both are easy mistakes and neither is visible in the result.
"""
mutable struct BudgetPacket
    layout::BudgetPacketLayout
    values::Vector{BUDGET_ACCOUNTING_TYPE}
    applicable::Vector{Bool}
    is_reduced::Bool
end

BudgetPacket(layout::BudgetPacketLayout) = BudgetPacket(
    layout,
    zeros(BUDGET_ACCOUNTING_TYPE, packet_length(layout)),
    fill(false, packet_length(layout)),
    false,
)

"""
    set_local!(packet, group, quantity, value)

Write one rank's local contribution to a slot, and mark the slot applicable.

Refused once the packet has been reduced, because the reduced buffer is the
global answer and writing into it would corrupt a value nothing would recompute.
"""
function set_local!(
    packet::BudgetPacket,
    group::Symbol,
    quantity::Symbol,
    value,
)
    packet.is_reduced && error(
        "Budget packet has already been reduced; $group/$quantity cannot be " *
        "written now. Build the packet, reduce it once, then read it.",
    )
    i = packet_index(packet.layout, group, quantity)
    packet.values[i] = BUDGET_ACCOUNTING_TYPE(value)
    packet.applicable[i] = true
    return nothing
end

"""
    set_inapplicable!(packet, group, quantity)

Mark a slot as a quantity this configuration does not own.

The slot keeps its zero and takes no part in any total. An inapplicable slot is
not a measured zero, and the difference is the whole reason the flag exists.
"""
function set_inapplicable!(
    packet::BudgetPacket,
    group::Symbol,
    quantity::Symbol,
)
    packet.is_reduced && error(
        "Budget packet has already been reduced; $group/$quantity cannot be " *
        "written now.",
    )
    i = packet_index(packet.layout, group, quantity)
    packet.values[i] = zero(BUDGET_ACCOUNTING_TYPE)
    packet.applicable[i] = false
    return nothing
end

"""
    reduce_packet!(context, packet)

Sum the packet across every rank of `context` with one collective, and mark it
reduced.

Reducing twice is refused. A second reduction would double every value, and the
result would look entirely ordinary.
"""
function reduce_packet!(context, packet::BudgetPacket)
    packet.is_reduced && error(
        "Budget packet has already been reduced; reducing again would double " *
        "every value.",
    )
    reduce_accounting_sums!(context, packet.values)
    packet.is_reduced = true
    return packet
end

"""
    packet_value(packet, group, quantity)

The global value of one slot. Errors if the packet has not been reduced.
"""
function packet_value(packet::BudgetPacket, group::Symbol, quantity::Symbol)
    packet.is_reduced || error(
        "Budget packet has not been reduced; $group/$quantity currently holds " *
        "this rank's local share, not the global total.",
    )
    return @inbounds packet.values[packet_index(packet.layout, group, quantity)]
end

"""
    packet_local_value(packet, group, quantity)

The local value of one slot, before reduction. For tests and for assembling a
packet; a global total comes from `packet_value`.
"""
packet_local_value(packet::BudgetPacket, group::Symbol, quantity::Symbol) =
    @inbounds packet.values[packet_index(packet.layout, group, quantity)]

"""
    packet_applicable(packet, group, quantity) -> Bool

Whether this configuration owns the quantity in that group.
"""
packet_applicable(packet::BudgetPacket, group::Symbol, quantity::Symbol) =
    @inbounds packet.applicable[packet_index(packet.layout, group, quantity)]

"""
    packet_groups(packet) -> Vector{Symbol}

The groups the packet holds, in layout order and without repeats.
"""
function packet_groups(packet::BudgetPacket)
    groups = Symbol[]
    for (group, _) in packet.layout.slots
        group in groups || push!(groups, group)
    end
    return groups
end

# ============================================================================
# Endpoint packets
# ============================================================================

"""
    endpoint_groups(surface_temperature)

Which reservoir groups a configuration's endpoint packet holds.

The atmosphere always exists. The slab surface exists only for a
`SurfaceConditions.SlabOceanTemperature`; every other surface is exterior to the
model, so a flux into it is a boundary crossing rather than a reservoir change.
"""
function endpoint_groups(surface_temperature)
    has_surface_reservoir(surface_temperature) || return (ATMOSPHERE_ENDPOINT_GROUP,)
    return (ATMOSPHERE_ENDPOINT_GROUP, SLAB_SURFACE_ENDPOINT_GROUP)
end

"""
    local_endpoint_packet(Y, surface_temperature, microphysics_model)

Every reservoir's authoritative integrals over the part of the domain this rank
owns, in one buffer, with no communication.

Applicability comes from the configuration, never from field presence. A slab
carries `Y.sfc.water` even in a dry run, where it holds a permanent zero, so
presence of the field cannot distinguish an inapplicable quantity from a
measured one.
"""
function local_endpoint_packet(Y, surface_temperature, microphysics_model)
    layout = endpoint_packet_layout(endpoint_groups(surface_temperature))
    packet = BudgetPacket(layout)

    atmosphere = ATMOSPHERE_ENDPOINT_GROUP
    set_local!(packet, atmosphere, :mass, local_atmosphere_mass(Y))
    set_local!(packet, atmosphere, :energy, local_atmosphere_energy(Y))
    if owns_atmosphere_water(microphysics_model)
        set_local!(packet, atmosphere, :water, local_atmosphere_water(Y))
    else
        set_inapplicable!(packet, atmosphere, :water)
    end

    if has_surface_reservoir(surface_temperature)
        surface = SLAB_SURFACE_ENDPOINT_GROUP
        set_local!(
            packet,
            surface,
            :energy,
            local_surface_energy(Y, surface_temperature),
        )
        if owns_surface_water(surface_temperature, microphysics_model)
            water = local_surface_water(Y, surface_temperature)
            set_local!(packet, surface, :water, water)
            # The slab's mass and water are one endpoint projected twice, not
            # two measurements. Both read `Y.sfc.water`, so they cannot
            # disagree. Independent collection belongs to the transfer legs.
            set_local!(
                packet,
                surface,
                :mass,
                local_surface_mass(Y, surface_temperature),
            )
        else
            set_inapplicable!(packet, surface, :water)
            set_inapplicable!(packet, surface, :mass)
        end
    end

    return packet
end

"""
    reduced_endpoint_packet(Y, surface_temperature, microphysics_model)

`local_endpoint_packet` followed by `reduce_packet!`: one
collective for every endpoint of every reservoir.
"""
function reduced_endpoint_packet(Y, surface_temperature, microphysics_model)
    packet = local_endpoint_packet(Y, surface_temperature, microphysics_model)
    reduce_packet!(budget_context(Y), packet)
    return packet
end
