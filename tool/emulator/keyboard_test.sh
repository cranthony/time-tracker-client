#!/usr/bin/env bash
# Checks on an Android emulator (or device) that the home screen "+" opens
# the New note dialog with the keyboard up, and the goal button the New
# goal sheet. Sends the intent each widget sends, from these states, and
# asks Android whether the keyboard is shown:
#
#   foreground  the app is in front (a check that detection works)
#   warm        the app is in the background
#   warm_events the app is in the background, on the Events page
#   cold        the app isn't running
#
# The goal button's cases are the same, named goal_<state>.
#
#     tool/emulator/keyboard_test.sh build/app/outputs/flutter-apk/app-release.apk
#
# Writes the device log and a screenshot per case to $OUT (build/emulator).
# Used by .github/workflows/emulator.yml.
set -u

APK=$1
PKG=com.cranthony.timetracker
OUT=${OUT:-build/emulator}
mkdir -p "$OUT"

# Every adb call waits out the device dropping off for a moment, as it does
# when Android restarts adbd, rather than failing whatever case is running.
adb() { command adb wait-for-device && command adb "$@"; }

# The emulator's runner starts this once Android says it's booted, which
# can be well before the user is unlocked -- and unlocking restarts adbd.
# Wait for both, then for things to settle.
prop() { adb shell getprop "$1" | tr -d '\r'; }
for _ in $(seq 1 120); do
  [ "$(prop sys.boot_completed)" = 1 ] &&
    [ "$(prop sys.user.0.ce_available)" = true ] && break
  sleep 1
done
echo "Booted: $(prop sys.boot_completed), user unlocked: $(prop sys.user.0.ce_available)"
sleep 5

adb install -r "$APK" >/dev/null || exit 1
# A keyboard even if the emulator reports a hardware one.
adb shell settings put secure show_ime_with_hard_keyboard 1
adb logcat -c
adb logcat -v time > "$OUT/logcat.txt" &
logcat=$!

launch() { adb shell am start -W -n "$PKG/.MainActivity" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER >/dev/null; }
# As AddNoteWidget's PendingIntent: the ADD_NOTE action, FLAG_ACTIVITY_NEW_TASK.
add_note() { adb shell am start -n "$PKG/.MainActivity" -a "$PKG.ADD_NOTE" -f 0x10000000 >/dev/null; }
# As AddGoalWidget's: the ADD_GOAL action, likewise.
add_goal() { adb shell am start -n "$PKG/.MainActivity" -a "$PKG.ADD_GOAL" -f 0x10000000 >/dev/null; }
home() { adb shell input keyevent KEYCODE_HOME; }
keyboard_shown() { adb shell dumpsys input_method | grep -q 'mInputShown=true'; }

# The on-screen views (Flutter's semantics included), one per line.
ui_nodes() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null &&
    adb shell cat /sdcard/ui.xml | tr '>' '\n' | grep '<node'
}
# Taps the middle of the first view whose text or description starts with $1.
tap_view() {
  local b
  b=$(ui_nodes | grep -E "(text|content-desc)=\"$1" | head -1 |
    sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
  [ -n "$b" ] || { echo "No view \"$1\" on screen"; return 1; }
  set -- $b
  adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
}

failed=()
# run_case NAME TIMEOUT [add_note|add_goal]
run_case() {
  local name=$1 timeout=$2 send=${3:-add_note}
  echo "::group::$name"
  local mark; mark=$(wc -l < "$OUT/logcat.txt")
  $send
  local shown=no
  for _ in $(seq 1 $((timeout * 2))); do
    sleep 0.5
    if keyboard_shown; then shown=yes; break; fi
  done
  # Late keyboards are worth knowing about, though they still fail.
  if [ $shown = no ]; then
    sleep 3
    keyboard_shown && echo "Keyboard showed up late (after ${timeout}s + 3s)"
  fi
  adb exec-out screencap -p > "$OUT/$name.png"
  echo "--- input_method:"
  adb shell dumpsys input_method | grep -E 'mInputShown|mCurFocusedWindow|mCurFocusedWindowSoftInputMode|mShowRequested|mServedView|mWindowVisible|mIsInputViewShown' | sed 's/^ *//' | sort -u
  echo "--- log:"
  tail -n +"$mark" "$OUT/logcat.txt" |
    grep -E 'TimeTracker|flutter|ImeTracker|InputMethodManager|InputMethodService|IMMS|ActivityTaskManager: (START|Displayed)' | head -80
  echo "::endgroup::"
  if [ $shown = yes ]; then
    echo "PASS $name: keyboard shown"
  else
    echo "::error::FAIL $name: no keyboard within ${timeout}s"
    failed+=("$name")
  fi
  # Close the dialog or sheet (and the keyboard first, if it's up) and leave.
  adb shell input keyevent KEYCODE_BACK; sleep 0.5
  keyboard_shown && { adb shell input keyevent KEYCODE_BACK; sleep 0.5; }
  adb shell input keyevent KEYCODE_BACK; sleep 0.5
  home; sleep 1
}

# The first launch also compiles and warms things up; don't time that.
launch; sleep 5

# Each state, for the widget whose intent $2 sends, its cases named $1...
run_cases() {
  local prefix=$1 send=$2
  launch; sleep 3
  run_case "${prefix}foreground" 5 "$send"

  launch; sleep 3; home; sleep 2
  run_case "${prefix}warm" 5 "$send"

  # The "+" has to bring Notes back from another page; the goal sheet
  # opens over it.
  launch; sleep 3
  if tap_view Events && sleep 2 && ui_nodes | grep -q 'Previous day'; then
    home; sleep 2
    run_case "${prefix}warm_events" 5 "$send"
  else
    adb exec-out screencap -p > "$OUT/${prefix}warm_events.png"
    echo "::error::FAIL ${prefix}warm_events: couldn't open the Events page"
    failed+=("${prefix}warm_events")
    home; sleep 1
  fi

  adb shell am force-stop "$PKG"; home; sleep 2
  run_case "${prefix}cold" 10 "$send"
}

run_cases "" add_note
run_cases goal_ add_goal

kill $logcat
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All cases passed"
