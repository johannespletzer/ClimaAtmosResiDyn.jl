#!/usr/bin/env bash
# Decide what the `ci` workflow runs for this event. Prints `key=value` lines
# for `$GITHUB_OUTPUT`: `tier`, `matrix`, `full_scope`, `check_bounds` and
# `allow_fail`. The reason goes to stderr and to the step summary.
#
# The tiers (docs/clima_atmos_specific.md, "Which jobs run when"):
#
#   none     only this job. The change touches only paths no test reads, or
#            the last green scheduled run tested this commit of `main`.
#   quick    the load jobs and `infrastructure` on 1.11. A draft pull request.
#   full     every group on 1.11. A pull request ready for review, and a push
#            to `main` that merges a tree no green `ci-full` has tested.
#   cache    the load jobs and a cache warm-up. A push to `main` that merges
#            exactly the tree a green `ci-full` tested on the pull request.
#   nightly  the fork's groups on 1.10. The Monday-to-Saturday schedule.
#   all      every group on 1.11 and the fork's groups on 1.10. The Sunday
#            schedule and tags.
#   manual   what a manual run (`workflow_dispatch`) asks for.
#
# Every tier runs the tests with `check_bounds: auto`, which lets `@inbounds`
# skip the bounds checks, except `all`, which keeps `yes`. On 2026-09-29 `auto`
# compiled the tagged models 1.4 to 2.8 times faster on Julia 1.11 (2.2 times
# summed over parent_budget, tagging_water and tagging_source_edmf). No test
# checks bounds itself, so the weekly run is where an out-of-bounds access
# still shows up.
#
# Environment: EVENT_NAME, GITHUB_REF, PR_DRAFT, PUSH_BEFORE, SCHEDULE,
# DISPATCH_VERSIONS, DISPATCH_GROUPS, DISPATCH_CHECK_BOUNDS, ALLOW_FAIL, and
# GH_TOKEN with GITHUB_REPOSITORY for the check-run lookup. For a local replay,
# CI_PLAN_HEAD names the commit to plan for instead of the checkout, GROUPS_JSON
# skips Julia, and CI_PLAN_FAKE_CI_FULL (success or failure) and
# CI_PLAN_FAKE_LAST_SCHEDULED (a SHA, or "none") skip the API.
set -euo pipefail

head=${CI_PLAN_HEAD:-HEAD}

# The Sunday schedule. Keep it equal to the second cron line in ci.yml.
readonly WEEKLY_CRON='0 1 * * 0'
# The groups that test upstream code. They run on 1.11 only, except in a manual
# run on both versions, because a difference between Julia versions inside
# upstream code is upstream's to find.
readonly UPSTREAM_ONLY='["dynamics","dynamics_tracers","dynamics_edmfx","restarts"]'
# The groups of the quick tier.
readonly QUICK='["infrastructure"]'

note() {
    echo "$*" >&2
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$*" >>"$GITHUB_STEP_SUMMARY"; fi
}

if [ -z "${GROUPS_JSON:-}" ]; then
    GROUPS_JSON=$(julia --startup-file=no .github/read_test_groups.jl | sed -n 's/^groups=//p')
fi
jq -e 'type == "array" and length > 0' <<<"$GROUPS_JSON" >/dev/null
fork_groups=$(jq -c --argjson up "$UPSTREAM_ONLY" '[.[] | select(. as $g | $up | index($g) | not)]' <<<"$GROUPS_JSON")

# `on_version v` turns a JSON list of groups on stdin into matrix entries.
on_version() { jq -c --arg v "$1" '[.[] | {version: $v, test_group: .}]'; }

# Paths no test, no package code and no load reads. Everything else, including
# a path this list does not know, runs the tests. One page under docs/ is read
# by a test, test/parent_budget/registry_tests.jl, so its directory is not
# inert.
is_inert() {
    case "$1" in
        docs/src/parent_budget/*) return 1 ;;
        docs/* | experiments/* | runscripts/* | calibration/*) return 0 ;;
        .pre-commit-config.yaml) return 0 ;;
        .github/workflows/ci.yml) return 1 ;;
        .github/workflows/*) return 0 ;;
        */*) return 1 ;;
        *.md) return 0 ;;
        *) return 1 ;;
    esac
}

