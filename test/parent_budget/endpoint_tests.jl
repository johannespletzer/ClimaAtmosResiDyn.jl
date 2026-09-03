using Test
using ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

include("../test_helpers.jl")

# Endpoint integrals against real ClimaCore state.
#
# `journal_tests.jl` exercises the ledger's rules on synthetic scalars. Nothing
# there ever builds a state, which is how a dry slab came to report a measured
# water budget: `Y.sfc.water` exists in a dry run, holding a permanent zero, and
# a presence check cannot tell that apart from a real measurement. These tests
# call the integrals on a state that exists.
#
# The spaces are small and built directly, with no simulation and no config, so
# these stay unit tests.

# Uniform fields, so each integral can be checked against another integral of
# the same state rather than against a hard-coded number that only restates the
# quadrature.
const ρ_VAL, Q_VAL, E_VAL = 1.2, 0.01, 2.5e5
const Q_LCL, Q_RAI = 0.002, 0.003
const SFC_T, SFC_WATER = 290.0, 3.0

# Field constructors. Written as plain functions broadcast over the local
# geometry, which is how the model itself builds prognostic state. Types are
# scalars under broadcasting, so `FT` rides along as an argument.
dry_center(_, FT) = (; ρ = FT(ρ_VAL), ρe_tot = FT(E_VAL))

moist_center(_, FT) = (; ρ = FT(ρ_VAL), ρq_tot = FT(Q_VAL), ρe_tot = FT(E_VAL))

function one_moment_center(_, FT)
    return (;
        ρ = FT(ρ_VAL),
        ρq_tot = FT(Q_VAL),
        ρq_lcl = FT(Q_LCL),
        ρq_icl = zero(FT),
        ρq_rai = FT(Q_RAI),
        ρq_sno = zero(FT),
        ρe_tot = FT(E_VAL),
    )
end

slab_variables(_, FT) = (; T = FT(SFC_T), water = FT(SFC_WATER))

function center_field(space, FT, moist, categories)
    lg = Fields.local_geometry_field(space)
    moist || return dry_center.(lg, FT)
    categories && return one_moment_center.(lg, FT)
    return moist_center.(lg, FT)
end

function test_state(spaces, FT; moist, categories = false, slab)
    c = center_field(spaces.cent_space, FT, moist, categories)
    slab || return Fields.FieldVector(; c)
    surface_space = Fields.level(spaces.face_space, Fields.half)
    sfc = slab_variables.(Fields.local_geometry_field(surface_space), FT)
    return Fields.FieldVector(; c, sfc)
end

slab_surface(FT) = CA.SurfaceConditions.SlabOceanTemperature{FT}()
prescribed_surface() = CA.SurfaceConditions.ExternalTemperature()

