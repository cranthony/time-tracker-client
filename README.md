# Time Tracker Client

A Flutter app for the [Time Tracker MCP server](https://github.com/cranthony/time-tracking-google-calendar-mcp).
For now it shows your **uncompacted notes**, by day, and has a **+** button to
record a new one; tap a note to change its description or time, or to
delete it. An **Events** page, from the bar at the bottom, shows a day's
events from your calendar; tap one to see or edit it, including the actions
done at it and what happened: who it was with and for, where, and notes.
Where events overlap, the timeline tints that time red and labels it
"overlap". Its **+** puts a cursor at now, which a tap on the timeline
moves: its arrows step it, and a "+" either side makes the event that
way, a box between two cursors -- its top and its bottom, alike. Each
cursor's time, after its corner (┌ or └), says what it's on -- "end of
Lunch", "start of Work", "note: …" -- with scissors while it cuts into
an event, and tapped, is typed in. On its outside, a "+" and a "−"
stretch and shrink the event there, and its handle drags it. The box
itself, dragged, moves; tapped, says what it does with the events in
its way: trims them (the default), keeps clear of them, cancels them,
or pushes them along -- its icon on it, but for trimming. Once there's
a box, a tap on the timeline leaves it be. Keeping, a "+" against an
event is greyed out. Then ✓ to fill it in. A cursor stops on the grid
set in [Settings](#settings) and, as set there, at events' edges and
notes too: its buttons step it to the next such stop, and dragged near
one it snaps there. While it's up, the edges and notes it stops at are
marked on the timeline, pulsing. Pressed and held, an event is moved
the same way, pushing to start with. While
Claude has a **compaction proposal** open -- what it says happened since the
last compaction -- it's a band over the timeline, each change marked, to
confirm: edits to the events in it edit the proposal, not the calendar, and
a bar above confirms it as shown or leaves a note for Claude to revise it
(see [Compaction proposals](#compaction-proposals)). Above them, a summary shows how the day's time is split by its top
actions; swipe it to see the top-level groups, or the time by priority. A **Plan** page
has four panes, swiped between or picked from its tabs, each but People
with a search of its own. Landing on it loads every pane at once, and it shows what it
had last time while it loads again. The Actions, People and Locations
panes each have a summary, at the top, of the time in the 24 hours
and 7 days before the last compaction -- or after it, with "Next" -- worked
out from the events; its arrows move the window a day at a time, and
tapping the date goes back to the last compaction.

- **Actions** (do), leftmost: what you do with your time, as a tree of
  groups -- names that roll up the actions in them -- with actions, the
  only thing events are given, as its leaves, each with its time in the
  window. The summary splits the time by the actions shown, or by
  priority. Tap a group to open or close it; tap an action to set its
  priority and color, or go on to its details. Only active actions take up one of the calendar's event labels. An
  action Claude made is *proposed* until you approve it. The search finds
  actions by name, path and note, in their groups.
- **Traits** (how to be): each trait you define -- none is built in. A
  trait is made of parts: chiefly *judgments*, which Claude makes of each
  event, each with a rubric, a rating scale of your own, and the facts
  it's judged from (actions, action history and location history, each
  with a lookback, location, general notes, person notes); and counts,
  time spent, continuity and follow-through, which can count one action
  or group. Every part reads the events with someone, or those done for
  them. Tap one for its page: its parts, then its health (the last day's
  score, the mean of everyone scored by it, and its trend);
  its pencil edits it, on a page of its own. Time spent's target is
  written, or stepped, in hours and minutes.
- **People** (who): two sections, each folded away by tapping its head.
  **Self** has your health and the two habits you focus on (starred on
  a habit's page), with a way to your page. **People** has
  the three you keep in front (starred on a person's page, or from their
  menu), each with their
  time with you in the summary's window and the last event with them --
  or the next, looking on; both picks are kept on the device. "All
  people and circles" opens everyone -- there's no search on the pane
  itself, with so few on it; its "+" is in People's head --
  to search, sort (by health, when
  last or next seen, or time in 24 hours or 7 days, either way) and
  edit, on a page of its own: each with a context
  that tells people of the same name apart, in any number of circles.
  Tap a circle to see only its people; tap a person for their page: who
  they are, which traits apply to them (every active one, or those
  picked, with their own parts for any) and what matters to them; and,
  once scored, their events in brief -- how many and their time, the
  most recent and the oldest -- and those cancelled against their
  follow-through likewise, each with a button, "All events" or "All
  cancelled events", to a page of them all. The
  summary splits the time by who it was with, or by circle (people in
  none are "Individuals"). Self's page has their habits too (see
  [Habits](#habits)).
- **Locations** (where): the places events happen, each with a hint the
  assistant recognizes it by. The summary splits the time by where it
  was.

The app works out the traits' scores itself, from the calendar's events
and Claude's judgments of them, as the server's scoring does: each
person's score of each trait for each of the last 7 days, each trait's
health (everyone's mean), and each person's relationship health (gray,
disconnected, to green, healthy) and history; and each of Self's habits'
scores and health (on track to off track). Follow-through counts the events the user cancelled that
count against each person or habit, which the server lists with them; their
pages list them too. Every way the app cancels an event asks whether it
counts: cancelling it, and making room for another -- each event a move,
a new event or clearing time would cancel is listed, a change of plan
unless turned on. Deleting a series from an event on is a change of plan,
as the server keeps it. As it opens, the app asks
for the week either side of today, and for any day further back (or
ahead) the traits read that it hasn't kept from an earlier run; the
Events page shares those days, and its saves change the scores at once.

Later it will show the summaries the server
generates.

It is built for Android and also runs on Windows and in Chrome. Chrome
needs no extra tooling, so it's the quickest way to try changes.

## One-time setup (both platforms)

1. **Install Flutter.** Follow <https://docs.flutter.dev/get-started/install>
   for your OS. When `flutter doctor` runs clean for the platform you want,
   you're done.
2. **Clone this repo** and fetch packages:
   ```sh
   git clone https://github.com/cranthony/time-tracker-client.git
   cd time-tracker-client
   flutter pub get
   ```
3. **Point it at your server.** Copy `config.example.json` to `config.json`
   (it's gitignored) and set `MCP_URL` to your deployed server's URL plus
   `/mcp`, the same URL you gave Claude.ai. You'll find it in the Render
   dashboard.

   If you skip `--dart-define-from-file=config.json` in the commands below,
   the app runs in an **offline demo mode** with in-memory notes. That's
   handy for UI work. To fill it with sample notes, events and a plan, see
   [Try it with sample data](#try-it-with-sample-data).

## Try it with sample data

To try the app on your own machine without a server or signing in, launch
it with `SAMPLE_DATA=true`. It starts with a realistic day of
[sample notes, events and a plan](#sample-data), dated relative to today.
You need only Flutter and a clone of this repo (steps 1 and 2 above); skip
`config.json`.

In Chrome, which needs no other tooling:

```sh
flutter run -d chrome --dart-define=SAMPLE_DATA=true
```

On Windows (with the [prerequisites](#run-on-windows) installed), or on a
plugged-in Android phone or a running emulator:

```sh
flutter run -d windows --dart-define=SAMPLE_DATA=true
flutter run --dart-define=SAMPLE_DATA=true      # Android
```

Or build the web app once and serve it, then open <http://localhost:8765>:

```sh
flutter build web --dart-define=SAMPLE_DATA=true
python -m http.server 8765 --directory build/web
```

A few things to know:

- **Don't add `--dart-define-from-file=config.json`.** Sample data is used
  only when there's no `MCP_URL`. With one, the app talks to your server
  and ignores `SAMPLE_DATA`.
- **Changes aren't saved.** New notes, edited events and actions last until
  the app restarts. Reloading the page in Chrome, or a hot restart (`R`
  in the terminal), starts again from the sample data. A hot reload (`r`)
  keeps them.
- Without `SAMPLE_DATA=true` the app starts empty.

## Run on Windows

Prerequisites (once):

- **Visual Studio 2022** (the full IDE, not VS Code), with the
  **"Desktop development with C++"** workload. The free Community edition
  is fine.
- **Developer Mode** on (Settings → System → For developers). Flutter needs
  it to build plugins.
- `flutter doctor` should show a ✓ for "Visual Studio - develop Windows apps".

Then:

```powershell
flutter run -d windows --dart-define-from-file=config.json
```

The app opens in a phone-sized window. Click **Sign in**: your browser
opens the WorkOS sign-in page. After you sign in, the browser shows
"Signed in", and the app loads your notes. Press `r` in the terminal to
hot-reload after code changes.

To build a standalone `.exe` instead:

```powershell
flutter build windows --dart-define-from-file=config.json
# → build\windows\x64\runner\Release\time_tracker_client.exe
```

## Run in Chrome

No prerequisites beyond Flutter and Chrome.

```powershell
flutter run -d chrome --web-port 8765 --dart-define-from-file=config.json
```

Or build it once and serve the static files:

```powershell
flutter build web --dart-define-from-file=config.json
python -m http.server 8765 --directory build/web
```

Then open <http://localhost:8765>. Click **Sign in**: a popup window shows
the WorkOS sign-in page, then closes itself, and the app loads your notes.
If Chrome blocks the popup, allow popups for the site and click again.

Serve it from `localhost` (any port). The server allows cross-origin calls
from `localhost`; for anywhere else, add that origin to the server's
`MCP_CORS_ALLOWED_ORIGINS`.

In the browser, registering the app and fetching tokens go through the
MCP server's `/oauth/register` and `/oauth/token`, which forward them to
AuthKit: AuthKit's own endpoints don't allow browser calls (no CORS
headers). Nothing needs configuring in WorkOS for this.

### Hosted on GitHub Pages

Every push to `main` builds the web app and publishes it to
<https://cranthony.github.io/time-tracker-client/>
([.github/workflows/pages.yml](.github/workflows/pages.yml)). It needs:

- **Pages** set to deploy from GitHub Actions (Settings → Pages → Source).
- The repository variable **`MCP_URL`** (Settings → Secrets and variables
  → Actions → Variables), the same value as in `config.json`.
- The server's **`MCP_CORS_ALLOWED_ORIGINS`** set to
  `https://cranthony.github.io` (on Render: the service's Environment tab).

#### Content-Security-Policy

The published app runs only its own code. The build serves CanvasKit (the
WebAssembly graphics engine) from the app's own site rather than Google's
CDN (`--no-web-resources-cdn`), and `tool/web_csp.dart` then adds a
Content-Security-Policy to `index.html` that:

- runs scripts and WebAssembly only from the app's own site: no inline
  scripts, no `eval`, nothing from other sites;
- lets the page connect only to its own site, the MCP server, AuthKit
  (which the tool reads from the server's metadata during the build) and
  Google's font server, which supplies fonts for emoji and other scripts.

`web/callback.html` has its own fixed policy, and its script is in
`web/callback.js`.

The app also refuses to run inside a frame, where another site could hide
it under its own page so that your clicks land on the app
("clickjacking"). Pages can't send the header that forbids framing, so
`web/start.js` checks instead, and only loads the app in a window or tab
of its own.

To try the published setup locally:

```powershell
flutter build web --csp --no-web-resources-cdn --dart-define-from-file=config.json
dart run tool/web_csp.dart build/web https://your-service.onrender.com/mcp
python -m http.server 8765 --directory build/web
```

## Run on Android

### Install from Google Play (internal testing)

Every push to `main` builds a signed app bundle
([.github/workflows/android.yml](.github/workflows/android.yml)) and
uploads it to Google Play's **internal testing** track, as
`com.cranthony.timetracker`. Internal testing needs no review and no
waiting period, and only testers you list can install it. Open the
track's opt-in link on the phone (Play Console → Testing → Internal
testing → Testers), and the app appears in the Play Store. If your work
profile's Play Store only offers approved apps, install it from the
personal profile.

One-time setup:

1. **Create the app** in the Play Console: Time Tracker, app, free.
2. **Upload the first bundle by hand.** Google's API can't create an
   app's first release. Download `time-tracker.aab` from the latest
   [GitHub Release](https://github.com/cranthony/time-tracker-client/releases/latest)
   and upload it under Testing → Internal testing. Keep **Play App
   Signing** on: Play signs what gets installed, and our key (below)
   becomes the *upload key* that proves builds come from you. Add
   yourself as a tester.
3. **Let GitHub publish.** In Google Cloud, create a project, enable the
   **Google Play Android Developer API**, and create a service account
   with a JSON key. In the Play Console (Users and permissions), invite
   the service account's email with release permissions for this app.
   Then store the key as a repository secret and delete the file:
   ```sh
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < key.json
   ```
   Until this secret exists, the workflow skips the Play upload.

The Play Console may also ask for app-content details (privacy policy,
data safety, content rating) before it will release to testers; its
setup checklist lists what's missing.

### Install the published build (no tools needed)

Every push to `main` also builds a signed APK and publishes it, with the
app bundle, as a GitHub Release. On the phone, open
<https://github.com/cranthony/time-tracker-client/releases/latest/download/time-tracker.apk>
in the browser, then open the downloaded file. The first time, Android
asks you to allow installs from your browser. To update, do the same
again: it installs over the old version and keeps you signed in.

Every build is signed with the same key, which is what lets updates
install over each other (and what Play checks as the upload key). It's kept in the `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD` repository secrets (a PKCS#12 keystore, key
alias `upload`), with a backup outside the repo. Losing it means
uninstalling the app to install a build signed with a new key. APKs you
build yourself are signed with your debug key instead, so Android won't
install one over a published build, or the other way round, without
uninstalling first.

### Build it yourself

Prerequisites (once):

- **Android Studio**, which installs the Android SDK. Open it once and let
  it finish setup, then run `flutter doctor --android-licenses` and accept.
- On the phone, **enable Developer options** (Settings → About phone → tap
  *Build number* 7 times). Then turn on **USB debugging** under
  Settings → System → Developer options.

**To run it while developing:** plug the phone in over USB and accept the
"Allow USB debugging?" prompt on the phone. Then:

```sh
flutter devices        # your phone should be listed
flutter run --dart-define-from-file=config.json
```

**To install it and keep it**, without a cable afterwards:

```sh
flutter build apk --release --dart-define-from-file=config.json
flutter install                  # with the phone plugged in
```

Alternatively, copy `build/app/outputs/flutter-apk/app-release.apk` to the
phone and open it. You'll have to allow installing from that source.

Tap **Sign in**, sign in in the browser, and Android returns you to the app.

### Add-note button on the home screen

There are two ways to get a one-tap **+** on the home screen:

- **Shortcut (labelled like your other icons):** long-press the Time
  Tracker icon, then drag **Add note** from its menu onto the home screen.
  The launcher draws the icon and its "Add note" label, so they match the
  rest of your home screen, including its icon shape and themed icons. You
  can also tap **Add note** in that menu without pinning it.
- **Widget (no label):** long-press an empty spot on the home screen,
  choose **Widgets**, find **Time Tracker**, and drag **Add note** to where
  you want it. It's a round **+** button.

Either one opens the app straight into the **New note** sheet, timed at
the moment you tapped, even if it takes a few seconds to type the
description. After you tap **Add**, it's saved like any other note,
including when you're offline.

## Signing in (WorkOS AuthKit)

The MCP server is an OAuth *resource server*, and WorkOS AuthKit issues its
tokens. The app signs in the same way Claude.ai does, so **nothing needs
configuring in WorkOS** beyond what the server's README already covers.
Specifically:

1. It reads `/.well-known/oauth-protected-resource/mcp` from the server to
   find AuthKit.
2. On first sign-in, it registers itself through **Dynamic Client
   Registration**. The "Allow MCP clients to authenticate using DCR…"
   setting in WorkOS has to be on, which it already is if Claude.ai works.
3. It runs the authorization-code flow with PKCE in your browser. It asks
   for a token for the server's URL (the `resource` parameter), which is
   the audience the server checks.
4. It stores the tokens in secure storage (Android Keystore or Windows
   DPAPI) and refreshes them automatically. Use **⋮ → Sign out** to
   forget them.

   Browsers have no such storage, so on the web the tokens are only
   ever in the page's memory, never in browser storage or on disk.
   Reloading the page or opening it again means signing in again,
   usually just a popup that closes itself, since AuthKit remembers
   you. While the page is open, its
   [Content-Security-Policy](#content-security-policy) keeps other
   sites' scripts off it, but browser extensions allowed to read the
   site, and programs running as you, could still reach the tokens. The
   client registration (not a secret) stays in `localStorage`, so the
   app reuses it instead of registering another client each time.

Redirect URIs it registers:

| Platform | Redirect URI |
| -------- | ------------ |
| Windows  | `http://localhost:47291/callback` |
| Android  | `com.cranthony.timetracker://oauth/callback` |
| Web      | `callback.html` next to the app, e.g. `http://localhost:8765/callback.html` |

### Troubleshooting sign-in

- **"Client registration failed"**: DCR is off in WorkOS (Connect →
  Configuration), or WorkOS refused the redirect URI above. If it's the
  Android one, try Windows first; that uses a plain localhost redirect.
- **The browser says it can't reach localhost:47291 (Windows)**: the app
  wasn't waiting for the redirect. Click Sign in again. Also check nothing
  else is using port 47291.
- **Chrome: "Failed to fetch" / `ClientException` loading notes**: the
  server refused the cross-origin call. Serve the app from `localhost`, or
  add its origin to the server's `MCP_CORS_ALLOWED_ORIGINS`.
- **Signed in, but loading notes fails with HTTP 401**: the token's
  audience doesn't match. `MCP_URL` must be exactly the server's public URL
  plus `/mcp`, with no trailing slash.

## Notes that haven't been saved yet

(For changes to events, see [Changes waiting to save](#changes-waiting-to-save).)

A new note is kept on the device first, and then sent to the server. If
you're offline, the server is down, or you're signed out, the note stays in
the list, tinted and in italics, with its status underneath:

- **Waiting to save / Saving…**: on its way.
- **Not saved · *reason* · retrying**: the last attempt failed. The app
  tries again after 5s, 10s, 20s and 40s, then every minute, until it
  works. Tap the note to retry right away, or pull down to refresh.
- **Not saved · sign in to save**: sign in and it's sent.

The **×** cancels a note that hasn't been saved (with Undo). A note that's
being sent can't be cancelled, since the server may already have it.

Unsaved notes survive closing the app. They're kept in SharedPreferences
on Android, a file in AppData on Windows, and localStorage in the browser.
Once a send has failed, the next attempt first checks whether the server
got the note after all, so a lost response doesn't create a duplicate.

**In the background:**

- **Android:** when the app leaves the screen with notes still unsaved, it
  hands them to Android's WorkManager. That runs once there's a network
  connection, even if the app has been closed, and keeps retrying with
  backoff. Android decides exactly when, usually within minutes, and later
  when battery saver is on. It can't sign you in, so if the sign-in has
  expired the notes wait until you open the app.
- **Windows:** a minimised app keeps running, so it keeps retrying.
- **Chrome:** it retries while the tab is open. A closed tab keeps the notes
  and sends them the next time you open the app.

## Settings

A **Settings** page, from the menu, holds what's kept on this device
alone. For now that's the grid the Events page's cursors snap to: every
5, 10, 15 (the default), 30 or 60 minutes from midnight, or none, to
stop at any minute. Every cursor also stops at events' edges and notes,
each of which can be turned off there.

## Background updates

On Android, the app fetches what it keeps while it's closed, so it's fresh
when you open it: the notes and when they were last compacted, every
action, trait, person, location and habit, and the week either side of
today's events. It fetches 10 minutes after each time Claude's routines
run -- compacting notes, answering the notes on a proposal -- and
otherwise every 6 hours. Android's WorkManager runs each fetch around its
time: usually within minutes, later while the phone's idle. Signed out,
it stops till you sign in.

The routines' times are **compaction schedule hints**, kept on the server
(the Compaction Schedule tab of the calendar's metadata spreadsheet): the
routines set them with `set_compaction_schedule_hints`, and the app reads
them with `get_compaction_schedule_hints` -- it can't change them. They're
in the calendar's time zone, which the app takes as the phone's. The
**Background updates** page, from the menu, lists them, each with when the
app updates after it; says it otherwise updates every 6 hours; and shows
when the next update is, and what the last did. A server without the
hints leaves just the 6-hourly updates. On the web and Windows the app
fetches only while it's open.

## Changes waiting to save

Changes to events -- editing, cancelling, adding or moving one -- and
edits of the open compaction proposal don't wait for the server: they're
kept on the device, shown at once as made, marked **Waiting to save**,
and sent in the background, strictly in the order they were made. They
survive closing the app, and Android's background task sends them too,
as it does notes.

While any are waiting, a line at the foot of every page says so: saving,
paused, trying again later, or stopped. Tap it to see them, oldest
first, each with how it's going. From there:

- **Pause** stops sending (kept across restarts) until **Resume**.
- **Try again now** skips the wait after a failed attempt.
- **Edit** changes a waiting change to an event, a new event, or a
  cancel, in its place; a move that changed others is dropped and made
  again instead.
- **Drop** throws one away: what it changed goes back to how the server
  has it.

A change that couldn't be sent -- offline, say -- is tried again by
itself after 5s, 10s, 20s and 40s, then every minute. One the server
refuses (an overlap, say) stops the queue there, saying why, since what
comes after may depend on it: fix it, try again, or drop it. One refused
as changing history can be approved from there (**Change history**).
Why it was refused names the events it's about rather than their ids,
each with **Show**, to go to it on the timeline, ringed.

What a waiting change changes can't change again until it's saved: an
event it cancels or adds not at all, and the fields it sets (its title,
its time, its actions) not until then. Their dialogs say so, those fields
don't open, and a change that would touch them -- a move pushing it, say
-- says which change it's waiting for. A proposal with edits waiting
can't be confirmed till they're saved. Series, and notes for Claude, are
still saved at once.

A new event is checked for before it's sent again after an attempt
nobody heard back from, so a lost response doesn't create it twice.

## Compaction proposals

A scheduled Claude routine compacts notes into the calendar as a
*proposal*: "this is what happened from the last compaction to
`through`" ([the server's design](https://github.com/cranthony/time-tracking-google-calendar-mcp/blob/claude/compaction-proposals/docs/compaction-proposals.md)).
Claude can't apply one; only confirming it in the app does.

- **The band.** On the Events page, the proposal's window is tinted and
  outlined, headed "What happened -- to confirm" and ending at a
  "through" line. Each event in it says what the proposal does to it --
  moved (and from where), new, cancelled, renamed, new actions or facts
  -- and whether Claude or you decided it; one as planned is plain. Those
  changed since the revision you last saw (kept on the device) have a dot.
  Its notes are lines across it, each with a badge: ↳ added to an event,
  ⇕ setting an event's start or end, ⊘ left out. Under the bar is one of
  them -- its time, text and what became of it -- highlighted on the
  timeline, with arrows to step to the note before or after -- back to
  the latest note the last compaction used, with a ✓, as context. Its pencil
  says what the note is for -- added to the event it falls within (or
  whose start or end it sets), to another of its day's, or left out --
  puts it back as Claude had it, or asks Claude about it.
- **Editing it.** Moving, resizing, cancelling or adding an event in the
  band, or setting its actions, people or location, edits the proposal
  (`amend_proposal`), with the same dialogs and press-and-hold move as
  ever, and what it does to the events in its way. Its whole description, location and priority can be
  changed too; a cancelled one can be put back as planned. If the server
  refuses an edit (an overlap, say), it stays in the dialog to fix, and
  the proposal loads again. Below the band is the plan, changed on the
  calendar; before it, history, changed only after asking.
- **Extending it.** Its "through" tab, with a pencil, extends what
  happened past where Claude's revision ran to: the end's cursor, its
  anchor fixed at Claude's end, dragged, stepped to its next stop
  ("+", "−"), or typed in (its settings, which also say what it stops
  at) -- never back past where it ends, nor past now -- then
  **Extend**. The notes it takes in are added to the events they fall
  within, as yours: their badge is a person with a "+", and they say
  so. The stretch you added is tinted apart, headed "extended by you".
  Claude's next revision runs to now, past it.
- **Its details**, under the bar, in pages swiped between and folded away
  like the day's summary: its notes; its follow-through -- how many
  cancels count against it, each with who it counts against, and a switch
  to say it's a change of plan, or not -- and what it adds, each person,
  action and location to settle: made now, one already here, or dropped,
  or asked about. Each is stepped through one at a time, and shown on the
  timeline.
- **The bar.** "Confirm ... happened as shown" applies it. "Note for
  Claude" leaves a note, about an event or all of it; while one's open
  it's waiting for Claude, who answers it on its next run (or ask in a
  conversation), and it can't be confirmed. "Notes" shows them, Claude's
  replies beside them, and withdraws an open one. If the calendar changed
  since it was planned, it says what changed and asks to confirm again; if
  it can't be planned any more, it's handed to Claude; if applying it
  stopped partway, Retry finishes it. Its menu goes to it, or abandons it.

The sample data has one open, so `SAMPLE_DATA=true` shows it.

## Habits

A habit is something you want to do well -- practicing guitar mindfully,
cooking from scratch -- about one action, or every action under one
group: its events are yours with that action, worked out from the tree
as it is when they're judged or scored, so moving an action between
groups moves it in or out. Like a person, it's held to traits: every
active one unless it picks some, each with its own parts if it likes (a
rubric for this habit alone). You're at every one of its events, so a
part that reads events done for someone doesn't apply; one that counts
an action names one in it, and the editor warns of one that doesn't.
Claude judges its events beside everyone's, under `habit:<id>`, and the
events cancelled that count against its follow-through are listed with
it, as a person's are; to judge past events, ask Claude.

The app scores them as it scores people, from those events and
judgments: a habit's page shows its health, each trait's score and
trend, how each was reached, and its events. An event's notes name its
judgments for a habit by the habit. Self's page lists them, with "Habit"
to add one; each has a page of its own, and a pencil that opens another
to edit it. They come from the server's `get_habits`,
`create_habit` and `update_habit`; a server without them shows none, and
nothing else changes. The sample data has two: one on the Guitar group
with parts of its own, one on Cook lunch or dinner with every trait,
each with Claude's judgments of a few of its events.

## Development

```sh
flutter analyze
flutter test
```

Tests cover the MCP client, the whole OAuth flow (against a fake AuthKit),
the outbox of unsaved notes, and the notes screen, so none of them need a
server.

### Sample data

`lib/demo/sample_data.dart` is a realistic day of notes, events and a plan
for trying the app without a server. Its traits are made of facets and
cadences; its people, Self and six others in five circles, run from
healthy to disconnected, with Claude's judgments of their recent events
behind each score; Self has two habits; its actions are a tree of groups three levels deep,
with every status, their own and inherited colors, and health ratings,
including skipped periods, periods not yet assessed, and a proposed
rating. It's dated relative to today, so it never goes stale. To run the app with it,
see [Try it with sample data](#try-it-with-sample-data).

### Visual tests

`test/visual` renders the main screens with the sample data, at a phone's
size, in light and dark: Plan (each pane, People looking on, everyone
as listed and sorted, a person being edited, a Time spent part's target, a circle's people, searches
of people and actions, a trait's page, a trait and an action being
edited, and its
actions with every status, and the time summary on each page and folded
away), a person's page, Self's habits, a habit's page, how one of its scores
was reached and one being edited, Events (with each page of its day summary, folded away, events that
overlap,
what happened at an event, and a compaction proposal: the band, its
start, a note stepped to, its notes for Claude, and waiting for Claude; and
changes waiting to save: on the timeline, their sheet, one refused, and
an event waiting, opened), the Background updates page
and Notes.
It writes them, at 2x and with the real fonts (Roboto and Material
Icons, from the Flutter SDK), to `build/screenshots/`. This is the quick
way to see a UI change without running the app:

```sh
flutter test test/visual
```

The fonts come with the SDK but are downloaded only for a build or
`flutter precache`. Without them the tests fail rather than draw text as
blocks; `flutter precache` downloads them.

Some characters show as a box with an X in it, such as the `→` in an action
history's "8h of 10h target → 82". The sample data uses the arrow because
the server writes it in every measured rating's explanation, so the app
must show it. The SDK's Roboto doesn't have it, and tests have no other
font to fall back on. The app itself shows it, since a phone or browser
finds it in another font.

Nothing is compared with images kept in the repo, so the repo doesn't grow
with every UI change. Instead, to see what a change did, screenshot before
and after it, then diff them (this needs `pip install pillow`):

```sh
flutter test test/visual --dart-define=SCREENSHOTS_DIR=build/before   # on main
flutter test test/visual --dart-define=SCREENSHOTS_DIR=build/after    # on your branch
python3 tool/visual_diff.py build/before build/after build/changes
```

`build/changes/index.html` shows each changed screen's before, after, and
their difference (changed pixels in red).

`.github/workflows/visual.yml` does this for every PR, against the PR's
base branch, on Linux. The job summary lists the changed screens. The
`visual-changes` artifact has the images, and the `screenshots` artifact
has every screen as the PR draws it. It reports changes; it doesn't fail
because a screen changed.

`.github/workflows/emulator.yml` also runs the Android app on an emulator
and checks that the home screen "+" brings the keyboard up
(`tool/emulator/keyboard_test.sh`). Tests go there only when they need
Android itself (intents, home screen widgets, the system keyboard, a cold
start); anything else, animations included, is a Flutter widget test,
which is faster and can check every frame.

On a pull request, the slow checks (the Android build, the emulator and
the visual tests) skip a push that changes nothing they use: one that
only changes docs, say, or, after a push they passed, only bumps the
version (`tool/ci/needs_run.sh`). A skipped check counts as passed.

### Versions

The version is in `pubspec.yaml` (e.g. `1.1.0+1`), and the app shows it
under **About** in its menu. Only the part before the `+` is maintained by
hand: CI builds with its run number as the build number, so Android sees
each build as an update. Every pull request that changes the app bumps the
version, following [semantic versioning](https://semver.org) (patch for
fixes, minor for features), and adds a section for it to `CHANGELOG.md`;
the `version` check (`.github/workflows/version.yml`) fails the PR
otherwise. Fixing it reruns only that check. Releases are titled with the
version, e.g. *Time Tracker 1.1.0 (build 25)*.

### App icon

The icon (a calendar page whose body is a clock, on teal) is drawn once in
`tool/icon/generate.py`, which writes every size and format: Android's
adaptive and themed icons and their PNG fallbacks, the web favicon and PWA
icons, and the Windows `.ico`. To change it, edit the drawing there and run:

```sh
pip install pillow playwright && playwright install chromium
python3 tool/icon/generate.py
```

### Layout

```
lib/
  main.dart                      entry point; picks MCP or demo backend
  models/note.dart               the server's NotedTime
  services/mcp_client.dart       MCP over Streamable HTTP, with bearer auth
  services/notes_repository.dart get_notes / note tools
  auth/oauth.dart                discovery, DCR, PKCE, token exchange/refresh
  auth/auth_session.dart         keeps tokens fresh, runs sign-in
  auth/redirect_receiver.dart    localhost listener (Windows) / deep link (Android)
  auth/web_redirect_receiver.dart  popup + web/callback.html (web)
  auth/platform_receiver*.dart   picks the receiver for the platform
  auth/token_store.dart          secure token storage
  outbox/note_outbox.dart        unsaved notes: retry, backoff, cancel
  outbox/outbox_store.dart       keeps them across restarts
  outbox/background_sync.dart    Android WorkManager task that sends them
  platform/add_note_shortcut.dart  taps on the home screen "+" (Android)
  screens/notes_screen.dart      uncompacted notes by day (saved and not), sign-in, "+"
  widgets/note_dialog.dart       new/edit note sheet: description, time, delete
android/app/src/main/kotlin/.../MainActivity.kt   forwards the sign-in deep link
                                                  and home screen "+" taps
android/app/src/main/kotlin/.../AddNoteWidget.kt  the home screen "+" widget
android/app/src/main/res/xml/shortcuts.xml         the "Add note" app shortcut
```
