import '../models/note.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where notes come from. The app talks to this rather than to MCP directly
/// so screens can be exercised without a server.
abstract class NotesRepository {
  /// Notes that haven't been compacted yet, oldest first.
  Future<List<Note>> uncompactedNotes();

  /// What [uncompactedNotes] last returned, kept from an earlier run of
  /// the app; null if there's nothing kept.
  Future<List<Note>?> cachedUncompactedNotes();

  /// Records [note] and returns it as stored, with its id.
  Future<Note> addNote(Note note);

  /// Changes the uncompacted note with [id]: a new [timestamp] and/or
  /// [description] (empty clears it); null leaves either as it is. Returns
  /// the note as stored, whose id changes if its timestamp did.
  Future<Note> editNote(String id, {DateTime? timestamp, String? description});

  /// Deletes the uncompacted note with [id].
  Future<void> deleteNote(String id);

  /// When notes were last compacted, and the latest note compacted.
  Future<CompactionStatus> compactionStatus();

  /// A short description of the backend, shown in the UI.
  String get label;
}

/// Reads and writes notes via the Time Tracker MCP server's `get_notes`,
/// `note`, `edit_note` and `delete_note` tools.
class McpNotesRepository implements NotesRepository {
  McpNotesRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _cacheKey = 'get_notes';

  @override
  String get label => _client.endpoint.host;

  @override
  Future<List<Note>> uncompactedNotes() async {
    final result = await _client.callTool('get_notes', {
      'include_compacted': false,
    });
    final notes = _notes(result);
    await _cache?.write(_cacheKey, result);
    return notes;
  }

  @override
  Future<List<Note>?> cachedUncompactedNotes() async {
    try {
      final result = await _cache?.read(_cacheKey);
      return result == null ? null : _notes(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  static List<Note> _notes(Object? result) =>
      (result as List)
          .map((n) => Note.fromJson((n as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<Note> addNote(Note note) async {
    final result = await _client.callTool('note', {
      'noted_time': note.toJson(),
    });
    return result is Map ? Note.fromJson(result.cast<String, dynamic>()) : note;
  }

  @override
  Future<Note> editNote(
    String id, {
    DateTime? timestamp,
    String? description,
  }) async {
    final result = await _client.callTool('edit_note', {
      'note_id': id,
      'timestamp': ?(timestamp == null ? null : localIsoTimestamp(timestamp)),
      'description': ?description,
    });
    return Note.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<void> deleteNote(String id) =>
      _client.callTool('delete_note', {'note_id': id});

  @override
  Future<CompactionStatus> compactionStatus() async {
    final result = await _client.callTool('get_compaction_status', {});
    return CompactionStatus.fromJson((result as Map).cast<String, dynamic>());
  }
}

/// Keeps notes in memory. Used when no server is configured, and in tests.
class InMemoryNotesRepository implements NotesRepository {
  InMemoryNotesRepository([
    List<Note>? notes,
    this.status = const CompactionStatus(),
  ]) {
    notes?.forEach(_store);
  }

  /// What [compactionStatus] says.
  final CompactionStatus status;

  @override
  Future<CompactionStatus> compactionStatus() async => status;

  final _notes = <Note>[];
  var _nextRow = 1;

  @override
  String get label => 'offline demo';

  @override
  Future<List<Note>> uncompactedNotes() async =>
      _notes.where((n) => !n.isCompacted).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<List<Note>?> cachedUncompactedNotes() async => null;

  @override
  Future<Note> addNote(Note note) async => _store(note);

  Note _store(Note note) {
    final stored = _withId(note, _nextRow++);
    _notes.add(stored);
    return stored;
  }

  @override
  Future<Note> editNote(
    String id, {
    DateTime? timestamp,
    String? description,
  }) async {
    final i = _indexOf(id);
    final old = _notes[i];
    final edited = Note(
      timestamp: timestamp ?? old.timestamp,
      description: description == null
          ? old.description
          : (description.isEmpty ? null : description),
    );
    return _notes[i] = _withId(edited, _rowOf(id));
  }

  @override
  Future<void> deleteNote(String id) async => _notes.removeAt(_indexOf(id));

  int _indexOf(String id) {
    final i = _notes.indexWhere((n) => n.id == id && !n.isCompacted);
    if (i < 0) throw McpException('No uncompacted note has id $id');
    return i;
  }

  // Like the server's ids: the timestamp, and the note's row.
  static Note _withId(Note note, int row) => Note(
    timestamp: note.timestamp,
    description: note.description,
    compactionId: note.compactionId,
    id: '${localIsoTimestamp(note.timestamp)}#$row',
  );

  static int _rowOf(String id) => int.parse(id.split('#').last);
}
