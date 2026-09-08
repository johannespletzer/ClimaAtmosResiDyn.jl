using Test
import ClimaAtmos as CA
import ClimaAtmos.Internals.ParentBudget as PB

# The coverage registry and the schema it builds.
#
# Two things are pinned here. The page `docs/src/parent_budget/coverage.md`
# and `COVERAGE_ROWS` describe the same rows, cell for cell, so neither can
# drift from the other without this file noticing. And the schema a
# configuration selects from those rows is the fail-closed core at work: built
# before anything is recorded, it names every envelope, roster row, final map
# and transfer leg a run owes, and a ledger holding it blocks every claim until
# the run supplies them.

const PAGE = joinpath(pkgdir(CA), "docs", "src", "parent_budget", "coverage.md")

const TABLE_HEADINGS = (
    "## Channel envelopes" => :envelopes,
    "## Explicit limited channel decomposition" => :limited,
    "## Explicit main channel decomposition" => :explicit,
    "## Implicit channel decomposition" => :implicit,
    "## Final accepted-state maps" => :final_maps,
    "## Transfer events" => :transfers,
    "## Non-authoritative paths" => :non_authoritative,
)

# The cells of the one table under `heading`, trimmed. The formatter pads every
# cell to the widest in its column, so padding is not content.
function page_table_cells(lines, heading)
    start = findfirst(==(heading), lines)
    isnothing(start) && error("coverage.md has no section $heading")
    rows = Vector{Vector{String}}()
    for line in lines[(start + 1):end]
        startswith(line, "## ") && break
        startswith(line, "|") || continue
        startswith(line, "|:") && continue
        cells = [String(strip(c)) for c in split(strip(strip(line), '|'), '|')]
        cells[1] == "Event id" && continue
        push!(rows, cells)
    end
    return rows
end

# The first cell that differs, named, so a failure says where to look.
function first_difference(page, registry)
    for (i, (p, r)) in enumerate(zip(page, registry))
        p == r && continue
        length(p) == length(r) ||
            return "row $i: the page has $(length(p)) cells, the registry $(length(r))"
        for (j, (a, b)) in enumerate(zip(p, r))
            a == b || return "row $i, column $j: page \"$a\", registry \"$b\""
        end
    end
    length(page) == length(registry) ||
        return "the page has $(length(page)) rows, the registry $(length(registry))"
    return nothing
end

slab(FT) = CA.AtmosSurface(; temperature = CA.SurfaceConditions.SlabOceanTemperature{FT}())

dry_model() = CA.AtmosModel()
dry_slab_model() = CA.AtmosModel(; surface = slab(Float64))
moist_model() = CA.AtmosModel(;
    microphysics_model = CA.EquilibriumMicrophysics0M(),
    microphysics_tendency_timestepping = CA.Implicit(),
)
moist_slab_model() = CA.AtmosModel(;
    microphysics_model = CA.EquilibriumMicrophysics0M(),
    microphysics_tendency_timestepping = CA.Implicit(),
    surface = slab(Float64),
)
one_moment_slab_model() = CA.AtmosModel(;
    microphysics_model = CA.NonEquilibriumMicrophysics1M(),
    microphysics_tendency_timestepping = CA.Implicit(),
    surface = slab(Float64),
)

schema_for(model; dss = false, implicit_solve = true) =
    PB.budget_schema(model; dss, implicit_solve)

channel(schema, name) = PB.channel_spec(schema, name)
final_map(schema, name) = PB.final_map_spec(schema, name)
event(schema, name) = PB.transfer_event_spec(schema, Symbol(name))
has_event(schema, name) = PB.has_transfer_event(schema, Symbol(name))
processes(schema, name) = Tuple(row.process for row in channel(schema, name).processes)

