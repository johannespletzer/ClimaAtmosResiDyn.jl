using Test
import ClimaAtmos as CA
import ClimaCore.Geometry as Geometry
import Dates

# `SeasonalOceanTemperature` is the `f` of an `AnalyticTemperature`, so it is
# called as `f(coordinates, surface_temp_params, t)` with `t` in seconds since
# the simulation's `start_date`.
@testset "seasonal zonally symmetric SST" begin
    FT = Float64
    day = FT(86400)
    year = FT(365.25) * day

    # Guard the coordinate constructor's argument order, so that a mistake
    # there fails here rather than as a confusing temperature mismatch below.
    probe = Geometry.LatLongZPoint(FT(45), FT(10), FT(100))
    @test probe.lat == FT(45)
    @test probe.z == FT(100)

    # Phased to 1 January, so `t` and the day of year agree.
    temperature = CA.Setups.SeasonalOceanTemperature{FT}(;
        amplitude = 4,
        peak_day = 210,
        start_day = 1,
    )
    at(lat, t) =
        temperature(Geometry.LatLongZPoint(FT(lat), FT(0), FT(0)), nothing, FT(t))

    steady(lat) = CA.Setups.zonally_symmetric_temperature(
        Geometry.LatLongZPoint(FT(lat), FT(0), FT(0)),
        nothing,
        FT(0),
    )

    peak = (temperature.peak_day - temperature.start_day) * day
    trough = peak + year / 2

    # The seasonal anomaly vanishes at the equator and at the poles, so there
    # the profile is the steady one at every time of year.
    for t in (FT(0), peak, trough)
        @test at(0, t) ≈ steady(0)
        @test at(90, t) ≈ steady(90)
        @test at(-90, t) ≈ steady(-90)
    end

    # It peaks at 45 degrees, where it reaches the full amplitude.
    @test at(45, peak) - steady(45) ≈ temperature.amplitude
    @test at(45, trough) - steady(45) ≈ -temperature.amplitude

    # Antisymmetric between the hemispheres: when the north is warm the south
    # is cold by the same amount.
    @test at(45, peak) - steady(45) ≈ -(at(-45, peak) - steady(-45))

    # A full year later is the same point in the cycle.
    @test at(45, peak) ≈ at(45, peak + year)

    # The amplitude is largest in midlatitudes and smaller in the tropics,
    # which is the shape an ocean surface has.
    @test abs(at(45, peak) - steady(45)) > abs(at(10, peak) - steady(10))
    @test abs(at(45, peak) - steady(45)) > abs(at(80, peak) - steady(80))

    # `start_day` phases the cycle to the calendar rather than to the start of
    # the run: a run beginning on the peak day is at its warmest at t = 0.
    shifted = CA.Setups.SeasonalOceanTemperature{FT}(;
        amplitude = 4,
        peak_day = 210,
        start_day = 210,
    )
    @test shifted(
        Geometry.LatLongZPoint(FT(45), FT(0), FT(0)),
        nothing,
        FT(0),
    ) ≈ at(45, peak)

    # The lapse-rate correction over elevated surfaces is kept.
    elevated =
        temperature(Geometry.LatLongZPoint(FT(45), FT(0), FT(1000)), nothing, peak)
    @test elevated ≈ at(45, peak) - FT(6.5)
end

@testset "SeasonalSST is selectable from the configuration" begin
    FT = Float32
    config = CA.AtmosConfig(
        Dict(
            "prognostic_surface" => "SeasonalSST",
            "start_date" => "19790401",
            "surface_setup" => "DefaultMoninObukhov",
        );
        job_id = "seasonal_sst_config",
    )
    surface = CA.AtmosSurface(config, CA.ClimaAtmosParameters(config), FT)
    @test surface.temperature isa CA.SurfaceConditions.AnalyticTemperature
    @test surface.temperature.f isa CA.Setups.SeasonalOceanTemperature
    # `start_day` comes from `start_date`, so the cycle is calendar-phased.
    @test surface.temperature.f.start_day ==
          FT(Dates.dayofyear(Dates.Date(1979, 4, 1)))
end
