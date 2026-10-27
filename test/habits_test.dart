import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/time_split.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/circle_screen.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/habit_screen.dart';
import 'package:time_tracker_client/screens/habits_pane.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/habits_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/facts_dialog.dart';
import 'package:time_tracker_client/widgets/plan_summaries.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';

/// Creative › Guitar › Play guitar and Practice guitar, and Walk.
final _actions = [
  PlanAction.fromJson({
    'id': 'creative',
    'name': 'Creative',
    'kind': 'group',
    'path': 'Creative',
    'effective_color': '#f4511e',
  }),
  PlanAction.fromJson({
    'id': 'guitar',
    'parent_id': 'creative',
    'name': 'Guitar',
    'kind': 'group',
    'path': 'Creative › Guitar',
    'effective_color': '#f4511e',
  }),
  PlanAction.fromJson({
    'id': 'play',
    'parent_id': 'guitar',
    'name': 'Play guitar',
    'path': 'Creative › Guitar › Play guitar',
  }),
  PlanAction.fromJson({
    'id': 'practice',
    'parent_id': 'guitar',
    'name': 'Practice guitar',
    'path': 'Creative › Guitar › Practice guitar',
  }),
  PlanAction.fromJson({'id': 'walk', 'name': 'Walk', 'path': 'Walk'}),
];

String? _parentOf(String id) =>
    _actions.where((a) => a.id == id).firstOrNull?.parentId;

const _traits = [
  Trait(
    id: 'present',
    name: 'Present',
    parts: [
      {
        'kind': 'judgment',
        'rubric': 'How present was I?',
        'ratings': {'0': 'Distracted', '3': 'Fully'},
        'facts': ['general_notes'],
      },
    ],
  ),
  Trait(
    id: 'reliable',
    name: 'Reliable',
    parts: [
      {'kind': 'count', 'target': 1, 'interval_days': 7},
    ],
  ),
];

const _mindfully = Habit(
  id: 'h1',
  name: 'Practice mindfully',
  actionId: 'guitar',
  note: 'One thing at a time',
  traits: PersonTraits(select: ['present']),
);

