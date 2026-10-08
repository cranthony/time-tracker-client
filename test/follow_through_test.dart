import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/follow_through_dialog.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

Event _event(String id, String summary, int hour) => Event(
  id: id,
  summary: summary,
  start: DateTime(2026, 9, 30, hour),
  end: DateTime(2026, 9, 30, hour + 1),
);

void main() {
  final a = _event('a', 'Call Mom', 12), b = _event('b', 'Texts', 13);
  final over = Overwrite(cancels: [a, b]).counting({'a'});

  test('making room cancels each as the user said: a commitment dropped, '
      'or a change of plan', () async {
    final client = _Client();

    await McpEventsRepository(client).makeRoom(over);

    expect(client.arguments['cancels'], [
      {'event_id': 'a', 'counts_against_follow_through': true},
      {'event_id': 'b', 'counts_against_follow_through': false},
    ]);
  });

  test('so does making room in a proposal', () {
    expect(ProposalEdits.over(over).cancels, [
      (eventId: 'a', countsAgainstFollowThrough: true),
      (eventId: 'b', countsAgainstFollowThrough: false),
    ]);
  });

  test('what was said is kept with a change waiting to save', () {
    final kept = Overwrite.fromJson(over.toJson());

    expect(kept.counts(a), isTrue);
    expect(kept.counts(b), isFalse);
  });

  group('askFollowThrough', () {
    Future<Set<String>?> ask(
      WidgetTester tester,
      Future<void> Function() answer,
    ) async {
      Set<String>? result = {'unanswered'};
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await askFollowThrough(context, [a, b]),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await answer();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('lists each cancel, a change of plan till turned on', (
      tester,
    ) async {
      final counted = await ask(tester, () async {
        expect(find.text('Cancel 2 events to make room?'), findsOneWidget);
        expect(find.text('Call Mom'), findsOneWidget);
        expect(find.textContaining('A change of plan'), findsNWidgets(2));
        await tester.tap(find.text('Texts'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel them'));
      });

      expect(counted, {'b'});
    });

    testWidgets('kept, calls the change off', (tester) async {
      final counted = await ask(
        tester,
        () => tester.tap(find.text('Keep them')),
      );

      expect(counted, isNull);
    });

    testWidgets('asks nothing when nothing is cancelled', (tester) async {
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await askFollowThrough(context, const []),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isEmpty);
    });
  });
}

/// Records what it's sent, and answers that nothing changed.
class _Client extends McpClient {
  _Client() : super(endpoint: Uri.parse('http://test'));

  Map<String, Object?> arguments = const {};

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    this.arguments = arguments;
    return {'events': []};
  }
}
