Login-node checks of 2026-09-24 for step 2 (design/W25_ISOLATION.md) and known
issue 7's probe (design/NEGATIVE_PARENT_WATER.md, section 5). Checks only: no
number here is a result.

w25_config_check.log  all 22 configs/w25i_*.yml build their model in the W25 run
                      tree and register every diagnostic they ask for.
w25_smoke.log, *.csv  analysis/water/w25_probes.jl, all three probes, on
                      w25i_d4w_default_z30_c for two steps (240 s): they run end
                      to end. The first build took about 36 min on the login node.
probe_check.log       configs/lr_s23_probe_ledgers.yml builds its model in the
                      probe run tree, keeps the old abort level 1.0, and all 68
                      diagnostics it asks for are registered.
Julia 1.11.9, the terrabyte depot; environments $SCRATCH/claude_work/plan2/
{w25i,probe}_testenv, the .buildkite manifest with ClimaAtmos at each run tree.
