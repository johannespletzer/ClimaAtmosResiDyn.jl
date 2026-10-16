#!/usr/bin/env bash
# Which of upstream's new commits reach the fork's own code. Read-only: it
# runs git and reads mirrors.toml, fetches nothing and writes nothing.
#
#   git fetch upstream main && git fetch origin
#   tag_impact.sh [checkout] [upstream_ref] [fork_ref] > $W/tag_impact.txt
#
# Defaults: the current directory, upstream/main, origin/main. A flag means
# "read this commit's diff", not "this commit breaks a tag". The finer checks
# are mirror_check.jl and removed_names.jl.
set -euo pipefail
cd "${1:-.}"
UP=${2:-upstream/main}
FORK=${3:-origin/main}
MIRRORS="$(dirname "$(readlink -f "$0")")/../mirrors.toml"
BASE=$(git merge-base "$FORK" "$UP")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The functions a diff changes in one file, from git's hunk headers. A header
# names the nearest line above the hunk that starts in column one, so this is
# a close guess, not a parse.
functions() {
    git diff -U0 "$1" "$2" -- "$3" | sed -nE 's/^@@[^@]*@@ ?//p' |
        sed -nE 's/.*(function|struct|macro) +([A-Za-z0-9_!.]+).*/\2/p; t; s/^([A-Za-z0-9_!.]+)[ (].*/\1/p' |
        sort -u
}

# Upstream files the fork changed hold the fork's hooks. Files the fork added
# are its own, and upstream cannot touch them. The default config has its own
# flag.
git diff --name-only --diff-filter=M "$BASE" "$FORK" -- src ext toml |
    sort > "$TMP/hooks"
# The parent files of the mirrors that repeat upstream code.
awk -F' = ' '
    /^\[\[mirror\]\]/ { if (name != "" && parent == "upstream") print pfile "\t" name; name = parent = pfile = "" }
    $1 == "name" { gsub(/"/, "", $2); name = $2 }
    $1 == "parent" { gsub(/"/, "", $2); parent = $2 }
    $1 == "parent_file" { gsub(/"/, "", $2); pfile = $2 }
    END { if (name != "" && parent == "upstream") print pfile "\t" name }' "$MIRRORS" > "$TMP/mirrors"

printf '## Base\n%s, %s commits to %s\n' \
    "$(git log -1 --format='%h %cs' "$BASE")" "$(git rev-list --count "$BASE".."$UP")" \
    "$(git log -1 --format='%h %cs' "$UP")"
printf '%s upstream files carry fork changes; %s mirrors repeat upstream code\n' \
    "$(wc -l < "$TMP/hooks")" "$(wc -l < "$TMP/mirrors")"

printf '\n## Commits that reach the fork (oldest first)\n'
echo "Flags: M mirror parent changed, H a function the fork also changed,"
echo "h a file the fork changed (other functions), O output (ref_counter),"
echo "C config default, P parameters or compat. Read every M and H diff."
quiet=()
for c in $(git rev-list --reverse --first-parent "$BASE".."$UP"); do
    git diff-tree --no-commit-id --name-only -r -m --first-parent "$c" | sort -u > "$TMP/files"
    files_h=""
    shared=""
    for f in $(comm -12 "$TMP/files" "$TMP/hooks"); do
        both=$(comm -12 <(functions "$BASE" "$FORK" "$f") <(functions "$c^" "$c" "$f") | tr '\n' ' ')
        if [ -n "$both" ]; then
            shared+="    $f: $both"$'\n'
        else
            files_h+="$f "
        fi
    done
    mirrors=$(awk -F'\t' 'NR == FNR { f[$1] = 1; next } ($1 in f) { print $2 }' \
        "$TMP/files" "$TMP/mirrors" | sort -u | tr '\n' ' ')
    flags=""
    [ -n "$mirrors" ] && flags+="M"
    [ -n "$shared" ] && flags+="H"
    [ -n "$files_h" ] && flags+="h"
    grep -qx 'reproducibility_tests/ref_counter.jl' "$TMP/files" && flags+="O"
    grep -qx 'config/default_configs/default_config.yml' "$TMP/files" && flags+="C"
    grep -qE '^(Project\.toml|toml/|src/parameters/)' "$TMP/files" && flags+="P"
    line="$(git log -1 --format='%h %s' "$c")"
    if [ -z "$flags" ]; then
        quiet+=("$line")
        continue
    fi
    printf '\n[%s] %s\n' "$flags" "$line"
    [ -n "$mirrors" ] && printf '  mirrors: %s\n' "$mirrors"
    [ -n "$shared" ] && printf '  functions both changed:\n%s' "$shared"
    [ -n "$files_h" ] && printf '  same file, other functions: %s\n' "$files_h"
done

printf '\n## Package mirrors whose package moved in upstream'"'"'s compat\n'
moved=0
for p in $(awk -F' = ' '$1 == "parent" { gsub(/"/, "", $2); if ($2 != "upstream") print $2 }' "$MIRRORS" | sort -u); do
    old=$(git show "$BASE":Project.toml | grep -m1 "^$p = " || true)
    new=$(git show "$UP":Project.toml | grep -m1 "^$p = " || true)
    if [ "$old" != "$new" ]; then
        echo "$p: ${old:-none} -> ${new:-none} (run mirror_check.jl with both environments)"
        moved=1
    fi
done
[ "$moved" = 0 ] && echo "none"

printf '\n## Commits with no contact (%s)\n' "${#quiet[@]}"
for l in "${quiet[@]}"; do echo "$l"; done
