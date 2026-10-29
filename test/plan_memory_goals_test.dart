import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

class _Client extends McpClient {
  _Client(this.call) : super(endpoint: Uri.parse('http://localhost/mcp'));
  final Future<Object?> Function(String, Map<String, Object?>) call;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) => call(name, arguments);
}

void main() {
  test('the goals are loaded again once a change to them is saved, with '
      'what the server made of it, and just once', () async {
    final started = {'status': 'inactive', 'at': '2026-10-01T08:00:00'};
    var goals = <Map<String, Object?>>[
      {'id': 'g1', 'title': 'Ship', 'status': 'active', 'version': 1},
      {
        'id': 'next',
        'title': 'Next',
        'status': 'inactive',
        'activate_when': {
          'after': [
            {'goal_closed': 'g1'},
          ],
        },
        'history': [started],
        'version': 1,
      },
    ];
    var fetches = 0;
    Future<Object?> server(String tool, Map<String, Object?> arguments) async {
      if (tool == 'get_goals') {
        fetches++;
        return goals;
      }
      // Closing Ship starts what waited for it, as the server does.
      goals = [
        {...goals[0], 'status': 'done', 'version': 2},
        {
          ...goals[1]..remove('activate_when'),
          'status': 'active',
          'history': [
            started,
            {'status': 'active', 'at': '2026-10-29T09:30:00'},
          ],
          'version': 2,
        },
      ];
      return goals[0];
    }

    final queue = WriteQueue(store: InMemoryOutboxStore(), call: server);
    addTearDown(queue.dispose);
    final repository = McpGoalsRepository(_Client(server), writes: queue);
    final memory = PlanMemory()..reloadGoalsOnSave(queue, repository);
    await memory.loadGoals(repository);
    expect(fetches, 1);

    await repository.updateGoal('g1', {'status': 'done'});
    await queue.flush();
    await pumpEventQueue();

    expect(fetches, 2);
    final next = memory.goals!.firstWhere((g) => g.id == 'next');
    expect(next.status, 'active');
    expect(next.history.map((c) => c.status), ['inactive', 'active']);
  });
}
