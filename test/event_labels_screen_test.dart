import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event_label.dart';
import 'package:time_tracker_client/screens/event_labels_screen.dart';
import 'package:time_tracker_client/services/event_labels_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

void main() {
  Widget app(EventLabelsRepository repo, {Future<void> Function()? onSignIn}) =>
      MaterialApp(
        home: EventLabelsScreen(
          repository: repo,
          serverLabel: 'offline demo',
          onSignIn: onSignIn,
        ),
      );

  test('EventLabel.fromJson keeps every property the server sent', () {
    final label = EventLabel.fromJson({
      'id': '3',
      'name': 'Exercise',
      'background_color': '#7bd148',
      'priority': 2,
      'fixed_time': true,
      'new_thing': 'x',
    });
    expect(label.id, '3');
    expect(label.name, 'Exercise');
    expect(label.backgroundColor, '#7bd148');
    expect(label.priority, 2);
    expect(label.fixedTime, isTrue);
    expect(label.properties['new_thing'], 'x');
  });

  test('parseColor reads #rrggbb and nothing else', () {
    expect(parseColor('#7bd148'), const Color(0xFF7BD148));
    expect(parseColor('7bd148'), isNull);
    expect(parseColor('#fff'), isNull);
    expect(parseColor(null), isNull);
  });

  testWidgets('lists labels by priority, with their properties', (
    tester,
  ) async {
    final repo = InMemoryEventLabelsRepository([
      const EventLabel(id: '1', name: 'Sleep', priority: 1, fixedTime: true),
      const EventLabel(id: '4', name: 'Misc'),
      const EventLabel(id: '2', name: 'Work', priority: 3, fixedTime: false),
      const EventLabel(id: '3', name: 'Exercise', priority: 2),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(names, ['Sleep', 'Exercise', 'Work', 'Misc']);
    expect(find.text('Priority 1 · Fixed time'), findsOneWidget);
    expect(find.text('Priority 2'), findsOneWidget);
    expect(find.text('Priority 3 · Flexible time'), findsOneWidget);
    expect(find.text('No priority'), findsOneWidget);
  });

  testWidgets('tapping a label shows all its properties', (tester) async {
    final repo = InMemoryEventLabelsRepository([
      EventLabel.fromJson({
        'id': '3',
        'name': 'Exercise',
        'background_color': '#7bd148',
        'priority': 2,
        'fixed_time': null,
        'new_thing': 'x',
      }),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exercise'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    String? valueOf(String key) {
      final label = find.descendant(of: dialog, matching: find.text(key));
      final column = find.ancestor(of: label, matching: find.byType(Column));
      final value = find.descendant(
        of: column.first,
        matching: find.byWidgetPredicate(
          (w) => w is SelectableText || (w is Text && w.data != key),
        ),
      );
      return switch (tester.widget(value.first)) {
        SelectableText(:final data) => data,
        Text(:final data) => data,
        _ => null,
      };
    }

    expect(valueOf('id'), '3');
    expect(valueOf('name'), 'Exercise');
    expect(valueOf('background_color'), '#7bd148');
    expect(valueOf('priority'), '2');
    expect(valueOf('fixed_time'), '(none)');
    // Ones the app doesn't know about yet too.
    expect(valueOf('new_thing'), 'x');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('says when there are none', (tester) async {
    await tester.pumpWidget(app(InMemoryEventLabelsRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No event labels.'), findsOneWidget);
  });

  testWidgets('asks to sign in when the server needs it', (tester) async {
    var signedIn = false;
    final repo = _SignInRepository(() => signedIn, [
      const EventLabel(id: '1', name: 'Sleep'),
    ]);
    await tester.pumpWidget(app(repo, onSignIn: () async => signedIn = true));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your event labels.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep'), findsOneWidget);
  });
}

/// Needs sign-in until [signedIn] says otherwise.
class _SignInRepository extends InMemoryEventLabelsRepository {
  _SignInRepository(this.signedIn, super.labels);

  final bool Function() signedIn;

  @override
  Future<List<EventLabel>> labels() {
    if (!signedIn()) throw SignInRequiredException();
    return super.labels();
  }
}
