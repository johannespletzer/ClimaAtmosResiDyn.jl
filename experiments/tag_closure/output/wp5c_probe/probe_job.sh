#!/bin/bash
# WP5b's probe: $LABEL off runs the code without cross blocks, on with them.
W=/dss/dsstbyfs02/scratch/0D/di38kez/claude_work/g3/wp5c
if [ "$LABEL" = off ]; then ENV=$W/testenv-off; CODE=/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-wedmf5b-off; else ENV=$W/testenv; CODE=/dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-wedmf5c; fi
mkdir -p $W/probe && cd $W/probe
unset JULIA_LOAD_PATH JULIA_PROJECT
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
echo "probe: $MODE $TRANSPORT newton $NEWTON $LABEL at $(git -C $CODE rev-parse --short HEAD 2>/dev/null)"
time /dss/dsshome1/0D/di38kez/.julia/juliaup/julia-1.11.9+0.x64.linux.gnu/bin/julia --project=$ENV /dss/dsshome1/0D/di38kez/git/Clima/ClimaAtmosResiDyn-exp/experiments/tag_closure/analysis/water/wp5b_probe.jl "$MODE" "$TRANSPORT" "$NEWTON" "$LABEL" $W/probe
