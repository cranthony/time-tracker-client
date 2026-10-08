import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/widgets/duration_field.dart';
import 'package:time_tracker_client/widgets/edit_page.dart';
import 'package:time_tracker_client/widgets/parts_editor.dart';
import 'package:time_tracker_client/widgets/trait_dialog.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester, String kept) async {
    final controller = TextEditingController(text: kept);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DurationField(controller: controller, label: 'Target'),
        ),
      ),
    );
    return controller;
  }

  group('DurationField', () {
    testWidgets('shows minutes as hours and minutes', (tester) async {
      await pump(tester, '90');

      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('1 h'), findsOneWidget);
      expect(find.text('30 m'), findsOneWidget);
    });

    testWidgets('keeps what is typed as minutes, however it is written', (
      tester,
    ) async {
      final controller = await pump(tester, '');

      for (final (typed, minutes) in [
        ('1h 30m', '90'),
        ('90m', '90'),
        ('45', '45'),
        ('2:15', '135'),
      ]) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump();
        expect(controller.text, minutes, reason: typed);
      }
    });

    testWidgets('says when what is typed is no length of time', (tester) async {
      final controller = await pump(tester, '30');

      await tester.enterText(find.byType(TextField), 'soon');
      await tester.pump();

      expect(controller.text, 'soon');
      expect(find.text('Hours and minutes, like "1h 30m"'), findsOneWidget);
    });

    testWidgets('steps by the hour and by 15 minutes, never below none', (
      tester,
    ) async {
      final controller = await pump(tester, '30');

      await tester.tap(find.byTooltip('An hour more'));
      await tester.pump();
      expect(controller.text, '90');
      expect(find.text('1h 30m'), findsOneWidget);

      await tester.tap(find.byTooltip('15 minutes more'));
      await tester.pump();
      expect(controller.text, '105');

      await tester.tap(find.byTooltip('An hour less'));
      await tester.tap(find.byTooltip('15 minutes less'));
      await tester.pump();
      expect(controller.text, '30');
      // Less than an hour: no hour to take away.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.remove).first,
            )
            .onPressed,
        isNull,
      );
    });
  });

  testWidgets("a trait is edited on a page, Time spent's target in hours "
      'and minutes', (tester) async {
    Trait? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTraitEditor(
              context,
              trait: const Trait(
                id: 'practice',
                name: 'Practice',
                parts: [
                  {'kind': 'duration', 'target_min': 60},
                ],
              ),
              save: (trait) async => saved = trait,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(EditPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Edit Practice'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '1h'), '1h 45m');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved!.parts.single['target_min'], 105);
  });

  testWidgets('parts are edited on a page too, done when they are right', (
    tester,
  ) async {
    List<Part>? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => edited = await showPartsEditor(
              context,
              title: 'Practice for Sam',
              parts: const [
                {'kind': 'duration', 'target_min': 30},
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(EditPage), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '30m'), 'soon');
    await tester.pump();
    // Not a number: not done till it is.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.widgetWithText(TextField, 'soon'), '2h');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(edited!.single['target_min'], 120);
  });
}
