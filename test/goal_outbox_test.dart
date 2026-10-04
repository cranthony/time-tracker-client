import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/pending_goal_save.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

/// A server that can refuse saves, or lose its answers.
class FlakyGoals extends InMemoryGoalsRepository {
  FlakyGoals() : super([const Goal(id: 'cook', name: 'Cooking')]);

  /// Thrown instead of saving.
  Object? failWith;

  /// Saves, then fails as if the answer never came.
  bool loseResponses = false;

  /// What's been asked, in order.
  final calls = <String>[];

  @override
  Future<GoalList> goals() {
    calls.add('goals');
    return super.goals();
  }

  @override
  Future<String> createGoal(Map<String, Object?> fields) async {
    calls.add('create ${fields['name']}');
    if (failWith case final error?) throw error;
    final id = await super.createGoal(fields);
    if (loseResponses) throw http.ClientException('connection reset');
    return id;
  }

  @override
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes) async {
    calls.add('update ${goal.id} $changes');
    if (failWith case final error?) throw error;
    await super.updateGoal(goal, changes);
    if (loseResponses) throw http.ClientException('connection reset');
  }
}

void main() {
  late FlakyGoals server;
  late InMemoryOutboxStore<PendingGoalSave> store;

  GoalOutbox outbox() => GoalOutbox(store: store, repository: server);

  /// Lets [box] send what it can.
  Future<void> settled(GoalOutbox box) async {
    for (var i = 0; i < 100 && box.busy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // And keep what it ends with.
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    server = FlakyGoals();
    store = InMemoryOutboxStore();
  });

  test('sends saves one at a time, in order, then says it is done', () async {
    final box = outbox();
    final events = <GoalSaveEvent>[];
    box.events.listen(events.add);
    await box.start();

    final shownAs = box.create({'name': 'Running', 'parent_id': null});
    box.update('cook', {'priority': 2});
    expect(box.saves.map((s) => s.goalId), [shownAs, 'cook']);
    await settled(box);

    expect(server.calls, ['create Running', 'update cook {priority: 2}']);
    expect(events, [
      isA<GoalSaved>()
          .having((e) => e.save.goalId, 'goalId', shownAs)
          .having((e) => e.createdId, 'createdId', 'g1'),
      isA<GoalSaved>().having((e) => e.save.goalId, 'goalId', 'cook'),
      isA<GoalSavesDone>(),
    ]);
    expect(box.saves, isEmpty);
    expect(store.items, isEmpty);
  });

  test('a save to a goal with one waiting joins it, to be sent as one', () {
    final box = outbox();
    box.update('cook', {'name': 'Cooking at home', 'priority': 1});
    box.update('cook', {'priority': 2});
    expect(box.saves.single.changes, {
      'name': 'Cooking at home',
      'priority': 2,
    });

    // As when what failed is edited: these stand in for them.
    box.update('cook', {'name': 'Home cooking'}, replace: true);
    expect(box.saves.single.changes, {'name': 'Home cooking'});
  });

  test('a save the server refuses is kept, and waits to be retried', () async {
    server.failWith = McpException('No room for it.');
    final box = outbox();
    final events = <GoalSaveEvent>[];
    box.events.listen(events.add);
    await box.start();

    final shownAs = box.create({'name': 'Running', 'parent_id': null});
    await settled(box);
    final failed = box.saves.single;
    expect(failed.error, 'No room for it.');
    expect(failed.uncertain, isFalse);
    expect(events.whereType<GoalSaveFailed>(), hasLength(1));
    expect(store.items.single.error, 'No room for it.');

    // Not by starting again: it would only be refused again.
    server.failWith = null;
    await box.start();
    await settled(box);
    expect(server.calls, ['create Running']);

    box.retry(shownAs);
    await settled(box);
    expect(server.calls, ['create Running', 'create Running']);
    expect(box.saves, isEmpty);
  });

  test('a later save to a goal whose save failed sends both, as one', () async {
    server.failWith = McpException('Try later.');
    final box = outbox();
    await box.start();
    box.update('cook', {'name': 'Cooking at home'});
    await settled(box);

    server.failWith = null;
    box.update('cook', {'priority': 2});
    await settled(box);
    expect(
      server.calls.last,
      'update cook {name: Cooking at home, priority: 2}',
    );
    expect(box.saves, isEmpty);
  });

  test('kept across restarts; one that got no answer is tried again, '
      "without making the goal twice", () async {
    server.loseResponses = true;
    final before = outbox();
    await before.start();
    before.create({'name': 'Running', 'parent_id': null});
    await settled(before);
    expect(before.saves.single.error, 'No connection to the server');
    expect(before.saves.single.uncertain, isTrue);

    // The app closes, and opens again.
    server.loseResponses = false;
    server.calls.clear();
    final after = outbox();
    final events = <GoalSaveEvent>[];
    after.events.listen(events.add);
    await after.start();
    await settled(after);

    expect(server.calls, ['goals']);
    expect(
      (await server.goals()).goals.where((g) => g.name == 'Running'),
      hasLength(1),
    );
    expect(
      events.first,
      isA<GoalSaved>().having((e) => e.createdId, 'createdId', 'g1'),
    );
    expect(after.saves, isEmpty);
  });

  test('a new goal that failed without an answer is let go of once the '
      'goals show it was made', () async {
    server.loseResponses = true;
    final box = outbox();
    await box.start();
    box.create({'name': 'Running', 'parent_id': null});
    await settled(box);
    // Refused: kept, though there's one of that name.
    server.loseResponses = false;
    server.failWith = McpException('Running is already a goal.');
    box.create({'name': 'Cooking', 'parent_id': null});
    await settled(box);
    expect(box.saves, hasLength(2));

    box.reconcile(await server.goals());
    expect(box.saves.single.changes['name'], 'Cooking');
  });

  test('discards what waits for a goal', () async {
    server.failWith = McpException('No.');
    final box = outbox();
    await box.start();
    box.update('cook', {'priority': 2});
    await settled(box);

    box.discard('cook');
    expect(box.saves, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(store.items, isEmpty);
  });

  test('PrefsOutboxStore.goals round-trips', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = PrefsOutboxStore.goals();
    const save = PendingGoalSave(
      id: 'x',
      goalId: 'cook',
      isNew: false,
      changes: {
        'measure': {'kind': 'duration', 'target_min': 600},
        'note': null,
      },
      error: 'offline',
      uncertain: true,
    );
    await prefs.save([save]);

    final loaded = (await PrefsOutboxStore.goals().load()).single;
    expect(loaded.toJson(), save.toJson());

    await prefs.save([]);
    expect(await prefs.load(), isEmpty);
  });
}
