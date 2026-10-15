#!/usr/bin/env bash
# Runs a command that may download Android SDK packages -- sdkmanager, or
# a Gradle build that installs the NDK -- and runs it again, up to three
# times in all, when one of those downloads came back broken ("Error on
# ZipFile unknown archive", an HTTP 502): Google's servers do that now
# and then. Any other failure is the command's own, and isn't retried.
#
#     tool/emulator/sdk_retry.sh flutter build apk --release
#
# Used by .github/workflows/emulator.yml.
set -u

log=$(mktemp)
trap 'rm -f "$log"' EXIT
for attempt in 1 2 3; do
  "$@" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  [ "$status" = 0 ] && exit 0
  grep -q 'An error occurred while preparing SDK package' "$log" || exit "$status"
  echo "::warning::An Android SDK download failed (attempt $attempt of 3)"
  sleep 10
done
exit "$status"
