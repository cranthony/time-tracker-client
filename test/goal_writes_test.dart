import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/goal.dart';
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

  Future<Object?> call(String tool, Map<String, Object?> arguments) async {
    calls.add((tool: tool, arguments: arguments));
    if (offline) throw http.ClientException('Failed host lookup');
    if (tool == 'get_goals') return <Object?>[];
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
        'deadline': '2026-12-01',
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

  test("a change that mustn't join an earlier one is sent after what's "
      'queued between them', () async {
    queue.shown(WriteKind.goal, [
      {'id': 'top', 'title': 'Top', 'status': 'active', 'version': 1},
      {'id': 'sub', 'title': 'Sub', 'status': 'active', 'version': 1},
    ]);
    server.offline = true;
    // An edit waiting to the parent, then closing the sub-goal, then the
    // parent: the parent's close can't jump ahead of the sub-goal's.
    await goals.updateGoal('top', {'title': 'Top!'});
    await goals.updateGoal('sub', {'status': 'done'}, join: false);
    await goals.updateGoal('top', {'status': 'done'}, join: false);
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
}