# The list above is only safe while no other file under test/, src/ or ext/
# builds a path into those directories, as `joinpath(pkgdir(CA), "docs", ...)`
# does. If one does, nothing counts as inert until the list is updated.
inert_allowed=1
readers=$(git grep -l -E '"(docs|experiments|runscripts|calibration)"' "$head" -- test src ext |
    sed "s/^$head://" || true)
unexpected=$(printf '%s\n' "$readers" | grep -v -x -e '' -e 'test/parent_budget/registry_tests.jl' || true)
if [ -n "$unexpected" ]; then
    inert_allowed=0
    note "These files read a path the plan treats as inert, so every path runs the tests: $unexpected"
fi

# True when the diff between two commits is not empty and touches only inert
# paths. `--no-renames` lists a renamed file under both names, so a file moved
# out of src/ still counts as a change to src/.
only_inert() {
    [ "$inert_allowed" = 1 ] || return 1
    local files f
    files=$(git diff --no-renames --name-only "$1" "$2")
    [ -n "$files" ] || return 1
    while IFS= read -r f; do
        is_inert "$f" || return 1
    done <<<"$files"
}

# True when the latest completed `ci-full` on a commit passed. A skipped
# `ci-full`, from a draft's run, does not count. Any failure of the lookup
# counts as "not tested", which costs a full run and nothing else.
ci_full_green() {
    if [ -n "${CI_PLAN_FAKE_CI_FULL:-}" ]; then
        [ "$CI_PLAN_FAKE_CI_FULL" = success ]
        return
    fi
    local last
    last=$(curl -fsS -m 30 \
        -H "Authorization: Bearer ${GH_TOKEN:?}" \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY:?}/commits/$1/check-runs?check_name=ci-full&filter=all&per_page=100" |
        jq -r '[.check_runs[]
                | select(.app.slug == "github-actions")
                | select(.conclusion == "success" or .conclusion == "failure")]
               | sort_by(.completed_at) | last | .conclusion // "none"') || return 1
    [ "$last" = success ]
}

# The commit the latest green scheduled run of `ci` on `main` tested, or nothing
# if it cannot be read. A failed run does not count, so a red nightly is run
# again the next night on the same commit.
last_scheduled_sha() {
    if [ -n "${CI_PLAN_FAKE_LAST_SCHEDULED:-}" ]; then
        [ "$CI_PLAN_FAKE_LAST_SCHEDULED" = none ] || echo "$CI_PLAN_FAKE_LAST_SCHEDULED"
        return
    fi
    curl -fsS -m 30 \
        -H "Authorization: Bearer ${GH_TOKEN:?}" \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY:?}/actions/workflows/ci.yml/runs?event=schedule&branch=main&status=success&per_page=1" |
        jq -r '.workflow_runs[0].head_sha // empty'
}

tier=
reason=
check_bounds=auto
matrix='[]'
full_scope=false

