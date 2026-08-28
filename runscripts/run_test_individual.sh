#!/bin/tcsh -f

# Run one test file or one test group on a Levante login node, on the CPU stack.
#
#   ./runscripts/run_test_individual.sh
#
# For anything long enough to hit the login-node time limit, submit
# run_test_as_job.sh instead.

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0
setenv JULIA_DEPOT_PATH ${HOME}/.julia/depots/levante-cpu
cd ~/git/ClimaAtmosResiDyn.jl

# Pick what to run by uncommenting one line. Everything else stays commented.

# A single file.
#julia +1.11 --project=.buildkite test/parameterized_tendencies/chemistry/passive_stratospheric_tracers.jl
julia +1.11 --project=.buildkite perf/tracer_scaling.jl

# A whole test group.
#setenv TEST_GROUP parameterizations
#julia +1.11 --project -e 'using Pkg; Pkg.test()'
