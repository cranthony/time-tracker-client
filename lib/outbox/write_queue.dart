import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../models/goal.dart';
import '../models/habit.dart';
import '../models/person.dart';
import '../models/trait.dart';
import '../models/travel_time.dart';
import '../services/mcp_client.dart';
import '../services/server_errors.dart';
import 'outbox.dart';
import 'pending_write.dart';

export 'pending_write.dart';

/// A kind of item the app writes through the [WriteQueue]: the tools that
/// make, change and delete one, and how they name it. Everything else --
/// keeping writes, sending them once, in order, merging and conflicts --
/// is the queue's, the same for every kind.
class WriteKind {
  const WriteKind({
    required this.name,
    required this.noun,
    required this.argument,
    required this.createTool,
    required this.updateTool,
    this.deleteTool,
    this.deleteArgument,
    required this.writable,
    this.single = false,
    this.itemIn,
    this.updateCalls,
    this.updateArguments,
    this.nameOf,
    this.batchTool,
  });

  /// The tool that makes, changes and deletes several at once, checked
  /// whole ([WriteQueue.batch]): taking `creates` (each as [createTool]
  /// takes one), `updates` (each `{[argument]: {id, ..., version},
  /// clear_fields}`) and `deletes` (each `{[deleteArgument]: id,
  /// if_version}`), and giving those it made or changed, as
  /// `"<argument>s"`, and the ids it deleted, as `deleted_ids`.
  final String? batchTool;

  /// For a kind whose update takes its fields beside its id rather than
  /// under [argument] (a note's): the update's arguments, from the item's
  /// [id], its [changes] (a null clearing a field) and the [version] last
  /// seen.
  final Map<String, Object?> Function(
    String id,
    Map<String, Object?> changes,
    int? version,
  )?
  updateArguments;

  /// What the user knows [item] by, when it isn't its name (a note's
  /// description).
  final String? Function(Map<String, Object?> item)? nameOf;

  /// The item, the [WriteKind] [id], in what a create or update gave --
  /// for a tool that gives more than the item itself (an action's, with
  /// those it moved); null if it's not there. Without it, the item is
  /// what the tool gave, or that under [argument].
  final Map<String, Object?>? Function(Map<String, Object?> result, String id)?
  itemIn;

  /// For a [single] kind whose tool sets one part at a time (a priority's
  /// color): the arguments of each call an update's changes make, in
  /// order, in place of [argument] wrapping them all.
  final List<Map<String, Object?>> Function(Map<String, Object?> changes)?
  updateCalls;

  /// Whether there's just the one of it -- settings, say -- set whole,
  /// with neither id nor version: its writes are all updates to [one].
  final bool single;

  /// The id the one of a [single] kind has in the queue.
  static const one = 'one';

  /// What of [item], as the server lists one, a create takes: without
  /// what the server works out (a location's path, say).
  final Map<String, Object?> Function(Map<String, Object?> item) writable;

  /// Its name in the queue: what a [PendingWrite.kind] says.
  final String name;

  /// What one's called, to the user: "location".
  final String noun;

  /// What the tools call one, as an argument (`{"location": {...}}`) and
  /// in what a create gives back.
  final String argument;
  final String createTool;
  final String updateTool;
  final String? deleteTool;

  /// What a delete calls its id: "location_id".
  final String? deleteArgument;

  /// [item], as the user knows it: its name.
  String label(Map<String, Object?>? item) => switch (item == null
      ? null
      : nameOf != null
      ? nameOf!(item)
      : item['name']) {
    final String name when name.trim().isNotEmpty && !single =>
      '$noun “${name.trim()}”',
    _ => noun,
  };

  static const person = WriteKind(
    name: 'person',
    noun: 'person',
    argument: 'person',
    createTool: 'create_person',
    updateTool: 'update_person',
    writable: _person,
    updateArguments: _personUpdate,
  );

  static Map<String, Object?> _person(Map<String, Object?> item) =>
      Person.fromJson({'id': '', ...item}).toJson();

  /// A person's update: their trait facts' summaries (`facts`) beside
  /// them, the rest under "person".
  static Map<String, Object?> _personUpdate(
    String id,
    Map<String, Object?> changes,
    int? version,
  ) => personUpdate(id, changes, version: version);

  static Map<String, Object?> _location(Map<String, Object?> item) =>
      Location.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _circle(Map<String, Object?> item) =>
      Circle.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _locationGroup(Map<String, Object?> item) =>
      LocationGroup.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _travelTime(Map<String, Object?> item) =>
      TravelTime.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _habit(Map<String, Object?> item) =>
      Habit.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _trait(Map<String, Object?> item) =>
      Trait.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _same(Map<String, Object?> item) => item;

  static Map<String, Object?> _action(Map<String, Object?> item) => {
    for (final key in actionFields)
      if (item.containsKey(key)) key: item[key],
  };

  static Map<String, Object?> _actionGroup(Map<String, Object?> item) => {
    for (final key in actionGroupFields)
      if (item.containsKey(key)) key: item[key],
  };

  /// What an action's create and update take.
  static const actionFields = [
    'id',
    'group_id',
    'name',
    'status',
    'background_color',
    'priority',
    'note',
    'commute',
  ];

  /// What an action group's create and update take.
  static const actionGroupFields = [
    'id',
    'group_id',
    'name',
    'background_color',
    'priority',
    'note',
  ];

  /// The one listed in [result]'s "changed" -- what an action's or
  /// group's write changed, it first -- with [id].
  static Map<String, Object?>? _changed(
    Map<String, Object?> result,
    String id,
  ) => switch (result['changed']) {
    final List changed =>
      changed
          .whereType<Map>()
          .where((i) => i['id'] == id)
          .firstOrNull
          ?.cast<String, Object?>(),
    _ => null,
  };

