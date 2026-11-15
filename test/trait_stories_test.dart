import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_example.dart';
import 'package:time_tracker_client/screens/trait_screen.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/people_picker.dart';
import 'package:time_tracker_client/widgets/trait_icon.dart';
import 'package:time_tracker_client/widgets/trait_stories.dart';

const _icon =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor">'
    '<circle cx="12" cy="12" r="9"/></svg>';

const _kind = Trait(
  id: 'kind',
  name: 'Kind',
  icon: _icon,
  parts: [
    {
      'kind': 'judgment',
      'rubric': 'Was it kind?',
      'ratings': {'0': 'No', '1': 'Yes'},
      'facts': ['general_notes'],
    },
  ],
);

const _people = PeopleList(
  people: [
    Person(id: selfPersonId, name: 'Me'),
    Person(id: 'alex', name: 'Alex'),
  ],
);

const _older = TraitExample(
  id: 'x1',
  traitId: 'kind',
  when: '2026-03-01',
  who: 'A stranger on the bus',
  what: 'Gave up their seat',
  why: 'Saw someone tired before they asked',
  version: 1,
);
const _newer = TraitExample(
  id: 'x2',
  traitId: 'kind',
  when: '2026-09-10',
  personId: 'alex',
  what: 'Carried the shopping up four floors',
  why: 'Did it without being asked',
  eventId: 'e1',
  version: 3,
);

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

