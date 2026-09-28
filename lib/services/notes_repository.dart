import '../models/note.dart';
import 'mcp_client.dart';

/// Where notes come from. The app talks to this rather than to MCP directly
/// so screens can be exercised without a server.
abstract class NotesRepository {
  /// Notes that haven't been compacted yet, oldest first.
  Future<List<Note>> uncompactedNotes();

  /// Records [note] and returns it as stored.
  Future<Note> addNote(Note note);

  /// A short description of the backend, shown in the UI.
  String get label;
}

/// Reads and writes notes via the Time Tracker MCP server's `get_notes` and
/// `note` tools.
class McpNotesRepository implements NotesRepository {
  McpNotesRepository(this._client);

  final McpClient _client;

  @override
  String get label => _client.endpoint.host;

  @override
  Future<List<Note>> uncompactedNotes() async {
    final result = await _client.callTool('get_notes', {
      'include_compacted': false,
    });
    final notes =
        (result as List)
            .map((n) => Note.fromJson((n as Map).cast<String, dynamic>()))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return notes;
  }

  @override
  Future<Note> addNote(Note note) async {
    final result = await _client.callTool('note', {
      'noted_time': note.toJson(),
    });
    return result is Map ? Note.fromJson(result.cast<String, dynamic>()) : note;
  }
}

/// Keeps notes in memory. Used when no server is configured, and in tests.
class InMemoryNotesRepository implements NotesRepository {
  InMemoryNotesRepository([List<Note>? notes]) : _notes = [...?notes];

  final List<Note> _notes;

  @override
  String get label => 'offline demo';

  @override
  Future<List<Note>> uncompactedNotes() async =>
      _notes.where((n) => !n.isCompacted).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<Note> addNote(Note note) async {
    _notes.add(note);
    return note;
  }
}
