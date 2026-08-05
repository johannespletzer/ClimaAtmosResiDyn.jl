#!/bin/tcsh -f

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0
setenv JULIA_DEPOT_PATH ${HOME}/.julia/depots/levante-cpu
cd ~/git/ClimaAtmosResiDyn.jl

setenv TEST_GROUP dynamics 

julia +1.11 --project -e 'using Pkg; Pkg.test()'
