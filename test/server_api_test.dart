// How the MCP repositories call the Time Tracker MCP server's action,
// people, circle and location tools, and read what they answer.

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';

void main() {
  group('McpGoalsRepository', () {
    final listed = {
      'get_actions': {
        'actions': [
          {
            'id': 'a2',
            'group_id': 'g2',
            'name': 'Play guitar',
            'status': 'active',
            'path': 'Creative › Guitar › Play guitar',
            'effective_color': '#f4511e',
            'effective_priority': 2,
            'holds_label': true,
          },
          {'id': 'a1', 'name': 'Walk', 'status': 'proposed', 'path': 'Walk'},
        ],
        'label_slots_used': 12,
        'label_slots_total': 200,
      },
      'get_action_groups': [
        {
          'id': 'g1',
          'name': 'Creative',
          'background_color': '#f4511e',
          'priority': 2,
          'path': 'Creative',
        },
        {
          'id': 'g2',
          'group_id': 'g1',
          'name': 'Guitar',
          'path': 'Creative › Guitar',
        },
      ],
    };

    test('lists actions and groups as one tree', () async {
      final client = _Client((name, _) => listed[name]);
      final goals = await McpGoalsRepository(client).goals();

      expect(client.calls.map((c) => c.$1), [
        'get_actions',
        'get_action_groups',
      ]);
      expect(client.calls.first.$2, {
        'statuses': ['proposed', 'active', 'archived', 'deleted'],
      });
      expect(
        [for (final g in goals.goals) (g.id, g.parentId, g.isGroup, g.status)],
        [
          ('g1', null, true, 'active'),
          ('g2', 'g1', true, 'active'),
          ('a2', 'g2', false, 'active'),
          ('a1', null, false, 'proposed'),
        ],
      );
      expect(goals.labelSlotsUsed, 12);
      expect(goals.goals[2].effectiveColor, '#f4511e');
    });

    test('creates an action, active, in a group, and a group', () async {
      final client = _Client((_, _) => {'created_id': 'new'});
      final repository = McpGoalsRepository(client);

      expect(
        await repository.createGoal({
          'name': 'Sing',
          'parent_id': 'g1',
          'priority': null,
          'note': 'Harmonies',
        }),
        'new',
      );
      await repository.createGoal({
        'name': 'Music',
        'kind': 'group',
        'parent_id': null,
        'status': 'active',
      });

      expectCall(client.calls[0], (
        'create_action',
        {
          'action': {
            'name': 'Sing',
            'group_id': 'g1',
            'note': 'Harmonies',
            'status': 'active',
          },
        },
      ));
      // A group has no status.
      expectCall(client.calls[1], (
        'create_action_group',
        {
          'group': {'name': 'Music'},
        },
      ));
    });

    test('updates an action or a group, clearing what was cleared', () async {
      final client = _Client((_, _) => {});
      final repository = McpGoalsRepository(client);

      await repository.updateGoal(const Goal(id: 'a1'), {
        'status': 'active',
        'parent_id': null,
        'priority': 1,
      });
      await repository.updateGoal(
        const Goal(id: 'g1', properties: {'kind': 'group'}),
        {'name': 'Making', 'background_color': null},
      );

      expectCall(client.calls[0], (
        'update_action',
        {
          'action': {'id': 'a1', 'status': 'active', 'priority': 1},
          'clear_fields': ['group_id'],
        },
      ));
      expectCall(client.calls[1], (
        'update_action_group',
        {
          'group': {'id': 'g1', 'name': 'Making'},
          'clear_fields': ['background_color'],
        },
      ));
    });

    test("isn't rated or ordered, and has no history", () async {
      final client = _Client((_, _) => null);
      final repository = McpGoalsRepository(client);

      expect(repository.rated, isFalse);
      expect(repository.reorderable, isFalse);
      expect(await repository.history(const Goal(id: 'a1')), isEmpty);
      expect(client.calls, isEmpty);
    });
  });

  group('McpPeopleRepository', () {
    test('lists everyone, with Self, and their circles', () async {
      final client = _Client(
        (name, _) => switch (name) {
          'get_people' => [
            {'id': 'self', 'name': 'Me', 'status': 'active'},
            {
              'id': 'p1',
              'name': 'Sam',
              'context': 'from salsa',
              'circles': ['c1'],
              'circle_names': ['Dance'],
            },
          ],
          _ => [
            {
              'id': 'c1',
              'name': 'Dance',
              'note': 'Thursdays',
              'member_ids': ['p1'],
            },
          ],
        },
      );
      final people = await McpPeopleRepository(client).people();

      expect(client.calls.map((c) => c.$1), ['get_people', 'get_circles']);
      expect(client.calls.first.$2, {
        'statuses': ['active', 'archived', 'deleted'],
      });
      expect(people.withSelf.map((p) => p.name), ['Me', 'Sam']);
      expect(people.circles.single.memberIds, ['p1']);
    });

    test(
      'creates a person, and updates one, clearing what was cleared',
      () async {
        final client = _Client(
          (name, _) => name == 'create_person'
              ? {
                  'person': {'id': 'p2', 'name': 'Priya'},
                  'created_id': 'p2',
                }
              : {'id': 'p1', 'name': 'Sam'},
        );
        final repository = McpPeopleRepository(client);

        final priya = await repository.createPerson(
          const Person(
            id: '',
            name: 'Priya',
            circleIds: ['c1'],
            traits: PersonTraits(select: ['present']),
          ),
        );
        await repository.updatePerson('p1', {
          'name': 'Sam',
          'context': null,
          'traits': null,
        });

        expect(priya.id, 'p2');
        expect(client.calls[0].$2, {
          'person': {
            'name': 'Priya',
            'status': 'active',
            'circles': ['c1'],
            'traits': {
              'select': ['present'],
            },
          },
        });
        expectCall(client.calls[1], (
          'update_person',
          {
            'person': {'id': 'p1', 'name': 'Sam'},
            'clear_fields': ['context', 'traits'],
          },
        ));
      },
    );

    test('creates, updates and deletes circles and locations', () async {
      final client = _Client(
        (name, _) => switch (name) {
          'create_circle' => {
            'circle': {'id': 'c2', 'name': 'Work'},
            'created_id': 'c2',
          },
          'create_location' => {
            'location': {'id': 'l1', 'name': 'Home'},
            'created_id': 'l1',
          },
          'update_location' => {'id': 'l1', 'name': 'Home'},
          'get_locations' => [
            {'id': 'l1', 'name': 'Home', 'hint': "'my place'"},
          ],
          _ => {'id': 'c2', 'name': 'Work'},
        },
      );
      final repository = McpPeopleRepository(client);

      expect(
        (await repository.createCircle(const Circle(id: '', name: 'Work'))).id,
        'c2',
      );
      await repository.updateCircle('c2', {'note': null});
      await repository.deleteCircle('c2');
      expect(
        (await repository.createLocation(const Location(id: '', name: 'Home')))
            .id,
        'l1',
      );
      await repository.updateLocation('l1', {'hint': null});
      expect((await repository.locations()).single.hint, "'my place'");
      await repository.deleteLocation('l1');

      expect(client.calls.map((c) => c.$1), [
        'create_circle',
        'update_circle',
        'delete_circle',
        'create_location',
        'update_location',
        'get_locations',
        'delete_location',
      ]);
      expect(client.calls[0].$2, {
        'circle': {'name': 'Work'},
      });
      expect(client.calls[1].$2, {
        'circle': {'id': 'c2'},
        'clear_fields': ['note'],
      });
      expect(client.calls[2].$2, {'circle_id': 'c2'});
      expect(client.calls[4].$2, {
        'location': {'id': 'l1'},
        'clear_fields': ['hint'],
      });
      expect(client.calls[6].$2, {'location_id': 'l1'});
    });
  });
}

/// Expects [call] to be [expected]: the tool's name, and what it was
/// given.
void expectCall(
  (String, Map<String, Object?>) call,
  (String, Map<String, Object?>) expected,
) {
  expect(call.$1, expected.$1);
  expect(call.$2, expected.$2);
}

/// Records each tool call, and answers with [answer].
class _Client extends McpClient {
  _Client(this.answer) : super(endpoint: Uri.parse('http://test'));

  final Object? Function(String name, Map<String, Object?> arguments) answer;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}