void main() {
  group('TraitExample', () {
    test('is read and written as the server keeps it', () {
      final json = {
        'id': 'x2',
        'trait_id': 'kind',
        'when': '2026-09-10',
        'person_id': 'alex',
        'who': null,
        'what': 'Carried the shopping up four floors',
        'why': 'Did it without being asked',
        'event_id': 'e1',
        'version': 3,
      };
      final example = TraitExample.fromJson(json);
      expect(example.who, isNull);
      expect(example.version, 3);
      expect(example.toJson(), {
        'id': 'x2',
        'trait_id': 'kind',
        'when': '2026-09-10',
        'person_id': 'alex',
        'what': 'Carried the shopping up four floors',
        'why': 'Did it without being asked',
        'event_id': 'e1',
      });
    });

    test("an edit sends what changed, a cleared field as null", () {
      final edited = TraitExample(
        id: _newer.id,
        traitId: 'kind',
        when: _newer.when,
        who: 'Alex, my neighbour',
        what: _newer.what,
        why: 'Did it unasked',
        version: _newer.version,
      );
      expect(edited.changesFrom(_newer), {
        'person_id': null,
        'who': 'Alex, my neighbour',
        'why': 'Did it unasked',
        'event_id': null,
      });
    });

    test('says what a story is missing', () {
      expect(traitExampleProblem(_older), isNull);
      expect(
        traitExampleProblem(
          const TraitExample(traitId: 'kind', when: '', what: 'a', why: 'b'),
        ),
        'Say when it happened.',
      );
      expect(
        traitExampleProblem(
          const TraitExample(
            traitId: 'kind',
            when: '2026-01-01',
            what: 'a',
            why: 'b',
          ),
        ),
        'Say who did it.',
      );
    });

    test('newest first', () {
      expect(newestFirst([_older, _newer]), [_newer, _older]);
    });
  });

  group('McpTraitsRepository', () {
    test('lists, creates, updates and deletes stories with their tools, '
        'version-checked', () async {
      final client = _Client(
        (name, arguments) => switch (name) {
          'get_trait_examples' => [_older.toJson(), _newer.toJson()],
          'delete_trait_example' => _newer.toJson(),
          _ => {
            ...(arguments['trait_example'] as Map).cast<String, Object?>(),
            'id': 'x9',
            'trait_id': 'kind',
            'when': '2026-01-01',
            'what': 'a',
            'why': 'b',
            'version': 1,
          },
        },
      );
      final repository = McpTraitsRepository(client);
      expect(
        [for (final e in await repository.examples(traitId: 'kind')) e.id],
        ['x2', 'x1'],
      );
      expect(client.calls.last.$2, {'trait_id': 'kind'});
      await repository.createExample(_older);
      expect(client.calls.last.$1, 'create_trait_example');
      expect(
        (client.calls.last.$2['trait_example'] as Map).containsKey('id'),
        isFalse,
      );
      await repository.updateExample(_newer, {'who': 'Alex', 'event_id': null});
      expect(client.calls.last.$2, {
        'trait_example': {'id': 'x2', 'who': 'Alex', 'version': 3},
        'clear_fields': ['event_id'],
      });
      await repository.deleteExample(_newer);
      expect(client.calls.last.$2, {'trait_example_id': 'x2', 'if_version': 3});
    });

    test("a server without them has none; other failures aren't hidden", () {
      expect(
        McpTraitsRepository(
          _Client((name, _) => throw McpException('Unknown tool: $name')),
        ).examples(),
        completion(isEmpty),
      );
      expect(
        McpTraitsRepository(_Client((_, _) => throw McpException('Offline')))
            .examples(),
        throwsA(isA<McpException>()),
      );
    });
  });

  test('the in-memory repository refuses a stale edit', () async {
    final repository = InMemoryTraitsRepository(
      traits: const [_kind],
      examples: const [_newer],
    );
    final saved = await repository.updateExample(_newer, {'what': 'Again'});
    expect(saved.version, 4);
    expect(
      repository.updateExample(_newer, {'what': 'Stale'}),
      throwsA(isA<McpException>()),
    );
  });

  test("memory names the traits an event's stories are of", () async {
    final memory = PlanMemory();
    await memory.loadTraits(
      InMemoryTraitsRepository(
        traits: const [_kind],
        examples: const [_older, _newer],
      ),
    );
    expect(memory.traitExamples, hasLength(2));
    expect(memory.storyTraitIds('e1'), ['kind']);
    expect(memory.storyTraitIds('e2'), isEmpty);
  });

  group("a trait's page", () {
    Future<InMemoryTraitsRepository> open(
      WidgetTester tester, {
      List<TraitExample> examples = const [_older, _newer],
      List<String>? opened,
    }) async {
      final repository = InMemoryTraitsRepository(
        traits: const [_kind],
        examples: examples,
      );
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PlanMemoryScope(
          // The people picker's people.
          memory: PlanMemory()..people = _people,
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: TraitScreen(
              trait: _kind,
              stories: TraitStories(
                load: (id) => repository.examples(traitId: id),
                save: (example, before) => before == null
                    ? repository.createExample(example)
                    : repository.updateExample(
                        before,
                        example.changesFrom(before),
                      ),
                delete: repository.deleteExample,
                people: _people,
                eventsOn: (day) async => [
                  (id: 'e7', label: '9:00 AM Walk to the park'),
                ],
                openEvent: (example) async => opened?.add(example.eventId!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists its stories, newest first: when, who, what, why, '
        'and the event', (tester) async {
      final opened = <String>[];
      await open(tester, opened: opened);
      expect(find.text('Stories'), findsOneWidget);
      final newer = find.text('Carried the shopping up four floors');
      final older = find.text('Gave up their seat');
      expect(
        tester.getTopLeft(newer).dy,
        lessThan(tester.getTopLeft(older).dy),
      );
      expect(find.textContaining('Alex'), findsOneWidget);
      expect(find.textContaining('A stranger on the bus'), findsOneWidget);
      expect(
        find.text('Why: Did it without being asked', findRichText: true),
        findsOneWidget,
      );
      // Only the one at an event links to it.
      expect(find.text('The event'), findsOneWidget);
      await tester.tap(find.text('The event'));
      expect(opened, ['e1']);
    });

    testWidgets('draws what and why in Markdown', (tester) async {
      await open(
        tester,
        examples: const [
          TraitExample(
            id: 'x3',
            traitId: 'kind',
            when: '2026-09-10',
            personId: 'alex',
            what: 'Carried **all** the shopping\n\n- up four floors',
            why: 'Did it *unasked*',
            version: 1,
          ),
        ],
      );
      final what = find.text('Carried all the shopping', findRichText: true);
      expect(what, findsOneWidget);
      var bold = false;
      tester.widget<RichText>(what).text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'all' &&
            span.style?.fontWeight == FontWeight.w700) {
          bold = true;
        }
        return true;
      });
      expect(bold, isTrue);
      expect(find.text('up four floors', findRichText: true), findsOneWidget);
      expect(find.text('•', findRichText: true), findsOneWidget);
      expect(
        find.text('Why: Did it unasked', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('says when it has none', (tester) async {
      await open(tester, examples: const []);
      expect(find.textContaining('None yet'), findsOneWidget);
    });

    testWidgets('adds a story: when, who, what, why and the event', (
      tester,
    ) async {
      final repository = await open(tester, examples: const []);
      await tester.tap(find.widgetWithText(TextButton, 'Story'));
      await tester.pumpAndSettle();
      expect(find.text('New story of Kind'), findsOneWidget);
      // Saying nothing says what's missing.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Say what they did.'), findsOneWidget);

      // Who: Me, to start with; picked from People, one person.
      expect(find.text('Me'), findsOneWidget);
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      expect(find.text('Who did it'), findsOneWidget);
      await tester.tap(find.text('Alex').last);
      await tester.pumpAndSettle();
      expect(find.text('Who did it'), findsNothing);
      expect(find.text('Alex'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'What they did'),
        'Fixed my bike',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Why it is kind'),
        'Saw it was broken',
      );
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9:00 AM Walk to the park').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = (await repository.examples()).single;
      expect(saved.personId, 'alex');
      expect(saved.what, 'Fixed my bike');
      expect(saved.why, 'Saw it was broken');
      expect(saved.eventId, 'e7');
      expect(find.text('Fixed my bike'), findsOneWidget);
    });

    testWidgets('edits a story, someone else in words', (tester) async {
      final repository = await open(tester, examples: const [_newer]);
      await tester.tap(find.byTooltip('More for this story'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit story of Kind'), findsOneWidget);
      // No one from People: only who, in words.
      await tester.tap(find.byTooltip('No one: say who in words'));
      await tester.pumpAndSettle();
      expect(find.text('No one picked'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Who, in words'),
        'The neighbour downstairs',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await repository.examples()).single;
      expect(saved.personId, isNull);
      expect(saved.who, 'The neighbour downstairs');
      expect(saved.version, 4);
    });

    testWidgets('deletes a story, once asked', (tester) async {
      final repository = await open(tester, examples: const [_newer]);
      await tester.tap(find.byTooltip('More for this story'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this story?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await repository.examples(), isEmpty);
      expect(find.textContaining('None yet'), findsOneWidget);
    });
  });

  testWidgets("a story's who is picked from People: a person, Self or a "
      'community, not a plain circle', (tester) async {
    Object? picked;
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: PlanMemory()
          ..people = const PeopleList(
            people: [
              Person(id: selfPersonId, name: 'Me'),
              Person(id: 'alex', name: 'Alex'),
            ],
            circles: [
              Circle(id: 'c1', name: 'Book club'),
              Circle(
                id: 'c2',
                name: 'The neighbourhood',
                kind: CircleKind.community,
              ),
            ],
          ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await pickPersonOrCircle(
                context,
                title: 'Who did it',
                communitiesOnly: true,
              ),
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('Communities'), findsOneWidget);
    expect(find.text('Book club'), findsNothing);
    await tester.tap(find.text('The neighbourhood'));
    await tester.pumpAndSettle();
    expect((picked as Circle).id, 'c2');
  });

  testWidgets("an event's dialog shows the stories at it, each by its "
      "trait's icon, and marks its trait", (tester) async {
    final event = Event(
      id: 'e1',
      summary: 'Moving day',
      start: DateTime(2026, 9, 10, 9),
      end: DateTime(2026, 9, 10, 12),
    );
    await tester.pumpWidget(
      TraitsScope(
        repository: InMemoryTraitsRepository(
          traits: const [_kind],
          examples: const [_older, _newer],
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(context, event),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Kind · alex: Carried the shopping up four floors'),
      findsOneWidget,
    );
    expect(find.textContaining('Gave up their seat'), findsNothing);
    // Marked by it, and the story beside its icon.
    expect(find.byType(TraitIcon), findsNWidgets(2));
  });

  test('storyWho names the person, and the words given', () {
    expect(storyWho(_newer, _people), 'Alex');
    expect(storyWho(_older, _people), 'A stranger on the bus');
    expect(
      storyWho(
        const TraitExample(
          traitId: 'kind',
          when: '2026-01-01',
          personId: selfPersonId,
          who: 'at work',
          what: 'a',
          why: 'b',
        ),
        _people,
      ),
      'Me (at work)',
    );
  });
}
