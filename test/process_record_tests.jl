using Test
import ClimaAtmos as CA

@testset "Process records" begin
    for FT in (Float32, Float64)
        @testset "Names and state fields ($FT)" begin
            rad = CA.RecordedProcess{:radiation}()
            sfc = CA.RecordedProcess{:surface_flux}()

            @test CA.process_name(rad) == :radiation
            @test CA.process_name(sfc) == :surface_flux

            # State entries are keyed `prc_e_<process>` / `prc_q_<process>`,
            # and the compile-time lookup finds them
            entry = CA.energy_record_entry(rad, FT[1, 2, 3])
            @test keys(entry) == (:prc_e_radiation,)
            @test CA.energy_record_field(entry, rad) == FT[1, 2, 3]

            wentry = CA.water_record_entry(sfc, FT[4, 5, 6])
            @test keys(wentry) == (:prc_q_surface_flux,)
            @test CA.water_record_field(wentry, sfc) == FT[4, 5, 6]

            # Records start at zero: a history, not a share of anything present
            fields = CA._energy_record_variables(zero(FT), (rad, sfc))
            @test keys(fields) == (:prc_e_radiation, :prc_e_surface_flux)
            @test iszero(fields.prc_e_radiation)
            @test fields.prc_e_radiation isa FT

            model = CA.ProcessRecordModel((rad, sfc))
            @test CA.energy_process_record_state_names(model) ==
                  (:prc_e_radiation, :prc_e_surface_flux)
            @test CA.water_process_record_state_names(model) ==
                  (:prc_q_radiation, :prc_q_surface_flux)
            @test CA._records_process(model, :radiation)
            @test !CA._records_process(model, :held_suarez)

            # A record is prognostic but must never be transported.
            # `gs_tracer_names` picks up any top-level `Y.c` field whose name
            # starts with `ρ`, and that alone opts a field into advection,
            # diffusion, hyperdiffusion and the sponges. The missing `ρ` is the
            # only thing keeping records out, so guard it here: a well-meaning
            # rename to `ρprc_e_radiation` would silently start transporting a
            # quantity whose whole purpose is to be separate from transport.
            for name in (
                CA.energy_process_record_state_names(model)...,
                CA.water_process_record_state_names(model)...,
            )
                @test !startswith(String(name), "ρ")
            end
        end

        @testset "Accumulation is signed and per process ($FT)" begin
            rad = CA.RecordedProcess{:radiation}()
            sfc = CA.RecordedProcess{:surface_flux}()
            processes = (rad, sfc)

            ᶜYₜ = (;
                prc_e_radiation = zeros(FT, 4),
                prc_e_surface_flux = zeros(FT, 4),
            )
            acc! =
                (Δ, src) -> CA._accumulate_records!(
                    CA.energy_record_field,
                    ᶜYₜ,
                    Δ,
                    src,
                    processes,
                )

            # A gain-and-loss increment reaches only the matching process, and
            # keeps its sign: a record is a history, not a composition
            ᶜΔ = FT[1, -2, 3, -4]
            acc!(ᶜΔ, :radiation)
            @test ᶜYₜ.prc_e_radiation == ᶜΔ
            @test all(iszero, ᶜYₜ.prc_e_surface_flux)

            # Accumulating the same process again adds to it
            acc!(ᶜΔ, :radiation)
            @test ᶜYₜ.prc_e_radiation == 2 .* ᶜΔ
            @test all(iszero, ᶜYₜ.prc_e_surface_flux)

            # A process the record does not list changes nothing
            acc!(ᶜΔ, :held_suarez)
            @test ᶜYₜ.prc_e_radiation == 2 .* ᶜΔ
            @test all(iszero, ᶜYₜ.prc_e_surface_flux)

            # Equal gain and loss cancel to zero, which is the correct answer
            # for a net record and the reason a record is not a source share
            acc!(-2 .* ᶜΔ, :radiation)
            @test all(iszero, ᶜYₜ.prc_e_radiation)

            acc!(ᶜΔ, :surface_flux)
            @test ᶜYₜ.prc_e_surface_flux == ᶜΔ

            # The water family is keyed separately, so an energy-side write
            # cannot land in a water record of the same process name
            ᶜwYₜ = (; prc_q_surface_flux = zeros(FT, 4))
            CA._accumulate_records!(
                CA.water_record_field,
                ᶜwYₜ,
                ᶜΔ,
                :surface_flux,
                (sfc,),
            )
            @test ᶜwYₜ.prc_q_surface_flux == ᶜΔ
        end

        @testset "The record integrates the rate, not the step count ($FT)" begin
            # `_accumulate_records!` adds to the record's TENDENCY, and the
            # timestepper integrates it. Forward Euler is enough to show the
            # result depends on elapsed time and not on how many evaluations
            # there were. `Yₜ` is zeroed at the top of every tendency
            # evaluation, which is why a fresh one is built each step.
            rad = CA.RecordedProcess{:radiation}()
            processes = (rad,)
            rate = FT(3)

            function integrated(dt, nsteps)
                record = zeros(FT, 1)
                for _ in 1:nsteps
                    ᶜYₜ = (; prc_e_radiation = zeros(FT, 1))
                    CA._accumulate_records!(
                        CA.energy_record_field,
                        ᶜYₜ,
                        FT[rate],
                        :radiation,
                        processes,
                    )
                    record .+= ᶜYₜ.prc_e_radiation .* dt
                end
                return record[1]
            end

            # A constant rate held for 60 s is rate * 60, whatever the step
            @test integrated(FT(10), 6) ≈ rate * 60 rtol = sqrt(eps(FT))
            @test integrated(FT(5), 12) ≈ rate * 60 rtol = sqrt(eps(FT))
            @test integrated(FT(2), 30) ≈ rate * 60 rtol = sqrt(eps(FT))

            # The same interval at three step sizes must agree. This is the
            # direct regression test: summing the rate instead of integrating
            # it gave rate * nsteps, so these three would have been 6, 12 and
            # 30 times `rate` rather than equal.
            @test integrated(FT(10), 6) ≈ integrated(FT(5), 12) rtol =
                sqrt(eps(FT))
            @test integrated(FT(5), 12) ≈ integrated(FT(2), 30) rtol =
                sqrt(eps(FT))
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
        @test CA.energy_process_record_state_names(one) == (:prc_e_radiation,)

        listed = CA.process_record_from_config(
            ["radiation", "surface_flux"],
            "energy_process_record",
            CA.KNOWN_TAG_SOURCES,
            CA.TAG_SOURCE_GROUPS,
        )
        @test CA.energy_process_record_state_names(listed) ==
              (:prc_e_radiation, :prc_e_surface_flux)

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
