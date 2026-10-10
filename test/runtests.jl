# When Julia 1.10+ is used interactively, stacktraces contain reduced type information to make them shorter.
# On the other hand, the full type information is printed when julia is not run interactively.
# Given that ClimaCore objects are heavily parametrized, non-abbreviated stacktraces are hard to read,
# so we force abbreviated stacktraces even in non-interactive runs.
# (See also Base.type_limited_string_from_context())
redirect_stderr(IOContext(stderr, :stacktrace_types_limited => Ref(false)))
using SafeTestsets
using Test

# Get test group from environment variable (default: run all tests)
TEST_GROUP = get(ENV, "TEST_GROUP", "all")

# Every group this file knows how to run. An unrecognised name matches none of
# the blocks below, runs zero tests and still exits successfully, so it is
# rejected here rather than passing silently.
const KNOWN_TEST_GROUPS = (
    "all",
    "infrastructure",
    "parent_budget",
    "diagnostics",
    "dynamics",
    "dynamics_tracers",
    "dynamics_edmfx",
    "tagging_energy",
    "tagging_water",
    "tagging_source",
    "tagging_record",
    "tagging_source_float32",
    "tagging_source_edmf",
    "tagging_source_increment",
    "tagging_source_updraft",
    "tagging_water_edmf",
    "tagging_water_edmf_copies",
    "tagging_water_edmf_copies_leak",
    "tagging_water_edmf_0m",
    "tagging_water_edmf_0m_explicit",
    "tagging_water_increment",
    "tagging_water_increment_explicit",
    "tagging_water_leak",
    "tagging_water_precipitation",
    "tagging_water_applications",
    "tagging_water_applications_parity",
    "tagging_water_applications_float32",
    "tagging_water_precipitation_sphere",
    "tagging_water_rainout_jacobian",
    "parameterizations",
    "restarts",
    "precompile",
)
TEST_GROUP in KNOWN_TEST_GROUPS || error(
    "Unknown TEST_GROUP $(repr(TEST_GROUP)). Known groups: " *
    join(KNOWN_TEST_GROUPS, ", ") *
    ". An unknown group would run no tests and exit successfully.",
)

# ============================================================================
# Precompile: no tests. `Pkg.test` precompiles the test environment before this
# file runs, and loading the packages below checks that the images load. CI
# runs this group on `main` when a merge skips the tests, so that the depot
# cache it saves still holds every image the test jobs use. `Musica` loads the
# `ClimaAtmosMusica` extension. `all` does not include it.
# ============================================================================
if TEST_GROUP == "precompile"
    using ClimaAtmos, Aqua, CairoMakie, Musica
end

#! format: off

# ============================================================================
# Infrastructure: Configuration, utilities, interfaces, and integration tests
# ============================================================================
if TEST_GROUP in ("infrastructure", "all")
    @safetestset "Aqua" begin @time include("aqua.jl") end

    @safetestset "Dependencies" begin @time include("dependencies.jl") end
    @safetestset "Callbacks" begin @time include("callbacks.jl") end
    @safetestset "Configuration tests" begin @time include("config.jl") end
    @safetestset "Grids" begin @time include("grids.jl") end
    @safetestset "Utilities" begin @time include("utilities.jl") end
    @safetestset "Variable manipulations" begin @time include("variable_manipulations_tests.jl") end
    @safetestset "Tracer processes" begin @time include("tracer_processes_tests.jl") end
    @safetestset "Tagged tracers" begin @time include("tagged_tracers_tests.jl") end
    @safetestset "Tagged water" begin @time include("tagged_water_tests.jl") end
    @safetestset "Tagged water with rain and snow parts" begin @time include("tagged_water_precipitation_tests.jl") end
    @safetestset "Tagged water rain-out Jacobian" begin @time include("tagged_water_rainout_jacobian_tests.jl") end
    @safetestset "Energy source tags" begin @time include("energy_source_tags_tests.jl") end
    @safetestset "Process records" begin @time include("process_record_tests.jl") end
    @safetestset "Parent-budget packets" begin @time include("parent_budget/reduction_tests.jl") end
    @safetestset "Parent-budget registry" begin @time include("parent_budget/registry_tests.jl") end
    @safetestset "Parent-budget journal" begin @time include("parent_budget/journal_tests.jl") end
    @safetestset "Parent-budget endpoints" begin @time include("parent_budget/endpoint_tests.jl") end
    @safetestset "Parameter tests" begin @time include("parameter_tests.jl") end

    @safetestset "Check TOML path" begin @time include("test_output_yaml_path.jl") end

    # Interface tests
    @safetestset "Radiation interface tests" begin @time include("rrtmgp_interface.jl") end
    @safetestset "Coupler compatibility" begin @time include("coupler_compatibility.jl") end
    @safetestset "Surface albedo tests" begin @time include("surface_albedo.jl") end
    @safetestset "Larcform1 setup" begin @time include("larcform1.jl") end

    # Config tests
    @safetestset "SlabOcean SST warning" begin @time include("slab_ocean_warning.jl") end
    @safetestset "Model getters" begin @time include("config/model_from_config.jl") end
    @safetestset "Tracer config" begin @time include("config/tracer_config.jl") end
    @safetestset "AtmosModel" begin @time include("config/atmos_model.jl") end
    @safetestset "Presets" begin @time include("presets.jl") end
    @safetestset "Topography tests" begin @time include("topography.jl") end
