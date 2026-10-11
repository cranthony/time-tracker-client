import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/pending_action_save.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/outbox_status.dart';
import 'package:time_tracker_client/widgets/status_bar.dart';

/// A server that fails each save with [failWith], while it's set.
class _Actions extends InMemoryActionsRepository {
  _Actions() : super([const PlanAction(id: 'cook', name: 'Cooking')]);

  Object? failWith;
  final calls = <String>[];

  @override
  Future<String> createAction(Map<String, Object?> fields) async {
    calls.add('create ${fields['name']}');
    if (failWith case final error?) throw error;
    return super.createAction(fields);
  }

  @override
  Future<void> updateAction(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    calls.add('update ${action.id}');
    if (failWith case final error?) throw error;
    await super.updateAction(action, changes);
  }
}

void main() {
  late _Actions server;
  late ActionOutbox outbox;

  /// The outbox, made in the test's zone, so its futures run in it, and
  /// the bar for it.
  Future<void> pump(WidgetTester tester) {
    server = _Actions();
    outbox = ActionOutbox(
      store: InMemoryOutboxStore<PendingActionSave>(),
      repository: server,
      clock: () => DateTime(2026, 10, 11, 9),
    );
    addTearDown(outbox.dispose);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StatusBar(
            sources: [
              ActionOutboxStatus(
                outbox,
                nameOf: (id) => id == 'cook' ? 'Cooking' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Does [change], then lets the outbox send what it can.
  Future<void> send(
    WidgetTester tester,
    FutureOr<void> Function() change,
  ) async {
    await change();
    await tester.pump();
    unawaited(outbox.flush());
    await tester.pumpAndSettle();
  }

  testWidgets('says nothing with nothing waiting', (tester) async {
    await pump(tester);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a save the server refused needs you: the sheet says why, '
      'to try again or drop', (tester) async {
    await pump(tester);
    server.failWith = McpException('No room for it.');
    await send(
      tester,
      () => outbox.create({'name': 'Running', 'parent_id': null}),
    );

    expect(find.text("Couldn't save “Running”: tap to fix it"), findsOneWidget);
    await tester.tap(find.byType(StatusBar));
    await tester.pumpAndSettle();
    expect(find.text('Actions waiting to save'), findsOneWidget);
    expect(find.text("Couldn't save: No room for it."), findsOneWidget);

    server.failWith = null;
    await send(tester, () => tester.tap(find.text('Try again')));
    expect(server.calls, ['create Running', 'create Running']);
    expect(find.text('Actions waiting to save'), findsNothing);
    expect(find.text('Nothing waiting: everything is saved.'), findsOneWidget);
  });

  testWidgets("one that couldn't be sent is tried again by itself, and can "
      'be dropped', (tester) async {
    await pump(tester);
    server.failWith = http.ClientException('connection reset');
    await send(
      tester,
      () => outbox.update('cook', {'priority': 2}, group: false),
    );

    expect(
      find.text('1 action waiting: trying again at 9:00 AM'),
      findsOneWidget,
    );
    await tester.tap(find.byType(StatusBar));
    await tester.pumpAndSettle();
    expect(find.text('“Cooking”'), findsOneWidget);
    expect(find.textContaining('trying again at 9:00 AM.'), findsOneWidget);

    await tester.tap(find.text('Drop'));
    await tester.pumpAndSettle();
    expect(outbox.saves, isEmpty);
    expect(find.textContaining('action waiting'), findsNothing);
  });
}
