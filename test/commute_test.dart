import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/commute.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart' show localIsoTimestamp;
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/travel_time.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/pending_event_box.dart';

/// The cafe, and the office downtown; ways of getting about: driving, and
/// transit, a group with the subway in it.
const _locations = [
  Location(id: 'cafe', name: 'The cafe'),
  Location(id: 'office', name: 'The office', groupId: 'downtown'),
];
const _groups = [LocationGroup(id: 'downtown', name: 'Downtown')];
const _actions = [
  PlanAction(
    id: 'drive',
    name: 'Drive',
    path: 'Drive',
    properties: {'commute': true},
  ),
  PlanAction(
    id: 'transit',
    name: 'Transit',
    path: 'Transit',
    properties: {'kind': 'group'},
  ),
  PlanAction(
    id: 'subway',
    name: 'Subway',
    parentId: 'transit',
    path: 'Transit › Subway',
    properties: {'commute': true},
  ),
  PlanAction(
    id: 'walk',
    name: 'Walk',
    path: 'Walk',
    properties: {'commute': true},
  ),
];
const _travel = [
  TravelTime(
    id: 't1',
    fromId: 'cafe',
    toId: 'downtown',
    times: [
      TravelMode(modeId: 'drive', minutes: 20, maxMinutes: 30),
      TravelMode(modeId: 'transit', minutes: 35),
    ],
  ),
];

