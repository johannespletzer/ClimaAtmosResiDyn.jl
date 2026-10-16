#!/usr/bin/env bash
# One mutant (or the control) per array task: runs its test files with
# terrabyte-test-job's test_job.sh, in its own worktree and environment.
#
#   MUT=<out_dir from make_mutants.jl> VER=1.11 \
#       sbatch --partition=$CLIMA_PARTITION_LONG --time=04:00:00 \
#       --cpus-per-task=4 --mem=48G --job-name=mut --array=0-<rows-1> \
#       --output=<out_dir>/slurm-%A_%a.out $CLIMA_SKILLS/mutation-run/scripts/mutation_job.sh
#
# Row 0 of mutants.tsv is the control. Each task writes
# <out_dir>/results/<name>.out (test_job.sh's summary) and its logs under
# <out_dir>/<name>-run/logs. Each mutant compiles ClimaAtmos into its own
# depot layer, <out_dir>/depots/<name>, in front of the shared depot, so the
# mutants' caches do not evict each other's (Julia keeps few per package).
set -u
# The site's values (account, partitions, depot) come from a private file
# outside the repository, CLIMA_SITE_ENV or ~/.config/climaatmos-fork/site.env.
# See .claude/site.example.env.
site_env=${CLIMA_SITE_ENV:-$HOME/.config/climaatmos-fork/site.env}
[[ -f $site_env ]] && source "$site_env"
: "${MUT:?set MUT to the out_dir of make_mutants.jl}"
VER=${VER:-1.11}
SHARED=${SHARED_DEPOT:-${CLIMA_JULIA_DEPOT:?set CLIMA_JULIA_DEPOT in $site_env, or SHARED_DEPOT}}
row=$(sed -n "$((${SLURM_ARRAY_TASK_ID:-0} + 1))p" "$MUT/mutants.tsv")
[ -n "$row" ] || { echo "no row ${SLURM_ARRAY_TASK_ID:-0} in $MUT/mutants.tsv" >&2; exit 2; }
IFS=$'\t' read -r name worktree env files expect why <<< "$row"
mkdir -p "$MUT/results" "$MUT/depots/$name"
echo "mutant $name: $why"
echo "expected to be caught by: ${expect:-nothing named}"
export JULIA_DEPOT_PATH="$MUT/depots/$name:$SHARED"
env CODE="$worktree" COMMIT="$(cat "$MUT/COMMIT" | cut -c1-9)+$name" TAG="$name" VER="$VER" \
    ENV_DIR="$env" FILES="$files" OUT="$MUT/$name-run" \
    bash "${CLIMA_SKILLS:?set CLIMA_SKILLS to the .claude/skills of the checkout}/terrabyte-test-job/scripts/test_job.sh" \
    > "$MUT/results/$name.out" 2>&1
status=$?
tail -n "$(( $(echo "$files" | wc -w) + 3 ))" "$MUT/results/$name.out"
exit $status
