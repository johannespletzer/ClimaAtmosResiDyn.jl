#!/bin/tcsh -f

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

# Individual files
#julia +1.11 --project=.buildkite perf/tracer_scaling.jl

# All tests in folder
setenv TEST_GROUP parameterizations
julia +1.11 --project -e 'using Pkg; Pkg.test()'

#setenv TEST_GROUP infrastructure 
#julia +1.11 --project -e 'import Pkg; Pkg.test()'
