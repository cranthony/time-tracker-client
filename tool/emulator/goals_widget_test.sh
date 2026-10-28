#!/usr/bin/env bash
# Checks on an Android emulator (or device) that the home screen goals
# widget (GoalsWidget.kt) shows the app's active goals, and that its taps
# open the app where they should. The app has to be built with sample
# data, for goals to show, and with GOALS_PIN, for its menu to offer to
# add the widget -- which there's no adb command for:
#
#   flutter build apk --release --dart-define=SAMPLE_DATA=true \
#     --dart-define=GOALS_PIN=true
#   tool/emulator/goals_widget_test.sh build/app/outputs/flutter-apk/app-release.apk
#
# The cases, in order:
#
#   shown      added from the app's menu, it shows the header, "Goals" and
#              the goal button, and the sample data's active goals, the
#              soonest due first: those due today -- "Sign up for the
#              race" (12:30), "Show the goals due above the timeline"
#              (5:00 PM), then "Draw the goal icon" (by the day's end) --
#              then "Add a Goals pane", "Ship the time tracker app" and
#              "Run a half marathon"; as many as fit its two cells, in
#              that order, each before "Today" or its date; not "Sketch
#              the Goals pane", which is done, nor the inactive ones
#   goal_cold  a goal tapped, the app's process gone: its page
#   goals_warm "Goals" tapped, the app in the background: Plan, on Goals
#   add_goal   its goal button tapped: the New goal sheet
#   title_bottom its settings opened, as the launcher does, and "Title at
#              the bottom" picked: its "Goals" header below its goals
#   text_large its settings opened again, and "Large" picked for its text
#              size: its rows twice as high, so the second goal starts
#              twice as far below the first
#
# Writes the device log, the widget's views and a screenshot per case to
# $OUT (build/emulator). Used by .github/workflows/emulator.yml.
set -u

APK=$1
PKG=com.cranthony.timetracker
OUT=${OUT:-build/emulator}
mkdir -p "$OUT"

# As calendar_widget_test.sh: wait out adbd restarting, then for the boot.
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
adb logcat -v time > "$OUT/goals_logcat.txt" &
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
  wait_for 'Add goal' 20 "$WIDGET" && return 0
  echo "The widget's not on the home screen; starting the launcher ($LAUNCHER) again"
  adb shell am force-stop "$LAUNCHER"
  home
  wait_for 'Add goal' 30 "$WIDGET"
}

# The sample data's goals (lib/demo/sample_data.dart) the widget shows,
# in order: the active ones, the soonest due first.
GOALS_EXPECTED='Sign up for the race|Show the goals due above the timeline|Draw the goal icon|Add a Goals pane|Ship the time tracker app|Run a half marathon'
# Every goal of the sample's, active or not, for picking out the widget's
# goals from its views.
GOALS_ALL='Sign up for the race|Show the goals due above the timeline|Draw the goal icon|Add a Goals pane|Ship the time tracker app|Run a half marathon|Sketch the Goals pane|Polish the settings|Finish the reading list'
# The goals the widget's views in $1 show, in order, joined by "|".
shown_goals() {
  grep "$WIDGET" "$1" | grep -oE 'text="[^"]*"' | sed 's/^text="\(.*\)"$/\1/' |
    grep -xE "$GOALS_ALL" | paste -sd '|'
}

failed=()
pass() { echo "PASS $1"; }
fail() {
  adb exec-out screencap -p > "$OUT/goals_$1_fail.png"
  ui_nodes > "$OUT/goals_$1_fail.txt" 2>/dev/null
  echo "::error::FAIL $1: $2"
  failed+=("$1")
}

# Opens the app, and adds the widget from its menu, accepting Android's
# prompt; the launcher puts it on the home screen.
PROMPT_ADD='(Add|ADD|Add to home screen|ADD TO HOME SCREEN)'
launch
if ! { wait_for 'Show menu' 30 && tap_view 'Show menu' &&
  wait_for 'Add goals to home screen' 10 &&
  tap_view 'Add goals to home screen'; }; then
  fail shown "couldn't ask to add the widget from the menu"
