#!/usr/bin/env bash
# What an upstream merge brings, before it is made. Read-only: it runs git and
# versions_diff.jl, fetches nothing and writes nothing.
#
#   git fetch upstream main && git fetch origin
#   upstream_survey.sh [checkout] [upstream_ref] [fork_ref] > $W/survey.txt
#
# Defaults: the current directory, upstream/main, origin/main. Each section is
# capped, so the output stays readable; rerun a section's git command for more.
set -u
CHECKOUT=${1:-.}
UP=${2:-upstream/main}
FORK=${3:-origin/main}
SCRIPTS=${SCRIPTS:-${CLIMA_SKILLS:?set CLIMA_SKILLS to the .claude/skills of the checkout}/upstream-sync/scripts}
cd "$CHECKOUT" || exit 1
section() { printf '\n## %s\n' "$*"; }
changed() { grep -E '^[+-][^+-]' || true; }

section "Base"
BASE=$(git merge-base "$FORK" "$UP")
LAST=$(git log "$FORK" --merges --grep='^Merge upstream' -1 --format='%h %p %s')
echo "merge base of $FORK and $UP: $(git log -1 --format='%h %cs %s' "$BASE")"
echo "last upstream merge on $FORK: $LAST"
[ "$(git rev-parse --short "$(echo "$LAST" | cut -d' ' -f3)")" = "$(git rev-parse --short "$BASE")" ] ||
    echo "WARNING: the merge base is not the last upstream merge's second parent"
echo "upstream: $(git rev-list --count "$BASE".."$UP") commits ahead, now at $(git log -1 --format='%h %cs' "$UP")"
echo "version: $(git show "$BASE":Project.toml | grep -m1 '^version') -> $(git show "$UP":Project.toml | grep -m1 '^version')"

section "Upstream's commits (first parent, newest first)"
git log --first-parent --format='%h %cs %s' "$BASE".."$UP" | head -n 60

section "Output changes: reproducibility_tests/ref_counter.jl"
COUNTS=$(git diff "$BASE" "$UP" -- reproducibility_tests/ref_counter.jl | grep -E '^[+-][0-9]+$' | tr -d '+-' | sort -n | uniq)
if [ -z "$COUNTS" ]; then
    echo "unchanged: upstream marked no change of output"
else
    echo "counter $(echo $COUNTS | tr ' ' '\n' | head -n 1) -> $(echo $COUNTS | tr ' ' '\n' | tail -n 1): upstream changed output, so the parity reference moves"
fi

section "Compat changes upstream (Project.toml, .buildkite, docs)"
git diff "$BASE" "$UP" -- Project.toml .buildkite/Project.toml docs/Project.toml | changed | head -n 40

section "The fork's compat against the new upstream (caps and fork-only entries)"
git diff "$UP" "$FORK" -- Project.toml | changed | head -n 30

section "Upstream's .buildkite manifest, key packages"
julia +1.11 --startup-file=no "$SCRIPTS/versions_diff.jl" \
    "$BASE:.buildkite/Manifest-v1.11.toml" "$UP:.buildkite/Manifest-v1.11.toml" |
    grep -E '^(package|Clima|Cloud|Surface|Thermodynamics|RRTMGP|Insolation|SciMLBase|DiffEqBase|[0-9]+ differ)'

section "Config keys upstream removed or added (default_config.yml)"
keys() { git show "$1":config/default_configs/default_config.yml | grep -oE '^[A-Za-z0-9_]+:' | sort -u; }
REMOVED=$(comm -23 <(keys "$BASE") <(keys "$UP") | tr -d ':')
echo "removed: $(echo $REMOVED)"
echo "added: $(comm -13 <(keys "$BASE") <(keys "$UP") | tr -d ':' | tr '\n' ' ')"
# Only the fork's own lines: a line the base has verbatim is upstream's, and
# the merge resolves it.
for k in $REMOVED; do
    git grep -n -w "$k" "$FORK" -- config test src docs examples | while IFS= read -r hit; do
        path=$(echo "$hit" | cut -d: -f2)
        text=$(echo "$hit" | cut -d: -f4-)
        git show "$BASE:$path" 2>/dev/null | grep -qxF -- "$text" || echo "$hit"
    done > "${TMPDIR:-/tmp}/survey_key_hits.$$"
    n=$(wc -l < "${TMPDIR:-/tmp}/survey_key_hits.$$")
    [ "$n" -gt 0 ] && { head -n 6 "${TMPDIR:-/tmp}/survey_key_hits.$$"; [ "$n" -gt 6 ] && echo "  ... $n fork lines use $k in all"; }
    rm -f "${TMPDIR:-/tmp}/survey_key_hits.$$"
done

section "Upstream's test and CI files (A added, D deleted, R renamed, M modified)"
git diff --name-status "$BASE" "$UP" -- test .github .buildkite/pipeline.yml .buildkite/full_pipeline.yml | head -n 40
echo "An added test file needs a place in the fork's test groups (KNOWN_TEST_GROUPS)."

section "Files both sides changed since the base"
comm -12 <(git diff --name-only "$BASE" "$UP" | sort) <(git diff --name-only "$BASE" "$FORK" | sort) | head -n 60

section "Conflicts git would leave (merge-tree, nothing written)"
OUTPUT=$(git merge-tree --write-tree --name-only --no-messages "$FORK" "$UP")
STATUS=$?
if [ $STATUS -eq 0 ]; then
    echo "none: the merge is clean"
else
    echo "$OUTPUT" | tail -n +2 | head -n 60
    echo "$(($(echo "$OUTPUT" | wc -l) - 1)) files conflict"
fi

section "Upstream's NEWS entries"
git diff "$BASE" "$UP" -- NEWS.md | grep -E '^\+ *(#|- )' | head -n 20
