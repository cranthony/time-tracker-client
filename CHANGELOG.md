# Changelog

Each release's version is in `pubspec.yaml` (the part before the `+`; CI
supplies the build number). Bump it in every pull request that changes the
app, following [semantic versioning](https://semver.org): patch for fixes,
minor for new features, major for changes that break something you rely
on. Add the new version's section here at the same time; CI checks both.

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
