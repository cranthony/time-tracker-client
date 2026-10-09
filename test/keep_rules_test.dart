import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/keep_rules.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  Event event(String id, int from, int to, [List<String> actions = const []]) =>
      Event(
        id: id,
        start: at(from),
        end: at(to),
        summary: id,
        properties: {'action_ids': actions},
      );

  // Sleep (an action in Rest), last night and tonight; work and a walk
  // today; compacted through 10.
  final events = [
    event('night', 0, 7, ['sleep']),
    event('work', 8, 10),
    event('walk', 10, 11),
    event('lunch', 12, 13),
    event('tonight', 22, 23, ['sleep']),
  ];
  const actions = {
    'rest': PlanAction(id: 'rest', name: 'Rest'),
    'sleep': PlanAction(id: 'sleep', name: 'Sleep', parentId: 'rest'),
  };
  Set<String> keep(
    List<KeepRule> rules, {
    DateTime? from,
    DateTime? to,
    String? except,
  }) => keepByRules(
    rules,
    events,
    from: from ?? at(12, 30),
    to: to ?? from ?? at(12, 30),
    lastCompaction: at(10),
    actions: actions,
    except: except,
  );

  test('historical events: each that ended by the last compaction', () {
    expect(keep(KeepRule.defaults), {'night', 'work'});
    expect(keep(const [KeepRule(KeepRuleKind.lastHistorical)]), {'work'});
  });

  test('the next and previous event with an action -- or in a group -- '
      'but never the one the cursor is in, nor the one being edited', () {
    const next = KeepRule(KeepRuleKind.nextWith, actionId: 'sleep');
    const previous = KeepRule(KeepRuleKind.previousWith, actionId: 'rest');
    expect(keep([next, previous]), {'tonight', 'night'});
    // Editing tonight's sleep: none after it.
    expect(keep([next], from: at(22), to: at(23), except: 'tonight'), isEmpty);
  });

  test('kept as JSON; one from a later version left out', () {
    const rule = KeepRule(KeepRuleKind.nextWith, actionId: 'sleep');
    expect(KeepRule.fromJson(rule.toJson()), rule);
    expect(KeepRule.fromJson({'kind': 'someday'}), isNull);
    expect(KeepRule.fromJson({'kind': 'nextWith'}), isNull);
  });

  testWidgets('Settings lists the rules, removes one, and adds another', (
    tester,
  ) async {
    final settings = AppSettings(persist: false);
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    await tester.scrollUntilVisible(
      find.text('Historical events'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Keep by default'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove “Historical events”'));
    await tester.pumpAndSettle();
    expect(settings.keepRules, isEmpty);
    // As the grid's "None" is.
    expect(find.text('None'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Add a rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last historical event').last);
    await tester.pumpAndSettle();
    expect(settings.keepRules, [const KeepRule(KeepRuleKind.lastHistorical)]);
  });
}
