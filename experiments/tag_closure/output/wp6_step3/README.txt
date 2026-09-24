WP6 step 3 (rev. 2, step 1), login-node test logs, 2026-09-24.
Code: claude/water-tags-wp6-step3 (worktree ../ClimaAtmosResiDyn-wp6s3), on #103 at f22cfb27.
Julia 1.11.9, depot /dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu,
environment $SCRATCH/claude_work/plan2/wp6s3_testenv (the .buildkite manifest with ClimaAtmos at the worktree).

wp6s3_tagged_water_tests.log          test/tagged_water_tests.jl at 98324f00..a0d00b25 (run on the working tree just before those commits): 567 passed
wp6s3_energy_source_tags_tests.log    test/energy_source_tags_tests.jl, same code: 548 passed
wp6s3_tracer_config.log               test/config/tracer_config.jl, same code: 267 passed
base_tagged_water_tests.log           test/tagged_water_tests.jl at f22cfb27 (git archive in scratch), the baseline: 457 passed.
                                      Its "Internal error ... stack overflow" line is the same as in the new run.
test/tagged_water_increment_integration.jl was started on the login node and stopped after 34 min,
still in its first build with no output; it waits for a compute node (see the report).