@testset "Parent-budget endpoints on real state" begin
    for FT in (Float32, Float64)
        # One set of spaces per float type; building them is the expensive part.
        spaces = get_spherical_extruded_spaces(; FT)
        tol = 10 * sqrt(eps(FT))

        @testset "Atmospheric integrals ($FT)" begin
            Y = test_state(spaces, FT; moist = true, slab = false)
            m = CA.atmosphere_mass(Y)
            w = CA.atmosphere_water(Y)
            e = CA.atmosphere_energy(Y)

            @test m > 0
            # The fields are uniform, so every integral is its value times the
            # same volume. Comparing ratios checks the integrals against each
            # other without restating the quadrature.
            @test w ≈ m * FT(Q_VAL / ρ_VAL) rtol = tol
            @test e ≈ m * FT(E_VAL / ρ_VAL) rtol = tol

            # ∫(ρ - ρq_tot) is written as one integral so the cancellation is
            # pointwise. It still has to agree with the difference of the two.
            @test CA.atmosphere_dry_mass(Y) ≈ m - w rtol = tol
        end

        @testset "Categories partition ρq_tot and are never added ($FT)" begin
            plain = test_state(spaces, FT; moist = true, slab = false)
            with_cat = test_state(
                spaces,
                FT;
                moist = true,
                categories = true,
                slab = false,
            )

            # Same ρq_tot, but one state also carries cloud and rain. Total
            # water is ∫ρq_tot alone, so the two must agree exactly. Adding a
            # category would invent water every time condensate became rain.
            @test CA.atmosphere_water(with_cat) == CA.atmosphere_water(plain)
            @test CA.atmosphere_mass(with_cat) == CA.atmosphere_mass(plain)
            @test CA.atmosphere_dry_mass(with_cat) ==
                  CA.atmosphere_dry_mass(plain)
        end

        @testset "A dry atmosphere owns no water ($FT)" begin
            Y = test_state(spaces, FT; moist = false, slab = false)
            @test CA.atmosphere_dry_mass(Y) == CA.atmosphere_mass(Y)

            endpoints =
                CA.budget_endpoints(Y, prescribed_surface(), CA.DryModel(), 0)
            atmos = only(endpoints.reservoirs)
            @test atmos.reservoir === CA.AtmosphereReservoir()
            @test atmos.water.status isa CA.NotApplicable
            @test atmos.mass.status isa CA.Measured
        end

        @testset "A prescribed surface is not a reservoir ($FT)" begin
            Y = test_state(spaces, FT; moist = true, slab = false)
            surface = prescribed_surface()
            model = CA.EquilibriumMicrophysics0M()
            @test isnothing(CA.surface_energy(Y, surface))
            @test isnothing(CA.surface_water(Y, surface, model))
            @test isnothing(CA.surface_mass(Y, surface, model))

            endpoints = CA.budget_endpoints(Y, surface, model, 0)
            @test length(endpoints.reservoirs) == 1
            # With no slab the coupled view names a reservoir that is not there.
            # It must be refused rather than quietly returning atmosphere-only
            # numbers under the coupled name.
            @test !CA.control_volume_available(
                endpoints,
                CA.ATMOSPHERE_AND_SURFACE,
            )
            @test CA.control_volume_available(endpoints, CA.ATMOSPHERE_ONLY)
        end

        @testset "A dry slab owns no water, and no mass either ($FT)" begin
            # The bug this file exists for. `Y.sfc.water` is built as `FT(0)`
            # whatever the moisture model is, so a presence check reported a
            # measured zero where the contract says the quantity does not apply.
            Y = test_state(spaces, FT; moist = false, slab = true)
            slab = slab_surface(FT)
            @test !isnothing(CA.surface_energy(Y, slab))
            @test isnothing(CA.surface_water(Y, slab, CA.DryModel()))
            @test isnothing(CA.surface_mass(Y, slab, CA.DryModel()))

            endpoints = CA.budget_endpoints(Y, slab, CA.DryModel(), 0)
            surface = endpoints.reservoirs[2]
            @test surface.reservoir === CA.SlabSurfaceReservoir()
            @test surface.water.status isa CA.NotApplicable
            @test surface.mass.status isa CA.NotApplicable
            @test surface.energy.status isa CA.Measured

            # And the coupled water view is inapplicable rather than closed.
            water =
                CA.endpoint_total(endpoints, :water, CA.ATMOSPHERE_AND_SURFACE)
            @test !water.applicable
            @test water.total == 0
        end

        @testset "A moist slab owns water and the mass with it ($FT)" begin
            Y = test_state(spaces, FT; moist = true, slab = true)
            slab = slab_surface(FT)
            models = (
                CA.EquilibriumMicrophysics0M(),
                CA.NonEquilibriumMicrophysics1M(),
            )
            for model in models
                w = CA.surface_water(Y, slab, model)
                m = CA.surface_mass(Y, slab, model)
                @test !isnothing(w)
                @test w > 0
                # Two projections of one endpoint, so they are equal by
                # construction. This pins that, rather than pretending it is an
                # independent measurement.
                @test m == w

                endpoints = CA.budget_endpoints(Y, slab, model, 0)
                surface = endpoints.reservoirs[2]
                @test surface.water.status isa CA.Measured
                @test surface.mass.status isa CA.Measured
                @test surface.mass.amount == surface.water.amount
                @test CA.control_volume_available(
                    endpoints,
                    CA.ATMOSPHERE_AND_SURFACE,
                )
            end
        end

        @testset "Endpoints are Float64 whatever the state is ($FT)" begin
            # The residual is what survives subtracting two large global totals.
            # Carrying it in the state's type would destroy it for a Float32
            # run, so the ledger's own arithmetic is always Float64.
            Y = test_state(spaces, FT; moist = true, slab = true)
            endpoints = CA.budget_endpoints(
                Y,
                slab_surface(FT),
                CA.EquilibriumMicrophysics0M(),
                0,
            )
            @test endpoints isa CA.BudgetEndpoints{Float64}
            for reservoir in endpoints.reservoirs
                for quantity in CA.BUDGET_QUANTITIES
                    @test CA.budget_component(reservoir, quantity).amount isa
                          Float64
                end
            end
        end
    end
end
