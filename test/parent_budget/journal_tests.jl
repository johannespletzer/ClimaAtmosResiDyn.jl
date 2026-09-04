using Test
import ClimaAtmos.Internals.ParentBudget as PB

# Journal, schema and transaction rules for the parent-budget ledger.
#
# These tests are deliberately state-free. They exercise the rules the ledger
# enforces rather than the physics it will later measure: expectations come from
# the schema and never from the records, a leg is recorded once, an unknown
# component blocks rather than reading as zero, an envelope and its
# decomposition never land in one sum, a final accepted-state map is a term of
# the primary identity and not an attribution channel, an exterior crossing is
# never tested as an internal cancellation, and a residual is a subtraction and
# never an entry.

const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP
const SLAB = PB.SLAB_SURFACE_ENDPOINT_GROUP

# Components, with the evidence every constructor requires.
mval(FT, x) = PB.measured(FT(x); method = :synthetic, source = :test)
zval(FT) = PB.invariant_zero(FT; proof = :writes_no_such_field, source = :test)
naval(FT) = PB.not_applicable(FT)
unkval(FT) = PB.unknown_component(FT)

# A leg with everything defaulted, so a test only names what it is about.
function test_leg(
    FT;
    event = :ev,
    leg = :atmos,
    reservoir = PB.AtmosphereReservoir(),
    channel = :explicit_main,
    level = PB.ChannelEnvelope(),
    mass = naval(FT),
    water = naval(FT),
    energy = naval(FT),
    path = PB.EquationTerm(),
    process = :test,
    phase = :explicit,
    step = 1,
    stage = 0,
    occurrence = 1,
    weight = one(FT),
    measured_at = :accepted_state,
)
    return PB.BudgetLeg{FT}(;
        event,
        leg,
        reservoir,
        channel,
        level,
        mass,
        water,
        energy,
        path,
        process,
        phase,
        step,
        stage,
        occurrence,
        weight,
        measured_at,
    )
end

# A configuration's declarations. The schema and the endpoints below have to
# agree about applicability, because the ledger checks that they do.
function test_schema(;
    slab = false,
    atmosphere_water = true,
    slab_water = slab,
    channels = PB.ChannelSpec[],
    final_maps = PB.FinalMapSpec[],
    events = PB.TransferEventSpec[],
)
    reservoirs = PB.ReservoirSpec[
        PB.ReservoirSpec(PB.AtmosphereReservoir(), (true, atmosphere_water, true)),
    ]
    control_volumes = PB.ControlVolume[PB.ATMOSPHERE_ONLY]
    if slab
        push!(
            reservoirs,
            PB.ReservoirSpec(
                PB.SlabSurfaceReservoir(),
                (slab_water, slab_water, true),
            ),
        )
        push!(control_volumes, PB.ATMOSPHERE_AND_SURFACE)
    end
    return PB.BudgetSchema(;
        reservoirs,
        control_volumes,
        channels,
        final_maps,
        transfer_events = events,
    )
end

# Endpoints with the atmosphere alone, or with a slab surface that owns energy
# and, in a moist configuration, water and the mass that goes with it. A `nothing`
# amount means the configuration does not own that quantity.
function test_endpoints(FT, step; m, w, e, sfc_w = nothing, sfc_e = nothing)
    reservoirs = [
        PB.ReservoirEndpoint{FT}(;
            reservoir = PB.AtmosphereReservoir(),
            mass = isnothing(m) ? naval(FT) : mval(FT, m),
            water = isnothing(w) ? naval(FT) : mval(FT, w),
            energy = isnothing(e) ? naval(FT) : mval(FT, e),
        ),
    ]
    if !isnothing(sfc_e)
        # The slab's mass and water are one endpoint projected twice.
        sfc = isnothing(sfc_w) ? naval(FT) : mval(FT, sfc_w)
        push!(
            reservoirs,
            PB.ReservoirEndpoint{FT}(;
                reservoir = PB.SlabSurfaceReservoir(),
                mass = sfc,
                water = sfc,
                energy = mval(FT, sfc_e),
            ),
        )
    end
    return PB.BudgetEndpoints{FT}(reservoirs, step)
