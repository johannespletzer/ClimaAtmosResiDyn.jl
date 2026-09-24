#!/bin/bash
# Run one Julia script ($SCRIPT) against the WP4a worktree, in its own dir.
W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work
mkdir -p $W/g3/wp5b/scripts/$(basename $SCRIPT .jl) && cd $W/g3/wp5b/scripts/$(basename $SCRIPT .jl)
unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
echo "script: $SCRIPT at $(git -C /dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-wedmf5b rev-parse --short HEAD)"
time /dss/dsshome1/0D/di38kez/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia --project=$W/g3/wp5b/testenv $SCRIPT
