import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/circadian.dart';
import 'package:time_tracker_client/screens/circadian_screen.dart';
import 'package:time_tracker_client/services/circadian_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12);

  Future<Circadian> open(
    WidgetTester tester,
    CircadianRepository repository,
  ) async {
    final circadian = Circadian(repository);
    await circadian.load();
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CircadianScreen(circadian: circadian, clock: () => now),
      ),
    );
    return circadian;
  }

  final rhythm = CircadianRhythm(
    revisions: [
      WakeRevision(id: 'a', date: DateTime(2026, 10, 1), hour: 7, minute: 30),
      WakeRevision(
        id: 'b',
        date: DateTime(2026, 10, 30),
        hour: 6,
        minute: 40,
        note: 'no alarm',
      ),
    ],
  );

  testWidgets("shows today's wake time, minimum and windows, and the "
      'history newest first', (tester) async {
    await open(tester, InMemoryCircadianRepository(rhythm));
    expect(find.text('You wake naturally at 6:40 AM'), findsOneWidget);
    expect(find.text('Since Fri, Oct 30'), findsOneWidget);
    expect(find.text('Temperature minimum 4:40 AM'), findsOneWidget);
    expect(find.text('Dim 10:40 PM to 4:40 AM'), findsOneWidget);
    expect(find.text('Bright 4:40 AM to 8:40 AM'), findsOneWidget);
    expect(find.text('Fri, Oct 30 · no alarm'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Woke at 6:40 AM')).dy,
      lessThan(tester.getTopLeft(find.text('Woke at 7:30 AM')).dy),
    );
  });

  testWidgets('says nothing is known yet without a revision', (tester) async {
    await open(tester, InMemoryCircadianRepository());
    expect(find.textContaining('Not known yet'), findsOneWidget);
    expect(find.text('Nothing yet.'), findsOneWidget);
  });

  testWidgets("saves a wake time for today, replacing today's", (tester) async {
    final repository = InMemoryCircadianRepository(rhythm);
    await open(tester, repository);
    await tester.enterText(
      find.widgetWithText(TextField, 'Note (optional)'),
      'camping',
    );
    await tester.tap(find.text('Save wake time'));
    await tester.pumpAndSettle();
    final last = repository.current.revisions.last;
    expect(last.date, DateTime(2026, 11, 2));
    expect((last.hour, last.minute, last.note), (6, 40, 'camping'));
    expect(find.text('Mon, Nov 2 · camping'), findsOneWidget);
    expect(find.text('Since Mon, Nov 2'), findsOneWidget);
  });

  testWidgets("saves the windows, and won't take one over a day", (
    tester,
  ) async {
    final repository = InMemoryCircadianRepository(rhythm);
    await open(tester, repository);
    final dim = find.widgetWithText(TextField, 'Dim window');
    await tester.enterText(dim, '2000');
    await tester.pump();
    expect(
      find.text('Each is whole minutes, up to 1440: a day.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save windows'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(dim, '300');
    await tester.pump();
    await tester.tap(find.text('Save windows'));
    await tester.pumpAndSettle();
    expect(repository.current.windows, const CircadianWindows(dimBefore: 300));
    expect(find.text('Dim 11:40 PM to 4:40 AM'), findsOneWidget);
  });

  testWidgets("shows the server's refusal", (tester) async {
    await open(tester, _Refusing(rhythm));
    await tester.tap(find.text('Save wake time'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save"), findsOneWidget);
  });
}

class _Refusing extends InMemoryCircadianRepository {
  _Refusing(super.current);

  @override
  Future<CircadianRhythm> setNaturalWakeTime(
    DateTime date, {
    required int hour,
    required int minute,
    String? note,
  }) async => throw McpException(
    'Tool error',
    serverMessage: 'That date is more than a year ahead.',
  );
}
