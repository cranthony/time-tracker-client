import '../models/plan_action.dart';
import 'outbox.dart';

/// A change to the actions waiting to be sent to the server, or that failed:
/// a new action, or changes to one.
class PendingActionSave implements OutboxItem<PendingActionSave> {
  const PendingActionSave({
    required this.id,
    required this.actionId,
    required this.isNew,
    required this.changes,
    this.group,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.refused = false,
  });

  @override
  final String id;

  /// The action it's for. For a new action, the id it's shown with until the
  /// server makes it, which the server knows nothing about.
  final String actionId;

  /// Whether it makes a new action, rather than changing one.
  final bool isNew;

  /// For a new action, everything it's made with, keyed as `create_action`
  /// takes them; else its changes, keyed as `update_action` takes them, a
  /// null clearing that property.
  final Map<String, Object?> changes;

  /// Whether the action it changes is a group, which the server changes
  /// with its own tool. Null for a save kept before this was, which is
  /// looked up when it's sent.
  final bool? group;

  @override
  final int attempts;
  @override
  final String? lastError;
  @override
  final DateTime? nextAttemptAt;
  @override
  final DateTime? sendingSince;
  @override
  final bool refused;

  /// Whether its last attempt failed: it's tried again after a while, or,
  /// if [refused], when it's retried.
  bool get failed => lastError != null;

  /// The new action it makes, shown as [actionId].
  PlanAction get action =>
      PlanAction.fromJson({'status': 'active', ...changes, 'id': actionId});

  /// The action in [actions] that's the new one it makes, if there is one. A
  /// name is only used once among siblings, so the same one under the same
  /// parent is it.
  PlanAction? madeIn(ActionList actions) => actions.actions
      .where(
        (g) => g.parentId == changes['parent_id'] && g.name == changes['name'],
      )
      .firstOrNull;

  /// It with [changes] in place of its own, sent afresh.
  PendingActionSave withChanges(Map<String, Object?> changes) =>
      PendingActionSave(
        id: id,
        actionId: actionId,
        isNew: isNew,
        changes: changes,
        group: group,
        attempts: attempts,
      );

  @override
  PendingActionSave copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    bool? refused,
  }) => PendingActionSave(
    id: id,
    actionId: actionId,
    isNew: isNew,
    changes: changes,
    group: group,
    attempts: attempts ?? this.attempts,
    lastError: lastError == null ? this.lastError : lastError(),
    nextAttemptAt: nextAttemptAt == null ? this.nextAttemptAt : nextAttemptAt(),
    sendingSince: sendingSince == null ? this.sendingSince : sendingSince(),
    refused: refused ?? this.refused,
  );

  factory PendingActionSave.fromJson(Map<String, dynamic> json) =>
      PendingActionSave(
        id: json['id'] as String,
        // Kept as 'goal_id', as older versions saved it.
        actionId: json['goal_id'] as String,
        isNew: json['is_new'] as bool? ?? false,
        changes: (json['changes'] as Map).cast<String, Object?>(),
        group: json['is_group'] as bool?,
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
        nextAttemptAt: _date(json['next_attempt_at']),
        sendingSince: _date(json['sending_since']),
        refused: json['refused'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal_id': actionId,
    'is_new': isNew,
    'changes': changes,
    'is_group': ?group,
    'attempts': attempts,
    'last_error': ?lastError,
    'next_attempt_at': ?nextAttemptAt?.toUtc().toIso8601String(),
    'sending_since': ?sendingSince?.toUtc().toIso8601String(),
    if (refused) 'refused': true,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