void main() {
  group('habits', () {
    test('are read as the server lists them, and sent back as it takes '
        'them', () {
      final habit = Habit.fromJson({
        'id': 'h1',
        'name': 'Practice mindfully',
        'action_id': 'guitar',
        'action_path': 'Creative › Guitar',
        'status': 'active',
        'note': 'One thing at a time',
        'traits': {
          'select': ['present'],
          'parts': {
            'present': [
              {'kind': 'follow_through'},
            ],
          },
        },
        'cancelled_events': [
          {
            'event_id': 'e1',
            'summary': 'Practice',
            'start': '2026-10-01T19:00:00Z',
            'end': '2026-10-01T20:00:00Z',
            'action_ids': ['practice'],
            'parts': ['present/follow_through'],
          },
        ],
      });

      expect(habit.subject, 'habit:h1');
      expect(habit.actionPath, 'Creative › Guitar');
      expect(habit.traits.select, ['present']);
      expect(habit.cancelledEvents.single.traitIds, ['present']);
      expect(habit.toJson(), {
        'id': 'h1',
        'name': 'Practice mindfully',
        'action_id': 'guitar',
        'status': 'active',
        'note': 'One thing at a time',
        'traits': {
          'select': ['present'],
          'parts': {
            'present': [
              {'kind': 'follow_through'},
            ],
          },
        },
      });
      // Every active trait, with theirs, unless it says.
      expect(const Habit(id: 'h2', name: 'Walk', actionId: 'walk').toJson(), {
        'id': 'h2',
        'name': 'Walk',
        'action_id': 'walk',
        'status': 'active',
      });
    });

    test("judgments' subjects say which are a habit's", () {
      expect(habitSubject('h1'), 'habit:h1');
      expect(habitIdOf('habit:h1'), 'h1');
      expect(habitIdOf('sam'), isNull);
    });

    test('are about the action, or any action under the group', () {
      expect(inScope('guitar', 'practice', _parentOf), isTrue);
      expect(inScope('guitar', 'guitar', _parentOf), isTrue);
      expect(inScope('creative', 'play', _parentOf), isTrue);
      expect(inScope('guitar', 'walk', _parentOf), isFalse);
      expect(inScope('practice', 'play', _parentOf), isFalse);
      // A group above it isn't in it.
      expect(inScope('guitar', 'creative', _parentOf), isFalse);
    });

    test("warn of parts that count outside them, or read what's done for "
        'someone', () {
      final warnings = habitPartWarnings(
        [
          {'kind': 'count', 'action': 'practice', 'target': 3},
          {'kind': 'count', 'action': 'walk', 'target': 1},
          {'kind': 'judgment', 'engagement_type': 'for', 'rubric': '?'},
        ],
        'guitar',
        _parentOf,
        {'walk': 'Walk', 'guitar': 'Guitar'},
      );

      expect(warnings, [
        'Number of events of Walk: outside Guitar, so it counts nothing here.',
        "Judgment reads events done for someone: you're at every one of a "
            "habit's, so it's left out.",
      ]);
    });
  });

  group('McpHabitsRepository', () {
    test('lists every habit, whatever its status, and keeps them', () async {
      final client = _Client(
        (name, _) => [
          {'id': 'h1', 'name': 'Practice mindfully', 'action_id': 'guitar'},
        ],
      );
      final cache = InMemoryResponseCache();
      final habits = await McpHabitsRepository(client, cache: cache).habits();

      expect(client.calls.single.$1, 'get_habits');
      expect(client.calls.single.$2, {
        'statuses': ['active', 'archived', 'deleted'],
      });
      expect(habits.single.actionId, 'guitar');
      final kept = await McpHabitsRepository(
        _Client((_, _) => null),
        cache: cache,
      ).cachedHabits();
      expect(kept!.single.name, 'Practice mindfully');
    });

    test('creates one, and updates one, clearing what is null', () async {
      final client = _Client(
        (name, arguments) => switch (name) {
          'create_habit' => {
            'habit': {
              ...(arguments['habit'] as Map),
              'id': 'h1',
              'action_path': 'Creative › Guitar',
            },
            'created_id': 'h1',
          },
          _ => {
            'id': 'h1',
            'name': 'Practice',
            'action_id': 'practice',
            'status': 'archived',
          },
        },
      );
      final repository = McpHabitsRepository(client);

      final created = await repository.createHabit(_mindfully);
      expect(created.id, 'h1');
      expect(created.actionPath, 'Creative › Guitar');
      expect(client.calls.first.$2, {
        'habit': {
          'name': 'Practice mindfully',
          'action_id': 'guitar',
          'status': 'active',
          'note': 'One thing at a time',
          'traits': {
            'select': ['present'],
          },
        },
      });

      final updated = await repository.updateHabit('h1', {
        'action_id': 'practice',
        'status': 'archived',
        'note': null,
        'traits': null,
      });
      expect(updated.status, 'archived');
      expect(client.calls.last.$1, 'update_habit');
      expect(client.calls.last.$2, {
        'habit': {'id': 'h1', 'action_id': 'practice', 'status': 'archived'},
        'clear_fields': ['note', 'traits'],
      });
    });
  });

  group('InMemoryHabitsRepository', () {
    test('checks names and actions, as the server does', () async {
      final repository = InMemoryHabitsRepository([_mindfully]);

      expect(
        () => repository.createHabit(
          const Habit(id: '', name: 'practice MINDFULLY', actionId: 'walk'),
        ),
        throwsA(isA<McpException>()),
      );
      expect(
        () => repository.createHabit(
          const Habit(id: '', name: 'Walk', actionId: ''),
        ),
        throwsA(isA<McpException>()),
      );
      final walk = await repository.createHabit(
        const Habit(id: '', name: 'Walk daily', actionId: 'walk'),
      );
      expect(walk.id, 'walk-daily');
    });

    test('keeps what it cancelled through an update', () async {
      final repository = InMemoryHabitsRepository([
        _mindfully.withCancelledEvents([
          CancelledEvent(
            start: DateTime(2026, 10, 1, 19),
            end: DateTime(2026, 10, 1, 20),
          ),
        ]),
      ]);

      final updated = await repository.updateHabit('h1', {'note': null});

      expect(updated.note, isNull);
      expect(updated.cancelledEvents, hasLength(1));
    });
  });

  group('PlanMemory', () {
    test(
      'loads habits best effort: a server without them leaves none',
      () async {
        final memory = PlanMemory();

        await memory.loadHabits(_Failing());

        expect(memory.habits, isNull);
        await memory.loadHabits(
          InMemoryHabitsRepository([_mindfully]),
          again: true,
        );
        expect(memory.habits!.single.name, 'Practice mindfully');
      },
    );
  });

  group("The Habits pane's summary", () {
    final asOf = DateTime(2026, 10, 11, 12);
    final window = SummaryWindow(asOf: asOf);
    final byId = {for (final a in _actions) a.id: a};
    const walking = Habit(id: 'h2', name: 'Walk daily', actionId: 'walk');
    const archived = Habit(
      id: 'h3',
      name: 'Old',
      actionId: 'walk',
      status: 'archived',
    );

    /// An hour of [actionIds], [hoursAgo] hours before [asOf].
    Event hour(String id, List<String> actionIds, int hoursAgo) =>
        Event.fromJson({
          'id': id,
          'summary': id,
          'start': localIsoTimestamp(asOf.subtract(Duration(hours: hoursAgo))),
          'end': localIsoTimestamp(
            asOf.subtract(Duration(hours: hoursAgo - 1)),
          ),
          'action_ids': actionIds,
        });

    final events = [
      // In the guitar group, so the habit on it.
      hour('practice', ['practice'], 3),
      hour('walk', ['walk'], 5),
      // Both: split between them.
      hour('both', ['play', 'walk'], 7),
      hour('creative', ['creative'], 9),
    ];

    Duration? time(List<SummarySlice> shares, String label) =>
        shares.where((s) => s.label == label).firstOrNull?.time;

    test('splits the time by the active habits, the rest "No habit"', () {
      final (day, _) = habitTime(events, window, const [
        _mindfully,
        walking,
        archived,
      ], byId);

      expect(time(day, 'Practice mindfully'), const Duration(minutes: 90));
      expect(time(day, 'Walk daily'), const Duration(minutes: 90));
      expect(time(day, 'Old'), isNull);
      expect(time(day, 'No habit'), const Duration(hours: 1));
    });

    test("and by each habit's health band, those unscored together", () {
      final (day, _) = habitHealthTime(
        events,
        window,
        const [_mindfully, walking],
        byId,
        (habit) => habit.id == 'h1' ? 80 : null,
      );

      expect(time(day, 'on track'), const Duration(minutes: 90));
      expect(time(day, 'Not scored yet'), const Duration(minutes: 90));
      expect(time(day, 'No habit'), const Duration(hours: 1));
    });
  });

  group('The Habits pane', () {
    Future<PlanMemory> pump(
      WidgetTester tester, {
      HabitsRepository? habits,
      PeopleRepository? people,
      Widget Function(Widget pane)? around,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final memory =
          PlanMemory(
              eventStore: EventStore(repository: InMemoryEventsRepository()),
            )
            ..traits = _traits
            ..people = people == null
                ? const PeopleList()
                : await people.people()
            ..actions = ActionList(actions: _actions);
      await memory.eventStore!.warm();
      final habitsPane = HabitsPane(
        repository: habits ?? InMemoryHabitsRepository(),
        memory: memory,
        actions: _actions,
      );
      final pane = MaterialApp(
        home: Scaffold(body: around?.call(habitsPane) ?? habitsPane),
      );
      await tester.pumpWidget(
        people == null ? pane : PeopleScope(repository: people, child: pane),
      );
      await tester.pumpAndSettle();
      return memory;
    }

    testWidgets("a person's habit's page opens theirs, a tap away", (
      tester,
    ) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          const Habit(
            id: 'h4',
            name: 'Close to Ana',
            actionId: '',
            personId: 'ana',
          ),
        ]),
        people: InMemoryPeopleRepository(
          people: const [Person(id: 'ana', name: 'Ana')],
        ),
      );
      await tester.tap(find.text('Close to Ana'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Ana'), findsOneWidget);
    });

    testWidgets("a circle's habit's page opens its, a tap away", (
      tester,
    ) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          const Habit(
            id: 'h5',
            name: 'Close to the pals',
            actionId: '',
            circleId: 'pals',
          ),
        ]),
        people: InMemoryPeopleRepository(
          people: const [
            Person(id: 'ana', name: 'Ana', circleIds: ['pals']),
          ],
          circles: const [Circle(id: 'pals', name: 'Pals')],
        ),
      );
      await tester.tap(find.text('Close to the pals'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pals'));
      await tester.pumpAndSettle();
      expect(find.byType(CircleScreen), findsOneWidget);
      expect(find.text('1 person'), findsOneWidget);
    });

    testWidgets('shows them by name, archived ones when asked', (tester) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          _mindfully,
          const Habit(
            id: 'h2',
            name: 'Walk daily',
            actionId: 'walk',
            status: 'archived',
          ),
          const Habit(
            id: 'h3',
            name: 'Gone',
            actionId: 'walk',
            status: 'deleted',
          ),
        ]),
      );

      expect(find.text('Practice mindfully'), findsOneWidget);
      expect(find.text('Layer 0'), findsOneWidget);
      expect(find.text('Walk daily'), findsNothing);

      await tester.tap(find.byTooltip('Show archived habits'));
      await tester.pumpAndSettle();
      expect(find.text('Walk daily'), findsOneWidget);
      expect(find.text('Gone'), findsNothing);
    });

    testWidgets("scrolls only its own list as it opens, not what it's in", (
      tester,
    ) async {
      // As the Plan screen's panes are, swiped partway past it.
      final panes = ScrollController(initialScrollOffset: 400);
      addTearDown(panes.dispose);
      await pump(
        tester,
        habits: InMemoryHabitsRepository([_mindfully]),
        around: (pane) => SingleChildScrollView(
          controller: panes,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(width: 800, child: pane),
              const SizedBox(width: 800),
            ],
          ),
        ),
      );

      expect(find.text('Layer 0'), findsOneWidget);
      expect(panes.offset, 400);
    });

    testWidgets('layers them by what they are built on, layer 0 lowest', (
      tester,
    ) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          const Habit(id: 'sleep', name: 'Sleep well', actionId: 'walk'),
          const Habit(id: 'eat', name: 'Eat well', actionId: 'walk'),
          const Habit(
            id: 'gym',
            name: 'Exercise',
            actionId: 'walk',
            foundations: ['habit:sleep', 'habit:eat'],
          ),
          const Habit(
            id: 'run',
            name: 'Run a race',
            actionId: 'walk',
            foundations: ['habit:gym', 'habit:sleep'],
          ),
        ]),
      );
      // Rated 0, with no events: what's built on them waits.
      expect(find.text('Exercise'), findsNothing);
      expect(
        find.text('2 more wait on foundations not yet on track.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Show all habits'));
      await tester.pumpAndSettle();

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Layer 2'), lessThan(top('Layer 1')));
      expect(top('Layer 1'), lessThan(top('Layer 0')));
      expect(top('Run a race'), lessThan(top('Exercise')));
      expect(top('Exercise'), lessThan(top('Sleep well')));
      expect(top('Eat well'), top('Sleep well'));
    });

    testWidgets('searches what it shows, with everything a match is built on', (
      tester,
    ) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          const Habit(id: 'sleep', name: 'Sleep well', actionId: 'walk'),
          const Habit(id: 'eat', name: 'Eat well', actionId: 'walk'),
          const Habit(
            id: 'gym',
            name: 'Exercise',
            actionId: 'walk',
            foundations: ['habit:sleep'],
          ),
        ]),
      );
      await tester.enterText(find.byType(TextField), 'exer');
      await tester.pumpAndSettle();
      // Waiting on a foundation rated 0, so not shown, nor found.
      expect(find.text('Exercise'), findsNothing);

      await tester.tap(find.byTooltip('Show all habits'));
      await tester.pumpAndSettle();

      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('Sleep well'), findsOneWidget);
      expect(find.text('Eat well'), findsNothing);
      final spans =
          (tester.widget<Text>(find.text('Exercise')).textSpan! as TextSpan)
              .children!
              .cast<TextSpan>();
      expect([for (final s in spans) s.text], ['Exer', 'cise']);
      expect(spans.first.style?.backgroundColor, isNotNull);
      expect(spans.last.style, isNull);
    });

    testWidgets("adds a person's habit, as a chip of theirs", (tester) async {
      final people = InMemoryPeopleRepository(
        people: const [Person(id: 'fam', name: 'Family')],
      );
      final habits = InMemoryHabitsRepository([_mindfully]);
      await pump(tester, habits: habits, people: people);
      expect(find.text('Family'), findsNothing);

      await tester.tap(find.byTooltip('New habit for a person or circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Family'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final added = (await habits.habits()).firstWhere((h) => h.isRelationship);
      expect((added.personId, added.name), ('fam', 'Family'));
      expect(find.text('Family'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Family'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.person),
        ),
        findsOneWidget,
      );
    });

    testWidgets("adds a circle's habit, picked from the circles alone", (
      tester,
    ) async {
      final people = InMemoryPeopleRepository(
        people: const [
          Person(id: 'ana', name: 'Ana', circleIds: ['pals']),
        ],
        circles: const [Circle(id: 'pals', name: 'Pals')],
      );
      final habits = InMemoryHabitsRepository([_mindfully]);
      await pump(tester, habits: habits, people: people);

      await tester.tap(find.byTooltip('New habit for a person or circle'));
      await tester.pumpAndSettle();
      // Everyone, searched; a circle marked as one (a plain one, a ring).
      expect(find.widgetWithText(ListTile, 'Ana'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Pals'),
          matching: find.byIcon(Icons.circle_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Circles'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Ana'), findsNothing);
      expect(find.text('Add circle…'), findsOneWidget);
      expect(find.text('Add person…'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Pals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final added = (await habits.habits()).firstWhere((h) => h.isRelationship);
      expect((added.circleId, added.name), ('pals', 'Pals'));
    });

    testWidgets('picks what one is built on from its menu', (tester) async {
      final repository = InMemoryHabitsRepository([
        _mindfully,
        const Habit(id: 'h2', name: 'Walk daily', actionId: 'walk'),
      ]);
      await pump(tester, habits: repository);

      await tester.longPress(find.text('Walk daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Built on…'));
      await tester.pumpAndSettle();
      // In a sheet up from the foot, its search focused.
      final search = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
      // Not itself.
      expect(find.widgetWithText(CheckboxListTile, 'Walk daily'), findsNothing);
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Practice mindfully'),
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        (await repository.habits()).firstWhere((h) => h.id == 'h2').foundations,
        ['habit:h1'],
      );
      expect(find.text('Layer 1'), findsOneWidget);
    });

    testWidgets('searches them by name, action and note', (tester) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          _mindfully,
          const Habit(id: 'h2', name: 'Walk daily', actionId: 'walk'),
        ]),
      );

      await tester.enterText(find.byType(TextField), 'guitar');
      await tester.pumpAndSettle();
      expect(find.text('Practice mindfully'), findsOneWidget);
      expect(find.text('Walk daily'), findsNothing);

      await tester.enterText(find.byType(TextField), 'one thing');
      await tester.pumpAndSettle();
      expect(find.text('Practice mindfully'), findsOneWidget);
    });

    testWidgets('archives one from its menu', (tester) async {
      final repository = InMemoryHabitsRepository([_mindfully]);
      await pump(tester, habits: repository);

      await tester.longPress(find.text('Practice mindfully'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect((await repository.habits()).single.status, 'archived');
      expect(find.text('Practice mindfully'), findsNothing);
    });

    testWidgets("says so if they can't be loaded", (tester) async {
      await pump(tester, habits: _Failing());

      expect(find.text("Couldn't load the habits."), findsOneWidget);
    });

    testWidgets("aren't on Self's page any more", (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            person: defaultSelf,
            traits: InMemoryTraitsRepository(traits: _traits),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Habits'), findsNothing);
    });

    testWidgets('adds one, on a group, with its own parts', (tester) async {
      final repository = InMemoryHabitsRepository();
      await pump(tester, habits: repository);

      expect(find.textContaining('No habits yet.'), findsOneWidget);
      await tester.tap(find.byTooltip('New habit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Practice mindfully',
      );
      await tester.tap(find.text('Pick an action or group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'guitar',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guitar').last);
      await tester.pumpAndSettle();
      expect(find.text('Creative › Guitar'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'One thing at a time',
      );
      // Reliable, of its own: counting walks warns that they're outside it.
      await tester.tap(find.byTooltip('Its own Reliable parts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any action'));
      await tester.pumpAndSettle();
      // Only what's in it is offered.
      expect(find.text('Walk'), findsNothing);
      await tester.tap(find.text('Creative › Guitar › Practice guitar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final habit = (await repository.habits()).single;
      expect(habit.name, 'Practice mindfully');
      expect(habit.actionId, 'guitar');
      expect(habit.note, 'One thing at a time');
      expect(habit.traits.select, isNull);
      expect(habit.traits.parts['reliable']!.single['action'], 'practice');
      expect(find.text('Practice mindfully'), findsOneWidget);
    });

    testWidgets("adds a recurring goal's, with no action", (tester) async {
      final repository = InMemoryHabitsRepository();
      await pump(tester, habits: repository);

      await tester.tap(find.byTooltip('New habit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Call Mom',
      );
      await tester.tap(find.text('A recurring goal'));
      await tester.pumpAndSettle();
      expect(find.text('Pick an action or group'), findsNothing);
      // Its goal rate's span follows the period till it's typed.
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      await tester.tap(find.text('Month'));
      // Its definition of done and note are HTML, edited as a goal's.
      await tester.tap(find.text('Add definition of done'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '<p>We talked for <b>20</b> minutes</p>',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Add definition of done'), findsNothing);
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '<p>Keep in touch</p>',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Goal rate counts the last'),
        '3',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final habit = (await repository.habits()).single;
      expect(habit.isGoal, isTrue);
      expect(habit.actionId, '');
      expect(habit.recurringGoal!.toJson(), {
        'period': 'month',
        'definition_of_done': '<p>We talked for <b>20</b> minutes</p>',
        'rate_periods': 3,
      });
      expect(habit.note, '<p>Keep in touch</p>');
      // Scored by its goal rate alone, till it's given traits.
      expect(habit.traits.select, isEmpty);
    });

    testWidgets('warns of its own parts that count nothing', (tester) async {
      await pump(
        tester,
        habits: InMemoryHabitsRepository([
          const Habit(
            id: 'h1',
            name: 'Practice mindfully',
            actionId: 'practice',
            traits: PersonTraits(
              parts: {
                'reliable': [
                  {'kind': 'count', 'action': 'walk', 'target': 1},
                ],
              },
            ),
          ),
        ]),
      );

      await tester.tap(find.text('Practice mindfully'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Practice mindfully'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Reliable: Number of events of Walk: outside Creative › Guitar › '
          'Practice guitar, so it counts nothing here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('opens its page, and edits it there', (tester) async {
      final repository = InMemoryHabitsRepository([_mindfully]);
      await pump(tester, habits: repository);

      await tester.tap(find.text('Practice mindfully'));
      await tester.pumpAndSettle();

      expect(find.byType(HabitScreen), findsOneWidget);
      expect(find.text('Creative › Guitar'), findsOneWidget);
      expect(find.text('Your events with any action in it'), findsOneWidget);
      expect(find.text('One thing at a time'), findsOneWidget);
      // Applying, and scored.
      expect(find.text('Present'), findsWidgets);
      expect(
        find.text("Nothing cancelled that counts against its follow-through."),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Edit Practice mindfully'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await repository.habits()).single.status, 'archived');
      expect(
        find.text('Your events with any action in it · Archived'),
        findsOneWidget,
      );
    });
  });

  testWidgets("a recurring goal's habit's page shows its goal and its goals", (
    tester,
  ) async {
    final habit = Habit.fromJson({
      'id': 'h1',
      'name': 'Call Mom',
      'recurring_goal': {'period': 'week', 'definition_of_done': 'We talked'},
      'traits': {'select': <String>[]},
      'status': 'active',
    });
    Goal goal(String start, String status, List<String> changes) =>
        Goal.fromJson({
          'id': 'h1_$start',
          'title': 'Call Mom',
          'habit_id': 'h1',
          'status': status,
          'deadline': {'at': '2026-12-31'},
          'due': '2026-12-31',
          'history': [
            for (final c in changes)
              {'status': c, 'at': '${start}T00:00:00-04:00'},
          ],
        });
    final memory = PlanMemory()
      ..goals = [
        goal('2026-10-11', 'done', ['active', 'done']),
        goal('2026-10-18', 'active', ['active', 'missed', 'active']),
        Goal.fromJson({'id': 'other', 'title': 'Other'}),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: HabitScreen(habit: habit, memory: memory),
      ),
    );

    expect(find.text('A goal each week: Call Mom'), findsOneWidget);
    expect(find.textContaining('We talked'), findsOneWidget);
    expect(find.text('Its goals'), findsOneWidget);
    expect(find.text('From Sun, Oct 18'), findsOneWidget);
    expect(find.textContaining('tried again'), findsOneWidget);
    expect(find.text('From Sun, Oct 11'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets("a recurring goal's goal's page opens its habit's", (
    tester,
  ) async {
    final habit = Habit.fromJson({
      'id': 'h1',
      'name': 'Call Mom',
      'recurring_goal': {'period': 'week'},
      'traits': {'select': <String>[]},
      'status': 'active',
    });
    final goal = Goal.fromJson({
      'id': 'h1_2026-10-18',
      'title': 'Call Mom',
      'habit_id': 'h1',
      'status': 'active',
      'deadline': {'at': '2026-10-24'},
      'history': [
        {'status': 'active', 'at': '2026-10-18T00:00:00-04:00'},
      ],
    });
    final memory = PlanMemory()
      ..habits = [habit]
      ..goals = [goal];
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      HabitsScope(
        repository: InMemoryHabitsRepository([habit]),
        child: MaterialApp(
          home: GoalScreen(
            goalId: goal.id,
            repository: InMemoryGoalsRepository([goal]),
            memory: memory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('From the habit Call Mom'));
    // Its page doesn't settle here, with no events to score it from.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HabitScreen), findsOneWidget);
    expect(find.text('A goal each week: Call Mom'), findsOneWidget);
  });

  testWidgets("a habit's page shows what it's built on", (tester) async {
    final builtOn = Habit.fromJson({
      'id': 'h1',
      'name': 'Practice mindfully',
      'action_id': 'guitar',
      'status': 'active',
      'foundations': ['self/sleep', 'p1', 'gone'],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HabitScreen(
          habit: builtOn,
          foundationNames: const {'self/sleep': 'Sleep well', 'p1': 'Ana'},
        ),
      ),
    );
    expect(find.text('Built on'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Sleep well'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Ana'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'gone'), findsOneWidget);

    // A new page, not this one with another habit.
    await tester.pumpWidget(
      MaterialApp(
        home: HabitScreen(key: const ValueKey('h1'), habit: _mindfully),
      ),
    );
    expect(
      find.text('Nothing: it sits at the bottom of the habit graph.'),
      findsOneWidget,
    );
  });

  testWidgets('its cancelled events are in brief, the lot a tap away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?> cancelled(String id, int day) => {
      'event_id': id,
      'summary': 'Practice $id',
      'start': '2026-10-0${day}T19:00:00Z',
      'end': '2026-10-0${day}T20:00:00Z',
      'action_ids': ['practice'],
      'parts': ['present/follow_through'],
    };
    final habit = Habit.fromJson({
      'id': 'h1',
      'name': 'Practice mindfully',
      'action_id': 'guitar',
      'status': 'active',
      'traits': {
        'scoring': {'statistic': 'percentile', 'percentile': 25},
      },
      'cancelled_events': [
        cancelled('a', 1),
        cancelled('b', 2),
        cancelled('c', 3),
      ],
    });
    await tester.pumpWidget(MaterialApp(home: HabitScreen(habit: habit)));

    expect(find.text('Combined: 25th percentile'), findsOneWidget);
    expect(find.text('3 cancelled · 3h planned'), findsOneWidget);
    expect(find.text('Practice c'), findsOneWidget);
    expect(find.text('Practice a'), findsOneWidget);
    expect(find.text('Practice b'), findsNothing);

    await tester.tap(find.text('All cancelled events'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled · Practice mindfully'), findsOneWidget);
    expect(find.text('Practice b'), findsOneWidget);
  });

  group('A habit, scored', () {
    /// Yesterday's practice, judged fully present for the habit.
    Event practice() {
      final now = DateTime.now();
      return Event.fromJson({
        'id': 'practice',
        'summary': 'Practice guitar',
        'start': localIsoTimestamp(
          DateTime(now.year, now.month, now.day - 1, 19),
        ),
        'end': localIsoTimestamp(
          DateTime(now.year, now.month, now.day - 1, 20),
        ),
        'action_ids': ['practice'],
        'judgments': {
          'habit:h1': {
            'present': {
              'judgment': {
                'rating': 3,
                'scale': 3,
                'reasoning': 'One thing, slowly',
              },
            },
          },
        },
      });
    }

    testWidgets("shows its health, each trait's score, and its events", (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final memory =
          PlanMemory(
              eventStore: EventStore(
                repository: InMemoryEventsRepository([practice()]),
              ),
            )
            ..traits = _traits
            ..people = const PeopleList()
            ..actions = ActionList(actions: _actions);
      await memory.eventStore!.warm();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitsPane(
              repository: InMemoryHabitsRepository([_mindfully]),
              memory: memory,
              actions: _actions,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practice mindfully'));
      await tester.pumpAndSettle();

      expect(find.text('Health'), findsOneWidget);
      expect(find.text('on track'), findsOneWidget);
      expect(find.text('How present was I? 100'), findsOneWidget);
      expect(find.text('Practice guitar'), findsOneWidget);
      expect(find.text("Combined: mean, the defaults'"), findsOneWidget);

      // In brief, the lot on a page of its own.
      expect(find.text('The only one'), findsOneWidget);
      await tester.tap(find.text('All events'));
      await tester.pumpAndSettle();
      expect(find.text('Events · Practice mindfully'), findsOneWidget);
      expect(find.text('Practice guitar'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Pulling down loads the events again.
      await tester.fling(find.text('Health'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Practice guitar'), findsOneWidget);

      await tester.tap(find.text('How present was I? 100'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rated 3: One thing, slowly'), findsOneWidget);
    });

    testWidgets("its judgments are named by it in an event's notes", (
      tester,
    ) async {
      final memory = PlanMemory()..habits = [_mindfully];
      await tester.pumpWidget(
        MaterialApp(
          // Above the navigator, as in the app, for the dialog to find.
          builder: (context, child) =>
              PlanMemoryScope(memory: memory, child: child!),
          home: Material(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFactsDialog(
                  context,
                  null,
                  judgments: judgmentsFromJson(
                    practice().properties['judgments'],
                  ),
                  traitNames: const {'present': 'Present'},
                  pickers: false,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Practice mindfully (habit) · Present: 3 of 3 — One thing, slowly',
        ),
        findsOneWidget,
      );
    });
  });
}

/// A server without habits.
class _Failing implements HabitsRepository {
  @override
  Future<List<Habit>> habits() async =>
      throw McpException('Unknown tool: get_habits');

  @override
  Future<List<Habit>?> cachedHabits() async => null;

  @override
  Future<Habit> createHabit(Habit habit) => throw UnimplementedError();

  @override
  Future<Habit> updateHabit(String id, Map<String, Object?> changes) =>
      throw UnimplementedError();
}

/// Records each tool call, and answers with [answer].
class _Client extends McpClient {
  _Client(this.answer) : super(endpoint: Uri.parse('http://test'));

  final Object? Function(String name, Map<String, Object?> arguments) answer;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}
