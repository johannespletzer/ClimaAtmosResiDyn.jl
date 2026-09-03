using Test
import ClimaComms
import ClimaAtmos as CA

# The packet layout and the single collective.
#
# These are pure: no state, no space, no communication beyond a singleton
# context, which reduces a buffer by leaving it alone. That is the point. The
# rules a packet has to obey — a fixed deterministic layout, applicability that
# is not a value, a local buffer that cannot be read as a global one, and one
# reduction and no more — are all decidable without a distributed run, and the
# serial core has to get them right before a distributed run can.

const ATMOS = CA.ATMOSPHERE_ENDPOINT_GROUP
const SLAB = CA.SLAB_SURFACE_ENDPOINT_GROUP

singleton_context() =
    ClimaComms.SingletonCommsContext(ClimaComms.CPUSingleThreaded())

@testset "Parent-budget packet layout and reduction" begin

    @testset "The layout is fixed and deterministic" begin
        layout = CA.endpoint_packet_layout((ATMOS, SLAB))
        # Groups in the order given, quantities in BUDGET_QUANTITIES order. Every
        # rank builds this from the configuration alone, which is what makes an
        # elementwise reduction of the buffer well defined.
        @test layout.slots == [
            (ATMOS, :mass),
            (ATMOS, :water),
            (ATMOS, :energy),
            (SLAB, :mass),
            (SLAB, :water),
            (SLAB, :energy),
        ]
        @test CA.packet_length(layout) == 6
        @test CA.packet_index(layout, SLAB, :water) == 5
        # Rebuilding gives the same answer, so a residual is reproducible.
        @test CA.endpoint_packet_layout((ATMOS, SLAB)).slots == layout.slots
    end

    @testset "A layout has one slot per pair" begin
        @test_throws ErrorException CA.BudgetPacketLayout([
            (ATMOS, :mass),
            (ATMOS, :mass),
        ])
        layout = CA.endpoint_packet_layout((ATMOS,))
        # Asking for a slot the configuration does not have is refused rather
        # than defaulted, which would silently read someone else's value.
        @test_throws ErrorException CA.packet_index(layout, SLAB, :mass)
    end

    @testset "Inapplicable is not a measured zero" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        CA.set_local!(packet, ATMOS, :mass, 12.5)
        CA.set_inapplicable!(packet, ATMOS, :water)
        CA.set_local!(packet, ATMOS, :energy, 0.0)

        @test CA.packet_applicable(packet, ATMOS, :mass)
        @test !CA.packet_applicable(packet, ATMOS, :water)
        # A measured zero is applicable. That distinction is the whole reason
        # the flag is carried beside the value instead of being inferred from it.
        @test CA.packet_applicable(packet, ATMOS, :energy)
        @test CA.packet_local_value(packet, ATMOS, :water) == 0
    end

    @testset "A local buffer cannot be read as a global one" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        CA.set_local!(packet, ATMOS, :mass, 3.0)
        # Reading before the reduction would return this rank's share under the
        # name of a global total, which is wrong on every rank but one and looks
        # entirely ordinary.
        @test_throws ErrorException CA.packet_value(packet, ATMOS, :mass)
        @test CA.packet_local_value(packet, ATMOS, :mass) == 3.0

        CA.reduce_packet!(singleton_context(), packet)
        @test CA.packet_value(packet, ATMOS, :mass) == 3.0
    end

    @testset "A packet is reduced once" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        CA.set_local!(packet, ATMOS, :mass, 1.0)
        CA.reduce_packet!(singleton_context(), packet)
        # A second reduction would double every value and the result would look
        # perfectly ordinary.
        @test_throws ErrorException CA.reduce_packet!(
            singleton_context(),
            packet,
        )
        # Writing into a reduced buffer is refused for the same reason.
        @test_throws ErrorException CA.set_local!(packet, ATMOS, :mass, 2.0)
        @test_throws ErrorException CA.set_inapplicable!(packet, ATMOS, :mass)
    end

    @testset "Values are held in the accounting type" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        # A Float32 input is widened on the way in, so the buffer the collective
        # sees is already in the accounting type rather than being converted
        # after a narrower reduction has lost the information.
        CA.set_local!(packet, ATMOS, :mass, Float32(1.5))
        @test eltype(packet.values) === CA.BUDGET_ACCOUNTING_TYPE
        @test CA.packet_local_value(packet, ATMOS, :mass) isa
              CA.BUDGET_ACCOUNTING_TYPE
    end

    @testset "Groups are reported in layout order" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS, SLAB)))
        @test CA.packet_groups(packet) == [ATMOS, SLAB]
    end

    @testset "Endpoints need a reduced packet" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        CA.set_local!(packet, ATMOS, :mass, 1.0)
        CA.set_local!(packet, ATMOS, :water, 2.0)
        CA.set_local!(packet, ATMOS, :energy, 3.0)
        @test_throws ErrorException CA.budget_endpoints(packet, 0)

        CA.reduce_packet!(singleton_context(), packet)
        endpoints = CA.budget_endpoints(packet, 7)
        @test endpoints.step == 7
        @test length(endpoints.reservoirs) == 1
        atmosphere = only(endpoints.reservoirs)
        @test atmosphere.reservoir === CA.AtmosphereReservoir()
        @test atmosphere.mass.amount == 1.0
        @test CA.component_status(atmosphere.mass) isa CA.Measured
        # The evidence records how the number was obtained, which is what lets a
        # report distinguish a packed endpoint from a leg taken from an applied
        # increment.
        @test CA.component_route(atmosphere.mass) === :packed_global_reduction
        @test CA.component_source(atmosphere.mass) === ATMOS
    end

    @testset "An inapplicable slot becomes an inapplicable component" begin
        packet = CA.BudgetPacket(CA.endpoint_packet_layout((ATMOS,)))
        CA.set_local!(packet, ATMOS, :mass, 1.0)
        CA.set_inapplicable!(packet, ATMOS, :water)
        CA.set_local!(packet, ATMOS, :energy, 3.0)
        CA.reduce_packet!(singleton_context(), packet)
        atmosphere = only(CA.budget_endpoints(packet, 0).reservoirs)
        @test CA.component_status(atmosphere.water) isa CA.NotApplicable
        @test atmosphere.water.amount == 0
        @test !CA.is_contributing(atmosphere.water)
    end

    @testset "The exterior has no endpoint" begin
        # Asking for one is a category error rather than a missing value: the
        # model does not own that state, so there is nothing to measure.
        @test_throws ErrorException CA.endpoint_group(CA.ExteriorReservoir())
        @test_throws ErrorException CA.endpoint_reservoir(:exterior)
        @test CA.endpoint_group(CA.AtmosphereReservoir()) === ATMOS
        @test CA.endpoint_reservoir(ATMOS) === CA.AtmosphereReservoir()
    end
end
