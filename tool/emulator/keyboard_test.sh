#!/usr/bin/env bash
# Checks on an Android emulator (or device) that the home screen "+" opens
# the New note dialog with the keyboard up. Sends the intent the widget
# sends, from three states, and asks Android whether the keyboard is shown:
#
#   foreground  the app is in front (a check that detection works)
#   warm        the app is in the background
#   warm_events the app is in the background, on the Events page
#   cold        the app isn't running
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

adb install -r "$APK" >/dev/null || exit 1
# A keyboard even if the emulator reports a hardware one.
adb shell settings put secure show_ime_with_hard_keyboard 1
adb logcat -c
adb logcat -v time > "$OUT/logcat.txt" &
logcat=$!

launch() { adb shell am start -W -n "$PKG/.MainActivity" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER >/dev/null; }
# As AddNoteWidget's PendingIntent: the ADD_NOTE action, FLAG_ACTIVITY_NEW_TASK.
add_note() { adb shell am start -n "$PKG/.MainActivity" -a "$PKG.ADD_NOTE" -f 0x10000000 >/dev/null; }
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
run_case() {
  local name=$1 timeout=$2
  echo "::group::$name"
  local mark; mark=$(wc -l < "$OUT/logcat.txt")
  add_note
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
  # Close the dialog (and the keyboard first, if it's up) and leave.
  adb shell input keyevent KEYCODE_BACK; sleep 0.5
  keyboard_shown && { adb shell input keyevent KEYCODE_BACK; sleep 0.5; }
  adb shell input keyevent KEYCODE_BACK; sleep 0.5
  home; sleep 1
}

# The first launch also compiles and warms things up; don't time that.
launch; sleep 5

run_case foreground 5

launch; sleep 3; home; sleep 2
run_case warm 5

# The "+" has to bring Notes back from another page.
launch; sleep 3
if tap_view Events && sleep 2 && ui_nodes | grep -q 'Previous day'; then
  home; sleep 2
  run_case warm_events 5
else
  adb exec-out screencap -p > "$OUT/warm_events.png"
  echo "::error::FAIL warm_events: couldn't open the Events page"
  failed+=(warm_events)
  home; sleep 1
fi

adb shell am force-stop "$PKG"; home; sleep 2
run_case cold 10

kill $logcat
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All cases passed"
