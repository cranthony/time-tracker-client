// A description links into the app: to a goal, a habit, a person, a
// circle, an action or a location, by id -- drawn with its icon and its
// current name, and opening it when tapped. The text editor puts one in.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/entity_link.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/screens/circle_screen.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/habit_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/habits_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/entity_links.dart';
import 'package:time_tracker_client/widgets/event_description.dart';
import 'package:time_tracker_client/widgets/goal_icon.dart';
import 'package:time_tracker_client/widgets/plow_icon.dart';
import 'package:time_tracker_client/widgets/text_editor.dart';

const _sam = Person(id: 'sam', name: 'Sam', circleIds: ['fam']);
const _family = Circle(id: 'fam', name: 'Family', memberIds: ['sam']);
const _home = Location(id: 'home', name: 'Home');
const _cook = PlanAction(id: 'cook', name: 'Cooking', path: 'Cooking');
const _calls = Habit(id: 'calls', name: 'Call Mom', actionId: 'cook');
final _move = Goal.fromJson({
  'id': 'move',
  'title': 'Help Sam move',
  'status': 'active',
});

void main() {
  test('a link into the app is its kind and id; anything else is not', () {
    expect(
      EntityLink.parse('goal:move'),
      const EntityLink(EntityKind.goal, 'move'),
    );
    expect(
      EntityLink.parse('Person://sam'),
      const EntityLink(EntityKind.person, 'sam'),
    );
    expect(EntityLink.parse('https://example.com'), isNull);
    expect(EntityLink.parse('mailto:sam@example.com'), isNull);
    expect(EntityLink.parse('goal:'), isNull);
    expect(const EntityLink(EntityKind.location, 'home').href, 'location:home');
  });

  group('in a description', () {
    final recognizers = <TapGestureRecognizer>[];
    tearDown(() {
      for (final r in recognizers) {
        r.dispose();
      }
      recognizers.clear();
    });
    final memory = PlanMemory()
      ..goals = [_move]
      ..people = const PeopleList(people: [_sam], circles: [_family])
      ..locations = const [_home]
      ..habits = const [_calls];
    final links = EntityLinks(memory: memory);
    List<DescriptionBlock> blocks(String text, {TextFormat? format}) =>
        descriptionBlocks(
          text,
          format: format,
          linkColor: Colors.blue,
          links: links,
          recognizer: (_) {
            final r = TapGestureRecognizer();
            recognizers.add(r);
            return r;
          },
        );
    // Each block's text, an icon as the object replacement character.
    List<String> texts(List<DescriptionBlock> blocks) => [
      for (final b in blocks) b.span.toPlainText(),
    ];

    test('a Markdown link keeps its text, its icon before it; one that is '
        'only the id, or an autolink, is named as the app has it', () {
      final result = blocks(
        'Ask [Sam](person:sam) about <goal:move>, at [](location:home).',
        format: TextFormat.markdown,
      );
      expect(texts(result), ['Ask ￼Sam about ￼Help Sam move, at ￼Home.']);
      expect(recognizers, hasLength(3));
      final spans = result.single.span.children!;
      expect(spans.whereType<WidgetSpan>(), hasLength(3));
      final named = spans.whereType<TextSpan>().where((s) => s.text == 'Sam');
      expect(named.single.recognizer, isNotNull);
      expect(named.single.style?.decoration, TextDecoration.underline);
    });

    test('an HTML link too, and a plain-text one, bare', () {
      // Its text only its id, it's named too.
      expect(texts(blocks('<p>See <a href="habit:calls">calls</a>.</p>')), [
        'See ￼Call Mom.',
      ]);
      expect(texts(blocks('<p>See <a href="habit:calls">the calls</a>.</p>')), [
        'See ￼the calls.',
      ]);
      expect(texts(blocks('See habit:calls and action:cook, or GOAL:move.')), [
        'See ￼Call Mom and ￼cook, or ￼Help Sam move.',
      ]);
      // One the app doesn't know is its id.
      expect(texts(blocks('goal:gone')), ['￼gone']);
      // An address with one in its path is the address.
      final [block] = blocks('https://example.com/goal:move x');
      expect(block.span.toPlainText(), 'https://example.com/goal:move x');
      expect(block.span.children!.whereType<WidgetSpan>(), isEmpty);
    });

    test('as plain text, for a calendar, a link is its text or its id', () {
      expect(
        descriptionText(
          'Ask [Sam](person:sam) about <goal:move> at [](location:home).',
          format: TextFormat.markdown,
        ),
        'Ask Sam about goal:move at location:home.',
      );
    });
  });

  group('tapped', () {
    late PlanMemory memory;
    late InMemoryActionsRepository actions;

    Future<void> pump(
      WidgetTester tester,
      String text, {
      TextFormat? format,
      bool scoped = true,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      memory = PlanMemory();
      actions = InMemoryActionsRepository(const [_cook]);
      final people = InMemoryPeopleRepository(
        people: const [_sam],
        circles: const [_family],
        locations: const [_home],
      );
      Widget scopes(Widget child) => PlanMemoryScope(
        memory: memory,
        child: GoalsScope(
          repository: InMemoryGoalsRepository([_move]),
          child: PeopleScope(
            repository: people,
            child: HabitsScope(
              repository: InMemoryHabitsRepository(const [_calls]),
              child: ActionsScope(
                repository: actions,
                outbox: ActionWrites.local(actions)..start(),
                child: child,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          // Above the navigator, as in the app, for the pages to find.
          builder: (context, child) => scoped ? scopes(child!) : child!,
          home: Scaffold(
            body: EventDescription(text, format: format, maxLines: null),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("a goal's icon or title opens its page, loading the goals "
        'if the app has not yet', (tester) async {
      await pump(tester, 'See [](goal:move).', format: TextFormat.markdown);
      // Not loaded yet: its id stands for it.
      expect(find.textContaining('move', findRichText: true), findsOneWidget);
      await tester.tap(find.byType(GoalIcon));
      await tester.pumpAndSettle();
      expect(find.byType(GoalScreen), findsOneWidget);
      // Loaded now, it's named.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Help Sam move', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets("a person's opens their page, a circle's its page", (
      tester,
    ) async {
      await pump(tester, 'With person:sam and circle:fam.');
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PersonScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(CircleScreen), findsOneWidget);
    });

    testWidgets("a habit's opens its page", (tester) async {
      await pump(tester, 'Keep habit:calls up.');
      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(HabitScreen), findsOneWidget);
    });

    testWidgets("an action's and a location's open their dialogs, as "
        'their panes do', (tester) async {
      await pump(tester, 'Under action:cook at location:home.');
      await tester.tap(find.byType(PlowIcon));
      await tester.pumpAndSettle();
      expect(find.text('Edit action'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.place_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Edit location'), findsOneWidget);
    });

    testWidgets('one the app has not got says so', (tester) async {
      await pump(tester, 'See goal:gone.');
      await tester.tap(find.byType(GoalIcon));
      await tester.pumpAndSettle();
      expect(find.byType(GoalScreen), findsNothing);
      expect(find.text('No goal “gone”'), findsOneWidget);
    });

    testWidgets('with nowhere to open it, it is only drawn', (tester) async {
      await pump(tester, 'See goal:move.', scoped: false);
      expect(find.byType(GoalIcon), findsOneWidget);
      await tester.tap(find.byType(GoalIcon));
      await tester.pumpAndSettle();
      expect(find.byType(GoalScreen), findsNothing);
    });
  });

  group('the text editor', () {
    Future<FormattedText?>? result;

    Future<void> open(
      WidgetTester tester, {
      String? text,
      TextFormat? format,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final memory = PlanMemory();
      final people = InMemoryPeopleRepository(
        people: const [_sam],
        circles: const [_family],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PlanMemoryScope(
            memory: memory,
            child: GoalsScope(
              repository: InMemoryGoalsRepository([_move]),
              child: PeopleScope(repository: people, child: child!),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => result = showTextEditor(
                  context,
                  title: 'Description',
                  text: text,
                  format: format,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> link(WidgetTester tester, String kind, String name) async {
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kind));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('Link puts a link to what is picked where the cursor is, '
        'as the format is written', (tester) async {
      await open(tester, text: 'Ask about it.', format: TextFormat.markdown);
      final field = find.byType(TextField);
      // After "Ask".
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .userUpdateTextEditingValue(
            const TextEditingValue(
              text: 'Ask about it.',
              selection: TextSelection.collapsed(offset: 3),
            ),
            SelectionChangedCause.keyboard,
          );
      await link(tester, 'Person or circle', 'Sam');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Ask [Sam](person:sam) about it.',
      );
      await link(tester, 'Goal', 'Help Sam move');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Ask [Sam](person:sam) [Help Sam move](goal:move) about it.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await result, (
        text: 'Ask [Sam](person:sam) [Help Sam move](goal:move) about it.',
        format: TextFormat.markdown,
      ));
    });

    testWidgets('in plain text, just its id; in HTML, an anchor', (
      tester,
    ) async {
      await open(tester, text: 'Ask', format: TextFormat.plain);
      await link(tester, 'Person or circle', 'Family');
      final field = find.byType(TextField);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Ask circle:fam',
      );

      await tester.tap(find.text('HTML'));
      await tester.pumpAndSettle();
      await link(tester, 'Goal', 'Help Sam move');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Ask circle:fam <a href="goal:move">Help Sam move</a>',
      );
    });
  });
}