end

function open_ledger(FT, schema, endpoints)
    ledger = PB.BudgetLedger{FT}(schema)
    PB.open_transaction!(ledger, endpoints)
    return ledger
end

# A tolerance loose enough that only a real discrepancy fails it, so a test that
# is about statuses is not also a test of arithmetic.
loose_tolerance(FT) = Dict(
    quantity => PB.BudgetTolerance(;
        absolute = FT(1e-6),
        relative = zero(FT),
        scale = one(FT),
        kappa = zero(FT),
    ) for quantity in PB.BUDGET_QUANTITIES
)

parent_result(commit, quantity, cv) = only(
    filter(
        r -> r.quantity === quantity && r.control_volume === cv,
        commit.parent,
    ),
)

attribution_results(commit, channel) =
    filter(r -> r.channel === channel, commit.attribution)

attribution_result(commit, channel, quantity, cv) = only(
    filter(
        r ->
            r.channel === channel &&
                r.quantity === quantity &&
                r.control_volume === cv,
        commit.attribution,
    ),
)

transfer_result(commit, event, quantity, cv) = only(
    filter(
        r ->
            r.event === event &&
                r.quantity === quantity &&
                r.control_volume === cv,
        commit.transfer,
    ),
)

@testset "Parent-budget journal" begin
    FT = Float64

    @testset "Evidence invariants hold at direct construction" begin
        # The rules live in the inner constructor, so a record built straight
        # from BudgetComponent obeys them as much as one built through a helper.
        @test_throws ErrorException PB.BudgetComponent{FT}(
            1.0,
            PB.BudgetEvidence(; status = PB.Measured()),
        )
        @test_throws ErrorException PB.BudgetComponent{FT}(
            0.0,
            PB.BudgetEvidence(; status = PB.Measured()),
        )
        @test_throws ErrorException PB.BudgetComponent{FT}(
            1.0,
            PB.BudgetEvidence(; status = PB.InvariantZero(), method = :proof),
        )
        @test_throws ErrorException PB.BudgetComponent{FT}(
            0.0,
            PB.BudgetEvidence(; status = PB.InvariantZero()),
        )
        @test_throws ErrorException PB.BudgetComponent{FT}(
            1.0,
            PB.BudgetEvidence(; status = PB.NotApplicable()),
        )
        @test_throws ErrorException PB.BudgetComponent{FT}(
            1.0,
            PB.BudgetEvidence(; status = PB.UnknownComponent()),
        )

        good = PB.BudgetComponent{FT}(
            2.5,
            PB.BudgetEvidence(;
                status = PB.Measured(),
                method = :applied_increment,
                source = :test,
                route = :packed_global_reduction,
            ),
        )
        @test good.amount == 2.5
        @test PB.component_method(good) === :applied_increment
        @test PB.component_source(good) === :test
        @test PB.component_route(good) === :packed_global_reduction

        # The helpers cannot be used to sidestep any of it either.
        @test_throws UndefKeywordError PB.measured(FT(1))
        @test_throws ErrorException PB.invariant_zero(FT; proof = :unspecified)
    end

    @testset "Statuses do different things" begin
        @test PB.is_contributing(mval(FT, 3))
        @test PB.is_contributing(zval(FT))
        @test !PB.is_contributing(naval(FT))
        @test !PB.is_contributing(unkval(FT))

        @test PB.is_blocking(unkval(FT))
        @test !PB.is_blocking(naval(FT))

        # An inapplicable quantity is not a measured zero, and the difference is
        # what keeps a dry model's water from reading as a closed budget.
        @test !PB.is_applicable(naval(FT))
        @test PB.is_applicable(unkval(FT))
        @test PB.status_name(PB.component_status(unkval(FT))) === :unknown
    end

    @testset "A schema refuses to contradict itself" begin
        atmosphere =
            PB.ReservoirSpec(PB.AtmosphereReservoir(), (true, true, true))
        @test_throws ErrorException PB.BudgetSchema(;
            reservoirs = PB.ReservoirSpec[],
            control_volumes = PB.ControlVolume[],
        )
        # A control volume naming a reservoir nothing declared.
        @test_throws ErrorException PB.BudgetSchema(;
            reservoirs = [atmosphere],
            control_volumes = [PB.ATMOSPHERE_AND_SURFACE],
        )
        # A channel writing a reservoir nothing declared.
        @test_throws ErrorException PB.BudgetSchema(;
            reservoirs = [atmosphere],
            control_volumes = [PB.ATMOSPHERE_ONLY],
            channels = [PB.ChannelSpec(:implicit, SLAB)],
        )
        # A repeated declaration, which would let one shadow the other.
        @test_throws ErrorException PB.BudgetSchema(;
            reservoirs = [atmosphere, atmosphere],
            control_volumes = [PB.ATMOSPHERE_ONLY],
        )
        # A final accepted-state map is not an attribution channel and cannot be
        # declared as one, and an attribution channel is not a final map.
        @test_throws ErrorException PB.ChannelSpec(:dss!, ATMOS)
        @test_throws ErrorException PB.FinalMapSpec(:explicit_main, ATMOS)
        @test isempty(intersect(PB.FINAL_STATE_MAPS, PB.ATTRIBUTION_CHANNELS))
    end

    @testset "Transfer topology is declared, and checked when it is" begin
        # An exterior crossing has one modeled side and names what it crosses
        # to. The counterparty is metadata; nothing numerical is ever made for it.
        exterior = PB.TransferEventSpec(
            :xfer_toa,
            PB.ExteriorCrossing(),
            :explicit_main,
            ((ATMOS, :atmosphere),);
            counterparty = :space,
        )
        @test PB.topology_name(exterior.topology) === :exterior
        @test !PB.tests_cancellation(exterior.topology)
        @test exterior.counterparty === :space
        @test PB.event_reservoir_names(exterior) == [ATMOS]

        coupled = PB.TransferEventSpec(
            :xfer_surface,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface)),
        )
        @test PB.tests_cancellation(coupled.topology)
        @test isnothing(coupled.counterparty)

        # An exterior crossing without a counterparty, a modeled event with one,
        # a one-sided cancellation, a leg in the exterior, and a repeated leg
        # are all refused at construction.
        @test_throws ErrorException PB.TransferEventSpec(
            :bad,
            PB.ExteriorCrossing(),
            :implicit,
            ((ATMOS, :atmosphere),),
        )
        @test_throws ErrorException PB.TransferEventSpec(
            :bad,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface));
            counterparty = :space,
        )
        @test_throws ErrorException PB.TransferEventSpec(
            :bad,
            PB.InternalTransfer(),
            :implicit,
            ((ATMOS, :atmosphere),),
        )
        @test_throws ErrorException PB.TransferEventSpec(
            :bad,
            PB.ExteriorCrossing(),
            :implicit,
            ((ATMOS, :atmosphere), (PB.EXTERIOR_LABEL, :space));
            counterparty = :space,
        )
        @test_throws ErrorException PB.TransferEventSpec(
            :bad,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (ATMOS, :atmosphere), (SLAB, :surface)),
        )
    end

    @testset "A record the schema does not declare is refused" begin
        schema = test_schema(;
            channels = [PB.ChannelSpec(:explicit_main, ATMOS)],
            final_maps = [PB.FinalMapSpec(:dss!, ATMOS)],
        )
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 1, w = 1, e = 1))

        # An undeclared channel belongs to no attribution identity, so it fails
        # closed rather than becoming a row nothing checks.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; channel = :post_implicit, mass = mval(FT, 1)),
        )
        # An undeclared reservoir has no endpoint to reconcile against.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; reservoir = PB.SlabSurfaceReservoir()),
        )
        # An undeclared final map, and a declared one in the wrong reservoir.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; level = PB.FinalMap(), channel = :lim!),
        )
        # An undeclared transfer event has no topology, so nothing knows which
        # test would apply to it.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; level = PB.ReservoirTransfer(), event = :xfer_unknown),
        )
        # A channel the schema declares is accepted.
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 1)))
        @test length(ledger.legs) == 1
    end

    @testset "A declared event only accepts the legs it declares" begin
        coupled = PB.TransferEventSpec(
            :xfer_surface,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface)),
        )
        schema = test_schema(;
            slab = true,
            channels = [
                PB.ChannelSpec(:implicit, (ATMOS, SLAB); requires_envelope = false),
            ],
            events = [coupled],
        )
        ledger = open_ledger(
            FT,
            schema,
            test_endpoints(FT, 0; m = 1, w = 1, e = 1, sfc_w = 1, sfc_e = 1),
        )
        transfer_leg(; kwargs...) = test_leg(
            FT;
            event = :xfer_surface,
            level = PB.ReservoirTransfer(),
            channel = :implicit,
            kwargs...,
        )
        # A modeled leg the specification did not declare would take part in a
        # cancellation nobody expected.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            transfer_leg(; leg = :invented),
        )
        # A declared leg in the wrong channel.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            transfer_leg(; leg = :atmosphere, channel = :explicit_main),
        )
        PB.record_leg!(ledger, transfer_leg(; leg = :atmosphere))
        PB.record_leg!(
            ledger,
            transfer_leg(; leg = :surface, reservoir = PB.SlabSurfaceReservoir()),
        )
        @test length(ledger.legs) == 2
    end

    @testset "A leg is recorded once" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 1, w = 1, e = 1))
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 2)))
        # A duplicated leg is caught at the second recording rather than as a
        # residual a whole step later, and a duplicate whose amount is zero
        # would otherwise pass every closure test.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; mass = mval(FT, 2)),
        )
        @test length(ledger.legs) == 1
    end

    @testset "A repeating path distinguishes its firings" begin
        schema = test_schema(; final_maps = [PB.FinalMapSpec(:constrain_state!, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 1, w = 1, e = 1))
        firing(stage; occurrence = 1) = test_leg(
            FT;
            event = :map_constrain,
            leg = :atmos,
            level = PB.FinalMap(),
            channel = :constrain_state!,
            mass = mval(FT, 1),
            stage,
            occurrence,
        )
        # `update_constrain_state_every = "stage"` fires the same correction once
        # per ARS343 stage. Without a stage index three of the four would be
        # refused as duplicates.
        for stage in 1:4
            PB.record_leg!(ledger, firing(stage))
        end
        @test length(ledger.legs) == 4
        @test_throws ErrorException PB.record_leg!(ledger, firing(2))
        PB.record_leg!(ledger, firing(2; occurrence = 2))
        @test length(ledger.legs) == 5
    end

    @testset "An event is one kind of thing" begin
        schema = test_schema(;
            channels = [PB.ChannelSpec(:explicit_main, ATMOS)],
            final_maps = [PB.FinalMapSpec(:dss!, ATMOS)],
        )
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 1, w = 1, e = 1))
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 1)))
        # The same event recorded at two levels would make both identities wrong.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; leg = :other, level = PB.FinalMap(), channel = :dss!),
        )
        # A channel applies one accepted update to one reservoir, so a second
        # envelope for it double-counts that update.
        @test_throws ErrorException PB.record_leg!(
            ledger,
            test_leg(FT; event = :ev2, leg = :again, mass = mval(FT, 1)),
        )
    end

    @testset "Tolerances must be usable numbers" begin
        function ok(;
            absolute = 1.0,
            relative = 0.1,
            scale = 2.0,
            kappa = 64.0,
        )
            return PB.BudgetTolerance(; absolute, relative, scale, kappa)
        end
        tolerance = ok()
        @test PB.tolerance_value(tolerance, 0.0, 0.0, 0.0) == 1.0 + 0.1 * 2.0

        # NaN rejects every step and Inf accepts every step, and both fail in
        # the comparison rather than at construction unless they are refused
        # here.
        for bad in (NaN, Inf, -Inf)
            @test_throws ErrorException ok(; absolute = bad)
            @test_throws ErrorException ok(; relative = bad)
            @test_throws ErrorException ok(; scale = bad)
            @test_throws ErrorException ok(; kappa = bad)
        end
        @test_throws ErrorException ok(; absolute = -1.0)
        @test_throws ErrorException ok(; relative = -1.0)
        @test_throws ErrorException ok(; kappa = -1.0)
        # The relative term is a fraction of a magnitude, and a signed or zero
        # magnitude is not one.
        @test_throws ErrorException ok(; scale = 0.0)
        @test_throws ErrorException ok(; scale = -1.0)
    end

    @testset "Claim status resolves in one order" begin
        # not applicable, then blocked, then failed, then passed.
        @test PB.claim_status(false, String[], 1e9, 1.0) === :not_applicable
        @test PB.claim_status(false, ["blocker"], 0.0, 1.0) === :not_applicable
        @test PB.claim_status(true, ["blocker"], 0.0, 1.0) === :blocked
        # A missing tolerance blocks for the same reason a missing measurement
        # does: there is no verdict to give.
        @test PB.claim_status(true, String[], 0.0, nothing) === :blocked
        @test PB.claim_status(true, String[], 2.0, 1.0) === :fail
        @test PB.claim_status(true, String[], 1.0, 1.0) === :pass
    end

    @testset "A final map is a parent term and not a channel" begin
        schema = test_schema(;
            channels = [PB.ChannelSpec(:explicit_main, ATMOS)],
            final_maps = [PB.FinalMapSpec(:dss!, ATMOS)],
        )
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        PB.record_leg!(
            ledger,
            test_leg(FT; event = :env_main, mass = mval(FT, 2)),
        )
        PB.record_leg!(
            ledger,
            test_leg(
                FT;
                event = :map_dss,
                leg = :dss,
                level = PB.FinalMap(),
                channel = :dss!,
                mass = mval(FT, 1),
            ),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 13, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        parent = parent_result(commit, :mass, :atmosphere_only)
        # The map's raw change is a term of the primary identity in its own
        # right, alongside the channel envelope and never inside it.
        @test parent.envelopes == 2
        @test parent.final_maps == 1
        @test parent.recorded == 3
        @test parent.residual == 0
        @test parent.status === :pass

        # It creates no attribution requirement: there is no envelope for a
        # final map to explain, so no attribution row names one.
        @test isempty(attribution_results(commit, :dss!))
        @test !isempty(attribution_results(commit, :explicit_main))
        @test isempty(parent.missing_expectations)
    end

    @testset "An expected channel that recorded nothing blocks" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:implicit, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        parent = parent_result(commit, :mass, :atmosphere_only)
        # The numbers close, and the claim is still blocked. A channel that
        # never reported would otherwise remove itself from its own audit.
        @test parent.residual == 0
        @test parent.status === :blocked
        @test length(parent.missing_expectations) == 1
        @test occursin("implicit", only(parent.missing_expectations))

        attribution =
            attribution_result(commit, :implicit, :mass, :atmosphere_only)
        @test attribution.status === :blocked
        @test any(b -> occursin("implicit", b), attribution.blocked_by)
    end

    @testset "An expected final map that recorded nothing blocks" begin
        schema = test_schema(; final_maps = [PB.FinalMapSpec(:lim!, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        parent = parent_result(commit, :mass, :atmosphere_only)
        @test parent.status === :blocked
        @test any(m -> occursin("lim!", m), parent.missing_expectations)
    end

    @testset "An aggregate is never summed with its decomposition" begin
        schema = test_schema(;
            channels = [
                PB.ChannelSpec(:explicit_main, ATMOS; requires_decomposition = true),
            ],
        )
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        PB.record_leg!(
            ledger,
            test_leg(FT; event = :env_main, mass = mval(FT, 4)),
        )
        for (i, amount) in enumerate((3, 1))
            PB.record_leg!(
                ledger,
                test_leg(
                    FT;
                    event = Symbol("proc_", i),
                    leg = Symbol("p", i),
                    level = PB.ProcessDecomposition(),
                    mass = mval(FT, amount),
                ),
            )
        end
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 14, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        parent = parent_result(commit, :mass, :atmosphere_only)
        # The envelope alone is the parent term. Adding the decomposition would
        # count the same update twice and the residual would be -4.
        @test parent.recorded == 4
        @test parent.residual == 0
        @test parent.status === :pass

        attribution = attribution_result(
            commit,
            :explicit_main,
            :mass,
            :atmosphere_only,
        )
        @test attribution.envelope == 4
        @test attribution.attributed == 4
        @test attribution.residual == 0
        @test attribution.status === :pass
    end

    @testset "An internal exchange cancels because its legs do" begin
        coupled = PB.TransferEventSpec(
            :xfer_surface,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface)),
        )
        schema = test_schema(;
            slab = true,
            channels = [
                PB.ChannelSpec(:implicit, (ATMOS, SLAB); requires_envelope = false),
            ],
            events = [coupled],
        )
        ledger = open_ledger(
            FT,
            schema,
            test_endpoints(FT, 0; m = 10, w = 5, e = 3, sfc_w = 1, sfc_e = 2),
        )
        transfer_leg(; kwargs...) = test_leg(
            FT;
            event = :xfer_surface,
            level = PB.ReservoirTransfer(),
            channel = :implicit,
            kwargs...,
        )
        PB.record_leg!(
            ledger,
            transfer_leg(; leg = :atmosphere, water = mval(FT, -2)),
        )
        PB.record_leg!(
            ledger,
            transfer_leg(;
                leg = :surface,
                reservoir = PB.SlabSurfaceReservoir(),
                water = mval(FT, 2),
            ),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 3, e = 3, sfc_w = 3, sfc_e = 2);
            tolerances = loose_tolerance(FT),
        )

        coupled_view =
            transfer_result(commit, :xfer_surface, :water, :atmosphere_and_surface)
        @test coupled_view.topology === :coupled
        @test coupled_view.expectation === :cancellation
        @test coupled_view.total == 0
        @test coupled_view.leg_count == 2
        @test coupled_view.status === :pass
        @test isempty(coupled_view.missing_legs)

        # The same recorded legs are a boundary crossing in the smaller view.
        # Nothing is recorded twice; the projection differs.
        atmosphere_view =
            transfer_result(commit, :xfer_surface, :water, :atmosphere_only)
        @test atmosphere_view.expectation === :boundary_crossing
        @test atmosphere_view.total == -2
        @test atmosphere_view.status === :not_applicable
        @test isnothing(atmosphere_view.tolerance)
    end

    @testset "A declared leg that was not recorded blocks the event" begin
        coupled = PB.TransferEventSpec(
            :xfer_surface,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface)),
        )
        schema = test_schema(;
            slab = true,
            channels = [
                PB.ChannelSpec(:implicit, (ATMOS, SLAB); requires_envelope = false),
            ],
            events = [coupled],
        )
        ledger = open_ledger(
            FT,
            schema,
            test_endpoints(FT, 0; m = 10, w = 5, e = 3, sfc_w = 1, sfc_e = 2),
        )
        PB.record_leg!(
            ledger,
            test_leg(
                FT;
                event = :xfer_surface,
                leg = :atmosphere,
                level = PB.ReservoirTransfer(),
                channel = :implicit,
                water = mval(FT, -2),
            ),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 3, e = 3, sfc_w = 3, sfc_e = 2);
            tolerances = loose_tolerance(FT),
        )
        result =
            transfer_result(commit, :xfer_surface, :water, :atmosphere_and_surface)
        # The surface leg was declared and never arrived. Its absence blocks the
        # event; it is never read as a zero that happens to make the sum fail.
        @test result.status === :blocked
        @test length(result.missing_legs) == 1
        @test occursin("surface", only(result.missing_legs))
        @test result.total == -2
    end

    @testset "An event that recorded nothing at all is still reported" begin
        coupled = PB.TransferEventSpec(
            :xfer_surface,
            PB.CoupledTransfer(),
            :implicit,
            ((ATMOS, :atmosphere), (SLAB, :surface)),
        )
        schema = test_schema(;
            slab = true,
            channels = [
                PB.ChannelSpec(:implicit, (ATMOS, SLAB); requires_envelope = false),
            ],
            events = [coupled],
        )
        ledger = open_ledger(
            FT,
            schema,
            test_endpoints(FT, 0; m = 10, w = 5, e = 3, sfc_w = 1, sfc_e = 2),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 5, e = 3, sfc_w = 1, sfc_e = 2);
            tolerances = loose_tolerance(FT),
        )
        result =
            transfer_result(commit, :xfer_surface, :water, :atmosphere_and_surface)
        # The row exists because the schema declares the event, not because
        # anything was recorded for it.
        @test result.leg_count == 0
        @test length(result.missing_legs) == 2
        @test result.status === :blocked
    end

    @testset "An exterior crossing is not an internal cancellation" begin
        exterior = PB.TransferEventSpec(
            :xfer_toa,
            PB.ExteriorCrossing(),
            :explicit_main,
            ((ATMOS, :atmosphere),);
            counterparty = :space,
        )
        schema = test_schema(;
            channels = [
                PB.ChannelSpec(:explicit_main, ATMOS; requires_envelope = false),
            ],
            events = [exterior],
        )
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        PB.record_leg!(
            ledger,
            test_leg(
                FT;
                event = :xfer_toa,
                leg = :atmosphere,
                level = PB.ReservoirTransfer(),
                energy = mval(FT, -7),
            ),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 5, e = -4);
            tolerances = loose_tolerance(FT),
        )
        result = transfer_result(commit, :xfer_toa, :energy, :atmosphere_only)
        @test result.topology === :exterior
        @test result.expectation === :exterior_crossing
        @test result.counterparty === :space
        # One modeled leg, and nothing fabricated on the other side. A
        # synthesized counterparty would guarantee cancellation and measure
        # nothing.
        @test result.leg_count == 1
        @test isempty(result.missing_legs)
        # The total is the signed crossing, not a residual, so it takes no
        # cancellation verdict and is judged against no tolerance.
        @test result.total == -7
        @test result.status === :not_applicable
        @test isnothing(result.tolerance)

        # There is no exterior reservoir to record a counter-leg against.
        @test_throws ErrorException PB.endpoint_reservoir(PB.EXTERIOR_LABEL)
    end

    @testset "Mass, water and energy stay independent" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        # One event measures energy, proves a mass zero, and has nothing to say
        # about water. A per-leg status would misdescribe two of the three.
        PB.record_leg!(
            ledger,
            test_leg(
                FT;
                event = :env_main,
                mass = zval(FT),
                water = unkval(FT),
                energy = mval(FT, 4),
            ),
        )
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = 5, e = 7);
            tolerances = loose_tolerance(FT),
        )
        @test parent_result(commit, :mass, :atmosphere_only).status === :pass
        @test parent_result(commit, :energy, :atmosphere_only).status === :pass
        water = parent_result(commit, :water, :atmosphere_only)
        @test water.status === :blocked
        @test !isempty(water.blocked_by)
    end

    @testset "A dry configuration's water is not a closed budget" begin
        schema = test_schema(; atmosphere_water = false)
        ledger =
            open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = nothing, e = 3))
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 10, w = nothing, e = 3);
            tolerances = loose_tolerance(FT),
        )
        water = parent_result(commit, :water, :atmosphere_only)
        # Zero endpoints and zero legs, and the claim is still not one the
        # configuration ever made.
        @test water.status === :not_applicable
        @test !water.applicable
    end

    @testset "A late failure leaves the ledger untouched" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 1)))

        # Closing endpoints that describe a different configuration from the one
        # the schema declares. The failure comes after every leg is in, which is
        # the case a non-atomic commit would half-count.
        @test_throws ErrorException PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 11, w = nothing, e = 3);
            tolerances = loose_tolerance(FT),
        )
        @test ledger.is_open
        @test ledger.committed_steps == 0
        @test length(ledger.legs) == 1
        @test isempty(ledger.cumulative_residual)
        @test isempty(ledger.cumulative_change)
        @test isnothing(ledger.last_closing)

        # The same transaction still commits once it is given endpoints that
        # match the configuration.
        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 11, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        @test commit.step == 1
        @test ledger.committed_steps == 1
        @test !ledger.is_open
    end

    @testset "Transactions are bounded and continuous" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = PB.BudgetLedger{FT}(schema)
        opening = test_endpoints(FT, 0; m = 10, w = 5, e = 3)
        PB.open_transaction!(ledger, opening)
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 1)))
        closing = test_endpoints(FT, 1; m = 11, w = 5, e = 3)
        PB.commit_transaction!(ledger, closing; tolerances = loose_tolerance(FT))

        # Per-step storage is cleared on commit, so a long run keeps the fixed
        # set of cumulative totals and nothing that grows with the step count.
        @test isempty(ledger.legs)
        @test isempty(ledger.recorded_keys)
        @test isempty(ledger.envelope_keys)

        # The next transaction has to open on the endpoint this one closed. A
        # gap between them is a change nothing accounted for.
        @test_throws ErrorException PB.open_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 12, w = 5, e = 3),
        )
        PB.open_transaction!(ledger)
        @test ledger.step == 2
        PB.abort_transaction!(ledger)
        @test !ledger.is_open
        @test ledger.committed_steps == 1
    end

    @testset "Cumulative residuals cannot cancel each other away" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = PB.BudgetLedger{FT}(schema)
        # Two steps whose residuals are +1 and -1. The signed sum is zero and
        # reports a perfectly closed run that closed on neither step, which is
        # why it is reported as drift and never passes a test on its own.
        endpoints = [
            test_endpoints(FT, i; m = 10 + i, w = 5, e = 3) for i in 0:2
        ]
        residuals = (1, -1)
        for (i, residual) in enumerate(residuals)
            PB.open_transaction!(ledger, endpoints[i])
            PB.record_leg!(
                ledger,
                test_leg(FT; step = i, mass = mval(FT, 1 - residual)),
            )
            PB.commit_transaction!(
                ledger,
                endpoints[i + 1];
                tolerances = loose_tolerance(FT),
            )
        end
        key = (:mass, :atmosphere_only)
        @test ledger.cumulative_residual[key] == 0
        @test ledger.cumulative_abs_residual[key] == 2
        @test ledger.max_abs_residual[key] == 1
        @test ledger.cumulative_change[key] == 2
        @test ledger.committed_steps == 2
    end

    @testset "A residual has no representation as a leg" begin
        # There is no constructor for one. A residual is produced by subtraction
        # at reconciliation time, so nothing can write one into the journal as a
        # balancing entry.
        @test !any(
            name -> occursin("residual", lowercase(String(name))),
            fieldnames(PB.BudgetLeg),
        )
        # A stage observation shares no supertype with a leg, so `record_leg!`
        # will not take one and no projection iterates them.
        @test !(PB.StageObservation <: PB.BudgetLeg)
        @test supertype(PB.StageObservation{FT}) === Any
        @test supertype(PB.BudgetLeg{FT}) === Any
    end

    @testset "Stage observations are evidence, never accounting" begin
        schema = test_schema(; channels = [PB.ChannelSpec(:explicit_main, ATMOS)])
        ledger = open_ledger(FT, schema, test_endpoints(FT, 0; m = 10, w = 5, e = 3))
        PB.record_leg!(ledger, test_leg(FT; mass = mval(FT, 1)))
        observation = PB.StageObservation{FT}(;
            event = :map_constrain,
            observation = :raw_stage_difference,
            reservoir = PB.AtmosphereReservoir(),
            mass = mval(FT, 99),
            water = naval(FT),
            energy = naval(FT),
            process = :test,
            step = 1,
            stage = 2,
        )
        PB.record_observation!(ledger, observation)
        # Observing the same map at the same stage twice is a reading, not a
        # double count, so observations are not deduplicated.
        PB.record_observation!(ledger, observation)
        @test length(ledger.observations) == 2

        commit = PB.commit_transaction!(
            ledger,
            test_endpoints(FT, 1; m = 11, w = 5, e = 3);
            tolerances = loose_tolerance(FT),
        )
        # A raw intermediate-stage difference is not an additive contribution to
        # the accepted endpoint, so recording one cannot move a budget.
        parent = parent_result(commit, :mass, :atmosphere_only)
        @test parent.recorded == 1
        @test parent.residual == 0
    end
end
