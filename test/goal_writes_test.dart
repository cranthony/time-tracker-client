import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_changes.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

/// A server, as the queue sees it: each call recorded, answered as the
/// server answers a write it made.
class _Server {
  final calls = <({String tool, Map<String, Object?> arguments})>[];
  bool offline = false;
  var version = 1;

  /// What the next calls do instead: throw, or give something.
  final answers =
      <Object? Function(String tool, Map<String, Object?> arguments)>[];

  Future<Object?> call(String tool, Map<String, Object?> arguments) async {
    calls.add((tool: tool, arguments: arguments));
    if (offline) throw http.ClientException('Failed host lookup');
    if (answers.isNotEmpty) return answers.removeAt(0)(tool, arguments);
    if (tool == 'get_goals') return <Object?>[];
    if (tool == 'update_goals') return _batch(arguments);
    if (tool == 'delete_goal') return {'goals': [], 'deleted_ids': []};
    final item = (arguments.values.first as Map).cast<String, Object?>();
    return tool.startsWith('create_')
        ? {
            'goal': {...item, 'version': 1},
            'created_id': item['id'],
          }
        : {...item, 'version': ++version};
  }
}

/// What `update_goals` gives for [arguments]: each goal made or changed,
/// and the ids deleted.
Map<String, Object?> _batch(Map<String, Object?> arguments) => {
  'goals': [
    for (final c in arguments['creates'] as List? ?? const [])
      {...(c as Map).cast<String, Object?>(), 'version': 1},
    for (final u in arguments['updates'] as List? ?? const [])
      {
        ...((u as Map)['goal'] as Map).cast<String, Object?>(),
        'version': (((u['goal'] as Map)['version'] as int?) ?? 0) + 1,
      },
  ],
  'deleted_ids': [
    for (final d in arguments['deletes'] as List? ?? const [])
      (d as Map)['goal_id'],
  ],
};

McpException _conflict(String id, Map<String, Object?>? current) =>
    McpException(
      'Tool failed: changed after version 1 was read',
      serverMessage: 'changed after version 1 was read',
      meta: {
        'conflict': {'id': id, 'current': current},
      },
    );

class _Client extends McpClient {
  _Client(this.server) : super(endpoint: Uri.parse('http://localhost/mcp'));
  final _Server server;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) => server.call(name, arguments);
}