void main() {
  group('the travel times, as commutes', () {
    test('a range is taken at its middle, rounded up to five minutes', () {
      expect(commuteMinutes(const TravelMode(modeId: 'm', minutes: 20)), 20);
      expect(
        commuteMinutes(
          const TravelMode(modeId: 'm', minutes: 25, maxMinutes: 40),
        ),
        35,
      );
      expect(
        commuteMinutes(
          const TravelMode(modeId: 'm', minutes: 20, maxMinutes: 30),
        ),
        25,
      );
    });

    test('each action with a time, its own or its group\'s, between the '
        'places or the groups they\'re in, quickest first', () {
      final options = commuteOptions(
        fromId: 'office',
        toId: 'cafe',
        actions: _actions,
        travelTimes: _travel,
        locations: _locations,
        groups: _groups,
      );
      expect(options.map((o) => (o.action.id, o.minutes, o.travel.id)), [
        ('drive', 25, 't1'),
        ('subway', 35, 't1'),
      ]);
      // Nothing between a place and itself, or by what has no time.
      expect(
        commuteOptions(
          fromId: 'cafe',
          toId: 'cafe',
          actions: _actions,
          travelTimes: _travel,
          locations: _locations,
          groups: _groups,
        ),
        isEmpty,
      );
    });

    test('a one-way travel time is only that way, and beats a two-way one', () {
      const travel = [
        ..._travel,
        TravelTime(
          id: 't2',
          fromId: 'office',
          toId: 'cafe',
          oneWay: true,
          times: [TravelMode(modeId: 'drive', minutes: 45)],
        ),
      ];
      int? drive(String from, String to) => estimateTravel(
        fromId: from,
        toId: to,
        modeIds: const ['drive'],
        travelTimes: travel,
        locations: _locations,
        groups: _groups,
      )?.time.minutes;
      expect(drive('office', 'cafe'), 45);
      expect(drive('cafe', 'office'), 20);
    });
  });

  group('moving an event', () {
    final day = DateTime(2026, 9, 30);
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 9, 30, hour, minute);

    Event event(
      String id,
      String summary,
      DateTime start,
      DateTime end, {
      Map<String, Object?> facts = const {},
    }) => Event(
      id: id,
      start: start,
      end: end,
      summary: summary,
      properties: {'summary': summary, if (facts.isNotEmpty) 'facts': facts},
    );

    Future<_Recording> pump(
      WidgetTester tester,
      List<Event> events, {
      EventOutbox Function(_Recording repo)? outbox,
      PeopleRepository? people,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Recording(events);
      final queue = outbox?.call(repo);
      final memory = PlanMemory()
        ..locations = _locations
        ..locationGroups = _groups
        ..travelTimes = _travel
        ..actions = const ActionList(actions: _actions);
      Widget scoped(Widget child) => people == null
          ? child
          : PeopleScope(repository: people, child: child);
      await tester.pumpWidget(
        MaterialApp(
          home: AppSettingsScope(
            settings: AppSettings(
              persist: false,
              grid: const Duration(hours: 1),
            )..setSnap(const {}),
            child: scoped(
              EventsScreen(
                repository: repo,
                serverLabel: 'test',
                memory: memory,
                actionsRepository: InMemoryActionsRepository(_actions),
                eventOutbox: queue,
                clock: () => day.add(const Duration(hours: 8)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    /// Lets what's changing play out, for a while: an event the box runs
    /// into pulses for as long as it does.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    PendingEventBoxView view(WidgetTester tester) =>
        tester.widget(find.byType(PendingEventBoxView));

    testWidgets('a commute to the next event is picked from the ways the '
        'travel times have, and made with the move, against its foot', (
      tester,
    ) async {
      final repo = await pump(tester, [
        event(
          'tea',
          'Tea',
          at(12),
          at(13),
          facts: {
            'location_ids': ['cafe'],
          },
        ),
        event(
          'work',
          'Work',
          at(14),
          at(17),
          facts: {
            'location_ids': ['office'],
          },
        ),
      ]);
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      // Nothing before it: only the foot has one.
      expect(view(tester).commuteEnds, {false});
      expect(
        find.byTooltip('Add a commute from the event before'),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Add a commute to the event after'));
      await tester.pumpAndSettle();
      expect(find.text('Commute from The cafe to The office'), findsOneWidget);
      expect(find.text('25m (20m–30m)'), findsOneWidget);
      expect(find.text('Subway'), findsOneWidget);
      // Walking has no time: it isn't offered.
      expect(find.text('Walk'), findsNothing);
      await tester.tap(find.text('Drive'));
      await tester.pumpAndSettle();
      expect(view(tester).queued, {false});
      expect(view(tester).pushed.single, (
        start: at(13),
        end: at(13, 25),
        label: 'Drive (commute)',
      ));

      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.created, [
        {
          'summary': 'Drive',
          'start': localIsoTimestamp(at(13)),
          'end': localIsoTimestamp(at(13, 25)),
          'action_ids': ['drive'],
          'facts': {'commute': true},
        },
      ]);
    });

    testWidgets('queued in the outbox, the commute is made once, and only '
        'once the move is', (tester) async {
      late EventOutbox queue;
      final repo = await pump(
        tester,
        [
          event(
            'tea',
            'Tea',
            at(12),
            at(13),
            facts: {
              'location_ids': ['cafe'],
            },
          ),
          event(
            'work',
            'Work',
            at(14),
            at(17),
            facts: {
              'location_ids': ['office'],
            },
          ),
        ],
        outbox: (repo) =>
            queue = EventOutbox(store: InMemoryOutboxStore(), events: repo),
      );
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a commute to the event after'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drive'));
      await tester.pumpAndSettle();
      // Nothing made till the move is.
      expect(repo.created, isEmpty);
      expect(queue.items, isEmpty);
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      await queue.flush(ignoreBackoff: true);
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(repo.created.length, 1);
      // One event: its title, and its action under it.
      expect(find.text('Drive'), findsNWidgets(2));
    });

    testWidgets('between places no travel time covers, the button still '
        'shows, and a travel time added from it is offered at once', (
      tester,
    ) async {
      final people = InMemoryPeopleRepository(
        locations: [
          ..._locations,
          const Location(id: 'gym', name: 'The gym'),
        ],
        locationGroups: _groups,
        travelTimes: _travel,
      );
      final repo = await pump(tester, [
        event(
          'tea',
          'Tea',
          at(12),
          at(13),
          facts: {
            'location_ids': ['cafe'],
          },
        ),
        event(
          'lift',
          'Lift',
          at(14),
          at(15),
          facts: {
            'location_ids': ['gym'],
          },
        ),
      ], people: people);
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a commute to the event after'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No travel times say'), findsOneWidget);
      await tester.tap(find.text('Add a travel time…'));
      await tester.pumpAndSettle();

      // From and to as the commute is; a way, and how long.
      expect(find.text('The cafe'), findsOneWidget);
      expect(find.text('The gym'), findsOneWidget);
      await tester.tap(find.widgetWithText(InputDecorator, 'By'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Walk').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Takes'), '15');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final added = (await people.travelTimes()).last;
      expect((added.fromId, added.toId), ('cafe', 'gym'));
      // Asked again, with it.
      expect(find.textContaining('No travel times say'), findsNothing);
      await tester.tap(find.text('Walk'));
      await tester.pumpAndSettle();
      expect(view(tester).pushed.single.label, 'Walk (commute)');
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.created.single['summary'], 'Walk');
    });

    testWidgets('a queued commute rides with the box, and goes again when '
        'its button is tapped', (tester) async {
      await pump(tester, [
        event(
          'tea',
          'Tea',
          at(12),
          at(13),
          facts: {
            'location_ids': ['cafe'],
          },
        ),
        event(
          'work',
          'Work',
          at(14),
          at(17),
          facts: {
            'location_ids': ['office'],
          },
        ),
      ]);
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add a commute to the event after'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subway'));
      await tester.pumpAndSettle();
      // An hour later: the commute's against its foot still, and Work is
      // trimmed where the commute runs into it.
      await tester.tap(find.byTooltip('Stretch it later').last);
      await settle(tester);
      expect(view(tester).pushed.first, (
        start: at(14),
        end: at(14, 35),
        label: 'Subway (commute)',
      ));

      await tester.tap(find.byTooltip('Take the commute away'));
      await settle(tester);
      expect(view(tester).queued, isEmpty);
      expect(view(tester).pushed, isEmpty);
    });

    testWidgets("no commute where there's one already, or the places are the "
        "same, and a commute that's there goes where the event goes", (
      tester,
    ) async {
      final repo = await pump(tester, [
        event(
          'home',
          'Breakfast',
          at(9),
          at(10),
          facts: {
            'location_ids': ['cafe'],
          },
        ),
        event(
          'tea',
          'Tea',
          at(11),
          at(12),
          facts: {
            'location_ids': ['cafe'],
          },
        ),
        event('ride', 'Drive', at(12), at(12, 30), facts: {'commute': true}),
        event(
          'work',
          'Work',
          at(13),
          at(17),
          facts: {
            'location_ids': ['office'],
          },
        ),
      ]);
      await tester.longPress(find.text('Tea'));
      await settle(tester);
      // Before it, the same place; after it, a commute already.
      expect(view(tester).commuteEnds, isEmpty);
      // The commute after it starts out pushed down, with it.
      await tester.tap(find.byTooltip('Stretch it later').last);
      await settle(tester);
      expect(view(tester).pushed.single, (
        start: at(13),
        end: at(13, 30),
        label: 'Drive',
      ));
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.saved['ride'], {
        'start': localIsoTimestamp(at(13)),
        'end': localIsoTimestamp(at(13, 30)),
      });
    });
  });
}

/// Records what's made, and each event's changes by id.
class _Recording extends InMemoryEventsRepository {
  _Recording(super.events);

  final created = <Map<String, Object?>>[];
  final saved = <String, Map<String, Object?>>{};

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    created.add(fields);
    return super.createEvent(fields);
  }

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    saved[event.id!] = changes;
    return super.updateEvent(event, changes);
  }
}
