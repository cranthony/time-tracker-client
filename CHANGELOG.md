# Changelog

Each release's version is in `pubspec.yaml` (the part before the `+`; CI
supplies the build number). Bump it in every pull request that changes the
app, following [semantic versioning](https://semver.org): patch for fixes,
minor for new features, major for changes that break something you rely
on. Add the new version's section here at the same time; CI checks both.

## 2.3.0

- Sample data: run with `--dart-define=SAMPLE_DATA=true` (and no
  `MCP_URL`) to try the app with a realistic day of notes, events and
  goals, including every goal status and health ratings.
- Visual tests screenshot the main screens in light and dark. On each pull
  request, CI shows which screens changed, with before, after and
  difference images. See "Visual tests" in the README.

## 2.2.0

- Each active goal with a cadence shows its health on the Goals page: a
  dot in its band's color (green from 70, yellow from 40, red below)
  beside its latest confirmed rating, and a small chart of its last 8
  ratings. A goal with periods gone unassessed says how many, e.g.
  "2 weeks unassessed".
- A goal's menu opens its history: its recent ratings as a bar chart,
  the band edges marked, proposed ratings (not yet confirmed in a
  reflection) hollow, and each assessment listed below with how it was
  reached. Tapping a bar picks it out in the list.

## 2.1.2

- An active goal with no color of its own shows a grey flag outline,
  filled with the color it inherits: its parent's, or as a last resort
  its priority's. A goal with its own color still shows a solid flag in
  it. Goal pickers show inherited colors too.

## 2.1.1

- The Goals page's status filter is a drop-down at the top right, with a
  check box for each status, instead of chips above the list. It stays
  open while you tick several, and a dot on its icon says it's showing
  something other than proposed, active and inactive goals.

## 2.1.0

- Goals have a status: proposed, active, inactive, completed, archived
  or deleted. Each shows its own icon, and anything but active is named
  under the goal. Only active goals take up a calendar label.
- Chips at the top of the Goals page pick which statuses are shown:
  proposed, active and inactive to start with.
- A goal's menu moves it to any other status. Moving an active goal away
  from active, or deleting a goal, asks first.

## 2.0.0

- Goals replace event labels: the **Goals** page replaces the Labels
  page, and needs a server with goals (one without them can't list
  anything there). Goals are listed as a tree, sub-goals indented under
  the goal they're part of, with how many of the calendar's 200 event
  labels are in use.
- Show active, inactive or all goals. Deactivate a goal from its menu
  (after a check) to free its label while keeping its history, or
  activate it again.
- Add a goal with **+**, or a sub-goal from a goal's menu. Tap a goal to
  change its name, parent, color, priority, fixed time, cadence (daily,
  weekly, monthly or every 2 months), target, deadline or note.
- An event's goals are picked by name from the active goals, the first
  one picked being its primary goal; its label now follows its goals,
  so it isn't edited directly any more.

## 1.12.1

- Cancelling an event no longer says it stays in the list, struck
  through: the server doesn't list cancelled events, so it leaves the
  list. A message says it was cancelled.

## 1.12.0

- Each page shows what it showed last time straight away, instead of a
  blank page while it waits for the server. A thin bar across the top
  says it's being refreshed; when the server answers, the page updates
  and the bar goes. If the server can't be reached, the page keeps
  what it has and says it may be out of date.
- On the Events page that's today, the day it opens on; other days
  still load when you step to them.
- The app keeps the server's last answers on the device, where it keeps
  unsaved notes, and forgets them when you sign out.

## 1.11.0

- The Labels page hides labels with no name. They hold the calendar's
  default colors, and aren't meant to be edited.
- A label's name can't be emptied: the dialog says "This can't be empty."
  and keeps it open until you type a name or cancel the edit.

## 1.10.1

- A note waiting to be saved no longer gets stuck showing "Saving…".
  If storing a note's progress on the device fails, or the device storage
  stops answering (after 10 seconds now), the app lets go of the note
  and tries again later, instead of waiting for a restart.
- A note the background task was saving when Android stopped it is
  checked against the server before the app sends it again, so it isn't
  saved twice.

## 1.10.0

- Clearing a label's color or priority now works: the app names them in
  `update_event_label`'s new `clear_fields`, which the server needs to
  blank a value. Before, the server kept the old one.
- A label's name, fixed time and note can be edited and cleared too.
  Fixed time is Yes, No or Not set.
- A label with no color takes its priority's color, and the color editor
  says so.

## 1.9.0

- Edit an event label from its dialog on the Labels page: tap its name,
  color or priority to change it there, then Save. Each changed value
  shows its old value struck through until you save. If saving fails,
  the dialog stays open with your edits and shows the server's error.
- Colors are picked from Google Calendar's 24 calendar colors, from a
  square and hue bar under "More colors", or typed as a hex code. "No
  color" clears it, and emptying the priority clears that; if the server
  won't, the dialog shows its error.
- A label's color shows next to its hex code, and next to each label's
  name when picking an event's label.

## 1.8.0

- Edit an event from its dialog on the Events page: tap a value to
  change it there, then Save. You can change the summary, start, end,
  description, location, label, priority, minimum duration, and whether
  its time and duration are fixed. Each changed value shows its old value
  struck through until you save. If the server moves other events to
  make room, a message says how many. If saving fails, the dialog stays
  open with your edits and shows the server's error.
- Cancel an event from its dialog. The server can't undo this, so the app
  asks first.
- Minimum durations show as "1h 30m" rather than "PT1H30M".
- Picking a label lists the labels by name. As on the Labels page, that
  syncs them from the event label sheet.

## 1.7.0

- A Labels page, from the bar at the bottom of the screen, lists your
  event labels: each one's color, name, priority and whether it's fixed
  time. Tap a label to see all its properties. The server has no
  read-only way to list labels yet, so opening the page syncs them from
  the event label sheet; that applies any edits pending in the sheet.

## 1.6.0

- Tap an event on the Events page to see all its properties, as the
  server has them, in a dialog. Start and end are in local time.

## 1.5.0

- An Events page, from the bar at the bottom of the screen, shows a
  day's events: each one's summary, start and end. Step a day back or
  forward with the arrows, or tap the date to pick one. Notes is still
  the page the app opens on.

## 1.4.1

- The server's name moved from the top of the notes screen into About.

## 1.4.0

- New and edited notes open in a sheet at the bottom of the screen, just
  above the keyboard, with a box four to eight lines tall. Delete is the
  bin at the top of the edit sheet. Swipe the sheet down (or tap above
  it) to cancel.

## 1.3.0

- Shows all uncompacted notes, not just today's, under day headings
  ("Today", "Yesterday", or the date).

## 1.2.0

- Tap a note to edit its description or time, or to delete it (with
  undo). Needs a server with the edit_note and delete_note tools.

## 1.1.1

- The home screen "+" brings the keyboard up on Android 16 too.

## 1.1.0

- The app's version and build number, under About in the menu.

## 1.0.0

Everything up to the start of versioning:

- Today's uncompacted notes from the Time Tracker MCP server, with a "+" to
  add one; signing in with WorkOS; Android, Windows and web.
- Notes not saved yet are kept, shown as pending, and retried until they're
  saved or cancelled, also in the background on Android.
- Notes are sent in the device's time zone.
- A home screen "+" widget and an "Add note" app shortcut, which open the
  New note dialog with the keyboard up.
- The calendar-dial app icon.