void main() {
  late _Server server;
  late WriteQueue queue;
  late McpGoalsRepository goals;

  setUp(() {
    server = _Server();
    queue = WriteQueue(store: InMemoryOutboxStore(), call: server.call);
    goals = McpGoalsRepository(_Client(server), writes: queue);
  });

  tearDown(() => queue.dispose());

  test('a goal is made, changed and deleted by its own tools', () async {
    final made = await goals.createGoal(
      const Goal(id: '', title: 'Ship', deadline: '2026-12-01'),
    );
    await queue.flush();
    await goals.updateGoal(made.id, {'title': 'Ship it', 'deadline': null});
    await queue.flush();
    await goals.deleteGoal(made.id);
    await queue.flush();

    expect(server.calls.map((c) => c.tool), [
      'create_goal',
      'update_goal',
      'delete_goal',
    ]);
    expect(server.calls[0].arguments, {
      'goal': {
        'title': 'Ship',
        // As the server takes a deadline.
        'deadline': {'at': '2026-12-01'},
        'status': 'active',
        'id': made.id,
      },
    });
    expect(server.calls[1].arguments, {
      'goal': {'id': made.id, 'title': 'Ship it', 'version': 1},
      'clear_fields': ['deadline'],
    });
    expect(server.calls[2].arguments, {'goal_id': made.id, 'if_version': 2});
  });

  test("an ordered change is sent after what's queued before it, joined "
      'with none', () async {
    queue.shown(WriteKind.goal, [
      {'id': 'top', 'title': 'Top', 'status': 'active', 'version': 1},
      {'id': 'sub', 'title': 'Sub', 'status': 'active', 'version': 1},
    ]);
    server.offline = true;
    // An edit waiting to the parent, then closing the sub-goal, then the
    // parent: the parent's close can't jump ahead of the sub-goal's.
    await goals.updateGoal('top', {'title': 'Top!'});
    await goals.updateGoal('sub', {'status': 'done'}, ordered: true);
    await goals.updateGoal('top', {'status': 'done'}, ordered: true);
    await queue.flush();
    server.offline = false;
    server.calls.clear();
    await queue.retryNow();

    expect(
      [
        for (final c in server.calls)
          (c.arguments['goal'] as Map).cast<String, Object?>()
            ..remove('version'),
      ],
      [
        {'id': 'top', 'title': 'Top!'},
        {'id': 'sub', 'status': 'done'},
        {'id': 'top', 'status': 'done'},
      ],
    );
  });

  test('what the server lists is shown with the writes waiting', () async {
    server.offline = true;
    await goals.createGoal(const Goal(id: '', title: 'Offline'));
    expect(queue.items, hasLength(1));
    server.offline = false;
    final listed = await goals.goals();
    expect(listed.single.title, 'Offline');
  });

  test('an ordered change waits for an earlier write that failed', () async {
    queue.shown(WriteKind.goal, [
      {'id': 'top', 'title': 'Top', 'status': 'active', 'version': 1},
      {'id': 'sub', 'title': 'Sub', 'status': 'active', 'version': 1},
    ]);
    server.offline = true;
    await goals.updateGoal('sub', {'status': 'done'}, ordered: true);
    await queue.flush();
    // The sub-goal's write failed, and waits to be tried again; the
    // parent's, queued after it, waits for it, though nothing names it.
    server.offline = false;
    await goals.updateGoal('top', {'status': 'done'}, ordered: true);
    await queue.flush();
    final [sub, top] = queue.items;
    expect(queue.waits(top), isTrue);
    expect(queue.waits(sub), isFalse);
    expect(
      server.calls.where((c) => (c.arguments['goal'] as Map?)?['id'] == 'top'),
      isEmpty,
    );
  });

  group('several goals at once', () {
    final top = {
      'id': 'top',
      'title': 'Top',
      'status': 'active',
      'deadline': '2026-12-01',
      'version': 1,
    };
    final sub = {
      'id': 'sub',
      'title': 'Sub',
      'parent_id': 'top',
      'status': 'active',
      'deadline': '2026-11-01',
      'version': 1,
    };
    final old = {
      'id': 'old',
      'title': 'Old',
      'status': 'obsolete',
      'version': 4,
    };

    /// Closing Top: Sub moved under a new goal, Top done, Old deleted.
    Future<Map<String, String>> close() => goals.changeGoals([
      GoalCreate(
        Goal.fromJson({'id': 'new', 'title': 'Inbox', 'status': 'inactive'}),
      ),
      const GoalUpdate('sub', {'parent_id': 'new'}),
      const GoalUpdate('top', {'status': 'done'}),
      const GoalDelete('old'),
    ]);

    setUp(() => queue.shown(WriteKind.goal, [top, sub, old]));

    test('go as one update_goals call, shown on each goal at once', () async {
      server.offline = true;
      final ids = await close();
      final made = ids['new']!;

      final shown = {
        for (final g in queue.shown(WriteKind.goal, [top, sub, old]))
          g['id']: g,
      };
      expect(shown[made]?['title'], 'Inbox');
      expect(shown['sub']?['parent_id'], made);
      expect(shown['top']?['status'], 'done');
      expect(shown.containsKey('old'), isFalse);
      expect(queue.making, {made});

      server.offline = false;
      server.calls.clear();
      await queue.retryNow();
      expect(server.calls.single.tool, 'update_goals');
      expect(server.calls.single.arguments, {
        'creates': [
          {'id': made, 'title': 'Inbox', 'status': 'inactive'},
        ],
        'updates': [
          {
            'goal': {'id': 'sub', 'parent_id': made, 'version': 1},
          },
          {
            'goal': {'id': 'top', 'status': 'done', 'version': 1},
          },
        ],
        'deletes': [
          {'goal_id': 'old', 'if_version': 4},
        ],
      });
      expect(queue.items, isEmpty);
    });

    test('a lost answer is sent again the same, to be made once', () async {
      server.answers.add(
        (_, _) => throw http.ClientException('Connection reset'),
      );
      await close();
      await queue.flush();
      expect(queue.items, hasLength(1));

      await queue.retryNow();
      expect(server.calls.map((c) => c.tool), ['update_goals', 'update_goals']);
      expect(server.calls[0].arguments, server.calls[1].arguments);
      expect(queue.items, isEmpty);
    });

    test(
      "a goal changed elsewhere in other fields is made to as it is now",
      () async {
        server.answers.add(
          (_, _) =>
              throw _conflict('top', {...top, 'title': 'Top!', 'version': 3}),
        );
        await close();
        await queue.flush();

        expect(server.calls, hasLength(2));
        final updates = server.calls.last.arguments['updates'] as List;
        expect((updates[1] as Map)['goal'], {
          'id': 'top',
          'status': 'done',
          'version': 3,
        });
        expect(queue.items, isEmpty);
      },
    );

    test('every goal changed elsewhere is resolved in turn before the '
        'batch is sent again', () async {
      server.answers.add(
        (_, _) => throw McpException(
          'Tool failed: 2 of the things it changes changed',
          serverMessage: '2 of the things it changes changed',
          meta: {
            'conflicts': [
              {
                'id': 'sub',
                'current': {...sub, 'parent_id': null, 'version': 2},
              },
              {
                'id': 'top',
                'current': {...top, 'status': 'inactive', 'version': 3},
              },
            ],
          },
        ),
      );
      await close();
      await queue.flush();
      await pumpEventQueue();

      var write = queue.items.single;
      expect((write.conflicted, write.conflictId), (true, 'sub'));
      expect(write.moreConflicts.map((c) => c['id']), ['top']);

      // The first resolved: on to the next, still waiting.
      await queue.resolve(queue.conflictView(write), {'parent_id': 'new'});
      await pumpEventQueue();
      write = queue.items.single;
      expect((write.conflicted, write.conflictId), (true, 'top'));
      expect(write.moreConflicts, isEmpty);
      final sent = server.calls.length;
      await queue.flush();
      expect(server.calls, hasLength(sent), reason: 'sent before resolved');

      // The last: sent, each made to the version it is now.
      await queue.resolve(queue.conflictView(write), {'status': 'done'});
      await queue.flush();
      final updates = server.calls.last.arguments['updates'] as List;
      expect([for (final u in updates) (u as Map)['goal']['version']], [2, 3]);
      expect(queue.items, isEmpty);
    });

    test('a write with no base says the version last read', () async {
      final kept = PendingWrite(
        id: 'w1',
        kind: WriteKind.goal.name,
        op: WriteOp.update,
        itemId: 'top',
        changes: const {'title': 'Top!'},
      );
      await queue.putBack(kept);
      await queue.flush();

      expect((server.calls.last.arguments['goal'] as Map)['version'], 1);
    });

    group('a goal changed elsewhere in the same field', () {
      Future<PendingWrite> conflicted() async {
        server.answers.add(
          (_, _) => throw _conflict('top', {
            ...top,
            'status': 'inactive',
            'version': 3,
          }),
        );
        await close();
        await queue.flush();
        await pumpEventQueue();
        final write = queue.items.single;
        expect(write.conflicted, isTrue);
        expect(write.conflictId, 'top');
        return write;
      }

      test('waits, showing just that goal, to be resolved', () async {
        final view = queue.conflictView(await conflicted());
        expect((view.op, view.itemId), (WriteOp.update, 'top'));
        expect(view.changes, {'status': 'done'});
        expect(view.current?['status'], 'inactive');
        expect(queue.label(view), 'goal “Top”');

        await queue.resolve(view, {'status': 'obsolete'});
        await queue.flush();
        final updates = server.calls.last.arguments['updates'] as List;
        expect((updates[1] as Map)['goal'], {
          'id': 'top',
          'status': 'obsolete',
          'version': 3,
        });
        expect(queue.items, isEmpty);
      });

      test('dropped, the rest is sent without it', () async {
        final view = queue.conflictView(await conflicted());

        expect(await queue.drop(view), isTrue);
        await queue.flush();
        final last = server.calls.last.arguments;
        expect(
          [for (final u in last['updates'] as List) (u as Map)['goal']['id']],
          ['sub'],
        );
        expect(last['creates'], hasLength(1));
        expect(queue.items, isEmpty);
      });
    });

    test(
      'a goal changed alone waits for an earlier change that failed',
      () async {
        server.offline = true;
        await goals.updateGoal('sub', {'status': 'done'});
        await queue.flush();
        server.offline = false;
        // Not said to be ordered: every goal change is.
        await goals.updateGoal('top', {'status': 'done'});
        final [first, second] = queue.items;
        expect(queue.waits(second), isTrue);
        expect(queue.waits(first), isFalse);
      },
    );
  });
}
