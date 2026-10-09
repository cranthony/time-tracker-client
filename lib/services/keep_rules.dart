import '../models/event.dart';
import '../models/plan_action.dart';

/// What a rule picks for a new or moved event's Keep list, as its box
/// starts.
enum KeepRuleKind {
  /// Every event that ended by the last compaction.
  historical('Historical events'),

  /// The last event to end by the last compaction.
  lastHistorical('Last historical event'),

  /// The latest event before the cursor with an action, or one in a
  /// group.
  previousWith('Previous event with'),

  /// The earliest event after the cursor with an action, or one in a
  /// group.
  nextWith('Next event with');

  const KeepRuleKind(this.label);

  final String label;

  /// Whether it names an action, or a group.
  bool get hasAction => this == previousWith || this == nextWith;
}

/// A rule for what goes in a new or moved event's Keep list as its box
/// starts: its [kind], and for one before or after the cursor, the
/// [actionId] -- an action's, or a group's -- its event has.
class KeepRule {
  const KeepRule(this.kind, {this.actionId});

  /// What the app keeps until it's told otherwise: every historical event.
  static const defaults = [KeepRule(KeepRuleKind.historical)];

  final KeepRuleKind kind;
  final String? actionId;

  Map<String, Object?> toJson() => {'kind': kind.name, 'action_id': ?actionId};

  /// Null if [json] isn't one -- from a later version, say.
  static KeepRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = KeepRuleKind.values.asNameMap()[json['kind']];
    if (kind == null) return null;
    final actionId = json['action_id'] as String?;
    if (kind.hasAction && actionId == null) return null;
    return KeepRule(kind, actionId: actionId);
  }

  /// It said in words, the action named from [actions]: "Next event with
  /// Sleep".
  String describe(Map<String, PlanAction> actions) => switch (actionId) {
    final id? => '${kind.label} ${actions[id]?.name ?? id}',
    null => kind.label,
  };

  @override
  bool operator ==(Object other) =>
      other is KeepRule && other.kind == kind && other.actionId == actionId;

  @override
  int get hashCode => Object.hash(kind, actionId);
}

/// The ids of the [events] [rules] pick to keep, for a box from [from] to
/// [to] -- for a new event, both its cursor: each historical event (that
/// ended by [lastCompaction]), or the last; the latest event before
/// [from], and the earliest after [to], with an action or one in a group
/// ([actions] says which are in which). Never [except], the event being
/// edited, nor one [from] or [to] is inside of.
Set<String> keepByRules(
  List<KeepRule> rules,
  List<Event> events, {
  required DateTime from,
  required DateTime to,
  DateTime? lastCompaction,
  Map<String, PlanAction> actions = const {},
  String? except,
}) {
  bool inside(Event e, DateTime t) => e.start.isBefore(t) && e.end.isAfter(t);
  final candidates = [
    for (final e in events)
      if (e.id != null &&
          e.id != except &&
          !e.isCancelled &&
          !inside(e, from) &&
          !inside(e, to))
        e,
  ];
  // Whether [e] has [actionId], or an action under it.
  bool has(Event e, String actionId) => e.actionIds.any((id) {
    String? at = id;
    // Up the tree, no further than it could go.
    for (var depth = 0; at != null && depth < 50; depth++) {
      if (at == actionId) return true;
      at = actions[at]?.parentId;
    }
    return false;
  });
  final historical = [
    for (final e in candidates)
      if (lastCompaction != null && !e.end.isAfter(lastCompaction)) e,
  ]..sort((a, b) => a.end.compareTo(b.end));
  final kept = <String>{};
  for (final rule in rules) {
    switch (rule.kind) {
      case KeepRuleKind.historical:
        kept.addAll([for (final e in historical) e.id!]);
      case KeepRuleKind.lastHistorical:
        if (historical.lastOrNull case final e?) kept.add(e.id!);
      case KeepRuleKind.previousWith:
        final before = [
          for (final e in candidates)
            if (!e.end.isAfter(from) && has(e, rule.actionId!)) e,
        ]..sort((a, b) => a.end.compareTo(b.end));
        if (before.lastOrNull case final e?) kept.add(e.id!);
      case KeepRuleKind.nextWith:
        final after = [
          for (final e in candidates)
            if (!e.start.isBefore(to) && has(e, rule.actionId!)) e,
        ]..sort((a, b) => a.start.compareTo(b.start));
        if (after.firstOrNull case final e?) kept.add(e.id!);
    }
  }
  return kept;
}
