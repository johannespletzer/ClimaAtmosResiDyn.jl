#!/usr/bin/env bash
# Local pre-flight for a parent-budget batch. Run it before every push so that one
# push costs one CI round. It mirrors what CI checks, in the order the cheap checks
# come first:
#
#   1. parse   every Julia file the branch changed, plus src/parent_budget and
#              test/parent_budget, with the Julia parser
#   2. hygiene trailing whitespace and a final newline on changed text files, which
#              is what the prek hooks in .pre-commit-config.yaml fix
#   3. columns report .jl lines wider than the 92-column margin. The formatter cannot
#              wrap comments and strings, so this is a warning, not a failure
#   4. links   .dev/check_markdown_link_ambiguity.py on changed .jl and .md files
#   5. shapes  .dev/check_identity_shapes.jl: a named identity tuple and the
#              container that stores it must agree
#   6. format  the pinned JuliaFormatter =2.10.1 from .dev/format over the whole
#              repository, exactly as the prek julia-formatter hook runs it. With
#              --fix the files are rewritten in place, which also pads every
#              markdown table to its widest cell. Without --fix nothing is
#              written and an unformatted tree fails the pre-flight
#   7. tests   with --test, TEST_GROUP=infrastructure through Pkg.test
#
# Usage: .dev/preflight.sh [--base <ref>] [--fix] [--test]
#   --base  the ref the branch is compared against to find changed files. Defaults to
#           origin/main. For a stacked branch pass the parent branch.
set -euo pipefail

base="origin/main"
fix=0
run_tests=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base) base="$2"; shift 2 ;;
        --fix) fix=1; shift ;;
        --test) run_tests=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

repo=$(git rev-parse --show-toplevel)
cd "$repo"
julia_cmd=${JULIA:-julia}
failures=0

# Changed files: committed since the merge base with $base, plus the working tree.
merge_base=$(git merge-base "$base" HEAD)
mapfile -t changed < <( { git diff --name-only "$merge_base" HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | while read -r f; do [ -f "$f" ] && echo "$f"; done )
changed_jl=(); changed_md=(); changed_text=()
for f in "${changed[@]:-}"; do
    [ -z "$f" ] && continue
    case "$f" in
        *.jl) changed_jl+=("$f"); changed_text+=("$f") ;;
        *.md) changed_md+=("$f"); changed_text+=("$f") ;;
        *.toml|*.yml|*.yaml|*.sh|*.py) changed_text+=("$f") ;;
    esac
done
echo "pre-flight on $(git rev-parse --short HEAD), ${#changed[@]} changed file(s) against $base"

# 1. parse
parse_targets=("${changed_jl[@]:-}")
while IFS= read -r f; do parse_targets+=("$f"); done < <(git ls-files 'src/parent_budget/*.jl' 'test/parent_budget/*.jl')
mapfile -t parse_targets < <(printf '%s\n' "${parse_targets[@]}" | grep -v '^$' | sort -u)
if [ ${#parse_targets[@]} -gt 0 ]; then
    if "$julia_cmd" --startup-file=no -e '
        bad = 0
        walk(ex, file) = begin
            if ex isa Expr
                if ex.head === :error || ex.head === :incomplete
                    println(file, ": ", ex)
                    global bad += 1
                end
                foreach(a -> walk(a, file), ex.args)
            end
        end
        for file in ARGS
            walk(Meta.parseall(read(file, String); filename = file), file)
        end
        bad == 0 || exit(1)' "${parse_targets[@]}"; then
        echo "1. parse: ok (${#parse_targets[@]} files)"
    else
        echo "1. parse: FAILED"; failures=$((failures + 1))
    fi
fi

# 2. hygiene
hygiene_bad=0
for f in "${changed_text[@]:-}"; do
    [ -z "$f" ] && continue
    if grep -n -E '[[:space:]]+$' "$f" >/dev/null; then
        if [ $fix -eq 1 ]; then sed -i -E 's/[[:space:]]+$//' "$f"; else echo "   trailing whitespace: $f"; hygiene_bad=1; fi
    fi
    if [ -s "$f" ] && [ "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" != '\n' ]; then
        if [ $fix -eq 1 ]; then printf '\n' >> "$f"; else echo "   no final newline: $f"; hygiene_bad=1; fi
    fi
done
if [ $hygiene_bad -eq 0 ]; then echo "2. hygiene: ok"; else echo "2. hygiene: FAILED (rerun with --fix)"; failures=$((failures + 1)); fi

# 3. columns (warning only)
if [ ${#changed_jl[@]} -gt 0 ]; then
    python3 - "${changed_jl[@]}" <<'PY'
import sys
wide = 0
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        for number, line in enumerate(fh, 1):
            if len(line.rstrip("\n")) > 92:
                print("   {}:{}: {} columns".format(path, number, len(line.rstrip("\n"))))
                wide += 1
print("3. columns: {} line(s) over 92 in changed .jl files (warning)".format(wide))
PY
else
    echo "3. columns: no changed .jl files"
fi

# 4. links
link_targets=("${changed_jl[@]:-}" "${changed_md[@]:-}")
mapfile -t link_targets < <(printf '%s\n' "${link_targets[@]}" | grep -v '^$' | grep -v '^docs/dev-guides/' | sort -u)
if [ ${#link_targets[@]} -gt 0 ]; then
    if python3 .dev/check_markdown_link_ambiguity.py "${link_targets[@]}"; then
        echo "4. links: ok"
    else
        echo "4. links: FAILED"; failures=$((failures + 1))
    fi
else
    echo "4. links: nothing to check"
fi

# 5. shapes
if "$julia_cmd" --startup-file=no .dev/check_identity_shapes.jl src/parent_budget; then
    echo "5. shapes: ok"
else
    echo "5. shapes: FAILED"; failures=$((failures + 1))
fi

# 6. format
# Check mode asks the formatter whether the tree is already formatted and writes
# nothing, so a stale index or a user's uncommitted work is never touched. Fix mode
# rewrites in place.
overwrite=false; [ $fix -eq 1 ] && overwrite=true
if "$julia_cmd" --startup-file=no --project=.dev/format -e '
    using Pkg
    try Pkg.resolve(; io = devnull) catch; Pkg.update(; io = devnull) end
    Pkg.instantiate(; io = devnull)
    using JuliaFormatter
    v = pkgversion(JuliaFormatter)
    v == v"2.10.1" || error("JuliaFormatter is $v, CI pins =2.10.1")
    format("."; overwrite = ARGS[1] == "true") || exit(1)' "$overwrite"; then
    echo "6. format: ok (pinned JuliaFormatter, tree already formatted)"
elif [ $fix -eq 1 ]; then
    echo "6. format: rewrote; review with git diff, then rerun without --fix"
else
    echo "6. format: FAILED, the tree is not formatted; rerun with --fix to rewrite"
    failures=$((failures + 1))
fi

# 7. tests
if [ $run_tests -eq 1 ]; then
    if TEST_GROUP=infrastructure "$julia_cmd" --project -e 'using Pkg; Pkg.test()'; then
        echo "7. tests: ok"
    else
        echo "7. tests: FAILED"; failures=$((failures + 1))
    fi
fi

if [ $failures -eq 0 ]; then echo "pre-flight: green"; else echo "pre-flight: $failures failure(s)"; exit 1; fi
