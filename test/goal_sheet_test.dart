import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/goal_drafts.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/goal_sheet.dart';

Goal _goal(String id, {String? parent, String status = 'active'}) =>
    Goal.fromJson({
      'id': id,
      'title': id,
      'parent_id': parent,
      'status': status,
      'deadline': '2026-12-01',
      'history': [
        {'status': status, 'at': '2026-10-01T09:00:00'},
      ],
    });

void main() {
  // A Sunday.
  final now = DateTime(2026, 10, 18, 9, 30);

  late List<Map<String, Object?>> kept;
  late GoalDrafts drafts;
  GoalSheetResult? result;

  /// Opens the sheet -- over a [PeopleScope] with [people], if given, as
  /// the app's has. With [addParents], its Under picker adds a goal to go
  /// under in a sheet of its own, as the app's does, kept with the rest,
  /// its title as its id.
  Future<void> open(
    WidgetTester tester, {
    GoalDrafts? withDrafts,
    List<Goal> goals = const [],
    List<Person>? people,
    bool addParents = false,
  }) async {
    kept = [];
    drafts = withDrafts ?? GoalDrafts.inMemory();
    result = null;
    final all = [...goals];
    Future<AddedParent?> addParent(
      BuildContext context,
      String title,
      DateTime day,
    ) async {
      Goal? added;
      await showAddGoalSheet(
        context,
        keep: (fields) async {
          kept.add(fields);
          added = Goal.fromJson({...fields, 'id': fields['title']});
          all.add(added!);
        },
        goals: [...all],
        title: title,
        day: day,
        addParent: (title, day) => addParent(context, title, day),
        now: () => now,
      );
      return switch (added) {
        final added? => (added: added, goals: [...all]),
        null => null,
      };
    }

    final app = MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showAddGoalSheet(
              context,
              keep: (fields) async => kept.add(fields),
              goals: goals,
              drafts: drafts,
              addParent: addParents
                  ? (title, day) => addParent(context, title, day)
                  : null,
              now: () => now,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      people == null
          ? app
          : PeopleScope(
              repository: InMemoryPeopleRepository(people: people),
              child: app,
            ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  final people = [
    const Person(id: 'ana', name: 'Ana'),
    const Person(id: 'sam', name: 'Sam', context: 'from salsa'),
    const Person(id: 'bo', name: 'Bo', status: 'archived'),
  ];

  /// The search field of the picker sheet open over the goal sheet.
  Finder search() => find.byType(TextField).last;

  FilledButton add(WidgetTester tester) =>
      tester.widget(find.widgetWithText(FilledButton, 'Add'));

  testWidgets('starts due today, shown with its day of the week', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Sun, Oct 18'), findsOneWidget);
    // Nothing to add yet.
    expect(add(tester).onPressed, isNull);
  });

  testWidgets('+ and - move it a day, not before today; Today goes back', (
    tester,
  ) async {
    await open(tester);
    final earlier = find.widgetWithIcon(IconButton, Icons.remove);
    expect(tester.widget<IconButton>(earlier).onPressed, isNull);

    await tester.tap(find.byTooltip('A day later'));
    await tester.tap(find.byTooltip('A day later'));
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    expect(find.text('Wed, Oct 21'), findsOneWidget);
    await tester.tap(earlier);
    await tester.pump();
    expect(find.text('Tue, Oct 20'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text('Sun, Oct 18'), findsOneWidget);
  });

  testWidgets('Add keeps an active goal due by the end of the day', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '  Ship it ');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(kept.single, {
      'title': 'Ship it',
      'deadline': '2026-10-19',
      'status': 'active',
    });
    expect(result, isA<AddedGoal>());
    expect(find.text('New goal'), findsNothing);
    expect(drafts.draft, isNull);
  });

  testWidgets("More closes it, giving what's typed", (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    final more = result as MoreGoal;
    expect(more.title, 'Ship it');
    expect(more.deadline, '2026-10-19');
    expect(kept, isEmpty);
    expect(drafts.draft?.title, 'Ship it');
  });

  testWidgets('its parent is picked searching for its title, by any word, '
      'selected to type over', (tester) async {
    final goals = [
      _goal('Health'),
      _goal('Run a marathon', parent: 'Health'),
      _goal('Someday', status: 'inactive'),
    ];
    await open(tester, goals: goals);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.pump();
    expect(find.text('Top level'), findsOneWidget);
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Run 10k').last,
    );
    expect(search.controller!.selection.start, 0);
    expect(search.controller!.selection.end, 'Run 10k'.length);
    expect(search.focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Any'))
          .selected,
      isTrue,
    );
    // Only active goals: the new one is active.
    expect(find.text('Someday'), findsNothing);
    await tester.tap(find.text('Run a marathon'));
    await tester.pumpAndSettle();
    expect(find.text('Under Health › Run a marathon'), findsOneWidget);
    expect(drafts.draft?.parentId, 'Run a marathon');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single['parent_id'], 'Run a marathon');
  });

  testWidgets('without a way to add one, its parent is only picked', (
    tester,
  ) async {
    await open(tester, goals: [_goal('Health')]);
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add goal'), findsNothing);
  });

  testWidgets('a parent is added, named as typed, in a New goal sheet over '
      'it, due when it is -- and that one can add its own', (tester) async {
    await open(tester, goals: [_goal('Health')], addParents: true);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    await tester.enterText(search(), 'Fitness');
    await tester.pump();
    await tester.tap(find.text('Add goal “Fitness”…'));
    await tester.pumpAndSettle();

    // The sheet it goes under, over it, named and due as typed there.
    expect(find.text('New goal'), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Fitness',
    );
    expect(find.text('Mon, Oct 19'), findsNWidgets(2));

    // One under that, in turn.
    await tester.tap(find.text('Top level').last);
    await tester.pumpAndSettle();
    await tester.enterText(search(), 'Wellbeing');
    await tester.pump();
    await tester.tap(find.text('Add goal “Wellbeing”…'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsNWidgets(3));
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsNWidgets(2));
    expect(find.text('Under Wellbeing'), findsOneWidget);
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Under Wellbeing › Fitness'), findsOneWidget);
    // Only the first sheet's is kept as a draft.
    expect(drafts.draft?.title, 'Run 10k');
    expect(drafts.draft?.parentId, 'Fitness');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect([for (final k in kept) (k['title'], k['parent_id'])], [
      ('Wellbeing', null),
      ('Fitness', 'Wellbeing'),
      ('Run 10k', 'Fitness'),
    ]);
    expect(kept.first['deadline'], '2026-10-19');
  });

  testWidgets('a parent called off leaves it as it was', (tester) async {
    await open(tester, goals: [_goal('Health')], addParents: true);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add goal “Run 10k”…'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsNWidgets(2));
    // Dismissed: back to the picker, to pick another.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Add goal “Run 10k”…'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Add goal “Run 10k”…'), findsNothing);
    expect(find.text('Top level'), findsOneWidget);
    expect(kept, isEmpty);
  });

  testWidgets('More gives its parent, priority and description', (
    tester,
  ) async {
    await open(tester, goals: [_goal('Running')]);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add description'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Around the lake');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Around the lake'), findsOneWidget);
    expect(drafts.draft?.description, 'Around the lake');

    await tester.tap(find.text('Inherit (P3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();
    expect(drafts.draft?.priority, 1);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final more = result as MoreGoal;
    expect(more.parentId, 'Running');
    expect(more.description, 'Around the lake');
    expect(more.priority, 1);
  });

  testWidgets('Add keeps its description and priority', (tester) async {
    final withDraft = GoalDrafts.inMemory();
    await withDraft.put(
      GoalDraft(
        title: 'Run 10k',
        day: now,
        description: 'Around the lake',
        priority: 0,
        parentId: 'Gone',
      ),
    );
    await open(tester, withDrafts: withDraft);
    // Its parent's gone: it's at the top level.
    expect(find.text('Top level'), findsOneWidget);
    expect(find.text('P0'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single, {
      'title': 'Run 10k',
      'deadline': '2026-10-18',
      'status': 'active',
      'description': 'Around the lake',
      'priority': 0,
    });
  });

  testWidgets("its priority starts as its parent's, beside the goal it goes "
      'under, and has no definition of done', (tester) async {
    final goals = [
      Goal.fromJson({..._goal('Health').toJson(), 'priority': 1}),
    ];
    await open(tester, goals: goals);
    await tester.enterText(find.byType(TextField), 'Health check');
    await tester.pump();
    expect(find.text('(P3)'), findsOneWidget);
    expect(find.text('Add definition of done'), findsNothing);
    final under = tester.getRect(find.text('Top level'));
    final priority = tester.getRect(find.text('(P3)'));
    expect(priority.center.dy, closeTo(under.center.dy, 4));
    expect(priority.left, greaterThan(under.right));
    expect(priority.left - under.right, lessThan(80));

    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    expect(find.text('Inherit (P1)'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single.containsKey('priority'), isFalse);
  });

  testWidgets('without people to pick from, there are no With or For rows', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('With'), findsNothing);
    expect(find.text('For'), findsNothing);
  });

  testWidgets('With and For sit on the line of the goal it goes under, at '
      'the right: With last, For just before it', (tester) async {
    await open(tester, people: people);
    final under = tester.getRect(find.text('Top level'));
    final with_ = tester.getRect(find.text('With'));
    final for_ = tester.getRect(find.text('For'));
    expect(with_.center.dy, closeTo(under.center.dy, 4));
    expect(for_.center.dy, closeTo(under.center.dy, 4));
    expect(for_.right, lessThan(with_.left));
    expect(under.right, lessThan(for_.left));
    // At the right, as the Add button is.
    final add = tester.getRect(find.widgetWithText(FilledButton, 'Add'));
    expect(with_.right, closeTo(add.right, 24));
  });

  testWidgets('With and For each add a person with a tap, searching for '
      "the title's words; no one is in both; a chip tapped takes them off", (
    tester,
  ) async {
    await open(tester, people: people);
    await tester.enterText(find.byType(TextField), 'Help Sam move');
    await tester.pump();
    expect(find.byType(InputChip), findsNothing);

    // Sam matches the title; a tap picks them.
    await tester.tap(find.text('With'));
    await tester.pumpAndSettle();
    expect(find.text('Sam (from salsa)'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
    await tester.tap(find.text('Sam (from salsa)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Sam'), findsOneWidget);
    expect(drafts.draft?.withIds, ['sam']);
    expect(drafts.draft?.forIds, isEmpty);

    // Picked as who it's for, they're no longer who it's with.
    await tester.tap(find.text('For'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam (from salsa)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Sam'), findsOneWidget);
    expect(drafts.draft?.withIds, isEmpty);
    expect(drafts.draft?.forIds, ['sam']);

    // Everyone active but Self and those picked already for this row,
    // searching over.
    await tester.tap(find.text('With'));
    await tester.pumpAndSettle();
    await tester.enterText(search(), '');
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Sam (from salsa)'), findsOneWidget);
    expect(find.text('Bo'), findsNothing);
    expect(find.text('Self'), findsNothing);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Ana'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Sam'), findsOneWidget);
    await tester.tap(find.text('For'));
    await tester.pumpAndSettle();
    await tester.enterText(search(), '');
    await tester.pumpAndSettle();
    expect(find.text('Sam (from salsa)'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single['with_ids'], ['ana']);
    expect(kept.single['for_ids'], ['sam']);
  });

  testWidgets('someone new is added in the quick New person sheet, named as '
      "it's typed, and picked", (tester) async {
    await open(tester, people: people);
    await tester.enterText(find.byType(TextField), 'Call Jo');
    await tester.pump();
    await tester.tap(find.text('For'));
    await tester.pumpAndSettle();
    await tester.enterText(search(), 'Jo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add person “Jo”…'));
    await tester.pumpAndSettle();

    expect(find.text('New person'), findsOneWidget);
    // Over the picker, whose search has it too.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Name'))
          .controller!
          .text,
      'Jo',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pumpAndSettle();

    // Back on the goal sheet, the picker closed, with them for it.
    expect(find.text('New person'), findsNothing);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Jo'), findsOneWidget);
    expect(drafts.draft?.forIds, hasLength(1));
    expect(drafts.draft?.withIds, isEmpty);
  });

  testWidgets('a chip tapped takes its person off, and Add sends no one '
      'once there is no one', (tester) async {
    await open(tester, people: people);
    await tester.enterText(find.byType(TextField), 'Help Sam move');
    await tester.pump();
    await tester.tap(find.text('For'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam (from salsa)'));
    await tester.pumpAndSettle();
    expect(drafts.draft?.forIds, ['sam']);

    await tester.tap(find.widgetWithText(InputChip, 'Sam'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
    expect(drafts.draft?.forIds, isEmpty);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single.containsKey('with_ids'), isFalse);
    expect(kept.single.containsKey('for_ids'), isFalse);
  });

  testWidgets("a draft's people come back, named, and More carries them "
      'over', (tester) async {
    final withDraft = GoalDrafts.inMemory();
    await withDraft.put(
      GoalDraft(
        title: 'Help Sam move',
        day: now,
        withIds: const ['ana'],
        forIds: const ['sam'],
      ),
    );
    await open(tester, withDrafts: withDraft, people: people);
    expect(find.widgetWithText(InputChip, 'Ana'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Sam'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final more = result as MoreGoal;
    expect(more.withIds, ['ana']);
    expect(more.forIds, ['sam']);
  });

  testWidgets('the full New goal page starts with the people given it', (
    tester,
  ) async {
    // Tall enough for the whole page, its People field at the foot.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalEditorPage(
          goals: const [],
          title: 'Help Sam move',
          withIds: const ['ana'],
          forIds: const ['sam'],
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Named by id, with no people loaded to name them.
    expect(find.text('With ana · For sam'), findsOneWidget);
  });

  test('a draft keeps its people, sent only when there are some', () {
    final draft = GoalDraft(
      title: 'Help Sam move',
      day: now,
      withIds: const ['ana'],
      forIds: const ['sam'],
    );
    final json = draft.toJson();
    expect(json['with_ids'], ['ana']);
    expect(json['for_ids'], ['sam']);
    final read = GoalDraft.fromJson(json);
    expect(read.withIds, ['ana']);
    expect(read.forIds, ['sam']);
    final alone = GoalDraft(title: 'Read more', day: now).toJson();
    expect(alone.containsKey('with_ids'), isFalse);
    expect(alone.containsKey('for_ids'), isFalse);
    expect(GoalDraft.fromJson(alone).withIds, isEmpty);
  });

  testWidgets("what's typed is kept as a draft, which the next sheet "
      'carries on with, or its trash can throws away', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    expect(drafts.draft?.title, 'Ship it');
    expect(drafts.draft?.day, DateTime(2026, 10, 19));

    // Dismissed, then opened again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Ship it'), findsOneWidget);
    expect(find.text('Mon, Oct 19'), findsOneWidget);

    await tester.tap(find.byTooltip('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsNothing);
    expect(drafts.draft, isNull);
  });

  testWidgets('a draft from days ago is due today at the earliest', (
    tester,
  ) async {
    final old = GoalDrafts.inMemory();
    await old.put(GoalDraft(title: 'Old', day: DateTime(2026, 10, 1)));
    await open(tester, withDrafts: old);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Sun, Oct 18'), findsOneWidget);
  });

  testWidgets('a failed keep stays open, saying so, to try again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddGoalSheet(
                context,
                keep: (_) async => throw Exception('disk full'),
                now: () => now,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't add the goal"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says when its field has focus, for the keyboard', (
    tester,
  ) async {
    var focused = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddGoalSheet(
                context,
                keep: (_) async {},
                now: () => now,
                onFieldFocused: () => focused++,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(focused, 1);
  });

  testWidgets('on a phone, the buttons go under the date, at the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();

    // The test font is wider than any real one, so the date's controls
    // themselves wrap here; on a phone they keep to one line.
    final later = find.byTooltip('A day later');
    // The buttons under the date, at the right.
    final add = find.widgetWithText(FilledButton, 'Add');
    expect(
      tester.getTopLeft(add).dy,
      greaterThan(tester.getBottomLeft(later).dy),
    );
    expect(tester.getTopRight(add).dx, closeTo(320 - 16, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen, it is all one line', (tester) async {
    await open(tester);
    final add = tester.getCenter(find.text('Add')).dy;
    expect(tester.getCenter(find.text('Today')).dy, closeTo(add, 4));
    expect(tester.takeException(), isNull);
  });
}