  static const action = WriteKind(
    name: 'action',
    noun: 'action',
    argument: 'action',
    createTool: 'create_action',
    updateTool: 'update_action',
    writable: _action,
    itemIn: _changed,
  );

  static const actionGroup = WriteKind(
    name: 'action_group',
    noun: 'action group',
    argument: 'group',
    createTool: 'create_action_group',
    updateTool: 'update_action_group',
    deleteTool: 'delete_action_group',
    deleteArgument: 'group_id',
    writable: _actionGroup,
    itemIn: _changed,
  );

  /// Each priority's color, as one item: {"0": "#rrggbb", ...}, a key a
  /// priority. Each color changed is set by a call of its own.
  static const priorityColors = WriteKind(
    name: 'priority_colors',
    noun: 'priority colors',
    argument: 'colors',
    createTool: 'update_priority_color',
    updateTool: 'update_priority_color',
    writable: _same,
    single: true,
    itemIn: _colorsIn,
    updateCalls: _colorCalls,
  );

  /// The priority colors in [result], `update_priority_color`'s, as the
  /// one item they make.
  static Map<String, Object?>? _colorsIn(
    Map<String, Object?> result,
    String id,
  ) => switch (result['colors']) {
    final List colors => priorityColorsItem(colors),
    _ => null,
  };

  /// `get_priority_colors`'s [colors] as the one item they make.
  static Map<String, Object?> priorityColorsItem(List colors) => {
    for (final c in colors.whereType<Map>())
      if (c['priority'] case final int p) '$p': c['color'],
    'id': one,
  };

  static List<Map<String, Object?>> _colorCalls(Map<String, Object?> changes) =>
      [
        for (final MapEntry(:key, :value) in changes.entries)
          if (int.tryParse(key) case final priority? when value is String)
            {'priority': priority, 'color': value},
      ];

  static const location = WriteKind(
    name: 'location',
    noun: 'location',
    argument: 'location',
    createTool: 'create_location',
    updateTool: 'update_location',
    deleteTool: 'delete_location',
    deleteArgument: 'location_id',
    writable: _location,
  );

  static const circle = WriteKind(
    name: 'circle',
    noun: 'circle',
    argument: 'circle',
    createTool: 'create_circle',
    updateTool: 'update_circle',
    deleteTool: 'delete_circle',
    deleteArgument: 'circle_id',
    writable: _circle,
  );

  static const locationGroup = WriteKind(
    name: 'location_group',
    noun: 'location group',
    argument: 'group',
    createTool: 'create_location_group',
    updateTool: 'update_location_group',
    deleteTool: 'delete_location_group',
    deleteArgument: 'group_id',
    writable: _locationGroup,
  );

  static const travelTime = WriteKind(
    name: 'travel_time',
    noun: 'travel time',
    argument: 'travel_time',
    createTool: 'create_travel_time',
    updateTool: 'update_travel_time',
    deleteTool: 'delete_travel_time',
    deleteArgument: 'travel_time_id',
    writable: _travelTime,
  );

  static const habit = WriteKind(
    name: 'habit',
    noun: 'habit',
    argument: 'habit',
    createTool: 'create_habit',
    updateTool: 'update_habit',
    writable: _habit,
  );

  /// A goal: made, changed and deleted one at a time -- or, a change to
  /// several (closing a goal and its sub-goals, say), all at once, by
  /// `update_goals` ([WriteQueue.batch]), so the server's rules hold for
  /// the result rather than each step.
  static const goal = WriteKind(
    name: 'goal',
    noun: 'goal',
    argument: 'goal',
    createTool: 'create_goal',
    updateTool: 'update_goal',
    deleteTool: 'delete_goal',
    deleteArgument: 'goal_id',
    writable: _goal,
    nameOf: _goalTitle,
    batchTool: 'update_goals',
  );

  static Map<String, Object?> _goal(Map<String, Object?> item) =>
      Goal.fromJson({'id': '', ...item}).toJson()..remove('version');

  static String? _goalTitle(Map<String, Object?> item) =>
      item['title'] as String?;

  static const trait = WriteKind(
    name: 'trait',
    noun: 'trait',
    argument: 'trait',
    createTool: 'create_trait',
    updateTool: 'update_trait',
    writable: _trait,
  );

  static const scoringDefaults = WriteKind(
    name: 'scoring_defaults',
    noun: 'scoring defaults',
    argument: 'defaults',
    createTool: 'set_scoring_defaults',
    updateTool: 'set_scoring_defaults',
    writable: _same,
    single: true,
  );

  /// A time note: a timestamp and what it marks. Edited by `edit_note`,
  /// whose description is cleared by an empty one.
  static const note = WriteKind(
    name: 'note',
    noun: 'note',
    argument: 'noted_time',
    createTool: 'note',
    updateTool: 'edit_note',
    deleteTool: 'delete_note',
    deleteArgument: 'note_id',
    writable: _note,
    updateArguments: _noteEdit,
    nameOf: _noteName,
  );

  static Map<String, Object?> _note(Map<String, Object?> item) => {
    for (final key in ['timestamp', 'description'])
      if (item[key] != null) key: item[key],
  };

  static Map<String, Object?> _noteEdit(
    String id,
    Map<String, Object?> changes,
    int? version,
  ) => {
    'note_id': id,
    if (changes['timestamp'] case final String timestamp)
      'timestamp': timestamp,
    if (changes.containsKey('description'))
      'description': changes['description'] ?? '',
    'version': ?version,
  };