end

# ============================================================================
# Parent budget: the parent budget driven by real simulations. Every file here builds
# several `AtmosSimulation`s and compiles the tendency pipeline for each, which
# is why they are not in `infrastructure` with the parent budget's unit tests.
# ============================================================================
if TEST_GROUP in ("parent_budget", "all")
    @safetestset "Parent-budget envelopes" begin @time include("parent_budget/envelope_tests.jl") end
    @safetestset "Parent-budget implicit attribution" begin @time include("parent_budget/implicit_attribution_tests.jl") end
    @safetestset "Parent-budget implicit Smagorinsky-Lilly" begin @time include("parent_budget/implicit_smagorinsky_tests.jl") end
    @safetestset "Parent-budget explicit attribution" begin @time include("parent_budget/explicit_attribution_tests.jl") end
    @safetestset "Parent-budget transfers" begin @time include("parent_budget/transfer_tests.jl") end
    @safetestset "Parent-budget restarts" begin @time include("parent_budget/restart_tests.jl") end
    @safetestset "Parent-budget report" begin @time include("parent_budget/report_tests.jl") end
    @safetestset "Parent-budget vapour constraint" begin @time include("parent_budget/vapor_constraint_tests.jl") end
end

# ============================================================================
# Diagnostics: Unit tests for diagnostic variables
# ============================================================================
if TEST_GROUP in ("diagnostics", "all")
    @safetestset "Diagnostics unit tests" begin @time include("diagnostics/unit_diagnostics.jl") end
    @safetestset "DiagnosticsConfig" begin @time include("diagnostics/diagnostics_config.jl") end
    @safetestset "COSP subcolumn tests" begin @time include("cosp/subcol_test.jl") end
    @safetestset "COSP CloudSat optics tests" begin @time include("cosp/cloudsat_optics_test.jl") end
    @safetestset "COSP CloudSat reflectivity tests" begin @time include("cosp/cloudsat_reflectivity_test.jl") end
    @safetestset "COSP CloudSat cloud fraction tests" begin @time include("cosp/cloudsat_cloud_fraction_test.jl") end
    @safetestset "COSP CloudSat CFAD tests" begin @time include("cosp/cloudsat_cfad_test.jl") end
end

# ============================================================================
# Dynamics: Prognostic equations
# ============================================================================
# ============================================================================
# Dynamics: the prognostic equations, in three groups against the 90-minute
# job timeout. As one group the ten files took 75 to 92 minutes on GitHub's
# runners, and a job cancelled at the limit reports as failed while never
# running the files that had not started. Almost all of the time is
# compilation of freshly built models: measured on one CPU with Julia 1.11,
# `tracer_mass_consistency_tests.jl` took 24 minutes,
# `edmfx_horizontal_diffusion_tests.jl` 17, `enforce_physical_constraints_tests.jl`
# 7, `edmfx_sgs_diffusive_flux_tests.jl` 4.5, and the other six files 7
# minutes together. The groups keep related files together and each stays
# under half the limit: the transport and water-consistency files, the two
# EDMFX diffusion files, and the rest.
#
# `dynamics` also runs the ERA5 forcing files, which used to be a group of
# their own. They build no simulation and use synthetic NetCDF files. They took
# about 2 minutes, or 5 to 8 at minimum compat, of a 10 to 23 minute job. The
# rest of that job was the setup every job pays.
if TEST_GROUP in ("dynamics", "all")
    @safetestset "Prognostic equations" begin @time include("prognostic_equations.jl") end
    @safetestset "Advection operators" begin @time include("prognostic_equations/advection_tests.jl") end
    @safetestset "Hyperdiffusion" begin @time include("prognostic_equations/hyperdiffusion_tests.jl") end
    @safetestset "Post-Newton implicit-advection correction" begin @time include("prognostic_equations/correct_implicit_advection_tests.jl") end
    @safetestset "Vertical diffusion tendency" begin @time include("prognostic_equations/vertical_diffusion_tests.jl") end
    @safetestset "Eddy diffusion closures" begin @time include("prognostic_equations/eddy_diffusion_closures_tests.jl") end
    @safetestset "ERA5 forcing" begin @time include("era5_tests.jl") end
    @safetestset "ERA5 model levels" begin @time include("era5_model_levels_tests.jl") end
    @safetestset "Column datasets" begin @time include("column_datasets_tests.jl") end
