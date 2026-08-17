using Test
import ClimaComms
ClimaComms.@import_required_backends
import ClimaAtmos as CA

struct NoOpChemistry <: CA.AbstractChemistryModel end

@testset "Chemistry Tendencies" begin

    # ========================================================================
    # Default: no chemistry model → no-op tendency
    # ========================================================================
    @testset "Default chemistry model is nothing" begin
        model = CA.AtmosModel()
        @test isnothing(model.chemistry_model)
    end

    @testset "chemistry_tendency! with nothing is a no-op" begin
        result = CA.chemistry_tendency!(nothing, nothing, nothing, 0.0, nothing)
        @test isnothing(result)
    end

    @testset "Abstract chemistry model fallback is a no-op" begin
        @test isnothing(
            CA.chemistry_tendency!(
                nothing,
                nothing,
                nothing,
                0.0,
                NoOpChemistry(),
            ),
        )
    end

    # ========================================================================
    # With Musica loaded: GasPhaseChem prints the version string
    # ========================================================================
    @testset "GasPhaseChem prints MUSICA version" begin
        if Sys.iswindows() || isnothing(Base.find_package("Musica"))
            @test_skip false
        else
            import Musica
            extension = Base.get_extension(CA, :ClimaAtmosMusica)
            extension_method = which(
                CA.chemistry_tendency!,
                (Nothing, Nothing, Nothing, Float64, CA.GasPhaseChem),
            )
            @test extension_method.module == extension
            @test_logs (:info, r"MUSICA version: .+") CA.chemistry_tendency!(
                nothing,
                nothing,
                nothing,
                0.0,
                CA.GasPhaseChem(),
            )
        end
    end
end
