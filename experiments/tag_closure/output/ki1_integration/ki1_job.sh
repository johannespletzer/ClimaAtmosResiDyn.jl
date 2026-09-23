#!/bin/bash
# Known issue 1 (G3 WP1): run test/tagged_water_integration.jl, copied with two
# @info lines that print the quantities its two assertions bound, against the
# clean run worktree ../ClimaAtmosResiDyn-wedmf-run (main's code after #95).
W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work
JULIA=/dss/dsshome1/0D/di38kez/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia
cd $W/g3/ki1
unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
FILE=$W/g3/ki1/tagged_water_integration_ki1.jl
echo "file: $FILE"; echo "code: /dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-wedmf-run"
time $JULIA --project=$W/wedmfrun_testenv -e "using Test; @testset \"tagged water integration\" begin; @eval module TI include(\"$FILE\") end; end"