  static String? _noteName(Map<String, Object?> item) =>
      item['description'] as String?;

  /// Every kind, by name.
  static final all = {
    for (final k in [
      person,
      location,
      circle,
      locationGroup,
      travelTime,
      habit,
      goal,
      trait,
      scoringDefaults,
      action,
      actionGroup,
      priorityColors,
      note,
    ])
      k.name: k,
  };
}

/// How a write the server refused as changed elsewhere since
/// ([PendingWrite.conflicted]) is resolved, for the dialog that asks the
/// user how (showWriteConflictDialog): the [WriteQueue]'s writes, and the
/// event outbox's.
abstract interface class ConflictResolver {
  /// What [write] writes, as one would name it: “location “Home””.
  String label(PendingWrite write);

  /// What one's called: "location".
  String noun(PendingWrite write);

  /// Whether [write]'s item, deleted elsewhere since, can be put back.
  bool canRestore(PendingWrite write);

  /// Sends [write] again with [changes], made to the item as it is now.
  Future<void> resolve(PendingWrite write, Map<String, Object?> changes);

  /// Sends [write] as it is over what changed elsewhere.
  Future<void> overwrite(PendingWrite write);

  /// Puts [write]'s item back, deleted elsewhere since, with its changes.
  Future<void> restore(PendingWrite write);

  /// Drops [write]. False if it's being sent.
  Future<bool> drop(PendingWrite write);
}

/// Sends a write to the server: [tool], with [arguments]; gives what the
/// tool gives.
typedef WriteCall = Future<Object?> Function(
  String tool,
  Map<String, Object?> arguments,
);

