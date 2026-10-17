import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/widgets/app_menu.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Future<void> Function()? onRefresh,
  }) => tester.pumpWidget(
    MaterialApp(
      home: AppSettingsScope(
        settings: AppSettings(persist: false),
        child: Scaffold(
          appBar: AppBar(
            actions: [AppMenu(serverLabel: 'test', onRefresh: onRefresh)],
          ),
        ),
      ),
    ),
  );

  testWidgets('without onRefresh, no refresh button', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Refresh'), findsNothing);
  });

  testWidgets('the refresh button refreshes, off until it is done', (
    tester,
  ) async {
    var refreshes = 0;
    var done = Completer<void>();
    await pump(
      tester,
      onRefresh: () {
        refreshes++;
        return done.future;
      },
    );

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(refreshes, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Tapped again while it's refreshing: nothing.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(refreshes, 1);

    done.complete();
    await tester.pump();
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    done = Completer<void>()..complete();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(refreshes, 2);
  });
}
