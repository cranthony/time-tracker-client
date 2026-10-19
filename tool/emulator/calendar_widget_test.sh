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
#              header, in order: the sample forecast's chance of rain
#              (70%), its high and low (61/50°, or 61° / 50°) and its
#              sky (cloudy) -- all of it at the widget's 3 cells; and under
#              "Today", the sample's goals due today: the two active ones
#              due soonest, in order, each with the goal icon, the second
#              with "+1" for the third, and not the done one
#   event_cold an event tapped, the app's process gone: Events, showing it
#   day_warm   a day's header tapped, the app in the background: Events
#   add_note   its "+" tapped: the New note dialog
#   title_bottom its settings opened, as the launcher does, and "Title at
#              the bottom" picked: its "Calendar" header below its days
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
# Runs $2... until it succeeds, for up to $1 seconds: the emulator's
# timings vary from run to run, so nothing's checked after a fixed wait.
poll() {
  local end=$((SECONDS + $1))
  shift
  until "$@"; do
    [ $SECONDS -lt "$end" ] || return 1
    sleep 0.5
  done
}
prop() { adb shell getprop "$1" | tr -d '\r'; }
booted() {
  [ "$(prop sys.boot_completed)" = 1 ] &&
    [ "$(prop sys.user.0.ce_available)" = true ]
}
poll 120 booted
echo "Booted: $(prop sys.boot_completed), user unlocked: $(prop sys.user.0.ce_available)"
# The package manager, for the install, up too.
pm_up() { adb shell pm path android 2>/dev/null | grep -q '^package:'; }
poll 60 pm_up || echo "The package manager isn't answering"
# Root, for the cold case's kill -9. The emulator's google_apis images
# allow it; adb() above waits out adbd restarting.
rooted() { adb shell id 2>/dev/null | grep -q 'uid=0'; }
adb root >/dev/null
poll 20 rooted || echo "adb root didn't take; kill -9 may be refused"

installed() { adb install -r "$APK" >/dev/null; }
poll 60 installed || exit 1
adb logcat -c
adb logcat -v time > "$OUT/calendar_logcat.txt" &
logcat=$!

launch() { adb shell am start -W -n "$PKG/.MainActivity" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER >/dev/null; }
home() { adb shell input keyevent KEYCODE_HOME; }
# The launcher's package, for widget_home to start it again.
LAUNCHER=$(adb shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME |
  tr -d '\r' | tail -1 | cut -d/ -f1)

# The on-screen views (Flutter's semantics, and the launcher's widget,
# included), one per line.
ui_nodes() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null &&
    adb shell cat /sdcard/ui.xml | tr '>' '\n' | grep '<node'
}
# Picks the widget's views (Glance's), not the app's or the launcher's.
WIDGET="resource-id=\"$PKG:id/glance_view_id_"
# Whether a view, of those $2 picks (all, by default), has the text or
# description $1 exactly.
on_screen() { ui_nodes | grep -E "${2:-.}" | grep -qE "(text|content-desc)=\"$1\""; }
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
# Waits up to $2 seconds for a view $1 (exactly), of those $3 picks, to
# show.
wait_for() { poll "$2" on_screen "$1" "${3:-.}"; }
# Goes to the home screen, and waits up to 20 seconds for the widget.
# Relaunched for a configuration change, as it can be in the emulator's
# first minutes, the launcher may come back without the widget, though
# it's still added and bound: started again, it reads its home screen
# afresh, the widget included.
widget_home() {
  home
  wait_for 'Add note' 20 "$WIDGET" && return 0
  echo "The widget's not on the home screen; starting the launcher ($LAUNCHER) again"
  adb shell am force-stop "$LAUNCHER"
  home
  wait_for 'Add note' 30 "$WIDGET"
}
# The bounds of the widget's list, as "left top right bottom".
list_bounds() {
  ui_nodes | grep "class=\"android.widget.ListView\" package=\"$PKG\"" | head -1 |
    sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'
}
# The first day's header, "Today" or "Tomorrow", the widget shows.
day_header() {
  ui_nodes | grep "$WIDGET" | grep -oE 'text="(Today|Tomorrow)"' | head -1 |
    sed 's/text="\(.*\)"/\1/'
}
# Waits up to 20 seconds for the widget, and scrolls its list back up
# until a day's header shows, a dozen swipes at most: the shown case
# scrolls it down to the events, past "Today" when today's come first.
to_day_header() {
  wait_for 'Add note' 20 "$WIDGET" || return 1
  local b
  for _ in $(seq 1 12); do
    [ -n "$(day_header)" ] && return 0
    b=$(list_bounds)
    [ -n "$b" ] || return 1
    set -- $b
    adb shell input swipe $((($1 + $3) / 2)) $(($2 + 10)) $((($1 + $3) / 2)) $(($4 - 10)) 300
    sleep 1
  done
  [ -n "$(day_header)" ]
}
# The three texts after the widget's "Today", in the views dumped to $1,
# joined by " | " -- its header's weather -- with the raindrop the dump
# writes as an entity written as itself.
today_header() {
  grep -oE 'text="[^"]*"' "$1" | sed 's/text="\(.*\)"/\1/' |
    sed 's/&#128167;/💧/g' | grep -v '^$' |
    awk '$0 == "Today" { n = 3; next } n > 0 { out = out (out ? " | " : "") $0; n-- } END { print out }'
}
# Whether today's header's weather, $1, is the sample forecast's, in
# order: the chance of rain, the high and low (compact or not), the sky.
weather_reads() {
  case "$1" in
    "💧70% | 61/50° | ☁"* | "💧70% | 61° / 50° | ☁"*) return 0 ;;
    *) return 1 ;;
  esac
}

