#!/usr/bin/env bash
# Decides whether a pull request's CHECK (a required job, e.g. "visual")
# has anything new to check, and writes run=true or run=false to
# $GITHUB_OUTPUT. A skipped job counts as passed for a required check.
#
#     tool/ci/needs_run.sh CHECK [PATHSPEC...]
#
# PATHSPECs (git pathspecs, e.g. ':!web') say which files CHECK depends on;
# without any, every file does. A change to pubspec.yaml's version line
# alone doesn't count, so bumping the version doesn't rerun the check.
#
# The check needs to run if the pull request changes a file it depends
# on, unless the previous push to the pull request passed it and nothing
# it depends on has changed since. If that push's check is still running,
# this waits for it.
#
# Reads GitHub's pull_request event: BASE_SHA, HEAD_SHA, BEFORE_SHA (the
# previous push, empty if none), REPO and GH_TOKEN. Needs the whole
# history (fetch-depth: 0).
set -eu

check=$1
shift
specs=("$@")
[ ${#specs[@]} -gt 0 ] || specs=(.)

decide() {
  echo "run=$1" >> "$GITHUB_OUTPUT"
  echo "$check: $2" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
}

# Prints the files between commits $1 and $2 that CHECK depends on.
changed() {
  git diff --name-only "$1" "$2" -- "${specs[@]}" | while read -r file; do
    if [ "$file" = pubspec.yaml ] &&
      cmp -s <(git show "$1:pubspec.yaml" | grep -v '^version:') \
        <(git show "$2:pubspec.yaml" | grep -v '^version:'); then
      continue
    fi
    echo "$file"
  done
}

since_base=$(changed "$(git merge-base "$BASE_SHA" "$HEAD_SHA")" "$HEAD_SHA")
[ -n "$since_base" ] || decide false "the pull request changes nothing it checks."

if [ -z "${BEFORE_SHA:-}" ] ||
  ! git merge-base --is-ancestor "$BEFORE_SHA" "$HEAD_SHA" 2>/dev/null; then
  decide true "checking the pull request (no earlier push to build on)."
fi

since_before=$(changed "$BEFORE_SHA" "$HEAD_SHA")
[ -z "$since_before" ] ||
  decide true "changed since the last push: $(echo $since_before | head -c 300)"

# Nothing it checks changed since the last push; did that push pass?
for _ in $(seq 1 60); do
  # Every run of CHECK on that commit, e.g. "completed/success".
  results=$(gh api "repos/$REPO/commits/$BEFORE_SHA/check-runs?check_name=$check&filter=all" \
    --jq '.check_runs[] | "check: \(.status)/\(.conclusion)"' 2>/dev/null |
    sed -n 's/^check: //p')
  if grep -qE '/(success|skipped)$' <<< "$results"; then
    decide false "unchanged since ${BEFORE_SHA:0:7}, which passed it."
  fi
  # Stop waiting once they've all finished (or if it never ran there).
  [ -n "$results" ] && grep -qv '^completed/' <<< "$results" || break
  echo "Waiting for $check on ${BEFORE_SHA:0:7} to finish..."
  sleep 30
done
decide true "the last push (${BEFORE_SHA:0:7}) didn't pass it."
