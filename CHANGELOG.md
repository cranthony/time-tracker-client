# Changelog

Each release's version is in `pubspec.yaml` (the part before the `+`; CI
supplies the build number). Bump it in every pull request that changes the
app, following [semantic versioning](https://semver.org): patch for fixes,
minor for new features, major for changes that break something you rely
on. Add the new version's section here at the same time; CI checks both.




## 7.136.0

- The Diagnostics page has hotkeys: H and L go between its Server and
  App panes, J and K from graph to graph (outlined while highlighted;
  Home and End to the first and last), and = and - zoom the pane's
  graphs in and out.

## 7.135.0

- An event's actions can each take a share of it, as its goals can:
  minutes, or a percent of what the minutes leave. Tap the chip by an
  action in the event's Actions row to set it. An action with neither
  shares what's left evenly with the others given neither, so events
  whose actions have no shares count as they always have.
- A goal or action given minutes or a percent can take the rest too
  ("+r"): the box under the minutes or percent.
- A goal with neither now counts the rest of the event (what the other
  goals' minutes and percents leave), not the whole of it.
- The day's summary and the Plan page's time by action count each
  action's share, and so does a trait's duration of an action, by the
  same reckoning.
- An event isn't shortened below what its actions' minutes take, as it
  isn't below its goals'.
- Needs the server that keeps action shares to set them.

## 7.134.0

- On a goal's page, J and K go from sub-goal to sub-goal, not to the
  buttons over them or the history under them.
- J and K now work only where there are items to go through: the Plan
  page's panes, a goal's sub-goals, a menu, and the lists of the People,
  Travel times and Notes pages, of a page of events, and of a picker.
  Elsewhere -- in a dialog, say -- they do nothing, and Tab and
  Shift+Tab go from button to button.
- E edits what's being read, as its pencil does: on a goal's, habit's,
  person's or trait's page, as it already did a description.
- Home and End highlight the first and last item, wherever J and K go
  through items -- scrolling a long list to its start or end -- and on
  the Events page, the day's first and last event.
- In an event's dialog, J and K no longer go between its parts: Tab and
  Shift+Tab do.
- U goes up a level, as the back button does: from an editor to what
  it edits (with changes made, as Esc does), from a page -- a habit's,
  say -- to the one under it, and out of a dialog or menu. A field's
  letter is never U.
- Enter and Space press nothing in a pane of the Plan page swiped away
  from: what was highlighted there is let go.

## 7.133.0

- A strip across the top of every screen says when the metadata
  spreadsheet or the calendar was changed outside the server in the last
  week -- how many times, and when last -- and goes once the server says
  there were none. Tapping it lists each change, newest first: when, what
  (cells edited, a tab deleted, events changed), which tab, the cells as
  found and as the server put them back. The spreadsheet is the
  server's alone, so hand edits are put back. Needs the server that warns
  of them.

## 7.132.0

- + makes a new one of what's shown, as the page's or pane's + does: on
  the Plan page's Goals pane a goal, and on a goal's page a sub-goal; on
  its other panes an action or group, habit, person or location; on the
  People and Travel times pages, a person or circle, or a travel time.
  On the Events page, + does what C does, and on the Notes page what
  Ctrl+M does. Where two keys do the same, the list of hotkeys (?) and
  the hint while Ctrl is held give both: C / +, Ctrl+M / +.

## 7.131.1

- An event added in the app and changed or cancelled from a dialog
  opened while it was still saving is changed as saved. That change used
  to be refused for good, offering only Retry, which failed again, or
  Drop. A change still waiting from before, made this way, now says to
  drop it and make it again, without retrying it.

## 7.131.0

- S presses the Sign in button, where a page asks you to sign in.
- J and K go from item to item -- on the Plan page, from goal to goal,
  not through each goal's edit button, nor the buttons over the list
  (nor, on the Actions pane, the Priority colors link);
  in a dialog or menu, from row to row. Tab still goes to every button.
  With nothing highlighted, J starts at the first item in view (on the
  Goals pane, the first goal) and K at the last. With the item
  highlighted scrolled away, they go on from it, scrolling the next
  one into view.

## 7.130.0

- A goal can be marked missed: not reached, and no longer pursued.
  It's closed like a done one -- listed only when the filter shows
  missed goals, and reopenable -- and a goal's page offers it beside
  Mark done (and in its menu); what's still open under a goal can be
  missed with it. A required sub-goal that was missed doesn't hold up
  its parent being done. Needs the server that has missed goals.

## 7.129.0

- An event's goals can be added, changed and cleared while reviewing
  what a compaction says happened, in its dialog's Goals row, as on the
  calendar -- for a new event too. Before, a goals edit was refused until
  the proposal was confirmed. Needs the server that takes goals on
  amend_proposal's creates.

## 7.128.0

- When several of the things one change touches were changed elsewhere
  -- goals saved together, or events moved to make room -- each is
  shown in turn to resolve, field by field, and the change is saved once
  they all are. Before, only the first was found.
- "Keep mine" on a change made elsewhere saves yours over it, as before,
  now saying the version it's made over -- which the server now asks of
  every change.
- A change kept from an older version of the app, which didn't say which
  version it was made to, says the one last read when it's sent.
- Events made by a change that moves others to make room have ids of
  their own, so if the calendar stops that change partway, sending it
  again doesn't make them twice.

## 7.127.0

- Events can be tagged with goals: the event dialog has a Goals row,
  picked from the goals the way actions are, each picked goal's chip
  tapped to set how much of the event it takes -- all of it, some
  minutes, or a percentage of what the minutes leave. Tagging an event
  with an inactive goal offers to activate it from when the event starts.
- On the Events page, an event's goals are listed under its actions
  where there's room, and a goal icon -- two stacked, for more than one
  goal -- replaces its priority chip.
- The app won't shorten an event -- from its dialog, by moving it, or
  making room for another -- below the minutes its goals take: it says
  so, and the goals' shares can be changed first.

## 7.126.0

- Goals: a new pane on the Plan page, "Goals" (aim), first of the five,
  for outcomes you mean to reach and can mark done. It lists your top-level goals,
  soonest due first, each with its deadline and the time spent toward it
  against what you expect it to take; the summary splits the window's
  time by top-level goal. The tabs are narrower, so all five fit on a
  phone.
- A goal's page shows its path and how deep it is, its status, deadline,
  history, description and definition of done, and the goals under it,
  each opening a page of its own. Mark a goal done or obsolete and you
  pick what becomes of what's left open under it: done, obsolete, or
  moved, under another goal or a new one. Activating a goal activates the
  goals it's under; select several inactive sub-goals to activate them
  together, giving each a deadline (end of today, end of this week, a
  date, or its parent's). Moving a goal offers to make it fit its new
  parent, and deleting one warns if events are tagged with it.
- Descriptions and definitions of done are HTML, edited in a large box
  with a preview a swipe to the right.
- Goals are saved through the write queue like everything else, offline
  too, and checked against the server's rules before they're queued. A
  change to several goals at once -- closing a goal and what's left open
  under it, say -- is saved as one change, checked whole; if another
  device changed one of those goals meanwhile, only that goal's part
  waits for you to resolve it.

## 7.125.1

- Carrying over what an older version left waiting is safer still: with
  an older version's window still open on the web, a note it adds while
  the new one carries the rest over is kept, to be carried over next;
  and anything left waiting that can't be read stays where it was rather
  than being lost.

## 7.125.0

- A change to an event is made to the event as you saw it. One changed
  elsewhere since -- on the calendar, say -- is made to it as it is now
  when the two touch different fields; when they touch the same, it
  waits for you to pick, field by field, from the changes waiting. So
  is each event a change moves or cancels to make room for another: one
  changed elsewhere is resolved on its own, or dropped from the change
  while the rest is saved.
- A new event has its own id from the moment it's made, so it's made
  once however often it's sent.
- Every write is made once by what it names and the version it was made
  to, rather than by an id kept for each write.

## 7.124.0

- Notes save through the same queue as everything else: a new note has
  its own id from the moment it's written, so it's saved once however
  often it's sent, and keeps its id when its time changes. An edit is
  made to the note as you last saw it; one changed elsewhere since waits
  for you to resolve, from the bar at the foot of the page.
- Notes waiting to save from before the update carry over, so nothing
  waiting is lost.
- Cancelling a change the background task is sending at that moment is
  refused, as it should be, rather than said to be done.

## 7.123.0

- Actions, action groups and the priority colors save the way people
  and places do: each change is kept on the device and sent once, in
  order, and shows at once on every page. One changed elsewhere since is
  merged when it's to other fields, or waits for you to resolve, field by
  field, from the bar at the foot of the page.
- Action saves waiting from before the update carry over, so nothing
  waiting is lost.

## 7.122.0

- A refresh button beside the menu, on the Day, Plan and Notes pages,
  refreshes the page -- on Plan, the pane shown -- as pulling it down
  does, for refreshing with a mouse. It spins until it's done.

## 7.121.0

- The arrow keys scroll the Plan page's pane shown -- Locations, say --
  rather than the Actions pane kept beside it.
- "/" goes to the search box shown, what's in it selected, everywhere
  there's one: each Plan pane, the people list, travel times, and the
  pickers -- the search of the tab shown, in one with tabs.
- Dialogs, sheets and editors have a letter for each field, shown on it
  while Ctrl is held: a text field is focused, what's in it selected; a
  switch or checkbox flipped; a picker opened; a choice -- a status, a
  priority -- moved on to the next. Lists of like things -- parts,
  events to cancel, notes on each person -- go by number. In an event,
  P, C, T, R and N join W, L, D, A and S: its priority, commute, time,
  recurrence and notes. In these, Esc in a text field first leaves it,
  so the letters work; a second Esc closes, as before.
- Holding Ctrl no longer takes the cursor out of the text field it's in.

## 7.120.0

- With the app open in two windows on the web -- a browser tab and the
  installed app, say -- they take turns changing what's waiting to save,
  through the browser's own lock, so neither can write over a change the
  other just made. Before, a note added in one at the moment the other
  saved could be lost.

## 7.119.0

- Notes, actions and changes to events are made once each, too, however
  many times they're tried: each is sent with a write id the server
  keeps, so one sent again after its answer was lost -- a connection
  dropped as it was saved -- isn't made twice.
- A change joins a write still waiting only if that write hasn't been
  tried yet; otherwise it's a write of its own, after it, so a write that
  was made unheard can't hide it.

## 7.118.0

- Circles, location groups, travel times, habits, traits and the scoring
  defaults are saved through the same queue as people and locations:
  each change is kept on the device and sent once, so their dialogs
  close at once, offline too, and what you made shows straight away.
  Changed elsewhere meanwhile, they're merged or resolved the same way.

## 7.117.0

- A change waiting as "Changed elsewhere" is resolved from the list of
  changes waiting to save: Resolve shows each field both you and someone
  else changed, with their value and yours, to pick one or type another;
  the rest of your change is kept, and it's sent again on top of theirs.
  Deleted elsewhere, it can be put back with your changes, or they can be
  dropped; and deleting something changed elsewhere shows what changed,
  to delete it anyway or keep it.

## 7.116.0

- People and locations are saved through a queue kept on the device, as
  notes are: adding or changing one never waits on the server, so it
  works offline -- the dialog closes as soon as it's queued, and the
  person or location shows at once, with its id, ready to pick. Each
  change is sent once, however many times it's tried, and retried until
  it's saved; nothing waiting is dropped unless you drop it. A change
  naming something not saved yet -- an event at a location made offline
  -- waits for it.
- A change made to something changed elsewhere since -- by Claude, say --
  is merged with what changed there when they're to different fields.
  When they're to the same field, or it was deleted, it waits, marked
  "Changed elsewhere", for you to keep yours or drop it.

## 7.115.0

- On the Events page, T goes to now, as the button with the crosshair
  does.
- Wherever J and K don't already do something, they highlight the next
  and the previous thing to tap in what's on top -- the items of the ⋮
  menu, say, or a dialog's buttons -- and Enter taps it.

## 7.114.0

- Ctrl+Enter and Esc work the same in everything with text to save or
  throw away: an event, its description, a note for Claude, the notes on
  what happened, an action, a person or a location, an event's
  properties, and a habit's or trait's page. Ctrl+Enter saves and closes;
  Esc closes at once if nothing changed, but with changes made the first
  Esc shakes the screen and says "Press Esc again to discard your
  changes", and only a second, soon after, discards them. In a text field,
  Esc counts at once -- except in an event, where the first leaves the
  summary's field, for its letter keys.
- A description being read: E edits it.
- In an event, Delete does what its trash can does.
- Ctrl+B, then S, opens the ⋮ menu.
- The up and down arrow keys scroll whatever's on top -- a page, a dialog
  (the list of hotkeys, say) or a sheet -- not only the Events timeline.
- On the Plan page, J and K go down and up the pane shown, highlighting
  what can be opened, and Enter opens it; H and L go to the pane on the
  left or right.

## 7.113.0

- Hotkeys in an event. J and K go between its parts, and Enter opens the
  one highlighted. W opens who it was with, L where it was, D its
  description and A its actions; S opens its summary with the text
  selected, to type over. Ctrl+Enter saves. Esc closes it, but with
  changes made the first Esc shakes it, saying so, and only the second
  discards them. In a list to pick from, / goes to its search.

## 7.112.0

- An event to push that the new or moved event covers part of is split at
  the box's edge: the part outside the box, on the side it isn't pushed
  to, stays where it is, and the rest is pushed whole. Pushing down an
  event the cursor was dropped in the middle of now saves it split, as it
  showed, instead of pushing all of it.
- The part split off is the same event as the one it came from, but for
  its id and times: its judgments, and whether its actions come from its
  label, are copied too.

## 7.111.0

- Hotkeys on the Events page. J and K highlight the next event and the
  one before, starting from the one happening now and going on to the
  next day or the one before past the day's last or first; Enter opens
  the one highlighted, and Esc lets it go. H and L go a day back and on.
  The up and down arrow keys scroll the timeline, by an hour, or as much
  as Settings' new Keyboard section says. C makes an event, its cursor at
  the end of the event highlighted, or at now: J and K move the cursor,
  Enter sets the start, J and K then move the end, and Enter goes on, as
  ✓ does. Esc leaves it, as ✕ does.

## 7.110.0

- Hotkeys, on the web or with a keyboard plugged in. Ctrl+M writes a
  note over whatever's open, and closing it goes back there. Ctrl+B, then
  N, E or P -- Ctrl let go first -- goes to Notes, to Events at now, or to
  Plan; while a dialog is open the screen shakes instead, so it's saved or
  discarded first. Ctrl+Enter saves the note being written. Esc leaves a
  text field. Hold Ctrl to see the hotkeys on the buttons they stand for,
  and press ? -- or pick Hotkeys from the menu -- for the list of them.

## 7.109.1

- A location a compaction makes -- as it's applied, or as you or Claude
  settle what it adds -- is named on its events at once, not shown by its
  id until the Events page is opened again. People and actions it makes
  are named at once too.

## 7.109.0

- A note under a proposal's bar shows all of its text, not just its first
  two lines. The panels above the timeline scroll once they fill half the
  page, so a long note can't push the timeline out of view.

## 7.108.0

- A habit's page shows what it's built on -- the habits and people under
  it on the habit graph -- below what it's for, as its editor does. Until
  now that was only seen while editing it.

## 7.107.0

- A description, where it's read in full -- its sheet, and a Google
  Calendar event's -- can have its text selected by touching and holding
  it, to copy.

## 7.106.0

- An event too short or too narrow to list its locations down its right
  shows them on its summary's line instead, before its diamonds. Its
  summary keeps at least half the line; a location cut short ends in an
  ellipsis, and the event's priority chip makes way for it.

## 7.105.0

- A new event starts at the place of the event before it. If that was a
  commute, or had no place, it starts at the place of the event after
  that one instead, unless that's a commute too. Logged from Google
  Calendar with a location of its own, it keeps that instead.

## 7.104.2

- Scrolled to the foot of the timeline, an event drawn on past midnight
  is clear of the buttons there: the room below the timeline grows by
  as far as it's drawn past.

## 7.104.1

- An event drawn past midnight at the foot of the timeline, pushed down
  by those above it, can be tapped to open it, as far as it's drawn.
  Without one, taps below midnight do what they did.

## 7.104.0

- Moving an event, the commute button shows at each end unless the event
  next to it is at the same place; an event with no place counts as an
  unknown one. It opens "Edit commute from … to …", listing every way to
  commute, each with the time the travel times give it and which travel
  time that is.
- Picking a way opens its summary and how long it takes, with where it
  goes and the expected time above. It edits the commute already there,
  past events at the same place, keeping its other actions and its own
  summary, and pushes it with the move; or it makes a new one against
  the event. "No commute" takes the commute there away.
- "A way to commute" in an action's dialog now says events with a
  commute are pushed with the events they lead to or from.

## 7.103.1

- On a small phone, the panels over the day's timeline -- its summary,
  weather, all-day events and Claude's proposal -- take at most half the
  page, scrolling within it past that, so the timeline always has room,
  and an event shown from the home-screen widget is in view.

## 7.103.0

- An event's description opens to read first, laid out as Google
  Calendar writes it, its links tappable; the pencil at the foot of the
  sheet edits it. A blank one is edited at once.
- The event dialog's description row shows it the same way, in smaller
  text, cut off with a fade when it's long.

## 7.102.1

- Swiping quickly across the Plan screen's panes no longer drops you
  back on Habits. Its list scrolling to where it opens was swiping the
  panes back to it too.

## 7.102.0

- The Travel times page has a search, which has the keyboard as soon as
  the page opens: it narrows the list by the places a travel time is
  between, its ways of getting there, and its note.

## 7.101.2

- In the actions list, an action that's a way to commute has a walking
  person for its icon instead of the plow.

## 7.101.1

- In the travel time editor, the action a way is by is marked with the
  commute icon, the walking person, instead of the directions sign.

## 7.101.0

- The timeline snaps to 5 minutes by default, instead of 15. A grid
  already picked in Settings is kept.

## 7.100.3

- The weather strip's line for a day gives its chance of rain whenever
  there's any, not only from 10%.

## 7.100.2

- Making an event repeat, changing how it repeats, or stopping it now
  shows the series' later events on the days after at once. Before,
  days already loaded kept showing what they had until they were
  reloaded by hand.

## 7.100.1

- Commutes are shown with a walking person instead of the bus and car,
  wherever their icon appears.

## 7.100.0

- Every picker of actions, people, habits and locations is now the same
  sheet, up from the foot of the screen, with the keyboard up to search
  at once -- what's typed already, if anything, selected to type over.
  Picking one action (an action's group, a habit's action, a keep rule's
  action) and picking what a habit or person is built on were dialogs;
  they're sheets now, as an event's actions are.
- Each picker starts with every group open, so what's in them is to
  hand: the action groups when picking how a travel time goes ("By"),
  say. Each group's arrow still closes it.
- Editing an event's actions in its Details opens the sheet at once.

## 7.99.0

- Notes being written are kept as drafts. What's typed in the note sheet
  is kept on the device as it's typed, so swiping the sheet away,
  switching pages or closing the app loses nothing. Drafts show on the
  Notes page at their time, dashed and in italics, and aren't sent until
  they're added; tap one to carry on with it, or use the sheet's trash
  can to throw it away. An edit you haven't saved is kept as a draft
  change, in its note's place.
- Edits and deletions of notes are queued on the device before the sheet
  closes, as new notes are, and retried until the server has them. They
  show on their notes until they're saved (a deletion struck through),
  and one the server refuses, for a note already compacted, waits to be
  cancelled. Undo on a deletion takes it back while it waits.

## 7.98.0

- An event's map location can be given to a location, from the Map
  location page of its location sheet: "Assign to a location" opens a
  picker over the sheet. Tapping a location with no map location gives it
  this one at once; one with another opens its dialog, the new one in its
  map location, the old under it, to save or not. Or a new location is
  made, named as it's typed, with this map location. Either way the event
  is at that location after, with no map location of its own.

## 7.97.1

- A note added from the New note sheet can't be dropped any more. The
  sheet keeps the note on the device itself before it closes, rather
  than leaving that to the Notes page, which lost it if it was gone by
  then: switched to Events by a tap on the home screen calendar, say.
  If the note can't be kept, the sheet stays open with it, saying so, to
  try again; and a note that wasn't kept no longer shows as waiting.

## 7.97.0

- The home screen calendar's title ("Calendar", and its "+") can be at
  its bottom instead of its top: long-press the widget and open its
  settings (on Android 12 and later; before, as it's added). Each widget
  keeps its own.

## 7.96.0

- In an event's details, a location with a map button sits level with
  its pin, its row no taller than the others. The button has the row's
  full height to be tapped in.

## 7.95.0

- The Events page's weather bar shows the temperature, in the units
  chosen. Where the forecast is by the hour, a label goes every third
  hour from a quarter hour after the forecast was fetched, so the first
  is soon after now. They hold still till it's fetched again, staying as
  now passes them, as today's sunrise does; then they fade out, and back
  in where they now go. Further out, there's one label in each part of
  the day. Where the chance of rain is labeled at the same time, the
  temperature is just below it.

## 7.94.0

- The weather's place given by latitude and longitude is easier to set
  and check: "Paste coordinates" fills both from what a maps app copied
  ("47.6062, -122.3321", or "47.6062° N, 122.3321° W"), and pasting that
  into either field splits it across both. Once both are a place, "Open
  in maps" shows it in a maps app.

## 7.93.1

- The Background updates page has the weather first, then everything
  else under a "Time Tracker" heading.

## 7.93.0

- The home screen calendar gives each day's weather in its header, while
  the weather's on: the chance of rain whenever there's any, the high
  and low, and the sky's icon -- today's chance, high and low being
  what's left of it. It's redrawn with each forecast, the background's every 15
  minutes among them. Too narrow for all of it, the days are named
  shorter, then the high and low are left out.

## 7.92.0

- The Events page's weather bar marks sunrise and sunset, from the
  forecast: an orange badge across the bar, the sun on the horizon, with
  its time beside it in orange after an arrow up or down. Today's are
  marked even once they're past; days past and beyond the forecast have
  none.

## 7.91.0

- An event's dialog has a Commute chip next to its priority: filled when
  the event is part of a commute, outlined and faded when it isn't.
  Tapping it opens a switch, "This event is part of a commute".

## 7.90.0

- Turned on, the weather's for a place given by its latitude and
  longitude, to start: turning it on no longer asks where the device
  is. Its location is asked for only if "Where this device is" is
  picked, now under the place in Settings. Weather already on for where
  the device is stays so.

## 7.89.0

- The weather's fetched in the background every 15 minutes, to start:
  a new choice on the Background updates page, and Android's shortest.

## 7.88.0

- The weather, from Open-Meteo, where the device is or for a latitude
  and longitude given. Turned on in Settings -- the location's asked
  for only if it's for where the device is -- a strip over the
  Events page's timeline gives the day's sky, high and low and chance
  of rain; today, whether rain's coming in the next three hours; and
  the week's days, to go to. The band beside the timeline shows the
  weather from now on in place of the priorities: the sky's color, and
  a blue bar as wide as rain's likely, labeled with the chance. It's as
  precise as a forecast can be: by the quarter hour, then the hour, then
  parts of days, then whole days. Units (°F or °C, inches or
  millimeters) are in Settings.
- The forecast is kept on the device, shown at once as the app opens,
  and fetched in the background on Android -- every hour, or as the
  Background updates page sets -- for where the device was last found
  while the app was open: never asking for its location there.

## 7.87.0

- An action can be a way to commute -- getting from one place to
  another, such as Drive or Walk -- switched on in its dialog. A travel
  time's "By" offers only those, and the groups they're in, plus whatever
  it was already by. Needs a server that keeps an action's commute.

## 7.86.0

- A location's or location group's travel times, in its edit dialog from
  the Locations pane: each one to or from it, tapped to edit, and "Add
  travel time", which picks the other place and opens the travel time
  both ways between them (the one there is, or a new one).
- The travel time editor has a button between From and To that switches
  them round.

## 7.85.0

- A person's page and a habit's share their health, Traits, Events and
  Cancelled sections, their headings and their pencil, so the two stay
  alike. Nothing on either page looks or reads differently.

## 7.84.0

- Tapping an action or group in the Actions pane, or "Edit" in its menu,
  opens it ready to edit, as a location does: its name, the group it's
  in, its status (an action's), priority, color and note, each said
  where it's inherited from. "Details", and tapping a value before
  editing it, are gone. Adding an action or group uses the same dialog.

## 7.83.0

- Editing a person or a habit, how their traits combine is above the
  traits, not below them, and edited with a sigma in place of the tuner
  -- as is every "how they combine". Their page says in brief how the
  traits combine: their own way, or the defaults'.
- A habit's page shows its events and its cancelled events in brief, as
  a person's does -- how many, their time, the most recent and the
  oldest -- with "All events" and "All cancelled events" opening the
  lot. Pulling it down loads the events again, as on a person's page.

## 7.82.0

- On the Events page, a commute has a small icon before its summary.
- Where there's room, each event lists down its right the locations it
  was at, the people with the user, and those it was for, each after its
  own icon -- a dotted outline for those it was for -- side by side
  while they fit: as many lines as the card has room for, and none on a
  card too narrow for them.

## 7.81.0

- Commutes. Moving an event that has a location, a commute button shows
  outside the "−" and "+" at an end of the box, when the nearest event
  that way is at another place. It offers the ways the travel times have
  of getting between them (actions, by their own time or their group's),
  each with how long it takes: a range taken at its middle, rounded up to
  five minutes. With none yet, or to add another, "Add a travel time…"
  opens one from there to there, then offers it. The one picked is made with the
  move, against the box's edge, and rides with it as the box changes,
  trimming what it runs into; tapped again, the button takes it away.
- A commute is marked as one on the event (its facts' commute), not
  known by its action, so a walk for its own sake is never taken for
  one. A commute right before or after an event that's moved starts out
  pushed up or down with it.

## 7.80.0

- The Plan page's Actions pane is laid out as the Locations pane is:
  each action and group indented under its group, after a plow or a
  folder in its color -- filled where the color is set on it, outlined
  where it's inherited -- in place of the colored bands. Groups are
  always open, and tapping one edits it, as tapping an action does.
- Its summary's first page is "By action", not "Visible actions".

## 7.79.0

- One picker everywhere: a location or group's "Inside", and a travel
  time's "From", "To" and "By", open the sheet the Events page picks
  actions, people and locations in -- searched (with "Any"), and browsed
  as a tree of folders -- where tapping one picks it. A group is picked
  with a tap too; its arrow opens it.
- An event's Location page shows the location groups as folders, as its
  Actions page does the action groups.

## 7.78.2

- An event's location is read only as a list (`location_ids`), as the
  server now sends it; the single `location_id` from before is gone.

## 7.78.1

- Habits pane: a person's trend sparkline is now in red, yellow and green,
  as a habit's is. The People pane and a person's page keep their gray to
  green.

## 7.78.0

- Travel times: roughly how long it takes to get between two places --
  locations, or location groups such as a neighborhood -- by each way of
  getting there, such as Drive or Transit (any action or action group).
  The Locations pane's commute button lists them. Each way's time is set
  in hours and minutes as other durations are, with an "Up to" for one
  that varies. A travel time counts both ways unless it's set to one way,
  so the way back can have its own.

## 7.77.0

- Locations can be grouped: by neighborhood, by city, and so on. The
  Locations pane's folder button adds a group, which can sit inside
  another. A location's editor picks the group it's in. The pane shows
  each group with what's in it indented under it; tapping one edits or
  deletes it, and deleting one moves what was in it up a level.
- Searching the locations, and picking an event's location, shows the
  groups each one is in beside its hint.

## 7.76.0

- An event can be at several locations, when it moved between them: the
  Location page picks as many as it was at, as With and For pick people,
  and the event shows each ("Home, The park"). Time by location counts
  each, and an event with no map location of its own opens the first of
  its locations' that has one.

## 7.75.0

- Picking an event's actions, people and location is quicker:
  - The search starts with the event's summary, selected, with the
    keyboard up, so you can type over it or pick from what it finds.
  - An "Any" toggle beside each search shows what matches any word typed,
    the best matches first, rather than only what matches every word.
  - Tapping anywhere on an action group opens or closes it.
  - "Add action", "Add person" and "Add location" open the usual editor,
    named as you searched, and pick what's added.
  - Long-pressing an action, group, person or location edits it.
  - Swiping between With and For, or to Map location, puts the keyboard
    in that page's box, its text selected; each keeps what you typed.

## 7.74.0

- A location can have a map location: an address, a place's name or a
  link, set where it's added or edited. An event there with no map
  location of its own still gets the map (or arrow) button, which opens
  its location's; one with its own opens that, as before. On the event's
  Map location page, the location's shows as a hint.

## 7.73.1

- "Scoring defaults" is in Settings now, saying what each default is,
  rather than under the traits.
- A scoring page starts from what's in effect without its own: a habit
  layer's from the lowest score -- the 0th percentile -- and a person's,
  habit's or circle's from the defaults', rather than from the mean. Saved
  as it starts, it goes on following the default.

## 7.73.0

- How scores combine is edited in the app. A judgment part's card says
  how to aggregate its judgments: by event or by time, the mean
  or a percentile, and only the best, worst or most recent few events --
  or, by time, hours, entered as a duration.
- A trait's page edits how its parts combine, each part's weight among
  it; a person's or habit's traits, how their traits combine and, trait
  by trait, how its parts do for them; a circle, how its people do. Each
  says what's used without one, and "Reset to default" goes back to
  it.
- "Scoring defaults", under the traits, sets them for everyone: a
  person's or habit's traits, a circle's people, and a habit layer.
- The sample data weighs Thoughtful's judgment twice, and scores
  Present's judgments by their events' time.

## 7.72.0

- A proposal that no longer plans against the calendar -- because
  something it decided about was changed or deleted since -- goes on
  showing its events as it last planned, rather than the calendar under
  it, with a line under its bar saying so. Why it no longer plans is
  still said at the foot of the page. The app keeps them from run to run.
- A proposal's menu can hide it, to show the calendar under it ("Hide
  proposal"), and show it again. Hidden while it no longer plans, the
  calendar can be changed directly, to fix what it no longer fits: once
  it plans again, it's shown again by itself. Hidden while it plans, the
  calendar is there to look at, but not to change.
- A proposal whose apply stopped partway no longer says at the foot of
  the page that it no longer fits the calendar: its bar says to retry.
  It's shown as it's being applied, and hidden, the calendar under it
  can be looked at but not changed, so nothing changes under the apply.

## 7.71.0

- Scores combine as the server's new scoring settings say. A judgment
  part can weigh each judgment by its event's time and take a
  percentile, or only the best, worst or most recent few events or
  hours; a trait, a person's or habit's traits, and a circle can each
  set how theirs combine -- weights, a percentile, only the best or
  worst few, a cap while any is low, a score for what isn't rated --
  with the scoring defaults for the rest. Without any, nothing changes:
  the mean, and a habit layer's lowest.
- A part's weight is its trait's now, kept by the part's id, so the
  Weight field has left the parts editor; a trait's page still shows
  each part's weight, and how its parts combine.
- Editing parts keeps each one's id, so its judgments stay with it, and
  a judgment's lookback and scoring, which the editor doesn't show.
- The defaults are loaded with the traits; a server from before them
  has none.

## 7.70.1

- Once a proposal is confirmed and applied -- here, or by the background
  task -- each of its days goes on showing what it said happened until
  that day has been loaded again, rather than flashing back to the
  calendar as it was before the apply.

## 7.70.0

- A number-of-events or time-spent part says what happens when you're
  short of its target: "Partial credit" (35h of 40h scores 88) or "Fade
  when missed" -- no partial credit, falling from 100 to 0 over the days
  you give it after the target was last met. That replaces the bare
  "Zero at, in days" field, and a part's one-line description says
  when it fades.
- Every part in the parts editor -- for a habit, a person or a trait --
  ends with its score as it stands: "Yesterday: 0 · 35h of 40h in the
  last 7 days; not met in the last 14 days", and, for one that fades,
  what partial credit would score. A trait's parts are scored for you.

## 7.69.2

- While an event is being moved, the red "overlap" tint where it was
  goes away: the faded event left behind no longer counts as
  overlapping anything. It comes back if the move is called off.

## 7.69.1

- Why a compaction proposal can't be confirmed any more is said in the
  status bar at the foot of the page, as other errors are -- tap it for
  the whole message -- instead of under the proposal's bar, where a long
  one pushed the calendar out of view.

## 7.69.0

- The web app can be built with a relative `MCP_URL`, such as `/mcp`,
  for a server on its own origin: it's resolved against the page's
  address. The Android and Windows apps refuse one at startup, saying
  why.
- The web build's Content-Security-Policy tool takes a relative
  `MCP_URL` too, and a server without sign-in, which has no
  protected-resource metadata.

## 7.68.0

- The app connects to the server before it signs in, and asks you to sign
  in only when the server wants it. A server built without sign-in
  (`AUTH_DISABLED`) is used as it is, with the amber strip, About and
  Settings saying so, and no Sign out.
- So there's no longer a build of the app without sign-in:
  `DISABLE_AUTH` is gone, and the same build works with either server.

## 7.67.1

- The app knows a server skips sign-in by the flag in its handshake
  (`_meta`'s `time-tracking/authDisabled`), not by its wording, which may
  change.

## 7.67.0

- A build without sign-in, for a corporate network whose proxy signs
  people in (`--dart-define=DISABLE_AUTH=true`): it never signs in and
  sends the server no token. An amber strip across the top of every
  screen says so, as do its title and About ("Time Tracker (no
  sign-in)") and Settings; a server that still wants a token is
  explained rather than asked to sign in to.
- The app shows the same strip when the server it connects to says it
  skips sign-in.

## 7.66.1

- Tapping an event on the home screen calendar with the app closed opens
  Events on the event's day, as it does with the app open, rather than
  on today. The event's near the top, where it stays in view as the page
  finishes loading.

## 7.66.0

- The Habits pane is a graph: each habit can be built on others, and on
  people. Layer 0, at the bottom, has what's built on nothing; each
  layer above, what's built on those below. Each habit is a chip in its
  action's color, with its trend, its consistency and its star; each
  layer has a trend of its lowest ratings. Hold a chip to pick what it's
  built on, or archive it; a habit's editor picks them too.
- People can be on the graph: the person button puts them there, built
  on habits and other people, and holding one takes them off.
- By default it shows only what's unlocked -- what has every foundation
  on track, or not rated yet -- saying how many more wait; the lock
  shows them all. The search marks what matches and shows what it's
  built on. It opens at the highest layer on track with everything
  below it.
- Consistency: how many days in a row a habit has been on track, or a
  relationship healthy, under its rating -- "1d", "7d", up to ">30d".
- A new kind of trait part, spacing: never too long between events of
  an action -- meals, say -- with exceptions, like sleep, that stop the
  clock and can set the time left after them.

## 7.65.0

- An event that doesn't repeat says "No recurrence" in its summary, and a
  new event does too. Tapped, it opens the same editor a series has,
  starting weekly on the event's day, to make it the first event of a
  series; "Don't repeat" takes that back before it's saved.

## 7.64.0

- An event's map location that's just a web link -- to a map, or a
  video call -- has an arrow by it instead of the map button, and opens
  the link itself rather than searching for it in a maps app.
- A Google Calendar event's sheet has the same button by its location,
  when it has one.

## 7.63.0

- Google Calendar events on the Events page (Android): turned on in
  Settings, which asks for the calendar permission, they're read from
  the phone -- never sent to the server -- from the Google calendars
  picked there, by account, each account's own to start with. Refused,
  only this is off, and Settings says so, offering the app's Android
  settings if it's refused for good.
- On the timeline they're drawn faintly behind your own events, a strip
  at its right edge marking each; a button beside "now" brings them over
  your events instead. All-day events are pills in a strip over the
  timeline, folded to a line if you like.
- Tapped, one shows its time, location, calendar and description (its
  HTML drawn, links tappable), with **Open in Calendar**, and **Log
  this**, which starts a new event at its times with its title,
  description and location.
- An event's location sheet has a second page, **Map location**: where
  it was, as a maps app would find it. With one, a map button by the
  event's location opens it in your default maps app.
- The location list picks with radio buttons: only one can be picked.
- An event being moved, drawn faintly where it was, no longer shows
  what's behind it.

## 7.62.0

- The pending event box, and its "+" buttons, are moved by pressing and
  holding them for a moment, then dragging -- with a buzz, and the box
  lifted while it's held. A quick swipe over them scrolls the timeline
  instead of moving them. Tapping a "+" still stretches the box a step;
  the handles at the right of its lines still drag at once.

## 7.61.0

- Diagnostics: the median, p95 and max lines across the tool calls'
  graphs say whose call each falls on -- "Max · confirm_proposal ·
  5.0 s" -- even with all the tools shown. A median halfway between
  two calls names both their tools; a value several tools' calls share,
  as timeouts do, names them all, the commonest first -- as many as
  fit across, and how many more. The mean, which is no one call's,
  still says which tools are shown.
- Lines that fall together, as p95 and max often do, are labelled once
  ("p95, Max · ..."), and the median's label sits under its line, clear
  of the mean's.

## 7.60.1

- Tapping the home screen calendar's "Today" or its title while the
  app is open no longer leaves it a blank grey screen.
- Tests for the home screen calendar: on an Android emulator, that it
  shows the events and that tapping an event, a day or its "+" opens
  the app where it should; and that each tap shows the right day, and
  event, on the Events page. Builds for that test (with
  `--dart-define=CALENDAR_PIN=true`) offer to add the calendar to the
  home screen from the app's menu; others don't.

## 7.60.0

- Diagnostics: the tool calls' and the server's memory graphs draw each
  sample as a dot, no longer joined by lines -- they come in bursts with
  long gaps between, which the lines drew across. Dashed lines mark the
  mean, median, p95 and max across each, labelled with which it is, the
  tools shown, and its value.

## 7.59.0

- When Notes, Events or Plan can't load, it tries again by itself --
  after 5s, 10s, 20s, 40s, then every minute -- until it loads.
- With what was loaded before still shown, it no longer says so over
  the page: the line at the foot of the screen does ("Couldn't load
  events: trying again at 9:42 AM"), and tapping it says why, to try
  again now. With nothing to show, the page still says so, and when
  it'll try again.

## 7.58.0

- The home screen "+" is drawn the same way as the calendar now (with
  Glance); it looks and works as before, and the buttons already on
  your home screen stay.

## 7.57.0

- Answering a point Claude isn't sure of quotes it in the note for
  Claude, so Claude reads which doubt it answers, and the app shows the
  answer under that point -- in the strip ("you answered: waiting for
  Claude") and in the whole recap, with Claude's reply. Other notes for
  Claude follow the recap's points, under "Notes for Claude", and the
  Claude page counts those waiting for Claude.
- "Notes for Claude" is their name everywhere, the menu included, so
  "Notes" is only ever your own.

## 7.56.0

- Actions and notes waiting to save now show in the line at the foot of
  the screen too, as event changes do: saving, waiting to try again, or
  stopped at one the server refused (in red, "tap to fix it"). Tapping
  it slides up each, by name, with why it couldn't be saved, to try
  again or drop.
- Plan no longer pops up an error when an action couldn't be saved: the
  line at the foot of the screen says so, and the action's row still
  shows it, to try again, edit or discard.
- The sheet's event changes are headed "Events waiting to save", apart
  from the actions and notes.

## 7.55.0

- The compaction proposal's bar is one row, over its details as one
  block: its time and revision, "Confirm", a button for a note for
  Claude, and a menu with its notes, "Go to it" and "Abandon it". What
  changed since you looked shows by its revision; what's out of the
  ordinary -- waiting for Claude, waiting to save, stopped partway, no
  longer fitting -- still gets a line of its own under it.

## 7.54.1

- Under the hood: the line at the foot of the screen, and the sheet it
  slides up, are no longer just the event changes': anything the app
  keeps you posted on can say something there, the most pressing first.
  Nothing looks different yet.

## 7.54.0

- The Plan page has a Habits pane ("build") where the Traits pane was: every one
  of your habits, in its action's color, with its action or group, its
  health and its last 8 days. Starred habits come first. Tap one to open
  it, use its menu to archive or restore it, and "+" to add one. Search
  finds habits by name, action and note, and archived habits show only
  when asked for. Above the list, the time in the summary's window: by
  habit, and by each habit's health (on track, needing attention, off
  track, not scored yet), with the rest as "No habit".
- The traits are now under Self in the People pane, with everything the
  Traits pane had except its search: scores and trends, each trait's
  menu, "Trait" to add one, and archived traits on request. Self's
  "All habits and scores" button is now a person icon in Self's head,
  beside their health: it opens your page, folded away or not.
- Self's page no longer lists habits: they're in the Habits pane.

## 7.53.1

- Claude's recap: tapping a point opens the whole recap, and the button
  beside it is gone, leaving the point more of the row.

## 7.53.0

- A home screen calendar for Android: your events from now to the next
  few days, under a header for each day. It always starts at now:
  what's over drops off as it ends, the event that's on is in bold, and
  it's kept up to date as the app or its background fetch gets the
  events. Tapping an event opens Events on it; tapping a day, that day;
  tapping the header, now. Its "+" adds a note, like the "+" widget.

## 7.52.0

- Claude's recap of a compaction proposal: what it did, and what it isn't
  sure of, in its own words -- bold, lists and all -- after a short
  overview. It's the first page under the proposal's bar, stepped
  through point by point, the events each point names outlined on the
  timeline and the notes it names marked; the button beside a point
  opens the whole recap, where each event and note it names is a chip
  that goes straight to it, and a point Claude isn't sure of can be
  answered in a note for Claude. A point about something you've changed
  since Claude wrote it says so.

## 7.51.1

- Events: "Go to now" puts now a fifth of the way down the screen,
  not a third, so more of what's ahead shows.

## 7.51.0

- What the background fetch keeps shows as soon as you're back in the
  app: the server's answers are each kept apart and read afresh, so the
  app sees what the fetch kept -- the proposal, say -- even while it's
  been running all along, and neither puts back an older answer over the
  other's. Back in the app, the Events page shows the proposal fetched
  meanwhile at once, while it asks the server again.
- An action renamed, approved or otherwise changed shows so on every
  page as soon as it's saved -- the Events page included, which kept the
  actions as it last fetched them -- and confirming a proposal fetches
  the actions again, with any it made or approved.

## 7.50.0

- A compaction proposal leaves the Events page as soon as it's confirmed
  and applied -- or abandoned -- and doesn't come back: a load asked for
  before it went through, answering with it still open, no longer shows
  it again. Gone as the banner says so, even when the background task
  confirmed it; and the proposal kept for next time is forgotten, so it
  isn't shown again as the app opens.

## 7.49.0

- Diagnostics' App pane says how many errors there are and shows the
  newest; **See all** opens the list on a page of its own, each still
  opened to read in full and copy.
- Slow frames aren't recorded while Diagnostics is open: its own graphs,
  drawn again as each frame was recorded, recorded more, on and on -- the
  graph filling with them at its right edge, jittering.
- Opening or closing an action group no longer builds every row again:
  each row is kept by its action, and one that shows nothing new isn't
  built again at all.

## 7.48.0

- Plan's Actions, Traits and People panes open faster, and don't freeze
  while they load:
  - The trait scores are worked out off the UI thread, on another
    isolate (on the web, in a task of their own), and only when what
    they're from changes -- not each time the traits, people, actions,
    habits or a day's events are loaded again, alike. Meanwhile the panes
    show them as they were, with the thin bar along the top.
  - The events kept change version only when a day's events do.
  - The time on actions is split once for the summary and the rows, and
    only when the window, events, actions or statuses shown change; the
    Actions pane is built only while it's shown, and the actions shown
    worked out once per change.
  - The People pane measures everyone's time once, not once a person;
    the Traits pane gathers its scores once, not once a trait.
  - Splitting time among events sweeps through them in order, rather
    than looking at every event for every stretch.

## 7.47.0

- Diagnostics' App pane times the app's own work on the device, to find
  what makes Plan slow: its **slow frames** (over 16 ms, those while Plan
  is open apart, freezes over 100 ms red), each **visit to Plan** from
  opening to loaded -- the trait scores, the time on actions and people,
  and the page's rebuilds, each its own, under the time spent waiting --
  and each kind of **work on the device**, with why the trait scores were
  worked out again each time.

## 7.46.0

- An event on the Events page shows its actions' diamonds, overlapping
  in their colors, by its length and priority chips at the top right.
  Below its summary it lists as many of its actions' names as its time
  leaves room for -- an event is no longer drawn taller to fit them
  all.
- Settings picks the snap grid from a menu, in place of radio buttons.

## 7.45.0

- The Events page's list buttons -- Keep, Push up, Push down and Cancel
  -- are tucked behind a checklist button beside go-to-new, with a dot
  while any list has events; it brings them out above ✕ and ✓, shaded
  while they're out, and they tuck away again when picking for one
  ends, and each time a box comes up.
- With just the one cursor placed, ✓ cancels the events in the Cancel
  list, asked as ever which count against follow-through ("Cancel an
  event?", not "to make room": nothing's made). It no longer splits the
  event the cursor is in; making an event over part of one does that
  job, and a box's first cursor still splits what it's placed in.
- Go to now sits flush right, where go-to-new is with a box up.

## 7.44.0

- An edit of the proposal that changes what an earlier compaction
  recorded -- sleeping in past a confirmed morning, say, pushing the
  start of what came next -- asks "Change history?" first, rather than
  being refused. Approved, it's sent with the server's
  `allow_compacted_changes`, which keeps to it in every revision after.
  One the app couldn't tell, refused, offers **Change history** from the
  changes waiting. Needs the server's `amend_proposal`
  `allow_compacted_changes`.

## 7.43.0

- Diagnostics' **App** pane: the app's own health, recorded on the device,
  by the app and its background task both. Its tool calls -- each one's
  whole time, retries and the network included, a line for the app's and
  one for the background task's, failed ones dotted red, the last 100 of
  each tool kept -- filtered and summed up as the server's are; how many
  changes waited to save in each outbox, stacked, over time; and the last
  20 errors, in full, to copy: failed calls, and errors the app didn't
  catch, with where.
- Diagnostics' zoom buttons keep the latest in view, on the right, rather
  than the middle.
- Fixed: what the background task's changes to the proposal came to was
  only said once the app had gone to the background and come back, not
  as soon as it came back.

## 7.42.0

- **Diagnostics**, in the ⋮ menu: the server's health, from its
  `get_health`. Graphs of its tool calls -- each one's own work, with
  auth and transport stacked on top, failed calls dotted red -- its
  memory, and its restarts, over the last day, week or everything, the
  latest on the right. Pick which tools' calls (reads, writes, an area,
  one tool), and each call or the mean, median, 95th percentile or max
  of each 15 minutes, hour, 6 hours or day; each graph sums up what's in
  view. Pinch, or tap the buttons, to zoom all three in together, in
  time; scrolling scrolls the page. An **App**
  pane, swiped to, is for the app's own metrics, later.

## 7.41.0

- Fixed: changes waiting to save could be lost, or sent twice, when the
  app and its Android background task were both at them -- the app
  coming back while the task ran, say. Each wrote what's kept on the
  device whole, from what it had read, overwriting what the other had
  written meanwhile: a change just made, or one's claim to be sending
  one. Now each change to what's kept holds a lock both share, and a
  change waiting is claimed for sending only if no one else has it.
- Sent again after an attempt nobody heard back from, a cancel isn't
  refused as made already, nor is an event a move splits off, or one an
  edit of the proposal creates, made twice.
- A sender that took too long to hear back, its change since claimed by
  the other, leaves it to the other.
- The app and the background task take turns: neither takes a change to
  send while the other's sending one, of notes, actions or events.
- A change being sent says who's sending it -- "Sending, by the
  background task…" -- in the changes waiting, and on the notes page.

## 7.40.0

- What a new or moved event's Keep list starts with is set in Settings,
  as rules: historical events -- every one that ended by the last
  compaction, kept unless told otherwise -- or the last of them; and
  the previous or next event, from the cursor (or the event moved),
  with an action or one in a group: "Next event with Sleep", say. Never
  the event the cursor's in, nor the one being moved.

## 7.39.0

- A new or moved event's box always trims the events in its way --
  splitting the one its cursor was placed in -- unless they're in a
  list, which take the place of its modes. Beside ✕ and ✓: **Keep**,
  **Push up** over **Push down**, and **Cancel**, each with a dot while
  it has events. Tap one to pick events for it -- any on the timeline,
  the days either side too -- each tap picking or unpicking one, ringed
  and marked with the list's icon; ✓ keeps them, ✕ or back puts the
  list back. The mode says which list, at the lower left.
- Events to keep stay as they are: the box, and what it pushes, go no
  further, its "+" greyed out. Those to push up or down are moved whole
  to just above or below the box when it -- or what it pushes -- reaches
  them, one after another, trimming what they run into without moving
  it. Those to cancel are cancelled. Pushing down the event the cursor
  was placed in puts the rest of it after the box, as splitting and
  pushing did.
- While picking, the box's buttons step aside, so taps reach the events.
  The overwriting pulse, too, holds still with animations turned off.

## 7.38.0

- The mode the Events page is in -- placing a cursor, creating an event,
  editing one, extending the compaction window -- is named at its lower
  left, over its icon, the newest on the left. Android's back leaves the
  mode, as ✕ does, undoing what was done in it, before it leaves the
  page.
- Placing a cursor inside an event, ✓ splits that event there -- the
  rest of it a new event -- and does nothing else, through the changes
  waiting to save as ever.
- A cursor's snap labels go outside the box: above its top, below its
  bottom. On the end of one event and the start of the next, "end of"
  is above "start of", as on the timeline.

## 7.37.0

- Confirming, finishing or abandoning the proposal, and leaving or
  withdrawing a note for Claude, wait to save like any other change:
  offline, they go when they can, even with the app closed. One the
  server refuses stops the queue there, to deal with. Once confirming,
  finishing or abandoning it waits, nothing more of it can be changed.
- What came of them is said over the proposal until you tap OK: a
  confirm recorded, planned again as a new revision to confirm, or gone
  to Claude.
- An edit of the proposal is sent from the revision you were looking at
  when you made it, not the one the edit before it made, so the server
  says which of Claude's newer changes it replaced -- and now the app
  does too, over the proposal, those events marked.
- Dropping a change to the proposal offers to drop those of it made
  after it too.
- A note for Claude, or abandoning, isn't made twice after an attempt
  nobody heard back from; a confirm finishes applying instead.

## 7.36.0

- A cursor's time, tapped -- and the compaction window's end's, from
  its settings -- is set in a dialog of its day, hour and minute, each
  with a "+" above and a "−" below stepping it by one. The day is the
  day shown ("+0") or the one before or after; a minute past 59 carries
  into the hour, and an hour past 23 into the day, either way.

## 7.35.0

- A new or moved event's box has no anchor any more: its cursors are its
  top and its bottom, alike. Each is labeled with its corner (┌, └) and
  its time, and under it, what it's on -- "end of Lunch", "start of
  Work" lined up over another, "note: …", faded to fit -- with scissors
  while it cuts into an event. Its time, tapped, is typed in.
- The box has one mode, not one for each cursor: it trims the events in
  its way, unless another is picked -- keeps clear of them, cancels them,
  or pushes them -- its icon on it but for trimming. Tap the box to
  change it. The switch, and each cursor's settings, are gone; trimming
  and pushing, and splitting and pushing, come back with lists of events
  to push.
- The box is dragged by itself, not a handle; once it's made, a tap on
  the timeline leaves it be. The "+", "−" and arrows are all one size,
  bigger and further apart, and the cursors' handles twice as wide.
- What a cursor stops at besides the grid -- events' edges, notes -- is
  set in Settings, for every cursor.

## 7.34.0

- The changes waiting to save open from the app menu too, as **Changes
  waiting to save** -- with how many, when there are any -- not only
  from the line at the foot of the screen, and so also when nothing's
  waiting: to see that everything's saved, or to pause the queue ahead.

## 7.33.0

- Which routines a proposal is expected from is now up to you: on
  Background updates, each routine's time has an **Expect proposal**
  button. The label no longer decides it, and none is expected until
  you say so.
- A proposal has come once one is open through a time after the
  routine ran (as far as Claude's own revision runs, not as you
  extended it), or a compaction was confirmed since. Whether there were
  notes to compact no longer matters: Claude proposes the calendar as
  planned when there are none.

## 7.32.0

- The open compaction proposal is kept on the device, and the
  background fetch fetches it: the Events page shows it at once, as it
  was kept, while it asks again.
- After a compaction routine (one whose label says "compaction"), if
  its proposal hasn't come, the background fetch checks again every 15
  minutes, for up to 3 hours. It's waiting when no new revision has come
  since the routine ran and there are notes from before it to compact.
- On Background updates, under **Timing**: how long after each routine
  to fetch (10 minutes, unless it's changed), and how often to check
  again until a proposal comes, or not to.

## 7.31.0

- A compaction proposal can be extended from the app, past where
  Claude's revision ran to: tap its "through" tab, now with a pencil,
  for the end's cursor -- its anchor fixed at Claude's end -- drag it,
  step it to its next stop, or type its time in its settings, and
  **Extend**. It's never cut short, nor extended past now. The notes it
  takes in are added to the events they fall within, as yours, with a
  badge of their own and saying so; the stretch is tinted apart,
  headed "extended by you". Needs the server's `amend_proposal`
  `through` and `claude_through`.
- Fixed: a cursor on an event from the server -- moving it, say -- didn't
  step: its "+" and "−" did nothing, as its stops were worked out in
  local time and the server's times are in UTC. And keeping events, a
  "+" against one is greyed out again.

## 7.30.0

- A new or moved event's cursors are its **anchor**, where it was
  started, and its **end**, each with a mode of its own in place of the
  six that went for the whole box. The anchor keeps clear of the event
  it's in (the default), trims it, cancels it, or splits it, the rest
  going right after the new event and pushing along what it runs into.
  The end keeps the box out of other events (the default), trims them,
  cancels them -- but the anchor's -- or pushes them along, earlier for
  a box drawn upward. Each is kept for the next event; a move starts
  out pushing.
- Before there's a box, the anchor has an arrow either side, stepping it
  to its next stop, and a "+" either side, making the box that way.
  Once there's one, each cursor has on its outside a "+" and a "−", its
  settings, and -- the anchor -- the switch, marked with an anchor,
  that makes the end the anchor. Keeping, a "+" against an event is
  greyed out. The cursor last touched is drawn bolder, and its buttons
  win where two cursors' would overlap.
- A cursor's settings, in a sheet: its mode, what it stops at besides
  the grid, and its time, typed in a dialog with its date.

## 7.29.0

- A cursor on the Events page stops at the next stop, not an hour on:
  the grid's next line, or an event's edge or a note before it. "+"
  once from a new cursor makes a quarter-hour event, or one up to the
  next edge or note. A dragged cursor snaps to an edge or a note it
  comes near, and otherwise to the grid. "−" never shrinks an event to
  nothing.
- While a cursor is up, the edges and notes it stops at are marked on
  the timeline, pulsing -- steady with animations turned off.
- What each cursor stops at is kept on the device, for each of a new
  event's ends; changing it comes with the cursors' own settings.

## 7.28.0

- A Settings page, from the menu: the grid the Events page's cursors
  snap to, every 5, 10, 15, 30 or 60 minutes, or none, to stop at any
  minute. It's 15 minutes until changed, as before, and kept on the
  device.

## 7.27.0

- A change the server refused names the events it's about, in place of
  their ids: "“Breakfast” (7:00 AM)", on its day if that's not today,
  or "an event at 9:15 AM" for one the app hasn't loaded (a series'
  instance says when it was to start). Each event named has a "Show"
  button that closes the sheet, goes to it on the Events page and
  rings it, pulsing, for a moment.

## 7.26.0

- A person's page sums up their events: how many in its window and
  their time, the most recent and the oldest. "All events" opens every
  one on a page of its own. The events cancelled against their
  follow-through are summed up the same way -- how many, the time they
  were planned for, the most recent and the oldest -- with "All
  cancelled events" for the lot.
- On the timeline, where events overlap, that time is tinted red and
  labeled "overlap". It only shows them; nothing else changes.

## 7.25.0

- A new event's dialog has what an event's has: who it's with and for,
  and its location, each picked in a sheet, in place of the free-text
  location, and its notes. A new event in a compaction proposal can
  name the people and locations the proposal adds.

## 7.24.0

- Making room no longer cancels events without asking whether that
  counts against follow-through. Moving or adding an event over others,
  or clearing their time, in "Overwrite and trim" or "Overwrite and
  cancel", asks first: each event it would cancel is listed, as a change
  of plan unless you turn it on as a commitment dropped. "Keep them"
  calls the change off, leaving it as it was. The same goes in a
  compaction proposal's band.

## 7.23.0

- On Android, the app fetches in the background, so what it shows is
  fresh when it opens: 10 minutes after each time Claude's routines run
  (compacting notes, answering the notes left on a proposal), and
  otherwise every 6 hours. Each fetch gets the notes and when they were
  last compacted, every action, trait, person, location and habit, and
  the week either side of today's events.
- The routines' times come from the server (`get_compaction_schedule_
  hints`), where the routines set them; the app only shows them. A
  "Background updates" page, from the menu, lists them -- each with when
  the app updates after it -- says plainly that it otherwise updates every
  6 hours, and when the next update is, and what the last did. A server
  without the times leaves just the 6-hourly updates.

## 7.22.0

- The People pane has no search: with Self and three people on it, there's
  nothing to search for. Everyone's page, from "All people and circles",
  keeps its search.
- The pane's second section, the three people you prioritize, is now
  just "People", and its "+", adding a person or a circle, is in that
  heading.
- Everyone's page sorts from a button of an up and a down arrow, not one
  that looked like it lined up text.

## 7.21.0

- A Time spent part says its target in hours and minutes -- "1h 20m of
  guitar every 7 days" -- and so does how its score was reached: "45m of
  1h 20m in the last 7 days". Its field is "Target time", and its hint no
  longer speaks of minutes.

## 7.20.0

- Changes to events, and to the open compaction proposal, no longer wait
  for the server: a dialog closes as soon as it's saved, and the change
  is shown at once, marked "Waiting to save", while it's sent in the
  background -- in the order made, kept on the device across restarts,
  and sent by Android's background task too. That covers editing,
  cancelling, adding and moving events, and every edit of the proposal.
- A line at the foot of every page says while any are waiting: saving,
  paused, trying again later, or stopped at one the server refused.
  Tapping it slides up the list of them, to pause or resume the queue,
  try again now, edit one (a change to an event, a new one, or a cancel)
  or drop one. One refused stops the queue there, saying why, as what
  comes after may depend on it; one refused as changing history can be
  approved from there.
- What a change waiting changes can't be changed again until it's saved:
  an event it cancels or adds not at all, and the fields it sets -- its
  title, its time, its actions -- not until then. Its dialogs say so, and
  those fields don't open; a change that would touch them says which
  change it's waiting for.
- A proposal can't be confirmed while edits of it are waiting, so what's
  confirmed is what's shown.

## 7.19.0

- The Events page's day summary opens on its top actions, then the
  top-level groups they're under -- now just "Top-level" -- then the
  time by priority.

## 7.18.0

- A trait is added or edited on a page of its own, as a person or a
  habit is, with room for its definition and its parts. So are someone's
  own parts for a trait, or a habit's.
- Time spent's target is in hours and minutes: written as you'd say it
  ("1h 30m", "90m", "1:30"), or set with steppers, an hour or 15 minutes
  at a time. It's still kept in minutes.

## 7.17.0

- A person is prioritized by a star, as a habit is focused on: on their
  page, and as they're edited. It still applies at once, on this
  device, and stops at three; their menu does it too.
- Editing a person or a habit, or adding one, opens a page of its own,
  not a dialog: the fields down the page, with room to write what
  matters to someone, or what a habit's for. Save is in its bar, beside
  the star; its close button calls it off.

## 7.16.0

- The People pane is two sections, one over the other, each folded away
  by tapping its head and open to start with:
  - **Self**, with your relationship health and its last 8 days in its
    head, and the two habits you focus on, each with its health. "All
    habits and scores" opens your page.
  - **Prioritized people**: the three you keep in front. "All people and
    circles" opens everyone, as the pane listed them before.
- A habit's star, on its page or your list of habits, focuses on it; a
  person's menu prioritizes them. Both are kept on this device only.
- Each person says their time with you in the summary's 24 hours and 7
  days -- in time or as a share, back or on, as the summary is set -- and
  the last event with them, or, looking on, the next.
- Everyone can be sorted, either way, by relationship health, when last
  (or next) seen, or time in the 24 hours or 7 days; Self stays first.
- The pane's search finds anyone, prioritized or not.

## 7.15.0

- A series' dialog picks who its events are with and for, and where they
  are, as an event's does: in a sheet up from the foot, shown after a
  person and a pin, in place of its free-text location (still in
  Details). What happened stays each event's own.

## 7.14.0

- Habits are scored, as people are: each trait that applies to one, for
  each of the last 7 days, from your events with its action -- or any
  action under its group, as the tree is now -- Claude's judgments of
  them for the habit, and the cancellations that count against it. A
  part that reads events done for someone is left out, and a trait with
  no other part isn't scored for it.
- A habit's page shows its health -- on track, needing attention or off
  track -- with its last 8 days; each trait's score, with its trend,
  tapping one for how it was reached; and its events.
- An event's notes name Claude's judgments of it for a habit by the
  habit: "Practice guitar (habit)".
- People score as before; a trait's health is still everyone's mean,
  without the habits.

## 7.13.0

- Habits: what you want to do well, each about one action -- or every
  action under a group -- and held to traits, as a person is: every
  active trait, or those picked, with parts of its own for any (a rubric
  for this habit alone, say). You're at every one of its events, so a
  part that reads events done for someone is left out, and one that
  counts an action outside it is warned of.
- Self's page lists them, each in its action's color, under Habits;
  "Habit" adds one. Tapping one opens its page: its action or group,
  what it's for, its traits, and what was cancelled that counts against
  its follow-through. Its pencil edits it -- its name, action or group,
  note, traits and status.
- Self, in the People pane, says how many habits they have.
- Habits come from the server's habit tools. A server without them shows
  none, and nothing else changes. Scores come later.

## 7.12.0

- In an event's dialog, its actions, who it was with and for, and its
  location are picked in a sheet up from the foot of the screen, as a
  note's is, with a search and the room to show what it finds: the
  actions as before, from the tree; who in a tab each -- with, and for;
  and the location from the list, a new one added there.
- Who takes the free-text location's place, in a line after a person,
  e.g. "With Sam · For Priya"; and the location, by its name after a
  pin. The free-text location isn't shown. The row of notes -- now after
  a note and pencil, not sparkles -- keeps the notes and Claude's
  judgments, and opens just the notes.
- The description is written in a sheet up from the foot, too.
- The actions are after a plow, drawn, not a flag.

## 7.11.0

- Every failure talking to the server is shown the same way: a sheet
  that slides up from the bottom, saying what couldn't be done and why
  in plain words -- couldn't reach the server, it took too long, it's
  having trouble, it said no (in its own words), or you were signed
  out. When trying again might help, it offers to. It replaces the
  error snackbars, and the errors written inside dialogs (a dialog
  stays open, as you left it, under the sheet). Something saved in the
  background that failed says so in the same sheet.
- A page that couldn't load says so the same way everywhere, with a
  "Try again" button.
- Retries are handled in one place, the connection to the server: a
  session the server forgot is started again, and a call that never
  reached the server is sent again, for any call. One that may have
  reached it -- the connection reset, a timeout, the server having
  trouble -- is sent again, up to three times, only if it only reads;
  for one that changes something, you decide, from the sheet.
- Background saves treat the server having trouble (a 502, 503 or 504)
  as something to try again, not a refusal.

## 7.10.0

- Under a compaction proposal's bar, its details, in pages swiped or
  tapped between, folded away like the day's summary: its notes, its
  follow-through, and what it adds. Each shows one at a time, with
  arrows to the one before or after, scrolling the timeline to it.
- Follow-through: how many of its cancels count against follow-through,
  of how many. Each cancel says whether it does, and against whom -- or
  that it's a change of plan -- outlined on the timeline; its switch
  says otherwise. Tapping a cancelled event, or a cancel there, shows it
  in full: when, who said so, and everyone it counts against, with the
  switch, putting it back as planned, and a note for Claude about it.
- Added: each person, action and location it adds -- named, not by the
  ref it goes by until it's made -- with what tells it apart, and the
  events it's at, outlined. Settle it: make it now (corrected, if need
  be), say it's one already here, or drop it; put it back as Claude
  proposed it; or ask Claude about it.
- An event in what happened, to confirm, takes the same edits as one in
  the plan: its whole description -- not only added to -- its location
  and its priority too. A priority can be set, not cleared.
- In an event's dialogs, and on its card, what a proposal adds is named,
  marked new, and offered among the people and locations to pick.

## 7.9.0

- The box's "+" buttons stretch it an hour at the end they're on: "+"
  above, earlier at its top, and "+" below, later at its foot --
  whichever cursor is there. (They moved the other cursor, which could
  shrink it.) Keeping events, a stretch stops at the event before, or
  after. Dragged, a "+" takes that end with it.
- Beside each, a "−" shrinks it an hour from that end, to no less than
  a quarter hour: "−" above, from the top, and "−" below, from the foot.
- The other cursor has a "−" and a "+" of its own, on its outside: the
  box shrunk and stretched at that end, as by the cursor's.

## 7.8.1

- The sample data's events no longer overlap: the events with people,
  and the plans, take their time out of each day's routine -- Work split
  around a call, TV cut short by guitar practice, and the like.

## 7.8.0

- Compaction proposals, on the Events page. While Claude has one open --
  what it says happened since the last compaction -- it's a band over the
  timeline, tinted and outlined, to confirm, ending at a line saying
  through when. Each event in it says what the proposal does to it --
  moved, and where it was; new; cancelled; renamed; new actions or facts
  -- and whether Claude or you decided it. Those changed since you last
  looked have a dot.
- Its notes are drawn across the band, over the events, each with a
  badge saying what became of it: added to an event, setting an event's
  start or end, or left out. Under the bar, one of them -- its time, its
  text and what became of it -- is highlighted on the timeline, and
  arrows go to the note before or after it, scrolling to it. Before the
  first, as context, is the latest note the last compaction used, with a
  check: there to see, not to change.
- Saying what a note is for: its pencil (or tapping it) asks. Add it to
  the event it falls within -- or, for one that sets an event's start or
  end, to that event -- or to another of its day's; leave it out; put it
  back as Claude had it; or ask Claude about it, in a note for Claude
  about that note. Which you said, and which Claude did, is shown with
  it. A note's edge stays where it is whatever it's added to.
- Edits to the events in the band edit the proposal, not the calendar:
  moving (pressing and holding, too), resizing, cancelling or adding one,
  or setting its actions, people or location, with what that does to the
  events in its way. A cancelled one can be put back as planned. One the
  server refuses stays in its dialog, to fix.
- A bar above the timeline confirms it ("Confirm ... happened as shown"),
  or leaves a note for Claude, about one of its events or all of it.
  While a note's open it's waiting for Claude, and can't be confirmed;
  its notes show Claude's replies, and an open one can be withdrawn. If
  the calendar changed since it was planned, it says what changed and
  asks to confirm again; if it can't be planned any more, it's handed to
  Claude; if applying it stopped partway, Retry finishes it. Its menu
  goes to it, or abandons it.
- The sample data has a proposal open.

## 7.7.0

- While a new event's being made, or one moved, on the Events page, the
  day before is stacked above the day shown, and the day after below --
  shaded, with a line at each midnight saying which day's which -- so
  the box can run across midnight, and events can be pushed on into the
  next day. What's on screen stays where it is as they come and go.

## 7.6.0

- Pressing and holding an event on the Events page moves it: the box a
  new event is made in comes up around it, pushing the events in its way
  to start with (its drop-down picks another way), and saying, by its
  cursor -- on the side away from the box, to read however short it
  is -- which event it's moving; the event is faint where it was. ✓
  saves the move, with what it does to the events in its way, in one go;
  ✕ leaves it be. After it, a new event treats the events in its way as
  it did before.
- A button on the box's cursor switches its two cursors: the box goes
  the other way from the cursor -- pushing the other way, pushing -- an
  arrow pointing from where the cursor was to where it's gone, and the
  cursor pinging there. If there's no room that way, it says so instead.

## 7.5.0

- Three more ways for a new event to treat the events in its way, in
  its drop-down, each pushing them along, their lengths kept, into the
  free time beyond -- as far as the day has room: the box is no longer
  than leaves it that. Where they go is outlined while the box is up.
  - **Trim and push**: an event the new one starts inside of is cut
    short there.
  - **Push**: like Keep, the cursor snaps out of an event, to its nearer
    edge -- which can be between two events that meet.
  - **Split and push**: an event the new one starts inside of is split
    there, and the rest of it pushed along after the new one.
  The box pushes the way it goes from its cursor: later, or earlier.
  Its trash makes the room without a new event.
- In the drop-down's dialog, each way's icon is beside its radio, ahead
  of its name, and only the one picked says what it does: tapping
  another picks it, and tapping it again, or Done, settles on it. Trim
  and push has scissors over its push, and Split and push a zipper
  coming open over its.

## 7.4.0

- Keeping events, when the new event's box is moved to fit into free
  time, an arrow points from where it was put to where it went, then
  fades.
- While making an event, a button above ✕ and ✓ scrolls the box back
  into the middle of the view.

## 7.3.1

- Changing a group's priority, or anything else about it, is saved: it
  was sent as an action's change, which the server refused, leaving the
  group stuck on the failed save. One stuck that way goes through when
  it's retried.

## 7.3.0

- Overwriting comes in two kinds, in the new event's drop-down:
  **Overwrite and trim** shortens or splits the events in the way (and
  cancels one it covers whole), as overwriting did; **Overwrite and
  cancel** cancels every event the new one touches, whole -- its shadow
  stretching past the box to cover them, while the new event keeps the
  box's times.
- Overwriting events, the new event's dialog has a trash can at its top
  right: rather than making the event, it clears the time -- trimming or
  cancelling the events under the box, as the mode says -- after asking.

## 7.2.0

- Events are added from a **+** on the Events page, in place of the zoom
  buttons (pinch to zoom); tapping a blank space does nothing. The +
  puts a cursor at now (or the middle of what's in view). In its middle,
  a + with an arrow down, below it, puts a second cursor an hour later
  each tap, and a + with an arrow up, above it, an hour earlier -- or
  either is dragged to where the second cursor goes. The event is
  always between the two cursors, in a box; each cursor's handle, at its
  right, moves it alone, and a bigger, fainter handle in the box moves
  it whole, as does tapping the timeline -- an event too, which doesn't
  open while the box is up. ✓ opens the new event; ✕ stops.
- Beside them, a drop-down picks whether the new event keeps clear of
  the events already there or overwrites them. Keeping them, the box
  fits into free time: a cursor in an event moves out of it, an end
  stops at the next event, and the box moved whole goes to the nearest
  free time it fits in that day (or fills the nearest, if none's long
  enough).
  Overwriting, its shadow is tinged red and slowly pulses where it would
  take time from events, and saving shortens, splits or cancels them (as
  a change of plan, not against follow-through) in the same batch as the
  new event.

## 7.1.2

- Traits judged from what matters to a person (the seeded Thoughtful, for
  one) are scored again: the app knows the server's "what matters" fact
  (time-tracking-google-calendar-mcp#139), so it no longer leaves their
  judgments out as having a fact it doesn't know. The trait editor can
  pick it too.

## 7.1.1

- An action picker opens at once: the Events page's pickers list the
  actions the app already has, and the Plan page's those it shows, rather
  than loading every action from the server each time a dialog opens.

## 7.1.0

Needs a server with the priority colors tools
(time-tracking-google-calendar-mcp#152).

- Priorities are shown in the server's colors, its priority labels'.
- The Actions pane's "Priority colors" changes them. Actions and groups
  without a color of their own change with them.

## 7.0.1

- The code says actions, not goals, throughout: nothing changes in use.
  What older versions saved on the device (actions waiting to be saved,
  and the Plan summaries' choices) is still read.

## 7.0.0

Needs a server whose event tools take batches and move nothing to make
room (time-tracking-google-calendar-mcp#151).

- Creating, changing and cancelling an event go through the server's
  batch tools. The server never moves other events to make room: a
  change that would overlap one is refused, as the app already kept
  times clear itself.
- Changing or cancelling an event compaction has already recorded asks
  "Change history?" first, and goes through only if you agree.
- Fixed time, fixed duration and minimum duration are gone: they only
  ever steered the server's reallocation, which is gone too. An event's
  summary no longer has a Fixed/Flexible time switch.

## 6.9.1

- The Events page and its dialogs say actions, not goals, which are
  gone: "Add actions" and a priority "From its actions" on an event, the
  action picker ("Search actions", "Primary action", "Show 2 inside"),
  and the day summary's "Actions" and "Top-level groups" pages, with
  time on no action as "No action".

## 6.9.0

- What the app loads is kept once, for every page: the events, day by
  day, in the store the traits are scored from -- the Events page's days
  and the Plan summaries' windows among them -- and the actions, the
  notes not yet compacted and when notes were last compacted, which the
  Notes, Events and Plan pages each used to load and keep apart. A page
  shows what another loaded at once, while it asks the server again.
- The events are no longer kept apart for the first day the Events page
  shows: every day the app has is kept from run to run.
- Fixes what was kept from the last run sometimes being lost when two
  pages asked for it at once.

## 6.8.1

- Sliding between days on the Events page draws a day the app already
  has as it slides in, rather than a spinner that its events then pop
  into; and a day the app loads while it's showing (as it opens, say)
  shows at once.

## 6.8.0

Needs a server that lists each person's cancelled events
(time-tracking-google-calendar-mcp#150).

- Follow-through is scored again, in the app: each event the user
  cancelled that counts against someone, as the server lists it with
  them, costs its penalty, and each day with an event kept with them wins
  its recovery back, as the server scores it.
- A person's page lists those cancellations, newest first: when each was
  planned, what was to be done, whether they were to be there or it was
  for them, when and how it was cancelled (it didn't happen, or was
  deleted), and the traits it counts against.

## 6.7.0

No longer needs the server's daily trait scores.

- The traits' scores are worked out in the app, from the events and
  Claude's judgments of them, as the server scores them: each person's
  score of each trait for each of the last 7 days, each trait's health,
  and each person's and circle's relationship health and history. Their
  pages show what's behind each score, with the events. Follow-through
  isn't scored: the server doesn't list cancelled events.
- As it opens, the app loads the week either side of today, and any
  earlier (or later) day the traits read that it hasn't kept from an
  earlier run. The Events page shows those days at once, and what's saved
  there changes the scores straight away.
- The sample data's scores are worked out from its events the same way.

## 6.6.0

- "Count against follow-through" starts on when confirming a
  cancellation: turn it off when the plan merely changed.

## 6.5.0

Needs a server whose delete_event takes counts_against_follow_through
(time-tracking-google-calendar-mcp#148).

- Cancelling an event goes through the server's delete_event, the one
  way it cancels events now, rather than saving it as cancelled.
- Confirming a cancellation offers "Count against follow-through": on,
  it lowers the follow-through of whoever a trait tracks the event for --
  a commitment dropped. Off, as it starts, it's just a change of plan.

## 6.4.0

- The Events page loads everyone, every location and every trait as it
  opens -- shared with the Plan page, and kept from the last run -- so an
  event's details name who it was with, where, and its judgments at once,
  and its "What happened" dialog lists them without waiting.

## 6.3.0

Needs a server with daily trait scores
(time-tracking-google-calendar-mcp#140).

- A trait's page shows its overall health below its parts -- the last
  day's score, the mean of everyone scored by it, and its trend -- in
  place of who it applies to.
- Traits' scores come from the server's daily scores, so they show
  against the real server, not just the sample data. Tapping a person's
  score for a day shows how each part's was reached.

## 6.2.0

- The Plan page keeps what it loaded while you're elsewhere in the app,
  and what it loaded last run, so it no longer goes blank while you move
  around it. Landing on it loads every pane at once.
- Tap a group to open or close it. Tap an action to set its priority and
  color; "Details" opens the rest.
- The time summaries are back, above the search on the Actions pane, with
  each action's and group's time in its row again. The client now works
  them out from the events. New on the People and Locations panes: time
  by person, by circle (people in none are "Individuals") and by location.
- The summaries measure from the last compaction by default; move them a
  day at a time, or look at the 24 hours and 7 days after instead of
  before.
- Tapping a trait opens its page; its pencil edits it.
- The Events page shows when notes were last compacted again.

## 6.1.0

- The Plan page swipes between panes -- Actions, Traits, People and
  Locations, in that order -- or picks one from its tabs, and each has a
  search. Searching actions shows those found in their groups.
- On the Actions pane, only a swipe right opens or closes a group: a
  swipe left goes on to the next pane.
- Actions have no targets, health or history: those are gone from their
  dialog and their rows, as is the Overall goal. Tapping one opens its
  details. Only people have health.

## 6.0.0

Needs a server with actions, people, circles, locations and judgments
(time-tracking-google-calendar-mcp#130 to #136).

- The Goals tab is now **Plan**, in four sections, each folded away or
  opened from its heading: Traits (how to be), People (who), Locations
  (where) and Actions (do).
- Traits are wholly yours: their parts are now *judgments* -- a rubric, a
  rating scale, and the facts Claude judges each event from (actions,
  locations and the notes, histories with a lookback) -- plus counts,
  time spent, continuity and follow-through, which can count one action or
  group. Every part reads events with someone, or done for them. The
  built-in kinds are gone. Traits rate people, not goals.
- People: Self, always, and everyone else, each with a context to tell
  people of the same name apart, in any number of circles, with what
  matters to them, and which traits apply to them -- every active one, or
  those picked, with their own parts for any. A person's page shows them.
- Locations, each with a hint for recognizing it, added, edited and
  deleted from the Plan page, or added from an event.
- Actions are what goals were: a tree, but of groups -- which can't be
  given to an event -- with actions as its leaves. They're proposed (made
  by Claude, to approve from its menu), active, archived or deleted. An
  action's target, health and history, and reordering, are only in the
  sample data for now: the server doesn't keep them.
- What happened at an event is now its facts: who was there with you, who
  it was done for, where, and a note on you and each person there, with
  Claude's judgments of it shown. Relationship health, from gray
  (disconnected) to green (healthy), and people's trait scores and
  histories are sample data only, until the server rates people.
- The Notes page says when a compaction's judgments are still pending.

## 5.16.1

- On the Goals page, a goal with sub-goals and a color of its own again
  shows that color down its whole band, as before 5.15.1.

## 5.16.0

- Cadences. A trait's "Number of events" and "Time spent" parts take an
  activity: they then count only events with them of that activity, such
  as a visit every 21 days or a call every week.
- A goal rated by traits can have its own parts for a trait: in its
  measure, "Customize for this goal" under a trait edits that goal's own
  parts (its cadences, say), starting from the trait's, and "Use the
  trait's" goes back. Its settings list them.
- A goal's traits page shows how it's rated: its traits, their weights,
  and its own parts. The tune button edits them there.

## 5.15.1

- On the Goals page, a goal with sub-goals and a color of its own shows
  that color only on its arrow; its band beneath is dashed in the color
  it'd inherit, so the color no longer runs on down beside its
  sub-goals.

## 5.15.0

- Traits. The Goals page's app bar opens the **Traits** list: each trait's
  name, definition, status, latest score (the mean across the goals rated
  by it) and its last days' scores. Tap a trait to rename it, reword it,
  change its status or edit its parts (each part's kind, settings and
  weight, and a judgment's rubric), checked before saving as the server
  checks it; "+" adds one, and its menu turns it on or off or archives it.
  Tapping a score shows each goal's score behind it, and each of those the
  parts and events behind it.
- A goal's measure can be **Traits**: every active trait, or the ones
  picked, each with a weight, over a window of days.
- A goal rated by traits has **Traits** in its menu: a page with its
  traits' latest scores (tap one for the parts and events behind it),
  what matters to them (editable), its history of activities and places,
  and its events with what happened at each.
- An event's details show **what happened** at it: who it was with and
  for, its activity and place, how creative, how much effort and how much
  attention (0-3 each), what was new, and why. Tap to edit them.

## 5.14.0

- In a weighted measure's editor, a sub-goal's weight can be set aside
  until a day: "Set aside until…" picks the day, and "Then" is what it
  weighs from that day on. Its settings show it as "weight 0 until
  2026-11-05, then 1". The close button makes it a plain weight again.

## 5.13.0

- The Events page's day summary and the Goals page's summary each have
  a toggle by their chevron, % on one half and a clock on the other,
  the one shown filled in. Tapping it anywhere turns each share's
  percentage into its time, such as "1h 30m", and back. Each page keeps
  it as it was left next time.
- On the Goals page, the toggle also decides how "Time spent" shows
  under each goal and on the overall card: "9h in 24h", or "37.5% of
  24h". "Time as a percentage" is gone from the menu; if it was picked,
  "Time spent" shows percentages instead.
- When a summary's titles don't fit beside the toggle and chevron on a
  narrow screen, they shrink to fit.

## 5.12.0

- On the Events page, the strip down an event's left edge is solid all
  the way, no longer dashed where the event is drawn taller than it
  lasts.
- Where two events meet in the same color, or colors too close to tell
  apart, a hairline divides them across the band, along the fill to the
  events, and over their strips.

## 5.11.2

- When the server fails after you sign in, the Notes, Events and Goals
  pages say what went wrong ("Could not load notes", with the server's
  reason) instead of asking you to sign in again.

## 5.11.1

- The web app runs only its own code. It loads its graphics engine from
  its own site rather than Google's, and the published app has a
  Content-Security-Policy: no scripts from other sites, and connections
  only to the server, the sign-in service and Google's fonts. The
  sign-in page's script moved to its own file for that.
- The web app keeps its sign-in only in memory, never in the browser's
  storage, so reloading the page or opening it again means signing in
  again.
- The web app won't run inside another site's page, where that site
  could trick you into clicking it.

## 5.11.0

- The Events page marks each note not yet compacted into the calendar,
  saved or still waiting to be, with a dashed line across like the "last
  compacted" one, but thinner and fainter, as a hint. Zoomed in, each is
  labeled "pending note", like "now" and "last compacted", where there's
  room.
- A "Go to now" button, above the zoom buttons, goes to today with now
  about a third of the way down the screen.
- The Events page goes back to the day, time and zoom it was left on,
  after switching to Notes or Goals, or closing the app, if it's back
  within 30 minutes. After that it opens on today, at now, as before; and
  so it does if it was left on today and it's since become tomorrow.

## 5.10.0

- The Goals page has a summary of the last 24 hours and 7 days under its
  heading: a bar for each, one over the other, with each share's
  percentage of each window. One page splits them by the goals shown,
  so with every goal collapsed it's the top-level goals; expanding a
  goal gives its sub-goals their time, and it keeps only its own. The
  rest of each window is "Not on goals". Swiping it, or tapping a title,
  turns to the windows split by priority, as the server counts it: the
  highest priority among the events at each moment, and the rest with
  no priority. Its chevron folds it away to a quiet "Show summary", and
  it stays folded next time.
- The Events page's day summary folds away the same way, and stays
  folded next time too. It and the Goals page's summary share their look
  and code.

## 5.9.0

- An event's times stay clear of the events either side when you change
  them, and when you make one by tapping the timeline. A start picked
  inside another event moves to that event's end, and an end picked past
  the next event's start comes back to it. A new event tapped just after
  another starts when that one ends, not inside it.
- Start and end each have − and + buttons, either side of the time, that
  take a quarter hour off or add one, up to the events either side, and
  never leaving the event shorter than 15 minutes. Under them, the
  dialog says how much free time there is between the events either
  side.
- In an event's Details, new times that would overlap another event
  can't be saved; it says which event is in the way.
- Saving or creating an event no longer moves, shrinks, splits or
  cancels other events to make room. If the new times would need that,
  nothing is saved, and the server's message says what would have had
  to change.

## 5.8.1

- The home screen "+" brings up the keyboard with the New note dialog
  reliably. It used to miss now and then, when the app's window was
  ready before the dialog's text box: the app asked for the keyboard
  too early and didn't ask again. Now it waits until both are ready.

## 5.8.0

- The Events page opens with a summary of the day above the timeline: a
  bar split by how much of the day went to each priority, with each
  share's percentage under it, and the time with nothing scheduled left
  empty. Swiping it, or tapping a title, turns to the top goals of the
  day, or to the top-level goals they're under: the three with the most
  time, then the rest together, then events with no goal. Where events
  overlap, they share the time; an event with more than one goal splits
  its time between them.

## 5.7.0

- A goal's parent, in its Details, and the goal a measure counts the
  events of ("Another goal") are now picked from the same searchable
  tree as an event's goals, in a dialog that opens on a tap: search by
  any words of a goal's path, or browse the tree, opened down to the
  goal picked now. Tapping a goal picks it; Enter picks the top match.
  The field shows the goal's whole path.
- A goal's parent can no longer be the goal itself or one of its own
  sub-goals, nor an archived or deleted goal, unless it's already the
  parent. "None (top-level)" makes it a top-level goal.
- Enter in a goal search picks what was just typed, even typed fast.

## 5.6.0

- On the Events page, a band beside the priority band, and as wide,
  shows each event where its times put it, in its color: its primary
  goal's, or else its priority's. That color fills the space from its
  piece of the band to the event, and a thin line of it runs round the
  event, in place of the gray bracket and line that marked where a
  moved or stretched event truly is. A cancelled event's are faint.
- Events that meet share one line between them, in the later one's
  color, and their corners there are square.

## 5.5.0

- Tapping a gap on the Events page's timeline (anywhere but an event)
  opens a new, blank event there, with its summary ready to type. It
  starts at the quarter hour you tapped and lasts an hour, or until the
  next event if that's sooner. Set any of its other properties as you
  would an event's, then tap "Create", which needs a summary.
- On a day with no events, tap any time, the "No events." card
  included, to add one there.

## 5.4.1

- Swiping between days on the Events page keeps the time of day shown.
  It went back to midnight after a day that was still loading or had no
  events.
- The hours down the side of the Events page stay still while the days
  slide past them. Each day's own marks, such as the times its events
  start and end, "now" and "last compacted", slide with it.

## 5.4.0

- Picking an event's goals, in its short dialog or its Details, no
  longer means scrolling every goal. The goals picked sit on top as
  chips, the primary goal starred; ✕ removes one. "Search goals" finds
  a goal by any words of its path, e.g. "cook tofu", showing where each
  match sits; Enter picks the top one. With the search empty, the goals
  are a tree that opens only down to the ones picked; the arrow beside
  a goal shows or hides its sub-goals.

## 5.3.0

- On the Goals page, each goal shows its color as a band down the left
  in place of its flag: solid if the color is its own, dashed if it's
  inherited. A sub-goal is indented by one band, its ancestors' bands
  running down beside its own, so its nesting can be seen at a glance;
  dashed bands side by side are offset into a checkerboard, and their
  dashes line up down the page. A goal with sub-goals has an arrow on
  its band, as tall as the goal, while they're hidden, and its band
  widens down into theirs while they're shown.
- Swipe a goal right to show or hide its sub-goals. Tapping a goal now
  always opens it.
- Each active goal's priority shows as a chip after its name, as on the
  Events page: filled if it's set on the goal, outlined if inherited.
- A goal's measure and its event properties are one dialog: its priority
  chip at the top (tap it to change it), then its measure, how it's
  doing, and its color. The "Event properties" choice under each goal is
  gone, and "Measure" in a goal's menu is now "Edit". The choices under
  each goal are now in the order Time spent, Time as a percentage,
  Measure.
- The sample data has a goal three levels deep.

## 5.2.0

- Clearing an event's or a series' priority, location, description or
  minimum duration now removes it, rather than leaving it as it was. A
  priority cleared ("From its goals") makes it follow its goals'
  priority again; the chip says "From goals" until it's saved. A
  series' priority can now be cleared too.
- An emptied summary is no longer a change: every event keeps one.

## 5.1.0

- Tapping an event on the Events page shows a shorter dialog with the
  properties you edit most: its priority as a chip above its summary,
  its times on one line, a "Repeats · see series" chip if it's in a
  series, its location and description (with "Add location" and "Add
  description" when they're blank), whether it's at a fixed time, and
  its goals, each after its colored diamond. Tap one to change it in
  place, then Save. "Details" opens every property, as before.
- The trash can at its top right cancels the event, after asking.
- "See series" opens the series the same way, with how it repeats under
  its summary. Tap that to change the frequency, the interval, the
  weekdays and when it ends. The series' trash can deletes this event
  and the ones after it, after asking; earlier events stay.
- Saving a change to a series says what it may do to its events: set
  each one's properties to the series', except its time, or, if you
  changed the time, move each one to it too, even events you changed
  on their own.
- A series' schedule comes from the server as a structured repeat, not
  RFC 5545 rules.

## 5.0.0

- Goals no longer have a fixed time, matching the server: an event is at
  a fixed time only if it says so itself. The event properties dialog
  and a goal's details no longer offer it, and the Goals page's "Event
  properties" summary shows only a goal's priority.
- An event without a priority of its own takes the highest (lowest
  numbered) of all its goals', not just its primary goal's; the primary
  goal only decides its color.

## 4.12.2

- The Notes page shows the latest compacted note and when notes were
  last compacted as they were last time, while it asks the server again,
  rather than leaving them out until it answers.

## 4.12.1

- On the Events page, an event's duration box says how it's drawn: with
  square corners when the event is drawn taller than it lasts (to fit
  its text), open at the top when it's drawn shorter (pushed down by the
  one above, but ending where it ends), and rounded when it's drawn as
  long as it lasts.
- The last compaction's line is labeled "last compacted", on two lines,
  so it's no longer cut off; the times down the side have a little more
  room.

## 4.12.0

- The Notes page shows the latest compacted note above the notes since,
  smaller and muted with a calendar mark, and under it a dashed line, as
  on the Events page, for when notes were last compacted.

## 4.11.0

- On the Events page, the days slide: drag left or right and the next
  day or the one before follows your finger, already loaded, scrolled to
  the same time of day; the arrows slide too. The days either side of
  the one shown are loaded in the background to be ready.
- "now" and "last compaction" are small, plain labels in their lines'
  colors, in place of the times beside them, and only when zoomed in.

## 4.10.0

- Each event on the Events page says how long it is and its priority
  ("P1", in the priority's color) at its top right. The length is filled
  in when the event is shorter than it's drawn.
- The line for now is labeled "now", and a dashed line marks the last
  compaction, labeled "last compaction", both at the left edge.
- Swipe left or right to go to the next day or the one before, and pinch
  to zoom in or out around your fingers.

## 4.9.0

- The Events page is a timeline of the day, midnight to midnight, at a
  constant scale. Down its left edge are the times where events start
  and end, then the hours, as many as fit; zoom in or out with the
  buttons at the bottom right. It opens on now, or on another day at its
  first event.
- Beside the times, a band shows the priority of the most important
  event going on, in its priority's color, labeled "P0" to "P3" where it
  starts and stops; it's clear where nothing is.
- Each event shows its summary, then its goals, the primary goal first,
  each after a diamond in the goal's color.
- An event too short for its text is drawn as tall as it needs: the
  strip down its edge is solid for as long as it lasts and dashed below,
  it says how long it is, and a bracket beside the band marks its real
  span. One pushed down by the event before it is joined by a line to
  where it truly starts.

## 4.8.0

- A goal can be measured by follow-through: each of its events that's
  cancelled (pushed off the calendar, or cancelled in a compaction) costs
  points, 25 unless set, and each day with one that happened wins 25
  back. The rating carries over between, so it stays low until days with
  kept events make it up. It starts at 100 30 days back (or however many
  are set), so an older cancellation is forgotten.

## 4.7.0

- Under "Event properties", tapping a goal on the Goals page opens its
  event properties: its priority, fixed time and color, each saying
  whether it's set on the goal or where it comes from, with "Set" or
  "Clear". Priorities 0 to 3 are a tap away, and "…" takes any other;
  clearing one shows what it'll inherit.

## 4.6.0

- A goal can be measured by a time window: whether one of the day's
  events falls between two times, with a grace and a "zero at", as for
  a time of day. A day without any is rated 0. Lunch between 11:30 and
  1:30, say, measuring "Eat well"'s events.
- Any measure can be rated only on days with events of its goal, or of
  another: other days are skipped, without asking its question. "How did
  practice go?" only on days of practice.
- The Goals page no longer says how many sub-goals a collapsed goal has:
  its arrow says it has some.

## 4.5.0

- Goal saves waiting to be sent, and ones that failed, are kept on the
  phone, so they survive the app closing and switching tabs. They're
  sent the same way notes are: ones that failed for want of a connection
  are tried again by themselves, after 5s, 10s, 20s, 40s, then every
  minute, and on Android the background task sends them once the app is
  closed. Ones the server refused wait to be retried. A new goal that may
  have been made before an answer was lost is looked for before it's made
  again.
- A save to a goal that already has one waiting, or that failed, joins
  it, so they're sent as one edit.
- Signing in again on the Goals page retries every save that failed.
- A note or goal that was just saved no longer goes missing from its
  page until the list is fetched again, whether the app saved it or the
  background task did; notes the background task saved used to stay
  missing until the page was refreshed. Each page fetches once after a
  round of saves, rather than after each.

## 4.4.0

- Saving a goal's details, a new goal, or a measure now closes the dialog
  at once, as adding a note does, and saves in the background: the change
  shows straight away, and a goal still being added shows a spinner in
  place of its menu until the server has made it. Saves go to the server
  one at a time, in order, and the goals are fetched once, after the
  last, rather than after each.
- A save that fails isn't lost: the goal stays, with an error in place
  of its menu, offering to try again, edit, or discard it. Tapping it
  opens what wasn't saved, to change and save again.

## 4.3.2

- "Edit measure" (or "Add a measure") now opens the measure editor in
  place of the Measure dialog rather than over it, so closing the editor
  goes straight back to the goals.

## 4.3.1

- A weighted rollup's weights only list active and inactive sub-goals
  (any weight the others had is kept), and grey out inactive ones,
  saying they aren't rated.
- A count's "What's counted" field no longer starts the keyboard
  capitalized, and says it's for display only.

## 4.3.0

- Tapping a goal, or the Overall card, shows its measure: what kind it
  is, what it rates ("10h per 7 days") and its settings, and how it's
  doing by it: its latest rating, its last 8 days, the days gone
  unrated and its recent time. "Edit measure" (or "Add a measure")
  opens the measure editor over it, saying how the measure reads as you
  change it, or what's missing. "Remove" clears it, asking first; its
  past ratings stay.
- A goal's details, where every property can be changed, are now under
  "Details" in its menu, or the Measure dialog's. The menu also has
  "Measure".

## 4.2.0

- The note sheet has - and + buttons beside the time, to move it a
  minute earlier or later, and a Now button to set it to now.

## 4.1.0

- The Goals page's new menu, beside the status filter, picks what each
  goal shows under its name: the time spent on it and its sub-goals in
  the last 24 hours and 7 days, its measure ("10h per 7 days"), its time
  as a share of each window ("37.5% of 24h · 6% of 7d"), or the priority
  and fixed time it gives its events ("Priority 1 · Fixed time"). The
  Overall card follows it too, though its time is shown even when
  there's none. The choice is kept on the device.
- A goal's measure, priority and fixed time are shown only when their
  option is picked, no longer always under its name.
- The time spent no longer has each window's share after it: pick "Time
  as a percentage" for that.

## 4.0.0

- A time-spent, number-of-events or time-of-day measure can look at
  another goal's events as though they were its own goal's: pick
  "Another goal" under "Events of" (with or without its sub-goals'). A
  "work 40 hours a week" sub-goal can measure its parent's events without
  any being tagged with it. This replaces choosing several goals.
- "Time of day" replaces "Wake-up time": when the day's first event of
  the goal starts, or its last ends, by (or not before) a time, with a
  grace and a "zero at". Measure waking from a "get up" goal's events,
  and work's "in by 9:30" and "out by 5:30" the same way. A goal still
  measured by wake-up time needs its measure changed.
- Needs a server with `events_of` and `time_constraint` measures.

## 3.3.0

- On the Goals page, a goal's time in the last 24 hours and 7 days, and
  the Overall card's, is followed by its share of that window when it's
  more than 1/24 (an hour a day): "9h in 24h (37.5%)".
- A goal's time leaves out a window it has no time in, and isn't shown if
  it has none in either. The Overall card's is always shown.

## 3.2.0

- Each goal's time on the Goals page, like the Overall card's, counts only
  the time through goals with the statuses shown: a paused sub-goal's
  time leaves its active parent's when inactive goals are hidden. Time is
  counted by the statuses of the goals events were given, not their
  parents'. Needs a server that splits each goal's time by status.

## 3.1.0

- The Goals page starts with an Overall card: the overall goal, above all
  the others, rated like any goal (by default, the average of the
  top-level goals'), with its last 8 days. It shows the time spent on the
  goals shown in the last 24 hours and 7 days, each event counted once,
  and follows the status filter. Tapping it shows its details, where its
  measure is set; tapping its ratings shows its history. It can't be a
  parent or be given to an event. Needs a server with the overall goal.

## 3.0.0

- Goals are rated once a day, in the daily reflection, and no longer have
  a cadence. A goal without a measure is rated as the average of its
  sub-goals'. Each goal's strike line is its last 8 days' ratings, and it
  says how many days have gone unrated.
- Measures: time spent and number of events count over the last few days
  ("1 visit per 60 days"), and can fall to 0 by a "zero at" number of days
  since the target was last met. Your rating is asked every few days,
  carried over in between. From sub-goals can be their average, a weighted
  average, or a percentile (0 for the lowest, 100 for the highest).
- The Goals page shows the time spent on each goal (and its sub-goals) in
  the last 24 hours and 7 days, up to when notes were last compacted, which
  it notes at the top.
- On the Goals page, tapping a goal's arrow or flag shows or hides its
  sub-goals, and tapping its ratings shows its history. Its menu adds a
  sub-goal, or shows its history or details. Its status is changed in its
  details, by tapping it.
- The Notes page shows when notes were last compacted, and the latest note
  compacted.
- Needs a server whose goals are rated daily (with `get_compaction_status`).

## 2.8.0

- An event that was never given goals, whose goals are inferred from its
  label, shows them "(from its label)" in its details. Opening them and
  keeping them, changed or not, sets them for real. Saving anything else
  leaves them inferred. Needs a server that sends `goals_from_label`.

## 2.7.0

- Press and hold a goal on the Goals page to reorder goals: drag one by
  its handle among the goals it sits with (its sub-goals go with it), then
  tap Done. The order is saved on the server.
- A time-spent or number-of-events measure can count the events of
  chosen goals (a parent included) rather than its own goal's, with or
  without their sub-goals'. The Goals page names the goals it counts.
- Picking a goal's parent lists the goals as a tree, by name, so a
  sub-goal is easy to tell apart; the pick shows its whole path,
  wrapping if it's long. Event goals are listed the same way.

## 2.6.0

- An event in a recurring series links to the series from its details
  ("Repeats: see or change the series"). The series shows its schedule in
  words, its rules, and the properties its events share, and any of them
  can be changed: for all its events, or for that event and the ones
  after it, which starts a new series from there. Needs a server with
  `get_recurrence` and `update_recurrence`.

## 2.5.0

- On the Goals page, a goal's sub-goals start collapsed, and the goal says
  how many it has. Its arrow expands it to show them, and adding a
  sub-goal expands its parent.
- A goal without its own color shows its flag as an outline in the color
  it inherits, rather than a grey outline filled with that color.

## 2.4.0

- A goal's measure, how each period's health is rated, can be edited in
  its dialog. Pick its kind (time spent, number of events, wake-up time,
  your rating, Claude's judgement, or from its sub-goals), then fill in
  that kind's fields, like "10h" per week or "up by 07:00". It's checked
  before saving, as the server checks it.
- The Goals page and a goal's history say what it's measured by, like
  "10h per week" or "1 dinner per week", in place of just its cadence.

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
