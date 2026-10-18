#!/usr/bin/env bash
# Fork parity on one terrabyte node: run parity_run.jl for a reference (a) and
# a candidate (b) at once, then compare them with parity_compare.jl.
#
#   A_ENV=<env> B_ENV=<env> A_COMMIT=<sha> B_COMMIT=<sha> OUT=<dir> \
#   CONFIGS=<configs.jl> [B_CONFIGS=<configs.jl>] [VER=1.11] [PREFIXES="ρq_tag_ ..."] \
#   [PARITY_FLOAT_TYPE=Float32] [NAMES="name ..."] \
#       sbatch --time=01:55:00 \
#       --cpus-per-task=4 --mem=48G --job-name=parity \
#       --output=<dir>/parity-%j.out $CLIMA_SKILLS/fork-parity/scripts/parity_job.sh
#
# The environments come from make_ci_env.jl and must share one manifest's
# versions. B_CONFIGS, when set, is the candidate's configuration file, for
# the diagnostic-on side of an off-against-on run in one checkout. The commits
# are passed in because compute nodes have no git. The skill lives in the
# checkout's .claude/skills, which CLIMA_SKILLS names.
set -u
# The site's values (account, partitions, depot) come from a private file
# outside the repository, CLIMA_SITE_ENV or ~/.config/climaatmos-fork/site.env.
# See .claude/site.example.env.
site_env=${CLIMA_SITE_ENV:-$HOME/.config/climaatmos-fork/site.env}
[[ -f $site_env ]] && source "$site_env"
type module >/dev/null 2>&1 || source "${MODULESHOME}/init/bash"
module load gcc/13.2.0 openmpi/4.1.8-gcc13
unset JULIA_LOAD_PATH JULIA_PROJECT
export JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH:-${CLIMA_JULIA_DEPOT:?set CLIMA_JULIA_DEPOT in $site_env, or JULIA_DEPOT_PATH}}
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-4}
# Musica_jll, a test dependency, needs a newer libstdc++ (CXXABI_1.3.15) than
# the one Julia ships, and Julia loads its own. The system's is new enough.
grep -q CXXABI_1.3.15 /usr/lib64/libstdc++.so.6 && export LD_PRELOAD=/usr/lib64/libstdc++.so.6
VER=${VER:-1.11}
JULIA=${JULIA:-$(ls -d "$HOME"/.julia/juliaup/julia-"$VER".*/bin/julia | sort -V | tail -n 1)}
# Slurm runs a spooled copy of this script, so its own path is no guide.
SCRIPTS=${PARITY_SCRIPTS:-${CLIMA_SKILLS:?set CLIMA_SKILLS to the .claude/skills of the checkout}/fork-parity/scripts}
B_CONFIGS=${B_CONFIGS:-$CONFIGS}
# With different configuration files b runs a diagnostic a does not, so b must
# have fields of its own. With the same file it must have none: one would be a
# fork field that is on by default. PARITY_OWN_FIELDS=any switches this off.
if [ "$B_CONFIGS" != "$CONFIGS" ]; then own=expected; else own=none; fi
export PARITY_OWN_FIELDS=${PARITY_OWN_FIELDS:-$own}
mkdir -p "$OUT/a" "$OUT/b" "$OUT/run_a" "$OUT/run_b"
echo "node $(hostname), $(grep -m1 'model name' /proc/cpuinfo), julia $VER, start $(date -Is)"
echo "a: $A_ENV at $A_COMMIT, configs $CONFIGS"
echo "b: $B_ENV at $B_COMMIT, configs $B_CONFIGS"
echo "float ${PARITY_FLOAT_TYPE:-Float64}; names ${NAMES:-all}; reported prefixes ${PREFIXES:-none}; fields only in b: $PARITY_OWN_FIELDS"

# Precompile on this node, one environment after the other. With one checkout
# on both sides the second is a no-op.
"$JULIA" --project="$A_ENV" -e 'using Pkg; Pkg.precompile()' || exit 2
"$JULIA" --project="$B_ENV" -e 'using Pkg; Pkg.precompile()' || exit 2
echo "precompiled $(date -Is)"

# The two sides run at once, each on its own core.
# shellcheck disable=SC2086
(cd "$OUT/run_a" && PARITY_COMMIT=$A_COMMIT "$JULIA" --project="$A_ENV" \
    "$SCRIPTS/parity_run.jl" "$OUT/a" "$CONFIGS" ${NAMES:-}) > "$OUT/a.log" 2>&1 &
pid_a=$!
# shellcheck disable=SC2086
(cd "$OUT/run_b" && PARITY_COMMIT=$B_COMMIT "$JULIA" --project="$B_ENV" \
    "$SCRIPTS/parity_run.jl" "$OUT/b" "$B_CONFIGS" ${NAMES:-}) > "$OUT/b.log" 2>&1 &
pid_b=$!
wait $pid_a; status_a=$?
wait $pid_b; status_b=$?
echo "runs done $(date -Is): a exited $status_a, b exited $status_b"
tail -n 3 "$OUT/a.log" "$OUT/b.log"
[ $status_a -eq 0 ] && [ $status_b -eq 0 ] || exit 3

# shellcheck disable=SC2086
"$JULIA" --project="$A_ENV" "$SCRIPTS/parity_compare.jl" "$OUT/a" "$OUT/b" ${PREFIXES:-} \
    > "$OUT/compare.out" 2>&1
status=$?
cat "$OUT/compare.out"
echo "compare exit status $status, end $(date -Is)"
exit $status
