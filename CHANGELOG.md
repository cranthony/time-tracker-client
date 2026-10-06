# Changelog

Each release's version is in `pubspec.yaml` (the part before the `+`; CI
supplies the build number). Bump it in every pull request that changes the
app, following [semantic versioning](https://semver.org): patch for fixes,
minor for new features, major for changes that break something you rely
on. Add the new version's section here at the same time; CI checks both.

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
