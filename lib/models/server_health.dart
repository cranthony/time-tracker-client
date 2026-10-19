/// The server's health metrics, as its `get_health` gives them: each tool's
/// last calls, its memory -- the most of each of its last 500
/// [memoryInterval]s -- after its calls and its own work, its restarts,
/// and its warnings of changes made behind its back. Times are UTC,
/// oldest first.
class ServerHealth {
  const ServerHealth({
    this.tools = const [],
    this.memory = const [],
    this.memoryInterval = const Duration(seconds: 1),
    this.restarts = const [],
    this.sheetWarnings = const [],
  });

  final List<ToolCalls> tools;
  final List<MemorySample> memory;

  /// How long each of the server's [memory] samples is the most of, as
  /// `memory_interval_seconds` says: a second, from a server too old to
  /// say. The closest two samples can be.
  final Duration memoryInterval;

  /// When the server last started, up to 100 times: there's one server,
  /// so each after the first is a restart -- a crash, or a deploy.
  final List<DateTime> restarts;

  /// What the server found changed behind its back, up to the last 100.
  final List<SheetWarning> sheetWarnings;

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
    memoryInterval: switch (json['memory_interval_seconds']) {
      final num seconds when seconds >= 1 => Duration(seconds: seconds.toInt()),
      _ => const Duration(seconds: 1),
    },
    restarts: [
      for (final r in json['restarts'] as List? ?? const [])
        ?DateTime.tryParse('$r'),
    ]..sort(),
    sheetWarnings: [
      for (final w in json['sheet_warnings'] as List? ?? const [])
        ?SheetWarning.fromJson((w as Map).cast<String, dynamic>()),
    ]..sort((a, b) => a.at.compareTo(b.at)),
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

/// The server's resident memory, in MiB: the most of each of its
/// [ServerHealth.memoryInterval]s, after a call -- any tool's -- or its
/// own work in the background. With [parts],
/// what it's made of, as the server reckons it: none from a server that
/// doesn't break it down.
class MemorySample {
  const MemorySample({required this.at, required this.mib, this.parts});

  final DateTime at;
  final double mib;

  /// Each tab of the metadata spreadsheet the server keeps ("Sheet: "
  /// and its title), the calendar it keeps, and, last, the rest of it:
  /// summing to [mib], give or take rounding.
  final List<MemoryPart>? parts;

  static MemorySample? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at']}');
    final mib = json['rss_mib'];
    if (at == null || mib is! num) return null;
    final parts = json['parts'];
    return MemorySample(
      at: at,
      mib: mib.toDouble(),
      parts: parts is List
          ? [
              for (final p in parts)
                if (p is Map && p['mib'] is num)
                  MemoryPart(
                    name: '${p['name']}',
                    mib: (p['mib'] as num).toDouble(),
                  ),
            ]
          : null,
    );
  }
}

/// A part of the server's memory: its name, and its MiB.
class MemoryPart {
  const MemoryPart({required this.name, required this.mib});

  /// "Sheet: " and a tab's title, [calendar] or [rest].
  final String name;
  final double mib;

  static const calendar = 'Calendar';
  static const rest = 'Rest of server';
  static const sheetPrefix = 'Sheet: ';

  bool get isSheet => name.startsWith(sheetPrefix);

  @override
  bool operator ==(Object other) =>
      other is MemoryPart && other.name == name && other.mib == mib;

  @override
  int get hashCode => Object.hash(name, mib);

  @override
  String toString() => '$name: $mib';
}

/// What the server found changed behind its back, as `get_health`'s
/// `sheet_warnings` gives it: the metadata spreadsheet's cells edited by
/// hand, or a tab of it deleted -- put back as the server keeps it, when
/// it could be -- or events changed outside the server (in Google
/// Calendar, say), taken as they are.
class SheetWarning {
  const SheetWarning({
    required this.at,
    required this.kind,
    this.tab,
    this.cells = const [],
    this.cellCount = 0,
    this.restored = false,
  });

  final DateTime at;
  final SheetWarningKind kind;

  /// The spreadsheet tab's title; none for a calendar warning.
  final String? tab;

  /// The first 20 cells changed -- for a calendar warning, events.
  final List<WarnedCell> cells;

  /// How many cells (or events) were changed in all.
  final int cellCount;

  /// Whether the server put back what it keeps. Never, for the calendar.
  final bool restored;

  static SheetWarning? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    final cells = [
      for (final c in json['cells'] as List? ?? const [])
        if (c is Map) WarnedCell.fromJson(c.cast<String, dynamic>()),
    ];
    return SheetWarning(
      at: at,
      kind: switch (json['kind']) {
        'deleted' => SheetWarningKind.deleted,
        'calendar' => SheetWarningKind.calendar,
        _ => SheetWarningKind.edited,
      },
      tab: json['tab'] as String?,
      cells: cells,
      cellCount: (json['cell_count'] as num?)?.toInt() ?? cells.length,
      restored: json['restored'] == true,
    );
  }
}

enum SheetWarningKind {
  /// Cells of the metadata spreadsheet edited by hand.
  edited,

  /// A tab of the metadata spreadsheet deleted by hand.
  deleted,

  /// Events changed outside the server.
  calendar,
}

/// A cell changed behind the server's back: its A1 name, what was found
/// there, and what the server keeps (and put back). For the calendar, the
/// event's id, its summary and status as found, and nothing kept.
class WarnedCell {
  const WarnedCell({required this.cell, required this.found, this.kept = ''});

  final String cell;
  final String found;
  final String kept;

  factory WarnedCell.fromJson(Map<String, dynamic> json) => WarnedCell(
    cell: '${json['cell'] ?? ''}',
    found: '${json['found'] ?? ''}',
    kept: '${json['kept'] ?? ''}',
  );
}
