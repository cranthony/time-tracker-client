#!/usr/bin/env bash
# Checks on an Android emulator (or device) that the home screen calendar
# (CalendarWidget.kt) shows the app's events, and that its taps open the
# app where they should. The app has to be built with sample data, for
# events to show, and with CALENDAR_PIN, for its menu to offer to add the
# widget -- which there's no adb command for:
#
#   flutter build apk --release --dart-define=SAMPLE_DATA=true \
#     --dart-define=CALENDAR_PIN=true
#   tool/emulator/calendar_widget_test.sh build/app/outputs/flutter-apk/app-release.apk
#
# The cases, in order:
#
#   shown      added from the app's menu, it shows the header, today, and
#              events from the sample data, and today's weather in its
#              header: the sample forecast's chance of rain
#   event_cold an event tapped, the app's process gone: Events, showing it
#   day_warm   a day's header tapped, the app in the background: Events
#   add_note   its "+" tapped: the New note dialog
#
# Writes the device log, the widget's views and a screenshot per case to
# $OUT (build/emulator). Used by .github/workflows/emulator.yml.
set -u

APK=$1
PKG=com.cranthony.timetracker
OUT=${OUT:-build/emulator}
mkdir -p "$OUT"

# As keyboard_test.sh: wait out adbd restarting, then for the boot.
adb() { command adb wait-for-device && command adb "$@"; }
prop() { adb shell getprop "$1" | tr -d '\r'; }
for _ in $(seq 1 120); do
  [ "$(prop sys.boot_completed)" = 1 ] &&
    [ "$(prop sys.user.0.ce_available)" = true ] && break
  sleep 1
done
echo "Booted: $(prop sys.boot_completed), user unlocked: $(prop sys.user.0.ce_available)"
sleep 5
# Root, for the cold case's kill -9. The emulator's google_apis images
# allow it; adb() above waits out adbd restarting.
adb root >/dev/null
sleep 3
adb shell id | grep -q 'uid=0' || echo "adb root didn't take; kill -9 may be refused"

adb install -r "$APK" >/dev/null || exit 1
adb logcat -c
adb logcat -v time > "$OUT/calendar_logcat.txt" &
logcat=$!

launch() { adb shell am start -W -n "$PKG/.MainActivity" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER >/dev/null; }
home() { adb shell input keyevent KEYCODE_HOME; }

