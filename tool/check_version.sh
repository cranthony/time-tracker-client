#!/usr/bin/env bash
# Fails unless a change to the app also bumps its version in pubspec.yaml
# and adds that version's section to CHANGELOG.md. Compares against BASE
# (a commit, e.g. the PR's base branch); see "Versions" in README.md.
#
#     tool/check_version.sh origin/main
set -eu

base=$1
app_paths=(lib android windows web pubspec.yaml)

if git diff --quiet "$base" -- "${app_paths[@]}"; then
  echo "The app is unchanged; no version bump needed."
  exit 0
fi

version_in() { sed -n 's/^version: *\([^+ ]*\).*/\1/p'; }
old=$(git show "$base:pubspec.yaml" | version_in)
new=$(version_in < pubspec.yaml)
echo "Version: $old -> $new"

if [ "$old" = "$new" ] ||
  [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -1)" != "$new" ]; then
  echo "::error file=pubspec.yaml::This changes the app; bump the version in pubspec.yaml past $old (see Versions in README.md)."
  exit 1
fi
if ! grep -q "^## $new\$" CHANGELOG.md; then
  echo "::error file=CHANGELOG.md::Add a \"## $new\" section to CHANGELOG.md saying what changed."
  exit 1
fi
echo "Version bumped and in the changelog."
