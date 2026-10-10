#=
The water tags' application producer with `update_constrain_state_every:
stage`, on the column of `water_tag_applications_common.jl` in Float64 for two
steps. The constraints then also run after each Newton solve, and their maps
enter with the weight b_imp/γ. The applied records of each tag add up to the
step changes of the model's own per-tag ledgers, to rounding. A writer call
outside the counted hooks is refused at the step's end. The build is a
specialisation of its own, so it runs in a process of its own.
=#
include("water_tag_applications_common.jl")

@testset "Water tag application producer at stage cadence" begin
    # With the constraints at every stage, their maps after each Newton
    # solve enter with the weight b_imp/γ.
    # Each step's finalization refuses writer calls outside the counted
    # hooks, so this run also shows there are none at this cadence.
    staged = run!(
        compile_metered_writers(
            build(
                config(
                    "Float64",
                    true,
                    Dict{String, Any}(
                        "update_constrain_state_every" => "stage",
                        "t_end" => "20secs",
                    ),
                ),
                "water_tag_applications_stage",
            ),
        ),
    )
    step = check_model_ledgers(staged)
    template = CA.water_meter(staged.integrator.p).template
    @test any(c -> c.role === :post_newton, template.calls)
    post_newton = count(
        a -> a["role"] == "post_newton",
        reduce(
            vcat,
            [s["applications"] for s in read_receipt(staged.output_dir)[2:end]],
        ),
    )
    @info "Applied post-Newton records at stage cadence" post_newton
    @test post_newton > 0
    # A writer called outside the counted hooks has no role in the step.
    # The step's finalization refuses it, with the count and the call.
    staged_meter = CA.water_meter(staged.integrator.p)
    tag = first(staged.integrator.p.atmos.water_tagging_model.tags)
    CA.meter_water_leg!(staged_meter, :rescale, tag, CA.NonPrecipitatingPart(), 0, 0, 0)
    @test staged_meter.unattributed == 1
    @test_throws r"saw 1 writer calls outside the counted hooks.*the rescale of lower, before any counted firing" CTS.step!(
        staged.integrator,
    )
end