# Endpoints that agree with the schema about applicability, so a ledger can
# open and commit with nothing recorded in between.
function synthetic_endpoints(schema, step)
    FT = PB.BUDGET_ACCOUNTING_TYPE
    reservoirs = PB.ReservoirEndpoint{FT}[]
    for spec in schema.reservoirs
        name = PB.reservoir_name(spec.reservoir)
        component(quantity) =
            PB.quantity_applicable(schema, name, quantity) ?
            PB.measured(FT(1); method = :synthetic, source = :test) :
            PB.not_applicable(FT)
        push!(
            reservoirs,
            PB.ReservoirEndpoint{FT}(;
                reservoir = spec.reservoir,
                mass = component(:mass),
                water = component(:water),
                energy = component(:energy),
            ),
        )
    end
    return PB.BudgetEndpoints{FT}(reservoirs, step)
end

@testset "Parent-budget registry" begin
    @testset "The page and the registry agree cell by cell" begin
        lines = readlines(PAGE)
        for (heading, table) in TABLE_HEADINGS
            difference = first_difference(
                page_table_cells(lines, heading),
                PB.registry_table_cells(table),
            )
            isnothing(difference) || @info "$heading: $difference"
            @test isnothing(difference)
        end
    end

    @testset "Rows have unique identities and resolvable cells" begin
        ids = [row.id for row in PB.COVERAGE_ROWS]
        @test allunique(ids)
        @test length(PB.COVERAGE_ROWS) == sum(
            length(PB.registry_rows(table)) for table in PB.REGISTRY_TABLES
        )
        with_slab = PB.RegistryContext(dry_slab_model(); dss = true, implicit_solve = true)
        without = PB.RegistryContext(dry_model(); dss = false, implicit_solve = false)
        for row in PB.COVERAGE_ROWS
            # Every reservoir cell resolves in both configurations, and a
            # channel cell names a label the schema knows.
            @test PB.row_reservoirs(row, with_slab) isa Tuple
            @test PB.row_reservoirs(row, without) isa Tuple
            if row.table === :transfers
                @test PB.transfer_topology(row, with_slab) isa PB.TransferTopology
                @test PB.transfer_counterparty(row) isa Symbol
            else
                @test PB.channel_name(row) in (PB.BUDGET_CHANNEL_LABELS..., :initialization)
            end
        end
    end

    @testset "Unsupported configurations are refused at setup" begin
        @test PB.is_supported(dry_model())
        @test_throws ErrorException PB.budget_schema(
            CA.AtmosModel(; turbconv_model = CA.EDOnlyEDMFX());
            dss = false, implicit_solve = true,
        )
        @test_throws ErrorException PB.budget_schema(
            CA.AtmosModel(; prescribed_flow = CA.ShipwayHill2012VelocityProfile{Float64}());
            dss = false, implicit_solve = true,
        )
        @test_throws ErrorException PB.budget_schema(
            CA.AtmosModel(; chemistry_model = CA.GasPhaseChem());
            dss = false, implicit_solve = true,
        )
        @test_throws ErrorException PB.budget_schema(
            CA.AtmosModel(; microphysics_model = CA.NonEquilibriumMicrophysics2M());
            dss = false, implicit_solve = true,
        )
    end

    @testset "A dry column declares three channels and no water" begin
        schema = schema_for(dry_model())
        @test [c.name for c in schema.channels] ==
              [:explicit_main, :explicit_limited, :implicit]
        @test [m.name for m in schema.final_maps] == [:lim!, :dss!, :constrain_state!]
        @test [cv.name for cv in schema.control_volumes] == [:atmosphere_only]
        for spec in schema.channels
            @test spec.requires_envelope
            @test spec.reservoirs == (PB.ATMOSPHERE_ENDPOINT_GROUP,)
            @test PB.expected_disposition(spec, :water) === :not_applicable
            @test PB.expected_disposition(spec, :mass) === :measured
        end
        # The rosters come from the decomposition rows the configuration
        # selects, and only from those.
        @test :horizontal_dynamics in processes(schema, :explicit_main)
        @test :explicit_vertical_advection in processes(schema, :explicit_main)
        @test :hyperdiffusion in processes(schema, :explicit_main)
        @test !(:viscous_sponge in processes(schema, :explicit_main))
        @test !(:held_suarez_heating in processes(schema, :explicit_main))
        @test :vertical_advection in processes(schema, :implicit)
        @test :solve_defect in processes(schema, :implicit)
        @test :post_implicit_correction in processes(schema, :implicit)
        @test !(:water_fallout in processes(schema, :implicit))
        @test processes(schema, :explicit_limited) == (:tracer_hyperdiffusion,)
        # Nothing configured runs in `lim!` or `constrain_state!`, and a column
        # has no DSS, so all three hooks are provably zero for mass and energy.
        for hook in (:lim!, :dss!, :constrain_state!)
            @test final_map(schema, hook).reservoirs == (PB.ATMOSPHERE_ENDPOINT_GROUP,)
            @test final_map(schema, hook).dispositions ==
                  (:invariant_zero, :not_applicable, :invariant_zero)
        end
        # The surface flux is a crossing into a store the model does not carry.
        flux = event(schema, "xfer.surface_turbulent_flux")
        @test flux.topology isa PB.ExteriorCrossing
        @test flux.counterparty === :unmodeled_surface_store
        @test flux.modeled_legs == ((PB.ATMOSPHERE_ENDPOINT_GROUP, :flux),)
        @test flux.channel === :explicit_main
        @test !has_event(schema, "xfer.radiation_toa")
        @test !has_event(schema, "xfer.precipitation_0m")
        @test !has_event(schema, "xfer.slab_qflux")
    end

    @testset "An explicit algorithm has no solve defect" begin
        schema = schema_for(dry_model(); implicit_solve = false)
        @test !(:solve_defect in processes(schema, :implicit))
        @test !(:post_implicit_correction in processes(schema, :implicit))
    end

    @testset "DSS on the accepted state is a measured final map" begin
        dry = schema_for(dry_model(); dss = true)
        @test final_map(dry, :dss!).dispositions ==
              (:measured, :not_applicable, :measured)
        moist = schema_for(moist_model(); dss = true)
        @test final_map(moist, :dss!).dispositions == (:measured, :measured, :measured)
    end

    @testset "A slab adds a reservoir, a control volume, and the coupled legs" begin
        schema = schema_for(moist_slab_model())
        @test [cv.name for cv in schema.control_volumes] ==
              [:atmosphere_only, :atmosphere_and_surface]
        @test PB.quantity_applicable(schema, PB.SLAB_SURFACE_ENDPOINT_GROUP, :water)
        for name in (:explicit_main, :explicit_limited, :implicit)
            @test channel(schema, name).reservoirs ==
                  (PB.ATMOSPHERE_ENDPOINT_GROUP, PB.SLAB_SURFACE_ENDPOINT_GROUP)
            @test PB.expected_disposition(channel(schema, name), :water) === :measured
        end
        flux = event(schema, "xfer.surface_turbulent_flux")
        @test flux.topology isa PB.CoupledTransfer
        @test isnothing(flux.counterparty)
        @test flux.modeled_legs == (
            (PB.ATMOSPHERE_ENDPOINT_GROUP, :flux),
            (PB.SLAB_SURFACE_ENDPOINT_GROUP, :flux),
        )
        # Zero-moment removal has no receiving reservoir even with a slab, and
        # it is applied through the implicit channel by default.
        removal = event(schema, "xfer.precipitation_0m")
        @test removal.topology isa PB.ExteriorCrossing
        @test removal.channel === :implicit
        @test removal.modeled_legs == ((PB.ATMOSPHERE_ENDPOINT_GROUP, :flux),)
        @test !has_event(schema, "xfer.precipitation_1m")
        @test !has_event(schema, "xfer.slab_qflux")
    end

    @testset "A dry slab owns energy only" begin
        schema = schema_for(dry_slab_model())
        @test !PB.quantity_applicable(schema, PB.SLAB_SURFACE_ENDPOINT_GROUP, :water)
        @test !PB.quantity_applicable(schema, PB.SLAB_SURFACE_ENDPOINT_GROUP, :mass)
        @test PB.quantity_applicable(schema, PB.SLAB_SURFACE_ENDPOINT_GROUP, :energy)
    end

    @testset "One-moment fallout is a coupled transfer on the implicit channel" begin
        schema = schema_for(one_moment_slab_model())
        fallout = event(schema, "xfer.precipitation_1m")
        @test fallout.topology isa PB.CoupledTransfer
        @test fallout.channel === :implicit
        @test length(fallout.modeled_legs) == 2
        @test !has_event(schema, "xfer.precipitation_0m")
        @test :microphysics_formation in processes(schema, :implicit)
        # Fallout is a transfer leg, never a roster row: it explains the
        # envelope through the transfer identity instead.
        @test !(:water_fallout in processes(schema, :implicit))
        # The grid-mean constraints clamp condensate only, so the constraint
        # hook stays provably zero for every parent quantity.
        @test final_map(schema, :constrain_state!).dispositions ==
              (:invariant_zero, :invariant_zero, :invariant_zero)
    end

    @testset "Every measured row names the event that brackets it" begin
        for row in PB.COVERAGE_ROWS
            isnothing(row.event) || @test row.event in PB.REGISTRY_EVENTS
            row.table in PB.ROSTER_TABLES && row.level === :decomposition || continue
            # A hook-metered row of the implicit channel names no event; every
            # other row with a measured quantity does, and a row with nothing
            # to measure is booked from the registry and needs none.
            String(row.id) in ("impl.solve_defect", "impl.post_implicit_correction",
                "impl.folded_dss", "impl.folded_constraint") && continue
            if :measured in row.dispositions
                @test !isnothing(row.event)
            end
        end
        @test :subsidence in PB.REGISTRY_EVENTS
        @test !(:horizontal_dynamics in PB.REGISTRY_EVENTS)
        # The schema carries the event onto the roster row.
        schema = schema_for(CA.AtmosModel(;
            subsidence = CA.LargeScaleSubsidence(z -> -0.001),
        ))
        row = PB.process_row(
            channel(schema, :explicit_main),
            :subsidence,
            PB.ATMOSPHERE_ENDPOINT_GROUP,
        )
        @test row.event === :subsidence
        @test isnothing(
            PB.process_row(
                channel(schema, :explicit_main),
                :horizontal_dynamics,
                PB.ATMOSPHERE_ENDPOINT_GROUP,
            ).event,
        )
        @test PB.ProcessRowSpec(:p, PB.ATMOSPHERE_ENDPOINT_GROUP).event === nothing
    end

    @testset "Idealized radiation is declared by its form" begin
        dycoms = schema_for(
            CA.AtmosModel(;
                microphysics_model = CA.EquilibriumMicrophysics0M(),
                radiation_mode = CA.RadiationDYCOMS{Float64}(),
            ),
        )
        @test has_event(dycoms, "xfer.radiation_toa")
        @test has_event(dycoms, "xfer.radiation_surface")
        @test !(:prescribed_radiative_heating in processes(dycoms, :explicit_main))
        trmm = schema_for(
            CA.AtmosModel(;
                microphysics_model = CA.EquilibriumMicrophysics0M(),
                radiation_mode = CA.RadiationTRMM_LBA(Float64),
            ),
        )
        @test !has_event(trmm, "xfer.radiation_toa")
        @test :prescribed_radiative_heating in processes(trmm, :explicit_main)
        @test PB.process_row(
            channel(trmm, :explicit_main),
            :prescribed_radiative_heating,
            PB.ATMOSPHERE_ENDPOINT_GROUP,
        ).event === :radiation
    end

    @testset "A ledger built from the schema blocks until the run supplies every term" begin
        for model in (dry_model(), moist_slab_model())
            schema = schema_for(model)
            FT = PB.BUDGET_ACCOUNTING_TYPE
            ledger = PB.BudgetLedger{FT}(schema)
            PB.open_transaction!(ledger, synthetic_endpoints(schema, 0))
            commit = PB.commit_transaction!(ledger, synthetic_endpoints(schema, 1))
            for r in commit.parent
                if r.applicable
                    @test r.status === :blocked
                    @test any(
                        contains("expected envelope for channel implicit"),
                        r.missing_expectations,
                    )
                    @test any(contains("expected final map lim!"), r.missing_expectations)
                else
                    @test r.status === :not_applicable
                end
            end
            for r in commit.attribution
                @test r.status in (:blocked, :not_applicable)
            end
            for r in commit.transfer
                @test r.status in (:blocked, :not_applicable)
                r.applicable && @test !isempty(r.missing_legs)
            end
        end
    end
end
