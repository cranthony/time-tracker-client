import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

import 'outbox_store.dart';
import 'write_queue.dart';

/// The [WriteQueue]'s store, which also holds what an older version of
/// the app left waiting in the outboxes it had before -- action saves
/// ('goal_outbox') and notes ('note_outbox') -- as writes: so nothing waiting is lost when the app's
/// updated. They're read in with what's in the queue, first, being older;
/// once the queue's saved with them, they're removed from where they
/// were. Each becomes the same write however often it's read in, so one
/// read in twice -- the app closed between the two -- is kept once.
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

  /// The older stores read in, by [load], not yet removed.
  final _readIn = <String>{};

  @override
  Future<List<PendingWrite>> load() async {
    final writes = await super.load();
    final ids = {for (final w in writes) w.id};
    final legacy = <PendingWrite>[];
    for (final (key, convert) in [
      (actionsKey, actionWrite),
      (notesKey, noteWrite),
    ]) {
      final json = await _legacy.getString(key);
      if (json == null) continue;
      _readIn.add(key);
      for (final item in jsonDecode(json) as List) {
        final write = convert((item as Map).cast<String, Object?>());
        if (write != null && ids.add(write.id)) legacy.add(write);
      }
    }
    return [...legacy, ...writes];
  }

  @override
  Future<void> save(List<PendingWrite> items) async {
    await super.save(items);
    // Kept in the queue now, so gone from where they were.
    for (final key in [..._readIn]) {
      await _legacy.remove(key);
      _readIn.remove(key);
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
