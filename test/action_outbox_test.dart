import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/outbox/outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/pending_action_save.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

/// A server that can refuse saves, or lose its answers.
class FlakyActions extends InMemoryActionsRepository {
  FlakyActions() : super([const PlanAction(id: 'cook', name: 'Cooking')]);

  /// Thrown instead of saving.
  Object? failWith;

  /// Saves, then fails as if the answer never came.
  bool loseResponses = false;

  /// What's been asked, in order.
  final calls = <String>[];

  @override
  Future<ActionList> actions() {
    calls.add('actions');
    return super.actions();
  }

  @override
  Future<String> createAction(Map<String, Object?> fields) async {
    calls.add('create ${fields['name']}');
    if (failWith case final error?) throw error;
    final id = await super.createAction(fields);
    if (loseResponses) throw http.ClientException('connection reset');
    return id;
  }

  @override
  Future<void> updateAction(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    calls.add('update ${action.id} $changes');
    if (failWith case final error?) throw error;
    await super.updateAction(action, changes);
    if (loseResponses) throw http.ClientException('connection reset');
  }
}

void main() {
  late FlakyActions server;
  late InMemoryOutboxStore<PendingActionSave> store;
  late DateTime now;
  late List<ActionOutbox> boxes;

  ActionOutbox outbox() {
    final box = ActionOutbox(
      store: store,
      repository: server,
      clock: () => now,
    );
    boxes.add(box);
    return box;
  }

  /// Lets [box] send what it can.
  Future<void> settled(ActionOutbox box) async {
    for (var i = 0; i < 100 && box.busy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // And keep what it ends with.
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    server = FlakyActions();
    store = InMemoryOutboxStore();
    now = DateTime.utc(2026, 10, 4, 9);
    boxes = [];
  });

  // So none tries again by itself, later, during another test.
  tearDown(() {
    for (final box in boxes) {
      box.dispose();
    }
  });

  test('sends saves one at a time, in order, then wants the actions '
      'fetched, once', () async {
    final box = outbox();
    final wanted = <bool>[];
    box.addListener(() => wanted.add(box.wantsFetch));
    box.start();

    final shownAs = box.create({'name': 'Running', 'parent_id': null});
    box.update('cook', {'priority': 2});
    expect(box.saves.map((s) => s.actionId), [shownAs, 'cook']);
    await settled(box);

    expect(server.calls, ['create Running', 'update cook {priority: 2}']);
    expect(box.saves, isEmpty);
    expect(store.items, isEmpty);
    // Kept, with the id the server gave the new action, until fetched.
    expect(box.justSaved.map((s) => (s.item.actionId, s.result)), [
      (shownAs, 'g1'),
      ('cook', null),
    ]);
    // Not while any were still to be sent.
    expect(wanted.last, isTrue);
    expect(wanted.where((w) => w), hasLength(1));

    final fetched = box.fetching();
    expect(box.wantsFetch, isFalse);
    fetched();
    expect(box.justSaved, isEmpty);
  });

  test('what was saved while the actions were fetched is kept after', () async {
    final box = outbox();
    box.update('cook', {'priority': 2});
    await box.flush();
    final fetched = box.fetching();
    box.update('cook', {'priority': 3});
    await box.flush();
    expect(box.wantsFetch, isTrue);

    fetched();
    expect(box.justSaved.single.item.changes, {'priority': 3});
    expect(box.wantsFetch, isTrue);
  });

  test("a save gone from the store was saved by another sender: it's "
      'kept until fetched, without a result', () async {
    final app = outbox();
    final shownAs = app.create({'name': 'Running', 'parent_id': null});
    await app.refresh();

    await outbox().flush(ignoreBackoff: true);
    expect(app.justSaved, isEmpty);
    await app.refresh();
    expect(app.saves, isEmpty);
    expect(app.justSaved.map((s) => (s.item.actionId, s.result)), [
      (shownAs, null),
    ]);
    expect(app.wantsFetch, isTrue);
  });

  test('a save to an action with one waiting joins it, to be sent as one', () {
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
    final events = <ActionSaveEvent>[];
    box.events.listen(events.add);
    box.start();

    final shownAs = box.create({'name': 'Running', 'parent_id': null});
    await settled(box);
    final failed = box.saves.single;
    expect(failed.lastError, 'No room for it.');
    expect(failed.refused, isTrue);
    expect(events.whereType<ActionSaveFailed>(), hasLength(1));
    expect(store.items.single.lastError, 'No room for it.');

    // Not by starting again: it would only be refused again.
    server.failWith = null;
    box.start();
    await settled(box);
    expect(server.calls, ['create Running']);

    box.retry(shownAs);
    await settled(box);
    expect(server.calls, ['create Running', 'create Running']);
    expect(box.saves, isEmpty);
  });

  test(
    'a later save to an action whose save failed sends both, as one',
    () async {
      server.failWith = McpException('Try later.');
      final box = outbox();
      box.start();
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
    },
  );

  test('kept across restarts; one that got no answer is tried again, '
      "without making the action twice", () async {
    server.loseResponses = true;
    final before = outbox();
    before.start();
    before.create({'name': 'Running', 'parent_id': null});
    await settled(before);
    expect(before.saves.single.lastError, 'No connection to the server');
    expect(before.saves.single.attempts, 1);
    expect(before.saves.single.refused, isFalse);

    // The app closes, and opens again, once it's time to try again.
    before.stop();
    now = now.add(Outbox.backoff(1));
    server.loseResponses = false;
    server.calls.clear();
    final after = outbox();
    after.start();
    await after.flush();

    expect(server.calls, ['actions']);
    expect(
      (await server.actions()).actions.where((g) => g.name == 'Running'),
      hasLength(1),
    );
    expect(after.justSaved.single.result, 'g1');
    expect(after.saves, isEmpty);
  });

  test('a new action that failed without an answer is let go of once the '
      'actions show it was made', () async {
    server.loseResponses = true;
    final box = outbox();
    box.start();
    box.create({'name': 'Running', 'parent_id': null});
    await settled(box);
    // Refused: kept, though there's one of that name.
    server.loseResponses = false;
    server.failWith = McpException('Running is already an action.');
    box.create({'name': 'Cooking', 'parent_id': null});
    await settled(box);
    expect(box.saves, hasLength(2));

    box.reconcile(await server.actions());
    expect(box.saves.single.changes['name'], 'Cooking');
  });

  test('one that fails without an answer is tried again by itself, after '
      'a while', () async {
    server.failWith = http.ClientException('connection reset');
    final box = outbox();
    box.create({'name': 'Running', 'parent_id': null});
    await box.flush();
    final failed = box.saves.single;
    expect(failed.attempts, 1);
    expect(failed.nextAttemptAt, now.add(Outbox.backoff(1)));

    server.failWith = null;
    await box.flush();
    expect(server.calls, ['create Running']);

    now = failed.nextAttemptAt!;
    final result = await box.flush();
    // It may have been made the first time, so that's checked first.
    expect(server.calls, ['create Running', 'actions', 'create Running']);
    expect(result.remaining, 0);
    expect(box.saves, isEmpty);
  });

  test('waits to sign in, then sends when retried', () async {
    server.failWith = SignInRequiredException();
    final box = outbox();
    box.update('cook', {'priority': 2});
    final result = await box.flush();
    expect(result.needsSignIn, isTrue);
    expect(box.needsSignIn, isTrue);
    expect(box.saves.single.lastError, 'Sign in to save');

    server.failWith = null;
    await box.retryNow();
    expect(box.needsSignIn, isFalse);
    expect(box.saves, isEmpty);
    expect((await server.actions()).actions.single.priority, 2);
  });

  test('the background task sends what the app kept', () async {
    final app = outbox();
    final shownAs = app.create({'name': 'Running', 'parent_id': null});
    app.update('cook', {'priority': 2});
    await app.refresh();
    expect(store.items.map((s) => s.actionId), [shownAs, 'cook']);

    // Its own outbox, as the app is in the background.
    final result = await outbox().flush(ignoreBackoff: true);
    expect(result.remaining, 0);
    expect(server.calls, ['create Running', 'update cook {priority: 2}']);

    await app.refresh();
    expect(app.saves, isEmpty);
  });

  test('leaves a save alone while another sender has it in flight, until '
      'it seems to have stopped', () async {
    store.items = [
      PendingActionSave(
        id: 'a',
        actionId: 'unsaved-a',
        isNew: true,
        changes: const {'name': 'Running', 'parent_id': null},
        sendingSince: now,
      ),
    ];
    final box = outbox();
    await box.refresh();
    expect(box.isSending(box.saves.single), isTrue);
    await box.flush(ignoreBackoff: true);
    expect(server.calls, isEmpty);

    // It may have made the action before it stopped, so that's checked.
    now = now.add(Outbox.inFlightTimeout);
    await box.flush();
    expect(server.calls, ['actions', 'create Running']);
    expect(box.saves, isEmpty);
  });

  test('discards what waits for an action', () async {
    server.failWith = McpException('No.');
    final box = outbox();
    box.start();
    box.update('cook', {'priority': 2});
    await settled(box);

    box.discard('cook');
    expect(box.saves, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(store.items, isEmpty);
  });

  test('PrefsOutboxStore.actions round-trips', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = PrefsOutboxStore.actions();
    final save = PendingActionSave(
      id: 'x',
      actionId: 'cook',
      isNew: false,
      changes: {
        'measure': {'kind': 'duration', 'target_min': 600},
        'note': null,
      },
      attempts: 2,
      lastError: 'offline',
      nextAttemptAt: DateTime.utc(2026, 10, 4, 9, 0, 20),
      sendingSince: DateTime.utc(2026, 10, 4, 9),
      refused: true,
    );
    await prefs.save([save]);

    final loaded = (await PrefsOutboxStore.actions().load()).single;
    expect(loaded.toJson(), save.toJson());

    await prefs.save([]);
    expect(await prefs.load(), isEmpty);
  });
}
