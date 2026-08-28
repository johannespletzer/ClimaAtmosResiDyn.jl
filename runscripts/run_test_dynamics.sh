#!/bin/tcsh -f

# Run the `dynamics` test group on a Levante login node, on the CPU stack.
#
#   ./runscripts/run_test_dynamics.sh
#
# The line below pins CloudMicrophysics to 0.37.1 and writes to the project's
# manifest, so expect a changed Manifest.toml afterwards. Project.toml currently
# asks for 0.38, so check the pin is still the version you want before running.

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0
setenv JULIA_DEPOT_PATH ${HOME}/.julia/depots/levante-cpu
cd ~/git/ClimaAtmosResiDyn.jl

setenv TEST_GROUP dynamics

julia +1.11 --project -e 'using Pkg; Pkg.add(name="CloudMicrophysics", version="0.37.1")'
julia +1.11 --project -e 'using Pkg; Pkg.test()'