# The sample data's events (lib/demo/sample_data.dart) that come every
# day but today, so some are always in the widget's next few days.
SAMPLE_EVENTS='(Get up and get ready|Work|Dinner|TV|Sleep)'
# The event for the cold case to tap: the first of them on the last
# screen in calendar_scrolled.txt, as "yes <event>" if it's under the
# widget's "Today", or "no <event>"; nothing if none's there. The next
# day's header is "Tomorrow", or, made room for the weather, its weekday
# ("Thu"); the one over an event may be on an earlier screen, so the
# screens are read in order -- the widget's views only, not the
# launcher's date ("Thu, Oct 15"). Under "Today", only "Sleep": still on
# from last night, it opens the day it started. A "Get up and get ready"
# today, from another series (the sample's events are every day but
# today), opens today -- whose weather, all-day events and Claude's recap
# leave the timeline no room to show it, on the emulator's small screen.
pick_event() {
  grep -E "^--\$|$WIDGET" "$OUT/calendar_scrolled.txt" 2>/dev/null |
    sed -n -e 's/^--$/--/p' -e 's/.*[[:space:]]text="\([^"]*\)".*/\1/p' |
    awk -v events="^$SAMPLE_EVENTS\$" '
      $0 == "--" { pick = ""; next }
      $0 == "Today" { under = 1; next }
      $0 ~ /^(Tomorrow|Mon|Tue|Wed|Thu|Fri|Sat|Sun)/ { under = 0; next }
      pick == "" && $0 ~ events && (!under || $0 == "Sleep") {
        pick = $0; today = under
      }
      END { if (pick != "") print (today ? "yes" : "no"), pick }'
}

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
PROMPT_ADD='(Add|ADD|Add to home screen|ADD TO HOME SCREEN)'
launch
if ! { wait_for 'Show menu' 30 && tap_view 'Show menu' &&
  wait_for 'Add calendar to home screen' 10 &&
  tap_view 'Add calendar to home screen'; }; then
  fail shown "couldn't ask to add the widget from the menu"
