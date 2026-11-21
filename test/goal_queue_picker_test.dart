import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_queue.dart';
import 'package:time_tracker_client/widgets/goal_queue_picker.dart';

Goal _goal(
  String id, {
  String status = 'inactive',
  List<String> after = const [],
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'status': status,
  'deadline': status == 'active' ? '2026-11-25' : '2026-12-31',
  if (status == 'inactive')
    'activate_when': {
      'after': [
        for (final a in after) {'goal_closed': a},
      ],
    },
  'history': [
    {'status': status, 'at': '2026-11-01T09:00:00'},
  ],
});

void main() {
  final goals = [
    _goal('Work', status: 'active'),
    _goal('Draft', after: ['Work']),
    _goal('Review', after: ['Draft']),
  ];

  Future<QueueSlot?> pick(
    WidgetTester tester,
    String? goalId,
    String button, {
    int index = 0,
  }) async {
    QueueSlot? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await pickQueueSlot(
              context,
              goals: goals,
              goalId: goalId,
              now: () => DateTime(2026, 11, 21, 9),
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(button).at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button).at(index));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('a new goal goes between two in a queue, or at its end', (
    tester,
  ) async {
    expect(find.text('Insert here'), findsNothing);
    final between = await pick(tester, null, 'Insert here', index: 1);
    expect((between?.after, between?.before), ('Draft', 'Review'));
    final end = await pick(tester, null, 'Insert here', index: 2);
    expect((end?.after, end?.before), ('Review', null));
  });

  testWidgets("a goal's own place and those behind it aren't offered", (
    tester,
  ) async {
    QueueSlot? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await pickQueueSlot(
              context,
              goals: goals,
              goalId: 'Draft',
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    // Only after Work, at the end: neither it nor what's behind it.
    expect(find.text('Insert here'), findsOneWidget);
    expect(find.textContaining('New branch'), findsNothing);
    expect(find.text('Draft'), findsNothing);
    expect(find.text('Review'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
