#!/usr/bin/env bash
# Checks on an Android emulator (or device) that changes waiting to save are
# handed off between the app and its WorkManager background task -- each
# with its own outboxes, in its own isolate, sharing what's kept -- with
# every one sent once: none lost, none twice. Runs
# integration_test/outbox_handoff_test.dart, a debug build of the app with
# a test of its own as its entry point.
#
#     tool/emulator/handoff_test.sh
#
# Writes the device log to $OUT (build/emulator). Used by
# .github/workflows/emulator.yml.
set -u

OUT=${OUT:-build/emulator}
mkdir -p "$OUT"

adb() { command adb wait-for-device && command adb "$@"; }

# As keyboard_test.sh: booted, the user unlocked, things settled.
prop() { adb shell getprop "$1" | tr -d '\r'; }
for _ in $(seq 1 120); do
  [ "$(prop sys.boot_completed)" = 1 ] &&
    [ "$(prop sys.user.0.ce_available)" = true ] && break
  sleep 1
done
echo "Booted: $(prop sys.boot_completed), user unlocked: $(prop sys.user.0.ce_available)"
sleep 5

adb logcat -c
adb logcat -v time > "$OUT/handoff_logcat.txt" &
logcat=$!

device=$(command adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
flutter test integration_test/outbox_handoff_test.dart -d "$device" --reporter expanded
status=$?

kill $logcat
# What the outboxes and WorkManager said, to read beside the result.
grep -E 'Handoff:|WM-|flutter' "$OUT/handoff_logcat.txt" | tail -200 || true
exit $status
