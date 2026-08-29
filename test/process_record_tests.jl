using Test
import ClimaAtmos as CA

@testset "Process records" begin
    for FT in (Float32, Float64)
        @testset "Names and cache fields ($FT)" begin
            rad = CA.RecordedProcess{:radiation}()
            sfc = CA.RecordedProcess{:surface_flux}()

            @test CA.process_name(rad) == :radiation
            @test CA.process_name(sfc) == :surface_flux

            # The cache entry is keyed `prc_<process>`, and the lookup finds it
            entry = CA.record_entry(rad, FT[1, 2, 3])
            @test keys(entry) == (:prc_radiation,)
            @test CA.record_field(entry, rad) == FT[1, 2, 3]

            fields = CA._record_fields(zeros(FT, 3), (rad, sfc))
            @test keys(fields) == (:prc_radiation, :prc_surface_flux)
            @test all(iszero, fields.prc_radiation)
            @test eltype(fields.prc_radiation) == FT

            model = CA.ProcessRecordModel((rad, sfc))
            @test CA.process_record_state_names(model) ==
                  (:prc_radiation, :prc_surface_flux)
            @test CA._records_process(model, :radiation)
            @test !CA._records_process(model, :held_suarez)
        end

        @testset "Accumulation is signed and per process ($FT)" begin
            rad = CA.RecordedProcess{:radiation}()
            sfc = CA.RecordedProcess{:surface_flux}()
            processes = (rad, sfc)

            records = (;
                prc_radiation = zeros(FT, 4),
                prc_surface_flux = zeros(FT, 4),
            )

            # A gain-and-loss increment reaches only the matching process, and
            # keeps its sign: a record is a history, not a composition
            ᶜΔ = FT[1, -2, 3, -4]
            CA._accumulate_records!(records, ᶜΔ, :radiation, processes)
            @test records.prc_radiation == ᶜΔ
            @test all(iszero, records.prc_surface_flux)

            # Accumulating the same process again adds to it
            CA._accumulate_records!(records, ᶜΔ, :radiation, processes)
            @test records.prc_radiation == 2 .* ᶜΔ
            @test all(iszero, records.prc_surface_flux)

            # A process the record does not list changes nothing
            CA._accumulate_records!(records, ᶜΔ, :held_suarez, processes)
            @test records.prc_radiation == 2 .* ᶜΔ
            @test all(iszero, records.prc_surface_flux)

            # Equal gain and loss cancel to zero, which is the correct answer
            # for a net record and the reason a record is not a source share
            CA._accumulate_records!(records, -2 .* ᶜΔ, :radiation, processes)
            @test all(iszero, records.prc_radiation)

            CA._accumulate_records!(records, ᶜΔ, :surface_flux, processes)
            @test records.prc_surface_flux == ᶜΔ
        end
    end

    @testset "Config parsing" begin
        # Absent or empty disables the record entirely
        @test isnothing(
            CA.process_record_from_config(
                nothing,
                "energy_process_record",
                CA.KNOWN_TAG_SOURCES,
                CA.TAG_SOURCE_GROUPS,
            ),
        )
        @test isnothing(
            CA.process_record_from_config(
                [],
                "energy_process_record",
                CA.KNOWN_TAG_SOURCES,
                CA.TAG_SOURCE_GROUPS,
            ),
        )

        # A single label, a list, and a group name all parse
        one = CA.process_record_from_config(
            "radiation",
            "energy_process_record",
            CA.KNOWN_TAG_SOURCES,
            CA.TAG_SOURCE_GROUPS,
        )
        @test CA.process_record_state_names(one) == (:prc_radiation,)

        listed = CA.process_record_from_config(
            ["radiation", "surface_flux"],
            "energy_process_record",
            CA.KNOWN_TAG_SOURCES,
            CA.TAG_SOURCE_GROUPS,
        )
        @test CA.process_record_state_names(listed) ==
              (:prc_radiation, :prc_surface_flux)

        grouped = CA.process_record_from_config(
            "forcing",
            "energy_process_record",
            CA.KNOWN_TAG_SOURCES,
            CA.TAG_SOURCE_GROUPS,
        )
        @test length(grouped.processes) ==
              length(CA.TAG_SOURCE_GROUPS.forcing)

        # An unknown process is refused rather than silently dropped
        @test_throws ErrorException CA.process_record_from_config(
            "not_a_process",
            "energy_process_record",
            CA.KNOWN_TAG_SOURCES,
            CA.TAG_SOURCE_GROUPS,
        )

        # The water record uses the water source table, which is smaller:
        # radiation moves no water
        @test_throws ErrorException CA.process_record_from_config(
            "radiation",
            "water_process_record",
            CA.KNOWN_WATER_TAG_SOURCES,
            CA.WATER_TAG_SOURCE_GROUPS,
        )
    end

    @testset "AtmosModel integration" begin
        # Disabled by default
        model = CA.AtmosModel()
        @test isnothing(model.energy_process_record)
        @test isnothing(model.water_process_record)
        @test isnothing(model.tagging.energy_process_record)

        # Enabled through the grouped kwarg interface, and reachable by the
        # forwarded property name
        record =
            CA.ProcessRecordModel((CA.RecordedProcess{:radiation}(),))
        model = CA.AtmosModel(; energy_process_record = record)
        @test model.energy_process_record isa CA.ProcessRecordModel
        @test CA.process_name(model.energy_process_record.processes[1]) ==
              :radiation
        @test isnothing(model.water_process_record)
    end

    @testset "Diagnostics registration" begin
        # No-op when disabled
        @test isnothing(
            CA.Diagnostics.register_process_record_diagnostics!(
                CA.AtmosModel(),
            ),
        )

        record = CA.ProcessRecordModel((
            CA.RecordedProcess{:radiation}(),
            CA.RecordedProcess{:surface_flux}(),
        ))
        CA.Diagnostics.register_process_record_diagnostics!(
            CA.AtmosModel(; energy_process_record = record),
        )
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_prc_radiation")
        @test haskey(CA.Diagnostics.ALL_DIAGNOSTICS, "e_prc_surface_flux")
    end
end
