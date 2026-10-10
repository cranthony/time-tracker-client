import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

void main() {
  test('an action renamed shows its new name wherever the actions are '
      'shown: as soon as the save waits, and once it is made, though they '
      "haven't been fetched again", () async {
    final repo = InMemoryActionsRepository([
      const PlanAction(id: 'idea', name: 'Idea', status: 'proposed'),
    ]);
    final outbox = ActionOutbox(store: InMemoryOutboxStore(), repository: repo);
    addTearDown(outbox.dispose);
    final memory = PlanMemory()
      ..actions = await repo.actions()
      ..useActionOutbox(outbox);
    var told = 0;
    memory.addListener(() => told++);
    String? named() => memory.shownActions!.actions.single.name;
    expect(named(), 'Idea');

    outbox.update('idea', {'name': 'Better idea'}, group: false);
    await pumpEventQueue();
    expect(named(), 'Better idea');
    expect(told, greaterThan(0));
    // As the server last listed them, still.
    expect(memory.actions!.actions.single.name, 'Idea');

    await outbox.flush(ignoreBackoff: true);
    expect(outbox.saves, isEmpty);
    expect(named(), 'Better idea');
    expect((await repo.actions()).actions.single.name, 'Better idea');
  });
}
