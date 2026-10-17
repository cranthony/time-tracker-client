import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../models/person.dart';
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
  });

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
  String label(Map<String, Object?>? item) => switch (item?['name']) {
    final String name when name.trim().isNotEmpty => '$noun “${name.trim()}”',
    _ => noun,
  };

  static const person = WriteKind(
    name: 'person',
    noun: 'person',
    argument: 'person',
    createTool: 'create_person',
    updateTool: 'update_person',
    writable: _person,
  );

  static Map<String, Object?> _person(Map<String, Object?> item) =>
      Person.fromJson({'id': '', ...item}).toJson();

  static Map<String, Object?> _location(Map<String, Object?> item) =>
      Location.fromJson({'id': '', ...item}).toJson();

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

  /// Every kind, by name.
  static final all = {
    for (final k in [person, location]) k.name: k,
  };
}

/// Sends a write to the server: [tool], with [arguments], made once by
/// its [writeId]; gives what the tool gives.
typedef WriteCall = Future<Object?> Function(
  String tool,
  Map<String, Object?> arguments,
  String writeId,
);

/// Every write the app makes to the server of the kinds it has
/// ([WriteKind.all]), kept on the device until it's saved: the app never
/// waits on the server to write, so it works the same offline. Each write
/// is sent once -- the server keeps what each write_id gave, so one sent
/// again isn't made again -- and retried until it's saved. Nothing is
/// dropped unless the user drops it ([drop]).
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
class WriteQueue extends Outbox<PendingWrite, Map<String, Object?>?> {
  WriteQueue({
    required super.store,
    required this._call,
    super.clock,
    super.sender,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Writes through [client], made once by their write_id.
  static WriteCall callOn(McpClient client) =>
      (tool, arguments, writeId) => client.callTool(tool, arguments, writeId);

  final WriteCall _call;
  final Random _random;

  /// Each kind's items as the app last saw them from the server, by id:
  /// what a change is made to.
  final _known = <String, Map<String, Map<String, Object?>>>{};

  /// Conflicts found sending, by write, till they're kept (see [failed]).
  final _conflicts = <String, Map<String, Object?>?>{};

  static const _idAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// A new id: 16 letters and digits, so no two clash.
  String _newId() => String.fromCharCodes([
    for (var i = 0; i < 16; i++)
      _idAlphabet.codeUnitAt(_random.nextInt(_idAlphabet.length)),
  ]);

  static WriteKind kindOf(PendingWrite write) => WriteKind.all[write.kind]!;

  /// [write]'s item, as one would name it: “location “Home””.
  String label(PendingWrite write) {
    final kind = kindOf(write);
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
      if (w.op == WriteOp.create) w.itemId,
  };

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

  /// Queues [changes] -- a null clears a field -- to the [kind] [id]: into
  /// a write to it still waiting, if there is one. Gives it as it's shown
  /// now, with them.
  Map<String, Object?> update(
    WriteKind kind,
    String id,
    Map<String, Object?> changes,
  ) {
    _queue((writes) {
      final i = writes.lastIndexWhere(
        (w) =>
            w.kind == kind.name &&
            w.itemId == id &&
            w.op != WriteOp.delete &&
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
            base: _known[kind.name]?[id],
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

  /// Queues deleting the [kind] [id]. If the server doesn't have it yet,
  /// its writes are just dropped -- unless one's being sent, when it's
  /// deleted once that's saved.
  void delete(WriteKind kind, String id) {
    _queue((writes) {
      bool its(PendingWrite w) =>
          w.kind == kind.name && w.itemId == id && !isSending(w);
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
          base: _known[kind.name]?[id],
        ),
      ];
    });
  }

  void _queue(List<PendingWrite> Function(List<PendingWrite>) edit) {
    unawaited(
      change(edit).then((_) => schedule(immediately: true), onError: (_) {}),
    );
  }

  /// Drops [write] without sending it -- and, for a new item, the writes
  /// to it waiting behind it, which can't be made without it. Only the
  /// user does this. False if it's being sent.
  Future<bool> drop(PendingWrite write) async {
    if (isSending(write)) return false;
    var dropped = false;
    await change((writes) {
      if (writes.any((w) => w.id == write.id && isSending(w))) return writes;
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

  /// Sends [write], [PendingWrite.conflicted], as it is, over what changed
  /// elsewhere: the user chose theirs.
  Future<void> overwrite(PendingWrite write) async {
    await replaceUnlessSending(
      write.id,
      (w) => w
          .rewritten(base: () => null, conflicted: false, current: () => null)
          .copyWith(refused: false, lastError: () => null),
    );
    schedule(immediately: true);
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
  Future<void> resolve(PendingWrite write, Map<String, Object?> changes) async {
    final current = write.current;
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
  Future<void> restore(PendingWrite write) async {
    final kind = kindOf(write);
    final fields = kind.writable({...?write.base, ...write.changes})
      ..remove('id')
      ..removeWhere((_, value) => value == null);
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
        // Changed elsewhere in other fields, and only once or twice:
        // made to it as it is now.
        if (merged < 2 && _merges(write, current)) {
          write = write.rewritten(base: () => current);
          await change(
            (writes) => [for (final w in writes) w.id == write.id ? write : w],
          );
          continue;
        }
        _conflicts[write.id] = current;
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

  static bool _same(Object? a, Object? b) =>
      jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

  static Object? _canonical(Object? value) => switch (value) {
    final Map map => {
      for (final key in [...map.keys.map((k) => '$k')]..sort())
        key: _canonical(map[key]),
    },
    final List list => [for (final v in list) _canonical(v)],
    _ => value,
  };

  Future<Map<String, Object?>?> _send(PendingWrite write) async {
    final kind = kindOf(write);
    final version = write.baseVersion;
    final (tool, arguments) = switch (write.op) {
      WriteOp.create => (
        kind.createTool,
        <String, Object?>{
          kind.argument: {...write.changes, 'id': write.itemId},
        },
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
    final result = await _call(tool, arguments, write.id);
    // A create gives the item under its kind's name, beside its id.
    return switch (result) {
      final Map map when write.op == WriteOp.create =>
        (map[kind.argument] as Map?)?.cast<String, Object?>(),
      final Map map => map.cast<String, Object?>(),
      _ => null,
    };
  }

  /// [write] is saved, giving [item] (null for a deletion): it's what's
  /// known of it now, and what the writes to it waiting behind are made to.
  Future<void> _saved(PendingWrite write, Map<String, Object?>? item) async {
    final known = _known.putIfAbsent(write.kind, () => {});
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
    final current = _conflicts.remove(item.id);
    unawaited(
      replaceUnlessSending(
        item.id,
        (w) => w
            .rewritten(conflicted: true, current: () => current)
            .copyWith(
              lastError: () => current == null
                  ? 'Deleted elsewhere since'
                  : 'Changed elsewhere since',
            ),
      ).catchError((_) => false),
    );
  }
}
