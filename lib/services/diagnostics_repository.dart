import 'package:flutter/widgets.dart';

import '../models/server_health.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where the Diagnostics page's metrics come from: the server's health,
/// as its `get_health` gives it -- each tool's last calls, its memory and
/// its restarts. The app talks to this rather than to MCP directly, so
/// the page can be exercised without a server. See [DiagnosticsScope].
abstract class DiagnosticsRepository {
  /// The server's health, now.
  Future<ServerHealth> serverHealth();

  /// What [serverHealth] last returned, kept from an earlier run of the
  /// app; null if there's nothing kept.
  Future<ServerHealth?> cachedServerHealth();
}

/// Whether [error] says the server has no `get_health`: an older one.
bool isUnknownTool(Object error) => '$error'.contains('Unknown tool');

/// The server's health via its `get_health` tool, kept in [_cache].
class McpDiagnosticsRepository implements DiagnosticsRepository {
  McpDiagnosticsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _key = 'server_health';

  static ServerHealth _decode(Object? result) =>
      ServerHealth.fromJson((result as Map).cast<String, dynamic>());

  @override
  Future<ServerHealth> serverHealth() async {
    final result = await _client.callTool('get_health', {'samples': true});
    await _cache?.write(_key, result);
    return _decode(result);
  }

  @override
  Future<ServerHealth?> cachedServerHealth() async {
    try {
      final kept = await _cache?.read(_key);
      return kept == null ? null : _decode(kept);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }
}

/// Gives the health it was made with: for the sample data, and tests.
class InMemoryDiagnosticsRepository implements DiagnosticsRepository {
  InMemoryDiagnosticsRepository([this.health = const ServerHealth()]);

  ServerHealth health;

  @override
  Future<ServerHealth> serverHealth() async => health;

  @override
  Future<ServerHealth?> cachedServerHealth() async => null;
}

/// Makes a [DiagnosticsRepository] available below it -- for the app
/// menu's Diagnostics.
class DiagnosticsScope extends InheritedWidget {
  const DiagnosticsScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final DiagnosticsRepository repository;

  /// The nearest one's repository, or null if there's none.
  static DiagnosticsRepository? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DiagnosticsScope>()?.repository;

  @override
  bool updateShouldNotify(DiagnosticsScope oldWidget) =>
      repository != oldWidget.repository;
}
