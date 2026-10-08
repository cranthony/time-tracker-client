import '../models/schedule_hints.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// When the user's scheduled routines run, as hints ([ScheduleHints]):
/// read only -- the routines set them, on the server.
abstract class ScheduleHintsRepository {
  Future<ScheduleHints> hints();

  /// What [hints] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<ScheduleHints?> cachedHints();
}

/// Reads them with the server's `get_compaction_schedule_hints`.
class McpScheduleHintsRepository implements ScheduleHintsRepository {
  McpScheduleHintsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _key = 'schedule_hints';

  static ScheduleHints _decode(Object? result) =>
      ScheduleHints.fromJson((result as Map).cast<String, dynamic>());

  @override
  Future<ScheduleHints> hints() async {
    final result = await _client.callTool('get_compaction_schedule_hints');
    await _cache?.write(_key, result);
    return _decode(result);
  }

  @override
  Future<ScheduleHints?> cachedHints() async {
    try {
      final kept = await _cache?.read(_key);
      return kept == null ? null : _decode(kept);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }
}

/// Gives the hints it was made with: for the sample data, and tests.
class InMemoryScheduleHintsRepository implements ScheduleHintsRepository {
  InMemoryScheduleHintsRepository([this._hints = const ScheduleHints()]);

  final ScheduleHints _hints;

  @override
  Future<ScheduleHints> hints() async => _hints;

  @override
  Future<ScheduleHints?> cachedHints() async => null;
}
