#!/bin/tcsh -f

# Run one ClimaAtmos test group on Levante as a batch job, on the CPU stack.
# The test groups are long enough that a login node times out, so they go to the
# shared partition.
#
#   sbatch runscripts/run_test_as_job.sh
#
# Output lands in tracer-tests-<jobid>.out next to where you submitted from.
# Edit the group at the bottom to pick what runs. Use run_test_individual.sh
# instead for a quick check on a login node.

#SBATCH --job-name=tracer-tests
#SBATCH --account=bd1062
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --output=tracer-tests-%j.out
#SBATCH --error=tracer-tests-%j.err

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0
setenv JULIA_DEPOT_PATH ${HOME}/.julia/depots/levante-cpu
cd ~/git/ClimaAtmosResiDyn.jl

# Pick what to run by uncommenting one block. Everything else stays commented.

# A single file.
#julia +1.11 --project=.buildkite perf/tracer_scaling.jl

# A whole test group.
setenv TEST_GROUP parameterizations
julia +1.11 --project -e 'using Pkg; Pkg.test()'

#setenv TEST_GROUP infrastructure
#julia +1.11 --project -e 'import Pkg; Pkg.test()'
