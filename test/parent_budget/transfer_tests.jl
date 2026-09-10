using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB
import ClimaTimeSteppers as CTS

# Boundaries and reservoir transfers.
#
# Every modeled leg of every transfer event is measured on its own side. Where
# an applied-update event isolates one leg, the leg is that event's own total:
# what the atmosphere integrated of the surface flux, what either side
# integrated of precipitation. Where an event lumps several legs, radiation's
# two crossings in the atmosphere and the slab's three fluxes in the slab
# tendency, the legs come from the flux fields those tendencies read, and the
# event's own total is kept beside their sum as a check. The topology comes
# from the schema: a crossing is reported, a coupled exchange is tested for
# cancellation, and the same event is a crossing in the atmosphere-only view
# and a cancellation in the coupled one.
#
# Three configurations: a dry column with a prescribed surface, where the
# surface flux is a crossing; a dry slab column, where it is coupled; and a
# moist DYCOMS column with a slab built through the configuration path, where
# surface flux, surface radiation and zero-moment precipitation are coupled
# and the top-of-atmosphere radiation is a crossing.

const FT = Float64
const ATMOS = PB.ATMOSPHERE_ENDPOINT_GROUP
const SLAB = PB.SLAB_SURFACE_ENDPOINT_GROUP

provisional_tolerances() = Dict(
    quantity =>
        PB.BudgetTolerance(; absolute = 0.0, relative = 0.0, scale = 1.0, kappa = 64.0)
    for quantity in PB.BUDGET_QUANTITIES
)

newton() = CTS.NewtonsMethod(;
    max_iters = 1,
    update_j = CTS.UpdateEvery(CTS.NewNewtonIteration),
)

slab_surface() =
    CA.AtmosSurface(; temperature = CA.SurfaceConditions.SlabOceanTemperature{FT}())

function column_simulation(;
    parent_budget_mode = "audit",
    model = CA.AtmosModel(),
    kwargs...,
)
    return CA.AtmosSimulation{FT}(;
        model,
        grid = CA.ColumnGrid(FT; z_elem = 10),
        dt = 60,
        t_end = 600,
        job_id = "parent_budget_transfers",
        output_dir = mktempdir(),
        default_callbacks = false,
        diagnostics = CA.DiagnosticsConfig(; default = false),
        update_cache_every = "step",
        ode_config = CTS.IMEXAlgorithm(CTS.ARS343(), newton()),
        parent_budget_tolerances = provisional_tolerances(),
        parent_budget_mode,
        kwargs...,
    )
end

function moist_slab_simulation()
    config = CA.AtmosConfig(
        Dict(
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
            "output_dir" => mktempdir(),
            "parent_budget_mode" => "audit",
        );
        job_id = "parent_budget_transfers_moist_slab",
    )
    simulation = CA.get_simulation(config)
    # The configuration path takes its tolerance from the calibration table.
    # These tests judge the residuals with the provisional one instead.
    adapter_of(simulation).tolerances =
        PB.parent_budget_tolerances(provisional_tolerances())
    return simulation
end

adapter_of(simulation) = simulation.integrator.p.parent_budget
step!(simulation, n) = foreach(_ -> CTS.step!(simulation.integrator), 1:n)

rows(adapter, which, view) =
    filter(r -> r.control_volume === view, getproperty(PB.latest_commit(adapter), which))
transfer_row(adapter, event, quantity, view) = only(
    filter(
        r -> String(r.event) == event && r.quantity === quantity,
        rows(adapter, :transfer, view),
    ),
)
parent_row(adapter, quantity, view) =
    only(filter(r -> r.quantity === quantity, rows(adapter, :parent, view)))
attribution_row(adapter, channel, quantity, view) = only(
    filter(
        r -> r.channel === channel && r.quantity === quantity,
        rows(adapter, :attribution, view),
    ),
)
legs_of(adapter, event, reservoir) = filter(
    l ->
        l.level isa PB.ReservoirTransfer && String(l.event) == event &&
        PB.reservoir_name(l.reservoir) === reservoir,
    adapter.last_legs,
)
status(component) = PB.component_status(component)

