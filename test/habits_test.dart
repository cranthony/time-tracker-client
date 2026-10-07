import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/habit_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/focus_store.dart';
import 'package:time_tracker_client/services/habits_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/facts_dialog.dart';

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

  group("Self's habits", () {
    Future<void> pump(
      WidgetTester tester, {
      Person person = defaultSelf,
      HabitsRepository? habits,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            person: person,
            traits: InMemoryTraitsRepository(traits: _traits),
            habits: habits,
            actions: _actions,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('are listed on their page, by name and action', (tester) async {
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

      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Practice mindfully'), findsOneWidget);
      expect(find.text('Creative › Guitar'), findsOneWidget);
      expect(find.text('Walk · Archived'), findsOneWidget);
      expect(find.text('Gone'), findsNothing);
    });

    testWidgets("aren't anyone else's", (tester) async {
      await pump(
        tester,
        person: const Person(id: 'sam', name: 'Sam'),
        habits: InMemoryHabitsRepository([_mindfully]),
      );

      expect(find.text('Habits'), findsNothing);
    });

    testWidgets("aren't there if they can't be loaded", (tester) async {
      await pump(tester, habits: _Failing());

      expect(find.text('Habits'), findsNothing);
      expect(find.text('What matters to you'), findsOneWidget);
    });

    testWidgets('adds one, on a group, with its own parts', (tester) async {
      final repository = InMemoryHabitsRepository();
      await pump(tester, habits: repository);

      expect(find.textContaining('None yet.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Habit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Practice mindfully',
      );
      await tester.tap(find.text('Pick an action or group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog).last,
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
      expect(find.text('Present'), findsOneWidget);
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

  testWidgets('a habit is focused on by its star, two at most', (tester) async {
    final memory = PlanMemory(
      focus: FocusStore(persist: false, habits: ['h2']),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HabitScreen(habit: _mindfully, memory: memory),
      ),
    );

    await tester.tap(find.byTooltip('Focus on Practice mindfully'));
    await tester.pump();
    expect(memory.focus.habits, ['h2', 'h1']);
    expect(find.byTooltip("Don't focus on Practice mindfully"), findsOneWidget);

    memory.focus.setFocusHabit('h1', false);
    memory.focus.setFocusHabit('h3', true);
    await tester.pump();
    expect(
      find.byTooltip('Focus on Practice mindfully (2 already)'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Focus on Practice mindfully (2 already)'));
    expect(memory.focus.habits, ['h2', 'h3']);
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
          home: PersonScreen(
            person: defaultSelf,
            traits: InMemoryTraitsRepository(traits: _traits),
            memory: memory,
            habits: InMemoryHabitsRepository([_mindfully]),
            actions: _actions,
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
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}
