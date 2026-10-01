# Helpers shared by `tagged_water_precipitation_integration.jl` (the column)
# and `tagged_water_precipitation_sphere_integration.jl` (the sphere). The two
# run as separate test groups, each in a process of its own: together they
# needed more than the 16 GB a GitHub runner has. Each file imports `Test` and
# `ClimaAtmos as CA` before it includes this one.

function build(config, job_id)
    return CA.get_simulation(CA.AtmosConfig(config; job_id))
end
function run!(simulation)
    @test CA.solve_atmos!(simulation).ret_code == :success
    return simulation
end

# Each compartment of the parent that the parts partition.
compartments(Y) = (;
    ρq_tag_ = parent(Y.c.ρq_tot) .- parent(Y.c.ρq_rai) .- parent(Y.c.ρq_sno),
    ρq_rtag_ = parent(Y.c.ρq_rai),
    ρq_stag_ = parent(Y.c.ρq_sno),
)

# The model's own fields, compared with `isequal`, which tells signed zeros
# apart. See "Fork parity with upstream" in `docs/clima_atmos_specific.md`.
function test_parity(Y, Y_plain)
    for name in propertynames(Y_plain.c)
        @test isequal(
            parent(getproperty(Y.c, name)),
            parent(getproperty(Y_plain.c, name)),
        )
    end
    @test isequal(parent(Y.f), parent(Y_plain.f))
    @test all(
        name ->
            hasproperty(Y_plain.c, name) ||
            CA.is_tagged_tracer_name(name) ||
            CA.is_tag_mechanism_ledger_name(name) ||
            CA.is_water_tag_ledger_name(name) ||
            CA.is_water_tag_exp_ledger_name(name) ||
            CA.is_water_tag_audit_name(name),
        propertynames(Y.c),
    )
end
