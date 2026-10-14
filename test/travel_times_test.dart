import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/travel_time.dart';
import 'package:time_tracker_client/screens/travel_times_screen.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

void main() {
  /// Home, in Park Slope; and the ways of getting about: walking, and
  /// transit, a group with the subway in it.
  Future<InMemoryPeopleRepository> pump(
    WidgetTester tester, {
    List<TravelTime> travelTimes = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryPeopleRepository(
      locationGroups: const [LocationGroup(id: 'slope', name: 'Park Slope')],
      locations: const [
        Location(id: 'home', name: 'Home', groupId: 'slope'),
        Location(id: 'work', name: 'Work'),
      ],
      travelTimes: travelTimes,
    );
    final memory = PlanMemory()
      ..actions = const ActionList(
        actions: [
          PlanAction(id: 'walk', name: 'Walk', path: 'Walk'),
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
          ),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: TravelTimesScreen(repository: repository, memory: memory),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  /// The travel time from [from] to [to], one way or both as [arrow] says.
  Finder route(String from, IconData arrow, String to) =>
      find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText(includeSemanticsLabels: false) ==
                '$from ￼ $to' &&
            find
                .descendant(of: find.byWidget(w), matching: find.byIcon(arrow))
                .evaluate()
                .isNotEmpty,
      );

  /// Picks [choice], a path ("Park Slope › Home"), for [field]: searched
  /// for in its sheet, and tapped by its name.
  Future<void> pick(WidgetTester tester, String field, String choice) async {
    await tester.tap(find.widgetWithText(InputDecorator, field).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      choice.replaceAll(' › ', ' '),
    );
    await tester.pumpAndSettle();
    // Its own row in the sheet, before any it's the group of.
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.widgetWithText(ListTile, choice.split(' › ').last),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('adds a travel time, its hours and minutes set as a duration '
      'is', (tester) async {
    final repository = await pump(tester);
    expect(find.textContaining('No travel times yet'), findsOneWidget);

    await tester.tap(find.byTooltip('New travel time'));
    await tester.pumpAndSettle();
    expect(find.text("Pick where it's from and to."), findsOneWidget);
    await pick(tester, 'From', 'Park Slope › Home');
    await pick(tester, 'To', 'Work');
    await pick(tester, 'By', 'Transit');
    // An hour less five minutes, by the steppers.
    await tester.tap(find.byTooltip('An hour more').first);
    await tester.pump();
    await tester.tap(find.byTooltip('5 minutes less').first);
    await tester.pump();
    // Up to an hour and a quarter, typed.
    await tester.enterText(
      find.widgetWithText(TextField, 'Up to (optional)'),
      '1h 15m',
    );
    await tester.pump();
    // And on foot, which takes longer.
    await tester.tap(find.text('Add a way'));
    await tester.pumpAndSettle();
    await pick(tester, 'By', 'Walk');
    await tester.enterText(find.widgetWithText(TextField, 'Takes').last, '2h');
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Note (optional)'),
      'the F',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repository.travelTimes()).single;
    expect((saved.fromId, saved.toId, saved.oneWay), ('home', 'work', false));
    expect(saved.times.map((t) => (t.modeId, t.minutes, t.maxMinutes)), [
      ('transit', 55, 75),
      ('walk', 120, null),
    ]);
    expect(saved.note, 'the F');
    expect(route('Park Slope › Home', Icons.sync_alt, 'Work'), findsOneWidget);
    expect(find.text('Transit 55m–1h 15m · Walk 2h\nthe F'), findsOneWidget);
  });

  testWidgets('says what keeps one from being saved', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('New travel time'));
    await tester.pumpAndSettle();

    await pick(tester, 'From', 'Work');
    await pick(tester, 'To', 'Work');
    expect(find.text('Pick two different places.'), findsOneWidget);
    await pick(tester, 'To', 'Park Slope');
    expect(find.text('Pick how each way gets there.'), findsOneWidget);
    await pick(tester, 'By', 'Walk');
    expect(find.text('Say how long each way takes.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Takes'), '30');
    await tester.enterText(
      find.widgetWithText(TextField, 'Up to (optional)'),
      '20',
    );
    await tester.pump();
    expect(find.text('"Up to" is at least what it takes.'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('makes one one way, and deletes it', (tester) async {
    final repository = await pump(
      tester,
      travelTimes: const [
        TravelTime(
          id: 't1',
          fromId: 'work',
          toId: 'slope',
          times: [TravelMode(modeId: 'subway', minutes: 30)],
        ),
      ],
    );
    expect(route('Work', Icons.sync_alt, 'Park Slope'), findsOneWidget);
    expect(find.text('Transit › Subway 30m'), findsOneWidget);

    await tester.tap(route('Work', Icons.sync_alt, 'Park Slope'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One way only'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only from Work to Park Slope'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.travelTimes()).single.oneWay, isTrue);
    expect(route('Work', Icons.arrow_forward, 'Park Slope'), findsOneWidget);

    await tester.tap(route('Work', Icons.arrow_forward, 'Park Slope'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(await repository.travelTimes(), isEmpty);
    expect(find.textContaining('No travel times yet'), findsOneWidget);
  });
}
