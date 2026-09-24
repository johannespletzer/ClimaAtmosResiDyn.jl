G4.16's interim guard (rev. 2, step 0), login-node test logs, 2026-09-24.
Code: claude/energy-explicit-1m-guard (worktree ../ClimaAtmosResiDyn-g416guard), 33eeb5cd, from main at 0b2b1032.
Julia 1.11.9, depot /dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu,
environment $SCRATCH/claude_work/plan2/guard_testenv.

guard_tracer_config.log   test/config/tracer_config.jl: every testset passes; "energy_source_tags against the scheme" 24/24.
                          Run on the working tree before the commit; only a docstring cross-reference changed after.
guard_config.log          test/config.jl: every testset passes

Extension to 1M, 2M and P3 (e55ae293), same environment:
guard2_tracer_config.log  test/config/tracer_config.jl: every testset passes; "energy_source_tags against the scheme" 36/36
guard2_config.log         test/config.jl: every testset passes
water_2m_check.jl         the check that water tags with 2M or 2MP3 are refused at configuration under both
                          transports, run against claude/water-tags-wp6-step3 (#102's config code): 4 of 4 passed
