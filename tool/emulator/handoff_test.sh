#!/usr/bin/env bash
# Checks on an Android emulator (or device) that changes waiting to save are
# handed off between the app and its WorkManager background task -- each
# with its own outboxes, in its own isolate, sharing what's kept -- with
# every one sent once: none lost, none twice -- the task, cancelled
# mid-request, finishing the change it's sending first. Runs
# integration_test/outbox_handoff_test.dart, a debug build of the app with
# a test of its own as its entry point. Building it first, before the
# emulator starts, leaves flutter test little to build:
#
#     flutter build apk --debug -t integration_test/outbox_handoff_test.dart
#     tool/emulator/handoff_test.sh
#
# Writes the device log, and flutter test's output, to $OUT
# (build/emulator). Used by .github/workflows/emulator.yml.
set -u

OUT=${OUT:-build/emulator}
mkdir -p "$OUT"

adb() { command adb wait-for-device && command adb "$@"; }
# As calendar_widget_test.sh: runs $2... until it succeeds, for up to $1
# seconds.
poll() {
  local end=$((SECONDS + $1))
  shift
  until "$@"; do
    [ $SECONDS -lt "$end" ] || return 1
    sleep 0.5
  done
}

# As keyboard_test.sh: booted, the user unlocked, and the package manager
# up, for the install.
prop() { adb shell getprop "$1" | tr -d '\r'; }
booted() {
  [ "$(prop sys.boot_completed)" = 1 ] &&
    [ "$(prop sys.user.0.ce_available)" = true ]
}
pm_up() { adb shell pm path android 2>/dev/null | grep -q '^package:'; }
ready() {
  poll 120 booted
  echo "Booted: $(prop sys.boot_completed), user unlocked: $(prop sys.user.0.ce_available)"
  poll 60 pm_up || echo "The package manager isn't answering"
}
ready

# The device log, picked up again should adb drop the device.
adb logcat -c
while :; do adb logcat -v time; sleep 1; done > "$OUT/handoff_logcat.txt" 2>&1 &
logcat=$!

device=$(command adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')

# Whether the test, not just its loading, got under way in the output $1.
started() { grep -E ' \+[0-9]+: ' "$1" | grep -vq ': loading '; }
# Runs the tests, their output to $1 as well. They take about 4 minutes once
# built. It has stalled just after installing the app, never starting --
# the app up, its VM service listening, but flutter test never reaching
# it, and adb's logcat cut off -- and failed to start the Dart
# Development Service there too: give up after 2 minutes without the test
# started (125), or at 15 minutes all told (124).
run_test() {
  local log=$1 pid installed=
  timeout 15m flutter test integration_test/outbox_handoff_test.dart \
    -d "$device" --reporter expanded > >(tee "$log") 2>&1 &
  pid=$!
  while kill -0 $pid 2>/dev/null; do
    started "$log" && break
    [ -z "$installed" ] && grep -q '^Installing ' "$log" && installed=$SECONDS
    if [ -n "$installed" ] && [ $((SECONDS - installed)) -ge 120 ]; then
      kill $pid
      wait $pid
      return 125
    fi
    sleep 1
  done
  wait $pid
}

# A second go when the app was installed but the test never started:
# that's the emulator and adb, not the handoff. Once it's started, its
# result stands; nor is a failed build tried again.
for attempt in 1 2; do
  out="$OUT/handoff_test_$attempt.txt"
  run_test "$out"
  status=$?
  [ $status = 0 ] && break
  if started "$out"; then
    [ $status = 124 ] &&
      echo "::error::The handoff test didn't finish within 15 minutes; it stalled"
    break
  fi
  grep -q '^Installing ' "$out" || break
  echo "::warning::The handoff test didn't start (attempt $attempt of 2, exit $status)"
  command adb devices -l
  command adb reconnect offline >/dev/null 2>&1
  ready
done
[ $status = 125 ] &&
  echo "::error::The handoff test didn't start, twice; see $out"

kill $logcat
pkill -f 'adb logcat -v time'
# What the outboxes and WorkManager said, to read beside the result.
grep -E 'Handoff:|WM-|flutter' "$OUT/handoff_logcat.txt" | tail -200 || true
exit $status
