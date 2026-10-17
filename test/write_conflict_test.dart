import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/write_conflict_dialog.dart';

void main() {
  late List<({String tool, Map<String, Object?> arguments})> calls;
  late List<Object? Function()> answers;
  late WriteQueue queue;
  late InMemoryOutboxStore<PendingWrite> store;

  const base = {'id': 'loc1', 'name': 'Home', 'hint': 'flat', 'version': 1};

  /// A write of [op] with [changes], refused as [current] is now, kept.
  Future<PendingWrite> kept(
    WriteOp op,
    Map<String, Object?> changes,
    Map<String, Object?>? current,
  ) async {
    store.items = [
      PendingWrite(
        id: 'w1',
        kind: 'location',
        op: op,
        itemId: 'loc1',
        changes: changes,
        base: base,
        conflicted: true,
        current: current,
        refused: true,
        lastError: 'Changed elsewhere since',
      ),
    ];
    await queue.refresh();
    return queue.items.single;
  }

  Future<Object?> call(
    String tool,
    Map<String, Object?> arguments,
    String _,
  ) async {
    calls.add((tool: tool, arguments: arguments));
    if (answers.isNotEmpty) return answers.removeAt(0)();
    final item = (arguments.values.first as Map).cast<String, Object?>();
    return tool.startsWith('create_') ? {arguments.keys.first: item} : item;
  }

  McpException conflict(Map<String, Object?>? current) => McpException(
    'Tool failed',
    serverMessage: 'changed',
    meta: {
      'conflict': {'current': current},
    },
  );

  /// A queue, made in the test -- not in setUp, outside its clock.
  void begin() {
    calls = [];
    answers = [];
    store = InMemoryOutboxStore();
    queue = WriteQueue(store: store, call: call);
    queue.shown(WriteKind.location, [
      {
        'id': 'loc1',
        'name': 'Home',
        'hint': 'flat',
        'map_location': null,
        'version': 1,
      },
    ]);
    addTearDown(queue.dispose);
  }

  /// Queues [write]ing, refused once as [current] is now.
  Future<PendingWrite> refused(
    void Function() write,
    Map<String, Object?>? current,
  ) async {
    answers.add(() => throw conflict(current));
    write();
    await queue.flush();
    await pumpEventQueue();
    return queue.items.single;
  }

  /// Opens [write]'s dialog; gives what it'll give, once it's closed.
  Future<({Future<bool> resolved})> resolve(
    WidgetTester tester,
    PendingWrite write,
  ) async {
    late Future<bool> resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                resolved = showWriteConflictDialog(context, queue, write),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (resolved: resolved);
  }

  test('the fields both changed are what clash', () async {
    begin();
    final write = await refused(
      () => queue.update(WriteKind.location, 'loc1', {
        'name': 'Flat',
        'hint': 'upstairs',
        'map_location': 'x',
      }),
      {
        'id': 'loc1',
        'name': 'House',
        'hint': 'upstairs',
        'map_location': null,
        'version': 2,
      },
    );
    // The hint was changed the same; the map location wasn't changed
    // elsewhere: only the name clashes.
    expect(WriteQueue.clashes(write), ['name']);
  });

  testWidgets('each field both changed is picked: theirs, mine, or typed', (
    tester,
  ) async {
    begin();
    final write = await kept(
      WriteOp.update,
      {'name': 'Flat', 'hint': 'upstairs'},
      {'id': 'loc1', 'name': 'House', 'hint': 'ground floor', 'version': 2},
    );
    final (:resolved) = await resolve(tester, write);

    expect(find.text('Changed elsewhere'), findsOneWidget);
    expect(find.text('House'), findsOneWidget);
    expect(find.text('Flat'), findsOneWidget);
    // Theirs for the name; something else for the hint.
    await tester.tap(find.text('House'));
    await tester.pump();
    // The hint's "something else": the second field's.
    await tester.enterText(find.byType(TextField).last, 'top floor');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await resolved, isTrue);
    final sent = queue.items.single;
    expect(sent.conflicted, isFalse);
    expect(sent.changes, {'hint': 'top floor'});
    expect(sent.baseVersion, 2);
  });

  testWidgets('deleted elsewhere: put back with the changes', (tester) async {
    begin();
    final write = await kept(WriteOp.update, {'name': 'Flat'}, null);
    final (:resolved) = await resolve(tester, write);

    expect(find.text('Location deleted elsewhere'), findsOneWidget);
    await tester.tap(find.text('Put it back'));
    await tester.pumpAndSettle();

    expect(await resolved, isTrue);
    final made = queue.items.single;
    expect((made.op, made.itemId), (WriteOp.create, 'loc1'));
    expect(made.changes, {'name': 'Flat', 'hint': 'flat'});
  });

  testWidgets('deleted elsewhere: or the changes dropped', (tester) async {
    begin();
    final write = await kept(WriteOp.update, {'name': 'Flat'}, null);
    await resolve(tester, write);

    await tester.tap(find.text('Drop my changes'));
    await tester.pumpAndSettle();

    expect(queue.items, isEmpty);
  });

  testWidgets('a deletion of what changed elsewhere asks first, saying what '
      'changed', (tester) async {
    begin();
    final write = await kept(WriteOp.delete, const {}, {
      'id': 'loc1',
      'name': 'House',
      'hint': 'flat',
      'version': 2,
    });
    await resolve(tester, write);

    expect(find.text('Delete location “Home”?'), findsOneWidget);
    expect(find.textContaining('Home → House'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(queue.items, isEmpty);
  });

  testWidgets('called off, it waits as it was', (tester) async {
    begin();
    final write = await kept(
      WriteOp.update,
      {'name': 'Flat'},
      {'id': 'loc1', 'name': 'House', 'version': 2},
    );
    final (:resolved) = await resolve(tester, write);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(await resolved, isFalse);
    expect(queue.items.single.conflicted, isTrue);
  });
}
