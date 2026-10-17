import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/outbox/actions_shown.dart';
import 'package:time_tracker_client/outbox/legacy_writes.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';

/// The server's reads: an action, a group and the priority colors.
class _Client extends McpClient {
  _Client() : super(endpoint: Uri.parse('http://localhost'));

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async => switch (name) {
    'get_actions' => {
      'actions': [
        {'id': 'run', 'name': 'Running', 'status': 'active', 'version': 3},
      ],
      'label_slots_used': 1,
      'label_slots_total': 200,
    },
    'get_action_groups' => [
      {'id': 'sport', 'name': 'Sport', 'version': 1},
    ],
    'get_priority_colors' => [
      for (final p in [0, 1, 2, 3]) {'priority': p, 'color': '#00000$p'},
    ],
    _ => throw http.ClientException('offline'),
  };
}

McpException _conflict(Map<String, Object?>? current) => McpException(
  'Tool failed: changed after version 3 was read',
  serverMessage: 'changed after version 3 was read',
  meta: {
    'conflict': {'current': current},
  },
);

void main() {
  late List<({String tool, Map<String, Object?> arguments})> calls;
  late List<Object? Function(String tool, Map<String, Object?> arguments)>
  answers;
  late WriteQueue queue;
  late McpActionsRepository repository;

  setUp(() {
    calls = [];
    answers = [];
    queue = WriteQueue(
      store: InMemoryOutboxStore(),
      call: (tool, arguments) async {
        calls.add((tool: tool, arguments: arguments));
        if (answers.isEmpty) throw http.ClientException('offline');
        return answers.removeAt(0)(tool, arguments);
      },
    );
    repository = McpActionsRepository(_Client(), writes: queue);
  });

  tearDown(() => queue.dispose());

  test('an action made and changed is shown at once, then sent with the '
      "server's names for its fields", () async {
    await repository.actions();
    final id = await repository.createAction({
      'name': 'Swimming',
      'parent_id': 'sport',
      'kind': 'action',
    });
    await pumpEventQueue();
    final shown = await repository.actions();

    expect(
      shown.actions.map((a) => (a.id, a.name, a.parentId)),
      contains((id, 'Swimming', 'sport')),
    );
    answers.add(
      (_, arguments) => {
        'changed': [
          {...(arguments['action'] as Map), 'version': 1},
        ],
        'created_id': id,
      },
    );
    await queue.flush();
    expect(calls.single.tool, 'create_action');
    expect(calls.single.arguments, {
      'action': {
        'group_id': 'sport',
        'name': 'Swimming',
        'status': 'active',
        'id': id,
      },
    });
  });

  test('a change is made to the version last seen; one changed elsewhere in '
      'other fields is made to it as it is now', () async {
    await repository.actions();
    await repository.updateAction(const PlanAction(id: 'run'), {
      'note': 'mornings',
    });
    await pumpEventQueue();
    answers
      ..add(
        (_, _) => throw _conflict({
          'id': 'run',
          'name': 'Jogging',
          'status': 'active',
          'version': 4,
        }),
      )
      ..add(
        (_, arguments) => {
          'changed': [
            {...(arguments['action'] as Map), 'name': 'Jogging', 'version': 5},
          ],
        },
      );
    await queue.flush();

    expect(calls.map((c) => (c.arguments['action'] as Map)['version']), [3, 4]);
    expect(queue.items, isEmpty);
    expect(
      (await repository.actions()).actions.map((a) => a.name),
      contains('Running'), // As the server lists it, now nothing waits.
    );
  });

  test(
    'a group is changed by its own tool, and a clearing is sent as one',
    () async {
      await repository.actions();
      await repository.updateAction(
        const PlanAction(id: 'sport', properties: {'kind': 'group'}),
        {'note': null, 'priority': 1},
      );
      await pumpEventQueue();
      answers.add((_, arguments) => {'changed': []});
      await queue.flush();

      expect(calls.single.tool, 'update_action_group');
      expect(calls.single.arguments, {
        'group': {'id': 'sport', 'priority': 1, 'version': 1},
        'clear_fields': ['note'],
      });
    },
  );

  test('a priority color changed shows at once, and is set by a call of its '
      'own, made once', () async {
    await repository.actions();
    await repository.updatePriorityColor(2, '#ff0000');
    await repository.updatePriorityColor(0, '#00ff00');
    await pumpEventQueue();

    expect(priorityPalette.value[2], const Color(0xffff0000));
    await repository.actions();
    expect(priorityPalette.value[0], const Color(0xff00ff00));
    for (final _ in [1, 2]) {
      answers.add(
        (_, arguments) => {
          'colors': [
            {'priority': arguments['priority'], 'color': arguments['color']},
          ],
        },
      );
    }
    await queue.flush();
    expect(calls.map((c) => c.arguments), [
      {'priority': 2, 'color': '#ff0000'},
      {'priority': 0, 'color': '#00ff00'},
    ]);
  });

  group('ActionWrites', () {
    test('a failed write is replaced, retried or discarded', () async {
      final writes = ActionWrites(queue);
      final id = writes.create({'name': 'Swim', 'parent_id': null});
      await pumpEventQueue();
      answers.add((_, _) => throw McpException('No room', serverMessage: 'x'));
      await queue.flush();
      final failed = writes.saves.single;
      expect((failed.isNew, failed.failed, failed.refused), (true, true, true));
      expect(failed.changes, {'name': 'Swim', 'status': 'active'});

      writes.update(id, {'name': 'Swimming'}, group: false, replace: true);
      await pumpEventQueue();
      expect(writes.saves.single.changes['name'], 'Swimming');
      expect(writes.saves.single.failed, isFalse);
      // Refused, it wasn't made: sent again under the same write id.
      expect(writes.saves.single.write.id, failed.write.id);

      writes.discard(id);
      await pumpEventQueue();
      expect(writes.saves, isEmpty);
    });

    test('shown: made and changed in the tree, a parent a group_id', () async {
      final writes = ActionWrites(queue);
      final listed = actionTree({
        'actions': {
          'actions': [
            {'id': 'run', 'name': 'Running', 'status': 'active'},
          ],
        },
        'groups': [
          {'id': 'sport', 'name': 'Sport'},
        ],
      });
      writes.update('run', {'parent_id': 'sport'}, group: false);
      final id = writes.create({'name': 'Swim', 'parent_id': 'sport'});
      await pumpEventQueue();

      final shown = actionsShown(listed, writes);
      expect(shown.actions.map((a) => (a.id, a.path)), [
        ('sport', 'Sport'),
        ('run', 'Sport › Running'),
        (id, 'Sport › Swim'),
      ]);
    });
  });

  group('what an older version left waiting', () {
    late SharedPreferencesAsync prefs;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      prefs = SharedPreferencesAsync();
    });

    test('its action saves are read into the queue, first, and removed once '
        "it's saved with them", () async {
      await prefs.setString(
        'goal_outbox',
        jsonEncode([
          {
            'id': 's1',
            'goal_id': 'unsaved-abc-0',
            'is_new': true,
            'changes': {'name': 'Swim', 'parent_id': 'sport'},
            'attempts': 1,
            'last_error': 'offline',
          },
          {
            'id': 's2',
            'goal_id': 'sport',
            'is_new': false,
            'is_group': true,
            'changes': {'note': null},
          },
        ]),
      );
      final store = PrefsOutboxStore.writes(prefs: prefs);
      final writes = WriteQueue(store: store, call: _never);
      await writes.refresh();

      expect(writes.items.map((w) => (w.id, w.kind, w.op, w.itemId)), [
        ('s1', 'action', WriteOp.create, 'unsaved-abc-0'),
        ('s2', 'action_group', WriteOp.update, 'sport'),
      ]);
      expect(writes.items.map((w) => w.changes), [
        {'group_id': 'sport', 'name': 'Swim', 'status': 'active'},
        {'note': null},
      ]);
      expect(writes.items.first.attempts, 1);
      // Not saved yet: still where it was.
      expect(await prefs.getString('goal_outbox'), isNotNull);

      await writes.drop(writes.items.last);
      expect(await prefs.getString('goal_outbox'), isNull);
      final again = WriteQueue(
        store: PrefsOutboxStore.writes(prefs: prefs),
        call: _never,
      );
      await again.refresh();
      expect(again.items.map((w) => w.id), ['s1']);
      writes.dispose();
      again.dispose();
    });

    test('read in twice -- the app closed before the old store was emptied '
        '-- each is kept once', () async {
      final saves = jsonEncode([
        {
          'id': 's1',
          'goal_id': 'run',
          'changes': {'name': 'Jog'},
        },
      ]);
      await prefs.setString('goal_outbox', saves);
      final store = WriteQueueStore(prefs: prefs);
      await store.save(await store.load());
      await prefs.setString('goal_outbox', saves);

      expect((await store.load()).map((w) => w.id), ['s1']);
    });
  });
}

/// A write call for a queue that's never to send.
Future<Object?> _never(String _, Map<String, Object?> _) async =>
    throw StateError('not to be sent');