# The on-screen views (Flutter's semantics, and the launcher's widget,
# included), one per line.
ui_nodes() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null &&
    adb shell cat /sdcard/ui.xml | tr '>' '\n' | grep '<node'
}
# Whether a view's text or description is $1 exactly.
on_screen() { ui_nodes | grep -qE "(text|content-desc)=\"$1\""; }
# Taps the middle of the first view, of those $2 picks (all, by
# default), whose text or description matches $1 (an extended regex).
tap_view() {
  local b
  b=$(ui_nodes | grep -E "${2:-.}" | grep -E "(text|content-desc)=\"$1\"" | head -1 |
    sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
  [ -n "$b" ] || { echo "No view \"$1\" on screen"; return 1; }
  set -- $b
  adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
}
# Waits up to $2 seconds for a view $1 (exactly) to show.
wait_for() {
  for _ in $(seq 1 $(($2 * 2))); do
    on_screen "$1" && return 0
    sleep 0.5
  done
  return 1
}

# The sample data's events (lib/demo/sample_data.dart) that come every
# day but today, so some are always in the widget's next few days.
SAMPLE_EVENTS='(Get up and get ready|Work|Dinner|TV|Sleep)'

failed=()
pass() { echo "PASS $1"; }
fail() {
  adb exec-out screencap -p > "$OUT/calendar_$1_fail.png"
  ui_nodes > "$OUT/calendar_$1_fail.txt" 2>/dev/null
  echo "::error::FAIL $1: $2"
  failed+=("$1")
}

# Opens the app, and adds the widget from its menu, accepting Android's
# prompt; the launcher puts it on the home screen.
launch
sleep 8
if ! { tap_view 'Show menu' && sleep 1 &&
  tap_view 'Add calendar to home screen' && sleep 2; }; then
  fail shown "couldn't ask to add the widget from the menu"
else
  # The launcher's prompt: its button, not its title, which may read the
  # same.
  adb exec-out screencap -p > "$OUT/calendar_prompt.png"
  tap_view '(Add|ADD|Add to home screen|ADD TO HOME SCREEN)' 'clickable="true"' ||
    echo "No prompt to accept; added already?"
  sleep 2
  home
  sleep 3
  # Today's header, before the list's scrolled past it: its weather's
  # chance of rain, from the sample forecast.
  ui_nodes > "$OUT/calendar_weather.txt"
  adb exec-out screencap -p > "$OUT/calendar_weather.png"
  grep -qE 'text="[^"]*[0-9]+%"' "$OUT/calendar_weather.txt" && weather=yes || weather=no
  # The list may start with today's events, or with nothing planned:
  # scroll it until an event shows, a dozen times at most -- after 7:45
  # AM, today's other events (Breakfast to Get ready for bed) fill more
  # than four swipes of the widget's two rows. Within the widget's list:
  # a swipe up that starts below the widget, on the home screen, opens
  # the launcher's app drawer instead.
  for _ in $(seq 1 12); do
    ui_nodes | grep -qE "text=\"$SAMPLE_EVENTS\"" && break
    b=$(ui_nodes | grep "class=\"android.widget.ListView\" package=\"$PKG\"" | head -1 |
      sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
    [ -n "$b" ] || break
    set -- $b
    x=$((($1 + $3) / 2))
    adb shell input swipe $x $(($4 - 10)) $x $(($2 + 10)) 300
    sleep 1
  done
  ui_nodes > "$OUT/calendar_shown.txt"
  adb exec-out screencap -p > "$OUT/calendar_shown.png"
  missing=()
  on_screen Calendar || missing+=(Calendar)
  on_screen 'Add note' || missing+=('"+"')
  ui_nodes | grep -qE "text=\"$SAMPLE_EVENTS\"" || missing+=(events)
  [ "$weather" = yes ] || missing+=(weather)
  if [ ${#missing[@]} -eq 0 ]; then
    pass shown
  else
    fail shown "the widget didn't show: ${missing[*]}"
  fi
fi

# An event, with the app's process gone, as Android ends it in the
# background: the tap that launched it is the one the Dart side collects
# as it starts. Not force-stopped: Android hides a stopped app's widgets
# until it's opened again.
event=$(ui_nodes | grep -oE "text=\"$SAMPLE_EVENTS\"" | head -1 | sed 's/text="\(.*\)"/\1/')
# Whether it's under the widget's "Today": the sample's events are every
# day but today, but a "Get up and get ready" today, from another series,
# shows first while it's on (7:00 to 7:45 AM) -- and opens today.
today=$(ui_nodes | grep -oE 'text="[^"]*"' | sed 's/text="\(.*\)"/\1/' |
  awk -v event="$event" '
    $0 == "Today" { under = 1; next }
    $0 == "Tomorrow" { under = 0; next }
    $0 == event { print (under ? "yes" : "no"); exit }')
# Not by am kill either: it won't end a process running a job, as Glance's
# session (a WorkManager job) is for a minute after the widget updates. So
# by kill -9, as root, as Android ends a process when it's short of memory.
for _ in $(seq 1 5); do
  pid=$(adb shell pidof "$PKG" | tr -d '\r')
  [ -z "$pid" ] && break
  adb shell kill -9 $pid
  sleep 1
done
if [ -z "$event" ]; then
  fail event_cold "no event in the widget to tap"
elif adb shell pidof "$PKG" >/dev/null; then
  fail event_cold "the app was still running after kill -9"
# On the timeline, it's labelled with its times too: "Dinner, 7:00 PM to
# 7:45 PM". On its own day: today only for one under "Today".
elif tap_view "$event" && wait_for 'Previous day' 15 &&
  ui_nodes | grep -qE "(text|content-desc)=\"$event[,\"]" &&
  if [ "$today" = yes ]; then on_screen Today; else ! on_screen Today; fi; then
  adb exec-out screencap -p > "$OUT/calendar_event_cold.png"
  pass "event_cold ($event)"
else
  fail event_cold "tapping \"$event\" didn't open Events showing it"
fi

# A day, with the app in the background, on Notes.
launch
sleep 3
tap_view Notes >/dev/null 2>&1
sleep 1
home
sleep 2
day=$(ui_nodes | grep -oE 'text="(Tomorrow|Today)"' | head -1 | sed 's/text="\(.*\)"/\1/')
if [ -n "$day" ] && tap_view "$day" && wait_for 'Previous day' 10; then
  adb exec-out screencap -p > "$OUT/calendar_day_warm.png"
  pass "day_warm ($day)"
else
  fail day_warm "tapping a day's header didn't open Events"
fi

# Its "+".
home
sleep 2
if tap_view 'Add note' && wait_for 'New note' 10; then
  adb exec-out screencap -p > "$OUT/calendar_add_note.png"
  pass add_note
else
  fail add_note "the \"+\" didn't open the New note dialog"
fi

kill $logcat
grep -E 'TimeTracker|flutter|HomeWidget|Glance|AppWidget' "$OUT/calendar_logcat.txt" | tail -100 || true
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All cases passed"