end

if TEST_GROUP in ("dynamics_tracers", "all")
    @safetestset "Tracer/mass transport consistency" begin @time include("prognostic_equations/tracer_mass_consistency_tests.jl") end
    @safetestset "Vertical water borrowing limiter" begin @time include("prognostic_equations/vertical_water_borrowing_tests.jl") end
    @safetestset "Enforce physical constraints" begin @time include("prognostic_equations/enforce_physical_constraints_tests.jl") end
end

if TEST_GROUP in ("dynamics_edmfx", "all")
    @safetestset "EDMFX SGS diffusive flux" begin @time include("prognostic_equations/edmfx_sgs_diffusive_flux_tests.jl") end
    @safetestset "EDMFX horizontal diffusive flux" begin @time include("prognostic_equations/edmfx_horizontal_diffusion_tests.jl") end
end

# ============================================================================
# Tagging: end-to-end tagged energy, tagged water, energy source and process
# record simulations. One group per file.
#
# These call `solve_atmos!` on many different tag sets. A tag name is a type
# parameter (`WaterTag{name, R, S}`), so each set is a fresh `AtmosModel` type
# and the whole tendency and solve pipeline is compiled from scratch, about
# 7 minutes per simulation on 1.11 against 1 to 2 minutes on 1.10.
#
# One group per file, because the files share no compilation: combining them
# adds their compile times with nothing reused. A job that then overruns its
# timeout is cancelled and reports as failed, and it also never runs the files
# that had not started, so the loss of coverage is silent even though the job
# is not.
#
# In CI each group runs on Julia 1.11 when a pull request is ready for review,
# and on 1.10 nightly (docs/clima_atmos_specific.md, "Which jobs run when").
#
# Each group runs against a 90-minute timeout, so keep new work to the smallest
# tag set that proves the claim, and prefer extending a set an existing test in
# the same file already builds. A second simulation with an identical tag
# signature costs seconds instead of minutes.
#
# Memory limits a group as well. A GitHub runner has 16 GB, and every model
# type a process compiles stays in its memory. An EDMF build holds about
# 12 to 14 GiB, and ClimaAtmos logs the process's memory after each solve
# ("Memory currently used ... (RSS)"). A job that runs out is not reported as
# a failed test: the runner is shut down and the job reads "The operation was
# canceled." Before adding a build to a group, check those lines in a local
# run, and keep the group well below 16 GiB.
# ============================================================================
if TEST_GROUP in ("tagging_energy", "all")
    @safetestset "Tagged tracers integration" begin @time include("tagged_tracers_integration.jl") end
end

if TEST_GROUP in ("tagging_water", "all")
    @safetestset "Tagged water integration" begin @time include("tagged_water_integration.jl") end
end

if TEST_GROUP in ("tagging_source", "all")
    @safetestset "Energy source tags integration" begin @time include("energy_source_tags_integration.jl") end
    # The cold precipitating column is the only state that reaches
    # sedimentation's upward branch, where falling ice carries negative energy.
    @safetestset "Energy source tags on a cold column" begin @time include("energy_source_tags_cold_column.jl") end
end

if TEST_GROUP in ("tagging_record", "all")
    @safetestset "Process record integration" begin @time include("process_record_integration.jl") end
end

# A separate group rather than folded into `tagging_source` or `tagging_record`,
# for the same "one group per file" reason as the rest of this section: the
# Float32 model configures both `energy_source_tags` and `energy_process_record`
# together, which is a type neither of those two files' models share, so it
# costs its own compile wherever it lives. Keeping it in its own group leaves
# the other two groups' CI time exactly as measured, rather than adding an
# unmeasured compile (1-moment microphysics included) on top of time limits
# this change has no data on.
if TEST_GROUP in ("tagging_source_float32", "all")
    @safetestset "Energy source tags and process records (Float32) integration" begin
        @time include("energy_source_tags_float32_integration.jl")
    end
end

# The EDMF column is the most expensive model in the suite to build, and this
# file builds it twice, with the tags and without them. A group of its own
# keeps that out of the other groups' time limits.
if TEST_GROUP in ("tagging_source_edmf", "all")
    @safetestset "Energy source tags under EDMF integration" begin
        @time include("energy_source_tags_edmf_integration.jl")
    end