else
  # The launcher's prompt: its button, not its title, which may read the
  # same.
  if wait_for "$PROMPT_ADD" 10 'clickable="true"'; then
    adb exec-out screencap -p > "$OUT/calendar_prompt.png"
    tap_view "$PROMPT_ADD" 'clickable="true"'
    prompt_gone() { ! on_screen "$PROMPT_ADD" 'clickable="true"'; }
    poll 10 prompt_gone
  else
    adb exec-out screencap -p > "$OUT/calendar_prompt.png"
    echo "No prompt to accept; added already?"
  fi
  home
  # Today's header, before the list's scrolled past it: its weather, from
  # the sample forecast (lib/demo/weather_sample.dart), in °F -- the
  # header's next three texts after "Today". Once the launcher's drawn
  # the widget, and the app's given it the forecast.
  weather_shown() {
    ui_nodes > "$OUT/calendar_weather.txt"
    today_weather=$(today_header "$OUT/calendar_weather.txt")
    weather_reads "$today_weather"
  }
  if poll 20 weather_shown; then weather=yes; else weather=no; fi
  adb exec-out screencap -p > "$OUT/calendar_weather.png"
  # Under "Today", the goals due today, once the app's loaded them, from
  # the sample data's (lib/demo/sample_data.dart): "Sign up for the race"
  # (12:30) and "Show the goals due above the timeline" (5 PM), each after
  # its icon ("Goal"), then "+1" for "Draw the goal icon" (by the day's
  # end); not "Sketch the Goals pane", which is done. The widget's texts,
  # in order, kept to those. Should the list have moved past "Today" as
  # the widget's drawn again, it's scrolled back up to it.
  GOALS_EXPECTED='Goal|Sign up for the race|Goal|Show the goals due above the timeline|+1'
  goals_shown() {
    ui_nodes > "$OUT/calendar_goals.txt" || return 1
    shown_goals=$(grep "$WIDGET" "$OUT/calendar_goals.txt" |
      grep -oE '(text|content-desc)="[^"]*"' | sed 's/^[a-z-]*="\(.*\)"$/\1/' |
      grep -xE 'Goal|Sign up for the race|Show the goals due above the timeline|Draw the goal icon|Sketch the Goals pane|\+[0-9]+' |
      paste -sd '|')
    [ "$shown_goals" = "$GOALS_EXPECTED" ] && return 0
    if ! grep "$WIDGET" "$OUT/calendar_goals.txt" | grep -q 'text="Today"'; then
      local b
      b=$(list_bounds)
      if [ -n "$b" ]; then
        set -- $b
        adb shell input swipe $((($1 + $3) / 2)) $(($2 + 10)) $((($1 + $3) / 2)) $(($4 - 10)) 300
        sleep 1
      fi
    fi
    return 1
  }
  if poll 30 goals_shown; then goals=yes; else goals=no; fi
  adb exec-out screencap -p > "$OUT/calendar_goals.png"
  # The list may start with today's events, or with nothing planned:
  # scroll it until an event to tap (pick_event, below) shows, a dozen
  # times at most -- after 7:45 AM, today's other events (Breakfast to Get
  # ready for bed) fill more than four swipes of the widget's two rows.
  # Within the widget's list: a swipe up that starts below the widget, on
  # the home screen, opens the launcher's app drawer instead. Each
  # screen's views, in order, go to calendar_scrolled.txt after a "--",
  # for the day headers scrolled past -- the weather case's first, with
  # "Today": the list can move on its own as the widget's drawn again,
  # and start already past it.
  { echo --; cat "$OUT/calendar_weather.txt"; } > "$OUT/calendar_scrolled.txt"
  for i in $(seq 0 12); do
    ui_nodes > "$OUT/calendar_shown.txt"
    { echo --; cat "$OUT/calendar_shown.txt"; } >> "$OUT/calendar_scrolled.txt"
    [ -n "$(pick_event)" ] && break
    [ "$i" -lt 12 ] || break
    b=$(list_bounds)
    [ -n "$b" ] || break
    set -- $b
    x=$((($1 + $3) / 2))
    adb shell input swipe $x $(($4 - 10)) $x $(($2 + 10)) 300
    sleep 1
  done
  adb exec-out screencap -p > "$OUT/calendar_shown.png"
  missing=()
  grep -qE '(text|content-desc)="Calendar"' "$OUT/calendar_shown.txt" ||
    missing+=(Calendar)
  grep -qE '(text|content-desc)="Add note"' "$OUT/calendar_shown.txt" ||
    missing+=('"+"')
  grep -qE "text=\"$SAMPLE_EVENTS\"" "$OUT/calendar_shown.txt" || missing+=(events)
  [ "$weather" = yes ] ||
    missing+=("today's weather (\"💧70% 61/50° ☁️\"; got \"$today_weather\")")
  [ "$goals" = yes ] ||
    missing+=("today's goals (\"$GOALS_EXPECTED\"; got \"${shown_goals:-}\")")
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
picked=$(pick_event)
event=${picked#* }
today=${picked%% *}
# Whether the widget's drawn, showing the event: not Glance's loading view
# (a ProgressBar, the app's), which it's left on if the app's ended while
# drawing it.
widget_drawn() {
  local nodes
  nodes=$(ui_nodes) || return 1
  grep "$WIDGET" <<<"$nodes" | grep -qE "text=\"$event\"" &&
    ! grep "package=\"$PKG\"" <<<"$nodes" | grep -q 'class="android.widget.ProgressBar"'
}
# Drawn, and still so 3 seconds on.
widget_settled() { widget_drawn && sleep 3 && widget_drawn; }
# Not by am kill either: it won't end a process running a job, as Glance's
# session (a WorkManager job) is for a minute after the widget updates. So
# by kill -9, as root, as Android ends a process when it's short of memory.
# Android may start it again at once, for a broadcast to the widget (an
# update, as packages change after the emulator's boot), or to restart
# WorkManager's job service: then it's let draw the widget before it's
# killed again -- killed while drawing, it leaves the widget on its
# loading view, with nothing to tap until the app draws it again. Its
# jobs are cancelled before each kill, so the job service isn't one of
# them. Done once there's been no process for 3 seconds running, for up
# to 2 minutes: the restarts come as long as packages keep changing.
end=$((SECONDS + 120))
while [ $SECONDS -lt $end ]; do
  pid=$(adb shell pidof "$PKG" | tr -d '\r')
  if [ -z "$pid" ]; then
    sleep 3
    [ -z "$(adb shell pidof "$PKG" | tr -d '\r')" ] && break
    continue
  fi
  echo "Killing the app (pid $pid)"
  poll 30 widget_settled || echo "The widget wasn't drawn again before the kill"
  adb shell cmd jobscheduler cancel "$PKG" >/dev/null
  adb shell kill -9 $(adb shell pidof "$PKG" | tr -d '\r')
  sleep 1
done
# Events showing it, once the app's started and gone to its day.
event_opened() {
  local nodes
  nodes=$(ui_nodes) || return 1
  shows() { grep -qE "(text|content-desc)=\"$1\"" <<<"$nodes"; }
  # On the timeline, it's labelled with its times too: "Dinner, 7:00 PM
  # to 7:45 PM". On its own day: for one under "Today", still on from last
  # night (Sleep, after midnight), the day it started.
  shows 'Previous day' &&
    grep -qE "(text|content-desc)=\"$event[,\"]" <<<"$nodes" &&
    if [ "$today" = yes ]; then shows Today || shows Yesterday
    else ! shows Today; fi
}
if [ -z "$event" ]; then
  fail event_cold "no event in the widget to tap"
elif adb shell pidof "$PKG" >/dev/null; then
  fail event_cold "the app was still running after kill -9"
elif ! poll 20 widget_drawn; then
  fail event_cold "the widget didn't show \"$event\" to tap (on its loading view?)"
elif tap_view "$event" "$WIDGET" && poll 20 event_opened; then
  adb exec-out screencap -p > "$OUT/calendar_event_cold.png"
  pass "event_cold ($event)"
else
  fail event_cold "tapping \"$event\" didn't open Events showing it"
fi

# A day, with the app in the background, on Notes.
launch
wait_for Notes 30 && tap_view Notes >/dev/null
sleep 1
widget_home
to_day_header
day=$(day_header)
if [ -n "$day" ] && tap_view "$day" "$WIDGET" && wait_for 'Previous day' 20; then
  adb exec-out screencap -p > "$OUT/calendar_day_warm.png"
  pass "day_warm ($day)"
else
  fail day_warm "tapping a day's header didn't open Events"
fi

# Its "+".
if widget_home && tap_view 'Add note' "$WIDGET" &&
  wait_for 'New note' 20; then
  adb exec-out screencap -p > "$OUT/calendar_add_note.png"
  pass add_note
else
  fail add_note "the \"+\" didn't open the New note dialog"
fi

# Its settings, opened as the launcher opens them, for its id: the title
# moved to the bottom, under the days. The top of a view $1 (exactly).
top_of() {
  ui_nodes | grep "$WIDGET" | grep -E "text=\"$1\"" | head -1 |
    sed -n 's/.*bounds="\[[0-9]*,\([0-9]*\)\].*/\1/p'
}
# Whether its title's at the bottom, below its first day's header, once
# it's redrawn.
title_moved() {
  after_title=$(top_of Calendar)
  after_day=$(top_of '(Today|Tomorrow)')
  [ -n "$after_title" ] && [ -n "$after_day" ] && [ "$after_title" -gt "$after_day" ]
}
# Its id, from the first widget the dump says is its receiver's.
widget_id=$(adb shell dumpsys appwidget | tr -d '\r' |
  awk '/id=[0-9]+/ { match($0, /id=[0-9]+/); id = substr($0, RSTART + 3, RLENGTH - 3) }
       /CalendarWidgetReceiver/ && id != "" { print id; exit }')
widget_home
to_day_header
before_title=$(top_of Calendar)
before_day=$(top_of '(Today|Tomorrow)')
if [ -z "$widget_id" ]; then
  fail title_bottom "couldn't find the widget's id"
elif ! adb shell am start -W -n "$PKG/.CalendarWidgetConfigureActivity" \
  --ei appWidgetId "$widget_id" >/dev/null || ! wait_for 'Title at the bottom' 20; then
  fail title_bottom "its settings didn't open"
# Done closes it onto the home screen as it was: not Home again, which,
# pressed on the home screen, goes to its first page.
elif [ -n "$before_title" ] && [ -n "$before_day" ] &&
  [ "$before_title" -lt "$before_day" ] &&
  tap_view 'Title at the bottom' && sleep 1 && tap_view Done &&
  { poll 20 title_moved || { to_day_header && title_moved; }; }; then
  adb exec-out screencap -p > "$OUT/calendar_title_bottom.png"
  pass title_bottom
else
  fail title_bottom "\"Calendar\" wasn't moved below the days (before $before_title/$before_day, after ${after_title:-?}/${after_day:-?})"
fi

kill $logcat
grep -E 'TimeTracker|flutter|HomeWidget|Glance|AppWidget' "$OUT/calendar_logcat.txt" | tail -100 || true
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All cases passed"