/// Every write the app makes to the server of the kinds it has
/// ([WriteKind.all]), kept on the device until it's saved: the app never
/// waits on the server to write, so it works the same offline. Each write
/// is retried until it's saved, and made once however often it's sent:
/// a new item names itself by its id, and a change says the version it
/// was made to, so the server gives back what's made already rather than
/// making it again. Nothing is dropped unless the user drops it ([drop]).
///
/// * A new item gets its id from the app ([create]), so it can be named
///   -- by an event, say -- before the server has it. A write naming an
///   item waits ([waits]) for the write making it, as does a later write
///   to the same item.
/// * A change to an item with a write waiting joins it ([update]): into
///   a new item's fields, or an update's changes. Deleting an item the
///   server doesn't have yet just drops its writes ([delete]).
/// * Each change says what version of the item it was made to ([base]).
///   One the server finds changed since is merged, if the change and
///   what changed elsewhere touch different fields; if they touch the
///   same, it waits, [PendingWrite.conflicted], for the user to resolve.
/// * What's shown of each kind is what the server gave, with the writes
///   waiting made to it ([shown]) -- and those just saved, till a fetch
///   started after them is in.
class WriteQueue extends Outbox<PendingWrite, Map<String, Object?>?>
    implements ConflictResolver {
  WriteQueue({
    required super.store,
    required this._call,
    super.clock,
    super.sender,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Writes through [client].
  static WriteCall callOn(McpClient client) => client.callTool;

  final WriteCall _call;
  final Random _random;

  /// Each kind's items as the app last saw them from the server, by id:
  /// what a change is made to.
  final _known = <String, Map<String, Map<String, Object?>>>{};

  /// Conflicts found sending, by write, till they're kept (see [failed]).
  final _conflicts =
      <String, List<({String? id, Map<String, Object?>? current})>>{};

  static const _idAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// A new id: 16 letters and digits, so no two clash.
  String _newId() => String.fromCharCodes([
    for (var i = 0; i < 16; i++)
      _idAlphabet.codeUnitAt(_random.nextInt(_idAlphabet.length)),
  ]);

  static WriteKind kindOf(PendingWrite write) => WriteKind.all[write.kind]!;

  @override
  String noun(PendingWrite write) => kindOf(write).noun;

  @override
  bool canRestore(PendingWrite write) => true;

  /// [write]'s item, as one would name it: “location “Home””.
  @override
  String label(PendingWrite write) {
    final kind = kindOf(write);
    if (write.op == WriteOp.batch) {
      final n = _batchIds(write).length;
      return n == 1 ? '1 ${kind.noun}' : '$n ${kind.noun}s';
    }
    return kind.label({
      ...?write.base,
      ...?_known[kind.name]?[write.itemId],
      ...write.changes,
    });
  }

  /// The ids of items being made, not saved yet: what a write naming one
  /// -- in this queue or another -- waits for.
  Set<String> get making => {
    for (final w in items)
      if (w.op == WriteOp.create)
        w.itemId
      else if (w.op == WriteOp.batch)
        for (final c in w.parts('creates')) ?c['id'] as String?,
  };

  /// The ids of the items a [WriteOp.batch] write makes, changes or
  /// deletes.
  static Set<String> _batchIds(PendingWrite write) => {
    for (final which in const ['creates', 'updates', 'deletes'])
      for (final p in write.parts(which)) ?p['id'] as String?,
  };

  /// A new id, as [create] gives one: for a new item in a [batch].
  String newId() => _newId();

  // -- Queueing ----------------------------------------------------------

  /// Queues making a [kind] from [fields], keyed as its create tool takes
  /// them; gives the id it has from now on.
  String create(WriteKind kind, Map<String, Object?> fields) {
    final id = _newId();
    _queue(
      (writes) => [
        ...writes,
        PendingWrite(
          id: _newId(),
          kind: kind.name,
          op: WriteOp.create,
          itemId: id,
          changes: {
            for (final MapEntry(:key, :value) in fields.entries)
              if (key != 'id' && key != 'version' && value != null) key: value,
          },
        ),
      ],
    );
    return id;
  }

  /// [create], giving the new item as it's shown: [fields], with its id.
  Map<String, Object?> created(WriteKind kind, Map<String, Object?> fields) {
    final id = create(kind, fields);
    return item(kind, id) ??
        {
          for (final MapEntry(:key, :value) in fields.entries)
            if (key != 'version' && value != null) key: value,
          'id': id,
        };
  }

  /// Queues [changes] -- a null clears a field -- to the [kind] [id]: into
  /// a write to it still waiting, if there is one -- unless it's [ordered]:
  /// then as a write of its own, sent only after every write of [kind]
  /// queued before it, for one of several changes the server takes only
  /// in order (a goal closed after its sub-goals; see
  /// [PendingWrite.ordered]). Gives it as it's shown now, with them.
  Map<String, Object?> update(
    WriteKind kind,
    String id,
    Map<String, Object?> changes, {
    Map<String, Object?>? base,
    bool ordered = false,
  }) {
    _queue((writes) {
      // Not one tried: it may have been made, unheard, and sent again it's
      // answered as it was then -- what's joined to it lost. A write after
      // it, waiting for it, then.
      final i = ordered
          ? -1
          : writes.lastIndexWhere(
              (w) =>
                  w.kind == kind.name &&
                  w.itemId == id &&
                  w.op != WriteOp.delete &&
                  w.attempts == 0 &&
                  !isSending(w),
            );
      if (i < 0) {
        return [
          ...writes,
          PendingWrite(
            id: _newId(),
            kind: kind.name,
            op: WriteOp.update,
            itemId: id,
            changes: changes,
            base: _known[kind.name]?[id] ?? base,
            ordered: ordered,
          ),
        ];
      }
      final joined = writes[i];
      // A new item's fields lose what's cleared; an update's changes
      // keep it, as a clearing.
      final merged = <String, Object?>{...joined.changes, ...changes};
      if (joined.op == WriteOp.create) {
        merged.removeWhere((_, value) => value == null);
      }
      return [
        for (final (j, w) in writes.indexed)
          j == i ? w.rewritten(changes: merged) : w,
      ];
    });
    return item(kind, id) ?? {'id': id, ...changes};
  }

  /// Queues several changes to [kind]s as one write, made at once by its
  /// [WriteKind.batchTool]: the items [creates] makes (each with its id,
  /// from [newId]), the [updates] to others (each an id and its changes,
  /// a null clearing a field) and the ids [deletes] deletes. It's
  /// [PendingWrite.ordered]: sent after every write of [kind] queued
  /// before it, and those after it wait for it.
  void batch(
    WriteKind kind, {
    List<Map<String, Object?>> creates = const [],
    List<(String, Map<String, Object?>)> updates = const [],
    List<String> deletes = const [],
  }) {
    final known = _known[kind.name] ?? const {};
    _queue(
      (writes) => [
        ...writes,
        PendingWrite(
          id: _newId(),
          kind: kind.name,
          op: WriteOp.batch,
          itemId: 'batch:${_newId()}',
          ordered: true,
          changes: {
            if (creates.isNotEmpty)
              'creates': [
                for (final c in creates)
                  {
                    for (final MapEntry(:key, :value) in c.entries)
                      if (key != 'version' && value != null) key: value,
                  },
              ],
            if (updates.isNotEmpty)
              'updates': [
                for (final (id, changes) in updates)
                  {'id': id, 'changes': changes, 'base': ?known[id]},
              ],
            if (deletes.isNotEmpty)
              'deletes': [
                for (final id in deletes) {'id': id, 'base': ?known[id]},
              ],
          },
        ),
      ],
    );
  }

  /// Queues deleting the [kind] [id]. If the server doesn't have it yet,
  /// its writes are just dropped -- unless one's being sent, when it's
  /// deleted once that's saved. [ordered], it's sent only after every
  /// write of [kind] queued before it (see [update]).
  void delete(
    WriteKind kind,
    String id, {
    Map<String, Object?>? base,
    bool ordered = false,
  }) {
    _queue((writes) {
      // Its writes not tried yet: one tried may have been made, so a
      // deletion goes after it.
      bool its(PendingWrite w) =>
          w.kind == kind.name &&
          w.itemId == id &&
          w.attempts == 0 &&
          !isSending(w);
      final made = writes.any(
        (w) => its(w) && w.op == WriteOp.create && !w.refused,
      );
      final kept = [
        for (final w in writes)
          if (!its(w) || w.op == WriteOp.delete) w,
      ];
      if (made) return kept;
      if (kept.any((w) => its(w) && w.op == WriteOp.delete)) return kept;
      return [
        ...kept,
        PendingWrite(
          id: _newId(),
          kind: kind.name,
          op: WriteOp.delete,
          itemId: id,
          base: _known[kind.name]?[id] ?? base,
          ordered: ordered,
        ),
      ];
    });
  }

  void _queue(List<PendingWrite> Function(List<PendingWrite>) edit) {
    final kept = change(edit)
        .then((_) => schedule(immediately: true), onError: (_) {});
    queued = kept;
    unawaited(kept);
  }

  /// Done once what was last queued -- by [create], [update] or [delete]
  /// -- is kept, or failed to be.
  Future<void> queued = Future.value();

  /// Keeps [items], [kind]s as the server gave them, as what changes are
  /// made to -- for a kind whose page shows its writes waiting itself,
  /// rather than made to what [shown] gives.
  void know(WriteKind kind, List<Map<String, Object?>> items) =>
      _known[kind.name] = {
        for (final item in items)
          if (item['id'] case final String id) id: item,
      };

  /// Puts back [write], one [drop]ped: the user took that back.
  Future<void> putBack(PendingWrite write) async {
    await change((writes) => [...writes, write]);
    schedule(immediately: true);
  }

  /// Drops [write] without sending it -- and, for a new item, the writes
  /// to it waiting behind it, which can't be made without it. Only the
  /// user does this. False if it's being sent.
  @override
  Future<bool> drop(PendingWrite write) async {
    // A batch's part in conflict: dropped, and the rest sent -- or, with
    // nothing else in it, the whole write.
    if (_batchOf(write) case final batch?
        when write.op != WriteOp.batch && _batchIds(batch).length > 1) {
      if (isSending(batch)) return false;
      await _resendPart(write, (_) => null);
      return true;
    }
    if (_batchOf(write) case final batch? when write.op != WriteOp.batch) {
      write = batch;
    }
    if (isSending(write)) return false;
    var dropped = false;
    await change((writes) {
      // Made to what's shown, then to what's kept: as what's kept says.
      if (writes.any((w) => w.id == write.id && isSending(w))) {
        dropped = false;
        return writes;
      }
      dropped = true;
      final making = write.op == WriteOp.create;
      return [
        for (final w in writes)
          if (w.id != write.id &&
              !(making &&
                  w.kind == write.kind &&
                  w.itemId == write.itemId &&
                  !isSending(w)))
            w,
      ];
    });
    schedule();
    return dropped;
  }

  /// [write], [PendingWrite.conflicted], as the conflict dialog shows it:
  /// for a [WriteOp.batch] write, the part in conflict as a write of its
  /// own -- the item's changes or deletion, its base and the item as it
  /// is now -- with the batch's id, so what's done to it is done to that
  /// part ([resolve], [overwrite], [restore], [drop]).
  PendingWrite conflictView(PendingWrite write) {
    final id = write.conflictId;
    if (write.op != WriteOp.batch || id == null) return write;
    Map<String, Object?>? map(Object? value) =>
        (value as Map?)?.cast<String, Object?>();
    final update = write.parts('updates').where((p) => p['id'] == id);
    final delete = write.parts('deletes').where((p) => p['id'] == id);
    final part = update.firstOrNull ?? delete.firstOrNull;
    return PendingWrite(
      id: write.id,
      kind: write.kind,
      op: update.isNotEmpty ? WriteOp.update : WriteOp.delete,
      itemId: id,
      changes: map(part?['changes']) ?? const {},
      base: map(part?['base']),
      conflicted: write.conflicted,
      current: write.current,
      attempts: write.attempts,
      lastError: write.lastError,
      refused: write.refused,
      ordered: true,
    );
  }

  /// The [WriteOp.batch] write [view] is a part of ([conflictView]), if
  /// it's one.
  PendingWrite? _batchOf(PendingWrite view) =>
      items.where((w) => w.id == view.id && w.op == WriteOp.batch).firstOrNull;

  /// The batch [view]'s of, its part for [view] as [edit] makes it (gone,
  /// if null), sent again.
  Future<void> _resendPart(
    PendingWrite view,
    Map<String, Object?>? Function(Map<String, Object?> part) edit, {
    Map<String, Object?>? made,
  }) async {
    await replaceUnlessSending(view.id, (w) {
      var out = _withPart(w, 'updates', view.itemId, edit);
      out = _withPart(out, 'deletes', view.itemId, edit);
      if (made != null) {
        out = out.rewritten(
          changes: {
            ...out.changes,
            'creates': [...out.parts('creates'), made],
          },
        );
      }
      // The next item changed elsewhere, if there's one, to resolve
      // before it's sent again.
      if (out.moreConflicts case [final next, ...final rest]) {
        return out.rewritten(
          current: () => (next['current'] as Map?)?.cast<String, Object?>(),
          conflictId: () => next['id'] as String?,
          moreConflicts: rest,
        );
      }
      return out
          .rewritten(
            conflicted: false,
            current: () => null,
            conflictId: () => null,
            moreConflicts: const [],
          )
          .copyWith(refused: false, lastError: () => null);
    });
    schedule(immediately: true);
  }

  /// Sends [write], [PendingWrite.conflicted], as it is, over what changed
  /// elsewhere: the user chose theirs.
  @override
  Future<void> overwrite(PendingWrite write) async {
    // Made to the item as it is now: its version, so the server, which
    // takes no change to an item without one, makes it over what changed.
    if (_batchOf(write) != null) {
      return _resendPart(write, (p) => {...p, 'base': write.current});
    }
    await replaceUnlessSending(
      write.id,
      (w) => w
          .rewritten(
            base: () => w.current,
            conflicted: false,
            current: () => null,
          )
          .copyWith(refused: false, lastError: () => null),
    );
    schedule(immediately: true);
  }

  /// Sends [write] again, now -- its error, and any refusal, let go --
  /// with [changes] in place of its own, if they're given: then, if it was
  /// tried, as a write of its own, since one tried may have been made,
  /// unheard, and sent again by its id it would be answered as it was.
  /// False if it's being sent.
  Future<bool> resend(
    PendingWrite write, {
    Map<String, Object?>? changes,
  }) async {
    final resent = await replaceUnlessSending(write.id, (w) {
      final changed = changes == null
          ? w
          : w.attempts == 0
          ? w.rewritten(changes: changes)
          : PendingWrite.fromJson({
              ...w.rewritten(changes: changes).toJson(),
              'id': _newId(),
              'attempts': 0,
            });
      return changed.copyWith(
        refused: false,
        lastError: () => null,
        nextAttemptAt: () => null,
      );
    });
    schedule(immediately: true);
    return resent;
  }

  // -- Resolving ---------------------------------------------------------

  /// The fields [write], [PendingWrite.conflicted], changes that were
  /// changed elsewhere too, to something else: for the user to pick
  /// between.
  static List<String> clashes(PendingWrite write) {
    final current = write.current;
    if (current == null) return const [];
    final base = write.base ?? const {};
    return [
      for (final MapEntry(:key, :value) in write.changes.entries)
        if (!_same(current[key], base[key]) && !_same(current[key], value)) key,
    ];
  }

  /// The fields of [write]'s item changed elsewhere since it was made:
  /// for a deletion, to say what deleting it would throw away.
  static List<String> changedElsewhere(PendingWrite write) {
    final current = write.current ?? const {};
    final base = write.base ?? const {};
    return [
      for (final key in {...base.keys, ...current.keys})
        if (key != 'version' && !_same(current[key], base[key])) key,
    ];
  }

  /// Sends [write], [PendingWrite.conflicted], again with [changes] --
  /// the user's picks -- made to the item as it is now.
  @override
  Future<void> resolve(PendingWrite write, Map<String, Object?> changes) async {
    final current = write.current;
    if (_batchOf(write) != null) {
      return _resendPart(
        write,
        (p) => {...p, 'changes': changes, 'base': ?current},
      );
    }
    await replaceUnlessSending(
      write.id,
      (w) => w
          .rewritten(
            changes: changes,
            base: () => current,
            conflicted: false,
            current: () => null,
          )
          .copyWith(refused: false, lastError: () => null),
    );
    schedule(immediately: true);
  }

  /// Puts back [write]'s item, deleted elsewhere since: made again, with
  /// its id, as it was with [write]'s changes.
  @override
  Future<void> restore(PendingWrite write) async {
    final kind = kindOf(write);
    final fields = kind.writable({...?write.base, ...write.changes})
      ..remove('id')
      ..removeWhere((_, value) => value == null);
    if (_batchOf(write) != null) {
      // Made again, with its id, in the batch's creates.
      return _resendPart(
        write,
        (_) => null,
        made: {...fields, 'id': write.itemId},
      );
    }
    final made = PendingWrite(
      id: _newId(),
      kind: write.kind,
      op: WriteOp.create,
      itemId: write.itemId,
      changes: fields,
    );
    await change(
      (writes) => [
        for (final w in writes)
          if (w.id == write.id) made else w,
      ],
    );
    schedule(immediately: true);
  }

  // -- Showing -----------------------------------------------------------

  /// [fromServer], the [kind]s the server gave, with the writes waiting --
  /// and those just saved -- made to them. Kept as what changes are made
  /// to.
  List<Map<String, Object?>> shown(
    WriteKind kind,
    List<Map<String, Object?>> fromServer,
  ) {
    _known[kind.name] = {
      for (final item in fromServer)
        if (item['id'] case final String id) id: item,
    };
    return _applied(kind, fromServer);
  }

  /// The [kind] [id] as it's shown: as last seen, with the writes waiting
  /// made to it; null if it isn't (deleted, or never seen).
  Map<String, Object?>? item(WriteKind kind, String id) => _applied(kind, [
    ?_known[kind.name]?[id],
  ]).where((i) => i['id'] == id).firstOrNull;

  List<Map<String, Object?>> _applied(
    WriteKind kind,
    List<Map<String, Object?>> shown,
  ) {
    final out = [for (final i in shown) Map<String, Object?>.of(i)];
    final writes = [for (final s in justSaved) s.item, ...items];
    for (final w in writes) {
      if (w.kind != kind.name) continue;
      if (w.op == WriteOp.batch) {
        for (final c in w.parts('creates')) {
          if (!out.any((i) => i['id'] == c['id'])) out.add({...c});
        }
        for (final u in w.parts('updates')) {
          final at = out.indexWhere((i) => i['id'] == u['id']);
          if (at >= 0) {
            out[at] = {
              ...out[at],
              ...(u['changes'] as Map? ?? const {}).cast<String, Object?>(),
            };
          }
        }
        for (final d in w.parts('deletes')) {
          out.removeWhere((i) => i['id'] == d['id']);
        }
        continue;
      }
      final at = out.indexWhere((i) => i['id'] == w.itemId);
      switch (w.op) {
        case WriteOp.create when at < 0:
          out.add({...w.changes, 'id': w.itemId});
        case WriteOp.create || WriteOp.update when at >= 0:
          out[at] = {...out[at], ...w.changes};
        case WriteOp.delete when at >= 0:
          out.removeAt(at);
        case _:
      }
    }
    return out;
  }

  // -- Sending -----------------------------------------------------------

  @override
  bool waits(PendingWrite item) {
    final names = {item.itemId, ..._strings(item.changes)};
    for (final w in items) {
      if (w.id == item.id) return false;
      if (names.contains(w.itemId)) return true;
      if (item.ordered && w.kind == item.kind) return true;
    }
    return false;
  }

  /// Every string in [value], however deep: the ids it may name.
  static Iterable<String> _strings(Object? value) sync* {
    switch (value) {
      case final String s:
        yield s;
      case final Map map:
        for (final v in map.values) {
          yield* _strings(v);
        }
      case final List list:
        for (final v in list) {
          yield* _strings(v);
        }
    }
  }

  @override
  Future<Map<String, Object?>?> send(
    PendingWrite item, {
    required bool maybeSaved,
  }) async {
    var write = item;
    for (var merged = 0; ; merged++) {
      try {
        final result = await _send(write);
        await _saved(write, result);
        return result;
      } on McpException catch (e) {
        final conflict = e.conflict;
        if (conflict == null) rethrow;
        final current = conflict.current;
        if (write.op == WriteOp.batch) {
          // Each item's part changed elsewhere in other fields is made to
          // it as it is now; those changed in the same, each in turn, wait
          // for the user. Sent again once or twice, if all merge.
          final left = <({String? id, Map<String, Object?>? current})>[];
          for (final stale in e.conflicts) {
            final id = stale.id;
            if (id != null && _partMerges(write, id, stale.current)) {
              write = _withPart(
                write,
                'updates',
                id,
                (p) => {...p, 'base': stale.current},
              );
            } else {
              left.add(stale);
            }
          }
          // Kept as merged, still claimed as it's being sent.
          final rebased = write;
          await change(
            (writes) => [
              for (final w in writes)
                w.id == rebased.id
                    ? rebased.copyWith(
                        sendingSince: () => w.sendingSince,
                        sentBy: () => w.sentBy,
                      )
                    : w,
            ],
          );
          if (left.isEmpty && merged < 2) continue;
          _conflicts[write.id] = left.isEmpty ? e.conflicts : left;
          rethrow;
        }
        // Changed elsewhere in other fields, and only once or twice:
        // made to it as it is now.
        if (merged < 2 && _merges(write, current)) {
          write = write.rewritten(base: () => current);
          await change(
            (writes) => [for (final w in writes) w.id == write.id ? write : w],
          );
          continue;
        }
        _conflicts[write.id] = [(id: null, current: current)];
        rethrow;
      }
    }
  }

  /// Whether [write] can be made to the item as it is now, [current]:
  /// it's still there, and nothing [write] changes was changed elsewhere
  /// since its base -- or was changed the same.
  static bool _merges(PendingWrite write, Map<String, Object?>? current) {
    if (current == null || write.op == WriteOp.create) return false;
    // A deletion of what's changed since is asked about first.
    if (write.op == WriteOp.delete) return false;
    final base = write.base ?? const {};
    return write.changes.entries.every(
      (c) =>
          _same(current[c.key], base[c.key]) || _same(current[c.key], c.value),
    );
  }

  /// Whether [write], a [WriteOp.batch] write, can make its changes to
  /// [id] to it as it is now, [current] (as [_merges] says for one item).
  static bool _partMerges(
    PendingWrite write,
    String id,
    Map<String, Object?>? current,
  ) {
    final part = write.parts('updates').where((p) => p['id'] == id).firstOrNull;
    if (part == null || current == null) return false;
    final base = (part['base'] as Map? ?? const {}).cast<String, Object?>();
    final changes = (part['changes'] as Map? ?? const {})
        .cast<String, Object?>();
    return changes.entries.every(
      (c) =>
          _same(current[c.key], base[c.key]) || _same(current[c.key], c.value),
    );
  }

  /// [write], a [WriteOp.batch] write, with its [which] part for [id] as
  /// [edit] makes it -- or gone, if [edit] gives null.
  static PendingWrite _withPart(
    PendingWrite write,
    String which,
    String id,
    Map<String, Object?>? Function(Map<String, Object?> part) edit,
  ) => write.rewritten(
    changes: {
      ...write.changes,
      which: [
        for (final p in write.parts(which))
          if (p['id'] != id) p else ?edit(p),
      ],
    }..removeWhere((_, v) => v is List && v.isEmpty),
  );

  static int? _versionOf(Object? base) => switch (base) {
    {'version': final int version} => version,
    _ => null,
  };

  /// Whether [a] and [b] are the same value -- two times the same moment,
  /// however each is written.
  static bool same(Object? a, Object? b) {
    if (a is String && b is String && a != b && a.contains('T')) {
      final (x, y) = (DateTime.tryParse(a), DateTime.tryParse(b));
      if (x != null && y != null) return x.isAtSameMomentAs(y);
    }
    return jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));
  }

  static bool _same(Object? a, Object? b) => same(a, b);

  static Object? _canonical(Object? value) => switch (value) {
    final Map map => {
      for (final key in [...map.keys.map((k) => '$k')]..sort())
        key: _canonical(map[key]),
    },
    final List list => [for (final v in list) _canonical(v)],
    _ => value,
  };

  /// The version the [kind] [id] was last read at, for a write made to
  /// it without saying -- one an older version of the app kept, say: the
  /// server takes no change to an item with a version that doesn't say
  /// which it was made to.
  int? _knownVersion(WriteKind kind, Object? id) =>
      _versionOf(_known[kind.name]?[id]);

  Future<Map<String, Object?>?> _send(PendingWrite write) async {
    final kind = kindOf(write);
    final version = write.baseVersion ?? _knownVersion(kind, write.itemId);
    if (kind.updateCalls case final calls?) {
      // One call for each part changed: each sets it whole, so it's the
      // same sent again.
      Object? result;
      for (final arguments in calls(write.changes)) {
        result = await _call(kind.updateTool, arguments);
      }
      return _item(kind, write, result);
    }
    final (tool, arguments) = switch (write.op) {
      WriteOp.batch => (
        kind.batchTool!,
        <String, Object?>{
          if (write.parts('creates') case final creates when creates.isNotEmpty)
            'creates': creates,
          if (write.parts('updates') case final updates when updates.isNotEmpty)
            'updates': [
              for (final u in updates)
                {
                  kind.argument: {
                    'id': u['id'],
                    for (final MapEntry(:key, :value)
                        in (u['changes'] as Map? ?? const {})
                            .cast<String, Object?>()
                            .entries)
                      key: ?value,
                    'version':
                        ?(_versionOf(u['base']) ??
                        _knownVersion(kind, u['id'])),
                  },
                  if ([
                        for (final MapEntry(:key, :value)
                            in (u['changes'] as Map? ?? const {}).entries)
                          if (value == null) key,
                      ]
                      case final cleared when cleared.isNotEmpty)
                    'clear_fields': cleared,
                },
            ],
          if (write.parts('deletes') case final deletes when deletes.isNotEmpty)
            'deletes': [
              for (final d in deletes)
                {
                  kind.deleteArgument!: d['id'],
                  'if_version':
                      ?(_versionOf(d['base']) ?? _knownVersion(kind, d['id'])),
                },
            ],
        },
      ),
      WriteOp.create => (
        kind.createTool,
        <String, Object?>{
          kind.argument: {...write.changes, 'id': write.itemId},
        },
      ),
      WriteOp.update when kind.single => (
        kind.updateTool,
        <String, Object?>{
          kind.argument: {
            for (final MapEntry(:key, :value) in write.changes.entries)
              key: ?value,
          },
          if (write.changes.entries.where((c) => c.value == null)
              case final cleared when cleared.isNotEmpty)
            'clear_fields': [for (final c in cleared) c.key],
        },
      ),
      WriteOp.update when kind.updateArguments != null => (
        kind.updateTool,
        kind.updateArguments!(write.itemId, write.changes, version),
      ),
      WriteOp.update => (
        kind.updateTool,
        <String, Object?>{
          kind.argument: {
            'id': write.itemId,
            for (final MapEntry(:key, :value) in write.changes.entries)
              key: ?value,
            'version': ?version,
          },
          if (write.changes.entries.where((c) => c.value == null)
              case final cleared when cleared.isNotEmpty)
            'clear_fields': [for (final c in cleared) c.key],
        },
      ),
      WriteOp.delete => (
        kind.deleteTool!,
        <String, Object?>{
          kind.deleteArgument!: write.itemId,
          'if_version': ?version,
        },
      ),
    };
    return _item(kind, write, await _call(tool, arguments));
  }

  /// The item [write] made or changed, in what its tool gave: [result].
  static Map<String, Object?>? _item(
    WriteKind kind,
    PendingWrite write,
    Object? result,
  ) {
    // A batch's result, whole: see _saved.
    if (write.op == WriteOp.batch) {
      return result is Map ? result.cast<String, Object?>() : null;
    }
    if (kind.itemIn case final itemIn?) {
      return result is Map ? itemIn(result.cast(), write.itemId) : null;
    }
    // A create mostly gives the item under its kind's name, beside its
    // id; some, the item itself.
    return switch (result) {
      final Map map when kind.single => {...map.cast(), 'id': WriteKind.one},
      final Map map
          when write.op == WriteOp.create && map[kind.argument] is Map =>
        (map[kind.argument] as Map).cast<String, Object?>(),
      final Map map => map.cast<String, Object?>(),
      _ => null,
    };
  }

  /// [write] is saved, giving [item] (null for a deletion): it's what's
  /// known of it now, and what the writes to it waiting behind are made to.
  Future<void> _saved(PendingWrite write, Map<String, Object?>? item) async {
    final known = _known.putIfAbsent(write.kind, () => {});
    if (write.op == WriteOp.batch) {
      final kind = kindOf(write);
      final made = {
        for (final i in item?['${kind.argument}s'] as List? ?? const [])
          if ((i as Map)['id'] case final String id)
            id: i.cast<String, Object?>(),
      };
      for (final id in item?['deleted_ids'] as List? ?? const []) {
        known.remove('$id');
      }
      known.addAll(made);
      await change(
        (writes) => [
          for (final w in writes)
            w.id != write.id &&
                    w.kind == write.kind &&
                    made.containsKey(w.itemId) &&
                    w.op != WriteOp.create &&
                    !isSending(w)
                ? w.rewritten(base: () => made[w.itemId])
                : w,
        ],
      );
      return;
    }
    if (write.op == WriteOp.delete) {
      known.remove(write.itemId);
      return;
    }
    if (item == null) return;
    known[write.itemId] = item;
    await change(
      (writes) => [
        for (final w in writes)
          w.id != write.id &&
                  w.kind == write.kind &&
                  w.itemId == write.itemId &&
                  w.op != WriteOp.create &&
                  !isSending(w)
              ? w.rewritten(base: () => item)
              : w,
      ],
    );
  }

  @override
  bool retries(Object error) {
    if (error is McpException && error.conflict != null) return false;
    return describeServerError(error).kind != FailureKind.refused;
  }

  @override
  void failed(PendingWrite item) {
    if (!_conflicts.containsKey(item.id)) return;
    final [(:id, :current), ...more] = _conflicts.remove(item.id)!;
    unawaited(
      replaceUnlessSending(
        item.id,
        (w) => w
            .rewritten(
              conflicted: true,
              current: () => current,
              conflictId: () => w.op == WriteOp.batch ? id : null,
              moreConflicts: [
                if (w.op == WriteOp.batch)
                  for (final c in more) {'id': c.id, 'current': c.current},
              ],
            )
            .copyWith(
              lastError: () => current == null
                  ? 'Deleted elsewhere since'
                  : 'Changed elsewhere since',
            ),
      ).catchError((_) => false),
    );
  }
}
