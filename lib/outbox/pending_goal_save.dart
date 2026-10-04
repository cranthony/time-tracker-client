import '../models/goal.dart';
import 'outbox.dart';

/// A change to the goals waiting to be sent to the server, or that failed:
/// a new goal, or changes to one.
class PendingGoalSave implements OutboxItem<PendingGoalSave> {
  const PendingGoalSave({
    required this.id,
    required this.goalId,
    required this.isNew,
    required this.changes,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.refused = false,
  });

  @override
  final String id;

  /// The goal it's for. For a new goal, the id it's shown with until the
  /// server makes it, which the server knows nothing about.
  final String goalId;

  /// Whether it makes a new goal, rather than changing one.
  final bool isNew;

  /// For a new goal, everything it's made with, keyed as `create_goal`
  /// takes them; else its changes, keyed as `update_goal` takes them, a
  /// null clearing that property.
  final Map<String, Object?> changes;

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

  /// The new goal it makes, shown as [goalId].
  Goal get goal =>
      Goal.fromJson({'status': 'active', ...changes, 'id': goalId});

  /// The goal in [goals] that's the new one it makes, if there is one. A
  /// name is only used once among siblings, so the same one under the same
  /// parent is it.
  Goal? madeIn(GoalList goals) => goals.goals
      .where(
        (g) => g.parentId == changes['parent_id'] && g.name == changes['name'],
      )
      .firstOrNull;

  /// It with [changes] in place of its own, sent afresh.
  PendingGoalSave withChanges(Map<String, Object?> changes) => PendingGoalSave(
    id: id,
    goalId: goalId,
    isNew: isNew,
    changes: changes,
    attempts: attempts,
  );

  @override
  PendingGoalSave copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    bool? refused,
  }) => PendingGoalSave(
    id: id,
    goalId: goalId,
    isNew: isNew,
    changes: changes,
    attempts: attempts ?? this.attempts,
    lastError: lastError == null ? this.lastError : lastError(),
    nextAttemptAt: nextAttemptAt == null ? this.nextAttemptAt : nextAttemptAt(),
    sendingSince: sendingSince == null ? this.sendingSince : sendingSince(),
    refused: refused ?? this.refused,
  );

  factory PendingGoalSave.fromJson(Map<String, dynamic> json) =>
      PendingGoalSave(
        id: json['id'] as String,
        goalId: json['goal_id'] as String,
        isNew: json['is_new'] as bool? ?? false,
        changes: (json['changes'] as Map).cast<String, Object?>(),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
        nextAttemptAt: _date(json['next_attempt_at']),
        sendingSince: _date(json['sending_since']),
        refused: json['refused'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal_id': goalId,
    'is_new': isNew,
    'changes': changes,
    'attempts': attempts,
    'last_error': ?lastError,
    'next_attempt_at': ?nextAttemptAt?.toUtc().toIso8601String(),
    'sending_since': ?sendingSince?.toUtc().toIso8601String(),
    if (refused) 'refused': true,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
