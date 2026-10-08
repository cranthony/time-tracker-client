import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/widgets/app_menu.dart';

void main() {
  group('snapToGrid', () {
    final at = DateTime(2026, 10, 8, 9, 7, 40);

    test('puts a time on the nearest line of the grid', () {
      expect(
        snapToGrid(at, const Duration(minutes: 15)),
        DateTime(2026, 10, 8, 9, 15),
      );
      expect(
        snapToGrid(at, const Duration(minutes: 5)),
        DateTime(2026, 10, 8, 9, 10),
      );
      expect(
        snapToGrid(at, const Duration(minutes: 60)),
        DateTime(2026, 10, 8, 9),
      );
    });

    test('with none, to the nearest minute', () {
      expect(snapToGrid(at, null), DateTime(2026, 10, 8, 9, 8));
    });
  });

  testWidgets('Settings, from the menu, picks the grid', (tester) async {
    final settings = AppSettings(persist: false);
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScope(
          settings: settings,
          child: Scaffold(
            appBar: AppBar(actions: const [AppMenu(serverLabel: 'test')]),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(settings.grid, AppSettings.defaultGrid);
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(settings.grid, isNull);
    await tester.tap(find.text('Every 30 minutes'));
    await tester.pumpAndSettle();
    expect(settings.grid, const Duration(minutes: 30));
  });
}