@testset "Parent-budget transfers" begin
    @testset "A prescribed surface makes the surface flux a crossing" begin
        simulation = column_simulation()
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        r = transfer_row(adapter, "xfer.surface_turbulent_flux", :energy, :atmosphere_only)
        @test r.status === :reported
        @test r.expectation === :exterior_crossing
        @test r.counterparty === :unmodeled_surface_store
        @test isnothing(r.tolerance)
        @test isempty(r.missing_legs)
        @test abs(r.total) > 1e3
        # The atmosphere's leg is the bracket's own total, one per weighted
        # stage, and the mass leg of a dry surface flux is measured zero.
        legs = legs_of(adapter, "xfer.surface_turbulent_flux", ATMOS)
        @test [l.stage for l in legs] == [2, 3, 4]
        @test all(l -> l.measured_at === :bracket_total, legs)
        @test all(l -> l.channel === :explicit_main, legs)
        @test all(l -> status(l.energy) isa PB.Measured, legs)
        @test all(l -> l.mass.amount == 0, legs)
        @test all(l -> status(l.water) isa PB.NotApplicable, legs)
        @test sum(l.energy.amount for l in legs) ≈ r.total
        # With the leg recorded, the explicit channel attributes in full.
        @test attribution_row(adapter, :explicit_main, :energy, :atmosphere_only).status ===
              :pass
        @test parent_row(adapter, :energy, :atmosphere_only).status === :pass
        # An isolated leg needs no bracket check.
        @test isempty(PB.latest_transfer_checks(adapter))
    end

    @testset "A slab makes the surface flux a coupled exchange" begin
        simulation = column_simulation(; model = CA.AtmosModel(; surface = slab_surface()))
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        # Both views exist. In the atmosphere-only view the same event crosses
        # the boundary; in the coupled view its two legs cancel.
        outer =
            transfer_row(adapter, "xfer.surface_turbulent_flux", :energy, :atmosphere_only)
        @test outer.status === :reported
        @test outer.expectation === :boundary_crossing
        coupled = transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_and_surface,
        )
        @test coupled.status === :pass
        @test coupled.expectation === :cancellation
        @test coupled.topology === :coupled
        @test abs(coupled.total) <= coupled.tolerance
        @test coupled.leg_count == 6
        # The slab's leg comes from the flux field its tendency subtracts,
        # and its sum over the stages is what the slab bracket applied.
        slab_legs = legs_of(adapter, "xfer.surface_turbulent_flux", SLAB)
        @test all(l -> l.measured_at === :flux_quadrature, slab_legs)
        @test all(l -> status(l.energy) isa PB.Measured, slab_legs)
        @test all(l -> status(l.water) isa PB.NotApplicable, slab_legs)
        checks = PB.latest_transfer_checks(adapter)
        @test [(c.event, c.reservoir) for c in checks] ==
              fill((:surface_temperature, SLAB), 3)
        for check in checks
            @test check.bracket[3] ≈ check.legs[3]
        end
        # Every identity holds in both views, the slab's included.
        for view in (:atmosphere_only, :atmosphere_and_surface)
            @test parent_row(adapter, :energy, view).status === :pass
            @test parent_row(adapter, :mass, view).status === :pass
            for channel in (:explicit_main, :explicit_limited, :implicit)
                @test attribution_row(adapter, channel, :energy, view).status === :pass
            end
        end
        @test adapter.reductions == 3
    end

    @testset "A missing or a sign-reversed leg is caught where it shows" begin
        simulation = column_simulation(; model = CA.AtmosModel(; surface = slab_surface()))
        adapter = adapter_of(simulation)
        # A slab leg that was not read blocks the event, naming the leg, and
        # the atmosphere's leg is still recorded.
        PB.inject_fault!(adapter, :leg_missing, :surface_temperature)
        step!(simulation, 1)
        r = transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_and_surface,
        )
        @test r.status === :blocked
        @test length(r.blocked_by) == 3
        @test all(b -> occursin("slab_surface", b), r.blocked_by)
        @test all(
            l -> status(l.energy) isa PB.UnknownComponent,
            legs_of(adapter, "xfer.surface_turbulent_flux", SLAB),
        )
        @test all(
            l -> status(l.energy) isa PB.Measured,
            legs_of(adapter, "xfer.surface_turbulent_flux", ATMOS),
        )
        @test transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_only,
        ).status === :reported
        # A slab leg with the wrong sign fails the cancellation by twice the
        # flux, while the parent identity, which reads no leg, still passes.
        PB.inject_fault!(adapter, :leg_sign_reversed, :surface_temperature)
        step!(simulation, 1)
        r = transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_and_surface,
        )
        @test r.status === :fail
        atmosphere = sum(
            l.energy.amount for l in legs_of(adapter, "xfer.surface_turbulent_flux", ATMOS)
        )
        @test r.total ≈ 2 * atmosphere
        @test parent_row(adapter, :energy, :atmosphere_and_surface).status === :pass
        # The bracket check keeps the mismatch instead of absorbing it.
        for check in PB.latest_transfer_checks(adapter)
            @test check.bracket[3] ≈ -check.legs[3]
        end
        PB.clear_fault!(adapter)
        step!(simulation, 1)
        @test transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_and_surface,
        ).status === :pass
    end

    @testset "Summary mode records no leg and blocks every transfer by name" begin
        simulation = column_simulation(;
            parent_budget_mode = "summary",
            model = CA.AtmosModel(; surface = slab_surface()),
        )
        adapter = adapter_of(simulation)
        step!(simulation, 1)
        r = transfer_row(
            adapter,
            "xfer.surface_turbulent_flux",
            :energy,
            :atmosphere_and_surface,
        )
        @test r.status === :blocked
        @test length(r.missing_legs) == 2
        @test isempty(legs_of(adapter, "xfer.surface_turbulent_flux", ATMOS))
        @test parent_row(adapter, :energy, :atmosphere_and_surface).status === :pass
    end

    @testset "A moist slab column closes every transfer it declares" begin
        simulation = moist_slab_simulation()
        adapter = adapter_of(simulation)
        step!(simulation, 2)
        coupled = :atmosphere_and_surface
        for event in (
            "xfer.surface_turbulent_flux",
            "xfer.radiation_surface",
            "xfer.precipitation_0m",
        )
            for quantity in (:mass, :water, :energy)
                r = transfer_row(adapter, event, quantity, coupled)
                if event == "xfer.radiation_surface" && quantity !== :energy
                    # Radiation moves no air, and the registry proves it.
                    @test r.status === :pass
                    @test r.total == 0
                    @test r.status_counts[:invariant_zero] == 6
                else
                    @test r.status === :pass
                    @test r.expectation === :cancellation
                    @test abs(r.total) <= r.tolerance
                    @test r.status_counts[:measured] == 6
                end
            end
        end
        toa = transfer_row(adapter, "xfer.radiation_toa", :energy, coupled)
        @test toa.status === :reported
        @test toa.counterparty === :space
        @test toa.total < 0
        # The atmosphere loses more through the top than it gains at the
        # surface from radiation, and the two legs sum to the radiation
        # bracket's own total at every stage.
        for check in filter(c -> c.event === :radiation, PB.latest_transfer_checks(adapter))
            @test check.reservoir === ATMOS
            @test check.bracket[3] ≈ check.legs[3] rtol = 1e-9
        end
        # The slab bracket sums its turbulent and radiative legs.
        for check in filter(
            c -> c.event === :surface_temperature,
            PB.latest_transfer_checks(adapter),
        )
            @test check.reservoir === SLAB
            @test check.bracket[3] ≈ check.legs[3] rtol = 1e-9
            @test check.bracket[2] ≈ check.legs[2] rtol = 1e-9
        end
        # Precipitation is applied implicitly on both sides, and both legs are
        # bracket totals measured at the solved stage.
        for reservoir in (ATMOS, SLAB)
            legs = legs_of(adapter, "xfer.precipitation_0m", reservoir)
            @test [l.stage for l in legs] == [2, 3, 4]
            @test all(l -> l.channel === :implicit, legs)
            @test all(l -> l.measured_at === :bracket_total, legs)
        end
        @test sum(
            l.water.amount for l in legs_of(adapter, "xfer.precipitation_0m", ATMOS)
        ) < 0
        # Every identity holds in both views: the slab's solve defect is booked
        # beside the atmosphere's, so the implicit channel attributes in the
        # coupled view too.
        for view in (:atmosphere_only, coupled)
            for quantity in PB.BUDGET_QUANTITIES
                @test parent_row(adapter, quantity, view).status === :pass
                for channel in (:explicit_main, :explicit_limited, :implicit)
                    @test attribution_row(adapter, channel, quantity, view).status === :pass
                end
            end
        end
        slab_defects = filter(
            l -> l.process === :solve_defect && PB.reservoir_name(l.reservoir) === SLAB,
            adapter.last_legs,
        )
        @test [l.stage for l in slab_defects] == [2, 3, 4]
        @test all(l -> l.leg === :slab_surface, slab_defects)
    end
end
