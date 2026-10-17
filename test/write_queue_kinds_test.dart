import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/scoring.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/travel_time.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/habits_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';

/// The server, for reads: [answers] by tool; offline for anything else.
class _Client extends McpClient {
  _Client(this.answers) : super(endpoint: Uri.parse('http://localhost'));

  final Map<String, Object?> answers;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async => answers.containsKey(name)
      ? answers[name]
      : throw http.ClientException('Failed host lookup');
}

void main() {
  late List<({String tool, Map<String, Object?> arguments})> calls;
  late WriteQueue queue;
  var offline = true;

  Future<Object?> call(
    String tool,
    Map<String, Object?> arguments,
    String _,
  ) async {
    calls.add((tool: tool, arguments: arguments));
    if (offline) throw http.ClientException('Failed host lookup');
    final item = (arguments.values.first as Map).cast<String, Object?>();
    return switch (tool) {
      // Gives the trait itself, not wrapped.
      'create_trait' => {...item, 'version': 1},
      'set_scoring_defaults' => item,
      _ when tool.startsWith('create_') => {
        arguments.keys.first: {...item, 'version': 1},
      },
      _ => {...item, 'version': 2},
    };
  }

  setUp(() {
    calls = [];
    offline = true;
    queue = WriteQueue(store: InMemoryOutboxStore(), call: call);
  });

  tearDown(() => queue.dispose());

  test(
    'the scoring defaults are set whole, with neither id nor version',
    () async {
      final traits = McpTraitsRepository(
        _Client({
          'get_scoring_defaults': {
            'traits': {'kind': 'mean'},
          },
        }),
        writes: queue,
      );
      await traits.scoringDefaults();

      final set = await traits.setScoringDefaults(
        const ScoringDefaults(
          traits: Aggregation(statistic: 'percentile', percentile: 0),
        ),
      );
      expect(set.traits?.percentile, 0);
      expect((await traits.scoringDefaults()).traits?.percentile, 0);

      offline = false;
      await queue.retryNow();
      expect(calls.last.tool, 'set_scoring_defaults');
      final sent = calls.last.arguments['defaults'] as Map;
      expect(sent.containsKey('id'), isFalse);
      expect(sent.containsKey('version'), isFalse);
      expect(queue.items, isEmpty);
    },
  );

  test(
    "a trait made offline is shown, and saved from what create_trait gives",
    () async {
      final traits = McpTraitsRepository(
        _Client({'get_traits': <Object?>[]}),
        writes: queue,
      );

      final made = await traits.createTrait(
        const Trait(id: '', name: 'Brave', parts: []),
      );
      expect(made.id, isNotEmpty);
      expect((await traits.traits()).single.name, 'Brave');

      offline = false;
      await queue.retryNow();
      expect(queue.items, isEmpty);
      expect((calls.last.arguments['trait'] as Map)['id'], made.id);
    },
  );

  test('a circle made offline is among the people read', () async {
    final people = McpPeopleRepository(
      _Client({'get_people': <Object?>[], 'get_circles': <Object?>[]}),
      writes: queue,
    );

    final family = await people.createCircle(
      const Circle(id: '', name: 'Family'),
    );
    final read = await people.people();

    expect(read.circles.single.id, family.id);
  });

  test('a habit made and changed offline joins one write', () async {
    final habits = McpHabitsRepository(
      _Client({'get_habits': <Object?>[]}),
      writes: queue,
    );

    final guitar = await habits.createHabit(
      const Habit(id: '', name: 'Guitar', actionId: 'guitar'),
    );
    await habits.updateHabit(guitar.id, {'note': 'scales'});
    await pumpEventQueue();

    expect(queue.items.single.op, WriteOp.create);
    expect((await habits.habits()).single.note, 'scales');
  });

  test('a travel time made offline, between places made offline, waits '
      'for them', () async {
    final people = McpPeopleRepository(
      _Client({'get_travel_times': <Object?>[]}),
      writes: queue,
    );
    final home = await people.createLocation(
      const Location(id: '', name: 'Home'),
    );
    final work = await people.createLocation(
      const Location(id: '', name: 'Work'),
    );

    await people.createTravelTime(
      TravelTime(
        id: '',
        fromId: home.id,
        toId: work.id,
        times: const [TravelMode(modeId: 'walk', minutes: 20)],
      ),
    );
    await pumpEventQueue();

    expect((await people.travelTimes()).single.fromId, home.id);
    offline = false;
    await queue.retryNow();
    expect(
      calls
          .where((c) => !c.tool.startsWith('get'))
          .map((c) => c.tool)
          .toList()
          .reversed
          .take(3)
          .toList()
          .reversed,
      ['create_location', 'create_location', 'create_travel_time'],
    );
  });
}
