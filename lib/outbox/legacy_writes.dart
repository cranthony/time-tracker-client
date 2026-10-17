import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import 'outbox_store.dart';
import 'store_lock.dart';
import 'write_queue.dart';

/// The [WriteQueue]'s store, which also holds what an older version of
/// the app left waiting in the outboxes it had before -- action saves
/// ('goal_outbox') and notes ('note_outbox') -- as writes: so nothing
/// waiting is lost when the app's updated. They're read in with what's in
/// the queue, first, being older; once the queue's saved with them,
/// they're taken out of where they were. Each becomes the same write
/// however often it's read in, so one read in twice -- the app closed
/// between the two -- is kept once.
///
/// Only what was read in is taken out, under the old store's own lock --
/// the one an older version's window, still open on the web, holds to
/// change it -- so what that adds meanwhile stays, to be read in next
/// time. What can't be read (from a version this doesn't know) stays
/// where it is, rather than be lost.
class WriteQueueStore extends PrefsOutboxStore<PendingWrite> {
  WriteQueueStore({super.prefs})
    : _legacy = prefs ?? SharedPreferencesAsync(),
      super(
        key: 'write_queue',
        fromJson: PendingWrite.fromJson,
        toJson: (write) => write.toJson(),
      );

  final SharedPreferencesAsync _legacy;

  /// Where an older version kept action saves.
  static const actionsKey = 'goal_outbox';

  /// Where an older version kept notes waiting to be saved.
  static const notesKey = 'note_outbox';

  /// Of each older store, the ids of what [load] read in from it, not yet
  /// taken out.
  final _readIn = <String, Set<String>>{};

  @override
  Future<List<PendingWrite>> load() async {
    final writes = await super.load();
    final ids = {for (final w in writes) w.id};
    final legacy = <PendingWrite>[];
    for (final (key, convert) in [
      (actionsKey, actionWrite),
      (notesKey, noteWrite),
    ]) {
      final read = _entries(await _legacy.getString(key));
      if (read == null) continue;
      final taken = _readIn[key] = {};
      for (final item in read) {
        final write = item is Map
            ? convert(item.cast<String, Object?>())
            : null;
        if (write == null) continue;
        taken.add(write.id);
        if (ids.add(write.id)) legacy.add(write);
      }
    }
    return [...legacy, ...writes];
  }

  @override
  Future<void> save(List<PendingWrite> items) async {
    await super.save(items);
    // Kept in the queue now, so taken out of where they were.
    for (final MapEntry(key: key, value: taken) in [..._readIn.entries]) {
      await IsolateStoreLock.forKey(key).hold((_) async {
        final json = await _legacy.getString(key);
        final now = _entries(json);
        if (now == null) return;
        final left = [
          for (final item in now)
            if (item is! Map || !taken.contains(item['id'])) item,
        ];
        if (left.length == now.length) return;
        if (left.isEmpty) {
          await _legacy.remove(key);
        } else {
          await _legacy.setString(key, jsonEncode(left));
        }
      });
      _readIn.remove(key);
    }
  }

  /// What an older store keeps, [json], as its entries; null if there's
  /// nothing, or it can't be read -- when it's left as it is.
  static List<Object?>? _entries(String? json) {
    if (json == null) return null;
    try {
      return switch (jsonDecode(json)) {
        final List entries => entries,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// An older version's action save, kept as [json], as the write it is;
  /// null if it can't be read.
  static PendingWrite? actionWrite(Map<String, Object?> json) {
    try {
      final isNew = json['is_new'] == true;
      final changes = (json['changes'] as Map).cast<String, Object?>();
      final group = isNew
          ? changes['kind'] == 'group'
          : json['is_group'] == true;
      final kind = group ? WriteKind.actionGroup : WriteKind.action;
      final fields = actionWriteFields(changes, group: group);
      final op = isNew ? WriteOp.create : WriteOp.update;
      return PendingWrite(
        id: json['id'] as String,
        kind: kind.name,
        op: op,
        // Kept as 'goal_id', as older versions saved it.
        itemId: json['goal_id'] as String,
        changes: {
          if (isNew) ...{
            for (final MapEntry(:key, :value) in fields.entries) key: ?value,
            if (!group) 'status': fields['status'] ?? 'active',
          } else
            ...fields,
        },
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
        refused: json['refused'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// An older version's note waiting, kept as [json], as the write it
/// is; null if it can't be read. A new note takes its id from the one it
/// had there, so it's the same write however often it's read in.
PendingWrite? noteWrite(Map<String, Object?> json) {
  try {
    Note note(Object? json) =>
        Note.fromJson((json as Map).cast<String, dynamic>());
    final id = json['id'] as String;
    final added = note(json['note']);
    final original = switch (json['original']) {
      final Map o => note(o),
      _ => null,
    };
    final (op, itemId, changes) = switch (json['change']) {
      'edit' => (
        WriteOp.update,
        original!.id!,
        <String, Object?>{
          if (!added.timestamp.isAtSameMomentAs(original.timestamp))
            'timestamp': localIsoTimestamp(added.timestamp),
          if ((added.description ?? '') != (original.description ?? ''))
            'description': added.description,
        },
      ),
      'delete' => (WriteOp.delete, original!.id!, const <String, Object?>{}),
      _ => (
        WriteOp.create,
        // Its own id, from the one it had: 2 to 40 lowercase letters,
        // digits and dashes, as the server takes it.
        'n${id.toLowerCase().replaceAll(RegExp('[^a-z0-9-]'), '-')}',
        <String, Object?>{
          'timestamp': localIsoTimestamp(added.timestamp),
          'description': ?added.description,
        },
      ),
    };
    return PendingWrite(
      id: id,
      kind: WriteKind.note.name,
      op: op,
      itemId: itemId.length > 40 ? itemId.substring(0, 40) : itemId,
      changes: changes,
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      refused: json['refused'] as bool? ?? false,
    );
  } catch (_) {
    return null;
  }
}

/// [fields], keyed as the Plan page edits an action (or a group, with
/// [group]), as the server's tools take them: a parent is a group_id, and
/// only what an action -- or a group -- has is kept.
Map<String, Object?> actionWriteFields(
  Map<String, Object?> fields, {
  required bool group,
}) {
  final taken = group ? WriteKind.actionGroupFields : WriteKind.actionFields;
  return {
    for (final MapEntry(:key, :value) in fields.entries)
      if (key == 'parent_id')
        'group_id': value
      else if (key != 'id' && taken.contains(key))
        key: value,
  };
}
