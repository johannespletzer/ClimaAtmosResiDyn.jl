#!/usr/bin/env bash
# Fork parity on one terrabyte node: run parity_run.jl in two checkouts at once
# and compare the results bit for bit with parity_compare.jl.
#
#   A=<checkout> B=<checkout> A_COMMIT=<sha> B_COMMIT=<sha> OUT=<dir> \
#       sbatch --account=hpda-c --partition=hpda2_test --time=01:55:00 \
#       --cpus-per-task=4 --mem=48G --job-name=parity \
#       --output=<dir>/parity-%j.out experiments/tag_closure/analysis/parity/parity_job.sh [names...]
#
# Both checkouts must use the same resolved `.buildkite` manifest and
# preferences. Copy one checkout's `Project.toml`, `Manifest-v1.11.toml` and
# `LocalPreferences.toml` into the other's `.buildkite` if they differ. The
# commits are passed in because compute nodes have no git. Submit from the
# experiment branch's root, or set PARITY_DIR to the directory of the driver.
set -u
source "$MODULESHOME/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
export JULIA_DEPOT_PATH=/dss/dsstbyfs02/scratch/0D/di38kez/julia-depots/terrabyte-cpu
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-4}
JULIA="$HOME/.juliaup/bin/julia +1.11"
# Slurm runs a spooled copy of this script, so the driver and the comparison
# are found from the submission directory, the experiment branch's root.
PARITY_DIR=${PARITY_DIR:-${SLURM_SUBMIT_DIR:-$PWD}/experiments/tag_closure/analysis/parity}
mkdir -p "$OUT/a" "$OUT/b" "$OUT/run_a" "$OUT/run_b"
echo "node $(hostname), $(grep -m1 'model name' /proc/cpuinfo), start $(date -Is)"
echo "a: $A at $A_COMMIT"
echo "b: $B at $B_COMMIT"

# Precompile on this node, one environment after the other.
$JULIA --project="$A/.buildkite" -e 'using Pkg; Pkg.precompile("ClimaAtmos")' || exit 2
$JULIA --project="$B/.buildkite" -e 'using Pkg; Pkg.precompile("ClimaAtmos")' || exit 2
echo "precompiled $(date -Is)"

# The two checkouts run at once, each on its own core.
(cd "$OUT/run_a" && PARITY_COMMIT=$A_COMMIT $JULIA --project="$A/.buildkite" "$PARITY_DIR/parity_run.jl" "$OUT/a" "$@") > "$OUT/a.log" 2>&1 &
pid_a=$!
(cd "$OUT/run_b" && PARITY_COMMIT=$B_COMMIT $JULIA --project="$B/.buildkite" "$PARITY_DIR/parity_run.jl" "$OUT/b" "$@") > "$OUT/b.log" 2>&1 &
pid_b=$!
wait $pid_a; status_a=$?
wait $pid_b; status_b=$?
echo "runs done $(date -Is): a exited $status_a, b exited $status_b"
tail -n 3 "$OUT/a.log" "$OUT/b.log"
[ $status_a -eq 0 ] && [ $status_b -eq 0 ] || exit 3

$JULIA --project="$A/.buildkite" "$PARITY_DIR/parity_compare.jl" "$OUT/a" "$OUT/b" > "$OUT/compare.out" 2>&1
status=$?
cat "$OUT/compare.out"
echo "compare exit status $status, end $(date -Is)"
exit $status