end

# `energy_source_tag_transport: enthalpy_increment` is a model type of its own,
# and its check against the column without tags needs a second. The file builds
# the EDMF column twice, so it has a group of its own.
if TEST_GROUP in ("tagging_source_increment", "all")
    @safetestset "Energy source tags following the implicit increment" begin
        @time include("energy_source_tags_increment_integration.jl")
    end
end

# The tags' updraft copies are a model type of their own, and the check against
# the column without tags needs a second. With the increment's two builds in one
# group, the three overran the timeout, so this file has a group of its own.
if TEST_GROUP in ("tagging_source_updraft", "all")
    @safetestset "Energy source tags with updraft copies" begin
        @time include("energy_source_tags_updraft_integration.jl")
    end
end

# The water tags under prognostic EDMF. Each file builds the EDMF column twice,
# with the tags and without them, and two builds fill a job's time limit, as they
# do for the energy source tags. So each has a group of its own: the default
# mode under 1M, the copies under 1M with the microphysics explicit, and the
# copies under 0M with the microphysics implicit, the default.
if TEST_GROUP in ("tagging_water_edmf", "all")
    @safetestset "Water tags under EDMF" begin
        @time include("tagged_water_edmf_integration.jl")
    end
end

if TEST_GROUP in ("tagging_water_edmf_copies", "all")
    @safetestset "Water tags with updraft copies" begin
        @time include("tagged_water_edmf_copies_integration.jl")
    end
end

# The copies with `water_tag_leak_correction: true` are a third EDMF model type.
# With the copies' own two builds in one process, it came close to the 16 GB a
# GitHub runner has, so it has a group of its own.
if TEST_GROUP in ("tagging_water_edmf_copies_leak", "all")
    @safetestset "Water tags with updraft copies and the leak correction" begin
        @time include("tagged_water_edmf_copies_leak_integration.jl")
    end
end

if TEST_GROUP in ("tagging_water_edmf_0m", "all")
    @safetestset "Water tags with updraft copies under 0M" begin
        @time include("tagged_water_edmf_0m_integration.jl")
    end
end

# The 0M rain-out split with the microphysics stepped explicitly, in both
# modes. Its three builds compile the explicit path, so it has a group of its
# own.
if TEST_GROUP in ("tagging_water_edmf_0m_explicit", "all")
    @safetestset "The 0M rain-out split, microphysics explicit" begin
        @time include("tagged_water_edmf_0m_explicit_integration.jl")
    end
end

# `water_tag_transport: increment` builds the EDMF column twice as well, with
# the tags following the parent's increment and without tags.
if TEST_GROUP in ("tagging_water_increment", "all")
    @safetestset "Water tags following the implicit increment" begin
        @time include("tagged_water_increment_integration.jl")
    end
end

# The same with the microphysics stepped explicitly, where the tags' closure
# rests on their sedimentation cross blocks. Its two builds compile the
# explicit path, so it has a group of its own too.
if TEST_GROUP in ("tagging_water_increment_explicit", "all")
    @safetestset "Water tags following the increment, microphysics explicit" begin
        @time include("tagged_water_increment_explicit_integration.jl")
    end
end

# `water_tag_leak_correction: true` is a model type of its own, and its check
# against the column without tags needs a second build, so it has its own group.
if TEST_GROUP in ("tagging_water_leak", "all")
    @safetestset "Water tags with the diffusion leak correction" begin
        @time include("tagged_water_leak_correction_integration.jl")
    end
end

# The water tags' rain and snow parts (`water_tag_precipitation: true`) on a
# 1-moment column without EDMF. The file builds the column three times: with
# the parts under each transport, and without tags.
if TEST_GROUP in ("tagging_water_precipitation", "all")
    @safetestset "Water tags with rain and snow parts" begin
        @time include("tagged_water_precipitation_integration.jl")
    end
end

# The water tags' application producer on the column of the rain and snow
# parts, in Float64. The file builds the column four times: with the
# producer, with the constraints at every stage, and twice from a checkpoint of
# the first. With the two groups below in one process, it took about 98
# minutes and 23.5 GB on Julia 1.10, past a GitHub runner's 90 minutes and
# 16 GB. So each float type's parity has a process of its own.
if TEST_GROUP in ("tagging_water_applications", "all")
    @safetestset "Water tag application producer" begin
        @time include("water_tag_applications_integration.jl")
    end
end

