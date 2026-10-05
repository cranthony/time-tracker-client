import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/goal_traits_screen.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/measure_editor.dart';
import 'package:time_tracker_client/widgets/parts_editor.dart';

const _reliable = Trait(
  id: 'reliable',
  name: 'Reliable',
  parts: [
    {'kind': 'continuity'},
  ],
);

const _cadences = {
  'kind': 'traits',
  'traits': 'all',
  'parts': {
    'reliable': [
      {'kind': 'continuity', 'last_within_days': 1, 'next_within_days': 1},
      {'kind': 'follow_through'},
      {'kind': 'count', 'target': 1, 'interval_days': 7, 'activity': 'church'},
    ],
  },
};

void main() {
  group('parts', () {
    test('are described in a line', () {
      expect(
        describePart(const {
          'kind': 'count',
          'target': 1,
          'interval_days': 21,
          'activity': 'visit',
        }),
        'visit every 21 days',
      );
      expect(
        describePart(const {'kind': 'count', 'target': 2, 'interval_days': 7}),
        '2 × any event with them every 7 days',
      );
      expect(
        describePart(const {
          'kind': 'continuity',
          'last_within_days': 1,
          'next_within_days': 1,
        }),
        'Continuity: last within day, next within day',
      );
      expect(describePart(const {'kind': 'follow_through'}), 'Follow-through');
    });

    test('check an activity is text', () {
      expect(
        partProblem(const {'kind': 'count', 'target': 1, 'activity': ' '}),
        'activity must be some text.',
      );
      expect(activityLabel('  Dance   Class '), 'dance class');
    });
  });

  group("a goal's own parts", () {
    test('are described and checked', () {
      expect(measureProblem(_cadences), isNull);
      expect(
        measureProblem(const {
          'kind': 'traits',
          'traits': 'all',
          'parts': {'reliable': <Object>[]},
        }),
        'Give Reliable at least one part for this goal.',
      );
      expect(
        describeMeasureSettings(_cadences),
        contains((
          'Reliable, for this goal',
          'Continuity: last within day, next within day\n'
              'Follow-through\n'
              'church every 7 days',
        )),
      );
    });

    testWidgets('are customized in the measure editor, and dropped again', (
      tester,
    ) async {
      final changes = <Measure?>[];
      await tester.pumpWidget(
        TraitsScope(
          repository: InMemoryTraitsRepository(traits: [_reliable]),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MeasureEditor(
                  measure: const {'kind': 'traits', 'traits': 'all'},
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Customize for this goal'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add part'));
      await tester.tap(find.text('Add part'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preparation').last);
      await tester.tap(find.text('Preparation').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number of events').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Activity (optional)'),
        'Visit',
      );
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(changes.last?['parts'], {
        'reliable': [
          {'kind': 'continuity'},
          {'kind': 'count', 'target': 1, 'activity': 'visit'},
        ],
      });
      expect(find.textContaining('Parts for this goal:'), findsOneWidget);

      await tester.tap(find.text("Use Reliable's"));
      await tester.pumpAndSettle();
      expect(changes.last?.containsKey('parts'), isFalse);
    });
  });

  testWidgets('a parts dialog refuses parts that are wrong', (tester) async {
    List<Part>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showPartsDialog(
              context,
              title: 'Parts',
              parts: const [
                {'kind': 'effort_paid'},
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Part 1: target, effort-minutes is needed.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
  });

  testWidgets("a goal's traits page shows how it's rated, and edits it", (
    tester,
  ) async {
    var edited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GoalTraitsScreen(
          goal: const Goal(id: 'p1', name: 'Person', measure: _cadences),
          repository: InMemoryTraitsRepository(
            ratings: {'p1': const TraitsRating(rating: 50)},
          ),
          onEditMeasure: (goal) async {
            edited++;
            return Goal(
              id: 'p1',
              name: 'Person',
              measure: {...goal.measure!, 'window_days': 14},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reliable, for this goal'), findsOneWidget);
    expect(find.textContaining('church every 7 days'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit how it is rated'));
    await tester.pumpAndSettle();

    expect(edited, 1);
    expect(find.text('14 days'), findsOneWidget);
  });
}