case "${EVENT_NAME:?}" in
    pull_request)
        # The checkout is GitHub's test merge. Its first parent is the base.
        if only_inert "$head^1" "$head"; then
            tier=none
            reason="The pull request changes only paths no test reads."
        elif [ "${PR_DRAFT:-false}" = true ]; then
            tier=quick
            reason="A draft pull request. Mark it ready for review to run every group."
        else
            tier=full
            reason="A pull request ready for review."
        fi
        ;;
    push)
        if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
            tier=all
            reason="A tag."
        elif [ "$(git rev-list --parents -n 1 "$head" | wc -w)" -eq 3 ]; then
            # A merge commit. If its first parent is an ancestor of the second,
            # the merge result is the pull request head's tree. GitHub's test
            # merge of that head was the same tree, so a green `ci-full` on
            # the head tested exactly this code.
            if only_inert "$head^1" "$head"; then
                tier=cache
                reason="The merge changes only paths no test reads."
            elif git merge-base --is-ancestor "$head^1" "$head^2" &&
                [ "$(git rev-parse "$head^{tree}")" = "$(git rev-parse "$head^2^{tree}")" ] &&
                ci_full_green "$(git rev-parse "$head^2")"; then
                tier=cache
                reason="ci-full passed on the pull request head $(git rev-parse --short "$head^2"), whose tree this merge is."
            else
                tier=full
                reason="The merged tree differs from what ci-full tested on the pull request, or it did not pass there."
            fi
        elif [ -n "${PUSH_BEFORE:-}" ] && git cat-file -e "${PUSH_BEFORE}^{commit}" 2>/dev/null &&
            only_inert "$PUSH_BEFORE" "$head"; then
            tier=cache
            reason="The push changes only paths no test reads."
        else
            tier=full
            reason="A push to main that is not a merge of a tested pull request."
        fi
        ;;
    schedule)
        if [ "${SCHEDULE:-}" = "$WEEKLY_CRON" ]; then
            tier=all
            reason="The weekly run of every group on both versions."
        # The commit, not its date: a commit made days ago can reach `main`
        # today. When the history cannot be read, the tests run.
        elif last=$(last_scheduled_sha) && [ -n "$last" ] &&
            [ "$last" = "$(git rev-parse "$head")" ]; then
            tier=none
            reason="The last green scheduled run tested this commit of main, $(git rev-parse --short "$head")."
        else
            tier=nightly
            reason="The nightly run of the fork's groups on Julia 1.10."
        fi
        ;;
    workflow_dispatch)
        tier=manual
        check_bounds=${DISPATCH_CHECK_BOUNDS:-auto}
        case "$check_bounds" in yes | auto) ;; *)
            echo "check_bounds must be yes or auto, not $check_bounds" >&2
            exit 1
            ;;
        esac
        requested=${DISPATCH_GROUPS:-all}
        if [ "$requested" = all ]; then
            selected=$GROUPS_JSON
        else
            selected=$(jq -c -R 'split(",") | map(gsub("^ +| +$"; ""))' <<<"$requested")
            # An empty entry or a repeated group is a typo, and would run a
            # matrix other than the one asked for.
            if jq -e 'any(.[]; length == 0) or length != (unique | length)' <<<"$selected" >/dev/null; then
                echo "groups must be names separated by single commas, each once: '$requested'" >&2
                exit 1
            fi
            unknown=$(jq -r --argjson known "$GROUPS_JSON" '[.[] | select(. as $g | $known | index($g) | not)] | join(", ")' <<<"$selected")
            if [ -n "$unknown" ]; then
                echo "Unknown test groups: $unknown. Known groups: $(jq -r 'join(", ")' <<<"$GROUPS_JSON")" >&2
                exit 1
            fi
        fi
        if ! jq -e 'length > 0' <<<"$selected" >/dev/null; then
            echo "No test group selected: '$requested'" >&2
            exit 1
        fi
        versions=${DISPATCH_VERSIONS:-both}
        case "$versions" in
            both) matrix=$(jq -c -s 'add' <(on_version 1.11 <<<"$selected") <(on_version 1.10 <<<"$selected")) ;;
            1.11 | 1.10) matrix=$(on_version "$versions" <<<"$selected") ;;
            *)
                echo "versions must be both, 1.11 or 1.10, not $versions" >&2
                exit 1
                ;;
        esac
        if [ "$requested" = all ] && [ "$versions" != 1.10 ]; then
            full_scope=true
        fi
        reason="A manual run: groups $requested, Julia $versions, check_bounds $check_bounds."
        ;;
    *)
        echo "ci_plan.sh does not know the event $EVENT_NAME" >&2
        exit 1
        ;;
esac

case "$tier" in
    quick) matrix=$(jq -c --argjson g "$GROUPS_JSON" '[.[] | select(. as $q | $g | index($q))]' <<<"$QUICK" | on_version 1.11) ;;
    full) matrix=$(on_version 1.11 <<<"$GROUPS_JSON") ;;
    nightly) matrix=$(on_version 1.10 <<<"$fork_groups") ;;
    all)
        matrix=$(jq -c -s 'add' <(on_version 1.11 <<<"$GROUPS_JSON") <(on_version 1.10 <<<"$fork_groups"))
        check_bounds=yes
        ;;
esac
case "$tier" in full | all) full_scope=true ;; esac

# ALLOW_FAIL quarantines jobs by `<version>/<group>`, separated by spaces.
allow_fail=$(jq -c -R 'split(" ") | map(select(length > 0))' <<<"${ALLOW_FAIL:-}")

note "Tier **$tier**: $reason Test jobs: $(jq length <<<"$matrix")."
echo "tier=$tier"
echo "matrix=$matrix"
echo "full_scope=$full_scope"
echo "check_bounds=$check_bounds"
echo "allow_fail=$allow_fail"