else
  # The launcher's prompt: its button, not its title, which may read the
  # same.
  if wait_for "$PROMPT_ADD" 10 'clickable="true"'; then
    adb exec-out screencap -p > "$OUT/goals_prompt.png"
    tap_view "$PROMPT_ADD" 'clickable="true"'
    prompt_gone() { ! on_screen "$PROMPT_ADD" 'clickable="true"'; }
    poll 10 prompt_gone
  else
    adb exec-out screencap -p > "$OUT/goals_prompt.png"
    echo "No prompt to accept; added already?"
  fi
  home
  # The goals, once the app's loaded them and the launcher's drawn the
  # widget: those shown, at least two, the first of those expected, in
  # order -- its two cells don't hold them all.
  goals_shown() {
    ui_nodes > "$OUT/goals_shown.txt" || return 1
    shown=$(shown_goals "$OUT/goals_shown.txt")
    [ -n "$shown" ] && [ "$(tr '|' '\n' <<<"$shown" | wc -l)" -ge 2 ] &&
      [ "${GOALS_EXPECTED#"$shown"}" != "$GOALS_EXPECTED" ]
  }
  if poll 30 goals_shown; then goals=yes; else goals=no; fi
  adb exec-out screencap -p > "$OUT/goals_shown.png"
  missing=()
  grep -qE '(text|content-desc)="Goals"' "$OUT/goals_shown.txt" ||
    missing+=(Goals)
  grep -qE '(text|content-desc)="Add goal"' "$OUT/goals_shown.txt" ||
    missing+=('the goal button')
  grep -qE 'text="Today' "$OUT/goals_shown.txt" ||
    missing+=('"Today"')
  [ "$goals" = yes ] ||
    missing+=("the goals (\"$GOALS_EXPECTED\"; got \"${shown:-}\")")
  if [ ${#missing[@]} -eq 0 ]; then
    pass shown
  else
    fail shown "the widget didn't show: ${missing[*]}"
  fi
fi

# A goal, with the app's process gone, as Android ends it in the
# background: the tap that launched it is the one the Dart side collects
# as it starts. Not force-stopped: Android hides a stopped app's widgets
# until it's opened again. The first goal shown: a sub-goal, so its page
# is told from Plan's Goals, which shows only the top-level goals.
goal=$(shown_goals "$OUT/goals_shown.txt" 2>/dev/null | cut -d'|' -f1)
# Whether the widget's drawn, showing the goal: not Glance's loading view
# (a ProgressBar, the app's), which it's left on if the app's ended while
# drawing it.
widget_drawn() {
  local nodes
  nodes=$(ui_nodes) || return 1
  grep "$WIDGET" <<<"$nodes" | grep -qE "text=\"$goal\"" &&
    ! grep "package=\"$PKG\"" <<<"$nodes" | grep -q 'class="android.widget.ProgressBar"'
}
# Drawn, and still so 3 seconds on.
widget_settled() { widget_drawn && sleep 3 && widget_drawn; }
# As calendar_widget_test.sh: by kill -9, as root, once there's been no
# process for 3 seconds, for up to 2 minutes, letting it draw the widget
# again each time Android starts it back up meanwhile.
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
# The goal's page, once the app's started and the goals have loaded: its
# title -- read with its parent's under it, on a line of its own -- with
# its Edit button; not Plan's Goals, which has none.
goal_opened() {
  local nodes
  nodes=$(ui_nodes) || return 1
  grep -qE "(text|content-desc)=\"$goal(\"|&#10;)" <<<"$nodes" &&
    grep -qE '(text|content-desc)="Edit"' <<<"$nodes"
}
if [ -z "$goal" ]; then
  fail goal_cold "no goal in the widget to tap"
elif adb shell pidof "$PKG" >/dev/null; then
  fail goal_cold "the app was still running after kill -9"
elif ! poll 20 widget_drawn; then
  fail goal_cold "the widget didn't show \"$goal\" to tap (on its loading view?)"
elif tap_view "$goal" "$WIDGET" && poll 30 goal_opened; then
  adb exec-out screencap -p > "$OUT/goals_goal_cold.png"
  pass "goal_cold ($goal)"
else
  fail goal_cold "tapping \"$goal\" didn't open its page"
fi

# "Goals", with the app in the background, on Notes -- left on the goal's
# page by the cold case, Back goes to the page under it first: Plan, on
# its Goals pane -- "Plan" over it, and the pane's New goal button.
launch
wait_for '(Notes|Back)' 30
if on_screen Back; then
  adb shell input keyevent KEYCODE_BACK
  sleep 1
fi
wait_for Notes 30 && tap_view Notes >/dev/null
sleep 1
goals_pane_opened() { on_screen Plan && on_screen 'New goal'; }
if widget_home && tap_view Goals "$WIDGET" && poll 20 goals_pane_opened; then
  adb exec-out screencap -p > "$OUT/goals_goals_warm.png"
  pass goals_warm
else
  fail goals_warm "tapping \"Goals\" didn't open Plan on Goals"
fi

# Its goal button.
if widget_home && tap_view 'Add goal' "$WIDGET" &&
  wait_for 'New goal' 20; then
  adb exec-out screencap -p > "$OUT/goals_add_goal.png"
  pass add_goal
else
  fail add_goal "the goal button didn't open the New goal sheet"
fi

# Its settings, opened as the launcher opens them, for its id: the title
# moved to the bottom, under the goals. The top of a view $1 (exactly).
top_of() {
  ui_nodes | grep "$WIDGET" | grep -E "text=\"$1\"" | head -1 |
    sed -n 's/.*bounds="\[[0-9]*,\([0-9]*\)\].*/\1/p'
}
# Whether its title's at the bottom, below its first goal, once it's
# redrawn.
title_moved() {
  after_title=$(top_of Goals)
  after_goal=$(top_of "$goal")
  [ -n "$after_title" ] && [ -n "$after_goal" ] && [ "$after_title" -gt "$after_goal" ]
}
# Its id, from the first widget the dump says is its receiver's.
widget_id=$(adb shell dumpsys appwidget | tr -d '\r' |
  awk '/id=[0-9]+/ { match($0, /id=[0-9]+/); id = substr($0, RSTART + 3, RLENGTH - 3) }
       /GoalsWidgetReceiver/ && id != "" { print id; exit }')
widget_home
before_title=$(top_of Goals)
before_goal=$(top_of "$goal")
if [ -z "$widget_id" ]; then
  fail title_bottom "couldn't find the widget's id"
elif ! adb shell am start -W -n "$PKG/.GoalsWidgetConfigureActivity" \
  --ei appWidgetId "$widget_id" >/dev/null || ! wait_for 'Title at the bottom' 20; then
  fail title_bottom "its settings didn't open"
# Done closes it onto the home screen as it was: not Home again, which,
# pressed on the home screen, goes to its first page.
elif [ -n "$before_title" ] && [ -n "$before_goal" ] &&
  [ "$before_title" -lt "$before_goal" ] &&
  tap_view 'Title at the bottom' && sleep 1 && tap_view Done &&
  poll 20 title_moved; then
  adb exec-out screencap -p > "$OUT/goals_title_bottom.png"
  pass title_bottom
else
  fail title_bottom "\"Goals\" wasn't moved below the goals (before $before_title/$before_goal, after ${after_title:-?}/${after_goal:-?})"
fi

# Its text size, from the same settings: "Large" doubles its rows, so
# the second goal starts twice as far below the first as before.
second=$(shown_goals "$OUT/goals_shown.txt" 2>/dev/null | cut -d'|' -f2)
row_gap() {
  local a b
  a=$(top_of "$goal")
  b=$(top_of "$second")
  [ -n "$a" ] && [ -n "$b" ] && echo $((b - a))
}
widget_home
before_gap=$(row_gap)
rows_doubled() {
  after_gap=$(row_gap)
  [ -n "$after_gap" ] && [ "$after_gap" -ge $((before_gap * 2 - 2)) ]
}
if [ -z "$before_gap" ] || [ "$before_gap" -le 0 ]; then
  fail text_large "couldn't measure the rows (gap ${before_gap:-?})"
elif ! adb shell am start -W -n "$PKG/.GoalsWidgetConfigureActivity" \
  --ei appWidgetId "$widget_id" >/dev/null || ! wait_for Large 20; then
  fail text_large "its settings didn't offer the text size"
elif tap_view Large && sleep 1 && tap_view Done && poll 20 rows_doubled; then
  adb exec-out screencap -p > "$OUT/goals_text_large.png"
  pass text_large
else
  fail text_large "the rows weren't doubled (gap before $before_gap, after ${after_gap:-?})"
fi

kill $logcat
grep -E 'TimeTracker|flutter|HomeWidget|Glance|AppWidget' "$OUT/goals_logcat.txt" | tail -100 || true
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All cases passed"
