/// The server's health metrics, as its `get_health` gives them: each tool's
/// last calls, its memory after each of its last calls, and its restarts.
/// Times are UTC, oldest first.
class ServerHealth {
  const ServerHealth({
    this.tools = const [],
    this.memory = const [],
    this.restarts = const [],
  });

  final List<ToolCalls> tools;
  final List<MemorySample> memory;

  /// When the server last started, up to 100 times: there's one server,
  /// so each after the first is a restart -- a crash, or a deploy.
  final List<DateTime> restarts;

  /// Every call, of every tool, oldest first.
  List<ToolCall> get calls =>
      [for (final t in tools) ...t.calls]..sort((a, b) => a.at.compareTo(b.at));

  factory ServerHealth.fromJson(Map<String, dynamic> json) => ServerHealth(
    tools: [
      for (final t in json['tools'] as List? ?? const [])
        ToolCalls.fromJson((t as Map).cast<String, dynamic>()),
    ],
    memory: [
      for (final m in json['memory'] as List? ?? const [])
        ?MemorySample.fromJson((m as Map).cast<String, dynamic>()),
    ],
    restarts: [
      for (final r in json['restarts'] as List? ?? const [])
        ?DateTime.tryParse('$r'),
    ]..sort(),
  );
}

/// One tool's last calls (up to 100), as the server recorded them.
class ToolCalls {
  const ToolCalls({required this.tool, this.calls = const []});

  final String tool;
  final List<ToolCall> calls;

  factory ToolCalls.fromJson(Map<String, dynamic> json) {
    final tool = '${json['tool']}';
    return ToolCalls(
      tool: tool,
      calls: [
        for (final c in json['calls'] as List? ?? const [])
          ?ToolCall.fromJson(tool, (c as Map).cast<String, dynamic>()),
      ]..sort((a, b) => a.at.compareTo(b.at)),
    );
  }
}

/// One call of a tool: when it ended, how long the tool's own work took,
/// how long the whole request took -- auth and transport included -- when
/// it came over HTTP, and whether it succeeded.
class ToolCall {
  const ToolCall({
    required this.tool,
    required this.at,
    required this.workMs,
    this.totalMs,
    this.ok = true,
  });

  final String tool;
  final DateTime at;
  final int workMs;
  final int? totalMs;
  final bool ok;

  /// The time past the tool's own work: what [workMs] and it stack to
  /// [totalMs]; none, when there's no total.
  int get overheadMs =>
      totalMs == null ? 0 : (totalMs! - workMs).clamp(0, totalMs!);

  /// The whole request's, or the tool's own when there's no other.
  int get wholeMs => totalMs ?? workMs;

  static ToolCall? fromJson(String tool, Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at']}');
    final work = json['work_ms'];
    if (at == null || work is! num) return null;
    return ToolCall(
      tool: tool,
      at: at,
      workMs: work.toInt(),
      totalMs: (json['total_ms'] as num?)?.toInt(),
      ok: json['ok'] != false,
    );
  }
}

/// The server's resident memory, in MiB, after a call -- any tool's.
class MemorySample {
  const MemorySample({required this.at, required this.mib});

  final DateTime at;
  final double mib;

  static MemorySample? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at']}');
    final mib = json['rss_mib'];
    if (at == null || mib is! num) return null;
    return MemorySample(at: at, mib: mib.toDouble());
  }
}
