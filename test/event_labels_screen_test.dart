import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event_label.dart';
import 'package:time_tracker_client/screens/event_labels_screen.dart';
import 'package:time_tracker_client/services/event_labels_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';

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

  test(
    'updateLabel sends changes, and names cleared ones in clear_fields',
    () async {
      final client = _FakeClient([
        {'id': '1', 'name': 'Exercise', 'background_color': '#4986e7'},
      ]);
      final labels = await McpEventLabelsRepository(client).updateLabel(
        const EventLabel(id: '1', name: 'Exercise'),
        {'background_color': null, 'priority': null, 'name': 'Running'},
      );
      expect(client.calls.single.$1, 'update_event_label');
      expect(client.calls.single.$2, {
        'label': {'id': '1', 'name': 'Running'},
        'clear_fields': ['background_color', 'priority'],
      });
      expect(labels.single.backgroundColor, '#4986e7');

      await McpEventLabelsRepository(client)
          .updateLabel(const EventLabel(id: '1'), {'note': 'Runs'});
      expect(client.calls.last.$2, {
        'label': {'id': '1', 'note': 'Runs'},
      });
    },
  );

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

  group('editing a label', () {
    List<EventLabel> sample() => [
      const EventLabel(
        id: '1',
        name: 'Exercise',
        backgroundColor: '#7bd148',
        priority: 2,
        fixedTime: false,
      ),
    ];

    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    Future<void> openColor(
      WidgetTester tester,
      EventLabelsRepository repo,
    ) async {
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      final value = inDialog(find.text('#7bd148'));
      await tester.ensureVisible(value);
      await tester.tap(value);
      await tester.pumpAndSettle();
    }

    Future<void> keepAndSave(WidgetTester tester) async {
      await tester.ensureVisible(find.byTooltip('Keep edit'));
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
    }

    Color? tileColor(WidgetTester tester) =>
        tester.widget<Icon>(find.byIcon(Icons.label)).color;

    testWidgets('picks a color from the palette', (tester) async {
      final repo = _RecordingRepository(sample());
      await openColor(tester, repo);
      expect(
        find.text("With no color, the label takes its priority's color."),
        findsOneWidget,
      );
      // The current color is ticked.
      expect(
        tester.getSemantics(find.bySemanticsLabel('#7bd148')),
        isSemantics(isSelected: true),
      );

      await tester.tap(find.bySemanticsLabel('#4986e7'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '#4986e7'), findsOneWidget);
      await keepAndSave(tester);

      expect(repo.saved, [
        {'background_color': '#4986e7'},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Saved.'), findsOneWidget);
      expect(tileColor(tester), const Color(0xFF4986E7));
    });

    testWidgets('takes a typed hex color', (tester) async {
      final repo = _RecordingRepository(sample());
      await openColor(tester, repo);
      await tester.enterText(find.widgetWithText(TextField, '#7bd148'), 'zz');
      await tester.pump();
      expect(find.text('Use #rrggbb'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123ABC');
      await tester.pump();
      expect(find.text('Use #rrggbb'), findsNothing);
      await keepAndSave(tester);
      expect(repo.saved, [
        {'background_color': '#123abc'},
      ]);
    });

    testWidgets('picks any color from the square and hue bar', (tester) async {
      final repo = _RecordingRepository(sample());
      await openColor(tester, repo);
      await tester.tap(find.text('More colors'));
      await tester.pumpAndSettle();
      // The square's bottom-left corner is black, whatever the hue.
      final pad = find.byKey(const Key('saturation-value'));
      await tester.ensureVisible(pad);
      await tester.tapAt(tester.getBottomLeft(pad) + const Offset(2, -2));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '#000000'), findsOneWidget);
      await keepAndSave(tester);
      expect(repo.saved, [
        {'background_color': '#000000'},
      ]);
    });

    testWidgets('clears the color and the priority', (tester) async {
      final repo = _RecordingRepository(sample());
      await openColor(tester, repo);
      await tester.tap(find.bySemanticsLabel('No color'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '#7bd148'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Keep edit'));
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();

      final priority = inDialog(find.text('2'));
      await tester.ensureVisible(priority);
      await tester.tap(priority);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      // The old values, struck through.
      expect(inDialog(find.text('#7bd148')), findsOneWidget);
      expect(inDialog(find.text('2')), findsOneWidget);

      await tester.tap(find.text('Save 2 changes'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'background_color': null, 'priority': null},
      ]);
      expect(find.text('No priority · Flexible time'), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsOneWidget);
    });

    testWidgets('renames', (tester) async {
      final repo = _RecordingRepository(sample());
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Exercise')).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Running');
      await keepAndSave(tester);
      expect(repo.saved, [
        {'name': 'Running'},
      ]);
      expect(find.text('Running'), findsOneWidget);
    });

    testWidgets('sets fixed time and a note, and clears the name', (
      tester,
    ) async {
      final repo = _RecordingRepository(sample());
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      Future<void> edit(Finder value) async {
        await tester.ensureVisible(value);
        await tester.tap(value);
        await tester.pumpAndSettle();
      }

      Future<void> keep() async {
        await tester.ensureVisible(find.byTooltip('Keep edit'));
        await tester.tap(find.byTooltip('Keep edit'));
        await tester.pumpAndSettle();
      }

      await edit(inDialog(find.text('Exercise')).last);
      await tester.enterText(find.byType(TextField), '');
      await keep();

      await edit(inDialog(find.text('false')));
      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      await keep();

      await edit(inDialog(find.text('(none)')).last);
      await tester.enterText(find.byType(TextField), 'Runs and swims');
      await keep();

      await tester.tap(find.text('Save 3 changes'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'name': null, 'fixed_time': null, 'note': 'Runs and swims'},
      ]);
      // A label with no name is hidden.
      expect(find.text('(no name)'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('shows the server\'s error and keeps the edit', (tester) async {
      final repo = _RecordingRepository(sample())
        ..error = McpException(
          'Tool update_event_label failed: Not a calendar color',
        );
      await openColor(tester, repo);
      await tester.tap(find.bySemanticsLabel('#4986e7'));
      await tester.pumpAndSettle();
      await keepAndSave(tester);
      expect(
        find.text(
          "Couldn't save. Tool update_event_label failed: "
          'Not a calendar color',
        ),
        findsOneWidget,
      );
      expect(find.text('Save 1 change'), findsOneWidget);
      expect(repo.saved, isEmpty);
    });
  });

  testWidgets('hides labels with no name', (tester) async {
    final repo = InMemoryEventLabelsRepository([
      const EventLabel(id: '1', name: 'Sleep'),
      const EventLabel(id: '2', backgroundColor: '#a4bdfc'),
      const EventLabel(id: '3', name: '', backgroundColor: '#7ae7bf'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(names, ['Sleep']);
    expect(find.text('(no name)'), findsNothing);
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

/// Records what's saved, and fails with [error] while it's set.
class _RecordingRepository extends InMemoryEventLabelsRepository {
  _RecordingRepository(super.labels);

  final saved = <Map<String, Object?>>[];
  Object? error;

  @override
  Future<List<EventLabel>> updateLabel(
    EventLabel label,
    Map<String, Object?> changes,
  ) async {
    if (error case final error?) throw error;
    saved.add(changes);
    return super.updateLabel(label, changes);
  }
}

/// Answers every tool call with [result], and records the calls.
class _FakeClient extends McpClient {
  _FakeClient(this.result) : super(endpoint: Uri.parse('http://test'));

  final Object? result;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((name, arguments));
    return result;
  }
}