# The model's fields with the producer and without it, after each of six
# steps, bit for bit. Each group builds the column twice in one float type.
if TEST_GROUP in ("tagging_water_applications_parity", "all")
    @safetestset "Water tag application producer: parity in Float64" begin
        include("water_tag_applications_parity_integration.jl")
        # Called in the latest world, since the include above defines it.
        @time Base.invokelatest(check_parity, "Float64")
    end
end
if TEST_GROUP in ("tagging_water_applications_float32", "all")
    @safetestset "Water tag application producer: parity in Float32" begin
        include("water_tag_applications_parity_integration.jl")
        @time Base.invokelatest(check_parity, "Float32")
    end
end

# The same parts under the horizontal operators, on a small sphere built twice,
# with the parts and without tags. It was part of the group above. After the
# column's three builds, the sphere took the process past the 16 GB a GitHub
# runner has, and on Julia 1.10 the runner was shut down during the first
# sphere's solve, in 3 of 7 runs. So the sphere runs in a process of its own.
if TEST_GROUP in ("tagging_water_precipitation_sphere", "all")
    @safetestset "Water tags with rain and snow parts on a sphere" begin
        @time include("tagged_water_precipitation_sphere_integration.jl")
    end
end

if TEST_GROUP in ("tagging_water_rainout_jacobian", "all")
    @safetestset "Tagged water rain-out Jacobian integration" begin
        @time include("tagged_water_rainout_jacobian_integration.jl")
    end
end

# ============================================================================
# Parameterizations: Parameterized tendency tests (excluding ERA5)
# ============================================================================
if TEST_GROUP in ("parameterizations", "all")
    # Sponge layers (combined for shared space setup)
    @safetestset "Sponge layers" begin @time include("parameterized_tendencies/sponge.jl") end
    @safetestset "LES energy flux split" begin @time include("parameterized_tendencies/les_energy_split_tests.jl") end

    # Microphysics tests
    @safetestset "Microphysics tendency tests" begin @time include("parameterized_tendencies/microphysics/tendency.jl") end
    @safetestset "Microphysics wrappers tests" begin @time include("parameterized_tendencies/microphysics/microphysics_wrappers.jl") end
    @safetestset "SGS quadrature tests" begin @time include("parameterized_tendencies/microphysics/sgs_quadrature.jl") end
    @safetestset "SGS moments tests" begin @time include("parameterized_tendencies/microphysics/sgs_moments.jl") end
    @safetestset "Tendency limiters tests" begin @time include("parameterized_tendencies/microphysics/tendency_limiters.jl") end
    @safetestset "Moisture fixers tests" begin @time include("parameterized_tendencies/microphysics/moisture_fixers.jl") end
    @safetestset "Cloud fraction tests" begin @time include("parameterized_tendencies/microphysics/cloud_fraction.jl") end
    @safetestset "SGS saturation tests" begin @time include("parameterized_tendencies/microphysics/sgs_saturation.jl") end
    @safetestset "BMT integration tests" begin @time include("parameterized_tendencies/microphysics/bmt_integration.jl") end
    @safetestset "Allocation tests" begin @time include("parameterized_tendencies/microphysics/allocations.jl") end

    # Chemistry tests
    @safetestset "Chemistry tendency tests" begin @time include("parameterized_tendencies/chemistry/chemistry_tendency.jl") end
    @safetestset "Passive stratospheric tracers" begin @time include("parameterized_tendencies/chemistry/passive_stratospheric_tracers.jl") end

    # Gravity wave: Beres convective NOGW pure-function unit tests (no simulation
    # build). The simulation-based Beres tests (test_beres_single_column.jl,
    # test_beres_sphere_integration.jl) run as standalone Buildkite steps.
    @safetestset "Beres NOGW unit tests" begin @time include("parameterized_tendencies/gravity_wave/non_orographic_gravity_wave/test_beres_unit.jl") end

    # NOTE: Gravity wave visualization scripts (test_nogw_3d.jl, test_nogw_mima.jl,
    # test_nogw_single_column.jl, test_ogw_3d.jl, test_ogw_baseflux.jl) are not included
    # in the test suite because they have no @test assertions - they only generate
    # comparison plots for visual verification.
end

# ============================================================================
# Restarts: Restart and reproducibility tests. Upstream runs restart.jl and
# unit_reproducibility_infra.jl as Buildkite steps. The fork has no Buildkite,
# so they run here. With no arguments, restart.jl runs its basic set.
# ============================================================================
if TEST_GROUP in ("restarts", "all")
    @safetestset "Restarts" begin @time include("restart.jl") end
    @safetestset "Reproducibility infra" begin @time include("unit_reproducibility_infra.jl") end
    @safetestset "Init with file" begin @time include("test_init_with_file.jl") end
end
#! format: on

nothing
