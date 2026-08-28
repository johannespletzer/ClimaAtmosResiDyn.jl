#!/bin/tcsh -f

# Run the short stratospheric passive tracer job on a Levante login node, on the
# CPU stack. This is the CI configuration, so it covers two simulated days and
# finishes in minutes. Use it to check that a change still runs end to end.
#
#   ./runscripts/run_strat.tcsh
#
# For a full multi-year integration, submit one of the xmodel.* GPU jobs with
# SCRIPT=experiments/passive_stratospheric_tracers.jl.

if (-f /sw/etc/csh.levante) then
    source /sw/etc/csh.levante
endif

module purge
module load gcc/11.2.0-gcc-11.2.0
module load openmpi/4.1.2-gcc-11.2.0
setenv JULIA_DEPOT_PATH ${HOME}/.julia/depots/levante-cpu
cd ~/git/ClimaAtmosResiDyn.jl

julia +1.11 --project=.buildkite .buildkite/ci_driver.jl \
  --config_file config/common_configs/numerics_sphere_he6ze31.yml \
  --config_file config/model_configs/passive_stratospheric_tracers_ci.yml \
  --job_id passive_stratospheric_tracers_ci
