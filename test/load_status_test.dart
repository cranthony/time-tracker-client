import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/load_status.dart';
import 'package:time_tracker_client/widgets/status_bar.dart';

void main() {
  final now = DateTime(2026, 10, 11, 9);
  final offline = http.ClientException('connection reset');

  Future<LoadStatus> pump(WidgetTester tester) async {
    final loads = LoadStatus('events', clock: () => now);
    addTearDown(loads.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(bottomNavigationBar: StatusBar(sources: [loads])),
      ),
    );
    return loads;
  }

  testWidgets('a failure is tried again by itself, backing off, until it '
      'loads', (tester) async {
    final loads = await pump(tester);
    var tries = 0;
    loads.bind(() async {
      tries++;
      if (tries < 2) {
        loads.failed(offline, hasData: true);
      } else {
        loads.loaded();
      }
    });

    loads.failed(offline, hasData: true);
    await tester.pump();
    expect(loads.nextAttemptAt, now.add(const Duration(seconds: 5)));
    expect(
      find.text("Couldn't load events: trying again at 9:00 AM"),
      findsOne,
    );

    await tester.pump(const Duration(seconds: 5));
    expect(tries, 1);
    expect(loads.nextAttemptAt, now.add(const Duration(seconds: 10)));

    await tester.pump(const Duration(seconds: 10));
    expect(tries, 2);
    expect(loads.error, isNull);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('with nothing shown, or signed out, the page says so, not the '
      'bar', (tester) async {
    final loads = await pump(tester);
    loads.failed(offline, hasData: false);
    await tester.pump();
    expect(find.byType(InkWell), findsNothing);
    expect(loads.nextAttemptAt, isNotNull);

    // Nor is it tried again by itself: only signing in helps.
    loads.failed(SignInRequiredException(), hasData: true);
    await tester.pump();
    expect(find.byType(InkWell), findsNothing);
    expect(loads.nextAttemptAt, isNull);
  });

  testWidgets('the sheet says why, to try again now', (tester) async {
    final loads = await pump(tester);
    var tries = 0;
    loads.bind(() async => tries++);
    loads.failed(offline, hasData: true);
    await tester.pump();

    await tester.tap(find.byType(StatusBar));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load events"), findsOneWidget);
    expect(
      find.textContaining(
        "Couldn't reach the server, or the connection "
        "dropped. What's shown may be out of date. Trying again at",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again now'));
    await tester.pump();
    expect(tries, 1);
  });

  testWidgets('unbinding forgets the failure, and stops trying again', (
    tester,
  ) async {
    final loads = await pump(tester);
    var tries = 0;
    loads.bind(() async => tries++);
    loads.failed(offline, hasData: true);
    await tester.pump();

    loads.unbind();
    await tester.pump(const Duration(minutes: 1));
    expect(tries, 0);
    expect(loads.error, isNull);
    expect(find.byType(InkWell), findsNothing);
  });
}
